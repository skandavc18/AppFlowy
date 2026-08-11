import 'dart:async';

import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';

/// How long a table is left alone after a change before it is read again.
const _settle = Duration(milliseconds: 350);

/// Turns a table into slides.
///
/// Rows come back as the text the table shows, in one call for the whole view,
/// so a deck of thousands of rows costs one round trip rather than one per
/// cell. What each column should look like is worked out once here rather than
/// in the widgets, so the deck can be tested without being drawn.
class SlideSource extends ChangeNotifier {
  SlideSource({required this.viewId, this.settle = _settle}) {
    LocationFieldRegistry.instance.revision.addListener(_onMarkedChanged);
    PropertyStyleRegistry.instance
      ..listenable(viewId)
      ..revision.addListener(_onMarkedChanged);
  }

  final String viewId;
  final Duration settle;

  SlideSpec _spec = const SlideSpec();
  List<FieldPB> _fields = const [];
  List<SlideCardData> _cards = const [];
  Timer? _timer;
  bool _loading = false;
  bool _disposed = false;
  String? _error;
  int _generation = 0;

  /// The columns the author marked as holding a place.
  Set<String> _marked = const {};

  SlideSpec get spec => _spec;
  List<FieldPB> get fields => _fields;
  List<SlideCardData> get cards => _cards;
  bool get isLoading => _loading;
  String? get error => _error;

  /// The columns a slide could show, in the table's own order.
  List<FieldPB> get columns => _fields;

  void _onMarkedChanged() {
    if (!_disposed) {
      invalidate();
    }
  }

  void updateSpec(SlideSpec spec) {
    if (spec == _spec) {
      return;
    }
    final relayout = spec.titleColumn != _spec.titleColumn ||
        spec.coverColumn != _spec.coverColumn ||
        !listEquals(spec.propertyColumns, _spec.propertyColumns) ||
        !listEquals(spec.hiddenColumns, _spec.hiddenColumns) ||
        spec.showEmptyProperties != _spec.showEmptyProperties;
    _spec = spec;
    if (relayout) {
      _rebuild();
    }
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
        Log.warn('Could not read the table $viewId for a deck: $failure');
        return null;
      });
      if (_disposed || generation != _generation || rows == null) {
        return;
      }

      final metas = await DatabaseEventGetAllRows(
        DatabaseViewIdPB()..value = viewId,
      ).send().fold<List<RowMetaPB>>((all) => all.items, (failure) {
        Log.warn('Could not read the rows of $viewId for a deck: $failure');
        return const [];
      });
      if (_disposed || generation != _generation) {
        return;
      }

      _read(rows, metas);
    } on Object catch (error, stack) {
      // A read that fails silently is indistinguishable from an empty table.
      _error = '$error';
      Log.error('[Slides] could not read $viewId', error, stack);
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

    final cards = <SlideCardData>[];
    for (final row in rows.rows) {
      final meta = _metas[row.rowId];
      final properties = <SlideProperty>[];
      for (final id in shown) {
        final field = byId[id];
        if (field == null) {
          continue;
        }
        final raw = cell(row, id);
        if (raw.trim().isEmpty && !_spec.showEmptyProperties) {
          continue;
        }
        final style = PropertyStyleRegistry.instance.cellStyleFor(
          viewId,
          id,
          row.rowId,
        );
        final styleKind = style?.kind.name;
        final value = slideValueForStyle(raw, styleKind);
        final kind = classifySlideProperty(
          field: field,
          value: value,
          isLocation: _marked.contains(id),
          facts: facts[id] ?? const SlideColumnFacts(),
          styleKind: styleKind,
        );
        properties.add(
          SlideProperty(
            fieldId: id,
            name: field.name,
            value: value,
            kind: kind,
            fraction: kind == SlidePropertyKind.progress
                ? slideFractionOf(
                    field: field,
                    value: value,
                    facts: facts[id] ?? const SlideColumnFacts(),
                    maximum: styleKind == 'progress' ? style?.maximum : null,
                  )
                : null,
          ),
        );
      }

      cards.add(
        SlideCardData(
          rowId: row.rowId,
          title: titleId.isEmpty ? '' : cell(row, titleId),
          subtitle: _subtitleOf(properties),
          icon: meta?.hasIcon() == true && meta!.icon.isNotEmpty
              ? meta.icon
              : null,
          coverUrl: _coverOf(row, meta, cell),
          documentId: meta?.documentId ?? '',
          accent: _accentOf(properties),
          properties: properties,
          lastModified: row.modifiedAt.toInt() == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  row.modifiedAt.toInt() * 1000,
                ),
        ),
      );
    }

    _cards = List.unmodifiable(cards);
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The columns a slide should read, in order.
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
  Map<String, SlideColumnFacts> _factsFor(
    RepeatedRowTextPB rows,
    Map<String, int> index,
    List<String> shown,
    Map<String, FieldPB> byId,
  ) {
    final facts = <String, SlideColumnFacts>{};
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
      facts[id] = SlideColumnFacts(lowest: lowest, highest: highest);
    }
    return facts;
  }

  /// The first badge or person on the slide stands in as its subtitle.
  String _subtitleOf(List<SlideProperty> properties) {
    for (final property in properties) {
      if (property.isEmpty) {
        continue;
      }
      if (property.kind == SlidePropertyKind.badge ||
          property.kind == SlidePropertyKind.person) {
        return property.value;
      }
    }
    return '';
  }

  String _accentOf(List<SlideProperty> properties) {
    for (final property in properties) {
      if (!property.isEmpty && property.kind == SlidePropertyKind.badge) {
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
      final value = cell(row, chosen);
      final picture = slidePartsOf(value).firstWhereOrNull(looksLikeSlideImage);
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
    // Only a real picture is worth putting on a slide; a colour is not.
    final looksLikeFile =
        data.startsWith('http') || data.contains('/') || data.contains(r'\');
    return looksLikeFile ? data : null;
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

extension _FirstWhereOrNull<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}
