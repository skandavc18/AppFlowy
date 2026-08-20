import 'dart:convert';

import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_store.dart';

/// An extension's actions, offered to the agent.
///
/// ⚠️ An action and an MCP tool are the same object — a name, a sentence and a
/// JSON Schema — so nothing here converts between two shapes. This is why
/// writing one recipe makes the agent able to call it with no second
/// declaration and no second permission system.
class ExtensionToolServer implements AIToolServer {
  ExtensionToolServer({
    required this.extensionId,
    ExtensionStore? store,
    ActionScheduler? scheduler,
  })  : _store = store ?? ExtensionStore.instance,
        _scheduler = scheduler ?? ActionScheduler.instance;

  final String extensionId;
  final ExtensionStore _store;
  final ActionScheduler _scheduler;

  LoadedExtension? get _extension => _store.byId(extensionId);

  @override
  String get id => extensionId;

  @override
  String get label => _extension?.manifest.name ?? extensionId;

  @override
  bool get isAvailable => _store.isEnabled(extensionId) && _extension != null;

  @override
  Future<List<AITool>> listTools() async {
    final extension = _extension;
    if (extension == null || !_store.isEnabled(extensionId)) {
      return const [];
    }
    return [
      for (final action in extension.actions)
        if (action.enabled && action.exposeToAgent)
          AITool(
            serverId: extensionId,
            serverLabel: extension.manifest.name,
            name: action.id,
            description: _describe(extension, action),
            schema: Map<String, dynamic>.from(action.schema),
            risk: action.risk,
          ),
    ];
  }

  static String _describe(LoadedExtension extension, ActionDefinition action) {
    if (action.description.isNotEmpty) {
      return action.description;
    }
    return '${action.id}, from the ${extension.manifest.name} extension.';
  }

  @override
  Future<AIToolResult> call(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final run = await _scheduler.runNow(
      extensionId: extensionId,
      actionId: name,
      arguments: Map<String, Object?>.from(arguments),
      cause: ActionRunCause.agent,
    );

    return switch (run.status) {
      ActionRunStatus.ok => AIToolResult(_report(run)),
      ActionRunStatus.skipped => AIToolResult(
          run.message.isEmpty ? 'Nothing to do.' : run.message,
        ),
      _ => AIToolResult.error(
          run.message.isEmpty ? 'It did not finish.' : run.message,
        ),
    };
  }

  /// What the model is told after a run.
  ///
  /// An action's own output is whatever it wrote, so the answer names the
  /// steps that ran rather than inventing a result the recipe never declared.
  static String _report(ActionRun run) {
    final ran = run.steps.where((step) => !step.skipped).length;
    final skipped = run.steps.length - ran;
    final parts = <String>[
      'Ran ${run.actionId}',
      if (ran > 0) '$ran step${ran == 1 ? '' : 's'}',
      if (skipped > 0) '$skipped skipped',
      '${run.duration.inMilliseconds} ms',
    ];
    return parts.join(' · ');
  }

  @override
  Future<void> dispose() async {}
}

/// The JSON Schema an action gets when it declares none, so the model is never
/// handed a tool with an undeclared shape.
const emptyActionSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{},
};

/// Pretty-prints a schema for the settings page.
String describeActionSchema(Map<String, Object?> schema) {
  final properties = schema['properties'];
  if (properties is! Map || properties.isEmpty) {
    return '';
  }
  return properties.keys.map((key) => '$key').join(', ');
}

/// Used by the settings page to show what an action would send.
String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
