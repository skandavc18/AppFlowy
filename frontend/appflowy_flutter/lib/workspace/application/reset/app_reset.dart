import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/extensions/application/extension_manager.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/shared/platform_secret_store.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/rust_sdk.dart';
import 'package:appflowy/workflows/application/workflow_manager.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup_settings.dart';
import 'package:appflowy/workspace/application/collections/email/connected_accounts.dart';
import 'package:appflowy/workspace/application/collections/email/mail_secret_store.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/sync/self_hosted_cloud.dart';
import 'package:appflowy/workspace/application/sync/server_settings_sync.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Marker file read by `init_sdk` in `dart-ffi` right after the previous
/// `AppFlowyCore` drops all database handles and before the next instance opens
/// them, ensuring locked SQLite / RocksDB files on Windows and Linux are wiped
/// cleanly.
const String pendingAppResetFile = 'pending_app_reset.json';

class AppResetError implements Exception {
  const AppResetError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Resets this AppFlowy installation to a completely fresh first-run state.
class AppFreshResetService {
  AppFreshResetService({
    AppPassword? passwords,
    WorkspaceSyncEngine? syncEngine,
    ServerSettingsSync? serverSync,
    BackupSettings? backupSettings,
    EncryptionVault? encryptionVault,
    ProviderConnections? providerConnections,
    SelfHostedCloudAccounts? selfHostedCloudAccounts,
    KeyValueStorage? storage,
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? defaultDataDirectory,
    Future<String> Function()? currentDataPath,
    Future<void> Function()? stopAutomation,
    Future<void> Function()? resetAutomation,
    Future<void> Function()? backendSignOut,
    Future<void> Function()? clearKeyringProfile,
    Future<void> Function()? restart,
  })  : _passwords = passwords ?? AppPassword.instance,
        _syncEngine = syncEngine ?? WorkspaceSyncEngine.instance,
        _serverSync = serverSync ?? ServerSettingsSync.instance,
        _backupSettings = backupSettings ?? BackupSettings.instance,
        _encryptionVault = encryptionVault ?? EncryptionVault.instance,
        _providerConnections =
            providerConnections ?? ProviderConnections.instance,
        _selfHostedCloudAccounts =
            selfHostedCloudAccounts ?? SelfHostedCloudAccounts.instance,
        _storageOverride = storage,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _defaultDataDirectory =
            defaultDataDirectory ?? appFlowyApplicationDataDirectory,
        _currentDataPath = currentDataPath ??
            (() async => getIt.isRegistered<ApplicationDataStorage>()
                ? await getIt<ApplicationDataStorage>().getPath()
                : (await appFlowyApplicationDataDirectory()).path),
        _stopAutomation = stopAutomation ?? _defaultStopAutomation,
        _resetAutomation = resetAutomation ?? _defaultResetAutomation,
        _backendSignOut = backendSignOut ?? _defaultBackendSignOut,
        _clearKeyringProfile =
            clearKeyringProfile ?? _defaultClearKeyringProfile,
        _restart = restart ?? _defaultRestart;

  static final AppFreshResetService instance = AppFreshResetService();

  final AppPassword _passwords;
  final WorkspaceSyncEngine _syncEngine;
  final ServerSettingsSync _serverSync;
  final BackupSettings _backupSettings;
  final EncryptionVault _encryptionVault;
  final ProviderConnections _providerConnections;
  final SelfHostedCloudAccounts _selfHostedCloudAccounts;
  final KeyValueStorage? _storageOverride;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _defaultDataDirectory;
  final Future<String> Function() _currentDataPath;
  final Future<void> Function() _stopAutomation;
  final Future<void> Function() _resetAutomation;
  final Future<void> Function() _backendSignOut;
  final Future<void> Function() _clearKeyringProfile;
  final Future<void> Function() _restart;

  KeyValueStorage? get _kv =>
      _storageOverride ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  /// Whether an AppFlowy password is set on this computer and therefore must be
  /// verified before resetting.
  Future<bool> requiresPassword() async {
    await _passwords.ensureLoaded();
    return _passwords.isSet;
  }

  /// Verifies [password] when an AppFlowy password is set, optionally clears
  /// the bound cloud sync folder when [clearCloudSync] is true, wipes all local
  /// workspaces, settings, credentials and keys, and restarts to first-time
  /// setup.
  Future<void> resetEverything({
    String? password,
    bool clearCloudSync = false,
  }) async {
    await _passwords.ensureLoaded();
    if (_passwords.isSet) {
      if (password == null ||
          password.isEmpty ||
          !await _passwords.check(password)) {
        throw const AppResetError('wrong_password');
      }
    }

    // 1. Stop background tasks so nothing writes back while resetting.
    await _stopAutomation();

    // 2. Clear remote cloud sync data first when requested; if that fails,
    //    abort before touching local data so nothing is left half-done.
    await _syncEngine.resetForFreshStart(clearRemote: clearCloudSync);
    await _serverSync.resetForFreshStart();

    // 3. Collect the data directories to wipe before clearing preferences.
    final pathsToWipe = <String>{};
    try {
      final currentPath = await _currentDataPath();
      if (_isSafeDirectory(currentPath)) {
        pathsToWipe.add(currentPath);
      }
    } on Object catch (error) {
      Log.warn('Current data path could not be read during reset: $error');
    }
    try {
      final defaultPath = (await _defaultDataDirectory()).path;
      if (_isSafeDirectory(defaultPath)) {
        pathsToWipe.add(defaultPath);
      }
    } on Object catch (error) {
      Log.warn('Default data path could not be read during reset: $error');
    }

    // 4. Sign out the active backend session best-effort and schedule full
    //    directory removal for `init_sdk` once database handles close.
    await _backendSignOut();
    try {
      final support = await _supportDirectory();
      await support.create(recursive: true);
      final marker = File(p.join(support.path, pendingAppResetFile));
      await marker.writeAsString(
        jsonEncode({'paths': pathsToWipe.toList(growable: false)}),
      );
    } on Object catch (error) {
      Log.warn('Pending reset marker could not be written: $error');
    }

    // 5. Wipe all secrets, caches, encryption/backup/sync state and KV storage.
    try {
      final mailAccounts = await const ConnectedAccountRegistry().all();
      final mailSecrets = MailSecretStore(storage: _storageOverride);
      for (final account in mailAccounts) {
        await mailSecrets.forget(account.id);
      }
    } on Object catch (error) {
      Log.info('Mail secrets could not be cleared during reset: $error');
    }

    await _providerConnections.clearAll();
    await _selfHostedCloudAccounts.forgetAll();
    OAuthAppRegistry.instance.invalidate();
    await _backupSettings.resetForFreshStart();
    await _encryptionVault.resetForFreshStart();
    await _passwords.clear();
    await _clearKeyringProfile();
    await _resetAutomation();

    try {
      await ProviderCache.instance.clearAll();
    } on Object {
      // Swept with the data directory below.
    }

    // Best-effort immediate removal for unlocked files; anything still held by
    // the native SDK is removed when `init_sdk` reads `pending_app_reset.json`.
    for (final targetPath in pathsToWipe) {
      await _deleteUnlockedContents(Directory(targetPath));
    }

    final storage = _kv;
    if (storage != null) {
      await storage.clear();
      // Point at the default first-run entry so AppFlowy opens on the unified
      // first-time setup choices.
      if (_storageOverride == null) {
        await useAppFlowyBetaCloudWithURL(
          kAppflowyCloudUrl,
          AuthenticatorType.appflowyCloud,
        );
      }
    }

    await _restart();
  }

  static bool _isSafeDirectory(String rawPath) {
    if (rawPath.isEmpty) {
      return false;
    }
    final abs = p.normalize(p.absolute(rawPath));
    return p.dirname(abs) != abs;
  }

  static Future<void> _deleteUnlockedContents(Directory directory) async {
    try {
      if (!directory.existsSync()) {
        return;
      }
      for (final entity in directory.listSync(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } on Object {
          // Held by an open DB handle; `pending_app_reset.json` removes it on
          // restart once handles drop.
        }
      }
    } on Object {
      // Handled by `pending_app_reset.json` on restart.
    }
  }

  static Future<void> _defaultStopAutomation() async {
    try {
      await Future.wait([
        WorkflowManager.instance.stop(),
        ExtensionManager.instance.stop(),
      ]);
    } on Object catch (error) {
      Log.info('Automation stop during reset reported: $error');
    }
  }

  static Future<void> _defaultResetAutomation() async {
    try {
      await Future.wait([
        WorkflowManager.instance.resetAccount(),
        ExtensionManager.instance.resetAccount(),
      ]);
    } on Object catch (error) {
      Log.info('Automation reset reported: $error');
    }
  }

  static Future<void> _defaultBackendSignOut() async {
    try {
      await UserEventSignOut().send();
    } on Object {
      // Local anonymous or uninitialized state; safe to ignore.
    }
  }

  static Future<void> _defaultClearKeyringProfile() async {
    if (LinuxKeyring.instance.isAvailable) {
      try {
        await LinuxKeyring.instance.clearProfile();
      } on Object catch (error) {
        Log.info('Keyring profile could not be cleared: $error');
      }
    }
    await PlatformChannelKeyring.instance.clearProfile();
  }

  static Future<void> _defaultRestart() async {
    if (!FlowyRunner.currentMode.isUnitTest) {
      await runAppFlowy();
    }
  }
}

@visibleForTesting
bool isSafeResetDirectory(String path) =>
    AppFreshResetService._isSafeDirectory(path);
