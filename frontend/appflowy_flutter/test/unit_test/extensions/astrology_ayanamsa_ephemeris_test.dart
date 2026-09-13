import 'dart:convert';
import 'dart:io';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_engine.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_time.dart';
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

// Independent Swiss IDs: deriving the oracle's mode from preset.swissId
// would allow an incorrect production mapping to agree with itself.
const _presetIds = {
  AstrologyAyanamsa.lahiri: 1,
  AstrologyAyanamsa.raman: 3,
  AstrologyAyanamsa.krishnamurti: 5,
  AstrologyAyanamsa.pushyaPaksha: 29,
  AstrologyAyanamsa.yukteshwar: 7,
  AstrologyAyanamsa.suryaSiddhanta: 21,
  AstrologyAyanamsa.trueChitra: 27,
};
const _bodyIds = {
  VedicBody.sun: 0,
  VedicBody.moon: 1,
  VedicBody.mars: 4,
  VedicBody.mercury: 2,
  VedicBody.jupiter: 5,
  VedicBody.venus: 3,
  VedicBody.saturn: 6,
  VedicBody.rahu: 10,
};
const _offsets = [3600.125, -7200.25];
const _longitudeTolerance = 1e-8;
const _cuspEpsilon = 1e-6;
const _rotatingLagnas = ['BL', 'HL', 'GL', 'Gk', 'Md'];

final _referenceDates = [
  DateTime.utc(1900, 1, 1, 12),
  DateTime.utc(2026, 9, 11, 13, 46, 15),
];
final _solarCases = [
  (name: 'day', utc: DateTime.utc(2026, 9, 11, 7), dayBirth: true),
  (
    name: 'night',
    utc: DateTime.utc(2026, 9, 11, 13, 46, 15),
    dayBirth: false,
  ),
  (name: 'pre-dawn', utc: DateTime.utc(2026, 9, 10, 22, 30), dayBirth: false),
];

typedef _NativePosition = ({
  double longitude,
  double latitude,
  double declination,
  double speed,
});
typedef _NativeReference = ({
  double julianDay,
  double ayanamsaDegrees,
  double ascendant,
  double midheaven,
  Map<VedicBody, _NativePosition> planets,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seven preset IDs and signed fractional labels survive JSON', () {
    expect(AstrologyAyanamsa.values, unorderedEquals(_presetIds.keys));
    for (final entry in _presetIds.entries) {
      expect(entry.key.swissId, entry.value, reason: entry.key.name);
      final baseline = AstrologyInput(
        utc: _referenceDates.last,
        place: _bengaluru,
        ayanamsa: entry.key,
      );
      for (final sample in const [
        (offset: 0.0, suffix: ''),
        (offset: -0.0, suffix: ''),
        (offset: 3600.0, suffix: ' (+3600″)'),
        (offset: 3600.125, suffix: ' (+3600.125″)'),
        (offset: -7200.25, suffix: ' (−7200.25″)'),
      ]) {
        final input = baseline.copyWith(
          ayanamsaOffsetArcseconds: sample.offset,
        );
        input.validate();
        expect(input.ayanamsaLabel, '${entry.key.label}${sample.suffix}');
        final restored = _roundTrip(input);
        expect(restored.ayanamsa, entry.key);
        expect(restored.ayanamsaOffsetArcseconds, sample.offset);
        expect(restored.ayanamsaLabel, input.ayanamsaLabel);
        expect(restored.fingerprint, input.fingerprint);
        if (sample.offset == 0) {
          expect(input.fingerprint, baseline.fingerprint);
          expect(
            input.toJson().containsKey('ayanamsa_offset_arcseconds'),
            isFalse,
          );
        } else {
          expect(input.fingerprint, isNot(baseline.fingerprint));
        }
      }
    }
  });

  test('nonfinite and out-of-range corrections fail before initialization',
      () async {
    // This guard never loads a DLL, accesses assets, or requests a directory.
    // It also catches a regression that moves validation after initialize().
    final guard = _InitializationGuardEngine();
    for (final offset in const [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1296000.0,
      -1296000.0,
      1296000.125,
      -1296000.125,
    ]) {
      final input = AstrologyInput(
        utc: _referenceDates.last,
        place: _bengaluru,
        ayanamsaOffsetArcseconds: offset,
      );
      // A decoded map can contain nonfinite numbers even though JSON text
      // cannot. Both construction paths must be rejected by calculate().
      for (final candidate in [
        input,
        AstrologyInput.fromJson(input.toJson()),
      ]) {
        expect(candidate.validate, throwsFormatException);
        await expectLater(
          guard.calculate(candidate),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('ayanamsha adjustment'),
            ),
          ),
          reason: 'correction $offset must not reach initialization',
        );
        expect(guard.initializationAttempts, 0);
      }
    }
    for (final offset in const [1295999.875, -1295999.875]) {
      expect(
        AstrologyInput(ayanamsaOffsetArcseconds: offset).validate,
        returnsNormally,
      );
    }
  });

  // Match astrology_ephemeris_test.dart's per-file native library discovery.
  final library = [
    const String.fromEnvironment('ASTROLOGY_TEST_LIBRARY'),
    'build/astrology_ephemeris/Release/sweph.dll',
    'build/windows/x64/runner/Debug/sweph.dll',
  ].where((path) => path.isNotEmpty && File(path).existsSync()).firstOrNull;

  group(
    'native ayanamsa ephemeris',
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
      setUp(engine.clearCache);
      tearDown(() {
        Sweph.swe_set_sid_mode(SiderealMode(1));
      });
      tearDownAll(() async {
        Sweph.swe_close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      for (final entry in _presetIds.entries) {
        test(
          '${entry.key.name} matches direct mode ${entry.value} in 1900 and 2026',
          () async {
            for (final utc in _referenceDates) {
              for (final trueNode in [false, true]) {
                final input = AstrologyInput(
                  utc: utc,
                  place: _bengaluru,
                  ayanamsa: entry.key,
                  trueNode: trueNode,
                );
                final reference = _directReference(input, entry.value);
                final chart = await engine.calculate(input);
                _expectMatchesDirect(chart, reference);
                expect(chart.input.ayanamsa, entry.key);
                expect(chart.input.trueNode, trueNode);
              }
            }
          },
        );
      }

      for (final offset in _offsets) {
        test(
          '$offset arcseconds rotates nine planets and Asc/MC for every preset',
          () async {
            for (final entry in _presetIds.entries) {
              for (final utc in _referenceDates) {
                for (final trueNode in [false, true]) {
                  final input = AstrologyInput(
                    utc: utc,
                    place: _bengaluru,
                    ayanamsa: entry.key,
                    trueNode: trueNode,
                  );
                  final reference = _directReference(input, entry.value);
                  final baseline = await engine.calculate(input);
                  final adjusted = await engine.calculate(
                    input.copyWith(ayanamsaOffsetArcseconds: offset),
                  );
                  final correction = offset / 3600;
                  _expectMatchesDirect(
                    adjusted,
                    reference,
                    correctionDegrees: correction,
                  );
                  expect(
                    adjusted.ayanamsaDegrees,
                    closeTo(
                      baseline.ayanamsaDegrees + correction,
                      _longitudeTolerance,
                    ),
                  );
                  for (final body in VedicBody.values) {
                    final before = baseline.planet(body);
                    final after = adjusted.planet(body);
                    final reason = '${entry.key.name} $utc $offset ${body.name}'
                        ' trueNode=$trueNode';
                    _expectLongitude(
                      after.longitude,
                      before.longitude - correction,
                      reason: reason,
                    );
                    // These are native values, not coordinates rotated by
                    // the custom correction (especially declination).
                    expect(after.latitude, before.latitude, reason: reason);
                    expect(
                      after.declination,
                      before.declination,
                      reason: reason,
                    );
                    expect(after.speed, before.speed, reason: reason);
                  }
                  _expectLongitude(
                    adjusted.ascendant,
                    baseline.ascendant - correction,
                    reason: '${entry.key.name} Asc $offset',
                  );
                  _expectLongitude(
                    adjusted.midheaven,
                    baseline.midheaven - correction,
                    reason: '${entry.key.name} MC $offset',
                  );
                  _expectUnchangedClocks(adjusted, baseline);
                }
              }
            }
          },
        );
      }

      test('presets and corrections preserve solar events and Vedic clocks',
          () async {
        for (final sample in _solarCases) {
          final input = AstrologyInput(utc: sample.utc, place: _bengaluru);
          final baseline = await engine.calculate(input);
          expect(baseline.sunrise, isNotNull, reason: sample.name);
          expect(baseline.sunset, isNotNull, reason: sample.name);
          expect(baseline.nextSunrise, isNotNull, reason: sample.name);
          expect(baseline.sunrise!.isBefore(baseline.utc), isTrue);
          expect(baseline.nextSunrise!.isAfter(baseline.utc), isTrue);
          expect(
            baseline.utc.isBefore(baseline.sunset!),
            sample.dayBirth,
            reason: sample.name,
          );
          if (sample.name == 'pre-dawn') {
            expect(
              AstrologyTime.localTime(input, baseline.sunrise!).day,
              10,
            );
          }
          for (final preset in _presetIds.keys) {
            for (final offset in [0.0, ..._offsets]) {
              final chart = await engine.calculate(
                input.copyWith(
                  ayanamsa: preset,
                  ayanamsaOffsetArcseconds: offset,
                ),
              );
              _expectUnchangedClocks(chart, baseline);
            }
          }
        }
      });

      test('Bhava Hora Ghati Gulika and Maandi rotate by the correction',
          () async {
        for (final preset in _presetIds.keys) {
          for (final sample in _solarCases) {
            final input = AstrologyInput(
              utc: sample.utc,
              place: _bengaluru,
              ayanamsa: preset,
            );
            final baseline = await engine.calculate(input);
            expect(baseline.sunset, isNotNull, reason: sample.name);
            expect(
              baseline.utc.isBefore(baseline.sunset!),
              sample.dayBirth,
            );
            expect(
              baseline.specialLagnas.map((point) => point.shortName),
              unorderedEquals([..._rotatingLagnas, 'SL']),
            );
            for (final offset in _offsets) {
              final adjusted = await engine.calculate(
                input.copyWith(ayanamsaOffsetArcseconds: offset),
              );
              for (final name in _rotatingLagnas) {
                _expectLongitude(
                  _special(adjusted, name).longitude,
                  _special(baseline, name).longitude - offset / 3600,
                  reason: '${preset.name} ${sample.name} $name $offset',
                );
              }
            }
          }
        }
      });

      test('Sri Lagna recomputes adjusted Moon fraction and adjusted Asc',
          () async {
        for (final entry in _presetIds.entries) {
          for (final utc in _referenceDates) {
            final input = AstrologyInput(
              utc: utc,
              place: _bengaluru,
              ayanamsa: entry.key,
            );
            final reference = _directReference(input, entry.value);
            final baseline = await engine.calculate(input);
            final moon = reference.planets[VedicBody.moon]!.longitude;
            _expectLongitude(
              _special(baseline, 'SL').longitude,
              _sriLagna(moon, reference.ascendant),
              reason: '${entry.key.name} $utc baseline Sri Lagna',
            );
            for (final offset in _offsets) {
              final correction = offset / 3600;
              final adjusted = await engine.calculate(
                input.copyWith(ayanamsaOffsetArcseconds: offset),
              );
              final sri = _special(adjusted, 'SL').longitude;
              _expectLongitude(
                sri,
                _sriLagna(
                  moon - correction,
                  reference.ascendant - correction,
                ),
                reason: '${entry.key.name} $utc Sri Lagna $offset',
              );
              expect(
                _angularError(
                  sri,
                  _special(baseline, 'SL').longitude - correction,
                ),
                greaterThan(1),
                reason: 'Rotating the final Sri Lagna is not recomputation.',
              );
            }
          }
        }
      });

      test('cache identity includes preset and full fractional correction',
          () async {
        final base = AstrologyInput(
          utc: _referenceDates.last,
          place: _bengaluru,
        );
        final inputs = [
          for (final preset in _presetIds.keys)
            for (final offset in [0.0, ..._offsets])
              base.copyWith(
                ayanamsa: preset,
                ayanamsaOffsetArcseconds: offset,
              ),
          base.copyWith(ayanamsaOffsetArcseconds: 3600),
          base.copyWith(ayanamsaOffsetArcseconds: -7200),
        ];
        // 23 entries fit in the 24-chart cache. The extra whole-arcsecond
        // values distinguish fractional corrections from rounded cache keys.
        expect(inputs, hasLength(23));
        final fingerprints = <String>{};
        final charts = <AstrologyChart>[];
        for (final input in inputs) {
          expect(fingerprints.add(input.fingerprint), isTrue);
          final reference = _directReference(
            input,
            _presetIds[input.ayanamsa]!,
          );
          final chart = await engine.calculate(input);
          expect(charts.any((previous) => identical(previous, chart)), isFalse);
          expect(chart.input.fingerprint, input.fingerprint);
          _expectMatchesDirect(
            chart,
            reference,
            correctionDegrees: input.ayanamsaOffsetArcseconds / 3600,
          );
          charts.add(chart);
        }
        for (final chart in charts.reversed) {
          // A cache hit must return its own immutable chart even while Swiss
          // currently holds another mode. Calls remain sequential.
          Sweph.swe_set_sid_mode(SiderealMode(21));
          expect(
            await engine.calculate(_roundTrip(chart.input)),
            same(chart),
          );
        }
        expect(
          await engine.calculate(base.copyWith(ayanamsaOffsetArcseconds: -0.0)),
          same(charts.first),
        );
      });

      test('cleared-cache Lahiri resets a different global Swiss mode',
          () async {
        for (final utc in _referenceDates) {
          final input = AstrologyInput(utc: utc, place: _bengaluru);
          final reference = _directReference(input, 1);
          final baseline = await engine.calculate(input);
          await engine.calculate(
            input.copyWith(
              ayanamsa: AstrologyAyanamsa.suryaSiddhanta,
              ayanamsaOffsetArcseconds: _offsets.first,
            ),
          );
          Sweph.swe_set_sid_mode(SiderealMode(29));
          engine.clearCache();
          final fresh = await engine.calculate(_roundTrip(input));
          expect(fresh, isNot(same(baseline)));
          _expectMatchesDirect(fresh, reference);
          _expectUnchangedClocks(fresh, baseline);
          expect(fresh.specialLagnas, hasLength(baseline.specialLagnas.length));
          for (final point in baseline.specialLagnas) {
            _expectLongitude(
              _special(fresh, point.shortName).longitude,
              point.longitude,
              reason: '$utc fresh Lahiri ${point.shortName}',
            );
          }
        }
      });

      test('custom settings preserve DST choice and birth UTC microseconds',
          () async {
        expect(
          () => AstrologyTime.parseBirthTime(
            date: '2024-03-10',
            time: '02:30:15',
            place: _newYork,
          ),
          throwsFormatException,
        );
        expect(
          () => AstrologyTime.parseBirthTime(
            date: '2024-11-03',
            time: '01:30:15',
            place: _newYork,
          ),
          throwsFormatException,
        );
        final instants = <DateTime>[];
        for (final choice in const [
          (offsetMinutes: -240, utcHour: 5),
          (offsetMinutes: -300, utcHour: 6),
        ]) {
          final utc = AstrologyTime.parseBirthTime(
            date: '2024-11-03',
            time: '01:30:15',
            place: _newYork,
            offsetMinutes: choice.offsetMinutes,
          ).add(const Duration(microseconds: 123456));
          expect(
            utc,
            DateTime.utc(2024, 11, 3, choice.utcHour, 30, 15, 123, 456),
          );
          instants.add(utc);
          final input = AstrologyInput(
            name: 'DST overlap',
            utc: utc,
            place: _newYork,
            utcOffsetMinutes: choice.offsetMinutes,
            trueNode: true,
          );
          final reference = _directReference(input, 1);
          final wholeSecond = _directReference(
            input.copyWith(
              utc: utc.subtract(const Duration(microseconds: 123456)),
            ),
            1,
          );
          final baseline = await engine.calculate(input);
          expect(baseline.julianDay, reference.julianDay);
          expect(baseline.julianDay, isNot(wholeSecond.julianDay));
          for (final preset in _presetIds.keys) {
            for (final offset in _offsets) {
              final changed = input.copyWith(
                ayanamsa: preset,
                ayanamsaOffsetArcseconds: offset,
              );
              final restored = _roundTrip(changed);
              expect(restored.utc!.isUtc, isTrue);
              expect(
                restored.utc!.microsecondsSinceEpoch,
                utc.microsecondsSinceEpoch,
              );
              expect(restored.utcOffsetMinutes, choice.offsetMinutes);
              expect(restored.trueNode, isTrue);
              expect(restored.place!.toJson(), input.place!.toJson());
              expect(
                AstrologyTime.localTime(restored, utc),
                DateTime.utc(2024, 11, 3, 1, 30, 15, 123, 456),
              );
              expect(
                AstrologyTime.offsetAt(restored, utc),
                Duration(minutes: choice.offsetMinutes),
              );
              // The same saved instant also retains the historical IANA DST
              // offset when no manual override is supplied.
              final automatic = AstrologyInput(
                utc: utc,
                place: _newYork,
                ayanamsa: preset,
                ayanamsaOffsetArcseconds: offset,
              );
              expect(
                AstrologyTime.offsetAt(_roundTrip(automatic), utc),
                Duration(minutes: choice.offsetMinutes),
              );
              final chart = await engine.calculate(restored);
              expect(chart.julianDay, reference.julianDay);
              _expectUnchangedClocks(chart, baseline);
            }
          }
        }
        expect(
            instants.last.difference(instants.first), const Duration(hours: 1));
      });

      test('offset-driven Moon cusps update sign nakshatra pada and Sri Lagna',
          () async {
        const cusps = [
          (
            longitude: 0.0,
            before: (sign: 11, mansion: 26, pada: 4),
            after: (sign: 0, mansion: 0, pada: 1),
          ),
          (
            longitude: 40 / 3,
            before: (sign: 0, mansion: 0, pada: 4),
            after: (sign: 0, mansion: 1, pada: 1),
          ),
          (
            longitude: 30.0,
            before: (sign: 0, mansion: 2, pada: 1),
            after: (sign: 1, mansion: 2, pada: 2),
          ),
        ];
        for (final entry in _presetIds.entries) {
          final input = AstrologyInput(
            utc: _referenceDates.last,
            place: _bengaluru,
            ayanamsa: entry.key,
          );
          final reference = _directReference(input, entry.value);
          final nativeMoon = reference.planets[VedicBody.moon]!.longitude;
          for (final cusp in cusps) {
            for (final side in [-1, 1]) {
              final target = cusp.longitude + side * _cuspEpsilon;
              final offset = (nativeMoon - target) * 3600;
              final correction = offset / 3600;
              final chart = await engine.calculate(
                input.copyWith(ayanamsaOffsetArcseconds: offset),
              );
              final moon = chart.planet(VedicBody.moon);
              final expected = side < 0 ? cusp.before : cusp.after;
              final reason = '${entry.key.name} Moon cusp ${cusp.longitude}'
                  ' side=$side';
              _expectLongitude(moon.longitude, target, reason: reason);
              expect(moon.sign, expected.sign, reason: reason);
              expect(
                moon.nakshatra,
                nakshatraNames[expected.mansion],
                reason: reason,
              );
              expect(moon.pada, expected.pada, reason: reason);
              _expectMatchesDirect(
                chart,
                reference,
                correctionDegrees: correction,
              );
              _expectLongitude(
                _special(chart, 'SL').longitude,
                _sriLagna(
                  nativeMoon - correction,
                  reference.ascendant - correction,
                ),
                reason: '$reason Sri Lagna',
              );
            }
          }
        }
      });

      test('offset-driven Asc cusps wrap and recompute Sri Lagna', () async {
        for (final entry in _presetIds.entries) {
          final input = AstrologyInput(
            utc: _referenceDates.last,
            place: _bengaluru,
            ayanamsa: entry.key,
          );
          final reference = _directReference(input, entry.value);
          for (final boundary in [0.0, 30.0]) {
            for (final side in [-1, 1]) {
              final target = boundary + side * _cuspEpsilon;
              final offset = (reference.ascendant - target) * 3600;
              final correction = offset / 3600;
              final chart = await engine.calculate(
                input.copyWith(ayanamsaOffsetArcseconds: offset),
              );
              final upperSign = boundary == 0 ? 0 : 1;
              final reason = '${entry.key.name} Asc cusp $boundary side=$side';
              _expectLongitude(chart.ascendant, target, reason: reason);
              expect(
                chart.lagna.sign,
                side < 0 ? (upperSign + 11) % 12 : upperSign,
                reason: reason,
              );
              _expectMatchesDirect(
                chart,
                reference,
                correctionDegrees: correction,
              );
              _expectLongitude(
                _special(chart, 'SL').longitude,
                _sriLagna(
                  reference.planets[VedicBody.moon]!.longitude - correction,
                  reference.ascendant - correction,
                ),
                reason: '$reason Sri Lagna',
              );
            }
          }
        }
      });
    },
    skip: library == null
        ? 'Build the Swiss Ephemeris native library before this group.'
        : false,
  );
}

AstrologyInput _roundTrip(AstrologyInput input) => AstrologyInput.fromJson(
      jsonDecode(jsonEncode(input.toJson())) as Map<String, Object?>,
    );

// Keep the oracle's angular arithmetic independent of the model helpers.
double _wrap(double degrees) => (degrees % 360 + 360) % 360;

double _angularError(double actual, double expected) =>
    ((actual - expected + 180) % 360 - 180).abs();

void _expectLongitude(
  double actual,
  double expected, {
  required String reason,
}) {
  expect(actual.isFinite, isTrue, reason: reason);
  expect(actual, greaterThanOrEqualTo(0), reason: reason);
  expect(actual, lessThan(360), reason: reason);
  expect(
    _angularError(actual, expected),
    lessThanOrEqualTo(_longitudeTolerance),
    reason: '$reason: expected ${_wrap(expected)}°, got $actual°',
  );
}

VedicPlacement _special(AstrologyChart chart, String shortName) =>
    chart.specialLagnas.singleWhere((point) => point.shortName == shortName);

double _sriLagna(double moon, double ascendant) {
  const mansionWidth = 40 / 3;
  final fraction = (_wrap(moon) % mansionWidth) / mansionWidth;
  return _wrap(ascendant + fraction * 360);
}

_NativeReference _directReference(AstrologyInput input, int nativeMode) {
  // Eager, synchronous calculations only: Swiss has mutable global state.
  // Use the selected mode directly, not tropical minus a mean ayanamsa.
  // In particular, do not introduce NONUT or TRUEPOS for fixed-star presets.
  Sweph.swe_set_sid_mode(SiderealMode(nativeMode));
  try {
    final utc = input.utc!;
    final place = input.place!;
    final seconds =
        utc.second + (utc.millisecond * 1000 + utc.microsecond) / 1000000;
    final jd = Sweph.swe_utc_to_jd(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      seconds,
      CalendarType.SE_GREG_CAL,
    )[1];
    final houses = Sweph.swe_houses_ex2(
      jd,
      SwephFlag.SEFLG_SIDEREAL,
      place.latitude,
      place.longitude,
      Hsys.W,
    );
    final siderealFlags = SwephFlag.SEFLG_SWIEPH |
        SwephFlag.SEFLG_SIDEREAL |
        SwephFlag.SEFLG_SPEED;
    final equatorialFlags = SwephFlag.SEFLG_SWIEPH | SwephFlag.SEFLG_EQUATORIAL;
    final planets = <VedicBody, _NativePosition>{};
    for (final entry in _bodyIds.entries) {
      final id =
          entry.key == VedicBody.rahu && input.trueNode ? 11 : entry.value;
      final ecliptic = Sweph.swe_calc_ut(jd, HeavenlyBody(id), siderealFlags);
      final equatorial =
          Sweph.swe_calc_ut(jd, HeavenlyBody(id), equatorialFlags);
      planets[entry.key] = (
        longitude: ecliptic.longitude,
        latitude: ecliptic.latitude,
        declination: equatorial.latitude,
        speed: ecliptic.speedInLongitude,
      );
    }
    final rahu = planets[VedicBody.rahu]!;
    planets[VedicBody.ketu] = (
      longitude: _wrap(rahu.longitude + 180),
      latitude: -rahu.latitude,
      declination: -rahu.declination,
      speed: rahu.speed,
    );
    return (
      julianDay: jd,
      ayanamsaDegrees: Sweph.swe_get_ayanamsa_ex_ut(jd, SwephFlag.SEFLG_SWIEPH),
      ascendant: houses.ascmc[0],
      midheaven: houses.ascmc[1],
      planets: planets,
    );
  } finally {
    // Never leave the oracle's selected mode implicit for the next caller.
    Sweph.swe_set_sid_mode(SiderealMode(1));
  }
}

void _expectMatchesDirect(
  AstrologyChart chart,
  _NativeReference reference, {
  double correctionDegrees = 0,
}) {
  final reason = '${chart.input.ayanamsaLabel} ${chart.utc}'
      ' trueNode=${chart.input.trueNode}';
  expect(chart.julianDay, reference.julianDay, reason: reason);
  expect(
    chart.ayanamsaDegrees,
    closeTo(reference.ayanamsaDegrees + correctionDegrees, _longitudeTolerance),
    reason: '$reason correction is ADDED to ayanamsa',
  );
  _expectLongitude(
    chart.ascendant,
    reference.ascendant - correctionDegrees,
    reason: '$reason Asc',
  );
  _expectLongitude(
    chart.midheaven,
    reference.midheaven - correctionDegrees,
    reason: '$reason MC',
  );
  expect(chart.planets, hasLength(9));
  expect(
    chart.planets.map((point) => point.body),
    unorderedEquals(VedicBody.values),
  );
  for (final body in VedicBody.values) {
    final actual = chart.planet(body);
    final native = reference.planets[body]!;
    _expectLongitude(
      actual.longitude,
      native.longitude - correctionDegrees,
      reason: '$reason ${body.name}',
    );
    expect(actual.latitude, closeTo(native.latitude, 1e-12), reason: reason);
    expect(
      actual.declination,
      closeTo(native.declination, 1e-12),
      reason: '$reason ${body.name} native equatorial declination',
    );
    expect(actual.speed, closeTo(native.speed, 1e-12), reason: reason);
  }
}

void _expectUnchangedClocks(AstrologyChart actual, AstrologyChart baseline) {
  final reason = '${actual.input.ayanamsaLabel} ${actual.utc}';
  expect(actual.utc, baseline.utc, reason: reason);
  expect(actual.input.utc, baseline.input.utc, reason: reason);
  expect(
    actual.input.utcOffsetMinutes,
    baseline.input.utcOffsetMinutes,
    reason: reason,
  );
  expect(actual.julianDay, baseline.julianDay, reason: reason);
  expect(actual.sunrise, baseline.sunrise, reason: reason);
  expect(actual.sunset, baseline.sunset, reason: reason);
  expect(actual.nextSunrise, baseline.nextSunrise, reason: reason);
  expect(actual.weekday, baseline.weekday, reason: reason);
  expect(actual.localMeanHours, baseline.localMeanHours, reason: reason);
  expect(
    AstrologyTime.offsetAt(actual.input, actual.utc),
    AstrologyTime.offsetAt(baseline.input, baseline.utc),
    reason: reason,
  );
  expect(
    AstrologyTime.localTime(actual.input, actual.utc),
    AstrologyTime.localTime(baseline.input, baseline.utc),
    reason: reason,
  );
}

class _InitializationGuardEngine extends AstrologyEngine {
  int initializationAttempts = 0;

  @override
  Future<void> initialize({
    String? modulePath,
    String? ephemerisDirectory,
  }) async {
    initializationAttempts++;
    throw StateError('Invalid input reached ephemeris initialization.');
  }
}
