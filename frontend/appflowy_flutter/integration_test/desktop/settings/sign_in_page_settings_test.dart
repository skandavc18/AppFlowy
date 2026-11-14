import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/desktop_sign_in_screen.dart';
import 'package:appflowy/workspace/presentation/settings/settings_dialog.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../shared/util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder field(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextField),
      );

  group('sign-in page:', () {
    testWidgets('settings keep to language and support', (tester) async {
      await tester.initializeAppFlowy();

      await tester.tapButton(find.byType(DesktopSignInSettingsButton));

      expect(find.byType(SimpleSettingsDialog), findsOneWidget);
      expect(
        find.text(LocaleKeys.settings_workspacePage_language_title.tr()),
        findsOneWidget,
      );
      expect(
        find.text(LocaleKeys.settings_menu_cloudAppFlowy.tr()),
        findsNothing,
      );
    });

    testWidgets('work on your own AppFlowy server, then choose another way',
        (tester) async {
      // Something on this machine that answers like an AppFlowy server.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final path = request.uri.path;
        request.response.statusCode = path == '/gotrue/health'
            ? HttpStatus.ok
            : path.startsWith('/api/sync-folders')
                ? HttpStatus.unauthorized
                : HttpStatus.notFound;
        request.response.close();
      });
      addTearDown(() => server.close(force: true));
      final serverUrl = 'http://127.0.0.1:${server.port}';
      const webUrl = 'https://pages.example.com';

      await tester.initializeAppFlowy();

      await tester
          .tapButton(find.byKey(const ValueKey('first-run-self-hosted')));
      await tester.tapButton(find.byKey(const ValueKey('appflowy-server-own')));
      await tester.enterText(field('appflowy-server-address'), serverUrl);
      await tester.enterText(field('appflowy-server-web'), webUrl);
      await tester.tapButton(
        find.text(LocaleKeys.firstRun_serverContinue.tr()),
      );

      // AppFlowy starts again on the server's own sign in.
      await tester.pumpUntilFound(
        find.text(LocaleKeys.firstRun_signInTo.tr(args: ['127.0.0.1'])),
        timeout: const Duration(seconds: 30),
      );
      expect(currentCloudType(), AuthenticatorType.appflowyCloudSelfHost);
      expect(await getAppFlowyCloudUrl(), serverUrl);
      expect(await getAppFlowyShareDomain(), webUrl);

      await tester.tapButton(find.text(LocaleKeys.firstRun_anotherWay.tr()));
      await tester.pumpUntilFound(
        find.byKey(const ValueKey('first-run-self-hosted')),
        timeout: const Duration(seconds: 30),
      );
      expect(currentCloudType(), AuthenticatorType.appflowyCloud);
    });
  });
}
