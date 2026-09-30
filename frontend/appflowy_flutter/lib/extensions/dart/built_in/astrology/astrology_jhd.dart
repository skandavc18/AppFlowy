import 'dart:convert';
import 'dart:typed_data';

import 'astrology_model.dart';
import 'astrology_time.dart';

/// Jagannatha Hora (.jhd) birth-data files.
///
/// Verified against the sample files shipped with JHora 8: plain text lines,
/// the chart name is the FILE name, and angles/times use a packed
/// sexagesimal "D.MMSSss" notation (19.1625 = 19:16:15).
///
///  1 month · 2 day · 3 year · 4 local time
///  5 time zone (EAST NEGATIVE: IST is -5.30)
///  6 longitude (EAST NEGATIVE: 77°35′E is -77.35) · 7 latitude (north +)
///  8 unused here · 9/10 time zone in decimal hours (east negative)
///  11 0 · 12 atlas id · 13 city · 14 country · 15–18 refraction settings
///
/// Older files stop after line 7 or 8, or store planet longitudes and a flag
/// string after line 8; only lines 1–7 are required.
class AstrologyJhdImport {
  const AstrologyJhdImport({required this.input, required this.warnings});

  final AstrologyInput input;
  final List<String> warnings;
}

/// Parses packed sexagesimal (D + M/100 + S/6000) into decimal units.
double parseJhdSexagesimal(String text, String label) {
  final value = double.tryParse(text.trim());
  if (value == null || !value.isFinite) {
    throw FormatException('The .jhd $label "$text" is not a number.');
  }
  final magnitude = value.abs();
  final whole = magnitude.floorToDouble();
  final minutes = (magnitude - whole) * 100;
  if (minutes >= 60 + 1e-6) {
    throw FormatException(
      'The .jhd $label "$text" has more than 59 minutes.',
    );
  }
  // Seconds, rounded to a microsecond to shed binary-fraction noise.
  final seconds = whole * 3600 + (magnitude - whole) * 6000;
  final rounded = (seconds * 1e6).round() / 1e6;
  return (value < 0 ? -rounded : rounded) / 3600;
}

/// Encodes decimal units as packed sexagesimal with six decimals. Seconds are
/// rounded to hundredths first, so 59.999″ can never print as 60 minutes.
String formatJhdSexagesimal(double value) {
  final centiseconds = (value.abs() * 360000).round();
  final whole = centiseconds ~/ 360000;
  final minutes = centiseconds ~/ 6000 % 60;
  final seconds = centiseconds % 6000 / 100;
  final packed = whole + minutes / 100 + seconds / 6000;
  if (centiseconds == 0) return '0.000000';
  return '${value < 0 ? '-' : ''}${packed.toStringAsFixed(6)}';
}

String _decimal(double value) =>
    value == 0 ? '0.000000' : value.toStringAsFixed(6);

String _fileText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // JHora writes the Windows ANSI code page.
    return latin1.decode(bytes);
  }
}

/// [fileName] supplies the chart name, as in JHora. Chart settings that a
/// .jhd file does not carry (style, ayanamsha, nodes) come from [settings].
AstrologyJhdImport parseJhd(
  Uint8List bytes, {
  required String fileName,
  AstrologyInput settings = const AstrologyInput(),
}) {
  final lines = const LineSplitter()
      .convert(_fileText(bytes))
      .map((line) => line.trim())
      .toList();
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  if (lines.length < 7) {
    throw const FormatException(
      'This is not a Jagannatha Hora birth file (it needs at least 7 lines).',
    );
  }
  int integer(int index, String label) {
    final value = int.tryParse(lines[index]);
    if (value == null) {
      throw FormatException('The .jhd $label "${lines[index]}" is invalid.');
    }
    return value;
  }

  final month = integer(0, 'month');
  final day = integer(1, 'day');
  final year = integer(2, 'year');
  final hours = parseJhdSexagesimal(lines[3], 'time');
  final zoneHours = parseJhdSexagesimal(lines[4], 'time zone');
  final longitude = -parseJhdSexagesimal(lines[5], 'longitude');
  final latitude = parseJhdSexagesimal(lines[6], 'latitude');
  final date = DateTime.utc(year, month, day);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      month < 1 ||
      month > 12) {
    throw FormatException('The .jhd date $year-$month-$day does not exist.');
  }
  if (year < 1800 || year >= 2400) {
    throw const FormatException('The bundled ephemeris covers 1800–2399.');
  }
  if (hours < 0 || hours >= 24) {
    throw const FormatException('The .jhd birth time is outside 00:00–24:00.');
  }
  if (zoneHours.abs() > 14) {
    throw const FormatException('The .jhd time zone is outside ±14 hours.');
  }
  AstrologyPlace(
    name: '',
    latitude: latitude,
    longitude: longitude,
    timeZone: '',
  ).validate();

  // East-negative in the file; an offset of +05:30 is stored as -5.30.
  final offset = Duration(microseconds: (-zoneHours * 3.6e9).round());
  final wall = date.add(Duration(microseconds: (hours * 3.6e9).round()));
  final utc = wall.subtract(offset);
  if (utc.year < 1800 || utc.year >= 2400) {
    throw const FormatException('The bundled ephemeris covers 1800–2399.');
  }

  final warnings = <String>[];
  if (lines.length >= 10) {
    final decimal = double.tryParse(lines[8]);
    // Old files store planet longitudes here; only a real zone is compared.
    if (decimal != null &&
        decimal.abs() <= 14 &&
        (decimal - zoneHours).abs() * 60 > 1) {
      warnings.add(
        'The file lists two different time zones '
        '(${lines[4]} and ${lines[8]}); the first was used, as in JHora’s '
        'birth-data dialog. Check the birth time zone.',
      );
    }
  }
  String text(int index) {
    if (lines.length <= index) return '';
    final value = lines[index];
    return value.toLowerCase() == 'unknown' || double.tryParse(value) != null
        ? ''
        : value;
  }

  final city = text(12);
  final country = text(13);
  final name = [city, country].where((part) => part.isNotEmpty).join(', ');
  var zone = '';
  Duration? zoneOffset;
  try {
    zone = AstrologyTime.zoneAt(latitude, longitude);
    zoneOffset = AstrologyTime.offsetAt(
      AstrologyInput(
        place: AstrologyPlace(
          name: name,
          latitude: latitude,
          longitude: longitude,
          timeZone: zone,
        ),
      ),
      utc,
    );
  } on Object {
    // No usable IANA zone here: keep the file's fixed offset instead.
    zone = '';
    zoneOffset = null;
  }
  int? manualMinutes;
  if (zoneOffset != offset) {
    // Keep the file's own offset rather than today's rules for that zone.
    manualMinutes = (offset.inMicroseconds / 6e7).round();
    if (Duration(minutes: manualMinutes) != offset) {
      warnings.add(
        'The file’s local mean time offset '
        '${astrologyJhdOffsetText(offset)} is shown rounded to the minute; '
        'the birth instant itself is exact.',
      );
    }
  }
  final baseName = fileName
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceFirst(RegExp(r'\.jhd$', caseSensitive: false), '')
      .trim();
  final input = AstrologyInput(
    name: baseName,
    utc: utc,
    place: AstrologyPlace(
      name:
          name.isEmpty ? astrologyCoordinatesLabel(latitude, longitude) : name,
      latitude: latitude,
      longitude: longitude,
      timeZone: zone,
    ),
    utcOffsetMinutes: manualMinutes,
    style: settings.style,
    ayanamsa: settings.ayanamsa,
    ayanamsaOffsetArcseconds: settings.ayanamsaOffsetArcseconds,
    trueNode: settings.trueNode,
    dashaYearDays: settings.dashaYearDays,
  );
  input.validate();
  return AstrologyJhdImport(
    input: input,
    warnings: List.unmodifiable(warnings),
  );
}

String astrologyJhdOffsetText(Duration offset) {
  final seconds = offset.inSeconds.abs();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${offset.isNegative ? '−' : '+'}${two(seconds ~/ 3600)}:'
      '${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
}

/// "12°59′N 77°35′E", used when a file names no place.
String astrologyCoordinatesLabel(double latitude, double longitude) {
  String part(double value, String positive, String negative) {
    final minutes = (value.abs() * 60).round();
    return '${minutes ~/ 60}°${(minutes % 60).toString().padLeft(2, '0')}′'
        '${value < 0 ? negative : positive}';
  }

  return '${part(latitude, 'N', 'S')} ${part(longitude, 'E', 'W')}';
}

/// Latin-1 CRLF text in the 18-line layout JHora 8 writes. [input] must have
/// a fixed birth instant and place; the file name carries its name.
Uint8List encodeJhd(AstrologyInput input) {
  final utc = input.utc;
  final place = input.place;
  if (utc == null || place == null) {
    throw const FormatException(
      'Choose a birth date, time and place before saving a .jhd file.',
    );
  }
  input.validate();
  final offset = AstrologyTime.offsetAt(input, utc);
  final local = utc.toUtc().add(offset);
  final clock = Duration(
    hours: local.hour,
    minutes: local.minute,
    seconds: local.second,
    milliseconds: local.millisecond,
    microseconds: local.microsecond,
  );
  final zoneHours = -offset.inMicroseconds / 3.6e9;
  final parts = place.name.split(',');
  final city = parts.length > 1
      ? parts.sublist(0, parts.length - 1).join(',').trim()
      : place.name.trim();
  final country = parts.length > 1 ? parts.last.trim() : '';
  String clean(String value, String fallback) {
    final text = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return text.isEmpty
        ? fallback
        : String.fromCharCodes(
            text.runes.map((rune) => rune > 0xFF ? 0x3F : rune),
          );
  }

  final lines = [
    '${local.month}',
    '${local.day}',
    '${local.year}',
    formatJhdSexagesimal(clock.inMicroseconds / 3.6e9),
    formatJhdSexagesimal(zoneHours),
    formatJhdSexagesimal(-place.longitude),
    formatJhdSexagesimal(place.latitude),
    '0.000000',
    _decimal(zoneHours),
    _decimal(zoneHours),
    '0',
    '0',
    clean(city, 'Unknown'),
    clean(country, 'Unknown'),
    '1',
    '1013.250000',
    '20.000000',
    '0',
  ];
  return Uint8List.fromList(latin1.encode('${lines.join('\r\n')}\r\n'));
}

/// A Windows-safe file name for [name], with the given extension.
String astrologyFileName(String name, String extension) {
  final base = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  return '${base.isEmpty ? 'Horoscope' : base}.$extension';
}
