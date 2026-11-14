import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/backup/backup_settings.dart';
import 'package:appflowy/workspace/application/encryption/encryption_policy.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/reset/app_reset.dart';
import 'package:appflowy/workspace/application/sync/self_hosted_cloud.dart';
import 'package:appflowy/workspace/application/sync/server_settings_sync.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:appflowy/workspace/application/sync/sync_settings.dart';
import 'package:appflowy/workspace/application/sync/sync_vault.dart';
import 'package:appflowy/workspace/application/sync/workspace_bundle_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory supportDir;
  late Directory dataDir;
  late Directory remoteSyncDir;
  late _MemoryKeyValue storage;
  late _MemoryKeyring keyring;

  setUp(() {
    root = Directory.systemTemp.createTempSync('appflowy_reset_test_');
    supportDir = Directory(p.join(root.path, 'support'))
      ..createSync(recursive: true);
    dataDir = Directory(p.join(root.path, 'data'))..createSync(recursive: true);
    remoteSyncDir = Directory(p.join(root.path, 'remote_sync'))
      ..createSync(recursive: true);
    storage = _MemoryKeyValue();
    keyring = _MemoryKeyring();
    EncryptionVault.instance.resetForTest();
    BackupSettings.instance.seedForTest(const BackupPolicy());
  });

  tearDown(() {
    EncryptionVault.instance.resetForTest();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  AppFreshResetService makeService({
    required AppPassword passwords,
    required WorkspaceSyncEngine syncEngine,
    required ServerSettingsSync serverSync,
    required ProviderConnections connections,
    required void Function() onRestarted,
    SelfHostedCloudAccounts? selfHostedCloudAccounts,
  }) =>
      AppFreshResetService(
        passwords: passwords,
        syncEngine: syncEngine,
        serverSync: serverSync,
        backupSettings: BackupSettings.instance,
        encryptionVault: EncryptionVault.instance,
        providerConnections: connections,
        selfHostedCloudAccounts: selfHostedCloudAccounts,
        storage: storage,
        supportDirectory: () async => supportDir,
        defaultDataDirectory: () async => dataDir,
        currentDataPath: () async => dataDir.path,
        stopAutomation: () async {},
        resetAutomation: () async {},
        backendSignOut: () async {},
        clearKeyringProfile: () async => keyring.items.clear(),
        restart: () async => onRestarted(),
      );

  test(
      'without an AppFlowy password set, resets without asking and keeps remote sync intact by default',
      () async {
    final secrets = ProviderSecretStore(storage: storage, keyring: keyring);
    final passwords = AppPassword(
      storage: storage,
      secrets: secrets,
      iterations: 200,
    );
    final connections = ProviderConnections(storage: storage, secrets: secrets);
    await connections.upsert(
      ProviderConnection(
        id: 'google|me',
        service: ProviderService.googleDrive,
        accountLabel: 'me@example.com',
        accountId: 'me',
        connectedAt: DateTime.utc(2026, 11, 12),
      ),
      const ProviderCredentials(accessToken: 'tok', refreshToken: 'ref'),
    );
    final selfHosted = SelfHostedCloudAccounts(
      storage: storage,
      secrets: secrets,
    );
    final selfHostedAccount = await selfHosted.remember(
      server: 'https://appflowy.example.com',
      email: 'me@example.com',
      tokens: SelfHostedCloudTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2030),
      ),
    );

    final syncSettings =
        SyncSettings(storage: storage, home: () async => supportDir);
    final syncEngine = WorkspaceSyncEngine(
      bridge: _MinimalBridge(),
      settings: syncSettings,
      dataPath: () async => dataDir.path,
      scratch: () async => Directory(p.join(root.path, 'scratch')),
      keys: MemoryKeyKeeper(),
      passwords: passwords,
      vaultIterations: 200,
    );
    await syncEngine.attach(
      workspaceId: 'ws-1',
      uid: 1,
      workspaceName: 'My Workspace',
      isLocalWorkspace: true,
    );
    await syncEngine.startUnsealed(
      BackupDestination(
        kind: BackupDestinationKind.folder,
        localPath: remoteSyncDir.path,
      ),
    );
    expect(remoteSyncDir.listSync(), isNotEmpty);

    File(p.join(dataDir.path, 'collab.db')).writeAsStringSync('local-data');
    await storage.set('user_pref', 'value');

    var restarted = false;
    final reset = makeService(
      passwords: passwords,
      syncEngine: syncEngine,
      serverSync: ServerSettingsSync(
        values: _EmptyCloudValues(),
        keys: MemoryKeyKeeper(),
        storage: storage,
        home: () async => supportDir,
        passwords: passwords,
      ),
      connections: connections,
      onRestarted: () => restarted = true,
      selfHostedCloudAccounts: selfHosted,
    );

    expect(await reset.requiresPassword(), isFalse);
    await reset.resetEverything();

    expect(restarted, isTrue);
    expect(connections.all, isEmpty);
    // AppFlowy starts again in this process: nothing may linger in memory.
    expect(selfHosted.all, isEmpty);
    expect(await secrets.read(selfHostedAccount.id), isNull);
    expect(storage.values, isEmpty);
    expect(keyring.items, isEmpty);
    expect(syncEngine.binding, isNull);
    // Remote sync folder was NOT wiped because clearCloudSync defaulted false.
    expect(remoteSyncDir.listSync(), isNotEmpty);

    final marker = File(p.join(supportDir.path, pendingAppResetFile));
    expect(marker.existsSync(), isTrue);
    final decoded = jsonDecode(marker.readAsStringSync()) as Map;
    expect(decoded['paths'], contains(dataDir.path));
  });

  test(
      'with an AppFlowy password set, refuses wrong or missing password and clears cloud sync when asked',
      () async {
    final secrets = ProviderSecretStore(storage: storage, keyring: keyring);
    final passwords = AppPassword(
      storage: storage,
      secrets: secrets,
      iterations: 200,
    );
    await passwords.choose('correct-app-password');

    EncryptionVault.instance
      ..configureForTest(storage: storage, passwords: passwords)
      ..seedForTest(policy: const EncryptionPolicy(iterations: 200));
    await EncryptionVault.instance.enable(passphrase: 'correct-app-password');

    final syncSettings =
        SyncSettings(storage: storage, home: () async => supportDir);
    final syncEngine = WorkspaceSyncEngine(
      bridge: _MinimalBridge(),
      settings: syncSettings,
      dataPath: () async => dataDir.path,
      scratch: () async => Directory(p.join(root.path, 'scratch')),
      keys: MemoryKeyKeeper(),
      passwords: passwords,
      vaultIterations: 200,
    );
    await syncEngine.attach(
      workspaceId: 'ws-1',
      uid: 1,
      workspaceName: 'Synced Workspace',
      isLocalWorkspace: true,
    );
    await syncEngine.startNew(
      BackupDestination(
        kind: BackupDestinationKind.folder,
        localPath: remoteSyncDir.path,
      ),
    );

    var restarted = false;
    final reset = makeService(
      passwords: passwords,
      syncEngine: syncEngine,
      serverSync: ServerSettingsSync(
        values: _EmptyCloudValues(),
        keys: MemoryKeyKeeper(),
        storage: storage,
        home: () async => supportDir,
        passwords: passwords,
      ),
      connections: ProviderConnections(storage: storage, secrets: secrets),
      onRestarted: () => restarted = true,
    );

    expect(await reset.requiresPassword(), isTrue);
    await expectLater(
      reset.resetEverything(),
      throwsA(isA<AppResetError>()),
    );
    await expectLater(
      reset.resetEverything(password: 'wrong-password'),
      throwsA(isA<AppResetError>()),
    );
    expect(restarted, isFalse);
    expect(passwords.isSet, isTrue);
    expect(remoteSyncDir.listSync(), isNotEmpty);

    await reset.resetEverything(
      password: 'correct-app-password',
      clearCloudSync: true,
    );
    expect(restarted, isTrue);
    expect(passwords.isSet, isFalse);
    expect(EncryptionVault.instance.isConfigured, isFalse);
    expect(
      remoteSyncDir
          .listSync()
          .where((e) => SyncFileName.parse(p.basename(e.path)) != null),
      isEmpty,
    );
  });
}

class _MinimalBridge implements WorkspaceBundleBridge {
  @override
  Future<WorkspaceBundleExport> exportSnapshot({
    required String path,
    String syncStatePath = '',
  }) async {
    await File(path).writeAsString('snapshot');
    return const WorkspaceBundleExport(
      wrote: true,
      objectCount: 1,
      uid: 1,
      workspaceId: 'ws-1',
      workspaceName: 'My Workspace',
      isLocalWorkspace: true,
    );
  }

  @override
  Future<WorkspaceBundleExport> exportChanges({
    required String path,
    required String syncStatePath,
  }) async =>
      const WorkspaceBundleExport(
        wrote: false,
        objectCount: 0,
        uid: 1,
        workspaceId: 'ws-1',
        workspaceName: 'My Workspace',
        isLocalWorkspace: true,
      );

  @override
  Future<WorkspaceBundleImport> importChanges({
    required String path,
    String syncStatePath = '',
  }) async =>
      const WorkspaceBundleImport();

  @override
  Future<void> scheduleRestore({
    required String path,
    String syncStatePath = '',
  }) async {}

  @override
  Future<WorkspaceRestoreOutcome?> takeRestoreOutcome() async => null;
}

class _EmptyCloudValues implements CloudUserValues {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

class _MemoryKeyring implements DesktopKeyring {
  final Map<String, String> items = {};

  @override
  bool get isAvailable => true;

  @override
  Future<void> store({
    required String scope,
    required String id,
    required String label,
    required String secret,
  }) async =>
      items['$scope/$id'] = secret;

  @override
  Future<String?> lookup({required String scope, required String id}) async =>
      items['$scope/$id'];

  @override
  Future<void> clear({required String scope, required String id}) async =>
      items.remove('$scope/$id');
}

class _MemoryKeyValue implements KeyValueStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }
}
