import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
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
  })  : store = store ?? WorkflowStore.instance,
        log = log ?? WorkflowRunLog.instance,
        services = services ?? AppWorkflowServices() {
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
  late final WorkflowScheduler scheduler;
  late final WorkflowWebhookServer webhooks;

  bool _started = false;
  bool _launchAtLogin = false;
  bool _quitting = false;

  bool get isStarted => _started;

  /// Whether Windows starts AppFlowy, hidden, when somebody signs in.
  bool get launchAtLogin => _launchAtLogin;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      await store.ensureLoaded();
      await log.ensureLoaded();
    } on Object catch (error) {
      Log.warn('Workflows could not be read at startup: $error');
    }
    scheduler.onRunFinished = _onRunFinished;
    store.addListener(_syncWebhookServer);
    scheduler.addListener(_syncWebhookServer);

    if (WorkflowBackground.isSupported) {
      WorkflowBackground.instance.attach(
        onTrayAction: _onTrayAction,
        onClosedToTray: _onClosedToTray,
      );
      await applyBackgroundSettings();
      _launchAtLogin =
          await WorkflowBackground.instance.isLaunchAtLoginEnabled();
      // Started hidden at sign-in, but nobody asked to keep running: a hidden
      // process with no icon could never be found again.
      if (WorkflowBackground.startedInBackground &&
          !store.settings.keepRunningInBackground) {
        await WorkflowBackground.instance.showWindow();
      }
      // The labels were written before translations finished loading.
      Timer(
        const Duration(seconds: 4),
        () => unawaited(applyBackgroundSettings()),
      );
    }

    await scheduler.start();
    _syncWebhookServer();
    notifyListeners();
  }

  // ------------------------------------------------------------- background

  Future<void> applyBackgroundSettings() async {
    if (!WorkflowBackground.isSupported) {
      return;
    }
    final settings = store.settings;
    final enabled =
        store.workflows.where((workflow) => workflow.enabled).length;
    await WorkflowBackground.instance.configure(
      keepRunning: settings.keepRunningInBackground,
      tooltip: settings.pausedAll
          ? _label(
              LocaleKeys.workflows_tray_tooltipPaused,
              'AppFlowy — workflows paused',
            )
          : _label(
              LocaleKeys.workflows_tray_tooltip,
              'AppFlowy — {} workflows on',
              args: ['$enabled'],
            ),
      menu: [
        WorkflowTrayItem(
          id: WorkflowBackground.openAction,
          label: _label(LocaleKeys.workflows_tray_open, 'Open AppFlowy'),
        ),
        const WorkflowTrayItem.separator(),
        WorkflowTrayItem(
          id: 'togglePause',
          label: settings.pausedAll
              ? _label(LocaleKeys.workflows_tray_resume, 'Resume workflows')
              : _label(LocaleKeys.workflows_tray_pause, 'Pause workflows'),
        ),
        const WorkflowTrayItem.separator(),
        WorkflowTrayItem(
          id: WorkflowBackground.quitAction,
          label: _label(LocaleKeys.workflows_tray_quit, 'Quit AppFlowy'),
        ),
      ],
    );
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
        body: _label(
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
    if (!settings.keepRunningInBackground && _launchAtLogin) {
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
    super.dispose();
  }
}
