import 'package:lat_lng_to_timezone/lat_lng_to_timezone.dart' as geo_tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'astrology_model.dart';

abstract final class AstrologyTime {
  static bool _ready = false;

  static void initialize() {
    if (_ready) return;
    tz_data.initializeTimeZones();
    _ready = true;
  }

  static String zoneAt(double latitude, double longitude) =>
      geo_tz.latLngToTimezoneString(latitude, longitude);

  static tz.Location location(String zone) {
    initialize();
    try {
      return tz.getLocation(zone);
    } on Object {
      throw const FormatException(
        'Choose a valid IANA time zone or enter a UTC offset.',
      );
    }
  }

  static Duration offsetAt(AstrologyInput input, DateTime utc) {
    final manual = input.utcOffsetMinutes;
    if (manual != null) return Duration(minutes: manual);
    final place = input.place;
    if (place == null) return utc.toLocal().timeZoneOffset;
    return tz.TZDateTime.from(utc.toUtc(), location(place.timeZone))
        .timeZoneOffset;
  }

  /// A wall-clock representation, deliberately independent of the PC's zone.
  static DateTime localTime(AstrologyInput input, DateTime utc) =>
      utc.toUtc().add(offsetAt(input, utc));

  static String offsetLabel(Duration offset) {
    final minutes = offset.inMinutes.abs();
    return '${offset.isNegative ? '−' : '+'}'
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
  }

  static int? parseOffset(String text) {
    final value = text.trim().replaceAll('−', '-');
    if (value.isEmpty) return null;
    final match = RegExp(r'^([+-]?)(\d{1,2}):(\d{2})$').firstMatch(value);
    int? minutes;
    if (match != null) {
      final part = int.parse(match[3]!);
      if (part < 60) {
        minutes =
            (int.parse(match[2]!) * 60 + part) * (match[1] == '-' ? -1 : 1);
      }
    } else {
      final hours = double.tryParse(value);
      if (hours != null && hours.isFinite) minutes = (hours * 60).round();
    }
    if (minutes == null || minutes.abs() > 840) {
      throw const FormatException(
        'Use a UTC offset such as +05:30 or −04:00 (±14 hours maximum).',
      );
    }
    return minutes;
  }

  /// Validates wall-clock components without resolving a time zone or instant.
  /// Empty fields use [now], which must already represent the birthplace clock.
  /// The UTC DateTime is only a component container, not a converted birth time.
  static DateTime parseWallTime({
    required String date,
    required String time,
    required DateTime now,
  }) {
    final dateMatch =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date.trim());
    final timeMatch =
        RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(time.trim());
    if (date.trim().isNotEmpty && dateMatch == null) {
      throw const FormatException('Use YYYY-MM-DD for the birth date.');
    }
    if (time.trim().isNotEmpty && timeMatch == null) {
      throw const FormatException(
        'Use 24-hour HH:mm or HH:mm:ss for the birth time.',
      );
    }
    final year = dateMatch == null ? now.year : int.parse(dateMatch[1]!);
    final month = dateMatch == null ? now.month : int.parse(dateMatch[2]!);
    final day = dateMatch == null ? now.day : int.parse(dateMatch[3]!);
    final hour = timeMatch == null ? now.hour : int.parse(timeMatch[1]!);
    final minute = timeMatch == null ? now.minute : int.parse(timeMatch[2]!);
    final second =
        timeMatch == null ? now.second : int.parse(timeMatch[3] ?? '0');
    final wall = DateTime.utc(year, month, day, hour, minute, second);
    if (wall.year != year ||
        wall.month != month ||
        wall.day != day ||
        wall.hour != hour ||
        wall.minute != minute ||
        wall.second != second) {
      throw const FormatException('That calendar date or time does not exist.');
    }
    if (year < 1800 || year >= 2400) {
      throw const FormatException('The bundled ephemeris covers 1800–2399.');
    }
    return wall;
  }

  /// Empty date/time fields use today's date/current time at the selected place.
  /// DST gaps are rejected; overlaps require an explicit offset, never a guess.
  static DateTime parseBirthTime({
    required String date,
    required String time,
    required AstrologyPlace place,
    int? offsetMinutes,
    DateTime? now,
  }) {
    final input = AstrologyInput(place: place, utcOffsetMinutes: offsetMinutes);
    input.validate();
    final localNow = localTime(input, now ?? DateTime.now().toUtc());
    final wall = parseWallTime(date: date, time: time, now: localNow);
    final year = wall.year;
    final month = wall.month;
    final day = wall.day;
    final hour = wall.hour;
    final minute = wall.minute;
    final second = wall.second;
    if (offsetMinutes != null) {
      return wall.subtract(Duration(minutes: offsetMinutes));
    }

    final zone = location(place.timeZone);
    final candidates = <int>{};
    // A zone has only a handful of distinct historic offsets. Testing them
    // also handles half-hour DST and historical local-mean-time offsets.
    for (final offset in zone.zones.map((zone) => zone.offset).toSet()) {
      final candidate = wall.subtract(Duration(milliseconds: offset));
      final back = tz.TZDateTime.from(candidate, zone);
      if (back.year == year &&
          back.month == month &&
          back.day == day &&
          back.hour == hour &&
          back.minute == minute &&
          back.second == second) {
        candidates.add(candidate.microsecondsSinceEpoch);
      }
    }
    if (candidates.isEmpty) {
      throw const FormatException(
        'This local time was skipped by a clock change. Check the time or specify its UTC offset.',
      );
    }
    if (candidates.length > 1) {
      throw const FormatException(
        'This local time occurred twice during a clock change. Specify the birth-time UTC offset to disambiguate it.',
      );
    }
    return DateTime.fromMicrosecondsSinceEpoch(candidates.single, isUtc: true);
  }
}
