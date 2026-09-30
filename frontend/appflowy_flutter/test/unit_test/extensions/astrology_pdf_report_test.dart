import 'dart:convert';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_pdf_report.dart';
import 'package:flutter_test/flutter_test.dart';

// A hand-authored chart: no ephemeris or native library is needed.
const _place = AstrologyPlace(
  name: 'Bengaluru, Karnataka, India',
  latitude: 12.9716,
  longitude: 77.5946,
  timeZone: 'Asia/Kolkata',
);
const _specialLagnas = [
  VedicPlacement(name: 'Bhava Lagna', shortName: 'BL', longitude: 45.125),
  VedicPlacement(name: 'Hora Lagna', shortName: 'HL', longitude: 93.25),
  VedicPlacement(name: 'Ghati Lagna', shortName: 'GL', longitude: 140.5),
  VedicPlacement(name: 'Gulika', shortName: 'Gk', longitude: 230.75),
  VedicPlacement(name: 'Maandi', shortName: 'Md', longitude: 231.75),
  VedicPlacement(name: 'Sri Lagna', shortName: 'SL', longitude: 315.5),
];

AstrologyChart _chart(IndianChartStyle style, {String name = 'Test'}) {
  final utc = DateTime.utc(1999, 12, 18, 9, 45);
  const longitudes = [
    242.5,
    330.25,
    300.75,
    228.1,
    1.5,
    205.3,
    14.2,
    98.6,
    278.6,
  ];
  const speeds = [1.01, 12.8, 0.72, -0.4, -0.02, 1.2, -0.05, -0.05, -0.05];
  final sunrise = DateTime.utc(1999, 12, 18, 0, 55);
  return AstrologyChart(
    input: AstrologyInput(
      name: name,
      utc: utc,
      place: _place,
      style: style,
    ),
    utc: utc,
    julianDay: 2451530.90625,
    ayanamsaDegrees: 23.8526,
    ascendant: 13.4,
    midheaven: 284,
    planets: [
      for (final body in VedicBody.values)
        VedicPlacement(
          name: body.label,
          shortName: body.shortName,
          body: body,
          longitude: longitudes[body.index],
          speed: speeds[body.index],
          latitude: body.index * 0.1,
          declination: (body.index - 3) * 2.0,
        ),
    ],
    specialLagnas: _specialLagnas,
    sunrise: sunrise,
    sunset: DateTime.utc(1999, 12, 18, 12, 20),
    nextSunrise: sunrise.add(const Duration(days: 1)),
    weekday: 6,
    localMeanHours: 15.2,
    ephemerisVersion: '2.10.03',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the full report builds with the bundled fonts in both styles',
      () async {
    final fonts = await AstrologyPdfFonts.load();
    for (final style in IndianChartStyle.values) {
      final bytes = await buildAstrologyPdf(
        chart: _chart(style, name: 'Reference · जन्म'),
        fonts: fonts,
        generatedAt: DateTime.utc(2026, 9, 28, 6, 30),
      );
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-', reason: style.name);
      // Charts, positions, vargas, 81 antardashas, Shadbala and Ashtakavarga
      // span several pages; the embedded fonts are subsets.
      expect(bytes.length, greaterThan(20000), reason: style.name);
      expect(bytes.length, lessThan(2000000), reason: style.name);
      final tail = latin1.decode(bytes.sublist(bytes.length - 64));
      expect(tail, contains('%%EOF'));
    }
  });

  test('polar charts without solar events still produce a report', () async {
    final fonts = await AstrologyPdfFonts.load();
    final chart = _chart(IndianChartStyle.north);
    final polar = AstrologyChart(
      input: chart.input,
      utc: chart.utc,
      julianDay: chart.julianDay,
      ayanamsaDegrees: chart.ayanamsaDegrees,
      ascendant: chart.ascendant,
      midheaven: chart.midheaven,
      planets: chart.planets,
      specialLagnas: const [],
      sunrise: null,
      sunset: null,
      nextSunrise: null,
      weekday: chart.weekday,
      localMeanHours: chart.localMeanHours,
    );
    final bytes = await buildAstrologyPdf(chart: polar, fonts: fonts);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
