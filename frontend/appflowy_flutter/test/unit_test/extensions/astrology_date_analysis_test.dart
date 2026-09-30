import 'package:appflowy/extensions/dart/built_in/astrology/astrology_date_analysis.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_events_sync.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_panchanga.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vimshottari.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

const _place = AstrologyPlace(
  name: 'Bengaluru, India',
  latitude: 12.9716,
  longitude: 77.5946,
  timeZone: 'Asia/Kolkata',
);

const _longitudes = [10.0, 20.0, 96.0, 151.0, 215.0, 278.0, 305.0, 345.0, 165.0];
const _speeds = [0.98, 13.2, 0.4, -0.65, 0.08, 1.1, 0.02, -0.05, -0.05];

AstrologyChart _chart({
  required DateTime utc,
  List<double> longitudes = _longitudes,
  double ascendant = 33,
  DateTime? sunrise,
  DateTime? sunset,
  DateTime? nextSunrise,
  int weekday = 0,
}) =>
    AstrologyChart(
      input: AstrologyInput(
        name: 'Test',
        utc: utc,
        place: _place,
        utcOffsetMinutes: 330,
      ),
      utc: utc,
      julianDay:
          2440587.5 + utc.millisecondsSinceEpoch / Duration.millisecondsPerDay,
      ayanamsaDegrees: 23.85,
      ascendant: ascendant,
      midheaven: 300,
      planets: [
        for (final body in VedicBody.values)
          VedicPlacement(
            name: body.label,
            shortName: body.shortName,
            body: body,
            longitude: longitudes[body.index],
            speed: _speeds[body.index],
          ),
      ],
      specialLagnas: const [],
      sunrise: sunrise,
      sunset: sunset,
      nextSunrise: nextSunrise,
      weekday: weekday,
      localMeanHours: 12,
    );

void main() {
  group('panchanga names', () {
    test('tithi, paksha, karana and nakshatra lords', () {
      expect(tithiName(1), 'Pratipada');
      expect(tithiName(15), 'Purnima');
      expect(tithiName(16), 'Pratipada');
      expect(tithiName(30), 'Amavasya');
      expect(pakshaName(15), 'Shukla');
      expect(pakshaName(16), 'Krishna');
      expect(karanaName(0), 'Kimstughna');
      expect(karanaName(1), 'Bava');
      expect(karanaName(7), 'Vishti');
      expect(karanaName(8), 'Bava');
      expect(karanaName(57), 'Shakuni');
      expect(karanaName(59), 'Naga');
      expect(nakshatraLord(0), VedicBody.ketu);
      expect(nakshatraLord(3), VedicBody.moon);
      expect(nakshatraLord(26), VedicBody.mercury);
      expect(ordinal(1), '1st');
      expect(ordinal(2), '2nd');
      expect(ordinal(3), '3rd');
      expect(ordinal(11), '11th');
      expect(ordinal(12), '12th');
    });

    test('houses count whole signs, including wrap-around', () {
      expect(houseFromSign(0, 0), 1);
      expect(houseFromSign(1, 10), 10);
      expect(houseFromSign(10, 1), 4);
      expect(houseFromSign(11, 10), 12);
    });

    test('compact longitudes never show the next sign or 60 minutes', () {
      expect(compactLongitude(125.5), 'Leo 5°30′');
      expect(compactLongitude(29.99999), 'Aries 29°59′');
      expect(compactLongitude(-0.5), 'Pisces 29°30′');
      expect(compactLongitude(360), 'Aries 0°00′');
    });
  });

  group('day divisions', () {
    // 06:00–18:00 IST = 00:30–12:30 UTC.
    final sunrise = DateTime.utc(2026, 9, 28, 0, 30);
    final sunset = DateTime.utc(2026, 9, 28, 12, 30);
    final next = DateTime.utc(2026, 9, 29, 0, 30);

    AstrologyChart day(int weekday, DateTime utc) => _chart(
          utc: utc,
          sunrise: sunrise,
          sunset: sunset,
          nextSunrise: next,
          weekday: weekday,
        );

    test('Monday Rahu Kalam, Yamaganda, Gulika, Abhijit and Brahma', () {
      final windows = muhurtaWindows(
        day(1, DateTime.utc(2026, 9, 28, 6)),
        previousSunset: DateTime.utc(2026, 9, 27, 12, 30),
      );
      MuhurtaWindow named(String name) =>
          windows.singleWhere((window) => window.name == name);
      expect(windows.map((window) => window.name), [
        'Brahma muhurta',
        'Rahu Kalam',
        'Yamaganda',
        'Abhijit muhurta',
        'Gulika Kalam',
      ]);
      expect(named('Rahu Kalam').start, DateTime.utc(2026, 9, 28, 2));
      expect(named('Rahu Kalam').end, DateTime.utc(2026, 9, 28, 3, 30));
      expect(named('Yamaganda').start, DateTime.utc(2026, 9, 28, 5));
      expect(named('Gulika Kalam').start, DateTime.utc(2026, 9, 28, 8));
      expect(named('Abhijit muhurta').start, DateTime.utc(2026, 9, 28, 6, 6));
      expect(named('Abhijit muhurta').end, DateTime.utc(2026, 9, 28, 6, 54));
      expect(
        named('Abhijit muhurta').quality,
        MuhurtaQuality.favourable,
      );
      // 13/15 and 14/15 of a 12-hour night: 96 and 48 minutes before sunrise.
      expect(named('Brahma muhurta').start, DateTime.utc(2026, 9, 27, 22, 54));
      expect(named('Brahma muhurta').end, DateTime.utc(2026, 9, 27, 23, 42));
      for (final window in windows) {
        expect(window.end.isAfter(window.start), isTrue);
      }
    });

    test('every weekday uses its traditional eighth', () {
      const rahu = [8, 2, 7, 5, 6, 4, 3];
      const yama = [5, 4, 3, 2, 1, 7, 6];
      const gulika = [7, 6, 5, 4, 3, 2, 1];
      for (var weekday = 0; weekday < 7; weekday++) {
        final windows = muhurtaWindows(day(weekday, sunrise));
        DateTime start(String name) =>
            windows.singleWhere((window) => window.name == name).start;
        DateTime part(int eighth) =>
            sunrise.add(Duration(minutes: 90 * (eighth - 1)));
        expect(start('Rahu Kalam'), part(rahu[weekday]));
        expect(start('Yamaganda'), part(yama[weekday]));
        expect(start('Gulika Kalam'), part(gulika[weekday]));
        expect(
          windows.any((window) => window.name == 'Brahma muhurta'),
          isFalse,
          reason: 'No previous sunset was supplied.',
        );
      }
      final wednesday = muhurtaWindows(day(3, sunrise))
          .singleWhere((window) => window.name == 'Abhijit muhurta');
      expect(wednesday.quality, MuhurtaQuality.avoid);
    });

    test('polar days have no windows or hora', () {
      final polar = _chart(utc: sunrise);
      expect(muhurtaWindows(polar), isEmpty);
      expect(horaAt(polar), isNull);
    });

    test('horas follow the weekday lord, then the Chaldean order', () {
      HoraPeriod hora(int weekday, DateTime utc) => horaAt(day(weekday, utc))!;
      final first = hora(0, DateTime.utc(2026, 9, 28, 1));
      expect(first.lord, VedicBody.sun);
      expect(first.number, 1);
      expect(first.isDay, isTrue);
      expect(first.start, sunrise);
      expect(first.end, DateTime.utc(2026, 9, 28, 1, 30));
      expect(hora(0, DateTime.utc(2026, 9, 28, 1, 45)).lord, VedicBody.venus);
      expect(hora(1, DateTime.utc(2026, 9, 28, 1)).lord, VedicBody.moon);
      // Sunday's first night hora belongs to Jupiter.
      final night = hora(0, DateTime.utc(2026, 9, 28, 12, 45));
      expect(night.lord, VedicBody.jupiter);
      expect(night.number, 13);
      expect(night.isDay, isFalse);
      // The 25th hora would be Monday's first: the Moon.
      expect(
        [
          VedicBody.sun,
          VedicBody.venus,
          VedicBody.mercury,
          VedicBody.moon,
          VedicBody.saturn,
          VedicBody.jupiter,
          VedicBody.mars,
        ][24 % 7],
        VedicBody.moon,
      );
    });
  });

  group('natal comparisons', () {
    test('Tara bala counts nakshatras from the birth star', () {
      expect(taraBala(natalMoon: 5, moon: 5).name, 'Janma');
      expect(taraBala(natalMoon: 5, moon: 5).favourable, isNull);
      expect(taraBala(natalMoon: 5, moon: 18).name, 'Sampat');
      expect(taraBala(natalMoon: 5, moon: 18).favourable, isTrue);
      expect(taraBala(natalMoon: 5, moon: 30).name, 'Vipat');
      expect(taraBala(natalMoon: 5, moon: 30).favourable, isFalse);
      final ninth = taraBala(natalMoon: 5, moon: 8 * 40 / 3 + 1);
      expect(ninth.count, 9);
      expect(ninth.name, 'Parama Mitra');
      final tenth = taraBala(natalMoon: 5, moon: 9 * 40 / 3 + 1);
      expect(tenth.count, 10);
      expect(tenth.tara, 1);
      // Counting wraps from Revati back to Ashwini.
      expect(taraBala(natalMoon: 355, moon: 5).count, 2);
    });

    test('Chandra bala and Saturn transits from the natal Moon', () {
      expect(chandraBala(natalMoon: 5, moon: 125).house, 5);
      expect(chandraBala(natalMoon: 5, moon: 125).favourable, isFalse);
      expect(chandraBala(natalMoon: 5, moon: 65).favourable, isTrue);
      expect(chandraBala(natalMoon: 355, moon: 5).house, 2);
      expect(
        saturnTransitNote(natalMoon: 5, saturn: 345),
        contains('rising phase'),
      );
      expect(saturnTransitNote(natalMoon: 5, saturn: 15), contains('peak'));
      expect(saturnTransitNote(natalMoon: 5, saturn: 45), contains('setting'));
      expect(
        saturnTransitNote(natalMoon: 5, saturn: 95),
        contains('Ardhashtama'),
      );
      expect(saturnTransitNote(natalMoon: 5, saturn: 215), contains('Ashtama'));
      expect(saturnTransitNote(natalMoon: 5, saturn: 125), isNull);
    });

    test('Sun-based upagrahas', () {
      final points = sunUpagrahas(10);
      expect(points.map((point) => point.name), [
        'Dhuma',
        'Vyatipata',
        'Parivesha',
        'Indrachapa',
        'Upaketu',
      ]);
      expect(points[0].longitude, closeTo(143 + 1 / 3, 1e-9));
      expect(points[1].longitude, closeTo(216 + 2 / 3, 1e-9));
      expect(points[2].longitude, closeTo(36 + 2 / 3, 1e-9));
      expect(points[3].longitude, closeTo(323 + 1 / 3, 1e-9));
      // Upaketu is always 30° behind the Sun.
      expect(points[4].longitude, closeTo(340, 1e-9));
      expect(sunUpagrahas(20)[4].longitude, closeTo(350, 1e-9));
    });
  });

  group('life-event values', () {
    final natal = _chart(utc: DateTime.utc(2000, 1, 2, 6, 15));
    final event = DateTime.utc(2020, 6, 1, 6, 30);
    final positions = [
      for (final body in VedicBody.values)
        VedicPlacement(
          name: body.label,
          shortName: body.shortName,
          body: body,
          longitude: _longitudes[body.index],
          speed: _speeds[body.index],
        ),
    ];

    test('dashas through Sookshma, Moon nakshatra and transit cells', () {
      final values = astrologyEventValues(
        natal: natal,
        positions: positions,
        utc: event,
      );
      final expected = dashaAt(
        vimshottariPeriods(
          birthUtc: natal.utc,
          moonLongitude: 20,
          yearDays: natal.input.dashaYearDays,
        ),
        event,
      );
      expect(values.dasha, hasLength(4));
      expect(values.dasha, expected.map((period) => period.lord));
      // Bharani birth star: Venus MD ended 10 years after birth, then Sun and
      // the Moon; mid-2020 falls in the Moon's Saturn antardasha.
      expect(values.dasha.first, VedicBody.moon);
      expect(values.dasha[1], VedicBody.saturn);
      expect(values.moonNakshatra, 'Bharani, pada 3 · lord Venus');
      expect(values.transits, hasLength(9));
      expect(values.transits[VedicBody.saturn], 'Aquarius 5°00′ · H10 · M11');
      expect(values.transits[VedicBody.rahu], 'Pisces 15°00′ R · H11 · M12');
      expect(values.transits[VedicBody.mercury], contains(' R · '));
      expect(values.transits[VedicBody.sun], 'Aries 10°00′ · H12 · M1');
    });

    test('events outside the natal cycle have no dasha lords', () {
      final values = astrologyEventValues(
        natal: natal,
        positions: positions,
        utc: DateTime.utc(2150),
      );
      expect(values.dasha, isEmpty);
      expect(values.transits, hasLength(9));
    });

    test('the date analysis places transits in the natal chart', () {
      final moment = _chart(
        utc: event,
        longitudes: const [70, 200, 10, 20, 30, 40, 345, 100, 280],
        sunrise: DateTime.utc(2020, 6, 1, 0, 30),
        sunset: DateTime.utc(2020, 6, 1, 13),
        nextSunrise: DateTime.utc(2020, 6, 2, 0, 30),
        weekday: 1,
      );
      final analysis = analyzeAstrologyDate(moment: moment, natal: natal);
      expect(analysis.dasha, hasLength(4));
      expect(analysis.dasha.first.lord, VedicBody.moon);
      expect(analysis.transits, hasLength(9));
      final saturn = analysis.transits
          .singleWhere((transit) => transit.placement.body == VedicBody.saturn);
      expect(saturn.fromLagna, 11);
      expect(saturn.fromMoon, 12);
      expect(analysis.saturn, contains('rising phase'));
      expect(analysis.tara!.count, greaterThan(0));
      expect(analysis.chandra!.house, 7);
      expect(analysis.hora, isNotNull);
      expect(analysis.muhurtas, hasLength(4));

      final alone = analyzeAstrologyDate(moment: moment);
      expect(alone.dasha, isEmpty);
      expect(
        alone.transits.every((transit) => transit.fromLagna == null),
        isTrue,
      );
      expect(alone.tara, isNull);
      expect(alone.saturn, isNull);
    });
  });

  group('event instants', () {
    test('a time is used exactly and labelled in the device zone', () {
      final local = DateTime(2024, 3, 5, 14, 7);
      final data = DateCellDataPB(
        timestamp: Int64(local.millisecondsSinceEpoch ~/ 1000),
        includeTime: true,
      );
      final instant = astrologyEventInstant(data)!;
      expect(instant.utc, local.toUtc());
      expect(instant.label, startsWith('2024-03-05 14:07 UTC'));
      expect(instant.label, isNot(contains('noon')));
    });

    test('a date alone means local noon, stated in the label', () {
      final midnight = DateTime(2024, 3, 5);
      final data = DateCellDataPB(
        timestamp: Int64(midnight.millisecondsSinceEpoch ~/ 1000),
      );
      final instant = astrologyEventInstant(data)!;
      expect(instant.utc, DateTime(2024, 3, 5, 12).toUtc());
      expect(instant.label, startsWith('2024-03-05 12:00 UTC'));
      expect(instant.label, endsWith('no time given, noon used'));
      expect(astrologyEventInstant(DateCellDataPB()), isNull);
    });

    test('the natal key ignores chart style and names', () {
      final input = AstrologyInput(
        name: 'A',
        utc: DateTime.utc(1990),
        place: _place,
      );
      expect(
        astrologyEventsNatalKey(input),
        astrologyEventsNatalKey(
          input.copyWith(name: 'B', style: IndianChartStyle.south),
        ),
      );
      expect(
        astrologyEventsNatalKey(input),
        isNot(
          astrologyEventsNatalKey(input.copyWith(utc: DateTime.utc(1990, 1, 2))),
        ),
      );
      expect(
        astrologyEventsNatalKey(input),
        isNot(
          astrologyEventsNatalKey(
            input.copyWith(ayanamsa: AstrologyAyanamsa.raman),
          ),
        ),
      );
    });
  });
}
