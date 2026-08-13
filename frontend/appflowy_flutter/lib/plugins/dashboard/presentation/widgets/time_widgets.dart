import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Time: what it is now, what is coming, and how long is left.
void registerDashboardTimeWidgets() {
  DashboardWidgetRegistry.register(_clock);
  DashboardWidgetRegistry.register(_calendar);
  DashboardWidgetRegistry.register(_countdown);
  DashboardWidgetRegistry.register(_reminders);
}

const _keyFormat = 'format';
const _keySeconds = 'seconds';
const _keyShowDate = 'show_date';
const _keyTarget = 'target';
const _keyLabel = 'label';
const _keyNote = 'note';
const _keyLimit = 'limit';
const _keyMode = 'mode';
const _keyWeekends = 'weekends';
const _keyWeekNumbers = 'week_numbers';
const _keyFirstDay = 'first_day';

// ---------------------------------------------------------------------- clock

final _clock = DashboardWidgetDefinition(
  type: 'clock',
  label: () => LocaleKeys.dashboard_widget_clock.tr(),
  description: () => LocaleKeys.dashboard_widget_clockHint.tr(),
  icon: Icons.schedule_rounded,
  group: DashboardWidgetGroup.time,
  defaultColumnSpan: 3,
  defaultRowSpan: 3,
  showsTitleByDefault: false,
  slashName: 'clock',
  keywords: const ['clock', 'time', 'now', 'hour', 'today'],
  builder: (context) => _ClockBody(context: context),
  configure: (context) => [
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_clockFormat.tr(),
      value: context.spec.setting(_keyFormat, fallback: '24'),
      choices: [
        DashboardChoice(
          value: '24',
          label: LocaleKeys.dashboard_clock_twentyFour.tr(),
        ),
        DashboardChoice(
          value: '12',
          label: LocaleKeys.dashboard_clock_twelve.tr(),
        ),
      ],
      onChanged: (value) => context.setSettings({_keyFormat: value}),
    ),
    DashboardConfigToggle(
      label: LocaleKeys.dashboard_config_showSeconds.tr(),
      value: context.spec.flag(_keySeconds),
      onChanged: (value) => context.setSettings({_keySeconds: value}),
    ),
    DashboardConfigToggle(
      label: LocaleKeys.dashboard_config_showDate.tr(),
      value: context.spec.flag(_keyShowDate, fallback: true),
      onChanged: (value) => context.setSettings({_keyShowDate: value}),
    ),
  ],
);

class _ClockBody extends StatefulWidget {
  const _ClockBody({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_ClockBody> createState() => _ClockBodyState();
}

class _ClockBodyState extends State<_ClockBody> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // One second only when the seconds are shown; otherwise a minute is
    // plenty and a dashboard left open all day costs nothing.
    _restart();
  }

  @override
  void didUpdateWidget(_ClockBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _restart();
  }

  void _restart() {
    final seconds = widget.context.spec.flag(_keySeconds);
    _tick?.cancel();
    _tick = Timer.periodic(
      seconds ? const Duration(seconds: 1) : const Duration(seconds: 20),
      (_) {
        if (mounted) {
          setState(() => _now = DateTime.now());
        }
      },
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.context.spec;
    final palette = widget.context.palette;
    final twelve = spec.setting(_keyFormat, fallback: '24') == '12';
    final showSeconds = spec.flag(_keySeconds);

    final hour =
        twelve ? (_now.hour % 12 == 0 ? 12 : _now.hour % 12) : _now.hour;
    final buffer = StringBuffer()
      ..write(twelve ? '$hour' : hour.toString().padLeft(2, '0'))
      ..write(':')
      ..write(_now.minute.toString().padLeft(2, '0'));
    if (showSeconds) {
      buffer
        ..write(':')
        ..write(_now.second.toString().padLeft(2, '0'));
    }

    return Center(
      child: DashboardFigure(
        value: buffer.toString(),
        suffix: twelve ? (_now.hour < 12 ? 'AM' : 'PM') : '',
        palette: palette,
        alignment: CrossAxisAlignment.center,
        size: 36,
        color: widget.context.strong,
        caption: spec.flag(_keyShowDate, fallback: true)
            ? DateFormat.yMMMMEEEEd().format(_now)
            : '',
      ),
    );
  }
}

// ------------------------------------------------------------------- calendar

final _calendar = DashboardWidgetDefinition(
  type: 'calendar',
  label: () => LocaleKeys.dashboard_widget_calendar.tr(),
  description: () => LocaleKeys.dashboard_widget_calendarHint.tr(),
  icon: Icons.calendar_month_rounded,
  group: DashboardWidgetGroup.time,
  defaultColumnSpan: 8,
  defaultRowSpan: 12,
  minimumColumnSpan: 4,
  minimumRowSpan: 7,
  showsTitleByDefault: false,
  padding: EdgeInsets.zero,
  slashName: 'calendar',
  keywords: const [
    'calendar',
    'month',
    'week',
    'day',
    'year',
    'agenda',
    'dates',
    'schedule',
    'reminders',
    'google calendar',
  ],
  builder: (context) => _DashboardCalendar(
    key: ValueKey('dashboard-calendar-${context.spec.id}'),
    context: context,
  ),
  configure: (context) => [
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_calendarView.tr(),
      value: context.spec.setting(_keyMode, fallback: 'month'),
      choices: [
        for (final mode in CalendarViewMode.values)
          DashboardChoice(
            value: mode.name,
            label: dashboardCalendarModeLabel(mode),
          ),
      ],
      onChanged: (value) => context.setSettings({_keyMode: value}),
    ),
    DashboardConfigToggle(
      label: LocaleKeys.dashboard_config_weekends.tr(),
      value: context.spec.flag(_keyWeekends, fallback: true),
      onChanged: (value) => context.setSettings({_keyWeekends: value}),
    ),
    DashboardConfigToggle(
      label: LocaleKeys.dashboard_config_weekNumbers.tr(),
      value: context.spec.flag(_keyWeekNumbers),
      onChanged: (value) => context.setSettings({_keyWeekNumbers: value}),
    ),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_weekStarts.tr(),
      value: '${context.spec.integer(_keyFirstDay, fallback: DateTime.monday)}',
      choices: [
        DashboardChoice(
          value: '${DateTime.monday}',
          label: DateFormat.EEEE().format(DateTime(2024)),
        ),
        DashboardChoice(
          value: '${DateTime.sunday}',
          label: DateFormat.EEEE().format(DateTime(2024, 1, 7)),
        ),
      ],
      onChanged: (value) => context.setSettings({
        _keyFirstDay: int.tryParse(value) ?? DateTime.monday,
      }),
    ),
  ],
);

/// The words for one way of looking at a calendar.
String dashboardCalendarModeLabel(CalendarViewMode mode) => switch (mode) {
      CalendarViewMode.month => LocaleKeys.dashboard_calendar_month.tr(),
      CalendarViewMode.week => LocaleKeys.dashboard_calendar_week.tr(),
      CalendarViewMode.day => LocaleKeys.dashboard_calendar_day.tr(),
      CalendarViewMode.agenda => LocaleKeys.dashboard_calendar_agenda.tr(),
      CalendarViewMode.year => LocaleKeys.dashboard_calendar_year.tr(),
    };

/// The whole calendar, on a dashboard.
///
/// It reads the same sources the calendar page does — this workspace's
/// reminders and any connected Google account — so an event added here is the
/// same event everywhere else, and one added elsewhere shows up here.
class _DashboardCalendar extends StatefulWidget {
  const _DashboardCalendar({super.key, required this.context});

  final DashboardWidgetContext context;

  @override
  State<_DashboardCalendar> createState() => _DashboardCalendarState();
}

class _DashboardCalendarState extends State<_DashboardCalendar> {
  final GlobalKey<CalendarShellState> _shell = GlobalKey<CalendarShellState>();
  late final ReminderCalendarProvider _reminders;
  late final CalendarWorkspace _workspace;

  DashboardWidgetContext get data => widget.context;

  @override
  void initState() {
    super.initState();
    _reminders = ReminderCalendarProvider(
      calendarName: LocaleKeys.reminders_title.tr(),
    );
    _workspace = CalendarWorkspace(providers: [_reminders]);
    ReminderStore.instance.start();
    unawaited(_attachGoogleCalendars());
  }

  /// Local sources first, so the calendar draws with or without a network.
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
  void dispose() {
    _workspace.dispose();
    super.dispose();
  }

  CalendarViewMode get _mode {
    final stored = data.spec.setting(_keyMode, fallback: 'month');
    for (final mode in CalendarViewMode.values) {
      if (mode.name == stored) {
        return mode;
      }
    }
    return CalendarViewMode.month;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // One tidy row of chrome when there is room for it; the stacked
        // arrangement only when the card really is narrow.
        builder: (context, constraints) => CalendarShell(
          key: _shell,
          workspace: _workspace,
          initialMode: _mode,
          onModeChanged: (mode) => data.setSettings({_keyMode: mode.name}),
          firstDayOfWeek:
              data.spec.integer(_keyFirstDay, fallback: DateTime.monday),
          showWeekends: data.spec.flag(_keyWeekends, fallback: true),
          showWeekNumbers: data.spec.flag(_keyWeekNumbers),
          compact: constraints.maxWidth < 460,
          quiet: true,
          delegate: CalendarViewDelegate(
            colorOf: _workspace.colorFor,
            canEdit: data.isTypable,
            onOpenEvent: _open,
            onCreateAt: _create,
            onReschedule: _reschedule,
            onToggleComplete: _toggleComplete,
            onShowMore: _showDay,
            onDayMenu: _dayMenu,
            onEventMenu: _eventMenu,
          ),
        ),
      );

  void _open(CalendarEvent event) {
    if (event.url.isNotEmpty) {
      unawaited(launchUrl(Uri.parse(event.url)));
    }
  }

  /// Everything on one day, where it was asked for.
  Future<void> _showDay(DateTime day, Offset position) async {
    final start = DateTime(day.year, day.month, day.day);
    final events = _workspace.eventsBetween(
      start,
      start.add(const Duration(days: 1)),
    );
    await showAppMenu<void>(
      context: context,
      anchor: position & Size.zero,
      entries: [
        AppMenuHeader(DateFormat.yMMMMd().format(day)),
        for (final event in events)
          AppMenuItem(
            label: event.title.isEmpty
                ? LocaleKeys.dashboard_reminders_untitled.tr()
                : event.title,
            iconWidget: CalendarColorDot(color: _workspace.colorFor(event)),
            subtitle: event.isAllDay
                ? LocaleKeys.calendarView_allDay.tr()
                : DateFormat.jm().format(event.start.local),
            onSelected: () => _open(event),
          ),
        if (events.isEmpty)
          AppMenuItem(
            label: LocaleKeys.dashboard_reminders_empty.tr(),
            enabled: false,
          ),
        const AppMenuSeparator(),
        if (data.isTypable)
          AppMenuItem(
            label: LocaleKeys.calendarView_newEvent.tr(),
            icon: Icons.add_rounded,
            onSelected: () => unawaited(_create(day)),
          ),
        AppMenuItem(
          label: LocaleKeys.calendarView_openDay.tr(),
          icon: Icons.view_day_rounded,
          onSelected: () => _shell.currentState?.showDay(day),
        ),
      ],
    );
  }

  /// What an event offers when it is asked.
  Future<void> _eventMenu(CalendarEvent event, Offset position) async {
    final provider = _workspace.providerFor(event);
    final canWrite =
        provider != null && provider.capabilities.canWrite && !event.readOnly;
    await showAppMenu<void>(
      context: context,
      anchor: position & Size.zero,
      entries: [
        if (event.url.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.calendarView_openInGoogle.tr(),
            icon: Icons.launch_rounded,
            onSelected: () => _open(event),
          ),
        if (event.kind == CalendarEventKind.reminder)
          AppMenuItem(
            label: event.isCompleted
                ? LocaleKeys.reminders_markNotDone.tr()
                : LocaleKeys.reminders_markDone.tr(),
            icon: Icons.check_circle_rounded,
            onSelected: () => unawaited(_toggleComplete(event)),
          ),
        AppMenuItem(
          label: LocaleKeys.calendarView_goToDate.tr(),
          icon: Icons.event_rounded,
          onSelected: () => _shell.currentState?.showDay(event.start.local),
        ),
        if (canWrite) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.calendarView_deleteEvent.tr(),
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: () => unawaited(_workspace.delete(event)),
          ),
        ],
      ],
    );
  }

  /// What a day offers when it is asked.
  Future<void> _dayMenu(DateTime day, Offset position) async {
    await showAppMenu<void>(
      context: context,
      anchor: position & Size.zero,
      entries: [
        if (data.isTypable)
          AppMenuItem(
            label: LocaleKeys.calendarView_newEvent.tr(),
            icon: Icons.add_rounded,
            onSelected: () => unawaited(_create(day)),
          ),
        if (data.isTypable)
          AppMenuItem(
            label: LocaleKeys.calendarView_addReminder.tr(),
            icon: Icons.notifications_rounded,
            onSelected: () => unawaited(_create(day, hasTime: true)),
          ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.calendarView_openDay.tr(),
          icon: Icons.view_day_rounded,
          onSelected: () => _shell.currentState?.showDay(day),
        ),
        AppMenuItem(
          label: LocaleKeys.calendarView_copyDate.tr(),
          icon: Icons.copy_rounded,
          onSelected: () => unawaited(
            Clipboard.setData(
              ClipboardData(text: DateFormat.yMMMMd().format(day)),
            ),
          ),
        ),
      ],
    );
  }

  /// A day was clicked. Ask what the reminder is rather than dropping an
  /// untitled event on the calendar and hoping it gets named.
  Future<void> _create(DateTime at, {bool hasTime = false}) async {
    if (!data.isTypable) {
      return;
    }
    await showReminderComposer(
      context,
      initialWhen: at,
      initialHasTime: hasTime,
    );
    await _reminders.refresh();
  }

  Future<void> _reschedule(
    CalendarEvent event,
    DateTime start,
    DateTime? end,
  ) =>
      _workspace.reschedule(event, start: start, end: end);

  Future<void> _toggleComplete(CalendarEvent event) async {
    if (event.kind == CalendarEventKind.reminder) {
      await _reminders.toggleComplete(event);
    }
  }
}

// ------------------------------------------------------------------ countdown

final _countdown = DashboardWidgetDefinition(
  type: 'countdown',
  label: () => LocaleKeys.dashboard_widget_countdown.tr(),
  description: () => LocaleKeys.dashboard_widget_countdownHint.tr(),
  icon: Icons.hourglass_bottom_rounded,
  group: DashboardWidgetGroup.time,
  defaultColumnSpan: 3,
  defaultRowSpan: 3,
  defaultAccent: DashboardAccent.orange,
  slashName: 'countdown',
  keywords: const ['countdown', 'deadline', 'timer', 'days left', 'until'],
  builder: (context) => _CountdownBody(context: context),
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_label.tr(),
      value: context.spec.setting(_keyLabel),
      onChanged: (value) => context.setSettings({_keyLabel: value}),
    ),
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_targetDate.tr(),
      hint: LocaleKeys.dashboard_config_targetDateHint.tr(),
      value: context.spec.setting(_keyTarget),
      placeholder: '2026-12-31',
      onChanged: (value) => context.setSettings({_keyTarget: value}),
    ),
    DashboardConfigText(
      label: LocaleKeys.dashboard_countdown_note.tr(),
      hint: LocaleKeys.dashboard_countdown_noteHint.tr(),
      value: context.spec.setting(_keyNote),
      multiline: true,
      onChanged: (value) => context.setSettings({_keyNote: value}),
    ),
  ],
);

class _CountdownBody extends StatefulWidget {
  const _CountdownBody({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_CountdownBody> createState() => _CountdownBodyState();
}

class _CountdownBodyState extends State<_CountdownBody> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.context.spec;
    final palette = widget.context.palette;
    final target = DateTime.tryParse(spec.setting(_keyTarget));
    if (target == null) {
      return DashboardPlaceholder(
        palette: palette,
        icon: Icons.event_rounded,
        message: LocaleKeys.dashboard_countdown_pickDate.tr(),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(_pickDate(null)),
      );
    }
    final now = DateTime.now();
    final remaining = target.difference(now);
    final past = remaining.isNegative;
    final days = remaining.abs().inDays;
    final hours = remaining.abs().inHours % 24;

    return MouseRegion(
      cursor: widget.context.isTypable
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.context.isTypable
                  ? () => unawaited(_pickDate(target))
                  : null,
              child: Center(
                child: DashboardFigure(
                  value: days > 0 ? '$days' : '$hours',
                  suffix: days > 0
                      ? LocaleKeys.dashboard_countdown_days.tr()
                      : LocaleKeys.dashboard_countdown_hours.tr(),
                  palette: palette,
                  alignment: CrossAxisAlignment.center,
                  color: past ? palette.textMuted : widget.context.strong,
                  caption: spec.setting(_keyLabel).isEmpty
                      ? (past
                          ? LocaleKeys.dashboard_countdown_passed.tr()
                          : DateFormat.yMMMd().format(target))
                      : spec.setting(_keyLabel),
                ),
              ),
            ),
          ),
          // What the countdown is FOR. A bare number on a wall says nothing
          // once the reason for setting it has been forgotten.
          if (widget.context.isTypable ||
              spec.setting(_keyNote).isNotEmpty) ...[
            const SizedBox(height: 8),
            DashboardEditableText(
              value: spec.setting(_keyNote),
              hint: LocaleKeys.dashboard_countdown_noteHint.tr(),
              palette: palette,
              enabled: widget.context.isTypable,
              textAlign: TextAlign.center,
              multiline: true,
              style: DashboardType.caption(palette),
              onChanged: (value) =>
                  widget.context.setSettings({_keyNote: value}),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDate(DateTime? current) async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
    );
    if (chosen == null) {
      return;
    }
    widget.context.setSettings({_keyTarget: chosen.toIso8601String()});
  }
}

// ------------------------------------------------------------------ reminders

final _reminders = DashboardWidgetDefinition(
  type: 'reminders',
  label: () => LocaleKeys.dashboard_widget_reminders.tr(),
  description: () => LocaleKeys.dashboard_widget_remindersHint.tr(),
  icon: Icons.notifications_active_rounded,
  group: DashboardWidgetGroup.time,
  defaultRowSpan: 5,
  keywords: const ['reminders', 'tasks', 'todo', 'due', 'upcoming'],
  builder: (context) => _RemindersBody(context: context),
  configure: (context) => [
    DashboardConfigNumber(
      label: LocaleKeys.dashboard_config_limit.tr(),
      value: context.spec.number(_keyLimit, fallback: 8),
      minimum: 1,
      maximum: 40,
      onChanged: (value) => context.setSettings({_keyLimit: value.round()}),
    ),
  ],
);

class _RemindersBody extends StatefulWidget {
  const _RemindersBody({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_RemindersBody> createState() => _RemindersBodyState();
}

class _RemindersBodyState extends State<_RemindersBody> {
  @override
  void initState() {
    super.initState();
    ReminderStore.instance.addListener(_onChanged);
    ReminderStore.instance.start();
  }

  @override
  void dispose() {
    ReminderStore.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.context.palette;
    final limit = widget.context.spec.integer(_keyLimit, fallback: 8);
    final reminders = ReminderStore.instance.outstanding.take(limit).toList();
    final canWrite = widget.context.isTypable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: reminders.isEmpty
              ? DashboardPlaceholder(
                  palette: palette,
                  icon: Icons.check_circle_outline_rounded,
                  message: LocaleKeys.dashboard_reminders_empty.tr(),
                  action:
                      canWrite ? LocaleKeys.dashboard_reminders_add.tr() : null,
                  onAction: canWrite ? () => unawaited(_compose()) : null,
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: reminders.length,
                  itemBuilder: (_, index) => _ReminderRow(
                    reminder: reminders[index],
                    palette: palette,
                    strong: widget.context.strong,
                    editable: canWrite,
                    onOpen: () => unawaited(_edit(reminders[index])),
                    onComplete: () => unawaited(
                      ReminderStore.instance.complete(reminders[index]),
                    ),
                  ),
                ),
        ),
        if (canWrite && reminders.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: DashboardButton(
              label: LocaleKeys.dashboard_reminders_add.tr(),
              icon: Icons.add_alert_rounded,
              palette: palette,
              onPressed: () => unawaited(_compose()),
            ),
          ),
      ],
    );
  }

  /// A reminder made here is an ordinary AppFlowy reminder: the notification
  /// scheduler already speaks for it, and the calendar widget already draws
  /// it, because both read the same store.
  Future<void> _compose({DateTime? when}) async {
    await showReminderComposer(context, initialWhen: when);
    await ReminderStore.instance.refresh();
  }

  Future<void> _edit(AppReminder reminder) async {
    await showReminderComposer(
      context,
      initialText: reminder.title,
      initialWhen: reminder.firesAt,
      pageId: reminder.pageId,
      objectId: reminder.objectId,
    );
    await ReminderStore.instance.refresh();
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.palette,
    required this.strong,
    required this.editable,
    required this.onOpen,
    required this.onComplete,
  });

  final AppReminder reminder;
  final DashboardPalette palette;
  final Color strong;
  final bool editable;
  final VoidCallback onOpen;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final overdue = reminder.firesAt.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: editable ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: editable ? onOpen : null,
          child: Row(
            children: [
              if (editable)
                DashboardIconButton(
                  icon: Icons.radio_button_unchecked_rounded,
                  palette: palette,
                  size: 22,
                  iconSize: 14,
                  tooltip: LocaleKeys.dashboard_reminders_done.tr(),
                  onPressed: onComplete,
                )
              else
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: overdue ? palette.textMuted : strong,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reminder.title.isEmpty
                      ? LocaleKeys.dashboard_reminders_untitled.tr()
                      : reminder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardType.body(palette).copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat.MMMd().add_jm().format(reminder.firesAt),
                style: DashboardType.caption(palette).copyWith(
                  color: overdue ? strong : palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
