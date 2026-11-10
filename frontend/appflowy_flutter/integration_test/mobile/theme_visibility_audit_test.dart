import 'dart:async';
import 'dart:io';

import 'package:appflowy/mobile/presentation/home/mobile_home_setting_page.dart';
import 'package:appflowy/mobile/presentation/setting/settings_page/mobile_settings_page_screen.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/theme_audit.dart';
import '../shared/theme_audit_seed.dart';
import '../shared/util.dart';

/// The mobile half of the visibility audit: the same scratch workspace and the
/// same scan, in the mobile shell, written to the app's external files folder
/// (`adb pull /sdcard/Android/data/<id>/files/theme-audit`).
///
/// THEME_AUDIT_ONLY (a --dart-define) limits the run to names starting with
/// any of its comma-separated prefixes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const filter = String.fromEnvironment('THEME_AUDIT_ONLY');
  final only = filter.split(',').where((name) => name.isNotEmpty).toSet();
  bool wants(String name) => only.isEmpty || only.any(name.startsWith);

  testWidgets(
    'mobile theme visibility audit',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final output = Directory(p.join(base.path, 'theme-audit'));
      if (output.existsSync()) {
        await output.delete(recursive: true);
      }
      await output.create(recursive: true);
      final audit = ThemeAudit(tester, output);
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();
      await audit.settle();
      final view = tester.view;
      audit.note(
        'screen ${view.physicalSize.width.round()}x'
        '${view.physicalSize.height.round()} at ${view.devicePixelRatio}x',
      );

      final previous = FlutterError.onError;
      FlutterError.onError = audit.recordError;
      try {
        final seed = ThemeAuditSeed(
          tester,
          audit,
          await Directory(p.join(output.path, 'scratch')).create(),
        );
        final pages = await seed.seed(wants: wants);
        await seed.home();
        for (final mode in AuditMode.values) {
          await audit.apply(mode);
          if (wants('home')) {
            await audit.capture(mode, 'home');
          }
          for (final page in pages) {
            await seed.open(page);
            await audit.capture(mode, page.name);
            if (page.document) {
              await _captureRestOfDocument(tester, audit, mode, page.name);
            }
            await seed.home();
          }
          if (wants('settings')) {
            await _captureSettings(tester, audit, seed, mode);
          }
        }
      } finally {
        FlutterError.onError = previous;
      }
      await audit.finish();
    },
    timeout: const Timeout(Duration(minutes: 90)),
  );
}

Future<void> _captureRestOfDocument(
  WidgetTester tester,
  ThemeAudit audit,
  AuditMode mode,
  String name,
) async {
  final editors = find.byType(AppFlowyEditor);
  if (editors.evaluate().isEmpty) {
    return;
  }
  final scroll =
      tester.widget<AppFlowyEditor>(editors.last).editorState.scrollService;
  if (scroll == null) {
    return;
  }
  final step = (scroll.onePageHeight ?? 700) * 0.85;
  for (var index = 1; index <= 16; index++) {
    final target = step * index;
    if (target > scroll.maxScrollExtent + step * 0.5) {
      break;
    }
    scroll.scrollTo(target, duration: const Duration(milliseconds: 1));
    await audit.pumpFor(const Duration(milliseconds: 800));
    await audit.capture(mode, '$name-$index');
  }
}

Future<void> _captureSettings(
  WidgetTester tester,
  ThemeAudit audit,
  ThemeAuditSeed seed,
  AuditMode mode,
) async {
  final router = GoRouter.of(AppGlobals.rootNavKey.currentContext!);
  unawaited(router.push(MobileHomeSettingPage.routeName));
  await audit.pumpFor(const Duration(milliseconds: 1200));
  await audit.capture(mode, 'settings');
  await seed.home();
  for (final page in SettingsPage.values) {
    unawaited(router.push(MobileSettingsPageScreen.location(page)));
    await audit.pumpFor(const Duration(milliseconds: 1500));
    await audit.capture(mode, 'settings-${page.name}');
    await seed.home();
  }
}
