import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show BoxConstraints;

/// Physical-pixel targets, independent of text scale and saved page geometry.
/// Buckets limit decode-cache churn while a cover/pane is being resized.
@immutable
class CoverImageDecodeSize {
  const CoverImageDecodeSize(this.width, this.height)
      : assert(width > 0 && width <= maximumDimension),
        assert(height > 0 && height <= maximumDimension);

  static const maximumDimension = 4096;
  final int width;
  final int height;

  static CoverImageDecodeSize? fromConstraints(
    BoxConstraints constraints,
    double devicePixelRatio, {
    double? width,
    double? height,
  }) {
    final size = constraints.constrain(Size(
      width ?? constraints.maxWidth,
      height ?? constraints.maxHeight,
    ));
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.isEmpty ||
        !devicePixelRatio.isFinite ||
        devicePixelRatio <= 0) {
      return null;
    }
    return CoverImageDecodeSize(
      _bucket(size.width * devicePixelRatio),
      _bucket(size.height * devicePixelRatio),
    );
  }

  static int _bucket(double pixels) {
    // Small thumbnails need small buckets; large hero covers use 256px steps.
    final step = pixels <= 256
        ? 32
        : pixels <= 1024
            ? 128
            : 256;
    return ((pixels.clamp(1, maximumDimension) / step).ceil() * step)
        .clamp(1, maximumDimension)
        .toInt();
  }

  /// Called by the codec with the actual encoded dimensions, before decoding.
  /// Crop must cover BOTH axes; fitting into a bounding box would blur the
  /// cropped axis. Preserve aspect for fit/crop; stretch is a paint operation.
  /// Extreme aspect ratios hit the explicit 4096px safety ceiling, not an
  /// unbounded allocation. Fullscreen providers never opt into this policy.
  ui.TargetImageSize target(
      int intrinsicWidth, int intrinsicHeight, BoxFit fit) {
    // Keep the scale rational until the final integer ceiling. For example,
    // 800 * (224 / 800) can be 224.00000000000003; ceil would allocate 225
    // pixels and break contain's bound on an otherwise exact-sized axis.
    final widthIsSmaller = width * intrinsicHeight <= height * intrinsicWidth;
    final useWidth = switch (fit) {
      BoxFit.contain || BoxFit.scaleDown => widthIsSmaller,
      BoxFit.fitWidth => true,
      BoxFit.fitHeight => false,
      BoxFit.none => true,
      BoxFit.cover || BoxFit.fill => !widthIsSmaller,
    };
    var numerator = useWidth ? width : height;
    var denominator = useWidth ? intrinsicWidth : intrinsicHeight;
    if (fit == BoxFit.none || numerator > denominator) {
      numerator = denominator = 1;
    }
    final longest = math.max(intrinsicWidth, intrinsicHeight);
    if (longest * numerator > maximumDimension * denominator) {
      numerator = maximumDimension;
      denominator = longest;
    }
    int pixels(int intrinsic) =>
        ((intrinsic * numerator + denominator - 1) ~/ denominator)
            .clamp(1, maximumDimension);
    return ui.TargetImageSize(
      width: pixels(intrinsicWidth),
      height: pixels(intrinsicHeight),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoverImageDecodeSize &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// A resize-only adapter: the wrapped provider still owns bytes, animation and
/// chunk events. Image's normal ScrollAwareImageProvider remains in charge of
/// admission. No preload, extra file read, or full-resolution probe decode.
class CoverImageProvider extends ImageProvider<CoverImageKey> {
  const CoverImageProvider(this.imageProvider, this.size, this.fit);

  final ImageProvider imageProvider;
  final CoverImageDecodeSize size;
  final BoxFit fit;

  @override
  Future<CoverImageKey> obtainKey(ImageConfiguration configuration) =>
      imageProvider.obtainKey(configuration).then(
            (key) => CoverImageKey(key, size, fit),
          );

  @override
  ImageStreamCompleter loadImage(
      CoverImageKey key, ImageDecoderCallback decode) {
    final completer = imageProvider.loadImage(
      key.source,
      (buffer, {getTargetSize}) => decode(
        buffer,
        getTargetSize: (width, height) =>
            key.size.target(width, height, key.fit),
      ),
    );
    completer.addEphemeralErrorListener((error, stack) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is CoverImageProvider &&
      imageProvider == other.imageProvider &&
      size == other.size &&
      fit == other.fit;

  @override
  int get hashCode => Object.hash(imageProvider, size, fit);
}

@immutable
class CoverImageKey {
  const CoverImageKey(this.source, this.size, this.fit);
  final Object source;
  final CoverImageDecodeSize size;
  final BoxFit fit;

  @override
  bool operator ==(Object other) =>
      other is CoverImageKey &&
      source == other.source &&
      size == other.size &&
      fit == other.fit;

  @override
  int get hashCode => Object.hash(source, size, fit);
}
