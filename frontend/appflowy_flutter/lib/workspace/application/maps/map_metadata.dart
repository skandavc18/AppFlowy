import 'dart:convert';

import 'package:appflowy/workspace/application/maps/map_spec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// The mark that says a table should open on a map.
///
/// Like a chart, a map is a reading of a table rather than a kind of view the
/// backend knows about: the rows are untouched and one click away, and the
/// same table can still be seen as a grid, a board or a calendar.
@immutable
class MapMetadata {
  const MapMetadata({required this.spec, this.showTable = false});

  static const envelopeKey = 'appflowy_map';
  static const currentVersion = 1;

  final MapSpec spec;

  /// Whether the page was last left showing the rows instead of the map.
  final bool showTable;

  MapMetadata copyWith({MapSpec? spec, bool? showTable}) => MapMetadata(
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

  /// Removes the mark, turning a map back into a plain table.
  static String removeFromExtra(String extra) {
    final values = decodeViewExtra(extra)..remove(envelopeKey);
    return values.isEmpty ? '' : jsonEncode(values);
  }

  static MapMetadata? fromExtra(String extra) {
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
    return MapMetadata(
      spec: MapSpec.fromJson(
        spec is Map ? Map<String, dynamic>.from(spec) : const {},
      ),
      showTable: values['show_table'] == true,
    );
  }

  /// The `extra` payload of a brand new map.
  static String newExtra({MapSpec spec = const MapSpec()}) =>
      MapMetadata(spec: spec).mergeIntoExtra('');
}

extension MapViewExtension on ViewPB {
  MapMetadata? get mapView => MapMetadata.fromExtra(extra);

  /// A map is a table that has been asked to place itself.
  bool get isMap =>
      mapView != null &&
      const [ViewLayoutPB.Grid, ViewLayoutPB.Board, ViewLayoutPB.Calendar]
          .contains(layout);
}
