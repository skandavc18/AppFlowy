import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/ai/providers/ai_providers.dart';
import 'package:appflowy/ai/skills/ai_skill.dart';
import 'package:appflowy/ai/tools/document_toolkit.dart';
import 'package:appflowy/ai/tools/tool_registry.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/operations/ai_writer_entities.dart';
import 'package:appflowy/workspace/application/command_palette/palette_ai.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:nanoid/nanoid.dart';
import 'package:uuid/uuid.dart';

/// The chat id tool permissions granted in the palette are remembered under.
const paletteAIChatId = 'command_palette';

/// The conversation the palette holds for the whole session.
///
/// Tool calls are approved through [approve], which the palette points at
/// itself while it is open so the question appears above it.
final PaletteAIConversation paletteAIConversation = PaletteAIConversation(
  engine: () => WorkspacePaletteAIEngine(approve: paletteAIApproval),
  newConversationId: () => const Uuid().v4(),
  readPage: readPaletteSourcePage,
);

/// Asks whether a tool may run while the palette's conversation is answering.
/// Null when no surface can ask, in which case the model is given no tools.
AIToolApproval? paletteAIApproval;

/// What a page says, as plain text. Empty when it cannot be read in time.
Future<String> readPaletteSourcePage(String pageId) async {
  try {
    final result = await DocumentEventGetDocumentText(
      OpenDocumentPayloadPB(documentId: pageId),
    ).send().timeout(const Duration(seconds: 3));
    return result.fold((data) => data.text, (_) => '');
  } on TimeoutException {
    return '';
  }
}

/// The model the palette answers with, as it is shown.
String paletteAIModelLabel() {
  final selection = CustomAIProviderStore.instance.activeSelection;
  if (selection == null) {
    return LocaleKeys.commandPalette_ai_appflowyModel.tr();
  }
  return '${selection.model} · ${selection.provider.name}';
}

/// Answers with whatever model is chosen at the moment the question is asked:
/// a provider the person configured, or AppFlowy's own AI.
class WorkspacePaletteAIEngine implements PaletteAIEngine {
  WorkspacePaletteAIEngine({this.approve});

  final AIToolApproval? approve;

  PaletteAIEngine? _delegate;
  int _generation = 0;

  @override
  String get label => paletteAIModelLabel();

  @override
  bool get canContinueInChat =>
      CustomAIProviderStore.instance.activeSelection != null;

  @override
  Future<void> answer(
    PaletteAIRequest request, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(PaletteAIFailure failure) onError,
    void Function(String note)? onNote,
  }) async {
    final generation = ++_generation;
    await CustomAIProviderStore.instance.ensureLoaded();
    if (generation != _generation) {
      return;
    }
    final selection = CustomAIProviderStore.instance.activeSelection;
    final delegate = selection == null
        ? AppFlowyPaletteAIEngine()
        : CustomProviderPaletteAIEngine(
            provider: selection.provider,
            model: selection.model,
            approve: approve,
          );
    _delegate = delegate;
    await delegate.answer(
      request,
      onDelta: onDelta,
      onDone: onDone,
      onError: onError,
      onNote: onNote,
    );
  }

  @override
  Future<void> stop() async {
    _generation++;
    final delegate = _delegate;
    _delegate = null;
    await delegate?.stop();
  }
}

/// Answers from a provider the person configured themselves, with the same
/// tools and skills the chat page has.
class CustomProviderPaletteAIEngine implements PaletteAIEngine {
  CustomProviderPaletteAIEngine({
    required this.provider,
    required this.model,
    this.approve,
  });

  final CustomAIProvider provider;
  final String model;
  final AIToolApproval? approve;

  final CustomAIChatRunner _runner = CustomAIChatRunner();

  @override
  String get label => '$model · ${provider.name}';

  @override
  bool get canContinueInChat => true;

  @override
  Future<void> answer(
    PaletteAIRequest request, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(PaletteAIFailure failure) onError,
    void Function(String note)? onNote,
  }) async {
    final approve = this.approve;
    if (approve != null) {
      await AIToolRegistry.instance.refresh();
    }
    await AISkillStore.instance.ensureLoaded();

    await _runner.ask(
      provider: provider,
      model: model,
      turns: [
        for (final exchange in request.history) ...[
          AIChatTurn.user(exchange.question),
          AIChatTurn.assistant(exchange.answer),
        ],
        AIChatTurn.user(request.prompt),
      ],
      systemPrompt: _systemPrompt(request, canAct: approve != null),
      tools: approve == null ? const [] : AIToolRegistry.instance.tools,
      chatId: paletteAIChatId,
      approve: approve,
      onToolNote: onNote,
      onDelta: onDelta,
      onDone: (_) => onDone(),
      onError: (message) => onError(
        PaletteAIFailure(
          message,
          needsSetup: message.contains('API key'),
        ),
      ),
    );
  }

  String _systemPrompt(PaletteAIRequest request, {required bool canAct}) {
    final buffer = StringBuffer()
      ..writeln(
        'You are the assistant in AppFlowy\'s search palette. AppFlowy is a '
        'workspace of pages, tables, folders and files.',
      )
      ..writeln()
      ..writeln(
        '- Answer in Markdown, briefly first; add detail only when it helps.',
      )
      ..writeln(
        '- When pages from the workspace are given, ground the answer in them '
        'and name the pages you used. Never invent what a page says.',
      );
    if (canAct) {
      buffer
        ..writeln(
          '- You can act on the workspace with the tools you have been given. '
          'Use a tool rather than describing what somebody should do.',
        )
        ..writeln('- Never invent an id. Find one with a tool that lists '
            'things.')
        ..writeln('- If a call is refused, stop and say so.');
    }
    final skills = AISkillStore.instance.instructionsFor(request.question);
    if (skills.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('# How to do this well')
        ..writeln(skills);
    }
    return buffer.toString();
  }

  @override
  Future<void> stop() => _runner.stop();
}

/// Answers from AppFlowy's own AI, in the cloud or running locally.
class AppFlowyPaletteAIEngine implements PaletteAIEngine {
  AppFlowyPaletteAIEngine({AIRepository? service})
      : _service = service ?? AppFlowyAIService();

  final AIRepository _service;

  String? _taskId;
  CompletionStream? _stream;
  int _generation = 0;

  @override
  String get label => LocaleKeys.commandPalette_ai_appflowyModel.tr();

  @override
  bool get canContinueInChat => false;

  @override
  Future<void> answer(
    PaletteAIRequest request, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(PaletteAIFailure failure) onError,
    void Function(String note)? onNote,
  }) async {
    await stop();
    final generation = ++_generation;
    var finished = false;
    void finish(void Function() report) {
      if (finished || generation != _generation) return;
      finished = true;
      report();
      final stream = _stream;
      _stream = null;
      _taskId = null;
      // Not from inside the stream's own handler: let it return first.
      if (stream is AppFlowyCompletionStream) {
        Timer.run(() => unawaited(stream.dispose()));
      }
    }

    final started = await _service.streamCompletion(
      // ⚠️ Must be a UUID: the backend never streams a completion for an
      // object id it cannot parse, and reports nothing either.
      objectId: request.conversationId,
      text: request.prompt,
      completionType: CompletionTypePB.UserQuestion,
      history: [
        for (final exchange in request.history) ...[
          AiWriterRecord.user(content: exchange.question, format: null),
          AiWriterRecord.ai(content: exchange.answer),
        ],
      ],
      sourceIds: [for (final source in request.sources) source.id],
      onStart: () async {},
      processMessage: (text) async {
        if (!finished && generation == _generation) onDelta(text);
      },
      processAssistMessage: (_) async {},
      onEnd: () async => finish(onDone),
      onError: (error) => finish(
        () => onError(
          PaletteAIFailure(
            error.message.isEmpty
                ? LocaleKeys.commandPalette_ai_failed.tr()
                : error.message,
          ),
        ),
      ),
      onLocalAIStreamingStateChange: (state) => finish(
        () => onError(
          PaletteAIFailure(
            switch (state) {
              LocalAIStreamingState.notReady =>
                LocaleKeys.settings_aiPage_keys_localAINotReadyRetryLater.tr(),
              LocalAIStreamingState.disabled =>
                LocaleKeys.settings_aiPage_keys_localAIDisabled.tr(),
            },
            needsSetup: true,
          ),
        ),
      ),
    );

    if (generation != _generation) {
      // Stopped while starting: the task began anyway, so end it too.
      if (started != null) {
        await _end(started.$1, started.$2);
      }
      return;
    }
    if (started == null) {
      finish(
        () => onError(
          PaletteAIFailure(
            LocaleKeys.commandPalette_ai_couldNotStart.tr(),
            needsSetup: true,
          ),
        ),
      );
      return;
    }
    if (!finished) {
      _taskId = started.$1;
      _stream = started.$2;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    final taskId = _taskId;
    final stream = _stream;
    _taskId = null;
    _stream = null;
    if (taskId != null && stream != null) {
      await _end(taskId, stream);
    }
  }

  Future<void> _end(String taskId, CompletionStream stream) async {
    try {
      await AIEventStopCompleteText(CompleteTextTaskPB(taskId: taskId)).send();
    } on Object catch (error) {
      Log.warn('The palette could not stop an answer: $error');
    }
    if (stream is AppFlowyCompletionStream) {
      await stream.dispose();
    }
  }
}

/// Writing an answer into the workspace.
abstract final class PaletteAIDocuments {
  /// Adds [markdown] to the end of the page [pageId]. False when nothing was
  /// written.
  static Future<bool> append(String pageId, String markdown) async {
    if (markdown.trim().isEmpty) {
      return false;
    }
    final toolkit = DocumentToolkit();
    final data = await toolkit.open(pageId);
    if (data == null) {
      return false;
    }
    final nodes = toolkit.parseMarkdown(markdown).root.children;
    if (nodes.isEmpty) {
      return false;
    }
    final written = await toolkit.insert(
      pageId: pageId,
      nodes: nodes,
      parentId: data.pageId,
      previousId: toolkit.lastTopLevelBlockId(data),
    );
    if (written == 0) {
      return false;
    }
    // A backend write reaches an open editor only when it is asked to re-read.
    await DocumentBloc.findOpen(pageId)?.forceReloadDocumentState();
    return true;
  }

  /// Makes a page called [name] under [parentViewId] holding [markdown].
  static Future<ViewPB?> createPage({
    required String parentViewId,
    required String name,
    required String markdown,
    ViewSectionPB? section,
  }) async {
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: name,
      section: section,
      initialDataBytes: _documentBytes(markdown),
    );
    return result.fold(
      (view) => view,
      (error) {
        Log.warn('The answer could not be saved as a page: ${error.msg}');
        return null;
      },
    );
  }

  /// Writes [exchanges] as the transcript of the chat [chatId], so the chat
  /// page opens on the conversation the palette was having.
  static Future<void> seedChat(
    String chatId,
    List<PaletteAIExchange> exchanges, {
    String model = '',
  }) async {
    var at = DateTime.now().subtract(Duration(seconds: exchanges.length * 2));
    for (final exchange in exchanges) {
      await CustomAIChatTranscript.upsert(
        chatId,
        CustomAIChatEntry(
          id: 'custom_q_${nanoid(10)}',
          role: CustomAIChatRole.user,
          text: exchange.question,
          createdAt: at,
          model: model,
        ),
      );
      at = at.add(const Duration(seconds: 1));
      await CustomAIChatTranscript.upsert(
        chatId,
        CustomAIChatEntry(
          id: 'custom_a_${nanoid(10)}',
          role: CustomAIChatRole.assistant,
          text: exchange.answer,
          createdAt: at,
          model: model,
        ),
      );
      at = at.add(const Duration(seconds: 1));
    }
  }

  static Uint8List? _documentBytes(String markdown) {
    if (markdown.trim().isEmpty) {
      return null;
    }
    final document = DocumentToolkit().parseMarkdown(markdown);
    return DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
  }
}
