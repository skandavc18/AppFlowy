import 'dart:async';

import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';

/// How long a table is left alone after a change before it is read again.
const _settle = Duration(milliseconds: 350);

/// Which columns a view wants read, and how.
///
/// Every view names its columns by field id rather than by heading, so
/// renaming a column never loses the arrangement.
@immutable
class TableReadSpec {
  const TableReadSpec({
    this.titleColumn = '',
    this.coverColumn = '',
    this.propertyColumns = const [],
    this.hiddenColumns = const [],
    this.startColumn = '',
    this.endColumn = '',
    this.showEmptyProperties = false,
  });

  final String titleColumn;
  final String coverColumn;
  final List<String> propertyColumns;
  final List<String> hiddenColumns;

  /// When a row begins and ends, for the views that place it in time. Empty
  /// means the source works it out from the table's own date columns.
  final String startColumn;
  final String endColumn;

  final bool showEmptyProperties;

  @override
  bool operator ==(Object other) =>
      other is TableReadSpec &&
      other.titleColumn == titleColumn &&
      other.coverColumn == coverColumn &&
      listEquals(other.propertyColumns, propertyColumns) &&
      listEquals(other.hiddenColumns, hiddenColumns) &&
      other.startColumn == startColumn &&
      other.endColumn == endColumn &&
      other.showEmptyProperties == showEmptyProperties;

  @override
  int get hashCode => Object.hash(
        titleColumn,
        coverColumn,
        Object.hashAll(propertyColumns),
        Object.hashAll(hiddenColumns),
        startColumn,
        endColumn,
        showEmptyProperties,
      );
}

/// Turns a table into rows any view can draw.
///
/// Rows come back as the text the table shows, in one call for the whole view,
/// so a table of thousands of rows costs one round trip rather than one per
/// cell. What each column should look like is worked out once here rather than
/// in the widgets, so a view can be tested without being drawn.
class TableRowSource extends ChangeNotifier {
  TableRowSource({required this.viewId, this.settle = _settle}) {
    LocationFieldRegistry.instance.revision.addListener(_onMarkedChanged);
    PropertyStyleRegistry.instance
      ..listenable(viewId)
      ..revision.addListener(_onMarkedChanged);
  }

  final String viewId;
  final Duration settle;

  TableReadSpec _spec = const TableReadSpec();
  List<FieldPB> _fields = const [];
  List<TableRowCard> _cards = const [];
  Timer? _timer;
  bool _loading = false;
  bool _disposed = false;
  String? _error;
  int _generation = 0;

  /// The columns the author marked as holding a place.
  Set<String> _marked = const {};

  TableReadSpec get spec => _spec;
  List<FieldPB> get fields => _fields;
  List<TableRowCard> get cards => _cards;
  bool get isLoading => _loading;
  String? get error => _error;

  /// The columns the author marked as holding a place.
  Set<String> get locationColumns => _marked;

  /// The column each row is titled by.
  String get titleColumn => _spec.titleColumn.isNotEmpty
      ? _spec.titleColumn
      : _fields.firstWhereOrNull((field) => field.isPrimary)?.id ?? '';

  /// The column that says when a row begins, worked out if not chosen.
  String get startColumn => _spec.startColumn.isNotEmpty
      ? _spec.startColumn
      : guessStartColumn(_fields) ?? '';

  /// The column that says when a row ends, worked out if not chosen.
  String get endColumn => _spec.endColumn.isNotEmpty
      ? _spec.endColumn
      : guessEndColumn(_fields, notThis: startColumn) ?? '';

  void _onMarkedChanged() {
    if (!_disposed) {
      invalidate();
    }
  }

  void updateSpec(TableReadSpec spec) {
    if (spec == _spec) {
      return;
    }
    _spec = spec;
    _rebuild();
  }

  Future<void> load() async {
    if (viewId.isEmpty || _loading) {
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    final generation = ++_generation;

    try {
      _fields = await FieldBackendService.getFields(viewId: viewId)
          .fold((fields) => fields, (_) => const <FieldPB>[]);
      _marked = (await LocationBackendService.locationFieldIds(viewId: viewId))
          .toSet();

      final rows = await DatabaseEventGetRowsAsText(
        DatabaseViewIdPB()..value = viewId,
      ).send().fold<RepeatedRowTextPB?>((rows) => rows, (failure) {
        _error = failure.msg;
        Log.warn('Could not read the table $viewId: $failure');
        return null;
      });
      if (_disposed || generation != _generation || rows == null) {
        return;
      }

      final metas = await DatabaseEventGetAllRows(
        DatabaseViewIdPB()..value = viewId,
      ).send().fold<List<RowMetaPB>>((all) => all.items, (failure) {
        Log.warn('Could not read the rows of $viewId: $failure');
        return const [];
      });
      if (_disposed || generation != _generation) {
        return;
      }

      _read(rows, metas);
    } on Object catch (error, stack) {
      // A read that fails silently is indistinguishable from an empty table.
      _error = '$error';
      Log.error('[TableView] could not read $viewId', error, stack);
    } finally {
      _loading = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// Reads the table again shortly, so a burst of edits costs one read.
  void invalidate() {
    _timer?.cancel();
    _timer = Timer(settle, () => unawaited(load()));
  }

  RepeatedRowTextPB? _rows;
  Map<String, RowMetaPB> _metas = const {};

  void _read(RepeatedRowTextPB rows, List<RowMetaPB> metas) {
    _rows = rows;
    _metas = {for (final meta in metas) meta.id: meta};
    _rebuild();
  }

  /// Feeds the source a table without going to the backend.
  @visibleForTesting
  void readForTest(
    RepeatedRowTextPB rows, {
    List<FieldPB> fields = const [],
    Set<String> marked = const {},
    List<RowMetaPB> metas = const [],
  }) {
    _fields = fields;
    _marked = marked;
    _read(rows, metas);
  }

  void _rebuild() {
    final rows = _rows;
    if (rows == null) {
      return;
    }
    final index = {
      for (var i = 0; i < rows.fieldIds.length; i++) rows.fieldIds[i]: i,
    };
    final byId = {for (final field in _fields) field.id: field};

    String cell(RowTextPB row, String fieldId) {
      final at = index[fieldId];
      if (at == null || at >= row.cells.length) {
        return '';
      }
      return row.cells[at];
    }

    final titleId = _spec.titleColumn.isNotEmpty
        ? _spec.titleColumn
        : _fields.firstWhereOrNull((field) => field.isPrimary)?.id ??
            (rows.fieldIds.isEmpty ? '' : rows.fieldIds.first);

    final shown = _shownColumns(rows.fieldIds, titleId);
    final facts = _factsFor(rows, index, shown, byId);
    final startId = startColumn;
    final endId = endColumn;

    final cards = <TableRowCard>[];
    for (final row in rows.rows) {
      final meta = _metas[row.rowId];
      final properties = <TableProperty>[];
      for (final id in shown) {
        final field = byId[id];
        if (field == null) {
          continue;
        }
        final raw = cell(row, id);
        if (raw.trim().isEmpty && !_spec.showEmptyProperties) {
          continue;
        }
        final columnFacts = facts[id] ?? const TableColumnFacts();
        final style = PropertyStyleRegistry.instance.cellStyleFor(
          viewId,
          id,
          row.rowId,
        );
        final styleKind = style?.kind.name;
        final value = tableValueForStyle(raw, styleKind);
        final kind = classifyTableProperty(
          field: field,
          value: value,
          isLocation: _marked.contains(id),
          facts: columnFacts,
          styleKind: styleKind,
        );
        properties.add(
          TableProperty(
            fieldId: id,
            name: field.name,
            value: value,
            kind: kind,
            fraction: kind == TablePropertyKind.progress
                ? tableFractionOf(
                    field: field,
                    value: value,
                    facts: columnFacts,
                    maximum: styleKind == 'progress' ? style?.maximum : null,
                  )
                : null,
            rating:
                kind == TablePropertyKind.rating ? tableRatingOf(value) : null,
          ),
        );
      }

      final starts =
          startId.isEmpty ? null : parseTableDate(cell(row, startId));
      final ends = endId.isEmpty ? null : parseTableDate(cell(row, endId));

      cards.add(
        TableRowCard(
          rowId: row.rowId,
          title: titleId.isEmpty ? '' : cell(row, titleId),
          subtitle: _subtitleOf(properties),
          icon: meta?.hasIcon() == true && meta!.icon.isNotEmpty
              ? meta.icon
              : null,
          coverUrl: _coverOf(row, meta, cell),
          cover: _coverOfRow(row, meta, cell),
          documentId: meta?.documentId ?? '',
          accent: _accentOf(properties),
          properties: properties,
          lastModified: row.modifiedAt.toInt() == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  row.modifiedAt.toInt() * 1000,
                ),
          startsAt: starts,
          endsAt: ends != null && starts != null && ends.isAfter(starts)
              ? ends
              : null,
        ),
      );
    }

    _cards = List.unmodifiable(cards);
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The columns a view should read, in order.
  List<String> _shownColumns(List<String> fieldIds, String titleId) {
    final hidden = _spec.hiddenColumns.toSet();
    final chosen = _spec.propertyColumns.isNotEmpty
        ? _spec.propertyColumns
        : fieldIds.where((id) => id != titleId).toList();
    return chosen
        .where((id) => id != titleId && !hidden.contains(id))
        .toList(growable: false);
  }

  /// The spread of each numeric column, so a bar knows how full to be.
  Map<String, TableColumnFacts> _factsFor(
    RepeatedRowTextPB rows,
    Map<String, int> index,
    List<String> shown,
    Map<String, FieldPB> byId,
  ) {
    final facts = <String, TableColumnFacts>{};
    for (final id in shown) {
      if (byId[id]?.fieldType != FieldType.Number) {
        continue;
      }
      final at = index[id];
      if (at == null) {
        continue;
      }
      double? lowest;
      double? highest;
      for (final row in rows.rows) {
        if (at >= row.cells.length) {
          continue;
        }
        final raw = row.cells[at].trim().replaceAll(',', '');
        final number = double.tryParse(
          raw.endsWith('%') ? raw.substring(0, raw.length - 1) : raw,
        );
        if (number == null) {
          continue;
        }
        lowest = lowest == null ? number : (number < lowest ? number : lowest);
        highest =
            highest == null ? number : (number > highest ? number : highest);
      }
      facts[id] = TableColumnFacts(lowest: lowest, highest: highest);
    }
    return facts;
  }

  /// The first badge or person on the row stands in as its subtitle.
  String _subtitleOf(List<TableProperty> properties) {
    for (final property in properties) {
      if (property.isEmpty) {
        continue;
      }
      if (property.kind == TablePropertyKind.badge ||
          property.kind == TablePropertyKind.person) {
        return property.value;
      }
    }
    return '';
  }

  String _accentOf(List<TableProperty> properties) {
    for (final property in properties) {
      if (!property.isEmpty && property.kind == TablePropertyKind.badge) {
        return property.value;
      }
    }
    return '';
  }

  String? _coverOf(
    RowTextPB row,
    RowMetaPB? meta,
    String Function(RowTextPB, String) cell,
  ) {
    final chosen = _spec.coverColumn;
    if (chosen.isNotEmpty) {
      final picture =
          tablePartsOf(cell(row, chosen)).firstWhereOrNull(looksLikeTableImage);
      if (picture != null) {
        return picture;
      }
    }
    if (meta == null || !meta.hasCover()) {
      return null;
    }
    final data = meta.cover.data;
    if (data.isEmpty) {
      return null;
    }
    // Only a real picture is worth putting on a card; a colour is not.
    final looksLikeFile =
        data.startsWith('http') || data.contains('/') || data.contains(r'\');
    return looksLikeFile ? data : null;
  }

  /// The cover the row's own page would show.
  ///
  /// A picture named by a column wins, then whatever the row wears, and
  /// failing both the gradient the row page falls back to — so a card and the
  /// page behind it never disagree.
  TableCover _coverOfRow(
    RowTextPB row,
    RowMetaPB? meta,
    String Function(RowTextPB, String) cell,
  ) {
    final chosen = _spec.coverColumn;
    if (chosen.isNotEmpty) {
      final picture =
          tablePartsOf(cell(row, chosen)).firstWhereOrNull(looksLikeTableImage);
      if (picture != null) {
        return TableCover(kind: TableCoverKind.picture, value: picture);
      }
    }
    final data = meta?.cover.data ?? '';
    if (data.isNotEmpty) {
      return TableCover(
        kind: switch (meta!.cover.coverType) {
          CoverTypePB.FileCover => TableCoverKind.picture,
          CoverTypePB.AssetCover => TableCoverKind.asset,
          CoverTypePB.ColorCover => TableCoverKind.colour,
          _ => TableCoverKind.gradient,
        },
        value: data,
      );
    }
    return TableCover(
      kind: TableCoverKind.gradient,
      value: FlowyGradientColor.forSeed(row.rowId).id,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    LocationFieldRegistry.instance.revision.removeListener(_onMarkedChanged);
    PropertyStyleRegistry.instance.revision.removeListener(_onMarkedChanged);
    _timer?.cancel();
    super.dispose();
  }
}

extension TableFirstWhereOrNull<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}
