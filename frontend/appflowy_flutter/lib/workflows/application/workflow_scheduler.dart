import 'dart:async';
import 'dart:collection';

import 'package:appflowy_backend/log.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'workflow_model.dart';
import 'workflow_payloads.dart';
import 'workflow_run.dart';
import 'workflow_run_log.dart';
import 'workflow_runner.dart';
import 'workflow_schedule.dart';
import 'workflow_services.dart';
import 'workflow_store.dart';

class _Job {
  _Job({
    required this.workflowId,
    required this.cause,
    this.trigger,
    this.continuation,
    this.key,
  });

  final String workflowId;
  final WorkflowRunCause cause;
  final Object? trigger;
  final WorkflowContinuation? continuation;

  /// Jobs with the same key are never queued twice.
  final String? key;
  final Completer<WorkflowRun?> done = Completer<WorkflowRun?>();
}

/// How a webhook request was answered.
@immutable
class WorkflowWebhookAnswer {
  const WorkflowWebhookAnswer(this.status, this.body);

  final int status;
  final Map<String, Object?> body;
}

/// What one look at a polling trigger found.
@immutable
class WorkflowPollResult {
  const WorkflowPollResult({required this.payloads, required this.state});

  /// One per run to start, oldest first.
  final List<Map<String, Object?>> payloads;
  final WorkflowTriggerState state;
}

/// Decides when workflows run, and runs them.
///
/// It keeps going whether or not the window is visible: that is the point of
/// letting AppFlowy run in the background.
class WorkflowScheduler extends ChangeNotifier {
  WorkflowScheduler({
    required this.store,
    required this.log,
    required this.services,
    WorkflowRunner? runner,
    this.tickInterval = const Duration(seconds: 20),
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        runner = runner ??
            WorkflowRunner(
              services: services,
              store: store,
              log: log,
              clock: clock,
            );

  static const maximumConcurrentRuns = 2;

  /// One look at a trigger starts at most this many runs; the rest wait for
  /// the next look rather than flooding.
  static const maximumItemsPerPoll = 10;

  /// A row or page younger than this is probably still being typed into.
  static const settleTime = Duration(seconds: 30);

  /// A webhook flood stops being accepted here.
  static const maximumQueue = 200;

  final WorkflowStore store;
  final WorkflowRunLog log;
  final WorkflowServices services;
  final WorkflowRunner runner;
  final Duration tickInterval;
  final DateTime Function() _clock;

  /// Called after every run, for failure notifications.
  void Function(Workflow workflow, WorkflowRun run)? onRunFinished;

  final ListQueue<_Job> _queue = ListQueue<_Job>();
  final Set<String> _queuedKeys = {};
  final Set<String> _active = {};
  final Set<String> _polling = {};
  final Map<String, Completer<Map<String, Object?>>> _sampleListeners = {};

  Timer? _timer;
  bool _ticking = false;
  bool _started = false;
  bool _appStartRaised = false;
  String _workspaceId = '';

  bool get isStarted => _started;
  String get workspaceId => _workspaceId;
  bool get isPaused => store.settings.pausedAll;

  bool isRunning(String workflowId) => _active.contains(workflowId);
  bool isQueued(String workflowId) =>
      _queue.any((job) => job.workflowId == workflowId);
  bool isPolling(String workflowId) => _polling.contains(workflowId);
  bool isListeningForSample(String workflowId) =>
      _sampleListeners.containsKey(workflowId);
  bool get hasSampleListeners => _sampleListeners.isNotEmpty;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    await store.ensureLoaded();
    await log.ensureLoaded();
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  /// One pass: resume parked runs, start due schedules, look at polling
  /// triggers, raise app-start triggers.
  Future<void> tick() async {
    if (_ticking) {
      return;
    }
    _ticking = true;
    try {
      if (!store.isLoaded) {
        await store.ensureLoaded();
      }
      if (!log.isLoaded) {
        await log.ensureLoaded();
      }
      if (!store.isLoaded || !log.isLoaded) {
        return;
      }
      final current = await services.currentWorkspaceId();
      if (current != _workspaceId) {
        _workspaceId = current;
        notifyListeners();
      }
      if (_workspaceId.isEmpty || isPaused) {
        return;
      }
      final now = _clock();
      _resumeDue(now);
      _scheduleDue(now);
      _pollDue(now);
      if (!_appStartRaised) {
        _appStartRaised = true;
        for (final workflow in store.workflows) {
          if (workflow.trigger.kind == WorkflowTriggerKind.appStart &&
              _eligible(workflow)) {
            _enqueue(
              _Job(
                workflowId: workflow.id,
                cause: WorkflowRunCause.appStart,
                trigger: manualTriggerPayload(now),
              ),
            );
          }
        }
      }
    } on Object catch (error, stack) {
      Log.error('The workflow scheduler stumbled: $error\n$stack');
    } finally {
      _ticking = false;
      _pump();
    }
  }

  /// Whether [workflow] may start on its own right now.
  bool _eligible(Workflow workflow) =>
      workflow.enabled &&
      workflow.isComplete &&
      !isPaused &&
      workspaceMatches(workflow);

  bool workspaceMatches(Workflow workflow) =>
      _workspaceId.isNotEmpty &&
      (workflow.workspaceId.isEmpty || workflow.workspaceId == _workspaceId);

  void _resumeDue(DateTime now) {
    for (final continuation in log.dueContinuations(now)) {
      final workflow = store.byId(continuation.workflowId);
      if (workflow == null || !workflow.enabled) {
        unawaited(
          log.cancelParked(
            continuation.workflowId,
            message: 'The workflow was turned off while this run waited.',
          ),
        );
        continue;
      }
      if (!workspaceMatches(workflow)) {
        continue;
      }
      _enqueue(
        _Job(
          workflowId: workflow.id,
          cause: continuation.cause,
          continuation: continuation,
          key: 'resume:${continuation.runId}',
        ),
      );
    }
  }

  void _scheduleDue(DateTime now) {
    for (final workflow in store.workflows) {
      if (workflow.trigger.kind != WorkflowTriggerKind.schedule ||
          !_eligible(workflow)) {
        continue;
      }
      final schedule = workflow.trigger.schedule;
      final state = store.triggerState(workflow.id);
      final next = schedule.nextRun(
        now: now,
        lastRun: state.lastScheduled,
        since: workflow.enabledAt ?? workflow.updatedAt,
      );
      if (next == null || next.isAfter(now)) {
        continue;
      }
      final key = 'schedule:${workflow.id}';
      if (_queuedKeys.contains(key)) {
        continue;
      }
      // An interval keeps its rhythm when it is only a tick late; anything
      // later than one interval was missed and is owed a single run.
      final anchor = schedule.mode == WorkflowScheduleMode.interval &&
              now.difference(next) < schedule.interval
          ? next
          : now;
      store.setTriggerState(
        workflow.id,
        state.copyWith(lastScheduled: anchor),
        immediate: true,
      );
      _enqueue(
        _Job(
          workflowId: workflow.id,
          cause: WorkflowRunCause.schedule,
          trigger: scheduleTriggerPayload(next),
          key: key,
        ),
      );
    }
  }

  void _pollDue(DateTime now) {
    for (final workflow in store.workflows) {
      if (!workflow.trigger.kind.polls ||
          !_eligible(workflow) ||
          _polling.contains(workflow.id)) {
        continue;
      }
      final state = store.triggerState(workflow.id);
      final last = state.lastPoll;
      if (last != null &&
          state.signature == workflow.trigger.signature &&
          now.difference(last) < workflow.trigger.pollInterval) {
        continue;
      }
      unawaited(_poll(workflow));
    }
  }

  Future<void> _poll(Workflow workflow) async {
    _polling.add(workflow.id);
    notifyListeners();
    final trigger = workflow.trigger;
    var state = store.triggerState(workflow.id);
    if (state.signature != trigger.signature) {
      state = WorkflowTriggerState(signature: trigger.signature);
    }
    try {
      final result = await pollTrigger(trigger, state);
      final now = _clock();
      store.setTriggerState(
        workflow.id,
        result.state.copyWith(lastPoll: now, lastError: ''),
        immediate: result.payloads.isNotEmpty,
      );
      final latest = store.byId(workflow.id);
      if (latest == null ||
          !_eligible(latest) ||
          latest.trigger.signature != trigger.signature) {
        return;
      }
      final cause = WorkflowRunCause.of(trigger.kind);
      for (final payload in result.payloads) {
        _enqueue(
          _Job(workflowId: workflow.id, cause: cause, trigger: payload),
        );
      }
    } on Object catch (error) {
      final message = error is WorkflowStepException ? error.message : '$error';
      store.setTriggerState(
        workflow.id,
        state.copyWith(lastPoll: _clock(), lastError: message),
      );
    } finally {
      _polling.remove(workflow.id);
      notifyListeners();
      _pump();
    }
  }

  /// One look at a polling trigger. The first look only takes note of what
  /// is there, so turning a workflow on never fires for the back catalogue.
  @visibleForTesting
  Future<WorkflowPollResult> pollTrigger(
    WorkflowTrigger trigger,
    WorkflowTriggerState state,
  ) async {
    final now = _clock();
    switch (trigger.kind) {
      case WorkflowTriggerKind.feed:
        final feed = await services.fetchFeed(trigger.url);
        if (!state.baselined) {
          return WorkflowPollResult(
            payloads: const [],
            state: state.copyWith(
              baselined: true,
              seen: [for (final item in feed.items) item.key],
            ),
          );
        }
        final seen = state.seen.toSet();
        final fresh = [
          for (final item in feed.items)
            if (!seen.contains(item.key)) item,
        ];
        // Feeds list newest first; runs go oldest first.
        final ordered = fresh.every((item) => item.publishedAt != null)
            ? (fresh.toList()
              ..sort((a, b) => a.publishedAt!.compareTo(b.publishedAt!)))
            : fresh.reversed.toList();
        final taken = ordered.take(maximumItemsPerPoll).toList();
        return WorkflowPollResult(
          payloads: [
            for (final item in taken) feedTriggerPayload(feed, item),
          ],
          state: state.copyWith(
            seen: [...state.seen, for (final item in taken) item.key],
          ),
        );

      case WorkflowTriggerKind.databaseRow:
        final table = await services.readRows(trigger.viewId);
        if (!state.baselined) {
          return WorkflowPollResult(
            payloads: const [],
            state: state.copyWith(
              baselined: true,
              stamps: {for (final row in table.rows) row.id: row.modifiedAt},
            ),
          );
        }
        final known = state.stamps;
        final updates = trigger.includeUpdates;
        final picked = <(WorkflowRowData, bool)>[];
        for (final row in table.rows) {
          if (picked.length >= maximumItemsPerPoll) {
            break;
          }
          final settled = row.modifiedAt <= 0 ||
              now.difference(stampToDate(row.modifiedAt)) >= settleTime;
          if (!settled) {
            continue;
          }
          final before = known[row.id];
          if (before == null) {
            picked.add((row, true));
          } else if (updates && row.modifiedAt > before) {
            picked.add((row, false));
          }
        }
        final handled = {for (final (row, _) in picked) row.id};
        final stamps = <String, int>{};
        for (final row in table.rows) {
          final before = known[row.id];
          if (handled.contains(row.id) || (before != null && !updates)) {
            stamps[row.id] = row.modifiedAt;
          } else if (before != null) {
            // Changed but not handled yet: keep the old stamp so the next look
            // still sees the change.
            stamps[row.id] = before;
          }
        }
        return WorkflowPollResult(
          payloads: [
            for (final (row, isNew) in picked)
              rowTriggerPayload(row, isNew: isNew),
          ],
          state: state.copyWith(stamps: stamps),
        );

      case WorkflowTriggerKind.newPage:
        final pages = await services.childPages(trigger.parentId);
        if (!state.baselined) {
          return WorkflowPollResult(
            payloads: const [],
            state: state.copyWith(
              baselined: true,
              stamps: {for (final page in pages) page.id: 0},
            ),
          );
        }
        final known = state.stamps;
        final fresh = <WorkflowPageInfo>[];
        for (final page in pages) {
          if (known.containsKey(page.id)) {
            continue;
          }
          final created = page.createdAt;
          if (created != null && now.difference(created) < settleTime) {
            continue;
          }
          fresh.add(page);
        }
        fresh.sort(
          (a, b) => (a.createdAt ?? now).compareTo(b.createdAt ?? now),
        );
        final taken = fresh.take(maximumItemsPerPoll).toList();
        final current = {for (final page in pages) page.id};
        return WorkflowPollResult(
          payloads: [
            for (final page in taken)
              pageTriggerPayload(page, trigger.parentId),
          ],
          state: state.copyWith(
            stamps: {
              for (final entry in known.entries)
                if (current.contains(entry.key)) entry.key: entry.value,
              for (final page in taken) page.id: 0,
            },
          ),
        );

      default:
        return WorkflowPollResult(payloads: const [], state: state);
    }
  }

  void _enqueue(_Job job, {bool first = false}) {
    final key = job.key;
    if (key != null) {
      if (_queuedKeys.contains(key)) {
        return;
      }
      _queuedKeys.add(key);
    }
    if (first) {
      _queue.addFirst(job);
    } else {
      _queue.addLast(job);
    }
    notifyListeners();
  }

  void _pump() {
    while (_active.length < maximumConcurrentRuns) {
      final job =
          _queue.firstWhereOrNull((job) => !_active.contains(job.workflowId));
      if (job == null) {
        return;
      }
      _queue.remove(job);
      if (job.key != null) {
        _queuedKeys.remove(job.key);
      }
      _active.add(job.workflowId);
      notifyListeners();
      unawaited(_run(job));
    }
  }

  Future<void> _run(_Job job) async {
    WorkflowRun? run;
    try {
      final workflow = store.byId(job.workflowId);
      if (workflow != null) {
        final continuation = job.continuation;
        run = continuation != null
            ? await runner.resume(workflow, continuation)
            : await runner.start(
                workflow,
                cause: job.cause,
                trigger: job.trigger,
              );
        onRunFinished?.call(workflow, run);
      }
    } on Object catch (error, stack) {
      Log.error('A workflow run stopped unexpectedly: $error\n$stack');
    } finally {
      _active.remove(job.workflowId);
      if (!job.done.isCompleted) {
        job.done.complete(run);
      }
      notifyListeners();
      _pump();
    }
  }

  /// Runs [workflow] now, ahead of anything waiting. Works while it is off
  /// and while everything is paused: a person asked for it.
  Future<WorkflowRun?> runNow(Workflow workflow) {
    final now = _clock();
    final trigger = switch (workflow.trigger.kind) {
      WorkflowTriggerKind.schedule => scheduleTriggerPayload(now),
      WorkflowTriggerKind.manual ||
      WorkflowTriggerKind.appStart =>
        manualTriggerPayload(now),
      _ => workflow.samples[Workflow.triggerSampleKey] ??
          const <String, Object?>{},
    };
    final job = _Job(
      workflowId: workflow.id,
      cause: WorkflowRunCause.manual,
      trigger: trigger,
    );
    _enqueue(job, first: true);
    _pump();
    return job.done.future;
  }

  /// Answers one webhook request.
  Future<WorkflowWebhookAnswer> handleWebhook(
    String workflowId,
    String token,
    Map<String, Object?> payload,
  ) async {
    await store.ensureLoaded();
    final workflow = store.byId(workflowId);
    if (workflow == null ||
        workflow.trigger.kind != WorkflowTriggerKind.webhook ||
        !_sameSecret(workflow.trigger.token, token)) {
      return const WorkflowWebhookAnswer(
        404,
        {'ok': false, 'error': 'There is no workflow at this address.'},
      );
    }
    final listener = _sampleListeners.remove(workflowId);
    if (listener != null && !listener.isCompleted) {
      listener.complete(payload);
      notifyListeners();
      return const WorkflowWebhookAnswer(
        200,
        {'ok': true, 'status': 'captured'},
      );
    }
    if (!workflow.enabled) {
      return const WorkflowWebhookAnswer(
        409,
        {'ok': false, 'error': 'This workflow is turned off.'},
      );
    }
    if (isPaused) {
      return const WorkflowWebhookAnswer(
        503,
        {'ok': false, 'error': 'Workflows are paused.'},
      );
    }
    if (!workflow.isComplete) {
      return const WorkflowWebhookAnswer(
        409,
        {'ok': false, 'error': 'This workflow is not finished.'},
      );
    }
    if (_workspaceId.isEmpty) {
      _workspaceId = await services.currentWorkspaceId();
    }
    if (!workspaceMatches(workflow)) {
      return const WorkflowWebhookAnswer(
        409,
        {
          'ok': false,
          'error': 'Open the workspace this workflow belongs to.',
        },
      );
    }
    if (_queue.length >= maximumQueue) {
      return const WorkflowWebhookAnswer(
        429,
        {'ok': false, 'error': 'Too many requests are waiting.'},
      );
    }
    _enqueue(
      _Job(
        workflowId: workflow.id,
        cause: WorkflowRunCause.webhook,
        trigger: payload,
      ),
    );
    _pump();
    return const WorkflowWebhookAnswer(
      202,
      {'ok': true, 'status': 'queued'},
    );
  }

  /// The next request to [workflowId]'s address is captured as its sample
  /// instead of starting a run.
  Future<Map<String, Object?>> waitForWebhookSample(String workflowId) {
    final existing = _sampleListeners[workflowId];
    if (existing != null && !existing.isCompleted) {
      return existing.future;
    }
    final completer = Completer<Map<String, Object?>>();
    _sampleListeners[workflowId] = completer;
    notifyListeners();
    return completer.future;
  }

  void cancelWebhookSample(String workflowId) {
    final listener = _sampleListeners.remove(workflowId);
    if (listener != null && !listener.isCompleted) {
      listener.completeError(StateError('cancelled'));
      // Nobody else listens to this future; keep the error from escaping.
      unawaited(listener.future.catchError((Object _) => <String, Object?>{}));
    }
    notifyListeners();
  }

  /// When [workflow] will next start on its own, if it will.
  DateTime? nextRunOf(Workflow workflow) {
    if (!workflow.enabled || !workflow.isComplete) {
      return null;
    }
    final now = _clock();
    final state = store.triggerState(workflow.id);
    final trigger = workflow.trigger;
    if (trigger.kind == WorkflowTriggerKind.schedule) {
      final next = trigger.schedule.nextRun(
        now: now,
        lastRun: state.lastScheduled,
        since: workflow.enabledAt ?? workflow.updatedAt,
      );
      if (next == null) {
        return null;
      }
      return next.isBefore(now) ? now : next;
    }
    if (trigger.kind.polls) {
      final last = state.lastPoll;
      if (last == null || state.signature != trigger.signature) {
        return now;
      }
      final next = last.add(trigger.pollInterval);
      return next.isBefore(now) ? now : next;
    }
    return null;
  }

  /// Waits until nothing is queued, polling or running.
  @visibleForTesting
  Future<void> settle() async {
    for (var turn = 0; turn < 10000; turn++) {
      if (_active.isEmpty && _polling.isEmpty && _queue.isEmpty) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('The workflow scheduler did not settle.');
  }

  static bool _sameSecret(String expected, String given) {
    if (expected.isEmpty || expected.length != given.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ given.codeUnitAt(i);
    }
    return difference == 0;
  }

  @override
  void dispose() {
    stop();
    for (final listener in _sampleListeners.values) {
      if (!listener.isCompleted) {
        listener.completeError(StateError('stopped'));
        unawaited(
          listener.future.catchError((Object _) => <String, Object?>{}),
        );
      }
    }
    _sampleListeners.clear();
    super.dispose();
  }
}
