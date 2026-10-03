import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'workflow_files.dart';
import 'workflow_model.dart';

/// How workflows behave as a whole.
@immutable
class WorkflowSettings {
  const WorkflowSettings({
    this.keepRunningInBackground = false,
    this.notifyOnFailure = true,
    this.pausedAll = false,
    this.closedHintShown = false,
  });

  /// Closing the window hides it to the notification area and workflows keep
  /// running until Quit is chosen there.
  final bool keepRunningInBackground;

  /// A run that fails without anyone watching posts a desktop notification.
  final bool notifyOnFailure;

  /// Nothing starts on its own while this is set; manual runs still work.
  final bool pausedAll;

  /// Whether the "still running in the background" notice was shown once.
  final bool closedHintShown;

  WorkflowSettings copyWith({
    bool? keepRunningInBackground,
    bool? notifyOnFailure,
    bool? pausedAll,
    bool? closedHintShown,
  }) =>
      WorkflowSettings(
        keepRunningInBackground:
            keepRunningInBackground ?? this.keepRunningInBackground,
        notifyOnFailure: notifyOnFailure ?? this.notifyOnFailure,
        pausedAll: pausedAll ?? this.pausedAll,
        closedHintShown: closedHintShown ?? this.closedHintShown,
      );

  Map<String, Object?> toJson() => {
        'keepRunningInBackground': keepRunningInBackground,
        'notifyOnFailure': notifyOnFailure,
        'pausedAll': pausedAll,
        'closedHintShown': closedHintShown,
      };

  static WorkflowSettings fromJson(Object? source) {
    if (source is! Map) {
      return const WorkflowSettings();
    }
    return WorkflowSettings(
      keepRunningInBackground: source['keepRunningInBackground'] == true,
      notifyOnFailure: source['notifyOnFailure'] != false,
      pausedAll: source['pausedAll'] == true,
      closedHintShown: source['closedHintShown'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkflowSettings &&
      other.keepRunningInBackground == keepRunningInBackground &&
      other.notifyOnFailure == notifyOnFailure &&
      other.pausedAll == pausedAll &&
      other.closedHintShown == closedHintShown;

  @override
  int get hashCode => Object.hash(
        keepRunningInBackground,
        notifyOnFailure,
        pausedAll,
        closedHintShown,
      );
}

/// What a trigger remembers between checks.
@immutable
class WorkflowTriggerState {
  const WorkflowTriggerState({
    this.signature = '',
    this.baselined = false,
    this.seen = const [],
    this.stamps = const {},
    this.lastPoll,
    this.lastScheduled,
    this.lastError = '',
  });

  /// How many things a polling trigger remembers having seen.
  static const seenLimit = 1000;

  /// Which configuration [seen] and [stamps] belong to.
  final String signature;

  /// Whether the first look happened. That look only records what is there:
  /// a new feed does not fire for its whole back catalogue.
  final bool baselined;

  /// Ids already handled, oldest first.
  final List<String> seen;

  /// Rows only: the change stamp each row had when last handled.
  final Map<String, int> stamps;
  final DateTime? lastPoll;

  /// Schedules only: the occurrence that last ran.
  final DateTime? lastScheduled;

  /// Why the last check failed, for the editor.
  final String lastError;

  WorkflowTriggerState copyWith({
    String? signature,
    bool? baselined,
    List<String>? seen,
    Map<String, int>? stamps,
    DateTime? lastPoll,
    DateTime? lastScheduled,
    String? lastError,
  }) {
    final nextSeen = seen ?? this.seen;
    return WorkflowTriggerState(
      signature: signature ?? this.signature,
      baselined: baselined ?? this.baselined,
      seen: nextSeen.length > seenLimit
          ? nextSeen.sublist(nextSeen.length - seenLimit)
          : nextSeen,
      stamps: stamps ?? this.stamps,
      lastPoll: lastPoll ?? this.lastPoll,
      lastScheduled: lastScheduled ?? this.lastScheduled,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, Object?> toJson() => {
        'signature': signature,
        'baselined': baselined,
        if (seen.isNotEmpty) 'seen': seen,
        if (stamps.isNotEmpty) 'stamps': stamps,
        if (lastPoll != null) 'lastPoll': lastPoll!.toUtc().toIso8601String(),
        if (lastScheduled != null)
          'lastScheduled': lastScheduled!.toUtc().toIso8601String(),
        if (lastError.isNotEmpty) 'lastError': lastError,
      };

  static WorkflowTriggerState fromJson(Object? source) {
    if (source is! Map) {
      return const WorkflowTriggerState();
    }
    final seen = source['seen'];
    final stamps = source['stamps'];
    return WorkflowTriggerState(
      signature: (source['signature'] as String?) ?? '',
      baselined: source['baselined'] == true,
      seen: [
        if (seen is List)
          for (final entry in seen)
            if (entry is String) entry,
      ],
      stamps: {
        if (stamps is Map)
          for (final entry in stamps.entries)
            if (entry.value is num)
              '${entry.key}': (entry.value as num).toInt(),
      },
      lastPoll:
          DateTime.tryParse((source['lastPoll'] as String?) ?? '')?.toLocal(),
      lastScheduled: DateTime.tryParse(
        (source['lastScheduled'] as String?) ?? '',
      )?.toLocal(),
      lastError: (source['lastError'] as String?) ?? '',
    );
  }
}

/// Every workflow, how workflows behave, what they stored, and what their
/// triggers remember.
///
/// Definitions and settings are written at once — they are what a person
/// made. Trigger memory and stored values change often and are gathered.
class WorkflowStore extends ChangeNotifier {
  WorkflowStore({String? rootOverride, WorkflowFiles? files})
      : files = files ?? WorkflowFiles(rootOverride: rootOverride);

  static final WorkflowStore instance = WorkflowStore();

  static const workflowsFile = 'workflows.json';
  static const settingsFile = 'settings.json';
  static const storageFile = 'storage.json';
  static const triggerFile = 'trigger_state.json';

  static const persistDebounce = Duration(seconds: 1);

  /// Stored values are for counters and small notes, not documents.
  static const storageLimit = 500;

  final WorkflowFiles files;

  List<Workflow> _workflows = const [];
  WorkflowSettings _settings = const WorkflowSettings();
  Map<String, Object?> _storage = {};
  Map<String, WorkflowTriggerState> _triggers = {};

  bool _loaded = false;
  Future<void>? _loading;
  Timer? _persist;
  bool _storageDirty = false;
  bool _triggersDirty = false;

  bool get isLoaded => _loaded;
  List<Workflow> get workflows => _workflows;
  WorkflowSettings get settings => _settings;
  Map<String, Object?> get storage => Map.unmodifiable(_storage);

  Workflow? byId(String id) =>
      _workflows.firstWhereOrNull((workflow) => workflow.id == id);

  WorkflowTriggerState triggerState(String workflowId) =>
      _triggers[workflowId] ?? const WorkflowTriggerState();

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final definitions = await files.read(workflowsFile);
      final settings = await files.read(settingsFile);
      final storage = await files.read(storageFile);
      final triggers = await files.read(triggerFile);

      final list = definitions is Map ? definitions['workflows'] : null;
      _workflows = [
        if (list is List)
          for (final entry in list)
            if (Workflow.fromJson(entry) case final workflow?) workflow,
      ];
      _settings = WorkflowSettings.fromJson(settings);
      _storage = storage is Map ? Map<String, Object?>.from(storage) : {};
      _triggers = {
        if (triggers is Map)
          for (final entry in triggers.entries)
            '${entry.key}': WorkflowTriggerState.fromJson(entry.value),
      };
      _loaded = true;
    } on Object catch (error) {
      // Read again next time rather than latched empty: a save after an empty
      // latch would wipe every workflow on disk.
      Log.warn('Workflows could not be read: $error');
    } finally {
      _loading = null;
    }
    if (_loaded) {
      notifyListeners();
    }
  }

  /// Adds [workflow], or replaces the one with its id.
  Future<void> save(Workflow workflow) async {
    await ensureLoaded();
    _requireLoaded();
    final index = _workflows.indexWhere((entry) => entry.id == workflow.id);
    _workflows = index < 0
        ? [..._workflows, workflow]
        : [
            for (final entry in _workflows)
              entry.id == workflow.id ? workflow : entry,
          ];
    notifyListeners();
    await _writeWorkflows();
  }

  Future<void> delete(String id) async {
    await ensureLoaded();
    _requireLoaded();
    final before = _workflows.length;
    _workflows = [
      for (final workflow in _workflows)
        if (workflow.id != id) workflow,
    ];
    if (_workflows.length == before) {
      return;
    }
    if (_triggers.remove(id) != null) {
      _triggersDirty = true;
      _schedulePersist();
    }
    notifyListeners();
    await _writeWorkflows();
  }

  Future<void> updateSettings(WorkflowSettings settings) async {
    await ensureLoaded();
    _requireLoaded();
    if (settings == _settings) {
      return;
    }
    _settings = settings;
    notifyListeners();
    await files.write(settingsFile, settings.toJson());
  }

  /// [immediate] writes at once: used when the trigger just fired, so a crash
  /// a moment later cannot make it fire again for the same thing.
  void setTriggerState(
    String workflowId,
    WorkflowTriggerState state, {
    bool immediate = false,
  }) {
    if (!_loaded) {
      return;
    }
    _triggers[workflowId] = state;
    _triggersDirty = true;
    if (immediate) {
      unawaited(flush());
    } else {
      _schedulePersist();
    }
  }

  void resetTriggerState(String workflowId) {
    if (_triggers.remove(workflowId) != null) {
      _triggersDirty = true;
      _schedulePersist();
    }
  }

  Object? readStorage(String key) => _storage[key.trim()];

  /// Writes or, for null, removes a stored value.
  void writeStorage(String key, Object? value) {
    final name = key.trim();
    if (name.isEmpty || !_loaded) {
      return;
    }
    if (value == null) {
      if (_storage.remove(name) == null) {
        return;
      }
    } else {
      if (!_storage.containsKey(name) && _storage.length >= storageLimit) {
        throw StateError(
          'Workflow storage is full ($storageLimit values). '
          'Remove values that are no longer needed.',
        );
      }
      _storage[name] = value;
    }
    _storageDirty = true;
    _schedulePersist();
    notifyListeners();
  }

  void clearStorage() {
    if (_storage.isEmpty) {
      return;
    }
    _storage = {};
    _storageDirty = true;
    _schedulePersist();
    notifyListeners();
  }

  void _requireLoaded() {
    if (!_loaded) {
      throw StateError('Workflows have not been read yet.');
    }
  }

  Future<void> _writeWorkflows() => files.write(workflowsFile, {
        'version': 1,
        'workflows': [for (final workflow in _workflows) workflow.toJson()],
      });

  void _schedulePersist() {
    _persist?.cancel();
    _persist = Timer(persistDebounce, () {
      _persist = null;
      unawaited(flush());
    });
  }

  /// Writes anything gathered, and waits for every queued write.
  Future<void> flush() async {
    _persist?.cancel();
    _persist = null;
    if (_storageDirty) {
      _storageDirty = false;
      await files.write(storageFile, _storage);
    }
    if (_triggersDirty) {
      _triggersDirty = false;
      await files.write(triggerFile, {
        for (final entry in _triggers.entries) entry.key: entry.value.toJson(),
      });
    }
    await files.settle();
  }

  @visibleForTesting
  Future<void> reload() {
    _loaded = false;
    _workflows = const [];
    _settings = const WorkflowSettings();
    _storage = {};
    _triggers = {};
    return ensureLoaded();
  }

  @override
  void dispose() {
    _persist?.cancel();
    super.dispose();
  }
}
