import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup_target.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/sync/self_hosted_cloud.dart';
import 'package:appflowy/workspace/application/sync/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'self_hosted_cloud_stand_in.dart';

void main() {
  late SelfHostedCloudStandIn server;
  late _MemoryStorage storage;
  late SelfHostedCloudAccounts accounts;
  late SelfHostedCloud cloud;

  setUp(() async {
    server = await SelfHostedCloudStandIn.start(
      users: {'me@example.com': 'right password'},
    );
    storage = _MemoryStorage();
    accounts = SelfHostedCloudAccounts(
      storage: storage,
      secrets: ProviderSecretStore(storage: storage, keyring: _MemoryKeyring()),
    );
    cloud = SelfHostedCloud(accounts: accounts);
  });
  tearDown(() => server.close());

  Future<SelfHostedCloudAccount> signIn() => cloud.signIn(
        server: server.url,
        email: 'me@example.com',
        password: 'right password',
      );

  test('an address is tidied into a server, or refused', () {
    expect(
      SelfHostedCloud.normalizeServer(' appflowy.example.com/ '),
      'https://appflowy.example.com',
    );
    expect(
      SelfHostedCloud.normalizeServer('http://10.0.0.2:8000/appflowy//'),
      'http://10.0.0.2:8000/appflowy',
    );
    expect(SelfHostedCloud.normalizeServer('ftp://example.com'), isNull);
    expect(SelfHostedCloud.normalizeServer('   '), isNull);
  });

  test('tells a server that keeps sync folders from one that cannot', () async {
    expect(await cloud.check(server.url), SelfHostedCloudCheck.ready);

    server.keepsSyncFolders = false;
    expect(await cloud.check(server.url), SelfHostedCloudCheck.noSyncFolders);

    final elsewhere = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    elsewhere.listen((request) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
    });
    final address = 'http://127.0.0.1:${elsewhere.port}';
    expect(await cloud.check(address), SelfHostedCloudCheck.notAppFlowyCloud);
    await elsewhere.close(force: true);
    expect(await cloud.check(address), SelfHostedCloudCheck.unreachable);
  });

  test('signing in keeps the tokens the server issued, never the password',
      () async {
    final account = await signIn();

    expect(account.server, server.url);
    expect(account.email, 'me@example.com');
    expect(
      account.label,
      'me@example.com · 127.0.0.1:${Uri.parse(server.url).port}',
    );
    expect((await accounts.tokensFor(account.id))?.refreshToken, isNotEmpty);
    expect(storage.values.values.join(), isNot(contains('right password')));

    // Signing in again is the same account, not a second one.
    expect((await signIn()).id, account.id);
    expect(accounts.all, hasLength(1));
  });

  test('says why the server turned a sign in or sign up down', () async {
    Future<SelfHostedCloudAuthProblem?> problem(
      Future<Object?> Function() attempt,
    ) async {
      try {
        await attempt();
        return null;
      } on SelfHostedCloudAuthError catch (error) {
        return error.problem;
      }
    }

    expect(
      await problem(
        () => cloud.signIn(
          server: server.url,
          email: 'me@example.com',
          password: 'wrong',
        ),
      ),
      SelfHostedCloudAuthProblem.wrongPassword,
    );
    expect(
      await problem(
        () => cloud.signUp(
          server: server.url,
          email: 'me@example.com',
          password: 'anything',
        ),
      ),
      SelfHostedCloudAuthProblem.accountExists,
    );
    server.signUpsOpen = false;
    expect(
      await problem(
        () => cloud.signUp(
          server: server.url,
          email: 'new@example.com',
          password: 'anything',
        ),
      ),
      SelfHostedCloudAuthProblem.signUpsClosed,
    );

    server
      ..signUpsOpen = true
      ..autoConfirm = false;
    final waiting = await cloud.signUp(
      server: server.url,
      email: 'new@example.com',
      password: 'a long password',
    );
    expect(waiting.needsConfirmation, isTrue);
  });

  test('a lapsed sign in is renewed once, however many ask at the same time',
      () async {
    final account = await signIn();
    final remote = SelfHostedCloudSyncRemote(
      account: account,
      folder: 'AppFlowy',
      cloud: cloud,
    );
    server.expireAccessTokens();

    await Future.wait([for (var i = 0; i < 5; i++) remote.list()]);
    expect(server.refreshes, 1);

    // The renewed refresh token is the one kept, so the next renewal works.
    server.expireAccessTokens();
    await remote.list();
    expect(server.refreshes, 2);
  });

  test('a sign in the server stopped renewing asks to sign in again', () async {
    final account = await signIn();
    await accounts.keepTokens(
      account.id,
      SelfHostedCloudTokens(
        accessToken: 'lapsed',
        refreshToken: 'revoked',
        expiresAt: DateTime(2000),
      ),
    );

    await expectLater(
      SelfHostedCloudSyncRemote(
        account: account,
        folder: 'AppFlowy',
        cloud: cloud,
      ).list(),
      throwsA(
        isA<ProviderFailure>().having(
          (failure) => failure.status.needsReconnect,
          'needs signing in again',
          isTrue,
        ),
      ),
    );
  });

  test('a sync folder holds files and attached files apart', () async {
    final scratch = await Directory.systemTemp.createTemp('self_hosted_cloud');
    addTearDown(() => scratch.delete(recursive: true));
    final account = await signIn();
    final remote = SelfHostedCloudSyncRemote(
      account: account,
      folder: 'Work notes',
      cloud: cloud,
    );
    await remote.ensureReady();

    final pack = File(p.join(scratch.path, 'pack'))
      ..writeAsBytesSync(List.generate(300000, (i) => i % 251));
    final info = File(p.join(scratch.path, 'info'))..writeAsStringSync('{}');
    final progress = <int>[];
    await remote.upload(
      'afsync1_20260101T000000-abcdef_base.pack',
      pack,
      onProgress: (done, _) => progress.add(done),
    );
    await remote.upload('afsync1_20260101T000000-abcdef_base.json', info);
    await remote.upload('afsync1_blob_${'a' * 64}', info, blob: true);
    expect(progress.last, 300000);

    final files = await remote.list();
    expect(files.map((file) => file.name), hasLength(2));
    expect(await remote.list(blobs: true), hasLength(1));
    expect(await cloud.folders(account), ['Work notes']);

    final packFile = files.firstWhere((file) => file.name.endsWith('.pack'));
    final back = File(p.join(scratch.path, 'back'));
    await remote.download(packFile, back);
    expect(back.readAsBytesSync(), pack.readAsBytesSync());
    final blob = (await remote.list(blobs: true)).single;
    expect(await remote.readText(blob), '{}');

    await remote.delete(blob);
    expect(await remote.list(blobs: true), isEmpty);
    await expectLater(
      remote.download(blob, back),
      throwsA(isA<BackupTargetError>()),
    );
  });

  group('working on a server', () {
    tearDown(() => getIt.reset());

    test('a self-hosted server stays chosen when AppFlowy starts again',
        () async {
      final kv = _MemoryStorage();
      getIt.registerSingleton<KeyValueStorage>(kv);
      await useAppFlowyServer(
        'https://appflowy.example.com',
        webUrl: 'https://appflowy.example.com',
      );

      final env = await AppFlowyCloudSharedEnv.fromEnv();
      getIt.registerFactory<AppFlowyCloudSharedEnv>(() => env);

      expect(env.authenticatorType, AuthenticatorType.appflowyCloud);
      expect(currentCloudType(), AuthenticatorType.appflowyCloudSelfHost);
      expect(isServerChosen, isTrue);
      expect(env.appflowyCloudConfig.base_url, 'https://appflowy.example.com');

      await useNoServer();
      expect(await kv.get(KVKeys.kCloudType), '2');
      expect(await chosenAppFlowyServer(), isNull);
    });
  });
}

class _MemoryStorage implements KeyValueStorage {
  final Map<String, String> values = {};

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();
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
