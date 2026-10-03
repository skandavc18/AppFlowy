import 'package:flutter/foundation.dart';

/// How a scheduled workflow repeats.
enum WorkflowScheduleMode {
  interval,
  daily,
  weekly,
  monthly;

  static WorkflowScheduleMode parse(Object? value) =>
      WorkflowScheduleMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => WorkflowScheduleMode.daily,
      );
}

enum WorkflowIntervalUnit {
  minutes,
  hours,
  days;

  static WorkflowIntervalUnit parse(Object? value) =>
      WorkflowIntervalUnit.values.firstWhere(
        (unit) => unit.name == value,
        orElse: () => WorkflowIntervalUnit.hours,
      );

  Duration of(int amount) => switch (this) {
        WorkflowIntervalUnit.minutes => Duration(minutes: amount),
        WorkflowIntervalUnit.hours => Duration(hours: amount),
        WorkflowIntervalUnit.days => Duration(days: amount),
      };
}

/// When a scheduled workflow runs.
///
/// Calendar schedules (daily/weekly/monthly) are worked out in local wall
/// time, so 09:00 stays 09:00 across a daylight-saving change.
@immutable
class WorkflowSchedule {
  const WorkflowSchedule({
    this.mode = WorkflowScheduleMode.daily,
    this.every = 1,
    this.unit = WorkflowIntervalUnit.hours,
    this.minuteOfDay = 9 * 60,
    this.weekdays = const {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    },
    this.dayOfMonth = 1,
  });

  /// Anything faster is a busy loop with a network call in it.
  static const minimumInterval = Duration(minutes: 1);

  final WorkflowScheduleMode mode;
  final int every;
  final WorkflowIntervalUnit unit;

  /// Minutes after local midnight.
  final int minuteOfDay;

  /// `DateTime.monday` … `DateTime.sunday`.
  final Set<int> weekdays;

  /// 1–31; a month without that day runs on its last day instead.
  final int dayOfMonth;

  Duration get interval {
    final value = unit.of(every < 1 ? 1 : every);
    return value < minimumInterval ? minimumInterval : value;
  }

  int get hour => minuteOfDay ~/ 60;
  int get minute => minuteOfDay % 60;

  /// When this schedule next wants to run.
  ///
  /// [lastRun] null means it never ran: an interval then first runs one
  /// interval after [since] (normally the moment it was turned on) and a
  /// calendar schedule waits for its first occurrence at or after [since]. A
  /// schedule that missed several occurrences while the app was closed is
  /// owed exactly ONE run.
  DateTime? nextRun({
    required DateTime now,
    DateTime? lastRun,
    DateTime? since,
  }) {
    if (mode == WorkflowScheduleMode.interval) {
      return (lastRun ?? since ?? now).add(interval);
    }
    if (mode == WorkflowScheduleMode.weekly && weekdays.isEmpty) {
      return null;
    }
    final reference = lastRun ?? since ?? now;
    final inclusive = lastRun == null;
    var day = DateTime(reference.year, reference.month, reference.day);
    // Never more than a year and a little to find the next occurrence.
    for (var i = 0; i < 400; i++) {
      if (_matches(day)) {
        final candidate = DateTime(day.year, day.month, day.day, hour, minute);
        final later = inclusive
            ? !candidate.isBefore(reference)
            : candidate.isAfter(reference);
        if (later) {
          return candidate;
        }
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return null;
  }

  bool isDue({required DateTime now, DateTime? lastRun, DateTime? since}) {
    final next = nextRun(now: now, lastRun: lastRun, since: since);
    return next != null && !next.isAfter(now);
  }

  bool _matches(DateTime day) => switch (mode) {
        WorkflowScheduleMode.interval => true,
        WorkflowScheduleMode.daily => true,
        WorkflowScheduleMode.weekly => weekdays.contains(day.weekday),
        WorkflowScheduleMode.monthly =>
          day.day == _clampedDay(day.year, day.month),
      };

  int _clampedDay(int year, int month) {
    final last = DateTime(year, month + 1, 0).day;
    final wanted = dayOfMonth.clamp(1, 31);
    return wanted > last ? last : wanted;
  }

  WorkflowSchedule copyWith({
    WorkflowScheduleMode? mode,
    int? every,
    WorkflowIntervalUnit? unit,
    int? minuteOfDay,
    Set<int>? weekdays,
    int? dayOfMonth,
  }) =>
      WorkflowSchedule(
        mode: mode ?? this.mode,
        every: every ?? this.every,
        unit: unit ?? this.unit,
        minuteOfDay: minuteOfDay ?? this.minuteOfDay,
        weekdays: weekdays ?? this.weekdays,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      );

  static WorkflowSchedule fromJson(Object? source) {
    if (source is! Map) {
      return const WorkflowSchedule();
    }
    final values = Map<String, Object?>.from(source);
    final days = values['weekdays'];
    return WorkflowSchedule(
      mode: WorkflowScheduleMode.parse(values['mode']),
      every: _int(values['every'], 1).clamp(1, 1000),
      unit: WorkflowIntervalUnit.parse(values['unit']),
      minuteOfDay: _int(values['minute'], 9 * 60).clamp(0, 24 * 60 - 1),
      weekdays: days is List
          ? {
              for (final day in days)
                if (day is int && day >= 1 && day <= 7) day,
            }
          : const WorkflowSchedule().weekdays,
      dayOfMonth: _int(values['day'], 1).clamp(1, 31),
    );
  }

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'every': every,
        'unit': unit.name,
        'minute': minuteOfDay,
        'weekdays': (weekdays.toList()..sort()),
        'day': dayOfMonth,
      };

  static int _int(Object? value, int fallback) => switch (value) {
        final int number => number,
        final num number => number.toInt(),
        final String text => int.tryParse(text) ?? fallback,
        _ => fallback,
      };

  @override
  bool operator ==(Object other) =>
      other is WorkflowSchedule &&
      other.mode == mode &&
      other.every == every &&
      other.unit == unit &&
      other.minuteOfDay == minuteOfDay &&
      setEquals(other.weekdays, weekdays) &&
      other.dayOfMonth == dayOfMonth;

  @override
  int get hashCode => Object.hash(
        mode,
        every,
        unit,
        minuteOfDay,
        Object.hashAllUnordered(weekdays),
        dayOfMonth,
      );
}
