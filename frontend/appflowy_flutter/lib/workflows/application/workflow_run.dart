import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'workflow_model.dart';

enum WorkflowRunStatus {
  running,
  succeeded,
  failed,
  filtered,
  waiting,
  cancelled;

  static WorkflowRunStatus parse(Object? value) =>
      WorkflowRunStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => WorkflowRunStatus.failed,
      );

  bool get isFinished =>
      this != WorkflowRunStatus.running && this != WorkflowRunStatus.waiting;
}

/// Why a run started.
enum WorkflowRunCause {
  manual,
  test,
  schedule,
  webhook,
  feed,
  databaseRow,
  newPage,
  appStart;

  static WorkflowRunCause parse(Object? value) =>
      WorkflowRunCause.values.firstWhere(
        (cause) => cause.name == value,
        orElse: () => WorkflowRunCause.manual,
      );

  static WorkflowRunCause of(WorkflowTriggerKind kind) => switch (kind) {
        WorkflowTriggerKind.manual => WorkflowRunCause.manual,
        WorkflowTriggerKind.schedule => WorkflowRunCause.schedule,
        WorkflowTriggerKind.webhook => WorkflowRunCause.webhook,
        WorkflowTriggerKind.feed => WorkflowRunCause.feed,
        WorkflowTriggerKind.databaseRow => WorkflowRunCause.databaseRow,
        WorkflowTriggerKind.newPage => WorkflowRunCause.newPage,
        WorkflowTriggerKind.appStart => WorkflowRunCause.appStart,
      };

  /// Started by a person, who is watching and needs no notification.
  bool get isInteractive =>
      this == WorkflowRunCause.manual || this == WorkflowRunCause.test;
}

enum WorkflowStepStatus {
  succeeded,
  failed,
  filtered,
  waiting,
  skipped;

  static WorkflowStepStatus parse(Object? value) =>
      WorkflowStepStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => WorkflowStepStatus.failed,
      );
}

/// What one step did during a run.
@immutable
class WorkflowStepResult {
  const WorkflowStepResult({
    required this.stepId,
    required this.kind,
    required this.status,
    this.label = '',
    this.message = '',
    this.output,
    this.durationMs = 0,
  });

  final String stepId;
  final WorkflowStepKind? kind;
  final String label;
  final WorkflowStepStatus status;
  final String message;

  /// A shortened copy of what the step produced.
  final Object? output;
  final int durationMs;

  Map<String, Object?> toJson() => {
        'stepId': stepId,
        if (kind != null) 'kind': kind!.name,
        if (label.isNotEmpty) 'label': label,
        'status': status.name,
        if (message.isNotEmpty) 'message': message,
        if (output != null) 'output': output,
        if (durationMs > 0) 'ms': durationMs,
      };

  static WorkflowStepResult? fromJson(Object? source) {
    if (source is! Map) {
      return null;
    }
    final values = Map<String, Object?>.from(source);
    return WorkflowStepResult(
      stepId: (values['stepId'] as String?) ?? '',
      kind: WorkflowStepKind.parse(values['kind']),
      label: (values['label'] as String?) ?? '',
      status: WorkflowStepStatus.parse(values['status']),
      message: (values['message'] as String?) ?? '',
      output: values['output'],
      durationMs: (values['ms'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkflowStepResult &&
      other.stepId == stepId &&
      other.kind == kind &&
      other.label == label &&
      other.status == status &&
      other.message == message &&
      const DeepCollectionEquality().equals(other.output, output) &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(stepId, kind, status, message, durationMs);
}

/// One run of a workflow, as kept in its history.
@immutable
class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.workflowId,
    required this.workflowName,
    required this.cause,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.message = '',
    this.trigger,
    this.steps = const [],
    this.resumeAt,
  });

  final String id;
  final String workflowId;
  final String workflowName;
  final WorkflowRunCause cause;
  final WorkflowRunStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// Why it failed or stopped, in a sentence.
  final String message;

  /// A shortened copy of what the trigger delivered.
  final Object? trigger;
  final List<WorkflowStepResult> steps;

  /// A run parked by a delay step continues at this moment.
  final DateTime? resumeAt;

  Duration? get duration => finishedAt?.difference(startedAt);

  WorkflowRun copyWith({
    WorkflowRunStatus? status,
    DateTime? finishedAt,
    String? message,
    List<WorkflowStepResult>? steps,
    DateTime? resumeAt,
    bool clearResumeAt = false,
  }) =>
      WorkflowRun(
        id: id,
        workflowId: workflowId,
        workflowName: workflowName,
        cause: cause,
        status: status ?? this.status,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        message: message ?? this.message,
        trigger: trigger,
        steps: steps ?? this.steps,
        resumeAt: clearResumeAt ? null : resumeAt ?? this.resumeAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'workflowId': workflowId,
        'workflowName': workflowName,
        'cause': cause.name,
        'status': status.name,
        'startedAt': startedAt.toUtc().toIso8601String(),
        if (finishedAt != null)
          'finishedAt': finishedAt!.toUtc().toIso8601String(),
        if (message.isNotEmpty) 'message': message,
        if (trigger != null) 'trigger': trigger,
        'steps': [for (final step in steps) step.toJson()],
        if (resumeAt != null) 'resumeAt': resumeAt!.toUtc().toIso8601String(),
      };

  static WorkflowRun? fromJson(Object? source) {
    if (source is! Map) {
      return null;
    }
    final values = Map<String, Object?>.from(source);
    final id = (values['id'] as String?) ?? '';
    final started =
        DateTime.tryParse((values['startedAt'] as String?) ?? '')?.toLocal();
    if (id.isEmpty || started == null) {
      return null;
    }
    final rawSteps = values['steps'];
    return WorkflowRun(
      id: id,
      workflowId: (values['workflowId'] as String?) ?? '',
      workflowName: (values['workflowName'] as String?) ?? '',
      cause: WorkflowRunCause.parse(values['cause']),
      status: WorkflowRunStatus.parse(values['status']),
      startedAt: started,
      finishedAt:
          DateTime.tryParse((values['finishedAt'] as String?) ?? '')?.toLocal(),
      message: (values['message'] as String?) ?? '',
      trigger: values['trigger'],
      steps: [
        if (rawSteps is List)
          for (final entry in rawSteps)
            if (WorkflowStepResult.fromJson(entry) case final step?) step,
      ],
      resumeAt:
          DateTime.tryParse((values['resumeAt'] as String?) ?? '')?.toLocal(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkflowRun &&
      other.id == id &&
      other.workflowId == workflowId &&
      other.workflowName == workflowName &&
      other.cause == cause &&
      other.status == status &&
      other.startedAt == startedAt &&
      other.finishedAt == finishedAt &&
      other.message == message &&
      const DeepCollectionEquality().equals(other.trigger, trigger) &&
      listEquals(other.steps, steps) &&
      other.resumeAt == resumeAt;

  @override
  int get hashCode => Object.hash(id, status, finishedAt, steps.length);
}

/// A run parked by a delay step, with everything it needs to carry on.
@immutable
class WorkflowContinuation {
  const WorkflowContinuation({
    required this.runId,
    required this.workflowId,
    required this.nextStep,
    required this.context,
    required this.resumeAt,
    required this.cause,
  });

  final String runId;
  final String workflowId;

  /// The id of the first step still to run.
  final String nextStep;

  /// The run's data so far: trigger, earlier outputs. JSON-safe.
  final Map<String, Object?> context;
  final DateTime resumeAt;
  final WorkflowRunCause cause;

  Map<String, Object?> toJson() => {
        'runId': runId,
        'workflowId': workflowId,
        'nextStep': nextStep,
        'context': context,
        'resumeAt': resumeAt.toUtc().toIso8601String(),
        'cause': cause.name,
      };

  static WorkflowContinuation? fromJson(Object? source) {
    if (source is! Map) {
      return null;
    }
    final values = Map<String, Object?>.from(source);
    final runId = (values['runId'] as String?) ?? '';
    final workflowId = (values['workflowId'] as String?) ?? '';
    final nextStep = (values['nextStep'] as String?) ?? '';
    final resumeAt =
        DateTime.tryParse((values['resumeAt'] as String?) ?? '')?.toLocal();
    final context = values['context'];
    if (runId.isEmpty ||
        workflowId.isEmpty ||
        nextStep.isEmpty ||
        resumeAt == null ||
        context is! Map) {
      return null;
    }
    return WorkflowContinuation(
      runId: runId,
      workflowId: workflowId,
      nextStep: nextStep,
      context: Map<String, Object?>.from(context),
      resumeAt: resumeAt,
      cause: WorkflowRunCause.parse(values['cause']),
    );
  }
}
