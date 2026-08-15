import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/workspace/application/canvas/canvas_geometry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/material.dart';

/// Everything on the canvas that is painted rather than laid out: the
/// background pattern, the connections, the freehand strokes and the guides.
///
/// Cards are widgets, because they hold real content — a page preview, a
/// database, a text field. Everything else is paint, because there can be
/// thousands of it and a widget each would not survive a large canvas.

/// The dots, grid or lines behind everything.
///
/// It is drawn from the camera rather than from a huge tiled child, so the
/// cost is the same whether the canvas holds one card or ten thousand.
class CanvasBackgroundPainter extends CustomPainter {
  const CanvasBackgroundPainter({
    required this.camera,
    required this.palette,
    required this.background,
    required this.spacing,
  });

  final CanvasCamera camera;
  final CanvasPalette palette;
  final CanvasBackground background;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.canvas);
    if (background == CanvasBackground.blank || size.isEmpty) {
      return;
    }

    // Step up to a coarser pattern as the canvas is zoomed out, or the dots
    // merge into a wash of grey and the canvas looks dirty rather than ruled.
    var step = spacing * camera.zoom;
    while (step > 0 && step < 9) {
      step *= 4;
    }
    if (step < 4 || !step.isFinite) {
      return;
    }

    // Fade the pattern out as it gets dense, instead of letting it fight the
    // cards for attention.
    final strength = ((step - 8) / 22).clamp(0.15, 1.0);
    final paint = Paint()
      ..color = palette.grid.withValues(
        alpha: palette.grid.a * strength,
      )
      ..strokeWidth = background == CanvasBackground.dots ? 0 : 1;

    final firstX = camera.offset.dx % step;
    final firstY = camera.offset.dy % step;

    switch (background) {
      case CanvasBackground.dots:
        final radius = math.min(1.6, math.max(0.7, step / 26));
        final points = <Offset>[];
        for (var x = firstX; x < size.width + step; x += step) {
          for (var y = firstY; y < size.height + step; y += step) {
            points.add(Offset(x, y));
          }
        }
        // One call for every dot on screen; drawPoints is what makes a dotted
        // background affordable at 120 Hz.
        canvas.drawPoints(
          ui.PointMode.points,
          points,
          paint
            ..strokeWidth = radius * 2
            ..strokeCap = StrokeCap.round,
        );
      case CanvasBackground.grid:
        for (var x = firstX; x < size.width + step; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = firstY; y < size.height + step; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case CanvasBackground.lines:
        for (var y = firstY; y < size.height + step; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case CanvasBackground.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(CanvasBackgroundPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.background != background ||
      oldDelegate.spacing != spacing ||
      oldDelegate.palette.canvas != palette.canvas ||
      oldDelegate.palette.grid != palette.grid;
}

/// One connection, worked out and ready to draw or hit test.
@immutable
class CanvasEdgeDrawing {
  const CanvasEdgeDrawing({
    required this.edge,
    required this.geometry,
    required this.colour,
    this.selected = false,
    this.hovered = false,
  });

  final CanvasEdge edge;
  final CanvasEdgeGeometry geometry;
  final Color colour;
  final bool selected;
  final bool hovered;
}

/// The connections between cards.
class CanvasEdgePainter extends CustomPainter {
  CanvasEdgePainter({
    required this.camera,
    required this.palette,
    required this.edges,
    this.pending,
    this.labelStyle,
  });

  final CanvasCamera camera;
  final CanvasPalette palette;
  final List<CanvasEdgeDrawing> edges;

  /// The line following the pointer while a connection is being made.
  final ({Offset from, Offset to})? pending;

  final TextStyle? labelStyle;

  final Map<String, TextPainter> _labels = <String, TextPainter>{};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.zoom);

    // Widths are divided by the zoom so a connection keeps the same weight on
    // screen however far in the canvas is taken. A hairline that thickens as
    // you zoom reads as a different drawing.
    final width = CanvasMetrics.edgeWidth / camera.zoom;

    for (final drawing in edges) {
      _paintEdge(canvas, drawing, width);
    }

    final live = pending;
    if (live != null) {
      final paint = Paint()
        ..color = palette.accent
        ..strokeWidth = width * 1.15
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(live.from.dx, live.from.dy)
        ..lineTo(live.to.dx, live.to.dy);
      canvas.drawPath(_dash(path, 7 / camera.zoom, 5 / camera.zoom), paint);
      canvas.drawCircle(
        live.to,
        4 / camera.zoom,
        Paint()..color = palette.accent,
      );
    }

    canvas.restore();
  }

  void _paintEdge(Canvas canvas, CanvasEdgeDrawing drawing, double width) {
    final geometry = drawing.geometry;
    final emphasis = drawing.selected ? 1.7 : (drawing.hovered ? 1.3 : 1.0);
    final paint = Paint()
      ..color = drawing.colour
      ..strokeWidth = width * emphasis
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    var path = Path()
      ..moveTo(geometry.start.dx, geometry.start.dy)
      ..cubicTo(
        geometry.controlStart.dx,
        geometry.controlStart.dy,
        geometry.controlEnd.dx,
        geometry.controlEnd.dy,
        geometry.end.dx,
        geometry.end.dy,
      );

    switch (drawing.edge.style) {
      case CanvasEdgeStyle.solid:
        break;
      case CanvasEdgeStyle.dashed:
        path = _dash(path, 9 / camera.zoom, 6 / camera.zoom);
      case CanvasEdgeStyle.dotted:
        path = _dash(path, 1.6 / camera.zoom, 5 / camera.zoom);
    }

    if (drawing.selected) {
      // A soft halo rather than a second, heavier line: a selected connection
      // should stand out without changing shape.
      canvas.drawPath(
        path,
        Paint()
          ..color = drawing.colour.withValues(alpha: 0.22)
          ..strokeWidth = width * 5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawPath(path, paint);

    _paintMarker(
      canvas,
      drawing.edge.endMarker,
      geometry.end,
      geometry.endAngle,
      drawing.colour,
      emphasis,
    );
    _paintMarker(
      canvas,
      drawing.edge.startMarker,
      geometry.start,
      geometry.startAngle,
      drawing.colour,
      emphasis,
    );

    if (drawing.edge.label.trim().isNotEmpty) {
      _paintLabel(canvas, drawing);
    }
  }

  void _paintMarker(
    Canvas canvas,
    CanvasEdgeMarker marker,
    Offset at,
    double angle,
    Color colour,
    double emphasis,
  ) {
    switch (marker) {
      case CanvasEdgeMarker.none:
        return;
      case CanvasEdgeMarker.dot:
        canvas.drawCircle(
          at,
          (CanvasMetrics.arrowSize * 0.34 * emphasis) / camera.zoom,
          Paint()..color = colour,
        );
      case CanvasEdgeMarker.arrow:
        final length = (CanvasMetrics.arrowSize * emphasis) / camera.zoom;
        final spread = 0.42;
        final path = Path()
          ..moveTo(at.dx, at.dy)
          ..lineTo(
            at.dx - length * math.cos(angle - spread),
            at.dy - length * math.sin(angle - spread),
          )
          ..lineTo(
            at.dx - length * 0.72 * math.cos(angle),
            at.dy - length * 0.72 * math.sin(angle),
          )
          ..lineTo(
            at.dx - length * math.cos(angle + spread),
            at.dy - length * math.sin(angle + spread),
          )
          ..close();
        canvas.drawPath(path, Paint()..color = colour);
    }
  }

  void _paintLabel(Canvas canvas, CanvasEdgeDrawing drawing) {
    final label = drawing.edge.label.trim();
    final painter = _labels.putIfAbsent(
      '${drawing.edge.id}|$label',
      () => TextPainter(
        text: TextSpan(
          text: label,
          style: (labelStyle ?? const TextStyle()).copyWith(
            fontSize: 12,
            height: 1.1,
            color: palette.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 190),
    );

    // The label is drawn at a fixed reading size whatever the zoom, so it does
    // not become a smudge when the canvas is taken out.
    final scale = 1 / camera.zoom;
    final centre = drawing.geometry.midpoint;
    final box = Rect.fromCenter(
      center: centre,
      width: (painter.width + 12) * scale,
      height: (painter.height + 6) * scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(5 * scale)),
      Paint()..color = palette.canvas.withValues(alpha: 0.92),
    );
    canvas.save();
    canvas.translate(box.left, box.top);
    canvas.scale(scale);
    painter.paint(canvas, const Offset(6, 3));
    canvas.restore();
  }

  Path _dash(Path source, double on, double off) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final step = draw ? on : off;
        if (draw) {
          dashed.addPath(
            metric.extractPath(
              distance,
              math.min(distance + step, metric.length),
            ),
            Offset.zero,
          );
        }
        distance += step;
        draw = !draw;
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(CanvasEdgePainter oldDelegate) => true;
}

/// The freehand layer.
class CanvasStrokePainter extends CustomPainter {
  const CanvasStrokePainter({
    required this.camera,
    required this.palette,
    required this.strokes,
    this.live,
    this.liveColour,
    this.liveTool = CanvasStrokeTool.pen,
    this.liveWidth = 3,
  });

  final CanvasCamera camera;
  final CanvasPalette palette;
  final List<CanvasStroke> strokes;

  /// The stroke under the pointer right now, not yet committed.
  final List<Offset>? live;
  final int? liveColour;
  final CanvasStrokeTool liveTool;
  final double liveWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty && (live == null || live!.length < 2)) {
      return;
    }
    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.zoom);

    for (final stroke in strokes) {
      _paintStroke(
        canvas,
        stroke.points,
        stroke.tool,
        stroke.color,
        stroke.width,
      );
    }
    final drawing = live;
    if (drawing != null && drawing.length > 1) {
      _paintStroke(canvas, drawing, liveTool, liveColour, liveWidth);
    }
    canvas.restore();
  }

  void _paintStroke(
    Canvas canvas,
    List<Offset> points,
    CanvasStrokeTool tool,
    int? colour,
    double width,
  ) {
    if (points.length < 2) {
      return;
    }
    final ink = colour == null ? palette.textPrimary : palette.accentAt(colour);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      // A highlighter is wide, translucent and multiplies, so overlapping
      // marks darken the way a real one does.
      ..strokeWidth = tool == CanvasStrokeTool.highlighter ? width * 4.5 : width
      ..color = tool == CanvasStrokeTool.highlighter
          ? ink.withValues(alpha: 0.28)
          : ink
      ..blendMode = tool == CanvasStrokeTool.highlighter && !palette.isDark
          ? BlendMode.multiply
          : BlendMode.srcOver;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    // Smooth the recorded points through their midpoints, or a quick gesture
    // is drawn as a chain of straight segments.
    for (var index = 1; index < points.length - 1; index++) {
      final current = points[index];
      final next = points[index + 1];
      path.quadraticBezierTo(
        current.dx,
        current.dy,
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CanvasStrokePainter oldDelegate) => true;
}

/// The lines that appear while something is being lined up, and the marquee.
class CanvasOverlayPainter extends CustomPainter {
  const CanvasOverlayPainter({
    required this.camera,
    required this.palette,
    this.guides = const <CanvasGuide>[],
    this.marquee,
    this.dropTarget,
  });

  final CanvasCamera camera;
  final CanvasPalette palette;
  final List<CanvasGuide> guides;

  /// The selection rectangle, in scene units.
  final Rect? marquee;

  /// The frame a dragged card would land in.
  final Rect? dropTarget;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.zoom);

    if (guides.isNotEmpty) {
      final paint = Paint()
        ..color = palette.guide.withValues(alpha: 0.9)
        ..strokeWidth = 1 / camera.zoom;
      for (final guide in guides) {
        // Reach a little past the objects being lined up, so the guide reads as
        // an alignment rather than as a border.
        const overshoot = 24.0;
        if (guide.vertical) {
          canvas.drawLine(
            Offset(guide.position, guide.start - overshoot),
            Offset(guide.position, guide.end + overshoot),
            paint,
          );
        } else {
          canvas.drawLine(
            Offset(guide.start - overshoot, guide.position),
            Offset(guide.end + overshoot, guide.position),
            paint,
          );
        }
      }
    }

    final target = dropTarget;
    if (target != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          target,
          Radius.circular(CanvasMetrics.frameRadius),
        ),
        Paint()
          ..color = palette.accent.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / camera.zoom,
      );
    }

    final box = marquee;
    if (box != null) {
      canvas
        ..drawRect(box, Paint()..color = palette.accent.withValues(alpha: 0.09))
        ..drawRect(
          box,
          Paint()
            ..color = palette.accent.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / camera.zoom,
        );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(CanvasOverlayPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.marquee != marquee ||
      oldDelegate.dropTarget != dropTarget ||
      oldDelegate.guides.length != guides.length ||
      !_sameGuides(oldDelegate.guides, guides);

  static bool _sameGuides(List<CanvasGuide> a, List<CanvasGuide> b) {
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

/// The whole canvas, drawn small.
class CanvasMinimapPainter extends CustomPainter {
  const CanvasMinimapPainter({
    required this.document,
    required this.palette,
    required this.content,
    required this.viewport,
  });

  final CanvasDocument document;
  final CanvasPalette palette;

  /// The box everything fits in, in scene units.
  final Rect content;

  /// What is on screen, in scene units.
  final Rect viewport;

  @override
  void paint(Canvas canvas, Size size) {
    if (content.isEmpty || size.isEmpty) {
      return;
    }
    final scale = math.min(
      size.width / content.width,
      size.height / content.height,
    );
    final origin = Offset(
      (size.width - content.width * scale) / 2,
      (size.height - content.height * scale) / 2,
    );

    Rect project(Rect rect) => Rect.fromLTWH(
          origin.dx + (rect.left - content.left) * scale,
          origin.dy + (rect.top - content.top) * scale,
          math.max(1.5, rect.width * scale),
          math.max(1.5, rect.height * scale),
        );

    for (final frame in document.frames) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(project(frame.rect), const Radius.circular(2)),
        Paint()..color = palette.accentAt(frame.color).withValues(alpha: 0.14),
      );
    }
    for (final node in document.nodes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(project(node.rect), const Radius.circular(1.5)),
        Paint()
          ..color = node.color == null
              ? palette.textMuted.withValues(alpha: 0.55)
              : palette.accentAt(node.color).withValues(alpha: 0.8),
      );
    }

    // What is on screen, drawn last so it is never hidden by a card.
    final window = project(viewport);
    canvas
      ..drawRect(window, Paint()..color = palette.accent.withValues(alpha: 0.1))
      ..drawRect(
        window,
        Paint()
          ..color = palette.accent.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
  }

  @override
  bool shouldRepaint(CanvasMinimapPainter oldDelegate) =>
      oldDelegate.document != document ||
      oldDelegate.content != content ||
      oldDelegate.viewport != viewport;
}
