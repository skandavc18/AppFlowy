import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'workflow_schedule.dart';

const _deepEquality = DeepCollectionEquality();

/// What starts a workflow.
enum WorkflowTriggerKind {
  manual,
  schedule,
  webhook,
  feed,
  databaseRow,
  newPage,
  appStart;

  static WorkflowTriggerKind parse(Object? value) =>
      WorkflowTriggerKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => WorkflowTriggerKind.manual,
      );

  /// Triggers that look for something new by asking again on a clock.
  bool get polls =>
      this == WorkflowTriggerKind.feed ||
      this == WorkflowTriggerKind.databaseRow ||
      this == WorkflowTriggerKind.newPage;

  /// The fields a run of this trigger always carries, for the data picker
  /// before anything has been tested.
  List<String> get knownFields => switch (this) {
        WorkflowTriggerKind.manual => const ['startedAt'],
        WorkflowTriggerKind.schedule => const [
            'time',
            'date',
            'weekday',
            'scheduledAt',
          ],
        WorkflowTriggerKind.webhook => const [
            'body',
            'query',
            'headers',
            'method',
            'receivedAt',
          ],
        WorkflowTriggerKind.feed => const [
            'title',
            'link',
            'summary',
            'image',
            'publishedAt',
            'feedTitle',
          ],
        WorkflowTriggerKind.databaseRow => const [
            'rowId',
            'fields',
            'modifiedAt',
            'isNew',
          ],
        WorkflowTriggerKind.newPage => const [
            'id',
            'name',
            'createdAt',
            'parentId',
          ],
        WorkflowTriggerKind.appStart => const ['startedAt'],
      };
}

/// What a step does.
enum WorkflowStepKind {
  httpRequest,
  createPage,
  appendToPage,
  addRow,
  notify,
  reminder,
  filter,
  delay,
  formatter,
  code,
  storage;

  static WorkflowStepKind? parse(Object? value) =>
      WorkflowStepKind.values.firstWhereOrNull((kind) => kind.name == value);

  /// Steps that only shape data or flow and touch nothing outside the run.
  bool get isUtility =>
      this == WorkflowStepKind.filter ||
      this == WorkflowStepKind.delay ||
      this == WorkflowStepKind.formatter ||
      this == WorkflowStepKind.code ||
      this == WorkflowStepKind.storage;

  List<String> get knownFields => switch (this) {
        WorkflowStepKind.httpRequest => const [
            'status',
            'ok',
            'body',
            'headers',
          ],
        WorkflowStepKind.createPage => const ['id', 'name', 'parentId'],
        WorkflowStepKind.appendToPage => const ['pageId', 'blocks'],
        WorkflowStepKind.addRow => const ['rowId', 'viewId', 'values'],
        WorkflowStepKind.notify => const ['title', 'body'],
        WorkflowStepKind.reminder => const ['id', 'title', 'scheduledAt'],
        WorkflowStepKind.filter => const ['passed'],
        WorkflowStepKind.delay => const ['resumeAt'],
        WorkflowStepKind.formatter => const ['output'],
        WorkflowStepKind.code => const ['output'],
        WorkflowStepKind.storage => const ['key', 'value'],
      };
}

/// One name/value line: a request header, a column and what goes in it.
@immutable
class WorkflowPair {
  const WorkflowPair(this.key, this.value);

  final String key;
  final String value;

  Map<String, Object?> toJson() => {'key': key, 'value': value};

  static WorkflowPair fromJson(Map<String, Object?> values) => WorkflowPair(
        (values['key'] as String?) ?? '',
        (values['value'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is WorkflowPair && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);
}

/// How a filter compares two values.
enum WorkflowOperator {
  equals,
  notEquals,
  contains,
  notContains,
  startsWith,
  endsWith,
  greaterThan,
  lessThan,
  isEmpty,
  isNotEmpty;

  static WorkflowOperator parse(Object? value) =>
      WorkflowOperator.values.firstWhere(
        (operator) => operator.name == value,
        orElse: () => WorkflowOperator.equals,
      );

  /// Whether the operator compares against a second value at all.
  bool get needsValue =>
      this != WorkflowOperator.isEmpty && this != WorkflowOperator.isNotEmpty;
}

/// One line of a filter: `{{trigger.title}} contains "invoice"`.
@immutable
class WorkflowCondition {
  const WorkflowCondition({
    this.left = '',
    this.operator = WorkflowOperator.equals,
    this.right = '',
  });

  final String left;
  final WorkflowOperator operator;
  final String right;

  WorkflowCondition copyWith({
    String? left,
    WorkflowOperator? operator,
    String? right,
  }) =>
      WorkflowCondition(
        left: left ?? this.left,
        operator: operator ?? this.operator,
        right: right ?? this.right,
      );

  Map<String, Object?> toJson() => {
        'left': left,
        'operator': operator.name,
        if (operator.needsValue) 'right': right,
      };

  static WorkflowCondition fromJson(Map<String, Object?> values) =>
      WorkflowCondition(
        left: (values['left'] as String?) ?? '',
        operator: WorkflowOperator.parse(values['operator']),
        right: (values['right'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is WorkflowCondition &&
      other.left == left &&
      other.operator == operator &&
      other.right == right;

  @override
  int get hashCode => Object.hash(left, operator, right);
}

/// Shared reading of a configuration map.
mixin _WorkflowConfig {
  Map<String, Object?> get config;

  String text(String key) {
    final value = config[key];
    return switch (value) {
      null => '',
      final String text => text,
      _ => '$value',
    };
  }

  bool flag(String key, {bool fallback = false}) {
    final value = config[key];
    return value is bool ? value : fallback;
  }

  int number(String key, {int fallback = 0}) {
    final value = config[key];
    return switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? fallback,
      _ => fallback,
    };
  }

  List<WorkflowPair> pairs(String key) {
    final value = config[key];
    if (value is! List) {
      return const [];
    }
    return [
      for (final entry in value)
        if (entry is Map)
          WorkflowPair.fromJson(Map<String, Object?>.from(entry)),
    ];
  }
}

Map<String, Object?> _withValue(
  Map<String, Object?> config,
  String key,
  Object? value,
) {
  final next = Map<String, Object?>.from(config);
  if (value == null) {
    next.remove(key);
  } else if (value is List<WorkflowPair>) {
    next[key] = [for (final pair in value) pair.toJson()];
  } else if (value is List<WorkflowCondition>) {
    next[key] = [for (final condition in value) condition.toJson()];
  } else if (value is WorkflowSchedule) {
    next[key] = value.toJson();
  } else {
    next[key] = value;
  }
  return next;
}

Map<String, Object?> _copyConfig(Object? source) => source is Map
    ? Map<String, Object?>.from(jsonDecode(jsonEncode(source)) as Map)
    : <String, Object?>{};

/// A secret that makes a webhook address unguessable.
String newWorkflowToken({math.Random? random}) {
  final source = random ?? math.Random.secure();
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(
    32,
    (_) => alphabet[source.nextInt(alphabet.length)],
  ).join();
}

/// A short id for a workflow or a run.
String newWorkflowId({math.Random? random}) {
  final source = random ?? math.Random.secure();
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(
    12,
    (_) => alphabet[source.nextInt(alphabet.length)],
  ).join();
}

/// What starts a workflow, and how it is set up.
@immutable
class WorkflowTrigger with _WorkflowConfig {
  const WorkflowTrigger({
    this.kind = WorkflowTriggerKind.manual,
    this.config = const {},
  });

  factory WorkflowTrigger.create(WorkflowTriggerKind kind) => switch (kind) {
        WorkflowTriggerKind.schedule => WorkflowTrigger(
            kind: kind,
            config: {'schedule': const WorkflowSchedule().toJson()},
          ),
        WorkflowTriggerKind.webhook => WorkflowTrigger(
            kind: kind,
            config: {'token': newWorkflowToken()},
          ),
        WorkflowTriggerKind.feed => WorkflowTrigger(
            kind: kind,
            config: const {'url': '', 'poll': 15},
          ),
        WorkflowTriggerKind.databaseRow => WorkflowTrigger(
            kind: kind,
            config: const {'viewId': '', 'updates': false, 'poll': 2},
          ),
        WorkflowTriggerKind.newPage => WorkflowTrigger(
            kind: kind,
            config: const {'parentId': '', 'poll': 2},
          ),
        _ => WorkflowTrigger(kind: kind),
      };

  final WorkflowTriggerKind kind;

  @override
  final Map<String, Object?> config;

  WorkflowSchedule get schedule =>
      WorkflowSchedule.fromJson(config['schedule']);

  String get token => text('token');
  String get url => text('url').trim();
  String get viewId => text('viewId');
  String get viewName => text('viewName');
  String get parentId => text('parentId');
  String get parentName => text('parentName');
  bool get includeUpdates => flag('updates');

  /// How often a polling trigger asks again.
  Duration get pollInterval {
    final fallback = kind == WorkflowTriggerKind.feed ? 15 : 2;
    final minutes = number('poll', fallback: fallback);
    return Duration(minutes: minutes < 1 ? 1 : minutes);
  }

  bool get isConfigured => switch (kind) {
        WorkflowTriggerKind.webhook => token.isNotEmpty,
        WorkflowTriggerKind.feed => _isWebAddress(url),
        WorkflowTriggerKind.databaseRow => viewId.isNotEmpty,
        WorkflowTriggerKind.newPage => parentId.isNotEmpty,
        WorkflowTriggerKind.schedule =>
          schedule.mode != WorkflowScheduleMode.weekly ||
              schedule.weekdays.isNotEmpty,
        _ => true,
      };

  /// What a polling trigger watches. When this changes, what it has already
  /// seen means nothing and it starts afresh.
  String get signature => switch (kind) {
        WorkflowTriggerKind.feed => 'feed|$url',
        WorkflowTriggerKind.databaseRow => 'row|$viewId|$includeUpdates',
        WorkflowTriggerKind.newPage => 'page|$parentId',
        _ => kind.name,
      };

  WorkflowTrigger withValue(String key, Object? value) =>
      WorkflowTrigger(kind: kind, config: _withValue(config, key, value));

  WorkflowTrigger withSchedule(WorkflowSchedule schedule) =>
      withValue('schedule', schedule);

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        if (config.isNotEmpty) 'config': config,
      };

  static WorkflowTrigger fromJson(Object? source) {
    if (source is! Map) {
      return const WorkflowTrigger();
    }
    final values = Map<String, Object?>.from(source);
    return WorkflowTrigger(
      kind: WorkflowTriggerKind.parse(values['kind']),
      config: _copyConfig(values['config']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkflowTrigger &&
      other.kind == kind &&
      _deepEquality.equals(other.config, config);

  @override
  int get hashCode => Object.hash(kind, _deepEquality.hash(config));
}

bool _isWebAddress(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Whether [value] is an address a request can go to, or will be once its
/// `{{ }}` placeholders are filled.
bool isWorkflowAddress(String value) => value.contains('{{')
    ? value.trim().startsWith('http')
    : _isWebAddress(value);

/// One thing a workflow does.
@immutable
class WorkflowStep with _WorkflowConfig {
  const WorkflowStep({
    required this.id,
    required this.kind,
    this.label = '',
    this.config = const {},
  });

  factory WorkflowStep.create(String id, WorkflowStepKind kind) =>
      switch (kind) {
        WorkflowStepKind.httpRequest => WorkflowStep(
            id: id,
            kind: kind,
            config: const {
              'method': 'POST',
              'url': '',
              'bodyKind': 'json',
              'body': '',
              'failOnError': true,
            },
          ),
        WorkflowStepKind.createPage => WorkflowStep(
            id: id,
            kind: kind,
            config: const {'parentId': '', 'title': '', 'content': ''},
          ),
        WorkflowStepKind.appendToPage => WorkflowStep(
            id: id,
            kind: kind,
            config: const {'pageId': '', 'content': ''},
          ),
        WorkflowStepKind.addRow => WorkflowStep(
            id: id,
            kind: kind,
            config: const {'viewId': ''},
          ),
        WorkflowStepKind.notify => WorkflowStep(
            id: id,
            kind: kind,
            config: const {'title': '', 'body': ''},
          ),
        WorkflowStepKind.reminder => WorkflowStep(
            id: id,
            kind: kind,
            config: const {'title': '', 'message': '', 'when': 'in 1 hour'},
          ),
        WorkflowStepKind.filter => WorkflowStep(
            id: id,
            kind: kind,
            config: {
              'all': true,
              'conditions': [const WorkflowCondition().toJson()],
            },
          ),
        WorkflowStepKind.delay => WorkflowStep(
            id: id,
            kind: kind,
            config: const {'amount': 10, 'unit': 'minutes'},
          ),
        WorkflowStepKind.formatter => WorkflowStep(
            id: id,
            kind: kind,
            config: const {'operation': 'trim', 'input': ''},
          ),
        WorkflowStepKind.code => WorkflowStep(
            id: id,
            kind: kind,
            config: const {
              'code': '// `input` holds the trigger and every earlier step.\n'
                  'return { greeting: "Hello " + (input.trigger.name || "there") };',
            },
          ),
        WorkflowStepKind.storage => WorkflowStep(
            id: id,
            kind: kind,
            config: const {'operation': 'set', 'key': '', 'value': ''},
          ),
      };

  final String id;
  final WorkflowStepKind kind;

  /// A name the person gave this step. Empty means the kind's own name.
  final String label;

  @override
  final Map<String, Object?> config;

  List<WorkflowCondition> get conditions {
    final value = config['conditions'];
    if (value is! List) {
      return const [];
    }
    return [
      for (final entry in value)
        if (entry is Map)
          WorkflowCondition.fromJson(Map<String, Object?>.from(entry)),
    ];
  }

  /// Delay steps only: how long to wait.
  Duration get delay {
    final amount = number('amount', fallback: 1).clamp(1, 100000);
    final unit = WorkflowIntervalUnit.parse(config['unit']);
    final value = unit.of(amount);
    return value > maximumDelay ? maximumDelay : value;
  }

  /// A run is never parked longer than this.
  static const maximumDelay = Duration(days: 30);

  bool get isConfigured => switch (kind) {
        WorkflowStepKind.httpRequest => isWorkflowAddress(text('url')),
        WorkflowStepKind.createPage => text('title').trim().isNotEmpty,
        WorkflowStepKind.appendToPage =>
          text('pageId').isNotEmpty && text('content').trim().isNotEmpty,
        WorkflowStepKind.addRow => text('viewId').isNotEmpty,
        WorkflowStepKind.notify =>
          text('title').trim().isNotEmpty || text('body').trim().isNotEmpty,
        WorkflowStepKind.reminder =>
          text('title').trim().isNotEmpty && text('when').trim().isNotEmpty,
        WorkflowStepKind.filter =>
          conditions.isNotEmpty && conditions.every((c) => c.left.isNotEmpty),
        WorkflowStepKind.delay => true,
        WorkflowStepKind.formatter => text('operation').isNotEmpty,
        WorkflowStepKind.code => text('code').trim().isNotEmpty,
        WorkflowStepKind.storage => text('key').trim().isNotEmpty,
      };

  WorkflowStep withValue(String key, Object? value) => WorkflowStep(
        id: id,
        kind: kind,
        label: label,
        config: _withValue(config, key, value),
      );

  WorkflowStep withLabel(String label) =>
      WorkflowStep(id: id, kind: kind, label: label.trim(), config: config);

  WorkflowStep withId(String id) =>
      WorkflowStep(id: id, kind: kind, label: label, config: config);

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        if (label.isNotEmpty) 'label': label,
        if (config.isNotEmpty) 'config': config,
      };

  static WorkflowStep? fromJson(Object? source) {
    if (source is! Map) {
      return null;
    }
    final values = Map<String, Object?>.from(source);
    final kind = WorkflowStepKind.parse(values['kind']);
    final id = (values['id'] as String?)?.trim() ?? '';
    if (kind == null || id.isEmpty) {
      return null;
    }
    return WorkflowStep(
      id: id,
      kind: kind,
      label: (values['label'] as String?) ?? '',
      config: _copyConfig(values['config']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkflowStep &&
      other.id == id &&
      other.kind == kind &&
      other.label == label &&
      _deepEquality.equals(other.config, config);

  @override
  int get hashCode => Object.hash(id, kind, label, _deepEquality.hash(config));
}

/// A trigger followed by the steps it sets off.
@immutable
class Workflow {
  const Workflow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.enabled = false,
    this.trigger = const WorkflowTrigger(),
    this.steps = const [],
    this.enabledAt,
    this.workspaceId = '',
    this.samples = const {},
    this.stepCounter = 0,
  });

  factory Workflow.create({
    required String name,
    String workspaceId = '',
    DateTime? now,
    WorkflowTrigger trigger = const WorkflowTrigger(),
    List<WorkflowStep> steps = const [],
    String description = '',
  }) {
    final at = now ?? DateTime.now();
    return Workflow(
      id: newWorkflowId(),
      name: name,
      description: description,
      createdAt: at,
      updatedAt: at,
      workspaceId: workspaceId,
      trigger: trigger,
      steps: steps,
    );
  }

  /// The sample a trigger test produced is stored under this key.
  static const triggerSampleKey = 'trigger';

  static const maximumSteps = 40;

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final WorkflowTrigger trigger;
  final List<WorkflowStep> steps;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When it was last turned on. A schedule counts its first run from here.
  final DateTime? enabledAt;

  /// The workspace whose pages and tables its steps act on. Empty means it
  /// was made before workspaces were recorded and may run anywhere.
  final String workspaceId;

  /// What the last test of the trigger and of each step produced, so the data
  /// picker can offer real field names.
  final Map<String, Object?> samples;

  /// The highest step number ever handed out.
  final int stepCounter;

  bool get isComplete =>
      trigger.isConfigured &&
      steps.isNotEmpty &&
      steps.every((step) => step.isConfigured);

  WorkflowStep? stepById(String id) =>
      steps.firstWhereOrNull((step) => step.id == id);

  int indexOfStep(String id) => steps.indexWhere((step) => step.id == id);

  /// `step1`, `step2`… Never reused while the workflow exists, so a template
  /// written against one step cannot silently start reading another.
  String nextStepId() {
    var highest = stepCounter;
    for (final step in steps) {
      final number = _stepNumber(step.id);
      if (number != null && number > highest) {
        highest = number;
      }
    }
    return 'step${highest + 1}';
  }

  static int? _stepNumber(String id) {
    final match = RegExp(r'^step(\d+)$').firstMatch(id);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Workflow copyWith({
    String? name,
    String? description,
    bool? enabled,
    WorkflowTrigger? trigger,
    List<WorkflowStep>? steps,
    DateTime? updatedAt,
    DateTime? enabledAt,
    bool clearEnabledAt = false,
    String? workspaceId,
    Map<String, Object?>? samples,
    int? stepCounter,
  }) =>
      Workflow(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        enabled: enabled ?? this.enabled,
        trigger: trigger ?? this.trigger,
        steps: steps ?? this.steps,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        enabledAt: clearEnabledAt ? null : enabledAt ?? this.enabledAt,
        workspaceId: workspaceId ?? this.workspaceId,
        samples: samples ?? this.samples,
        stepCounter: stepCounter ?? this.stepCounter,
      );

  Workflow replaceStep(WorkflowStep step) => copyWith(
        steps: [
          for (final existing in steps)
            existing.id == step.id ? step : existing,
        ],
      );

  Workflow insertStep(int index, WorkflowStep step) {
    final next = [...steps]..insert(index.clamp(0, steps.length), step);
    final number = _stepNumber(step.id) ?? 0;
    return copyWith(
      steps: next,
      stepCounter: math.max(stepCounter, number),
    );
  }

  Workflow removeStep(String id) => copyWith(
        steps: [
          for (final step in steps)
            if (step.id != id) step,
        ],
        samples: {
          for (final entry in samples.entries)
            if (entry.key != id) entry.key: entry.value,
        },
      );

  Workflow moveStep(String id, int offset) {
    final from = indexOfStep(id);
    final to = from + offset;
    if (from < 0 || to < 0 || to >= steps.length) {
      return this;
    }
    final next = [...steps];
    final step = next.removeAt(from);
    next.insert(to, step);
    return copyWith(steps: next);
  }

  Workflow withSample(String key, Object? sample) => copyWith(
        samples: {
          ...samples,
          key: sample,
        },
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (description.isNotEmpty) 'description': description,
        'enabled': enabled,
        'trigger': trigger.toJson(),
        'steps': [for (final step in steps) step.toJson()],
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (enabledAt != null)
          'enabledAt': enabledAt!.toUtc().toIso8601String(),
        if (workspaceId.isNotEmpty) 'workspaceId': workspaceId,
        if (samples.isNotEmpty) 'samples': samples,
        if (stepCounter > 0) 'stepCounter': stepCounter,
      };

  static Workflow? fromJson(Object? source) {
    if (source is! Map) {
      return null;
    }
    final values = Map<String, Object?>.from(source);
    final id = (values['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      return null;
    }
    final created =
        DateTime.tryParse((values['createdAt'] as String?) ?? '')?.toLocal() ??
            DateTime.now();
    final rawSteps = values['steps'];
    return Workflow(
      id: id,
      name: (values['name'] as String?) ?? '',
      description: (values['description'] as String?) ?? '',
      enabled: values['enabled'] == true,
      trigger: WorkflowTrigger.fromJson(values['trigger']),
      steps: [
        if (rawSteps is List)
          for (final entry in rawSteps)
            if (WorkflowStep.fromJson(entry) case final step?) step,
      ],
      createdAt: created,
      updatedAt: DateTime.tryParse((values['updatedAt'] as String?) ?? '')
              ?.toLocal() ??
          created,
      enabledAt:
          DateTime.tryParse((values['enabledAt'] as String?) ?? '')?.toLocal(),
      workspaceId: (values['workspaceId'] as String?) ?? '',
      samples: _copyConfig(values['samples']),
      stepCounter: switch (values['stepCounter']) {
        final int number when number > 0 => number,
        _ => 0,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Workflow &&
      other.id == id &&
      other.name == name &&
      other.description == description &&
      other.enabled == enabled &&
      other.trigger == trigger &&
      listEquals(other.steps, steps) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.enabledAt == enabledAt &&
      other.workspaceId == workspaceId &&
      other.stepCounter == stepCounter &&
      _deepEquality.equals(other.samples, samples);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        enabled,
        trigger,
        Object.hashAll(steps),
        updatedAt,
        workspaceId,
      );
}
