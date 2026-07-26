import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Subtle, film-like looks. Deliberately restrained: the editor is meant for
/// everyday touch-ups inside a document, not for stylised social filters.
enum ImageFilterPreset {
  none('None'),
  natural('Natural'),
  warm('Warm'),
  cool('Cool'),
  monochrome('Mono'),
  vintage('Vintage');

  const ImageFilterPreset(this.label);

  final String label;
}

/// A single continuous control in the adjustments panel.
enum ImageAdjustment {
  exposure('Exposure'),
  brightness('Brightness'),
  contrast('Contrast'),
  highlights('Highlights'),
  shadows('Shadows'),
  temperature('Temperature'),
  tint('Tint'),
  saturation('Saturation'),
  vibrance('Vibrance'),
  sharpness('Sharpness'),
  blur('Blur');

  const ImageAdjustment(this.label);

  final String label;

  /// Sharpness and blur only make sense in one direction.
  bool get isUnipolar =>
      this == ImageAdjustment.sharpness || this == ImageAdjustment.blur;

  double get minValue => isUnipolar ? 0 : -1;

  double get maxValue => 1;
}

@immutable
class ImageAdjustments {
  const ImageAdjustments({
    this.exposure = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.temperature = 0,
    this.tint = 0,
    this.saturation = 0,
    this.vibrance = 0,
    this.sharpness = 0,
    this.blur = 0,
  });

  static const none = ImageAdjustments();

  final double exposure;
  final double brightness;
  final double contrast;
  final double highlights;
  final double shadows;
  final double temperature;
  final double tint;
  final double saturation;
  final double vibrance;
  final double sharpness;
  final double blur;

  bool get isNeutral => this == none;

  double valueOf(ImageAdjustment adjustment) => switch (adjustment) {
        ImageAdjustment.exposure => exposure,
        ImageAdjustment.brightness => brightness,
        ImageAdjustment.contrast => contrast,
        ImageAdjustment.highlights => highlights,
        ImageAdjustment.shadows => shadows,
        ImageAdjustment.temperature => temperature,
        ImageAdjustment.tint => tint,
        ImageAdjustment.saturation => saturation,
        ImageAdjustment.vibrance => vibrance,
        ImageAdjustment.sharpness => sharpness,
        ImageAdjustment.blur => blur,
      };

  ImageAdjustments withValue(ImageAdjustment adjustment, double value) {
    final clamped =
        value.clamp(adjustment.minValue, adjustment.maxValue).toDouble();
    return switch (adjustment) {
      ImageAdjustment.exposure => copyWith(exposure: clamped),
      ImageAdjustment.brightness => copyWith(brightness: clamped),
      ImageAdjustment.contrast => copyWith(contrast: clamped),
      ImageAdjustment.highlights => copyWith(highlights: clamped),
      ImageAdjustment.shadows => copyWith(shadows: clamped),
      ImageAdjustment.temperature => copyWith(temperature: clamped),
      ImageAdjustment.tint => copyWith(tint: clamped),
      ImageAdjustment.saturation => copyWith(saturation: clamped),
      ImageAdjustment.vibrance => copyWith(vibrance: clamped),
      ImageAdjustment.sharpness => copyWith(sharpness: clamped),
      ImageAdjustment.blur => copyWith(blur: clamped),
    };
  }

  ImageAdjustments copyWith({
    double? exposure,
    double? brightness,
    double? contrast,
    double? highlights,
    double? shadows,
    double? temperature,
    double? tint,
    double? saturation,
    double? vibrance,
    double? sharpness,
    double? blur,
  }) =>
      ImageAdjustments(
        exposure: exposure ?? this.exposure,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        highlights: highlights ?? this.highlights,
        shadows: shadows ?? this.shadows,
        temperature: temperature ?? this.temperature,
        tint: tint ?? this.tint,
        saturation: saturation ?? this.saturation,
        vibrance: vibrance ?? this.vibrance,
        sharpness: sharpness ?? this.sharpness,
        blur: blur ?? this.blur,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageAdjustments &&
          other.exposure == exposure &&
          other.brightness == brightness &&
          other.contrast == contrast &&
          other.highlights == highlights &&
          other.shadows == shadows &&
          other.temperature == temperature &&
          other.tint == tint &&
          other.saturation == saturation &&
          other.vibrance == vibrance &&
          other.sharpness == sharpness &&
          other.blur == blur;

  @override
  int get hashCode => Object.hash(
        exposure,
        brightness,
        contrast,
        highlights,
        shadows,
        temperature,
        tint,
        saturation,
        vibrance,
        sharpness,
        blur,
      );
}

/// Aspect ratios offered by the crop tool.
enum ImageCropRatio {
  free('Free', null),
  original('Original', null),
  square('1:1', 1),
  fourThree('4:3', 4 / 3),
  sixteenNine('16:9', 16 / 9),
  a4('A4', 210 / 297);

  const ImageCropRatio(this.label, this.ratio);

  final String label;

  /// Width divided by height, or null when the ratio is not fixed.
  final double? ratio;

  /// Resolves the ratio for a source whose oriented aspect is [sourceAspect].
  double? resolve(double sourceAspect) => switch (this) {
        ImageCropRatio.free => null,
        ImageCropRatio.original => sourceAspect,
        _ => ratio,
      };
}

/// Rotation, mirroring and the normalized crop window.
///
/// The crop is expressed in the *oriented* frame — the one the user sees after
/// rotation and mirroring — which is what makes rotate-then-crop predictable.
@immutable
class ImageTransform {
  const ImageTransform({
    this.quarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.crop = const Rect.fromLTRB(0, 0, 1, 1),
    this.ratio = ImageCropRatio.free,
  });

  static const identity = ImageTransform();

  final int quarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final Rect crop;
  final ImageCropRatio ratio;

  bool get isIdentity =>
      quarterTurns == 0 &&
      !flipHorizontal &&
      !flipVertical &&
      crop == const Rect.fromLTRB(0, 0, 1, 1);

  ImageTransform rotated(int turns) {
    final next = (quarterTurns + turns) % 4;
    return copyWith(
      quarterTurns: next < 0 ? next + 4 : next,
      // The crop window belongs to the previous orientation, so rotating has
      // to start from a clean window instead of a silently squashed one.
      crop: const Rect.fromLTRB(0, 0, 1, 1),
    );
  }

  ImageTransform copyWith({
    int? quarterTurns,
    bool? flipHorizontal,
    bool? flipVertical,
    Rect? crop,
    ImageCropRatio? ratio,
  }) =>
      ImageTransform(
        quarterTurns: quarterTurns ?? this.quarterTurns,
        flipHorizontal: flipHorizontal ?? this.flipHorizontal,
        flipVertical: flipVertical ?? this.flipVertical,
        crop: crop ?? this.crop,
        ratio: ratio ?? this.ratio,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageTransform &&
          other.quarterTurns == quarterTurns &&
          other.flipHorizontal == flipHorizontal &&
          other.flipVertical == flipVertical &&
          other.crop == crop &&
          other.ratio == ratio;

  @override
  int get hashCode =>
      Object.hash(quarterTurns, flipHorizontal, flipVertical, crop, ratio);
}

enum ImageAnnotationTool {
  arrow('Arrow'),
  rectangle('Rectangle'),
  ellipse('Circle'),
  freehand('Draw'),
  highlight('Highlight'),
  text('Text'),
  blur('Blur region'),
  marker('Marker');

  const ImageAnnotationTool(this.label);

  final String label;

  /// Tools that are captured as a drag between two corners.
  bool get isDragged =>
      this == ImageAnnotationTool.arrow ||
      this == ImageAnnotationTool.rectangle ||
      this == ImageAnnotationTool.ellipse ||
      this == ImageAnnotationTool.highlight ||
      this == ImageAnnotationTool.blur;
}

/// One drawn mark. Coordinates are normalized to the cropped output so that
/// annotations survive zooming, panning and full resolution export.
@immutable
class ImageAnnotation {
  const ImageAnnotation({
    required this.id,
    required this.tool,
    required this.points,
    required this.color,
    this.strokeWidth = 0.005,
    this.text,
    this.markerNumber,
  });

  final int id;
  final ImageAnnotationTool tool;
  final List<Offset> points;
  final Color color;

  /// Fraction of the output width, so strokes scale with the export size.
  final double strokeWidth;
  final String? text;
  final int? markerNumber;

  ImageAnnotation copyWith({
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
    String? text,
    int? markerNumber,
  }) =>
      ImageAnnotation(
        id: id,
        tool: tool,
        points: points ?? this.points,
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        text: text ?? this.text,
        markerNumber: markerNumber ?? this.markerNumber,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageAnnotation &&
          other.id == id &&
          other.tool == tool &&
          listEquals(other.points, points) &&
          other.color == color &&
          other.strokeWidth == strokeWidth &&
          other.text == text &&
          other.markerNumber == markerNumber;

  @override
  int get hashCode => Object.hash(
        id,
        tool,
        Object.hashAll(points),
        color,
        strokeWidth,
        text,
        markerNumber,
      );
}

/// The complete, immutable description of an edit. Every history entry is one
/// of these, which keeps undo and redo trivial.
@immutable
class ImageEditSettings {
  const ImageEditSettings({
    this.adjustments = ImageAdjustments.none,
    this.transform = ImageTransform.identity,
    this.filter = ImageFilterPreset.none,
    this.annotations = const [],
  });

  static const pristine = ImageEditSettings();

  final ImageAdjustments adjustments;
  final ImageTransform transform;
  final ImageFilterPreset filter;
  final List<ImageAnnotation> annotations;

  bool get isPristine =>
      adjustments.isNeutral &&
      transform.isIdentity &&
      filter == ImageFilterPreset.none &&
      annotations.isEmpty;

  ImageEditSettings copyWith({
    ImageAdjustments? adjustments,
    ImageTransform? transform,
    ImageFilterPreset? filter,
    List<ImageAnnotation>? annotations,
  }) =>
      ImageEditSettings(
        adjustments: adjustments ?? this.adjustments,
        transform: transform ?? this.transform,
        filter: filter ?? this.filter,
        annotations: annotations ?? this.annotations,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageEditSettings &&
          other.adjustments == adjustments &&
          other.transform == transform &&
          other.filter == filter &&
          listEquals(other.annotations, annotations);

  @override
  int get hashCode => Object.hash(
        adjustments,
        transform,
        filter,
        Object.hashAll(annotations),
      );
}
