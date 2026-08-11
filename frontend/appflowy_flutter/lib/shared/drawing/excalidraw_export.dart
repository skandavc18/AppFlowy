import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'excalidraw_painter.dart';
import 'excalidraw_scene.dart';

/// Rasterises a whole drawing, trimmed to what is actually on it.
Future<Uint8List?> drawSceneToPng(
  DrawScene scene,
  Brightness brightness, {
  double pixelRatio = 2,
  double padding = 24,
  Color? background,
}) async {
  final bounds = scene.contentBounds;
  if (bounds == null || bounds.isEmpty) {
    return null;
  }
  final frame = bounds.inflate(padding);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  if (background != null) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, frame.width, frame.height),
      Paint()..color = background,
    );
  }
  canvas.translate(-frame.left, -frame.top);
  DrawScenePainter(scene: scene, brightness: brightness)
      .paint(canvas, frame.size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    math.max(1, (frame.width * pixelRatio).ceil()),
    math.max(1, (frame.height * pixelRatio).ceil()),
  );
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

/// Writes a drawing as SVG.
///
/// Strokes are the same generated geometry the screen paints, so an exported
/// picture is the drawing rather than a second interpretation of it.
String drawSceneToSvg(
  DrawScene scene,
  Brightness brightness, {
  double padding = 24,
  Color? background,
}) {
  final bounds = scene.contentBounds ?? const Rect.fromLTWH(0, 0, 100, 100);
  final frame = bounds.inflate(padding);
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${_n(frame.width)}" '
      'height="${_n(frame.height)}" '
      'viewBox="${_n(frame.left)} ${_n(frame.top)} ${_n(frame.width)} '
      '${_n(frame.height)}">',
    );
  if (background != null) {
    buffer.writeln(
      '<rect x="${_n(frame.left)}" y="${_n(frame.top)}" '
      'width="${_n(frame.width)}" height="${_n(frame.height)}" '
      'fill="${_hex(background)}"/>',
    );
  }

  final cache = DrawPathCache();
  for (final element in scene.visible) {
    final opacity = (element.opacity / 100).clamp(0.0, 1.0);
    final stroke = drawColour(element.strokeColor, brightness) ??
        (brightness == Brightness.dark
            ? const Color(0xFFE3E3E3)
            : const Color(0xFF1E1E1E));

    if (element.type == DrawElementType.text) {
      final box = element.bounds;
      final anchor = switch (element.textAlign) {
        'center' => ('middle', box.center.dx),
        'right' => ('end', box.right),
        _ => ('start', box.left),
      };
      final lines = element.text.split('\n');
      final step = element.fontSize * element.lineHeight;
      final block = step * lines.length;
      final top = switch (element.verticalAlign) {
        'middle' => box.top + (box.height - block) / 2,
        'bottom' => box.bottom - block,
        _ => box.top,
      };
      // Each stored line is written out as it is: the editor already decided
      // where the text breaks, and re-flowing it would move the words.
      for (var i = 0; i < lines.length; i++) {
        buffer.writeln(
          '<text x="${_n(anchor.$2)}" '
          'y="${_n(top + step * i + element.fontSize * 0.82)}" '
          'text-anchor="${anchor.$1}" '
          'font-size="${_n(element.fontSize)}" fill="${_hex(stroke)}" '
          'fill-opacity="${_n(opacity)}" '
          'font-family="${_fontStack(element)}">'
          '${_escape(lines[i])}</text>',
        );
      }
      continue;
    }

    final geometry = cache.geometryFor(element);
    final background = drawColour(element.backgroundColor, brightness);
    if (background != null && geometry.fill != null) {
      if (element.fillStyle == 'solid') {
        buffer.writeln(
          '<path d="${_pathData(geometry.fill!)}" fill="${_hex(background)}" '
          'fill-opacity="${_n(opacity)}" stroke="none"/>',
        );
      } else if (geometry.hatch != null) {
        buffer.writeln(
          '<path d="${_pathData(geometry.hatch!)}" fill="none" '
          'stroke="${_hex(background)}" stroke-opacity="${_n(opacity)}" '
          'stroke-width="${_n(math.max(0.8, element.strokeWidth * 0.6))}" '
          'stroke-linecap="round"/>',
        );
      }
    }

    final dash = switch (element.strokeStyle) {
      'dashed' => ' stroke-dasharray="${_n(element.strokeWidth * 4)} '
          '${_n(element.strokeWidth * 3)}"',
      'dotted' => ' stroke-dasharray="0.5 ${_n(element.strokeWidth * 3)}"',
      _ => '',
    };
    buffer.writeln(
      '<path d="${_pathData(geometry.outline)}" fill="none" '
      'stroke="${_hex(stroke)}" stroke-opacity="${_n(opacity)}" '
      'stroke-width="${_n(element.strokeWidth)}" stroke-linecap="round" '
      'stroke-linejoin="round"$dash/>',
    );

    if (element.type == DrawElementType.arrow) {
      final points = element.points;
      if (points.length >= 2) {
        final origin = Offset(element.x, element.y);
        final tip = origin + points.last;
        final before = origin + points[points.length - 2];
        final direction = tip - before;
        if (direction.distance > 0.01) {
          final unit = direction / direction.distance;
          final normal = Offset(-unit.dy, unit.dx);
          final length = math.max(12.0, element.strokeWidth * 6);
          final a = tip - unit * length + normal * length * 0.42;
          final b = tip - unit * length - normal * length * 0.42;
          buffer.writeln(
            '<path d="M ${_n(a.dx)} ${_n(a.dy)} L ${_n(tip.dx)} ${_n(tip.dy)} '
            'L ${_n(b.dx)} ${_n(b.dy)}" fill="none" stroke="${_hex(stroke)}" '
            'stroke-width="${_n(element.strokeWidth)}" '
            'stroke-linecap="round" stroke-linejoin="round"/>',
          );
        }
      }
    }
  }

  buffer.writeln('</svg>');
  return buffer.toString();
}

/// Flattens a [Path] into an SVG `d` attribute by walking its metrics.
///
/// The generated strokes are already curves, so sampling at a fine step keeps
/// the wobble without needing the original segment list.
String _pathData(Path path) {
  final buffer = StringBuffer();
  for (final metric in path.computeMetrics()) {
    if (metric.length <= 0) {
      continue;
    }
    final steps = math.max(2, (metric.length / 3).ceil());
    for (var i = 0; i <= steps; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / steps);
      if (tangent == null) {
        continue;
      }
      final point = tangent.position;
      buffer.write(
        i == 0
            ? 'M ${_n(point.dx)} ${_n(point.dy)}'
            : ' L ${_n(point.dx)} ${_n(point.dy)}',
      );
    }
    buffer.write(' ');
  }
  return buffer.toString().trim();
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Names the drawing's typeface first, then something to fall back on.
String _fontStack(DrawElement element) {
  final family = drawFontFamilyFor(element);
  return switch (family) {
    'RobotoMono' => 'Cascadia, ui-monospace, monospace',
    null => 'Helvetica, system-ui, sans-serif',
    _ => '$family, Virgil, system-ui, sans-serif',
  };
}

String _hex(Color color) {
  final red = (color.r * 255).round();
  final green = (color.g * 255).round();
  final blue = (color.b * 255).round();
  return '#${((red << 16) | (green << 8) | blue).toRadixString(16).padLeft(6, '0')}';
}

String _n(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);
