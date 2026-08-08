import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/calendar/google_calendar_provider.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:flutter/material.dart';

/// How the calendar is being narrowed, if at all.
@immutable
class CalendarFilter {
  const CalendarFilter({
    this.query = '',
    this.showEvents = true,
    this.showReminders = true,
    this.showCompleted = true,
    this.hiddenCalendars = const <String>{},
  });

  final String query;
  final bool showEvents;
  final bool showReminders;
  final bool showCompleted;
  final Set<String> hiddenCalendars;

  bool get isActive =>
      query.trim().isNotEmpty ||
      !showEvents ||
      !showReminders ||
      !showCompleted ||
      hiddenCalendars.isNotEmpty;

  bool allows(CalendarEvent event) {
    if (hiddenCalendars.contains(event.calendarId)) {
      return false;
    }
    if (!showCompleted && event.isCompleted) {
      return false;
    }
    final isReminder = event.kind == CalendarEventKind.reminder;
    if (isReminder && !showReminders) {
      return false;
    }
    if (!isReminder && !showEvents) {
      return false;
    }
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    return event.title.toLowerCase().contains(needle) ||
        event.location.toLowerCase().contains(needle) ||
        event.description.toLowerCase().contains(needle);
  }

  CalendarFilter copyWith({
    String? query,
    bool? showEvents,
    bool? showReminders,
    bool? showCompleted,
    Set<String>? hiddenCalendars,
  }) =>
      CalendarFilter(
        query: query ?? this.query,
        showEvents: showEvents ?? this.showEvents,
        showReminders: showReminders ?? this.showReminders,
        showCompleted: showCompleted ?? this.showCompleted,
        hiddenCalendars: hiddenCalendars ?? this.hiddenCalendars,
      );
}

/// Everything the calendar shows, from every source, in one place.
///
/// The views read this and nothing else, which is what keeps them ignorant of
/// whether an event is a table row, a reminder or a Google entry.
class CalendarWorkspace extends ChangeNotifier {
  CalendarWorkspace({
    required List<CalendarProvider> providers,
    KeyValueStorage? storage,
  })  : _providers = providers,
        _storage = storage {
    for (final provider in _providers) {
      provider.addListener(_onProviderChanged);
    }
  }

  /// Where the Google calendar picks are remembered.
  static const selectionKey = 'appflowy_google_calendar_selection';

  final List<CalendarProvider> _providers;
  final KeyValueStorage? _storage;

  CalendarFilter _filter = const CalendarFilter();
  CalendarWindow? _window;
  bool _loading = false;

  List<CalendarProvider> get providers =>
      List<CalendarProvider>.unmodifiable(_providers);

  /// Take on a source discovered after the calendar opened — a connected
  /// account is read in the background so the local sources draw immediately.
  void addProvider(CalendarProvider provider) {
    if (_providers.contains(provider)) {
      return;
    }
    _providers.add(provider);
    provider.addListener(_onProviderChanged);
    notifyListeners();
    final window = _window;
    if (window != null) {
      unawaited(provider.load(window));
    }
  }

  void removeProvider(CalendarProvider provider) {
    if (!_providers.remove(provider)) {
      return;
    }
    provider.removeListener(_onProviderChanged);
    provider.dispose();
    notifyListeners();
  }

  CalendarFilter get filter => _filter;

  bool get isLoading => _loading;

  /// Every calendar on offer, in the order the providers were given.
  List<CalendarInfo> get calendars => [
        for (final provider in _providers) ...provider.calendars,
      ];

  /// The colour an event should be drawn in.
  Color colorFor(CalendarEvent event) {
    final own = event.color;
    if (own != null) {
      return own;
    }
    for (final calendar in calendars) {
      if (calendar.id == event.calendarId) {
        return calendar.color;
      }
    }
    return const Color(0xFF3B82F6);
  }

  /// Everything visible, already filtered and sorted.
  List<CalendarEvent> get events {
    final all = <CalendarEvent>[];
    for (final provider in _providers) {
      for (final event in provider.events) {
        if (_filter.allows(event)) {
          all.add(event);
        }
      }
    }
    all.sort(compareCalendarEvents);
    return all;
  }

  /// Only what falls inside [from]..[to], which is what a view actually draws.
  List<CalendarEvent> eventsBetween(DateTime from, DateTime to) => [
        for (final event in events)
          if (event.overlaps(from, to)) event,
      ];

  /// The worst state any source is in — one indicator, not one per calendar.
  CalendarSyncStatus get status {
    if (_providers.isEmpty) {
      return CalendarSyncStatus.idle;
    }
    CalendarSyncStatus worst = _providers.first.status;
    for (final provider in _providers) {
      final status = provider.status;
      if (_rank(status.state) > _rank(worst.state)) {
        worst = status;
      }
    }
    return worst;
  }

  static int _rank(CalendarSyncState state) => switch (state) {
        CalendarSyncState.expired => 5,
        CalendarSyncState.failed => 4,
        CalendarSyncState.offline => 3,
        CalendarSyncState.syncing => 2,
        CalendarSyncState.synced => 1,
        CalendarSyncState.idle => 0,
      };

  /// The sources that are not local, for the sync indicator.
  List<CalendarProvider> get remoteProviders =>
      _providers.where((p) => !p.service.isLocal).toList(growable: false);

  Future<void> load(CalendarWindow window) async {
    if (_window != null && _window!.covers(window)) {
      return;
    }
    _window = window;
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final window = _window ??
        CalendarWindow(
          DateTime(DateTime.now().year, DateTime.now().month - 1),
          DateTime(DateTime.now().year, DateTime.now().month + 2),
        );
    await Future.wait([
      for (final provider in _providers) provider.load(window),
    ]);
    _loading = false;
    notifyListeners();
  }

  void setFilter(CalendarFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void setCalendarVisible(String calendarId, bool visible) {
    for (final provider in _providers) {
      provider.setCalendarVisible(calendarId, visible);
    }
    final hidden = Set<String>.from(_filter.hiddenCalendars);
    if (visible) {
      hidden.remove(calendarId);
    } else {
      hidden.add(calendarId);
    }
    _filter = _filter.copyWith(hiddenCalendars: hidden);
    notifyListeners();
  }

  void setCalendarColor(String calendarId, Color color) {
    for (final provider in _providers) {
      provider.setCalendarColor(calendarId, color);
    }
    notifyListeners();
  }

  /// Which provider owns [event], so a write goes to the right place.
  CalendarProvider? providerFor(CalendarEvent event) {
    for (final provider in _providers) {
      if (provider.calendars.any((c) => c.id == event.calendarId)) {
        return provider;
      }
    }
    return null;
  }

  /// Where a new event should go when nobody said.
  CalendarProvider? get defaultProvider {
    for (final provider in _providers) {
      if (provider.capabilities.canCreate) {
        return provider;
      }
    }
    return null;
  }

  Future<bool> reschedule(
    CalendarEvent event, {
    required DateTime start,
    DateTime? end,
  }) async {
    final provider = providerFor(event);
    if (provider == null) {
      return false;
    }
    final movedStart = event.start.at(start);
    final movedEnd = end == null ? null : (event.end ?? event.start).at(end);
    return provider.rescheduleEvent(event, start: movedStart, end: movedEnd);
  }

  Future<bool> delete(CalendarEvent event) async =>
      await providerFor(event)?.deleteEvent(event) ?? false;

  Future<CalendarEvent?> create(CalendarEventDraft draft) async {
    final provider = draft.calendarId.isEmpty
        ? defaultProvider
        : _providers.firstWhere(
            (p) => p.calendars.any((c) => c.id == draft.calendarId),
            orElse: () => defaultProvider ?? _providers.first,
          );
    return provider?.createEvent(draft);
  }

  void _onProviderChanged() => notifyListeners();

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  /// Remember which Google calendars are being shown.
  Future<void> saveGoogleSelection(
    List<GoogleCalendarSelection> selections,
  ) async {
    await _kv?.set(selectionKey, GoogleCalendarSelection.encodeAll(selections));
  }

  Future<List<GoogleCalendarSelection>> readGoogleSelection() async =>
      GoogleCalendarSelection.decodeAll(await _kv?.get(selectionKey));

  @override
  void dispose() {
    for (final provider in _providers) {
      provider.removeListener(_onProviderChanged);
      provider.dispose();
    }
    super.dispose();
  }
}

/// Build the Google sources for every connected account.
///
/// Returns nothing at all when nobody has connected one, which is what makes
/// the calendar work identically with and without an external service.
Future<List<GoogleCalendarProvider>> buildGoogleCalendarProviders({
  ProviderConnections? connections,
  List<GoogleCalendarSelection> selections = const [],
}) async {
  final store = connections ?? ProviderConnections.instance;
  await store.ensureLoaded();

  final providers = <GoogleCalendarProvider>[];
  for (final connection in store.all) {
    if (connection.service != ProviderService.googleCalendar) {
      continue;
    }
    final selection = selections.firstWhere(
      (s) => s.connectionId == connection.id,
      orElse: () => GoogleCalendarSelection(
        connectionId: connection.id,
        calendarIds: const <String>{},
      ),
    );
    providers.add(
      GoogleCalendarProvider(
        connection: connection,
        selectedCalendarIds: selection.calendarIds,
      ),
    );
  }
  return providers;
}
