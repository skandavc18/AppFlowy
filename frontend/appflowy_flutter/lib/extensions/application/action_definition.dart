import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/extensions/application/action_schedule.dart';
import 'package:appflowy/extensions/application/action_template.dart';
import 'package:flutter/foundation.dart';

/// Something other than a clock that can start an action.
enum ActionEvent {
  none,
  appStart,
  appResume,
  documentOpen,
  documentChange,
  documentClose,
  rowChanged,
  reminderFired;

  static ActionEvent parse(String name) => switch (name.trim()) {
        'start' || 'appStart' => ActionEvent.appStart,
        'resume' || 'appResume' => ActionEvent.appResume,
        'documentOpen' || 'pageOpen' => ActionEvent.documentOpen,
        'documentChange' || 'pageChange' => ActionEvent.documentChange,
        'documentClose' || 'pageClose' => ActionEvent.documentClose,
        'rowChanged' || 'row' => ActionEvent.rowChanged,
        'reminder' || 'reminderFired' => ActionEvent.reminderFired,
        _ => ActionEvent.none,
      };
}

/// When an action runs by itself.
@immutable
class ActionTrigger {
  const ActionTrigger({
    this.schedule,
    this.event = ActionEvent.none,
    this.viewId = '',
    this.tag = '',
    this.forEachKey = '',
    this.argumentName = '',
  });

  static const manual = ActionTrigger();

  final ActionSchedule? schedule;
  final ActionEvent event;

  /// Narrows a document or row event to one page. Empty means any.
  final String viewId;

  /// Narrows a reminder event to reminders carrying this tag.
  final String tag;

  /// A data key holding a list. The action runs once per entry.
  final String forEachKey;

  /// The argument each `forEach` entry is supplied as.
  final String argumentName;

  bool get isManual => schedule == null && event == ActionEvent.none;

  bool get isScheduled => schedule != null;

  bool get fansOut => forEachKey.isNotEmpty;

  static ActionTrigger fromJson(Map<String, Object?> values) {
    final fanOut = values['forEach'];
    var forEachKey = '';
    if (fanOut is Map && fanOut['data'] is String) {
      forEachKey = (fanOut['data']! as String).trim();
    } else if (fanOut is String) {
      forEachKey = fanOut.trim();
    }

    return ActionTrigger(
      schedule: ActionSchedule.fromJson(values),
      event: values['on'] is String
          ? ActionEvent.parse(values['on']! as String)
          : ActionEvent.none,
      viewId: (values['view'] as String?)?.trim() ?? '',
      tag: (values['tag'] as String?)?.trim() ?? '',
      forEachKey: forEachKey,
      argumentName: (values['as'] as String?)?.trim() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
        if (schedule != null) ...schedule!.toJson(),
        if (event != ActionEvent.none) 'on': event.name,
        if (viewId.isNotEmpty) 'view': viewId,
        if (tag.isNotEmpty) 'tag': tag,
        if (forEachKey.isNotEmpty) 'forEach': {'data': forEachKey},
        if (argumentName.isNotEmpty) 'as': argumentName,
      };
}

/// What a `document` step does to a page.
enum DocumentOperation {
  /// Markdown added at the end of the page.
  append,

  /// Attributes merged onto one block. The safe one: it never touches text, so
  /// it cannot move a caret.
  setAttributes,

  /// A block's words replaced.
  replaceText,

  /// A block removed.
  delete;

  static DocumentOperation? parse(String name) => switch (name.trim()) {
        'append' => DocumentOperation.append,
        'setAttributes' || 'attributes' => DocumentOperation.setAttributes,
        'replaceText' || 'text' => DocumentOperation.replaceText,
        'delete' => DocumentOperation.delete,
        _ => null,
      };
}

/// One thing an action does.
@immutable
sealed class ActionStep {
  const ActionStep({required this.id, this.when});

  final String id;
  final ActionCondition? when;

  /// The word the run log uses for this step.
  String get kind;

  static ActionStep? fromJson(Map<String, Object?> values, int index) {
    final id = (values['id'] as String?)?.trim().isNotEmpty ?? false
        ? (values['id']! as String).trim()
        : 'step$index';
    final rawWhen = values['when'];
    final when = rawWhen is String && rawWhen.trim().isNotEmpty
        ? ActionCondition.parse(rawWhen)
        : null;

    Map<String, Object?> body(String key) {
      final value = values[key];
      return value is Map ? Map<String, Object?>.from(value) : {};
    }

    if (values['http'] is Map) {
      return HttpStep.fromJson(id: id, when: when, values: body('http'));
    }
    if (values['mcp'] is Map) {
      final mcp = body('mcp');
      final tool = (mcp['tool'] as String?)?.trim() ?? '';
      if (tool.isEmpty) {
        return null;
      }
      return McpToolStep(
        id: id,
        when: when,
        tool: tool,
        arguments: mcp['arguments'] is Map
            ? Map<String, Object?>.from(mcp['arguments']! as Map)
            : const {},
      );
    }
    if (values['set'] is Map) {
      final set = body('set');
      final key = (set['key'] as String?)?.trim() ?? '';
      if (key.isEmpty) {
        return null;
      }
      return SetDataStep(
        id: id,
        when: when,
        key: key,
        value: set['value'],
        staleAfter: set['staleAfter'] is String
            ? ActionSchedule.parseInterval(set['staleAfter']! as String)
            : null,
      );
    }
    if (values['delete'] is Map) {
      final key = (body('delete')['key'] as String?)?.trim() ?? '';
      return key.isEmpty ? null : DeleteDataStep(id: id, when: when, key: key);
    }
    if (values['document'] is Map) {
      return DocumentStep.fromJson(
          id: id, when: when, values: body('document'));
    }
    if (values['script'] is Map) {
      final script = body('script');
      final file = (script['file'] as String?)?.trim() ?? '';
      if (file.isEmpty || !_isSafeScriptName(file)) {
        return null;
      }
      final libraries = script['libraries'];
      return ScriptStep(
        id: id,
        when: when,
        file: file,
        input: script['input'],
        libraries: [
          if (libraries is List)
            for (final entry in libraries)
              if (entry is String && entry.trim().isNotEmpty) entry.trim(),
        ],
      );
    }
    if (values['notify'] is Map) {
      final notify = body('notify');
      return NotifyStep(
        id: id,
        when: when,
        title: (notify['title'] as String?) ?? '',
        body: (notify['body'] as String?) ?? '',
        level: (notify['level'] as String?)?.trim() ?? 'info',
      );
    }
    if (values['action'] is Map) {
      final call = body('action');
      final target = (call['id'] as String?)?.trim() ?? '';
      if (target.isEmpty) {
        return null;
      }
      return CallActionStep(
        id: id,
        when: when,
        actionId: target,
        arguments: call['arguments'] is Map
            ? Map<String, Object?>.from(call['arguments']! as Map)
            : const {},
      );
    }
    return null;
  }
}

/// A request against a host the manifest named.
@immutable
class HttpStep extends ActionStep {
  const HttpStep({
    required super.id,
    required this.url,
    super.when,
    this.method = 'GET',
    this.headers = const {},
    this.body,
  });

  final String method;
  final String url;
  final Map<String, Object?> headers;
  final Object? body;

  @override
  String get kind => 'http';

  static HttpStep? fromJson({
    required String id,
    required ActionCondition? when,
    required Map<String, Object?> values,
  }) {
    for (final method in const ['get', 'post', 'put', 'patch', 'delete']) {
      final url = values[method];
      if (url is String && url.trim().isNotEmpty) {
        return HttpStep(
          id: id,
          when: when,
          method: method.toUpperCase(),
          url: url.trim(),
          headers: values['headers'] is Map
              ? Map<String, Object?>.from(values['headers']! as Map)
              : const {},
          body: values['body'],
        );
      }
    }
    final url = (values['url'] as String?)?.trim() ?? '';
    if (url.isEmpty) {
      return null;
    }
    return HttpStep(
      id: id,
      when: when,
      method: ((values['method'] as String?) ?? 'GET').toUpperCase(),
      url: url,
      headers: values['headers'] is Map
          ? Map<String, Object?>.from(values['headers']! as Map)
          : const {},
      body: values['body'],
    );
  }
}

/// A call to a tool on a configured MCP server.
@immutable
class McpToolStep extends ActionStep {
  const McpToolStep({
    required super.id,
    required this.tool,
    super.when,
    this.arguments = const {},
  });

  final String tool;
  final Map<String, Object?> arguments;

  @override
  String get kind => 'mcp';
}

/// Writes a value into the extension's reactive store.
@immutable
class SetDataStep extends ActionStep {
  const SetDataStep({
    required super.id,
    required this.key,
    super.when,
    this.value,
    this.staleAfter,
  });

  final String key;
  final Object? value;
  final Duration? staleAfter;

  @override
  String get kind => 'set';
}

@immutable
class DeleteDataStep extends ActionStep {
  const DeleteDataStep({
    required super.id,
    required this.key,
    super.when,
  });

  final String key;

  @override
  String get kind => 'delete';
}

/// Changes a page.
@immutable
class DocumentStep extends ActionStep {
  const DocumentStep({
    required super.id,
    required this.operation,
    required this.pageId,
    super.when,
    this.blockId = '',
    this.markdown = '',
    this.text = '',
    this.attributes = const {},
  });

  final DocumentOperation operation;
  final String pageId;
  final String blockId;
  final String markdown;
  final String text;
  final Map<String, Object?> attributes;

  @override
  String get kind => 'document';

  static DocumentStep? fromJson({
    required String id,
    required ActionCondition? when,
    required Map<String, Object?> values,
  }) {
    final operation =
        DocumentOperation.parse((values['op'] as String?) ?? 'append');
    final pageId = (values['page'] as String?)?.trim() ?? '';
    if (operation == null || pageId.isEmpty) {
      return null;
    }
    return DocumentStep(
      id: id,
      when: when,
      operation: operation,
      pageId: pageId,
      blockId: (values['block'] as String?)?.trim() ?? '',
      markdown: (values['markdown'] as String?) ?? '',
      text: (values['text'] as String?) ?? '',
      attributes: values['attributes'] is Map
          ? Map<String, Object?>.from(values['attributes']! as Map)
          : const {},
    );
  }
}

@immutable
class NotifyStep extends ActionStep {
  const NotifyStep({
    required super.id,
    super.when,
    this.title = '',
    this.body = '',
    this.level = 'info',
  });

  final String title;
  final String body;
  final String level;

  @override
  String get kind => 'notify';
}

@immutable
class CallActionStep extends ActionStep {
  const CallActionStep({
    required super.id,
    required this.actionId,
    super.when,
    this.arguments = const {},
  });

  final String actionId;
  final Map<String, Object?> arguments;

  @override
  String get kind => 'action';
}

/// Glue JavaScript, run in a worker that has no network, no filesystem and no
/// DOM. Because it is inert it needs no permission of its own.
@immutable
class ScriptStep extends ActionStep {
  const ScriptStep({
    required super.id,
    required this.file,
    super.when,
    this.input,
    this.libraries = const [],
  });

  /// A file inside the extension's own `scripts/` folder.
  final String file;

  /// What the script is handed. The whole step context when left out.
  final Object? input;

  /// Which declared libraries to put in scope. All of them when empty.
  final List<String> libraries;

  @override
  String get kind => 'script';
}

/// ⚠️ A script name may not climb out of `scripts/`.
bool _isSafeScriptName(String file) =>
    !file.contains('..') &&
    !file.startsWith('/') &&
    !file.startsWith(r'\') &&
    !file.contains(':');

/// One action: what it is called, what it takes, when it runs, what it does.
///
/// This is also the declaration the AI agent sees — the name, the sentence and
/// the JSON Schema are exactly what an MCP tool carries, so an action needs no
/// second description to be callable by the model.
@immutable
class ActionDefinition {
  const ActionDefinition({
    required this.id,
    required this.description,
    this.risk = AIToolRisk.write,
    this.schema = const {'type': 'object', 'properties': <String, Object?>{}},
    this.trigger = ActionTrigger.manual,
    this.steps = const [],
    this.enabled = true,
    this.exposeToAgent = true,
  });

  final String id;
  final String description;
  final AIToolRisk risk;

  /// JSON Schema for the arguments.
  final Map<String, Object?> schema;
  final ActionTrigger trigger;
  final List<ActionStep> steps;
  final bool enabled;

  /// Whether the model is told about this action. A noisy internal step can be
  /// hidden without being turned off.
  final bool exposeToAgent;

  static AIToolRisk _risk(Object? value) => switch (value) {
        'read' => AIToolRisk.read,
        'destructive' => AIToolRisk.destructive,
        _ => AIToolRisk.write,
      };

  static ActionDefinition? fromJson(Map<String, Object?> values) {
    final id = (values['id'] as String?)?.trim() ?? '';
    if (id.isEmpty || !_idPattern.hasMatch(id)) {
      return null;
    }
    final rawSteps = values['steps'];
    final steps = <ActionStep>[];
    if (rawSteps is List) {
      for (var index = 0; index < rawSteps.length; index++) {
        final entry = rawSteps[index];
        if (entry is! Map) {
          continue;
        }
        final step =
            ActionStep.fromJson(Map<String, Object?>.from(entry), index);
        if (step != null) {
          steps.add(step);
        }
      }
    }

    return ActionDefinition(
      id: id,
      description: (values['description'] as String?)?.trim() ?? '',
      risk: _risk(values['risk']),
      schema: values['schema'] is Map
          ? Map<String, Object?>.from(values['schema']! as Map)
          : const {'type': 'object', 'properties': <String, Object?>{}},
      trigger: values['trigger'] is Map
          ? ActionTrigger.fromJson(
              Map<String, Object?>.from(values['trigger']! as Map),
            )
          : ActionTrigger.manual,
      steps: steps,
      enabled: values['enabled'] != false,
      exposeToAgent: values['agent'] != false,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        if (description.isNotEmpty) 'description': description,
        'risk': risk.name,
        'schema': schema,
        if (!trigger.isManual) 'trigger': trigger.toJson(),
        if (!enabled) 'enabled': false,
        if (!exposeToAgent) 'agent': false,
      };

  /// Same rule as an extension id: it becomes half of a tool name.
  static final RegExp _idPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$');
}
