import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// A page identity's square frame, in logical pixels. This is view metadata,
/// not an icon choice, editor attribute, global preference or image file.
abstract final class IconSize {
  static const key = 'page_icon_size';
  static const minimum = 16.0;
  static const maximum = 320.0;

  /// Missing/invalid values keep the host's original optical default. Reading
  /// is tolerant; writing deliberately refuses malformed surrounding metadata.
  static double? decode(String extra) {
    try {
      final value = ViewCoverCodec.decodeExtra(extra)[key];
      if (value is num &&
          value.isFinite &&
          value >= minimum &&
          value <= maximum) {
        return value.toDouble();
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static double clamp(double size) {
    if (!size.isFinite) {
      throw ArgumentError.value(size, 'size', 'Must be finite');
    }
    return size.clamp(minimum, maximum).toDouble();
  }

  /// Null resets to the original default by removing ONLY this field.
  static String merge(String extra, double? size) {
    final metadata = ViewCoverCodec.decodeExtra(extra);
    if (size == null) {
      metadata.remove(key);
    } else {
      if (!size.isFinite || size < minimum || size > maximum) {
        throw ArgumentError.value(size, 'size', 'Outside page icon bounds');
      }
      metadata[key] = size;
    }
    return jsonEncode(metadata);
  }

  /// Use only after acknowledgement, against the host's CURRENT view. Never
  /// mutate/freeze a shared protobuf or adopt a stale save response wholesale.
  static ViewPB applyTo(ViewPB view, double? size) =>
      ViewPB.fromBuffer(view.writeToBuffer())..extra = merge(view.extra, size);
}
