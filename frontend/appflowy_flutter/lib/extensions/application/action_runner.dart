import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/ai/tools/document_toolkit.dart';
import 'package:appflowy/ai/tools/tool_permissions.dart';
import 'package:appflowy/ai/tools/tool_registry.dart';
import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_template.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/application/extension_library_cache.dart';
import 'package:appflowy/extensions/application/extension_manifest.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/application/script_host.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Runs one action's steps.
///
/// Permission model: **the manifest is the consent for a run started by a
/// trigger.** Nobody is present to answer a dialog when a poller fires at
/// three in the morning, so a capability an extension did not declare is
/// refused outright rather than queued behind a prompt. When the *agent* calls
/// the same action the existing `AIToolRegistry` consent applies on top.
class ActionRunner {
  ActionRunner({
    ExtensionDataStore? data,
    ProviderSecretStore? secrets,
    ScriptHost? scripts,
    ExtensionLibraryCache? libraries,
    http.Client? client,
  })  : _data = data ?? ExtensionDataStore.instance,
        _secrets = secrets ?? ProviderSecretStore(),
        _scripts = scripts ?? ScriptHost.instance,
        _libraries = libraries ?? ExtensionLibraryCache.instance,
        _client = client ?? http.Client();

  final ExtensionDataStore _data;
  final ProviderSecretStore _secrets;
  final ScriptHost _scripts;
  final ExtensionLibraryCache _libraries;
  final http.Client _client;
  final DocumentToolkit _documents = DocumentToolkit();

  /// One action may not run longer than this. Everything in this repo that
  /// reaches the network has a deadline; a run without one leaves the
  /// scheduler holding a slot for ever.
  static const runTimeout = Duration(seconds: 90);

  static const requestTimeout = Duration(seconds: 20);

  /// A stranger's response is not read past this. A recipe that pointed at a
  /// large file would otherwise pull it entirely into memory.
  static const maximumResponseBytes = 4 * 1024 * 1024;

  /// How far `action` steps may chain before it is called a loop.
  static const maximumDepth = 4;

  /// A page whose editor saw a keystroke this recently is left alone.
  static const caretQuietPeriod = Duration(seconds: 20);

  Future<ActionRun> run({
    required LoadedExtension extension,
    required ActionDefinition action,
    Map<String, Object?> arguments = const {},
    ActionRunCause cause = ActionRunCause.manual,
    int depth = 0,
  }) async {
    final started = DateTime.now();
    final pending = ActionRun(
      extensionId: extension.id,
      actionId: action.id,
      startedAt: started,
      status: ActionRunStatus.running,
      cause: cause,
    );

    final records = <ActionStepRecord>[];
    var status = ActionRunStatus.ok;
    var message = '';

    try {
      final context = await _buildContext(extension, arguments);
      for (final step in action.steps) {
        if (step.when != null && !step.when!.evaluate(context)) {
          records.add(
            ActionStepRecord(id: step.id, kind: step.kind, skipped: true),
          );
          continue;
        }
        try {
          final produced = await _runStep(
            extension: extension,
            step: step,
            context: context,
            depth: depth,
          );
          context[step.id] = produced;
          records.add(
            ActionStepRecord(id: step.id, kind: step.kind, skipped: false),
          );
        } on _StepRefused catch (refusal) {
          status = ActionRunStatus.refused;
          message = refusal.message;
          records.add(
            ActionStepRecord(
              id: step.id,
              kind: step.kind,
              skipped: false,
              error: refusal.message,
            ),
          );
          break;
        } on Object catch (error) {
          status = ActionRunStatus.failed;
          message = '$error';
          records.add(
            ActionStepRecord(
              id: step.id,
              kind: step.kind,
              skipped: false,
              error: '$error',
            ),
          );
          break;
        }
      }

      if (status == ActionRunStatus.ok &&
          records.isNotEmpty &&
          records.every((record) => record.skipped)) {
        status = ActionRunStatus.skipped;
        message = 'Nothing to do.';
      }
    } on Object catch (error) {
      status = ActionRunStatus.failed;
      message = '$error';
    }

    return pending.finished(
      status: status,
      duration: DateTime.now().difference(started),
      message: message,
      steps: records,
    );
  }

  Future<ActionContext> _buildContext(
    LoadedExtension extension,
    Map<String, Object?> arguments,
  ) async {
    await _data.ensureLoaded();
    final prefix = '${extension.id}.';
    final own = <String, Object?>{};
    for (final key in _data.keysUnder(extension.id)) {
      if (key.length > prefix.length && key.startsWith(prefix)) {
        _place(own, key.substring(prefix.length), _data.read(key));
      }
    }
    return <String, Object?>{
      'args': Map<String, Object?>.from(arguments),
      'data': own,
      'extension': extension.id,
      'now': DateTime.now().toIso8601String(),
    };
  }

  /// Files `quote.AAPL` into `{quote: {AAPL: …}}` so a recipe can read
  /// `{{ data.quote.AAPL }}` the way it wrote it.
  static void _place(Map<String, Object?> into, String key, Object? value) {
    final parts = key.split('.');
    var current = into;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = current[parts[i]];
      if (next is Map<String, Object?>) {
        current = next;
      } else {
        final made = <String, Object?>{};
        current[parts[i]] = made;
        current = made;
      }
    }
    current[parts.last] = value;
  }

  Future<Object?> _runStep({
    required LoadedExtension extension,
    required ActionStep step,
    required ActionContext context,
    required int depth,
  }) async {
    switch (step) {
      case HttpStep():
        return _runHttp(extension, step, context);
      case McpToolStep():
        return _runMcp(extension, step, context);
      case SetDataStep():
        return _runSet(extension, step, context);
      case DeleteDataStep():
        return _runDelete(extension, step, context);
      case DocumentStep():
        return _runDocument(extension, step, context);
      case NotifyStep():
        return _runNotify(step, context);
      case ScriptStep():
        return _runScript(extension, step, context);
      case CallActionStep():
        return _runAction(extension, step, context, depth);
    }
  }

  Future<Object?> _runScript(
    LoadedExtension extension,
    ScriptStep step,
    ActionContext context,
  ) async {
    final file = File(p.join(extension.folder, 'scripts', step.file));
    if (!file.existsSync()) {
      throw _StepRefused('There is no script called "${step.file}".');
    }
    final source = await file.readAsString();
    final libraries = await _libraries.sourcesFor(
      extension.manifest,
      extension.folder,
      names: step.libraries,
    );
    final input =
        step.input == null ? context : renderActionValue(step.input, context);

    final outcome = await _scripts.run(
      source: source,
      input: input,
      libraries: libraries,
    );
    if (outcome.isError) {
      throw _StepRefused('${step.file}: ${outcome.error}');
    }
    return outcome.value;
  }

  Future<Object?> _runHttp(
    LoadedExtension extension,
    HttpStep step,
    ActionContext context,
  ) async {
    final rendered = renderActionTemplate(step.url, context);
    final uri = Uri.tryParse(await _fillSecrets(extension, rendered));
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw _StepRefused('"$rendered" is not an address that can be fetched.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw _StepRefused('Only http and https can be fetched.');
    }
    if (!extension.manifest.allowsHost(uri.host)) {
      throw _StepRefused(
        '${extension.manifest.name} has not asked for ${uri.host}. '
        'Add "net:${uri.host}" to its permissions.',
      );
    }

    final headers = <String, String>{};
    for (final entry in step.headers.entries) {
      final value = renderActionValue(entry.value, context);
      headers[entry.key] = await _fillSecrets(extension, '$value');
    }

    final request = http.Request(step.method, uri)..headers.addAll(headers);
    if (step.body != null) {
      final body = renderActionValue(step.body, context);
      if (body is String) {
        request.body = body;
      } else {
        request.body = jsonEncode(body);
        headers.putIfAbsent('content-type', () => 'application/json');
        request.headers['content-type'] =
            headers['content-type'] ?? 'application/json';
      }
    }

    final streamed = await _client.send(request).timeout(requestTimeout);
    final bytes = <int>[];
    await for (final chunk in streamed.stream) {
      bytes.addAll(chunk);
      if (bytes.length > maximumResponseBytes) {
        throw _StepRefused(
          '${uri.host} sent more than '
          '${maximumResponseBytes ~/ (1024 * 1024)} MB.',
        );
      }
    }

    final text = utf8.decode(bytes, allowMalformed: true);
    final type = streamed.headers['content-type'] ?? '';
    Object? body = text;
    if (type.contains('json') || _looksLikeJson(text)) {
      try {
        body = jsonDecode(text);
      } on FormatException {
        body = text;
      }
    }

    return <String, Object?>{
      'status': streamed.statusCode,
      'ok': streamed.statusCode >= 200 && streamed.statusCode < 300,
      'headers': streamed.headers,
      'body': body,
    };
  }

  static bool _looksLikeJson(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  /// Replaces `{{ secret.<name> }}` at the point of use.
  ///
  /// ⚠️ Secrets are deliberately NOT part of the template context. If they
  /// were, a recipe could write one into the data store or a page, and the run
  /// log would carry it. They exist only inside a request's own address and
  /// headers, and only for names the manifest declared.
  Future<String> _fillSecrets(LoadedExtension extension, String source) async {
    if (!source.contains('secret.')) {
      return source;
    }
    var filled = source;
    for (final name in extension.manifest.secrets) {
      final token = '{{ secret.$name }}';
      final compact = '{{secret.$name}}';
      if (!filled.contains(token) && !filled.contains(compact)) {
        continue;
      }
      final value = await _secrets.read(_secretKey(extension.id, name)) ?? '';
      filled = filled.replaceAll(token, value).replaceAll(compact, value);
    }
    return filled;
  }

  static String secretKey(String extensionId, String name) =>
      _secretKey(extensionId, name);

  static String _secretKey(String extensionId, String name) =>
      'appflowy_extension_${extensionId}_$name';

  Future<Object?> _runMcp(
    LoadedExtension extension,
    McpToolStep step,
    ActionContext context,
  ) async {
    if (!extension.manifest.allows(ExtensionPermissionKind.mcp)) {
      throw _StepRefused(
        '${extension.manifest.name} has not asked to call tools. '
        'Add "mcp" to its permissions.',
      );
    }
    final name = renderActionTemplate(step.tool, context);
    final tool = AIToolRegistry.instance.toolFor(name);
    if (tool == null) {
      throw _StepRefused(
        'There is no tool called "$name". Check the server is turned on in '
        'Settings, AI.',
      );
    }
    final arguments = renderActionValue(step.arguments, context);
    final outcome = await AIToolRegistry.instance.run(
      AIToolCall(
        id: 'extension:${extension.id}:${step.id}',
        name: name,
        arguments: arguments is Map<String, Object?>
            ? Map<String, dynamic>.from(arguments)
            : <String, dynamic>{},
      ),
      chatId: 'extension:${extension.id}',
      // A trigger has nobody to ask, so an unapproved tool is refused rather
      // than left waiting on a dialog nobody will see.
      approve: (_, __) async => AIToolDecision.denyOnce,
    );
    if (outcome.result.isError) {
      throw _StepRefused(outcome.result.text);
    }
    final text = outcome.result.text;
    if (_looksLikeJson(text)) {
      try {
        return jsonDecode(text);
      } on FormatException {
        return text;
      }
    }
    return text;
  }

  Future<Object?> _runSet(
    LoadedExtension extension,
    SetDataStep step,
    ActionContext context,
  ) async {
    if (!extension.manifest.allows(ExtensionPermissionKind.data)) {
      throw _StepRefused(
        '${extension.manifest.name} has not asked to keep values. '
        'Add "data" to its permissions.',
      );
    }
    final key = ExtensionDataStore.qualify(
      extension.id,
      renderActionTemplate(step.key, context),
    );
    final value = renderActionValue(step.value, context);
    await _data.write(key, value, staleAfter: step.staleAfter);
    return value;
  }

  Future<Object?> _runDelete(
    LoadedExtension extension,
    DeleteDataStep step,
    ActionContext context,
  ) async {
    if (!extension.manifest.allows(ExtensionPermissionKind.data)) {
      throw _StepRefused(
        '${extension.manifest.name} has not asked to keep values.',
      );
    }
    await _data.remove(
      ExtensionDataStore.qualify(
        extension.id,
        renderActionTemplate(step.key, context),
      ),
    );
    return null;
  }

  /// ⚠️⚠️ An extension's write reaches the collab, but an OPEN editor is not
  /// told: `DocumentBloc._onDocumentStateUpdate` returns early unless the event
  /// is `isRemote` and document sync is on, so the page on screen would keep
  /// showing what it had. `syncV3()` re-reads, DIFFS against the editor's own
  /// document and applies only what changed with `isRemote: true`.
  ///
  /// That flag is also what keeps this out of the undo stack: `apply` routes a
  /// remote transaction through `_applyTransactionFromRemote` and returns
  /// before `_recordRedoOrUndo`. So Ctrl+Z after a refresh still undoes the
  /// person's own last edit, never the extension's.
  static Future<void> _refreshOpenEditor(String pageId) async {
    final bloc = DocumentBloc.findOpen(pageId);
    if (bloc == null || bloc.isClosed) {
      return;
    }
    try {
      await bloc.forceReloadDocumentState();
    } on Object catch (error) {
      Log.warn('A page could not be refreshed after a write: $error');
    }
  }

  Future<Object?> _runDocument(
    LoadedExtension extension,
    DocumentStep step,
    ActionContext context,
  ) async {
    if (!extension.manifest.allows(ExtensionPermissionKind.documentWrite)) {
      throw _StepRefused(
        '${extension.manifest.name} has not asked to change pages. '
        'Add "document:write" to its permissions.',
      );
    }

    final pageId = renderActionTemplate(step.pageId, context).trim();
    if (pageId.isEmpty) {
      throw _StepRefused('This step does not say which page to change.');
    }

    // ⚠️ Rule three: never write under a live caret. A page being typed in is
    // left alone rather than having its blocks rewritten mid-sentence.
    if (_isBeingEdited(pageId) &&
        step.operation != DocumentOperation.setAttributes) {
      throw _StepRefused(
        'That page is being written in, so it was left alone.',
      );
    }

    // ⚠️ Rule two: a document must be OPENED before it can be written. Reading
    // it with getDocument hands back a throwaway copy and every write is
    // silently dropped.
    final data = await _documents.open(pageId);
    if (data == null) {
      throw _StepRefused('That page could not be opened.');
    }

    switch (step.operation) {
      case DocumentOperation.append:
        final markdown = renderActionTemplate(step.markdown, context);
        if (markdown.trim().isEmpty) {
          return 0;
        }
        final document = _documents.parseMarkdown(markdown);
        final added = await _documents.insert(
          pageId: pageId,
          nodes: document.root.children,
          parentId: data.pageId,
          previousId: _documents.lastTopLevelBlockId(data),
        );
        await _refreshOpenEditor(pageId);
        return added;
      case DocumentOperation.setAttributes:
        final blockId = renderActionTemplate(step.blockId, context).trim();
        if (blockId.isEmpty) {
          throw _StepRefused('This step does not say which block to change.');
        }
        final attributes = renderActionValue(step.attributes, context);
        final applied = await _documents.update(
          pageId: pageId,
          data: data,
          blockId: blockId,
          attributes: attributes is Map
              ? Map<String, dynamic>.from(attributes)
              : const <String, dynamic>{},
        );
        if (!applied) {
          throw _StepRefused('There is no block "$blockId" on that page.');
        }
        await _refreshOpenEditor(pageId);
        return true;
      case DocumentOperation.replaceText:
        final blockId = renderActionTemplate(step.blockId, context).trim();
        if (blockId.isEmpty) {
          throw _StepRefused('This step does not say which block to change.');
        }
        final applied = await _documents.update(
          pageId: pageId,
          data: data,
          blockId: blockId,
          text: renderActionTemplate(step.text, context),
        );
        if (!applied) {
          throw _StepRefused('There is no block "$blockId" on that page.');
        }
        await _refreshOpenEditor(pageId);
        return true;
      case DocumentOperation.delete:
        final blockId = renderActionTemplate(step.blockId, context).trim();
        if (blockId.isEmpty) {
          throw _StepRefused('This step does not say which block to remove.');
        }
        final removed = await _documents.delete(
          pageId: pageId,
          data: data,
          blockId: blockId,
        );
        await _refreshOpenEditor(pageId);
        return removed;
    }
  }

  static bool _isBeingEdited(String pageId) {
    final bloc = DocumentBloc.findOpen(pageId);
    if (bloc == null) {
      return false;
    }
    final editor = bloc.state.editorState;
    if (editor == null) {
      return false;
    }
    // A caret in the page is enough: somebody is in it right now.
    return editor.selection != null;
  }

  Future<Object?> _runNotify(NotifyStep step, ActionContext context) async {
    final title = renderActionTemplate(step.title, context);
    final body = renderActionTemplate(step.body, context);
    if (title.trim().isEmpty && body.trim().isEmpty) {
      return null;
    }
    // ⚠️ Only warning / success / error exist — showToastNotification throws
    // an UnimplementedError for any other type.
    final type = switch (step.level) {
      'warning' => ToastificationType.warning,
      'error' => ToastificationType.error,
      _ => ToastificationType.success,
    };
    showToastNotification(
      context: AppGlobals.rootNavKey.currentContext,
      message: title.trim().isEmpty ? body : title,
      description: title.trim().isEmpty ? null : body,
      type: type,
    );
    return null;
  }

  Future<Object?> _runAction(
    LoadedExtension extension,
    CallActionStep step,
    ActionContext context,
    int depth,
  ) async {
    if (depth >= maximumDepth) {
      throw _StepRefused(
        'Actions called each other more than $maximumDepth deep.',
      );
    }
    final targetId = renderActionTemplate(step.actionId, context).trim();
    final target = extension.actionFor(targetId);
    if (target == null) {
      throw _StepRefused('There is no action called "$targetId".');
    }
    final arguments = renderActionValue(step.arguments, context);
    final outcome = await run(
      extension: extension,
      action: target,
      arguments: arguments is Map<String, Object?>
          ? arguments
          : const <String, Object?>{},
      cause: ActionRunCause.chained,
      depth: depth + 1,
    );
    if (outcome.status == ActionRunStatus.failed ||
        outcome.status == ActionRunStatus.refused) {
      throw _StepRefused(outcome.message);
    }
    return outcome.status.name;
  }

  void dispose() {
    _client.close();
  }
}

/// A step that could not run for a reason worth reading, as opposed to an
/// unexpected failure.
class _StepRefused implements Exception {
  _StepRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Logged rather than thrown when an extension is beyond help.
void reportExtensionProblem(String extensionId, String problem) =>
    Log.warn('Extension $extensionId: $problem');
