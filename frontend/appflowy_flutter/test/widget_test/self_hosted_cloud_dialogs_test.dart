import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/sync/self_hosted_cloud.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/appflowy_server.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/self_hosted_cloud_dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  Finder field(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextField),
      );

  group('syncing through a self-hosted AppFlowy Cloud', () {
    Future<Future<BackupDestination?>> start(
      WidgetTester tester,
      _FakeCloud cloud,
    ) async {
      late Future<BackupDestination?> chosen;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => chosen =
                  chooseSelfHostedCloudDestination(context, cloud: cloud),
              child: const Text('Set up'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up'));
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('asks for the address, then the account, then the folder',
        (tester) async {
      final cloud = _FakeCloud();
      final chosen = await start(tester, cloud);

      await tester.enterText(
        field('self-hosted-sync-server'),
        'appflowy.example.com/',
      );
      await tester.enterText(field('self-hosted-sync-email'), 'me@example.com');
      await tester.enterText(field('self-hosted-sync-password'), 'wrong');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "That email and password don't match an account on this server.",
        ),
        findsOneWidget,
      );

      await tester.enterText(field('self-hosted-sync-password'), 'right');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(cloud.checked, ['https://appflowy.example.com']);

      // The folder another computer already syncs to is the one offered.
      expect(
        find.byKey(const ValueKey('self-hosted-sync-folder-AppFlowy')),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final destination = await chosen;
      expect(destination?.kind, BackupDestinationKind.selfHostedCloud);
      expect(destination?.server, 'https://appflowy.example.com');
      expect(destination?.folderId, 'AppFlowy');
      expect(destination?.connectionId, 'account');
      expect(destination?.isReady, isTrue);
    });

    testWidgets('an AppFlowy Cloud without sync folders is named as such',
        (tester) async {
      final cloud = _FakeCloud(answer: SelfHostedCloudCheck.noSyncFolders);
      final chosen = await start(tester, cloud);

      await tester.enterText(
        field('self-hosted-sync-server'),
        'https://appflowy.example.com',
      );
      await tester.enterText(field('self-hosted-sync-email'), 'me@example.com');
      await tester.enterText(field('self-hosted-sync-password'), 'right');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("can't hold sync folders yet"),
        findsOneWidget,
      );
      expect(cloud.signedIn, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await chosen, isNull);
    });
  });

  group('working on an AppFlowy server', () {
    tearDown(() => getIt.reset());

    testWidgets('your own server is checked, and its pages open at it',
        (tester) async {
      late Future<AppFlowyServerChoice?> chosen;
      final checked = <String>[];
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => chosen = showDialog<AppFlowyServerChoice>(
                context: context,
                builder: (_) => AppFlowyServerDialog(
                  check: (server) async {
                    checked.add(server);
                    return SelfHostedCloudCheck.noSyncFolders;
                  },
                ),
              ),
              child: const Text('Choose'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appflowy-server-own')));
      await tester.pumpAndSettle();
      await tester.enterText(
        field('appflowy-server-address'),
        'af.example.com',
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      final choice = await chosen;
      expect(checked, ['https://af.example.com']);
      expect(choice?.url, 'https://af.example.com');
      expect(choice?.webUrl, 'https://af.example.com');
    });

    testWidgets('the Sync card connects, signs in, changes and leaves',
        (tester) async {
      final storage = _MemoryStorage();
      getIt.registerSingleton<KeyValueStorage>(storage);
      var chosen = AuthenticatorType.appflowyCloud;
      getIt.registerFactory<AppFlowyCloudSharedEnv>(
        () => AppFlowyCloudSharedEnv(
          authenticatorType: AuthenticatorType.appflowyCloud,
          chosenType: chosen,
          appflowyCloudConfig: AppFlowyCloudConfiguration(
            base_url: 'https://af.example.com',
            ws_base_url: 'wss://af.example.com/ws/v1',
            gotrue_url: 'https://af.example.com/gotrue',
            enable_sync_trace: false,
            base_web_domain: 'https://af.example.com',
          ),
        ),
      );
      var restarts = 0;
      Future<void> pump(UserProfilePB user) async {
        await tester.pumpWidget(
          _app(
            AppFlowyServerPanel(
              key: UniqueKey(),
              userProfile: user,
              restart: () => restarts++,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // Kept on this computer.
      await pump(UserProfilePB()..userAuthType = AuthTypePB.Local);
      expect(find.text('Connect…'), findsOneWidget);
      expect(find.text('Leave'), findsNothing);

      // A server chosen, not signed in to yet.
      chosen = AuthenticatorType.appflowyCloudSelfHost;
      await pump(UserProfilePB()..userAuthType = AuthTypePB.Local);
      expect(find.text('AppFlowy server · af.example.com'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Change server…'), findsOneWidget);

      // Signed in.
      await pump(
        UserProfilePB()
          ..userAuthType = AuthTypePB.Server
          ..email = 'me@example.com',
      );
      expect(
        find.textContaining('Signed in as me@example.com'),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsNothing);
      expect(find.text('Leave'), findsOneWidget);

      // Leaving forgets the server and starts again.
      await pump(UserProfilePB()..userAuthType = AuthTypePB.Local);
      await storage.set(KVKeys.kCloudType, '3');
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave server'));
      await tester.pumpAndSettle();
      expect(await storage.get(KVKeys.kCloudType), '2');
      expect(restarts, 1);
    });
  });
}

/// Answers the way a server would, without one.
class _FakeCloud extends SelfHostedCloud {
  _FakeCloud({this.answer = SelfHostedCloudCheck.ready})
      : super(
          accounts: SelfHostedCloudAccounts(
            storage: _MemoryStorage(),
            secrets: ProviderSecretStore(
              storage: _MemoryStorage(),
              keyring: _NoKeyring(),
            ),
          ),
        );

  final SelfHostedCloudCheck answer;
  final List<String> checked = [];
  bool signedIn = false;

  @override
  Future<SelfHostedCloudCheck> check(String server) async {
    checked.add(server);
    return answer;
  }

  @override
  Future<SelfHostedCloudAccount> signIn({
    required String server,
    required String email,
    required String password,
    String? keepId,
  }) async {
    if (password != 'right') {
      throw const SelfHostedCloudAuthError(
        SelfHostedCloudAuthProblem.wrongPassword,
      );
    }
    signedIn = true;
    return SelfHostedCloudAccount(
      id: keepId ?? 'account',
      server: server,
      email: email,
    );
  }

  @override
  Future<List<String>> folders(SelfHostedCloudAccount account) async =>
      ['AppFlowy'];
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

class _NoKeyring implements DesktopKeyring {
  @override
  bool get isAvailable => false;

  @override
  Future<void> store({
    required String scope,
    required String id,
    required String label,
    required String secret,
  }) async {}

  @override
  Future<String?> lookup({required String scope, required String id}) async =>
      null;

  @override
  Future<void> clear({required String scope, required String id}) async {}
}

Widget _app(Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: DesktopAppearance().getThemeData(
            AppTheme.fallback,
            Brightness.light,
            'Poppins',
            builtInCodeFontFamily,
          ),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
