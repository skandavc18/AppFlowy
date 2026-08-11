import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import 'mermaid_model.dart';

/// The role a piece of ink plays, resolved to a real colour by
/// `MermaidPalette` at paint time.
///
/// Keeping the scene in roles rather than colours is what lets one laid-out
/// diagram be painted in light, dark and paper without being laid out again,
/// and lets the SVG export carry the same appearance.
enum MermaidInk {
  /// The fill of an ordinary node.
  surface,

  /// The fill of a secondary band — a class title strip, a section header.
  surfaceStrong,

  /// The page behind the diagram.
  canvas,

  /// Node outlines and connectors.
  line,

  /// A quieter line, for grids and guides.
  lineSoft,

  /// Primary text.
  text,

  /// Secondary text — edge labels, captions.
  textMuted,

  /// Text drawn on an accent fill.
  onAccent,

  /// The theme accent.
  accent,

  /// A translucent accent wash.
  accentSoft,

  /// A series colour, chosen per element by `MermaidShape.series`.
  series,
}

enum MermaidTextRole { node, label, title, caption, member, mono }

enum MermaidTextAlign { left, center, right }

/// One drawable piece of a laid-out diagram.
///
/// The set is deliberately small: every diagram type is expressed with these,
/// so the painter and the SVG writer each have one place to handle each one.
@immutable
sealed class MermaidShape {
  const MermaidShape();
}

/// A rounded rectangle, ellipse, diamond, hexagon… anything a node wears.
@immutable
class MermaidBoxShape extends MermaidShape {
  const MermaidBoxShape({
    required this.rect,
    required this.shape,
    this.fill = MermaidInk.surface,
    this.stroke = MermaidInk.line,
    this.strokeWidth = 1.4,
    this.dashed = false,
    this.series,
    this.radius = 10,
    this.shadow = true,
  });

  final Rect rect;
  final MermaidNodeShape shape;
  final MermaidInk fill;
  final MermaidInk stroke;
  final double strokeWidth;
  final bool dashed;

  /// Index into the series palette when [fill] or [stroke] is
  /// [MermaidInk.series].
  final int? series;
  final double radius;

  /// Whether the box is lifted off the canvas with a very soft shadow.
  final bool shadow;
}

/// A connector.
///
/// With [cubic] set the four points are read as a single Bézier — start, two
/// controls, end — which is what keeps a flowchart from reading as an old
/// CASE tool. Otherwise the points are joined as a polyline.
@immutable
class MermaidEdgeShape extends MermaidShape {
  const MermaidEdgeShape({
    required this.points,
    this.stroke = MermaidInk.line,
    this.strokeWidth = 1.4,
    this.style = MermaidLineStyle.solid,
    this.head = MermaidArrowHead.none,
    this.tail = MermaidArrowHead.none,
    this.cubic = false,
    this.series,
  });

  final List<Offset> points;
  final MermaidInk stroke;
  final double strokeWidth;
  final MermaidLineStyle style;
  final MermaidArrowHead head;
  final MermaidArrowHead tail;
  final bool cubic;
  final int? series;

  /// The direction the line arrives at its last point, used to aim the head.
  Offset get headDirection {
    if (points.length < 2) {
      return const Offset(1, 0);
    }
    return _unit(points.last - points[points.length - 2]);
  }

  /// The direction the line leaves its first point, used to aim the tail.
  Offset get tailDirection {
    if (points.length < 2) {
      return const Offset(-1, 0);
    }
    return _unit(points.first - points[1]);
  }

  static Offset _unit(Offset value) {
    final length = value.distance;
    return length < 0.0001 ? const Offset(1, 0) : value / length;
  }
}

@immutable
class MermaidTextShape extends MermaidShape {
  const MermaidTextShape({
    required this.text,
    required this.anchor,
    this.role = MermaidTextRole.node,
    this.ink = MermaidInk.text,
    this.align = MermaidTextAlign.center,
    this.maxWidth,
    this.series,
    this.bold = false,
    this.italic = false,
  });

  final String text;

  /// The top-left of the laid-out block for [MermaidTextAlign.left], and the
  /// top-centre / top-right for the other two.
  final Offset anchor;
  final MermaidTextRole role;
  final MermaidInk ink;
  final MermaidTextAlign align;
  final double? maxWidth;
  final int? series;
  final bool bold;
  final bool italic;
}

/// A pie slice or a ring segment.
@immutable
class MermaidArcShape extends MermaidShape {
  const MermaidArcShape({
    required this.rect,
    required this.startAngle,
    required this.sweepAngle,
    required this.series,
    this.stroke = MermaidInk.canvas,
    this.strokeWidth = 2,
  });

  final Rect rect;
  final double startAngle;
  final double sweepAngle;
  final int series;
  final MermaidInk stroke;
  final double strokeWidth;
}

/// A stick figure — the only bespoke glyph a sequence diagram needs.
@immutable
class MermaidActorGlyph extends MermaidShape {
  const MermaidActorGlyph({required this.rect, this.stroke = MermaidInk.line});

  final Rect rect;
  final MermaidInk stroke;
}

/// A laid-out diagram: everything needed to paint it or write it as SVG.
@immutable
class MermaidScene {
  const MermaidScene({
    required this.size,
    required this.shapes,
    this.error,
  });

  const MermaidScene.failed(String message)
      : size = const Size(320, 120),
        shapes = const <MermaidShape>[],
        error = message;

  final Size size;
  final List<MermaidShape> shapes;

  /// Set when the source could not be read; the view draws a notice.
  final String? error;

  bool get isEmpty => shapes.isEmpty && error == null;
}

/// Measures a run of text so layout can size a box around it.
///
/// Passed in rather than reached for, so the layout pass stays pure and can be
/// exercised without a widget tree.
typedef MermaidTextMeasurer = Size Function(
  String text,
  MermaidTextRole role, {
  double? maxWidth,
  bool bold,
});

/// The colours a scene is painted with.
@immutable
class MermaidPalette {
  const MermaidPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceStrong,
    required this.line,
    required this.lineSoft,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.series,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceStrong;
  final Color line;
  final Color lineSoft;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;

  /// A restrained, evenly spaced set used for pie slices, class accents and
  /// journey scores.
  final List<Color> series;

  Color seriesAt(int index) => series[index.abs() % series.length];

  Color resolve(MermaidInk ink, {int? series}) {
    switch (ink) {
      case MermaidInk.canvas:
        return canvas;
      case MermaidInk.surface:
        return surface;
      case MermaidInk.surfaceStrong:
        return surfaceStrong;
      case MermaidInk.line:
        return line;
      case MermaidInk.lineSoft:
        return lineSoft;
      case MermaidInk.text:
        return text;
      case MermaidInk.textMuted:
        return textMuted;
      case MermaidInk.accent:
        return accent;
      case MermaidInk.accentSoft:
        return accentSoft;
      case MermaidInk.onAccent:
        return onAccent;
      case MermaidInk.series:
        return seriesAt(series ?? 0);
    }
  }
}

/// Fixed geometry every diagram is laid out against.
abstract final class MermaidMetrics {
  static const double nodePaddingX = 16;
  static const double nodePaddingY = 11;
  static const double minNodeWidth = 56;
  static const double minNodeHeight = 38;
  static const double rankGap = 62;
  static const double siblingGap = 26;
  static const double diagramPadding = 22;
  static const double edgeLabelPadding = 5;

  static const double actorGap = 46;
  static const double actorHeight = 42;
  static const double messageGap = 44;

  static const double memberRowHeight = 20;

  static double fontSizeFor(MermaidTextRole role) => switch (role) {
        MermaidTextRole.node => 13.5,
        MermaidTextRole.label => 11.5,
        MermaidTextRole.title => 16,
        MermaidTextRole.caption => 11,
        MermaidTextRole.member => 12,
        MermaidTextRole.mono => 12,
      };
}
