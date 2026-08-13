import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A borderless 30px control, the only button shape the calendar uses.
class CalendarControlButton extends StatefulWidget {
  const CalendarControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = false,
    this.size = CalendarMetrics.controlSize,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final double size;

  @override
  State<CalendarControlButton> createState() => _CalendarControlButtonState();
}

class _CalendarControlButtonState extends State<CalendarControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final enabled = widget.onPressed != null;
    final tint = widget.active
        ? palette.accent
        : enabled
            ? palette.textSecondary
            : palette.textMuted.withValues(alpha: 0.5);

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: CalendarMetrics.hover,
          curve: CalendarMetrics.hoverCurve,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            // Fade from the wash's own hue: lerping out of transparent black
            // flashes grey on a light surface.
            color: widget.active
                ? palette.accent.withValues(alpha: 0.12)
                : palette.hover.withValues(alpha: _hovered && enabled ? 1 : 0),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 17, color: tint),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    return tooltip == null || tooltip.isEmpty
        ? button
        : Tooltip(message: tooltip, child: button);
  }
}

/// The compact reading switcher: Month · Week · Day · Agenda.
///
/// A segmented control rather than a dropdown, because four choices that are
/// switched between constantly should each be one click away.
class CalendarViewSwitcher extends StatelessWidget {
  const CalendarViewSwitcher({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.labels,
    this.available = const [
      CalendarViewMode.month,
      CalendarViewMode.week,
      CalendarViewMode.day,
      CalendarViewMode.agenda,
    ],
  });

  final CalendarViewMode mode;
  final ValueChanged<CalendarViewMode> onChanged;
  final String Function(CalendarViewMode) labels;
  final List<CalendarViewMode> available;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.sunken.withValues(alpha: palette.isDark ? 0.55 : 0.7),
        borderRadius: BorderRadius.circular(CalendarMetrics.controlRadius + 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in available)
            _SwitcherSegment(
              label: labels(option),
              selected: option == mode,
              onTap: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}

class _SwitcherSegment extends StatefulWidget {
  const _SwitcherSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SwitcherSegment> createState() => _SwitcherSegmentState();
}

class _SwitcherSegmentState extends State<_SwitcherSegment> {
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
          duration: CalendarMetrics.change,
          curve: CalendarMetrics.hoverCurve,
          height: CalendarMetrics.controlSize - 4,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.surface
                : palette.hover.withValues(alpha: _hovered ? 0.7 : 0),
            borderRadius: BorderRadius.circular(CalendarMetrics.controlRadius),
            boxShadow: widget.selected ? palette.chromeShadow : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: CalendarMetrics.change,
            curve: CalendarMetrics.hoverCurve,
            style: TextStyle(
              fontSize: 12.5,
              height: 1,
              letterSpacing: -0.1,
              color:
                  widget.selected ? palette.textPrimary : palette.textSecondary,
              fontVariations: [
                FontVariation.weight(widget.selected ? 620 : 545),
              ],
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

/// The one empty state the calendar uses, in every view.
///
/// Two short lines and, when there is something worth doing, one quiet action.
class CalendarEmptyState extends StatelessWidget {
  const CalendarEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CalendarMetrics.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 26 : 34,
              color: palette.textMuted.withValues(alpha: 0.55),
            ),
            SizedBox(
              height: compact ? CalendarMetrics.space2 : CalendarMetrics.space3,
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 13 : 14.5,
                height: 1.25,
                color: palette.textSecondary,
                fontVariations: const [FontVariation.weight(600)],
              ),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: CalendarMetrics.space1),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  height: 1.35,
                  color: palette.textMuted,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: CalendarMetrics.space4),
              _QuietAction(label: actionLabel!, onTap: onAction!),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuietAction extends StatefulWidget {
  const _QuietAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_QuietAction> createState() => _QuietActionState();
}

class _QuietActionState extends State<_QuietAction> {
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: _hovered ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(CalendarMetrics.controlRadius),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
              height: 1,
              color: palette.accent,
              fontVariations: const [FontVariation.weight(600)],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section label: "TODAY", "AUGUST", "MON".
class CalendarSectionLabel extends StatelessWidget {
  const CalendarSectionLabel({
    super.key,
    required this.text,
    this.emphasised = false,
    this.color,
  });

  final String text;
  final bool emphasised;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        height: 1,
        letterSpacing: 0.7,
        color: color ?? (emphasised ? palette.accent : palette.textMuted),
        fontVariations: [FontVariation.weight(emphasised ? 660 : 600)],
      ),
    );
  }
}

/// A dot in a calendar's own colour, used wherever a calendar is named.
class CalendarColorDot extends StatelessWidget {
  const CalendarColorDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// The application's kinetic scrolling, installed only if it is not already.
///
/// ⚠️ Nesting a second [PremiumScrollScope] inside the ambient one installs a
/// second wheel dispatcher, and the outer one then claims pointer signals the
/// inner scrollable never sees — which reads as "this view will not scroll".
/// `DocumentScrollScope` guards against exactly this; so does everything here.
class CalendarScrollScope extends StatelessWidget {
  const CalendarScrollScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ScrollConfiguration.of(context) is PremiumScrollBehavior
          ? child
          : PremiumScrollScope(enabled: true, child: child);
}

/// Whether this calendar is the one scrollable the page coordinates with.
///
/// On a full page the cover and the title live in a `NestedScrollView` header,
/// and they only move when the reading below drives them — which means the
/// reading has to take the page's own controller rather than keep one.
bool calendarDrivesPageScroll(BuildContext context) =>
    Provider.of<DatabasePluginWidgetBuilderSize?>(context, listen: false)
        ?.coordinateVerticalScroll ??
    false;
