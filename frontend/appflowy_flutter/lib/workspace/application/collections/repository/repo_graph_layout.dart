import 'dart:math' as math;

import 'package:appflowy/workspace/application/collections/repository/repo_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The most files the graph draws before it starts leaving the least
/// connected ones out. Past this a web is unreadable anyway, and the layout
/// is quadratic in the node count.
const int maxRepoGraphNodes = 220;

/// One placed file in the dependency graph.
@immutable
class RepoGraphNode {
  const RepoGraphNode({
    required this.path,
    required this.position,
    required this.radius,
    required this.degree,
  });

  final String path;
  final Offset position;
  final double radius;
  final int degree;
}

/// A graph laid out inside a box.
@immutable
class RepoGraphLayoutResult {
  const RepoGraphLayoutResult({
    required this.nodes,
    required this.edges,
  });

  static const empty = RepoGraphLayoutResult(nodes: {}, edges: []);

  final Map<String, RepoGraphNode> nodes;
  final List<(String, String)> edges;

  bool get isEmpty => nodes.isEmpty;
}

/// Arranges [degrees] inside [size].
///
/// Deterministic: the starting positions come from a hash of each path, so
/// the same repository is drawn the same way every time it is opened rather
/// than reshuffling on each rebuild.
RepoGraphLayoutResult layoutRepoGraph({
  required Map<String, int> degrees,
  required List<(String, String)> edges,
  required RepoGraphLayout layout,
  required Size size,
}) {
  if (degrees.isEmpty || size.shortestSide <= 0) {
    return RepoGraphLayoutResult.empty;
  }
  final ranked = degrees.entries.toList()
    ..sort((a, b) {
      final byDegree = b.value.compareTo(a.value);
      return byDegree != 0 ? byDegree : a.key.compareTo(b.key);
    });
  final kept = ranked.take(maxRepoGraphNodes).toList();
  final paths = {for (final entry in kept) entry.key};
  final liveEdges = [
    for (final edge in edges)
      if (paths.contains(edge.$1) &&
          paths.contains(edge.$2) &&
          edge.$1 != edge.$2)
        edge,
  ];

  final positions = switch (layout) {
    RepoGraphLayout.force => _forceLayout(kept, liveEdges, size),
    RepoGraphLayout.radial => _radialLayout(kept, size),
    RepoGraphLayout.layered => _layeredLayout(kept, liveEdges, size),
  };

  final maxDegree = kept.first.value.clamp(1, 1 << 30);
  return RepoGraphLayoutResult(
    nodes: {
      for (final entry in kept)
        entry.key: RepoGraphNode(
          path: entry.key,
          position: positions[entry.key] ?? size.center(Offset.zero),
          radius: 4 + 8 * math.sqrt(entry.value / maxDegree),
          degree: entry.value,
        ),
    },
    edges: liveEdges,
  );
}

/// A stable pseudo-random start, so the same project keeps the same shape.
double _seeded(String value, int salt) {
  var hash = 0x811c9dc5 ^ salt;
  for (final unit in value.codeUnits) {
    hash = (hash ^ unit) * 0x01000193 & 0x7fffffff;
  }
  return (hash % 10007) / 10007;
}

Map<String, Offset> _forceLayout(
  List<MapEntry<String, int>> nodes,
  List<(String, String)> edges,
  Size size,
) {
  final count = nodes.length;
  final width = size.width;
  final height = size.height;
  final positions = <String, Offset>{
    for (final node in nodes)
      node.key: Offset(
        width * (0.12 + 0.76 * _seeded(node.key, 7)),
        height * (0.12 + 0.76 * _seeded(node.key, 31)),
      ),
  };
  if (count == 1) {
    return {nodes.first.key: size.center(Offset.zero)};
  }

  final k = math.sqrt(width * height / count);
  // Big graphs need fewer passes to look settled and cost more per pass.
  final iterations = count <= 60
      ? 240
      : count <= 140
          ? 150
          : 90;
  var temperature = math.min(width, height) / 8;
  final cooling = temperature / (iterations + 1);
  final displacement = <String, Offset>{};

  for (var step = 0; step < iterations; step++) {
    for (final node in nodes) {
      displacement[node.key] = Offset.zero;
    }
    for (var i = 0; i < count; i++) {
      final a = nodes[i].key;
      final pa = positions[a]!;
      for (var j = i + 1; j < count; j++) {
        final b = nodes[j].key;
        final delta = pa - positions[b]!;
        final distance = math.max(delta.distance, 0.01);
        final force = k * k / distance;
        final push = delta / distance * force;
        displacement[a] = displacement[a]! + push;
        displacement[b] = displacement[b]! - push;
      }
    }
    for (final edge in edges) {
      final delta = positions[edge.$1]! - positions[edge.$2]!;
      final distance = math.max(delta.distance, 0.01);
      final pull = delta / distance * (distance * distance / k);
      displacement[edge.$1] = displacement[edge.$1]! - pull;
      displacement[edge.$2] = displacement[edge.$2]! + pull;
    }
    for (final node in nodes) {
      final delta = displacement[node.key]!;
      final distance = math.max(delta.distance, 0.01);
      final step = delta / distance * math.min(distance, temperature);
      final moved = positions[node.key]! + step;
      positions[node.key] = Offset(
        moved.dx.clamp(18.0, math.max(width - 18, 18.0)),
        moved.dy.clamp(18.0, math.max(height - 18, 18.0)),
      );
    }
    temperature = math.max(temperature - cooling, 0.1);
  }
  return positions;
}

/// The most connected files in the middle, the rest on rings around them.
Map<String, Offset> _radialLayout(
  List<MapEntry<String, int>> nodes,
  Size size,
) {
  final centre = size.center(Offset.zero);
  final maxRadius = size.shortestSide / 2 - 24;
  final positions = <String, Offset>{};
  var index = 0;
  var ring = 0;
  while (index < nodes.length) {
    // Each ring holds a few more than the one inside it.
    final capacity = ring == 0 ? 1 : (ring * 6);
    final take = math.min(capacity, nodes.length - index);
    final radius =
        nodes.length == 1 ? 0.0 : maxRadius * (ring / _ringCount(nodes.length));
    for (var slot = 0; slot < take; slot++) {
      final angle = take == 1 ? 0.0 : 2 * math.pi * slot / take;
      positions[nodes[index + slot].key] =
          centre + Offset(radius * math.cos(angle), radius * math.sin(angle));
    }
    index += take;
    ring += 1;
  }
  return positions;
}

int _ringCount(int count) {
  var ring = 0;
  var placed = 0;
  while (placed < count) {
    placed += ring == 0 ? 1 : ring * 6;
    ring += 1;
  }
  return math.max(ring - 1, 1);
}

/// Files that depend on nothing at the top, everything that needs them below.
Map<String, Offset> _layeredLayout(
  List<MapEntry<String, int>> nodes,
  List<(String, String)> edges,
  Size size,
) {
  final dependencies = <String, Set<String>>{
    for (final node in nodes) node.key: <String>{},
  };
  for (final edge in edges) {
    dependencies[edge.$1]?.add(edge.$2);
  }
  final layerOf = <String, int>{};
  final remaining = {for (final node in nodes) node.key};
  var layer = 0;
  while (remaining.isNotEmpty && layer < 40) {
    final ready = [
      for (final path in remaining)
        if (!dependencies[path]!.any(remaining.contains)) path,
    ];
    // A cycle leaves nothing ready; everything left shares the last layer.
    final placing = ready.isEmpty ? remaining.toList() : ready;
    for (final path in placing) {
      layerOf[path] = layer;
    }
    remaining.removeAll(placing);
    layer += 1;
  }

  final layers = <int, List<String>>{};
  for (final node in nodes) {
    layers.putIfAbsent(layerOf[node.key] ?? 0, () => []).add(node.key);
  }
  final depth = layers.keys.isEmpty ? 1 : layers.keys.reduce(math.max) + 1;
  final positions = <String, Offset>{};
  for (final entry in layers.entries) {
    final y = depth == 1
        ? size.height / 2
        : 30 + (size.height - 60) * (entry.key / (depth - 1));
    final row = entry.value..sort();
    for (var index = 0; index < row.length; index++) {
      final x = row.length == 1
          ? size.width / 2
          : 30 + (size.width - 60) * (index / (row.length - 1));
      positions[row[index]] = Offset(x, y);
    }
  }
  return positions;
}
