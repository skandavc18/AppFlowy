import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/year_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/google_calendar_provider.dart';
import 'package:appflowy/shared/calendar/notification_scheduler.dart';
import 'package:appflowy/shared/calendar/reminder_parser.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent _event(
  String id,
  DateTime start, {
  DateTime? end,
  bool allDay = false,
  CalendarEventKind kind = CalendarEventKind.event,
  String title = '',
}) =>
    CalendarEvent(
      id: id,
      calendarId: 'c',
      title: title.isEmpty ? id : title,
      kind: kind,
      start: allDay ? ZonedDateTime.allDay(start) : ZonedDateTime.local(start),
      end: end == null
          ? null
          : allDay
              ? ZonedDateTime.allDay(end)
              : ZonedDateTime.local(end),
    );

void main() {
  group('what a day means', () {
    test('an all-day end is inclusive, so the last day is drawn', () {
      final event = _event(
        'a',
        DateTime(2026, 8, 3),
        end: DateTime(2026, 8, 5),
        allDay: true,
      );
      expect(event.startDay, DateTime(2026, 8, 3));
      expect(event.endDay, DateTime(2026, 8, 5));
      expect(event.touchesDay(DateTime(2026, 8, 5)), isTrue);
      expect(event.touchesDay(DateTime(2026, 8, 6)), isFalse);
    });

    test('a one-day all-day event does not paint across two cells', () {
      final event = _event('a', DateTime(2026, 8, 3), allDay: true);
      expect(event.spansDays, isFalse);
      expect(event.endDay, event.startDay);
    });

    test('daylight saving does not make a day 23 hours long', () {
      expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    });

    test('a zoned instant keeps the zone it was written in', () {
      final zoned = ZonedDateTime.fromUtc(
        DateTime.utc(2026, 8, 3, 9),
        timeZone: 'Europe/Berlin',
      );
      expect(zoned.timeZone, 'Europe/Berlin');
      expect(zoned.utc, DateTime.utc(2026, 8, 3, 9));
      expect(zoned.isAllDay, isFalse);
    });

    test('moving to another day keeps the time of day', () {
      final at = ZonedDateTime.local(DateTime(2026, 8, 3, 14, 30));
      final moved = at.onDay(DateTime(2026, 8, 9));
      expect(moved.local, DateTime(2026, 8, 9, 14, 30));
    });
  });

  group('the month grid', () {
    test('a week row draws a multi-day event as one bar, not five chips', () {
      final days = weekDays(DateTime(2026, 8, 5));
      final layout = layOutMonthWeek(
        days,
        [
          _event(
            'trip',
            DateTime(2026, 8, 4),
            end: DateTime(2026, 8, 6),
            allDay: true,
          ),
        ],
        maxLanes: 3,
      );
      expect(layout.bars, hasLength(1));
      expect(layout.bars.first.columnSpan, 3);
      expect(layout.bars.first.lane, 0);
      expect(layout.bars.first.continuesBefore, isFalse);
      expect(layout.bars.first.continuesAfter, isFalse);
    });

    test('an event running past the row is marked as continuing', () {
      final days = weekDays(DateTime(2026, 8, 5));
      final layout = layOutMonthWeek(
        days,
        [
          _event(
            'long',
            DateTime(2026, 7, 30),
            end: DateTime(2026, 8, 12),
            allDay: true,
          ),
        ],
        maxLanes: 3,
      );
      expect(layout.bars.single.continuesBefore, isTrue);
      expect(layout.bars.single.continuesAfter, isTrue);
      expect(layout.bars.single.columnSpan, days.length);
    });

    test('two overlapping events take separate lanes', () {
      final days = weekDays(DateTime(2026, 8, 5));
      final layout = layOutMonthWeek(
        days,
        [
          _event(
            'a',
            DateTime(2026, 8, 4),
            end: DateTime(2026, 8, 6),
            allDay: true,
          ),
          _event(
            'b',
            DateTime(2026, 8, 5),
            end: DateTime(2026, 8, 7),
            allDay: true,
          ),
        ],
        maxLanes: 3,
      );
      expect(layout.laneCount, 2);
      expect({for (final bar in layout.bars) bar.lane}, {0, 1});
    });

    test('two events that do not overlap share one lane', () {
      final days = weekDays(DateTime(2026, 8, 5));
      final layout = layOutMonthWeek(
        days,
        [
          _event('a', DateTime(2026, 8, 3), allDay: true),
          _event('b', DateTime(2026, 8, 6), allDay: true),
        ],
        maxLanes: 3,
      );
      expect(layout.laneCount, 1);
    });

    test('anything past the lanes is reported as overflow per column', () {
      final days = weekDays(DateTime(2026, 8, 5));
      final layout = layOutMonthWeek(
        days,
        [
          for (var i = 0; i < 5; i++)
            _event('e$i', DateTime(2026, 8, 5, 9 + i), allDay: true),
        ],
        maxLanes: 2,
      );
      expect(layout.bars, hasLength(2));
      final column = days.indexWhere((d) => d.day == 5);
      expect(layout.overflowAt(column), 3);
    });

    test('hiding weekends drops them from the grid', () {
      final days = monthGridDays(DateTime(2026, 8), showWeekends: false);
      expect(days.any(isWeekend), isFalse);
      expect(days.length % 5, 0);
    });

    test('the grid always starts on the chosen first day of the week', () {
      final monday = monthGridDays(DateTime(2026, 8));
      expect(monday.first.weekday, DateTime.monday);
      final sunday =
          monthGridDays(DateTime(2026, 8), firstDayOfWeek: DateTime.sunday);
      expect(sunday.first.weekday, DateTime.sunday);
    });
  });

  group('the time grid', () {
    test('an event that does not overlap takes the whole column', () {
      final placements = layOutDayColumn(DateTime(2026, 8, 3), [
        _event(
          'a',
          DateTime(2026, 8, 3, 9),
          end: DateTime(2026, 8, 3, 10),
        ),
      ]);
      expect(placements, hasLength(1));
      expect(placements.single.left, 0);
      expect(placements.single.width, 1);
      expect(placements.single.startMinutes, 540);
      expect(placements.single.endMinutes, 600);
    });

    test('two overlapping events share the width', () {
      final placements = layOutDayColumn(DateTime(2026, 8, 3), [
        _event('a', DateTime(2026, 8, 3, 9), end: DateTime(2026, 8, 3, 11)),
        _event('b', DateTime(2026, 8, 3, 10), end: DateTime(2026, 8, 3, 12)),
      ]);
      expect(placements, hasLength(2));
      expect(placements.map((p) => p.width), everyElement(closeTo(0.5, 0.001)));
      expect({for (final p in placements) p.left}, {0.0, 0.5});
    });

    test('an event widens into a column nothing else is using', () {
      // 9–10 and 9–10 overlap; a third at 11 belongs to its own cluster and
      // must not be squeezed by them.
      final placements = layOutDayColumn(DateTime(2026, 8, 3), [
        _event('a', DateTime(2026, 8, 3, 9), end: DateTime(2026, 8, 3, 10)),
        _event('b', DateTime(2026, 8, 3, 9), end: DateTime(2026, 8, 3, 10)),
        _event('c', DateTime(2026, 8, 3, 11), end: DateTime(2026, 8, 3, 12)),
      ]);
      final third = placements.firstWhere((p) => p.event.id == 'c');
      expect(third.width, 1);
      expect(third.left, 0);
    });

    test('a short event is still tall enough to read', () {
      final placements = layOutDayColumn(DateTime(2026, 8, 3), [
        _event(
          'a',
          DateTime(2026, 8, 3, 9),
          end: DateTime(2026, 8, 3, 9, 5),
        ),
      ]);
      expect(placements.single.durationMinutes, minimumEventMinutes);
    });

    test('an event running over midnight is clipped to the day drawn', () {
      final placements = layOutDayColumn(DateTime(2026, 8, 4), [
        _event(
          'a',
          DateTime(2026, 8, 3, 22),
          end: DateTime(2026, 8, 4, 2),
        ),
      ]);
      expect(placements.single.startMinutes, 0);
      expect(placements.single.endMinutes, 120);
    });

    test('all-day events never appear in the time grid', () {
      final placements = layOutDayColumn(DateTime(2026, 8, 3), [
        _event('a', DateTime(2026, 8, 3), allDay: true),
      ]);
      expect(placements, isEmpty);
    });

    test('a drop snaps to the nearest slot', () {
      final at = snapToSlot(DateTime(2026, 8, 3), 553);
      expect(at, DateTime(2026, 8, 3, 9, 15));
    });
  });

  group('the agenda', () {
    test('a multi-day event appears under every day it touches', () {
      final sections = groupAgenda(
        [
          _event(
            'trip',
            DateTime(2026, 8, 3),
            end: DateTime(2026, 8, 5),
            allDay: true,
          ),
        ],
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 10),
      );
      expect(sections.map((s) => s.day), [
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 5),
      ]);
    });

    test('empty days are left out unless asked for', () {
      final events = [_event('a', DateTime(2026, 8, 3, 9))];
      expect(
        groupAgenda(
          events,
          from: DateTime(2026, 8),
          to: DateTime(2026, 8, 6),
        ),
        hasLength(1),
      );
      expect(
        groupAgenda(
          events,
          from: DateTime(2026, 8),
          to: DateTime(2026, 8, 6),
          includeEmptyDays: true,
        ),
        hasLength(5),
      );
    });

    test('a day reads all-day first, then by time', () {
      final sections = groupAgenda(
        [
          _event('later', DateTime(2026, 8, 3, 14)),
          _event('earlier', DateTime(2026, 8, 3, 9)),
          _event('whole', DateTime(2026, 8, 3), allDay: true),
        ],
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 6),
      );
      expect(
        sections.single.events.map((e) => e.id),
        ['whole', 'earlier', 'later'],
      );
    });
  });

  group('reading a reminder out of ordinary words', () {
    final now = DateTime(2026, 8, 3, 8); // a Monday

    test('“Call John tomorrow at 10 AM”', () {
      final parsed = parseReminderText('Call John tomorrow at 10 AM', now: now);
      expect(parsed.title, 'Call John');
      expect(parsed.when, DateTime(2026, 8, 4, 10));
      expect(parsed.hasTime, isTrue);
    });

    test('“Submit report Friday 5 PM”', () {
      final parsed = parseReminderText('Submit report Friday 5 PM', now: now);
      expect(parsed.title, 'Submit report');
      expect(parsed.when, DateTime(2026, 8, 7, 17));
      expect(parsed.hasTime, isTrue);
    });

    test('“Pay electricity bill on Aug 15”', () {
      final parsed =
          parseReminderText('Pay electricity bill on Aug 15', now: now);
      expect(parsed.title, 'Pay electricity bill');
      expect(parsed.when, DateTime(2026, 8, 15, 9));
      expect(parsed.hasTime, isFalse);
    });

    test('a repeat is read and taken out of the title', () {
      final parsed =
          parseReminderText('Stand up every weekday at 9:30', now: now);
      expect(parsed.title, 'Stand up');
      expect(parsed.recurrence.kind, CalendarRecurrenceKind.weekdays);
      expect(parsed.when, DateTime(2026, 8, 3, 9, 30));
    });

    test('a time already gone today means tomorrow', () {
      final parsed = parseReminderText('Water the plants at 7am', now: now);
      expect(parsed.when, DateTime(2026, 8, 4, 7));
    });

    test('a month already past means next year', () {
      final parsed = parseReminderText(
        'Renew licence on Jan 3',
        now: DateTime(2026, 12, 20),
      );
      expect(parsed.when!.year, 2027);
    });

    test('a line with no date keeps every word', () {
      final parsed = parseReminderText('Think about the roadmap', now: now);
      expect(parsed.when, isNull);
      expect(parsed.title, 'Think about the roadmap');
    });

    test('an ISO date is understood', () {
      final parsed = parseReminderText('Ship 2026-09-01 at 15:00', now: now);
      expect(parsed.when, DateTime(2026, 9, 1, 15));
      expect(parsed.title, 'Ship');
    });
  });

  group('repeating', () {
    test('daily steps a day at a time', () {
      final rule = CalendarRecurrence(kind: CalendarRecurrenceKind.daily);
      expect(
        rule.nextAfter(DateTime(2026, 8, 3, 9), DateTime(2026, 8, 3, 10)),
        DateTime(2026, 8, 4, 9),
      );
    });

    test('weekdays skips the weekend', () {
      final rule = CalendarRecurrence(kind: CalendarRecurrenceKind.weekdays);
      // Friday 7 August 2026 → Monday 10 August.
      expect(
        rule
            .nextAfter(DateTime(2026, 8, 7, 9), DateTime(2026, 8, 7, 10))!
            .weekday,
        DateTime.monday,
      );
    });

    test('monthly clamps to the end of a short month', () {
      final rule = CalendarRecurrence(kind: CalendarRecurrenceKind.monthly);
      expect(
        rule.nextAfter(DateTime(2026, 1, 31), DateTime(2026, 1, 31, 1)),
        DateTime(2026, 2, 28),
      );
    });

    test('a rule that has run out answers nothing', () {
      final rule = CalendarRecurrence(
        kind: CalendarRecurrenceKind.daily,
        until: DateTime(2026, 8, 3),
      );
      expect(
        rule.nextAfter(DateTime(2026, 8, 3, 9), DateTime(2026, 8, 3, 10)),
        isNull,
      );
    });

    test('a custom rule is carried through, not guessed at', () {
      final rule = CalendarRecurrence.fromJson({
        'kind': 'custom',
        'rrule': 'FREQ=WEEKLY;BYDAY=MO,WE',
      });
      expect(rule.kind, CalendarRecurrenceKind.custom);
      expect(rule.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(
        rule.nextAfter(DateTime(2026, 8, 3), DateTime(2026, 8, 3)),
        isNull,
      );
    });
  });

  group('what the system still owes somebody', () {
    final now = DateTime(2026, 8, 3, 12);

    AppReminder reminder({
      required DateTime at,
      DateTime? notified,
      DateTime? snoozed,
      bool done = false,
      bool archived = false,
    }) =>
        AppReminder(
          id: 'r',
          title: 'Submit report',
          message: '',
          scheduledAt: at,
          notifiedAt: notified,
          snoozedUntil: snoozed,
          isDone: done,
          isArchived: archived,
        );

    test('a reminder that has come due is owed', () {
      expect(
        dueReminders([reminder(at: DateTime(2026, 8, 3, 11))], now: now),
        hasLength(1),
      );
    });

    test('one still in the future is not', () {
      expect(
        dueReminders([reminder(at: DateTime(2026, 8, 3, 13))], now: now),
        isEmpty,
      );
    });

    test('one already announced is not repeated', () {
      expect(
        dueReminders(
          [
            reminder(
              at: DateTime(2026, 8, 3, 11),
              notified: DateTime(2026, 8, 3, 11),
            ),
          ],
          now: now,
        ),
        isEmpty,
      );
    });

    test('a snoozed reminder waits until the snooze is over', () {
      expect(
        dueReminders(
          [
            reminder(
              at: DateTime(2026, 8, 3, 11),
              snoozed: DateTime(2026, 8, 3, 13),
            ),
          ],
          now: now,
        ),
        isEmpty,
      );
    });

    test('something long past is history, not an interruption', () {
      expect(
        dueReminders([reminder(at: DateTime(2026, 8))], now: now),
        isEmpty,
      );
    });

    test('a done or archived reminder never speaks', () {
      expect(
        dueReminders(
          [
            reminder(at: DateTime(2026, 8, 3, 11), done: true),
            reminder(at: DateTime(2026, 8, 3, 11), archived: true),
          ],
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('completing a reminder', () {
    test('a plain reminder finishes', () {
      final done = AppReminder(
        id: 'r',
        title: 't',
        message: '',
        scheduledAt: DateTime(2026, 8, 3, 9),
      ).complete(now: DateTime(2026, 8, 3, 10));
      expect(done.isDone, isTrue);
    });

    test('a repeating reminder moves on instead of finishing', () {
      final next = AppReminder(
        id: 'r',
        title: 't',
        message: '',
        scheduledAt: DateTime(2026, 8, 3, 9),
        recurrence: CalendarRecurrence(kind: CalendarRecurrenceKind.daily),
      ).complete(now: DateTime(2026, 8, 3, 10));
      expect(next.isDone, isFalse);
      expect(next.scheduledAt, DateTime(2026, 8, 4, 9));
    });

    test('snoozing until tomorrow lands in the morning', () {
      final snoozed = AppReminder(
        id: 'r',
        title: 't',
        message: '',
        scheduledAt: DateTime(2026, 8, 3, 9),
      ).snooze(SnoozeOption.tomorrow, now: DateTime(2026, 8, 3, 22));
      expect(snoozed.snoozedUntil, DateTime(2026, 8, 4, 9));
      expect(snoozed.firesAt, DateTime(2026, 8, 4, 9));
    });

    test('every extra fact survives a round trip through the meta map', () {
      final source = AppReminder(
        id: 'r',
        title: 'Pay the bill',
        message: 'before it is late',
        scheduledAt: DateTime(2026, 8, 15, 17),
        priority: ReminderPriority.high,
        recurrence: CalendarRecurrence(kind: CalendarRecurrenceKind.monthly),
        kind: ReminderKind.page,
        playsSound: false,
      );
      final restored = AppReminder.fromPB(source.toPB());
      expect(restored.priority, ReminderPriority.high);
      expect(restored.recurrence.kind, CalendarRecurrenceKind.monthly);
      expect(restored.kind, ReminderKind.page);
      expect(restored.playsSound, isFalse);
      expect(restored.scheduledAt, source.scheduledAt);
    });

    test('a reminder becomes something the calendar can draw', () {
      final event = AppReminder(
        id: 'r',
        title: 'Submit report',
        message: '',
        scheduledAt: DateTime(2026, 8, 15, 17),
      ).toCalendarEvent(calendarOverride: 'reminders');
      expect(event.kind, CalendarEventKind.reminder);
      expect(event.calendarId, 'reminders');
      expect(event.hasReminder, isTrue);
      expect(event.end, isNull);
    });
  });

  group('reading Google', () {
    test('a timed event keeps the zone Google named', () {
      final event = parseGoogleEvent(
        {
          'id': 'abc',
          'summary': 'Standup',
          'start': {
            'dateTime': '2026-08-03T09:00:00+02:00',
            'timeZone': 'Europe/Berlin',
          },
          'end': {
            'dateTime': '2026-08-03T09:15:00+02:00',
            'timeZone': 'Europe/Berlin',
          },
        },
        calendarId: 'g',
      )!;
      expect(event.title, 'Standup');
      expect(event.start.timeZone, 'Europe/Berlin');
      expect(event.start.utc, DateTime.utc(2026, 8, 3, 7));
      expect(event.duration, const Duration(minutes: 15));
      expect(event.isAllDay, isFalse);
    });

    test("Google's exclusive all-day end is brought back a day", () {
      final event = parseGoogleEvent(
        {
          'id': 'abc',
          'summary': 'Holiday',
          'start': {'date': '2026-08-03'},
          'end': {'date': '2026-08-06'},
        },
        calendarId: 'g',
      )!;
      expect(event.isAllDay, isTrue);
      expect(event.startDay, DateTime(2026, 8, 3));
      expect(event.endDay, DateTime(2026, 8, 5));
    });

    test('a one-day all-day event does not end before it starts', () {
      final event = parseGoogleEvent(
        {
          'id': 'abc',
          'start': {'date': '2026-08-03'},
          'end': {'date': '2026-08-04'},
        },
        calendarId: 'g',
      )!;
      expect(event.endDay, DateTime(2026, 8, 3));
    });

    test('a cancelled event is not shown at all', () {
      expect(
        parseGoogleEvent(
          {'id': 'abc', 'status': 'cancelled'},
          calendarId: 'g',
        ),
        isNull,
      );
    });

    test('a recurring event carries its rule through untouched', () {
      final event = parseGoogleEvent(
        {
          'id': 'abc',
          'start': {'dateTime': '2026-08-03T09:00:00Z'},
          'end': {'dateTime': '2026-08-03T10:00:00Z'},
          'recurrence': ['RRULE:FREQ=WEEKLY;BYDAY=MO,WE'],
        },
        calendarId: 'g',
      )!;
      expect(event.recurrence.kind, CalendarRecurrenceKind.weekly);
      expect(event.recurrence.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE');
    });

    test('an all-day event is written back with an exclusive end', () {
      final body = googleEventBody(
        title: 'Holiday',
        start: ZonedDateTime.allDay(DateTime(2026, 8, 3)),
        end: ZonedDateTime.allDay(DateTime(2026, 8, 5)),
      );
      expect((body['start']! as Map)['date'], '2026-08-03');
      expect((body['end']! as Map)['date'], '2026-08-06');
    });

    test('a timed event with no end is given an hour', () {
      final body = googleEventBody(
        start: ZonedDateTime.fromUtc(DateTime.utc(2026, 8, 3, 9)),
      );
      expect(
        (body['end']! as Map)['dateTime'],
        DateTime.utc(2026, 8, 3, 10).toIso8601String(),
      );
    });

    test('a calendar id survives being qualified and taken apart again', () {
      final id =
          GoogleCalendarProvider.qualify('conn', 'a@group.calendar.google.com');
      expect(
        GoogleCalendarProvider.remoteIdOf(id),
        'a@group.calendar.google.com',
      );
    });

    test('which calendars were chosen survives a round trip', () {
      final selection = GoogleCalendarSelection(
        connectionId: 'conn',
        calendarIds: {'work', 'home'},
        hidden: {'home'},
        defaultCalendarId: 'work',
      );
      final restored = GoogleCalendarSelection.decodeAll(
        GoogleCalendarSelection.encodeAll([selection]),
      ).single;
      expect(restored.calendarIds, {'work', 'home'});
      expect(restored.hidden, {'home'});
      expect(restored.defaultCalendarId, 'work');
    });
  });

  group('narrowing the calendar', () {
    final events = [
      _event('e', DateTime(2026, 8, 3, 9), title: 'Design review'),
      _event(
        'r',
        DateTime(2026, 8, 3, 17),
        kind: CalendarEventKind.reminder,
        title: 'Submit report',
      ),
    ];

    test('a search reads the title', () {
      const filter = CalendarFilter(query: 'design');
      expect(events.where(filter.allows).map((e) => e.id), ['e']);
    });

    test('reminders and events can be shown separately', () {
      expect(
        events.where(const CalendarFilter(showReminders: false).allows).length,
        1,
      );
      expect(
        events.where(const CalendarFilter(showEvents: false).allows).length,
        1,
      );
    });

    test('a hidden calendar takes its events with it', () {
      const filter = CalendarFilter(hiddenCalendars: {'c'});
      expect(events.where(filter.allows), isEmpty);
    });

    test('an untouched filter is not active', () {
      expect(const CalendarFilter().isActive, isFalse);
      expect(const CalendarFilter(query: 'x').isActive, isTrue);
    });
  });

  group('the year', () {
    test('a day with nothing on it is not counted at all', () {
      final counts = countEventsPerDay([
        _event('a', DateTime(2026, 8, 3, 9)),
      ]);
      expect(counts[DateTime(2026, 8, 3)], 1);
      expect(counts.containsKey(DateTime(2026, 8, 4)), isFalse);
    });

    test('a multi-day event counts on every day it touches', () {
      final counts = countEventsPerDay([
        _event(
          'trip',
          DateTime(2026, 8, 3),
          end: DateTime(2026, 8, 5),
          allDay: true,
        ),
      ]);
      expect(counts[DateTime(2026, 8, 3)], 1);
      expect(counts[DateTime(2026, 8, 4)], 1);
      expect(counts[DateTime(2026, 8, 5)], 1);
      expect(counts.containsKey(DateTime(2026, 8, 6)), isFalse);
    });

    test('a busy day adds up', () {
      final counts = countEventsPerDay([
        _event('a', DateTime(2026, 8, 3, 9)),
        _event('b', DateTime(2026, 8, 3, 11)),
        _event('c', DateTime(2026, 8, 3, 15)),
      ]);
      expect(counts[DateTime(2026, 8, 3)], 3);
    });
  });

  group('reminders on a table view', () {
    TableRowCard card(String id) => TableRowCard(rowId: id, title: id);

    test('a row with no reminder is left exactly as it was', () {
      final cards = [card('a')];
      expect(attachRemindersToCards(cards, const []), same(cards));
    });

    test('a reminder on a row is carried onto its card', () {
      final reminder = AppReminder(
        id: 'r',
        title: 't',
        message: '',
        scheduledAt: DateTime(2026, 8, 3, 9),
      );
      // The row id lives in the meta map, so build it through the protobuf.
      final pb = reminder.toPB()..meta['row_id'] = 'a';
      final decorated =
          attachRemindersToCards([card('a')], [AppReminder.fromPB(pb)]);
      expect(decorated.single.hasReminder, isTrue);
      expect(decorated.single.reminderAt, DateTime(2026, 8, 3, 9));
    });

    test('an outstanding reminder wins over one already done', () {
      final done = AppReminder(
        id: 'r1',
        title: 't',
        message: '',
        scheduledAt: DateTime(2026, 8, 1, 9),
        isDone: true,
      ).toPB()
        ..meta['row_id'] = 'a';
      final open = AppReminder(
        id: 'r2',
        title: 't',
        message: '',
        scheduledAt: DateTime(2026, 8, 5, 9),
      ).toPB()
        ..meta['row_id'] = 'a';
      final decorated = attachRemindersToCards(
        [card('a')],
        [AppReminder.fromPB(done), AppReminder.fromPB(open)],
      );
      expect(decorated.single.reminderDone, isFalse);
      expect(decorated.single.reminderAt, DateTime(2026, 8, 5, 9));
    });
  });
}
