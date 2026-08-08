import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:flutter/material.dart';

/// The palette a calendar is drawn in.
///
/// Deliberately the same one the other table readings use, so a calendar, a
/// board and a gallery of the same table feel like one application rather than
/// three. Only the pieces a calendar alone needs are added here.
typedef CalendarPalette = TableViewPalette;

CalendarPalette calendarPaletteOf(BuildContext context) =>
    tableViewPaletteOf(context);

/// Every fixed size, duration and curve the calendar is built from.
///
/// A modern calendar is mostly whitespace and one accent; the numbers below
/// are what keep it that way when three views share a design.
abstract final class CalendarMetrics {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 22;
  static const double space6 = 28;

  static const double chipRadius = 7;
  static const double cardRadius = 14;
  static const double controlRadius = 9;
  static const double pillRadius = 999;

  /// The bar at the top: month name, navigation, the view switcher.
  static const double toolbarHeight = 52;
  static const double controlSize = 30;
  static const double controlGap = 6;

  /// Weekday names above the month grid.
  static const double weekdayStripHeight = 30;

  /// One event line inside a month cell, and the gap under it.
  static const double monthChipHeight = 21;
  static const double monthChipGap = 3;

  /// The date number's own band at the top of a month cell.
  static const double monthDateBandHeight = 26;

  /// The smallest a month cell may become before the grid starts scrolling
  /// instead of squashing further. Low enough that six weeks still fit a
  /// short window, so a month is not cut off the moment the page is small.
  static const double monthCellMinHeight = 74;

  /// One hour of the time grid at rest, and the range a zoom may reach.
  static const double hourHeight = 52;
  static const double minimumHourHeight = 30;
  static const double maximumHourHeight = 160;

  /// The clock column down the left of a week or day view.
  static const double timeGutterWidth = 60;

  /// The all-day strip above the time grid.
  static const double allDayRowHeight = 24;
  static const double allDayMaxRows = 3;

  /// How far apart two overlapping events sit.
  static const double overlapInset = 3;

  /// The smallest an event block may be drawn, whatever its length.
  static const double minimumEventHeight = 18;

  /// Drag targets snap to this.
  static const int snapMinutes = 15;

  /// The grab strip at the bottom edge of an event, for resizing.
  static const double resizeHandleHeight = 7;

  static const double agendaTimeColumnWidth = 76;
  static const double agendaRowMinHeight = 44;

  // Motion. Small interactions are quick; changing what you are looking at
  // takes long enough to follow.
  static const Duration hover = Duration(milliseconds: 150);
  static const Duration press = Duration(milliseconds: 120);
  static const Duration change = Duration(milliseconds: 180);
  static const Duration navigate = Duration(milliseconds: 280);
  static const Duration switchView = Duration(milliseconds: 320);

  static const Curve hoverCurve = Curves.easeOutCubic;
  static const Curve navigateCurve = Curves.easeInOutCubic;

  /// How often the "now" line steps.
  static const Duration nowTick = Duration(seconds: 30);
}

/// The extra colours a calendar needs beyond the shared palette.
extension CalendarPaletteX on CalendarPalette {
  /// The faintest possible line — a calendar is defined by its whitespace, so
  /// a grid line must be barely there.
  Color get gridLine => border.withValues(alpha: isDark ? 0.30 : 0.34);

  /// The line between weeks, one step stronger than between days.
  Color get weekLine => border.withValues(alpha: isDark ? 0.42 : 0.48);

  /// Saturday and Sunday, tinted rather than boxed.
  Color get weekendWash => isPaper
      ? sunken.withValues(alpha: 0.5)
      : sunken.withValues(alpha: isDark ? 0.35 : 0.55);

  /// A day belonging to the month either side.
  Color get outsideMonthText => textMuted.withValues(alpha: 0.62);

  /// Today's date number sits in this.
  Color get todayBadge => accent;

  Color get todayBadgeText => Colors.white;

  /// A very light wash over the whole of today's column or cell.
  Color get todayWash => accent.withValues(alpha: isDark ? 0.10 : 0.055);

  /// The current-time line.
  Color get nowLine => const Color(0xFFEF4444);

  /// The block a drag would land in.
  Color get dropTarget => accent.withValues(alpha: isDark ? 0.22 : 0.13);

  /// The face of an event, tinted from its own colour.
  Color eventSurface(Color colour) => isDark
      ? Color.alphaBlend(colour.withValues(alpha: 0.30), surface)
      : Color.alphaBlend(colour.withValues(alpha: 0.14), surface);

  Color eventSurfaceHovered(Color colour) => isDark
      ? Color.alphaBlend(colour.withValues(alpha: 0.42), surface)
      : Color.alphaBlend(colour.withValues(alpha: 0.22), surface);

  /// The words on an event: the event's own colour, darkened enough to read.
  Color eventInk(Color colour) {
    if (isDark) {
      return Color.alphaBlend(colour.withValues(alpha: 0.55), textPrimary);
    }
    final hsl = HSLColor.fromColor(colour);
    return hsl.withLightness((hsl.lightness * 0.55).clamp(0.12, 0.4)).toColor();
  }

  /// The 3px bar down the leading edge of an event.
  Color eventAccent(Color colour) => colour;

  /// A completed event fades rather than being struck out in red.
  Color get completedInk => textMuted;

  /// The soft lift an event takes under the pointer.
  List<BoxShadow> eventShadow({bool raised = false}) => [
        BoxShadow(
          color: shadow.withValues(
            alpha: (isDark ? 0.40 : 0.11) * (raised ? 1.6 : 1),
          ),
          blurRadius: raised ? 14 : 7,
          spreadRadius: -3,
          offset: Offset(0, raised ? 5 : 2),
        ),
      ];

  /// The card the whole calendar sits on.
  Color get stage => isPaper ? canvas : canvas;

  /// The strip behind the weekday names and the all-day row.
  Color get chrome => surface;
}

/// The eight colours an event falls back to when nothing gave it one.
abstract final class CalendarSwatches {
  static const List<Color> all = [
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF84CC16),
  ];

  /// A stable colour for a name, so the same calendar keeps the same hue
  /// across restarts. FNV rather than `hashCode`, which is not promised to be
  /// stable between runs.
  static Color forKey(String key) {
    if (key.isEmpty) {
      return all.first;
    }
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return all[hash % all.length];
  }
}
