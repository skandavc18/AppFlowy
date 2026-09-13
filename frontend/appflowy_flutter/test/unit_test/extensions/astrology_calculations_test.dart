import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vimshottari.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Vedic positions', () {
    test('normalizes negative and wrapped longitudes', () {
      expect(zodiacSign(-1), 11);
      expect(zodiacSign(360), 0);
      expect(angularDistance(359, 1), 2);
    });

    test('nakshatra and pada boundaries are half open', () {
      expect(nakshatraIndex(0), 0);
      expect(nakshatraIndex(40 / 3), 1);
      expect(nakshatraPada(10 / 3), 2);
      expect(nakshatraIndex(359.999999), 26);
      expect(nakshatraPada(359.999999), 4);
      expect(nakshatraIndex(360), 0);
    });

    test('longitude rounding cannot cross the sign or print sixty', () {
      expect(formatZodiacLongitude(29.999999), '29° Ar 59′ 59″');
      expect(formatZodiacLongitude(30), '0° Ta 00′ 00″');
    });

    test('navamsha begins correctly in all twelve natal signs', () {
      const beginnings = [0, 9, 6, 3, 0, 9, 6, 3, 0, 9, 6, 3];
      for (var sign = 0; sign < 12; sign++) {
        expect(divisionalSign(sign * 30, 9), beginnings[sign]);
        expect(
          divisionalSign(sign * 30 + 29.99999, 9),
          (beginnings[sign] + 8) % 12,
        );
      }
    });

    test('Parashari hora and unequal trimsamsa are not harmonics', () {
      expect(divisionalSign(1, 2), 4);
      expect(divisionalSign(16, 2), 3);
      expect(divisionalSign(31, 2), 3);
      expect(divisionalSign(46, 2), 4);
      expect(divisionalSign(17, 30), 8);
      expect(divisionalSign(18, 30), 2);
      expect(divisionalSign(42, 30), 11);
    });

    test('all supported divisions map every sign to a valid sign', () {
      for (final division in astrologyDivisions.keys) {
        for (var halfDegree = 0; halfDegree < 720; halfDegree++) {
          expect(
            divisionalSign(halfDegree / 2, division),
            inInclusiveRange(0, 11),
          );
        }
      }
      expect(() => divisionalSign(0, 0), throwsArgumentError);
    });
  });

  group('horoscope inputs', () {
    test('blank input really means now and device location', () {
      final input = AstrologyInput.fromJson(const {});
      expect(input.isTransit, isTrue);
      expect(input.place, isNull);
    });

    test('a saved input round trips without changing its instant', () {
      final input = AstrologyInput(
        name: 'Test person',
        utc: DateTime.utc(1990, 5, 15, 9),
        place: const AstrologyPlace(
          name: 'Bengaluru',
          latitude: 12.98,
          longitude: 77.58,
          timeZone: 'Asia/Kolkata',
        ),
        style: IndianChartStyle.south,
        trueNode: true,
      );
      expect(AstrologyInput.fromJson(input.toJson()).toJson(), input.toJson());
    });

    test('bad dates and coordinates cannot silently become today', () {
      expect(
        () => AstrologyInput.fromJson({'utc': 'not a date'}),
        throwsFormatException,
      );
      expect(
        () => AstrologyInput.fromJson({'utc': '1990-05-15T12:00:00'}),
        throwsFormatException,
      );
      expect(
        () => AstrologyPlace.fromJson({'latitude': 91, 'longitude': 0}),
        throwsFormatException,
      );
      expect(
        () => AstrologyPlace.fromJson(
          {'latitude': double.nan, 'longitude': 0},
        ),
        throwsFormatException,
      );
      expect(
        () => AstrologyInput(utc: DateTime.utc(1700)).validate(),
        throwsFormatException,
      );
    });
  });

  group('Vimshottari dasha', () {
    final birth = DateTime.utc(2000);

    test('starts with the birth nakshatra lord and totals 120 years', () {
      final periods = vimshottariPeriods(birthUtc: birth, moonLongitude: 0);
      expect(periods.first.lord, VedicBody.ketu);
      expect(periods.first.start, birth);
      expect(
        periods.last.end.difference(birth).inMicroseconds,
        (120 * 365.25636 * Duration.microsecondsPerDay).round(),
      );
    });

    test('birth balance preserves the pre-birth subperiods', () {
      final periods = vimshottariPeriods(
        birthUtc: birth,
        moonLongitude: 20,
        yearDays: 360,
      );
      expect(periods.first.lord, VedicBody.venus);
      expect(periods.first.start, birth.subtract(const Duration(days: 3600)));
      expect(periods.first.end, birth.add(const Duration(days: 3600)));
      expect(periods.first.children.first.start, periods.first.start);
      expect(dashaAt(periods, birth).first.lord, VedicBody.venus);
      expect(dashaAt(periods, birth)[1].lord, VedicBody.rahu);
    });

    test('four levels have no gaps, overlaps or truncated last periods', () {
      final periods =
          vimshottariPeriods(birthUtc: birth, moonLongitude: 156.781);
      final counts = [0, 0, 0, 0];
      void check(List<DashaPeriod> list) {
        expect(list, hasLength(9));
        for (var i = 0; i < list.length; i++) {
          final period = list[i];
          counts[period.level]++;
          expect(period.end.isAfter(period.start), isTrue);
          if (i > 0) expect(period.start, list[i - 1].end);
          final children = period.children;
          if (period.level < 3) {
            expect(children.first.start, period.start);
            expect(children.last.end, period.end);
            expect(children.every((child) => child.level == period.level + 1),
                isTrue);
            expect(
              children.fold<int>(
                0,
                (sum, child) =>
                    sum + child.end.difference(child.start).inMicroseconds,
              ),
              period.end.difference(period.start).inMicroseconds,
            );
            check(children);
          } else {
            expect(children, isEmpty);
          }
        }
      }

      check(periods);
      expect(counts, [9, 81, 729, 6561]);
      expect(dashaAt(periods, birth), hasLength(4));
      expect(dashaAt(periods, periods[1].start).first.lord, periods[1].lord);
      expect(dashaAt(periods, periods.last.end), isEmpty);
    });

    test('Sun Sookshma retains the traditional proportional duration', () {
      final root = DashaPeriod(
        lord: VedicBody.sun,
        start: birth,
        end: birth.add(const Duration(days: 2160)),
      );
      final antar = root.children.first;
      final pratyantar = antar.children.first;
      final sookshma = pratyantar.children.first;
      expect(antar.end.difference(antar.start), const Duration(days: 108));
      expect(
        pratyantar.end.difference(pratyantar.start),
        const Duration(days: 5, hours: 9, minutes: 36),
      );
      expect(
        sookshma.end.difference(sookshma.start),
        const Duration(hours: 6, minutes: 28, seconds: 48),
      );
      expect(sookshma.level, 3);
      expect(sookshma.children, isEmpty);
      expect(
        dashaAt([root], birth).map((period) => period.lord),
        [
          VedicBody.sun,
          VedicBody.sun,
          VedicBody.sun,
          VedicBody.sun,
        ],
      );
      expect(dashaAt([root], sookshma.end).last.lord, VedicBody.moon);
      expect(
        dashaAt([root], sookshma.end.subtract(const Duration(microseconds: 1)))
            .last
            .lord,
        VedicBody.sun,
      );
    });

    test('Sookshma partitions preserve awkward microsecond boundaries', () {
      for (final yearDays in [360.0, 365.25, 365.25636]) {
        final roots = vimshottariPeriods(
          birthUtc: DateTime.utc(2000, 1, 1, 0, 0, 0, 123, 456),
          moonLongitude: 17.12345,
          yearDays: yearDays,
        );
        final parent = roots[3].children[5].children[7];
        final children = parent.children;
        expect(children.first.start, parent.start);
        expect(children.last.end, parent.end);
        final firstLord = vimshottariLords.indexOf(parent.lord);
        var elapsed = 0;
        for (var index = 0; index < children.length; index++) {
          final child = children[index];
          elapsed += vimshottariYears[(firstLord + index) % 9];
          final expected =
              (BigInt.from(parent.end.difference(parent.start).inMicroseconds) *
                          BigInt.from(elapsed) +
                      BigInt.from(60)) ~/
                  BigInt.from(120);
          expect(child.end.difference(parent.start).inMicroseconds,
              expected.toInt());
          expect(child.lord, vimshottariLords[(firstLord + index) % 9]);
          if (index > 0) expect(child.start, children[index - 1].end);
          final path = dashaAt(roots, child.start);
          expect(path, hasLength(4));
          expect(path.last.start, child.start);
          expect(path.last.end, child.end);
          expect(path.every((period) => period.contains(child.start)), isTrue);
        }
        expect(dashaAt(roots, roots.last.end), isEmpty);
      }
    });
  });
}
