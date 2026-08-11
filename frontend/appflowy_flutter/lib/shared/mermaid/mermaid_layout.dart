import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'mermaid_model.dart';
import 'mermaid_scene.dart';

/// Lays a parsed diagram out into drawable shapes.
///
/// The pass is pure: it takes a [MermaidTextMeasurer] rather than reaching for
/// a widget tree, so the same code runs in a test and in the renderer, and a
/// scene laid out once can be painted in any theme.
MermaidScene layoutMermaid(
  MermaidDocument document,
  MermaidTextMeasurer measure,
) {
  if (document.error != null) {
    return MermaidScene.failed(document.error!);
  }
  switch (document.kind) {
    case MermaidDiagramKind.flowchart:
    case MermaidDiagramKind.classDiagram:
    case MermaidDiagramKind.state:
    case MermaidDiagramKind.entityRelationship:
      final graph = document.graph;
      if (graph == null || graph.nodes.isEmpty) {
        return const MermaidScene(size: Size.zero, shapes: []);
      }
      return _layoutGraph(graph, document.kind, measure);
    case MermaidDiagramKind.sequence:
      return _layoutSequence(document.sequence!, measure);
    case MermaidDiagramKind.pie:
      return _layoutPie(document.pie!, measure);
    case MermaidDiagramKind.mindmap:
      return _layoutMindmap(document.mindmap!, measure);
    case MermaidDiagramKind.timeline:
      return _layoutTimeline(document.timeline!, measure);
    case MermaidDiagramKind.journey:
      return _layoutJourney(document.journey!, measure);
    case MermaidDiagramKind.gantt:
      return _layoutGantt(document.gantt!, measure);
    case MermaidDiagramKind.unsupported:
      return const MermaidScene.failed('Unsupported diagram');
  }
}

// ---------------------------------------------------------------------------
// Directed graph — flowchart, class, state, entity relationship
// ---------------------------------------------------------------------------

class _Placed {
  _Placed(this.node, this.size);

  final MermaidNode node;
  Size size;
  int rank = 0;
  double order = 0;
  double cross = 0;
  double along = 0;

  Rect get rect => Rect.fromLTWH(0, 0, size.width, size.height);
}

const double _maxLabelWidth = 210;

MermaidScene _layoutGraph(
  MermaidGraph graph,
  MermaidDiagramKind kind,
  MermaidTextMeasurer measure,
) {
  final placed = <String, _Placed>{};
  for (final node in graph.nodes) {
    placed[node.id] = _Placed(node, _sizeOfNode(node, measure));
  }

  final edges = graph.edges
      .where((edge) =>
          placed.containsKey(edge.from) && placed.containsKey(edge.to))
      .toList();

  _assignRanks(placed, edges);
  _orderRanks(placed, edges, graph);

  final direction = graph.direction;
  final vertical = direction.isVertical;

  // Extent along the flow axis, one entry per rank.
  final ranks = <int, List<_Placed>>{};
  for (final item in placed.values) {
    ranks.putIfAbsent(item.rank, () => <_Placed>[]).add(item);
  }
  final rankKeys = ranks.keys.toList()..sort();
  for (final key in rankKeys) {
    ranks[key]!.sort((a, b) => a.order.compareTo(b.order));
  }

  var along = 0.0;
  for (final key in rankKeys) {
    final items = ranks[key]!;
    final extent = items
        .map((item) => vertical ? item.size.height : item.size.width)
        .fold<double>(0, math.max);
    for (final item in items) {
      final own = vertical ? item.size.height : item.size.width;
      item.along = along + (extent - own) / 2;
    }
    along += extent + MermaidMetrics.rankGap;
  }
  final alongTotal = math.max(0.0, along - MermaidMetrics.rankGap);

  // Cross axis: pack each rank, keeping members of one subgraph together.
  var crossTotal = 0.0;
  for (final key in rankKeys) {
    final items = ranks[key]!;
    var cursor = 0.0;
    String? previousGroup;
    for (final item in items) {
      final group = item.node.subgraph;
      if (previousGroup != null && group != previousGroup) {
        cursor += MermaidMetrics.siblingGap;
      }
      item.cross = cursor;
      cursor += (vertical ? item.size.width : item.size.height) +
          MermaidMetrics.siblingGap;
      previousGroup = group;
    }
    crossTotal =
        math.max(crossTotal, math.max(0, cursor - MermaidMetrics.siblingGap));
  }

  // Pull each node toward the average of what it is joined to, then re-pack so
  // nothing overlaps. Two passes is enough to straighten most chains.
  for (var pass = 0; pass < 3; pass++) {
    _straighten(ranks, rankKeys, placed, edges, vertical);
  }
  crossTotal = 0;
  for (final key in rankKeys) {
    for (final item in ranks[key]!) {
      crossTotal = math.max(
        crossTotal,
        item.cross + (vertical ? item.size.width : item.size.height),
      );
    }
  }

  // Centre each rank across the widest one.
  for (final key in rankKeys) {
    final items = ranks[key]!;
    final last = items.last;
    final extent = last.cross + (vertical ? last.size.width : last.size.height);
    final shift = (crossTotal - extent) / 2;
    for (final item in items) {
      item.cross += shift;
    }
  }

  Rect rectOf(_Placed item) {
    final crossPos = item.cross;
    final alongPos = direction.isReversed
        ? alongTotal -
            item.along -
            (vertical ? item.size.height : item.size.width)
        : item.along;
    return vertical
        ? Rect.fromLTWH(crossPos, alongPos, item.size.width, item.size.height)
        : Rect.fromLTWH(alongPos, crossPos, item.size.width, item.size.height);
  }

  final rects = <String, Rect>{
    for (final entry in placed.entries) entry.key: rectOf(entry.value),
  };

  final shapes = <MermaidShape>[];

  // Subgraph containers sit behind everything they hold.
  final containers = <MermaidShape>[];
  for (final group in graph.subgraphs) {
    final members = placed.values
        .where((item) => item.node.subgraph == group.id)
        .map((item) => rects[item.node.id]!)
        .toList();
    if (members.isEmpty) {
      continue;
    }
    var bounds = members.first;
    for (final rect in members.skip(1)) {
      bounds = bounds.expandToInclude(rect);
    }
    final labelSize = measure(group.label, MermaidTextRole.caption, bold: true);
    final frame = Rect.fromLTRB(
      bounds.left - 16,
      bounds.top - 16 - labelSize.height,
      bounds.right + 16,
      bounds.bottom + 16,
    );
    containers.add(
      MermaidBoxShape(
        rect: frame,
        shape: MermaidNodeShape.rounded,
        fill: MermaidInk.accentSoft,
        stroke: MermaidInk.lineSoft,
        strokeWidth: 1,
        radius: 14,
        shadow: false,
      ),
    );
    containers.add(
      MermaidTextShape(
        text: group.label,
        anchor: Offset(frame.left + 14, frame.top + 8),
        role: MermaidTextRole.caption,
        ink: MermaidInk.textMuted,
        align: MermaidTextAlign.left,
        bold: true,
      ),
    );
  }
  shapes.addAll(containers);

  // Edges under the boxes, so a connector never crosses a label.
  for (final edge in edges) {
    shapes.addAll(
      _edgeShapes(edge, rects[edge.from]!, rects[edge.to]!, direction, measure),
    );
  }

  for (final item in placed.values) {
    shapes.addAll(_nodeShapes(item.node, rects[item.node.id]!, kind, measure));
  }

  var bounds = _boundsOf(shapes) ?? Rect.zero;
  bounds = bounds.inflate(MermaidMetrics.diagramPadding);
  return MermaidScene(
    size: Size(bounds.width, bounds.height),
    shapes: _translate(shapes, -bounds.topLeft),
  );
}

void _straighten(
  Map<int, List<_Placed>> ranks,
  List<int> rankKeys,
  Map<String, _Placed> placed,
  List<MermaidEdge> edges,
  bool vertical,
) {
  final incoming = <String, List<String>>{};
  final outgoing = <String, List<String>>{};
  for (final edge in edges) {
    incoming.putIfAbsent(edge.to, () => []).add(edge.from);
    outgoing.putIfAbsent(edge.from, () => []).add(edge.to);
  }

  double centreOf(_Placed item) =>
      item.cross + (vertical ? item.size.width : item.size.height) / 2;

  for (final key in rankKeys) {
    final items = ranks[key]!;
    final desired = <_Placed, double>{};
    for (final item in items) {
      final neighbours = <String>[
        ...?incoming[item.node.id],
        ...?outgoing[item.node.id],
      ].where((id) => placed[id] != null && placed[id]!.rank != key).toList();
      if (neighbours.isEmpty) {
        continue;
      }
      final sum = neighbours
          .map((id) => centreOf(placed[id]!))
          .fold<double>(0, (a, b) => a + b);
      desired[item] = sum / neighbours.length;
    }
    if (desired.isEmpty) {
      continue;
    }
    // Move toward the target while keeping order and spacing.
    for (final item in items) {
      final target = desired[item];
      if (target == null) {
        continue;
      }
      final own = vertical ? item.size.width : item.size.height;
      item.cross = item.cross + (target - own / 2 - item.cross) * 0.6;
    }
    items.sort((a, b) => a.cross.compareTo(b.cross));
    var cursor = items.first.cross;
    for (final item in items) {
      if (item.cross < cursor) {
        item.cross = cursor;
      }
      cursor = item.cross +
          (vertical ? item.size.width : item.size.height) +
          MermaidMetrics.siblingGap;
    }
    final shift = items.first.cross;
    if (shift < 0) {
      for (final item in items) {
        item.cross -= shift;
      }
    }
  }

  // Re-base so the smallest cross offset across the whole graph is zero.
  var minimum = double.infinity;
  for (final item in placed.values) {
    minimum = math.min(minimum, item.cross);
  }
  if (minimum.isFinite && minimum != 0) {
    for (final item in placed.values) {
      item.cross -= minimum;
    }
  }
}

/// Longest-path ranking that ignores edges closing a cycle, so a loop does not
/// push a node infinitely far down.
void _assignRanks(Map<String, _Placed> placed, List<MermaidEdge> edges) {
  final children = <String, List<String>>{};
  final indegree = <String, int>{for (final id in placed.keys) id: 0};
  final forward = <MermaidEdge>[];

  final visiting = <String>{};
  final visited = <String>{};
  final adjacency = <String, List<String>>{};
  for (final edge in edges) {
    adjacency.putIfAbsent(edge.from, () => []).add(edge.to);
  }
  final back = <String>{};
  void walk(String id) {
    visiting.add(id);
    for (final next in adjacency[id] ?? const <String>[]) {
      if (visiting.contains(next)) {
        back.add('$id\u0000$next');
        continue;
      }
      if (!visited.contains(next)) {
        walk(next);
      }
    }
    visiting.remove(id);
    visited.add(id);
  }

  for (final id in placed.keys) {
    if (!visited.contains(id)) {
      walk(id);
    }
  }

  for (final edge in edges) {
    if (edge.from == edge.to || back.contains('${edge.from}\u0000${edge.to}')) {
      continue;
    }
    forward.add(edge);
    children.putIfAbsent(edge.from, () => []).add(edge.to);
    indegree[edge.to] = (indegree[edge.to] ?? 0) + 1;
  }

  final queue = <String>[
    for (final entry in indegree.entries)
      if (entry.value == 0) entry.key,
  ];
  if (queue.isEmpty && placed.isNotEmpty) {
    queue.add(placed.keys.first);
  }
  final order = <String>[];
  final remaining = Map<String, int>.from(indegree);
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    order.add(id);
    for (final next in children[id] ?? const <String>[]) {
      remaining[next] = (remaining[next] ?? 1) - 1;
      if (remaining[next] == 0) {
        queue.add(next);
      }
    }
  }
  for (final id in placed.keys) {
    if (!order.contains(id)) {
      order.add(id);
    }
  }
  for (final id in order) {
    final item = placed[id]!;
    for (final next in children[id] ?? const <String>[]) {
      final child = placed[next]!;
      child.rank = math.max(child.rank, item.rank + 1);
    }
  }
}

void _orderRanks(
  Map<String, _Placed> placed,
  List<MermaidEdge> edges,
  MermaidGraph graph,
) {
  var index = 0;
  for (final node in graph.nodes) {
    placed[node.id]!.order = (index++).toDouble();
  }

  final incoming = <String, List<String>>{};
  for (final edge in edges) {
    incoming.putIfAbsent(edge.to, () => []).add(edge.from);
  }

  for (var pass = 0; pass < 4; pass++) {
    for (final item in placed.values) {
      final parents = incoming[item.node.id];
      if (parents == null || parents.isEmpty) {
        continue;
      }
      final sum = parents
          .map((id) => placed[id]?.order ?? item.order)
          .fold<double>(0, (a, b) => a + b);
      item.order = sum / parents.length;
    }
    // Keep members of one subgraph next to each other.
    final groups = <String, List<_Placed>>{};
    for (final item in placed.values) {
      final group = item.node.subgraph;
      if (group != null) {
        groups.putIfAbsent(group, () => []).add(item);
      }
    }
    for (final members in groups.values) {
      final average =
          members.map((item) => item.order).reduce((a, b) => a + b) /
              members.length;
      for (final item in members) {
        item.order = item.order * 0.4 + average * 0.6;
      }
    }
  }
}

Size _sizeOfNode(MermaidNode node, MermaidTextMeasurer measure) {
  if (node.shape == MermaidNodeShape.point) {
    return const Size(18, 18);
  }
  if (node.shape == MermaidNodeShape.record) {
    final title = measure(
      node.label,
      MermaidTextRole.node,
      maxWidth: _maxLabelWidth,
      bold: true,
    );
    var width = title.width;
    for (final member in node.members) {
      width = math.max(
        width,
        measure(member, MermaidTextRole.member, maxWidth: _maxLabelWidth).width,
      );
    }
    final height = title.height +
        MermaidMetrics.nodePaddingY * 2 +
        (node.members.isEmpty
            ? 0
            : node.members.length * MermaidMetrics.memberRowHeight + 12);
    return Size(
      math.max(
          MermaidMetrics.minNodeWidth, width + MermaidMetrics.nodePaddingX * 2),
      height,
    );
  }

  final text =
      measure(node.label, MermaidTextRole.node, maxWidth: _maxLabelWidth);
  var width = text.width + MermaidMetrics.nodePaddingX * 2;
  var height = text.height + MermaidMetrics.nodePaddingY * 2;

  switch (node.shape) {
    case MermaidNodeShape.diamond:
      width *= 1.5;
      height *= 1.7;
    case MermaidNodeShape.circle:
    case MermaidNodeShape.doubleCircle:
      final side = math.max(width, height) * 1.12;
      width = side;
      height = side;
    case MermaidNodeShape.hexagon:
    case MermaidNodeShape.parallelogram:
    case MermaidNodeShape.parallelogramAlt:
    case MermaidNodeShape.trapezoid:
    case MermaidNodeShape.trapezoidAlt:
      width += 26;
    case MermaidNodeShape.cylinder:
      height += 14;
    case MermaidNodeShape.subroutine:
      width += 16;
    case MermaidNodeShape.asymmetric:
      width += 14;
    default:
      break;
  }

  return Size(
    math.max(MermaidMetrics.minNodeWidth, width),
    math.max(MermaidMetrics.minNodeHeight, height),
  );
}

List<MermaidShape> _nodeShapes(
  MermaidNode node,
  Rect rect,
  MermaidDiagramKind kind,
  MermaidTextMeasurer measure,
) {
  if (node.shape == MermaidNodeShape.point) {
    return [
      MermaidBoxShape(
        rect: rect.deflate(3),
        shape: MermaidNodeShape.circle,
        fill: MermaidInk.text,
        stroke: MermaidInk.text,
        strokeWidth: 0,
        shadow: false,
      ),
    ];
  }

  if (node.shape == MermaidNodeShape.record) {
    final title = measure(
      node.label,
      MermaidTextRole.node,
      maxWidth: _maxLabelWidth,
      bold: true,
    );
    final bandHeight = title.height + MermaidMetrics.nodePaddingY * 2;
    final shapes = <MermaidShape>[
      MermaidBoxShape(
        rect: rect,
        shape: MermaidNodeShape.rounded,
        radius: 12,
      ),
      MermaidBoxShape(
        rect: Rect.fromLTWH(rect.left, rect.top, rect.width, bandHeight),
        shape: MermaidNodeShape.rounded,
        fill: node.accent == null ? MermaidInk.accentSoft : MermaidInk.series,
        stroke: MermaidInk.lineSoft,
        strokeWidth: 0,
        radius: 12,
        series: node.accent,
        shadow: false,
      ),
      MermaidTextShape(
        text: node.label,
        anchor: Offset(rect.center.dx, rect.top + MermaidMetrics.nodePaddingY),
        bold: true,
      ),
    ];
    var y = rect.top + bandHeight + 7;
    for (final member in node.members) {
      shapes.add(
        MermaidTextShape(
          text: member,
          anchor: Offset(rect.left + MermaidMetrics.nodePaddingX, y),
          role: MermaidTextRole.member,
          ink: MermaidInk.textMuted,
          align: MermaidTextAlign.left,
          maxWidth: rect.width - MermaidMetrics.nodePaddingX * 2,
        ),
      );
      y += MermaidMetrics.memberRowHeight;
    }
    return shapes;
  }

  final labelSize =
      measure(node.label, MermaidTextRole.node, maxWidth: _maxLabelWidth);
  return [
    MermaidBoxShape(
      rect: rect,
      shape: node.shape,
      fill: node.accent == null ? MermaidInk.surface : MermaidInk.series,
      series: node.accent,
      radius: node.shape == MermaidNodeShape.rectangle ? 4 : 12,
    ),
    MermaidTextShape(
      text: node.label,
      anchor: Offset(rect.center.dx, rect.center.dy - labelSize.height / 2),
      maxWidth: _maxLabelWidth,
    ),
  ];
}

List<MermaidShape> _edgeShapes(
  MermaidEdge edge,
  Rect from,
  Rect to,
  MermaidDirection direction,
  MermaidTextMeasurer measure,
) {
  final vertical = direction.isVertical;
  final downhill = vertical
      ? to.center.dy >= from.center.dy
      : to.center.dx >= from.center.dx;

  Offset exit;
  Offset entry;
  if (vertical) {
    exit = downhill ? from.bottomCenter : from.topCenter;
    entry = downhill ? to.topCenter : to.bottomCenter;
  } else {
    exit = downhill ? from.centerRight : from.centerLeft;
    entry = downhill ? to.centerLeft : to.centerRight;
  }

  final span = entry - exit;
  final reach =
      (vertical ? span.dy.abs() : span.dx.abs()).clamp(24.0, 120.0) * 0.55;
  final control1 = vertical
      ? Offset(exit.dx, exit.dy + (downhill ? reach : -reach))
      : Offset(exit.dx + (downhill ? reach : -reach), exit.dy);
  final control2 = vertical
      ? Offset(entry.dx, entry.dy - (downhill ? reach : -reach))
      : Offset(entry.dx - (downhill ? reach : -reach), entry.dy);

  final shapes = <MermaidShape>[
    MermaidEdgeShape(
      points: [exit, control1, control2, entry],
      style: edge.style,
      head: edge.head,
      tail: edge.tail,
      cubic: true,
      strokeWidth: edge.style == MermaidLineStyle.thick ? 2.4 : 1.4,
    ),
  ];

  if (edge.label.isNotEmpty) {
    final size = measure(edge.label, MermaidTextRole.label, maxWidth: 160);
    final midpoint = _cubicAt(exit, control1, control2, entry, 0.5);
    final box = Rect.fromCenter(
      center: midpoint,
      width: size.width + MermaidMetrics.edgeLabelPadding * 2 + 4,
      height: size.height + MermaidMetrics.edgeLabelPadding,
    );
    shapes.add(
      MermaidBoxShape(
        rect: box,
        shape: MermaidNodeShape.rounded,
        fill: MermaidInk.canvas,
        strokeWidth: 0,
        radius: 6,
        shadow: false,
      ),
    );
    shapes.add(
      MermaidTextShape(
        text: edge.label,
        anchor: Offset(box.center.dx, box.center.dy - size.height / 2),
        role: MermaidTextRole.label,
        ink: MermaidInk.textMuted,
        maxWidth: 160,
      ),
    );
  }

  void cardinality(String text, Offset at, Offset away) {
    if (text.isEmpty) {
      return;
    }
    final size = measure(text, MermaidTextRole.caption, maxWidth: 60);
    final anchor = at + away * 16;
    shapes.add(
      MermaidTextShape(
        text: text,
        anchor: Offset(anchor.dx, anchor.dy - size.height / 2),
        role: MermaidTextRole.caption,
        ink: MermaidInk.textMuted,
      ),
    );
  }

  cardinality(
      edge.fromLabel,
      exit,
      vertical
          ? Offset(1.6, downhill ? 0.6 : -0.6)
          : Offset(downhill ? 0.6 : -0.6, -1.2));
  cardinality(
      edge.toLabel,
      entry,
      vertical
          ? Offset(1.6, downhill ? -0.6 : 0.6)
          : Offset(downhill ? -0.6 : 0.6, -1.2));

  return shapes;
}

Offset _cubicAt(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}

// ---------------------------------------------------------------------------
// Sequence
// ---------------------------------------------------------------------------

MermaidScene _layoutSequence(
  MermaidSequence sequence,
  MermaidTextMeasurer measure,
) {
  if (sequence.actors.isEmpty) {
    return const MermaidScene(size: Size.zero, shapes: []);
  }

  final headWidths = <String, double>{};
  var actorHeight = MermaidMetrics.actorHeight;
  for (final actor in sequence.actors) {
    final size = measure(actor.label, MermaidTextRole.node, maxWidth: 160);
    headWidths[actor.id] =
        math.max(96, size.width + MermaidMetrics.nodePaddingX * 2);
    actorHeight = math.max(actorHeight, size.height + 22);
  }

  // Widen the gap so the longest message on a hop still fits between its two
  // lifelines — a cramped label is the first thing that reads as unfinished.
  final gaps = <int, double>{};
  final ids = sequence.actors.map((actor) => actor.id).toList();
  int indexOf(String id) => ids.indexOf(id);

  for (final step in sequence.steps) {
    if (step.kind != MermaidSequenceStepKind.message) {
      continue;
    }
    final a = indexOf(step.from);
    final b = indexOf(step.to);
    if (a < 0 || b < 0 || a == b) {
      continue;
    }
    final size = measure(step.text, MermaidTextRole.label, maxWidth: 320);
    final needed = size.width + 28;
    final span = (b - a).abs();
    final start = math.min(a, b);
    for (var i = 0; i < span; i++) {
      gaps[start + i] = math.max(gaps[start + i] ?? 0, needed / span);
    }
  }

  final centres = <String, double>{};
  var x = 0.0;
  for (var i = 0; i < ids.length; i++) {
    final width = headWidths[ids[i]]!;
    centres[ids[i]] = x + width / 2;
    final gap = math.max(MermaidMetrics.actorGap, gaps[i] ?? 0);
    x += width + gap;
  }
  final totalWidth =
      x - math.max(MermaidMetrics.actorGap, gaps[ids.length - 1] ?? 0);

  final shapes = <MermaidShape>[];
  var y = actorHeight + 26;
  final openBlocks = <_SequenceBlock>[];
  final blockShapes = <MermaidShape>[];
  var depth = 0;

  for (final step in sequence.steps) {
    switch (step.kind) {
      case MermaidSequenceStepKind.blockStart:
        openBlocks.add(_SequenceBlock(step.keyword, step.text, y, depth));
        depth += 1;
        y += 30;
      case MermaidSequenceStepKind.blockElse:
        if (openBlocks.isNotEmpty) {
          final block = openBlocks.last;
          block.dividers.add((y: y + 6, label: step.text));
        }
        y += 26;
      case MermaidSequenceStepKind.blockEnd:
        if (openBlocks.isNotEmpty) {
          final block = openBlocks.removeLast();
          depth = math.max(0, depth - 1);
          final inset = 16.0 + block.depth * 10;
          final frame = Rect.fromLTRB(
            -inset,
            block.top,
            totalWidth + inset,
            y + 8,
          );
          blockShapes.add(
            MermaidBoxShape(
              rect: frame,
              shape: MermaidNodeShape.rounded,
              fill: MermaidInk.canvas,
              stroke: MermaidInk.lineSoft,
              strokeWidth: 1,
              radius: 12,
              shadow: false,
            ),
          );
          final tabSize = measure('${block.keyword} ${block.label}'.trim(),
              MermaidTextRole.caption);
          blockShapes.add(
            MermaidBoxShape(
              rect: Rect.fromLTWH(
                frame.left,
                frame.top,
                tabSize.width + 20,
                tabSize.height + 10,
              ),
              shape: MermaidNodeShape.rounded,
              fill: MermaidInk.accentSoft,
              stroke: MermaidInk.lineSoft,
              strokeWidth: 0,
              radius: 8,
              shadow: false,
            ),
          );
          blockShapes.add(
            MermaidTextShape(
              text: '${block.keyword} ${block.label}'.trim(),
              anchor: Offset(frame.left + 10, frame.top + 5),
              role: MermaidTextRole.caption,
              ink: MermaidInk.textMuted,
              align: MermaidTextAlign.left,
              bold: true,
            ),
          );
          for (final divider in block.dividers) {
            blockShapes.add(
              MermaidEdgeShape(
                points: [
                  Offset(frame.left, divider.y),
                  Offset(frame.right, divider.y),
                ],
                stroke: MermaidInk.lineSoft,
                strokeWidth: 1,
                style: MermaidLineStyle.dashed,
              ),
            );
            if (divider.label.isNotEmpty) {
              blockShapes.add(
                MermaidTextShape(
                  text: divider.label,
                  anchor: Offset(frame.left + 12, divider.y - 16),
                  role: MermaidTextRole.caption,
                  ink: MermaidInk.textMuted,
                  align: MermaidTextAlign.left,
                ),
              );
            }
          }
          y += 16;
        }
      case MermaidSequenceStepKind.note:
        final size = measure(step.text, MermaidTextRole.label, maxWidth: 220);
        final width = size.width + 24;
        final height = size.height + 18;
        final fromX = centres[step.from] ?? 0;
        final toX = centres[step.to] ?? fromX;
        final left = switch (step.placement) {
          MermaidNotePlacement.leftOf => fromX - width - 18,
          MermaidNotePlacement.rightOf => fromX + 18,
          MermaidNotePlacement.over =>
            (fromX + toX) / 2 - math.max(width, (toX - fromX).abs() + 40) / 2,
        };
        final boxWidth = step.placement == MermaidNotePlacement.over
            ? math.max(width, (toX - fromX).abs() + 40)
            : width;
        shapes.add(
          MermaidBoxShape(
            rect: Rect.fromLTWH(left, y, boxWidth, height),
            shape: MermaidNodeShape.rounded,
            fill: MermaidInk.accentSoft,
            stroke: MermaidInk.lineSoft,
            strokeWidth: 1,
            shadow: false,
          ),
        );
        shapes.add(
          MermaidTextShape(
            text: step.text,
            anchor: Offset(left + boxWidth / 2, y + 9),
            role: MermaidTextRole.label,
            ink: MermaidInk.textMuted,
            maxWidth: 220,
          ),
        );
        y += height + 18;
      case MermaidSequenceStepKind.message:
        final fromX = centres[step.from];
        final toX = centres[step.to];
        if (fromX == null || toX == null) {
          continue;
        }
        final size = measure(step.text, MermaidTextRole.label, maxWidth: 320);
        if (step.from == step.to) {
          final loopWidth = math.max(60.0, size.width * 0.6);
          shapes.add(
            MermaidEdgeShape(
              points: [
                Offset(fromX, y + 6),
                Offset(fromX + loopWidth, y + 6),
                Offset(fromX + loopWidth, y + 30),
                Offset(fromX, y + 30),
              ],
              style: step.style,
              head: step.head,
            ),
          );
          shapes.add(
            MermaidTextShape(
              text: step.text,
              anchor: Offset(fromX + loopWidth + 10, y + 8),
              role: MermaidTextRole.label,
              ink: MermaidInk.textMuted,
              align: MermaidTextAlign.left,
              maxWidth: 320,
            ),
          );
          y += 46;
          continue;
        }
        final lineY = y + size.height + 8;
        shapes.add(
          MermaidTextShape(
            text: step.text,
            anchor: Offset((fromX + toX) / 2, y),
            role: MermaidTextRole.label,
            ink: MermaidInk.textMuted,
            maxWidth: 320,
          ),
        );
        shapes.add(
          MermaidEdgeShape(
            points: [Offset(fromX, lineY), Offset(toX, lineY)],
            style: step.style,
            head: step.head,
          ),
        );
        y = lineY + MermaidMetrics.messageGap * 0.6;
    }
  }

  final bottom = y + 12;

  // Lifelines behind everything.
  final lifelines = <MermaidShape>[];
  for (final actor in sequence.actors) {
    final centre = centres[actor.id]!;
    lifelines.add(
      MermaidEdgeShape(
        points: [Offset(centre, actorHeight), Offset(centre, bottom)],
        stroke: MermaidInk.lineSoft,
        strokeWidth: 1,
        style: MermaidLineStyle.dashed,
      ),
    );
  }

  final heads = <MermaidShape>[];
  for (final actor in sequence.actors) {
    final width = headWidths[actor.id]!;
    final centre = centres[actor.id]!;
    final rect = Rect.fromLTWH(centre - width / 2, 0, width, actorHeight);
    if (actor.isActor) {
      heads.add(
        MermaidActorGlyph(
          rect: Rect.fromLTWH(centre - 13, 0, 26, actorHeight - 16),
        ),
      );
      heads.add(
        MermaidTextShape(
          text: actor.label,
          anchor: Offset(centre, actorHeight - 15),
          role: MermaidTextRole.label,
        ),
      );
    } else {
      heads.add(
        MermaidBoxShape(
            rect: rect, shape: MermaidNodeShape.rounded, radius: 12),
      );
      heads.add(
        MermaidTextShape(
          text: actor.label,
          anchor: Offset(centre, rect.center.dy - 9),
          maxWidth: 160,
        ),
      );
    }
  }

  final all = <MermaidShape>[
    ...blockShapes,
    ...lifelines,
    ...shapes,
    ...heads,
  ];

  var bounds = _boundsOf(all) ?? Rect.zero;
  bounds = bounds.inflate(MermaidMetrics.diagramPadding);
  return MermaidScene(
    size: Size(bounds.width, bounds.height),
    shapes: _translate(all, -bounds.topLeft),
  );
}

class _SequenceBlock {
  _SequenceBlock(this.keyword, this.label, this.top, this.depth);

  final String keyword;
  final String label;
  final double top;
  final int depth;
  final List<({double y, String label})> dividers = [];
}

// ---------------------------------------------------------------------------
// Pie
// ---------------------------------------------------------------------------

MermaidScene _layoutPie(MermaidPie pie, MermaidTextMeasurer measure) {
  final total = pie.total;
  if (pie.slices.isEmpty || total <= 0) {
    return const MermaidScene(size: Size.zero, shapes: []);
  }

  const diameter = 230.0;
  var top = 0.0;
  final shapes = <MermaidShape>[];
  if (pie.title.isNotEmpty) {
    final size = measure(pie.title, MermaidTextRole.title, bold: true);
    shapes.add(
      MermaidTextShape(
        text: pie.title,
        anchor: Offset(diameter / 2, 0),
        role: MermaidTextRole.title,
        bold: true,
      ),
    );
    top = size.height + 18;
  }

  final circle = Rect.fromLTWH(0, top, diameter, diameter);
  var angle = -math.pi / 2;
  for (var i = 0; i < pie.slices.length; i++) {
    final sweep = (pie.slices[i].value / total) * math.pi * 2;
    shapes.add(
      MermaidArcShape(
        rect: circle,
        startAngle: angle,
        sweepAngle: sweep,
        series: i,
      ),
    );
    angle += sweep;
  }

  // A legend reads better than labels crowded round a small circle.
  var legendY = top + 6;
  var legendWidth = 0.0;
  final legendLeft = diameter + 28;
  for (var i = 0; i < pie.slices.length; i++) {
    final slice = pie.slices[i];
    final percent = (slice.value / total) * 100;
    final label = pie.showData
        ? '${slice.label}  ${_trim(slice.value)}'
        : '${slice.label}  ${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%';
    final size = measure(label, MermaidTextRole.label, maxWidth: 210);
    shapes.add(
      MermaidBoxShape(
        rect: Rect.fromLTWH(legendLeft, legendY + 3, 10, 10),
        shape: MermaidNodeShape.rounded,
        fill: MermaidInk.series,
        stroke: MermaidInk.series,
        strokeWidth: 0,
        series: i,
        radius: 3,
        shadow: false,
      ),
    );
    shapes.add(
      MermaidTextShape(
        text: label,
        anchor: Offset(legendLeft + 18, legendY),
        role: MermaidTextRole.label,
        align: MermaidTextAlign.left,
        maxWidth: 210,
      ),
    );
    legendWidth = math.max(legendWidth, size.width + 18);
    legendY += size.height + 10;
  }

  var bounds = _boundsOf(shapes) ?? Rect.zero;
  bounds = bounds.inflate(MermaidMetrics.diagramPadding);
  return MermaidScene(
    size: Size(bounds.width, bounds.height),
    shapes: _translate(shapes, -bounds.topLeft),
  );
}

String _trim(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

// ---------------------------------------------------------------------------
// Mind map
// ---------------------------------------------------------------------------

class _MindBox {
  _MindBox(this.node, this.size, this.depth);

  final MermaidMindNode node;
  final Size size;
  final int depth;
  final List<_MindBox> children = [];
  double y = 0;
  double x = 0;
  double height = 0;
}

MermaidScene _layoutMindmap(MermaidMindNode root, MermaidTextMeasurer measure) {
  _MindBox build(MermaidMindNode node, int depth) {
    final size = measure(node.label, MermaidTextRole.node, maxWidth: 190);
    final box = _MindBox(
      node,
      Size(
        math.max(56, size.width + 30),
        math.max(34, size.height + 18),
      ),
      depth,
    );
    for (final child in node.children) {
      box.children.add(build(child, depth + 1));
    }
    return box;
  }

  final tree = build(root, 0);

  const verticalGap = 14.0;
  const horizontalGap = 54.0;

  double measureHeight(_MindBox box) {
    if (box.children.isEmpty) {
      box.height = box.size.height;
      return box.height;
    }
    var total = 0.0;
    for (final child in box.children) {
      total += measureHeight(child) + verticalGap;
    }
    box.height = math.max(box.size.height, total - verticalGap);
    return box.height;
  }

  measureHeight(tree);

  void place(_MindBox box, double x, double top) {
    box.x = x;
    box.y = top + (box.height - box.size.height) / 2;
    var cursor = top;
    for (final child in box.children) {
      place(child, x + box.size.width + horizontalGap, cursor);
      cursor += child.height + verticalGap;
    }
  }

  place(tree, 0, 0);

  final shapes = <MermaidShape>[];
  void draw(_MindBox box) {
    final rect = Rect.fromLTWH(box.x, box.y, box.size.width, box.size.height);
    if (box.node.label.isNotEmpty) {
      shapes.add(
        MermaidBoxShape(
          rect: rect,
          shape: box.depth == 0 ? MermaidNodeShape.stadium : box.node.shape,
          fill: box.depth == 0 ? MermaidInk.accent : MermaidInk.surface,
          radius: 14,
        ),
      );
      shapes.add(
        MermaidTextShape(
          text: box.node.label,
          anchor: Offset(rect.center.dx, rect.center.dy - 9),
          ink: box.depth == 0 ? MermaidInk.onAccent : MermaidInk.text,
          bold: box.depth <= 1,
          maxWidth: 190,
        ),
      );
    }
    for (final child in box.children) {
      final childRect =
          Rect.fromLTWH(child.x, child.y, child.size.width, child.size.height);
      final start = rect.centerRight;
      final end = childRect.centerLeft;
      final reach = (end.dx - start.dx) * 0.5;
      shapes.add(
        MermaidEdgeShape(
          points: [
            start,
            Offset(start.dx + reach, start.dy),
            Offset(end.dx - reach, end.dy),
            end,
          ],
          cubic: true,
          stroke: MermaidInk.lineSoft,
          strokeWidth: 1.6,
        ),
      );
      draw(child);
    }
  }

  draw(tree);

  var bounds = _boundsOf(shapes) ?? Rect.zero;
  bounds = bounds.inflate(MermaidMetrics.diagramPadding);
  return MermaidScene(
    size: Size(bounds.width, bounds.height),
    shapes: _translate(shapes, -bounds.topLeft),
  );
}

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------

MermaidScene _layoutTimeline(
  MermaidTimeline timeline,
  MermaidTextMeasurer measure,
) {
  final shapes = <MermaidShape>[];
  var top = 0.0;
  if (timeline.title.isNotEmpty) {
    final size = measure(timeline.title, MermaidTextRole.title, bold: true);
    shapes.add(
      MermaidTextShape(
        text: timeline.title,
        anchor: const Offset(0, 0),
        role: MermaidTextRole.title,
        align: MermaidTextAlign.left,
        bold: true,
      ),
    );
    top = size.height + 20;
  }

  const columnWidth = 170.0;
  const columnGap = 18.0;
  var x = 0.0;
  var sectionIndex = 0;
  final axisY = top + 34;
  var maxBottom = axisY;

  for (final section in timeline.sections) {
    final start = x;
    for (final entry in section.entries) {
      final periodSize = measure(entry.period, MermaidTextRole.label,
          maxWidth: columnWidth, bold: true);
      shapes.add(
        MermaidTextShape(
          text: entry.period,
          anchor: Offset(x + columnWidth / 2, axisY - periodSize.height - 14),
          role: MermaidTextRole.label,
          bold: true,
          maxWidth: columnWidth,
        ),
      );
      shapes.add(
        MermaidBoxShape(
          rect: Rect.fromCircle(
              center: Offset(x + columnWidth / 2, axisY), radius: 6),
          shape: MermaidNodeShape.circle,
          fill: MermaidInk.series,
          stroke: MermaidInk.canvas,
          strokeWidth: 2.5,
          series: sectionIndex,
          shadow: false,
        ),
      );
      var cardY = axisY + 22;
      for (final event in entry.events) {
        final size =
            measure(event, MermaidTextRole.label, maxWidth: columnWidth - 24);
        final height = size.height + 18;
        shapes.add(
          MermaidBoxShape(
            rect: Rect.fromLTWH(x, cardY, columnWidth, height),
            shape: MermaidNodeShape.rounded,
          ),
        );
        shapes.add(
          MermaidTextShape(
            text: event,
            anchor: Offset(x + columnWidth / 2, cardY + 9),
            role: MermaidTextRole.label,
            maxWidth: columnWidth - 24,
          ),
        );
        cardY += height + 8;
      }
      maxBottom = math.max(maxBottom, cardY);
      x += columnWidth + columnGap;
    }
    if (section.title.isNotEmpty && x > start) {
      shapes.add(
        MermaidBoxShape(
          rect: Rect.fromLTWH(start, top, x - start - columnGap, 24),
          shape: MermaidNodeShape.rounded,
          fill: MermaidInk.series,
          stroke: MermaidInk.series,
          strokeWidth: 0,
          series: sectionIndex,
          radius: 8,
          shadow: false,
        ),
      );
      shapes.add(
        MermaidTextShape(
          text: section.title,
          anchor: Offset(start + (x - start - columnGap) / 2, top + 4),
          role: MermaidTextRole.caption,
          ink: MermaidInk.onAccent,
          bold: true,
        ),
      );
    }
    sectionIndex += 1;
  }

  if (x > 0) {
    shapes.insert(
      0,
      MermaidEdgeShape(
        points: [Offset(0, axisY), Offset(x - columnGap, axisY)],
        stroke: MermaidInk.lineSoft,
        strokeWidth: 2,
      ),
    );
  }

  var bounds = _boundsOf(shapes) ?? Rect.zero;
  bounds = bounds.inflate(MermaidMetrics.diagramPadding);
  return MermaidScene(
    size: Size(bounds.width, bounds.height),
    shapes: _translate(shapes, -bounds.topLeft),
  );
}

// ---------------------------------------------------------------------------
// Journey
// ---------------------------------------------------------------------------

MermaidScene _layoutJourney(
  MermaidJourney journey,
  MermaidTextMeasurer measure,
) {
  final shapes = <MermaidShape>[];
  var y = 0.0;
  if (journey.title.isNotEmpty) {
    final size = measure(journey.title, MermaidTextRole.title, bold: true);
    shapes.add(
      MermaidTextShape(
        text: journey.title,
        anchor: const Offset(0, 0),
        role: MermaidTextRole.title,
        align: MermaidTextAlign.left,
        bold: true,
      ),
    );
    y = size.height + 18;
  }

  const cardWidth = 180.0;
  const cardGap = 14.0;
  var sectionIndex = 0;

  for (final section in journey.sections) {
    if (section.title.isNotEmpty) {
      final size = measure(section.title, MermaidTextRole.label, bold: true);
      shapes.add(
        MermaidBoxShape(
          rect: Rect.fromLTWH(0, y, size.width + 22, size.height + 10),
          shape: MermaidNodeShape.rounded,
          fill: MermaidInk.series,
          stroke: MermaidInk.series,
          strokeWidth: 0,
          series: sectionIndex,
          radius: 8,
          shadow: false,
        ),
      );
      shapes.add(
        MermaidTextShape(
          text: section.title,
          anchor: Offset(11, y + 5),
          role: MermaidTextRole.label,
          ink: MermaidInk.onAccent,
          align: MermaidTextAlign.left,
          bold: true,
        ),
      );
      y += size.height + 20;
    }

    var x = 0.0;
    var rowHeight = 0.0;
    for (final task in section.tasks) {
      final labelSize =
          measure(task.label, MermaidTextRole.label, maxWidth: cardWidth - 24);
      final actors = task.actors.join(', ');
      final actorSize = actors.isEmpty
          ? Size.zero
          : measure(actors, MermaidTextRole.caption, maxWidth: cardWidth - 24);
      final height = labelSize.height + actorSize.height + 40;
      final rect = Rect.fromLTWH(x, y, cardWidth, height);
      shapes.add(
        MermaidBoxShape(
            rect: rect, shape: MermaidNodeShape.rounded, radius: 12),
      );
      shapes.add(
        MermaidTextShape(
          text: task.label,
          anchor: Offset(x + 12, y + 12),
          role: MermaidTextRole.label,
          align: MermaidTextAlign.left,
          maxWidth: cardWidth - 24,
        ),
      );
      if (actors.isNotEmpty) {
        shapes.add(
          MermaidTextShape(
            text: actors,
            anchor: Offset(x + 12, y + 12 + labelSize.height + 4),
            role: MermaidTextRole.caption,
            ink: MermaidInk.textMuted,
            align: MermaidTextAlign.left,
            maxWidth: cardWidth - 24,
          ),
        );
      }
      // Five dots reading the score, so state is never colour alone.
      for (var i = 0; i < 5; i++) {
        shapes.add(
          MermaidBoxShape(
            rect: Rect.fromCircle(
              center: Offset(x + 16 + i * 15, rect.bottom - 15),
              radius: 4.5,
            ),
            shape: MermaidNodeShape.circle,
            fill: i < task.score ? MermaidInk.series : MermaidInk.lineSoft,
            stroke: MermaidInk.lineSoft,
            strokeWidth: 0,
            series: _journeySeries(task.score),
            shadow: false,
          ),
        );
      }
      rowHeight = math.max(rowHeight, height);
      x += cardWidth + cardGap;
    }
    y += rowHeight + 22;
    sectionIndex += 1;
  }

  var bounds = _boundsOf(shapes) ?? Rect.zero;
  bounds = bounds.inflate(MermaidMetrics.diagramPadding);
  return MermaidScene(
    size: Size(bounds.width, bounds.height),
    shapes: _translate(shapes, -bounds.topLeft),
  );
}

int _journeySeries(int score) => switch (score) {
      >= 5 => 2,
      4 => 2,
      3 => 4,
      _ => 3,
    };

// ---------------------------------------------------------------------------
// Gantt
// ---------------------------------------------------------------------------

MermaidScene _layoutGantt(MermaidGantt gantt, MermaidTextMeasurer measure) {
  final earliest = gantt.earliest;
  final latest = gantt.latest;
  if (earliest == null || latest == null) {
    return const MermaidScene(size: Size.zero, shapes: []);
  }
  final span = math.max(1, latest.difference(earliest).inMinutes).toDouble();

  var labelWidth = 120.0;
  for (final section in gantt.sections) {
    for (final task in section.tasks) {
      labelWidth = math.max(
        labelWidth,
        measure(task.label, MermaidTextRole.label, maxWidth: 220).width + 16,
      );
    }
  }

  const chartWidth = 520.0;
  const rowHeight = 30.0;
  var y = 0.0;
  final shapes = <MermaidShape>[];

  if (gantt.title.isNotEmpty) {
    final size = measure(gantt.title, MermaidTextRole.title, bold: true);
    shapes.add(
      MermaidTextShape(
        text: gantt.title,
        anchor: const Offset(0, 0),
        role: MermaidTextRole.title,
        align: MermaidTextAlign.left,
        bold: true,
      ),
    );
    y = size.height + 18;
  }

  final axisTop = y;
  y += 24;

  double xFor(DateTime moment) =>
      labelWidth + (moment.difference(earliest).inMinutes / span) * chartWidth;

  var sectionIndex = 0;
  for (final section in gantt.sections) {
    if (section.title.isNotEmpty) {
      shapes.add(
        MermaidTextShape(
          text: section.title,
          anchor: Offset(0, y + 4),
          role: MermaidTextRole.label,
          align: MermaidTextAlign.left,
          bold: true,
        ),
      );
      y += 24;
    }
    for (final task in section.tasks) {
      final left = xFor(task.start);
      final right = math.max(left + 6, xFor(task.end));
      shapes.add(
        MermaidTextShape(
          text: task.label,
          anchor: Offset(0, y + 6),
          role: MermaidTextRole.label,
          ink: MermaidInk.textMuted,
          align: MermaidTextAlign.left,
          maxWidth: labelWidth - 12,
        ),
      );
      if (task.milestone) {
        shapes.add(
          MermaidBoxShape(
            rect: Rect.fromCenter(
              center: Offset(left, y + rowHeight / 2 - 4),
              width: 16,
              height: 16,
            ),
            shape: MermaidNodeShape.diamond,
            fill: MermaidInk.accent,
            stroke: MermaidInk.accent,
            strokeWidth: 0,
            shadow: false,
          ),
        );
      } else {
        shapes.add(
          MermaidBoxShape(
            rect: Rect.fromLTWH(left, y, right - left, rowHeight - 10),
            shape: MermaidNodeShape.rounded,
            fill: task.done ? MermaidInk.lineSoft : MermaidInk.series,
            stroke: MermaidInk.lineSoft,
            strokeWidth: task.active ? 1.6 : 0,
            series: sectionIndex,
            radius: 7,
            shadow: false,
          ),
        );
      }
      y += rowHeight;
    }
    sectionIndex += 1;
  }

  // The axis, drawn last so its extent is known but inserted underneath.
  final axisShapes = <MermaidShape>[
    MermaidEdgeShape(
      points: [
        Offset(labelWidth, axisTop + 18),
        Offset(labelWidth + chartWidth, axisTop + 18),
      ],
      stroke: MermaidInk.lineSoft,
      strokeWidth: 1,
    ),
  ];
  for (var i = 0; i <= 4; i++) {
    final at = earliest.add(Duration(minutes: (span * i / 4).round()));
    final x = labelWidth + chartWidth * i / 4;
    axisShapes.add(
      MermaidTextShape(
        text: _shortDate(at),
        anchor: Offset(x, axisTop),
        role: MermaidTextRole.caption,
        ink: MermaidInk.textMuted,
      ),
    );
    axisShapes.add(
      MermaidEdgeShape(
        points: [Offset(x, axisTop + 18), Offset(x, y)],
        stroke: MermaidInk.lineSoft,
        strokeWidth: 1,
        style: MermaidLineStyle.dotted,
      ),
    );
  }

  final all = <MermaidShape>[...axisShapes, ...shapes];
  var bounds = _boundsOf(all) ?? Rect.zero;
  bounds = bounds.inflate(MermaidMetrics.diagramPadding);
  return MermaidScene(
    size: Size(bounds.width, bounds.height),
    shapes: _translate(all, -bounds.topLeft),
  );
}

String _shortDate(DateTime moment) =>
    '${moment.day.toString().padLeft(2, '0')}/${moment.month.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Rect? _boundsOf(List<MermaidShape> shapes) {
  Rect? bounds;
  void include(Rect rect) {
    bounds = bounds == null ? rect : bounds!.expandToInclude(rect);
  }

  for (final shape in shapes) {
    switch (shape) {
      case MermaidBoxShape():
        include(shape.rect);
      case MermaidArcShape():
        include(shape.rect);
      case MermaidActorGlyph():
        include(shape.rect);
      case MermaidEdgeShape():
        for (final point in shape.points) {
          include(Rect.fromCenter(center: point, width: 2, height: 2));
        }
      case MermaidTextShape():
        // Text is measured at paint time; a generous box keeps it inside.
        final width = shape.maxWidth ?? 160;
        final left = switch (shape.align) {
          MermaidTextAlign.left => shape.anchor.dx,
          MermaidTextAlign.center => shape.anchor.dx - width / 2,
          MermaidTextAlign.right => shape.anchor.dx - width,
        };
        include(Rect.fromLTWH(left, shape.anchor.dy, width, 20));
    }
  }
  return bounds;
}

List<MermaidShape> _translate(List<MermaidShape> shapes, Offset delta) => [
      for (final shape in shapes)
        switch (shape) {
          MermaidBoxShape() => MermaidBoxShape(
              rect: shape.rect.shift(delta),
              shape: shape.shape,
              fill: shape.fill,
              stroke: shape.stroke,
              strokeWidth: shape.strokeWidth,
              dashed: shape.dashed,
              series: shape.series,
              radius: shape.radius,
              shadow: shape.shadow,
            ),
          MermaidEdgeShape() => MermaidEdgeShape(
              points: [for (final point in shape.points) point + delta],
              stroke: shape.stroke,
              strokeWidth: shape.strokeWidth,
              style: shape.style,
              head: shape.head,
              tail: shape.tail,
              cubic: shape.cubic,
              series: shape.series,
            ),
          MermaidTextShape() => MermaidTextShape(
              text: shape.text,
              anchor: shape.anchor + delta,
              role: shape.role,
              ink: shape.ink,
              align: shape.align,
              maxWidth: shape.maxWidth,
              series: shape.series,
              bold: shape.bold,
              italic: shape.italic,
            ),
          MermaidArcShape() => MermaidArcShape(
              rect: shape.rect.shift(delta),
              startAngle: shape.startAngle,
              sweepAngle: shape.sweepAngle,
              series: shape.series,
              stroke: shape.stroke,
              strokeWidth: shape.strokeWidth,
            ),
          MermaidActorGlyph() => MermaidActorGlyph(
              rect: shape.rect.shift(delta),
              stroke: shape.stroke,
            ),
        },
    ];
