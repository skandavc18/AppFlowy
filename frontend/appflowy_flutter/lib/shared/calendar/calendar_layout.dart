import 'dart:math' as math;

import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:flutter/foundation.dart';

/// Which reading of the calendar is on screen.
enum CalendarViewMode {
  month,
  week,
  day,
  agenda,
  year;

  bool get isTimeGrid =>
      this == CalendarViewMode.week || this == CalendarViewMode.day;

  static CalendarViewMode fromValue(Object? value) =>
      CalendarViewMode.values.firstWhere(
        (m) => m.name == value,
        orElse: () => CalendarViewMode.month,
      );
}

/// Midnight on the day [value] falls in.
DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Whether two instants land on the same day in the reader's own clock.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole days between two dates, ignoring the clock. Daylight saving makes a
/// day 23 or 25 hours long, so [Duration.inDays] is wrong here.
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return (b.difference(a).inHours / 24).round();
}

/// The first day of the week containing [day], for a week starting on
/// [firstDayOfWeek] (1 = Monday … 7 = Sunday, matching [DateTime.weekday]).
DateTime startOfWeek(DateTime day, int firstDayOfWeek) {
  final start = firstDayOfWeek.clamp(1, 7);
  final delta = (day.weekday - start + 7) % 7;
  return startOfDay(day).subtract(Duration(days: delta));
}

/// The seven (or five) weekday numbers a grid shows, in the order it draws
/// them.
List<int> weekdayOrder(int firstDayOfWeek, {bool showWeekends = true}) {
  final start = firstDayOfWeek.clamp(1, 7);
  final all = List<int>.generate(7, (i) => (start - 1 + i) % 7 + 1);
  if (showWeekends) {
    return all;
  }
  return all
      .where((d) => d != DateTime.saturday && d != DateTime.sunday)
      .toList();
}

bool isWeekend(DateTime day) =>
    day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

/// The days a month grid draws, including the leading and trailing days that
/// belong to the neighbouring months.
List<DateTime> monthGridDays(
  DateTime month, {
  int firstDayOfWeek = DateTime.monday,
  bool showWeekends = true,
}) {
  final first = DateTime(month.year, month.month);
  final gridStart = startOfWeek(first, firstDayOfWeek);
  final order = weekdayOrder(firstDayOfWeek, showWeekends: showWeekends);
  final weeks = _weeksInMonthGrid(month, firstDayOfWeek);

  final days = <DateTime>[];
  for (var week = 0; week < weeks; week++) {
    for (var offset = 0; offset < 7; offset++) {
      final day = gridStart.add(Duration(days: week * 7 + offset));
      if (order.contains(day.weekday)) {
        days.add(day);
      }
    }
  }
  return days;
}

int _weeksInMonthGrid(DateTime month, int firstDayOfWeek) {
  final first = DateTime(month.year, month.month);
  final gridStart = startOfWeek(first, firstDayOfWeek);
  final lastDay = DateTime(month.year, month.month + 1, 0);
  return (daysBetween(gridStart, lastDay) / 7).floor() + 1;
}

/// The days of one week row, in drawing order.
List<DateTime> weekDays(
  DateTime anyDayInWeek, {
  int firstDayOfWeek = DateTime.monday,
  bool showWeekends = true,
}) {
  final start = startOfWeek(anyDayInWeek, firstDayOfWeek);
  return List<DateTime>.generate(7, (i) => start.add(Duration(days: i)))
      .where((d) => showWeekends || !isWeekend(d))
      .toList();
}

/// The ISO 8601 week number, which is what "week 32" means everywhere that
/// prints one.
int isoWeekNumber(DateTime day) {
  final thursday = startOfDay(day)
      .add(Duration(days: 4 - (day.weekday == 7 ? 7 : day.weekday)));
  final firstOfYear = DateTime(thursday.year);
  return ((daysBetween(firstOfYear, thursday)) / 7).floor() + 1;
}

// ---------------------------------------------------------------------------
// Month grid
// ---------------------------------------------------------------------------

/// One event's berth inside a week row of the month grid.
///
/// A multi-day event is ONE bar spanning several columns, not one chip per
/// day — that is the whole difference between a calendar and a list of days.
@immutable
class MonthEventBar {
  const MonthEventBar({
    required this.event,
    required this.startColumn,
    required this.endColumn,
    required this.lane,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  final CalendarEvent event;

  /// Inclusive column indices within the week row.
  final int startColumn;
  final int endColumn;

  /// Which stacked line inside the cell it sits on.
  final int lane;

  /// Whether the event started before this row, or runs past its end.
  final bool continuesBefore;
  final bool continuesAfter;

  int get columnSpan => endColumn - startColumn + 1;

  @override
  bool operator ==(Object other) =>
      other is MonthEventBar &&
      other.event.id == event.id &&
      other.startColumn == startColumn &&
      other.endColumn == endColumn &&
      other.lane == lane;

  @override
  int get hashCode => Object.hash(event.id, startColumn, endColumn, lane);
}

/// A whole week row, already laid out.
@immutable
class MonthWeekLayout {
  const MonthWeekLayout({
    required this.days,
    required this.bars,
    required this.overflow,
    required this.laneCount,
  });

  final List<DateTime> days;
  final List<MonthEventBar> bars;

  /// How many events a column could not show, by column index.
  final Map<int, int> overflow;

  /// How many lanes are actually used, so a light week is not padded out.
  final int laneCount;

  int overflowAt(int column) => overflow[column] ?? 0;
}

/// Lay one week row out: multi-day bars first, then the rest, packed into the
/// lowest free lane, with anything past [maxLanes] reported as overflow.
///
/// Pure, so the whole month grid can be tested without a widget tree.
MonthWeekLayout layOutMonthWeek(
  List<DateTime> days,
  List<CalendarEvent> events, {
  required int maxLanes,
}) {
  if (days.isEmpty) {
    return const MonthWeekLayout(
      days: [],
      bars: [],
      overflow: {},
      laneCount: 0,
    );
  }

  final columnOf = <DateTime, int>{
    for (var i = 0; i < days.length; i++) days[i]: i,
  };
  final rowStart = days.first;
  final rowEnd = days.last;

  final visible = events
      .where((e) => !e.endDay.isBefore(rowStart) && !e.startDay.isAfter(rowEnd))
      .toList()
    ..sort(_monthBarOrder);

  // lane -> the last column it is occupied up to (inclusive), -1 when free.
  final lanes = <int>[];
  final bars = <MonthEventBar>[];
  final overflow = <int, int>{};

  for (final event in visible) {
    final firstDay =
        event.startDay.isBefore(rowStart) ? rowStart : event.startDay;
    final lastDay = event.endDay.isAfter(rowEnd) ? rowEnd : event.endDay;

    // A hidden weekend leaves a gap: clamp onto the nearest drawn column.
    final startColumn = _columnAtOrAfter(columnOf, days, firstDay);
    final endColumn = _columnAtOrBefore(columnOf, days, lastDay);
    if (startColumn < 0 || endColumn < 0 || endColumn < startColumn) {
      continue;
    }

    var lane = 0;
    while (lane < lanes.length && lanes[lane] >= startColumn) {
      lane++;
    }

    if (lane >= maxLanes) {
      for (var column = startColumn; column <= endColumn; column++) {
        overflow[column] = (overflow[column] ?? 0) + 1;
      }
      continue;
    }

    if (lane == lanes.length) {
      lanes.add(endColumn);
    } else {
      lanes[lane] = endColumn;
    }

    bars.add(
      MonthEventBar(
        event: event,
        startColumn: startColumn,
        endColumn: endColumn,
        lane: lane,
        continuesBefore: event.startDay.isBefore(rowStart),
        continuesAfter: event.endDay.isAfter(rowEnd),
      ),
    );
  }

  return MonthWeekLayout(
    days: days,
    bars: bars,
    overflow: overflow,
    laneCount: lanes.length,
  );
}

int _columnAtOrAfter(
  Map<DateTime, int> columnOf,
  List<DateTime> days,
  DateTime day,
) {
  final exact = columnOf[day];
  if (exact != null) {
    return exact;
  }
  for (var i = 0; i < days.length; i++) {
    if (!days[i].isBefore(day)) {
      return i;
    }
  }
  return -1;
}

int _columnAtOrBefore(
  Map<DateTime, int> columnOf,
  List<DateTime> days,
  DateTime day,
) {
  final exact = columnOf[day];
  if (exact != null) {
    return exact;
  }
  for (var i = days.length - 1; i >= 0; i--) {
    if (!days[i].isAfter(day)) {
      return i;
    }
  }
  return -1;
}

/// Longest first, then earliest, so bars form clean unbroken lines.
int _monthBarOrder(CalendarEvent a, CalendarEvent b) {
  final aSpan = daysBetween(a.startDay, a.endDay);
  final bSpan = daysBetween(b.startDay, b.endDay);
  if (aSpan != bSpan) {
    return bSpan.compareTo(aSpan);
  }
  if (a.isAllDay != b.isAllDay) {
    return a.isAllDay ? -1 : 1;
  }
  return compareCalendarEvents(a, b);
}

// ---------------------------------------------------------------------------
// Time grid (week and day)
// ---------------------------------------------------------------------------

/// One event's berth in a day column, in fractions of the column's width.
@immutable
class TimeGridPlacement {
  const TimeGridPlacement({
    required this.event,
    required this.startMinutes,
    required this.endMinutes,
    required this.left,
    required this.width,
  });

  final CalendarEvent event;

  /// Minutes from local midnight, clamped into the day being drawn.
  final double startMinutes;
  final double endMinutes;

  /// 0..1 across the column.
  final double left;
  final double width;

  double get durationMinutes => math.max(endMinutes - startMinutes, 0);

  @override
  bool operator ==(Object other) =>
      other is TimeGridPlacement &&
      other.event.id == event.id &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes &&
      other.left == left &&
      other.width == width;

  @override
  int get hashCode =>
      Object.hash(event.id, startMinutes, endMinutes, left, width);
}

/// The shortest event that still reads as a block rather than a line.
const double minimumEventMinutes = 20;

/// Place a day's timed events side by side.
///
/// Overlapping events are grouped into clusters, each cluster is packed into
/// as few columns as it needs, and every event is then widened to fill any
/// free columns to its right. That last step is what stops a lone event in a
/// busy hour rendering as a thin sliver.
List<TimeGridPlacement> layOutDayColumn(
  DateTime day,
  List<CalendarEvent> events,
) {
  final dayStart = startOfDay(day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  final timed = <_Span>[];
  for (final event in events) {
    if (event.isAllDay) {
      continue;
    }
    final start = event.start.local;
    final end = event.end?.local ?? start.add(const Duration(minutes: 20));
    if (!end.isAfter(dayStart) || !start.isBefore(dayEnd)) {
      continue;
    }
    final from = start.isBefore(dayStart) ? dayStart : start;
    final to = end.isAfter(dayEnd) ? dayEnd : end;
    final startMinutes = from.difference(dayStart).inSeconds / 60.0;
    var endMinutes = to.difference(dayStart).inSeconds / 60.0;
    if (endMinutes - startMinutes < minimumEventMinutes) {
      endMinutes = math.min(startMinutes + minimumEventMinutes, 24 * 60);
    }
    timed.add(_Span(event, startMinutes, endMinutes));
  }

  if (timed.isEmpty) {
    return const [];
  }

  timed.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) {
      return byStart;
    }
    final byEnd = b.end.compareTo(a.end);
    return byEnd != 0 ? byEnd : compareCalendarEvents(a.event, b.event);
  });

  final placements = <TimeGridPlacement>[];
  var cluster = <_Span>[];
  var clusterEnd = double.negativeInfinity;

  void flush() {
    if (cluster.isNotEmpty) {
      placements.addAll(_placeCluster(cluster));
      cluster = <_Span>[];
    }
  }

  for (final span in timed) {
    if (cluster.isNotEmpty && span.start >= clusterEnd) {
      flush();
      clusterEnd = double.negativeInfinity;
    }
    cluster.add(span);
    clusterEnd = math.max(clusterEnd, span.end);
  }
  flush();

  return placements;
}

List<TimeGridPlacement> _placeCluster(List<_Span> cluster) {
  // Pack into columns: the first column whose last event has finished.
  final columnEnds = <double>[];
  final columnOf = <int>[];

  for (final span in cluster) {
    var column = 0;
    while (column < columnEnds.length && columnEnds[column] > span.start) {
      column++;
    }
    if (column == columnEnds.length) {
      columnEnds.add(span.end);
    } else {
      columnEnds[column] = span.end;
    }
    columnOf.add(column);
  }

  final total = columnEnds.length;
  final slot = 1 / total;

  return [
    for (var i = 0; i < cluster.length; i++)
      () {
        final span = cluster[i];
        final column = columnOf[i];
        // Widen right until something actually blocks the way.
        var reach = column + 1;
        while (reach < total && !_blocked(cluster, columnOf, span, reach)) {
          reach++;
        }
        return TimeGridPlacement(
          event: span.event,
          startMinutes: span.start,
          endMinutes: span.end,
          left: column * slot,
          width: (reach - column) * slot,
        );
      }(),
  ];
}

bool _blocked(
  List<_Span> cluster,
  List<int> columnOf,
  _Span span,
  int column,
) {
  for (var i = 0; i < cluster.length; i++) {
    if (columnOf[i] != column) {
      continue;
    }
    final other = cluster[i];
    if (other.start < span.end && span.start < other.end) {
      return true;
    }
  }
  return false;
}

class _Span {
  const _Span(this.event, this.start, this.end);

  final CalendarEvent event;
  final double start;
  final double end;
}

/// Where a drag would drop, snapped to [snapMinutes].
DateTime snapToSlot(
  DateTime day,
  double minutesFromMidnight, {
  int snapMinutes = 15,
}) {
  final step = snapMinutes < 1 ? 1 : snapMinutes;
  final clamped = minutesFromMidnight.clamp(0, 24 * 60 - step).toDouble();
  final snapped = (clamped / step).round() * step;
  return startOfDay(day).add(Duration(minutes: snapped));
}

// ---------------------------------------------------------------------------
// Agenda
// ---------------------------------------------------------------------------

/// One day of the agenda, already sorted.
@immutable
class AgendaSection {
  const AgendaSection({required this.day, required this.events});

  final DateTime day;
  final List<CalendarEvent> events;
}

/// Group into one section per day that has anything, oldest first.
///
/// A multi-day event appears under every day it touches — an agenda answers
/// "what is happening today", not "what started today".
List<AgendaSection> groupAgenda(
  List<CalendarEvent> events, {
  required DateTime from,
  required DateTime to,
  bool includeEmptyDays = false,
}) {
  final byDay = <DateTime, List<CalendarEvent>>{};
  final start = startOfDay(from);
  final end = startOfDay(to);

  for (final event in events) {
    var day = event.startDay.isBefore(start) ? start : event.startDay;
    final last = event.endDay;
    var guard = 0;
    while (!day.isAfter(last) && day.isBefore(end) && guard < 400) {
      byDay.putIfAbsent(day, () => <CalendarEvent>[]).add(event);
      day = day.add(const Duration(days: 1));
      guard++;
    }
  }

  final days = <DateTime>[];
  if (includeEmptyDays) {
    for (var day = start;
        day.isBefore(end);
        day = day.add(const Duration(days: 1))) {
      days.add(day);
    }
  } else {
    days.addAll(byDay.keys);
    days.sort();
  }

  return [
    for (final day in days)
      AgendaSection(
        day: day,
        events: (byDay[day] ?? <CalendarEvent>[])..sort(compareCalendarEvents),
      ),
  ];
}
