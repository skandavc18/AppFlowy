import 'dart:convert';

import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

/// The extra facts a first-class reminder carries.
///
/// Every one of these rides in [ReminderPB.meta], which is already a
/// `map<string, string>` — so reminders gain repeat, priority, completion,
/// snooze and sound with **no protobuf or Rust change at all**.
abstract final class ReminderKeys {
  /// What the reminder is attached to.
  static const kind = 'af_kind';

  /// A [CalendarRecurrence], JSON encoded.
  static const repeat = 'af_repeat';

  static const priority = 'af_priority';

  static const isDone = 'af_done';
  static const completedAt = 'af_completed_at';

  /// Milliseconds since the epoch; the reminder is silent until then.
  static const snoozedUntil = 'af_snoozed_until';

  /// Whether the operating system has already been told about this one, so a
  /// restart does not repeat every notification of the day.
  static const notifiedAt = 'af_notified_at';

  static const playsSound = 'af_sound';

  /// The calendar it should be drawn on.
  static const calendarId = 'af_calendar';

  /// The view a standalone reminder should open.
  static const pageId = 'af_page';
}

/// What a reminder hangs off.
enum ReminderKind {
  /// Nothing but itself.
  standalone,

  /// A block inside a page.
  block,

  /// A row in a table.
  row,

  /// A whole page.
  page,

  /// An event on a calendar.
  event;

  static ReminderKind fromValue(Object? value) =>
      ReminderKind.values.firstWhere(
        (k) => k.name == value,
        orElse: () => ReminderKind.standalone,
      );
}

/// How loudly a reminder asks.
///
/// Deliberately restrained: colour is a hint, never a warning banner.
enum ReminderPriority {
  none,
  low,
  medium,
  high;

  static ReminderPriority fromValue(Object? value) =>
      ReminderPriority.values.firstWhere(
        (p) => p.name == value,
        orElse: () => ReminderPriority.none,
      );

  Color? tint(Color accent) => switch (this) {
        ReminderPriority.none => null,
        ReminderPriority.low => const Color(0xFF64748B),
        ReminderPriority.medium => const Color(0xFFD97706),
        ReminderPriority.high => const Color(0xFFDC2626),
      };
}

/// How long "snooze" means.
enum SnoozeOption {
  fiveMinutes(Duration(minutes: 5)),
  tenMinutes(Duration(minutes: 10)),
  thirtyMinutes(Duration(minutes: 30)),
  oneHour(Duration(hours: 1)),
  tomorrow(Duration.zero),
  custom(Duration.zero);

  const SnoozeOption(this.delay);

  final Duration delay;

  /// When a reminder snoozed now would next speak.
  DateTime resolve(DateTime now, {Duration? custom}) => switch (this) {
        SnoozeOption.tomorrow => DateTime(now.year, now.month, now.day + 1, 9),
        SnoozeOption.custom => now.add(custom ?? const Duration(minutes: 15)),
        _ => now.add(delay),
      };
}

/// A reminder, read out of the fields the backend already stores.
///
/// This is a *view* over [ReminderPB] rather than a second store: creating one
/// never has to be kept in step with the other.
@immutable
class AppReminder {
  const AppReminder({
    required this.id,
    required this.title,
    required this.message,
    required this.scheduledAt,
    this.objectId = '',
    this.kind = ReminderKind.standalone,
    this.priority = ReminderPriority.none,
    this.recurrence = CalendarRecurrence.none,
    this.includeTime = true,
    this.isDone = false,
    this.isRead = false,
    this.isArchived = false,
    this.snoozedUntil,
    this.notifiedAt,
    this.playsSound = true,
    this.calendarId = '',
    this.blockId = '',
    this.rowId = '',
    this.pageId = '',
  });

  factory AppReminder.fromPB(ReminderPB pb) {
    final meta = pb.meta;
    return AppReminder(
      id: pb.id,
      title: pb.title,
      message: pb.message,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(
        pb.scheduledAt.toInt() * 1000,
      ),
      objectId: pb.objectId,
      kind: ReminderKind.fromValue(meta[ReminderKeys.kind]),
      priority: ReminderPriority.fromValue(meta[ReminderKeys.priority]),
      recurrence: _decodeRecurrence(meta[ReminderKeys.repeat]),
      includeTime: pb.includeTime ?? true,
      isDone: meta[ReminderKeys.isDone] == 'true',
      isRead: pb.isRead,
      isArchived: pb.isArchived,
      snoozedUntil: _millis(meta[ReminderKeys.snoozedUntil]),
      notifiedAt: _millis(meta[ReminderKeys.notifiedAt]),
      playsSound: meta[ReminderKeys.playsSound] != 'false',
      calendarId: meta[ReminderKeys.calendarId] ?? '',
      blockId: pb.blockId ?? '',
      rowId: pb.rowId ?? '',
      pageId: meta[ReminderKeys.pageId] ?? '',
    );
  }

  final String id;
  final String title;
  final String message;

  /// When it should speak. Always an instant, never a wall clock.
  final DateTime scheduledAt;

  final String objectId;
  final ReminderKind kind;
  final ReminderPriority priority;
  final CalendarRecurrence recurrence;

  /// False for "some time on the 15th", which must not fire at midnight.
  final bool includeTime;

  final bool isDone;
  final bool isRead;
  final bool isArchived;

  final DateTime? snoozedUntil;
  final DateTime? notifiedAt;
  final bool playsSound;

  final String calendarId;
  final String blockId;
  final String rowId;
  final String pageId;

  /// The moment this reminder actually speaks, snooze included.
  DateTime get firesAt {
    final snoozed = snoozedUntil;
    if (snoozed != null && snoozed.isAfter(scheduledAt)) {
      return snoozed;
    }
    return scheduledAt;
  }

  bool get isSnoozed =>
      snoozedUntil != null && snoozedUntil!.isAfter(DateTime.now());

  /// Whether the operating system still owes somebody this notification.
  bool get isDue =>
      !isDone &&
      !isArchived &&
      !firesAt.isAfter(DateTime.now()) &&
      (notifiedAt == null || notifiedAt!.isBefore(firesAt));

  /// The reminder as something the calendar can draw.
  CalendarEvent toCalendarEvent({String? calendarOverride}) => CalendarEvent(
        id: 'reminder:$id',
        calendarId: calendarOverride ?? calendarId,
        title: title.isEmpty ? message : title,
        start: includeTime
            ? ZonedDateTime.local(firesAt)
            : ZonedDateTime.allDay(firesAt),
        kind: CalendarEventKind.reminder,
        origin: CalendarEventOrigin.reminder,
        description: message,
        isCompleted: isDone,
        hasReminder: true,
        reminderId: id,
        recurrence: recurrence,
        rowId: rowId,
      );

  /// The meta map to write back, merged over whatever is already stored.
  Map<String, String> toMeta({Map<String, String>? existing}) => {
        ...?existing,
        ReminderKeys.kind: kind.name,
        ReminderKeys.priority: priority.name,
        if (recurrence.repeats)
          ReminderKeys.repeat: jsonEncode(recurrence.toJson()),
        ReminderMetaKeys.includeTime: includeTime.toString(),
        ReminderKeys.isDone: isDone.toString(),
        ReminderKeys.playsSound: playsSound.toString(),
        if (snoozedUntil != null)
          ReminderKeys.snoozedUntil:
              snoozedUntil!.millisecondsSinceEpoch.toString(),
        if (notifiedAt != null)
          ReminderKeys.notifiedAt:
              notifiedAt!.millisecondsSinceEpoch.toString(),
        if (calendarId.isNotEmpty) ReminderKeys.calendarId: calendarId,
        if (pageId.isNotEmpty) ReminderKeys.pageId: pageId,
        if (blockId.isNotEmpty) ReminderMetaKeys.blockId: blockId,
        if (rowId.isNotEmpty) ReminderMetaKeys.rowId: rowId,
        ReminderMetaKeys.date: scheduledAt.millisecondsSinceEpoch.toString(),
        ReminderMetaKeys.isArchived: isArchived.toString(),
      };

  ReminderPB toPB() => ReminderPB(
        id: id,
        objectId: objectId,
        title: title,
        message: message,
        meta: toMeta(),
        scheduledAt: Int64(scheduledAt.millisecondsSinceEpoch ~/ 1000),
        isAck: scheduledAt.isBefore(DateTime.now()),
        isRead: isRead,
      );

  AppReminder copyWith({
    String? title,
    String? message,
    DateTime? scheduledAt,
    ReminderKind? kind,
    ReminderPriority? priority,
    CalendarRecurrence? recurrence,
    bool? includeTime,
    bool? isDone,
    bool? isRead,
    bool? isArchived,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
    DateTime? notifiedAt,
    bool? playsSound,
    String? calendarId,
    String? pageId,
  }) =>
      AppReminder(
        id: id,
        title: title ?? this.title,
        message: message ?? this.message,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        objectId: objectId,
        kind: kind ?? this.kind,
        priority: priority ?? this.priority,
        recurrence: recurrence ?? this.recurrence,
        includeTime: includeTime ?? this.includeTime,
        isDone: isDone ?? this.isDone,
        isRead: isRead ?? this.isRead,
        isArchived: isArchived ?? this.isArchived,
        snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
        notifiedAt: notifiedAt ?? this.notifiedAt,
        playsSound: playsSound ?? this.playsSound,
        calendarId: calendarId ?? this.calendarId,
        blockId: blockId,
        rowId: rowId,
        pageId: pageId ?? this.pageId,
      );

  /// Mark done. A repeating reminder does not finish — it moves on.
  AppReminder complete({DateTime? now}) {
    final at = now ?? DateTime.now();
    if (recurrence.repeats) {
      final next = recurrence.nextAfter(scheduledAt, at);
      if (next != null) {
        return copyWith(
          scheduledAt: next,
          isDone: false,
          isRead: false,
          clearSnooze: true,
          notifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
      }
    }
    return copyWith(isDone: true, isRead: true, clearSnooze: true);
  }

  AppReminder snooze(SnoozeOption option, {Duration? custom, DateTime? now}) =>
      copyWith(
        snoozedUntil: option.resolve(now ?? DateTime.now(), custom: custom),
        isRead: true,
      );

  static CalendarRecurrence _decodeRecurrence(String? raw) {
    if (raw == null || raw.isEmpty) {
      return CalendarRecurrence.none;
    }
    try {
      return CalendarRecurrence.fromJson(jsonDecode(raw));
    } catch (_) {
      return CalendarRecurrence.none;
    }
  }

  static DateTime? _millis(String? raw) {
    final value = raw == null ? null : int.tryParse(raw);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  @override
  bool operator ==(Object other) =>
      other is AppReminder &&
      other.id == id &&
      other.title == title &&
      other.message == message &&
      other.scheduledAt == scheduledAt &&
      other.isDone == isDone &&
      other.isArchived == isArchived &&
      other.snoozedUntil == snoozedUntil &&
      other.recurrence == recurrence &&
      other.priority == priority;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        message,
        scheduledAt,
        isDone,
        isArchived,
        snoozedUntil,
        recurrence,
        priority,
      );
}
