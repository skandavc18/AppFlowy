import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'image_edit_settings.dart';

/// Identity 4x5 colour matrix in Flutter's row-major layout.
const List<double> _identityMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Returns the matrix that applies [second] after [first].
List<double> _compose(List<double> second, List<double> first) {
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += second[row * 5 + k] * first[k * 5 + col];
      }
      if (col == 4) {
        sum += second[row * 5 + 4];
      }
      result[row * 5 + col] = sum;
    }
  }
  return result;
}

List<double> _scaleRgb(double r, double g, double b) => <double>[
      r, 0, 0, 0, 0, //
      0, g, 0, 0, 0, //
      0, 0, b, 0, 0, //
      0, 0, 0, 1, 0, //
    ];

List<double> _offsetRgb(double value) => <double>[
      1, 0, 0, 0, value, //
      0, 1, 0, 0, value, //
      0, 0, 1, 0, value, //
      0, 0, 0, 1, 0, //
    ];

List<double> _contrastMatrix(double amount) {
  final intercept = 127.5 * (1 - amount);
  return <double>[
    amount, 0, 0, 0, intercept, //
    0, amount, 0, 0, intercept, //
    0, 0, amount, 0, intercept, //
    0, 0, 0, 1, 0, //
  ];
}

const double _lumR = 0.2126;
const double _lumG = 0.7152;
const double _lumB = 0.0722;

List<double> _saturationMatrix(double amount) {
  final inverse = 1 - amount;
  return <double>[
    _lumR * inverse + amount, _lumG * inverse, _lumB * inverse, 0, 0, //
    _lumR * inverse, _lumG * inverse + amount, _lumB * inverse, 0, 0, //
    _lumR * inverse, _lumG * inverse, _lumB * inverse + amount, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _presetMatrix(ImageFilterPreset preset) => switch (preset) {
      ImageFilterPreset.none => _identityMatrix,
      ImageFilterPreset.natural =>
        _compose(_saturationMatrix(1.06), _contrastMatrix(1.05)),
      ImageFilterPreset.warm => _compose(
          _offsetRgb(3),
          _scaleRgb(1.06, 1.005, 0.94),
        ),
      ImageFilterPreset.cool => _compose(
          _offsetRgb(2),
          _scaleRgb(0.945, 0.995, 1.07),
        ),
      ImageFilterPreset.monochrome =>
        _compose(_contrastMatrix(1.07), _saturationMatrix(0)),
      ImageFilterPreset.vintage => _compose(
          _offsetRgb(9),
          _compose(
            _scaleRgb(1.04, 0.99, 0.92),
            _saturationMatrix(0.78),
          ),
        ),
    };

/// Builds the single colour matrix that represents every non-spatial
/// adjustment, so the GPU applies them in one pass.
List<double> buildColorMatrix(
  ImageAdjustments adjustments,
  ImageFilterPreset preset,
) {
  var matrix = _identityMatrix;

  if (adjustments.exposure != 0) {
    final gain = math.pow(2, adjustments.exposure * 1.2).toDouble();
    matrix = _compose(_scaleRgb(gain, gain, gain), matrix);
  }

  if (adjustments.temperature != 0) {
    final t = adjustments.temperature;
    matrix = _compose(
      _scaleRgb(1 + t * 0.16, 1 + t * 0.02, 1 - t * 0.16),
      matrix,
    );
  }

  if (adjustments.tint != 0) {
    final t = adjustments.tint;
    matrix = _compose(
      _scaleRgb(1 - t * 0.06, 1 + t * 0.12, 1 - t * 0.06),
      matrix,
    );
  }

  if (adjustments.contrast != 0) {
    matrix = _compose(_contrastMatrix(1 + adjustments.contrast * 0.6), matrix);
  }

  if (adjustments.brightness != 0) {
    matrix = _compose(_offsetRgb(adjustments.brightness * 52), matrix);
  }

  if (adjustments.saturation != 0) {
    matrix = _compose(_saturationMatrix(1 + adjustments.saturation), matrix);
  }

  if (adjustments.vibrance != 0) {
    // Vibrance is a gentler saturation: enough to lift flat colours without
    // clipping skin tones the way a full saturation boost does.
    matrix = _compose(
      _saturationMatrix(1 + adjustments.vibrance * 0.45),
      matrix,
    );
  }

  if (preset != ImageFilterPreset.none) {
    matrix = _compose(_presetMatrix(preset), matrix);
  }

  return matrix;
}

/// White with alpha driven by luminance (or its inverse), used to confine the
/// highlight and shadow passes to the right tonal range.
List<double> _toneMaskMatrix(List<double> base, {required bool highlights}) {
  final mask = highlights
      ? <double>[
          0, 0, 0, 0, 255, //
          0, 0, 0, 0, 255, //
          0, 0, 0, 0, 255, //
          _lumR, _lumG, _lumB, 0, 0, //
        ]
      : <double>[
          0, 0, 0, 0, 255, //
          0, 0, 0, 0, 255, //
          0, 0, 0, 0, 255, //
          -_lumR, -_lumG, -_lumB, 1, 0, //
        ];
  return _compose(mask, base);
}

/// Geometry of an edit: how the source pixels map into the cropped output.
class ImageEditGeometry {
  ImageEditGeometry({required this.imageSize, required this.transform});

  factory ImageEditGeometry.forImage(
    ui.Image image,
    ImageTransform transform,
  ) =>
      ImageEditGeometry(
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        transform: transform,
      );

  final Size imageSize;
  final ImageTransform transform;

  bool get _isQuarterTurned => transform.quarterTurns.isOdd;

  /// Size of the image after rotation, before cropping.
  Size get orientedSize =>
      _isQuarterTurned ? Size(imageSize.height, imageSize.width) : imageSize;

  Rect get cropRect {
    final oriented = orientedSize;
    final crop = transform.crop;
    return Rect.fromLTRB(
      crop.left * oriented.width,
      crop.top * oriented.height,
      crop.right * oriented.width,
      crop.bottom * oriented.height,
    );
  }

  Size get outputSize {
    final rect = cropRect;
    return Size(
      math.max(1, rect.width),
      math.max(1, rect.height),
    );
  }

  double get outputAspectRatio {
    final size = outputSize;
    return size.width / size.height;
  }

  /// Maps a point normalized to the cropped output back to source pixels.
  Offset outputToImage(Offset normalized) {
    final crop = cropRect;
    final oriented = orientedSize;
    var x = crop.left + normalized.dx * crop.width;
    var y = crop.top + normalized.dy * crop.height;
    if (transform.flipHorizontal) {
      x = oriented.width - x;
    }
    if (transform.flipVertical) {
      y = oriented.height - y;
    }
    return switch (transform.quarterTurns % 4) {
      1 => Offset(y, imageSize.height - x),
      2 => Offset(imageSize.width - x, imageSize.height - y),
      3 => Offset(imageSize.width - y, x),
      _ => Offset(x, y),
    };
  }

  Rect outputRectToImage(Rect normalized) => Rect.fromPoints(
        outputToImage(normalized.topLeft),
        outputToImage(normalized.bottomRight),
      );

  /// Applies the source-to-output transform to [canvas]; afterwards the canvas
  /// is in source pixel space and the image can be drawn at the origin.
  void applyTo(ui.Canvas canvas, Rect destination) {
    final crop = cropRect;
    final oriented = orientedSize;
    canvas.translate(destination.left, destination.top);
    canvas.scale(
      destination.width / crop.width,
      destination.height / crop.height,
    );
    canvas.translate(-crop.left, -crop.top);
    if (transform.flipHorizontal) {
      canvas.translate(oriented.width, 0);
      canvas.scale(-1, 1);
    }
    if (transform.flipVertical) {
      canvas.translate(0, oriented.height);
      canvas.scale(1, -1);
    }
    switch (transform.quarterTurns % 4) {
      case 1:
        canvas.translate(imageSize.height, 0);
        canvas.rotate(math.pi / 2);
      case 2:
        canvas.translate(imageSize.width, imageSize.height);
        canvas.rotate(math.pi);
      case 3:
        canvas.translate(0, imageSize.width);
        canvas.rotate(-math.pi / 2);
      default:
        break;
    }
  }
}

const double _toneStrength = 0.55;

double _blurSigma(double amount, Size imageSize) =>
    amount * 0.02 * imageSize.shortestSide;

double _sharpenSigma(Size imageSize) =>
    math.max(0.8, imageSize.shortestSide * 0.0015);

/// Draws [image] into [destination] with every adjustment, filter, crop and
/// annotation applied. The same routine feeds the live preview and the export,
/// so what the user sees is what gets written to disk.
void paintEditedImage(
  ui.Canvas canvas,
  ui.Image image,
  Rect destination,
  ImageEditSettings settings, {
  bool includeAnnotations = true,
  FilterQuality filterQuality = FilterQuality.medium,
}) {
  final geometry = ImageEditGeometry.forImage(image, settings.transform);
  final imageSize = geometry.imageSize;
  final imageRect = Offset.zero & imageSize;
  final matrix = buildColorMatrix(settings.adjustments, settings.filter);
  final adjustments = settings.adjustments;

  canvas.save();
  canvas.clipRect(destination);
  geometry.applyTo(canvas, destination);

  // One layer keeps the tonal and sharpening passes blending against the
  // photo instead of whatever is behind the editor.
  canvas.saveLayer(imageRect, ui.Paint());

  final basePaint = ui.Paint()
    ..filterQuality = filterQuality
    ..colorFilter = ui.ColorFilter.matrix(matrix);
  if (adjustments.blur > 0) {
    final sigma = _blurSigma(adjustments.blur, imageSize);
    basePaint.imageFilter = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.decal,
    );
  }
  canvas.drawImage(image, Offset.zero, basePaint);

  if (adjustments.highlights != 0) {
    _paintTonePass(
      canvas,
      image,
      imageRect,
      matrix,
      amount: adjustments.highlights,
      highlights: true,
    );
  }
  if (adjustments.shadows != 0) {
    _paintTonePass(
      canvas,
      image,
      imageRect,
      matrix,
      amount: adjustments.shadows,
      highlights: false,
    );
  }

  if (adjustments.sharpness > 0) {
    _paintSharpenPass(
      canvas,
      image,
      imageRect,
      matrix,
      amount: adjustments.sharpness,
      sigma: _sharpenSigma(imageSize),
    );
  }

  if (includeAnnotations) {
    for (final annotation in settings.annotations) {
      if (annotation.tool != ImageAnnotationTool.blur ||
          annotation.points.length < 2) {
        continue;
      }
      final region = geometry.outputRectToImage(
        Rect.fromPoints(annotation.points.first, annotation.points.last),
      );
      if (region.width <= 0 || region.height <= 0) {
        continue;
      }
      final sigma = math.max(2.0, region.shortestSide * 0.09);
      canvas.save();
      canvas.clipRect(region);
      canvas.drawImage(
        image,
        Offset.zero,
        ui.Paint()
          ..filterQuality = filterQuality
          ..colorFilter = ui.ColorFilter.matrix(matrix)
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
          ),
      );
      canvas.restore();
    }
  }

  canvas.restore();
  canvas.restore();

  if (includeAnnotations && settings.annotations.isNotEmpty) {
    paintAnnotations(canvas, destination, settings.annotations);
  }
}

void _paintTonePass(
  ui.Canvas canvas,
  ui.Image image,
  Rect imageRect,
  List<double> baseMatrix, {
  required double amount,
  required bool highlights,
}) {
  final strength = (amount.abs() * _toneStrength).clamp(0.0, 1.0);
  if (strength <= 0) {
    return;
  }
  final paint = ui.Paint()
    ..colorFilter = ui.ColorFilter.matrix(
        _toneMaskMatrix(baseMatrix, highlights: highlights))
    ..color = ui.Color.fromRGBO(255, 255, 255, strength)
    // Adding white lifts the masked range; multiplying by the mask's inverse
    // pulls it down. Both keep untouched tones exactly where they were.
    ..blendMode = amount > 0 ? ui.BlendMode.plus : ui.BlendMode.multiply;
  canvas.drawImage(image, Offset.zero, paint);
}

/// Classic high-pass sharpening: overlay `0.5 + 0.5 * (image - blur(image))`
/// on top of the photo. Neutral grey leaves flat areas untouched, so only
/// edges gain contrast.
void _paintSharpenPass(
  ui.Canvas canvas,
  ui.Image image,
  Rect imageRect,
  List<double> baseMatrix, {
  required double amount,
  required double sigma,
}) {
  const halve = <double>[
    0.5, 0, 0, 0, 0, //
    0, 0.5, 0, 0, 0, //
    0, 0, 0.5, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
  const invert = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  canvas.saveLayer(
    imageRect,
    ui.Paint()..blendMode = ui.BlendMode.overlay,
  );
  canvas.drawRect(imageRect, ui.Paint()..color = const Color(0xFF808080));

  canvas.saveLayer(
    imageRect,
    ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, amount.clamp(0, 1)),
  );
  canvas.drawImage(
    image,
    Offset.zero,
    ui.Paint()
      ..colorFilter = ui.ColorFilter.matrix(_compose(halve, baseMatrix)),
  );
  canvas.drawImage(
    image,
    Offset.zero,
    ui.Paint()
      ..colorFilter = ui.ColorFilter.matrix(
        _compose(halve, _compose(invert, baseMatrix)),
      )
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
      )
      ..blendMode = ui.BlendMode.plus,
  );
  canvas.restore();
  canvas.restore();
}

/// Paints the marks on top of an already rendered photo occupying [area].
void paintAnnotations(
  ui.Canvas canvas,
  Rect area,
  List<ImageAnnotation> annotations,
) {
  Offset toLocal(Offset normalized) => Offset(
        area.left + normalized.dx * area.width,
        area.top + normalized.dy * area.height,
      );

  canvas.save();
  canvas.clipRect(area);
  for (final annotation in annotations) {
    if (annotation.points.isEmpty) {
      continue;
    }
    final stroke = math.max(1.0, annotation.strokeWidth * area.width);
    final paint = ui.Paint()
      ..color = annotation.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (annotation.tool) {
      case ImageAnnotationTool.blur:
        break;
      case ImageAnnotationTool.arrow:
        if (annotation.points.length < 2) {
          break;
        }
        _paintArrow(
          canvas,
          toLocal(annotation.points.first),
          toLocal(annotation.points.last),
          paint,
          stroke,
        );
      case ImageAnnotationTool.rectangle:
        if (annotation.points.length < 2) {
          break;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromPoints(
              toLocal(annotation.points.first),
              toLocal(annotation.points.last),
            ),
            Radius.circular(stroke * 0.9),
          ),
          paint,
        );
      case ImageAnnotationTool.ellipse:
        if (annotation.points.length < 2) {
          break;
        }
        canvas.drawOval(
          Rect.fromPoints(
            toLocal(annotation.points.first),
            toLocal(annotation.points.last),
          ),
          paint,
        );
      case ImageAnnotationTool.highlight:
        if (annotation.points.length < 2) {
          break;
        }
        canvas.drawRect(
          Rect.fromPoints(
            toLocal(annotation.points.first),
            toLocal(annotation.points.last),
          ),
          ui.Paint()
            ..color = annotation.color.withValues(alpha: 0.32)
            ..blendMode = ui.BlendMode.srcOver,
        );
      case ImageAnnotationTool.freehand:
        final path = Path()
          ..moveTo(
            toLocal(annotation.points.first).dx,
            toLocal(annotation.points.first).dy,
          );
        for (var i = 1; i < annotation.points.length; i++) {
          final point = toLocal(annotation.points[i]);
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      case ImageAnnotationTool.text:
        _paintText(canvas, toLocal(annotation.points.first), annotation, area);
      case ImageAnnotationTool.marker:
        _paintMarker(
            canvas, toLocal(annotation.points.first), annotation, area);
    }
  }
  canvas.restore();
}

void _paintArrow(
  ui.Canvas canvas,
  Offset from,
  Offset to,
  ui.Paint paint,
  double stroke,
) {
  final delta = to - from;
  final length = delta.distance;
  if (length < 0.5) {
    return;
  }
  final direction = delta / length;
  final head = math.min(length * 0.4, stroke * 4.5);
  final base = to - direction * head;
  canvas.drawLine(from, base, paint);

  final normal = Offset(-direction.dy, direction.dx) * (head * 0.42);
  final path = Path()
    ..moveTo(to.dx, to.dy)
    ..lineTo(base.dx + normal.dx, base.dy + normal.dy)
    ..lineTo(base.dx - normal.dx, base.dy - normal.dy)
    ..close();
  canvas.drawPath(
    path,
    ui.Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true,
  );
}

TextPainter _annotationTextPainter(
  ImageAnnotation annotation,
  double fontSize,
) {
  return TextPainter(
    text: TextSpan(
      text: annotation.text ?? '',
      style: TextStyle(
        color: annotation.color,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.2,
        shadows: [
          ui.Shadow(
            color: const Color(0xFF000000).withValues(alpha: 0.35),
            blurRadius: fontSize * 0.25,
          ),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

void _paintText(
  ui.Canvas canvas,
  Offset origin,
  ImageAnnotation annotation,
  Rect area,
) {
  final text = annotation.text;
  if (text == null || text.isEmpty) {
    return;
  }
  final fontSize = math.max(10.0, annotation.strokeWidth * area.width * 5.2);
  _annotationTextPainter(annotation, fontSize).paint(canvas, origin);
}

void _paintMarker(
  ui.Canvas canvas,
  Offset center,
  ImageAnnotation annotation,
  Rect area,
) {
  final radius = math.max(10.0, annotation.strokeWidth * area.width * 3.4);
  canvas.drawCircle(
    center,
    radius,
    ui.Paint()
      ..color = annotation.color
      ..isAntiAlias = true,
  );
  final painter = TextPainter(
    text: TextSpan(
      text: '${annotation.markerNumber ?? 1}',
      style: TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: radius * 1.15,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    center - Offset(painter.width / 2, painter.height / 2),
  );
}

/// Renders the edit at full source resolution.
Future<ui.Image> renderEditedImage(
  ui.Image image,
  ImageEditSettings settings,
) async {
  final geometry = ImageEditGeometry.forImage(image, settings.transform);
  final size = geometry.outputSize;
  final width = size.width.round().clamp(1, 1 << 16);
  final height = size.height.round().clamp(1, 1 << 16);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintEditedImage(
    canvas,
    image,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    settings,
    filterQuality: FilterQuality.high,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// Renders the edit and encodes it as PNG bytes.
Future<Uint8List> encodeEditedImage(
  ui.Image image,
  ImageEditSettings settings,
) async {
  final rendered = await renderEditedImage(image, settings);
  try {
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Unable to encode the edited image');
    }
    return data.buffer.asUint8List();
  } finally {
    rendered.dispose();
  }
}
