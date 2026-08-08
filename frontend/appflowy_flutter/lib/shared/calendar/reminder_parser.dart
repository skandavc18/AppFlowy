import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:flutter/foundation.dart';

/// What a line of plain text turned out to mean.
///
/// The parser never decides anything on somebody's behalf: it reports what it
/// found and what it removed, and the interface shows that for review before
/// anything is saved.
@immutable
class ParsedReminder {
  const ParsedReminder({
    required this.title,
    required this.when,
    this.hasTime = false,
    this.recurrence = CalendarRecurrence.none,
    this.matchedText = '',
  });

  /// What is left after the date words are taken out.
  final String title;

  /// Null when nothing date-like was found.
  final DateTime? when;

  /// False for "on Aug 15" — a day with no hour must not fire at midnight.
  final bool hasTime;

  final CalendarRecurrence recurrence;

  /// The words the date was read from, so the interface can show what it took.
  final String matchedText;

  bool get isEmpty => when == null && title.isEmpty;
}

/// Read a date, a time and a repeat out of ordinary English.
///
/// Deliberately conservative — it recognises the handful of shapes people
/// actually type and leaves everything else in the title rather than guessing.
ParsedReminder parseReminderText(String input, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  var text = input.trim();
  if (text.isEmpty) {
    return const ParsedReminder(title: '', when: null);
  }

  final taken = <String>[];

  final repeat = _readRecurrence(text);
  if (repeat != null) {
    text = _cut(text, repeat.match);
    taken.add(repeat.match);
  }

  final time = _readTime(text);
  if (time != null) {
    text = _cut(text, time.match);
    taken.add(time.match);
  }

  final day = _readDay(text, reference);
  if (day != null) {
    text = _cut(text, day.match);
    taken.add(day.match);
  }

  DateTime? when;
  var hasTime = false;

  if (day != null || time != null) {
    final base =
        day?.day ?? DateTime(reference.year, reference.month, reference.day);
    if (time != null) {
      when = DateTime(
        base.year,
        base.month,
        base.day,
        time.hour,
        time.minute,
      );
      hasTime = true;
      // "at 9" typed at 5pm with no day means tomorrow morning.
      if (day == null && when.isBefore(reference)) {
        when = when.add(const Duration(days: 1));
      }
    } else {
      when = DateTime(base.year, base.month, base.day, 9);
      hasTime = false;
    }
  }

  return ParsedReminder(
    title: _tidy(text),
    when: when,
    hasTime: hasTime,
    recurrence: repeat?.recurrence ?? CalendarRecurrence.none,
    matchedText: taken.where((t) => t.isNotEmpty).join(' ').trim(),
  );
}

String _cut(String text, String match) {
  if (match.isEmpty) {
    return text;
  }
  final index = text.toLowerCase().indexOf(match.toLowerCase());
  if (index < 0) {
    return text;
  }
  return '${text.substring(0, index)} ${text.substring(index + match.length)}';
}

String _tidy(String text) {
  var out = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Strip the joining words the date left behind.
  out = out.replaceAll(
    RegExp(r'\s+(on|at|by|before)$', caseSensitive: false),
    '',
  );
  out = out.replaceAll(
    RegExp(r'^(on|at|by|before)\s+', caseSensitive: false),
    '',
  );
  return out.trim();
}

// ---------------------------------------------------------------------------

class _TimeMatch {
  const _TimeMatch(this.hour, this.minute, this.match);

  final int hour;
  final int minute;
  final String match;
}

/// `10 AM`, `5:30pm`, `at 17:00`, `noon`, `midnight`.
_TimeMatch? _readTime(String text) {
  final noon = RegExp(r'\b(at\s+)?(noon|midday)\b', caseSensitive: false)
      .firstMatch(text);
  if (noon != null) {
    return _TimeMatch(12, 0, noon.group(0)!);
  }
  final midnight =
      RegExp(r'\b(at\s+)?midnight\b', caseSensitive: false).firstMatch(text);
  if (midnight != null) {
    return _TimeMatch(0, 0, midnight.group(0)!);
  }

  final clock = RegExp(
    r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (clock != null) {
    var hour = int.parse(clock.group(1)!);
    final minute = int.tryParse(clock.group(2) ?? '0') ?? 0;
    final meridiem = clock.group(3)!.toLowerCase();
    if (meridiem.startsWith('p') && hour != 12) {
      hour += 12;
    } else if (meridiem.startsWith('a') && hour == 12) {
      hour = 0;
    }
    if (hour < 24 && minute < 60) {
      return _TimeMatch(hour, minute, clock.group(0)!);
    }
  }

  // 24 hour, but only with an explicit "at" or a colon — a bare "15" in
  // "Aug 15" is a date, not a time.
  final military = RegExp(
    r'\b(?:at\s+(\d{1,2})(?::(\d{2}))?|(\d{1,2}):(\d{2}))\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (military != null) {
    final hour =
        int.tryParse(military.group(1) ?? military.group(3) ?? '') ?? -1;
    final minute =
        int.tryParse(military.group(2) ?? military.group(4) ?? '0') ?? 0;
    if (hour >= 0 && hour < 24 && minute < 60) {
      return _TimeMatch(hour, minute, military.group(0)!);
    }
  }
  return null;
}

class _DayMatch {
  const _DayMatch(this.day, this.match);

  final DateTime day;
  final String match;
}

const _weekdayNames = <String, int>{
  'monday': DateTime.monday,
  'mon': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'tue': DateTime.tuesday,
  'tues': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'wed': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'thu': DateTime.thursday,
  'thurs': DateTime.thursday,
  'friday': DateTime.friday,
  'fri': DateTime.friday,
  'saturday': DateTime.saturday,
  'sat': DateTime.saturday,
  'sunday': DateTime.sunday,
  'sun': DateTime.sunday,
};

const _monthNames = <String, int>{
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

_DayMatch? _readDay(String text, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);

  final relative = RegExp(
    r'\b(today|tonight|tomorrow|day after tomorrow|next week|next month)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (relative != null) {
    final word = relative.group(1)!.toLowerCase();
    final day = switch (word) {
      'today' || 'tonight' => today,
      'tomorrow' => today.add(const Duration(days: 1)),
      'day after tomorrow' => today.add(const Duration(days: 2)),
      'next week' => today.add(const Duration(days: 7)),
      _ => DateTime(today.year, today.month + 1, today.day),
    };
    return _DayMatch(day, relative.group(0)!);
  }

  final inDays = RegExp(
    r'\bin\s+(\d{1,3})\s+(day|days|week|weeks|month|months)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (inDays != null) {
    final amount = int.parse(inDays.group(1)!);
    final unit = inDays.group(2)!.toLowerCase();
    final day = unit.startsWith('week')
        ? today.add(Duration(days: 7 * amount))
        : unit.startsWith('month')
            ? DateTime(today.year, today.month + amount, today.day)
            : today.add(Duration(days: amount));
    return _DayMatch(day, inDays.group(0)!);
  }

  // "Aug 15", "August 15 2026", "15 Aug".
  final monthFirst = RegExp(
    r'\b(?:on\s+)?(' +
        _monthNames.keys.join('|') +
        r')\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (monthFirst != null) {
    final month = _monthNames[monthFirst.group(1)!.toLowerCase()]!;
    final dayOfMonth = int.parse(monthFirst.group(2)!);
    final year = int.tryParse(monthFirst.group(3) ?? '') ??
        _yearFor(month, dayOfMonth, today);
    if (dayOfMonth >= 1 && dayOfMonth <= 31) {
      return _DayMatch(DateTime(year, month, dayOfMonth), monthFirst.group(0)!);
    }
  }

  final dayFirst = RegExp(
    r'\b(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(' +
        _monthNames.keys.join('|') +
        r')\.?(?:,?\s+(\d{4}))?\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (dayFirst != null) {
    final dayOfMonth = int.parse(dayFirst.group(1)!);
    final month = _monthNames[dayFirst.group(2)!.toLowerCase()]!;
    final year = int.tryParse(dayFirst.group(3) ?? '') ??
        _yearFor(month, dayOfMonth, today);
    if (dayOfMonth >= 1 && dayOfMonth <= 31) {
      return _DayMatch(DateTime(year, month, dayOfMonth), dayFirst.group(0)!);
    }
  }

  final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(text);
  if (iso != null) {
    final parsed = DateTime.tryParse(iso.group(0)!);
    if (parsed != null) {
      return _DayMatch(parsed, iso.group(0)!);
    }
  }

  final weekday = RegExp(
    r'\b(?:on\s+|next\s+|this\s+)?(' + _weekdayNames.keys.join('|') + r')\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (weekday != null) {
    final target = _weekdayNames[weekday.group(1)!.toLowerCase()]!;
    final wantsNext = weekday.group(0)!.toLowerCase().contains('next');
    var delta = (target - today.weekday + 7) % 7;
    if (delta == 0 || wantsNext) {
      delta += 7;
    }
    return _DayMatch(today.add(Duration(days: delta)), weekday.group(0)!);
  }

  return null;
}

/// A month already past this year means next year — "Jan 3" typed in December
/// is almost never last January.
int _yearFor(int month, int day, DateTime today) {
  final thisYear = DateTime(today.year, month, day);
  return thisYear.isBefore(today) ? today.year + 1 : today.year;
}

class _RepeatMatch {
  const _RepeatMatch(this.recurrence, this.match);

  final CalendarRecurrence recurrence;
  final String match;
}

_RepeatMatch? _readRecurrence(String text) {
  final every = RegExp(
    r'\b(every\s+day|daily|every\s+weekday|weekdays|every\s+week|weekly|every\s+month|monthly|every\s+year|yearly|annually)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (every == null) {
    return null;
  }
  final word = every.group(1)!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final kind = switch (word) {
    'every day' || 'daily' => CalendarRecurrenceKind.daily,
    'every weekday' || 'weekdays' => CalendarRecurrenceKind.weekdays,
    'every week' || 'weekly' => CalendarRecurrenceKind.weekly,
    'every month' || 'monthly' => CalendarRecurrenceKind.monthly,
    _ => CalendarRecurrenceKind.yearly,
  };
  return _RepeatMatch(CalendarRecurrence(kind: kind), every.group(0)!);
}
