import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_sync_indicator.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/agenda_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/time_grid_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/year_view.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The calendar, whatever it is showing.
///
/// It owns three things and nothing else: which day is in view, which reading
/// is on screen, and how the window is narrowed. Everything else belongs to
/// [CalendarWorkspace] (what the events are) or to the views (how they look).
class CalendarShell extends StatefulWidget {
  const CalendarShell({
    super.key,
    required this.workspace,
    required this.delegate,
    this.firstDayOfWeek = DateTime.monday,
    this.showWeekends = true,
    this.showWeekNumbers = false,
    this.initialMode = CalendarViewMode.month,
    this.onModeChanged,
    this.toolbarTrailing,
    this.onConnectCalendar,
    this.hasDateField = true,
    this.compact = false,
  });

  final CalendarWorkspace workspace;
  final CalendarViewDelegate delegate;
  final int firstDayOfWeek;
  final bool showWeekends;
  final bool showWeekNumbers;
  final CalendarViewMode initialMode;
  final ValueChanged<CalendarViewMode>? onModeChanged;
  final Widget? toolbarTrailing;
  final VoidCallback? onConnectCalendar;

  /// False when the table has no date column yet, which is the one thing that
  /// stops the calendar working at all.
  final bool hasDateField;

  /// A phone: the same readings, stacked into two short rows instead of one
  /// long one, and search behind a button.
  final bool compact;

  @override
  State<CalendarShell> createState() => CalendarShellState();
}

class CalendarShellState extends State<CalendarShell> {
  late CalendarViewMode _mode = widget.initialMode;
  DateTime _anchor = startOfDay(DateTime.now());
  DateTime? _selectedDay;
  bool _searching = false;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_onWorkspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWindow());
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_onWorkspaceChanged);
    _search.dispose();
    super.dispose();
  }

  void _onWorkspaceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _loadWindow() {
    unawaited(widget.workspace.load(CalendarWindow(_windowStart, _windowEnd)));
  }

  // --- what is on screen -----------------------------------------------------

  DateTime get _windowStart => switch (_mode) {
        CalendarViewMode.month => startOfWeek(
            DateTime(_anchor.year, _anchor.month),
            widget.firstDayOfWeek,
          ),
        CalendarViewMode.week => startOfWeek(_anchor, widget.firstDayOfWeek),
        CalendarViewMode.day => startOfDay(_anchor),
        CalendarViewMode.agenda => startOfDay(_anchor),
        CalendarViewMode.year => DateTime(_anchor.year),
      };

  DateTime get _windowEnd => switch (_mode) {
        CalendarViewMode.month => _windowStart.add(const Duration(days: 42)),
        CalendarViewMode.week => _windowStart.add(const Duration(days: 7)),
        CalendarViewMode.day => _windowStart.add(const Duration(days: 1)),
        CalendarViewMode.agenda => _windowStart.add(const Duration(days: 60)),
        CalendarViewMode.year => DateTime(_anchor.year + 1),
      };

  String get _title => switch (_mode) {
        CalendarViewMode.month => DateFormat.yMMMM().format(_anchor),
        CalendarViewMode.week => _weekTitle(),
        CalendarViewMode.day => DateFormat.yMMMMEEEEd().format(_anchor),
        CalendarViewMode.agenda => DateFormat.yMMMM().format(_anchor),
        CalendarViewMode.year => DateFormat.y().format(_anchor),
      };

  String _weekTitle() {
    final start = startOfWeek(_anchor, widget.firstDayOfWeek);
    final end = start.add(const Duration(days: 6));
    if (start.month == end.month) {
      return '${DateFormat.MMMM().format(start)} '
          '${start.day}–${end.day}, ${end.year}';
    }
    return '${DateFormat.MMMd().format(start)} – '
        '${DateFormat.yMMMd().format(end)}';
  }

  void _step(int direction) {
    setState(() {
      _anchor = switch (_mode) {
        CalendarViewMode.month =>
          DateTime(_anchor.year, _anchor.month + direction),
        CalendarViewMode.week => _anchor.add(Duration(days: 7 * direction)),
        CalendarViewMode.day => _anchor.add(Duration(days: direction)),
        CalendarViewMode.agenda => _anchor.add(Duration(days: 30 * direction)),
        CalendarViewMode.year => DateTime(_anchor.year + direction),
      };
    });
    _loadWindow();
  }

  void _goToToday() {
    setState(() => _anchor = startOfDay(DateTime.now()));
    _loadWindow();
  }

  /// Open a day in the day reading — what "+3 more" and a date click do.
  void showDay(DateTime day) {
    setState(() {
      _anchor = startOfDay(day);
      _mode = CalendarViewMode.day;
    });
    widget.onModeChanged?.call(_mode);
    _loadWindow();
  }

  /// Open a month — what clicking a month in the year reading does.
  void showMonth(DateTime month) {
    setState(() {
      _anchor = DateTime(month.year, month.month);
      _mode = CalendarViewMode.month;
    });
    widget.onModeChanged?.call(_mode);
    _loadWindow();
  }

  void setMode(CalendarViewMode mode) {
    setState(() => _mode = mode);
    widget.onModeChanged?.call(mode);
    _loadWindow();
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.compact)
          _buildCompactToolbar(palette)
        else
          _buildToolbar(palette),
        Expanded(
          // No `AnimatedSwitcher`: it keeps the outgoing reading alive, and
          // two scroll views cannot share the page's scroll controller.
          child: _buildBody(),
        ),
      ],
    );
  }

  /// Two short rows: navigation and title above, readings below.
  Widget _buildCompactToolbar(CalendarPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(
          CalendarMetrics.space2,
          CalendarMetrics.space2,
          CalendarMetrics.space2,
          CalendarMetrics.space1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: CalendarMetrics.controlSize,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1,
                        letterSpacing: -0.3,
                        color: palette.textPrimary,
                        fontVariations: const [FontVariation.weight(680)],
                      ),
                    ),
                  ),
                  CalendarControlButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: LocaleKeys.calendarView_previous.tr(),
                    onPressed: () => _step(-1),
                  ),
                  _TodayButton(onTap: _goToToday),
                  CalendarControlButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: LocaleKeys.calendarView_next.tr(),
                    onPressed: () => _step(1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CalendarMetrics.space1),
            SizedBox(
              height: CalendarMetrics.controlSize,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: CalendarViewSwitcher(
                        mode: _mode,
                        onChanged: setMode,
                        labels: _labelFor,
                        available: _availableModes,
                      ),
                    ),
                  ),
                  const SizedBox(width: CalendarMetrics.space1),
                  CalendarControlButton(
                    icon: Icons.search_rounded,
                    tooltip: LocaleKeys.calendarView_search.tr(),
                    active: widget.workspace.filter.query.isNotEmpty,
                    onPressed: _openSearchSheet,
                  ),
                  CalendarFilterButton(workspace: widget.workspace),
                  CalendarSyncIndicator(workspace: widget.workspace),
                ],
              ),
            ),
          ],
        ),
      );

  /// On a phone there is no room for a persistent field, so search is a sheet.
  Future<void> _openSearchSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(CalendarMetrics.space4),
          decoration: BoxDecoration(
            color: calendarPaletteOf(context).surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18),
            ),
          ),
          child: _SearchField(
            controller: _search,
            onChanged: (value) => widget.workspace.setFilter(
              widget.workspace.filter.copyWith(query: value),
            ),
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  List<CalendarViewMode> get _availableModes => const [
        CalendarViewMode.month,
        CalendarViewMode.week,
        CalendarViewMode.day,
        CalendarViewMode.agenda,
        CalendarViewMode.year,
      ];

  Widget _buildToolbar(CalendarPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(
          CalendarMetrics.space3,
          CalendarMetrics.space2,
          CalendarMetrics.space3,
          CalendarMetrics.space2,
        ),
        child: SizedBox(
          height: CalendarMetrics.controlSize,
          child: Row(
            children: [
              CalendarControlButton(
                icon: Icons.chevron_left_rounded,
                tooltip: LocaleKeys.calendarView_previous.tr(),
                onPressed: () => _step(-1),
              ),
              const SizedBox(width: 2),
              CalendarControlButton(
                icon: Icons.chevron_right_rounded,
                tooltip: LocaleKeys.calendarView_next.tr(),
                onPressed: () => _step(1),
              ),
              const SizedBox(width: CalendarMetrics.space2),
              _TodayButton(onTap: _goToToday),
              const SizedBox(width: CalendarMetrics.space3),
              Flexible(
                child: AnimatedSwitcher(
                  duration: CalendarMetrics.change,
                  child: Text(
                    _title,
                    key: ValueKey(_title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1,
                      letterSpacing: -0.25,
                      color: palette.textPrimary,
                      fontVariations: const [FontVariation.weight(660)],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CalendarMetrics.space3),
              if (_searching)
                _SearchField(
                  controller: _search,
                  onChanged: (value) => widget.workspace.setFilter(
                    widget.workspace.filter.copyWith(query: value),
                  ),
                  onClose: () {
                    setState(() => _searching = false);
                    _search.clear();
                    widget.workspace.setFilter(
                      widget.workspace.filter.copyWith(query: ''),
                    );
                  },
                )
              else
                CalendarControlButton(
                  icon: Icons.search_rounded,
                  tooltip: LocaleKeys.calendarView_search.tr(),
                  onPressed: () => setState(() => _searching = true),
                ),
              const SizedBox(width: 2),
              CalendarFilterButton(workspace: widget.workspace),
              const SizedBox(width: CalendarMetrics.space2),
              CalendarSyncIndicator(workspace: widget.workspace),
              const SizedBox(width: CalendarMetrics.space2),
              CalendarViewSwitcher(
                mode: _mode,
                onChanged: setMode,
                labels: _labelFor,
                available: _availableModes,
              ),
              if (widget.toolbarTrailing != null) ...[
                const SizedBox(width: CalendarMetrics.space2),
                widget.toolbarTrailing!,
              ],
            ],
          ),
        ),
      );

  static String _labelFor(CalendarViewMode mode) => switch (mode) {
        CalendarViewMode.month => LocaleKeys.calendarView_views_month.tr(),
        CalendarViewMode.week => LocaleKeys.calendarView_views_week.tr(),
        CalendarViewMode.day => LocaleKeys.calendarView_views_day.tr(),
        CalendarViewMode.agenda => LocaleKeys.calendarView_views_agenda.tr(),
        CalendarViewMode.year => LocaleKeys.calendarView_views_year.tr(),
      };

  Widget _buildBody() {
    if (!widget.hasDateField) {
      return CalendarEmptyState(
        icon: Icons.event_busy_rounded,
        title: LocaleKeys.calendarView_empty_noDateFieldTitle.tr(),
        message: LocaleKeys.calendarView_empty_noDateFieldBody.tr(),
      );
    }

    final events = widget.workspace.eventsBetween(_windowStart, _windowEnd);

    return switch (_mode) {
      CalendarViewMode.month => CalendarMonthView(
          month: _anchor,
          events: events,
          delegate: widget.delegate,
          firstDayOfWeek: widget.firstDayOfWeek,
          showWeekends: widget.showWeekends,
          showWeekNumbers: widget.showWeekNumbers,
          selectedDay: _selectedDay,
          onSelectDay: (day) => setState(() => _selectedDay = day),
        ),
      CalendarViewMode.week => CalendarTimeGridView(
          days: weekDays(
            _anchor,
            firstDayOfWeek: widget.firstDayOfWeek,
            showWeekends: widget.showWeekends,
          ),
          events: events,
          delegate: widget.delegate,
        ),
      CalendarViewMode.day => CalendarTimeGridView(
          days: [startOfDay(_anchor)],
          events: events,
          delegate: widget.delegate,
        ),
      CalendarViewMode.agenda => CalendarAgendaView(
          from: _windowStart,
          to: _windowEnd,
          events: events,
          delegate: widget.delegate,
          allDayLabel: LocaleKeys.calendarView_allDay.tr(),
          labelFor: _agendaLabel,
          emptyState: _emptyState(),
        ),
      CalendarViewMode.year => CalendarYearView(
          year: _anchor.year,
          events: events,
          delegate: widget.delegate,
          firstDayOfWeek: widget.firstDayOfWeek,
          onOpenMonth: showMonth,
          onOpenDay: showDay,
        ),
    };
  }

  Widget _emptyState() {
    if (widget.workspace.filter.isActive) {
      return CalendarEmptyState(
        icon: Icons.search_off_rounded,
        title: LocaleKeys.calendarView_empty_searchTitle.tr(),
        message: LocaleKeys.calendarView_empty_searchBody.tr(),
        actionLabel: LocaleKeys.calendarView_filters_reset.tr(),
        onAction: () {
          _search.clear();
          widget.workspace.setFilter(const CalendarFilter());
        },
      );
    }
    final hasRemote = widget.workspace.remoteProviders.isNotEmpty;
    if (!hasRemote && widget.onConnectCalendar != null) {
      return CalendarEmptyState(
        icon: Icons.event_available_rounded,
        title: LocaleKeys.calendarView_empty_rangeTitle.tr(),
        message: LocaleKeys.calendarView_empty_noConnectionBody.tr(),
        actionLabel: LocaleKeys.calendarView_empty_connect.tr(),
        onAction: widget.onConnectCalendar,
      );
    }
    return CalendarEmptyState(
      icon: Icons.event_available_rounded,
      title: LocaleKeys.calendarView_empty_rangeTitle.tr(),
      message: LocaleKeys.calendarView_empty_rangeBody.tr(),
    );
  }

  static String _agendaLabel(DateTime day, {required bool relative}) {
    if (!relative) {
      return DateFormat.EEEE().format(day);
    }
    final today = startOfDay(DateTime.now());
    final delta = daysBetween(today, day);
    return switch (delta) {
      0 => LocaleKeys.calendarView_relative_today.tr(),
      1 => LocaleKeys.calendarView_relative_tomorrow.tr(),
      -1 => LocaleKeys.calendarView_relative_yesterday.tr(),
      _ => DateFormat.EEEE().format(day),
    };
  }
}

class _TodayButton extends StatefulWidget {
  const _TodayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TodayButton> createState() => _TodayButtonState();
}

class _TodayButtonState extends State<_TodayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: CalendarMetrics.hover,
          curve: CalendarMetrics.hoverCurve,
          height: CalendarMetrics.controlSize,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.hover.withValues(alpha: _hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(CalendarMetrics.controlRadius),
          ),
          child: Text(
            LocaleKeys.calendarView_today.tr(),
            style: TextStyle(
              fontSize: 12.5,
              height: 1,
              color: palette.textSecondary,
              fontVariations: const [FontVariation.weight(590)],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return SizedBox(
      width: 208,
      height: CalendarMetrics.controlSize,
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        style: TextStyle(fontSize: 12.5, color: palette.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.sunken.withValues(alpha: 0.7),
          hintText: LocaleKeys.calendarView_searchHint.tr(),
          hintStyle: TextStyle(fontSize: 12.5, color: palette.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 15,
            color: palette.textMuted,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 30),
          suffixIcon: GestureDetector(
            onTap: onClose,
            child: Icon(
              Icons.close_rounded,
              size: 15,
              color: palette.textMuted,
            ),
          ),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 30),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CalendarMetrics.controlRadius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CalendarMetrics.controlRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CalendarMetrics.controlRadius),
            borderSide: BorderSide(color: palette.accent, width: 1.2),
          ),
        ),
      ),
    );
  }
}
