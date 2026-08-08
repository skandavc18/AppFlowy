import 'dart:math' as math;

import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_chip.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// What the calendar hands each view so it can draw and act.
///
/// One object rather than a dozen callbacks per view, so adding an interaction
/// does not mean editing four constructors.
class CalendarViewDelegate {
  const CalendarViewDelegate({
    required this.colorOf,
    this.onOpenEvent,
    this.onEventMenu,
    this.onCreateAt,
    this.onReschedule,
    this.onToggleComplete,
    this.onShowMore,
    this.canEdit = true,
  });

  /// The colour an event is drawn in: its own, else its calendar's.
  final Color Function(CalendarEvent) colorOf;

  final void Function(CalendarEvent)? onOpenEvent;
  final void Function(CalendarEvent, Offset globalPosition)? onEventMenu;

  /// Somebody asked for a new event at this moment. [hasTime] is false when
  /// they clicked a day rather than an hour.
  final void Function(DateTime at, {bool hasTime})? onCreateAt;

  /// A drag finished. [end] is null when only the start moved.
  final void Function(CalendarEvent event, DateTime start, DateTime? end)?
      onReschedule;

  final void Function(CalendarEvent)? onToggleComplete;

  /// "+3 more" was clicked.
  final void Function(DateTime day)? onShowMore;

  final bool canEdit;
}

/// The month grid.
///
/// Structure comes from whitespace and one hairline, never from boxes: a cell
/// has no border of its own, weekends are a wash, and today is a filled date
/// badge rather than an outlined cell.
class CalendarMonthView extends StatefulWidget {
  const CalendarMonthView({
    super.key,
    required this.month,
    required this.events,
    required this.delegate,
    this.firstDayOfWeek = DateTime.monday,
    this.showWeekends = true,
    this.showWeekNumbers = false,
    this.selectedDay,
    this.onSelectDay,
    this.emptyBuilder,
  });

  final DateTime month;
  final List<CalendarEvent> events;
  final CalendarViewDelegate delegate;
  final int firstDayOfWeek;
  final bool showWeekends;
  final bool showWeekNumbers;
  final DateTime? selectedDay;
  final ValueChanged<DateTime>? onSelectDay;
  final WidgetBuilder? emptyBuilder;

  @override
  State<CalendarMonthView> createState() => _CalendarMonthViewState();
}

class _CalendarMonthViewState extends State<CalendarMonthView> {
  /// Which day a drag is currently over, and what is being dragged.
  ///
  /// ⚠️ This is a notifier rather than `setState` on purpose. Rebuilding the
  /// month while a `Draggable` still owns the gesture re-parents that subtree
  /// mid-drag, which is what trips `_InactiveElements.remove` in framework.dart.
  final ValueNotifier<_MonthDrag?> _drag = ValueNotifier<_MonthDrag?>(null);

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final days = monthGridDays(
      widget.month,
      firstDayOfWeek: widget.firstDayOfWeek,
      showWeekends: widget.showWeekends,
    );
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

    final columns = weekdayOrder(
      widget.firstDayOfWeek,
      showWeekends: widget.showWeekends,
    ).length;
    final rows = (days.length / columns).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekdayStrip(
          days: days.take(columns).toList(),
          showWeekNumbers: widget.showWeekNumbers,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rowHeight = (constraints.maxHeight / rows)
                  .clamp(CalendarMetrics.monthCellMinHeight, 400.0);
              // The grid is ALWAYS inside one scroll view. Adding and removing
              // a scroll view depending on whether the month happens to fit
              // re-parents the whole grid between frames, and it is also why a
              // squashed month could not be scrolled at all.
              return CalendarScrollScope(
                child: SingleChildScrollView(
                  primary: calendarDrivesPageScroll(context) ? true : null,
                  child: SizedBox(
                    height: math.max(rowHeight * rows, constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var row = 0; row < rows; row++)
                          SizedBox(
                            height: rowHeight,
                            child: _WeekRow(
                              days: days
                                  .skip(row * columns)
                                  .take(columns)
                                  .toList(growable: false),
                              events: widget.events,
                              month: widget.month,
                              delegate: widget.delegate,
                              palette: palette,
                              rowHeight: rowHeight,
                              showWeekNumbers: widget.showWeekNumbers,
                              selectedDay: widget.selectedDay,
                              onSelectDay: widget.onSelectDay,
                              drag: _drag,
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
      ],
    );
  }
}

/// What a month drag is over, so only the cells under the pointer repaint.
@immutable
class _MonthDrag {
  const _MonthDrag(this.day, this.event);

  final DateTime day;
  final CalendarEvent event;
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip({required this.days, required this.showWeekNumbers});

  final List<DateTime> days;
  final bool showWeekNumbers;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final format = DateFormat.E();
    return SizedBox(
      height: CalendarMetrics.weekdayStripHeight,
      child: Row(
        children: [
          if (showWeekNumbers) const SizedBox(width: CalendarMetrics.space5),
          for (final day in days)
            Expanded(
              child: Center(
                child: Text(
                  format.format(day).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1,
                    letterSpacing: 0.6,
                    color: isWeekend(day)
                        ? palette.textMuted.withValues(alpha: 0.72)
                        : palette.textMuted,
                    fontVariations: const [FontVariation.weight(620)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.days,
    required this.events,
    required this.month,
    required this.delegate,
    required this.palette,
    required this.rowHeight,
    required this.showWeekNumbers,
    required this.selectedDay,
    required this.onSelectDay,
    required this.drag,
  });

  final List<DateTime> days;
  final List<CalendarEvent> events;
  final DateTime month;
  final CalendarViewDelegate delegate;
  final CalendarPalette palette;
  final double rowHeight;
  final bool showWeekNumbers;
  final DateTime? selectedDay;
  final ValueChanged<DateTime>? onSelectDay;
  final ValueNotifier<_MonthDrag?> drag;

  @override
  Widget build(BuildContext context) {
    // How many chips fit under the date band, leaving room for "+N more".
    final usable = rowHeight -
        CalendarMetrics.monthDateBandHeight -
        CalendarMetrics.space1;
    final slots = (usable /
            (CalendarMetrics.monthChipHeight + CalendarMetrics.monthChipGap))
        .floor()
        .clamp(0, 8);

    final layout = layOutMonthWeek(days, events, maxLanes: slots);
    final needsMore = layout.overflow.isNotEmpty;
    final lanes = needsMore ? (slots - 1).clamp(0, slots) : slots;
    final finalLayout =
        needsMore ? layOutMonthWeek(days, events, maxLanes: lanes) : layout;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.weekLine, width: 0.7),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showWeekNumbers)
            SizedBox(
              width: CalendarMetrics.space5,
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  '${isoWeekNumber(days.first)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1,
                    color: palette.textMuted.withValues(alpha: 0.6),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth = constraints.maxWidth / days.length;
                return Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < days.length; i++)
                          Expanded(
                            child: _DayCell(
                              day: days[i],
                              month: month,
                              palette: palette,
                              delegate: delegate,
                              isFirstColumn: i == 0,
                              selected: selectedDay != null &&
                                  isSameDay(selectedDay!, days[i]),
                              overflow: finalLayout.overflowAt(i),
                              onSelect: onSelectDay,
                              drag: drag,
                            ),
                          ),
                      ],
                    ),
                    for (final bar in finalLayout.bars)
                      Positioned(
                        left: bar.startColumn * columnWidth + 2,
                        width: bar.columnSpan * columnWidth - 4,
                        top: CalendarMetrics.monthDateBandHeight +
                            bar.lane *
                                (CalendarMetrics.monthChipHeight +
                                    CalendarMetrics.monthChipGap),
                        height: CalendarMetrics.monthChipHeight,
                        child: _MonthBar(
                          bar: bar,
                          delegate: delegate,
                          drag: drag,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.bar,
    required this.delegate,
    required this.drag,
  });

  final MonthEventBar bar;
  final CalendarViewDelegate delegate;
  final ValueNotifier<_MonthDrag?> drag;

  @override
  Widget build(BuildContext context) {
    final event = bar.event;
    final colour = delegate.colorOf(event);
    final chip = ValueListenableBuilder<_MonthDrag?>(
      valueListenable: drag,
      builder: (context, value, _) => CalendarEventChip(
        event: event,
        color: colour,
        continuesBefore: bar.continuesBefore,
        continuesAfter: bar.continuesAfter,
        showTime: !event.isAllDay && bar.columnSpan == 1,
        dimmed: value != null && value.event.id == event.id,
        onTap: delegate.onOpenEvent == null
            ? null
            : () => delegate.onOpenEvent!(event),
        onSecondaryTap: delegate.onEventMenu == null
            ? null
            : (position) => delegate.onEventMenu!(event, position),
      ),
    );

    if (!delegate.canEdit || event.readOnly) {
      return chip;
    }

    return Draggable<CalendarEvent>(
      data: event,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragGhost(event: event, color: colour),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      onDragEnd: (_) => drag.value = null,
      onDraggableCanceled: (_, __) => drag.value = null,
      child: chip,
    );
  }
}

class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.event, required this.color});

  final CalendarEvent event;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Transform.translate(
      offset: const Offset(-70, -12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 160,
          height: CalendarMetrics.monthChipHeight + 3,
          decoration: BoxDecoration(
            color: palette.eventSurfaceHovered(color),
            borderRadius: BorderRadius.circular(CalendarMetrics.chipRadius),
            boxShadow: palette.eventShadow(raised: true),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Container(width: 2.5, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1,
                    color: palette.eventInk(color),
                    fontVariations: const [FontVariation.weight(600)],
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.day,
    required this.month,
    required this.palette,
    required this.delegate,
    required this.isFirstColumn,
    required this.selected,
    required this.overflow,
    required this.onSelect,
    required this.drag,
  });

  final DateTime day;
  final DateTime month;
  final CalendarPalette palette;
  final CalendarViewDelegate delegate;
  final bool isFirstColumn;
  final bool selected;
  final int overflow;
  final ValueChanged<DateTime>? onSelect;
  final ValueNotifier<_MonthDrag?> drag;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final day = widget.day;
    final today = isSameDay(day, DateTime.now());
    final inMonth =
        day.month == widget.month.month && day.year == widget.month.year;

    return DragTarget<CalendarEvent>(
      onWillAcceptWithDetails: (details) {
        widget.drag.value = _MonthDrag(day, details.data);
        return true;
      },
      onLeave: (_) {
        if (widget.drag.value?.day == day) {
          widget.drag.value = null;
        }
      },
      onAcceptWithDetails: (details) {
        widget.drag.value = null;
        final event = details.data;
        final delta = daysBetween(event.startDay, day);
        if (delta == 0) {
          return;
        }
        final start = event.start.local.add(Duration(days: delta));
        final end = event.end?.local.add(Duration(days: delta));
        widget.delegate.onReschedule?.call(event, start, end);
      },
      builder: (context, candidate, rejected) {
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSelect?.call(day),
            onDoubleTap: widget.delegate.onCreateAt == null
                ? null
                : () => widget.delegate.onCreateAt!(day, hasTime: false),
            child: ValueListenableBuilder<_MonthDrag?>(
              valueListenable: widget.drag,
              builder: (context, drag, child) {
                final isDropTarget = drag != null && isSameDay(drag.day, day);
                return AnimatedContainer(
                  duration: CalendarMetrics.hover,
                  curve: CalendarMetrics.hoverCurve,
                  decoration: BoxDecoration(
                    color: isDropTarget
                        ? palette.dropTarget
                        : today
                            ? palette.todayWash
                            : isWeekend(day)
                                ? palette.weekendWash
                                : Colors.transparent,
                    border: widget.isFirstColumn
                        ? null
                        : Border(
                            left:
                                BorderSide(color: palette.gridLine, width: 0.7),
                          ),
                  ),
                  child: child,
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: CalendarMetrics.monthDateBandHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 4, 0),
                      child: Row(
                        children: [
                          _DateBadge(
                            day: day,
                            today: today,
                            inMonth: inMonth,
                            selected: widget.selected,
                            palette: palette,
                          ),
                          const Spacer(),
                          if (_hovered &&
                              widget.delegate.onCreateAt != null &&
                              widget.delegate.canEdit)
                            _AddButton(
                              onTap: () => widget.delegate.onCreateAt!(
                                day,
                                hasTime: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.overflow > 0)
                    _MoreRow(
                      count: widget.overflow,
                      onTap: () => widget.delegate.onShowMore?.call(day),
                    ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({
    required this.day,
    required this.today,
    required this.inMonth,
    required this.selected,
    required this.palette,
  });

  final DateTime day;
  final bool today;
  final bool inMonth;
  final bool selected;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    // The first day of a month names itself, which is what stops a grid of
    // bare numbers reading as a spreadsheet.
    final label = day.day == 1 ? DateFormat.MMMd().format(day) : '${day.day}';

    return AnimatedContainer(
      duration: CalendarMetrics.change,
      curve: CalendarMetrics.hoverCurve,
      height: 19,
      padding: EdgeInsets.symmetric(horizontal: today || selected ? 7 : 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: today
            ? palette.todayBadge
            : selected
                ? palette.accent.withValues(alpha: 0.14)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(CalendarMetrics.pillRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          height: 1,
          letterSpacing: -0.1,
          color: today
              ? palette.todayBadgeText
              : inMonth
                  ? palette.textPrimary
                  : palette.outsideMonthText,
          fontVariations: [
            FontVariation.weight(today || day.day == 1 ? 660 : 570),
          ],
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: palette.hover,
            borderRadius: BorderRadius.circular(6),
          ),
          child:
              Icon(Icons.add_rounded, size: 13, color: palette.textSecondary),
        ),
      ),
    );
  }
}

class _MoreRow extends StatefulWidget {
  const _MoreRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  State<_MoreRow> createState() => _MoreRowState();
}

class _MoreRowState extends State<_MoreRow> {
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
        child: Container(
          height: CalendarMetrics.monthChipHeight - 3,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: palette.hover.withValues(alpha: _hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(CalendarMetrics.chipRadius),
          ),
          child: Text(
            '+${widget.count}',
            style: TextStyle(
              fontSize: 10.5,
              height: 1,
              color: palette.textMuted,
              fontVariations: const [FontVariation.weight(620)],
            ),
          ),
        ),
      ),
    );
  }
}
