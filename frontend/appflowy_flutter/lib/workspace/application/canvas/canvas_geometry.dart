import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/foundation.dart';

/// The geometry an infinite canvas is made of. Everything here is pure: it
/// takes numbers and returns numbers, so the feel of panning, snapping and
/// aligning can be tested without building a single widget.

/// How far out and how far in the canvas may be taken.
const double minimumCanvasZoom = 0.1;
const double maximumCanvasZoom = 4.0;

/// How close two edges must be, in screen pixels, before they snap together.
const double canvasSnapTolerance = 7;

/// A card is only picked up after the pointer has really travelled, so an
/// ordinary click that wobbles stays a click.
const double canvasDragThreshold = 4;

/// Where the canvas is being looked at from.
///
/// [offset] is where the scene's origin lands on screen and [zoom] is how many
/// screen pixels one scene unit occupies, which is the whole of the mapping.
@immutable
class CanvasCamera {
  const CanvasCamera({this.offset = Offset.zero, this.zoom = 1});

  final Offset offset;
  final double zoom;

  Offset toScene(Offset screenPoint) => (screenPoint - offset) / zoom;

  Offset toScreen(Offset scenePoint) => scenePoint * zoom + offset;

  Rect sceneToScreen(Rect rect) => Rect.fromLTWH(
        rect.left * zoom + offset.dx,
        rect.top * zoom + offset.dy,
        rect.width * zoom,
        rect.height * zoom,
      );

  Rect screenToScene(Rect rect) => Rect.fromLTWH(
        (rect.left - offset.dx) / zoom,
        (rect.top - offset.dy) / zoom,
        rect.width / zoom,
        rect.height / zoom,
      );

  /// The part of the scene a viewport of [size] can see.
  Rect visibleScene(Size size) => Rect.fromLTWH(
        -offset.dx / zoom,
        -offset.dy / zoom,
        size.width / zoom,
        size.height / zoom,
      );

  CanvasCamera panned(Offset screenDelta) =>
      CanvasCamera(offset: offset + screenDelta, zoom: zoom);

  /// Zoom while keeping whatever is under [screenFocus] exactly there. This is
  /// what makes wheel and pinch zoom feel like the canvas rather than a page.
  CanvasCamera zoomedTo(double nextZoom, {Offset screenFocus = Offset.zero}) {
    final clamped = nextZoom.clamp(minimumCanvasZoom, maximumCanvasZoom);
    if (clamped == zoom) {
      return this;
    }
    final scene = toScene(screenFocus);
    return CanvasCamera(offset: screenFocus - scene * clamped, zoom: clamped);
  }

  CanvasCamera zoomedBy(double factor, {Offset screenFocus = Offset.zero}) =>
      zoomedTo(zoom * factor, screenFocus: screenFocus);

  /// Put [scenePoint] in the middle of a viewport of [size].
  CanvasCamera centeredOn(Offset scenePoint, Size size, {double? atZoom}) {
    final nextZoom =
        (atZoom ?? zoom).clamp(minimumCanvasZoom, maximumCanvasZoom);
    return CanvasCamera(
      offset: Offset(size.width / 2, size.height / 2) - scenePoint * nextZoom,
      zoom: nextZoom,
    );
  }

  /// Frame [content] inside a viewport of [size].
  ///
  /// Never zooms past [maximumFitZoom]: a canvas holding one small card should
  /// not open with that card filling the window.
  static CanvasCamera fittedTo(
    Rect content,
    Size size, {
    double padding = 72,
    double maximumFitZoom = 1.2,
  }) {
    if (size.width < 2 || size.height < 2) {
      return const CanvasCamera();
    }
    if (content.isEmpty || content.width <= 0 || content.height <= 0) {
      return CanvasCamera(
        offset: Offset(size.width / 2, size.height / 2) - content.center,
      );
    }
    final usable = Size(
      math.max(1, size.width - padding * 2),
      math.max(1, size.height - padding * 2),
    );
    final zoom = math
        .min(usable.width / content.width, usable.height / content.height)
        .clamp(minimumCanvasZoom, math.min(maximumFitZoom, maximumCanvasZoom))
        .toDouble();
    return CanvasCamera(
      offset: Offset(size.width / 2, size.height / 2) - content.center * zoom,
      zoom: zoom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasCamera && other.offset == offset && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(offset, zoom);

  @override
  String toString() => 'CanvasCamera(offset: $offset, zoom: $zoom)';
}

/// A line the canvas draws while something is being dragged, to show what it
/// has lined up with.
@immutable
class CanvasGuide {
  const CanvasGuide({
    required this.vertical,
    required this.position,
    required this.start,
    required this.end,
  });

  /// A vertical guide runs down the canvas at x == [position].
  final bool vertical;
  final double position;

  /// How far the guide is drawn, so it reaches only the objects it relates.
  final double start;
  final double end;

  CanvasGuide merged(CanvasGuide other) => CanvasGuide(
        vertical: vertical,
        position: position,
        start: math.min(start, other.start),
        end: math.max(end, other.end),
      );

  @override
  bool operator ==(Object other) =>
      other is CanvasGuide &&
      other.vertical == vertical &&
      other.position == position &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(vertical, position, start, end);
}

/// Where a dragged object landed, and why.
@immutable
class CanvasSnap {
  const CanvasSnap({
    required this.position,
    this.guides = const <CanvasGuide>[],
  });

  final Offset position;
  final List<CanvasGuide> guides;

  @override
  bool operator ==(Object other) =>
      other is CanvasSnap &&
      other.position == position &&
      listEquals(other.guides, guides);

  @override
  int get hashCode => Object.hash(position, guides.length);
}

/// Settle a moving box against a grid and against its neighbours.
///
/// [tolerance] is in SCENE units, so the caller divides the screen tolerance by
/// the zoom — snapping should feel the same distance whatever the zoom is.
CanvasSnap snapCanvasRect({
  required Rect moving,
  required Iterable<Rect> neighbours,
  double gridSize = 0,
  double tolerance = canvasSnapTolerance,
  bool snapToGrid = false,
  bool snapToObjects = true,
}) {
  var x = moving.left;
  var y = moving.top;
  final guides = <CanvasGuide>[];

  if (snapToGrid && gridSize > 0) {
    x = (x / gridSize).round() * gridSize;
    y = (y / gridSize).round() * gridSize;
  }

  if (snapToObjects) {
    final width = moving.width;
    final height = moving.height;

    // Left / centre / right of the moving box against the same three of each
    // neighbour: nine candidates per axis, nearest wins.
    var bestX = tolerance;
    double? snappedX;
    CanvasGuide? guideX;
    var bestY = tolerance;
    double? snappedY;
    CanvasGuide? guideY;

    for (final other in neighbours) {
      for (final entry in <List<double>>[
        <double>[x, other.left],
        <double>[x, other.right],
        <double>[x + width / 2, other.center.dx],
        <double>[x + width, other.left],
        <double>[x + width, other.right],
      ]) {
        final distance = (entry[0] - entry[1]).abs();
        if (distance < bestX) {
          bestX = distance;
          snappedX = x + (entry[1] - entry[0]);
          guideX = CanvasGuide(
            vertical: true,
            position: entry[1],
            start: math.min(y, other.top),
            end: math.max(y + height, other.bottom),
          );
        }
      }
      for (final entry in <List<double>>[
        <double>[y, other.top],
        <double>[y, other.bottom],
        <double>[y + height / 2, other.center.dy],
        <double>[y + height, other.top],
        <double>[y + height, other.bottom],
      ]) {
        final distance = (entry[0] - entry[1]).abs();
        if (distance < bestY) {
          bestY = distance;
          snappedY = y + (entry[1] - entry[0]);
          guideY = CanvasGuide(
            vertical: false,
            position: entry[1],
            start: math.min(x, other.left),
            end: math.max(x + width, other.right),
          );
        }
      }
    }

    if (snappedX != null) {
      x = snappedX;
      guides.add(guideX!);
    }
    if (snappedY != null) {
      y = snappedY;
      guides.add(guideY!);
    }
  }

  return CanvasSnap(position: Offset(x, y), guides: guides);
}

/// Which way a set of selected objects is lined up.
enum CanvasAlign { left, centerX, right, top, centerY, bottom }

/// The new top-left of every box in [rects] once aligned. Boxes that do not
/// move are left out, so the caller can apply the result as a patch.
Map<String, Offset> alignCanvasRects(
  Map<String, Rect> rects,
  CanvasAlign align,
) {
  if (rects.length < 2) {
    return const <String, Offset>{};
  }
  final box = unionOfCanvasRects(rects.values);
  final moved = <String, Offset>{};
  rects.forEach((id, rect) {
    final next = switch (align) {
      CanvasAlign.left => Offset(box.left, rect.top),
      CanvasAlign.centerX => Offset(box.center.dx - rect.width / 2, rect.top),
      CanvasAlign.right => Offset(box.right - rect.width, rect.top),
      CanvasAlign.top => Offset(rect.left, box.top),
      CanvasAlign.centerY => Offset(rect.left, box.center.dy - rect.height / 2),
      CanvasAlign.bottom => Offset(rect.left, box.bottom - rect.height),
    };
    if (next != rect.topLeft) {
      moved[id] = next;
    }
  });
  return moved;
}

/// Space boxes evenly along [axis], keeping the outermost two where they are.
Map<String, Offset> distributeCanvasRects(
  Map<String, Rect> rects,
  CanvasAxis axis,
) {
  if (rects.length < 3) {
    return const <String, Offset>{};
  }
  final entries = rects.entries.toList()
    ..sort(
      (a, b) => axis == CanvasAxis.horizontal
          ? a.value.center.dx.compareTo(b.value.center.dx)
          : a.value.center.dy.compareTo(b.value.center.dy),
    );

  final first = entries.first.value;
  final last = entries.last.value;
  final span = axis == CanvasAxis.horizontal
      ? last.center.dx - first.center.dx
      : last.center.dy - first.center.dy;
  final step = span / (entries.length - 1);

  final moved = <String, Offset>{};
  for (var index = 1; index < entries.length - 1; index++) {
    final entry = entries[index];
    final rect = entry.value;
    final target =
        (axis == CanvasAxis.horizontal ? first.center.dx : first.center.dy) +
            step * index;
    final next = axis == CanvasAxis.horizontal
        ? Offset(target - rect.width / 2, rect.top)
        : Offset(rect.left, target - rect.height / 2);
    if (next != rect.topLeft) {
      moved[entry.key] = next;
    }
  }
  return moved;
}

/// Put an equal gap between boxes along [axis], in reading order.
Map<String, Offset> spaceCanvasRects(
  Map<String, Rect> rects,
  CanvasAxis axis, {
  double gap = 32,
}) {
  if (rects.length < 2) {
    return const <String, Offset>{};
  }
  final entries = rects.entries.toList()
    ..sort(
      (a, b) => axis == CanvasAxis.horizontal
          ? a.value.left.compareTo(b.value.left)
          : a.value.top.compareTo(b.value.top),
    );

  final moved = <String, Offset>{};
  var cursor = axis == CanvasAxis.horizontal
      ? entries.first.value.right
      : entries.first.value.bottom;
  for (var index = 1; index < entries.length; index++) {
    final entry = entries[index];
    final rect = entry.value;
    final next = axis == CanvasAxis.horizontal
        ? Offset(cursor + gap, rect.top)
        : Offset(rect.left, cursor + gap);
    if (next != rect.topLeft) {
      moved[entry.key] = next;
    }
    cursor = axis == CanvasAxis.horizontal
        ? next.dx + rect.width
        : next.dy + rect.height;
  }
  return moved;
}

/// Which axis a distribution runs along. Named apart from Flutter's `Axis` so
/// the presentation layer can import both without an ambiguity.
enum CanvasAxis { horizontal, vertical }

/// The point on a box's edge that a connection meets.
Offset canvasAnchorPoint(Rect rect, CanvasSide side) => switch (side) {
      CanvasSide.top => Offset(rect.center.dx, rect.top),
      CanvasSide.bottom => Offset(rect.center.dx, rect.bottom),
      CanvasSide.left => Offset(rect.left, rect.center.dy),
      CanvasSide.right => Offset(rect.right, rect.center.dy),
      CanvasSide.auto => rect.center,
    };

/// The side of [from] that faces [to]. Boxes mostly beside each other connect
/// left-to-right; boxes mostly above each other connect top-to-bottom.
CanvasSide resolveCanvasSide(Rect from, Rect to) {
  final delta = to.center - from.center;
  if (delta == Offset.zero) {
    return CanvasSide.right;
  }
  // Compare against the boxes' own proportions, so a wide card still connects
  // from its side rather than its top when the other card is barely above it.
  final horizontal = delta.dx.abs() / math.max(1, from.width + to.width);
  final vertical = delta.dy.abs() / math.max(1, from.height + to.height);
  if (horizontal >= vertical) {
    return delta.dx >= 0 ? CanvasSide.right : CanvasSide.left;
  }
  return delta.dy >= 0 ? CanvasSide.bottom : CanvasSide.top;
}

/// A connection, worked out as a cubic curve so it can be drawn and hit tested
/// with the same numbers.
@immutable
class CanvasEdgeGeometry {
  const CanvasEdgeGeometry({
    required this.start,
    required this.end,
    required this.controlStart,
    required this.controlEnd,
    required this.startSide,
    required this.endSide,
  });

  final Offset start;
  final Offset end;
  final Offset controlStart;
  final Offset controlEnd;
  final CanvasSide startSide;
  final CanvasSide endSide;

  /// The point at [t] along the curve, 0 at the start and 1 at the end.
  Offset pointAt(double t) {
    final u = 1 - t;
    return start * (u * u * u) +
        controlStart * (3 * u * u * t) +
        controlEnd * (3 * u * t * t) +
        end * (t * t * t);
  }

  /// Where a label sits, and which way the curve is heading there.
  Offset get midpoint => pointAt(0.5);

  /// The direction the curve arrives at the end, for drawing an arrow head.
  double get endAngle {
    final before = pointAt(0.94);
    final delta = end - before;
    if (delta.distanceSquared < 0.0001) {
      return 0;
    }
    return math.atan2(delta.dy, delta.dx);
  }

  double get startAngle {
    final after = pointAt(0.06);
    final delta = start - after;
    if (delta.distanceSquared < 0.0001) {
      return math.pi;
    }
    return math.atan2(delta.dy, delta.dx);
  }

  /// How far [point] is from the curve, sampled finely enough for hit testing.
  double distanceTo(Offset point, {int samples = 24}) {
    var best = double.infinity;
    var previous = start;
    for (var index = 1; index <= samples; index++) {
      final current = pointAt(index / samples);
      best = math.min(best, _distanceToSegment(point, previous, current));
      previous = current;
    }
    return best;
  }
}

/// Work out the curve joining two boxes.
CanvasEdgeGeometry canvasEdgeGeometry({
  required Rect from,
  required Rect to,
  CanvasSide fromSide = CanvasSide.auto,
  CanvasSide toSide = CanvasSide.auto,
}) {
  final resolvedFrom =
      fromSide == CanvasSide.auto ? resolveCanvasSide(from, to) : fromSide;
  final resolvedTo =
      toSide == CanvasSide.auto ? resolveCanvasSide(to, from) : toSide;

  final start = canvasAnchorPoint(from, resolvedFrom);
  final end = canvasAnchorPoint(to, resolvedTo);

  // The curve leaves each card square to its own edge and only then bends, so
  // two cards side by side are joined by a shape rather than a diagonal.
  final reach = math.max(36.0, (end - start).distance * 0.38);
  return CanvasEdgeGeometry(
    start: start,
    end: end,
    controlStart: start + _sideDirection(resolvedFrom) * reach,
    controlEnd: end + _sideDirection(resolvedTo) * reach,
    startSide: resolvedFrom,
    endSide: resolvedTo,
  );
}

Offset _sideDirection(CanvasSide side) => switch (side) {
      CanvasSide.top => const Offset(0, -1),
      CanvasSide.bottom => const Offset(0, 1),
      CanvasSide.left => const Offset(-1, 0),
      CanvasSide.right => const Offset(1, 0),
      CanvasSide.auto => Offset.zero,
    };

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared < 0.000001) {
    return (point - a).distance;
  }
  final t = (((point - a).dx * ab.dx + (point - a).dy * ab.dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return (point - (a + ab * t)).distance;
}

/// A free spot near [near] that does not sit on top of anything in [taken].
///
/// Used when a card is created without a place of its own — pasted, dropped
/// from the toolbar, or made by a template.
Offset findFreeCanvasSpot({
  required Offset near,
  required Size size,
  required Iterable<Rect> taken,
  double step = 32,
  int attempts = 200,
}) {
  final boxes = taken.toList();
  bool free(Offset candidate) {
    final rect = (candidate & size).inflate(8);
    for (final box in boxes) {
      if (box.overlaps(rect)) {
        return false;
      }
    }
    return true;
  }

  if (free(near)) {
    return near;
  }
  // Spiral outwards, which keeps a new card near where it was asked for
  // instead of marching it off in one direction.
  for (var ring = 1; ring <= attempts; ring++) {
    final radius = step * ring;
    for (var turn = 0; turn < 8; turn++) {
      final angle = turn * math.pi / 4;
      final candidate =
          near + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (free(candidate)) {
        return candidate;
      }
    }
  }
  return near;
}

/// Everything inside a marquee. A box counts as selected when the marquee
/// touches it, which is what a spatial tool is expected to do.
Set<String> canvasObjectsIn(Rect marquee, Map<String, Rect> objects) {
  final normalised = Rect.fromLTRB(
    math.min(marquee.left, marquee.right),
    math.min(marquee.top, marquee.bottom),
    math.max(marquee.left, marquee.right),
    math.max(marquee.top, marquee.bottom),
  );
  return {
    for (final entry in objects.entries)
      if (normalised.overlaps(entry.value)) entry.key,
  };
}
