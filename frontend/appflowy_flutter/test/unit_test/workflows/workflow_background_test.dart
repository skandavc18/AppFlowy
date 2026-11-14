import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workflows/application/workflow_background.dart';
import 'package:appflowy/workflows/application/workflow_manager.dart';
import 'package:appflowy/workflows/application/workflow_run_log.dart';
import 'package:appflowy/workflows/application/workflow_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workflow_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(WorkflowBackground.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late WorkflowManager manager;
  late MemoryWorkflowFiles files;
  var configureSucceeds = true;
  var loginSucceeds = true;
  var launchAtLogin = false;
  PlatformException? configureError;

  setUp(() async {
    calls.clear();
    configureSucceeds = true;
    loginSucceeds = true;
    launchAtLogin = false;
    configureError = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'configure':
          if (configureError case final error?) throw error;
          return configureSucceeds;
        case 'setLaunchAtLogin':
          if (loginSucceeds) {
            launchAtLogin =
                (call.arguments as Map<Object?, Object?>)['enabled']! as bool;
          }
          return loginSucceeds;
        case 'isLaunchAtLoginEnabled':
          return launchAtLogin;
      }
      return null;
    });
    files = MemoryWorkflowFiles();
    final store = WorkflowStore(files: files);
    final log = WorkflowRunLog(files: MemoryWorkflowFiles());
    await store.ensureLoaded();
    await log.ensureLoaded();
    manager = WorkflowManager(
      store: store,
      log: log,
      services: FakeWorkflowServices(),
    );
  });

  tearDown(() {
    manager.dispose();
    manager.scheduler.dispose();
    manager.store.dispose();
    manager.log.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    WorkflowBackground.recordLaunchArguments(const []);
  });

  test('background support includes Linux and Windows', () {
    expect(
      WorkflowBackground.isSupported,
      Platform.isLinux || Platform.isWindows,
    );
    WorkflowBackground.recordLaunchArguments(['--background']);
    expect(WorkflowBackground.startedInBackground, isTrue);
    WorkflowBackground.recordLaunchArguments([]);
    expect(WorkflowBackground.startedInBackground, isFalse);
  });

  test(
    'a failed logout restores the background startup choice',
    () async {
      await manager.start();
      await manager.updateSettings(
        manager.store.settings.copyWith(keepRunningInBackground: true),
      );
      await manager.setLaunchAtLogin(true);
      await manager.stop();
      expect(launchAtLogin, isFalse);
      await manager.resumeAfterSignOutFailure();
      expect(manager.isStarted, isTrue);
      expect(manager.store.settings.keepRunningInBackground, isTrue);
      expect(launchAtLogin, isTrue);
      await manager.stop();
    },
    skip: !WorkflowBackground.isSupported,
  );

  test(
    'logout stops background scheduling, disables autostart, and resets the account',
    () async {
      await manager.start();
      await manager.updateSettings(
        manager.store.settings.copyWith(keepRunningInBackground: true),
      );
      await manager.setLaunchAtLogin(true);
      await manager.stop();
      expect(manager.isStarted, isFalse);
      expect(manager.scheduler.isStarted, isFalse);
      expect(launchAtLogin, isFalse);
      expect(
        calls.where((call) => call.method == 'configure').last.arguments,
        containsPair('keepRunning', false),
      );
      files.data.clear();
      await manager.resetAccount();
      expect(manager.store.workflows, isEmpty);
      expect(manager.log.runs, isEmpty);
      expect(manager.store.settings.keepRunningInBackground, isFalse);
      await manager.start();
      expect(manager.isStarted, isTrue);
      await manager.stop();
    },
    skip: !WorkflowBackground.isSupported,
  );

  test(
    'disabling background mode also disables launch at sign-in',
    () async {
      await manager.updateSettings(
        manager.store.settings.copyWith(keepRunningInBackground: true),
      );
      expect(manager.store.settings.keepRunningInBackground, isTrue);
      expect(await manager.setLaunchAtLogin(true), isTrue);
      expect(manager.launchAtLogin, isTrue);
      await manager.updateSettings(
        manager.store.settings.copyWith(keepRunningInBackground: false),
      );
      expect(manager.launchAtLogin, isFalse);
      expect(launchAtLogin, isFalse);
      expect(manager.backgroundErrorKey, isNull);
      expect(
        calls.where((call) => call.method == 'configure').last.arguments,
        containsPair('keepRunning', false),
      );
    },
    skip: !WorkflowBackground.isSupported,
  );

  for (final platformError in [false, true]) {
    test(
      'a refused tray configuration is visible and rolled back ($platformError)',
      () async {
        configureSucceeds = false;
        if (platformError) {
          configureError = PlatformException(
            code: 'background-unavailable',
            message: 'A notification area is required.',
          );
        }
        await manager.updateSettings(
          manager.store.settings.copyWith(keepRunningInBackground: true),
        );
        expect(manager.store.settings.keepRunningInBackground, isFalse);
        expect(
          manager.backgroundErrorKey,
          LocaleKeys.workflows_background_configurationFailed,
        );
        expect(calls.map((call) => call.method), contains('showWindow'));
        await manager.store.flush();
        final restored = WorkflowStore(files: files);
        await restored.ensureLoaded();
        expect(restored.settings.keepRunningInBackground, isFalse);
        restored.dispose();

        configureSucceeds = true;
        configureError = null;
        await manager.updateSettings(
          manager.store.settings.copyWith(keepRunningInBackground: true),
        );
        expect(manager.store.settings.keepRunningInBackground, isTrue);
        expect(manager.backgroundErrorKey, isNull);
      },
      skip: !WorkflowBackground.isSupported,
    );
  }

  test(
    'an unwritable autostart entry reports failure without enabling it',
    () async {
      loginSucceeds = false;
      expect(await manager.setLaunchAtLogin(true), isFalse);
      expect(manager.launchAtLogin, isFalse);
      expect(
        manager.backgroundErrorKey,
        LocaleKeys.workflows_background_launchAtLoginFailed,
      );
      loginSucceeds = true;
      expect(await manager.setLaunchAtLogin(true), isTrue);
      expect(manager.backgroundErrorKey, isNull);
    },
    skip: !WorkflowBackground.isSupported,
  );

  test(
    'native tray, close, and show events reach their listeners',
    () async {
      final actions = <String>[];
      var closed = 0;
      var shown = 0;
      void onShown() => shown++;
      final background = WorkflowBackground.instance;
      background.attach(
        onTrayAction: actions.add,
        onClosedToTray: () => closed++,
      );
      background.addShownListener(onShown);
      try {
        for (final call in [
          const MethodCall('onTrayAction', 'togglePause'),
          const MethodCall('onClosedToTray'),
          const MethodCall('onWindowShown'),
        ]) {
          await messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(call),
            (_) {},
          );
        }
        expect(actions, ['togglePause']);
        expect(closed, 1);
        expect(shown, 1);
      } finally {
        background.removeShownListener(onShown);
      }
    },
    skip: !WorkflowBackground.isSupported,
  );
}
