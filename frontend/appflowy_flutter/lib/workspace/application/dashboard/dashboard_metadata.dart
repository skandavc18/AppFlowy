import 'dart:convert';

import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// The note on a view that says "this page is a dashboard".
///
/// A dashboard is a `ViewLayoutPB.Document` wearing this envelope, exactly as a
/// chart is a grid wearing one. `ViewLayoutPB` lives in the pinned protobuf
/// schema and cannot gain a value from this side, and a dashboard has no
/// business being a database view anyway — the layout, the widgets and the
/// state are all its own.
@immutable
class DashboardMetadata {
  const DashboardMetadata({required this.document});

  static const envelopeKey = 'appflowy_dashboard';
  static const currentVersion = 1;

  final DashboardDocument document;

  DashboardMetadata copyWith({DashboardDocument? document}) =>
      DashboardMetadata(document: document ?? this.document);

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'spec': document.toJson(),
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  static String removeFromExtra(String extra) {
    final values = decodeViewExtra(extra)..remove(envelopeKey);
    return values.isEmpty ? '' : jsonEncode(values);
  }

  static DashboardMetadata? fromExtra(String extra) {
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
    return DashboardMetadata(
      document: DashboardDocument.fromJson(
        spec is Map ? Map<String, Object?>.from(spec) : const {},
      ),
    );
  }

  static String newExtra({DashboardDocument? document}) =>
      DashboardMetadata(document: document ?? DashboardDocument.blank())
          .mergeIntoExtra('');

  @override
  bool operator ==(Object other) =>
      other is DashboardMetadata && other.document == document;

  @override
  int get hashCode => document.hashCode;
}

extension DashboardViewExtension on ViewPB {
  DashboardMetadata? get dashboard => DashboardMetadata.fromExtra(extra);

  /// A dashboard is a document page, never a database view.
  bool get isDashboard => layout == ViewLayoutPB.Document && dashboard != null;
}
