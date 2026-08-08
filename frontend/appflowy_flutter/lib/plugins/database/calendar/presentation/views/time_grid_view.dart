import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_chip.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The week and day readings: a time grid with a live "now" line.
///
/// Week and day are the same widget with a different number of columns —
/// splitting them would mean maintaining the drag, the overlap layout and the
/// now line twice.
class CalendarTimeGridView extends StatefulWidget {
  const CalendarTimeGridView({
    super.key,
    required this.days,
    required this.events,
    required this.delegate,
    this.hourHeight = CalendarMetrics.hourHeight,
    this.scrollToHour = 8,
  });

  final List<DateTime> days;
  final List<CalendarEvent> events;
  final CalendarViewDelegate delegate;
  final double hourHeight;

  /// Where the grid opens, so a day does not start at midnight.
  final int scrollToHour;

  @override
  State<CalendarTimeGridView> createState() => _CalendarTimeGridViewState();
}

class _CalendarTimeGridViewState extends State<CalendarTimeGridView> {
  final ScrollController _scroll = ScrollController();
  Timer? _nowTimer;
  DateTime _now = DateTime.now();

  /// The live preview while something is being dragged or resized.
  _GridDrag? _drag;

  @override
  void initState() {
    super.initState();
    _nowTimer = Timer.periodic(
      CalendarMetrics.nowTick,
      (_) {
        if (mounted) {
          setState(() => _now = DateTime.now());
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealOpeningHour());
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _revealOpeningHour() {
    if (!_scroll.hasClients) {
      return;
    }
    final target = widget.scrollToHour * widget.hourHeight;
    _scroll.jumpTo(math.min(target, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final allDay = <DateTime, List<CalendarEvent>>{
      for (final day in widget.days)
        day:
            widget.events.where((e) => e.isAllDay && e.touchesDay(day)).toList()
              ..sort(compareCalendarEvents),
    };
    final allDayRows = allDay.values
        .map((e) => e.length)
        .fold<int>(0, math.max)
        .clamp(0, CalendarMetrics.allDayMaxRows.toInt());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayHeaderStrip(days: widget.days, now: _now),
        if (allDayRows > 0)
          _AllDayStrip(
            days: widget.days,
            byDay: allDay,
            rows: allDayRows,
            delegate: widget.delegate,
          ),
        Container(height: 0.7, color: palette.weekLine),
        Expanded(
          child: CalendarScrollScope(
            child: SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: widget.hourHeight * 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TimeGutter(hourHeight: widget.hourHeight, now: _now),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _HourLinesPainter(
                                  hourHeight: widget.hourHeight,
                                  line: palette.gridLine,
                                  halfLine:
                                      palette.gridLine.withValues(alpha: 0.42),
                                  columns: widget.days.length,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final day in widget.days)
                                Expanded(
                                  child: _DayColumn(
                                    day: day,
                                    events: widget.events,
                                    delegate: widget.delegate,
                                    hourHeight: widget.hourHeight,
                                    now: _now,
                                    drag: _drag,
                                    onDrag: (next) =>
                                        setState(() => _drag = next),
                                  ),
                                ),
                            ],
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
      ],
    );
  }
}

/// What a live drag is doing, so the preview and the commit agree.
@immutable
class _GridDrag {
  const _GridDrag({
    required this.event,
    required this.start,
    required this.end,
  });

  final CalendarEvent event;
  final DateTime start;
  final DateTime end;
}

class _DayHeaderStrip extends StatelessWidget {
  const _DayHeaderStrip({required this.days, required this.now});

  final List<DateTime> days;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: CalendarMetrics.timeGutterWidth),
          for (final day in days)
            Expanded(
              child: _DayHeader(day: day, today: isSameDay(day, now)),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.today});

  final DateTime day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          DateFormat.E().format(day).toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            height: 1,
            letterSpacing: 0.65,
            color: today ? palette.accent : palette.textMuted,
            fontVariations: const [FontVariation.weight(620)],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 22,
          width: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: today ? palette.todayBadge : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 13,
              height: 1,
              color: today ? palette.todayBadgeText : palette.textPrimary,
              fontVariations: [FontVariation.weight(today ? 660 : 570)],
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _AllDayStrip extends StatelessWidget {
  const _AllDayStrip({
    required this.days,
    required this.byDay,
    required this.rows,
    required this.delegate,
  });

  final List<DateTime> days;
  final Map<DateTime, List<CalendarEvent>> byDay;
  final int rows;
  final CalendarViewDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: CalendarMetrics.timeGutterWidth),
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final event in byDay[day]!.take(rows))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: SizedBox(
                          height: CalendarMetrics.allDayRowHeight,
                          child: CalendarEventChip(
                            event: event,
                            color: delegate.colorOf(event),
                            showTime: false,
                            continuesBefore: event.startDay.isBefore(day),
                            continuesAfter: event.endDay.isAfter(day),
                            onTap: delegate.onOpenEvent == null
                                ? null
                                : () => delegate.onOpenEvent!(event),
                            onSecondaryTap: delegate.onEventMenu == null
                                ? null
                                : (p) => delegate.onEventMenu!(event, p),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeGutter extends StatelessWidget {
  const _TimeGutter({required this.hourHeight, required this.now});

  final double hourHeight;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final usesMeridiem = (DateFormat.jm().pattern ?? '').contains('a');
    return SizedBox(
      width: CalendarMetrics.timeGutterWidth,
      child: Stack(
        children: [
          for (var hour = 1; hour < 24; hour++)
            Positioned(
              top: hour * hourHeight - 6,
              right: 10,
              child: Text(
                usesMeridiem
                    ? DateFormat('h a').format(DateTime(2020, 1, 1, hour))
                    : DateFormat('HH:mm').format(DateTime(2020, 1, 1, hour)),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  color: palette.textMuted.withValues(alpha: 0.85),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          Positioned(
            top: (now.hour * 60 + now.minute) / 60 * hourHeight - 7,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: palette.nowLine,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                calendarShortTime(now),
                style: const TextStyle(
                  fontSize: 9.5,
                  height: 1,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontVariations: [FontVariation.weight(640)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourLinesPainter extends CustomPainter {
  const _HourLinesPainter({
    required this.hourHeight,
    required this.line,
    required this.halfLine,
    required this.columns,
  });

  final double hourHeight;
  final Color line;
  final Color halfLine;
  final int columns;

  @override
  void paint(Canvas canvas, Size size) {
    final hour = Paint()
      ..color = line
      ..strokeWidth = 0.7;
    final half = Paint()
      ..color = halfLine
      ..strokeWidth = 0.5;

    for (var i = 1; i < 24; i++) {
      final y = i * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hour);
      // The half-hour rule only appears once an hour is tall enough that it
      // helps rather than crowds.
      if (hourHeight >= 44) {
        final mid = y + hourHeight / 2;
        if (mid < size.height) {
          canvas.drawLine(Offset(0, mid), Offset(size.width, mid), half);
        }
      }
    }

    if (columns > 1) {
      final column = Paint()
        ..color = line
        ..strokeWidth = 0.7;
      final width = size.width / columns;
      for (var i = 1; i < columns; i++) {
        canvas.drawLine(
          Offset(i * width, 0),
          Offset(i * width, size.height),
          column,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HourLinesPainter old) =>
      old.hourHeight != hourHeight ||
      old.line != line ||
      old.halfLine != halfLine ||
      old.columns != columns;
}

class _DayColumn extends StatefulWidget {
  const _DayColumn({
    required this.day,
    required this.events,
    required this.delegate,
    required this.hourHeight,
    required this.now,
    required this.drag,
    required this.onDrag,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final CalendarViewDelegate delegate;
  final double hourHeight;
  final DateTime now;
  final _GridDrag? drag;
  final ValueChanged<_GridDrag?> onDrag;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  DateTime? _pendingSlot;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final today = isSameDay(widget.day, widget.now);
    final placements = layOutDayColumn(widget.day, _eventsWithPreview());

    return DragTarget<CalendarEvent>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) {
          return;
        }
        final event = details.data;
        final local = box.globalToLocal(details.offset);
        final start = snapToSlot(
          widget.day,
          local.dy / widget.hourHeight * 60,
        );
        final length =
            event.hasDuration ? event.duration : const Duration(hours: 1);
        widget.delegate.onReschedule?.call(event, start, start.add(length));
      },
      builder: (context, candidate, rejected) => LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: widget.delegate.onCreateAt == null
              ? null
              : (details) => _pendingSlot = snapToSlot(
                    widget.day,
                    details.localPosition.dy / widget.hourHeight * 60,
                    snapMinutes: 30,
                  ),
          onDoubleTap: widget.delegate.onCreateAt == null
              ? null
              : () {
                  final at = _pendingSlot;
                  if (at != null) {
                    widget.delegate.onCreateAt!(at, hasTime: true);
                  }
                },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (today)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: palette.todayWash),
                  ),
                ),
              for (final placement in placements)
                _place(placement, constraints.maxWidth),
              if (today) _nowLine(palette),
            ],
          ),
        ),
      ),
    );
  }

  /// The day's events with any live drag already applied, so neighbours part
  /// around the preview rather than jumping when it lands.
  List<CalendarEvent> _eventsWithPreview() {
    final drag = widget.drag;
    final base = widget.events.where((e) => !e.isAllDay);
    if (drag == null) {
      return base.toList();
    }
    final events = <CalendarEvent>[];
    var placed = false;
    for (final event in base) {
      if (event.id != drag.event.id) {
        events.add(event);
        continue;
      }
      placed = true;
      events.add(
        event.copyWith(
          start: ZonedDateTime.local(drag.start),
          end: ZonedDateTime.local(drag.end),
        ),
      );
    }
    if (!placed && isSameDay(drag.start, widget.day)) {
      events.add(
        drag.event.copyWith(
          start: ZonedDateTime.local(drag.start),
          end: ZonedDateTime.local(drag.end),
        ),
      );
    }
    return events;
  }

  Widget _place(TimeGridPlacement placement, double width) {
    final top = placement.startMinutes / 60 * widget.hourHeight;
    final height = math.max(
      placement.durationMinutes / 60 * widget.hourHeight,
      CalendarMetrics.minimumEventHeight,
    );
    return Positioned(
      top: top,
      left: placement.left * width + CalendarMetrics.overlapInset,
      width: math.max(
        placement.width * width - CalendarMetrics.overlapInset * 2,
        24,
      ),
      height: height,
      child: _TimedEvent(
        placement: placement,
        delegate: widget.delegate,
        hourHeight: widget.hourHeight,
        onDrag: widget.onDrag,
      ),
    );
  }

  Widget _nowLine(CalendarPalette palette) {
    final minutes = widget.now.hour * 60 + widget.now.minute;
    return Positioned(
      top: minutes / 60 * widget.hourHeight - 1,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: palette.nowLine,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(child: Container(height: 1.6, color: palette.nowLine)),
          ],
        ),
      ),
    );
  }
}

/// One block in the time grid, which can be moved and resized in place.
class _TimedEvent extends StatefulWidget {
  const _TimedEvent({
    required this.placement,
    required this.delegate,
    required this.hourHeight,
    required this.onDrag,
  });

  final TimeGridPlacement placement;
  final CalendarViewDelegate delegate;
  final double hourHeight;
  final ValueChanged<_GridDrag?> onDrag;

  @override
  State<_TimedEvent> createState() => _TimedEventState();
}

class _TimedEventState extends State<_TimedEvent> {
  double _travelled = 0;
  bool _resizing = false;
  DateTime? _originStart;
  DateTime? _originEnd;

  bool get _editable =>
      widget.delegate.canEdit && !widget.placement.event.readOnly;

  @override
  Widget build(BuildContext context) {
    final event = widget.placement.event;
    final chip = CalendarEventChip(
      event: event,
      color: widget.delegate.colorOf(event),
      density: CalendarChipDensity.block,
      onTap: widget.delegate.onOpenEvent == null
          ? null
          : () => widget.delegate.onOpenEvent!(event),
      onSecondaryTap: widget.delegate.onEventMenu == null
          ? null
          : (position) => widget.delegate.onEventMenu!(event, position),
    );

    if (!_editable) {
      return chip;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => _begin(resize: false),
            onVerticalDragUpdate: (details) => _update(details.delta.dy),
            onVerticalDragEnd: (_) => _commit(),
            onVerticalDragCancel: _cancel,
            child: chip,
          ),
        ),
        // The resize strip is a later sibling so it wins the pointer at the
        // very bottom edge, where both gestures overlap.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: CalendarMetrics.resizeHandleHeight,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => _begin(resize: true),
              onVerticalDragUpdate: (details) => _update(details.delta.dy),
              onVerticalDragEnd: (_) => _commit(),
              onVerticalDragCancel: _cancel,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }

  void _begin({required bool resize}) {
    final event = widget.placement.event;
    _travelled = 0;
    _resizing = resize;
    _originStart = event.start.local;
    _originEnd =
        event.end?.local ?? event.start.local.add(const Duration(hours: 1));
  }

  void _update(double dy) {
    _travelled += dy;
    final next = _preview();
    widget.onDrag(next);
  }

  void _commit() {
    final drag = _preview();
    widget.onDrag(null);
    if (drag == null) {
      return;
    }
    widget.delegate.onReschedule?.call(drag.event, drag.start, drag.end);
  }

  void _cancel() {
    _travelled = 0;
    widget.onDrag(null);
  }

  /// The bounds the drag has reached, snapped. Null when nothing has moved,
  /// so a click that wobbles by a pixel never writes to the row.
  _GridDrag? _preview() {
    final start = _originStart;
    final end = _originEnd;
    if (start == null || end == null) {
      return null;
    }
    const step = CalendarMetrics.snapMinutes;
    final minutes = _travelled / widget.hourHeight * 60;
    final snapped = (minutes / step).round() * step;
    if (snapped == 0) {
      return null;
    }

    if (_resizing) {
      final nextEnd = end.add(Duration(minutes: snapped));
      if (nextEnd.difference(start).inMinutes < step) {
        return null;
      }
      return _GridDrag(
        event: widget.placement.event,
        start: start,
        end: nextEnd,
      );
    }

    return _GridDrag(
      event: widget.placement.event,
      start: start.add(Duration(minutes: snapped)),
      end: end.add(Duration(minutes: snapped)),
    );
  }
}
