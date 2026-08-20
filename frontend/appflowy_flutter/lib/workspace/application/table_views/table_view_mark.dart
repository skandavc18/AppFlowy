import 'dart:convert';

import 'package:appflowy/extensions/dart/extension_registries.dart';
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
  }) : _envelopeKey = null;

  /// A mark for a table view an extension supplied, which has no enum value.
  const TableViewMark.forKey(
    String envelopeKey, {
    this.settings = const {},
    this.showTable = false,
  })  : kind = null,
        _envelopeKey = envelopeKey;

  static const currentVersion = 1;

  final TableViewKind? kind;

  final String? _envelopeKey;

  /// Where this mark is stored in the view's `extra`, whichever kind it is.
  String get envelopeKey => _envelopeKey ?? kind!.envelopeKey;

  /// Whatever the view itself wants remembered.
  final Map<String, dynamic> settings;

  /// Whether the page was last left showing the rows instead of the view.
  final bool showTable;

  TableViewMark copyWith({
    Map<String, dynamic>? settings,
    bool? showTable,
  }) =>
      TableViewMark.forKey(
        envelopeKey,
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
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  /// Removes the mark, turning the view back into a plain table.
  static String removeFromExtra(String extra, TableViewKind kind) =>
      removeKeyFromExtra(extra, kind.envelopeKey);

  static String removeKeyFromExtra(String extra, String envelopeKey) {
    final values = decodeViewExtra(extra)..remove(envelopeKey);
    return values.isEmpty ? '' : jsonEncode(values);
  }

  static TableViewMark? fromExtra(String extra, TableViewKind kind) =>
      fromExtraKey(extra, kind.envelopeKey);

  static TableViewMark? fromExtraKey(String extra, String envelopeKey) {
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
    return TableViewMark.forKey(
      envelopeKey,
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

  /// The envelope a view is wearing, built in or from an extension.
  static String? envelopeKeyOf(String extra) {
    final builtIn = kindOf(extra);
    if (builtIn != null) {
      return builtIn.envelopeKey;
    }
    for (final key in ExtensionTableViewRegistry.envelopeKeys()) {
      if (fromExtraKey(extra, key) != null) {
        return key;
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

  static String newExtraForKey(
    String envelopeKey, {
    Map<String, dynamic> settings = const {},
  }) =>
      TableViewMark.forKey(envelopeKey, settings: settings).mergeIntoExtra('');
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

  /// The envelope this view wears, built in or supplied by an extension.
  String? get tableViewEnvelopeKey => _tableLayouts.contains(layout)
      ? TableViewMark.envelopeKeyOf(extra)
      : null;

  /// The extension table view this is, if an extension supplied it and that
  /// extension is still switched on.
  ExtensionTableView? get extensionTableView {
    final key = tableViewEnvelopeKey;
    return key == null ? null : ExtensionTableViewRegistry.byEnvelopeKey(key);
  }

  TableViewMark? tableViewMarkForKey(String envelopeKey) =>
      _tableLayouts.contains(layout)
          ? TableViewMark.fromExtraKey(extra, envelopeKey)
          : null;

  bool get isTimelineView => tableViewKind == TableViewKind.timeline;

  bool get isFeedView => tableViewKind == TableViewKind.feed;

  bool get isFormView => tableViewKind == TableViewKind.form;

  bool get isGalleryView => tableViewKind == TableViewKind.gallery;

  bool get isMailboxView => tableViewKind == TableViewKind.mailbox;
}
