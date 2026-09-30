import 'dart:math' as math;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_tables.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vimshottari.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Geometry with the bundled UI face, not the test font's square glyphs, so
// heights match what the dashboard card actually has to hold.
void main() {
  setUpAll(() async {
    final families = {
      for (final brightness in Brightness.values)
        for (final paper in [false, true])
          _theme(brightness, paper: paper).textTheme.bodyMedium?.fontFamily,
    }.whereType<String>();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  for (final (brightness, paper) in const [
    (Brightness.light, false),
    (Brightness.dark, false),
    (Brightness.light, true),
  ]) {
    // The template's half-width card on eight- and twelve-column canvases.
    for (final width in [681.0, 531.0]) {
      testWidgets(
        '${paper ? 'paper' : brightness.name} ${width.toInt()}: the default '
        'card holds the whole tree at every level unscrolled',
        (tester) async {
          // Twenty-nine comfortable dashboard rows (29 × 46 + 28 × 14) less
          // the card header (40) and body padding (2 × 6).
          final chart = _chart();
          final active = dashaAt(_periods(chart), _reading(chart));
          expect(active, hasLength(4));
          await _pump(
            tester,
            chart,
            Size(width, 1674),
            brightness: brightness,
            paper: paper,
          );
          for (var level = 0; level <= 4; level++) {
            final trail = active.take(level).toList();
            expect(_key('dasha-page-${_path(trail)}'), findsOneWidget);
            expect(
              _scroll(tester).position.maxScrollExtent,
              0,
              reason: 'Level $level must not need the card to scroll.',
            );
            if (level < 4) {
              await tester
                  .tap(_key('dasha-open-${_path(active.take(level + 1))}'));
              await tester.pumpAndSettle();
            }
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('rails join each opened period to its parent and every row',
      (tester) async {
    final chart = _chart();
    final active = dashaAt(_periods(chart), _reading(chart));
    await _pump(tester, chart, const Size(1100, 1134));
    for (var level = 1; level <= 3; level++) {
      await tester.tap(_key('dasha-open-${_path(active.take(level))}'));
      await tester.pumpAndSettle();
    }
    final trail = active.take(3).toList();
    final palette = AstrologyPalette.of(tester.element(_key('dasha-tree')));
    final pixel = await _pixels(tester);
    bool inked(Offset point) => _distance(pixel(point), palette.surface) > 0.08;

    // Opened ancestors step in under one another, each joined by an elbow.
    final cards = [
      tester.getRect(_key('dasha-path-card-0')),
      tester.getRect(_key('dasha-path-card-1')),
      tester.getRect(_key('dasha-overview')),
    ];
    for (var index = 1; index < cards.length; index++) {
      final step = cards[index].left - cards[index - 1].left;
      expect(step, greaterThan(20));
      final rail = cards[index - 1].left + step / 2;
      final gap = (cards[index - 1].bottom + cards[index].top) / 2;
      expect(inked(Offset(rail, gap)), isTrue, reason: 'rail above $index');
      expect(inked(Offset(rail - 6, gap)), isFalse);
    }

    // The selected period's nine rows hang one step deeper on its rail.
    final overview = cards.last;
    final rows = [
      for (final period in trail.last.children)
        (
          period: period,
          rect: tester.getRect(_key('dasha-card-${_path([...trail, period])}')),
        ),
    ];
    final step = rows.first.rect.left - overview.left;
    expect(step, closeTo(cards[1].left - cards[0].left, 0.01));
    final rail = overview.left + step / 2;
    final rowAnchor = 10 + (15 * 1.45 + 2 + 11.5 * 1.45) / 2;
    for (final (index, row) in rows.indexed) {
      final elbow = row.rect.top + rowAnchor;
      expect(
        inked(Offset(row.rect.left - 3, elbow)),
        isTrue,
        reason: '${row.period.lord.label} elbow',
      );
      expect(inked(Offset(row.rect.left - 3, row.rect.top + 4)), isFalse);
      if (index > 0) {
        final gap = (rows[index - 1].rect.bottom + row.rect.top) / 2;
        expect(inked(Offset(rail, gap)), isTrue, reason: 'rail at $index');
      }
    }
    // Nothing continues below the last row's elbow.
    final last = rows.last.rect;
    expect(inked(Offset(rail, last.bottom - 4)), isFalse);

    // The running period's elbow and edge track wear its own color.
    final running = rows.singleWhere(
      (row) => row.period.contains(_reading(chart)),
    );
    final planet = palette.planetTone(running.period.lord).mark;
    final rail0 =
        palette.planetTone(trail.last.lord).mark.withValues(alpha: 0.45);
    final elbow =
        pixel(Offset(running.rect.left - 3, running.rect.top + rowAnchor));
    expect(
      _distance(elbow, planet),
      lessThan(_distance(elbow, Color.alphaBlend(rail0, palette.surface))),
    );
    expect(
      _distance(
        pixel(running.rect.bottomLeft + const Offset(16, -1.5)),
        planet,
      ),
      lessThan(0.12),
    );
    expect(
      tester
          .widget<Text>(
            _key('dasha-progress-${_path([...trail, running.period])}'),
          )
          .data,
      matches(RegExp(r'^\d{1,3}% elapsed$')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('right-to-left trees indent and draw from the right',
      (tester) async {
    final chart = _chart();
    final active = dashaAt(_periods(chart), _reading(chart));
    await _pump(
      tester,
      chart,
      const Size(1100, 1134),
      direction: TextDirection.rtl,
    );
    for (var level = 1; level <= 2; level++) {
      await tester.tap(_key('dasha-open-${_path(active.take(level))}'));
      await tester.pumpAndSettle();
    }
    final trail = active.take(2).toList();
    final ancestor = tester.getRect(_key('dasha-path-card-0'));
    final overview = tester.getRect(_key('dasha-overview'));
    final row = tester.getRect(
      _key('dasha-card-${_path([...trail, trail.last.children.first])}'),
    );
    expect(overview.right, lessThan(ancestor.right));
    expect(row.right, lessThan(overview.right));
    expect(ancestor.left, closeTo(overview.left, 0.01));
    final palette = AstrologyPalette.of(tester.element(_key('dasha-tree')));
    final pixel = await _pixels(tester);
    final step = overview.right - row.right;
    final gap = (overview.bottom + row.top) / 2;
    expect(
      _distance(pixel(Offset(overview.right - step / 2, gap)), palette.surface),
      greaterThan(0.04),
    );
    expect(tester.takeException(), isNull);
  });

  for (final (brightness, paper) in const [
    (Brightness.light, false),
    (Brightness.dark, false),
    (Brightness.light, true),
  ]) {
    final name = paper ? 'paper' : brightness.name;

    testWidgets('$name: cards draw no outline, only their own tone',
        (tester) async {
      final chart = _chart();
      final active = dashaAt(_periods(chart), _reading(chart));
      await _pump(
        tester,
        chart,
        const Size(1100, 1134),
        brightness: brightness,
        paper: paper,
      );
      for (var level = 1; level <= 3; level++) {
        await tester.tap(_key('dasha-open-${_path(active.take(level))}'));
        await tester.pumpAndSettle();
      }
      final trail = active.take(3).toList();
      for (final period in trail.last.children) {
        final path = _path([...trail, period]);
        final fill = tester
            .widget<AnimatedContainer>(_key('dasha-card-fill-$path'))
            .decoration! as BoxDecoration;
        expect(fill.border, isNull);
        final shape = tester.widget<Material>(_key('dasha-card-$path')).shape!;
        expect((shape as RoundedRectangleBorder).side, BorderSide.none);
      }
      final pixel = await _pixels(tester);
      for (final card in [
        _key('dasha-path-card-0'),
        _key('dasha-path-card-1'),
        _key('dasha-overview'),
        for (final period in trail.last.children)
          _key('dasha-card-${_path([...trail, period])}'),
      ]) {
        final rect = tester.getRect(card);
        // An outline would set the outermost pixels apart from just inside.
        for (final (edge, inside) in [
          (
            Offset(rect.left + 0.5, rect.center.dy),
            Offset(rect.left + 4.5, rect.center.dy),
          ),
          (
            Offset(rect.right - 0.5, rect.center.dy),
            Offset(rect.right - 4.5, rect.center.dy),
          ),
          (
            Offset(rect.center.dx, rect.top + 0.5),
            Offset(rect.center.dx, rect.top + 4.5),
          ),
        ]) {
          expect(
            _distance(pixel(edge), pixel(inside)),
            lessThan(0.03),
            reason: '$card at $edge',
          );
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: every lord has a distinct, gentle tone',
        (tester) async {
      await _pump(
        tester,
        _chart(),
        const Size(600, 400),
        brightness: brightness,
        paper: paper,
      );
      final palette = AstrologyPalette.of(tester.element(_key('dasha-tree')));
      final hues = <double>[];
      for (final body in VedicBody.values) {
        final tone = palette.planetTone(body);
        for (final background in [
          palette.surface,
          tone.wash,
          tone.fill,
          tone.fillStrong,
          tone.chip,
        ]) {
          expect(
            _contrast(tone.ink, background),
            greaterThanOrEqualTo(4.5),
            reason: '${body.label} ink',
          );
        }
        expect(
          _contrast(tone.onMark, tone.mark),
          greaterThanOrEqualTo(4.2),
          reason: '${body.label} badge',
        );
        expect(tone.fill.a, 1);
        // A tint of the page, not a saturated block.
        expect(
          _distance(tone.fill, palette.surface),
          lessThan(0.2),
          reason: '${body.label} fill',
        );
        final mark = HSLColor.fromColor(tone.mark);
        if (body != VedicBody.moon) {
          expect(
            mark.saturation,
            inInclusiveRange(0.35, 0.6),
            reason: body.label,
          );
        }
        hues.add(mark.hue);
      }
      for (var i = 0; i < hues.length; i++) {
        for (var j = i + 1; j < hues.length; j++) {
          final apart = (hues[i] - hues[j]).abs();
          expect(math.min(apart, 360 - apart), greaterThanOrEqualTo(16));
        }
      }
    });
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

String _path(Iterable<DashaPeriod> trail) =>
    trail.isEmpty ? 'root' : trail.map((period) => period.lord.name).join('-');

ScrollController _scroll(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(_key('astrology-dasha-scroll'))
    .controller!;

double _distance(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// Reads the rendered card, so the tree's lines are checked where they are
/// actually painted rather than trusted from their painter's inputs.
Future<Color Function(Offset global)> _pixels(WidgetTester tester) async {
  final boundary = _key('capture');
  final origin = tester.getTopLeft(boundary);
  late final ByteData data;
  late final int width;
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(boundary));
    width = image.width;
    data = (await image.toByteData())!;
    image.dispose();
  });
  return (global) {
    final local = global - origin;
    final index = (local.dy.floor() * width + local.dx.floor()) * 4;
    return Color.fromARGB(
      data.getUint8(index + 3),
      data.getUint8(index),
      data.getUint8(index + 1),
      data.getUint8(index + 2),
    );
  };
}

ThemeData _theme(Brightness brightness, {bool paper = false}) =>
    DesktopAppearance().getThemeData(
      paper
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      brightness,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

Future<void> _pump(
  WidgetTester tester,
  AstrologyChart chart,
  Size size, {
  Brightness brightness = Brightness.light,
  bool paper = false,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(size.width + 40, size.height + 40);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: _theme(brightness, paper: paper),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: Directionality(
              textDirection: direction,
              child: SizedBox.fromSize(
                size: size,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AstrologyDashaTable(
                        chart: chart,
                        at: _reading(chart),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Deep inside the cycle, so all four running periods are real rows.
DateTime _reading(AstrologyChart chart) =>
    chart.utc.add(const Duration(days: 360 * 31 + 17));

List<DashaPeriod> _periods(AstrologyChart chart) => vimshottariPeriods(
      birthUtc: chart.utc,
      moonLongitude: chart.planet(VedicBody.moon).longitude,
      yearDays: chart.input.dashaYearDays,
    );

// Hand-authored: no engine, ephemeris, location service or network.
AstrologyChart _chart() {
  final utc = DateTime.utc(2000, 1, 2, 6, 15, 30);
  final input = AstrologyInput(
    name: 'Fabricated chart',
    utc: utc,
    place: const AstrologyPlace(
      name: 'Fixture city',
      latitude: 12.98,
      longitude: 77.58,
      timeZone: 'Asia/Kolkata',
    ),
    utcOffsetMinutes: 330,
    dashaYearDays: 360,
  )..validate();
  final midnight = DateTime.utc(utc.year, utc.month, utc.day);
  final sunrise = midnight.add(const Duration(minutes: 42, seconds: 11));
  const longitudes = [
    10.0,
    20.0,
    96.0,
    151.0,
    215.0,
    278.0,
    305.0,
    345.0,
    165.0,
  ];
  return AstrologyChart(
    input: input,
    utc: utc,
    julianDay:
        2440587.5 + utc.millisecondsSinceEpoch / Duration.millisecondsPerDay,
    ayanamsaDegrees: 23.85675,
    ascendant: 33,
    midheaven: 301,
    planets: [
      for (final body in VedicBody.values)
        VedicPlacement(
          name: body.label,
          shortName: body.shortName,
          body: body,
          longitude: longitudes[body.index],
        ),
    ],
    specialLagnas: const [],
    sunrise: sunrise,
    sunset: midnight.add(const Duration(hours: 12, minutes: 31)),
    nextSunrise: sunrise.add(const Duration(days: 1)),
    weekday: 0,
    localMeanHours: 12,
  );
}
