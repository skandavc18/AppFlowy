import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The board's surfaces.
///
/// Borrowed wholesale from the shared table-view tokens, so a column, a card
/// and a gallery tile are recognisably the same material and a change to the
/// application's palette reaches all of them at once.
typedef BoardPalette = TableViewPalette;

BoardPalette boardPaletteOf(BuildContext context) =>
    tableViewPaletteOf(context);

/// The geometry and motion a board is built on.
abstract final class BoardMetrics {
  /// A column reads as a workspace of its own rather than a bare list.
  static const double columnRadius = 16;
  static const double columnGap = 7;

  /// A card is a document, not a form: rounder and softer than a card control.
  static const double cardRadius = 14;
  static const double cardGap = 4;

  /// How far a column holds its cards in from its own edge.
  static const double columnInset = 8;

  /// How far a card rises under the pointer.
  static const double cardLift = 2;
  static const double cardGrowth = 1.008;

  static const Duration hover = Duration(milliseconds: 140);
  static const Duration settle = Duration(milliseconds: 220);
  static const Curve hoverCurve = Curves.easeOutCubic;
}

/// The well a grouped column sits in, tinted towards the colour of its group.
///
/// Barely there on purpose: enough to tell one column from the next at a
/// glance, never enough to fight the cards floating on it. A group with no
/// colour of its own — a checkbox, a date, or the catch-all "No …" column —
/// keeps the neutral sunken grey.
Color boardColumnWashColor(BoardPalette palette, Color groupColor) =>
    _boardTinted(palette, groupColor, deepened: false);

/// The tint a card's page preview wears.
///
/// It borrows the wash of the column the card sits in, so the writing on a
/// card reads as part of its group rather than as a grey slab dropped on it,
/// and deepens in the group's OWN colour under the pointer — a neutral grey
/// there would read as the card going dead rather than lighting up.
Color boardCardPreviewTint(
  BoardPalette palette,
  Color? groupColor, {
  required bool hovered,
}) {
  if (groupColor == null) {
    final well = _boardWell(palette);
    return hovered ? Color.alphaBlend(palette.hover, well) : well;
  }
  return _boardTinted(palette, groupColor, deepened: hovered);
}

// The well can be a translucent scrim, so settle it against the board before
// tinting; a wash is painted over that same scrim and must be opaque.
Color _boardWell(BoardPalette palette) =>
    Color.alphaBlend(palette.sunken, palette.canvas);

Color _boardTinted(
  BoardPalette palette,
  Color groupColor, {
  required bool deepened,
}) {
  final strength =
      palette.isDark ? (deepened ? 0.26 : 0.15) : (deepened ? 0.44 : 0.28);
  return Color.alphaBlend(
    groupColor.withValues(alpha: strength),
    _boardWell(palette),
  );
}

/// Marks the subtree that is genuinely laid out inside a column.
///
/// A card being dragged is rebuilt in the drag overlay, outside the board and
/// therefore outside this marker, so its wash stays behind in the column it
/// came from instead of flying about as a coloured slab.
class BoardColumnSurface extends InheritedWidget {
  const BoardColumnSurface({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BoardColumnSurface>() != null;

  @override
  bool updateShouldNotify(BoardColumnSurface oldWidget) => false;
}

/// One piece of a column's well: the header band, a card's berth, the footer.
///
/// Painted edge to edge so the pieces stack into one continuous surface — the
/// board package owns the column's own background and offers no per-column
/// colour, so the columns paint their own.
class BoardColumnWash extends StatelessWidget {
  const BoardColumnWash({
    super.key,
    required this.color,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Color? color;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final body = padding == EdgeInsets.zero
        ? child
        : Padding(padding: padding, child: child);
    final wash = color;
    if (wash == null || !BoardColumnSurface.of(context)) {
      return body;
    }
    return ColoredBox(color: wash, child: body);
  }
}

/// How the board scrolls.
///
/// Momentum in both directions and a thin scrollbar that only shows itself
/// while the board is moving, so a column keeps its full width at rest.
class BoardScrollBehaviour extends MaterialScrollBehavior {
  const BoardScrollBehaviour();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (details.direction == AxisDirection.left ||
        details.direction == AxisDirection.right) {
      return child;
    }
    return RawScrollbar(
      controller: details.controller,
      thumbColor: tableViewPaletteOf(context).border,
      thickness: 4,
      radius: const Radius.circular(4),
      thumbVisibility: false,
      child: child,
    );
  }
}
