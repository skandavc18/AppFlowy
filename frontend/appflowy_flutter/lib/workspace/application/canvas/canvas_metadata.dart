import 'dart:convert';

import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// The note on a view that says "this page is a canvas".
///
/// A canvas is a `ViewLayoutPB.Document` wearing this envelope, exactly as a
/// dashboard is. `ViewLayoutPB` lives in the pinned protobuf schema and cannot
/// gain a value from this side — and a canvas has no business being a database
/// view anyway, since nothing about it is a table.
@immutable
class CanvasMetadata {
  const CanvasMetadata({required this.document});

  static const envelopeKey = 'appflowy_canvas';
  static const currentVersion = 1;

  final CanvasDocument document;

  CanvasMetadata copyWith({CanvasDocument? document}) =>
      CanvasMetadata(document: document ?? this.document);

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'spec': document.toJson(),
      };

  /// Merge into whatever else the view already carries — the cover, the icon,
  /// the spell-check mark. A stale copy would erase all of it.
  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  static String removeFromExtra(String extra) {
    final values = decodeViewExtra(extra)..remove(envelopeKey);
    return values.isEmpty ? '' : jsonEncode(values);
  }

  static CanvasMetadata? fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return null;
    }
    final values = Map<String, dynamic>.from(envelope);
    final version = values['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      return null;
    }
    final spec = values['spec'];
    return CanvasMetadata(
      document: CanvasDocument.fromJson(
        spec is Map ? Map<String, Object?>.from(spec) : const {},
      ),
    );
  }

  static String newExtra({CanvasDocument? document}) =>
      CanvasMetadata(document: document ?? CanvasDocument.blank())
          .mergeIntoExtra('');

  @override
  bool operator ==(Object other) =>
      other is CanvasMetadata && other.document == document;

  @override
  int get hashCode => document.hashCode;
}

extension CanvasViewExtension on ViewPB {
  CanvasMetadata? get canvas => CanvasMetadata.fromExtra(extra);

  /// A canvas is a document page, never a database view.
  bool get isCanvas => layout == ViewLayoutPB.Document && canvas != null;
}
