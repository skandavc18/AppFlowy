import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_sync_indicator.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/agenda_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_agenda_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/time_grid_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/year_view.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// An embedded host can own its presentation without changing the table's
/// saved page layout. A null mode follows that page until the host chooses one;
/// a null callback makes runtime navigation local, never a table-setting write.
class CalendarPresentationScope extends InheritedWidget {
  const CalendarPresentationScope({
    super.key,
    required super.child,
    this.mode,
    this.onModeChanged,
    this.embedded = true,
  });

  final CalendarViewMode? mode;
  final ValueChanged<CalendarViewMode>? onModeChanged;
  final bool embedded;

  static CalendarPresentationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CalendarPresentationScope>();

  @override
  bool updateShouldNotify(CalendarPresentationScope oldWidget) =>
      mode != oldWidget.mode ||
      onModeChanged != oldWidget.onModeChanged ||
      embedded != oldWidget.embedded;
}

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
    this.mode,
    this.onModeChanged,
    this.toolbarTrailing,
    this.onConnectCalendar,
    this.hasDateField = true,
    this.compact = false,
    this.quiet = false,
    this.embedded = false,
    this.initialDate,
    this.now = DateTime.now,
  });

  final CalendarWorkspace workspace;
  final CalendarViewDelegate delegate;
  final int firstDayOfWeek;
  final bool showWeekends;
  final bool showWeekNumbers;
  final CalendarViewMode initialMode;

  /// When supplied, the host's saved choice is authoritative, including a
  /// failed save that rolls back before the next frame. Read-only hosts can
  /// leave this null so navigating layouts remains a local viewing action.
  final CalendarViewMode? mode;
  final ValueChanged<CalendarViewMode>? onModeChanged;
  final Widget? toolbarTrailing;
  final VoidCallback? onConnectCalendar;

  /// False when the table has no date column yet, which is the one thing that
  /// stops the calendar working at all.
  final bool hasDateField;

  /// A phone: the same readings, stacked into two short rows instead of one
  /// long one, and search behind a button.
  final bool compact;

  /// Embedded on a page or a dashboard: navigation and the views, nothing
  /// else. Searching and filtering belong to the calendar's own page.
  final bool quiet;

  /// Card density is independent of toolbar visibility. Pages share their
  /// available height between month and events; embeds retain a compact grid.
  final bool embedded;

  final DateTime? initialDate;
  final DateTime Function() now;

  @override
  State<CalendarShell> createState() => CalendarShellState();
}

class CalendarShellState extends State<CalendarShell> {
  late CalendarViewMode _mode = widget.mode ?? widget.initialMode;
  late DateTime _anchor = startOfDay(widget.initialDate ?? widget.now());
  DateTime? _selectedDay;
  bool _searching = false;
  final TextEditingController _search = TextEditingController();
  final PageStorageBucket _scrollState = PageStorageBucket();
  CalendarPresentationScope? _presentation;

  bool get _quiet => widget.quiet || _presentation != null;

  CalendarViewMode get _preferredMode =>
      _presentation?.mode ?? widget.mode ?? widget.initialMode;

  CalendarViewMode? get _controlledMode => _presentation == null
      ? widget.mode
      : _presentation!.onModeChanged == null
          ? null
          : _presentation!.mode ?? widget.mode;

  @override
  void initState() {
    super.initState();
    _search.text = widget.workspace.filter.query;
    widget.workspace.addListener(_onWorkspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWindow());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final previous = _presentation;
    _presentation = CalendarPresentationScope.maybeOf(context);
    final changed = previous?.mode != _presentation?.mode ||
        (previous == null) != (_presentation == null) ||
        (previous?.onModeChanged == null) !=
            (_presentation?.onModeChanged == null);
    final controlled = _controlledMode;
    if ((controlled != null && controlled != _mode) ||
        (changed && _preferredMode != _mode)) {
      _adoptMode(controlled ?? _preferredMode);
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadWindow());
    }
  }

  @override
  void didUpdateWidget(CalendarShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rebound = oldWidget.workspace != widget.workspace;
    if (rebound) {
      oldWidget.workspace.removeListener(_onWorkspaceChanged);
      widget.workspace.addListener(_onWorkspaceChanged);
      _search.text = widget.workspace.filter.query;
    }
    final controlled = _controlledMode;
    final modeChanged = controlled != null
        ? controlled != _mode
        : oldWidget.initialMode != widget.initialMode;
    if (modeChanged) _adoptMode(controlled ?? _preferredMode);
    if (rebound ||
        modeChanged ||
        oldWidget.firstDayOfWeek != widget.firstDayOfWeek) {
      // load notifies synchronously. Do not dirty ancestors during their build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadWindow());
    }
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
    if (!mounted) return;
    unawaited(widget.workspace.load(CalendarWindow(_windowStart, _windowEnd)));
  }

  void _reportMode(CalendarViewMode mode) {
    final presentation = _presentation;
    if (presentation != null) {
      presentation.onModeChanged?.call(mode);
    } else {
      widget.onModeChanged?.call(mode);
    }
  }

  // --- what is on screen -----------------------------------------------------

  DateTime get _windowStart => switch (_mode) {
        CalendarViewMode.month ||
        CalendarViewMode.monthAgenda ||
        CalendarViewMode.monthSplit =>
          startOfWeek(
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
        CalendarViewMode.monthAgenda ||
        CalendarViewMode.monthSplit =>
          calendarDayOffset(_windowStart, 42),
        CalendarViewMode.week => _windowStart.add(const Duration(days: 7)),
        CalendarViewMode.day => _windowStart.add(const Duration(days: 1)),
        CalendarViewMode.agenda => _windowStart.add(const Duration(days: 60)),
        CalendarViewMode.year => DateTime(_anchor.year + 1),
      };

  String get _title => switch (_mode) {
        CalendarViewMode.month ||
        CalendarViewMode.monthAgenda ||
        CalendarViewMode.monthSplit =>
          DateFormat.yMMMM().format(_anchor),
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
        CalendarViewMode.monthAgenda ||
        CalendarViewMode.monthSplit =>
          calendarMonthOffset(_selectedDay ?? _anchor, direction),
        CalendarViewMode.week => _anchor.add(Duration(days: 7 * direction)),
        CalendarViewMode.day => _anchor.add(Duration(days: direction)),
        CalendarViewMode.agenda => _anchor.add(Duration(days: 30 * direction)),
        CalendarViewMode.year => DateTime(_anchor.year + direction),
      };
      if (_mode.hasMonthAgenda) _selectedDay = _anchor;
    });
    _loadWindow();
  }

  void _goToToday() {
    setState(() {
      _anchor = startOfDay(widget.now());
      _selectedDay = _anchor;
    });
    _loadWindow();
  }

  void _selectAgendaDay(DateTime day) {
    final changedMonth = day.month != _anchor.month || day.year != _anchor.year;
    setState(() {
      _selectedDay = startOfDay(day);
      _anchor = _selectedDay!;
    });
    if (changedMonth) _loadWindow();
  }

  /// Open a day in the day reading — what "+3 more" and a date click do.
  void showDay(DateTime day) {
    setState(() {
      _anchor = startOfDay(day);
      _selectedDay = _anchor;
      _mode = CalendarViewMode.day;
    });
    _reportMode(_mode);
    _loadWindow();
  }

  /// Find navigation changes only the date being read, not the saved layout,
  /// filters, focus, selection in an editor, or an event's typed date value.
  void revealDateForFind(DateTime day) {
    if (!mounted) return;
    final date = startOfDay(day);
    if (!date.isBefore(_windowStart) &&
        date.isBefore(_windowEnd) &&
        (!_mode.hasMonthAgenda || _selectedDay == date)) {
      return;
    }
    setState(() {
      _anchor = date;
      _selectedDay = date;
    });
    _loadWindow();
  }

  /// Open a month — what clicking a month in the year reading does.
  void showMonth(DateTime month) {
    setState(() {
      _anchor = DateTime(month.year, month.month);
      _selectedDay = _anchor;
      _mode = CalendarViewMode.month;
    });
    _reportMode(_mode);
    _loadWindow();
  }

  void setMode(CalendarViewMode mode) {
    if (_mode == mode) return;
    setState(() => _adoptMode(mode));
    _reportMode(mode);
    _loadWindow();
  }

  void _adoptMode(CalendarViewMode mode) {
    _mode = mode;
    if (mode.hasMonthAgenda &&
        (_selectedDay == null ||
            _selectedDay!.month != _anchor.month ||
            _selectedDay!.year != _anchor.year)) {
      _selectedDay = _anchor;
    }
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Quiet calendars are also hosted directly by dashboard cards.
    return _quiet
        ? PreviewToolbarRegion(child: Builder(builder: _buildCalendar))
        : _buildCalendar(context);
  }

  Widget _buildCalendar(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => _buildContent(
          context,
          compactMonthAgenda: widget.compact ||
              widget.embedded ||
              (_presentation?.embedded ?? false) ||
              constraints.maxWidth < 760 ||
              constraints.maxHeight < 480,
        ),
      );

  Widget _buildContent(
    BuildContext context, {
    required bool compactMonthAgenda,
  }) {
    final palette = calendarPaletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_mode.hasMonthAgenda)
          _buildMonthAgendaToolbar(compact: compactMonthAgenda)
        else if (widget.compact)
          _buildCompactToolbar(palette)
        else
          _buildToolbar(palette),
        Expanded(
          // No `AnimatedSwitcher`: it keeps the outgoing reading alive, and
          // two scroll views cannot share the page's scroll controller.
          child: PageStorage(
            bucket: _scrollState,
            child: _buildBody(compactMonthAgenda: compactMonthAgenda),
          ),
        ),
      ],
    );
  }

  /// Date identity plus icon-sized actions leave room for six weeks and an
  /// agenda in a dashboard-sized box. Text grows instead of being clipped into
  /// a fixed-height toolbar, and resizing never changes this tree's shape.
  Widget _buildMonthAgendaToolbar({required bool compact}) =>
      CalendarMonthAgendaMeasure(
        sideBySide: _mode == CalendarViewMode.monthSplit,
        compact: compact,
        child: Padding(
          key: const ValueKey('calendar-month-agenda-toolbar'),
          padding: const EdgeInsets.symmetric(
            horizontal: WorkspaceTokens.space3,
            vertical: WorkspaceTokens.space1,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.cardTitle,
                      ),
                    ),
                  ),
                  PreviewToolbar(
                    keepVisible: _searching ||
                        widget.workspace.status.state.needsAttention,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CalendarControlButton(
                          icon: Icons.chevron_left_rounded,
                          tooltip: LocaleKeys.calendarView_previous.tr(),
                          onPressed: () => _step(-1),
                        ),
                        CalendarControlButton(
                          key: const ValueKey('calendar-go-today'),
                          icon: Icons.today_rounded,
                          tooltip: LocaleKeys.calendarView_today.tr(),
                          onPressed: _goToToday,
                        ),
                        CalendarControlButton(
                          icon: Icons.chevron_right_rounded,
                          tooltip: LocaleKeys.calendarView_next.tr(),
                          onPressed: () => _step(1),
                        ),
                        CalendarViewSwitcher(
                          mode: _mode,
                          onChanged: setMode,
                          labels: calendarViewModeLabel,
                          popup: true,
                          iconOnly: true,
                        ),
                        if (!_quiet)
                          CalendarControlButton(
                            icon: Icons.search_rounded,
                            tooltip: LocaleKeys.calendarView_search.tr(),
                            onPressed: () =>
                                setState(() => _searching = !_searching),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!_quiet)
                PreviewToolbar(
                  keepVisible: _searching ||
                      widget.workspace.status.state.needsAttention ||
                      widget.workspace.status.state.isBusy,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        CalendarFilterButton(workspace: widget.workspace),
                        CalendarSyncIndicator(workspace: widget.workspace),
                        if (widget.toolbarTrailing != null)
                          widget.toolbarTrailing!,
                      ],
                    ),
                  ),
                ),
              if (_searching && !_quiet)
                _SearchField(
                  controller: _search,
                  onChanged: (value) => widget.workspace.setFilter(
                    widget.workspace.filter.copyWith(query: value),
                  ),
                  onClose: () {
                    setState(() => _searching = false);
                    _search.clear();
                    widget.workspace
                        .setFilter(widget.workspace.filter.copyWith(query: ''));
                  },
                ),
            ],
          ),
        ),
      );

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
                        fontSize: 17,
                        height: 1,
                        letterSpacing: -0.4,
                        color: palette.textPrimary,
                        fontVariations: const [FontVariation.weight(700)],
                      ),
                    ),
                  ),
                  Flexible(
                    child: PreviewToolbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CalendarMetrics.space1),
            SizedBox(
              height: CalendarMetrics.controlSize,
              child: PreviewToolbar(
                keepVisible: !widget.hasDateField ||
                    widget.workspace.status.state.needsAttention ||
                    widget.workspace.status.state.isBusy,
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
                          popup: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: CalendarMetrics.space1),
                    if (!_quiet) ...[
                      CalendarControlButton(
                        icon: Icons.search_rounded,
                        tooltip: LocaleKeys.calendarView_search.tr(),
                        active: widget.workspace.filter.query.isNotEmpty,
                        onPressed: _openSearchSheet,
                      ),
                      CalendarFilterButton(workspace: widget.workspace),
                      CalendarSyncIndicator(workspace: widget.workspace),
                    ],
                  ],
                ),
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

  List<CalendarViewMode> get _availableModes => CalendarViewMode.values;

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
              Flexible(
                child: PreviewToolbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CalendarMetrics.space3),
              Expanded(
                child: AnimatedSwitcher(
                  duration:
                      WorkspaceTokens.motion(context, CalendarMetrics.change),
                  child: Text(
                    _title,
                    key: ValueKey(_title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1,
                      letterSpacing: -0.45,
                      color: palette.textPrimary,
                      fontVariations: const [FontVariation.weight(700)],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CalendarMetrics.space3),
              Flexible(
                flex: 2,
                child: PreviewToolbar(
                  keepVisible: _searching ||
                      !widget.hasDateField ||
                      widget.workspace.status.state.needsAttention ||
                      widget.workspace.status.state.isBusy,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_quiet) ...[
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
                              onPressed: () =>
                                  setState(() => _searching = true),
                            ),
                          const SizedBox(width: 2),
                          CalendarFilterButton(workspace: widget.workspace),
                          const SizedBox(width: CalendarMetrics.space2),
                          CalendarSyncIndicator(workspace: widget.workspace),
                          const SizedBox(width: CalendarMetrics.space2),
                        ],
                        CalendarViewSwitcher(
                          mode: _mode,
                          onChanged: setMode,
                          labels: _labelFor,
                          available: _availableModes,
                          popup: true,
                        ),
                        if (widget.toolbarTrailing != null) ...[
                          const SizedBox(width: CalendarMetrics.space2),
                          widget.toolbarTrailing!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  static String _labelFor(CalendarViewMode mode) => calendarViewModeLabel(mode);

  Widget _buildBody({required bool compactMonthAgenda}) {
    if (!widget.hasDateField) {
      return CalendarEmptyState(
        icon: Icons.event_busy_rounded,
        title: LocaleKeys.calendarView_empty_noDateFieldTitle.tr(),
        message: LocaleKeys.calendarView_empty_noDateFieldBody.tr(),
      );
    }

    final events = _mode.hasMonthAgenda
        ? widget.workspace.events
            .where(
              (event) =>
                  !event.endDay.isBefore(_windowStart) &&
                  event.startDay.isBefore(_windowEnd),
            )
            .toList()
        : widget.workspace.eventsBetween(_windowStart, _windowEnd);

    return switch (_mode) {
      CalendarViewMode.month => CalendarMonthView(
          key: const PageStorageKey('calendar-month'),
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
          key: const PageStorageKey('calendar-week'),
          days: weekDays(
            _anchor,
            firstDayOfWeek: widget.firstDayOfWeek,
            showWeekends: widget.showWeekends,
          ),
          events: events,
          delegate: widget.delegate,
        ),
      CalendarViewMode.day => CalendarTimeGridView(
          key: const PageStorageKey('calendar-day'),
          days: [startOfDay(_anchor)],
          events: events,
          delegate: widget.delegate,
        ),
      CalendarViewMode.agenda => CalendarAgendaView(
          key: const PageStorageKey('calendar-agenda'),
          from: _windowStart,
          to: _windowEnd,
          events: events,
          delegate: widget.delegate,
          allDayLabel: LocaleKeys.calendarView_allDay.tr(),
          labelFor: _agendaLabel,
          emptyState: _emptyState(),
        ),
      CalendarViewMode.year => CalendarYearView(
          key: const PageStorageKey('calendar-year'),
          year: _anchor.year,
          events: events,
          delegate: widget.delegate,
          firstDayOfWeek: widget.firstDayOfWeek,
          onOpenMonth: showMonth,
          onOpenDay: showDay,
        ),
      CalendarViewMode.monthAgenda ||
      CalendarViewMode.monthSplit =>
        CalendarMonthAgendaView(
          key: const PageStorageKey('calendar-month-with-agenda'),
          month: _anchor,
          selectedDay: _selectedDay ?? _anchor,
          events: events,
          delegate: widget.delegate,
          onSelectDay: _selectAgendaDay,
          sideBySide: _mode == CalendarViewMode.monthSplit,
          compact: compactMonthAgenda,
          firstDayOfWeek: widget.firstDayOfWeek,
          showWeekends: widget.showWeekends,
          showWeekNumbers: widget.showWeekNumbers,
          now: widget.now,
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
      child: TextButton(
        onPressed: widget.onTap,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: palette.textSecondary,
        ),
        child: AnimatedContainer(
          duration: WorkspaceTokens.motion(context, CalendarMetrics.hover),
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
      height: MediaQuery.textScalerOf(context).scale(12.5) + 18,
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
          prefixIcon: WorkspaceGlyph(
            Icons.search_rounded,
            size: 15,
            color: palette.textMuted,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 30),
          suffixIcon: CalendarControlButton(
            icon: Icons.close_rounded,
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            onPressed: onClose,
            size: 26,
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
