import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_view_setting.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/application/table_calendar_provider.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_details.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/plugins/database/find/database_find_calendar.dart';
import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/plugins/database/widgets/setting/field_visibility_extension.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    _adoptStoredModeAfterFrame();
    ReminderStore.instance.start();
    unawaited(_attachGoogleCalendars());
  }

  /// Bring in whatever Google accounts are already connected.
  ///
  /// Deliberately after the local sources are up: the calendar has to be
  /// usable the instant it opens, with or without a network.
  Future<void> _attachGoogleCalendars() async {
    final selections = await _workspace.readGoogleSelection();
    if (!mounted) return;
    final providers =
        await buildGoogleCalendarProviders(selections: selections);
    if (!mounted) {
      for (final provider in providers) {
        provider.dispose();
      }
      return;
    }
    for (final provider in providers) {
      _workspace.addProvider(provider);
    }
  }

  @override
  void didUpdateWidget(CalendarStage old) {
    super.didUpdateWidget(old);
    if (old.view.extra != widget.view.extra) {
      _adoptStoredModeAfterFrame();
    }
    if (old.view.name != widget.view.name) {
      _table.rename(widget.view.name);
    }
  }

  void _adoptStoredModeAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CalendarViewSettings.instance.adopt(widget.view);
    });
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

  bool get _canEdit {
    if (!mounted) return false;
    final access = context.read<PageAccessLevelBloc?>()?.state;
    return access == null
        ? !widget.view.isLocked
        : !access.isLoadingLockStatus && access.isEditable;
  }

  bool get _canCreate => _canEdit && _workspace.defaultProvider != null;

  bool _canEditEvent(CalendarEvent event) =>
      _canEdit &&
      !event.readOnly &&
      (_workspace.providerFor(event)?.capabilities.canEdit ?? false);

  String? get _primaryFieldId {
    for (final field in widget.databaseController.fieldController.fieldInfos) {
      if (field.isPrimary) return field.id;
    }
    return null;
  }

  DatabaseFindViewSnapshot _findSnapshot() {
    final rows = widget.databaseController.rowCache.rowInfos
        .map((row) => row.rowId)
        .toSet();
    return DatabaseFindViewSnapshot(
      viewId: widget.view.id,
      rowIds: {
        for (final event in _workspace.events)
          if (event.calendarId == TableCalendarProvider.localCalendarId &&
              rows.contains(event.rowId))
            event.rowId,
      },
      fieldIds: widget.databaseController.fieldController.fieldInfos
          .where((field) => field.visibility?.isVisibleState() ?? false)
          .map((field) => field.id),
      revision: (
        _workspace.filter,
        _table.dateField?.id,
        widget.databaseController
      ),
    );
  }

  Future<String?> _materializeFindTarget(DatabaseFindRequest request) async {
    if (!request.isCurrent || request.target.rowId == null) return null;
    for (final event in _workspace.events) {
      if (event.calendarId != TableCalendarProvider.localCalendarId ||
          event.rowId != request.target.rowId) {
        continue;
      }
      if (!request.isCurrent) return null;
      _shell.currentState?.revealDateForFind(event.startDay);
      return 'Calendar date reached. Only rendered event titles can be highlighted; other properties, overflow events, and year-view density are not text in this layout. The calendar mode and filters are unchanged.';
    }
    return 'The row has no scheduled event allowed by the current calendar filters.';
  }

  @override
  Widget build(BuildContext context) => DatabaseFindLayout(
        viewId: widget.view.id,
        snapshot: _findSnapshot,
        materialize: _materializeFindTarget,
        child: DatabaseFindCalendarScope(
          viewId: widget.view.id,
          calendarId: TableCalendarProvider.localCalendarId,
          primaryFieldId: _primaryFieldId,
          child: _buildCalendar(context),
        ),
      );

  Widget _buildCalendar(BuildContext context) {
    // Rebuild action affordances when access or the page lock changes.
    context.watch<PageAccessLevelBloc?>();
    return ValueListenableBuilder<CalendarViewMode?>(
      valueListenable: CalendarViewSettings.instance.listenable(widget.view),
      builder: (context, savedMode, _) => CalendarShell(
        key: _shell,
        workspace: _workspace,
        hasDateField: _hasDateField,
        firstDayOfWeek: _firstWeekday,
        showWeekends: widget.showWeekends,
        showWeekNumbers: widget.showWeekNumbers,
        onConnectCalendar: widget.onConnectCalendar,
        toolbarTrailing: widget.toolbarTrailing,
        compact: widget.compact,
        initialMode: savedMode ??
            (widget.compact ? CalendarViewMode.agenda : CalendarViewMode.month),
        mode: _canEdit
            ? savedMode ??
                (widget.compact
                    ? CalendarViewMode.agenda
                    : CalendarViewMode.month)
            : null,
        onModeChanged: (mode) {
          if (_canEdit) {
            unawaited(CalendarViewSettings.instance.set(widget.view, mode));
          }
        },
        delegate: CalendarViewDelegate(
          colorOf: _workspace.colorFor,
          canEdit: _canEdit,
          canEditEvent: _canEditEvent,
          onOpenEvent: _open,
          onEventMenu: _menu,
          onCreateAt: _canCreate ? _create : null,
          onReschedule: _canEdit ? _reschedule : null,
          onToggleComplete: _canEdit ? _toggleComplete : null,
          onShowMore: _showDay,
        ),
      ),
    );
  }

  void _open(CalendarEvent event) {
    if (event.rowId.isNotEmpty) {
      widget.onOpenRow(event.rowId);
      return;
    }
    if (event.url.isNotEmpty) {
      unawaited(launchUrl(Uri.parse(event.url)));
      return;
    }
    unawaited(showCalendarEventDetails(context, event: event));
  }

  void _showDay(DateTime day, Offset position) =>
      _shell.currentState?.showDay(day);

  Future<void> _create(DateTime at, {bool hasTime = false}) async {
    if (!_canCreate) return;
    final created = await _workspace.create(
      CalendarEventDraft(
        title: '',
        start: hasTime ? ZonedDateTime.local(at) : ZonedDateTime.allDay(at),
        end: hasTime
            ? ZonedDateTime.local(at.add(const Duration(hours: 1)))
            : null,
      ),
    );
    if (mounted && _canEdit && created != null && created.rowId.isNotEmpty) {
      widget.onOpenRow(created.rowId);
    }
  }

  Future<void> _reschedule(
    CalendarEvent event,
    DateTime start,
    DateTime? end,
  ) async {
    if (!_canEditEvent(event) ||
        !(_workspace.providerFor(event)?.capabilities.canMove ?? false)) {
      return;
    }
    await _workspace.reschedule(event, start: start, end: end);
  }

  Future<void> _toggleComplete(CalendarEvent event) async {
    if (_canEditEvent(event) && event.kind == CalendarEventKind.reminder) {
      await _reminders.toggleComplete(event);
    }
  }

  Future<void> _menu(CalendarEvent event, Offset position) async {
    final provider = _workspace.providerFor(event);
    final canWrite = _canEditEvent(event);
    final canDelete = _canEdit &&
        !event.readOnly &&
        (provider?.capabilities.canDelete ?? false);

    await showAppMenu<void>(
      context: context,
      anchor: position & Size.zero,
      entries: [
        AppMenuItem(
          label: event.rowId.isNotEmpty
              ? LocaleKeys.calendarView_openRow.tr()
              : LocaleKeys.reminders_open.tr(),
          icon: Icons.open_in_new_rounded,
          onSelected: () => _open(event),
        ),
        if (event.url.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.calendarView_openInGoogle.tr(),
            icon: Icons.launch_rounded,
            onSelected: () => unawaited(launchUrl(Uri.parse(event.url))),
          ),
        if (canWrite && event.kind == CalendarEventKind.reminder)
          AppMenuItem(
            label: event.isCompleted
                ? LocaleKeys.reminders_markNotDone.tr()
                : LocaleKeys.reminders_markDone.tr(),
            icon: Icons.check_circle_rounded,
            onSelected: () => unawaited(_toggleComplete(event)),
          ),
        if (canWrite && event.rowId.isNotEmpty && widget.onDuplicateRow != null)
          AppMenuItem(
            label: LocaleKeys.calendarView_duplicateEvent.tr(),
            icon: Icons.copy_rounded,
            onSelected: () {
              if (_canEditEvent(event)) widget.onDuplicateRow!(event.rowId);
            },
          ),
        if (canWrite && event.rowId.isNotEmpty && !event.hasReminder)
          AppMenuItem(
            label: LocaleKeys.calendarView_addReminder.tr(),
            icon: Icons.notifications_rounded,
            onSelected: () => unawaited(_addReminderFor(event)),
          ),
        if (canDelete) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.calendarView_deleteEvent.tr(),
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: () {
              if (!_canEdit ||
                  event.readOnly ||
                  !(_workspace.providerFor(event)?.capabilities.canDelete ??
                      false)) {
                return;
              }
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
    if (!_canEditEvent(event) || field == null || event.rowId.isEmpty) {
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
    if (!mounted || !_canEditEvent(event) || reminder == null) {
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
