import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/canvas/presentation/canvas_painters.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/workspace/application/canvas/canvas_geometry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/material.dart';

/// Taking a picture of a canvas.
///
/// Everything is drawn from the same painters the screen uses, so an exported
/// canvas is the canvas — not a second renderer that will drift.
///
/// Cards are drawn as their shape, their colour and their words. A page card's
/// live preview and a database card's real table are deliberately NOT
/// rasterised: they are other people's widgets, they load asynchronously, and
/// half of them would be blank in the picture.

/// What part of a canvas to export.
enum CanvasExportScope {
  everything,
  viewport,
  selection;
}

/// The box the export covers, or null when there is nothing to draw.
Rect? canvasExportBounds(
  CanvasDocument document, {
  CanvasExportScope scope = CanvasExportScope.everything,
  Rect? viewport,
  Iterable<String> selection = const <String>[],
}) {
  final box = switch (scope) {
    CanvasExportScope.everything => document.bounds,
    CanvasExportScope.viewport => viewport ?? document.bounds,
    CanvasExportScope.selection => document.boundsOf(selection),
  };
  if (box.isEmpty || box.width < 1 || box.height < 1) {
    return null;
  }
  return box.inflate(scope == CanvasExportScope.viewport ? 0 : 40);
}

/// Draw a canvas onto a [Canvas] positioned so [bounds] fills [size].
///
/// Shared by the PNG writer and by anything else that wants a still of a
/// canvas — a nested canvas card, for instance.
void paintCanvasStill(
  Canvas canvas,
  CanvasDocument document,
  CanvasPalette palette,
  Rect bounds,
  Size size, {
  bool transparentBackground = false,
  TextStyle? baseStyle,
}) {
  final scale =
      math.min(size.width / bounds.width, size.height / bounds.height);
  final camera = CanvasCamera(
    offset: Offset(
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    ),
    zoom: scale,
  );

  if (!transparentBackground) {
    CanvasBackgroundPainter(
      camera: camera,
      palette: palette,
      background: document.settings.background,
      spacing: document.settings.gridSize,
    ).paint(canvas, size);
  }

  final collapsed = <String>{
    for (final frame in document.frames)
      if (frame.collapsed) ...[
        frame.id,
        ...document.descendantFrames(frame.id),
      ],
  };

  // Frames first: they are the ground the cards stand on.
  canvas.save();
  canvas.translate(camera.offset.dx, camera.offset.dy);
  canvas.scale(camera.zoom);
  for (final frame in document.frames) {
    final accent = palette.accentAt(frame.color);
    final rect = RRect.fromRectAndRadius(
      frame.rect,
      const Radius.circular(CanvasMetrics.frameRadius),
    );
    canvas
      ..drawRRect(
        rect,
        Paint()
          ..color = frame.color == null
              ? palette.sunken
              : accent.withValues(alpha: palette.isDark ? 0.09 : 0.055),
      )
      ..drawRRect(
        rect,
        Paint()
          ..color = accent.withValues(alpha: palette.isDark ? 0.4 : 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 / camera.zoom,
      );
    if (frame.title.trim().isNotEmpty) {
      _paintText(
        canvas,
        frame.title.trim(),
        Rect.fromLTWH(
          frame.rect.left + 12,
          frame.rect.top - 26,
          frame.rect.width,
          22,
        ),
        (baseStyle ?? const TextStyle()).copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: frame.color == null ? palette.textSecondary : accent,
        ),
        maxLines: 1,
      );
    }
  }
  canvas.restore();

  // Connections, then cards on top of them.
  CanvasEdgePainter(
    camera: camera,
    palette: palette,
    labelStyle: baseStyle,
    edges: [
      for (final edge in document.edges)
        if (document.nodeById(edge.from) != null &&
            document.nodeById(edge.to) != null &&
            !collapsed.contains(document.nodeById(edge.from)!.frameId) &&
            !collapsed.contains(document.nodeById(edge.to)!.frameId))
          CanvasEdgeDrawing(
            edge: edge,
            geometry: canvasEdgeGeometry(
              from: document.nodeById(edge.from)!.rect,
              to: document.nodeById(edge.to)!.rect,
              fromSide: edge.fromSide,
              toSide: edge.toSide,
            ),
            colour: edge.color == null
                ? palette.textMuted
                    .withValues(alpha: palette.isDark ? 0.75 : 0.62)
                : palette.accentAt(edge.color),
          ),
    ],
  ).paint(canvas, size);

  canvas.save();
  canvas.translate(camera.offset.dx, camera.offset.dy);
  canvas.scale(camera.zoom);
  for (final node in document.nodes) {
    if (collapsed.contains(node.frameId)) {
      continue;
    }
    final rect = RRect.fromRectAndRadius(
      node.rect,
      const Radius.circular(CanvasMetrics.cardRadius),
    );
    canvas
      ..drawRRect(rect, Paint()..color = palette.surfaceFor(node.color))
      ..drawRRect(
        rect,
        Paint()
          ..color = palette.borderFor(node.color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / camera.zoom,
      );
    final words = node.title.trim().isNotEmpty
        ? node.title.trim()
        : node.text.trim().isNotEmpty
            ? node.text.trim()
            : node.url.trim();
    if (words.isNotEmpty) {
      _paintText(
        canvas,
        words,
        node.rect.deflate(CanvasMetrics.space3),
        (baseStyle ?? const TextStyle()).copyWith(
          fontSize: 14,
          height: 1.4,
          color: palette.textPrimary,
        ),
      );
    }
  }
  canvas.restore();

  CanvasStrokePainter(
    camera: camera,
    palette: palette,
    strokes: document.strokes,
  ).paint(canvas, size);
}

void _paintText(
  Canvas canvas,
  String text,
  Rect box,
  TextStyle style, {
  int maxLines = 8,
}) {
  if (box.width < 4 || box.height < 4) {
    return;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: box.width);
  painter.paint(canvas, box.topLeft);
}

/// A PNG of the canvas.
Future<Uint8List?> canvasToPng(
  CanvasDocument document,
  CanvasPalette palette, {
  required Rect bounds,
  double pixelRatio = 2,
  bool transparentBackground = false,
  double maximumEdge = 6000,
  TextStyle? baseStyle,
}) async {
  if (bounds.width < 1 || bounds.height < 1) {
    return null;
  }
  // A canvas can be enormous. Cap the picture rather than asking the GPU for
  // a texture it cannot make.
  final ratio = math.min(
    pixelRatio,
    maximumEdge / math.max(bounds.width, bounds.height),
  );
  final width = (bounds.width * ratio).round();
  final height = (bounds.height * ratio).round();
  if (width < 1 || height < 1) {
    return null;
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);
  paintCanvasStill(
    canvas,
    document,
    palette,
    bounds,
    bounds.size,
    transparentBackground: transparentBackground,
    baseStyle: baseStyle,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data?.buffer.asUint8List();
}

/// An SVG of the canvas.
///
/// Written by hand from the same model, so it carries real shapes and real
/// text rather than an embedded bitmap.
String canvasToSvg(
  CanvasDocument document,
  CanvasPalette palette, {
  required Rect bounds,
  bool transparentBackground = false,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'width="${bounds.width.round()}" height="${bounds.height.round()}" '
      'viewBox="${bounds.left.toStringAsFixed(2)} '
      '${bounds.top.toStringAsFixed(2)} '
      '${bounds.width.toStringAsFixed(2)} '
      '${bounds.height.toStringAsFixed(2)}">',
    );

  if (!transparentBackground) {
    buffer.writeln(
      '<rect x="${bounds.left}" y="${bounds.top}" '
      'width="${bounds.width}" height="${bounds.height}" '
      'fill="${_svgColour(palette.canvas)}"/>',
    );
  }

  final collapsed = <String>{
    for (final frame in document.frames)
      if (frame.collapsed) ...[
        frame.id,
        ...document.descendantFrames(frame.id),
      ],
  };

  for (final frame in document.frames) {
    final accent = palette.accentAt(frame.color);
    buffer.writeln(
      '<rect x="${frame.rect.left}" y="${frame.rect.top}" '
      'width="${frame.rect.width}" height="${frame.rect.height}" rx="16" '
      'fill="${_svgColour(frame.color == null ? palette.sunken : accent)}" '
      'fill-opacity="${frame.color == null ? 1 : 0.08}" '
      'stroke="${_svgColour(accent)}" stroke-opacity="0.35"/>',
    );
    if (frame.title.trim().isNotEmpty) {
      buffer.writeln(
        '<text x="${frame.rect.left + 12}" y="${frame.rect.top - 8}" '
        'font-family="sans-serif" font-size="13" font-weight="600" '
        'fill="${_svgColour(frame.color == null ? palette.textSecondary : accent)}">'
        '${_escape(frame.title.trim())}</text>',
      );
    }
  }

  for (final edge in document.edges) {
    final from = document.nodeById(edge.from);
    final to = document.nodeById(edge.to);
    if (from == null || to == null) {
      continue;
    }
    if (collapsed.contains(from.frameId) || collapsed.contains(to.frameId)) {
      continue;
    }
    final geometry = canvasEdgeGeometry(
      from: from.rect,
      to: to.rect,
      fromSide: edge.fromSide,
      toSide: edge.toSide,
    );
    final colour = _svgColour(
      edge.color == null ? palette.textMuted : palette.accentAt(edge.color),
    );
    final dash = switch (edge.style) {
      CanvasEdgeStyle.solid => '',
      CanvasEdgeStyle.dashed => ' stroke-dasharray="9 6"',
      CanvasEdgeStyle.dotted => ' stroke-dasharray="1.6 5"',
    };
    buffer.writeln(
      '<path d="M ${geometry.start.dx} ${geometry.start.dy} '
      'C ${geometry.controlStart.dx} ${geometry.controlStart.dy} '
      '${geometry.controlEnd.dx} ${geometry.controlEnd.dy} '
      '${geometry.end.dx} ${geometry.end.dy}" fill="none" '
      'stroke="$colour" stroke-width="1.9"$dash/>',
    );
    if (edge.endMarker == CanvasEdgeMarker.arrow) {
      final angle = geometry.endAngle;
      const length = 9.0;
      const spread = 0.42;
      final a = geometry.end -
          Offset(
            length * math.cos(angle - spread),
            length * math.sin(angle - spread),
          );
      final b = geometry.end -
          Offset(
            length * math.cos(angle + spread),
            length * math.sin(angle + spread),
          );
      buffer.writeln(
        '<polygon points="${geometry.end.dx},${geometry.end.dy} '
        '${a.dx},${a.dy} ${b.dx},${b.dy}" fill="$colour"/>',
      );
    }
    if (edge.label.trim().isNotEmpty) {
      final mid = geometry.midpoint;
      buffer.writeln(
        '<text x="${mid.dx}" y="${mid.dy}" text-anchor="middle" '
        'font-family="sans-serif" font-size="12" '
        'fill="${_svgColour(palette.textSecondary)}">'
        '${_escape(edge.label.trim())}</text>',
      );
    }
  }

  for (final node in document.nodes) {
    if (collapsed.contains(node.frameId)) {
      continue;
    }
    buffer.writeln(
      '<rect x="${node.rect.left}" y="${node.rect.top}" '
      'width="${node.rect.width}" height="${node.rect.height}" rx="14" '
      'fill="${_svgColour(palette.surfaceFor(node.color))}" '
      'stroke="${_svgColour(palette.borderFor(node.color))}"/>',
    );
    final words =
        node.title.trim().isNotEmpty ? node.title.trim() : node.text.trim();
    if (words.isEmpty) {
      continue;
    }
    // SVG has no text wrapping, so the lines are written out one at a time at
    // roughly the measure the card can hold.
    final perLine = math.max(6, (node.rect.width - 24) ~/ 7.6);
    final lines = <String>[];
    for (final paragraph in words.split('\n')) {
      var rest = paragraph;
      while (rest.length > perLine && lines.length < 8) {
        var cut = rest.lastIndexOf(' ', perLine);
        if (cut <= 0) {
          cut = perLine;
        }
        lines.add(rest.substring(0, cut));
        rest = rest.substring(cut).trimLeft();
      }
      if (lines.length < 8) {
        lines.add(rest);
      }
    }
    for (var index = 0; index < lines.length; index++) {
      buffer.writeln(
        '<text x="${node.rect.left + 12}" '
        'y="${node.rect.top + 26 + index * 19}" '
        'font-family="sans-serif" font-size="14" '
        'fill="${_svgColour(palette.textPrimary)}">'
        '${_escape(lines[index])}</text>',
      );
    }
  }

  for (final stroke in document.strokes) {
    if (stroke.points.length < 2) {
      continue;
    }
    final points =
        stroke.points.map((point) => '${point.dx},${point.dy}').join(' ');
    final colour = _svgColour(
      stroke.color == null
          ? palette.textPrimary
          : palette.accentAt(stroke.color),
    );
    final highlighter = stroke.tool == CanvasStrokeTool.highlighter;
    buffer.writeln(
      '<polyline points="$points" fill="none" stroke="$colour" '
      'stroke-width="${highlighter ? stroke.width * 4.5 : stroke.width}" '
      'stroke-opacity="${highlighter ? 0.28 : 1}" '
      'stroke-linecap="round" stroke-linejoin="round"/>',
    );
  }

  buffer.writeln('</svg>');
  return buffer.toString();
}

String _svgColour(Color colour) {
  final red = (colour.r * 255).round();
  final green = (colour.g * 255).round();
  final blue = (colour.b * 255).round();
  return '#${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
