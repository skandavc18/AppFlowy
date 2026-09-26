import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// The date identity, navigation and reading share one measure. Embedded cards
/// keep a compact reading width; a page uses its available width, with a small
/// extra inset rather than a fixed desktop cap. The wrapper never changes.
class CalendarMonthAgendaMeasure extends StatelessWidget {
  const CalendarMonthAgendaMeasure({
    super.key,
    required this.sideBySide,
    required this.child,
    this.compact = false,
  });

  final bool sideBySide;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: EdgeInsets.symmetric(
              horizontal: !compact && constraints.maxWidth >= 960
                  ? WorkspaceTokens.space3
                  : 0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: compact ? (sideBySide ? 1100 : 720) : double.infinity,
              ),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        ),
      );
}

double _weekdayHeight(TextScaler scaler) =>
    math.max(20.0, scaler.scale(11) * 1.4 + WorkspaceTokens.space1);

/// Both month-with-events readings use this same tree. Only constraints and
/// the Flex direction change: resizing never replaces a scrollable or action.
class CalendarMonthAgendaView extends StatefulWidget {
  const CalendarMonthAgendaView({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.events,
    required this.delegate,
    required this.onSelectDay,
    this.sideBySide = false,
    this.compact = false,
    this.firstDayOfWeek = DateTime.monday,
    this.showWeekends = true,
    this.showWeekNumbers = false,
    this.now = DateTime.now,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<CalendarEvent> events;
  final CalendarViewDelegate delegate;
  final ValueChanged<DateTime> onSelectDay;
  final bool sideBySide;
  final bool compact;
  final int firstDayOfWeek;
  final bool showWeekends;
  final bool showWeekNumbers;
  final DateTime Function() now;

  @override
  State<CalendarMonthAgendaView> createState() =>
      _CalendarMonthAgendaViewState();
}

class _CalendarMonthAgendaViewState extends State<CalendarMonthAgendaView> {
  final _outerScroll = ScrollController();
  final _agendaScroll = ScrollController();
  final _gridFocus = FocusNode(debugLabel: 'Calendar dates');
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Relative day labels and today's marker stay current overnight. This
    // never polls a provider or changes the selected day under the reader.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(CalendarMonthAgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.selectedDay, widget.selectedDay)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _agendaScroll.hasClients) _agendaScroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _outerScroll.dispose();
    _agendaScroll.dispose();
    _gridFocus.dispose();
    super.dispose();
  }

  void _select(DateTime day) {
    _gridFocus.requestFocus();
    widget.onSelectDay(startOfDay(day));
  }

  KeyEventResult _onGridKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final day = widget.selectedDay;
    final rtl = Directionality.of(context) == ui.TextDirection.rtl;
    DateTime next;
    var direction = 1;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      direction = (key == LogicalKeyboardKey.arrowRight) != rtl ? 1 : -1;
      next = calendarDayOffset(day, direction);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      direction = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      next = calendarDayOffset(day, direction * 7);
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown) {
      direction = key == LogicalKeyboardKey.pageDown ? 1 : -1;
      next = calendarMonthOffset(day, direction);
    } else if (key == LogicalKeyboardKey.home) {
      next = startOfWeek(day, widget.firstDayOfWeek);
    } else if (key == LogicalKeyboardKey.end) {
      direction = -1;
      next = calendarDayOffset(startOfWeek(day, widget.firstDayOfWeek), 6);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      next = day;
    } else {
      return KeyEventResult.ignored;
    }
    while (!widget.showWeekends && isWeekend(next)) {
      next = calendarDayOffset(next, direction);
    }
    _select(next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedDay());
    return KeyEventResult.handled;
  }

  void _revealSelectedDay() {
    if (!mounted) return;
    final gridContext = _gridFocus.context;
    final box = gridContext?.findRenderObject();
    if (gridContext == null || box is! RenderBox || !box.hasSize) return;
    final scrollable = Scrollable.maybeOf(gridContext);
    if (scrollable == null) return;
    final days = monthGridDays(
      widget.month,
      firstDayOfWeek: widget.firstDayOfWeek,
      showWeekends: widget.showWeekends,
    );
    final index = days.indexWhere((day) => isSameDay(day, widget.selectedDay));
    if (index < 0) return;
    final columns = widget.showWeekends ? 7 : 5;
    final weekdayHeight = _weekdayHeight(MediaQuery.textScalerOf(context));
    final rowHeight =
        (box.size.height - weekdayHeight) / (days.length ~/ columns);
    final rect = Rect.fromLTWH(
      0,
      weekdayHeight + (index ~/ columns) * rowHeight,
      box.size.width,
      rowHeight,
    );
    final viewport = RenderAbstractViewport.of(box);
    final top = viewport.getOffsetToReveal(box, 0, rect: rect).offset;
    final bottom = viewport.getOffsetToReveal(box, 1, rect: rect).offset;
    final position = scrollable.position;
    final target = position.pixels < bottom
        ? bottom
        : position.pixels > top
            ? top
            : position.pixels;
    position.jumpTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = monthGridDays(
      widget.month,
      firstDayOfWeek: widget.firstDayOfWeek,
      showWeekends: widget.showWeekends,
    );
    final columns = widget.showWeekends ? 7 : 5;
    final rows = days.length ~/ columns;
    final scaler = MediaQuery.textScalerOf(context);
    final weekdayHeight = _weekdayHeight(scaler);
    final weekNumberWidth = widget.showWeekNumbers
        ? math.max(24.0, scaler.scale(11) * 2 + WorkspaceTokens.space1)
        : 0.0;
    final minimumGridWidth = math.max(
      240.0,
      columns *
              math.max(32.0, scaler.scale(14) * 1.4 + WorkspaceTokens.space1) +
          weekNumberWidth,
    );
    final agendaHeaderHeight = math.max(
          CalendarMetrics.controlSize,
          scaler.scale(15) * 1.35,
        ) +
        WorkspaceTokens.space1;
    final now = widget.now();

    return CalendarScrollScope(
      child: CalendarMonthAgendaMeasure(
        sideBySide: widget.sideBySide,
        compact: widget.compact,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WorkspaceTokens.space3,
            vertical: WorkspaceTokens.space1,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The shell decides card/page density from the host bounds.
              // Opening search can shorten the body: retain the page's row
              // floor and scroll rather than stretch compact rows full-width.
              final fullPage = !widget.compact && constraints.maxWidth >= 600;
              final spacious = fullPage ||
                  (constraints.maxWidth >= 600 && constraints.maxHeight >= 420);
              final gridMinimumWidth = fullPage
                  ? math.max(minimumGridWidth, columns * 64 + weekNumberWidth)
                  : minimumGridWidth;
              final minimumAgendaWidth = math.max(
                fullPage ? 320.0 : 220.0,
                scaler.scale(12) * (fullPage ? 14 : 11),
              );
              final eventRowHeight = math.max(
                fullPage ? 48.0 : 40.0,
                scaler.scale(fullPage ? 16 : 14) * 1.25 +
                    scaler.scale(12) * 1.4 +
                    WorkspaceTokens.space1,
              );
              final beside = widget.sideBySide &&
                  constraints.maxWidth >=
                      gridMinimumWidth +
                          minimumAgendaWidth +
                          WorkspaceTokens.space6;
              final dateFontSize = fullPage ? 18.0 : 14.0;
              final badgeExtent = math.max(
                fullPage ? 44.0 : (spacious ? 36.0 : 32.0),
                scaler.scale(dateFontSize) + 10,
              );
              final minimumRowHeight = math.max(
                fullPage ? 56.0 : (spacious ? 44.0 : 32.0),
                badgeExtent,
              );
              final minimumGridHeight = weekdayHeight + rows * minimumRowHeight;
              final gap = beside
                  ? WorkspaceTokens.space6
                  : spacious
                      ? WorkspaceTokens.space4
                      : WorkspaceTokens.space2;
              final agendaMinimumHeight =
                  agendaHeaderHeight + eventRowHeight * (fullPage ? 3 : 1);
              final height = math.max(
                constraints.hasBoundedHeight ? constraints.maxHeight : 0.0,
                beside
                    ? math.max(minimumGridHeight, agendaMinimumHeight)
                    : minimumGridHeight + gap + agendaMinimumHeight,
              );
              // A page shares height as well as width. The stack reserves an
              // actual event viewport (not just its heading); the split lets
              // both panes use the full height. Large text can outer-scroll
              // instead of deleting weeks or squeezing dates below their floor.
              final gridHeight = fullPage
                  ? beside
                      ? height
                      : math.max(
                          minimumGridHeight,
                          math.min(
                            height * 0.58,
                            height - gap - agendaMinimumHeight,
                          ),
                        )
                  : minimumGridHeight;
              // Keep short page rows at 56px; use a larger square target only
              // when it fits, without growing the grid or shrinking its agenda.
              final targetExtent =
                  fullPage && (gridHeight - weekdayHeight) / rows >= 64
                      ? 64.0
                      : 56.0;
              final gridWidth = beside
                  ? math.min(
                      fullPage ? double.infinity : 600.0,
                      math.max(
                        gridMinimumWidth,
                        math.min(
                          fullPage
                              ? (constraints.maxWidth - gap) * 0.62
                              : constraints.maxWidth * 0.56,
                          constraints.maxWidth - minimumAgendaWidth - gap,
                        ),
                      ),
                    )
                  : constraints.maxWidth;
              final drivesPage = calendarDrivesPageScroll(context);
              return ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  key: const PageStorageKey('calendar-month-agenda-outer'),
                  controller: drivesPage ? null : _outerScroll,
                  primary: drivesPage,
                  child: SizedBox(
                    height: height,
                    child: Flex(
                      key: const ValueKey('calendar-month-agenda-layout'),
                      direction: beside ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: gridWidth,
                          height: beside ? height : gridHeight,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              key:
                                  const ValueKey('calendar-compact-month-grid'),
                              height: gridHeight,
                              child: Focus(
                                key: const ValueKey('calendar-date-grid-focus'),
                                focusNode: _gridFocus,
                                // One Tab stop for the month; arrows select
                                // dates. Native buttons keep semantic actions.
                                descendantsAreFocusable: false,
                                onKeyEvent: _onGridKey,
                                onFocusChange: (_) {
                                  if (mounted) setState(() {});
                                },
                                child: _MonthGrid(
                                  days: days,
                                  columns: columns,
                                  month: widget.month,
                                  selectedDay: widget.selectedDay,
                                  events: widget.events,
                                  today: now,
                                  delegate: widget.delegate,
                                  weekdayHeight: weekdayHeight,
                                  weekNumberWidth: weekNumberWidth,
                                  badgeExtent: badgeExtent,
                                  dateFontSize: dateFontSize,
                                  targetExtent: targetExtent,
                                  focusExtent: fullPage ? 56 : 44,
                                  focused: _gridFocus.hasFocus,
                                  onSelect: _select,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: beside ? gap : 0,
                          height: beside ? 0 : gap,
                          child: Padding(
                            padding: EdgeInsetsDirectional.only(
                              start: beside ? 0 : weekNumberWidth,
                            ),
                            child: Center(
                              child: ColoredBox(
                                color: calendarPaletteOf(context).gridLine,
                                child: SizedBox(
                                  key:
                                      const ValueKey('calendar-agenda-divider'),
                                  width: beside ? 0.5 : double.infinity,
                                  height: beside ? double.infinity : 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsetsDirectional.only(
                              start: beside ? 0 : weekNumberWidth,
                            ),
                            child: _DayAgenda(
                              day: widget.selectedDay,
                              now: now,
                              events: widget.events,
                              delegate: widget.delegate,
                              controller: _agendaScroll,
                              fullPage: fullPage,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Uses the model's inclusive all-day bounds, not UTC midnight comparisons.
List<CalendarEvent> calendarEventsOnDay(
  List<CalendarEvent> events,
  DateTime day,
) =>
    events.where((event) => event.touchesDay(day)).toList()
      ..sort(compareCalendarEvents);

/// Each later event appears once. An event spanning the selected day is
/// already in that day's list, so it is not repeated under Upcoming.
List<CalendarEvent> calendarEventsAfterDay(
  List<CalendarEvent> events,
  DateTime day,
) =>
    events.where((event) => event.startDay.isAfter(startOfDay(day))).toList()
      ..sort((a, b) {
        final date = a.startDay.compareTo(b.startDay);
        return date != 0 ? date : compareCalendarEvents(a, b);
      });

String _dateKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.days,
    required this.columns,
    required this.month,
    required this.selectedDay,
    required this.events,
    required this.today,
    required this.delegate,
    required this.weekdayHeight,
    required this.weekNumberWidth,
    required this.badgeExtent,
    required this.dateFontSize,
    required this.targetExtent,
    required this.focusExtent,
    required this.focused,
    required this.onSelect,
  });

  final List<DateTime> days;
  final int columns;
  final DateTime month;
  final DateTime selectedDay;
  final List<CalendarEvent> events;
  final DateTime today;
  final CalendarViewDelegate delegate;
  final double weekdayHeight;
  final double weekNumberWidth;
  final double badgeExtent;
  final double dateFontSize;
  final double targetExtent;
  final double focusExtent;
  final bool focused;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Column(
      children: [
        SizedBox(
          height: weekdayHeight,
          child: Row(
            children: [
              if (weekNumberWidth > 0) SizedBox(width: weekNumberWidth),
              for (final day in days.take(columns))
                Expanded(
                  child: _WeekdayLabel(day: day),
                ),
            ],
          ),
        ),
        for (var row = 0; row < days.length ~/ columns; row++)
          Expanded(
            child: Row(
              key: ValueKey('calendar-compact-week-$row'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (weekNumberWidth > 0)
                  SizedBox(
                    width: weekNumberWidth,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${isoWeekNumber(days[row * columns])}',
                          key: ValueKey('calendar-week-number-$row'),
                          style: WorkspaceTypography.style(
                            context,
                            WorkspaceTextRole.caption,
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final day in days.skip(row * columns).take(columns))
                  Expanded(
                    child: _CompactDay(
                      day: day,
                      inMonth:
                          day.year == month.year && day.month == month.month,
                      today: isSameDay(day, today),
                      selected: isSameDay(day, selectedDay),
                      focused: focused,
                      badgeExtent: badgeExtent,
                      dateFontSize: dateFontSize,
                      targetExtent: targetExtent,
                      focusExtent: focusExtent,
                      events: calendarEventsOnDay(events, day),
                      delegate: delegate,
                      palette: palette,
                      onSelect: () => onSelect(day),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final style = WorkspaceTypography.style(
      context,
      WorkspaceTextRole.caption,
      color: isWeekend(day) ? palette.textMuted : palette.textSecondary,
    );
    final short = DateFormat.E().format(day);
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = TextPainter(
          text: TextSpan(text: short, style: style),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final label = text.width <= constraints.maxWidth - 4
            ? short
            : DateFormat.E().dateSymbols.NARROWWEEKDAYS[day.weekday % 7];
        text.dispose();
        return Tooltip(
          message: DateFormat.EEEE().format(day),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                key: ValueKey('calendar-weekday-${day.weekday}'),
                style: style,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactDay extends StatefulWidget {
  const _CompactDay({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.focused,
    required this.badgeExtent,
    required this.dateFontSize,
    required this.targetExtent,
    required this.focusExtent,
    required this.events,
    required this.delegate,
    required this.palette,
    required this.onSelect,
  });

  final DateTime day;
  final bool inMonth;
  final bool today;
  final bool selected;
  final bool focused;
  final double badgeExtent;
  final double dateFontSize;
  final double targetExtent;
  final double focusExtent;
  final List<CalendarEvent> events;
  final CalendarViewDelegate delegate;
  final CalendarPalette palette;
  final VoidCallback onSelect;

  @override
  State<_CompactDay> createState() => _CompactDayState();
}

class _CompactDayState extends State<_CompactDay> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final palette = widget.palette;
    final events = widget.events;
    final delegate = widget.delegate;
    final label = DateFormat.yMMMMEEEEd().format(day);
    final ink = widget.today
        ? palette.accent
        : !widget.inMonth
            ? palette.outsideMonthText
            : isWeekend(day)
                ? palette.textSecondary
                : palette.textPrimary;
    final colors = events.map(delegate.colorOf).toSet().take(3);
    final duration =
        WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration);
    return Center(
      // The native hit target is larger than the painted date, but never an
      // entire stretched column. Narrow cards can use the whole available cell.
      child: SizedBox(
        width: widget.targetExtent,
        height: widget.targetExtent,
        child: GestureDetector(
          onSecondaryTapDown: delegate.onDayMenu == null
              ? null
              : (details) => delegate.onDayMenu!(day, details.globalPosition),
          onLongPressStart: delegate.onDayMenu == null
              ? null
              : (details) => delegate.onDayMenu!(day, details.globalPosition),
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: TextButton(
                key: ValueKey('calendar-day-${_dateKey(day)}'),
                onPressed: widget.onSelect,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: ink,
                  overlayColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                ),
                child: Semantics(
                  label: label,
                  value: [
                    if (widget.today)
                      LocaleKeys.calendarView_relative_today.tr(),
                    '${LocaleKeys.calendarView_filters_events.tr()}: ${events.length}',
                  ].join(', '),
                  selected: widget.selected,
                  excludeSemantics: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: widget.focusExtent,
                            maxHeight: widget.focusExtent,
                          ),
                          child: SizedBox.expand(
                            child: AnimatedContainer(
                              key: ValueKey(
                                'calendar-day-focus-${_dateKey(day)}',
                              ),
                              duration: duration,
                              decoration: BoxDecoration(
                                color: palette.dayHover.withValues(
                                  alpha: _hovered ? palette.dayHover.a : 0,
                                ),
                                borderRadius: BorderRadius.circular(
                                  WorkspaceTokens.controlRadius,
                                ),
                                border: Border.all(
                                  width: 1.5,
                                  color: widget.selected && widget.focused
                                      ? palette.accent
                                      : palette.accent.withValues(alpha: 0),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox.square(
                            dimension: widget.badgeExtent,
                            child: AnimatedContainer(
                              key: ValueKey(
                                'calendar-day-badge-${_dateKey(day)}',
                              ),
                              duration: duration,
                              decoration: BoxDecoration(
                                color: widget.selected
                                    ? palette.daySelected
                                    : widget.today
                                        ? palette.todayWash
                                        : palette.accent.withValues(alpha: 0),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: widget.today
                                      ? palette.accent
                                      : palette.accent.withValues(alpha: 0),
                                ),
                              ),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${day.day}',
                                        maxLines: 1,
                                        softWrap: false,
                                        style: WorkspaceTypography.style(
                                          context,
                                          WorkspaceTextRole.body,
                                          color: ink,
                                        ).copyWith(
                                          fontSize: widget.dateFontSize,
                                          height: 1,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        height: 5,
                                        child: events.isEmpty
                                            ? null
                                            : Row(
                                                key: ValueKey(
                                                  'calendar-day-dots-${_dateKey(day)}',
                                                ),
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  for (final color in colors)
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 1,
                                                      ),
                                                      child: CalendarColorDot(
                                                        color: color,
                                                        size: 3,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.day,
    required this.now,
    required this.events,
    required this.delegate,
    required this.controller,
    required this.fullPage,
  });

  final DateTime day;
  final DateTime now;
  final List<CalendarEvent> events;
  final CalendarViewDelegate delegate;
  final ScrollController controller;
  final bool fullPage;

  @override
  Widget build(BuildContext context) {
    final selected = calendarEventsOnDay(events, day);
    final upcoming = calendarEventsAfterDay(events, day);
    final count = math.max(selected.length, 1);
    final heading = calendarAgendaDayLabel(day, now);
    final palette = calendarPaletteOf(context);
    final indexByKey = <String, int>{
      for (var index = 0; index < selected.length; index++)
        'calendar-agenda-event-${selected[index].id}': index,
      for (var index = 0; index < upcoming.length; index++)
        'calendar-agenda-event-${upcoming[index].id}': count + 1 + index,
    };
    return Column(
      key: const ValueKey('calendar-day-agenda'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          // Removing an editing affordance must not move the first event.
          constraints:
              const BoxConstraints(minHeight: CalendarMetrics.controlSize),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    heading,
                    key: const ValueKey('calendar-selected-day'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.cardTitle,
                    ),
                  ),
                ),
              ),
              if (delegate.canEdit && delegate.onCreateAt != null)
                CalendarControlButton(
                  key: const ValueKey('calendar-agenda-add'),
                  icon: Icons.add_rounded,
                  tooltip: LocaleKeys.calendarView_newEvent.tr(),
                  onPressed: () => delegate.onCreateAt!(day, hasTime: false),
                ),
            ],
          ),
        ),
        const SizedBox(height: WorkspaceTokens.space1),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey('calendar-day-agenda-scroll'),
            controller: controller,
            primary: false,
            padding: EdgeInsets.zero,
            itemCount: count + (upcoming.isEmpty ? 0 : upcoming.length + 1),
            findChildIndexCallback: (key) =>
                key is ValueKey<String> ? indexByKey[key.value] : null,
            itemBuilder: (context, index) {
              if (index < count) {
                if (selected.isEmpty) {
                  return ConstrainedBox(
                    key: const ValueKey('calendar-empty-day'),
                    constraints: BoxConstraints(minHeight: fullPage ? 48 : 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: WorkspaceTokens.space2,
                      ),
                      child: Row(
                        children: [
                          WorkspaceGlyph.named(
                            'calendar-blank',
                            size: 20,
                            color: palette.textMuted,
                          ),
                          const SizedBox(width: WorkspaceTokens.space2),
                          Expanded(
                            child: Text(
                              LocaleKeys.calendarView_empty_selectedDay.tr(),
                              style: WorkspaceTypography.style(
                                context,
                                WorkspaceTextRole.metadata,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return _CompactEvent(
                  key: ValueKey('calendar-agenda-event-${selected[index].id}'),
                  event: selected[index],
                  delegate: delegate,
                  showDate: false,
                  now: now,
                  fullPage: fullPage,
                );
              }
              if (index == count) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: WorkspaceTokens.space2,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      LocaleKeys.calendarView_upcoming.tr(),
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.caption,
                      ),
                    ),
                  ),
                );
              }
              final event = upcoming[index - count - 1];
              return _CompactEvent(
                key: ValueKey('calendar-agenda-event-${event.id}'),
                event: event,
                delegate: delegate,
                showDate: true,
                now: now,
                fullPage: fullPage,
              );
            },
          ),
        ),
      ],
    );
  }
}

String calendarAgendaDayLabel(DateTime day, DateTime now) {
  final relative = switch (daysBetween(startOfDay(now), startOfDay(day))) {
    0 => LocaleKeys.calendarView_relative_today.tr(),
    1 => LocaleKeys.calendarView_relative_tomorrow.tr(),
    -1 => LocaleKeys.calendarView_relative_yesterday.tr(),
    _ => DateFormat.EEEE().format(day),
  };
  return '$relative · ${DateFormat.MMMd().format(day)}';
}

/// Localized real start/end times; no placeholder duration or inferred event.
String calendarAgendaTimeLabel(BuildContext context, CalendarEvent event) {
  if (event.isAllDay) return LocaleKeys.calendarView_allDay.tr();
  String time(DateTime value) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(value),
        alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
      );
  final start = event.start.local;
  final end = event.end?.local;
  if (end == null) return time(start);
  if (event.spansDays) {
    return '${DateFormat.MMMd().format(start)} ${time(start)} – '
        '${DateFormat.MMMd().format(end)} ${time(end)}';
  }
  return '${time(start)}–${time(end)}';
}

class _CompactEvent extends StatelessWidget {
  const _CompactEvent({
    super.key,
    required this.event,
    required this.delegate,
    required this.showDate,
    required this.now,
    required this.fullPage,
  });

  final CalendarEvent event;
  final CalendarViewDelegate delegate;
  final bool showDate;
  final DateTime now;
  final bool fullPage;

  void _menu(BuildContext context, [Offset? position]) {
    final box = context.findRenderObject() as RenderBox?;
    delegate.onEventMenu?.call(
      event,
      position ??
          (box == null || !box.hasSize
              ? Offset.zero
              : box.localToGlobal(box.size.center(Offset.zero))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final title = event.title.isEmpty
        ? LocaleKeys.calendar_defaultNewCalendarTitle.tr()
        : event.title;
    final time = calendarAgendaTimeLabel(context, event);
    final metadata = showDate
        ? '${calendarAgendaDayLabel(event.startDay, now)} · $time'
        : time;
    final canComplete = delegate.allowsEditing(event) &&
        event.kind != CalendarEventKind.event &&
        delegate.onToggleComplete != null;
    return CallbackShortcuts(
      bindings: {
        if (delegate.onEventMenu != null) ...{
          const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
              _menu(context),
          const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
              _menu(context),
        },
      },
      child: GestureDetector(
        onSecondaryTapDown: delegate.onEventMenu == null
            ? null
            : (details) => _menu(context, details.globalPosition),
        onLongPressStart: delegate.onEventMenu == null
            ? null
            : (details) => _menu(context, details.globalPosition),
        child: Row(
          children: [
            CalendarColorDot(color: delegate.colorOf(event), size: 5),
            const SizedBox(width: WorkspaceTokens.space1),
            Expanded(
              child: Tooltip(
                message: '$title\n$metadata',
                excludeFromSemantics: true,
                child: TextButton(
                  onPressed: delegate.onOpenEvent == null
                      ? null
                      : () => delegate.onOpenEvent!(event),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WorkspaceTokens.space1,
                      vertical: 2,
                    ),
                    minimumSize: Size(0, fullPage ? 48 : 40),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: AlignmentDirectional.centerStart,
                    foregroundColor: palette.textPrimary,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.body,
                          color: event.isCompleted
                              ? palette.completedInk
                              : palette.textPrimary,
                        ).copyWith(
                          fontSize: fullPage ? 16 : 14,
                          height: 1.25,
                          decoration: event.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.metadata,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (canComplete)
              CalendarControlButton(
                key: ValueKey('calendar-agenda-complete-${event.id}'),
                icon: event.isCompleted
                    ? Icons.check_rounded
                    : Icons.radio_button_unchecked_rounded,
                tooltip: event.isCompleted
                    ? LocaleKeys.reminders_markNotDone.tr()
                    : LocaleKeys.reminders_markDone.tr(),
                onPressed: () => delegate.onToggleComplete!(event),
              ),
          ],
        ),
      ),
    );
  }
}
