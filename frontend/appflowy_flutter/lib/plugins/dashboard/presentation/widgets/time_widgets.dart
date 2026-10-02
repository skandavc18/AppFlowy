import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_details.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/date_picker_popup.dart';
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
  surface: DashboardSurface.tinted,
  identity: DashboardAccent.purple,
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
    final tone = widget.context.tone;
    final twelve = spec.setting(_keyFormat, fallback: '24') == '12';
    final showSeconds = spec.flag(_keySeconds);
    final showDate = spec.flag(_keyShowDate, fallback: true);

    final hour =
        twelve ? (_now.hour % 12 == 0 ? 12 : _now.hour % 12) : _now.hour;
    final time = '${twelve ? '$hour' : hour.toString().padLeft(2, '0')}'
        ':${_now.minute.toString().padLeft(2, '0')}';
    final period = twelve ? (_now.hour < 12 ? 'AM' : 'PM') : '';

    // The time is the whole point: set large and light, with the seconds and
    // the half of the day as small companions on its baseline.
    final face = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            time,
            style: DashboardType.display(
              palette,
              size: 58,
              color: tone.figure,
              weight: FontWeight.w300,
            ),
          ),
          if (showSeconds)
            Text(
              ':${_now.second.toString().padLeft(2, '0')}',
              style: DashboardType.display(
                palette,
                size: 24,
                color: tone.label.withValues(alpha: 0.7),
              ),
            ),
          if (period.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                period,
                style: DashboardType.eyebrow(palette, color: tone.label),
              ),
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // A short clock is only a time; a taller one is a little calendar
        // page — the day above, the date below.
        if (!showDate || constraints.maxHeight < 104) {
          return Align(alignment: Alignment.centerLeft, child: face);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat.EEEE().format(_now).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardType.eyebrow(palette, color: tone.label)
                  .copyWith(letterSpacing: 1.1, fontSize: 11.5),
            ),
            Expanded(
              child: Align(alignment: Alignment.bottomLeft, child: face),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat.yMMMMd().format(_now),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardType.body(palette, color: tone.inkSoft)
                  .copyWith(fontSize: 13),
            ),
          ],
        );
      },
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
  minimumRowSpan: 5,
  showsTitleByDefault: false,
  // Its navigation runs along the top edge; floating controls would sit on it.
  reservesHeader: true,
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
  builder: (context) => DashboardCalendar(
    key: ValueKey('dashboard-calendar-${context.spec.id}'),
    context: context,
  ),
  configure: (context) => [
    DashboardConfigCalendarView(
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
      CalendarViewMode.monthAgenda ||
      CalendarViewMode.monthSplit =>
        calendarViewModeLabel(mode),
    };

/// The whole calendar, on a dashboard.
///
/// It reads the same sources the calendar page does — this workspace's
/// reminders and any connected Google account — so an event added here is the
/// same event everywhere else, and one added elsewhere shows up here.
class DashboardCalendar extends StatefulWidget {
  const DashboardCalendar({
    super.key,
    required this.context,
    this.workspace,
    this.delegate,
    this.initialDate,
    this.now = DateTime.now,
  }) : assert(workspace == null || delegate != null);

  final DashboardWidgetContext context;

  /// A host may lend its already-connected workspace and actions. The calendar
  /// never starts reminder/network services or disposes a borrowed workspace.
  final CalendarWorkspace? workspace;
  final CalendarViewDelegate? delegate;
  final DateTime? initialDate;
  final DateTime Function() now;

  @override
  State<DashboardCalendar> createState() => _DashboardCalendarState();
}

class _DashboardCalendarState extends State<DashboardCalendar> {
  final GlobalKey<CalendarShellState> _shell = GlobalKey<CalendarShellState>();
  ReminderCalendarProvider? _reminders;
  late CalendarWorkspace _workspace;
  bool _ownsWorkspace = false;

  DashboardWidgetContext get data => widget.context;
  BuildContext get _calendarContext => _shell.currentContext ?? context;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    final borrowed = widget.workspace;
    _ownsWorkspace = borrowed == null;
    if (borrowed != null) {
      _workspace = borrowed;
      _reminders = null;
      return;
    }
    _reminders = ReminderCalendarProvider(
      calendarName: LocaleKeys.reminders_title.tr(),
    );
    _workspace = CalendarWorkspace(providers: [_reminders!]);
    ReminderStore.instance.start();
    unawaited(_attachGoogleCalendars());
  }

  @override
  void didUpdateWidget(DashboardCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      final previous = _workspace;
      final owned = _ownsWorkspace;
      _bind();
      if (owned) previous.dispose();
    }
  }

  /// Local sources first, so the calendar draws with or without a network.
  Future<void> _attachGoogleCalendars() async {
    final workspace = _workspace;
    final selections = await workspace.readGoogleSelection();
    if (!mounted || workspace != _workspace) return;
    final providers =
        await buildGoogleCalendarProviders(selections: selections);
    if (!mounted || workspace != _workspace) {
      for (final provider in providers) {
        provider.dispose();
      }
      return;
    }
    for (final provider in providers) {
      workspace.addProvider(provider);
    }
  }

  @override
  void dispose() {
    if (_ownsWorkspace) _workspace.dispose();
    super.dispose();
  }

  CalendarViewMode get _mode => CalendarViewMode.fromValue(
        data.spec.setting(_keyMode, fallback: 'month'),
      );

  bool get _canEdit => data.isTypable && (widget.delegate?.canEdit ?? true);

  bool get _canCreate => _canEdit && _workspace.defaultProvider != null;

  bool _canEditEvent(CalendarEvent event) =>
      _canEdit &&
      !event.readOnly &&
      (widget.delegate?.allowsEditing(event) ?? true) &&
      (_workspace.providerFor(event)?.capabilities.canEdit ?? false);

  CalendarViewDelegate get _delegate {
    final boundWorkspace = _workspace;
    final boundWidgetId = data.spec.id;
    bool stillBound() =>
        mounted &&
        identical(boundWorkspace, _workspace) &&
        data.spec.id == boundWidgetId;
    final actions = widget.delegate ??
        CalendarViewDelegate(
          colorOf: _workspace.colorFor,
          onOpenEvent: _open,
          onCreateAt: _create,
          onReschedule: _reschedule,
          onToggleComplete: _toggleComplete,
          onShowMore: _showDay,
          onDayMenu: _dayMenu,
          onEventMenu: _eventMenu,
        );
    return CalendarViewDelegate(
      colorOf: actions.colorOf,
      canEdit: _canEdit,
      canEditEvent: _canEditEvent,
      onOpenEvent: actions.onOpenEvent == null
          ? null
          : (event) {
              if (stillBound()) actions.onOpenEvent!(event);
            },
      onEventMenu: actions.onEventMenu == null
          ? null
          : (event, position) {
              if (stillBound()) actions.onEventMenu!(event, position);
            },
      onDayMenu: actions.onDayMenu == null
          ? null
          : (day, position) {
              if (stillBound()) actions.onDayMenu!(day, position);
            },
      onShowMore: actions.onShowMore == null
          ? null
          : (day, position) {
              if (stillBound()) actions.onShowMore!(day, position);
            },
      onCreateAt: !_canCreate || actions.onCreateAt == null
          ? null
          : (at, {bool hasTime = false}) {
              if (stillBound() && _canCreate) {
                actions.onCreateAt!(at, hasTime: hasTime);
              }
            },
      onReschedule: !_canEdit || actions.onReschedule == null
          ? null
          : (event, start, end) {
              if (stillBound() &&
                  _canEditEvent(event) &&
                  (_workspace.providerFor(event)?.capabilities.canMove ??
                      false)) {
                actions.onReschedule!(event, start, end);
              }
            },
      onToggleComplete: !_canEdit || actions.onToggleComplete == null
          ? null
          : (event) {
              if (stillBound() && _canEditEvent(event)) {
                actions.onToggleComplete!(event);
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // One tidy row of chrome when there is room for it; the stacked
        // arrangement only when the card really is narrow.
        builder: (context, constraints) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: MediaQuery.of(context).disableAnimations ||
                data.document.settings.reduceMotion,
          ),
          child: CalendarShell(
            key: _shell,
            workspace: _workspace,
            initialMode: _mode,
            mode: data.isTypable ? _mode : null,
            initialDate: widget.initialDate,
            now: widget.now,
            onModeChanged: (mode) => data.setSettings({_keyMode: mode.name}),
            firstDayOfWeek:
                data.spec.integer(_keyFirstDay, fallback: DateTime.monday),
            showWeekends: data.spec.flag(_keyWeekends, fallback: true),
            showWeekNumbers: data.spec.flag(_keyWeekNumbers),
            compact: constraints.maxWidth < 460,
            quiet: true,
            embedded: data.controller.modalWidgetId != data.spec.id,
            delegate: _delegate,
          ),
        ),
      );

  void _open(CalendarEvent event) {
    if (event.url.isNotEmpty) {
      unawaited(launchUrl(Uri.parse(event.url)));
      return;
    }
    unawaited(showCalendarEventDetails(_calendarContext, event: event));
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
        if (_canCreate)
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
    final canWrite = _canEditEvent(event);
    final canDelete = _canEdit &&
        !event.readOnly &&
        (provider?.capabilities.canDelete ?? false);
    await showAppMenu<void>(
      context: context,
      anchor: position & Size.zero,
      entries: [
        if (event.url.isEmpty)
          AppMenuItem(
            label: LocaleKeys.reminders_open.tr(),
            icon: Icons.open_in_new_rounded,
            onSelected: () => _open(event),
          ),
        if (event.url.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.calendarView_openInGoogle.tr(),
            icon: Icons.launch_rounded,
            onSelected: () => _open(event),
          ),
        if (canWrite && event.kind == CalendarEventKind.reminder)
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
        if (canDelete) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.calendarView_deleteEvent.tr(),
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: () {
              if (_canEdit &&
                  !event.readOnly &&
                  (_workspace.providerFor(event)?.capabilities.canDelete ??
                      false)) {
                unawaited(_workspace.delete(event));
              }
            },
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
        if (_canCreate)
          AppMenuItem(
            label: LocaleKeys.calendarView_newEvent.tr(),
            icon: Icons.add_rounded,
            onSelected: () => unawaited(_create(day)),
          ),
        if (_canCreate)
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
    final reminders = _reminders;
    if (!_canCreate || reminders == null) {
      return;
    }
    await showReminderComposer(
      context,
      initialWhen: at,
      initialHasTime: hasTime,
    );
    if (mounted && identical(reminders, _reminders)) await reminders.refresh();
  }

  Future<void> _reschedule(
    CalendarEvent event,
    DateTime start,
    DateTime? end,
  ) async {
    if (_canEditEvent(event) &&
        (_workspace.providerFor(event)?.capabilities.canMove ?? false)) {
      await _workspace.reschedule(event, start: start, end: end);
    }
  }

  Future<void> _toggleComplete(CalendarEvent event) async {
    if (_canEditEvent(event) && event.kind == CalendarEventKind.reminder) {
      await _reminders?.toggleComplete(event);
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
  surface: DashboardSurface.gradient,
  identity: DashboardAccent.orange,
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
  final _figure = GlobalKey();

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
    final tone = widget.context.tone;
    final label = spec.setting(_keyLabel);
    final date = DateFormat.yMMMd().format(target);

    return MouseRegion(
      cursor: widget.context.isTypable
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // What is being counted down to, in the widget's own ink.
          Text(
            label.isNotEmpty
                ? label
                : (past ? LocaleKeys.dashboard_countdown_passed.tr() : date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardType.eyebrow(palette, color: tone.label),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.context.isTypable
                  ? () => unawaited(_pickDate(target))
                  : null,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  key: _figure,
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        days > 0 ? '$days' : '$hours',
                        style: DashboardType.display(
                          palette,
                          size: 60,
                          weight: FontWeight.w300,
                          color: past ? palette.textMuted : tone.figure,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        days > 0
                            ? LocaleKeys.dashboard_countdown_days.tr()
                            : LocaleKeys.dashboard_countdown_hours.tr(),
                        style: DashboardType.eyebrow(
                          palette,
                          color: tone.label,
                        ).copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                past ? LocaleKeys.dashboard_countdown_passed.tr() : date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.caption(palette, color: tone.inkSoft),
              ),
            ),
          // What the countdown is FOR. A bare number on a wall says nothing
          // once the reason for setting it has been forgotten.
          // Keep the note's slot even when the stored value is empty: its
          // first unsaved draft lives in the field, not in the spec yet.
          const SizedBox(height: 6),
          DashboardEditableText(
            value: spec.setting(_keyNote),
            hint: widget.context.isTypable
                ? LocaleKeys.dashboard_countdown_noteHint.tr()
                : '',
            palette: palette,
            enabled: widget.context.isTypable,
            multiline: true,
            style: DashboardType.caption(palette, color: tone.inkSoft)
                .copyWith(fontSize: 12.5, height: 1.4),
            onChanged: (value) => widget.context.setSettings({_keyNote: value}),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(DateTime? current) async {
    final chosen = await showDatePickerPopup(
      context: _figure.currentContext ?? context,
      initialDate: current,
    );
    if (chosen == null || !mounted) {
      return;
    }
    widget.context.setSettings({
      _keyTarget:
          DateTime(chosen.year, chosen.month, chosen.day).toIso8601String(),
    });
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
  identity: DashboardAccent.orange,
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
    final title = reminder.title.isEmpty
        ? LocaleKeys.dashboard_reminders_untitled.tr()
        : reminder.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _HoverRow(
        palette: palette,
        onTap: editable ? onOpen : null,
        child: Row(
          children: [
            if (editable)
              DashboardIconButton(
                icon: Icons.radio_button_unchecked_rounded,
                palette: palette,
                color: overdue ? strong : palette.textMuted,
                tooltip: LocaleKeys.dashboard_reminders_done.tr(),
                onPressed: onComplete,
              )
            else
              SizedBox(
                width: 24,
                child: Center(
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: overdue ? strong : palette.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.body(palette).copyWith(fontSize: 13.5),
              ),
            ),
            const SizedBox(width: 8),
            // When it is due, as a small chip — warm when it has slipped by.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: overdue
                    ? strong.withValues(alpha: palette.isDark ? 0.2 : 0.12)
                    : palette.sunken.withValues(alpha: 0.8),
                borderRadius:
                    BorderRadius.circular(DashboardMetrics.pillRadius),
              ),
              child: Text(
                DateFormat.MMMd().add_jm().format(reminder.firesAt),
                style: DashboardType.caption(
                  palette,
                  color: overdue ? strong : palette.textSecondary,
                ).copyWith(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A list row that answers the pointer with a soft wash.
class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.palette,
    required this.child,
    this.onTap,
  });

  final DashboardPalette palette;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final live = widget.onTap != null;
    return MouseRegion(
      cursor: live ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: live && _hovered ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(10),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
