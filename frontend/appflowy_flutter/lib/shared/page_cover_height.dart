import 'dart:convert';
import 'dart:math' as math;

import 'package:appflowy/workspace/application/settings/cover_appearance.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// Logical-pixel override, independent of the cover image and default ratio.
abstract final class PageCoverHeight {
  static const key = 'page_cover_height';
  static const minimum = 96.0;
  static const maximum = 640.0;

  static double? decode(String extra) {
    try {
      final value = ViewCoverCodec.decodeExtra(extra)[key];
      return value is num &&
              value.isFinite &&
              value >= minimum &&
              value <= maximum
          ? value.toDouble()
          : null;
    } on FormatException {
      return null;
    }
  }

  static double maximumFor(double width) => width.isFinite && width > 0
      ? math.max(minimum, math.min(maximum, width))
      : maximum;

  static double resolve({
    required double width,
    required CoverAppearance appearance,
    required double fallback,
    double? override,
  }) {
    final ratio = appearance.aspectRatio;
    final value = override ??
        (ratio != null &&
                CoverAppearance.validRatio(ratio) &&
                width.isFinite &&
                width > 0
            ? width / ratio
            : fallback);
    return (value.isFinite ? value : minimum)
        .clamp(minimum, maximumFor(width))
        .toDouble();
  }

  static String merge(String extra, double? height) {
    // Refuse malformed surrounding metadata; never silently replace it.
    final map = ViewCoverCodec.decodeExtra(extra);
    if (height == null) {
      map.remove(key);
    } else {
      if (!height.isFinite || height < minimum || height > maximum) {
        throw ArgumentError('Invalid page cover height');
      }
      map[key] = height;
    }
    return jsonEncode(map);
  }

  static ViewPB applyTo(ViewPB view, double? height) =>
      ViewPB.fromBuffer(view.writeToBuffer())
        ..extra = merge(view.extra, height);
}
