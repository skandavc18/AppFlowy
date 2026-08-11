import 'dart:math' as math;
import 'dart:ui';

/// A deterministic pseudo-random source.
///
/// Every element carries a seed, so its wobble is worked out once and never
/// changes between frames — a shape that shimmers while the canvas repaints
/// is the fastest way to make a drawing feel cheap.
class RoughRandom {
  RoughRandom(int seed) : _state = seed == 0 ? 1 : seed & 0x7FFFFFFF;

  int _state;

  double next() {
    // A small xorshift: cheap, stable and good enough for a hand wobble.
    _state ^= _state << 13;
    _state &= 0x7FFFFFFF;
    _state ^= _state >> 17;
    _state ^= _state << 5;
    _state &= 0x7FFFFFFF;
    return _state / 0x7FFFFFFF;
  }

  /// A value in `-amount .. amount`.
  double offset(double amount) => (next() * 2 - 1) * amount;
}

/// Turns geometry into the slightly-off strokes of a drawn line.
///
/// This is a compact reimplementation of the sketching Excalidraw does with
/// roughjs: every straight edge is drawn twice with a gentle bow, and fills
/// are hatched rather than flat. Doing it in Dart is what lets a drawing be
/// painted, exported and themed without a browser.
abstract final class Rough {
  /// How far a stroke may wander for a given roughness and length.
  ///
  /// roughjs displaces by about two pixels whatever the length, shrinking
  /// only on very short runs; scaling with length is what turns a long edge
  /// into a scribble that the editor never draws.
  static double _wobble(double roughness, double length) {
    const maximum = 2.0;
    final offset = length < 20 ? math.max(0.4, length / 10) : maximum;
    return offset * roughness;
  }

  /// One hand-drawn line, as a path with two passes.
  static Path line(
    Offset a,
    Offset b,
    RoughRandom random, {
    double roughness = 1,
    int passes = 2,
  }) {
    final path = Path();
    if (roughness <= 0.01) {
      return path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    final length = (b - a).distance;
    final amount = _wobble(roughness, length);
    for (var pass = 0; pass < passes; pass++) {
      final start =
          a + Offset(random.offset(amount / 2), random.offset(amount / 2));
      final end =
          b + Offset(random.offset(amount / 2), random.offset(amount / 2));
      // Two control points along the run give the bow of a drawn stroke.
      final mid1 = Offset.lerp(a, b, 0.32)! +
          Offset(random.offset(amount), random.offset(amount));
      final mid2 = Offset.lerp(a, b, 0.68)! +
          Offset(random.offset(amount), random.offset(amount));
      path
        ..moveTo(start.dx, start.dy)
        ..cubicTo(mid1.dx, mid1.dy, mid2.dx, mid2.dy, end.dx, end.dy);
    }
    return path;
  }

  /// A closed polygon drawn edge by edge.
  static Path polygon(
    List<Offset> points,
    RoughRandom random, {
    double roughness = 1,
    int passes = 2,
  }) {
    final path = Path();
    if (points.length < 2) {
      return path;
    }
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      path.addPath(
        line(a, b, random, roughness: roughness, passes: passes),
        Offset.zero,
      );
    }
    return path;
  }

  /// A closed polygon whose corners are rounded off.
  static Path roundedPolygon(
    List<Offset> points,
    double radius,
    RoughRandom random, {
    double roughness = 1,
    int passes = 2,
  }) {
    final path = Path();
    if (points.length < 3) {
      return polygon(points, random, roughness: roughness, passes: passes);
    }
    for (var pass = 0; pass < passes; pass++) {
      for (var i = 0; i < points.length; i++) {
        final current = points[i];
        final next = points[(i + 1) % points.length];
        final after = points[(i + 2) % points.length];
        final from = _towards(current, next, radius);
        final to = _towards(next, current, radius);
        path.addPath(
          line(from, to, random, roughness: roughness, passes: 1),
          Offset.zero,
        );
        final corner = _towards(next, after, radius);
        path
          ..moveTo(to.dx, to.dy)
          ..quadraticBezierTo(next.dx, next.dy, corner.dx, corner.dy);
      }
    }
    return path;
  }

  static Offset _towards(Offset from, Offset to, double distance) {
    final delta = to - from;
    final length = delta.distance;
    if (length < 0.001) {
      return from;
    }
    return from + delta * (math.min(distance, length / 2) / length);
  }

  /// An ellipse traced as a wandering closed curve.
  static Path ellipse(
    Rect rect,
    RoughRandom random, {
    double roughness = 1,
    int passes = 2,
  }) {
    final path = Path();
    final centre = rect.center;
    final radiusX = rect.width / 2;
    final radiusY = rect.height / 2;
    if (radiusX <= 0 || radiusY <= 0) {
      return path;
    }
    final amount = _wobble(roughness, math.max(rect.width, rect.height)) * 0.6;
    const steps = 22;

    for (var pass = 0; pass < passes; pass++) {
      final points = <Offset>[];
      final start = random.next() * 0.4;
      for (var i = 0; i <= steps; i++) {
        final angle = start + (i / steps) * math.pi * 2;
        points.add(
          Offset(
            centre.dx + math.cos(angle) * (radiusX + random.offset(amount)),
            centre.dy + math.sin(angle) * (radiusY + random.offset(amount)),
          ),
        );
      }
      path.addPath(_throughPoints(points, closed: true), Offset.zero);
    }
    return path;
  }

  /// A rounded rectangle, drawn as a polygon with its corners cut.
  static Path rectangle(
    Rect rect,
    RoughRandom random, {
    double roughness = 1,
    double radius = 0,
    int passes = 2,
  }) {
    if (radius <= 0.5) {
      return polygon(
        [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft],
        random,
        roughness: roughness,
        passes: passes,
      );
    }
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    final points = <Offset>[
      Offset(rect.left + r, rect.top),
      Offset(rect.right - r, rect.top),
      Offset(rect.right, rect.top + r),
      Offset(rect.right, rect.bottom - r),
      Offset(rect.right - r, rect.bottom),
      Offset(rect.left + r, rect.bottom),
      Offset(rect.left, rect.bottom - r),
      Offset(rect.left, rect.top + r),
    ];
    return polygon(points, random, roughness: roughness, passes: passes);
  }

  /// A smooth curve through freehand points.
  static Path stroke(List<Offset> points) => _throughPoints(points);

  static Path _throughPoints(List<Offset> points, {bool closed = false}) {
    final path = Path();
    if (points.isEmpty) {
      return path;
    }
    if (points.length < 3) {
      path.moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path;
    }
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final midpoint = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    if (closed) {
      path.close();
    }
    return path;
  }

  /// Hatching lines across [shape], used for every fill style but `solid`.
  static Path hachure(
    Path shape,
    Rect bounds,
    RoughRandom random, {
    double gap = 8,
    double angle = -41,
    double roughness = 1,
  }) {
    final result = Path();
    if (bounds.isEmpty) {
      return result;
    }
    final radians = angle * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    final diagonal = bounds.longestSide * 1.5;
    final centre = bounds.center;
    final steps = (diagonal / gap).ceil();

    for (var i = -steps; i <= steps; i++) {
      final offset = i * gap;
      // A line at `angle`, offset perpendicular to itself.
      final origin = centre + Offset(-sin * offset, cos * offset);
      final a = origin + Offset(cos, sin) * -diagonal;
      final b = origin + Offset(cos, sin) * diagonal;
      final clipped = _clipToPath(shape, a, b);
      for (final segment in clipped) {
        result.addPath(
          line(segment.$1, segment.$2, random,
              roughness: roughness * 0.6, passes: 1),
          Offset.zero,
        );
      }
    }
    return result;
  }

  /// Walks a line, keeping the stretches that fall inside [shape].
  ///
  /// Sampling rather than solving is deliberate: it works for any path,
  /// including the wobbly ones this file produces, at a cost that is
  /// invisible next to a repaint.
  static List<(Offset, Offset)> _clipToPath(Path shape, Offset a, Offset b) {
    const samples = 96;
    final segments = <(Offset, Offset)>[];
    Offset? start;
    Offset? previous;
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final point = Offset.lerp(a, b, t)!;
      final inside = shape.contains(point);
      if (inside && start == null) {
        start = point;
      } else if (!inside && start != null) {
        if (previous != null && (previous - start).distance > 1) {
          segments.add((start, previous));
        }
        start = null;
      }
      previous = point;
    }
    if (start != null && previous != null && (previous - start).distance > 1) {
      segments.add((start, previous));
    }
    return segments;
  }
}
