import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:appflowy/workspace/application/canvas/canvas_model.dart';

/// Arranging a canvas by hand is the point, so every layout here is a starting
/// position rather than a rule: it returns where things would go, the caller
/// applies it as one undoable change, and the person moves anything they like
/// afterwards.

/// The shapes a canvas can be arranged into.
enum CanvasLayoutKind {
  /// A → B → C, following the connections left to right.
  flow('flow'),

  /// A hierarchy growing downwards from whatever has no parent.
  tree('tree'),

  /// One centre with branches balanced either side of it.
  mindMap('mind_map'),

  /// Reading order in a tidy grid, for a canvas with no connections at all.
  grid('grid');

  const CanvasLayoutKind(this.id);

  final String id;

  static CanvasLayoutKind fromId(String? id) => values.firstWhere(
        (kind) => kind.id == id,
        orElse: () => CanvasLayoutKind.tree,
      );
}

/// The spacing every arrangement is built from.
class CanvasLayoutSpacing {
  const CanvasLayoutSpacing({
    this.alongAxis = 96,
    this.acrossAxis = 40,
    this.columns = 4,
  });

  /// Between one rank and the next — columns in a flow, rows in a tree.
  final double alongAxis;

  /// Between siblings within a rank.
  final double acrossAxis;

  /// How wide a grid arrangement runs before wrapping.
  final int columns;
}

/// Where every arranged object should be put. Objects that would not move are
/// left out, so the result can be applied as a patch.
Map<String, Offset> layOutCanvas(
  CanvasDocument document, {
  CanvasLayoutKind kind = CanvasLayoutKind.tree,
  Iterable<String>? only,
  Offset? origin,
  CanvasLayoutSpacing spacing = const CanvasLayoutSpacing(),
}) {
  final wanted = only?.toSet();
  final nodes = [
    for (final node in document.nodes)
      if (wanted == null || wanted.contains(node.id)) node,
  ];
  if (nodes.length < 2) {
    return const <String, Offset>{};
  }

  final ids = {for (final node in nodes) node.id};
  final edges = [
    for (final edge in document.edges)
      if (ids.contains(edge.from) && ids.contains(edge.to)) edge,
  ];

  final anchor = origin ??
      unionOfCanvasRects([for (final node in nodes) node.rect]).topLeft;

  final placed = switch (kind) {
    CanvasLayoutKind.grid => _gridLayout(nodes, anchor, spacing),
    CanvasLayoutKind.flow =>
      _rankedLayout(nodes, edges, anchor, spacing, horizontal: true),
    CanvasLayoutKind.tree =>
      _rankedLayout(nodes, edges, anchor, spacing, horizontal: false),
    CanvasLayoutKind.mindMap => _mindMapLayout(nodes, edges, anchor, spacing),
  };

  return {
    for (final node in nodes)
      if (placed[node.id] != null && placed[node.id] != node.position)
        node.id: placed[node.id]!,
  };
}

Map<String, Offset> _gridLayout(
  List<CanvasNode> nodes,
  Offset origin,
  CanvasLayoutSpacing spacing,
) {
  // Sort by where things already are, so a tidy-up keeps the arrangement the
  // person had in mind rather than reordering it by id.
  final ordered = [...nodes]..sort((a, b) {
      final row = a.position.dy.compareTo(b.position.dy);
      return row != 0 ? row : a.position.dx.compareTo(b.position.dx);
    });
  final columns = math.max(1, spacing.columns);
  final columnWidth = ordered
      .map((node) => node.size.width)
      .fold<double>(0, (widest, width) => math.max(widest, width));

  final placed = <String, Offset>{};
  var rowTop = origin.dy;
  var rowHeight = 0.0;
  for (var index = 0; index < ordered.length; index++) {
    final node = ordered[index];
    final column = index % columns;
    if (column == 0 && index > 0) {
      rowTop += rowHeight + spacing.acrossAxis;
      rowHeight = 0;
    }
    placed[node.id] = Offset(
      origin.dx + column * (columnWidth + spacing.acrossAxis),
      rowTop,
    );
    rowHeight = math.max(rowHeight, node.size.height);
  }
  return placed;
}

/// A flow or a tree: rank by how far a card is from a root, then pack ranks.
Map<String, Offset> _rankedLayout(
  List<CanvasNode> nodes,
  List<CanvasEdge> edges,
  Offset origin,
  CanvasLayoutSpacing spacing, {
  required bool horizontal,
}) {
  final ranks = _rankNodes(nodes, edges);
  if (ranks.isEmpty) {
    return _gridLayout(nodes, origin, spacing);
  }

  final byId = {for (final node in nodes) node.id: node};
  final byRank = <int, List<String>>{};
  ranks.forEach(
    (id, rank) => byRank.putIfAbsent(rank, () => <String>[]).add(id),
  );

  // Keep siblings in the order their parents were placed in, which is what
  // stops a tree's lines from crossing for no reason.
  final parentOf = <String, String>{};
  for (final edge in edges) {
    final from = ranks[edge.from];
    final to = ranks[edge.to];
    if (from != null && to != null && to == from + 1) {
      parentOf.putIfAbsent(edge.to, () => edge.from);
    }
  }

  final placed = <String, Offset>{};
  final rankOrder = byRank.keys.toList()..sort();
  var alongCursor = horizontal ? origin.dx : origin.dy;
  final orderWithinRank = <String, int>{};

  for (final rank in rankOrder) {
    final members = byRank[rank]!
      ..sort((a, b) {
        final parentA = orderWithinRank[parentOf[a]] ?? 1 << 20;
        final parentB = orderWithinRank[parentOf[b]] ?? 1 << 20;
        if (parentA != parentB) {
          return parentA.compareTo(parentB);
        }
        final nodeA = byId[a]!;
        final nodeB = byId[b]!;
        return horizontal
            ? nodeA.position.dy.compareTo(nodeB.position.dy)
            : nodeA.position.dx.compareTo(nodeB.position.dx);
      });

    var acrossCursor = horizontal ? origin.dy : origin.dx;
    var thickest = 0.0;
    for (var index = 0; index < members.length; index++) {
      final node = byId[members[index]]!;
      orderWithinRank[node.id] = index;
      placed[node.id] = horizontal
          ? Offset(alongCursor, acrossCursor)
          : Offset(acrossCursor, alongCursor);
      acrossCursor += (horizontal ? node.size.height : node.size.width) +
          spacing.acrossAxis;
      thickest = math.max(
        thickest,
        horizontal ? node.size.width : node.size.height,
      );
    }
    alongCursor += thickest + spacing.alongAxis;
  }
  return placed;
}

/// A centre with its branches shared out either side, alternating so the map
/// stays balanced rather than growing to the right for ever.
Map<String, Offset> _mindMapLayout(
  List<CanvasNode> nodes,
  List<CanvasEdge> edges,
  Offset origin,
  CanvasLayoutSpacing spacing,
) {
  final ranks = _rankNodes(nodes, edges);
  if (ranks.isEmpty) {
    return _gridLayout(nodes, origin, spacing);
  }
  final byId = {for (final node in nodes) node.id: node};
  final roots = [
    for (final entry in ranks.entries)
      if (entry.value == 0) entry.key,
  ];
  if (roots.isEmpty) {
    return _gridLayout(nodes, origin, spacing);
  }

  final children = <String, List<String>>{};
  for (final edge in edges) {
    final from = ranks[edge.from];
    final to = ranks[edge.to];
    if (from != null && to != null && to == from + 1) {
      children.putIfAbsent(edge.from, () => <String>[]).add(edge.to);
    }
  }

  final placed = <String, Offset>{};
  final centre = byId[roots.first]!;
  placed[centre.id] = origin;
  final centrePoint = Offset(
    origin.dx + centre.size.width / 2,
    origin.dy + centre.size.height / 2,
  );

  // Each first-level branch takes a side; everything under it follows.
  final branches = children[centre.id] ?? const <String>[];
  final right = <String>[];
  final left = <String>[];
  for (var index = 0; index < branches.length; index++) {
    (index.isEven ? right : left).add(branches[index]);
  }

  void placeSide(List<String> branch, {required bool toTheRight}) {
    final heights = <String, double>{};
    double measure(String id) {
      final own = byId[id]?.size.height ?? 0;
      final kids = children[id] ?? const <String>[];
      final total = kids.isEmpty
          ? own
          : kids.map(measure).fold<double>(0, (sum, height) => sum + height) +
              spacing.acrossAxis * (kids.length - 1);
      final height = math.max(own, total);
      heights[id] = height;
      return height;
    }

    final block = branch.map(measure).fold<double>(
              0,
              (sum, height) => sum + height + spacing.acrossAxis,
            ) -
        (branch.isEmpty ? 0 : spacing.acrossAxis);

    var cursor = centrePoint.dy - block / 2;
    void place(String id, int depth) {
      final node = byId[id];
      if (node == null) {
        return;
      }
      final height = heights[id] ?? node.size.height;
      final along = spacing.alongAxis + centre.size.width / 2;
      final x = toTheRight
          ? centrePoint.dx +
              along +
              (depth - 1) * (node.size.width + spacing.alongAxis)
          : centrePoint.dx -
              along -
              (depth - 1) * (node.size.width + spacing.alongAxis) -
              node.size.width;
      placed[id] = Offset(x, cursor + height / 2 - node.size.height / 2);

      final kids = children[id] ?? const <String>[];
      if (kids.isEmpty) {
        cursor += height + spacing.acrossAxis;
        return;
      }
      final saved = cursor;
      for (final kid in kids) {
        place(kid, depth + 1);
      }
      cursor = saved + height + spacing.acrossAxis;
    }

    for (final id in branch) {
      place(id, 1);
    }
  }

  placeSide(right, toTheRight: true);
  placeSide(left, toTheRight: false);

  // Anything the connections never reached still deserves a place.
  final loose = [
    for (final node in nodes)
      if (!placed.containsKey(node.id)) node,
  ];
  if (loose.isNotEmpty) {
    final used = unionOfCanvasRects([
      for (final entry in placed.entries)
        entry.value & (byId[entry.key]?.size ?? Size.zero),
    ]);
    placed.addAll(
      _gridLayout(
        loose,
        Offset(origin.dx, used.bottom + spacing.alongAxis),
        spacing,
      ),
    );
  }
  return placed;
}

/// How far each card is from a root, following the connections.
///
/// A root is anything nothing points at; a canvas whose connections form a
/// cycle still ranks, because a card is only ever pushed forward once.
Map<String, int> _rankNodes(List<CanvasNode> nodes, List<CanvasEdge> edges) {
  if (edges.isEmpty) {
    return const <String, int>{};
  }
  final incoming = <String, int>{for (final node in nodes) node.id: 0};
  final outgoing = <String, List<String>>{};
  for (final edge in edges) {
    incoming[edge.to] = (incoming[edge.to] ?? 0) + 1;
    outgoing.putIfAbsent(edge.from, () => <String>[]).add(edge.to);
  }

  var roots = [
    for (final entry in incoming.entries)
      if (entry.value == 0) entry.key,
  ];
  if (roots.isEmpty) {
    // Every card is pointed at — a ring. Start from whichever is highest on
    // the canvas, so the arrangement is at least predictable.
    final ordered = [...nodes]
      ..sort((a, b) => a.position.dy.compareTo(b.position.dy));
    roots = [ordered.first.id];
  }

  final ranks = <String, int>{for (final root in roots) root: 0};
  var frontier = roots;
  var depth = 0;
  while (frontier.isNotEmpty && depth < nodes.length) {
    depth++;
    final next = <String>[];
    for (final id in frontier) {
      for (final child in outgoing[id] ?? const <String>[]) {
        if (ranks.containsKey(child)) {
          continue;
        }
        ranks[child] = depth;
        next.add(child);
      }
    }
    frontier = next;
  }

  // A card no connection reached joins the last rank rather than vanishing.
  final deepest = ranks.values.fold<int>(0, math.max);
  for (final node in nodes) {
    ranks.putIfAbsent(node.id, () => deepest + 1);
  }
  return ranks;
}

/// The next place a mind-map child should go, for the Tab/Enter keys.
///
/// Kept separate from the whole-canvas arrangement because pressing Tab should
/// put ONE card down beside its parent, not rearrange everything already there.
Offset nextMindMapChildPosition({
  required Rect parent,
  required Iterable<Rect> siblings,
  required Size size,
  CanvasLayoutSpacing spacing = const CanvasLayoutSpacing(),
  bool toTheRight = true,
}) {
  final x = toTheRight
      ? parent.right + spacing.alongAxis
      : parent.left - spacing.alongAxis - size.width;
  final existing = siblings.toList();
  if (existing.isEmpty) {
    return Offset(x, parent.center.dy - size.height / 2);
  }
  final lowest = existing.fold<double>(
    existing.first.bottom,
    (bottom, rect) => math.max(bottom, rect.bottom),
  );
  return Offset(x, lowest + spacing.acrossAxis);
}

/// The next place a mind-map sibling should go, for Enter.
Offset nextMindMapSiblingPosition({
  required Rect sibling,
  required Size size,
  CanvasLayoutSpacing spacing = const CanvasLayoutSpacing(),
}) =>
    Offset(sibling.left, sibling.bottom + spacing.acrossAxis);
