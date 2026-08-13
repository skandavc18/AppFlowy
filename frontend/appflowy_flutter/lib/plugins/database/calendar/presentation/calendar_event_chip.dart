import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// How much of an event a chip has room to say.
enum CalendarChipDensity {
  /// One line inside a month cell.
  compact,

  /// A row in the agenda: title above, time and place below.
  comfortable,

  /// A block in a time grid, as tall as the event is long.
  block,
}

/// One event, drawn the same way wherever it appears.
///
/// Visually light on purpose: a soft tint of the event's own colour, a 3px
/// leading bar and nothing else. A solid block of saturated colour is what
/// makes most calendars unreadable once a week is busy.
class CalendarEventChip extends StatefulWidget {
  const CalendarEventChip({
    super.key,
    required this.event,
    required this.color,
    this.density = CalendarChipDensity.compact,
    this.onTap,
    this.onSecondaryTap,
    this.onToggleComplete,
    this.selected = false,
    this.dimmed = false,
    this.continuesBefore = false,
    this.continuesAfter = false,
    this.showTime = true,
    this.trailing,
  });

  final CalendarEvent event;
  final Color color;
  final CalendarChipDensity density;
  final VoidCallback? onTap;
  final void Function(Offset globalPosition)? onSecondaryTap;
  final VoidCallback? onToggleComplete;
  final bool selected;

  /// Faded because something else is being dragged or filtered.
  final bool dimmed;

  final bool continuesBefore;
  final bool continuesAfter;
  final bool showTime;
  final Widget? trailing;

  @override
  State<CalendarEventChip> createState() => _CalendarEventChipState();
}

class _CalendarEventChipState extends State<CalendarEventChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final chip = _buildChip(context);
    if (widget.density != CalendarChipDensity.compact) {
      return chip;
    }
    // A month cell is narrower than most titles, so the whole of one is only
    // ever a hover away.
    return Tooltip(
      message: _description(context),
      waitDuration: const Duration(milliseconds: 400),
      child: chip,
    );
  }

  String _description(BuildContext context) {
    final event = widget.event;
    final title = event.title.isEmpty ? _untitled(context) : event.title;
    return event.isAllDay ? title : '${_shortTime(event.start.local)}  $title';
  }

  Widget _buildChip(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final colour = widget.color;
    final raised = _hovered || widget.selected;

    final radius = BorderRadius.only(
      topLeft: Radius.circular(
        widget.continuesBefore ? 2 : CalendarMetrics.chipRadius,
      ),
      bottomLeft: Radius.circular(
        widget.continuesBefore ? 2 : CalendarMetrics.chipRadius,
      ),
      topRight: Radius.circular(
        widget.continuesAfter ? 2 : CalendarMetrics.chipRadius,
      ),
      bottomRight: Radius.circular(
        widget.continuesAfter ? 2 : CalendarMetrics.chipRadius,
      ),
    );

    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (details) => widget.onSecondaryTap!(details.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: CalendarMetrics.hover,
          opacity: widget.dimmed ? 0.42 : 1,
          child: AnimatedContainer(
            duration: CalendarMetrics.hover,
            curve: CalendarMetrics.hoverCurve,
            decoration: BoxDecoration(
              color: raised
                  ? palette.eventSurfaceHovered(colour)
                  : palette.eventSurface(colour),
              borderRadius: radius,
              boxShadow: raised ? palette.eventShadow(raised: true) : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              crossAxisAlignment: widget.density == CalendarChipDensity.block
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: [
                if (!widget.continuesBefore)
                  Container(width: 3, color: palette.eventAccent(colour)),
                Expanded(child: _buildBody(palette, colour)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(CalendarPalette palette, Color colour) {
    final event = widget.event;
    final ink =
        event.isCompleted ? palette.completedInk : palette.eventInk(colour);

    return switch (widget.density) {
      CalendarChipDensity.compact => _compact(palette, ink),
      CalendarChipDensity.comfortable => _comfortable(palette, ink, colour),
      CalendarChipDensity.block => _block(ink),
    };
  }

  Widget _compact(CalendarPalette palette, Color ink) {
    final event = widget.event;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          if (event.kind == CalendarEventKind.reminder) ...[
            Icon(Icons.notifications_rounded, size: 11, color: ink),
            const SizedBox(width: 4),
          ] else if (event.hasReminder) ...[
            Icon(Icons.notifications_none_rounded, size: 11, color: ink),
            const SizedBox(width: 4),
          ],
          if (widget.showTime && !event.isAllDay) ...[
            Text(
              _shortTime(event.start.local),
              style: TextStyle(
                fontSize: 10.5,
                height: 1,
                color: ink.withValues(alpha: 0.78),
                fontVariations: const [FontVariation.weight(600)],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Text(
              event.title.isEmpty ? _untitled(context) : event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1,
                letterSpacing: -0.1,
                color: ink,
                fontVariations: const [FontVariation.weight(590)],
                decoration:
                    event.isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }

  Widget _comfortable(CalendarPalette palette, Color ink, Color colour) {
    final event = widget.event;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Row(
        children: [
          if (widget.onToggleComplete != null) ...[
            _CompleteToggle(
              done: event.isCompleted,
              color: colour,
              onTap: widget.onToggleComplete!,
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (event.kind == CalendarEventKind.reminder) ...[
                      Icon(Icons.notifications_rounded, size: 12, color: ink),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        event.title.isEmpty ? _untitled(context) : event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.15,
                          letterSpacing: -0.15,
                          color: ink,
                          fontVariations: const [FontVariation.weight(600)],
                          decoration: event.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                if (event.location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 11,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          event.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }

  Widget _block(Color ink) {
    final event = widget.event;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tall = constraints.maxHeight >= 34;
        final veryTall = constraints.maxHeight >= 52;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 6,
            vertical: tall ? 4 : 1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (event.hasReminder ||
                      event.kind == CalendarEventKind.reminder) ...[
                    Icon(
                      event.kind == CalendarEventKind.reminder
                          ? Icons.notifications_rounded
                          : Icons.notifications_none_rounded,
                      size: 11,
                      color: ink,
                    ),
                    const SizedBox(width: 3),
                  ],
                  Expanded(
                    child: Text(
                      event.title.isEmpty ? _untitled(context) : event.title,
                      maxLines: tall ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        letterSpacing: -0.1,
                        color: ink,
                        fontVariations: const [FontVariation.weight(600)],
                        decoration: event.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (veryTall && widget.showTime) ...[
                const SizedBox(height: 1),
                Text(
                  _range(event),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.1,
                    color: ink.withValues(alpha: 0.72),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (veryTall &&
                  constraints.maxHeight >= 74 &&
                  event.location.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  event.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.1,
                    color: ink.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _range(CalendarEvent event) {
    final start = _shortTime(event.start.local);
    final end = event.end;
    return end == null ? start : '$start – ${_shortTime(end.local)}';
  }

  String _untitled(BuildContext context) => '';
}

class _CompleteToggle extends StatelessWidget {
  const _CompleteToggle({
    required this.done,
    required this.color,
    required this.onTap,
  });

  final bool done;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: CalendarMetrics.press,
          curve: CalendarMetrics.hoverCurve,
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: done ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? color : palette.border,
              width: 1.5,
            ),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 11, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// `9:00`, `9:30`, `14:05` — or `9:00 AM` where that is how the clock reads.
String _shortTime(DateTime value) {
  final pattern = DateFormat.jm().pattern ?? '';
  if (pattern.contains('a')) {
    return value.minute == 0
        ? DateFormat('h a').format(value)
        : DateFormat('h:mm a').format(value);
  }
  return DateFormat('HH:mm').format(value);
}

/// The same short time, for anything outside this file that needs it.
String calendarShortTime(DateTime value) => _shortTime(value);
