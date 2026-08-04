import 'dart:async';

import 'package:appflowy/workspace/application/collections/database/database_collection_state.dart';
import 'package:appflowy/workspace/application/collections/database/database_schema.dart';
import 'package:appflowy/workspace/application/collections/database/database_summary_cache.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// Holds a database collection: the tables in it, which one is open, and what
/// each of them contains.
class DatabaseCollectionController extends ChangeNotifier {
  DatabaseCollectionController({
    Map<String, dynamic>? initialState,
    this.onPersist,
    DatabaseSummaryCache? summaries,
    Duration persistDebounce = const Duration(milliseconds: 900),
  })  : _state = DatabaseCollectionState.fromJson(initialState ?? const {}),
        _summaries = summaries ?? DatabaseSummaryCache(),
        _persistDebounce = persistDebounce;

  final ValueChanged<Map<String, dynamic>>? onPersist;
  final DatabaseSummaryCache _summaries;
  final Duration _persistDebounce;

  DatabaseCollectionState _state;
  List<DatabaseTable> _tables = const [];
  List<DatabaseRelation> _relations = const [];
  Timer? _persistTimer;
  bool _reading = false;
  bool _disposed = false;

  DatabaseCollectionState get state => _state;
  List<DatabaseTable> get tables => _tables;
  List<DatabaseRelation> get relations => _relations;
  bool get isReading => _reading;
  bool get isEmpty => _tables.isEmpty;

  DatabaseTable? get activeTable {
    final id = _state.activeTableId;
    for (final table in _tables) {
      if (table.id == id) {
        return table;
      }
    }
    return _tables.isEmpty ? null : _tables.first;
  }

  DatabaseTableSummary? summaryFor(String viewId) =>
      _summaries.summaryFor(viewId);

  /// Every relation that leaves [viewId].
  List<DatabaseRelation> relationsFrom(String viewId) =>
      _relations.where((r) => r.fromViewId == viewId).toList();

  /// Every relation that lands on [viewId].
  List<DatabaseRelation> relationsTo(String viewId) =>
      _relations.where((r) => r.toViewId == viewId).toList();

  /// Adopts the collection's children.
  void setViews(List<ViewPB> views) {
    final next = databaseTablesFrom(views);
    if (listEquals(next, _tables)) {
      return;
    }
    final gone = _tables
        .where((table) => next.every((other) => other.id != table.id))
        .map((table) => table.id);
    for (final id in gone) {
      _summaries.invalidate(id);
    }
    _tables = next;
    _rebuildRelations();
    notifyListeners();
    unawaited(readSummaries());
  }

  void openTable(String viewId) {
    if (_state.activeTableId == viewId) {
      return;
    }
    _state = _state.copyWith(activeTableId: viewId);
    _schedulePersist();
    notifyListeners();
  }

  void setRailVisible(bool visible) {
    _state = _state.copyWith(showRail: visible);
    _schedulePersist();
    notifyListeners();
  }

  void setSchemaVisible(bool visible) {
    _state = _state.copyWith(showSchema: visible);
    _schedulePersist();
    notifyListeners();
  }

  /// Remembers how one table is charted.
  void setChartSpecJson(String viewId, Map<String, dynamic> spec) {
    _state = _state.copyWith(
      chartSpecs: {..._state.chartSpecs, viewId: spec},
    );
    _schedulePersist();
    notifyListeners();
  }

  /// Reads what every table holds, so the schema and the relations are real.
  Future<void> readSummaries({bool force = false}) async {
    if (_reading || _tables.isEmpty) {
      return;
    }
    if (force) {
      for (final table in _tables) {
        _summaries.invalidate(table.id);
      }
    }
    _reading = true;
    notifyListeners();
    try {
      await _summaries.readAll(
        _tables.map((table) => table.view).toList(),
        onProgress: () {
          if (!_disposed) {
            _rebuildRelations();
            notifyListeners();
          }
        },
      );
    } finally {
      _reading = false;
      if (!_disposed) {
        _rebuildRelations();
        notifyListeners();
      }
    }
  }

  /// Forgets one table's columns, for after a field has been added or changed.
  void refreshTable(String viewId) {
    _summaries.invalidate(viewId);
    unawaited(readSummaries());
  }

  void _rebuildRelations() {
    _relations = buildDatabaseRelations(
      _summaries.summariesFor(_tables.map((table) => table.id)),
    );
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, _persist);
  }

  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = null;
    onPersist?.call(_state.toJson());
  }

  /// Writes the state now, for a hand-off that cannot wait for the debounce.
  void flush() => _persist();

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    _persist();
    super.dispose();
  }
}
