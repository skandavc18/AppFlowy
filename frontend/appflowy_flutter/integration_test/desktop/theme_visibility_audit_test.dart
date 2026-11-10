import 'dart:io';

import 'package:appflowy/workspace/presentation/settings/settings_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu_element.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/theme_audit.dart';
import '../shared/theme_audit_seed.dart';
import '../shared/util.dart';

/// Opt-in visibility audit: fills a scratch workspace with one of every block,
/// page kind, collection and file preview, then renders each in Light, Dark
/// and Paper. Every surface is written as a screenshot, and every text or
/// glyph whose rendered contrast falls below WCAG AA is reported.
///
/// Run with THEME_AUDIT_OUTPUT set to an absolute directory. Preferences
/// are held in memory and the workspace lives in a temporary directory; run
/// with FLUTTER_TEST set so the desktop keyring is never touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['THEME_AUDIT_OUTPUT'] ?? '';
  final only = (Platform.environment['THEME_AUDIT_ONLY'] ?? '')
      .split(',')
      .where((name) => name.isNotEmpty)
      .toSet();

  testWidgets(
    'theme visibility audit',
    (tester) async {
      if (!p.isAbsolute(output)) {
        markTestSkipped('Set THEME_AUDIT_OUTPUT to an absolute directory.');
        return;
      }
      SharedPreferences.setMockInitialValues({});
      final audit = ThemeAudit(tester, Directory(output));
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();
      await audit.fitWindow(const Size(1600, 1200));

      // Half-configured blocks are expected to complain; the audit is about
      // what reaches the screen, so errors are kept as notes, not failures.
      final previous = FlutterError.onError;
      FlutterError.onError = audit.recordError;
      try {
        final seed = ThemeAuditSeed(
          tester,
          audit,
          await Directory(p.join(output, 'scratch')).create(recursive: true),
        );
        bool wants(String name) => only.isEmpty || only.any(name.startsWith);
        final pages = await seed.seed(wants: wants);
        for (final mode in AuditMode.values) {
          await audit.apply(mode);
          for (final page in pages) {
            await seed.open(page);
            await audit.capture(mode, page.name);
            if (page.document) {
              await _captureRestOfDocument(tester, audit, mode, page.name);
            }
          }
          if (only.isEmpty || only.contains('settings')) {
            await _captureSettings(tester, audit, mode);
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
      tester.widget<AppFlowyEditor>(editors.first).editorState.scrollService;
  if (scroll == null) {
    return;
  }
  final step = (scroll.onePageHeight ?? 900) * 0.85;
  for (var index = 1; index <= 16; index++) {
    final target = step * index;
    if (target > scroll.maxScrollExtent + step * 0.5) {
      break;
    }
    // The editor animates every scroll and asserts a non-zero duration.
    scroll.scrollTo(target, duration: const Duration(milliseconds: 1));
    await audit.pumpFor(const Duration(milliseconds: 800));
    await audit.capture(mode, '$name-$index');
  }
  scroll.scrollTo(0, duration: const Duration(milliseconds: 1));
  await audit.pumpFor(const Duration(milliseconds: 200));
}

Future<void> _captureSettings(
  WidgetTester tester,
  ThemeAudit audit,
  AuditMode mode,
) async {
  await tester.openSettings();
  await audit.settle();
  final pages = [
    for (final element in find.byType(SettingsMenuElement).evaluate())
      (element.widget as SettingsMenuElement).page,
  ];
  for (final page in pages) {
    try {
      await tester.openSettingsPage(page);
    } on Object catch (error) {
      audit.note('settings ${page.name} did not open: $error');
      continue;
    }
    await audit.pumpFor(const Duration(milliseconds: 600));
    await audit.capture(
      mode,
      'settings-${page.name}',
      within: find.byType(SettingsDialog),
    );
  }
  final dialog = find.byType(SettingsDialog);
  for (var i = 0; i < 3 && dialog.evaluate().isNotEmpty; i++) {
    await tester.tapAt(const Offset(4, 4));
    await audit.settle();
  }
}
