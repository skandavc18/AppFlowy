import 'dart:io';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_engine.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_time.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/shadbala.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweph/sweph.dart';

const _bengaluru = AstrologyPlace(
  name: 'Bengaluru',
  latitude: 12 + 59 / 60,
  longitude: 77 + 35 / 60,
  timeZone: 'Asia/Kolkata',
);
const _newYork = AstrologyPlace(
  name: 'New York',
  latitude: 40.71,
  longitude: -74.01,
  timeZone: 'America/New_York',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('birth wall clock resolves independently of this computer', () {
    expect(
      AstrologyTime.parseBirthTime(
        date: '2026-09-11',
        time: '19:16:15',
        place: _bengaluru,
      ),
      DateTime.utc(2026, 9, 11, 13, 46, 15),
    );
    expect(
      () => AstrologyTime.parseBirthTime(
        date: '2026-02-30',
        time: '12:00',
        place: _bengaluru,
      ),
      throwsFormatException,
    );
    expect(
      () => AstrologyTime.parseBirthTime(
        date: '2026-02-28',
        time: '24:01',
        place: _bengaluru,
      ),
      throwsFormatException,
    );
    expect(AstrologyTime.parseOffset('+05:45'), 345);
    expect(AstrologyTime.parseOffset('−03:30'), -210);
    expect(() => AstrologyTime.parseOffset('05:60'), throwsFormatException);
  });

  test('DST skipped and repeated times require explicit handling', () {
    expect(
      () => AstrologyTime.parseBirthTime(
        date: '2024-03-10',
        time: '02:30',
        place: _newYork,
      ),
      throwsFormatException,
    );
    expect(
      () => AstrologyTime.parseBirthTime(
        date: '2024-11-03',
        time: '01:30',
        place: _newYork,
      ),
      throwsFormatException,
    );
    final first = AstrologyTime.parseBirthTime(
      date: '2024-11-03',
      time: '01:30',
      place: _newYork,
      offsetMinutes: -240,
    );
    final second = AstrologyTime.parseBirthTime(
      date: '2024-11-03',
      time: '01:30',
      place: _newYork,
      offsetMinutes: -300,
    );
    expect(second.difference(first), const Duration(hours: 1));
    expect(first, DateTime.utc(2024, 11, 3, 5, 30));
  });

  test('all aspect segments including 330–360 degrees remain bounded', () {
    for (final body in VedicBody.classical) {
      for (var angle = -720; angle <= 720; angle++) {
        expect(grahaDrishti(body, angle.toDouble()), inInclusiveRange(0, 60));
      }
      expect(grahaDrishti(body, 350), 0);
      expect(grahaDrishti(body, 180), 60);
    }
    expect(grahaDrishti(VedicBody.mars, 90), 60);
    expect(grahaDrishti(VedicBody.jupiter, 120), 60);
    expect(grahaDrishti(VedicBody.saturn, 270), 60);
    expect(normalizeDegrees(-1e-16), 0);
  });

  test('exaltation strength stays in real virupas', () {
    const exalted = [10.0, 33.0, 298.0, 165.0, 95.0, 357.0, 200.0];
    for (final body in VedicBody.classical) {
      expect(uchchaBala(body, exalted[body.index]), 60);
      expect(uchchaBala(body, exalted[body.index] + 180), 0);
    }
  });

  final library = [
    const String.fromEnvironment('ASTROLOGY_TEST_LIBRARY'),
    'build/astrology_ephemeris/Release/sweph.dll',
    'build/windows/x64/runner/Debug/sweph.dll',
  ].where((path) => path.isNotEmpty && File(path).existsSync()).firstOrNull;

  group(
    'bundled Swiss Ephemeris',
    () {
      final engine = AstrologyEngine();
      late Directory directory;
      setUpAll(() async {
        directory =
            await Directory.systemTemp.createTemp('appflowy-astrology-');
        await engine.initialize(
          modulePath: File(library!).absolute.path,
          ephemerisDirectory: directory.path,
        );
      });
      tearDownAll(() async {
        Sweph.swe_close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      test('reference screenshot longitudes and divisional signs', () async {
        final chart = await engine.calculate(
          AstrologyInput(
            utc: DateTime.utc(2026, 9, 11, 13, 46, 15),
            place: _bengaluru,
          ),
        );
        // The screenshot does not expose its ayanamsa choice. The 0.1-degree
        // tolerance compares ephemerides, not claims of exact JHora settings.
        const expected = [
          144.6233611,
          150.0764361,
          85.790525,
          157.2835694,
          111.6536667,
          186.5659639,
          348.7859833,
          304.5115583,
          124.5115583,
        ];
        for (final body in VedicBody.values) {
          final actual = chart.planet(body).longitude;
          expect(
            angularDistance(actual, expected[body.index]),
            lessThan(0.1),
            reason: body.label,
          );
        }
        expect(angularDistance(chart.ascendant, 341.5101861), lessThan(0.1));
        expect(zodiacSign(chart.ascendant), 11);
        expect(divisionalSign(chart.ascendant, 9), 6);
        expect(chart.tithi, 1);
        expect(chart.planet(VedicBody.moon).nakshatra, 'Uttara Phalguni');
        expect(chart.specialLagnas, hasLength(6));
        expect(chart.ephemerisVersion, startsWith('2.10'));
        final strengths = calculateShadbala(chart);
        expect(strengths, hasLength(7));
        for (final row in strengths) {
          expect(row.total!.isFinite, isTrue);
          expect(
            row.total,
            closeTo(
              row.sthana +
                  row.dig +
                  row.kala! +
                  row.cheshta +
                  row.naisargika +
                  row.drik,
              1e-8,
            ),
          );
        }
        expect(strengths.first.naisargika, 60);
        expect(strengths.last.naisargika, 8.57);
      });

      test('nodes are opposite and mean versus true is configurable', () async {
        final utc = DateTime.utc(2026, 9, 11, 13, 46, 15);
        final mean = await engine.calculate(
          AstrologyInput(utc: utc, place: _bengaluru),
        );
        final trueNode = await engine.calculate(
          AstrologyInput(utc: utc, place: _bengaluru, trueNode: true),
        );
        expect(
          angularDistance(
            mean.planet(VedicBody.rahu).longitude,
            mean.planet(VedicBody.ketu).longitude,
          ),
          closeTo(180, 1e-9),
        );
        expect(
          angularDistance(
            mean.planet(VedicBody.rahu).longitude,
            trueNode.planet(VedicBody.rahu).longitude,
          ),
          greaterThan(0.001),
        );
      });

      test('pre-dawn is part of the previous Vedic day', () async {
        final chart = await engine.calculate(
          AstrologyInput(
            utc: DateTime.utc(2026, 9, 10, 22, 30),
            place: _bengaluru,
          ),
        );
        expect(chart.sunrise!.isBefore(chart.utc), isTrue);
        expect(chart.nextSunrise!.isAfter(chart.utc), isTrue);
        expect(chart.weekday, 4);
        expect(AstrologyTime.localTime(chart.input, chart.sunrise!).day, 10);
      });

      test(
        'polar day never receives fabricated sunrise lagnas or total strength',
        () async {
          final chart = await engine.calculate(
            AstrologyInput(
              utc: DateTime.utc(2026, 6, 21, 12),
              place: const AstrologyPlace(
                name: 'Tromsø',
                latitude: 69.65,
                longitude: 18.96,
                timeZone: 'Europe/Oslo',
              ),
            ),
          );
          expect(chart.sunrise, isNull);
          expect(chart.warnings, isNotEmpty);
          expect(chart.specialLagnas.map((point) => point.shortName), ['SL']);
          expect(
            calculateShadbala(chart).every((row) => row.total == null),
            isTrue,
          );
        },
      );
    },
    skip: library == null
        ? 'Build the Swiss Ephemeris native library before this group.'
        : false,
  );
}
