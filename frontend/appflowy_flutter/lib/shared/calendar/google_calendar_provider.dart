import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_http.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

/// Google's own colour numbers, so a calendar keeps the hue somebody chose in
/// Google rather than being recoloured on arrival.
const Map<String, Color> googleCalendarColors = {
  '1': Color(0xFF7986CB),
  '2': Color(0xFF33B679),
  '3': Color(0xFF8E24AA),
  '4': Color(0xFFE67C73),
  '5': Color(0xFFF6BF26),
  '6': Color(0xFFF4511E),
  '7': Color(0xFF039BE5),
  '8': Color(0xFF616161),
  '9': Color(0xFF3F51B5),
  '10': Color(0xFF0B8043),
  '11': Color(0xFFD50000),
};

/// One calendar hosted by Google, read and written through its v3 API.
///
/// It answers the same [CalendarProvider] questions the table does, which is
/// what lets the renderer stay ignorant of where an event came from — there is
/// deliberately no Google-shaped interface anywhere in the calendar.
class GoogleCalendarProvider extends CalendarProvider {
  GoogleCalendarProvider({
    required this.connection,
    required this.selectedCalendarIds,
    ProviderTransport? transport,
    this.onCalendarsDiscovered,
  }) : _transport = transport ?? ProviderTransport(connectionId: connection.id);

  static const _base = 'https://www.googleapis.com/calendar/v3';

  /// How many events one page may bring back. Google caps this at 2500.
  static const _pageSize = 250;

  final ProviderConnection connection;

  /// Which of the account's calendars are being shown. Empty means "the ones
  /// Google marks as selected".
  final Set<String> selectedCalendarIds;

  /// Called once the account's calendar list is known, so settings can offer
  /// them without a second request.
  final void Function(List<CalendarInfo>)? onCalendarsDiscovered;

  final ProviderTransport _transport;

  final List<CalendarInfo> _calendars = <CalendarInfo>[];
  final Map<String, List<CalendarEvent>> _byCalendar =
      <String, List<CalendarEvent>>{};
  final Map<String, Color> _colorOverrides = <String, Color>{};
  final Set<String> _hidden = <String>{};

  CalendarSyncStatus _status = CalendarSyncStatus.idle;
  CalendarWindow? _window;
  bool _disposed = false;

  /// Writes made while offline, replayed when the service is reachable again.
  final List<_PendingWrite> _pending = <_PendingWrite>[];

  @override
  CalendarService get service => CalendarService.google;

  @override
  List<CalendarInfo> get calendars => [
        for (final calendar in _calendars)
          calendar.copyWith(
            isVisible: !_hidden.contains(calendar.id),
            color: _colorOverrides[calendar.id] ?? calendar.color,
          ),
      ];

  @override
  CalendarCapabilities get capabilities {
    final canWrite = connection.scopes.any(
      (s) => s.endsWith('/auth/calendar') || s.endsWith('/calendar.events'),
    );
    return canWrite ? CalendarCapabilities.full : CalendarCapabilities.readOnly;
  }

  @override
  CalendarSyncStatus get status =>
      _status.copyWith(pendingWrites: _pending.length);

  @override
  List<CalendarEvent> get events => [
        for (final entry in _byCalendar.entries)
          if (!_hidden.contains(entry.key))
            for (final event in entry.value)
              _colorOverrides.containsKey(entry.key)
                  ? event.copyWith(color: _colorOverrides[entry.key])
                  : event,
      ];

  @override
  Future<void> load(CalendarWindow window) async {
    final known = _window;
    if (known != null && known.covers(window) && _byCalendar.isNotEmpty) {
      return;
    }
    _window = window.padded();
    await _sync();
  }

  @override
  Future<void> refresh() async {
    _window ??= _defaultWindow();
    await _sync(force: true);
  }

  CalendarWindow _defaultWindow() {
    final now = DateTime.now();
    return CalendarWindow(
      DateTime(now.year, now.month - 1),
      DateTime(now.year, now.month + 2),
    );
  }

  Future<void> _sync({bool force = false}) async {
    if (_disposed) {
      return;
    }
    _setStatus(const CalendarSyncStatus(state: CalendarSyncState.syncing));
    try {
      await _drainPending();
      if (_calendars.isEmpty || force) {
        await _readCalendarList();
      }
      final window = _window ?? _defaultWindow();
      for (final calendar in _calendars) {
        if (_hidden.contains(calendar.id)) {
          continue;
        }
        _byCalendar[calendar.id] = await _readEvents(calendar, window);
      }
      _setStatus(
        CalendarSyncStatus(
          state: CalendarSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } on ProviderFailure catch (failure) {
      _setStatus(_statusFor(failure));
    } catch (error) {
      Log.warn('Google Calendar could not be read: $error');
      _setStatus(const CalendarSyncStatus(state: CalendarSyncState.failed));
    }
  }

  CalendarSyncStatus _statusFor(ProviderFailure failure) =>
      switch (failure.status) {
        ProviderStatus.offline =>
          const CalendarSyncStatus(state: CalendarSyncState.offline),
        ProviderStatus.authExpired ||
        ProviderStatus.permissionDenied =>
          const CalendarSyncStatus(state: CalendarSyncState.expired),
        _ => const CalendarSyncStatus(state: CalendarSyncState.failed),
      };

  void _setStatus(CalendarSyncStatus status) {
    _status = status;
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _readCalendarList() async {
    final body = await _transport.json('$_base/users/me/calendarList');
    final items = body is Map ? body['items'] : null;
    if (items is! List) {
      return;
    }
    final found = <CalendarInfo>[];
    for (final raw in items) {
      if (raw is! Map) {
        continue;
      }
      final id = _text(raw['id']);
      if (id.isEmpty) {
        continue;
      }
      final selected = selectedCalendarIds.isEmpty
          ? raw['selected'] == true || raw['primary'] == true
          : selectedCalendarIds.contains(id);
      if (!selected) {
        continue;
      }
      found.add(
        CalendarInfo(
          id: qualify(connection.id, id),
          name: _text(raw['summaryOverride'], _text(raw['summary'], id)),
          service: CalendarService.google,
          color: _colorOf(raw),
          description: _text(raw['description']),
          isPrimary: raw['primary'] == true,
          isReadOnly: _text(raw['accessRole']) == 'reader' ||
              _text(raw['accessRole']) == 'freeBusyReader',
          timeZone: _text(raw['timeZone']),
          accountLabel: connection.accountLabel,
          connectionId: connection.id,
        ),
      );
    }
    _calendars
      ..clear()
      ..addAll(found);
    _byCalendar.removeWhere(
      (id, _) => !_calendars.any((calendar) => calendar.id == id),
    );
    onCalendarsDiscovered?.call(List<CalendarInfo>.unmodifiable(_calendars));
  }

  static Color _colorOf(Map<Object?, Object?> raw) {
    final hex = _text(raw['backgroundColor']);
    if (hex.startsWith('#') && hex.length == 7) {
      final value = int.tryParse(hex.substring(1), radix: 16);
      if (value != null) {
        return Color(0xFF000000 | value);
      }
    }
    return googleCalendarColors[_text(raw['colorId'])] ??
        const Color(0xFF1A73E8);
  }

  Future<List<CalendarEvent>> _readEvents(
    CalendarInfo calendar,
    CalendarWindow window,
  ) async {
    final remote = remoteIdOf(calendar.id);
    final events = <CalendarEvent>[];
    String? pageToken;
    var pages = 0;

    do {
      final body = await _transport.json(
        '$_base/calendars/${Uri.encodeComponent(remote)}/events',
        query: {
          'timeMin': window.from.toUtc().toIso8601String(),
          'timeMax': window.to.toUtc().toIso8601String(),
          // Recurring events are asked for already expanded: without an RRULE
          // engine this side, letting Google do it is the only honest answer.
          'singleEvents': 'true',
          'orderBy': 'startTime',
          'maxResults': '$_pageSize',
          'showDeleted': 'false',
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      if (body is! Map) {
        break;
      }
      final items = body['items'];
      if (items is List) {
        for (final raw in items) {
          if (raw is Map) {
            final event = parseGoogleEvent(
              Map<String, Object?>.from(raw),
              calendarId: calendar.id,
              readOnly: calendar.isReadOnly || !capabilities.canEdit,
            );
            if (event != null) {
              events.add(event);
            }
          }
        }
      }
      pageToken = _text(body['nextPageToken']);
      if (pageToken.isEmpty) {
        pageToken = null;
      }
      pages++;
      // A window of a few months cannot honestly need more than this; the cap
      // stops a mis-set window walking somebody's whole history.
    } while (pageToken != null && pages < 12);

    return events;
  }

  // --- writes ---------------------------------------------------------------

  @override
  Future<CalendarEvent?> createEvent(CalendarEventDraft draft) async {
    if (!capabilities.canCreate) {
      return null;
    }
    final calendarId = draft.calendarId.isNotEmpty
        ? draft.calendarId
        : _calendars
            .firstWhere(
              (c) => c.isPrimary && !c.isReadOnly,
              orElse: () => _calendars.isEmpty
                  ? const CalendarInfo(
                      id: '',
                      name: '',
                      service: CalendarService.google,
                    )
                  : _calendars.first,
            )
            .id;
    if (calendarId.isEmpty) {
      return null;
    }

    try {
      final body = await _transport.json(
        '$_base/calendars/${Uri.encodeComponent(remoteIdOf(calendarId))}/events',
        method: 'POST',
        body: googleEventBody(
          title: draft.title,
          start: draft.start,
          end: draft.end,
          description: draft.description,
          location: draft.location,
        ),
      );
      if (body is! Map) {
        return null;
      }
      final event = parseGoogleEvent(
        Map<String, Object?>.from(body),
        calendarId: calendarId,
      );
      if (event != null) {
        _byCalendar.putIfAbsent(calendarId, () => <CalendarEvent>[]).add(event);
        notifyListeners();
      }
      return event;
    } on ProviderFailure catch (failure) {
      _remember(_PendingWrite.create(draft));
      _setStatus(_statusFor(failure));
      return null;
    }
  }

  @override
  Future<bool> rescheduleEvent(
    CalendarEvent event, {
    required ZonedDateTime start,
    ZonedDateTime? end,
  }) async {
    if (!capabilities.canMove || event.readOnly) {
      return false;
    }
    final moved = event.copyWith(start: start, end: end, clearEnd: end == null);
    _applyLocally(moved);

    try {
      await _transport.json(
        '$_base/calendars/${Uri.encodeComponent(remoteIdOf(event.calendarId))}'
        '/events/${Uri.encodeComponent(event.remoteId)}',
        method: 'PATCH',
        body: googleEventBody(start: start, end: end),
      );
      return true;
    } on ProviderFailure catch (failure) {
      _remember(_PendingWrite.reschedule(event, start, end));
      _setStatus(_statusFor(failure));
      // The local move stands: it will go out when the service is reachable.
      return true;
    }
  }

  @override
  Future<bool> updateEvent(
    CalendarEvent event,
    CalendarEventDraft draft,
  ) async {
    if (!capabilities.canEdit || event.readOnly) {
      return false;
    }
    try {
      await _transport.json(
        '$_base/calendars/${Uri.encodeComponent(remoteIdOf(event.calendarId))}'
        '/events/${Uri.encodeComponent(event.remoteId)}',
        method: 'PATCH',
        body: googleEventBody(
          title: draft.title,
          start: draft.start,
          end: draft.end,
          description: draft.description,
          location: draft.location,
        ),
      );
      _applyLocally(
        event.copyWith(
          title: draft.title,
          start: draft.start,
          end: draft.end,
          clearEnd: draft.end == null,
          description: draft.description,
          location: draft.location,
        ),
      );
      return true;
    } on ProviderFailure catch (failure) {
      _setStatus(_statusFor(failure));
      return false;
    }
  }

  @override
  Future<bool> deleteEvent(CalendarEvent event) async {
    if (!capabilities.canDelete || event.readOnly) {
      return false;
    }
    _byCalendar[event.calendarId]?.removeWhere((e) => e.id == event.id);
    notifyListeners();
    try {
      await _transport.send(
        '$_base/calendars/${Uri.encodeComponent(remoteIdOf(event.calendarId))}'
        '/events/${Uri.encodeComponent(event.remoteId)}',
        method: 'DELETE',
      );
      return true;
    } on ProviderFailure catch (failure) {
      _remember(_PendingWrite.delete(event));
      _setStatus(_statusFor(failure));
      return true;
    }
  }

  void _applyLocally(CalendarEvent event) {
    final list = _byCalendar[event.calendarId];
    if (list == null) {
      return;
    }
    final index = list.indexWhere((e) => e.id == event.id);
    if (index >= 0) {
      list[index] = event;
      notifyListeners();
    }
  }

  void _remember(_PendingWrite write) {
    _pending
      ..removeWhere((existing) => existing.key == write.key)
      ..add(write);
  }

  /// Replay what was done offline. Anything that fails again stays queued.
  Future<void> _drainPending() async {
    if (_pending.isEmpty) {
      return;
    }
    final queued = List<_PendingWrite>.from(_pending);
    _pending.clear();
    for (final write in queued) {
      try {
        await write.send(this);
      } on ProviderFailure {
        _pending.add(write);
      }
    }
  }

  @override
  void setCalendarVisible(String calendarId, bool visible) {
    if (visible) {
      _hidden.remove(calendarId);
    } else {
      _hidden.add(calendarId);
    }
    notifyListeners();
    if (visible && !_byCalendar.containsKey(calendarId)) {
      unawaited(refresh());
    }
  }

  @override
  void setCalendarColor(String calendarId, Color color) {
    _colorOverrides[calendarId] = color;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// A calendar id that stays unique when two accounts hold the same calendar.
  static String qualify(String connectionId, String remoteId) =>
      'google:$connectionId:$remoteId';

  /// The other half of [qualify].
  static String remoteIdOf(String calendarId) {
    final parts = calendarId.split(':');
    return parts.length >= 3 ? parts.sublist(2).join(':') : calendarId;
  }

  static String _text(Object? value, [String fallback = '']) =>
      value is String && value.isNotEmpty ? value : fallback;
}

/// One Google event as something the calendar can draw.
///
/// Public and pure so every shape Google sends — timed, all-day, cancelled,
/// zoned — can be checked without a network.
CalendarEvent? parseGoogleEvent(
  Map<String, Object?> raw, {
  required String calendarId,
  bool readOnly = false,
}) {
  if (raw['status'] == 'cancelled') {
    return null;
  }
  final id = raw['id'];
  if (id is! String || id.isEmpty) {
    return null;
  }

  final start = _parseEndpoint(raw['start']);
  if (start == null) {
    return null;
  }
  var end = _parseEndpoint(raw['end']);

  // Google's all-day end is exclusive: a one-day event ends the next morning.
  if (end != null && start.isAllDay && end.isAllDay) {
    final last = end.local.subtract(const Duration(days: 1));
    end = last.isBefore(start.local) ? null : ZonedDateTime.allDay(last);
  }

  final reminders = raw['reminders'];
  final hasReminder = reminders is Map &&
      (reminders['useDefault'] == true ||
          (reminders['overrides'] is List &&
              (reminders['overrides'] as List).isNotEmpty));

  return CalendarEvent(
    id: 'google:$calendarId:$id',
    calendarId: calendarId,
    title: raw['summary'] is String && (raw['summary'] as String).isNotEmpty
        ? raw['summary'] as String
        : '',
    start: start,
    end: end,
    origin: CalendarEventOrigin.external,
    description:
        raw['description'] is String ? raw['description'] as String : '',
    location: raw['location'] is String ? raw['location'] as String : '',
    color: googleCalendarColors[raw['colorId']],
    hasReminder: hasReminder,
    recurrence: _parseRecurrence(raw['recurrence']),
    readOnly: readOnly,
    remoteId: id,
    url: raw['htmlLink'] is String ? raw['htmlLink'] as String : '',
  );
}

ZonedDateTime? _parseEndpoint(Object? value) {
  if (value is! Map) {
    return null;
  }
  final date = value['date'];
  if (date is String && date.isNotEmpty) {
    final parsed = DateTime.tryParse(date);
    return parsed == null ? null : ZonedDateTime.allDay(parsed);
  }
  final dateTime = value['dateTime'];
  if (dateTime is! String || dateTime.isEmpty) {
    return null;
  }
  // The string carries its own offset, which already accounts for daylight
  // saving at that instant — parsing it is what keeps a zoned event correct.
  final parsed = DateTime.tryParse(dateTime);
  if (parsed == null) {
    return null;
  }
  return ZonedDateTime.fromUtc(
    parsed.toUtc(),
    timeZone: value['timeZone'] is String ? value['timeZone'] as String : '',
  );
}

CalendarRecurrence _parseRecurrence(Object? value) {
  if (value is! List) {
    return CalendarRecurrence.none;
  }
  for (final entry in value) {
    if (entry is String && entry.startsWith('RRULE:')) {
      final rule = entry.substring(6);
      final kind = rule.contains('FREQ=DAILY')
          ? CalendarRecurrenceKind.daily
          : rule.contains('FREQ=WEEKLY')
              ? CalendarRecurrenceKind.weekly
              : rule.contains('FREQ=MONTHLY')
                  ? CalendarRecurrenceKind.monthly
                  : rule.contains('FREQ=YEARLY')
                      ? CalendarRecurrenceKind.yearly
                      : CalendarRecurrenceKind.custom;
      return CalendarRecurrence(kind: kind, rrule: rule);
    }
  }
  return CalendarRecurrence.none;
}

/// The body Google wants for a create or a patch.
///
/// An all-day end is written back exclusive, matching the way it is read.
Map<String, Object?> googleEventBody({
  String? title,
  ZonedDateTime? start,
  ZonedDateTime? end,
  String? description,
  String? location,
}) =>
    {
      if (title != null) 'summary': title,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      if (start != null) 'start': _endpointBody(start),
      if (end != null)
        'end': _endpointBody(
          end.isAllDay
              ? ZonedDateTime.allDay(end.local.add(const Duration(days: 1)))
              : end,
        )
      else if (start != null)
        'end': _endpointBody(
          start.isAllDay
              ? ZonedDateTime.allDay(start.local.add(const Duration(days: 1)))
              : start.shiftedBy(const Duration(hours: 1)),
        ),
    };

Map<String, Object?> _endpointBody(ZonedDateTime value) {
  if (value.isAllDay) {
    final day = value.local;
    return {
      'date': '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}',
    };
  }
  return {
    'dateTime': value.utc.toIso8601String(),
    if (value.timeZone.isNotEmpty) 'timeZone': value.timeZone,
  };
}

/// A write that could not go out, kept so it can be replayed.
@immutable
class _PendingWrite {
  const _PendingWrite._(this.key, this._send);

  factory _PendingWrite.create(CalendarEventDraft draft) => _PendingWrite._(
        'create:${draft.title}:${draft.start.millisecondsSinceEpoch}',
        (provider) => provider.createEvent(draft),
      );

  factory _PendingWrite.reschedule(
    CalendarEvent event,
    ZonedDateTime start,
    ZonedDateTime? end,
  ) =>
      _PendingWrite._(
        'move:${event.id}',
        (provider) => provider.rescheduleEvent(event, start: start, end: end),
      );

  factory _PendingWrite.delete(CalendarEvent event) => _PendingWrite._(
        'delete:${event.id}',
        (provider) => provider.deleteEvent(event),
      );

  final String key;
  final Future<Object?> Function(GoogleCalendarProvider) _send;

  Future<void> send(GoogleCalendarProvider provider) => _send(provider);
}

/// Which Google calendars somebody chose, remembered between runs.
@immutable
class GoogleCalendarSelection {
  const GoogleCalendarSelection({
    required this.connectionId,
    required this.calendarIds,
    this.colors = const <String, int>{},
    this.hidden = const <String>{},
    this.defaultCalendarId = '',
  });

  final String connectionId;
  final Set<String> calendarIds;
  final Map<String, int> colors;
  final Set<String> hidden;
  final String defaultCalendarId;

  Map<String, Object?> toJson() => {
        'connection': connectionId,
        'calendars': calendarIds.toList(),
        if (colors.isNotEmpty) 'colors': colors,
        if (hidden.isNotEmpty) 'hidden': hidden.toList(),
        if (defaultCalendarId.isNotEmpty) 'default': defaultCalendarId,
      };

  static GoogleCalendarSelection? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final connection = value['connection'];
    if (connection is! String || connection.isEmpty) {
      return null;
    }
    return GoogleCalendarSelection(
      connectionId: connection,
      calendarIds: {
        ...?(value['calendars'] as List?)?.whereType<String>(),
      },
      colors: {
        for (final entry in _colorEntries(value['colors']))
          entry.key: entry.value,
      },
      hidden: {...?(value['hidden'] as List?)?.whereType<String>()},
      defaultCalendarId:
          value['default'] is String ? value['default'] as String : '',
    );
  }

  static List<MapEntry<String, int>> _colorEntries(Object? value) {
    if (value is! Map) {
      return const [];
    }
    return [
      for (final entry in value.entries)
        if (entry.key is String && entry.value is int)
          MapEntry(entry.key as String, entry.value as int),
    ];
  }

  static String encodeAll(List<GoogleCalendarSelection> all) =>
      jsonEncode([for (final one in all) one.toJson()]);
  static List<GoogleCalendarSelection> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .map(GoogleCalendarSelection.fromJson)
          .whereType<GoogleCalendarSelection>()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
