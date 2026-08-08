import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/application/table_calendar_provider.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The calendar as a reading of one table.
///
/// This is the only place that knows a calendar event might be a row: it wires
/// the sources up, turns an interaction into a write, and hands the renderer a
/// [CalendarViewDelegate] that says nothing about where anything came from.
class CalendarStage extends StatefulWidget {
  const CalendarStage({
    super.key,
    required this.view,
    required this.databaseController,
    required this.firstDayOfWeek,
    required this.showWeekends,
    required this.showWeekNumbers,
    required this.onOpenRow,
    this.onDuplicateRow,
    this.onDeleteRow,
    this.onConnectCalendar,
    this.toolbarTrailing,
    this.compact = false,
  });

  final ViewPB view;
  final DatabaseController databaseController;

  /// 0 is Sunday, matching `CalendarLayoutSettingPB.firstDayOfWeek`.
  final int firstDayOfWeek;
  final bool showWeekends;
  final bool showWeekNumbers;

  final void Function(String rowId) onOpenRow;
  final void Function(String rowId)? onDuplicateRow;
  final void Function(String rowId)? onDeleteRow;
  final VoidCallback? onConnectCalendar;
  final Widget? toolbarTrailing;

  /// A phone: the same readings, laid out for a narrow window.
  final bool compact;

  @override
  State<CalendarStage> createState() => _CalendarStageState();
}

class _CalendarStageState extends State<CalendarStage> {
  final GlobalKey<CalendarShellState> _shell = GlobalKey<CalendarShellState>();
  late final TableCalendarProvider _table;
  late final ReminderCalendarProvider _reminders;
  late final CalendarWorkspace _workspace;

  @override
  void initState() {
    super.initState();
    _table = TableCalendarProvider(
      databaseController: widget.databaseController,
      calendarName: widget.view.name.isEmpty
          ? LocaleKeys.calendar_menuName.tr()
          : widget.view.name,
    );
    _reminders = ReminderCalendarProvider(
      calendarName: LocaleKeys.reminders_title.tr(),
    );
    _workspace = CalendarWorkspace(providers: [_table, _reminders]);
    ReminderStore.instance.start();
    unawaited(_attachGoogleCalendars());
  }

  /// Bring in whatever Google accounts are already connected.
  ///
  /// Deliberately after the local sources are up: the calendar has to be
  /// usable the instant it opens, with or without a network.
  Future<void> _attachGoogleCalendars() async {
    final selections = await _workspace.readGoogleSelection();
    final providers =
        await buildGoogleCalendarProviders(selections: selections);
    if (!mounted) {
      return;
    }
    for (final provider in providers) {
      _workspace.addProvider(provider);
    }
  }

  @override
  void didUpdateWidget(CalendarStage old) {
    super.didUpdateWidget(old);
    if (old.view.name != widget.view.name) {
      _table.rename(widget.view.name);
    }
  }

  @override
  void dispose() {
    _workspace.dispose();
    super.dispose();
  }

  bool get _hasDateField => _table.dateField != null;

  /// `CalendarLayoutSettingPB` counts from Sunday; `DateTime` from Monday.
  int get _firstWeekday =>
      widget.firstDayOfWeek == 0 ? DateTime.sunday : widget.firstDayOfWeek;

  @override
  Widget build(BuildContext context) => CalendarShell(
        key: _shell,
        workspace: _workspace,
        hasDateField: _hasDateField,
        firstDayOfWeek: _firstWeekday,
        showWeekends: widget.showWeekends,
        showWeekNumbers: widget.showWeekNumbers,
        onConnectCalendar: widget.onConnectCalendar,
        toolbarTrailing: widget.toolbarTrailing,
        compact: widget.compact,
        initialMode:
            widget.compact ? CalendarViewMode.agenda : CalendarViewMode.month,
        delegate: CalendarViewDelegate(
          colorOf: _workspace.colorFor,
          onOpenEvent: _open,
          onEventMenu: _menu,
          onCreateAt: _create,
          onReschedule: _reschedule,
          onToggleComplete: _toggleComplete,
          onShowMore: _showDay,
        ),
      );

  void _open(CalendarEvent event) {
    if (event.rowId.isNotEmpty) {
      widget.onOpenRow(event.rowId);
      return;
    }
    if (event.url.isNotEmpty) {
      unawaited(launchUrl(Uri.parse(event.url)));
    }
  }

  void _showDay(DateTime day) => _shell.currentState?.showDay(day);

  Future<void> _create(DateTime at, {bool hasTime = false}) async {
    await _workspace.create(
      CalendarEventDraft(
        title: '',
        start: hasTime ? ZonedDateTime.local(at) : ZonedDateTime.allDay(at),
        end: hasTime
            ? ZonedDateTime.local(at.add(const Duration(hours: 1)))
            : null,
      ),
    );
  }

  Future<void> _reschedule(
    CalendarEvent event,
    DateTime start,
    DateTime? end,
  ) async {
    await _workspace.reschedule(event, start: start, end: end);
  }

  Future<void> _toggleComplete(CalendarEvent event) async {
    if (event.kind == CalendarEventKind.reminder) {
      await _reminders.toggleComplete(event);
    }
  }

  Future<void> _menu(CalendarEvent event, Offset position) async {
    final provider = _workspace.providerFor(event);
    final canWrite =
        provider != null && provider.capabilities.canWrite && !event.readOnly;

    await showAppMenu<void>(
      context: context,
      anchor: position & Size.zero,
      entries: [
        AppMenuItem(
          label: event.rowId.isNotEmpty
              ? LocaleKeys.calendarView_openRow.tr()
              : LocaleKeys.calendarView_editEvent.tr(),
          icon: Icons.open_in_new_rounded,
          onSelected: () => _open(event),
        ),
        if (event.url.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.calendarView_openInGoogle.tr(),
            icon: Icons.launch_rounded,
            onSelected: () => unawaited(launchUrl(Uri.parse(event.url))),
          ),
        if (event.kind == CalendarEventKind.reminder)
          AppMenuItem(
            label: event.isCompleted
                ? LocaleKeys.reminders_markNotDone.tr()
                : LocaleKeys.reminders_markDone.tr(),
            icon: Icons.check_circle_rounded,
            onSelected: () => unawaited(_toggleComplete(event)),
          ),
        if (event.rowId.isNotEmpty && widget.onDuplicateRow != null)
          AppMenuItem(
            label: LocaleKeys.calendarView_duplicateEvent.tr(),
            icon: Icons.copy_rounded,
            onSelected: () => widget.onDuplicateRow!(event.rowId),
          ),
        if (event.rowId.isNotEmpty && !event.hasReminder)
          AppMenuItem(
            label: LocaleKeys.calendarView_addReminder.tr(),
            icon: Icons.notifications_rounded,
            onSelected: () => unawaited(_addReminderFor(event)),
          ),
        if (canWrite) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.calendarView_deleteEvent.tr(),
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: () {
              if (event.rowId.isNotEmpty && widget.onDeleteRow != null) {
                widget.onDeleteRow!(event.rowId);
              } else {
                unawaited(_workspace.delete(event));
              }
            },
          ),
        ],
      ],
    );
  }

  /// Put a reminder on the row's own date cell, which is where the rest of the
  /// application already looks for one.
  Future<void> _addReminderFor(CalendarEvent event) async {
    final field = _table.dateField;
    if (field == null || event.rowId.isEmpty) {
      return;
    }
    final reminder = await ReminderStore.instance.create(
      buildReminder(
        title: event.title,
        when: event.start.local,
        includeTime: !event.isAllDay,
        kind: ReminderKind.row,
        objectId: widget.view.id,
      ),
    );
    if (reminder == null) {
      return;
    }
    await DateCellBackendService(
      viewId: _table.viewId,
      fieldId: field.id,
      rowId: event.rowId,
    ).update(reminderId: reminder.id);
    await _table.refresh();
  }
}
