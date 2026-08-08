import 'package:flutter/material.dart';

/// What a thing on the calendar actually is.
///
/// A reminder and an event are drawn differently and answer different
/// questions, but they share one place on the grid, so they share one model.
enum CalendarEventKind {
  /// Something that occupies a span of time.
  event,

  /// A single moment that asks for attention.
  reminder,

  /// Something with a completion state.
  task,
}

/// Where an event came from.
///
/// The renderer never asks this; only the parts that write back do.
enum CalendarEventOrigin {
  /// A row in an AppFlowy table.
  table,

  /// A reminder held by AppFlowy itself.
  reminder,

  /// A calendar hosted somewhere else.
  external,
}

/// An instant, kept together with the zone it was written in.
///
/// Storing the instant alone loses "9am in Berlin"; storing the wall clock
/// alone loses which instant that was. Google hands back both, and a moved
/// event has to be written back with both, so both are carried.
@immutable
class ZonedDateTime {
  const ZonedDateTime._(this._utc, this.timeZone, this.isAllDay);

  /// An instant expressed in whatever zone this machine is set to.
  factory ZonedDateTime.local(DateTime value, {String timeZone = ''}) =>
      ZonedDateTime._(value.toUtc(), timeZone, false);

  /// A whole day, which has no instant until a zone is chosen.
  factory ZonedDateTime.allDay(DateTime day) => ZonedDateTime._(
        DateTime.utc(day.year, day.month, day.day),
        '',
        true,
      );

  factory ZonedDateTime.fromUtc(DateTime utc, {String timeZone = ''}) =>
      ZonedDateTime._(
        utc.isUtc ? utc : utc.toUtc(),
        timeZone,
        false,
      );

  final DateTime _utc;

  /// The IANA name the source used, when it named one. Empty means "wherever
  /// this machine is", which is the only honest answer for a local event.
  final String timeZone;

  final bool isAllDay;

  DateTime get utc => _utc;

  /// What a person reading this machine's clock sees.
  DateTime get local =>
      isAllDay ? DateTime(_utc.year, _utc.month, _utc.day) : _utc.toLocal();

  int get millisecondsSinceEpoch => _utc.millisecondsSinceEpoch;

  ZonedDateTime shiftedBy(Duration delta) => isAllDay
      ? ZonedDateTime.allDay(local.add(delta))
      : ZonedDateTime._(_utc.add(delta), timeZone, false);

  /// Move to another day, keeping the time of day.
  ZonedDateTime onDay(DateTime day) {
    if (isAllDay) {
      return ZonedDateTime.allDay(day);
    }
    final at = local;
    return ZonedDateTime.local(
      DateTime(day.year, day.month, day.day, at.hour, at.minute, at.second),
      timeZone: timeZone,
    );
  }

  /// Move to another instant, keeping the declared zone.
  ZonedDateTime at(DateTime moment) => isAllDay
      ? ZonedDateTime.allDay(moment)
      : ZonedDateTime.local(moment, timeZone: timeZone);

  @override
  bool operator ==(Object other) =>
      other is ZonedDateTime &&
      other._utc == _utc &&
      other.timeZone == timeZone &&
      other.isAllDay == isAllDay;

  @override
  int get hashCode => Object.hash(_utc, timeZone, isAllDay);

  @override
  String toString() => isAllDay
      ? 'ZonedDateTime.allDay(${local.toIso8601String()})'
      : 'ZonedDateTime(${_utc.toIso8601String()}, $timeZone)';
}

/// How often something comes back.
enum CalendarRecurrenceKind {
  none,
  daily,
  weekdays,
  weekly,
  monthly,
  yearly,
  custom;

  bool get repeats => this != CalendarRecurrenceKind.none;
}

/// A repeat rule, kept small enough to say honestly what it does.
///
/// [custom] carries an RFC 5545 RRULE straight through, because that is what
/// a hosted calendar speaks and rewriting it would only lose meaning.
@immutable
class CalendarRecurrence {
  const CalendarRecurrence({
    this.kind = CalendarRecurrenceKind.none,
    this.interval = 1,
    this.rrule = '',
    this.until,
    this.count,
  });

  static const none = CalendarRecurrence();

  final CalendarRecurrenceKind kind;

  /// Every N days/weeks/months. Always at least 1.
  final int interval;

  /// The rule exactly as the hosting service wrote it, for [kind] custom.
  final String rrule;

  final DateTime? until;
  final int? count;

  bool get repeats => kind.repeats;

  /// The next occurrence strictly after [after], or null when it has run out.
  DateTime? nextAfter(DateTime start, DateTime after) {
    if (!repeats) {
      return null;
    }
    final step = interval < 1 ? 1 : interval;
    var next = start;
    var guard = 0;
    // A bounded walk: a rule with an interval measured in years still lands
    // inside a few hundred steps, and nothing here may loop unbounded.
    while (!next.isAfter(after) && guard < 4000) {
      next = switch (kind) {
        CalendarRecurrenceKind.daily => next.add(Duration(days: step)),
        CalendarRecurrenceKind.weekdays => _nextWeekday(next),
        CalendarRecurrenceKind.weekly => next.add(Duration(days: 7 * step)),
        CalendarRecurrenceKind.monthly => _addMonths(next, step),
        CalendarRecurrenceKind.yearly => _addMonths(next, 12 * step),
        // A custom rule is the service's business; without an RRULE engine the
        // honest answer is that this side cannot expand it.
        CalendarRecurrenceKind.custom ||
        CalendarRecurrenceKind.none =>
          next.add(const Duration(days: 1)),
      };
      guard++;
      if (kind == CalendarRecurrenceKind.custom) {
        return null;
      }
    }
    if (until != null && next.isAfter(until!)) {
      return null;
    }
    return next.isAfter(after) ? next : null;
  }

  static DateTime _nextWeekday(DateTime from) {
    var next = from.add(const Duration(days: 1));
    while (
        next.weekday == DateTime.saturday || next.weekday == DateTime.sunday) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  static DateTime _addMonths(DateTime from, int months) {
    final total = from.month - 1 + months;
    final year = from.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      from.day > lastDay ? lastDay : from.day,
      from.hour,
      from.minute,
    );
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        if (interval != 1) 'interval': interval,
        if (rrule.isNotEmpty) 'rrule': rrule,
        if (until != null) 'until': until!.toUtc().toIso8601String(),
        if (count != null) 'count': count,
      };

  static CalendarRecurrence fromJson(Object? value) {
    if (value is! Map) {
      return none;
    }
    final kind = CalendarRecurrenceKind.values.firstWhere(
      (k) => k.name == value['kind'],
      orElse: () => CalendarRecurrenceKind.none,
    );
    final until = value['until'];
    return CalendarRecurrence(
      kind: kind,
      interval: value['interval'] is int ? value['interval'] as int : 1,
      rrule: value['rrule'] is String ? value['rrule'] as String : '',
      until: until is String ? DateTime.tryParse(until) : null,
      count: value['count'] is int ? value['count'] as int : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarRecurrence &&
      other.kind == kind &&
      other.interval == interval &&
      other.rrule == rrule &&
      other.until == until &&
      other.count == count;

  @override
  int get hashCode => Object.hash(kind, interval, rrule, until, count);
}

/// One thing on the calendar, whoever it belongs to.
///
/// This is the only model the renderer knows. A table row, an AppFlowy
/// reminder and a Google event all become one of these, which is what stops
/// the calendar growing a second interface per source.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    this.end,
    this.kind = CalendarEventKind.event,
    this.origin = CalendarEventOrigin.table,
    this.description = '',
    this.location = '',
    this.color,
    this.isCompleted = false,
    this.hasReminder = false,
    this.reminderId = '',
    this.recurrence = CalendarRecurrence.none,
    this.readOnly = false,
    this.rowId = '',
    this.remoteId = '',
    this.url = '',
  });

  /// Unique across every calendar shown at once.
  final String id;

  /// Which calendar it belongs to; also decides its colour.
  final String calendarId;

  final String title;
  final ZonedDateTime start;

  /// Null for a moment with no duration — a reminder, or a milestone.
  final ZonedDateTime? end;

  final CalendarEventKind kind;
  final CalendarEventOrigin origin;

  final String description;
  final String location;

  /// Set only when the event overrides its calendar's colour.
  final Color? color;

  final bool isCompleted;
  final bool hasReminder;
  final String reminderId;

  final CalendarRecurrence recurrence;

  /// True when the source refuses writes — a subscribed holiday feed, say.
  final bool readOnly;

  /// The table row behind it, when there is one.
  final String rowId;

  /// The hosting service's own id, when there is one.
  final String remoteId;

  /// Where to open it outside AppFlowy.
  final String url;

  bool get isAllDay => start.isAllDay;

  bool get hasDuration => end != null && end!.utc.isAfter(start.utc);

  Duration get duration =>
      hasDuration ? end!.utc.difference(start.utc) : Duration.zero;

  /// The day this event is filed under, in the reader's own clock.
  DateTime get startDay {
    final at = start.local;
    return DateTime(at.year, at.month, at.day);
  }

  /// The last day it touches.
  ///
  /// An all-day end is **inclusive** everywhere in this model. A source whose
  /// end is exclusive (Google's is) brings it back a day as it is read, so
  /// nothing downstream has to know which convention it came from.
  DateTime get endDay {
    final at = (end ?? start).local;
    return DateTime(at.year, at.month, at.day);
  }

  bool get spansDays => endDay.isAfter(startDay);

  /// Whether any part of this event falls on [day].
  bool touchesDay(DateTime day) {
    final target = DateTime(day.year, day.month, day.day);
    return !target.isBefore(startDay) && !target.isAfter(endDay);
  }

  /// Whether any part of this event falls inside [from]..[to).
  bool overlaps(DateTime from, DateTime to) {
    final startsAt = start.utc;
    final endsAt = end?.utc ?? startsAt;
    return startsAt.isBefore(to.toUtc()) && !endsAt.isBefore(from.toUtc());
  }

  CalendarEvent copyWith({
    String? title,
    ZonedDateTime? start,
    ZonedDateTime? end,
    bool clearEnd = false,
    String? description,
    String? location,
    Color? color,
    bool? isCompleted,
    bool? hasReminder,
    String? reminderId,
    CalendarRecurrence? recurrence,
    bool? readOnly,
    String? calendarId,
  }) =>
      CalendarEvent(
        id: id,
        calendarId: calendarId ?? this.calendarId,
        title: title ?? this.title,
        start: start ?? this.start,
        end: clearEnd ? null : (end ?? this.end),
        kind: kind,
        origin: origin,
        description: description ?? this.description,
        location: location ?? this.location,
        color: color ?? this.color,
        isCompleted: isCompleted ?? this.isCompleted,
        hasReminder: hasReminder ?? this.hasReminder,
        reminderId: reminderId ?? this.reminderId,
        recurrence: recurrence ?? this.recurrence,
        readOnly: readOnly ?? this.readOnly,
        rowId: rowId,
        remoteId: remoteId,
        url: url,
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.id == id &&
      other.calendarId == calendarId &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.kind == kind &&
      other.isCompleted == isCompleted &&
      other.hasReminder == hasReminder &&
      other.description == description &&
      other.location == location &&
      other.color == color &&
      other.recurrence == recurrence;

  @override
  int get hashCode => Object.hash(
        id,
        calendarId,
        title,
        start,
        end,
        kind,
        isCompleted,
        hasReminder,
        description,
        location,
        color,
        recurrence,
      );

  @override
  String toString() => 'CalendarEvent($id, $title, ${start.local})';
}

/// Sort the way a person reads a day: all-day first, then by time, then by
/// name so the order never jitters between rebuilds.
int compareCalendarEvents(CalendarEvent a, CalendarEvent b) {
  if (a.isAllDay != b.isAllDay) {
    return a.isAllDay ? -1 : 1;
  }
  final byStart = a.start.utc.compareTo(b.start.utc);
  if (byStart != 0) {
    return byStart;
  }
  // A longer event first: it reads as the container of the shorter ones.
  final byLength = b.duration.compareTo(a.duration);
  if (byLength != 0) {
    return byLength;
  }
  final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
}
