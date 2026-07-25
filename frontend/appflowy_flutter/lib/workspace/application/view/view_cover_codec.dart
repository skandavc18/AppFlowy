import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_cover.dart';

abstract final class ViewCoverCodec {
  static const coverKey = 'cover';
  static const coverTypeKey = 'type';
  static const coverValueKey = 'value';

  static Map<String, dynamic> decodeExtra(String extra) {
    if (extra.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(extra);
    if (decoded is! Map) {
      throw const FormatException('View extra metadata must be a JSON object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static PageStyleCover? decodeCover(String extra) {
    final metadata = decodeExtra(extra);
    final value = metadata[coverKey];
    if (value is! Map) {
      return null;
    }

    final cover = Map<String, dynamic>.from(value);
    final type = cover[coverTypeKey];
    final coverValue = cover[coverValueKey];
    return PageStyleCover(
      type: PageStyleCoverImageType.fromString(type is String ? type : null),
      value: coverValue is String ? coverValue : '',
    );
  }

  static String mergeCover(String extra, PageStyleCover cover) {
    final metadata = decodeExtra(extra);
    metadata[coverKey] = <String, dynamic>{
      coverTypeKey: cover.type.toString(),
      coverValueKey: cover.value,
    };
    return jsonEncode(metadata);
  }
}
