import 'dart:io';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_date_analysis.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_engine.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_panchanga.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vimshottari.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sweph/sweph.dart';

const _bengaluru = AstrologyPlace(
  name: 'Bengaluru',
  latitude: 12 + 59 / 60,
  longitude: 77 + 35 / 60,
  timeZone: 'Asia/Kolkata',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final library = [
    const String.fromEnvironment('ASTROLOGY_TEST_LIBRARY'),
    'build/astrology_ephemeris/Release/sweph.dll',
    'build/windows/x64/runner/Debug/sweph.dll',
    'build/windows/x64/runner/Release/sweph.dll',
  ].where((path) => path.isNotEmpty && File(path).existsSync()).firstOrNull;

  group(
    'Swiss Ephemeris date analysis',
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

      test('fast transit positions equal the full chart', () async {
        for (final input in [
          AstrologyInput(
            utc: DateTime.utc(1999, 12, 18, 9, 45),
            place: _bengaluru,
          ),
          AstrologyInput(
            utc: DateTime.utc(2026, 9, 28, 6, 30),
            place: _bengaluru,
            ayanamsa: AstrologyAyanamsa.raman,
            ayanamsaOffsetArcseconds: 30,
            trueNode: true,
          ),
        ]) {
          final chart = await engine.calculate(input);
          final positions = await engine.positions(input, input.utc!);
          expect(
            positions.map((placement) => placement.body),
            VedicBody.values,
          );
          for (final body in VedicBody.values) {
            expect(
              positions[body.index].longitude,
              closeTo(chart.planet(body).longitude, 1e-9),
              reason: body.label,
            );
            expect(
              positions[body.index].speed,
              closeTo(chart.planet(body).speed, 1e-12),
              reason: body.label,
            );
          }
        }
      });

      test('panchanga end times are the actual boundary crossings', () async {
        for (final utc in [
          DateTime.utc(2026, 9, 28, 6, 30),
          DateTime.utc(2024, 4, 8, 18),
          DateTime.utc(1999, 12, 18, 9, 45),
        ]) {
          final chart = await engine.calculate(
            AstrologyInput(utc: utc, place: _bengaluru),
          );
          final times = await engine.panchangaTimes(chart);
          Future<AstrologyChart> at(DateTime instant) => engine.calculate(
                AstrologyInput(utc: instant, place: _bengaluru),
              );
          Future<void> crossing(
            DateTime? end,
            int Function(AstrologyChart chart) limb,
            int count,
            String name,
          ) async {
            expect(end, isNotNull, reason: name);
            expect(end!.isAfter(utc), isTrue, reason: name);
            expect(
              end.difference(utc),
              lessThan(const Duration(hours: 27)),
              reason: name,
            );
            final before = await at(end.subtract(const Duration(seconds: 1)));
            final after = await at(end.add(const Duration(seconds: 1)));
            expect(limb(before), limb(chart), reason: '$name before its end');
            expect(
              limb(after),
              (limb(chart) + 1) % count,
              reason: '$name after its end',
            );
          }

          await crossing(
            times.tithiEnd,
            (chart) => chart.tithi - 1,
            30,
            'tithi',
          );
          await crossing(
            times.karanaEnd,
            (chart) => (chart.elongation / 6).floor(),
            60,
            'karana',
          );
          await crossing(
            times.nakshatraEnd,
            (chart) => nakshatraIndex(chart.planet(VedicBody.moon).longitude),
            27,
            'nakshatra',
          );
          await crossing(times.yogaEnd, (chart) => chart.yoga, 27, 'yoga');
          expect(
            times.karanaEnd!.isAfter(times.tithiEnd!),
            isFalse,
            reason: 'A karana is half a tithi.',
          );

          final sunset = times.previousSunset!;
          expect(sunset.isBefore(chart.sunrise!), isTrue);
          expect(
            chart.sunrise!.difference(sunset).inMinutes,
            inInclusiveRange(10 * 60, 14 * 60),
          );
        }
      });

      test('a natal chart analysed on another date', () async {
        final natalInput = AstrologyInput(
          name: 'Reference',
          utc: DateTime.utc(1999, 12, 18, 9, 45),
          place: _bengaluru,
        );
        final natal = await engine.calculate(natalInput);
        final moment = await engine.calculate(
          AstrologyInput(
              utc: DateTime.utc(2026, 9, 28, 6, 30), place: _bengaluru),
        );
        final analysis = analyzeAstrologyDate(
          moment: moment,
          natal: natal,
          times: await engine.panchangaTimes(moment),
        );
        expect(analysis.dasha, hasLength(4));
        expect(
          analysis.dasha.map((period) => period.level),
          [0, 1, 2, 3],
        );
        for (final period in analysis.dasha) {
          expect(period.contains(moment.utc), isTrue);
        }
        expect(analysis.transits, hasLength(9));
        expect(
          analysis.muhurtas.map((window) => window.name),
          containsAll([
            'Brahma muhurta',
            'Rahu Kalam',
            'Yamaganda',
            'Gulika Kalam',
            'Abhijit muhurta',
          ]),
        );
        // 2026-09-28 is a Monday: Rahu Kalam is the second eighth of daytime.
        expect(moment.weekday, 1);
        final rahu = analysis.muhurtas
            .singleWhere((window) => window.name == 'Rahu Kalam');
        final eighth = moment.sunset!.difference(moment.sunrise!) ~/ 8;
        expect(
          rahu.start.difference(moment.sunrise!).inSeconds,
          closeTo(eighth.inSeconds, 1),
        );
        expect(analysis.hora, isNotNull);
        expect(analysis.tara, isNotNull);

        final values = astrologyEventValues(
          natal: natal,
          positions: await engine.positions(natalInput, moment.utc),
          utc: moment.utc,
        );
        expect(
          values.dasha,
          analysis.dasha.map((period) => period.lord),
        );
        expect(
          values.moonNakshatra,
          startsWith(moment.planet(VedicBody.moon).nakshatra),
        );
        expect(
          vimshottariLevelNames,
          hasLength(values.dasha.length),
        );
        expect(tithiName(moment.tithi), isNotEmpty);
      });
    },
    skip: library == null
        ? 'Build the Windows runner or set ASTROLOGY_TEST_LIBRARY.'
        : false,
  );
}
