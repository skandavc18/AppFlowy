import 'dart:convert';

import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// The mark that says a table should open as a chart.
///
/// A chart is not a kind of view the backend knows about — it is a reading of
/// a table. So a chart *is* a table, with this note attached saying which
/// picture of it to show first. Nothing is lost: the rows are always there,
/// one click away.
@immutable
class ChartMetadata {
  const ChartMetadata({required this.spec, this.showTable = false});

  static const envelopeKey = 'appflowy_chart';
  static const currentVersion = 1;

  /// How the table is plotted.
  final ChartSpec spec;

  /// Whether the page was last left showing the rows instead of the picture.
  final bool showTable;

  ChartMetadata copyWith({ChartSpec? spec, bool? showTable}) => ChartMetadata(
        spec: spec ?? this.spec,
        showTable: showTable ?? this.showTable,
      );

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'spec': spec.toJson(),
        if (showTable) 'show_table': true,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  /// Removes the mark, turning a chart back into a plain table.
  static String removeFromExtra(String extra) {
    final values = decodeViewExtra(extra)..remove(envelopeKey);
    return values.isEmpty ? '' : jsonEncode(values);
  }

  static ChartMetadata? fromExtra(String extra) {
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
    return ChartMetadata(
      spec: ChartSpec.fromJson(
        spec is Map ? Map<String, dynamic>.from(spec) : const {},
      ),
      showTable: values['show_table'] == true,
    );
  }

  /// The `extra` payload of a brand new chart.
  static String newExtra({ChartSpec spec = const ChartSpec()}) =>
      ChartMetadata(spec: spec).mergeIntoExtra('');
}

extension ChartViewExtension on ViewPB {
  ChartMetadata? get chart => ChartMetadata.fromExtra(extra);

  /// A chart is a table that has been asked to draw itself.
  bool get isChart =>
      chart != null &&
      const [ViewLayoutPB.Grid, ViewLayoutPB.Board, ViewLayoutPB.Calendar]
          .contains(layout);
}
