import 'dart:async';
import 'dart:io';

import 'package:appflowy/workflows/application/workflow_background.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run.dart';
import 'package:appflowy/workflows/application/workflow_run_log.dart';
import 'package:appflowy/workflows/application/workflow_schedule.dart';
import 'package:appflowy/workflows/application/workflow_scheduler.dart';
import 'package:appflowy/workflows/application/workflow_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import '../../test/unit_test/workflows/workflow_test_support.dart';

/// Opt in with an isolated XDG_CONFIG_HOME and a StatusNotifier desktop.
void main([List<String> arguments = const []]) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('WORKFLOW_BACKGROUND_NATIVE_TEST');
  const configRoot = String.fromEnvironment('WORKFLOW_BACKGROUND_TEST_CONFIG');
  if (!enabled || !Platform.isLinux) {
    test('requires an opt-in Linux desktop', () {}, skip: true);
    return;
  }
  if (configRoot.isEmpty ||
      Platform.environment['XDG_CONFIG_HOME'] != configRoot) {
    throw StateError('Set an isolated WORKFLOW_BACKGROUND_TEST_CONFIG and '
        'matching XDG_CONFIG_HOME before testing autostart.');
  }
  unawaited(
    binding.allTestsPassed.future.then(
      (passed) async {
        debugPrint('WORKFLOW_BACKGROUND_NATIVE_RESULT: $passed');
        await SystemNavigator.pop();
      },
    ),
  );

  testWidgets('scheduled work continues after the native Linux window closes',
      (tester) async {
    await windowManager.ensureInitialized();
    if (arguments.contains('--background')) {
      expect(await windowManager.isVisible(), isFalse);
    }
    final background = WorkflowBackground.instance;
    var closed = 0;
    var shown = 0;
    void onShown() => shown++;
    background.attach(
      onTrayAction: (_) {},
      onClosedToTray: () => closed++,
    );
    background.addShownListener(onShown);
    final store = WorkflowStore(files: MemoryWorkflowFiles());
    final log = WorkflowRunLog(files: MemoryWorkflowFiles());
    final services = FakeWorkflowServices();
    var now = DateTime(2026, 3, 2, 9);
    final scheduler = WorkflowScheduler(
      store: store,
      log: log,
      services: services,
      clock: () => now,
      tickInterval: const Duration(milliseconds: 50),
    );
    try {
      expect(
        await background.configure(
          keepRunning: true,
          tooltip: 'AppFlowy workflow test',
          menu: const [
            WorkflowTrayItem(id: 'open', label: 'Open AppFlowy'),
            WorkflowTrayItem(id: 'togglePause', label: 'Pause workflows'),
            WorkflowTrayItem(id: 'quit', label: 'Quit AppFlowy'),
          ],
        ),
        isTrue,
      );
      if (arguments.contains('--background')) {
        expect(await windowManager.isVisible(), isFalse);
      }
      await background.showWindow();
      await _eventually(windowManager.isVisible);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Background workflow test')),
        ),
      );
      await _eventually(() async => shown == 1);
      await store.ensureLoaded();
      await log.ensureLoaded();
      await store.save(
        readyWorkflow(
          trigger:
              WorkflowTrigger.create(WorkflowTriggerKind.schedule).withSchedule(
            const WorkflowSchedule(mode: WorkflowScheduleMode.interval),
          ),
          steps: [
            step(1, WorkflowStepKind.notify, {'title': 'Hidden schedule'}),
          ],
          enabledAt: now,
        ),
      );
      await scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(services.notifications, isEmpty);

      await windowManager.close();
      await _eventually(() async => !await windowManager.isVisible());
      expect(closed, 1);
      now = now.add(const Duration(hours: 1));
      await _eventually(() async => services.notifications.isNotEmpty);
      expect(services.notifications.single.$1, 'Hidden schedule');
      expect(log.runs.single.cause, WorkflowRunCause.schedule);
      expect(await windowManager.isVisible(), isFalse);

      await background.showWindow();
      await _eventually(
        () async => await windowManager.isVisible() && shown == 2,
      );

      expect(await background.isLaunchAtLoginEnabled(), isFalse);
      expect(await background.setLaunchAtLogin(true), isTrue);
      expect(await background.isLaunchAtLoginEnabled(), isTrue);
      final entry = File(
        '$configRoot/autostart/io.appflowy.appflowy-background.desktop',
      );
      final desktopFile = await entry.readAsString();
      expect(desktopFile, contains('Type=Application'));
      expect(desktopFile, contains('--background'));
      expect(desktopFile, contains('Exec="'));
      expect(await background.setLaunchAtLogin(false), isTrue);
      expect(await entry.exists(), isFalse);
      expect(await background.isLaunchAtLoginEnabled(), isFalse);

      await background.hideWindow();
      await _eventually(() async => !await windowManager.isVisible());
      expect(
        await background.configure(
          keepRunning: false,
          tooltip: 'AppFlowy',
          menu: const [],
        ),
        isTrue,
      );
      await _eventually(
        () async => await windowManager.isVisible() && shown == 3,
      );
    } finally {
      scheduler.dispose();
      store.dispose();
      log.dispose();
      background.removeShownListener(onShown);
      await background.configure(
        keepRunning: false,
        tooltip: 'AppFlowy',
        menu: const [],
      );
    }
  });
}

Future<void> _eventually(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Native background operation did not complete within five seconds.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
