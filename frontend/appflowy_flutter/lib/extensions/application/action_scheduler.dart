import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_runner.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/application/extension_run_log.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/widgets.dart';

/// One run waiting for a slot.
@immutable
class _Pending {
  const _Pending({
    required this.extensionId,
    required this.actionId,
    required this.cause,
    this.arguments = const {},
  });

  final String extensionId;
  final String actionId;
  final ActionRunCause cause;
  final Map<String, Object?> arguments;

  /// Two requests for the same action with the same arguments are one request.
  String get key =>
      '$extensionId/$actionId/${arguments.entries.map((e) => '${e.key}=${e.value}').join(',')}';
}

/// Decides when actions run, and makes sure they do not all run at once.
///
/// ⚠️ There is ONE of these for every extension. Twenty extensions each owning
/// a `Timer.periodic` would each wake the app on its own schedule and compete
/// for the network while somebody is typing.
class ActionScheduler extends ChangeNotifier {
  ActionScheduler({
    ExtensionStore? store,
    ExtensionRunLog? log,
    ActionRunner? runner,
  })  : _store = store ?? ExtensionStore.instance,
        _log = log ?? ExtensionRunLog.instance,
        _runner = runner ?? ActionRunner();

  static final ActionScheduler instance = ActionScheduler();

  /// How often the clock is consulted. Actions run on the order of minutes, so
  /// a coarse tick costs nothing and keeps the app quiet.
  static const tick = Duration(seconds: 20);

  /// Long enough after launch that the workspace has settled — an action that
  /// fired during startup would compete with everything the app is loading.
  static const settleAfterStart = Duration(seconds: 20);

  /// How many runs may be in flight at once.
  static const maximumConcurrent = 3;

  /// The longest a failing action is made to wait before it is tried again.
  static const maximumBackoff = Duration(minutes: 30);

  final ExtensionStore _store;
  final ExtensionRunLog _log;
  final ActionRunner _runner;

  final List<_Pending> _queue = [];
  final Set<String> _queued = {};
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _blockedUntil = {};

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  int _inFlight = 0;
  bool _started = false;
  bool _active = true;

  bool get isRunning => _inFlight > 0;

  int get queueLength => _queue.length;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    await _store.ensureLoaded();
    await _log.ensureLoaded();
    await ExtensionDataStore.instance.ensureLoaded();
    await _store.startWatching();

    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        // Nothing runs while the window is hidden: a background poller that
        // kept the network busy would be a battery bug on a laptop.
        _active = state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive;
        if (_active) {
          _pump();
        }
      },
    );

    _timer = Timer.periodic(tick, (_) => _sweep());

    // ⚠️ Catch-up is ONE run per missed action, not one per interval that went
    // by. A poller left off for a week must not wake up and fire six hundred
    // times.
    Timer(settleAfterStart, () {
      _raise(ActionEvent.appStart);
      _sweep();
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _started = false;
    await _store.stopWatching();
    await ExtensionDataStore.instance.flush();
    await _log.flush();
  }

  /// Something happened that an action may have asked to hear about.
  void raise(ActionEvent event, {String viewId = '', String tag = ''}) =>
      _raise(event, viewId: viewId, tag: tag);

  void _raise(ActionEvent event, {String viewId = '', String tag = ''}) {
    if (event == ActionEvent.none) {
      return;
    }
    for (final extension in _store.active) {
      for (final action in extension.actions) {
        if (!action.enabled || action.trigger.event != event) {
          continue;
        }
        final wanted = action.trigger;
        if (wanted.viewId.isNotEmpty && wanted.viewId != viewId) {
          continue;
        }
        if (wanted.tag.isNotEmpty && wanted.tag != tag) {
          continue;
        }
        _enqueueAll(
          extension: extension,
          action: action,
          cause: ActionRunCause.event,
          extra: {
            if (viewId.isNotEmpty) 'view': viewId,
            if (tag.isNotEmpty) 'tag': tag,
          },
        );
      }
    }
    _pump();
  }

  void _sweep() {
    if (!_active) {
      return;
    }
    final now = DateTime.now();
    for (final extension in _store.active) {
      for (final action in extension.scheduledActions) {
        final key = '${extension.id}/${action.id}';
        final blocked = _blockedUntil[key];
        if (blocked != null && blocked.isAfter(now)) {
          continue;
        }
        final lastAttempt = _log.lastAttemptOf(extension.id, action.id);
        if (!action.trigger.schedule!.isDue(now: now, lastRun: lastAttempt)) {
          continue;
        }
        _enqueueAll(
          extension: extension,
          action: action,
          cause: ActionRunCause.schedule,
        );
      }
    }
    _pump();
  }

  /// Queues one run, or one per entry when the trigger fans out.
  void _enqueueAll({
    required LoadedExtension extension,
    required ActionDefinition action,
    required ActionRunCause cause,
    Map<String, Object?> extra = const {},
  }) {
    final trigger = action.trigger;
    if (!trigger.fansOut) {
      _enqueue(
        _Pending(
          extensionId: extension.id,
          actionId: action.id,
          cause: cause,
          arguments: extra,
        ),
      );
      return;
    }

    final key = ExtensionDataStore.qualify(extension.id, trigger.forEachKey);
    final value = ExtensionDataStore.instance.read(key);
    if (value is! List || value.isEmpty) {
      return;
    }
    final name = trigger.argumentName.isEmpty ? 'item' : trigger.argumentName;
    for (final entry in value) {
      _enqueue(
        _Pending(
          extensionId: extension.id,
          actionId: action.id,
          cause: cause,
          arguments: {...extra, name: entry},
        ),
      );
    }
  }

  void _enqueue(_Pending pending) {
    if (_queued.contains(pending.key)) {
      return;
    }
    _queued.add(pending.key);
    _queue.add(pending);
  }

  void _pump() {
    if (!_active) {
      return;
    }
    while (_inFlight < maximumConcurrent && _queue.isNotEmpty) {
      final pending = _queue.removeAt(0);
      _queued.remove(pending.key);
      unawaited(_dispatch(pending));
    }
  }

  Future<void> _dispatch(_Pending pending) async {
    final extension = _store.byId(pending.extensionId);
    final action = extension?.actionFor(pending.actionId);
    if (extension == null || action == null) {
      return;
    }

    _inFlight++;
    notifyListeners();
    try {
      final run = await _execute(
        extension: extension,
        action: action,
        arguments: pending.arguments,
        cause: pending.cause,
      );
      _recordOutcome(extension.id, action, run);
    } finally {
      _inFlight--;
      notifyListeners();
      _pump();
    }
  }

  Future<ActionRun> _execute({
    required LoadedExtension extension,
    required ActionDefinition action,
    required Map<String, Object?> arguments,
    required ActionRunCause cause,
  }) async {
    try {
      return await _runner
          .run(
            extension: extension,
            action: action,
            arguments: arguments,
            cause: cause,
          )
          .timeout(
            ActionRunner.runTimeout,
            onTimeout: () => ActionRun(
              extensionId: extension.id,
              actionId: action.id,
              startedAt: DateTime.now(),
              status: ActionRunStatus.failed,
              cause: cause,
              message: 'It did not finish within '
                  '${ActionRunner.runTimeout.inSeconds} seconds.',
            ),
          );
    } on Object catch (error) {
      Log.warn('Action ${extension.id}/${action.id} failed: $error');
      return ActionRun(
        extensionId: extension.id,
        actionId: action.id,
        startedAt: DateTime.now(),
        status: ActionRunStatus.failed,
        cause: cause,
        message: '$error',
      );
    }
  }

  void _recordOutcome(
      String extensionId, ActionDefinition action, ActionRun run) {
    _log.record(run);

    final key = '$extensionId/${action.id}';
    if (run.status == ActionRunStatus.failed ||
        run.status == ActionRunStatus.refused) {
      final failures = (_failures[key] ?? 0) + 1;
      _failures[key] = failures;
      // Jittered exponential backoff, so a service that is refusing is not
      // asked again on every tick — and so several actions that failed
      // together do not come back in step.
      final base = math.min(
        maximumBackoff.inSeconds,
        30 * math.pow(2, math.min(failures, 6)).toInt(),
      );
      final jitter = math.Random().nextInt(math.max(1, base ~/ 4));
      _blockedUntil[key] = DateTime.now().add(Duration(seconds: base + jitter));
    } else {
      _failures.remove(key);
      _blockedUntil.remove(key);
    }
  }

  /// When this action is next owed a run, for the settings page.
  DateTime? nextRunOf(String extensionId, ActionDefinition action) {
    final schedule = action.trigger.schedule;
    if (schedule == null || !action.enabled) {
      return null;
    }
    final blocked = _blockedUntil['$extensionId/${action.id}'];
    final next = schedule.nextRun(
      now: DateTime.now(),
      lastRun: _log.lastAttemptOf(extensionId, action.id),
    );
    if (next == null) {
      return blocked;
    }
    if (blocked != null && blocked.isAfter(next)) {
      return blocked;
    }
    return next;
  }

  /// Runs an action at once, jumping the queue. Used by the "Run now" button
  /// and by the agent.
  Future<ActionRun> runNow({
    required String extensionId,
    required String actionId,
    Map<String, Object?> arguments = const {},
    ActionRunCause cause = ActionRunCause.manual,
  }) async {
    await _store.ensureLoaded();
    final extension = _store.byId(extensionId);
    final action = extension?.actionFor(actionId);
    if (extension == null || action == null) {
      return ActionRun(
        extensionId: extensionId,
        actionId: actionId,
        startedAt: DateTime.now(),
        status: ActionRunStatus.failed,
        cause: cause,
        message: 'There is no action called "$actionId".',
      );
    }

    _inFlight++;
    notifyListeners();
    try {
      final run = await _execute(
        extension: extension,
        action: action,
        arguments: arguments,
        cause: cause,
      );
      _recordOutcome(extension.id, action, run);
      return run;
    } finally {
      _inFlight--;
      notifyListeners();
      _pump();
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    _runner.dispose();
    super.dispose();
  }
}
