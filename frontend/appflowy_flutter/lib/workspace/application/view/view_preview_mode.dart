import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

enum ViewPreviewMode {
  cover,
  content;

  static ViewPreviewMode fromValue(Object? value) {
    return value == content.name ? content : cover;
  }
}

abstract final class ViewPreviewModeCodec {
  static const key = 'preview_mode';

  static ViewPreviewMode decode(String extra) {
    final metadata = ViewCoverCodec.decodeExtra(extra);
    return ViewPreviewMode.fromValue(metadata[key]);
  }

  static String merge(String extra, ViewPreviewMode mode) {
    final metadata = ViewCoverCodec.decodeExtra(extra);
    metadata[key] = mode.name;
    return jsonEncode(metadata);
  }
}

extension ViewPreviewModeExtension on ViewPB {
  ViewPreviewMode get previewMode {
    try {
      return ViewPreviewModeCodec.decode(extra);
    } on FormatException {
      return ViewPreviewMode.cover;
    }
  }
}
