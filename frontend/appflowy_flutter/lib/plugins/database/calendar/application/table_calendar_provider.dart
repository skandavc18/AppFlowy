import 'dart:async';

import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter/material.dart';

/// The table this calendar is a reading of.
///
/// Every write goes through the row, so the grid, the board, the timeline and
/// the calendar can never disagree — which is the whole point of the calendar
/// staying a *view* of the table rather than a second store.
class TableCalendarProvider extends CalendarProvider {
  TableCalendarProvider({
    required this.databaseController,
    required this.calendarName,
    this.accent = const Color(0xFF3B82F6),
  }) {
    _calendar = CalendarInfo(
      id: localCalendarId,
      name: calendarName,
      service: CalendarService.local,
      color: accent,
      isPrimary: true,
    );
    _listen();
  }

  /// The one calendar a table stands for.
  static const localCalendarId = 'appflowy:table';

  final DatabaseController databaseController;
  final String calendarName;
  final Color accent;

  late CalendarInfo _calendar;
  final List<CalendarEvent> _events = <CalendarEvent>[];
  CalendarSyncStatus _status = CalendarSyncStatus.idle;

  DatabaseCallbacks? _callbacks;
  bool _disposed = false;

  String get viewId => databaseController.viewId;

  String? get _dateFieldId =>
      databaseController.databaseLayoutSetting?.calendar.fieldId;

  FieldInfo? get dateField {
    final id = _dateFieldId;
    if (id == null || id.isEmpty) {
      return null;
    }
    return databaseController.fieldController.getField(id);
  }

  @override
  CalendarService get service => CalendarService.local;

  @override
  List<CalendarInfo> get calendars => [_calendar];

  @override
  CalendarCapabilities get capabilities => CalendarCapabilities.full;

  @override
  CalendarSyncStatus get status => _status;

  @override
  List<CalendarEvent> get events => List<CalendarEvent>.unmodifiable(_events);

  void _listen() {
    _callbacks = DatabaseCallbacks(
      onRowsCreated: (_) => unawaited(refresh()),
      onRowsDeleted: (_) => unawaited(refresh()),
      onRowsUpdated: (_, __) => unawaited(refresh()),
      onNumOfRowsChanged: (_, __, ___) => unawaited(refresh()),
    );
    databaseController.addListener(onDatabaseChanged: _callbacks);
  }

  @override
  Future<void> load(CalendarWindow window) => refresh();

  @override
  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    final result = await DatabaseEventGetAllCalendarEvents(
      CalendarEventRequestPB(viewId: viewId),
    ).send();
    if (_disposed) {
      return;
    }
    result.fold(
      (payload) {
        _events
          ..clear()
          ..addAll(payload.items.map(_convert).whereType<CalendarEvent>());
        _status = CalendarSyncStatus(
          state: CalendarSyncState.synced,
          lastSyncedAt: DateTime.now(),
        );
        notifyListeners();
      },
      (error) {
        Log.error('The calendar could not read its table: $error');
        _status = const CalendarSyncStatus(state: CalendarSyncState.failed);
        notifyListeners();
      },
    );
  }

  /// A row as something the calendar can draw.
  ///
  /// Public so the whole conversion can be checked without a backend.
  @visibleForTesting
  static CalendarEvent? convert(
    CalendarEventPB pb, {
    String calendarId = localCalendarId,
  }) {
    if (!pb.hasTimestamp()) {
      return null;
    }
    final start = DateTime.fromMillisecondsSinceEpoch(
      pb.timestamp.toInt() * 1000,
    );
    final hasEnd = pb.hasEndTimestamp() && pb.isRange;
    final end = hasEnd
        ? DateTime.fromMillisecondsSinceEpoch(pb.endTimestamp.toInt() * 1000)
        : null;

    return CalendarEvent(
      id: 'row:${pb.rowMeta.id}',
      calendarId: calendarId,
      title: pb.title,
      start: pb.includeTime
          ? ZonedDateTime.local(start)
          : ZonedDateTime.allDay(start),
      end: end == null
          ? null
          : pb.includeTime
              ? ZonedDateTime.local(end)
              : ZonedDateTime.allDay(end),
      hasReminder: pb.reminderId.isNotEmpty,
      reminderId: pb.reminderId,
      rowId: pb.rowMeta.id,
    );
  }

  CalendarEvent? _convert(CalendarEventPB pb) =>
      convert(pb, calendarId: _calendar.id);

  @override
  Future<CalendarEvent?> createEvent(CalendarEventDraft draft) async {
    final field = dateField;
    if (field == null) {
      Log.warn('The calendar has no date column, so it cannot add an event.');
      return null;
    }
    final result = await RowBackendService.createRow(
      viewId: viewId,
      withCells: (builder) => builder.insertDate(field, draft.start.local),
    );
    return result.fold(
      (meta) async {
        // A row created with only a timestamp is an all-day row; anything with
        // a clock or an end has to be written into the cell afterwards.
        if (!draft.start.isAllDay || draft.end != null) {
          await DateCellBackendService(
            viewId: viewId,
            fieldId: field.id,
            rowId: meta.id,
          ).update(
            includeTime: !draft.start.isAllDay,
            isRange: draft.end != null,
            date: draft.start.local,
            endDate: draft.end?.local,
          );
        }
        await refresh();
        return _events.firstWhere(
          (e) => e.rowId == meta.id,
          orElse: () => CalendarEvent(
            id: 'row:${meta.id}',
            calendarId: _calendar.id,
            title: draft.title,
            start: draft.start,
            end: draft.end,
            rowId: meta.id,
          ),
        );
      },
      (error) {
        Log.error('The calendar could not add a row: $error');
        return null;
      },
    );
  }

  @override
  Future<bool> rescheduleEvent(
    CalendarEvent event, {
    required ZonedDateTime start,
    ZonedDateTime? end,
  }) async {
    final field = dateField;
    if (field == null || event.rowId.isEmpty) {
      return false;
    }
    final result = await DateCellBackendService(
      viewId: viewId,
      fieldId: field.id,
      rowId: event.rowId,
    ).update(
      includeTime: !start.isAllDay,
      isRange: end != null,
      date: start.local,
      endDate: end?.local,
    );
    return result.fold(
      (_) {
        // Answer from the local copy at once so the block does not snap back
        // while the row round trip is in flight.
        final index = _events.indexWhere((e) => e.id == event.id);
        if (index >= 0) {
          _events[index] = _events[index].copyWith(
            start: start,
            end: end,
            clearEnd: end == null,
          );
          notifyListeners();
        }
        unawaited(refresh());
        return true;
      },
      (error) {
        Log.error('The calendar could not move a row: $error');
        return false;
      },
    );
  }

  @override
  Future<bool> updateEvent(
    CalendarEvent event,
    CalendarEventDraft draft,
  ) =>
      rescheduleEvent(event, start: draft.start, end: draft.end);

  @override
  Future<bool> deleteEvent(CalendarEvent event) async {
    if (event.rowId.isEmpty) {
      return false;
    }
    final result = await RowBackendService.deleteRows(viewId, [event.rowId]);
    return result.fold((_) => true, (error) {
      Log.error('The calendar could not delete a row: $error');
      return false;
    });
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

  /// Rename the calendar when the view is renamed.
  void rename(String name) {
    if (_calendar.name == name) {
      return;
    }
    _calendar = _calendar.copyWith(name: name);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    databaseController.removeListener(onDatabaseChanged: _callbacks);
    _callbacks = null;
    super.dispose();
  }
}
