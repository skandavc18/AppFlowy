import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'mermaid_model.dart';
import 'mermaid_painter.dart';
import 'mermaid_scene.dart';

/// Writes a laid-out diagram as SVG.
///
/// The same scene, the same palette and the same faces the screen uses, so an
/// exported picture is what was on the page rather than a second renderer's
/// idea of it.
String mermaidSceneToSvg(
  MermaidScene scene,
  MermaidPalette palette,
  MermaidTypography typography, {
  bool transparentBackground = false,
}) {
  final width = math.max(1.0, scene.size.width);
  final height = math.max(1.0, scene.size.height);
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

  for (final shape in scene.shapes) {
    switch (shape) {
      case MermaidBoxShape():
        buffer.writeln(_boxToSvg(shape, palette));
      case MermaidEdgeShape():
        buffer.writeln(_edgeToSvg(shape, palette));
      case MermaidTextShape():
        buffer.writeln(_textToSvg(shape, palette, typography));
      case MermaidArcShape():
        buffer.writeln(_arcToSvg(shape, palette));
      case MermaidActorGlyph():
        buffer.writeln(_actorToSvg(shape, palette));
    }
  }

  buffer.writeln('</svg>');
  return buffer.toString();
}

/// Rasterises a laid-out diagram to PNG bytes at [pixelRatio].
Future<Uint8List?> mermaidSceneToPng(
  MermaidScene scene,
  MermaidPalette palette,
  MermaidTypography typography, {
  double pixelRatio = 2,
  bool transparentBackground = false,
}) async {
  final width = math.max(1.0, scene.size.width);
  final height = math.max(1.0, scene.size.height);
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
  MermaidPainter(scene: scene, palette: palette, typography: typography)
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

// ---------------------------------------------------------------------------

String _boxToSvg(MermaidBoxShape shape, MermaidPalette palette) {
  final fill = _hex(palette.resolve(shape.fill, series: shape.series));
  final stroke = _hex(palette.resolve(shape.stroke, series: shape.series));
  final strokeAttrs = shape.strokeWidth <= 0
      ? 'stroke="none"'
      : 'stroke="$stroke" stroke-width="${_n(shape.strokeWidth)}"'
          '${shape.dashed ? ' stroke-dasharray="5 4"' : ''}';
  final rect = shape.rect;

  switch (shape.shape) {
    case MermaidNodeShape.circle:
    case MermaidNodeShape.point:
      return '<ellipse cx="${_n(rect.center.dx)}" cy="${_n(rect.center.dy)}" '
          'rx="${_n(rect.width / 2)}" ry="${_n(rect.height / 2)}" '
          'fill="$fill" $strokeAttrs/>';
    case MermaidNodeShape.doubleCircle:
      return '<g><ellipse cx="${_n(rect.center.dx)}" cy="${_n(rect.center.dy)}" '
          'rx="${_n(rect.width / 2)}" ry="${_n(rect.height / 2)}" '
          'fill="$fill" $strokeAttrs/>'
          '<ellipse cx="${_n(rect.center.dx)}" cy="${_n(rect.center.dy)}" '
          'rx="${_n(rect.width / 2 - 5)}" ry="${_n(rect.height / 2 - 5)}" '
          'fill="none" $strokeAttrs/></g>';
    case MermaidNodeShape.stadium:
      return _rectSvg(rect, rect.height / 2, fill, strokeAttrs);
    case MermaidNodeShape.rectangle:
      return _rectSvg(rect, 3, fill, strokeAttrs);
    case MermaidNodeShape.cylinder:
      return '<g>${_rectSvg(rect, 8, fill, strokeAttrs)}'
          '<path d="M ${_n(rect.left)} ${_n(rect.top + 7)} '
          'A ${_n(rect.width / 2)} 7 0 0 0 ${_n(rect.right)} ${_n(rect.top + 7)}" '
          'fill="none" $strokeAttrs/></g>';
    case MermaidNodeShape.subroutine:
      return '<g>${_rectSvg(rect, shape.radius, fill, strokeAttrs)}'
          '<line x1="${_n(rect.left + 8)}" y1="${_n(rect.top)}" '
          'x2="${_n(rect.left + 8)}" y2="${_n(rect.bottom)}" $strokeAttrs/>'
          '<line x1="${_n(rect.right - 8)}" y1="${_n(rect.top)}" '
          'x2="${_n(rect.right - 8)}" y2="${_n(rect.bottom)}" $strokeAttrs/></g>';
    default:
      final polygon = mermaidPolygonFor(rect, shape.shape);
      if (polygon != null) {
        final points =
            polygon.map((point) => '${_n(point.dx)},${_n(point.dy)}').join(' ');
        return '<polygon points="$points" fill="$fill" $strokeAttrs/>';
      }
      return _rectSvg(rect, shape.radius, fill, strokeAttrs);
  }
}

String _rectSvg(Rect rect, double radius, String fill, String strokeAttrs) =>
    '<rect x="${_n(rect.left)}" y="${_n(rect.top)}" width="${_n(rect.width)}" '
    'height="${_n(rect.height)}" rx="${_n(radius)}" ry="${_n(radius)}" '
    'fill="$fill" $strokeAttrs/>';

String _edgeToSvg(MermaidEdgeShape shape, MermaidPalette palette) {
  if (shape.points.length < 2) {
    return '';
  }
  final stroke = _hex(palette.resolve(shape.stroke, series: shape.series));
  final dash = switch (shape.style) {
    MermaidLineStyle.dashed => ' stroke-dasharray="7 5"',
    MermaidLineStyle.dotted => ' stroke-dasharray="2 5"',
    _ => '',
  };
  final buffer = StringBuffer('<g>');
  final points = shape.points;
  final path = StringBuffer('M ${_n(points.first.dx)} ${_n(points.first.dy)}');
  if (shape.cubic && points.length == 4) {
    path.write(' C ${_n(points[1].dx)} ${_n(points[1].dy)}'
        ' ${_n(points[2].dx)} ${_n(points[2].dy)}'
        ' ${_n(points[3].dx)} ${_n(points[3].dy)}');
  } else {
    for (final point in points.skip(1)) {
      path.write(' L ${_n(point.dx)} ${_n(point.dy)}');
    }
  }
  buffer.write(
    '<path d="$path" fill="none" stroke="$stroke" '
    'stroke-width="${_n(shape.strokeWidth)}" stroke-linecap="round"$dash/>',
  );
  buffer.write(
    _headToSvg(shape.head, points.last, shape.headDirection, stroke, palette),
  );
  buffer.write(
    _headToSvg(shape.tail, points.first, shape.tailDirection, stroke, palette),
  );
  buffer.write('</g>');
  return buffer.toString();
}

String _headToSvg(
  MermaidArrowHead head,
  Offset at,
  Offset direction,
  String stroke,
  MermaidPalette palette,
) {
  if (head == MermaidArrowHead.none) {
    return '';
  }
  final normal = Offset(-direction.dy, direction.dx);
  final surface = _hex(palette.canvas);

  String polygon(List<Offset> points, String fill) =>
      '<polygon points="${points.map((p) => '${_n(p.dx)},${_n(p.dy)}').join(' ')}" '
      'fill="$fill" stroke="$stroke" stroke-width="1.2"/>';

  String line(Offset a, Offset b) =>
      '<line x1="${_n(a.dx)}" y1="${_n(a.dy)}" x2="${_n(b.dx)}" y2="${_n(b.dy)}" '
      'stroke="$stroke" stroke-width="1.4" stroke-linecap="round"/>';

  switch (head) {
    case MermaidArrowHead.none:
      return '';
    case MermaidArrowHead.arrow:
      return polygon(
        [
          at,
          at - direction * 10 + normal * 4.6,
          at - direction * 10 - normal * 4.6,
        ],
        stroke,
      );
    case MermaidArrowHead.open:
      return line(at, at - direction * 10 + normal * 5) +
          line(at, at - direction * 10 - normal * 5);
    case MermaidArrowHead.cross:
      final back = at - direction * 4;
      return line(
            back + direction * 5 + normal * 5,
            back - direction * 5 - normal * 5,
          ) +
          line(
            back + direction * 5 - normal * 5,
            back - direction * 5 + normal * 5,
          );
    case MermaidArrowHead.circle:
      final centre = at - direction * 5;
      return '<circle cx="${_n(centre.dx)}" cy="${_n(centre.dy)}" r="5" '
          'fill="$surface" stroke="$stroke" stroke-width="1.4"/>';
    case MermaidArrowHead.triangle:
      return polygon(
        [
          at,
          at - direction * 12 + normal * 6,
          at - direction * 12 - normal * 6,
        ],
        surface,
      );
    case MermaidArrowHead.filledDiamond:
    case MermaidArrowHead.hollowDiamond:
      return polygon(
        [
          at,
          at - direction * 8 + normal * 5,
          at - direction * 16,
          at - direction * 8 - normal * 5,
        ],
        head == MermaidArrowHead.filledDiamond ? stroke : surface,
      );
    case MermaidArrowHead.one:
      final bar = at - direction * 9;
      return line(bar + normal * 6, bar - normal * 6);
    case MermaidArrowHead.many:
      final base = at - direction * 12;
      return line(at, base + normal * 6) +
          line(at, base - normal * 6) +
          line(at, base);
    case MermaidArrowHead.zeroOrOne:
      final centre = at - direction * 16;
      final bar = at - direction * 6;
      final dot = '<circle cx="${_n(centre.dx)}" cy="${_n(centre.dy)}" r="4.5" '
          'fill="$surface" stroke="$stroke" stroke-width="1.4"/>';
      return '$dot${line(bar + normal * 6, bar - normal * 6)}';
    case MermaidArrowHead.zeroOrMany:
      final centre = at - direction * 18;
      final base = at - direction * 13;
      final dot = '<circle cx="${_n(centre.dx)}" cy="${_n(centre.dy)}" r="4.5" '
          'fill="$surface" stroke="$stroke" stroke-width="1.4"/>';
      return '$dot${line(at, base + normal * 6)}${line(at, base - normal * 6)}';
  }
}

String _textToSvg(
  MermaidTextShape shape,
  MermaidPalette palette,
  MermaidTypography typography,
) {
  if (shape.text.isEmpty) {
    return '';
  }
  final style = typography.styleFor(
    shape.role,
    bold: shape.bold,
    italic: shape.italic,
  );
  final fontSize = style.fontSize ?? 13;
  final lineHeight = fontSize * (style.height ?? 1.32);
  final lines = _wrapLines(shape.text, style, shape.maxWidth);
  final anchor = switch (shape.align) {
    MermaidTextAlign.left => 'start',
    MermaidTextAlign.center => 'middle',
    MermaidTextAlign.right => 'end',
  };
  final colour = _hex(palette.resolve(shape.ink, series: shape.series));
  final family = style.fontFamily ?? 'system-ui';

  final buffer = StringBuffer(
    '<text x="${_n(shape.anchor.dx)}" y="${_n(shape.anchor.dy + fontSize * 1.02)}" '
    'text-anchor="$anchor" fill="$colour" font-size="${_n(fontSize)}" '
    'font-family="$family, system-ui, sans-serif" '
    'font-weight="${shape.bold ? 600 : 400}"'
    '${shape.italic ? ' font-style="italic"' : ''}>',
  );
  for (var i = 0; i < lines.length; i++) {
    buffer.write(
      '<tspan x="${_n(shape.anchor.dx)}" '
      'dy="${i == 0 ? '0' : _n(lineHeight)}">${_escape(lines[i])}</tspan>',
    );
  }
  buffer.write('</text>');
  return buffer.toString();
}

String _arcToSvg(MermaidArcShape shape, MermaidPalette palette) {
  final centre = shape.rect.center;
  final rx = shape.rect.width / 2;
  final ry = shape.rect.height / 2;
  final start = Offset(
    centre.dx + rx * math.cos(shape.startAngle),
    centre.dy + ry * math.sin(shape.startAngle),
  );
  final endAngle = shape.startAngle + shape.sweepAngle;
  final end = Offset(
    centre.dx + rx * math.cos(endAngle),
    centre.dy + ry * math.sin(endAngle),
  );
  final large = shape.sweepAngle.abs() > math.pi ? 1 : 0;
  final fill = _hex(palette.seriesAt(shape.series));
  final stroke = _hex(palette.resolve(shape.stroke));
  return '<path d="M ${_n(centre.dx)} ${_n(centre.dy)} '
      'L ${_n(start.dx)} ${_n(start.dy)} '
      'A ${_n(rx)} ${_n(ry)} 0 $large 1 ${_n(end.dx)} ${_n(end.dy)} Z" '
      'fill="$fill" stroke="$stroke" stroke-width="${_n(shape.strokeWidth)}"/>';
}

String _actorToSvg(MermaidActorGlyph shape, MermaidPalette palette) {
  final stroke = _hex(palette.resolve(shape.stroke));
  final rect = shape.rect;
  final headRadius = rect.width * 0.3;
  final headCentre = Offset(rect.center.dx, rect.top + headRadius + 1);
  final shoulders = headCentre.dy + headRadius + 3;
  return '<g fill="none" stroke="$stroke" stroke-width="1.6" '
      'stroke-linecap="round">'
      '<circle cx="${_n(headCentre.dx)}" cy="${_n(headCentre.dy)}" '
      'r="${_n(headRadius)}"/>'
      '<line x1="${_n(rect.center.dx)}" y1="${_n(shoulders)}" '
      'x2="${_n(rect.center.dx)}" y2="${_n(rect.bottom - 8)}"/>'
      '<line x1="${_n(rect.left)}" y1="${_n(shoulders + 4)}" '
      'x2="${_n(rect.right)}" y2="${_n(shoulders + 4)}"/>'
      '<line x1="${_n(rect.center.dx)}" y1="${_n(rect.bottom - 8)}" '
      'x2="${_n(rect.left + 2)}" y2="${_n(rect.bottom)}"/>'
      '<line x1="${_n(rect.center.dx)}" y1="${_n(rect.bottom - 8)}" '
      'x2="${_n(rect.right - 2)}" y2="${_n(rect.bottom)}"/></g>';
}

/// Splits a run of text the way the renderer wrapped it, so the SVG breaks in
/// the same places as the screen.
List<String> _wrapLines(String text, TextStyle style, double? maxWidth) {
  if (maxWidth == null && !text.contains('\n')) {
    return [text];
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
    maxLines: 6,
  )..layout(maxWidth: maxWidth ?? double.infinity);

  final lines = <String>[];
  var offset = 0;
  var guard = 0;
  while (offset < text.length && guard < 32) {
    guard += 1;
    final boundary = painter.getLineBoundary(TextPosition(offset: offset));
    final end = boundary.end <= offset ? text.length : boundary.end;
    lines.add(text.substring(offset, end).trimRight());
    offset = end;
    while (offset < text.length && text[offset] == '\n') {
      offset += 1;
    }
  }
  painter.dispose();
  return lines.isEmpty ? [text] : lines;
}

String _escape(String text) => const HtmlEscape().convert(text);

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

String _n(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}
