import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/blank/home/home_arrangement.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// How many of Home's twelve columns are shown side by side.
enum HomeGridMode {
  /// Every section keeps its stored column, width and height.
  grid,

  /// Narrower windows: two sections of half width or less that follow each
  /// other share a row, and everything else takes the full width.
  pairs,

  /// Narrow windows: one section per row.
  single,
}

/// One section placed on [HomeGrid].
class HomeGridItem {
  HomeGridItem({
    required this.id,
    required this.placement,
    required this.child,
    required this.label,
    required this.icon,
    int minSpan = 1,
    int minRows = 1,
    this.canFit = true,
    this.hidden = false,
    this.onConfigure,
  })  : minSpan = minSpan.clamp(1, homeGridColumns),
        minRows = minRows.clamp(1, homeMaximumRows);

  final String id;
  final HomeBlockPlacement placement;
  final Widget child;

  /// What the section is called while Home is being customised.
  final String label;
  final IconData icon;

  /// The fewest columns it can be narrowed to.
  final int minSpan;

  /// The fewest height units it can be shortened to.
  final int minRows;

  /// Whether it can be as tall as its content. Sections that can't always
  /// keep a pinned height.
  final bool canFit;

  /// Shown only while customising, dimmed, because what it shows is hidden.
  final bool hidden;

  /// Opens the section's own settings; null when it has none.
  final VoidCallback? onConfigure;
}

/// Tells a section whether Home pinned its height. A pinned section fills
/// the height it is given and scrolls what doesn't fit, instead of being as
/// tall as its content.
class HomeTileExtent extends InheritedWidget {
  const HomeTileExtent({
    super.key,
    required this.fixed,
    required super.child,
  });

  final bool fixed;

  static bool fixedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeTileExtent>()?.fixed ??
      false;

  @override
  bool updateShouldNotify(HomeTileExtent oldWidget) => fixed != oldWidget.fixed;
}

/// A section's columns and laid-out height, before it is packed.
typedef HomeGridBox = ({int column, int span, double height});

/// Where a packed section sits.
typedef HomeGridSlot = ({int column, int span, double top, double height});

bool _spansOverlap(int column, int span, int otherColumn, int otherSpan) =>
    column < otherColumn + otherSpan && otherColumn < column + span;

/// Packs sections in reading order. Each one sits just below the lowest
/// earlier section sharing any of its columns, or at the top when none does,
/// so nothing ever floats above a section that comes before it.
List<HomeGridSlot> packHomeGrid(List<HomeGridBox> boxes, {double gap = 0}) {
  final slots = <HomeGridSlot>[];
  for (final box in boxes) {
    var top = 0.0;
    for (final slot in slots) {
      if (_spansOverlap(slot.column, slot.span, box.column, box.span)) {
        top = math.max(top, slot.top + slot.height + gap);
      }
    }
    slots.add(
      (column: box.column, span: box.span, top: top, height: box.height),
    );
  }
  return slots;
}

/// Where a section being dragged belongs among [others] (the remaining
/// sections, packed without it): after every section sharing its columns
/// whose middle is above its top edge, and before every one whose middle is
/// below it. When several positions qualify, because none of the sections
/// between them shares its columns, the one nearest [origin] wins, so a
/// sideways drag doesn't reshuffle sections it never passed.
int homeGridInsertionIndex(
  List<HomeGridSlot> others, {
  required int column,
  required int span,
  required double top,
  required int origin,
}) {
  var lowest = 0;
  int? highest;
  for (var i = 0; i < others.length; i++) {
    final other = others[i];
    if (!_spansOverlap(other.column, other.span, column, span)) {
      continue;
    }
    if (other.top + other.height / 2 <= top) {
      lowest = i + 1;
    } else {
      highest ??= i;
    }
  }
  final upper = highest ?? others.length;
  return lowest <= upper ? origin.clamp(lowest, upper) : lowest;
}

/// The nearest section before [index] sharing one of its columns: the one
/// it trades places with when moved up.
int? homeGridIndexAbove(List<HomeBlockPlacement> placements, int index) {
  for (var i = index - 1; i >= 0; i--) {
    if (placements[i].overlapsColumns(placements[index])) {
      return i;
    }
  }
  return null;
}

/// The nearest section after [index] sharing one of its columns: the one it
/// trades places with when moved down.
int? homeGridIndexBelow(List<HomeBlockPlacement> placements, int index) {
  for (var i = index + 1; i < placements.length; i++) {
    if (placements[i].overlapsColumns(placements[index])) {
      return i;
    }
  }
  return null;
}

/// Two columns: a section of half width or less followed by another shares
/// a row with it; everything else takes the full width. Heights are kept.
List<HomeBlockPlacement> homeGridPairs(List<HomeBlockPlacement> placements) {
  const half = homeGridColumns ~/ 2;
  final paired = <HomeBlockPlacement>[];
  var i = 0;
  while (i < placements.length) {
    final current = placements[i];
    final next = i + 1 < placements.length ? placements[i + 1] : null;
    if (current.span <= half && next != null && next.span <= half) {
      paired
        ..add(HomeBlockPlacement(span: half, rows: current.rows))
        ..add(HomeBlockPlacement(column: half, span: half, rows: next.rows));
      i += 2;
    } else {
      paired.add(HomeBlockPlacement(rows: current.rows));
      i += 1;
    }
  }
  return paired;
}

/// Where sections are drawn in [mode], from where they are stored.
List<HomeBlockPlacement> homeGridShownPlacements(
  List<HomeBlockPlacement> placements,
  HomeGridMode mode,
) =>
    switch (mode) {
      HomeGridMode.grid => placements,
      HomeGridMode.pairs => homeGridPairs(placements),
      HomeGridMode.single => [
          for (final placement in placements)
            HomeBlockPlacement(rows: placement.rows),
        ],
    };

/// The narrowest a section is drawn or made on the grid. In a narrower
/// window that takes more of its columns.
const homeGridReadableWidth = 200.0;

/// How many columns of a grid [width] wide, [columnGap] apart, a section
/// takes to be at least [readable] wide.
int homeGridReadableSpan(
  double width, {
  double readable = homeGridReadableWidth,
  double columnGap = 24,
}) {
  final step = (width + columnGap) / homeGridColumns;
  if (step <= 0) {
    return homeGridColumns;
  }
  // A hair under, so a width that is exactly enough isn't rounded up.
  return ((readable + columnGap) / step - 1e-6)
      .ceil()
      .clamp(1, homeGridColumns);
}

/// The height of [rows] height units, gaps between them included.
double homeGridRowsHeight(int rows, double rowHeight, double rowGap) =>
    rows * rowHeight + math.max(0, rows - 1) * rowGap;

/// How many height units [height] fills best.
int homeGridRowsFor(
  double height,
  double rowHeight,
  double rowGap, {
  int minimum = 1,
}) =>
    ((height + rowGap) / (rowHeight + rowGap))
        .round()
        .clamp(math.min(minimum, homeMaximumRows), homeMaximumRows);

/// What is being dragged: a lifted section following the pointer, or a
/// section being resized, outlined meanwhile.
@immutable
class _HomeGridDrag {
  const _HomeGridDrag(this.id, {this.floating, this.resizing = false});

  final String id;

  /// The lifted section's top-left corner, in the grid's coordinates.
  final Offset? floating;

  final bool resizing;

  @override
  bool operator ==(Object other) =>
      other is _HomeGridDrag &&
      other.id == id &&
      other.floating == floating &&
      other.resizing == resizing;

  @override
  int get hashCode => Object.hash(id, floating, resizing);
}

/// The colours the grid paints itself: where a lifted section will land,
/// the section itself while lifted, and the outline of one being resized.
@immutable
class _HomeGridStyle {
  const _HomeGridStyle({
    required this.accent,
    required this.poolFill,
    required this.poolStroke,
    required this.background,
    required this.shadows,
    required this.radius,
  });

  factory _HomeGridStyle.of(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return _HomeGridStyle(
      accent: palette.accent,
      poolFill: palette.accent.withValues(alpha: palette.isDark ? 0.14 : 0.08),
      poolStroke: palette.accent.withValues(alpha: 0.55),
      background: palette.background,
      shadows: palette.elevation(floating: true),
      radius: WorkspaceTokens.cardRadius + 6,
    );
  }

  final Color accent;
  final Color poolFill;
  final Color poolStroke;

  /// Beneath a lifted section, so the sections it passes over don't show
  /// through its translucent frame.
  final Color background;
  final List<BoxShadow> shadows;
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is _HomeGridStyle &&
      other.accent == accent &&
      other.poolFill == poolFill &&
      other.poolStroke == poolStroke &&
      other.background == background &&
      listEquals(other.shadows, shadows) &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(
        accent,
        poolFill,
        poolStroke,
        background,
        Object.hashAll(shadows),
        radius,
      );
}

class _HomeGridParentData extends ContainerBoxParentData<RenderBox> {
  String? id;
  int column = 0;
  int span = homeGridColumns;

  /// Where the section settles.
  Offset target = Offset.zero;

  /// Where the section's current glide started.
  Offset from = Offset.zero;

  /// Whether it has been laid out before; new sections appear in place.
  bool placed = false;
}

class _HomeGridTile extends ParentDataWidget<_HomeGridParentData> {
  _HomeGridTile({
    required this.id,
    required this.column,
    required this.span,
    required super.child,
  }) : super(key: ValueKey('home-tile-$id'));

  final String id;
  final int column;
  final int span;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _HomeGridParentData;
    if (data.id == id && data.column == column && data.span == span) {
      return;
    }
    data
      ..id = id
      ..column = column
      ..span = span;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _HomeGridLayout;
}

class _HomeGridLayout extends MultiChildRenderObjectWidget {
  const _HomeGridLayout({
    super.key,
    required this.vsync,
    required this.drag,
    required this.columnGap,
    required this.rowGap,
    required this.animate,
    required this.duration,
    required this.textDirection,
    required this.style,
    required this.minHeight,
    required super.children,
  });

  final TickerProvider vsync;
  final ValueListenable<_HomeGridDrag?> drag;
  final double columnGap;
  final double rowGap;

  /// Whether sections glide to new places rather than jump.
  final bool animate;
  final Duration duration;
  final TextDirection textDirection;
  final _HomeGridStyle style;

  /// Keeps the grid from shrinking while a section is lifted out of it.
  final double minHeight;

  @override
  _RenderHomeGrid createRenderObject(BuildContext context) => _RenderHomeGrid(
        vsync: vsync,
        drag: drag,
        columnGap: columnGap,
        rowGap: rowGap,
        animate: animate,
        duration: duration,
        textDirection: textDirection,
        style: style,
        minHeight: minHeight,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderHomeGrid renderObject) {
    renderObject
      ..vsync = vsync
      ..drag = drag
      ..columnGap = columnGap
      ..rowGap = rowGap
      ..animate = animate
      ..duration = duration
      ..textDirection = textDirection
      ..style = style
      ..minHeight = minHeight;
  }
}

/// Lays sections out on twelve columns, packed in reading order, and glides
/// them to new places as they move. A lifted section is drawn on top where
/// the pointer holds it, above a pool marking where it will land.
class _RenderHomeGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HomeGridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HomeGridParentData> {
  _RenderHomeGrid({
    required TickerProvider vsync,
    required ValueListenable<_HomeGridDrag?> drag,
    required double columnGap,
    required double rowGap,
    required bool animate,
    required Duration duration,
    required TextDirection textDirection,
    required _HomeGridStyle style,
    required double minHeight,
  })  : _vsync = vsync,
        _drag = drag,
        _columnGap = columnGap,
        _rowGap = rowGap,
        _animate = animate,
        _textDirection = textDirection,
        _style = style,
        _minHeight = minHeight,
        _motion = AnimationController(
          vsync: vsync,
          duration: duration,
          value: 1,
        ) {
    _motion.addListener(_onTick);
  }

  final AnimationController _motion;

  /// The section following the pointer.
  String? _lifted;

  /// The section that was let go, kept on top until it has settled.
  String? _landing;
  double? _laidOutWidth;
  bool _snapNext = false;

  TickerProvider _vsync;
  set vsync(TickerProvider value) {
    if (identical(value, _vsync)) {
      return;
    }
    _vsync = value;
    _motion.resync(value);
  }

  ValueListenable<_HomeGridDrag?> _drag;
  set drag(ValueListenable<_HomeGridDrag?> value) {
    if (identical(value, _drag)) {
      return;
    }
    if (attached) {
      _drag.removeListener(_onDrag);
      value.addListener(_onDrag);
    }
    _drag = value;
    _onDrag();
  }

  double _columnGap;
  set columnGap(double value) {
    if (value == _columnGap) {
      return;
    }
    _columnGap = value;
    markNeedsLayout();
  }

  double _rowGap;
  set rowGap(double value) {
    if (value == _rowGap) {
      return;
    }
    _rowGap = value;
    markNeedsLayout();
  }

  bool _animate;
  set animate(bool value) {
    if (value == _animate) {
      return;
    }
    _animate = value;
    // Sections change size when their frames come and go; they jump to
    // their new places rather than slide across each other.
    _snapNext = true;
    markNeedsLayout();
  }

  set duration(Duration value) {
    if (value != _motion.duration) {
      _motion.duration = value;
    }
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    _snapNext = true;
    markNeedsLayout();
  }

  _HomeGridStyle _style;
  set style(_HomeGridStyle value) {
    if (value == _style) {
      return;
    }
    _style = value;
    markNeedsPaint();
  }

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) {
      return;
    }
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HomeGridParentData) {
      child.parentData = _HomeGridParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _drag.addListener(_onDrag);
    if (_motion.value != 1) {
      _motion.value = 1;
    }
  }

  @override
  void detach() {
    _drag.removeListener(_onDrag);
    _motion.stop();
    super.detach();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  /// Where [id]'s section is drawn now, in the grid's coordinates.
  Rect? rectOf(String id) {
    final child = _childOf(id);
    if (child == null) {
      return null;
    }
    return (child.parentData! as _HomeGridParentData).offset & child.size;
  }

  /// Each section's laid-out height, by id.
  Map<String, double> get heights => {
        for (var child = firstChild; child != null; child = childAfter(child))
          (child.parentData! as _HomeGridParentData).id!: child.size.height,
      };

  RenderBox? _childOf(String? id) {
    if (id == null) {
      return null;
    }
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if ((child.parentData! as _HomeGridParentData).id == id) {
        return child;
      }
    }
    return null;
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth, 'Home grid needs a bounded width.');
    final width = constraints.maxWidth;
    final step = (width + _columnGap) / homeGridColumns;
    final boxes = <HomeGridBox>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _HomeGridParentData;
      child.layout(
        BoxConstraints.tightFor(
          width: math.max(0.0, data.span * step - _columnGap),
        ),
        parentUsesSize: true,
      );
      boxes.add(
        (column: data.column, span: data.span, height: child.size.height),
      );
    }
    final slots = packHomeGrid(boxes, gap: _rowGap);
    var moved = false;
    var bottom = 0.0;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _HomeGridParentData;
      final slot = slots[index++];
      final start = slot.column * step;
      final target = Offset(
        _textDirection == TextDirection.rtl
            ? width - start - child.size.width
            : start,
        slot.top,
      );
      bottom = math.max(bottom, slot.top + slot.height);
      if (!data.placed) {
        data
          ..placed = true
          ..from = target
          ..target = target
          ..offset = target;
      } else if (data.target != target) {
        data.target = target;
        moved = true;
      }
    }
    final resized = _laidOutWidth != null && _laidOutWidth != width;
    _laidOutWidth = width;
    if (moved && _animate && !resized && !_snapNext) {
      _glide();
    } else if (moved || resized || _snapNext) {
      _settle();
    }
    _snapNext = false;
    size = constraints.constrain(
      Size(
        width,
        math.max(bottom, _minHeight),
      ),
    );
    _place();
  }

  /// Glides every section from where it is drawn now to its slot.
  void _glide() {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _HomeGridParentData;
      data.from = data.offset;
    }
    _motion.forward(from: 0);
  }

  /// Puts every section in its slot at once.
  void _settle() => _motion.value = 1;

  void _onTick() {
    if (_motion.value == 1) {
      _landing = null;
      markNeedsSemanticsUpdate();
    }
    _place();
    markNeedsPaint();
  }

  void _onDrag() {
    final drag = _drag.value;
    final lifted = drag?.floating == null ? null : drag!.id;
    final dropped = _lifted != null && lifted != _lifted;
    if (dropped) {
      _landing = _lifted;
    }
    _lifted = lifted;
    if (dropped) {
      // Let go: the section glides from the pointer into its slot.
      if (_animate) {
        _glide();
      } else {
        _settle();
      }
    }
    _place();
    markNeedsPaint();
  }

  void _place() {
    final drag = _drag.value;
    final floating = drag?.floating;
    final t = Curves.easeOutCubic.transform(_motion.value.clamp(0.0, 1.0));
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _HomeGridParentData;
      data.offset = floating != null && data.id == drag!.id
          ? floating
          : Offset.lerp(data.from, data.target, t)!;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final lifted = _childOf(_lifted);
    final top = lifted ?? _childOf(_landing);
    final radius = Radius.circular(_style.radius);
    if (lifted != null) {
      final data = lifted.parentData! as _HomeGridParentData;
      final pool = RRect.fromRectAndRadius(
        (offset + data.target) & lifted.size,
        radius,
      );
      context.canvas
        ..drawRRect(pool, Paint()..color = _style.poolFill)
        ..drawRRect(
          pool,
          Paint()
            ..color = _style.poolStroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
    }
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (!identical(child, top)) {
        final data = child.parentData! as _HomeGridParentData;
        context.paintChild(child, offset + data.offset);
      }
    }
    if (top != null) {
      final data = top.parentData! as _HomeGridParentData;
      final card = RRect.fromRectAndRadius(
        (offset + data.offset) & top.size,
        radius,
      );
      final canvas = context.canvas;
      if (identical(top, lifted)) {
        for (final shadow in _style.shadows) {
          canvas.drawRRect(
            card.shift(shadow.offset).inflate(shadow.spreadRadius),
            shadow.toPaint(),
          );
        }
      }
      canvas.drawRRect(card, Paint()..color = _style.background);
      context.paintChild(top, offset + data.offset);
    }
    final drag = _drag.value;
    final resized = drag != null && drag.resizing ? _childOf(drag.id) : null;
    if (resized != null) {
      final data = resized.parentData! as _HomeGridParentData;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius((offset + data.offset) & resized.size, radius),
        Paint()
          ..color = _style.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final top = _childOf(_lifted ?? _landing);
    if (top != null && _hitTestChild(result, top, position)) {
      return true;
    }
    for (var child = lastChild; child != null; child = childBefore(child)) {
      if (!identical(child, top) && _hitTestChild(result, child, position)) {
        return true;
      }
    }
    return false;
  }

  bool _hitTestChild(
    BoxHitTestResult result,
    RenderBox child,
    Offset position,
  ) {
    final data = child.parentData! as _HomeGridParentData;
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'Sections are packed by the heights they lay out to.',
      ),
    );
    return Size.zero;
  }
}

/// Home's sections on a twelve-column grid.
///
/// While [editing], every section is framed and can be dragged anywhere, the
/// others moving out of its way, and resized from either side, its bottom
/// edge and both bottom corners. Each drag has a button or a menu entry that
/// does the same.
class HomeGrid extends StatefulWidget {
  const HomeGrid({
    super.key,
    required this.items,
    required this.editing,
    required this.onArrange,
    required this.onRemove,
    this.mode = HomeGridMode.grid,
    this.rowHeight = 46,
    this.rowGap = 14,
    this.columnGap = 24,
  });

  final List<HomeGridItem> items;
  final bool editing;

  /// Commits a new order of the sections, together with a new placement for
  /// [id], the section that was moved or resized.
  final void Function(
    List<String> order,
    String id,
    HomeBlockPlacement placement,
  ) onArrange;
  final ValueChanged<String> onRemove;
  final HomeGridMode mode;

  /// The height of one height unit, and the gap between two.
  final double rowHeight;
  final double rowGap;
  final double columnGap;

  @override
  State<HomeGrid> createState() => _HomeGridState();
}

/// Where a section is resized from. Start and end follow the text direction.
/// There is no top edge: a section's top is wherever the sections above it
/// end, so its height changes at the bottom.
enum _HomeGripEdge {
  start,
  end,
  bottom,
  bottomStart,
  bottomEnd;

  bool get changesWidth => this != bottom;

  bool get changesHeight => this != start && this != end;

  /// Whether the start edge moves, the end edge staying where it is.
  bool get fromStart => this == start || this == bottomStart;
}

/// A section being dragged around or resized.
sealed class _HomeGridSession {
  _HomeGridSession(this.id, this.placement, this.height);

  final String id;

  /// Where the section is placed if it is let go now.
  HomeBlockPlacement placement;

  /// The grid's height when the drag began, which it keeps meanwhile, so
  /// the page doesn't shift under the pointer.
  final double height;

  /// How far the pointer has travelled, page scrolling included.
  Offset travelled = Offset.zero;
}

final class _HomeMoveSession extends _HomeGridSession {
  _HomeMoveSession({
    required String id,
    required HomeBlockPlacement placement,
    required this.origin,
    required this.order,
    required this.others,
    required this.reference,
    required this.originIndex,
    required double height,
  })  : arranged = order,
        super(id, placement, height);

  /// Where the section was drawn when it was picked up.
  final Rect origin;

  /// The order when it was picked up.
  final List<String> order;

  /// The other sections, in order, and where they sit without it.
  final List<String> others;
  final List<HomeGridSlot> reference;
  final int originIndex;

  /// The order if it is let go now.
  List<String> arranged;
}

final class _HomeResizeSession extends _HomeGridSession {
  _HomeResizeSession({
    required String id,
    required HomeBlockPlacement placement,
    required this.edge,
    required this.origin,
    required this.content,
    required this.baseRows,
    required double height,
  })  : start = placement,
        super(id, placement, height);

  final _HomeGripEdge edge;

  /// Where the section was drawn when the resize began.
  final Rect origin;

  /// The content's height when the resize began, and in height units.
  final double content;
  final int baseRows;
  final HomeBlockPlacement start;
}

class _HomeGridState extends State<HomeGrid> with TickerProviderStateMixin {
  final _layoutKey = GlobalKey();

  /// Keeps each section's state while its frame comes and goes.
  final _contentKeys = <String, GlobalKey>{};
  final _drag = ValueNotifier<_HomeGridDrag?>(null);
  _HomeGridSession? _session;
  ScrollableState? _scrollable;
  Timer? _scrollTimer;
  double _scrollReach = 0;

  _RenderHomeGrid? get _grid {
    final grid = _layoutKey.currentContext?.findRenderObject();
    return grid is _RenderHomeGrid && grid.hasSize ? grid : null;
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  bool get _isGrid => widget.mode == HomeGridMode.grid;

  @override
  void didUpdateWidget(HomeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final session = _session;
    if (session != null &&
        (!widget.editing ||
            widget.mode != oldWidget.mode ||
            _itemOf(session.id) == null)) {
      _stopScrolling();
      _session = null;
      _drag.value = null;
    }
  }

  @override
  void dispose() {
    _stopScrolling();
    _drag.dispose();
    super.dispose();
  }

  HomeGridItem? _itemOf(String id) {
    for (final item in widget.items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  /// The order sections are drawn in: while one is dragged, where it would
  /// land if it were let go.
  List<String> _order() {
    final ids = [for (final item in widget.items) item.id];
    final session = _session;
    if (session is! _HomeMoveSession) {
      return ids;
    }
    final known = ids.toSet();
    final seen = <String>{};
    return [
      for (final id in session.arranged)
        if (known.contains(id) && seen.add(id)) id,
      for (final id in ids)
        if (seen.add(id)) id,
    ];
  }

  HomeBlockPlacement _placementOf(HomeGridItem item) {
    final session = _session;
    return session != null && session.id == item.id
        ? session.placement
        : item.placement;
  }

  double? _contentHeight(String id) {
    final box = _contentKeys[id]?.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : null;
  }

  double get _columnStep {
    final width = _grid?.size.width ?? 0;
    return (width + widget.columnGap) / homeGridColumns;
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final item in widget.items) item.id: item};
    _contentKeys.removeWhere((id, _) => !byId.containsKey(id));
    final items = [for (final id in _order()) byId[id]!];
    final shown = homeGridShownPlacements(
      [for (final item in items) _placementOf(item)],
      widget.mode,
    );
    final motion = WorkspaceTokens.motion(
      context,
      WorkspaceTokens.transitionDuration,
    );
    final session = _session;
    return _HomeGridLayout(
      key: _layoutKey,
      vsync: this,
      drag: _drag,
      columnGap: widget.columnGap,
      rowGap: widget.rowGap,
      animate: widget.editing && motion > Duration.zero,
      duration: motion,
      textDirection: Directionality.of(context),
      style: _HomeGridStyle.of(context),
      minHeight: session?.height ?? 0,
      children: [
        for (var i = 0; i < items.length; i++)
          _HomeGridTile(
            id: items[i].id,
            column: shown[i].column,
            span: shown[i].span,
            child: RepaintBoundary(
              child: _buildTile(context, items, shown, i),
            ),
          ),
      ],
    );
  }

  Widget _buildTile(
    BuildContext context,
    List<HomeGridItem> items,
    List<HomeBlockPlacement> shown,
    int index,
  ) {
    final item = items[index];
    final rows = shown[index].rows;
    final editing = widget.editing;
    final content = KeyedSubtree(
      key: _contentKeys.putIfAbsent(
        item.id,
        () => GlobalKey(debugLabel: 'home-${item.id}'),
      ),
      child: HomeTileExtent(
        fixed: rows != null,
        child: SizedBox(
          height: rows == null
              ? null
              : homeGridRowsHeight(rows, widget.rowHeight, widget.rowGap),
          // Shown as it is, but not used while it is being arranged.
          child: ExcludeFocus(
            excluding: editing,
            child: IgnorePointer(
              ignoring: editing,
              child: Opacity(
                opacity: editing && item.hidden ? 0.45 : 1,
                child: item.child,
              ),
            ),
          ),
        ),
      ),
    );
    return editing
        ? _buildFrame(context, items, shown, index, content)
        : content;
  }

  Widget _buildFrame(
    BuildContext context,
    List<HomeGridItem> items,
    List<HomeBlockPlacement> shown,
    int index,
    Widget content,
  ) {
    final item = items[index];
    final palette = WorkspacePalette.of(context);
    final session = _session;
    final moving = session is _HomeMoveSession && session.id == item.id;
    final id = item.id;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _HomeMoveRecognizer:
                GestureRecognizerFactoryWithHandlers<_HomeMoveRecognizer>(
              () => _HomeMoveRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = ((_) => _startMove(id))
                ..onUpdate = ((details) =>
                    _updateMove(details.delta, details.globalPosition))
                ..onEnd = ((_) => _finishMove(id, commit: true))
                ..onCancel = (() => _finishMove(id, commit: false)),
            ),
          },
          child: MouseRegion(
            cursor:
                moving ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
            child: DecoratedBox(
              key: ValueKey('home-frame-$id'),
              decoration: BoxDecoration(
                color: palette.hover.withValues(alpha: palette.hover.a * 0.55),
                borderRadius:
                    BorderRadius.circular(WorkspaceTokens.cardRadius + 6),
                border: Border.all(
                  color: palette.accent
                      .withValues(alpha: palette.isDark ? 0.5 : 0.4),
                  width: 1.2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 2, 10, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context, items, shown, index),
                    content,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Narrower windows decide widths themselves, so only heights change
        // there.
        if (_isGrid)
          for (final edge in const [_HomeGripEdge.start, _HomeGripEdge.end])
            PositionedDirectional(
              top: 40,
              start: edge.fromStart ? 0 : null,
              end: edge.fromStart ? null : 0,
              bottom: 20,
              width: 14,
              child: _buildGrip(item, edge),
            ),
        PositionedDirectional(
          start: 20,
          end: 20,
          bottom: 0,
          height: 14,
          child: _buildGrip(item, _HomeGripEdge.bottom),
        ),
        if (_isGrid)
          for (final edge in const [
            _HomeGripEdge.bottomStart,
            _HomeGripEdge.bottomEnd,
          ])
            PositionedDirectional(
              start: edge.fromStart ? 0 : null,
              end: edge.fromStart ? null : 0,
              bottom: 0,
              width: 20,
              height: 20,
              child: _buildGrip(item, edge),
            ),
      ],
    );
  }

  Widget _buildGrip(HomeGridItem item, _HomeGripEdge edge) => _HomeGrip(
        key: ValueKey('home-grip-${edge.name}-${item.id}'),
        edge: edge,
        tooltip: switch (edge) {
          _HomeGripEdge.start ||
          _HomeGripEdge.end =>
            LocaleKeys.landing_resizeWidth.tr(),
          _HomeGripEdge.bottom => LocaleKeys.landing_resizeHeight.tr(),
          _HomeGripEdge.bottomStart ||
          _HomeGripEdge.bottomEnd =>
            LocaleKeys.landing_resizeBoth.tr(),
        },
        onStart: () => _startResize(item.id, edge),
        onUpdate: _updateResize,
        onEnd: (commit) => _finishResize(item.id, commit: commit),
      );

  Widget _buildHeader(
    BuildContext context,
    List<HomeGridItem> items,
    List<HomeBlockPlacement> shown,
    int index,
  ) {
    final item = items[index];
    final palette = WorkspacePalette.of(context);
    final above = _neighbour(shown, index, up: true);
    final below = _neighbour(shown, index, up: false);
    final fits = item.canFit && item.placement.rows != null;
    final up = above == null ? null : () => _reorder(items, index, above);
    final down = below == null ? null : () => _reorder(items, index, below);
    final buttons = 4 + (fits ? 1 : 0) + (item.onConfigure == null ? 0 : 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final glyphs = width >= 100;
        final roomy = width >=
            (glyphs ? 41 : 0) + (item.hidden ? 19 : 0) + buttons * 28 + 40;
        final more = Builder(
          builder: (anchor) => _button(
            context,
            key: 'more',
            id: item.id,
            icon: Icons.more_horiz_rounded,
            tooltip: LocaleKeys.landing_layoutOptions.tr(),
            onPressed: () =>
                _openMenu(anchor, items, shown, index, compact: !roomy),
          ),
        );
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34),
          child: Row(
            children: [
              if (glyphs) ...[
                WorkspaceGlyph(
                  Icons.drag_indicator_rounded,
                  color: palette.mutedText,
                ),
                const SizedBox(width: 2),
                WorkspaceGlyph(item.icon, size: 15, color: palette.accent),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  item.label,
                  key: ValueKey('home-block-label-${item.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.metadata,
                    color: palette.primaryText,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (item.hidden && glyphs)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Tooltip(
                    message: LocaleKeys.landing_hiddenWidget.tr(),
                    child: WorkspaceGlyph(
                      Icons.visibility_off_rounded,
                      size: 15,
                      color: palette.mutedText,
                    ),
                  ),
                ),
              if (roomy) ...[
                _button(
                  context,
                  key: 'up',
                  id: item.id,
                  icon: Icons.keyboard_arrow_up_rounded,
                  tooltip: LocaleKeys.landing_moveUp.tr(),
                  onPressed: up,
                ),
                _button(
                  context,
                  key: 'down',
                  id: item.id,
                  icon: Icons.keyboard_arrow_down_rounded,
                  tooltip: LocaleKeys.landing_moveDown.tr(),
                  onPressed: down,
                ),
                if (fits)
                  _button(
                    context,
                    key: 'fit',
                    id: item.id,
                    icon: Icons.fit_screen_rounded,
                    tooltip: LocaleKeys.landing_fitHeight.tr(),
                    onPressed: () => _resizeTo(item, item.placement.fitted()),
                  ),
              ],
              more,
              if (roomy) ...[
                if (item.onConfigure != null)
                  _button(
                    context,
                    key: 'configure',
                    id: item.id,
                    icon: Icons.tune_rounded,
                    tooltip: LocaleKeys.landing_configure.tr(),
                    onPressed: item.onConfigure,
                  ),
                _button(
                  context,
                  key: 'remove',
                  id: item.id,
                  icon: Icons.close_rounded,
                  tooltip: LocaleKeys.landing_removeFromHome.tr(),
                  onPressed: () => widget.onRemove(item.id),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _button(
    BuildContext context, {
    required String key,
    required String id,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final palette = WorkspacePalette.of(context);
    return IconButton(
      key: ValueKey('home-block-$key-$id'),
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        hoverColor: WorkspaceChrome.hoverColor(context),
      ),
      icon: WorkspaceGlyph(
        icon,
        size: 16,
        color: onPressed == null ? palette.mutedText : palette.secondaryText,
      ),
    );
  }

  /// The section [index] trades places with when moved up or down: the
  /// nearest one sharing its columns, or simply the next one in narrower
  /// windows, where sections follow each other.
  int? _neighbour(
    List<HomeBlockPlacement> shown,
    int index, {
    required bool up,
  }) {
    final placements =
        _isGrid ? shown : List.filled(shown.length, const HomeBlockPlacement());
    return up
        ? homeGridIndexAbove(placements, index)
        : homeGridIndexBelow(placements, index);
  }

  void _reorder(List<HomeGridItem> items, int index, int target) {
    if (_session != null || !widget.editing) {
      return;
    }
    final order = [for (final item in items) item.id];
    final id = order.removeAt(index);
    order.insert(target, id);
    widget.onArrange(order, id, items[index].placement);
  }

  void _resizeTo(HomeGridItem item, HomeBlockPlacement next) {
    if (_session != null || !widget.editing) {
      return;
    }
    final placement = next.clamped();
    if (placement != item.placement) {
      widget.onArrange(_order(), item.id, placement);
    }
  }

  /// Its height in height units: pinned, or what its content fills.
  int _currentRows(HomeGridItem item) =>
      item.placement.rows ??
      homeGridRowsFor(
        _contentHeight(item.id) ?? 0,
        widget.rowHeight,
        widget.rowGap,
        minimum: item.minRows,
      );

  void _openMenu(
    BuildContext anchor,
    List<HomeGridItem> items,
    List<HomeBlockPlacement> shown,
    int index, {
    required bool compact,
  }) {
    if (_session != null) {
      return;
    }
    final item = items[index];
    final placement = item.placement;
    final rows = _currentRows(item);
    final above = _neighbour(shown, index, up: true);
    final below = _neighbour(shown, index, up: false);
    // Columns are counted from the start edge, which is on the right in
    // right-to-left text.
    final leftward = _rtl ? 1 : -1;
    bool inBounds(int column) =>
        column >= 0 && column <= homeGridColumns - placement.span;
    void shift(int by) =>
        _resizeTo(item, placement.copyWith(column: placement.column + by));
    void pin(int rows) => _resizeTo(
          item,
          HomeBlockPlacement(
            column: placement.column,
            span: placement.span,
            rows: rows,
          ),
        );
    showAppMenuForWidget<void>(
      context: anchor,
      entries: [
        if (compact) ...[
          AppMenuItem(
            label: LocaleKeys.landing_moveUp.tr(),
            icon: Icons.arrow_upward_rounded,
            enabled: above != null,
            onSelected: () => _reorder(items, index, above!),
          ),
          AppMenuItem(
            label: LocaleKeys.landing_moveDown.tr(),
            icon: Icons.arrow_downward_rounded,
            enabled: below != null,
            onSelected: () => _reorder(items, index, below!),
          ),
          const AppMenuSeparator(),
        ],
        if (_isGrid) ...[
          AppMenuItem(
            label: LocaleKeys.landing_moveLeft.tr(),
            icon: Icons.west_rounded,
            enabled: inBounds(placement.column + leftward),
            onSelected: () => shift(leftward),
          ),
          AppMenuItem(
            label: LocaleKeys.landing_moveRight.tr(),
            icon: Icons.east_rounded,
            enabled: inBounds(placement.column - leftward),
            onSelected: () => shift(-leftward),
          ),
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.landing_makeWider.tr(),
            icon: Icons.width_wide_rounded,
            enabled: placement.span < homeGridColumns,
            onSelected: () => _resizeTo(
              item,
              HomeBlockPlacement(
                column: math.min(
                  placement.column,
                  homeGridColumns - placement.span - 1,
                ),
                span: placement.span + 1,
                rows: placement.rows,
              ),
            ),
          ),
          AppMenuItem(
            label: LocaleKeys.landing_makeNarrower.tr(),
            icon: Icons.width_normal_rounded,
            enabled: placement.span > item.minSpan,
            onSelected: () => _resizeTo(
              item,
              placement.copyWith(span: placement.span - 1),
            ),
          ),
          const AppMenuSeparator(),
        ],
        AppMenuItem(
          label: LocaleKeys.landing_makeTaller.tr(),
          icon: Icons.unfold_more_rounded,
          enabled: rows < homeMaximumRows,
          onSelected: () => pin(rows + 1),
        ),
        AppMenuItem(
          label: LocaleKeys.landing_makeShorter.tr(),
          icon: Icons.unfold_less_rounded,
          enabled: rows > item.minRows,
          onSelected: () => pin(rows - 1),
        ),
        if (item.canFit)
          AppMenuItem(
            label: LocaleKeys.landing_fitHeight.tr(),
            icon: Icons.fit_screen_rounded,
            enabled: placement.rows != null,
            onSelected: () => _resizeTo(item, placement.fitted()),
          ),
        if (compact) ...[
          const AppMenuSeparator(),
          if (item.onConfigure != null)
            AppMenuItem(
              label: LocaleKeys.landing_configure.tr(),
              icon: Icons.tune_rounded,
              onSelected: item.onConfigure,
            ),
          AppMenuItem(
            label: LocaleKeys.landing_removeFromHome.tr(),
            icon: Icons.close_rounded,
            destructive: true,
            onSelected: () => widget.onRemove(item.id),
          ),
        ],
      ],
    );
  }

  void _startMove(String id) {
    final grid = _grid;
    if (_session != null || !widget.editing || grid == null) {
      return;
    }
    final origin = grid.rectOf(id);
    final byId = {for (final item in widget.items) item.id: item};
    final order = _order();
    final index = order.indexOf(id);
    if (origin == null || index < 0 || byId[id] == null) {
      return;
    }
    final others = [...order]..removeAt(index);
    final heights = grid.heights;
    final placements = homeGridShownPlacements(
      [for (final other in others) byId[other]!.placement],
      widget.mode,
    );
    final reference = packHomeGrid(
      [
        for (var i = 0; i < others.length; i++)
          (
            column: placements[i].column,
            span: placements[i].span,
            height: heights[others[i]] ?? 0,
          ),
      ],
      gap: widget.rowGap,
    );
    _scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    setState(() {
      _session = _HomeMoveSession(
        id: id,
        placement: byId[id]!.placement,
        origin: origin,
        order: order,
        others: others,
        reference: reference,
        originIndex: index,
        height: grid.size.height,
      );
    });
    _drag.value = _HomeGridDrag(id, floating: origin.topLeft);
  }

  void _updateMove(Offset delta, Offset? global) {
    final session = _session;
    final grid = _grid;
    if (session is! _HomeMoveSession || grid == null) {
      return;
    }
    session.travelled += delta;
    final floating = session.origin.topLeft + session.travelled;
    _drag.value = _HomeGridDrag(session.id, floating: floating);
    var placement = session.placement;
    // Narrower windows stack sections, so only the order can change there.
    var columns = const HomeBlockPlacement();
    final step = _columnStep;
    if (_isGrid && step > 0) {
      final start = _rtl
          ? grid.size.width - floating.dx - session.origin.width
          : floating.dx;
      placement = placement.copyWith(
        column:
            (start / step).round().clamp(0, homeGridColumns - placement.span),
      );
      columns = placement;
    }
    final arranged = [...session.others]..insert(
        homeGridInsertionIndex(
          session.reference,
          column: columns.column,
          span: columns.span,
          top: floating.dy,
          origin: session.originIndex,
        ),
        session.id,
      );
    if (placement != session.placement ||
        !listEquals(arranged, session.arranged)) {
      setState(() {
        session
          ..placement = placement
          ..arranged = arranged;
      });
    }
    if (global != null) {
      _scrollNear(global);
    }
  }

  void _finishMove(String id, {required bool commit}) {
    final session = _session;
    if (session is! _HomeMoveSession || session.id != id) {
      return;
    }
    _stopScrolling();
    final item = _itemOf(id);
    if (commit &&
        item != null &&
        (session.placement != item.placement ||
            !listEquals(session.arranged, session.order))) {
      widget.onArrange(_order(), id, session.placement);
    }
    _drag.value = null;
    setState(() => _session = null);
  }

  void _startResize(String id, _HomeGripEdge edge) {
    final grid = _grid;
    final item = _itemOf(id);
    if (_session != null || !widget.editing || grid == null || item == null) {
      return;
    }
    final origin = grid.rectOf(id);
    final content = _contentHeight(id);
    if (origin == null || content == null) {
      return;
    }
    _scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    setState(() {
      _session = _HomeResizeSession(
        id: id,
        placement: item.placement,
        edge: edge,
        origin: origin,
        content: content,
        height: grid.size.height,
        baseRows: item.placement.rows ??
            homeGridRowsFor(
              content,
              widget.rowHeight,
              widget.rowGap,
              minimum: item.minRows,
            ),
      );
    });
    _drag.value = _HomeGridDrag(id, resizing: true);
  }

  void _updateResize(Offset delta, Offset? global) {
    final session = _session;
    final item = _session == null ? null : _itemOf(_session!.id);
    if (session is! _HomeResizeSession || item == null || _grid == null) {
      return;
    }
    session.travelled += delta;
    final start = session.start;
    final edge = session.edge;
    final step = _columnStep;
    var column = start.column;
    var span = start.span;
    if (_isGrid && edge.changesWidth && step > 0) {
      final towardsEnd = _rtl ? -session.travelled.dx : session.travelled.dx;
      final grown = edge.fromStart ? -towardsEnd : towardsEnd;
      // The opposite edge stays put, so it can grow up to the grid's edge on
      // the side it is pulled from.
      final most = edge.fromStart ? start.end : homeGridColumns - start.column;
      span = ((session.origin.width + grown + widget.columnGap) / step)
          .round()
          .clamp(math.min(item.minSpan, most), most);
      if (edge.fromStart) {
        column = start.end - span;
      }
    }
    var rows = start.rows;
    if (edge.changesHeight) {
      final next = homeGridRowsFor(
        math.max(0.0, session.content + session.travelled.dy),
        widget.rowHeight,
        widget.rowGap,
        minimum: item.minRows,
      );
      // Until it is dragged to another height, it stays as tall as its
      // content.
      rows = start.rows == null && item.canFit && next == session.baseRows
          ? null
          : next;
    }
    final placement = HomeBlockPlacement(
      column: column,
      span: span,
      rows: rows,
    );
    // Laid out at its new size as it is dragged, the others making way; only
    // whole columns and height units change anything.
    if (placement != session.placement) {
      setState(() => session.placement = placement);
    }
    if (global != null) {
      _scrollNear(global);
    }
  }

  void _finishResize(String id, {required bool commit}) {
    final session = _session;
    if (session is! _HomeResizeSession || session.id != id) {
      return;
    }
    _stopScrolling();
    if (commit && session.placement != session.start) {
      widget.onArrange(_order(), id, session.placement.clamped());
    }
    _drag.value = null;
    setState(() => _session = null);
  }

  /// Scrolls the page while the pointer is held near its top or bottom.
  void _scrollNear(Offset global) {
    final viewport = _scrollable?.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      return;
    }
    const zone = 72.0;
    final y = viewport.globalToLocal(global).dy;
    final height = viewport.size.height;
    final reach = y < zone
        ? (y - zone) / zone
        : y > height - zone
            ? (y - height + zone) / zone
            : 0.0;
    _scrollReach = reach.clamp(-1.0, 1.0);
    if (_scrollReach == 0) {
      _stopScrolling();
    } else {
      _scrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _scrollStep(),
      );
    }
  }

  void _scrollStep() {
    final scrollable = _scrollable;
    final session = _session;
    if (!mounted ||
        session == null ||
        scrollable == null ||
        !scrollable.mounted) {
      _stopScrolling();
      return;
    }
    final position = scrollable.position;
    final next = (position.pixels + _scrollReach * 16)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final moved = next - position.pixels;
    if (moved == 0) {
      return;
    }
    position.jumpTo(next);
    // The page moved under a pointer that held still, so whatever it holds
    // moves along the page.
    switch (session) {
      case _HomeMoveSession():
        _updateMove(Offset(0, moved), null);
      case _HomeResizeSession():
        _updateResize(Offset(0, moved), null);
    }
  }

  void _stopScrolling() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _scrollReach = 0;
  }
}

/// One edge a section is resized by: a quiet mark that lights up when the
/// pointer reaches it or holds it.
class _HomeGrip extends StatefulWidget {
  const _HomeGrip({
    super.key,
    required this.edge,
    required this.tooltip,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final _HomeGripEdge edge;
  final String tooltip;
  final VoidCallback onStart;
  final void Function(Offset delta, Offset global) onUpdate;

  /// Called with whether the new size should be kept.
  final void Function(bool commit) onEnd;

  @override
  State<_HomeGrip> createState() => _HomeGripState();
}

class _HomeGripState extends State<_HomeGrip> {
  bool _hovered = false;
  bool _held = false;

  void _release(bool commit) {
    if (!_held) {
      return;
    }
    if (mounted) {
      setState(() => _held = false);
    }
    widget.onEnd(commit);
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final color = _hovered || _held
        ? palette.accent.withValues(alpha: 0.85)
        : palette.mutedText.withValues(alpha: 0.6);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );
    // The start side is on the right in right-to-left text.
    final left = widget.edge.fromStart != rtl;
    final (cursor, mark) = switch (widget.edge) {
      _HomeGripEdge.start || _HomeGripEdge.end => (
          SystemMouseCursors.resizeLeftRight,
          bar(3, 26),
        ),
      _HomeGripEdge.bottom => (SystemMouseCursors.resizeUpDown, bar(26, 3)),
      _HomeGripEdge.bottomStart || _HomeGripEdge.bottomEnd => (
          left
              ? SystemMouseCursors.resizeDownLeft
              : SystemMouseCursors.resizeDownRight,
          CustomPaint(
            size: const Size.square(9),
            painter: _CornerMark(color: color, left: left),
          ),
        ),
    };
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _HomeGripRecognizer:
                GestureRecognizerFactoryWithHandlers<_HomeGripRecognizer>(
              () => _HomeGripRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = ((_) {
                  setState(() => _held = true);
                  widget.onStart();
                })
                ..onUpdate = ((details) =>
                    widget.onUpdate(details.delta, details.globalPosition))
                ..onEnd = ((_) => _release(true))
                ..onCancel = (() => _release(false)),
            ),
          },
          child: Center(child: mark),
        ),
      ),
    );
  }
}

/// A section is at least as eager to be picked up as the page under it is to
/// scroll. Sharing the scroll view's threshold lets the deeper recogniser,
/// the section, win; a mouse gets a few pixels of grace so a slightly shaky
/// click on a header button is still a click.
class _HomeMoveRecognizer extends PanGestureRecognizer {
  _HomeMoveRecognizer({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      math.max(
        computeHitSlop(pointerDeviceKind, gestureSettings),
        pointerDeviceKind == PointerDeviceKind.mouse ? 4.0 : 0.0,
      );

  // Two fingers on a trackpad scroll the page, even over a section.
  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}
}

/// A grip keeps its gesture even when the page would take it, so pressing
/// one never scrolls the page instead of resizing.
class _HomeGripRecognizer extends _HomeMoveRecognizer {
  _HomeGripRecognizer({super.debugOwner});

  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}

/// A corner grip's mark: an L along the corner it resizes from.
class _CornerMark extends CustomPainter {
  const _CornerMark({required this.color, required this.left});

  final Color color;

  /// Whether it marks a bottom-left corner rather than a bottom-right one.
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final x = left ? 0.0 : size.width;
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x, size.height)
      ..lineTo(size.width - x, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CornerMark oldDelegate) =>
      color != oldDelegate.color || left != oldDelegate.left;
}
