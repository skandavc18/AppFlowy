import 'dart:io';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_engine.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/shadbala.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweph/sweph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = [
    const String.fromEnvironment('ASTROLOGY_TEST_LIBRARY'),
    'build/astrology_ephemeris/Release/sweph.dll',
    'build/windows/x64/runner/Debug/sweph.dll',
  ].where((path) => path.isNotEmpty && File(path).existsSync()).firstOrNull;

  group(
    'JHora Shadbala reference',
    () {
      final engine = AstrologyEngine();
      late Directory directory;
      setUpAll(() async {
        directory =
            await Directory.systemTemp.createTemp('shadbala-reference-');
        await engine.initialize(
          modulePath: File(library!).absolute.path,
          ephemerisDirectory: directory.path,
        );
      });
      tearDownAll(() async {
        Sweph.swe_close();
        await directory.delete(recursive: true);
      });

      test('1999 Bangalore afternoon reproduces the supplied percentages',
          () async {
        // Anonymous input supplied with the issue, verified in JHora 8.0's
        // Shadbala Summary / Break-up / Sthana / Kala tables. Default Lahiri,
        // mean nodes, Parasara aspects, Bangalore 12N59 / 77E35.
        // JHora uses older Swiss 2.02 true positions, vs our 2.10 apparent
        // positions; allow 0.06 virupa for that and mean-table precision.
        final chart = await engine.calculate(
          AstrologyInput(
            utc: DateTime.utc(1999, 12, 18, 9, 45),
            utcOffsetMinutes: 330,
            place: const AstrologyPlace(
              name: 'Bangalore reference',
              latitude: 12 + 59 / 60,
              longitude: 77 + 35 / 60,
              timeZone: 'Asia/Kolkata',
            ),
          ),
        );
        final rows = calculateShadbala(chart);
        const totals = [363.41, 390.82, 387.82, 423.22, 643.81, 435.25, 329.28];
        const sthana = [182.39, 207.17, 238.40, 189.46, 276.22, 204.81, 122.88];
        const dig = [43.05, 22.99, 59.94, 7.87, 52.72, 30.73, 2.01];
        const kala = [63.81, 114.56, 46.63, 172.74, 244.87, 122.61, 153.21];
        const cheshta = [0.0, 0.0, 21.80, 16.96, 41.04, 27.62, 45.81];
        const drik = [14.17, -5.32, 3.91, 10.49, -5.32, 6.62, -3.20];
        const ayana = [0.70, 17.72, 9.62, 57.80, 41.88, 9.62, 11.20];
        const natonnata = [43.05, 16.95, 16.95, 60.0, 43.05, 43.05, 16.95];
        const expected = [121, 109, 129, 101, 165, 132, 110];
        for (final row in rows) {
          final index = row.body.index;
          for (final component in [
            (name: 'Total', actual: row.total, expected: totals[index]),
            (name: 'Sthana', actual: row.sthana, expected: sthana[index]),
            (name: 'Dig', actual: row.dig, expected: dig[index]),
            (name: 'Kala', actual: row.kala, expected: kala[index]),
            (name: 'Cheshta', actual: row.cheshta, expected: cheshta[index]),
            (name: 'Drik', actual: row.drik, expected: drik[index]),
            (
              name: 'Ayana',
              actual: row.breakdown['Ayana'],
              expected: ayana[index],
            ),
            (
              name: 'Natonnata',
              actual: row.breakdown['Natonnata'],
              expected: natonnata[index],
            ),
          ]) {
            expect(
              component.actual,
              closeTo(component.expected, 0.06),
              reason: '${row.body.label} ${component.name}: JHora 8 table',
            );
          }
          expect(
            row.ratio! * 100,
            closeTo(expected[row.body.index], 0.5),
            reason: '${row.body.label}: JHora reference percentage',
          );
        }
      });
      test('2026 Bangalore nighttime matches independent JHora components',
          () async {
        final chart = await engine.calculate(
          AstrologyInput(
            utc: DateTime.utc(2026, 9, 11, 13, 46, 9),
            utcOffsetMinutes: 330,
            place: const AstrologyPlace(
              name: 'Bangalore reference',
              latitude: 12 + 59 / 60,
              longitude: 77 + 35 / 60,
              timeZone: 'Asia/Kolkata',
            ),
          ),
        );
        const totals = [475.24, 511.01, 385.18, 424.38, 400.82, 337.38, 342.04];
        const sthana = [167.00, 197.22, 190.74, 254.30, 204.45, 160.69, 152.90];
        const dig = [24.38, 33.80, 4.77, 1.40, 16.61, 21.64, 2.44];
        const kala = [230.01, 238.50, 151.93, 148.33, 137.19, 86.76, 147.88];
        const cheshta = [0.0, 0.0, 27.86, 10.01, 13.21, 45.36, 52.33];
        const drik = [-6.15, -9.95, -7.25, -15.35, -4.92, -19.91, -22.08];
        for (final row in calculateShadbala(chart)) {
          final index = row.body.index;
          for (final component in [
            (name: 'Sthana', actual: row.sthana, expected: sthana[index]),
            (name: 'Dig', actual: row.dig, expected: dig[index]),
            (name: 'Kala', actual: row.kala, expected: kala[index]),
            (name: 'Cheshta', actual: row.cheshta, expected: cheshta[index]),
            (name: 'Drik', actual: row.drik, expected: drik[index]),
            (name: 'Total', actual: row.total, expected: totals[index]),
          ]) {
            expect(
              component.actual,
              closeTo(component.expected, 0.06),
              reason: '${row.body.label} ${component.name}: JHora nighttime',
            );
          }
        }
      });

      test('1900 historical reference retains the documented component values',
          () async {
        final chart = await engine.calculate(
          AstrologyInput(
            utc: DateTime.utc(1900, 1, 1, 6, 30),
            utcOffsetMinutes: 330,
            place: const AstrologyPlace(
              name: 'Bangalore reference',
              latitude: 12 + 59 / 60,
              longitude: 77 + 35 / 60,
              timeZone: 'Asia/Kolkata',
            ),
          ),
        );
        const sthana = [187.66, 152.36, 220.37, 159.79, 157.51, 253.25, 264.28];
        const dig = [58.76, 0.13, 57.54, 24.22, 18.16, 10.00, 32.98];
        const kala = [208.97, 223.00, 60.92, 177.89, 123.98, 141.72, 119.74];
        const cheshta = [0.0, 0.0, 2.70, 24.91, 13.40, 17.73, 4.81];
        const drik = [1.15, 0.64, 1.61, 0.0, 0.69, -1.57, 0.0];
        for (final row in calculateShadbala(chart)) {
          final i = row.body.index;
          for (final component in [
            (name: 'Sthana', actual: row.sthana, expected: sthana[i]),
            (name: 'Dig', actual: row.dig, expected: dig[i]),
            (name: 'Kala', actual: row.kala, expected: kala[i]),
            (name: 'Cheshta', actual: row.cheshta, expected: cheshta[i]),
            (name: 'Drik', actual: row.drik, expected: drik[i]),
          ]) {
            expect(
              component.actual,
              closeTo(component.expected, 0.06),
              reason: '${row.body.label} ${component.name}: JHora 1900',
            );
          }
        }
      });

      test('waxing but dark Moon differs from a bright waxing Moon', () async {
        // Direct JHora Kala readings at 00:02:19 and 12:02:19 IST, Sep 19.
        // The first has elongation ~89°, the second ~94.44°. A waxing-only
        // classification would give the first Moon 59.33, not 60.67 virupas.
        for (final sample in [
          (utc: DateTime.utc(2026, 9, 18, 18, 32, 19), paksha: 60.67),
          (utc: DateTime.utc(2026, 9, 19, 6, 32, 19), paksha: 62.96),
        ]) {
          final chart = await engine.calculate(
            AstrologyInput(
              utc: sample.utc,
              utcOffsetMinutes: 330,
              place: const AstrologyPlace(
                name: 'Bangalore reference',
                latitude: 12 + 59 / 60,
                longitude: 77 + 35 / 60,
                timeZone: 'Asia/Kolkata',
              ),
            ),
          );
          expect(chart.elongation, inInclusiveRange(88, 96));
          final moon = calculateShadbala(chart)[VedicBody.moon.index];
          expect(moon.breakdown['Paksha'], closeTo(sample.paksha, 0.02));
        }
      });

      test(
          'mean Cheshta retains its reference frame across presets and offsets',
          () async {
        final input = AstrologyInput(
          utc: DateTime.utc(1999, 12, 18, 9, 45),
          place: const AstrologyPlace(
            name: 'Bangalore reference',
            latitude: 12 + 59 / 60,
            longitude: 77 + 35 / 60,
            timeZone: 'Asia/Kolkata',
          ),
        );
        final baseline = calculateShadbala(await engine.calculate(input));
        for (final mode in AstrologyAyanamsa.values) {
          for (final adjustment in [-7200.25, 0.0, 3600.125]) {
            final chart = await engine.calculate(
              input.copyWith(
                ayanamsa: mode,
                ayanamsaOffsetArcseconds: adjustment,
              ),
            );
            for (final row in calculateShadbala(chart)) {
              expect(
                row.cheshta,
                closeTo(baseline[row.body.index].cheshta, 1e-8),
                reason: '${mode.label}, $adjustment: ${row.body.label}',
              );
            }
          }
        }
      });
    },
    skip: library == null ? 'Build the native ephemeris library first.' : false,
  );
}
