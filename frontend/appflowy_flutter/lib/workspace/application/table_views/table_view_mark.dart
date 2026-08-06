import 'dart:convert';

import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

/// The ways a table can be read that the backend knows nothing about.
///
/// A chart, a map and a slide deck each wrote their own envelope; three more
/// copies of the same twenty lines would be three more places for it to drift.
/// These share one.
enum TableViewKind {
  timeline('appflowy_timeline'),
  feed('appflowy_feed'),
  form('appflowy_form'),
  gallery('appflowy_gallery'),
  mailbox('appflowy_mailbox');

  const TableViewKind(this.envelopeKey);

  final String envelopeKey;
}

/// The mark each of these views is drawn with, wherever a view is named.
IconData tableViewIcon(TableViewKind kind) => switch (kind) {
      TableViewKind.timeline => Icons.timeline_rounded,
      TableViewKind.feed => Icons.article_rounded,
      TableViewKind.form => Icons.assignment_rounded,
      TableViewKind.gallery => Icons.grid_view_rounded,
      TableViewKind.mailbox => Icons.mark_email_unread_rounded,
    };

/// The mark that says a table should open as something other than a grid.
///
/// The rows are untouched and one click away, and the same table can still be
/// seen as a grid, a board or a calendar.
@immutable
class TableViewMark {
  const TableViewMark({
    required this.kind,
    this.settings = const {},
    this.showTable = false,
  });

  static const currentVersion = 1;

  final TableViewKind kind;

  /// Whatever the view itself wants remembered.
  final Map<String, dynamic> settings;

  /// Whether the page was last left showing the rows instead of the view.
  final bool showTable;

  TableViewMark copyWith({
    Map<String, dynamic>? settings,
    bool? showTable,
  }) =>
      TableViewMark(
        kind: kind,
        settings: settings ?? this.settings,
        showTable: showTable ?? this.showTable,
      );

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'spec': settings,
        if (showTable) 'show_table': true,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[kind.envelopeKey] = toJson();
    return jsonEncode(values);
  }

  /// Removes the mark, turning the view back into a plain table.
  static String removeFromExtra(String extra, TableViewKind kind) {
    final values = decodeViewExtra(extra)..remove(kind.envelopeKey);
    return values.isEmpty ? '' : jsonEncode(values);
  }

  static TableViewMark? fromExtra(String extra, TableViewKind kind) {
    final envelope = decodeViewExtra(extra)[kind.envelopeKey];
    if (envelope is! Map) {
      return null;
    }
    final values = Map<String, dynamic>.from(envelope);
    final version = values['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      return null;
    }
    final spec = values['spec'];
    return TableViewMark(
      kind: kind,
      settings: spec is Map ? Map<String, dynamic>.from(spec) : const {},
      showTable: values['show_table'] == true,
    );
  }

  /// Which of these marks a view is wearing, if any.
  static TableViewKind? kindOf(String extra) {
    for (final kind in TableViewKind.values) {
      if (fromExtra(extra, kind) != null) {
        return kind;
      }
    }
    return null;
  }

  /// The `extra` payload of a brand new view of this kind.
  static String newExtra(
    TableViewKind kind, {
    Map<String, dynamic> settings = const {},
  }) =>
      TableViewMark(kind: kind, settings: settings).mergeIntoExtra('');
}

/// The layouts a mark is allowed to sit on. A document is never a table.
const _tableLayouts = [
  ViewLayoutPB.Grid,
  ViewLayoutPB.Board,
  ViewLayoutPB.Calendar,
];

extension TableViewMarkExtension on ViewPB {
  /// Which of the shared table views this is, if it is one.
  TableViewKind? get tableViewKind {
    if (!_tableLayouts.contains(layout)) {
      return null;
    }
    return TableViewMark.kindOf(extra);
  }

  TableViewMark? tableViewMark(TableViewKind kind) =>
      _tableLayouts.contains(layout)
          ? TableViewMark.fromExtra(extra, kind)
          : null;

  bool get isTimelineView => tableViewKind == TableViewKind.timeline;

  bool get isFeedView => tableViewKind == TableViewKind.feed;

  bool get isFormView => tableViewKind == TableViewKind.form;

  bool get isGalleryView => tableViewKind == TableViewKind.gallery;

  bool get isMailboxView => tableViewKind == TableViewKind.mailbox;
}
