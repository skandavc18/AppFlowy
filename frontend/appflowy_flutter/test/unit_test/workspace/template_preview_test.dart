import 'package:appflowy/plugins/templates/presentation/template_preview.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The application's real theme, because a preview mounts real widgets and
/// they reach for theme extensions a bare `MaterialApp` does not carry.
Widget _themedApp({required Widget child}) {
  final materialTheme = DesktopAppearance().getThemeData(
    AppTheme.fallback,
    Brightness.light,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final palette = materialTheme.extension<PremiumThemeExtension>()!;
  return MaterialApp(
    theme: materialTheme,
    home: AppFlowyTheme(
      data: PremiumTheme.appFlowyTheme(
        base: AppFlowyDefaultTheme().light(),
        palette: palette,
        brightness: Brightness.light,
      ),
      child: Scaffold(body: child),
    ),
  );
}

/// Templates made only of tables.
///
/// Deliberately not every template: a clock ticks on a `Timer.periodic` and an
/// editor keeps timers of its own, so a whole-catalogue widget test can never
/// settle. A table preview is the part that broke, and it holds no clock.
List<WorkspaceTemplate> _tableOnly() => [
      for (final template in TemplateRegistry.all())
        if (template.parts.every((part) => part.blueprint is TemplateDatabase))
          template,
    ];

Future<Size?> _open(WidgetTester tester, WorkspaceTemplate template) async {
  await tester.pumpWidget(
    _themedApp(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showTemplatePreview(context, template, confirmLabel: 'Use'),
          child: const Text('open'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  final dialog = find.byType(Dialog);
  if (dialog.evaluate().isEmpty) {
    return null;
  }
  try {
    return tester.getSize(dialog);
  } on Object {
    // An unsized dialog is exactly the failure being guarded against.
    return Size.zero;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('previewing a template that makes a table', () {
    tearDown(TemplateRegistry.reset);

    test('there are some to preview', () {
      expect(_tableOnly(), isNotEmpty);
    });

    // ⚠️ The bug this guards: `Row(crossAxisAlignment: stretch)` inside a
    // scroll view forces h=Infinity on every cell. Layout throws where the
    // rendering library swallows it, nothing gets a size, and the dialog
    // comes up blank — which reads as the card having done nothing at all.
    testWidgets('the dialog comes up with a real size', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final blank = <String, String>{};
      for (final template in _tableOnly()) {
        final size = await _open(tester, template);
        if (size == null) {
          blank[template.id] = 'no dialog opened';
        } else if (size.width <= 0 || size.height <= 0) {
          blank[template.id] = 'the dialog came up unsized';
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }

      expect(
        blank,
        isEmpty,
        reason: 'these previews showed nothing:\n'
            '${blank.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}',
      );
    });

    testWidgets('it draws the columns the table will have', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final template = _tableOnly().first;
      await _open(tester, template);

      final table =
          (template.parts.single.blueprint as TemplateDatabase).build(const {});
      for (final column in table.columns) {
        expect(
          find.text(column.name),
          findsWidgets,
          reason: '${template.id} did not draw the column "${column.name}"',
        );
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
