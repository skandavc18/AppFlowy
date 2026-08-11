import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'mind_map_layout.dart';
import 'mind_map_theme.dart';

/// Draws a whole laid-out map onto a canvas.
///
/// The canvas builds its nodes as widgets so they can be typed into; export
/// needs the same picture without a widget tree, so the drawing is written
/// once here and shared by the PNG and SVG writers.
class MindMapPainter extends CustomPainter {
  const MindMapPainter({
    required this.layout,
    required this.palette,
    required this.baseStyle,
  });

  final MindMapLayout layout;
  final MindMapPalette palette;
  final TextStyle baseStyle;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in layout.links) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = link.depth <= 1 ? 2.6 : (link.depth == 2 ? 1.9 : 1.5)
        ..color = palette
            .branchAt(link.colorIndex)
            .withValues(alpha: link.depth <= 1 ? 0.85 : 0.62);
      canvas.drawPath(
        Path()
          ..moveTo(link.start.dx, link.start.dy)
          ..cubicTo(
            link.control1.dx,
            link.control1.dy,
            link.control2.dx,
            link.control2.dy,
            link.end.dx,
            link.end.dy,
          ),
        paint,
      );
    }

    for (final placement in layout.placements) {
      final isRoot = placement.depth == 0;
      final accent = palette.branchAt(
        MindMapMetrics.accentFor(placement.node, placement.depth),
      );
      final chosen = placement.node.colorIndex != null;
      final fill = isRoot
          ? (chosen ? accent : palette.rootFill)
          : chosen
              ? palette.fillFor(accent)
              : palette.node;
      final ink = isRoot && !chosen ? palette.onRoot : palette.inkOn(fill);
      final rrect = RRect.fromRectAndRadius(
        placement.rect,
        Radius.circular(
          isRoot
              ? MindMapCanvasMetrics.rootRadius
              : MindMapCanvasMetrics.nodeRadius,
        ),
      );
      canvas
        ..drawRRect(rrect, Paint()..color = fill)
        ..drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = chosen
                ? accent.withValues(alpha: 0.8)
                : isRoot
                    ? Colors.transparent
                    : accent.withValues(alpha: 0.35),
        );

      final painter = TextPainter(
        text: TextSpan(
          text: placement.node.text,
          style: baseStyle.copyWith(
            fontSize: MindMapCanvasMetrics.fontSizeFor(placement.depth),
            fontWeight: MindMapCanvasMetrics.weightFor(placement.depth),
            height: 1.3,
            color: ink,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
        maxLines: MindMapCanvasMetrics.maximumNodeLines,
      )..layout(
          maxWidth:
              placement.rect.width - MindMapCanvasMetrics.nodePaddingX * 2,
        );
      painter.paint(
        canvas,
        Offset(
          placement.rect.center.dx - painter.width / 2,
          placement.rect.center.dy - painter.height / 2,
        ),
      );
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant MindMapPainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.palette != palette;
}

/// Rasterises the whole map, not just what happens to be on screen.
Future<Uint8List?> mindMapToPng(
  MindMapLayout layout,
  MindMapPalette palette,
  TextStyle baseStyle, {
  double pixelRatio = 2,
  bool transparentBackground = false,
}) async {
  final width = math.max(1.0, layout.size.width);
  final height = math.max(1.0, layout.size.height);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width * pixelRatio, height * pixelRatio),
  );
  canvas.scale(pixelRatio);
  if (!transparentBackground) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = palette.canvas,
    );
  }
  MindMapPainter(layout: layout, palette: palette, baseStyle: baseStyle)
      .paint(canvas, Size(width, height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * pixelRatio).ceil(),
    (height * pixelRatio).ceil(),
  );
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

/// Writes the map as SVG — resolution independent, and the text stays text.
String mindMapToSvg(
  MindMapLayout layout,
  MindMapPalette palette,
  TextStyle baseStyle, {
  bool transparentBackground = false,
}) {
  final width = math.max(1.0, layout.size.width);
  final height = math.max(1.0, layout.size.height);
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${_n(width)}" '
      'height="${_n(height)}" viewBox="0 0 ${_n(width)} ${_n(height)}">',
    );
  if (!transparentBackground) {
    buffer.writeln(
      '<rect width="${_n(width)}" height="${_n(height)}" '
      'fill="${_hex(palette.canvas)}"/>',
    );
  }

  for (final link in layout.links) {
    final colour = palette
        .branchAt(link.colorIndex)
        .withValues(alpha: link.depth <= 1 ? 0.85 : 0.62);
    buffer.writeln(
      '<path d="M ${_n(link.start.dx)} ${_n(link.start.dy)} '
      'C ${_n(link.control1.dx)} ${_n(link.control1.dy)} '
      '${_n(link.control2.dx)} ${_n(link.control2.dy)} '
      '${_n(link.end.dx)} ${_n(link.end.dy)}" fill="none" '
      'stroke="${_hex(colour)}" stroke-linecap="round" '
      'stroke-width="${link.depth <= 1 ? 2.6 : (link.depth == 2 ? 1.9 : 1.5)}"/>',
    );
  }

  final family = baseStyle.fontFamily ?? 'system-ui';
  for (final placement in layout.placements) {
    final isRoot = placement.depth == 0;
    final accent = palette.branchAt(
      MindMapMetrics.accentFor(placement.node, placement.depth),
    );
    final chosen = placement.node.colorIndex != null;
    final fill = isRoot
        ? (chosen ? accent : palette.rootFill)
        : chosen
            ? palette.fillFor(accent)
            : palette.node;
    final ink = isRoot && !chosen ? palette.onRoot : palette.inkOn(fill);
    final radius = isRoot
        ? MindMapCanvasMetrics.rootRadius
        : MindMapCanvasMetrics.nodeRadius;
    final stroke = chosen
        ? _hex(accent.withValues(alpha: 0.8))
        : isRoot
            ? 'none'
            : _hex(accent.withValues(alpha: 0.35));
    buffer.writeln(
      '<rect x="${_n(placement.rect.left)}" y="${_n(placement.rect.top)}" '
      'width="${_n(placement.rect.width)}" '
      'height="${_n(placement.rect.height)}" rx="${_n(radius)}" '
      'fill="${_hex(fill)}" '
      'stroke="$stroke" '
      'stroke-width="1.2"/>',
    );
    final fontSize = MindMapCanvasMetrics.fontSizeFor(placement.depth);
    buffer.writeln(
      '<text x="${_n(placement.rect.center.dx)}" '
      'y="${_n(placement.rect.center.dy + fontSize * 0.36)}" '
      'text-anchor="middle" font-size="${_n(fontSize)}" '
      'font-family="$family, system-ui, sans-serif" '
      'font-weight="${MindMapCanvasMetrics.weightFor(placement.depth) == FontWeight.w600 ? 600 : 500}" '
      'fill="${_hex(ink)}">'
      '${const HtmlEscape().convert(placement.node.text)}</text>',
    );
  }

  buffer.writeln('</svg>');
  return buffer.toString();
}

String _hex(Color color) {
  final red = (color.r * 255).round();
  final green = (color.g * 255).round();
  final blue = (color.b * 255).round();
  final alpha = (color.a * 255).round();
  final rgb =
      ((red << 16) | (green << 8) | blue).toRadixString(16).padLeft(6, '0');
  return alpha == 0xFF
      ? '#$rgb'
      : '#$rgb${alpha.toRadixString(16).padLeft(2, '0')}';
}

String _n(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);
