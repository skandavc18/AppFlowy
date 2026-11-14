import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import 'workflow_background.dart';
import 'workflow_model.dart';
import 'workflow_payloads.dart';
import 'workflow_run.dart';
import 'workflow_run_log.dart';
import 'workflow_runner.dart';
import 'workflow_scheduler.dart';
import 'workflow_services.dart';
import 'workflow_store.dart';
import 'workflow_webhook_server.dart';

/// Workflows as the rest of the app sees them: what exists, how to change it,
/// and the machinery that runs it — with or without a window.
class WorkflowManager extends ChangeNotifier {
  WorkflowManager({
    WorkflowStore? store,
    WorkflowRunLog? log,
    WorkflowServices? services,
    WorkflowScheduler? scheduler,
    WorkflowWebhookServer? webhooks,
    WorkspaceSyncEngine? syncEngine,
  })  : store = store ?? WorkflowStore.instance,
        log = log ?? WorkflowRunLog.instance,
        services = services ?? AppWorkflowServices(),
        _sync = syncEngine ?? WorkspaceSyncEngine.instance {
    this.scheduler = scheduler ??
        WorkflowScheduler(
          store: this.store,
          log: this.log,
          services: this.services,
        );
    this.webhooks = webhooks ??
        WorkflowWebhookServer(handler: this.scheduler.handleWebhook);
  }

  static final WorkflowManager instance = WorkflowManager();

  final WorkflowStore store;
  final WorkflowRunLog log;
  final WorkflowServices services;
  final WorkspaceSyncEngine _sync;
  late final WorkflowScheduler scheduler;
  late final WorkflowWebhookServer webhooks;

  bool _started = false;
  Future<void>? _starting;
  Timer? _backgroundTimer;
  bool _launchAtLogin = false;
  bool _launchAtLoginBeforeStop = false;
  bool _quitting = false;
  String? _backgroundErrorKey;
  (bool, bool, bool)? _lastSyncTrayState;

  bool get isStarted => _started;

  /// Whether the operating system starts AppFlowy hidden at sign-in.
  bool get launchAtLogin => _launchAtLogin;

  String? get backgroundErrorKey => _backgroundErrorKey;

  Future<void> start() {
    final running = _starting;
    if (running != null) return running;
    final next = _start().whenComplete(() => _starting = null);
    _starting = next;
    return next;
  }

  bool get _syncWantsBackground =>
      _sync.settings.bindings.isNotEmpty &&
      _sync.settings.keepRunningInBackground;

  void _onSyncStateChanged() {
    if (!_started || !WorkflowBackground.isSupported) {
      return;
    }
    final current = (
      _sync.settings.bindings.isNotEmpty,
      _sync.settings.keepRunningInBackground,
      _sync.isAllPaused,
    );
    if (_lastSyncTrayState == current) {
      return;
    }
    _lastSyncTrayState = current;
    unawaited(_syncBackgroundChanged());
  }

  Future<void> _syncBackgroundChanged() async {
    await applyBackgroundSettings();
    if (!FlowyRunner.currentMode.isTest &&
        _syncWantsBackground &&
        !_launchAtLogin &&
        _backgroundErrorKey == null) {
      await setLaunchAtLogin(true);
    } else if (!store.settings.keepRunningInBackground &&
        !_syncWantsBackground &&
        _launchAtLogin) {
      await setLaunchAtLogin(false);
    }
  }

  void _onWindowShown() {
    _sync.setBackgroundMode(false);
  }

  Future<void> _start() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      await store.ensureLoaded();
      await log.ensureLoaded();
      await _sync.settings.ensureLoaded();
    } on Object catch (error) {
      Log.warn('Workflows could not be read at startup: $error');
    }
    scheduler.onRunFinished = _onRunFinished;
    store.addListener(_syncWebhookServer);
    scheduler.addListener(_syncWebhookServer);
    _sync.addListener(_onSyncStateChanged);
    _sync.settings.addListener(_onSyncStateChanged);
    _lastSyncTrayState = (
      _sync.settings.bindings.isNotEmpty,
      _sync.settings.keepRunningInBackground,
      _sync.isAllPaused,
    );

    if (WorkflowBackground.isSupported) {
      WorkflowBackground.instance.attach(
        onTrayAction: _onTrayAction,
        onClosedToTray: _onClosedToTray,
      );
      WorkflowBackground.instance.addShownListener(_onWindowShown);
      if (WorkflowBackground.startedInBackground) {
        _sync.setBackgroundMode(true);
      }
      await applyBackgroundSettings();
      _launchAtLogin =
          await WorkflowBackground.instance.isLaunchAtLoginEnabled();
      if (_backgroundErrorKey != null && _launchAtLogin) {
        await setLaunchAtLogin(false);
      } else if (!FlowyRunner.currentMode.isTest &&
          _syncWantsBackground &&
          !_launchAtLogin &&
          _backgroundErrorKey == null) {
        await setLaunchAtLogin(true);
      }
      // Started hidden at sign-in, but neither workflows nor sync asked to keep
      // running: a hidden process with no icon could never be found again.
      if (WorkflowBackground.startedInBackground &&
          !store.settings.keepRunningInBackground &&
          !_syncWantsBackground) {
        await WorkflowBackground.instance.showWindow();
      }
      // The labels were written before translations finished loading.
      _backgroundTimer = Timer(
        const Duration(seconds: 4),
        () => unawaited(applyBackgroundSettings()),
      );
    }

    await scheduler.start();
    _syncWebhookServer();
    notifyListeners();
  }

  // ------------------------------------------------------------- background

  Future<void> stop() async {
    await _starting;
    _started = false;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    store.removeListener(_syncWebhookServer);
    scheduler.removeListener(_syncWebhookServer);
    _sync.removeListener(_onSyncStateChanged);
    _sync.settings.removeListener(_onSyncStateChanged);
    if (WorkflowBackground.isSupported) {
      WorkflowBackground.instance.removeShownListener(_onWindowShown);
    }
    await webhooks.stop();
    await scheduler.stopAndDrain();
    await Future.wait([store.flush(), log.flush()]);
    if (WorkflowBackground.isSupported) {
      _launchAtLoginBeforeStop = _launchAtLogin ||
          await WorkflowBackground.instance.isLaunchAtLoginEnabled();
      await WorkflowBackground.instance.configure(
        keepRunning: false,
        tooltip: 'AppFlowy',
        menu: const [],
      );
      if (!await WorkflowBackground.instance.setLaunchAtLogin(false)) {
        throw StateError('AppFlowy could not disable workflow startup.');
      }
    }
    _launchAtLogin = false;
  }

  Future<void> resumeAfterSignOutFailure() async {
    final restoreStartup = _launchAtLoginBeforeStop;
    await start();
    if (restoreStartup && store.settings.keepRunningInBackground) {
      if (!await setLaunchAtLogin(true)) {
        throw StateError('AppFlowy could not restore workflow startup.');
      }
    }
    _launchAtLoginBeforeStop = false;
  }

  Future<void> resetAccount() async {
    scheduler.resetAccount();
    await store.resetAccount();
    await log.resetAccount();
    _backgroundErrorKey = null;
    _launchAtLoginBeforeStop = false;
    _quitting = false;
    notifyListeners();
  }

  Future<void> reloadSyncedFiles() async {
    await store.reload();
    await log.reload();
    if (_started) await applyBackgroundSettings();
    notifyListeners();
  }

  Future<void> applyBackgroundSettings() async {
    if (!WorkflowBackground.isSupported) {
      return;
    }
    final settings = store.settings;
    final syncActive = _syncWantsBackground;
    final keepRunning = settings.keepRunningInBackground || syncActive;
    final enabled =
        store.workflows.where((workflow) => workflow.enabled).length;
    final syncPaused = _sync.isAllPaused;

    final String tooltip;
    if (syncActive && !settings.keepRunningInBackground) {
      tooltip = syncPaused
          ? _label(
              LocaleKeys.sync_trayTooltipPaused,
              'AppFlowy — sync paused',
            )
          : _label(
              LocaleKeys.sync_trayTooltipActive,
              'AppFlowy — syncing in background',
            );
    } else {
      tooltip = settings.pausedAll
          ? _label(
              LocaleKeys.workflows_tray_tooltipPaused,
              'AppFlowy — workflows paused',
            )
          : _label(
              LocaleKeys.workflows_tray_tooltip,
              'AppFlowy — {} workflows on',
              args: ['$enabled'],
            );
    }

    final configured = await WorkflowBackground.instance.configure(
      keepRunning: keepRunning,
      tooltip: tooltip,
      menu: [
        WorkflowTrayItem(
          id: WorkflowBackground.openAction,
          label: _label(LocaleKeys.workflows_tray_open, 'Open AppFlowy'),
        ),
        if (syncActive) ...[
          const WorkflowTrayItem.separator(),
          WorkflowTrayItem(
            id: 'syncNow',
            label: _label(LocaleKeys.sync_syncNow, 'Sync now'),
          ),
          WorkflowTrayItem(
            id: 'toggleSyncPause',
            label: syncPaused
                ? _label(LocaleKeys.sync_resume, 'Resume sync')
                : _label(LocaleKeys.sync_pause, 'Pause sync'),
          ),
        ],
        if (settings.keepRunningInBackground || !syncActive) ...[
          const WorkflowTrayItem.separator(),
          WorkflowTrayItem(
            id: 'togglePause',
            label: settings.pausedAll
                ? _label(LocaleKeys.workflows_tray_resume, 'Resume workflows')
                : _label(LocaleKeys.workflows_tray_pause, 'Pause workflows'),
          ),
        ],
        const WorkflowTrayItem.separator(),
        WorkflowTrayItem(
          id: WorkflowBackground.quitAction,
          label: _label(LocaleKeys.workflows_tray_quit, 'Quit AppFlowy'),
        ),
      ],
    );
    final previousError = _backgroundErrorKey;
    if (settings.keepRunningInBackground) {
      if (configured) {
        _backgroundErrorKey = null;
      } else {
        _backgroundErrorKey =
            LocaleKeys.workflows_background_configurationFailed;
        await store.updateSettings(
          store.settings.copyWith(keepRunningInBackground: false),
        );
        await WorkflowBackground.instance.showWindow();
      }
    } else if (syncActive && !configured) {
      // Desktop without a tray host: fall back gracefully to window-only sync.
      await WorkflowBackground.instance.showWindow();
    } else if (configured) {
      _backgroundErrorKey = null;
    }
    if (_backgroundErrorKey != previousError) notifyListeners();
  }

  /// A translation, or [fallback] while translations are not loaded yet.
  static String _label(String key, String fallback, {List<String>? args}) {
    String filled(String text) {
      var result = text;
      for (final arg in args ?? const <String>[]) {
        result = result.replaceFirst('{}', arg);
      }
      return result;
    }

    try {
      final value = key.tr(args: args);
      return value.isEmpty || value == key ? filled(fallback) : value;
    } on Object {
      return filled(fallback);
    }
  }

  void _onTrayAction(String action) {
    switch (action) {
      case 'syncNow':
        unawaited(_sync.syncNow());
      case 'toggleSyncPause':
        unawaited(_sync.setPaused(!_sync.isAllPaused));
      case 'togglePause':
        unawaited(
          updateSettings(
            store.settings.copyWith(pausedAll: !store.settings.pausedAll),
          ),
        );
      case WorkflowBackground.quitAction:
        unawaited(quitApplication());
    }
  }

  void _onClosedToTray() {
    _sync.setBackgroundMode(true);
    unawaited(applyBackgroundSettings());
    if (store.settings.closedHintShown) {
      return;
    }
    unawaited(
      services.notify(
        title: _label(
          LocaleKeys.workflows_tray_stillRunningTitle,
          'AppFlowy is still running',
        ),
        body: _syncWantsBackground
            ? _label(
                LocaleKeys.sync_trayStillRunningBody,
                'AppFlowy keeps syncing in the background. Use the AppFlowy '
                'icon in the notification area to open, pause, or quit.',
              )
            : _label(
                LocaleKeys.workflows_tray_stillRunningBody,
                'Workflows keep running in the background. Use the AppFlowy icon '
                'in the notification area to open or quit.',
              ),
      ),
    );
    unawaited(
      updateSettings(store.settings.copyWith(closedHintShown: true)),
    );
  }

  /// Writes everything down and ends the process.
  Future<void> quitApplication() async {
    if (_quitting) {
      return;
    }
    _quitting = true;
    await prepareToQuit();
    await WorkflowBackground.instance.quit();
  }

  Future<void> prepareToQuit() async {
    scheduler.stop();
    try {
      await Future.wait([
        webhooks.stop(),
        store.flush(),
        log.flush(),
        if (_sync.isBoundHere && !_sync.isAllPaused) _sync.syncNow(),
      ]).timeout(const Duration(seconds: 3));
    } on Object catch (error) {
      Log.warn('Workflows were not fully written before quitting: $error');
    }
  }

  Future<void> updateSettings(WorkflowSettings settings) async {
    final before = store.settings;
    await store.updateSettings(settings);
    if (before.keepRunningInBackground != settings.keepRunningInBackground ||
        before.pausedAll != settings.pausedAll) {
      await applyBackgroundSettings();
    }
    if (!store.settings.keepRunningInBackground &&
        !_syncWantsBackground &&
        _launchAtLogin) {
      await setLaunchAtLogin(false);
    }
    if (before.pausedAll && !settings.pausedAll) {
      unawaited(scheduler.tick());
    }
    notifyListeners();
  }

  Future<bool> setLaunchAtLogin(bool enabled) async {
    final done = await WorkflowBackground.instance.setLaunchAtLogin(enabled);
    _launchAtLogin = await WorkflowBackground.instance.isLaunchAtLoginEnabled();
    if (!done) {
      _backgroundErrorKey = LocaleKeys.workflows_background_launchAtLoginFailed;
    } else if (_backgroundErrorKey ==
        LocaleKeys.workflows_background_launchAtLoginFailed) {
      _backgroundErrorKey = null;
    }
    notifyListeners();
    return done;
  }

  void _onRunFinished(Workflow workflow, WorkflowRun run) {
    if (run.status != WorkflowRunStatus.failed ||
        run.cause.isInteractive ||
        !store.settings.notifyOnFailure) {
      return;
    }
    unawaited(
      services.notify(
        title: _label(
          LocaleKeys.workflows_notifications_failedTitle,
          '"{}" failed',
          args: [workflow.name],
        ),
        body: run.message,
      ),
    );
  }

  void _syncWebhookServer() {
    if (_quitting) {
      return;
    }
    final needed = scheduler.hasSampleListeners ||
        store.workflows.any(
          (workflow) =>
              workflow.enabled &&
              workflow.trigger.kind == WorkflowTriggerKind.webhook,
        );
    if (needed && !webhooks.isRunning) {
      unawaited(webhooks.start().then((_) => notifyListeners()));
    } else if (!needed && webhooks.isRunning) {
      unawaited(webhooks.stop().then((_) => notifyListeners()));
    }
  }

  // --------------------------------------------------------------- editing

  Future<Workflow> create(Workflow draft) async {
    final workspace = scheduler.workspaceId.isNotEmpty
        ? scheduler.workspaceId
        : await services.currentWorkspaceId();
    final now = DateTime.now();
    final workflow = draft.copyWith(
      workspaceId: workspace,
      updatedAt: now,
      enabled: false,
      clearEnabledAt: true,
    );
    await store.save(workflow);
    notifyListeners();
    return workflow;
  }

  Future<void> save(Workflow workflow) async {
    await store.save(workflow.copyWith(updatedAt: DateTime.now()));
    if (workflow.enabled) {
      unawaited(applyBackgroundSettings());
    }
    notifyListeners();
  }

  Future<void> setEnabled(Workflow workflow, bool enabled) async {
    final latest = store.byId(workflow.id) ?? workflow;
    if (enabled) {
      // What happened while it was off is not its business: schedules count
      // from now, and feeds and tables take a fresh look first.
      store.resetTriggerState(workflow.id);
      await store.save(
        latest.copyWith(
          enabled: true,
          enabledAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      unawaited(scheduler.tick());
    } else {
      await log.cancelParked(
        workflow.id,
        message: 'The workflow was turned off.',
      );
      await store.save(
        latest.copyWith(enabled: false, updatedAt: DateTime.now()),
      );
    }
    unawaited(applyBackgroundSettings());
    notifyListeners();
  }

  Future<void> delete(Workflow workflow) async {
    scheduler.cancelWebhookSample(workflow.id);
    await log.cancelParked(workflow.id);
    await store.delete(workflow.id);
    log.clearFor(workflow.id);
    unawaited(applyBackgroundSettings());
    notifyListeners();
  }

  Future<Workflow> duplicate(Workflow workflow, {required String name}) async {
    final trigger = workflow.trigger.kind == WorkflowTriggerKind.webhook
        ? workflow.trigger.withValue('token', newWorkflowToken())
        : workflow.trigger;
    final copy = Workflow.create(
      name: name,
      description: workflow.description,
      trigger: trigger,
      steps: workflow.steps,
    ).copyWith(
      samples: workflow.samples,
      stepCounter: workflow.stepCounter,
    );
    return create(copy);
  }

  Future<WorkflowRun?> runNow(Workflow workflow) => scheduler.runNow(workflow);

  Future<WorkflowStepTest> testStep(Workflow workflow, WorkflowStep step) =>
      scheduler.runner.testStep(workflow, step);

  String webhookAddress(Workflow workflow) =>
      webhooks.addressFor(workflow.id, workflow.trigger.token);

  /// Fetches something real for the trigger to hand its steps, so the data
  /// picker can offer actual fields. Webhooks wait for the next request.
  Future<Object?> sampleTrigger(Workflow workflow) async {
    final trigger = workflow.trigger;
    final now = DateTime.now();
    switch (trigger.kind) {
      case WorkflowTriggerKind.manual:
      case WorkflowTriggerKind.appStart:
        return manualTriggerPayload(now);
      case WorkflowTriggerKind.schedule:
        return scheduleTriggerPayload(now);
      case WorkflowTriggerKind.webhook:
        final listening = scheduler.waitForWebhookSample(workflow.id);
        _syncWebhookServer();
        await webhooks.start();
        notifyListeners();
        return listening;
      case WorkflowTriggerKind.feed:
        final feed = await services.fetchFeed(trigger.url);
        if (feed.items.isEmpty) {
          throw const WorkflowStepException('That feed has no items yet.');
        }
        return feedTriggerPayload(feed, feed.items.first);
      case WorkflowTriggerKind.databaseRow:
        final table = await services.readRows(trigger.viewId);
        if (table.rows.isEmpty) {
          throw const WorkflowStepException('That table has no rows yet.');
        }
        return rowTriggerPayload(table.rows.last, isNew: true);
      case WorkflowTriggerKind.newPage:
        final pages = await services.childPages(trigger.parentId);
        if (pages.isEmpty) {
          throw const WorkflowStepException(
            'Nothing has been added there yet.',
          );
        }
        final newest = pages.reduce(
          (a, b) => (a.createdAt ?? DateTime(0)).isAfter(
            b.createdAt ?? DateTime(0),
          )
              ? a
              : b,
        );
        return pageTriggerPayload(newest, trigger.parentId);
    }
  }

  void cancelTriggerSample(Workflow workflow) {
    scheduler.cancelWebhookSample(workflow.id);
    _syncWebhookServer();
  }

  @override
  void dispose() {
    store.removeListener(_syncWebhookServer);
    scheduler.removeListener(_syncWebhookServer);
    _sync.removeListener(_onSyncStateChanged);
    _sync.settings.removeListener(_onSyncStateChanged);
    if (WorkflowBackground.isSupported) {
      WorkflowBackground.instance.removeShownListener(_onWindowShown);
    }
    super.dispose();
  }
}
