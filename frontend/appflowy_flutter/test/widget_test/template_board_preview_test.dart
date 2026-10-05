import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_guide.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_template_gallery.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:appflowy/plugins/templates/presentation/template_preview.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/templates/template_guides.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/template_samples.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

/// Money boards shown before they are made: from their own rows, never as a
/// wall of "choose a table" cards, and offered where a dashboard starts.
Widget _app(Widget child) {
  final theme = DesktopAppearance()
      .getThemeData(
        AppTheme.fallback,
        Brightness.light,
        '',
        builtInCodeFontFamily,
      )
      .copyWith(platform: TargetPlatform.windows);
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, navigator) => AppFlowyTheme(
          data: PremiumTheme.appFlowyTheme(
            base: AppFlowyDefaultTheme().light(),
            palette: theme.extension<PremiumThemeExtension>()!,
            brightness: theme.brightness,
          ),
          child: TooltipVisibility(visible: false, child: navigator!),
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var step = 0; step < 20; step++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  tearDown(TemplateRegistry.reset);

  testWidgets('every dashboard template says how to use it', (tester) async {
    // Translations load with the first app.
    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await _settle(tester);
    final ids = <String>[
      for (final template in TemplateRegistry.all())
        if (template.boardPart != null) template.id,
      for (final template in dashboardTemplates())
        if (template.id != 'blank') template.id,
    ];
    expect(ids, contains('assets'));
    for (final id in ids) {
      final steps = templateGuide(id);
      expect(steps, hasLength(3), reason: '$id has no guide');
      for (final step in steps) {
        expect(step, isNot(contains('templates.guide')), reason: id);
        expect(step.trim(), isNotEmpty, reason: id);
      }
    }
    expect(templateGuide('board_personal'), templateGuide('personal'));
    expect(templateGuide('landing'), isEmpty);
  });

  testWidgets('the guide is shown, and dismissed once read', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    var dismissed = 0;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => DashboardGuideCard(
            steps: const ['First this', 'Then that', 'Last of all'],
            palette: DashboardPalette.of(context),
            onDismiss: () => dismissed++,
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Then that'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dashboard-guide-dismiss')));
    await tester.pump();
    expect(dismissed, 1);
    expect(tester.takeException(), isNull);
  });

  test('every board reads tables its samples provide', () {
    for (final template in TemplateRegistry.boards()) {
      final samples = templateSamples(template);
      final board = (template.boardPart!.blueprint as TemplateDashboard)
          .build(samples.ids);
      for (final section in board.sections) {
        for (final widget in section.widgets) {
          final viewId = widget.source.viewId;
          if (viewId.isEmpty) {
            continue;
          }
          expect(
            samples.tables[viewId]?.rows,
            isNotEmpty,
            reason: '${template.id}: ${widget.type} reads $viewId',
          );
        }
      }
    }
  });

  for (final (id, expected) in <(String, String Function(WorkspaceTemplate))>[
    ('assets', (_) => '₹'),
    (
      'quotes',
      (template) {
        final rows = templateSamples(template).tables.values.first.rows.length;
        return '${LocaleKeys.dashboard_money_allThemes.tr()}  $rows';
      },
    ),
  ]) {
    testWidgets('the $id preview draws its board from its own rows',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 1100);
      addTearDown(tester.view.reset);
      final template = TemplateRegistry.forId(id)!;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showTemplatePreview(context, template, confirmLabel: 'Use'),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('open'));
      await _settle(tester);

      expect(
        find.textContaining(expected(template), findRichText: true),
        findsWidgets,
        reason: 'the board did not draw its sample rows',
      );
      expect(
        find.text(LocaleKeys.dashboard_money_chooseTable.tr()),
        findsNothing,
        reason: 'a widget was left waiting for a table',
      );
      expect(find.text(templateGuide(id)[1]), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('an empty dashboard offers the boards that bring tables',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 2600);
    addTearDown(tester.view.reset);
    WorkspaceTemplate? chosen;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => DashboardTemplateGallery(
            palette: DashboardPalette.of(context),
            onChosen: (_) {},
            onBoardChosen: (template) => chosen = template,
          ),
        ),
      ),
    );
    await _settle(tester);
    // Each card also draws its board, whose widgets can share its name.
    final net = find.byKey(const ValueKey('dashboard-template-assets'));
    expect(net, findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard-template-quotes')),
      findsOneWidget,
    );
    await tester.tap(net);
    await tester.pump();
    expect(chosen?.id, 'assets');
    expect(tester.takeException(), isNull);
  });
}
