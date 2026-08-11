import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'excalidraw_rough.dart';
import 'excalidraw_scene.dart';

/// Paints a drawing.
///
/// Shapes are cached as paths per element version, so panning, zooming and
/// selecting cost a repaint rather than a re-generation of every wobbly line.
class DrawScenePainter extends CustomPainter {
  DrawScenePainter({
    required this.scene,
    required this.brightness,
    this.selection = const <String>{},
    this.selectionColor,
    this.marquee,
    this.hoveredId,
    this.images = const <String, ui.Image>{},
    this.cache,
  });

  final DrawScene scene;
  final Brightness brightness;
  final Set<String> selection;
  final Color? selectionColor;
  final Rect? marquee;
  final String? hoveredId;
  final Map<String, ui.Image> images;
  final DrawPathCache? cache;

  @override
  void paint(Canvas canvas, Size size) {
    for (final element in scene.visible) {
      _paintElement(canvas, element);
    }

    final accent = selectionColor ?? const Color(0xFF6965DB);
    if (hoveredId != null && !selection.contains(hoveredId)) {
      final element = scene.find(hoveredId!);
      if (element != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            element.bounds.inflate(4),
            const Radius.circular(4),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = accent.withValues(alpha: 0.4),
        );
      }
    }

    if (selection.isNotEmpty) {
      Rect? combined;
      for (final id in selection) {
        final element = scene.find(id);
        if (element == null) {
          continue;
        }
        final rect = element.bounds.inflate(4);
        combined = combined == null ? rect : combined.expandToInclude(rect);
        if (selection.length > 1) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = accent.withValues(alpha: 0.45),
          );
        }
      }
      if (combined != null) {
        canvas.drawRect(
          combined,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = accent,
        );
        for (final handle in drawSelectionHandles(combined)) {
          canvas
            ..drawRRect(
              RRect.fromRectAndRadius(handle.rect, const Radius.circular(2.5)),
              Paint()..color = Colors.white,
            )
            ..drawRRect(
              RRect.fromRectAndRadius(handle.rect, const Radius.circular(2.5)),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2
                ..color = accent,
            );
        }
      }
    }

    if (marquee != null) {
      canvas
        ..drawRect(marquee!, Paint()..color = accent.withValues(alpha: 0.10))
        ..drawRect(
          marquee!,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = accent.withValues(alpha: 0.7),
        );
    }
  }

  void _paintElement(Canvas canvas, DrawElement element) {
    final opacity = (element.opacity / 100).clamp(0.0, 1.0);
    if (opacity <= 0) {
      return;
    }
    // Excalidraw stores geometry unrotated and turns it about its centre.
    final angle = element.angle;
    final rotated = angle.abs() > 0.0001;
    if (rotated) {
      final centre = element.bounds.center;
      canvas
        ..save()
        ..translate(centre.dx, centre.dy)
        ..rotate(angle)
        ..translate(-centre.dx, -centre.dy);
    }
    if (opacity < 1) {
      canvas.saveLayer(
        element.bounds.inflate(40),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }

    switch (element.type) {
      case DrawElementType.text:
        _paintText(canvas, element);
      case DrawElementType.image:
        _paintImage(canvas, element);
      default:
        _paintShape(canvas, element);
    }

    if (opacity < 1) {
      canvas.restore();
    }
    if (rotated) {
      canvas.restore();
    }
  }

  void _paintShape(Canvas canvas, DrawElement element) {
    final geometry = (cache ?? DrawPathCache.shared).geometryFor(element);
    final stroke = drawColour(element.strokeColor, brightness) ??
        (brightness == Brightness.dark
            ? const Color(0xFFE3E3E3)
            : const Color(0xFF1E1E1E));
    final background = drawColour(element.backgroundColor, brightness);

    if (background != null && geometry.fill != null) {
      if (element.fillStyle == 'solid') {
        canvas.drawPath(geometry.fill!, Paint()..color = background);
      } else {
        canvas.drawPath(
          geometry.hatch ?? geometry.fill!,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.8, element.strokeWidth * 0.6)
            ..strokeCap = StrokeCap.round
            ..color = background,
        );
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = element.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = stroke;

    final outline = switch (element.strokeStyle) {
      'dashed' => _dash(
          geometry.outline, [element.strokeWidth * 4, element.strokeWidth * 3]),
      'dotted' => _dash(geometry.outline, [0.5, element.strokeWidth * 3]),
      _ => geometry.outline,
    };
    canvas.drawPath(outline, paint);

    if (element.type == DrawElementType.freedraw) {
      // A pen stroke is filled, not outlined: that is what gives it a nib.
      canvas.drawPath(
        geometry.outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = element.strokeWidth * 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = stroke,
      );
    }

    if (element.type == DrawElementType.arrow) {
      _paintArrowHead(canvas, element, stroke);
    }
  }

  void _paintArrowHead(Canvas canvas, DrawElement element, Color stroke) {
    final points = element.points;
    if (points.length < 2) {
      return;
    }
    final origin = Offset(element.x, element.y);
    final tip = origin + points.last;
    final before = origin + points[points.length - 2];
    final direction = tip - before;
    if (direction.distance < 0.01) {
      return;
    }
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final length = math.max(12.0, element.strokeWidth * 6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = element.strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = stroke;
    canvas
      ..drawLine(tip, tip - unit * length + normal * length * 0.42, paint)
      ..drawLine(tip, tip - unit * length - normal * length * 0.42, paint);
  }

  void _paintText(Canvas canvas, DrawElement element) {
    final colour = drawColour(element.strokeColor, brightness) ??
        (brightness == Brightness.dark
            ? const Color(0xFFE3E3E3)
            : const Color(0xFF1E1E1E));
    final painter = drawTextPainter(element, colour);
    // The stored text is already wrapped, so laying it out unbounded and
    // placing it by hand keeps the lines the editor decided on.
    final box = element.bounds;
    final dy = switch (element.verticalAlign) {
      'middle' => box.top + (box.height - painter.height) / 2,
      'bottom' => box.bottom - painter.height,
      _ => box.top,
    };
    final dx = switch (element.textAlign) {
      'center' => box.left + (box.width - painter.width) / 2,
      'right' => box.right - painter.width,
      _ => box.left,
    };
    painter.paint(canvas, Offset(dx, dy));
    painter.dispose();
  }

  void _paintImage(Canvas canvas, DrawElement element) {
    final image = images[element.fileId];
    final rect = element.bounds;
    if (image == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x55888888),
      );
      return;
    }
    paintImage(
      canvas: canvas,
      rect: rect,
      image: image,
      fit: BoxFit.fill,
    );
  }

  static Path _dash(Path source, List<double> pattern) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var index = 0;
      while (distance < metric.length) {
        final step = math.max(0.5, pattern[index % pattern.length]);
        if (index.isEven) {
          result.addPath(
            metric.extractPath(
              distance,
              math.min(distance + step, metric.length),
            ),
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
  bool shouldRepaint(covariant DrawScenePainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.selection != selection ||
      oldDelegate.marquee != marquee ||
      oldDelegate.hoveredId != hoveredId ||
      oldDelegate.brightness != brightness ||
      oldDelegate.images.length != images.length;
}

/// The outline, fill and hatching of one element.
@immutable
class DrawGeometry {
  const DrawGeometry({required this.outline, this.fill, this.hatch});

  final Path outline;
  final Path? fill;
  final Path? hatch;
}

/// Remembers the generated geometry of each element.
///
/// Keyed on the element's own version counter, which Excalidraw already
/// increments on every change — so a cache entry can never go stale.
class DrawPathCache {
  static final DrawPathCache shared = DrawPathCache();

  final Map<String, ({int version, DrawGeometry geometry})> _entries = {};

  DrawGeometry geometryFor(DrawElement element) {
    final version = (element.data['version'] as num?)?.toInt() ?? 0;
    final hit = _entries[element.id];
    if (hit != null && hit.version == version) {
      return hit.geometry;
    }
    final geometry = _build(element);
    _entries[element.id] = (version: version, geometry: geometry);
    if (_entries.length > 600) {
      _entries.remove(_entries.keys.first);
    }
    return geometry;
  }

  void clear() => _entries.clear();

  /// Excalidraw's own corner rule: a proportional radius on small shapes and
  /// a fixed 32 once they are big enough for it to look right.
  static double _cornerRadius(DrawElement element, Rect rect) {
    final type = element.roundnessType;
    if (type == null) {
      return 0;
    }
    final shortest = math.min(rect.width, rect.height);
    if (type == 3) {
      const fixed = 32.0;
      const cutoff = fixed / 0.25;
      return shortest <= cutoff ? shortest * 0.25 : fixed;
    }
    return shortest * 0.25;
  }

  /// The same shape as [Rough.roundedPolygon], but closed and fillable.
  static Path _roundedPolygon(List<Offset> points, double radius) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final previous = points[(i - 1 + points.length) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final into = _towards(current, previous, radius);
      final outOf = _towards(current, next, radius);
      if (i == 0) {
        path.moveTo(into.dx, into.dy);
      } else {
        path.lineTo(into.dx, into.dy);
      }
      path.quadraticBezierTo(current.dx, current.dy, outOf.dx, outOf.dy);
    }
    return path..close();
  }

  static Offset _towards(Offset from, Offset to, double distance) {
    final delta = to - from;
    final length = delta.distance;
    if (length < 0.001) {
      return from;
    }
    return from + delta * (math.min(distance, length / 2) / length);
  }

  DrawGeometry _build(DrawElement element) {
    final random = RoughRandom(element.seed);
    final roughness = element.roughness;
    final rect = element.bounds;

    switch (element.type) {
      case DrawElementType.rectangle:
        final radius = _cornerRadius(element, rect);
        final fill = Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
        return DrawGeometry(
          outline: Rough.rectangle(
            rect,
            random,
            roughness: roughness,
            radius: radius,
          ),
          fill: fill,
          hatch: _hatchFor(element, fill, rect, random),
        );
      case DrawElementType.diamond:
        final points = [
          rect.topCenter,
          rect.centerRight,
          rect.bottomCenter,
          rect.centerLeft,
        ];
        final radius = _cornerRadius(element, rect);
        final fill = radius > 0.5
            ? _roundedPolygon(points, radius)
            : (Path()..addPolygon(points, true));
        return DrawGeometry(
          outline: radius > 0.5
              ? Rough.roundedPolygon(
                  points,
                  radius,
                  random,
                  roughness: roughness,
                )
              : Rough.polygon(points, random, roughness: roughness),
          fill: fill,
          hatch: _hatchFor(element, fill, rect, random),
        );
      case DrawElementType.ellipse:
        final fill = Path()..addOval(rect);
        return DrawGeometry(
          outline: Rough.ellipse(rect, random, roughness: roughness),
          fill: fill,
          hatch: _hatchFor(element, fill, rect, random),
        );
      case DrawElementType.line:
      case DrawElementType.arrow:
        final origin = Offset(element.x, element.y);
        final points = [for (final point in element.points) origin + point];
        if (points.length < 2) {
          return DrawGeometry(outline: Path());
        }
        if (points.length == 2) {
          return DrawGeometry(
            outline: Rough.line(
              points.first,
              points.last,
              random,
              roughness: roughness,
            ),
          );
        }
        return DrawGeometry(outline: Rough.stroke(points));
      case DrawElementType.freedraw:
        final origin = Offset(element.x, element.y);
        return DrawGeometry(
          outline: Rough.stroke([
            for (final point in element.points) origin + point,
          ]),
        );
      default:
        return DrawGeometry(outline: Path());
    }
  }

  Path? _hatchFor(
    DrawElement element,
    Path fill,
    Rect rect,
    RoughRandom random,
  ) {
    if (element.fillStyle == 'solid' ||
        drawColour(element.backgroundColor, Brightness.light) == null) {
      return null;
    }
    final gap = switch (element.fillStyle) {
      'cross-hatch' => 9.0,
      'zigzag' => 6.0,
      _ => 8.0,
    };
    final hatch = Rough.hachure(
      fill,
      rect,
      random,
      gap: gap,
      roughness: element.roughness,
    );
    if (element.fillStyle == 'cross-hatch') {
      hatch.addPath(
        Rough.hachure(
          fill,
          rect,
          RoughRandom(element.seed + 7),
          gap: gap,
          angle: 41,
          roughness: element.roughness,
        ),
        Offset.zero,
      );
    }
    return hatch;
  }
}

/// One resize grip.
@immutable
class DrawHandle {
  const DrawHandle(this.corner, this.rect);

  final DrawCorner corner;
  final Rect rect;
}

enum DrawCorner { topLeft, topRight, bottomLeft, bottomRight }

/// The four corner grips of a selection box.
List<DrawHandle> drawSelectionHandles(Rect bounds) {
  const size = 8.0;
  Rect at(Offset centre) =>
      Rect.fromCenter(center: centre, width: size, height: size);
  return [
    DrawHandle(DrawCorner.topLeft, at(bounds.topLeft)),
    DrawHandle(DrawCorner.topRight, at(bounds.topRight)),
    DrawHandle(DrawCorner.bottomLeft, at(bounds.bottomLeft)),
    DrawHandle(DrawCorner.bottomRight, at(bounds.bottomRight)),
  ];
}

/// Reads an Excalidraw colour string.
///
/// `transparent` really means "no fill", which is why this answers null
/// rather than a clear colour: the difference decides whether a shape is
/// filled at all.
Color? drawColour(String value, Brightness brightness) {
  final text = value.trim().toLowerCase();
  if (text.isEmpty || text == 'transparent' || text == 'none') {
    return null;
  }
  if (text.startsWith('#')) {
    final hex = text.substring(1);
    final normalised = switch (hex.length) {
      3 => hex.split('').map((c) => '$c$c').join(),
      6 => hex,
      8 => hex.substring(6) + hex.substring(0, 6),
      _ => null,
    };
    if (normalised == null) {
      return null;
    }
    final parsed = int.tryParse(normalised, radix: 16);
    if (parsed == null) {
      return null;
    }
    return normalised.length == 8 ? Color(parsed) : Color(0xFF000000 | parsed);
  }
  return null;
}

/// Writes a colour back in the form Excalidraw stores.
String drawColourToHex(Color color) {
  final red = (color.r * 255).round();
  final green = (color.g * 255).round();
  final blue = (color.b * 255).round();
  return '#${((red << 16) | (green << 8) | blue).toRadixString(16).padLeft(6, '0')}';
}

/// Excalidraw's font families, mapped to the faces we ship.
///
/// The same typefaces the editor uses are bundled, so a drawing reads the
/// same on the page as it does under the cursor.
String? drawFontFamilyFor(DrawElement element) {
  final family = (element.data['fontFamily'] as num?)?.toInt() ?? 5;
  return switch (family) {
    // 1 Virgil (now drawn in Excalifont), 5 Excalifont.
    1 || 5 => 'Excalifont',
    3 => 'RobotoMono',
    6 => 'Nunito',
    8 => 'ComicShanns',
    _ => null,
  };
}

/// Lays out a text element exactly as Excalidraw stored it.
///
/// The text already carries the editor's line breaks, so it is never wrapped
/// again — re-wrapping against different font metrics is what splits a word
/// across two lines in the preview but not in the editor.
TextPainter drawTextPainter(DrawElement element, Color colour) {
  final size = element.fontSize;
  return TextPainter(
    text: TextSpan(
      text: element.text,
      style: TextStyle(
        fontSize: size,
        height: element.lineHeight,
        color: colour,
        fontFamily: drawFontFamilyFor(element),
        leadingDistribution: TextLeadingDistribution.even,
      ),
    ),
    textAlign: switch (element.textAlign) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    },
    textDirection: ui.TextDirection.ltr,
  )..layout();
}
