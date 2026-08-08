import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Twelve months at once, each day carrying how busy it is.
///
/// A year cannot show events, so it shows *density*: the dot under a date
/// grows with the number of things on that day. Clicking a day opens it,
/// clicking a month heading opens the month.
class CalendarYearView extends StatelessWidget {
  const CalendarYearView({
    super.key,
    required this.year,
    required this.events,
    required this.delegate,
    required this.onOpenMonth,
    required this.onOpenDay,
    this.firstDayOfWeek = DateTime.monday,
  });

  final int year;
  final List<CalendarEvent> events;
  final CalendarViewDelegate delegate;
  final ValueChanged<DateTime> onOpenMonth;
  final ValueChanged<DateTime> onOpenDay;
  final int firstDayOfWeek;

  @override
  Widget build(BuildContext context) {
    final counts = countEventsPerDay(events);
    final busiest = counts.values.fold<int>(0, (a, b) => a > b ? a : b);

    return CalendarScrollScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Three across on a narrow window, four normally, six when there is
          // room — a mini month below ~180px stops being readable.
          final columns = constraints.maxWidth >= 1180
              ? 6
              : constraints.maxWidth >= 780
                  ? 4
                  : constraints.maxWidth >= 520
                      ? 3
                      : 2;
          return GridView.builder(
            primary: calendarDrivesPageScroll(context) ? true : null,
            padding: const EdgeInsets.fromLTRB(
              CalendarMetrics.space4,
              CalendarMetrics.space2,
              CalendarMetrics.space4,
              CalendarMetrics.space6,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: CalendarMetrics.space4,
              crossAxisSpacing: CalendarMetrics.space4,
              childAspectRatio: 0.92,
            ),
            itemCount: 12,
            itemBuilder: (context, index) => _MiniMonth(
              month: DateTime(year, index + 1),
              counts: counts,
              busiest: busiest,
              firstDayOfWeek: firstDayOfWeek,
              onOpenMonth: onOpenMonth,
              onOpenDay: onOpenDay,
            ),
          );
        },
      ),
    );
  }
}

/// How many things fall on each day, so a year can show where the work is.
///
/// Pure, so the density can be checked without drawing anything.
Map<DateTime, int> countEventsPerDay(List<CalendarEvent> events) {
  final counts = <DateTime, int>{};
  for (final event in events) {
    var day = event.startDay;
    final last = event.endDay;
    var guard = 0;
    while (!day.isAfter(last) && guard < 400) {
      counts.update(day, (value) => value + 1, ifAbsent: () => 1);
      day = day.add(const Duration(days: 1));
      guard++;
    }
  }
  return counts;
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.month,
    required this.counts,
    required this.busiest,
    required this.firstDayOfWeek,
    required this.onOpenMonth,
    required this.onOpenDay,
  });

  final DateTime month;
  final Map<DateTime, int> counts;
  final int busiest;
  final int firstDayOfWeek;
  final ValueChanged<DateTime> onOpenMonth;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final days = monthGridDays(month, firstDayOfWeek: firstDayOfWeek);
    final headings = weekDays(days.first, firstDayOfWeek: firstDayOfWeek);
    final today = startOfDay(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthHeading(
          month: month,
          isThisMonth: month.year == today.year && month.month == today.month,
          onTap: () => onOpenMonth(month),
        ),
        const SizedBox(height: CalendarMetrics.space2),
        Row(
          children: [
            for (final day in headings)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat.E().format(day).substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      height: 1,
                      color: palette.textMuted.withValues(alpha: 0.7),
                      fontVariations: const [FontVariation.weight(620)],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        // Rows that divide the box exactly: a nested grid would clip the last
        // week whenever the tile is a pixel short.
        Expanded(
          child: Column(
            children: [
              for (var row = 0; row * 7 < days.length; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (final day in days.skip(row * 7).take(7))
                        Expanded(
                          child: _MiniDay(
                            day: day,
                            inMonth: day.month == month.month,
                            isToday: isSameDay(day, today),
                            count: counts[day] ?? 0,
                            busiest: busiest,
                            onTap: () => onOpenDay(day),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthHeading extends StatefulWidget {
  const _MonthHeading({
    required this.month,
    required this.isThisMonth,
    required this.onTap,
  });

  final DateTime month;
  final bool isThisMonth;
  final VoidCallback onTap;

  @override
  State<_MonthHeading> createState() => _MonthHeadingState();
}

class _MonthHeadingState extends State<_MonthHeading> {
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
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: CalendarMetrics.hover,
            curve: CalendarMetrics.hoverCurve,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: palette.hover.withValues(alpha: _hovered ? 1 : 0),
              borderRadius:
                  BorderRadius.circular(CalendarMetrics.controlRadius),
            ),
            child: Text(
              DateFormat.MMMM().format(widget.month),
              style: TextStyle(
                fontSize: 12.5,
                height: 1,
                letterSpacing: -0.15,
                color:
                    widget.isThisMonth ? palette.accent : palette.textPrimary,
                fontVariations: [
                  FontVariation.weight(widget.isThisMonth ? 670 : 600),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniDay extends StatefulWidget {
  const _MiniDay({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.count,
    required this.busiest,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final int count;
  final int busiest;
  final VoidCallback onTap;

  @override
  State<_MiniDay> createState() => _MiniDayState();
}

class _MiniDayState extends State<_MiniDay> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    // A day with nothing on it shows no dot at all; the busiest day in the
    // year sets the top of the scale, so the picture is relative to the work.
    final weight = widget.busiest == 0
        ? 0.0
        : (widget.count / widget.busiest).clamp(0.0, 1.0);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: widget.count == 0
              ? DateFormat.yMMMd().format(widget.day)
              : '${DateFormat.yMMMd().format(widget.day)} · ${widget.count}',
          waitDuration: const Duration(milliseconds: 500),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: CalendarMetrics.hover,
                  curve: CalendarMetrics.hoverCurve,
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.isToday
                        ? palette.todayBadge
                        : palette.hover.withValues(alpha: _hovered ? 1 : 0),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${widget.day.day}',
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1,
                      color: widget.isToday
                          ? palette.todayBadgeText
                          : widget.inMonth
                              ? palette.textSecondary
                              : palette.outsideMonthText,
                      fontVariations: [
                        FontVariation.weight(widget.isToday ? 660 : 550),
                      ],
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 4,
                  width: 6,
                  child: widget.count == 0
                      ? null
                      : Center(
                          child: Container(
                            width: 3 + weight * 3,
                            height: 3 + weight * 3,
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(
                                alpha: 0.45 + weight * 0.55,
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
