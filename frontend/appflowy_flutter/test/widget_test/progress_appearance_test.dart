import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/shared/progress_bar.dart';
import 'package:appflowy/shared/slides/slide_property_view.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _modes = ['light', 'dark', 'paper'];
const _progress = PropertyStyle(kind: PropertyStyleKind.progress);
const _fraction = 0.549206349206349;
const _defaultFills = {
  'light': Color(0xFF43955A),
  'dark': Color(0xFF71C68B),
  'paper': Color(0xFF588C42),
};
// The old paper fill is the regression baseline for washed-out green.
const _legacyPaleFill = Color(0xFFA8C992);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final families = _modes
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  for (final sample in {
    '54.183636': '54',
    '54.9206349206349': '55',
    '99.9%': '100%',
    ' 54.5 % ': '55%',
    '3/8': '3/8',
    '2.55 / 8': '3/8',
    '1,234.6': '1235',
    '-0.2': '0',
    '1e308': '1e+308',
    '': '',
    'not started': 'not started',
    'NaN': 'NaN',
    'Infinity': 'Infinity',
  }.entries) {
    test('progress label ${sample.key} reads as ${sample.value}', () {
      expect(progressDisplayLabel(sample.key), sample.value);
    });
  }

  for (final mode in _modes) {
    for (final compact in [false, true]) {
      testWidgets('$mode: mailbox/card labels round without changing the value',
          (tester) async {
        const property = TableProperty(
          fieldId: 'progress',
          name: 'Progress',
          value: '54.9206349206349',
          kind: TablePropertyKind.progress,
          fraction: _fraction,
        );
        await tester.pumpWidget(
          _app(
            mode,
            SizedBox(
              width: compact ? 110 : 220,
              child: Builder(
                builder: (context) => TablePropertyView(
                  property: property,
                  palette: tableViewPaletteOf(context),
                  compact: compact,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('55'), findsOneWidget);
        expect(find.text(property.value), findsNothing);
        final bar = tester.widget<AppFlowyProgressBar>(
          find.byType(AppFlowyProgressBar),
        );
        final colors = ProgressBarColors.of(
          tester.element(find.byType(TablePropertyView)),
        );
        expect(bar.fraction, _fraction);
        expect(bar.fill, colors.fill);
        expect(bar.highlight, colors.highlight);
        expect(bar.track, colors.track);
        _expectVisibleDefaultProgress(bar, mode);
        expect(property.value, '54.9206349206349');
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.value == '55',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$mode: Slide uses the same rounded green progress',
        (tester) async {
      const property = SlideProperty(
        fieldId: 'progress',
        name: 'Progress',
        value: '54.9206349206349',
        kind: SlidePropertyKind.progress,
        fraction: _fraction,
      );
      await tester.pumpWidget(
        _app(
          mode,
          SizedBox(
            width: 220,
            child: Builder(
              builder: (context) => SlidePropertyView(
                property: property,
                palette: slidePaletteOf(context),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('55'), findsOneWidget);
      expect(find.text(property.value), findsNothing);
      final bar = tester.widget<AppFlowyProgressBar>(
        find.byType(AppFlowyProgressBar),
      );
      final colors = ProgressBarColors.of(
        tester.element(find.byType(SlidePropertyView)),
      );
      expect(bar.fraction, _fraction);
      expect(bar.fill, colors.fill);
      expect(bar.highlight, colors.highlight);
      expect(bar.track, colors.track);
      _expectVisibleDefaultProgress(bar, mode);
      expect(property.value, '54.9206349206349');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$mode: integer percentages retain fractional edit precision',
        (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        _app(
          mode,
          SizedBox(
            width: 240,
            child: PropertyValueControl(
              style: _progress.withSetting('step', 0.25),
              value: '54.183636',
              onChanged: changes.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('54%'), findsOneWidget);
      expect(changes, isEmpty);
      final barFinder = find.byType(AppFlowyProgressBar);
      _expectVisibleDefaultProgress(
        tester.widget<AppFlowyProgressBar>(barFinder),
        mode,
      );
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(changes, ['54.433636']);
      expect(find.text('54%'), findsOneWidget);
      expect(tester.takeException(), isNull);

      for (final value in ['0', '54', '100']) {
        await tester.pumpWidget(
          _app(
            mode,
            SizedBox(
              width: 240,
              child: PropertyValueControl(
                key: ValueKey('default-progress-$value'),
                style: _progress,
                value: value,
                onChanged: changes.add,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bar = tester.widget<AppFlowyProgressBar>(barFinder);
        final fraction = double.parse(value) / 100;
        expect(bar.fraction, fraction);
        expect(find.text('$value%'), findsOneWidget);
        _expectVisibleDefaultProgress(bar, mode);
        final paint = find.descendant(
          of: barFinder,
          matching: find.byType(CustomPaint),
        );
        expect(
          paint,
          paintsExactlyCountTimes(#drawRRect, fraction == 0 ? 1 : 2),
        );
        final painted = paints..rrect(color: bar.track);
        if (fraction > 0) {
          final size = tester.getSize(paint);
          painted.rrect(
            rrect: RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, size.width * fraction, size.height),
              Radius.circular(size.height / 2),
            ),
          );
        }
        expect(paint, painted);
        expect(changes, ['54.433636']);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('rounding does not affect ordinary numeric fields',
      (tester) async {
    await tester.pumpWidget(
      _app(
        'paper',
        Builder(
          builder: (context) => TablePropertyView(
            property: const TableProperty(
              fieldId: 'price',
              name: 'Price',
              value: '54.183636',
              kind: TablePropertyKind.number,
            ),
            palette: tableViewPaletteOf(context),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('54.183636'), findsOneWidget);
    expect(find.byType(AppFlowyProgressBar), findsNothing);
  });

  testWidgets('explicit progress accents remain customisable', (tester) async {
    await tester.pumpWidget(
      _app(
        'light',
        SizedBox(
          width: 240,
          child: PropertyValueControl(
            style: _progress.withSetting('accent', 'blue'),
            value: '40',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = tester.widget<AppFlowyProgressBar>(
      find.byType(AppFlowyProgressBar),
    );
    expect(bar.fill.b, greaterThan(bar.fill.g));
    expect(bar.fill.computeLuminance(), greaterThan(0.25));
  });

  testWidgets('progress visual reference in light, dark and paper',
      (tester) async {
    tester.view.physicalSize = const Size(1020, 660);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const canvas = ValueKey('progress-reference');
    await tester.pumpWidget(
      _app(
        'light',
        RepaintBoundary(
          key: canvas,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final mode in _modes)
                Expanded(
                  child: Theme(
                    data: _theme(mode),
                    child: Builder(
                      builder: (context) => _referenceColumn(context, mode),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(canvas),
      matchesGoldenFile('goldens/progress_controls.png'),
    );
  });
}

void _expectVisibleDefaultProgress(AppFlowyProgressBar bar, String mode) {
  expect(bar.fill, _defaultFills[mode]);
  expect(bar.fill.g, greaterThan(bar.fill.r));
  expect(bar.fill.g, greaterThan(bar.fill.b));
  expect(
    bar.fill.computeLuminance(),
    lessThan(_legacyPaleFill.computeLuminance()),
    reason: '$mode: default green must be deeper than the legacy pale fill',
  );
  expect(bar.highlight, isNotNull);
  expect(bar.track.a, 1.0);
  for (final color in {
    'fill': bar.fill,
    'highlight': bar.highlight!,
  }.entries) {
    expect(
      _contrastRatio(color.value, bar.track),
      greaterThanOrEqualTo(3.0),
      reason: '$mode ${color.key} must have at least 3:1 contrast '
          'against its actual track',
    );
  }
  if (mode != 'dark') {
    expect(
      _contrastRatio(bar.fill, bar.track),
      greaterThan(_contrastRatio(_legacyPaleFill, bar.track)),
      reason: '$mode: the new fill must improve contrast over the pale fill',
    );
  }
}

double _contrastRatio(Color foreground, Color track) {
  final luminance = Color.alphaBlend(foreground, track).computeLuminance();
  final trackLuminance = track.computeLuminance();
  return luminance > trackLuminance
      ? (luminance + 0.05) / (trackLuminance + 0.05)
      : (trackLuminance + 0.05) / (luminance + 0.05);
}

Widget _referenceColumn(BuildContext context, String mode) {
  final palette = tableViewPaletteOf(context);
  Widget caption(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: palette.textMuted),
        ),
      );
  return Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${mode[0].toUpperCase()}${mode.substring(1)}',
            style: TextStyle(fontSize: 20, color: palette.textPrimary),
          ),
          const SizedBox(height: 28),
          caption('Interactive progress'),
          for (final value in ['0', '54.9206349206349', '100']) ...[
            PropertyValueControl(
              style: _progress,
              value: value,
              onChanged: (_) {},
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          caption('Without step buttons'),
          PropertyValueControl(
            style: _progress.withSetting('show_buttons', false),
            value: '32',
            onChanged: (_) {},
          ),
          const SizedBox(height: 32),
          caption('Mailbox / cards'),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: TablePropertyView(
              property: const TableProperty(
                fieldId: 'progress',
                name: 'Progress',
                value: '54.9206349206349',
                kind: TablePropertyKind.progress,
                fraction: _fraction,
              ),
              palette: palette,
            ),
          ),
        ],
      ),
    ),
  );
}

ThemeData _theme(String mode) => DesktopAppearance().getThemeData(
      mode == 'paper'
          ? AppTheme.builtins.firstWhere(
              (theme) => theme.themeName == BuiltInTheme.paper,
            )
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );

Widget _app(String mode, Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: _theme(mode),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: child),
        ),
      ),
    );
