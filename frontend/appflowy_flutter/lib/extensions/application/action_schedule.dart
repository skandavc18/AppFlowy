import 'package:flutter/foundation.dart';

/// How often an action wants to run.
///
/// Deliberately small: an interval, a time of day, or nothing. A cron
/// expression is a language, and the recipe format is not one.
@immutable
class ActionSchedule {
  const ActionSchedule._({this.interval, this.minutesAfterMidnight});

  const ActionSchedule.every(Duration interval) : this._(interval: interval);

  const ActionSchedule.at(int minutesAfterMidnight)
      : this._(minutesAfterMidnight: minutesAfterMidnight);

  /// The shortest interval worth honouring. Anything faster is a busy loop
  /// with a network call in it.
  static const minimumInterval = Duration(seconds: 30);

  final Duration? interval;
  final int? minutesAfterMidnight;

  bool get isEmpty => interval == null && minutesAfterMidnight == null;

  /// `30s`, `15m`, `2h`, `1d`, or a bare number of minutes.
  static Duration? parseInterval(String source) {
    final trimmed = source.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return null;
    }
    final match = RegExp(r'^(\d+)\s*([smhd]?)$').firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    final amount = int.tryParse(match.group(1)!);
    if (amount == null || amount <= 0) {
      return null;
    }
    final unit = match.group(2)!;
    final duration = switch (unit) {
      's' => Duration(seconds: amount),
      'h' => Duration(hours: amount),
      'd' => Duration(days: amount),
      _ => Duration(minutes: amount),
    };
    return duration < minimumInterval ? minimumInterval : duration;
  }

  /// `09:30` / `9:30` / `21:05`.
  static int? parseTimeOfDay(String source) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(source.trim());
    if (match == null) {
      return null;
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  /// When this schedule next wants to run.
  ///
  /// [lastRun] being null means it has never run, and an interval schedule is
  /// then due at once — that is what makes a newly written action visibly do
  /// something instead of waiting a quarter of an hour.
  DateTime? nextRun({required DateTime now, DateTime? lastRun}) {
    final every = interval;
    if (every != null) {
      return lastRun == null ? now : lastRun.add(every);
    }

    final minutes = minutesAfterMidnight;
    if (minutes == null) {
      return null;
    }
    final today =
        DateTime(now.year, now.month, now.day).add(Duration(minutes: minutes));
    if (lastRun != null && !lastRun.isBefore(today)) {
      return today.add(const Duration(days: 1));
    }
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  /// Whether this schedule is owed a run at [now].
  ///
  /// A schedule missed while the app was closed is owed exactly ONE run, not
  /// one per interval that elapsed — a poller left off for a week must not
  /// wake up and fire six hundred times.
  bool isDue({required DateTime now, DateTime? lastRun}) {
    final next = nextRun(now: now, lastRun: lastRun);
    return next != null && !next.isAfter(now);
  }

  static ActionSchedule? fromJson(Map<String, Object?> values) {
    final every = values['every'];
    if (every is String) {
      final parsed = parseInterval(every);
      if (parsed != null) {
        return ActionSchedule.every(parsed);
      }
    }
    if (every is int && every > 0) {
      return ActionSchedule.every(Duration(minutes: every));
    }
    final at = values['at'];
    if (at is String) {
      final parsed = parseTimeOfDay(at);
      if (parsed != null) {
        return ActionSchedule.at(parsed);
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    final every = interval;
    if (every != null) {
      return {'every': '${every.inSeconds}s'};
    }
    final minutes = minutesAfterMidnight ?? 0;
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return {'at': '$hour:$minute'};
  }

  @override
  bool operator ==(Object other) =>
      other is ActionSchedule &&
      other.interval == interval &&
      other.minutesAfterMidnight == minutesAfterMidnight;

  @override
  int get hashCode => Object.hash(interval, minutesAfterMidnight);
}
