import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const chartAppearances = ['light', 'dark', 'paper'];
const chartAppearanceTable = ChartTable(
  columns: [
    'Category',
    'Revenue USD',
    'Costs USD',
    'Day',
    'Units',
    'Weight kg',
  ],
  columnIds: ['category', 'revenue', 'costs', 'day', 'units', 'weight'],
  rows: [
    ['North', '24.5', '12', '2026-09-01T00:00:00Z', '4', '4'],
    ['South', '36', '22', '2026-09-02T00:00:00Z', '9', '9'],
    ['East', '18', '10', '2026-09-03T00:00:00Z', '2', '2'],
    ['West', '30', '16', '2026-09-04T00:00:00Z', '6', '6'],
  ],
);

ChartSpec chartAppearanceSpec(
  ChartType type, {
  bool showControls = false,
  bool showLegend = true,
  Map<String, int> colors = const {},
}) =>
    ChartSpec(
      type: type,
      categoryColumn: 'category',
      valueColumns: const ['revenue', 'costs'],
      xColumn: type.drawsPoints ? 'units' : null,
      sizeColumn: type.sizesPoints ? 'weight' : null,
      showControls: showControls,
      showLegend: showLegend,
      colors: colors,
    );

ThemeData chartAppearanceTheme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

void setUpChartAppearanceFixtures() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontFetching = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    final families = <String>{'DM Sans'};
    for (final appearance in chartAppearances) {
      final text = chartAppearanceTheme(appearance).textTheme;
      families.addAll([
        text.bodyMedium!.fontFamily!,
        text.bodySmall!.fontFamily!,
        text.titleMedium!.fontFamily!,
        text.labelLarge!.fontFamily!,
      ]);
    }
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);
}

Widget chartAppearanceApp(
  String appearance,
  Widget body, {
  double textScale = 1,
  bool reducedMotion = false,
  bool accessibleNavigation = false,
}) {
  final theme = chartAppearanceTheme(appearance);
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    startLocale: const Locale('en', 'US'),
    fallbackLocale: const Locale('en', 'US'),
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, navigator) => AppFlowyTheme(
          data: PremiumTheme.appFlowyTheme(
            base: appearance == 'dark'
                ? AppFlowyDefaultTheme().dark()
                : AppFlowyDefaultTheme().light(),
            palette: theme.extension<PremiumThemeExtension>()!,
            brightness: theme.brightness,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reducedMotion,
              accessibleNavigation: accessibleNavigation,
            ),
            child: TooltipVisibility(visible: false, child: navigator!),
          ),
        ),
        home: Scaffold(body: body),
      ),
    ),
  );
}

Finder get chartAppearancePlot => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ChartPainter,
    );

ChartPainter chartAppearancePainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(chartAppearancePlot).painter! as ChartPainter;

Offset chartHitPosition(ChartPainter painter, ChartHit hit) =>
    painter.spec.type.isCircular ? hit.anchor : hit.rect.center;

Rect chartRenderedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  // Both corners must cross the render transform. getSize reports layout
  // dimensions and would falsely flag content fitted into a tiny host.
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void expectChartRectInside(Rect child, Rect parent) {
  expect(child.width, greaterThan(0));
  expect(child.height, greaterThan(0));
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.01));
  expect(child.top, greaterThanOrEqualTo(parent.top - 0.01));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.01));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.01));
}
