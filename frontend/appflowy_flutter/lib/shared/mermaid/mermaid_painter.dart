import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'mermaid_model.dart';
import 'mermaid_scene.dart';

/// The type faces a diagram is set in.
///
/// Derived from the page's own body style so a diagram is lettered like the
/// paragraph above it rather than in a renderer's default face.
@immutable
class MermaidTypography {
  const MermaidTypography({required this.base, required this.mono});

  final TextStyle base;
  final TextStyle mono;

  TextStyle styleFor(MermaidTextRole role,
      {bool bold = false, bool italic = false}) {
    final source =
        role == MermaidTextRole.mono || role == MermaidTextRole.member
            ? mono
            : base;
    return source.copyWith(
      fontSize: MermaidMetrics.fontSizeFor(role),
      height: 1.32,
      fontWeight: bold ? FontWeight.w600 : null,
      fontStyle: italic ? FontStyle.italic : null,
      letterSpacing: role == MermaidTextRole.title ? -0.2 : 0,
    );
  }
}

/// Measures text with a real [TextPainter], for the layout pass.
MermaidTextMeasurer mermaidMeasurer(
  MermaidTypography typography, {
  double textScale = 1,
}) {
  final cache = <String, Size>{};
  return (text, role, {double? maxWidth, bool bold = false}) {
    if (text.isEmpty) {
      return Size.zero;
    }
    final key = '$text|${role.index}|$maxWidth|$bold';
    final hit = cache[key];
    if (hit != null) {
      return hit;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: typography.styleFor(role, bold: bold),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: TextScaler.linear(textScale),
      maxLines: 6,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final size = Size(painter.width, painter.height);
    painter.dispose();
    cache[key] = size;
    return size;
  };
}

/// Paints a laid-out [MermaidScene].
class MermaidPainter extends CustomPainter {
  MermaidPainter({
    required this.scene,
    required this.palette,
    required this.typography,
    this.textScale = 1,
  });

  final MermaidScene scene;
  final MermaidPalette palette;
  final MermaidTypography typography;
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in scene.shapes) {
      switch (shape) {
        case MermaidBoxShape():
          _paintBox(canvas, shape);
        case MermaidEdgeShape():
          _paintEdge(canvas, shape);
        case MermaidTextShape():
          _paintText(canvas, shape);
        case MermaidArcShape():
          _paintArc(canvas, shape);
        case MermaidActorGlyph():
          _paintActor(canvas, shape);
      }
    }
  }

  void _paintBox(Canvas canvas, MermaidBoxShape shape) {
    final path = mermaidShapePath(shape.rect, shape.shape, shape.radius);
    if (shape.shadow) {
      canvas.drawShadow(
        path,
        palette.line.withValues(alpha: 0.30),
        2.5,
        true,
      );
    }
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = palette.resolve(shape.fill, series: shape.series);
    canvas.drawPath(path, fill);

    if (shape.strokeWidth > 0) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = palette.resolve(shape.stroke, series: shape.series);
      canvas.drawPath(
        shape.dashed ? _dash(path, const [5, 4]) : path,
        stroke,
      );
    }

    if (shape.shape == MermaidNodeShape.doubleCircle) {
      final inner = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.strokeWidth
        ..color = palette.resolve(shape.stroke, series: shape.series);
      canvas.drawOval(shape.rect.deflate(5), inner);
    }
    if (shape.shape == MermaidNodeShape.subroutine) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.strokeWidth
        ..color = palette.resolve(shape.stroke, series: shape.series);
      canvas.drawLine(
        Offset(shape.rect.left + 8, shape.rect.top),
        Offset(shape.rect.left + 8, shape.rect.bottom),
        line,
      );
      canvas.drawLine(
        Offset(shape.rect.right - 8, shape.rect.top),
        Offset(shape.rect.right - 8, shape.rect.bottom),
        line,
      );
    }
    if (shape.shape == MermaidNodeShape.cylinder) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.strokeWidth
        ..color = palette.resolve(shape.stroke, series: shape.series);
      canvas.drawArc(
        Rect.fromLTWH(shape.rect.left, shape.rect.top, shape.rect.width, 14),
        0,
        math.pi,
        false,
        line,
      );
    }
  }

  void _paintEdge(Canvas canvas, MermaidEdgeShape shape) {
    if (shape.points.length < 2) {
      return;
    }
    final path = mermaidEdgePath(shape);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shape.strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = palette.resolve(shape.stroke, series: shape.series);

    switch (shape.style) {
      case MermaidLineStyle.dashed:
        canvas.drawPath(_dash(path, const [7, 5]), paint);
      case MermaidLineStyle.dotted:
        canvas.drawPath(_dash(path, const [2, 5]), paint);
      case MermaidLineStyle.solid:
      case MermaidLineStyle.thick:
        canvas.drawPath(path, paint);
    }

    final ink = palette.resolve(shape.stroke, series: shape.series);
    _paintHead(canvas, shape.head, shape.points.last, shape.headDirection, ink);
    _paintHead(
        canvas, shape.tail, shape.points.first, shape.tailDirection, ink);
  }

  void _paintHead(
    Canvas canvas,
    MermaidArrowHead head,
    Offset at,
    Offset direction,
    Color ink,
  ) {
    if (head == MermaidArrowHead.none) {
      return;
    }
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = ink;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    final surface = Paint()
      ..style = PaintingStyle.fill
      ..color = palette.canvas;

    final normal = Offset(-direction.dy, direction.dx);

    switch (head) {
      case MermaidArrowHead.none:
        return;
      case MermaidArrowHead.arrow:
        final path = Path()
          ..moveTo(at.dx, at.dy)
          ..lineTo(
            at.dx - direction.dx * 10 + normal.dx * 4.6,
            at.dy - direction.dy * 10 + normal.dy * 4.6,
          )
          ..lineTo(
            at.dx - direction.dx * 10 - normal.dx * 4.6,
            at.dy - direction.dy * 10 - normal.dy * 4.6,
          )
          ..close();
        canvas.drawPath(path, fill);
      case MermaidArrowHead.open:
        canvas.drawLine(
          at,
          at - direction * 10 + normal * 5,
          stroke,
        );
        canvas.drawLine(
          at,
          at - direction * 10 - normal * 5,
          stroke,
        );
      case MermaidArrowHead.cross:
        final back = at - direction * 4;
        canvas.drawLine(back + normal * 5, back - normal * 5, stroke);
        canvas.drawLine(
          back + direction * 5 + normal * 5,
          back - direction * 5 - normal * 5,
          stroke,
        );
        canvas.drawLine(
          back + direction * 5 - normal * 5,
          back - direction * 5 + normal * 5,
          stroke,
        );
      case MermaidArrowHead.circle:
        canvas.drawCircle(at - direction * 5, 5, surface);
        canvas.drawCircle(at - direction * 5, 5, stroke);
      case MermaidArrowHead.triangle:
        final path = Path()
          ..moveTo(at.dx, at.dy)
          ..lineTo(
            at.dx - direction.dx * 12 + normal.dx * 6,
            at.dy - direction.dy * 12 + normal.dy * 6,
          )
          ..lineTo(
            at.dx - direction.dx * 12 - normal.dx * 6,
            at.dy - direction.dy * 12 - normal.dy * 6,
          )
          ..close();
        canvas.drawPath(path, surface);
        canvas.drawPath(path, stroke);
      case MermaidArrowHead.filledDiamond:
      case MermaidArrowHead.hollowDiamond:
        final tip = at;
        final back = at - direction * 16;
        final path = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - direction.dx * 8 + normal.dx * 5,
            tip.dy - direction.dy * 8 + normal.dy * 5,
          )
          ..lineTo(back.dx, back.dy)
          ..lineTo(
            tip.dx - direction.dx * 8 - normal.dx * 5,
            tip.dy - direction.dy * 8 - normal.dy * 5,
          )
          ..close();
        canvas.drawPath(
          path,
          head == MermaidArrowHead.filledDiamond ? fill : surface,
        );
        canvas.drawPath(path, stroke);
      case MermaidArrowHead.one:
        final at1 = at - direction * 9;
        canvas.drawLine(at1 + normal * 6, at1 - normal * 6, stroke);
      case MermaidArrowHead.many:
        final base = at - direction * 12;
        canvas.drawLine(at, base + normal * 6, stroke);
        canvas.drawLine(at, base - normal * 6, stroke);
        canvas.drawLine(at, base, stroke);
      case MermaidArrowHead.zeroOrOne:
        final centre = at - direction * 16;
        canvas.drawCircle(centre, 4.5, surface);
        canvas.drawCircle(centre, 4.5, stroke);
        final bar = at - direction * 6;
        canvas.drawLine(bar + normal * 6, bar - normal * 6, stroke);
      case MermaidArrowHead.zeroOrMany:
        final centre = at - direction * 18;
        canvas.drawCircle(centre, 4.5, surface);
        canvas.drawCircle(centre, 4.5, stroke);
        final base = at - direction * 13;
        canvas.drawLine(at, base + normal * 6, stroke);
        canvas.drawLine(at, base - normal * 6, stroke);
    }
  }

  void _paintText(Canvas canvas, MermaidTextShape shape) {
    if (shape.text.isEmpty) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: shape.text,
        style: typography
            .styleFor(shape.role, bold: shape.bold, italic: shape.italic)
            .copyWith(
              color: palette.resolve(shape.ink, series: shape.series),
            ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: switch (shape.align) {
        MermaidTextAlign.left => TextAlign.left,
        MermaidTextAlign.center => TextAlign.center,
        MermaidTextAlign.right => TextAlign.right,
      },
      textScaler: TextScaler.linear(textScale),
      maxLines: 6,
      ellipsis: '…',
    )..layout(maxWidth: shape.maxWidth ?? double.infinity);

    final dx = switch (shape.align) {
      MermaidTextAlign.left => shape.anchor.dx,
      MermaidTextAlign.center => shape.anchor.dx - painter.width / 2,
      MermaidTextAlign.right => shape.anchor.dx - painter.width,
    };
    painter.paint(canvas, Offset(dx, shape.anchor.dy));
    painter.dispose();
  }

  void _paintArc(Canvas canvas, MermaidArcShape shape) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = palette.seriesAt(shape.series);
    canvas.drawArc(shape.rect, shape.startAngle, shape.sweepAngle, true, paint);
    if (shape.strokeWidth > 0) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.strokeWidth
        ..color = palette.resolve(shape.stroke);
      canvas.drawArc(
        shape.rect,
        shape.startAngle,
        shape.sweepAngle,
        true,
        stroke,
      );
    }
  }

  void _paintActor(Canvas canvas, MermaidActorGlyph shape) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = palette.resolve(shape.stroke);
    final rect = shape.rect;
    final headRadius = rect.width * 0.3;
    final headCentre = Offset(rect.center.dx, rect.top + headRadius + 1);
    canvas.drawCircle(headCentre, headRadius, paint);
    final shoulders = headCentre.dy + headRadius + 3;
    canvas.drawLine(
      Offset(rect.center.dx, shoulders),
      Offset(rect.center.dx, rect.bottom - 8),
      paint,
    );
    canvas.drawLine(
      Offset(rect.left, shoulders + 4),
      Offset(rect.right, shoulders + 4),
      paint,
    );
    canvas.drawLine(
      Offset(rect.center.dx, rect.bottom - 8),
      Offset(rect.left + 2, rect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(rect.center.dx, rect.bottom - 8),
      Offset(rect.right - 2, rect.bottom),
      paint,
    );
  }

  static Path _dash(Path source, List<double> pattern) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var index = 0;
      while (distance < metric.length) {
        final step = pattern[index % pattern.length];
        if (index.isEven) {
          result.addPath(
            metric.extractPath(
                distance, math.min(distance + step, metric.length)),
            Offset.zero,
          );
        }
        distance += step;
        index += 1;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant MermaidPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.palette != palette ||
      oldDelegate.textScale != textScale;
}

/// The outline of a node, shared by the painter and the SVG writer.
Path mermaidShapePath(Rect rect, MermaidNodeShape shape, double radius) {
  switch (shape) {
    case MermaidNodeShape.circle:
    case MermaidNodeShape.doubleCircle:
      return Path()..addOval(rect);
    case MermaidNodeShape.stadium:
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
        );
    case MermaidNodeShape.rectangle:
      return Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)));
    case MermaidNodeShape.point:
      return Path()..addOval(rect);
    case MermaidNodeShape.cylinder:
      final capRadius = Radius.elliptical(rect.width / 2, 7);
      return Path()
        ..addRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: capRadius,
            topRight: capRadius,
            bottomLeft: capRadius,
            bottomRight: capRadius,
          ),
        );
    default:
      final polygon = mermaidPolygonFor(rect, shape);
      if (polygon != null) {
        final path = Path()..moveTo(polygon.first.dx, polygon.first.dy);
        for (final point in polygon.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        return path..close();
      }
      return Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }
}

/// The corner points of the shapes drawn as straight-sided polygons.
List<Offset>? mermaidPolygonFor(Rect rect, MermaidNodeShape shape) {
  final slant = math.min(20.0, rect.width * 0.18);
  switch (shape) {
    case MermaidNodeShape.diamond:
      return [
        rect.topCenter,
        rect.centerRight,
        rect.bottomCenter,
        rect.centerLeft,
      ];
    case MermaidNodeShape.hexagon:
      return [
        Offset(rect.left + slant, rect.top),
        Offset(rect.right - slant, rect.top),
        rect.centerRight,
        Offset(rect.right - slant, rect.bottom),
        Offset(rect.left + slant, rect.bottom),
        rect.centerLeft,
      ];
    case MermaidNodeShape.parallelogram:
      return [
        Offset(rect.left + slant, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right - slant, rect.bottom),
        Offset(rect.left, rect.bottom),
      ];
    case MermaidNodeShape.parallelogramAlt:
      return [
        Offset(rect.left, rect.top),
        Offset(rect.right - slant, rect.top),
        Offset(rect.right, rect.bottom),
        Offset(rect.left + slant, rect.bottom),
      ];
    case MermaidNodeShape.trapezoid:
      return [
        Offset(rect.left + slant, rect.top),
        Offset(rect.right - slant, rect.top),
        Offset(rect.right, rect.bottom),
        Offset(rect.left, rect.bottom),
      ];
    case MermaidNodeShape.trapezoidAlt:
      return [
        Offset(rect.left, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right - slant, rect.bottom),
        Offset(rect.left + slant, rect.bottom),
      ];
    case MermaidNodeShape.asymmetric:
      return [
        Offset(rect.left, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right, rect.bottom),
        Offset(rect.left, rect.bottom),
        Offset(rect.left + slant, rect.center.dy),
      ];
    default:
      return null;
  }
}

/// The line of a connector, shared by the painter and the SVG writer.
Path mermaidEdgePath(MermaidEdgeShape shape) {
  final path = Path()..moveTo(shape.points.first.dx, shape.points.first.dy);
  if (shape.cubic && shape.points.length == 4) {
    path.cubicTo(
      shape.points[1].dx,
      shape.points[1].dy,
      shape.points[2].dx,
      shape.points[2].dy,
      shape.points[3].dx,
      shape.points[3].dy,
    );
    return path;
  }
  for (final point in shape.points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  return path;
}
