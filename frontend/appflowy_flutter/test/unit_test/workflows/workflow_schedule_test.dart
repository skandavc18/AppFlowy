import 'package:appflowy/workflows/application/workflow_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026-03-02 is a Monday.
  group('WorkflowSchedule', () {
    test('an interval first runs one interval after it was turned on', () {
      const schedule = WorkflowSchedule(
        mode: WorkflowScheduleMode.interval,
        every: 2,
      );
      final since = DateTime(2026, 3, 2, 10);
      expect(
        schedule.nextRun(now: since, since: since),
        DateTime(2026, 3, 2, 12),
      );
      expect(
        schedule.nextRun(
          now: since,
          lastRun: DateTime(2026, 3, 2, 12, 30),
          since: since,
        ),
        DateTime(2026, 3, 2, 14, 30),
      );
    });

    test('an interval is never shorter than a minute', () {
      const schedule = WorkflowSchedule(
        mode: WorkflowScheduleMode.interval,
        every: 0,
        unit: WorkflowIntervalUnit.minutes,
      );
      expect(schedule.interval, const Duration(minutes: 1));
    });

    test('daily waits for the first time at or after it was turned on', () {
      const schedule = WorkflowSchedule();
      expect(
        schedule.nextRun(
          now: DateTime(2026, 3, 2, 8),
          since: DateTime(2026, 3, 2, 8),
        ),
        DateTime(2026, 3, 2, 9),
      );
      expect(
        schedule.nextRun(
          now: DateTime(2026, 3, 2, 10),
          since: DateTime(2026, 3, 2, 10),
        ),
        DateTime(2026, 3, 3, 9),
      );
      expect(
        schedule.nextRun(
          now: DateTime(2026, 3, 3, 9),
          lastRun: DateTime(2026, 3, 3, 9),
        ),
        DateTime(2026, 3, 4, 9),
      );
    });

    test('several missed days are owed exactly one run', () {
      const schedule = WorkflowSchedule();
      final lastRun = DateTime(2026, 3, 1, 9);
      final now = DateTime(2026, 3, 5, 12);
      expect(
        schedule.nextRun(now: now, lastRun: lastRun),
        DateTime(2026, 3, 2, 9),
      );
      expect(schedule.isDue(now: now, lastRun: lastRun), isTrue);
      // The catch-up run is recorded at `now`; the next is tomorrow morning.
      expect(schedule.nextRun(now: now, lastRun: now), DateTime(2026, 3, 6, 9));
      expect(schedule.isDue(now: now, lastRun: now), isFalse);
    });

    test('weekly only runs on the chosen days', () {
      const schedule = WorkflowSchedule(
        mode: WorkflowScheduleMode.weekly,
        minuteOfDay: 16 * 60,
        weekdays: {DateTime.friday},
      );
      expect(
        schedule.nextRun(
          now: DateTime(2026, 3, 2, 8),
          since: DateTime(2026, 3, 2, 8),
        ),
        DateTime(2026, 3, 6, 16),
      );
      expect(
        schedule.nextRun(
          now: DateTime(2026, 3, 6, 16),
          lastRun: DateTime(2026, 3, 6, 16),
        ),
        DateTime(2026, 3, 13, 16),
      );
      const none = WorkflowSchedule(
        mode: WorkflowScheduleMode.weekly,
        weekdays: {},
      );
      expect(none.nextRun(now: DateTime(2026, 3, 2)), isNull);
    });

    test('monthly runs on the last day of a shorter month', () {
      const schedule = WorkflowSchedule(
        mode: WorkflowScheduleMode.monthly,
        dayOfMonth: 31,
        minuteOfDay: 0,
      );
      expect(
        schedule.nextRun(
          now: DateTime(2026, 2),
          since: DateTime(2026, 2),
        ),
        DateTime(2026, 2, 28),
      );
      expect(
        schedule.nextRun(
          now: DateTime(2026, 2, 28),
          lastRun: DateTime(2026, 2, 28),
        ),
        DateTime(2026, 3, 31),
      );
    });

    test('survives JSON and clamps nonsense', () {
      const schedule = WorkflowSchedule(
        mode: WorkflowScheduleMode.weekly,
        every: 3,
        unit: WorkflowIntervalUnit.days,
        minuteOfDay: 17 * 60 + 15,
        weekdays: {DateTime.tuesday, DateTime.saturday},
        dayOfMonth: 12,
      );
      expect(WorkflowSchedule.fromJson(schedule.toJson()), schedule);
      final clamped = WorkflowSchedule.fromJson({
        'mode': 'daily',
        'minute': 99999,
        'day': 0,
        'weekdays': [0, 3, 9, 'x'],
      });
      expect(clamped.minuteOfDay, 24 * 60 - 1);
      expect(clamped.dayOfMonth, 1);
      expect(clamped.weekdays, {3});
      expect(WorkflowSchedule.fromJson('nonsense'), const WorkflowSchedule());
    });
  });
}
