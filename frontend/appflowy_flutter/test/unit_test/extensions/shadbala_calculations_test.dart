import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_time.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/shadbala.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('continuous Cheshta kendra', () {
    test('reproduces Raman examples 49–51 for Mars', () {
      // Published mean, true and apogee longitudes, not computed fixtures.
      expect(
        cheshtaKendraBala(
          meanLongitude: 266.34,
          trueLongitude: 229 + 49 / 60,
          apogeeLongitude: 181.2275,
        ),
        closeTo(22.2836111111111, 1e-10),
      );
    });

    test('359 and 1 have midpoint zero in either order', () {
      for (final pair in const [(359.0, 1.0), (1.0, 359.0)]) {
        for (final point in const [(0.0, 0.0), (90.0, 30.0), (180.0, 60.0)]) {
          expect(
            cheshtaKendraBala(
              meanLongitude: pair.$1,
              trueLongitude: pair.$2,
              apogeeLongitude: point.$1,
            ),
            closeTo(point.$2, 1e-10),
          );
        }
      }
    });

    test('common rotations and independent full turns preserve strength', () {
      for (final rotation in [-725.5, -180.0, 0.0, 23.8525, 359.75, 720.0]) {
        for (final turns in const [(0, 0, 0), (360, -720, 1080)]) {
          expect(
            cheshtaKendraBala(
              meanLongitude: 359 + rotation + turns.$1,
              trueLongitude: 1 + rotation + turns.$2,
              apogeeLongitude: 90 + rotation + turns.$3,
            ),
            closeTo(30, 1e-10),
            reason: 'rotation $rotation, turns $turns',
          );
        }
      }
    });

    test('is continuous across zero rather than using motion-state buckets',
        () {
      // Here the midpoint moves by half the true-longitude change, so the
      // strength changes by minus one sixth of that change.
      const cases = [
        (-0.006, 25.001),
        (-0.003, 25.0005),
        (0.0, 25.0),
        (0.003, 24.9995),
        (0.006, 24.999),
      ];
      for (final sample in cases) {
        expect(
          cheshtaKendraBala(
            meanLongitude: 0,
            trueLongitude: sample.$1,
            apogeeLongitude: 75,
          ),
          closeTo(sample.$2, 1e-10),
        );
      }
    });

    test('rejects nonfinite values in each of its three arguments', () {
      for (final invalid in _nonfinite) {
        expect(
          () => cheshtaKendraBala(
            meanLongitude: invalid,
            trueLongitude: 1,
            apogeeLongitude: 90,
          ),
          throwsArgumentError,
        );
        expect(
          () => cheshtaKendraBala(
            meanLongitude: 359,
            trueLongitude: invalid,
            apogeeLongitude: 90,
          ),
          throwsArgumentError,
        );
        expect(
          () => cheshtaKendraBala(
            meanLongitude: 359,
            trueLongitude: 1,
            apogeeLongitude: invalid,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('Raman mean-longitude Cheshta', () {
    // 1900-01-01 00:00 at 76 E LMT is 1899-12-31 18:56 UT.
    final epoch = _julianDay(DateTime.utc(1899, 12, 31, 18, 56));

    test('uses the LMT epoch and the tabulated 1900 longitudes', () {
      expect(epoch, closeTo(2415020.288888889, 1e-9));
      expect(
        _julianDay(DateTime.utc(1900)) - epoch,
        closeTo(76 / 360, 5e-10),
      );
      // At zero elapsed days choose the true longitude equal to the mean
      // argument: the expected kendra is a direct tabular separation / 3.
      // The year argument deliberately selects the table's 1900 correction.
      _expectMeanCheshta(epoch, 1900, const [
        (VedicBody.mars, 270.22, 4.2544),
        (VedicBody.mercury, 257.4568, 28.9289333333333),
        (VedicBody.jupiter, 216.71, 13.5822666666667),
        (VedicBody.venus, 257.4568, 22.0177333333333),
        (VedicBody.saturn, 241.74, 5.23893333333333),
      ]);
    });

    test('negative elapsed days retain mean motion and 1899 corrections', () {
      // Independently evaluated at -1 day: mean Sun = 256.47119735;
      // mean Me/Ju/Ve/Sa = 166.579012/216.63360404/321.908854/241.705561.
      _expectMeanCheshta(epoch - 1, 1899, const [
        (VedicBody.mars, 269.695981, 4.40826121666667),
        (VedicBody.mercury, 256.47119735, 29.9640617833333),
        (VedicBody.jupiter, 216.63360404, 13.27919777),
        (VedicBody.venus, 256.47119735, 21.8125522166667),
        (VedicBody.saturn, 241.705561, 4.92187878333333),
      ]);
    });

    test('one elapsed day uses each planet own tabulated mean rate', () {
      // Independently evaluated at +1 day: mean Sun = 258.44240265;
      // mean Me/Ju/Ve/Sa = 174.762318/216.79309596/325.112146/241.773439.
      _expectMeanCheshta(epoch + 1, 1900, const [
        (VedicBody.mars, 270.744019, 4.10053878333333),
        (VedicBody.mercury, 258.44240265, 27.89336155),
        (VedicBody.jupiter, 216.79309596, 13.88310223),
        (VedicBody.venus, 258.44240265, 22.2232477833333),
        (VedicBody.saturn, 241.773439, 5.55632121666667),
      ]);
    });

    test('matches the 1999 JHora Cheshta table without a native engine', () {
      // Frozen full-precision Lahiri positions from the existing Bangalore
      // reference (1999-12-18 09:45 UT). Expected strengths are the independently
      // read JHora 8 table, not output of meanLongitudeCheshtaBala.
      // Allow 0.03 virupa for rounded table values / older ephemeris positions.
      final jd = _julianDay(DateTime.utc(1999, 12, 18, 9, 45));
      expect(jd, 2451530.90625);
      _expectMeanCheshta(
        jd,
        1999,
        const [
          (VedicBody.sun, 242.161859947642, 0.0),
          (VedicBody.moon, 1.9948608970937713, 0.0),
          (VedicBody.mars, 293.1854520086148, 21.80),
          (VedicBody.mercury, 226.62195323127656, 16.96),
          (VedicBody.jupiter, 1.1657436746370458, 41.04),
          (VedicBody.venus, 200.8079153458011, 27.62),
          (VedicBody.saturn, 16.997966037976738, 45.81),
        ],
        tolerance: 0.03,
      );
    });

    test('Sun and Moon contribute no separate Cheshta', () {
      for (final body in [VedicBody.sun, VedicBody.moon]) {
        for (final longitude in [-359.9, 0.0, 91.125, 720.0]) {
          expect(
            meanLongitudeCheshtaBala(
              body: body,
              julianDay: epoch - 365,
              year: 1899,
              referenceLongitude: longitude,
            ),
            0,
          );
        }
      }
    });

    test('rejects nodes and nonfinite inputs, including for luminaries', () {
      for (final body in [VedicBody.rahu, VedicBody.ketu]) {
        expect(
          () => meanLongitudeCheshtaBala(
            body: body,
            julianDay: epoch,
            year: 1900,
            referenceLongitude: 0,
          ),
          throwsArgumentError,
        );
      }
      for (final body in VedicBody.classical) {
        for (final invalid in _nonfinite) {
          expect(
            () => meanLongitudeCheshtaBala(
              body: body,
              julianDay: invalid,
              year: 1900,
              referenceLongitude: 0,
            ),
            throwsArgumentError,
          );
          expect(
            () => meanLongitudeCheshtaBala(
              body: body,
              julianDay: epoch,
              year: 1900,
              referenceLongitude: invalid,
            ),
            throwsArgumentError,
          );
        }
      }
    });
  });

  group('360-day / 30-day period lords', () {
    final epoch = DateTime.utc(1827, 5, 2);

    test('counts May 2 inclusively and ignores time-of-day components', () {
      for (final date in [
        DateTime.utc(1827, 5),
        epoch,
        DateTime.utc(1827, 5, 2, 23, 59, 59, 999, 999),
        DateTime.utc(1827, 5, 3),
      ]) {
        expect(
          shadbalaPeriodLords(date),
          (year: VedicBody.mercury, month: VedicBody.mercury),
        );
      }
    });

    test('the first 30-day boundary is May 31, not June 1', () {
      expect(
        shadbalaPeriodLords(DateTime.utc(1827, 5, 30, 23, 59, 59, 999, 999)),
        (year: VedicBody.mercury, month: VedicBody.mercury),
      );
      for (final date in [
        DateTime.utc(1827, 5, 31),
        DateTime.utc(1827, 6),
      ]) {
        expect(
          shadbalaPeriodLords(date),
          (year: VedicBody.mercury, month: VedicBody.venus),
        );
      }
    });

    test('the first 360-day boundary includes the 1828 leap day', () {
      expect(
        shadbalaPeriodLords(DateTime.utc(1828, 4, 24, 23, 59, 59, 999, 999)),
        (year: VedicBody.mercury, month: VedicBody.jupiter),
      );
      for (final date in [
        DateTime.utc(1828, 4, 25),
        DateTime.utc(1828, 4, 26),
      ]) {
        expect(
          shadbalaPeriodLords(date),
          (year: VedicBody.saturn, month: VedicBody.saturn),
        );
      }
    });

    test('negative ahargana uses floor, not truncation toward zero', () {
      const cases = [
        (-1, VedicBody.sun, VedicBody.moon),
        (-29, VedicBody.sun, VedicBody.moon),
        (-30, VedicBody.sun, VedicBody.moon),
        (-31, VedicBody.sun, VedicBody.saturn),
        (-359, VedicBody.sun, VedicBody.sun),
        (-360, VedicBody.sun, VedicBody.sun),
        (-361, VedicBody.jupiter, VedicBody.venus),
      ];
      for (final sample in cases) {
        final date = epoch.add(Duration(days: sample.$1 - 1));
        expect(
          shadbalaPeriodLords(date),
          (year: sample.$2, month: sample.$3),
          reason: 'inclusive day ${sample.$1}: $date',
        );
      }
    });

    test('year and month lords advance through their own seven-step cycles',
        () {
      const yearLords = [
        VedicBody.saturn,
        VedicBody.mars,
        VedicBody.venus,
        VedicBody.moon,
        VedicBody.jupiter,
        VedicBody.sun,
        VedicBody.mercury,
      ];
      const monthLords = [
        VedicBody.venus,
        VedicBody.sun,
        VedicBody.mars,
        VedicBody.jupiter,
        VedicBody.saturn,
        VedicBody.moon,
        VedicBody.mercury,
      ];
      for (var i = 0; i < 7; i++) {
        expect(
          shadbalaPeriodLords(epoch.add(Duration(days: 360 * (i + 1) - 1)))
              .year,
          yearLords[i],
        );
        expect(
          shadbalaPeriodLords(epoch.add(Duration(days: 30 * (i + 1) - 1)))
              .month,
          monthLords[i],
        );
      }
    });

    test('uses actual zoned calendar components, not the converted UTC date',
        () {
      // N=72000 is simultaneously a year and month boundary in modern times.
      final boundary = epoch.add(const Duration(days: 71999));
      final wall = tz.TZDateTime(
        AstrologyTime.location('Pacific/Kiritimati'),
        boundary.year,
        boundary.month,
        boundary.day,
        0,
        30,
      );
      expect(wall.timeZoneOffset, const Duration(hours: 14));
      expect(
        shadbalaPeriodLords(wall),
        (year: VedicBody.moon, month: VedicBody.moon),
      );
      expect(
        shadbalaPeriodLords(
          DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute),
        ),
        (year: VedicBody.moon, month: VedicBody.moon),
      );
      expect(
        shadbalaPeriodLords(wall.toUtc()),
        (year: VedicBody.venus, month: VedicBody.saturn),
      );
    });
  });

  group('tabular Ayana', () {
    test('equators and solstices obey all seven directional conventions', () {
      const expected = [
        [60.0, 30.0, 30.0, 30.0, 30.0, 30.0, 30.0],
        [120.0, 0.0, 60.0, 60.0, 60.0, 60.0, 0.0],
        [60.0, 30.0, 30.0, 30.0, 30.0, 30.0, 30.0],
        [0.0, 60.0, 0.0, 60.0, 0.0, 0.0, 60.0],
      ];
      for (var quadrant = 0; quadrant < 4; quadrant++) {
        for (final body in VedicBody.classical) {
          expect(
            tabularAyanaBala(body, quadrant * 90.0, 0),
            expected[quadrant][body.index],
            reason: '${body.label}, ${quadrant * 90} degrees',
          );
        }
      }
    });

    test('all 15-degree knots use Raman cumulative arcminutes', () {
      // 0,362,703,1002,1238,1388,1440 arcminutes give these independently
      // evaluated northern/southern strengths (30 +/- arcminutes / 48).
      const north = [
        30.0,
        37.5416666666667,
        44.6458333333333,
        50.875,
        55.7916666666667,
        58.9166666666667,
        60.0,
      ];
      const south = [
        30.0,
        22.4583333333333,
        15.3541666666667,
        9.125,
        4.20833333333333,
        1.08333333333333,
        0.0,
      ];
      const cases = [
        (VedicBody.sun, north, south, 2.0),
        (VedicBody.moon, south, north, 1.0),
        (VedicBody.mars, north, south, 1.0),
        (VedicBody.mercury, north, north, 1.0),
        (VedicBody.jupiter, north, south, 1.0),
        (VedicBody.venus, north, south, 1.0),
        (VedicBody.saturn, south, north, 1.0),
      ];
      for (final sample in cases) {
        for (var knot = 0; knot < 7; knot++) {
          expect(
            tabularAyanaBala(sample.$1, knot * 15.0, 0),
            closeTo(sample.$2[knot] * sample.$4, 1e-10),
            reason: '${sample.$1.label}, northern knot $knot',
          );
          expect(
            tabularAyanaBala(sample.$1, 180 + knot * 15.0, 0),
            closeTo(sample.$3[knot] * sample.$4, 1e-10),
            reason: '${sample.$1.label}, southern knot $knot',
          );
        }
      }
    });

    test('fractional segments interpolate and reflect in all quadrants', () {
      const cases = [
        (7.5, 33.7708333333333),
        (22.5, 41.09375),
        (52.5, 53.3333333333333),
        (82.5, 59.4583333333333),
      ];
      for (final sample in cases) {
        for (final longitude in [sample.$1, 180 - sample.$1]) {
          expect(
            tabularAyanaBala(VedicBody.mars, longitude, 0),
            closeTo(sample.$2, 1e-10),
          );
        }
        for (final longitude in [180 + sample.$1, 360 - sample.$1]) {
          expect(
            tabularAyanaBala(VedicBody.mars, longitude, 0),
            closeTo(60 - sample.$2, 1e-10),
          );
          expect(
            tabularAyanaBala(VedicBody.mercury, longitude, 0),
            closeTo(sample.$2, 1e-10),
          );
        }
      }
    });

    test('fractional planetary longitude is never rounded to whole degrees',
        () {
      const cases = [
        (-7.875, 37.6008680555556),
        (-7.125, 37.9560763888889),
      ];
      for (final sample in cases) {
        // With the fixed 23° reference, these become 15.125° / 15.875°.
        // The helper uses referenceDegrees as supplied, without rounding.
        expect(
          tabularAyanaBala(VedicBody.mars, sample.$1, 23),
          closeTo(sample.$2, 1e-10),
        );
        final rows = calculateShadbala(
          _chart(
            longitudes: {VedicBody.mars: sample.$1},
            ayanamsaDegrees: 23.9,
          ),
        );
        expect(
          _row(rows, VedicBody.mars).breakdown['Ayana'],
          closeTo(sample.$2, 1e-10),
        );
      }
    });

    test('an explicit reference angle shifts the tabular argument', () {
      const at23 = [101.75, 9.125, 50.875, 50.875, 50.875, 50.875, 9.125];
      const at24 = [
        102.405555555556,
        8.79722222222222,
        51.2027777777778,
        51.2027777777778,
        51.2027777777778,
        51.2027777777778,
        8.79722222222222,
      ];
      for (final body in VedicBody.classical) {
        final first = tabularAyanaBala(body, 22, 23);
        expect(first, closeTo(at23[body.index], 1e-10));
        expect(
          tabularAyanaBala(body, 22, 24),
          closeTo(at24[body.index], 1e-10),
        );
      }
    });

    test('negative and positive full turns preserve both angular inputs', () {
      const expected = [101.75, 9.125, 50.875, 50.875, 50.875, 50.875, 9.125];
      for (final body in VedicBody.classical) {
        for (final turn in [-720.0, -360.0, 0.0, 360.0, 720.0]) {
          for (final ayanamsaTurn in [-360.0, 0.0, 360.0]) {
            expect(
              tabularAyanaBala(body, 22 + turn, 23 + ayanamsaTurn),
              closeTo(expected[body.index], 1e-10),
            );
          }
        }
      }
    });

    test('rejects nodes and nonfinite longitude or ayanamsha', () {
      for (final body in [VedicBody.rahu, VedicBody.ketu]) {
        expect(() => tabularAyanaBala(body, 0, 23), throwsArgumentError);
      }
      for (final body in VedicBody.classical) {
        for (final invalid in _nonfinite) {
          expect(
            () => tabularAyanaBala(body, invalid, 23),
            throwsArgumentError,
          );
          expect(
            () => tabularAyanaBala(body, 0, invalid),
            throwsArgumentError,
          );
        }
      }
    });
  });

  group('bounded directed Drik', () {
    test('ordinary aspects retain their knots and linear interpolation', () {
      const knots = [
        0.0,
        0.0,
        15.0,
        45.0,
        30.0,
        0.0,
        60.0,
        45.0,
        30.0,
        15.0,
        0.0,
        0.0,
        0.0,
      ];
      for (final body in [
        VedicBody.sun,
        VedicBody.moon,
        VedicBody.mercury,
        VedicBody.venus,
      ]) {
        for (var knot = 0; knot < knots.length; knot++) {
          expect(grahaDrishti(body, knot * 30.0), knots[knot]);
        }
        for (final sample in const [
          (45.0, 7.5),
          (75.0, 30.0),
          (105.0, 37.5),
          (165.0, 30.0),
          (195.0, 52.5),
          (285.0, 7.5),
        ]) {
          expect(grahaDrishti(body, sample.$1), sample.$2);
        }
      }
    });

    test('special full aspects replace knots and never exceed sixty', () {
      for (final sample in const [
        (VedicBody.mars, 90.0),
        (VedicBody.mars, 210.0),
        (VedicBody.jupiter, 120.0),
        (VedicBody.jupiter, 240.0),
        (VedicBody.saturn, 60.0),
        (VedicBody.saturn, 270.0),
      ]) {
        for (final turn in [-360.0, 0.0, 360.0]) {
          expect(grahaDrishti(sample.$1, sample.$2 + turn), 60);
        }
      }
      for (final body in VedicBody.classical) {
        for (var halfDegree = 0; halfDegree <= 720; halfDegree++) {
          expect(
            grahaDrishti(body, halfDegree / 2),
            inInclusiveRange(0, 60),
          );
        }
      }
    });
  });

  group('synthetic chart components', () {
    test('bright Moon and associated Mercury change at the quarter phases', () {
      for (final phase in [
        0.0,
        89.999,
        90.0,
        90.001,
        180.0,
        269.999,
        270.0,
        270.001,
        359.999,
      ]) {
        final chart = _chart(
          longitudes: {
            VedicBody.sun: 0,
            VedicBody.moon: phase,
            VedicBody.mercury: phase,
            VedicBody.mars: 45,
            VedicBody.saturn: 75,
            VedicBody.rahu: 45,
            VedicBody.ketu: 225,
          },
        );
        final rows = calculateShadbala(chart);
        final halfPhase = (phase <= 180 ? phase : 360 - phase) / 3;
        final bright = phase >= 90 && phase <= 270;
        expect(
          rows[VedicBody.moon.index].breakdown['Paksha'],
          closeTo((bright ? halfPhase : 60 - halfPhase) * 2, 1e-9),
        );
        expect(
          rows[VedicBody.mercury.index].breakdown['Paksha'],
          closeTo(bright ? halfPhase : 60 - halfPhase, 1e-9),
        );
      }
    });

    test('legacy Ayana reference does not drift with the displayed ayanamsha',
        () {
      // JHora 8 uses a fixed 23° reference, confirmed in 1900, 1999 and 2026.
      for (final ayanamsha in [21.5, 23.85, 24.22, 29.9]) {
        final rows = calculateShadbala(_chart(ayanamsaDegrees: ayanamsha));
        expect(rows.first.breakdown['Ayana'], 101.75);
      }
    });

    test('Dig uses each ascendant-relative weak point and shortest arc', () {
      const ascendant = 37.125;
      const weakOffsets = [90.0, 270.0, 90.0, 180.0, 180.0, 270.0, 0.0];
      for (final sample in const [
        (0.0, 0.0),
        (45.0, 15.0),
        (90.0, 30.0),
        (180.0, 60.0),
        (270.0, 30.0),
        (315.0, 15.0),
        (360.0, 0.0),
      ]) {
        final rows = calculateShadbala(
          _chart(
            ascendant: ascendant,
            longitudes: {
              for (final body in VedicBody.classical)
                body: ascendant + weakOffsets[body.index] + sample.$1,
            },
          ),
        );
        for (final row in rows) {
          expect(
            row.dig,
            closeTo(sample.$2, 1e-10),
            reason: '${row.body.label}, weak-point offset ${sample.$1}',
          );
        }
      }
    });

    test('changing MC cannot change equal-house Dig', () {
      // Separations from the specified weak points for the default fixture.
      const separations = [85.25, 175.25, 97.75, 44.25, 76.75, 37.75, 49.75];
      for (final mc in [0.0, 90.0, 180.0, 270.0, 359.9]) {
        for (final row in calculateShadbala(_chart(midheaven: mc))) {
          expect(
            row.dig,
            closeTo(separations[row.body.index] / 3, 1e-10),
            reason: '${row.body.label}, MC $mc',
          );
        }
      }
    });

    test('Natonnata follows the solar arc with complementary night strength',
        () {
      const dayBodies = [VedicBody.sun, VedicBody.jupiter, VedicBody.venus];
      for (final sample in const [
        (0.0, 0.0),
        (45.0, 15.0),
        (90.0, 30.0),
        (135.0, 45.0),
        (180.0, 60.0),
        (225.0, 45.0),
        (270.0, 30.0),
        (315.0, 15.0),
      ]) {
        for (final clockHours in [0.0, 12.0, 23.5]) {
          final rows = calculateShadbala(
            _chart(
              ascendant: 0,
              longitudes: {VedicBody.sun: 90 + sample.$1},
              localMeanHours: clockHours,
            ),
          );
          for (final row in rows) {
            final expected = row.body == VedicBody.mercury
                ? 60.0
                : dayBodies.contains(row.body)
                    ? sample.$2
                    : 60 - sample.$2;
            expect(row.breakdown['Natonnata'], closeTo(expected, 1e-10));
          }
          expect(
            _row(rows, VedicBody.sun).breakdown['Natonnata'],
            _row(rows, VedicBody.sun).dig,
          );
          expect(
            _row(rows, VedicBody.sun).breakdown['Natonnata']! +
                _row(rows, VedicBody.moon).breakdown['Natonnata']!,
            closeTo(60, 1e-10),
          );
        }
      }
    });

    test('Drekkana is half-open with male, neutral, female decans', () {
      const first = [15.0, 0.0, 15.0, 0.0, 15.0, 0.0, 0.0];
      const middle = [0.0, 0.0, 0.0, 15.0, 0.0, 0.0, 15.0];
      const last = [0.0, 15.0, 0.0, 0.0, 0.0, 15.0, 0.0];
      for (final sample in const [
        (0.0, first),
        (9.999, first),
        (10.0, middle),
        (19.999, middle),
        (20.0, last),
        (29.999, last),
        (30.0, first),
      ]) {
        final rows = calculateShadbala(
          _chart(
            longitudes: {
              for (final body in VedicBody.classical)
                body: body.index * 30 + sample.$1,
            },
          ),
        );
        for (final row in rows) {
          expect(
            row.breakdown['Drekkana'],
            sample.$2[row.body.index],
            reason: '${row.body.label}, sign degree ${sample.$1}',
          );
        }
      }
    });

    test('Hora changes at exact elapsed hours, not unequal daylight horas', () {
      // Wednesday sunrise has seconds; daylight is 10.5 hours, not 12 hours.
      const hour = Duration.microsecondsPerHour;
      for (final sample in const [
        (0, VedicBody.mercury),
        (hour - 1, VedicBody.mercury),
        (hour, VedicBody.moon),
        (hour + 1, VedicBody.moon),
        (2 * hour - 1, VedicBody.moon),
        (2 * hour, VedicBody.saturn),
      ]) {
        final rows = calculateShadbala(
          _chart(utc: _rise.add(Duration(microseconds: sample.$1))),
        );
        _expectAward(rows, 'Hora', sample.$2, 60);
      }
    });

    test('pre-dawn keeps the previous sunrise until the next actual sunrise',
        () {
      final twentyThreeHours = _rise.add(const Duration(hours: 23));
      for (final sample in [
        (
          twentyThreeHours.subtract(const Duration(microseconds: 1)),
          VedicBody.moon,
        ),
        (twentyThreeHours, VedicBody.saturn),
        (_nextRise.subtract(const Duration(microseconds: 1)), VedicBody.saturn),
      ]) {
        final rows = calculateShadbala(_chart(utc: sample.$1));
        _expectAward(rows, 'Hora', sample.$2, 60);
        _expectAward(rows, 'Dina', VedicBody.mercury, 45);
      }
      final nextDay = calculateShadbala(
        _chart(
          utc: _nextRise,
          solarTimes: (
            rise: _nextRise,
            set: _nextRise.add(const Duration(hours: 10, minutes: 30)),
            next: _nextRise.add(const Duration(days: 1)),
          ),
        ),
      );
      _expectAward(nextDay, 'Hora', VedicBody.jupiter, 60);
      _expectAward(nextDay, 'Dina', VedicBody.jupiter, 45);
    });

    test('chart period lords use the local date of the previous sunrise', () {
      // First case: sunrise is May 31 locally, but May 30 in UTC.
      // Second case: the birth is May 31 locally, but sunrise is still May 30.
      final cases = [
        (
          utc: DateTime.utc(1827, 5, 31, 0, 30),
          times: (
            rise: DateTime.utc(1827, 5, 30, 20, 30),
            set: DateTime.utc(1827, 5, 31, 6, 30),
            next: DateTime.utc(1827, 5, 31, 20, 30),
          ),
          month: VedicBody.venus,
        ),
        (
          utc: DateTime.utc(1827, 5, 31),
          times: (
            rise: DateTime.utc(1827, 5, 30, 1),
            set: DateTime.utc(1827, 5, 30, 13),
            next: DateTime.utc(1827, 5, 31, 1),
          ),
          month: VedicBody.mercury,
        ),
      ];
      for (final sample in cases) {
        final rows = calculateShadbala(
          _chart(
            utc: sample.utc,
            solarTimes: sample.times,
            utcOffsetMinutes: 330,
          ),
        );
        _expectAward(rows, 'Varsha', VedicBody.mercury, 15);
        _expectAward(rows, 'Masa', sample.month, 30);
      }
    });

    test('each missing polar solar event makes Kala and aggregates unavailable',
        () {
      final times = <_SolarTimes>[
        (rise: null, set: _set, next: _nextRise),
        (rise: _rise, set: null, next: _nextRise),
        (rise: _rise, set: _set, next: null),
        (rise: null, set: null, next: null),
      ];
      for (final solarTimes in times) {
        for (final row in calculateShadbala(_chart(solarTimes: solarTimes))) {
          expect(row.kala, isNull);
          expect(row.total, isNull);
          expect(row.rupas, isNull);
          expect(row.ratio, isNull);
          for (final value in [
            row.sthana,
            row.dig,
            row.cheshta,
            row.naisargika,
            row.drik,
          ]) {
            expect(value.isFinite, isTrue);
          }
          for (final name in ['Tribhaga', 'Varsha', 'Masa', 'Dina', 'Hora']) {
            expect(row.breakdown[name], 0);
          }
        }
      }
    });

    test(
        'totals use the seven required minima and exact legacy natural weights',
        () {
      final rows = calculateShadbala(_chart());
      expect(rows.map((row) => row.body), const [
        VedicBody.sun,
        VedicBody.moon,
        VedicBody.mars,
        VedicBody.mercury,
        VedicBody.jupiter,
        VedicBody.venus,
        VedicBody.saturn,
      ]);
      const required = [300.0, 360.0, 300.0, 420.0, 390.0, 330.0, 300.0];
      const natural = [60.0, 51.43, 17.14, 25.70, 34.28, 42.85, 8.57];
      for (final row in rows) {
        final index = row.body.index;
        expect(row.required, required[index]);
        expect(row.naisargika, natural[index]);
        final sthana = _sumParts(row, const [
          'Uchcha',
          'Saptavargaja',
          'Ojayugma',
          'Kendradi',
          'Drekkana',
        ]);
        final kala = _sumParts(row, _kalaParts);
        final total =
            sthana + row.dig + kala + row.cheshta + natural[index] + row.drik;
        expect(row.sthana, closeTo(sthana, 1e-10));
        expect(row.kala, closeTo(kala, 1e-10));
        expect(row.total, closeTo(total, 1e-10));
        expect(row.rupas, closeTo(total / 60, 1e-10));
        expect(row.ratio, closeTo(total / required[index], 1e-10));
      }
    });

    test('Sun Ayana and Moon Paksha are doubled once, only inside Kala', () {
      // Default longitudes: Sun 22°, Moon 112°; integration passes the
      // fixed 23° legacy reference, not the chart's 23.85° ayanamsha.
      final rows = calculateShadbala(_chart());
      for (final sample in const [
        (VedicBody.sun, 101.75, 30.0, 60.0),
        (VedicBody.moon, 9.125, 60.0, 51.43),
      ]) {
        final row = _row(rows, sample.$1);
        expect(row.breakdown['Ayana'], sample.$2);
        expect(row.breakdown['Paksha'], sample.$3);
        expect(row.cheshta, 0);
        expect(row.motion, 'Counted in Kala');
        final otherKala = _sumParts(row, const [
          'Natonnata',
          'Tribhaga',
          'Varsha',
          'Masa',
          'Dina',
          'Hora',
          'Yuddha',
        ]);
        final expectedKala = otherKala + sample.$2 + sample.$3;
        expect(row.kala, closeTo(expectedKala, 1e-10));
        expect(
          row.total,
          closeTo(
            row.sthana + row.dig + expectedKala + sample.$4 + row.drik,
            1e-10,
          ),
        );
      }
    });

    test('changing the dasha year cannot change any Shadbala component', () {
      final baseline = calculateShadbala(_chart(dashaYearDays: 360))
          .map(_components)
          .toList();
      for (final yearDays in [365.0, 365.2425, 365.25636, 366.0]) {
        expect(
          calculateShadbala(_chart(dashaYearDays: yearDays))
              .map(_components)
              .toList(),
          baseline,
          reason: 'dasha year $yearDays',
        );
      }
    });
  });
}

const _nonfinite = [double.nan, double.infinity, double.negativeInfinity];
const _kalaParts = [
  'Natonnata',
  'Paksha',
  'Tribhaga',
  'Varsha',
  'Masa',
  'Dina',
  'Hora',
  'Ayana',
  'Yuddha',
];

typedef _SolarTimes = ({DateTime? rise, DateTime? set, DateTime? next});

final _rise = DateTime.utc(2000, 1, 5, 6, 17, 33);
final _set = DateTime.utc(2000, 1, 5, 16, 47, 33);
final _nextRise = DateTime.utc(2000, 1, 6, 6, 16, 49);

// Independent Unix-epoch conversion; no ephemeris or Shadbala helper involved.
double _julianDay(DateTime utc) =>
    2440587.5 + utc.microsecondsSinceEpoch / Duration.microsecondsPerDay;

void _expectMeanCheshta(
  double julianDay,
  int year,
  List<(VedicBody, double, double)> cases, {
  double tolerance = 1e-8,
}) {
  for (final sample in cases) {
    final actual = meanLongitudeCheshtaBala(
      body: sample.$1,
      julianDay: julianDay,
      year: year,
      referenceLongitude: sample.$2,
    );
    expect(actual, closeTo(sample.$3, tolerance), reason: sample.$1.label);
    expect(actual, inInclusiveRange(0, 60));
  }
}

// All nine bodies are supplied so node exclusion is observable. Positions and
// solar events are synthetic; no apparent diameters means no planetary war.
AstrologyChart _chart({
  Map<VedicBody, double> longitudes = const {},
  double ascendant = 17.25,
  double midheaven = 111,
  double ayanamsaDegrees = 23.85,
  double localMeanHours = 12,
  DateTime? utc,
  _SolarTimes? solarTimes,
  int utcOffsetMinutes = 0,
  double dashaYearDays = 365.25636,
}) {
  final instant = utc ?? DateTime.utc(2000, 1, 5, 12);
  final solar = solarTimes ?? (rise: _rise, set: _set, next: _nextRise);
  final localDay =
      (solar.rise ?? instant).add(Duration(minutes: utcOffsetMinutes));
  const positions = [
    22.0,
    112.0,
    205.0,
    153.0,
    274.0,
    325.0,
    67.0,
    10.0,
    190.0,
  ];
  return AstrologyChart(
    input: AstrologyInput(
      utc: instant,
      utcOffsetMinutes: utcOffsetMinutes,
      dashaYearDays: dashaYearDays,
      place: const AstrologyPlace(
        name: 'Synthetic chart',
        latitude: 12,
        longitude: 76,
        timeZone: 'UTC',
      ),
    ),
    utc: instant,
    julianDay: _julianDay(instant),
    ayanamsaDegrees: ayanamsaDegrees,
    ascendant: ascendant,
    midheaven: midheaven,
    planets: [
      for (final body in VedicBody.values)
        VedicPlacement(
          name: body.label,
          shortName: body.shortName,
          body: body,
          longitude: longitudes[body] ?? positions[body.index],
          speed: 1,
        ),
    ],
    specialLagnas: const [],
    sunrise: solar.rise,
    sunset: solar.set,
    nextSunrise: solar.next,
    weekday: localDay.weekday % 7,
    localMeanHours: localMeanHours,
  );
}

ShadbalaRow _row(List<ShadbalaRow> rows, VedicBody body) =>
    rows.singleWhere((row) => row.body == body);

void _expectAward(
  List<ShadbalaRow> rows,
  String component,
  VedicBody lord,
  double strength,
) {
  for (final row in rows) {
    expect(
      row.breakdown[component],
      row.body == lord ? strength : 0,
      reason: '${row.body.label} $component, lord ${lord.label}',
    );
  }
}

double _sumParts(ShadbalaRow row, List<String> parts) =>
    parts.fold(0.0, (sum, name) => sum + row.breakdown[name]!);

List<Object?> _components(ShadbalaRow row) => [
      row.body,
      row.sthana,
      row.dig,
      row.kala,
      row.cheshta,
      row.naisargika,
      row.drik,
      row.required,
      row.total,
      row.rupas,
      row.ratio,
      row.breakdown,
      row.motion,
    ];
