import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_jhd.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Byte-for-byte layouts of files shipped with Jagannatha Hora 8.
Uint8List _file(List<String> lines) =>
    Uint8List.fromList(latin1.encode('${lines.join('\r\n')}\r\n'));

final _india = _file([
  '8',
  '15',
  '1947',
  '0.000167',
  '-5.300000',
  '-77.130000',
  '28.400000',
  '0.000000',
  '-5.500000',
  '-5.500000',
  '0',
  '105',
  'Delhi',
  'India',
]);

final _gandhi = _file([
  '10',
  '2',
  '1869',
  '7.200000',
  '-4.392667',
  '-69.490000',
  '21.370000',
  '0.000000',
  '-4.654444',
  '-4.654444',
  '0',
  '0',
  'Unknown',
  'Unknown',
]);

final _author = _file([
  '4',
  '4',
  '1970',
  '17.506666666666668',
  '-5.300000',
  '-81.080000',
  '16.100000',
  '0.000000',
  '-5.500000',
  '-5.500000',
  '0',
  '105',
  'Machilipatnam',
  'India',
  '1',
  '1013.250000',
  '20.000000',
  '0',
]);

/// The older layout: planet longitudes and a flag string after line 8.
final _raman = _file([
  '8',
  '8',
  '1912',
  '19.3800',
  '-5.30',
  '-77.35',
  '12.59',
  '0.975635',
  '112.980246',
  '53.638040',
  '141.357796',
  '133.951795',
  '222.962485',
  '122.239615',
  '40.154017',
  '352.791606',
  '309.112932',
  '000100000',
]);

final _aurobindo = _file(
  ['8', '15', '1872', '5.1700', '-5.53', '-88.20', '22.30'],
);

void main() {
  group('packed sexagesimal', () {
    test('decodes minutes and fractional seconds like JHora', () {
      expect(
        parseJhdSexagesimal('19.1625', 'time'),
        closeTo(19 + 16 / 60 + 15 / 3600, 1e-12),
      );
      expect(
        parseJhdSexagesimal('19.1615', 'time'),
        closeTo(19 + 16 / 60 + 9 / 3600, 1e-12),
      );
      expect(
        parseJhdSexagesimal('17.506666666666668', 'time'),
        closeTo(17 + 50 / 60 + 40 / 3600, 1e-9),
      );
      expect(parseJhdSexagesimal('-5.300000', 'zone'), closeTo(-5.5, 1e-12));
      expect(
        parseJhdSexagesimal('-4.392667', 'zone'),
        closeTo(-(4 + 39 / 60 + 16.002 / 3600), 1e-9),
      );
      expect(
        parseJhdSexagesimal('0.000167', 'time') * 3600,
        closeTo(1.002, 1e-9),
      );
      expect(() => parseJhdSexagesimal('5.75', 'time'), throwsFormatException);
      expect(() => parseJhdSexagesimal('x', 'time'), throwsFormatException);
    });

    test('encodes without ever printing 60 minutes', () {
      expect(formatJhdSexagesimal(19 + 16 / 60 + 15 / 3600), '19.162500');
      expect(formatJhdSexagesimal(-5.5), '-5.300000');
      expect(formatJhdSexagesimal(0), '0.000000');
      expect(formatJhdSexagesimal(-0.0), '0.000000');
      expect(formatJhdSexagesimal(74.006), '74.003600');
      expect(
        formatJhdSexagesimal(5 + 59 / 60 + 59.999 / 3600),
        '6.000000',
      );
      for (final value in [0.5, 12.98333, 77.58333, 179.99999, 33.8688]) {
        expect(
          parseJhdSexagesimal(formatJhdSexagesimal(value), 'value'),
          closeTo(value, 0.006 / 3600),
        );
      }
    });
  });

  group('reading JHora files', () {
    test('India.jhd: named place, Indian time zone rules', () {
      final result = parseJhd(_india, fileName: r'C:\data\India.jhd');
      final input = result.input;
      expect(input.name, 'India');
      expect(input.utc, DateTime.utc(1947, 8, 14, 18, 30, 1, 2));
      expect(input.place!.name, 'Delhi, India');
      expect(input.place!.latitude, closeTo(28 + 40 / 60, 1e-9));
      expect(input.place!.longitude, closeTo(77 + 13 / 60, 1e-9));
      expect(input.place!.timeZone, 'Asia/Kolkata');
      expect(input.utcOffsetMinutes, isNull);
      expect(result.warnings, isEmpty);
    });

    test('Mahatma Gandhi.jhd: local mean time kept as a fixed offset', () {
      final result = parseJhd(_gandhi, fileName: 'Mahatma Gandhi.jhd');
      final input = result.input;
      expect(input.name, 'Mahatma Gandhi');
      // 07:20 at +04:39:16.002 (the file's precision).
      expect(input.utc, DateTime.utc(1869, 10, 2, 2, 40, 43, 998));
      expect(input.place!.name, '21°37′N 69°49′E');
      expect(input.place!.latitude, closeTo(21 + 37 / 60, 1e-9));
      expect(input.place!.longitude, closeTo(69 + 49 / 60, 1e-9));
      expect(input.utcOffsetMinutes, 279);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('+04:39:16'));
    });

    test('Author of this software.jhd: 18-line layout', () {
      final input =
          parseJhd(_author, fileName: 'Author of this software.jhd').input;
      expect(input.utc, DateTime.utc(1970, 4, 4, 12, 20, 40));
      expect(input.place!.name, 'Machilipatnam, India');
      expect(input.place!.latitude, closeTo(16 + 10 / 60, 1e-9));
      expect(input.place!.longitude, closeTo(81 + 8 / 60, 1e-9));
      expect(input.utcOffsetMinutes, isNull);
    });

    test('older layouts ignore stored planet longitudes and flags', () {
      final result = parseJhd(_raman, fileName: 'Prof. B. V. Raman.jhd');
      expect(result.input.name, 'Prof. B. V. Raman');
      expect(result.input.utc, DateTime.utc(1912, 8, 8, 14, 8));
      expect(result.input.place!.name, '12°59′N 77°35′E');
      expect(result.input.place!.latitude, closeTo(12 + 59 / 60, 1e-9));
      expect(result.input.place!.longitude, closeTo(77 + 35 / 60, 1e-9));
      expect(result.warnings, isEmpty);

      final seven = parseJhd(_aurobindo, fileName: 'Aurobindo Ghose.jhd');
      expect(seven.input.utc, DateTime.utc(1872, 8, 14, 23, 24));
      expect(seven.input.utcOffsetMinutes, 353);
      expect(seven.warnings, isEmpty);
    });

    test('chart settings that JHD does not store come from the dashboard', () {
      final input = parseJhd(
        _india,
        fileName: 'India.jhd',
        settings: const AstrologyInput(
          style: IndianChartStyle.south,
          ayanamsa: AstrologyAyanamsa.raman,
          ayanamsaOffsetArcseconds: 12,
          trueNode: true,
          dashaYearDays: 360,
        ),
      ).input;
      expect(input.style, IndianChartStyle.south);
      expect(input.ayanamsa, AstrologyAyanamsa.raman);
      expect(input.ayanamsaOffsetArcseconds, 12);
      expect(input.trueNode, isTrue);
      expect(input.dashaYearDays, 360);
    });

    test('conflicting zone lines are reported, not silently merged', () {
      final lines = latin1.decode(_india).split('\r\n');
      lines[8] = '-6.500000';
      final result = parseJhd(
        Uint8List.fromList(latin1.encode(lines.join('\r\n'))),
        fileName: 'India.jhd',
      );
      expect(result.input.utc, DateTime.utc(1947, 8, 14, 18, 30, 1, 2));
      expect(result.warnings.single, contains('two different time zones'));
    });

    test('malformed files are rejected with a reason', () {
      final lines = latin1.decode(_india).split('\r\n');
      Uint8List edited(int index, String value) {
        final copy = [...lines]..[index] = value;
        return Uint8List.fromList(latin1.encode(copy.join('\r\n')));
      }

      expect(
        () => parseJhd(_file(['8', '15', '1947']), fileName: 'a.jhd'),
        throwsFormatException,
      );
      for (final (index, value) in const [
        (0, '13'),
        (1, '32'),
        (2, '1700'),
        (3, '24.000000'),
        (4, '-15.000000'),
        (6, '91.000000'),
        (0, 'August'),
      ]) {
        expect(
          () => parseJhd(edited(index, value), fileName: 'a.jhd'),
          throwsFormatException,
          reason: 'line ${index + 1} = $value',
        );
      }
      expect(
        () => parseJhd(Uint8List.fromList([0, 159, 146, 150]), fileName: 'x'),
        throwsFormatException,
      );
    });
  });

  group('writing JHora files', () {
    final bengaluru = AstrologyInput(
      name: 'Reference',
      utc: DateTime.utc(1999, 12, 18, 9, 45),
      place: const AstrologyPlace(
        name: 'Bengaluru, Karnataka, India',
        latitude: 12 + 59 / 60,
        longitude: 77 + 35 / 60,
        timeZone: 'Asia/Kolkata',
      ),
    );

    test('the 18-line layout JHora 8 writes', () {
      final text = latin1.decode(encodeJhd(bengaluru));
      expect(text, endsWith('\r\n'));
      expect(text.split('\r\n')..removeLast(), [
        '12',
        '18',
        '1999',
        '15.150000',
        '-5.300000',
        '-77.350000',
        '12.590000',
        '0.000000',
        '-5.500000',
        '-5.500000',
        '0',
        '0',
        'Bengaluru, Karnataka',
        'India',
        '1',
        '1013.250000',
        '20.000000',
        '0',
      ]);
    });

    test('round trips east, west, north and south exactly enough', () {
      final back = parseJhd(encodeJhd(bengaluru), fileName: 'Reference.jhd');
      expect(back.input.name, 'Reference');
      expect(back.input.utc, bengaluru.utc);
      expect(back.input.place!.name, 'Bengaluru, Karnataka, India');
      expect(back.input.place!.latitude, closeTo(12 + 59 / 60, 1e-9));
      expect(back.input.place!.longitude, closeTo(77 + 35 / 60, 1e-9));
      expect(back.input.utcOffsetMinutes, isNull);
      expect(back.warnings, isEmpty);

      for (final input in [
        AstrologyInput(
          name: 'New York',
          utc: DateTime.utc(2024, 7, 4, 16),
          place: const AstrologyPlace(
            name: 'New York, United States',
            latitude: 40.7128,
            longitude: -74.006,
            timeZone: 'America/New_York',
          ),
        ),
        AstrologyInput(
          name: 'Sydney',
          utc: DateTime.utc(2024, 1, 10, 1, 2, 3),
          place: const AstrologyPlace(
            name: 'Sydney, Australia',
            latitude: -33.8688,
            longitude: 151.2093,
            timeZone: 'Australia/Sydney',
          ),
        ),
      ]) {
        final text = latin1.decode(encodeJhd(input)).split('\r\n');
        final result = parseJhd(encodeJhd(input), fileName: input.name);
        expect(result.input.utc, input.utc, reason: input.name);
        expect(
          result.input.place!.latitude,
          closeTo(input.place!.latitude, 1e-6),
        );
        expect(
          result.input.place!.longitude,
          closeTo(input.place!.longitude, 1e-6),
        );
        expect(result.input.place!.timeZone, input.place!.timeZone);
        expect(result.input.utcOffsetMinutes, isNull);
        if (input.name == 'New York') {
          // West longitudes and zones are positive in JHD.
          expect(text[4], '4.000000');
          expect(text[5], '74.003600');
        } else {
          expect(text[4], '-11.000000');
          expect(text[6], startsWith('-33.52'));
        }
      }
    });

    test('names outside Latin-1 degrade to ?, never to invalid bytes', () {
      final bytes = encodeJhd(
        AstrologyInput(
          utc: DateTime.utc(2000),
          place: const AstrologyPlace(
            name: 'बेंगलुरु, São Tomé',
            latitude: 12.97,
            longitude: 77.59,
            timeZone: 'Asia/Kolkata',
          ),
        ),
      );
      final lines = latin1.decode(bytes).split('\r\n');
      expect(lines[12], '????????');
      expect(lines[13], 'São Tomé');
    });

    test('live horoscopes must be resolved first', () {
      expect(() => encodeJhd(const AstrologyInput()), throwsFormatException);
    });

    test('file names are safe on Windows', () {
      expect(astrologyFileName('Ram: "test"/1', 'jhd'), 'Ram test 1.jhd');
      expect(astrologyFileName('  ', 'pdf'), 'Horoscope.pdf');
      expect(astrologyFileName('Name. ', 'pdf'), 'Name.pdf');
    });
  });
}
