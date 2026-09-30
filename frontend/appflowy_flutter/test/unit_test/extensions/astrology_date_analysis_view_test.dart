import 'package:appflowy/extensions/dart/built_in/astrology/astrology_date_analysis.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_date_analysis_view.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_panchanga.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Hand-authored charts only: no engine, location service or network.
const _place = AstrologyPlace(
  name: 'Bengaluru',
  latitude: 12.98,
  longitude: 77.58,
  timeZone: 'Asia/Kolkata',
);

final _natal = AstrologyInput(
  name: 'Reference',
  utc: DateTime.utc(1999, 12, 18, 9, 45),
  place: _place,
);

AstrologyChart _chart(AstrologyInput input, {double moon = 20}) {
  final utc = input.utc!;
  final midnight = DateTime.utc(utc.year, utc.month, utc.day);
  final sunrise = midnight.add(const Duration(minutes: 30));
  final longitudes = [
    10.0,
    moon,
    96.0,
    151.0,
    215.0,
    278.0,
    345.0,
    125.0,
    305.0
  ];
  const speeds = [0.98, 13.2, 0.4, -0.65, 0.08, 1.1, 0.02, -0.05, -0.05];
  return AstrologyChart(
    input: input,
    utc: utc,
    julianDay:
        2440587.5 + utc.millisecondsSinceEpoch / Duration.millisecondsPerDay,
    ayanamsaDegrees: 23.85,
    ascendant: 33,
    midheaven: 300,
    planets: [
      for (final body in VedicBody.values)
        VedicPlacement(
          name: body.label,
          shortName: body.shortName,
          body: body,
          longitude: longitudes[body.index],
          speed: speeds[body.index],
        ),
    ],
    specialLagnas: const [],
    sunrise: sunrise,
    sunset: sunrise.add(const Duration(hours: 12)),
    nextSunrise: sunrise.add(const Duration(days: 1)),
    weekday: 1,
    localMeanHours: 12,
  );
}

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool paper = false,
}) =>
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
        brightness: brightness,
        extensions: [PaperThemeExtension(enabled: paper)],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 900, height: 1400, child: child),
        ),
      ),
    );

void main() {
  final requests = <AstrologyInput>[];
  final natalChart = _chart(_natal);

  Future<AstrologyDateAnalysis> analyzer(
    AstrologyInput natal,
    AstrologyInput moment,
  ) async {
    requests.add(moment);
    final chart = _chart(moment, moon: 200);
    return analyzeAstrologyDate(
      moment: chart,
      natal: natalChart,
      times: AstrologyPanchangaTimes(
        tithiEnd: moment.utc!.add(const Duration(hours: 5)),
        nakshatraEnd: moment.utc!.add(const Duration(hours: 9)),
        yogaEnd: moment.utc!.add(const Duration(hours: 20)),
        karanaEnd: moment.utc!.add(const Duration(hours: 2)),
        previousSunset: chart.sunrise!.subtract(const Duration(hours: 12)),
      ),
    );
  }

  setUp(requests.clear);

  for (final (name, brightness, paper) in [
    ('light', Brightness.light, false),
    ('dark', Brightness.dark, false),
    ('paper', Brightness.light, true),
  ]) {
    testWidgets('every section renders on the $name surface', (tester) async {
      await tester.pumpWidget(
        _app(
          AstrologyDateAnalysisView(
            natal: _natal,
            analyzer: analyzer,
            clock: () => DateTime.utc(2026, 9, 28, 6, 30, 45),
          ),
          brightness: brightness,
          paper: paper,
        ),
      );
      await tester.pump();

      // "Now" at the birthplace, whole minutes, with the natal settings.
      expect(requests, hasLength(1));
      expect(requests.single.utc, DateTime.utc(2026, 9, 28, 6, 30));
      expect(requests.single.place, same(_place));
      expect(requests.single.ayanamsa, _natal.ayanamsa);

      for (final heading in [
        'Natal dasha on this date',
        'Transits',
        'Panchanga',
        'Muhurta',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      expect(
        find.text('Monday, 2026-09-28 · 12:00 UTC+05:30 · Bengaluru'),
        findsOneWidget,
      );
      for (final level in [
        'Mahadasha',
        'Antardasha',
        'Pratyantardasha',
        'Sookshma dasha',
      ]) {
        expect(find.text(level), findsOneWidget, reason: level);
      }
      expect(find.text('Rahu Kalam'), findsOneWidget);
      expect(find.text('Brahma muhurta'), findsOneWidget);
      expect(find.text('Tara bala'), findsOneWidget);
      expect(find.text('Chandra bala'), findsOneWidget);
      expect(find.textContaining('Sade Sati'), findsOneWidget);
      expect(find.text('Saturn'), findsWidgets);

      final context = tester.element(
        find.byKey(const ValueKey('astrology-date-analysis-surface')),
      );
      final palette = AstrologyPalette.of(context);
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('astrology-date-analysis-surface')),
            )
            .color,
        palette.surface,
      );
      if (paper) {
        expect(PaperTheme.isEnabled(context), isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('date only means noon at the chosen place', (tester) async {
    await tester.pumpWidget(
      _app(
        AstrologyDateAnalysisView(
          natal: _natal,
          analyzer: analyzer,
          clock: () => DateTime.utc(2026, 9, 28, 1, 5),
        ),
      ),
    );
    await tester.pump();
    expect(requests.single.utc, DateTime.utc(2026, 9, 28, 1, 5));

    await tester.tap(
      find.byKey(const ValueKey('astrology-date-analysis-noon')),
    );
    await tester.pump();
    await tester.pump();
    // 12:00 IST on the same local date.
    expect(requests.last.utc, DateTime.utc(2026, 9, 28, 6, 30));
    expect(find.textContaining('noon is used'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('astrology-date-analysis-now')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('astrology-date-analysis-now')));
    await tester.pump();
    await tester.pump();
    expect(requests.last.utc, DateTime.utc(2026, 9, 28, 1, 5));
  });

  testWidgets('another place waits for a choice instead of guessing',
      (tester) async {
    await tester.pumpWidget(
      _app(
        AstrologyDateAnalysisView(
          natal: _natal,
          analyzer: analyzer,
          clock: () => DateTime.utc(2026, 9, 28, 6, 30),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('astrology-date-analysis-place')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Another place…').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('astrology-date-analysis-place-search')),
      findsOneWidget,
    );
    expect(requests, hasLength(1), reason: 'No analysis without a place.');
  });

  testWidgets('without birth details only the date itself is analysed',
      (tester) async {
    await tester.pumpWidget(
      _app(
        AstrologyDateAnalysisView(
          natal: const AstrologyInput(place: _place),
          analyzer: (natal, moment) async => analyzeAstrologyDate(
            moment: _chart(moment),
          ),
          clock: () => DateTime.utc(2026, 9, 28, 6, 30),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Save a birth date'), findsOneWidget);
    expect(find.text('From Lagna'), findsNothing);
    expect(find.text('Panchanga'), findsOneWidget);
  });

  testWidgets('previews never calculate', (tester) async {
    await tester.pumpWidget(
      _app(
        AstrologyDateAnalysisView(
          natal: _natal,
          preview: true,
          analyzer: analyzer,
        ),
      ),
    );
    await tester.pump();
    expect(requests, isEmpty);
    expect(find.textContaining('No location is requested'), findsOneWidget);
  });
}
