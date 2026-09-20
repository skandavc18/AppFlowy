import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _reference = ValueKey('chart-integrated-reference');
const _appearances = ['light', 'dark', 'paper'];
const _types = [ChartType.bar, ChartType.line, ChartType.donut];
const _title = 'Quarterly revenue';
const _table = ChartTable(
  columns: ['Quarter', 'Revenue', 'Costs'],
  columnIds: ['quarter', 'revenue', 'costs'],
  rows: [
    ['Q1', '5000', '2800'],
    ['Q2', '7500', '4200'],
    ['Q3', '6200', '3600'],
    ['Q4', '9000', '5000'],
  ],
);

ChartSpec _spec(ChartType type) => ChartSpec(
      type: type,
      categoryColumn: 'quarter',
      valueColumns: const ['revenue', 'costs'],
      palette: ChartPaletteName.ocean,
      showValues: true,
    );

// New baselines are generated and visually reviewed separately. Keep the real
// stage, legends and preview controls; only the table read is replaced.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontFetching = GoogleFonts.config.allowRuntimeFetching;
  final loadedFamilies = <String>{'DM Sans'};
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final appearance in _appearances) {
      final text = _theme(appearance).textTheme;
      loadedFamilies.addAll([
        text.bodyMedium!.fontFamily!,
        text.bodySmall!.fontFamily!,
        text.titleMedium!.fontFamily!,
        text.headlineSmall!.fontFamily!,
        text.labelLarge!.fontFamily!,
      ]);
    }
    for (final family in loadedFamilies) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  for (final appearance in _appearances) {
    testWidgets(
      '$appearance: populated charts blend into the page at rest and hover',
      (tester) async {
        tester.view.physicalSize = const Size(800, 920);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sources = [
          for (final type in _types)
            ChartSource(
              viewId: 'golden-chart-${type.name}',
              // Injecting the loader skips native initialization and streams.
              loadTable: (_) async => _table,
            ),
        ];
        TestGesture? mouse;
        try {
          await _mount(tester, appearance, sources);
          expect(find.byType(ChartStage), findsNWidgets(3));
          expect(find.byType(AppChart), findsNWidgets(3));
          expect(find.text(_title), findsNWidgets(3));
          expect(
            PaperTheme.isEnabled(tester.element(find.byKey(_reference))),
            appearance == 'paper',
          );
          for (final type in _types) {
            final stage = _stage(type);
            final chart = tester.widget<AppChart>(
              find.descendant(of: stage, matching: find.byType(AppChart)),
            );
            expect(chart.data.categories, ['Q1', 'Q2', 'Q3', 'Q4']);
            expect(
              chart.data.series.map((series) => series.name),
              ['Revenue', 'Costs'],
            );
            expect(chart.spec.categoryColumn, 'Quarter');
            expect(
              loadedFamilies,
              contains(chart.palette.baseTextStyle.fontFamily),
            );
            final shell = tester.widget<Container>(
              find
                  .descendant(of: stage, matching: find.byType(Container))
                  .first,
            );
            final decoration = shell.decoration! as BoxDecoration;
            expect(decoration.color, isNull);
            expect(decoration.border, isNull);
            expect(decoration.boxShadow, isNull);
            _expectTools(tester, type, visible: false);
          }

          // Hover identity, not data: show the actual refresh/options actions
          // without a chart tooltip or an open menu obscuring the reference.
          mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(4, 4));
          await mouse.moveTo(
            tester.getCenter(
              find.descendant(
                of: _stage(ChartType.donut),
                matching: find.text(_title),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final type in _types) {
            _expectTools(tester, type, visible: type == ChartType.donut);
          }
          expect(find.byType(ChartTooltip), findsNothing);
          expect(
            find.byIcon(Icons.more_horiz_rounded).hitTestable(),
            findsOneWidget,
          );
          final more = find
              .descendant(
                of: _stage(ChartType.donut),
                matching: find.byType(ChartIconAction),
              )
              .last;
          expect(
            tester.getRect(more).right,
            tester.getRect(_stage(ChartType.donut)).right - 12,
            reason: 'Header actions align with the trailing page inset.',
          );
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_reference),
            matchesGoldenFile('goldens/chart_integrated_$appearance.png'),
          );

          await mouse.moveTo(const Offset(4, 4));
          await tester.pumpAndSettle();
          _expectTools(tester, ChartType.donut, visible: false);
        } finally {
          await mouse?.removePointer();
          // Unmount here to dispose reveal/preview/focus controllers before
          // the fake-clock test ends; borrowed sources remain our responsibility.
          await tester.pumpWidget(const SizedBox.shrink());
          for (final source in sources) {
            source.dispose();
          }
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

Finder _stage(ChartType type) => find.byKey(ValueKey('chart-${type.name}'));

void _expectTools(
  WidgetTester tester,
  ChartType type, {
  required bool visible,
}) {
  final bars = find.descendant(
    of: _stage(type),
    matching: find.byType(PreviewToolbar),
  );
  expect(bars, findsNWidgets(type.isCircular ? 1 : 2));
  for (final element in bars.evaluate()) {
    final fade = find
        .descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(AnimatedOpacity),
        )
        .first;
    expect(tester.widget<AnimatedOpacity>(fade).opacity, visible ? 1 : 0);
    expect(
      tester.renderObject<RenderAnimatedOpacity>(fade).opacity.value,
      visible ? 1 : 0,
    );
  }
}

ThemeData _theme(String appearance) => DesktopAppearance()
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

Widget _referenceSheet(
  BuildContext context,
  String appearance,
  List<ChartSource> sources,
) {
  final text = Theme.of(context).textTheme;
  final palette = PremiumThemeExtension.of(context);
  return RepaintBoundary(
    key: _reference,
    child: ColoredBox(
      color: palette.canvas,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Charts / ${appearance.toUpperCase()}',
              style: text.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'One table · Revenue and costs in USD · No background cards',
              style: text.bodySmall!.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < _types.length; index++) ...[
              if (index > 0) const SizedBox(height: 16),
              Text(
                ['Bar · idle', 'Line · idle', 'Donut · header hover'][index],
                style: text.bodySmall!.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 4),
              Expanded(
                flex: _types[index].isCircular ? 6 : 5,
                child: PreviewToolbarRegion(
                  child: ChartStage(
                    key: ValueKey('chart-${_types[index].name}'),
                    viewId: sources[index].viewId,
                    source: sources[index],
                    title: _title,
                    spec: _spec(_types[index]),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    onSpecChanged: (_) {},
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  List<ChartSource> sources,
) async {
  final theme = _theme(appearance);
  final defaults = AppFlowyDefaultTheme();
  Widget app(Widget body) => EasyLocalization(
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
                base: appearance == 'dark' ? defaults.dark() : defaults.light(),
                palette: theme.extension<PremiumThemeExtension>()!,
                brightness: theme.brightness,
              ),
              child: TooltipVisibility(visible: false, child: navigator!),
            ),
            home: Scaffold(body: body),
          ),
        ),
      );
  // Settle localization before mounting charts. The injected reads complete in
  // microtasks; pumpAndSettle advances the finite chart reveal on the fake clock.
  await tester.pumpWidget(app(const SizedBox.shrink()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    app(
      Builder(
        builder: (context) => _referenceSheet(context, appearance, sources),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
