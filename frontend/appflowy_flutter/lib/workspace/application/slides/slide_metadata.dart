import 'dart:convert';

import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// The mark that says a table should be read one row at a time.
///
/// Like a chart or a map, a slide deck is a reading of a table rather than a
/// kind of view the backend knows about: the rows are untouched and one click
/// away, and the same table can still be seen as a grid, a board or a
/// calendar.
@immutable
class SlideMetadata {
  const SlideMetadata({required this.spec, this.showTable = false});

  static const envelopeKey = 'appflowy_slide';
  static const currentVersion = 1;

  final SlideSpec spec;

  /// Whether the page was last left showing the rows instead of the slides.
  final bool showTable;

  SlideMetadata copyWith({SlideSpec? spec, bool? showTable}) => SlideMetadata(
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

  /// Removes the mark, turning a deck back into a plain table.
  static String removeFromExtra(String extra) {
    final values = decodeViewExtra(extra)..remove(envelopeKey);
    return values.isEmpty ? '' : jsonEncode(values);
  }

  static SlideMetadata? fromExtra(String extra) {
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
    return SlideMetadata(
      spec: SlideSpec.fromJson(
        spec is Map ? Map<String, dynamic>.from(spec) : const {},
      ),
      showTable: values['show_table'] == true,
    );
  }

  /// The `extra` payload of a brand new deck.
  static String newExtra({SlideSpec spec = const SlideSpec()}) =>
      SlideMetadata(spec: spec).mergeIntoExtra('');
}

extension SlideViewExtension on ViewPB {
  SlideMetadata? get slideView => SlideMetadata.fromExtra(extra);

  /// A deck is a table that has been asked to show one row at a time.
  bool get isSlideDeck =>
      slideView != null &&
      const [ViewLayoutPB.Grid, ViewLayoutPB.Board, ViewLayoutPB.Calendar]
          .contains(layout);
}
