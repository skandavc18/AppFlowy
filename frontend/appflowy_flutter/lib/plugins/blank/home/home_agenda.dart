import 'dart:async';

import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

/// Something on today's schedule: a calendar event or an AppFlowy reminder.
@immutable
class HomeAgendaItem {
  const HomeAgendaItem({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.location = '',
    this.color,
    this.event,
    this.reminder,
  });

  factory HomeAgendaItem.event(CalendarEvent event, Color color) =>
      HomeAgendaItem(
        id: event.id,
        title: event.title.trim(),
        start: event.start.local,
        end: event.end?.local,
        allDay: event.isAllDay,
        location: event.location.trim(),
        color: color,
        event: event,
      );

  factory HomeAgendaItem.reminder(AppReminder reminder) => HomeAgendaItem(
        id: 'reminder:${reminder.id}',
        title:
            (reminder.title.trim().isEmpty ? reminder.message : reminder.title)
                .trim(),
        start: reminder.firesAt,
        allDay: !reminder.includeTime,
        reminder: reminder,
      );

  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String location;
  final Color? color;
  final CalendarEvent? event;
  final AppReminder? reminder;

  bool get isReminder => reminder != null;

  /// A timed item is still ahead while it has not finished.
  bool isAheadAt(DateTime now) =>
      allDay ? start.isAfter(now) : (end ?? start).isAfter(now);
}

int _compareItems(HomeAgendaItem a, HomeAgendaItem b) {
  // All-day items lead their day; then by time; then by title.
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

int _priorityRank(ReminderPriority priority) => switch (priority) {
      ReminderPriority.high => 0,
      ReminderPriority.medium => 1,
      ReminderPriority.low => 2,
      ReminderPriority.none => 3,
    };

/// What today holds, computed from plain lists so it is the same everywhere.
@immutable
class HomeAgenda {
  const HomeAgenda({
    this.today = const [],
    this.overdue = const [],
    this.upcoming = const [],
    this.next,
    this.priority,
  });

  factory HomeAgenda.compute({
    required DateTime now,
    required List<CalendarEvent> events,
    required List<AppReminder> reminders,
    required Color Function(CalendarEvent event) colorOf,
    int upcomingDays = 7,
    int upcomingLimit = 4,
  }) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day + 1);
    final horizon = DateTime(now.year, now.month, now.day + 1 + upcomingDays);

    // Reminders are read from their store; their calendar copies would repeat.
    final calendar = [
      for (final event in events)
        if (event.kind != CalendarEventKind.reminder && !event.isCompleted)
          HomeAgendaItem.event(event, colorOf(event)),
    ];
    final outstanding = [
      for (final reminder in reminders)
        if (!reminder.isDone && !reminder.isArchived)
          HomeAgendaItem.reminder(reminder),
    ];

    bool overlapsToday(HomeAgendaItem item) {
      final end = item.end ?? item.start;
      return item.start.isBefore(dayEnd) &&
          (end.isAfter(dayStart) || !item.start.isBefore(dayStart));
    }

    final today = [
      ...calendar.where(overlapsToday),
      ...outstanding.where(
        (item) => !item.start.isBefore(dayStart) && item.start.isBefore(dayEnd),
      ),
    ]..sort(_compareItems);
    final overdue = outstanding
        .where((item) => item.start.isBefore(dayStart))
        .toList()
      ..sort(_compareItems);
    final upcoming = [
      ...calendar.where(
        (item) => !item.start.isBefore(dayEnd) && item.start.isBefore(horizon),
      ),
      ...outstanding.where(
        (item) => !item.start.isBefore(dayEnd) && item.start.isBefore(horizon),
      ),
    ]..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : _compareItems(a, b);
      });

    // The most pressing reminder this week: overdue before due, loud before
    // quiet, then soonest.
    final ranked =
        outstanding.where((item) => item.start.isBefore(horizon)).toList()
          ..sort((a, b) {
            final lateA = a.start.isBefore(now), lateB = b.start.isBefore(now);
            if (lateA != lateB) return lateA ? -1 : 1;
            final byPriority = _priorityRank(a.reminder!.priority)
                .compareTo(_priorityRank(b.reminder!.priority));
            if (byPriority != 0) return byPriority;
            return a.start.compareTo(b.start);
          });
    final priority = ranked.isEmpty ? null : ranked.first;

    HomeAgendaItem? next;
    for (final item in today) {
      if (!item.isReminder && !item.allDay && item.isAheadAt(now)) {
        next = item;
        break;
      }
    }
    if (next == null) {
      for (final item in today) {
        if (item.isReminder &&
            !item.allDay &&
            !item.start.isBefore(now) &&
            item.id != priority?.id) {
          next = item;
          break;
        }
      }
    }

    return HomeAgenda(
      today: List.unmodifiable(today),
      overdue: List.unmodifiable(overdue),
      upcoming: List.unmodifiable(upcoming.take(upcomingLimit)),
      next: next,
      priority: priority,
    );
  }

  final List<HomeAgendaItem> today;
  final List<HomeAgendaItem> overdue;
  final List<HomeAgendaItem> upcoming;
  final HomeAgendaItem? next;
  final HomeAgendaItem? priority;
}

/// Reminders and connected calendars for Home. Local reminders draw at once;
/// connected calendars join in the background when they have loaded.
class HomeAgendaSource extends ChangeNotifier {
  HomeAgendaSource({
    ReminderStore? store,
    CalendarWorkspace? calendar,
    this.connectCalendars = true,
  })  : _store = store ?? ReminderStore.instance,
        _ownsCalendar = calendar == null,
        _calendar = calendar ?? CalendarWorkspace(providers: []);

  final ReminderStore _store;
  final CalendarWorkspace _calendar;
  final bool _ownsCalendar;
  final bool connectCalendars;
  bool _started = false;
  bool _disposed = false;
  DateTime _today = DateTime.now();
  DateTime? _month;

  ReminderStore get store => _store;
  CalendarWorkspace get calendar => _calendar;

  void start(DateTime now) {
    if (_started || _disposed) return;
    _started = true;
    _store.addListener(_changed);
    _calendar.addListener(_changed);
    _store.start();
    _today = startOfDay(now);
    unawaited(_calendar.load(_window()));
    if (connectCalendars) unawaited(_connect());
  }

  /// Also read the days a month calendar shows, keeping the coming days
  /// loaded for the agenda. Call again when the day turns over.
  void showMonth(DateTime month, DateTime now) {
    _month = DateTime(month.year, month.month);
    _today = startOfDay(now);
    if (_started && !_disposed) unawaited(_calendar.load(_window()));
  }

  CalendarWindow _window() {
    var from = _today;
    var to = calendarDayOffset(_today, 9);
    final month = _month;
    if (month != null) {
      // A month grid shows up to a week either side of the month itself.
      final first = calendarDayOffset(month, -7);
      final last = calendarDayOffset(DateTime(month.year, month.month + 1), 14);
      if (first.isBefore(from)) from = first;
      if (last.isAfter(to)) to = last;
    }
    return CalendarWindow(from, to);
  }

  Future<void> _connect() async {
    try {
      final selections = await _calendar.readGoogleSelection();
      if (_disposed) return;
      final providers =
          await buildGoogleCalendarProviders(selections: selections);
      if (_disposed) {
        for (final provider in providers) {
          provider.dispose();
        }
        return;
      }
      for (final provider in providers) {
        _calendar.addProvider(provider);
      }
    } catch (error) {
      Log.warn('Connected calendars could not be read for Home: $error');
    }
  }

  HomeAgenda agendaAt(DateTime now) {
    final from = DateTime(now.year, now.month, now.day);
    return HomeAgenda.compute(
      now: now,
      events: _calendar.eventsBetween(from, from.add(const Duration(days: 9))),
      reminders: _store.reminders,
      colorOf: _calendar.colorFor,
    );
  }

  Iterable<CalendarEvent> _eventsBetween(DateTime from, DateTime to) =>
      _calendar.eventsBetween(from, to).where(
            (event) =>
                event.kind != CalendarEventKind.reminder && !event.isCompleted,
          );

  /// Calendar events on [day], all-day ones first, then by time. Reminders
  /// have their own list.
  List<HomeAgendaItem> eventsOn(DateTime day) {
    final from = startOfDay(day);
    return [
      for (final event in _eventsBetween(from, calendarDayOffset(from, 1)))
        if (event.touchesDay(from))
          HomeAgendaItem.event(event, _calendar.colorFor(event)),
    ]..sort(_compareItems);
  }

  /// Events in the [days] after [day], soonest first.
  List<HomeAgendaItem> eventsAfter(
    DateTime day, {
    int days = 7,
    int limit = 3,
  }) {
    final from = calendarDayOffset(startOfDay(day), 1);
    final items = [
      for (final event in _eventsBetween(from, calendarDayOffset(from, days)))
        if (!event.startDay.isBefore(from))
          HomeAgendaItem.event(event, _calendar.colorFor(event)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return items.take(limit).toList();
  }

  /// The days in [from]..[to) that hold an event.
  Set<DateTime> eventDays(DateTime from, DateTime to) {
    final start = startOfDay(from);
    final end = startOfDay(to);
    final days = <DateTime>{};
    for (final event in _eventsBetween(start, end)) {
      var day = event.startDay.isBefore(start) ? start : event.startDay;
      while (!day.isAfter(event.endDay) && day.isBefore(end)) {
        days.add(day);
        day = calendarDayOffset(day, 1);
      }
    }
    return days;
  }

  /// Reminders still waiting to be done, overdue ones first, then soonest.
  List<HomeAgendaItem> outstandingReminders() => [
        for (final reminder in _store.reminders)
          if (!reminder.isDone && !reminder.isArchived)
            HomeAgendaItem.reminder(reminder),
      ]..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : _compareItems(a, b);
        });

  /// The days that have a reminder waiting on them.
  Set<DateTime> reminderDays() => {
        for (final item in outstandingReminders()) startOfDay(item.start),
      };

  Future<void> refresh() => _store.refresh();

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) {
      _store.removeListener(_changed);
      _calendar.removeListener(_changed);
    }
    if (_ownsCalendar) _calendar.dispose();
    super.dispose();
  }
}
