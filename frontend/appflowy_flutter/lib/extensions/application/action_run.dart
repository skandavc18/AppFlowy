import 'package:flutter/foundation.dart';

/// How a run ended.
enum ActionRunStatus {
  running,
  ok,

  /// A step failed. [ActionRun.message] says which and why.
  failed,

  /// A permission was not granted.
  refused,

  /// Its `when:` was false, or it had nothing to do.
  skipped;

  bool get isFinished => this != ActionRunStatus.running;
}

/// Why an action ran, which is the first thing anybody asks when it did
/// something unexpected.
enum ActionRunCause {
  schedule,
  event,
  agent,
  manual,
  island,
  chained;

  static ActionRunCause parse(String name) => ActionRunCause.values.firstWhere(
        (cause) => cause.name == name,
        orElse: () => ActionRunCause.manual,
      );
}

/// One step's fate inside a run.
@immutable
class ActionStepRecord {
  const ActionStepRecord({
    required this.id,
    required this.kind,
    required this.skipped,
    this.error = '',
  });

  final String id;
  final String kind;
  final bool skipped;
  final String error;

  bool get failed => error.isNotEmpty;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        if (skipped) 'skipped': true,
        if (error.isNotEmpty) 'error': error,
      };

  static ActionStepRecord fromJson(Map<String, Object?> values) =>
      ActionStepRecord(
        id: (values['id'] as String?) ?? '',
        kind: (values['kind'] as String?) ?? '',
        skipped: values['skipped'] == true,
        error: (values['error'] as String?) ?? '',
      );
}

/// What happened one time an action ran.
///
/// ⚠️ This exists because a periodic action that silently stops is the worst
/// failure there is. Without a record, "it used to update and now it does not"
/// has no evidence at all.
@immutable
class ActionRun {
  const ActionRun({
    required this.extensionId,
    required this.actionId,
    required this.startedAt,
    required this.status,
    this.cause = ActionRunCause.manual,
    this.duration = Duration.zero,
    this.message = '',
    this.steps = const [],
  });

  final String extensionId;
  final String actionId;
  final DateTime startedAt;
  final Duration duration;
  final ActionRunStatus status;
  final ActionRunCause cause;
  final String message;
  final List<ActionStepRecord> steps;

  ActionRun finished({
    required ActionRunStatus status,
    required Duration duration,
    String message = '',
    List<ActionStepRecord> steps = const [],
  }) =>
      ActionRun(
        extensionId: extensionId,
        actionId: actionId,
        startedAt: startedAt,
        duration: duration,
        status: status,
        cause: cause,
        message: message,
        steps: steps,
      );

  Map<String, Object?> toJson() => {
        'extension': extensionId,
        'action': actionId,
        'startedAt': startedAt.toIso8601String(),
        'ms': duration.inMilliseconds,
        'status': status.name,
        'cause': cause.name,
        if (message.isNotEmpty) 'message': message,
        if (steps.isNotEmpty)
          'steps': [for (final step in steps) step.toJson()],
      };

  static ActionRun? fromJson(Map<String, Object?> values) {
    final startedAt = DateTime.tryParse((values['startedAt'] as String?) ?? '');
    if (startedAt == null) {
      return null;
    }
    final rawSteps = values['steps'];
    return ActionRun(
      extensionId: (values['extension'] as String?) ?? '',
      actionId: (values['action'] as String?) ?? '',
      startedAt: startedAt,
      duration: Duration(milliseconds: (values['ms'] as int?) ?? 0),
      status: ActionRunStatus.values.firstWhere(
        (status) => status.name == values['status'],
        orElse: () => ActionRunStatus.ok,
      ),
      cause: ActionRunCause.parse((values['cause'] as String?) ?? ''),
      message: (values['message'] as String?) ?? '',
      steps: [
        if (rawSteps is List)
          for (final entry in rawSteps)
            if (entry is Map)
              ActionStepRecord.fromJson(Map<String, Object?>.from(entry)),
      ],
    );
  }
}

/// The last few runs of one action, and when it is next owed one.
@immutable
class ActionRunSummary {
  const ActionRunSummary({
    required this.actionId,
    this.lastRun,
    this.nextRun,
    this.runs = 0,
    this.failures = 0,
  });

  final String actionId;
  final ActionRun? lastRun;
  final DateTime? nextRun;
  final int runs;
  final int failures;

  bool get isHealthy =>
      lastRun == null || lastRun!.status != ActionRunStatus.failed;
}
