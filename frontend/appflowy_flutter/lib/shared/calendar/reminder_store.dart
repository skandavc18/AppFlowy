import 'dart:async';

import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/notification_scheduler.dart';
import 'package:appflowy/user/application/reminder/reminder_service.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Every reminder in the workspace, read once and shared.
///
/// The panel, the calendar, the timeline and the notification scheduler all
/// have to agree the moment a reminder is completed or snoozed, so there is
/// exactly one of these rather than a copy per surface.
class ReminderStore extends ChangeNotifier
    implements ReminderNotificationDelegate {
  ReminderStore({IReminderService? service, Duration? refreshEvery})
      : _service = service ?? const ReminderService(),
        _refreshEvery = refreshEvery ?? const Duration(seconds: 30);

  static final ReminderStore instance = ReminderStore();

  final IReminderService _service;
  final Duration _refreshEvery;

  final List<AppReminder> _reminders = <AppReminder>[];
  Timer? _timer;
  bool _loading = false;

  @override
  List<AppReminder> get reminders => List<AppReminder>.unmodifiable(_reminders);

  /// Everything that is not done and not archived, soonest first.
  List<AppReminder> get outstanding =>
      _reminders.where((r) => !r.isDone && !r.isArchived).toList()
        ..sort((a, b) => a.firesAt.compareTo(b.firesAt));

  bool get isLoading => _loading;

  /// Somebody opened a surface that shows reminders.
  void start() {
    _timer ??= Timer.periodic(_refreshEvery, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    if (_loading) {
      return;
    }
    _loading = true;
    final result = await _service.fetchReminders();
    _loading = false;
    result.fold(
      (items) {
        _reminders
          ..clear()
          ..addAll(items.map(AppReminder.fromPB));
        notifyListeners();
      },
      (error) => Log.error('Reminders could not be read: $error'),
    );
  }

  AppReminder? byId(String id) {
    for (final reminder in _reminders) {
      if (reminder.id == id) {
        return reminder;
      }
    }
    return null;
  }

  /// Create one and remember it locally at once, so the interface answers
  /// before the round trip finishes.
  Future<AppReminder?> create(AppReminder reminder) async {
    final withId = reminder.id.isEmpty ? _identified(reminder) : reminder;
    final result = await _service.addReminder(reminder: withId.toPB());
    return result.fold(
      (_) {
        _reminders.add(withId);
        notifyListeners();
        return withId;
      },
      (error) {
        Log.error('A reminder could not be saved: $error');
        return null;
      },
    );
  }

  static AppReminder _identified(AppReminder source) => AppReminder(
        id: const Uuid().v4(),
        title: source.title,
        message: source.message,
        scheduledAt: source.scheduledAt,
        objectId: source.objectId,
        kind: source.kind,
        priority: source.priority,
        recurrence: source.recurrence,
        includeTime: source.includeTime,
        playsSound: source.playsSound,
        calendarId: source.calendarId,
        pageId: source.pageId,
      );

  Future<bool> save(AppReminder reminder) async {
    final result = await _service.updateReminder(reminder: reminder.toPB());
    return result.fold(
      (_) {
        _apply(reminder);
        return true;
      },
      (error) {
        Log.error('A reminder could not be updated: $error');
        return false;
      },
    );
  }

  Future<bool> remove(String id) async {
    final result = await _service.removeReminder(reminderId: id);
    return result.fold(
      (_) {
        _reminders.removeWhere((r) => r.id == id);
        notifyListeners();
        return true;
      },
      (error) {
        Log.error('A reminder could not be removed: $error');
        return false;
      },
    );
  }

  void _apply(AppReminder reminder) {
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index >= 0) {
      _reminders[index] = reminder;
    } else {
      _reminders.add(reminder);
    }
    notifyListeners();
  }

  // --- ReminderNotificationDelegate -----------------------------------------

  @override
  Future<void> markNotified(AppReminder reminder) =>
      save(reminder.copyWith(notifiedAt: DateTime.now()));

  @override
  Future<void> complete(AppReminder reminder) => save(reminder.complete());

  @override
  Future<void> snooze(AppReminder reminder, SnoozeOption option) =>
      save(reminder.snooze(option));

  @override
  Future<void> open(AppReminder reminder) async {
    final handler = onOpenRequested;
    if (handler != null) {
      await handler(reminder);
    }
  }

  /// Set once, by whatever knows how to bring a page or a row to the front.
  Future<void> Function(AppReminder)? onOpenRequested;

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

/// AppFlowy's own reminders, drawn on the calendar beside table events.
///
/// Works with nothing connected and no network — which is exactly what makes
/// it the source everything else falls back to.
class ReminderCalendarProvider extends CalendarProvider {
  ReminderCalendarProvider({
    ReminderStore? store,
    required this.calendarName,
    this.accent = const Color(0xFFF59E0B),
  }) : _store = store ?? ReminderStore.instance {
    _calendar = CalendarInfo(
      id: reminderCalendarId,
      name: calendarName,
      service: CalendarService.local,
      color: accent,
    );
    _store.addListener(_onChanged);
  }

  static const reminderCalendarId = 'appflowy:reminders';

  final ReminderStore _store;
  final String calendarName;
  final Color accent;

  late CalendarInfo _calendar;

  @override
  CalendarService get service => CalendarService.local;

  @override
  List<CalendarInfo> get calendars => [_calendar];

  @override
  CalendarCapabilities get capabilities => const CalendarCapabilities(
        canCreate: true,
        canEdit: true,
        canDelete: true,
        canMove: true,
        supportsReminders: true,
        supportsRecurrence: true,
      );

  @override
  CalendarSyncStatus get status => const CalendarSyncStatus(
        state: CalendarSyncState.synced,
      );

  @override
  List<CalendarEvent> get events => _calendar.isVisible
      ? [
          for (final reminder in _store.reminders)
            if (!reminder.isArchived)
              reminder.toCalendarEvent(calendarOverride: _calendar.id),
        ]
      : const [];

  void _onChanged() => notifyListeners();

  @override
  Future<void> load(CalendarWindow window) => _store.refresh();

  @override
  Future<void> refresh() => _store.refresh();

  @override
  Future<CalendarEvent?> createEvent(CalendarEventDraft draft) async {
    final reminder = AppReminder(
      id: const Uuid().v4(),
      title: draft.title,
      message: draft.description,
      scheduledAt: draft.start.local,
      includeTime: !draft.start.isAllDay,
      recurrence: draft.recurrence,
      calendarId: _calendar.id,
    );
    final saved = await _store.create(reminder);
    return saved?.toCalendarEvent(calendarOverride: _calendar.id);
  }

  @override
  Future<bool> rescheduleEvent(
    CalendarEvent event, {
    required ZonedDateTime start,
    ZonedDateTime? end,
  }) async {
    final reminder = _store.byId(event.reminderId);
    if (reminder == null) {
      return false;
    }
    return _store.save(
      reminder.copyWith(
        scheduledAt: start.local,
        includeTime: !start.isAllDay,
        clearSnooze: true,
        // A moved reminder has not been announced at its new time.
        notifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }

  @override
  Future<bool> updateEvent(
    CalendarEvent event,
    CalendarEventDraft draft,
  ) async {
    final reminder = _store.byId(event.reminderId);
    if (reminder == null) {
      return false;
    }
    return _store.save(
      reminder.copyWith(
        title: draft.title,
        message: draft.description,
        scheduledAt: draft.start.local,
        includeTime: !draft.start.isAllDay,
        recurrence: draft.recurrence,
      ),
    );
  }

  @override
  Future<bool> deleteEvent(CalendarEvent event) =>
      _store.remove(event.reminderId);

  /// Tick a reminder off, or move a repeating one on.
  Future<bool> toggleComplete(CalendarEvent event) async {
    final reminder = _store.byId(event.reminderId);
    if (reminder == null) {
      return false;
    }
    return _store.save(
      reminder.isDone ? reminder.copyWith(isDone: false) : reminder.complete(),
    );
  }

  @override
  void setCalendarVisible(String calendarId, bool visible) {
    if (calendarId != _calendar.id) {
      return;
    }
    _calendar = _calendar.copyWith(isVisible: visible);
    notifyListeners();
  }

  @override
  void setCalendarColor(String calendarId, Color color) {
    if (calendarId != _calendar.id) {
      return;
    }
    _calendar = _calendar.copyWith(color: color);
    notifyListeners();
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }
}

/// A reminder built from ordinary words, ready to be reviewed and saved.
AppReminder buildReminder({
  required String title,
  required DateTime when,
  bool includeTime = true,
  CalendarRecurrence recurrence = CalendarRecurrence.none,
  ReminderPriority priority = ReminderPriority.none,
  ReminderKind kind = ReminderKind.standalone,
  String objectId = '',
  String message = '',
  bool playsSound = true,
}) =>
    AppReminder(
      id: const Uuid().v4(),
      title: title,
      message: message,
      scheduledAt: when,
      objectId: objectId,
      kind: kind,
      priority: priority,
      recurrence: recurrence,
      includeTime: includeTime,
      playsSound: playsSound,
    );

/// The words a notification uses. Kept beside the store so the timing and the
/// copy stay in one place per language.
ReminderNotificationCopy reminderNotificationCopy(
  AppReminder reminder, {
  required String heading,
  required String done,
  required String snooze,
  required String open,
  required String Function(DateTime) formatWhen,
}) =>
    (
      title: reminder.title.isEmpty ? heading : reminder.title,
      body: reminder.message.isEmpty
          ? formatWhen(reminder.scheduledAt)
          : '${reminder.message}\n${formatWhen(reminder.scheduledAt)}',
      done: done,
      snooze: snooze,
      open: open,
    );

/// A reminder made out of a [ReminderPB] that arrived from somewhere else.
AppReminder reminderFromPB(ReminderPB pb) => AppReminder.fromPB(pb);

/// Mark the rows that carry a reminder.
///
/// Pure, so a table view can be checked against a reminder list with no store
/// and no backend. A row with several reminders takes the soonest one that is
/// still outstanding.
List<TableRowCard> attachRemindersToCards(
  List<TableRowCard> cards,
  List<AppReminder> reminders,
) {
  if (cards.isEmpty || reminders.isEmpty) {
    return cards;
  }
  final byRow = <String, AppReminder>{};
  for (final reminder in reminders) {
    if (reminder.rowId.isEmpty || reminder.isArchived) {
      continue;
    }
    final existing = byRow[reminder.rowId];
    if (existing == null ||
        (existing.isDone && !reminder.isDone) ||
        (existing.isDone == reminder.isDone &&
            reminder.firesAt.isBefore(existing.firesAt))) {
      byRow[reminder.rowId] = reminder;
    }
  }
  if (byRow.isEmpty) {
    return cards;
  }
  return [
    for (final card in cards)
      if (byRow[card.rowId] case final reminder?)
        card.withReminder(
          at: reminder.firesAt,
          done: reminder.isDone,
          repeats: reminder.recurrence.repeats,
        )
      else
        card,
  ];
}
