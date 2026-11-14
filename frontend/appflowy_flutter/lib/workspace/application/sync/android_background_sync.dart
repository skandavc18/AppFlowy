import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/rust_sdk.dart';
import 'package:appflowy/user/application/auth/device_id.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/sync/app_synced_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/sync/sync_settings.dart';
import 'package:appflowy_backend/appflowy_backend.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Coordinates Android's `JobScheduler` periodic background sync (`SyncJobService`)
/// with the Dart `WorkspaceSyncEngine`.
class AndroidBackgroundSync {
  AndroidBackgroundSync._();

  static final AndroidBackgroundSync instance = AndroidBackgroundSync._();

  static const String channelName = 'appflowy/background_sync';
  static const MethodChannel _channel = MethodChannel(channelName);

  bool _attached = false;
  bool? _lastScheduledState;

  static bool get isSupported =>
      !kIsWeb &&
      Platform.isAndroid &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> attach() async {
    if (!isSupported || _attached) {
      return;
    }
    _attached = true;
    _channel.setMethodCallHandler(_onCall);
    final settings = SyncSettings.instance;
    await settings.ensureLoaded();
    settings.addListener(_syncSchedule);
    await _syncSchedule();
  }

  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    SyncSettings.instance.removeListener(_syncSchedule);
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'triggerSyncNow':
        final engine = WorkspaceSyncEngine.instance;
        if (engine.isBoundHere && !engine.isAllPaused) {
          await engine.syncNow();
        }
        return true;
    }
    return null;
  }

  Future<void> _syncSchedule() async {
    if (!isSupported) {
      return;
    }
    final settings = SyncSettings.instance;
    final wantScheduled = settings.keepRunningInBackground &&
        settings.bindings.any((b) => !b.paused);
    if (_lastScheduledState == wantScheduled) {
      return;
    }
    _lastScheduledState = wantScheduled;
    try {
      await _channel.invokeMethod<bool>('setPeriodicSyncEnabled', {
        'enabled': wantScheduled,
      });
    } on MissingPluginException {
      // Ignored outside the Android host.
    } on PlatformException catch (error) {
      Log.warn('Android periodic sync schedule failed: ${error.message}');
    }
  }
}

/// Runs a single headless background sync round on Android when `SyncJobService`
/// wakes the app while no UI `MainActivity` is open.
Future<void> runAndroidHeadlessSyncRound() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidBackgroundSync.channelName);

  var succeeded = true;
  FlowySDK? sdk;
  try {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      getIt.registerFactory<KeyValueStorage>(() => DartKeyValue());
    }
    if (!getIt.isRegistered<ApplicationDataStorage>()) {
      getIt.registerFactory<ApplicationDataStorage>(
        () => ApplicationDataStorage(),
      );
    }

    final settings = SyncSettings.instance;
    await settings.ensureLoaded();
    final activeBindings = [
      for (final b in settings.bindings)
        if (!b.paused) b,
    ];
    if (!settings.keepRunningInBackground || activeBindings.isEmpty) {
      return;
    }

    if (!getIt.isRegistered<AppFlowyCloudSharedEnv>()) {
      final env = await AppFlowyCloudSharedEnv.fromEnv();
      getIt.registerFactory<AppFlowyCloudSharedEnv>(() => env);
    }

    final supportRoot = await getApplicationSupportDirectory();
    final defaultAppDir = await appFlowyApplicationDataDirectory();
    final customDataPath = await getIt<ApplicationDataStorage>().getPath();
    final deviceId = await getDeviceId();
    String version = '0.11.4';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } on Object {
      // Fallback version string is sufficient for DB access.
    }

    final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
    final config = AppFlowyConfiguration(
      root: supportRoot.path,
      app_version: version,
      custom_app_path: customDataPath,
      origin_app_path: defaultAppDir.path,
      device_id: deviceId,
      platform: Platform.operatingSystem,
      authenticator_type: cloudEnv.authenticatorType.value,
      appflowy_cloud_config: cloudEnv.appflowyCloudConfig,
      envs: const {},
    );

    sdk = getIt.isRegistered<FlowySDK>() ? getIt<FlowySDK>() : FlowySDK();
    if (!getIt.isRegistered<FlowySDK>()) {
      getIt.registerSingleton<FlowySDK>(sdk);
    }
    await sdk.init(jsonEncode(config.toJson()));

    final engine = WorkspaceSyncEngine.instance;
    engine.configure(
      dataPath: () async => customDataPath,
      preferences: AppSyncedPreferences(
        dataPath: () async => customDataPath,
        workspaceId: () => engine.binding?.workspaceId,
      ),
    );

    // Group active bindings by (workspaceId, uid) and run one full sync round
    // for each bound local workspace.
    final workspaces = <(String, int), String>{};
    for (final b in activeBindings) {
      workspaces[(b.workspaceId, b.uid)] = b.workspaceName;
    }
    for (final entry in workspaces.entries) {
      final (workspaceId, uid) = entry.key;
      await engine.attach(
        workspaceId: workspaceId,
        uid: uid,
        workspaceName: entry.value,
        isLocalWorkspace: true,
      );
      await engine.syncNow();
      engine.detach();
    }
  } on Object catch (error, stackTrace) {
    succeeded = false;
    Log.warn('Headless Android background sync failed: $error\n$stackTrace');
  } finally {
    WorkspaceSyncEngine.instance.detach();
    try {
      await sdk?.dispose();
    } on Object {
      // Disposed when engine tears down.
    }
    try {
      await channel.invokeMethod<void>('headlessDone', {
        'succeeded': succeeded,
      });
    } on Object {
      // JobService has its own timeout guard if messenger already closed.
    }
  }
}
