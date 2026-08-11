import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import 'mind_map_model.dart';

/// Which way a branch grows from the trunk.
enum MindMapSide { left, right }

/// How a whole map is arranged.
enum MindMapLayoutMode {
  /// Branches balanced either side of the root — the classic mind map.
  balanced,

  /// Everything grows to the right, which reads better for a deep outline.
  rightward,
}

/// Where one node ended up.
@immutable
class MindMapPlacement {
  const MindMapPlacement({
    required this.node,
    required this.rect,
    required this.depth,
    required this.side,
    required this.parentId,
    required this.hiddenChildren,
  });

  final MindMapNode node;
  final Rect rect;
  final int depth;
  final MindMapSide side;
  final String? parentId;

  /// How many nodes are folded away under this one, so the collapse marker
  /// can say so instead of just being a dot.
  final int hiddenChildren;

  /// Where a connector leaves this node toward its children.
  Offset get outward =>
      side == MindMapSide.right ? rect.centerRight : rect.centerLeft;

  /// Where a connector from the parent arrives.
  Offset get inward =>
      side == MindMapSide.right ? rect.centerLeft : rect.centerRight;
}

/// A connector between two placed nodes.
@immutable
class MindMapLink {
  const MindMapLink({
    required this.fromId,
    required this.toId,
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
    required this.depth,
    required this.colorIndex,
  });

  final String fromId;
  final String toId;
  final Offset start;
  final Offset control1;
  final Offset control2;
  final Offset end;
  final int depth;
  final int colorIndex;
}

/// A laid-out map.
@immutable
class MindMapLayout {
  const MindMapLayout({
    required this.size,
    required this.placements,
    required this.links,
  });

  static const MindMapLayout empty = MindMapLayout(
    size: Size.zero,
    placements: <MindMapPlacement>[],
    links: <MindMapLink>[],
  );

  final Size size;
  final List<MindMapPlacement> placements;
  final List<MindMapLink> links;

  MindMapPlacement? placementFor(String id) {
    for (final placement in placements) {
      if (placement.node.id == id) {
        return placement;
      }
    }
    return null;
  }

  /// The topmost node under [point], searched back to front so a node drawn
  /// later wins.
  MindMapPlacement? hitTest(Offset point) {
    for (final placement in placements.reversed) {
      if (placement.rect.inflate(2).contains(point)) {
        return placement;
      }
    }
    return null;
  }
}

/// Measures a node so the layout knows how much room it needs.
typedef MindMapNodeSizer = Size Function(MindMapNode node, int depth);

/// Fixed geometry the layout and the canvas agree on.
abstract final class MindMapMetrics {
  static const double horizontalGap = 56;
  static const double verticalGap = 14;
  static const double padding = 48;
  static const double collapseMarker = 18;

  /// The accent a node wears when it has not chosen one: branches take their
  /// colour from the trunk they hang off, which is what makes a large map
  /// readable at a glance.
  static int accentFor(MindMapNode node, int branchIndex) =>
      node.colorIndex ?? branchIndex;
}

class _Box {
  _Box(this.node, this.size, this.depth, this.side, this.parentId, this.branch);

  final MindMapNode node;
  final Size size;
  final int depth;
  final MindMapSide side;
  final String? parentId;
  final int branch;
  final List<_Box> children = <_Box>[];

  double extent = 0;
  double x = 0;
  double y = 0;

  int get hidden => node.collapsed ? node.flattened.length - 1 : 0;
}

/// Lays a mind map out.
///
/// Pure: it takes a sizer rather than reaching for a widget tree, so the same
/// arithmetic runs in a test, in the canvas and in the exporter — and a very
/// large map is laid out once per change rather than once per frame.
MindMapLayout layoutMindMap(
  MindMapDocument document,
  MindMapNodeSizer sizeOf, {
  MindMapLayoutMode mode = MindMapLayoutMode.balanced,
}) {
  final rootSize = sizeOf(document.root, 0);
  final rootBox = _Box(document.root, rootSize, 0, MindMapSide.right, null, -1);

  final visibleChildren =
      document.root.collapsed ? const <MindMapNode>[] : document.root.children;

  // Split the trunk's branches between the two sides so a wide map stays
  // compact rather than trailing off the right edge.
  final rightCount = mode == MindMapLayoutMode.rightward
      ? visibleChildren.length
      : (visibleChildren.length / 2).ceil();

  _Box build(
    MindMapNode node,
    int depth,
    MindMapSide side,
    String? parentId,
    int branch,
  ) {
    final box = _Box(node, sizeOf(node, depth), depth, side, parentId, branch);
    if (!node.collapsed) {
      for (final child in node.children) {
        box.children.add(build(child, depth + 1, side, node.id, branch));
      }
    }
    return box;
  }

  for (var i = 0; i < visibleChildren.length; i++) {
    final side = i < rightCount ? MindMapSide.right : MindMapSide.left;
    rootBox.children
        .add(build(visibleChildren[i], 1, side, document.root.id, i));
  }

  double measure(_Box box) {
    if (box.children.isEmpty) {
      box.extent = box.size.height;
      return box.extent;
    }
    var total = 0.0;
    for (final child in box.children) {
      total += measure(child) + MindMapMetrics.verticalGap;
    }
    box.extent = math.max(
      box.size.height,
      total - MindMapMetrics.verticalGap,
    );
    return box.extent;
  }

  final right =
      rootBox.children.where((box) => box.side == MindMapSide.right).toList();
  final left =
      rootBox.children.where((box) => box.side == MindMapSide.left).toList();

  double measureSide(List<_Box> boxes) {
    var total = 0.0;
    for (final box in boxes) {
      total += measure(box) + MindMapMetrics.verticalGap;
    }
    return boxes.isEmpty ? 0 : total - MindMapMetrics.verticalGap;
  }

  final rightExtent = measureSide(right);
  final leftExtent = measureSide(left);
  final height = math.max(
    rootSize.height,
    math.max(rightExtent, leftExtent),
  );

  rootBox.x = 0;
  rootBox.y = (height - rootSize.height) / 2;

  void place(_Box box, double top) {
    box.y = top + (box.extent - box.size.height) / 2;
    var cursor = top;
    for (final child in box.children) {
      // A branch keeps the side it started on, so a child always steps one
      // gap further out from its parent.
      child.x = child.side == MindMapSide.right
          ? box.x + box.size.width + MindMapMetrics.horizontalGap
          : box.x - MindMapMetrics.horizontalGap - child.size.width;
      place(child, cursor);
      cursor += child.extent + MindMapMetrics.verticalGap;
    }
  }

  var cursor = (height - rightExtent) / 2;
  for (final box in right) {
    box.x = rootBox.x + rootSize.width + MindMapMetrics.horizontalGap;
    place(box, cursor);
    cursor += box.extent + MindMapMetrics.verticalGap;
  }
  cursor = (height - leftExtent) / 2;
  for (final box in left) {
    box.x = rootBox.x - MindMapMetrics.horizontalGap - box.size.width;
    place(box, cursor);
    cursor += box.extent + MindMapMetrics.verticalGap;
  }

  // Gather, shifting everything into positive space with a margin.
  var bounds =
      Rect.fromLTWH(rootBox.x, rootBox.y, rootSize.width, rootSize.height);
  void expand(_Box box) {
    bounds = bounds.expandToInclude(
      Rect.fromLTWH(box.x, box.y, box.size.width, box.size.height),
    );
    for (final child in box.children) {
      expand(child);
    }
  }

  for (final box in rootBox.children) {
    expand(box);
  }

  final shift = Offset(
    -bounds.left + MindMapMetrics.padding,
    -bounds.top + MindMapMetrics.padding,
  );

  final placements = <MindMapPlacement>[];
  final links = <MindMapLink>[];

  void collect(_Box box) {
    final rect = Rect.fromLTWH(box.x, box.y, box.size.width, box.size.height)
        .shift(shift);
    placements.add(
      MindMapPlacement(
        node: box.node,
        rect: rect,
        depth: box.depth,
        side: box.side,
        parentId: box.parentId,
        hiddenChildren: box.hidden,
      ),
    );
    for (final child in box.children) {
      final childRect =
          Rect.fromLTWH(child.x, child.y, child.size.width, child.size.height)
              .shift(shift);
      final start =
          child.side == MindMapSide.right ? rect.centerRight : rect.centerLeft;
      final end = child.side == MindMapSide.right
          ? childRect.centerLeft
          : childRect.centerRight;
      final reach = (end.dx - start.dx) * 0.5;
      links.add(
        MindMapLink(
          fromId: box.node.id,
          toId: child.node.id,
          start: start,
          control1: Offset(start.dx + reach, start.dy),
          control2: Offset(end.dx - reach, end.dy),
          end: end,
          depth: child.depth,
          colorIndex: MindMapMetrics.accentFor(child.node, child.branch),
        ),
      );
      collect(child);
    }
  }

  collect(rootBox);

  final laidOut = bounds.shift(shift);
  return MindMapLayout(
    size: Size(
      laidOut.right + MindMapMetrics.padding,
      laidOut.bottom + MindMapMetrics.padding,
    ),
    placements: placements,
    links: links,
  );
}
