import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ayanamsha configuration', () {
    test('legacy inputs retain Lahiri and a zero adjustment', () {
      final input = AstrologyInput.fromJson(const {});
      expect(input.ayanamsa, AstrologyAyanamsa.lahiri);
      expect(input.ayanamsaOffsetArcseconds, 0);
      expect(input.toJson(), isNot(contains('ayanamsa_offset_arcseconds')));
      expect(input.ayanamsaLabel, 'Lahiri');
      expect(
        AstrologyInput.fromJson(const {'ayanamsa': 'raman'}).ayanamsa,
        AstrologyAyanamsa.raman,
      );
      expect(
        AstrologyInput.fromJson(const {'ayanamsa': 'krishnamurti'}).ayanamsa,
        AstrologyAyanamsa.krishnamurti,
      );
    });

    test('presets use the documented Swiss Ephemeris IDs', () {
      expect(
        {for (final mode in AstrologyAyanamsa.values) mode.name: mode.swissId},
        {
          'lahiri': 1,
          'raman': 3,
          'krishnamurti': 5,
          'pushyaPaksha': 29,
          'yukteshwar': 7,
          'suryaSiddhanta': 21,
          'trueChitra': 27,
        },
      );
    });

    for (final mode in AstrologyAyanamsa.values) {
      for (final adjustment in [-3600.125, 0.0, 7.25]) {
        test('${mode.name} / $adjustment round trips without changing UTC', () {
          final input = AstrologyInput(
            name: 'Reference',
            utc: DateTime.utc(2024, 11, 3, 5, 30, 45, 123, 456),
            utcOffsetMinutes: -240,
            ayanamsa: mode,
            ayanamsaOffsetArcseconds: adjustment,
          );
          input.validate();
          final restored = AstrologyInput.fromJson(input.toJson());
          expect(restored.toJson(), input.toJson());
          expect(restored.utc, input.utc);
          expect(restored.ayanamsaOffsetArcseconds, adjustment);
          expect(
            restored.copyWith(name: 'Renamed').ayanamsaOffsetArcseconds,
            adjustment,
          );
          expect(restored.copyWith(useCurrentTime: true).ayanamsa, mode);
          expect(
            restored
                .copyWith(useCurrentLocation: true)
                .ayanamsaOffsetArcseconds,
            adjustment,
          );
        });
      }
    }

    test('cache identities include both the preset and adjustment', () {
      const input = AstrologyInput();
      final adjusted = input.copyWith(ayanamsaOffsetArcseconds: 7.5);
      expect(adjusted.fingerprint, isNot(input.fingerprint));
      expect(
        adjusted.copyWith(ayanamsa: AstrologyAyanamsa.raman).fingerprint,
        isNot(adjusted.fingerprint),
      );
      expect(
        adjusted.copyWith(ayanamsaOffsetArcseconds: 0).fingerprint,
        input.fingerprint,
      );
      expect(adjusted.ayanamsaLabel, 'Lahiri (+7.5″)');
      expect(
        input.copyWith(ayanamsaOffsetArcseconds: -60).ayanamsaLabel,
        'Lahiri (−60″)',
      );
    });

    for (final invalid in [
      double.nan,
      double.infinity,
      -double.infinity,
      1296000.0,
      -1296000.0,
    ]) {
      test('rejects invalid adjustment $invalid', () {
        expect(
          () => AstrologyInput(ayanamsaOffsetArcseconds: invalid).validate(),
          throwsFormatException,
        );
      });
    }
    test('malformed saved adjustment is not silently ignored', () {
      expect(
        () => AstrologyInput.fromJson(
          const {'ayanamsa_offset_arcseconds': 'not a number'},
        ),
        throwsFormatException,
      );
    });
  });
}
