import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'workflow_files.dart';
import 'workflow_run.dart';

/// The history of runs, and the runs parked by a delay step.
class WorkflowRunLog extends ChangeNotifier {
  WorkflowRunLog({String? rootOverride, WorkflowFiles? files})
      : files = files ?? WorkflowFiles(rootOverride: rootOverride);

  static final WorkflowRunLog instance = WorkflowRunLog();

  static const runsFile = 'runs.json';
  static const pendingFile = 'pending.json';

  /// Runs kept across every workflow, newest first.
  static const runLimit = 400;

  static const persistDebounce = Duration(milliseconds: 800);

  final WorkflowFiles files;

  List<WorkflowRun> _runs = const [];
  List<WorkflowContinuation> _pending = const [];
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _persist;
  bool _runsDirty = false;

  bool get isLoaded => _loaded;

  /// Newest first.
  List<WorkflowRun> get runs => _runs;
  List<WorkflowContinuation> get pending => _pending;

  List<WorkflowRun> runsFor(String workflowId) => [
        for (final run in _runs)
          if (run.workflowId == workflowId) run,
      ];

  WorkflowRun? latestFor(String workflowId) =>
      _runs.firstWhereOrNull((run) => run.workflowId == workflowId);

  WorkflowRun? byId(String runId) =>
      _runs.firstWhereOrNull((run) => run.id == runId);

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final runs = await files.read(runsFile);
      final pending = await files.read(pendingFile);
      _pending = [
        if (pending is List)
          for (final entry in pending)
            if (WorkflowContinuation.fromJson(entry) case final item?) item,
      ];
      final parked = {for (final item in _pending) item.runId};
      var repaired = false;
      final loaded = <WorkflowRun>[];
      if (runs is List) {
        for (final entry in runs) {
          final run = WorkflowRun.fromJson(entry);
          if (run == null) {
            continue;
          }
          // A run that was going when the app stopped did not finish, and a
          // parked run whose note was lost will never continue.
          final interrupted = run.status == WorkflowRunStatus.running ||
              (run.status == WorkflowRunStatus.waiting &&
                  !parked.contains(run.id));
          if (!interrupted) {
            loaded.add(run);
            continue;
          }
          repaired = true;
          loaded.add(
            run.copyWith(
              status: WorkflowRunStatus.cancelled,
              finishedAt: run.finishedAt ?? run.startedAt,
              message: 'AppFlowy closed before this run finished.',
              clearResumeAt: true,
            ),
          );
        }
      }
      _runs = loaded;
      _loaded = true;
      if (repaired) {
        _runsDirty = true;
        _schedulePersist();
      }
    } on Object catch (error) {
      Log.warn('Workflow history could not be read: $error');
    } finally {
      _loading = null;
    }
    if (_loaded) {
      notifyListeners();
    }
  }

  /// Adds [run], or replaces the one with its id.
  void record(WorkflowRun run) {
    if (!_loaded) {
      return;
    }
    final index = _runs.indexWhere((entry) => entry.id == run.id);
    if (index < 0) {
      final next = [run, ..._runs];
      _runs = next.length > runLimit ? next.sublist(0, runLimit) : next;
    } else {
      _runs = [
        for (final entry in _runs) entry.id == run.id ? run : entry,
      ];
    }
    _runsDirty = true;
    _schedulePersist();
    notifyListeners();
  }

  void clearFor(String workflowId) {
    final before = _runs.length;
    _runs = [
      for (final run in _runs)
        if (run.workflowId != workflowId ||
            run.status == WorkflowRunStatus.waiting)
          run,
    ];
    if (_runs.length != before) {
      _runsDirty = true;
      _schedulePersist();
      notifyListeners();
    }
  }

  /// Parks a run; written at once, since losing it loses the run.
  Future<void> park(WorkflowContinuation continuation) async {
    if (!_loaded) {
      return;
    }
    _pending = [
      for (final item in _pending)
        if (item.runId != continuation.runId) item,
      continuation,
    ];
    notifyListeners();
    await _writePending();
  }

  Future<void> unpark(String runId) async {
    final before = _pending.length;
    _pending = [
      for (final item in _pending)
        if (item.runId != runId) item,
    ];
    if (_pending.length != before) {
      notifyListeners();
      await _writePending();
    }
  }

  /// Drops every parked run of a workflow that was deleted or switched off,
  /// and marks those runs cancelled.
  Future<void> cancelParked(String workflowId, {String message = ''}) async {
    final doomed = [
      for (final item in _pending)
        if (item.workflowId == workflowId) item.runId,
    ];
    if (doomed.isEmpty) {
      return;
    }
    _pending = [
      for (final item in _pending)
        if (item.workflowId != workflowId) item,
    ];
    final now = DateTime.now();
    _runs = [
      for (final run in _runs)
        doomed.contains(run.id)
            ? run.copyWith(
                status: WorkflowRunStatus.cancelled,
                finishedAt: now,
                message: message,
                clearResumeAt: true,
              )
            : run,
    ];
    _runsDirty = true;
    _schedulePersist();
    notifyListeners();
    await _writePending();
  }

  List<WorkflowContinuation> dueContinuations(DateTime now) => [
        for (final item in _pending)
          if (!item.resumeAt.isAfter(now)) item,
      ];

  Future<void> _writePending() => files.write(
        pendingFile,
        [for (final item in _pending) item.toJson()],
      );

  void _schedulePersist() {
    _persist?.cancel();
    _persist = Timer(persistDebounce, () {
      _persist = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _persist?.cancel();
    _persist = null;
    if (_runsDirty) {
      _runsDirty = false;
      await files.write(runsFile, [for (final run in _runs) run.toJson()]);
    }
    await files.settle();
  }

  @visibleForTesting
  Future<void> reload() {
    _loaded = false;
    _runs = const [];
    _pending = const [];
    return ensureLoaded();
  }

  @override
  void dispose() {
    _persist?.cancel();
    super.dispose();
  }
}
