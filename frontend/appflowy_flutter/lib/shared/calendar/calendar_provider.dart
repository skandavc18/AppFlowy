import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:flutter/material.dart';

/// Which implementation answers a calendar's questions.
enum CalendarService {
  /// The table this calendar view is a reading of, plus AppFlowy's own
  /// reminders. Always present, always works offline.
  local,

  /// A calendar hosted by Google.
  google;

  static CalendarService fromValue(Object? value) =>
      CalendarService.values.firstWhere(
        (s) => s.name == value,
        orElse: () => CalendarService.local,
      );

  bool get isLocal => this == CalendarService.local;
}

/// A colour as a single number, which is how a setting stores one.
///
/// `Color.value` is deprecated and `toARGB32` is not in this Flutter version.
int packCalendarColor(Color color) =>
    ((color.a * 255).round() << 24) |
    ((color.r * 255).round() << 16) |
    ((color.g * 255).round() << 8) |
    (color.b * 255).round();

/// How a connected calendar is getting on.
///
/// The interface says one short thing per state and nothing else — a sync
/// indicator that shouts is worse than none.
enum CalendarSyncState {
  idle,
  syncing,
  synced,
  offline,
  expired,
  failed;

  bool get isBusy => this == CalendarSyncState.syncing;
  bool get needsAttention =>
      this == CalendarSyncState.expired || this == CalendarSyncState.failed;
}

/// What a source reports about itself, without any words for the screen.
@immutable
class CalendarSyncStatus {
  const CalendarSyncStatus({
    this.state = CalendarSyncState.idle,
    this.lastSyncedAt,
    this.detail = '',
    this.pendingWrites = 0,
  });

  static const idle = CalendarSyncStatus();

  final CalendarSyncState state;
  final DateTime? lastSyncedAt;

  /// One sentence, already safe to show. Never a raw response body.
  final String detail;

  /// Changes made offline that are still waiting to go out.
  final int pendingWrites;

  CalendarSyncStatus copyWith({
    CalendarSyncState? state,
    DateTime? lastSyncedAt,
    String? detail,
    int? pendingWrites,
  }) =>
      CalendarSyncStatus(
        state: state ?? this.state,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        detail: detail ?? this.detail,
        pendingWrites: pendingWrites ?? this.pendingWrites,
      );
}

/// One calendar somebody can show or hide.
@immutable
class CalendarInfo {
  const CalendarInfo({
    required this.id,
    required this.name,
    required this.service,
    this.color = const Color(0xFF3B82F6),
    this.description = '',
    this.isVisible = true,
    this.isPrimary = false,
    this.isReadOnly = false,
    this.timeZone = '',
    this.accountLabel = '',
    this.connectionId = '',
  });

  /// Unique across every connected account: `<service>:<connection>:<remote>`.
  final String id;

  final String name;
  final CalendarService service;
  final Color color;
  final String description;

  final bool isVisible;
  final bool isPrimary;

  /// A subscribed feed — holidays, somebody else's shared calendar.
  final bool isReadOnly;

  /// The IANA zone the hosting service files this calendar under.
  final String timeZone;

  /// The account it came through, for the settings list.
  final String accountLabel;
  final String connectionId;

  CalendarInfo copyWith({
    String? name,
    Color? color,
    bool? isVisible,
    bool? isReadOnly,
  }) =>
      CalendarInfo(
        id: id,
        name: name ?? this.name,
        service: service,
        color: color ?? this.color,
        description: description,
        isVisible: isVisible ?? this.isVisible,
        isPrimary: isPrimary,
        isReadOnly: isReadOnly ?? this.isReadOnly,
        timeZone: timeZone,
        accountLabel: accountLabel,
        connectionId: connectionId,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'service': service.name,
        'color': packCalendarColor(color),
        if (description.isNotEmpty) 'description': description,
        'visible': isVisible,
        if (isPrimary) 'primary': true,
        if (isReadOnly) 'read_only': true,
        if (timeZone.isNotEmpty) 'time_zone': timeZone,
        if (accountLabel.isNotEmpty) 'account': accountLabel,
        if (connectionId.isNotEmpty) 'connection': connectionId,
      };

  static CalendarInfo? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final id = value['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final packed = value['color'];
    return CalendarInfo(
      id: id,
      name: value['name'] is String ? value['name'] as String : id,
      service: CalendarService.fromValue(value['service']),
      color: packed is int ? Color(packed) : const Color(0xFF3B82F6),
      description:
          value['description'] is String ? value['description'] as String : '',
      isVisible: value['visible'] != false,
      isPrimary: value['primary'] == true,
      isReadOnly: value['read_only'] == true,
      timeZone:
          value['time_zone'] is String ? value['time_zone'] as String : '',
      accountLabel:
          value['account'] is String ? value['account'] as String : '',
      connectionId:
          value['connection'] is String ? value['connection'] as String : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarInfo &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.isVisible == isVisible &&
      other.isReadOnly == isReadOnly;

  @override
  int get hashCode => Object.hash(id, name, color, isVisible, isReadOnly);
}

/// What a source is allowed to do, asked once rather than guessed per action.
@immutable
class CalendarCapabilities {
  const CalendarCapabilities({
    this.canCreate = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canMove = false,
    this.canResize = false,
    this.supportsReminders = false,
    this.supportsRecurrence = false,
  });

  static const readOnly = CalendarCapabilities();

  static const full = CalendarCapabilities(
    canCreate: true,
    canEdit: true,
    canDelete: true,
    canMove: true,
    canResize: true,
    supportsReminders: true,
    supportsRecurrence: true,
  );

  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
  final bool canMove;
  final bool canResize;
  final bool supportsReminders;
  final bool supportsRecurrence;

  bool get canWrite => canCreate || canEdit || canDelete;
}

/// The window a view is showing, so a source only fetches what is on screen.
@immutable
class CalendarWindow {
  const CalendarWindow(this.from, this.to);

  /// Inclusive, at local midnight.
  final DateTime from;

  /// Exclusive, at local midnight.
  final DateTime to;

  bool contains(DateTime day) => !day.isBefore(from) && day.isBefore(to);

  /// Whether [other] is already covered by this window.
  bool covers(CalendarWindow other) =>
      !other.from.isBefore(from) && !other.to.isAfter(to);

  /// Grow to whole months either side, so paging a month never refetches.
  CalendarWindow padded({int months = 1}) => CalendarWindow(
        DateTime(from.year, from.month - months),
        DateTime(to.year, to.month + months),
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'CalendarWindow($from → $to)';
}

/// A draft of an event, used for both create and edit.
@immutable
class CalendarEventDraft {
  const CalendarEventDraft({
    required this.title,
    required this.start,
    this.end,
    this.calendarId = '',
    this.description = '',
    this.location = '',
    this.recurrence = CalendarRecurrence.none,
    this.kind = CalendarEventKind.event,
  });

  final String title;
  final ZonedDateTime start;
  final ZonedDateTime? end;
  final String calendarId;
  final String description;
  final String location;
  final CalendarRecurrence recurrence;
  final CalendarEventKind kind;
}

/// One source of events, whoever holds them.
///
/// Every method may be called while offline; an implementation that cannot
/// reach its service reports it through [status] and keeps serving whatever it
/// last read rather than throwing at the renderer.
abstract class CalendarProvider extends ChangeNotifier {
  CalendarService get service;

  /// The calendars this source offers.
  List<CalendarInfo> get calendars;

  CalendarCapabilities get capabilities;

  CalendarSyncStatus get status;

  /// Everything this source knows about inside the last requested window.
  List<CalendarEvent> get events;

  /// Read [window]. Implementations must be idempotent — a view may ask for
  /// the same window twice while paging.
  Future<void> load(CalendarWindow window);

  /// Ask the service again, ignoring anything cached.
  Future<void> refresh();

  Future<CalendarEvent?> createEvent(CalendarEventDraft draft) async => null;

  /// Move and/or resize. [start] and [end] are the new bounds.
  Future<bool> rescheduleEvent(
    CalendarEvent event, {
    required ZonedDateTime start,
    ZonedDateTime? end,
  }) async =>
      false;

  Future<bool> updateEvent(
    CalendarEvent event,
    CalendarEventDraft draft,
  ) async =>
      false;

  Future<bool> deleteEvent(CalendarEvent event) async => false;

  /// Show or hide one of this source's calendars.
  void setCalendarVisible(String calendarId, bool visible) {}

  void setCalendarColor(String calendarId, Color color) {}
}
