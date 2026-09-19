import 'dart:async';

import 'package:appflowy/core/notification/grid_notification.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:flutter/foundation.dart';

/// How long a table is left alone after a change before it is read again.
const _settle = Duration(milliseconds: 400);

/// Reads a table for charting.
///
/// Read the requested view's loaded rows, not the CSV export (which always
/// exports the database's first view). Field ids align the schema with the
/// cells even when the field response arrives in a different order.
///
/// There is no backend ownership token to release. The source owns only its
/// Dart subscription/timer, never closes a shared editor, and re-ensures it on
/// each refresh. An external CloseView can still silence row-order events until
/// the next refresh; preventing that requires a shared backend lease contract.
class ChartSource extends ChangeNotifier {
  ChartSource({
    required this.viewId,
    this.settle = _settle,
    Future<ChartTable> Function(String viewId)? loadTable,
    Future<void> Function(String viewId)? initializeView,
    Stream<SubscribeObject>? notifications,
  })  : _loadTable = loadTable ?? readChartTable,
        _initializeView =
            initializeView ?? (loadTable == null ? _initializeChartView : null),
        _notifications = notifications,
        _watchDatabase = loadTable == null || notifications != null;

  final String viewId;
  final Duration settle;
  final Future<ChartTable> Function(String viewId) _loadTable;

  // An injected table loader owns its initialization unless supplied separately.
  final Future<void> Function(String viewId)? _initializeView;
  final Stream<SubscribeObject>? _notifications;
  final bool _watchDatabase;

  ChartTable _table = ChartTable.empty;
  Timer? _timer;
  StreamSubscription<SubscribeObject>? _subscription;
  Future<void>? _inFlight;
  String? _error;
  bool _loading = false;
  bool _reloadRequested = false;
  bool _disposed = false;

  ChartTable get table => _table;
  String? get error => _error;
  bool get isLoading => _loading;

  /// Reads the table now. A refresh during a read queues one more read instead
  /// of being silently lost; all callers wait for that fresh result.
  Future<void> load() {
    if (_disposed || viewId.isEmpty) {
      return Future.value();
    }
    _timer?.cancel();
    _timer = null;
    final pending = _inFlight;
    if (pending != null) {
      _reloadRequested = true;
      return pending;
    }
    if (_watchDatabase && _subscription == null) {
      final parser = DatabaseNotificationParser(
        id: viewId,
        callback: (type, _) {
          if (type == DatabaseNotification.DidUpdateRow ||
              type == DatabaseNotification.DidUpdateFields ||
              type == DatabaseNotification.DidUpdateFilter ||
              type == DatabaseNotification.DidUpdateSort ||
              type == DatabaseNotification.DidUpdateViewRowsVisibility ||
              type == DatabaseNotification.DidReorderRows ||
              type == DatabaseNotification.DidReorderSingleRow) {
            invalidate();
          }
        },
      );
      _subscription =
          (_notifications ?? RustStreamReceiver.shared.observable.stream)
              .listen(parser.parse);
    }
    final completion = Completer<void>();
    _inFlight = completion.future;
    _loading = true;
    notifyListeners();
    unawaited(_read(completion));
    return completion.future;
  }

  Future<void> _read(Completer<void> completion) async {
    try {
      do {
        _reloadRequested = false;
        try {
          if (_disposed) {
            return;
          }
          // Re-ensure on every refresh: another database host may have closed
          // the shared editor since our last read. Subscribe before opening.
          final initialize = _initializeView;
          if (initialize != null) {
            await initialize(viewId);
          }
          if (_disposed) {
            return;
          }
          final table = await _loadTable(viewId);
          if (_disposed) {
            return;
          }
          _table = table;
          _error = null;
        } on Object catch (error) {
          if (_disposed) {
            return;
          }
          _error = '$error';
          Log.warn('Could not read the table $viewId for a chart');
        }
      } while (_reloadRequested && !_disposed);
    } finally {
      _loading = false;
      _inFlight = null;
      if (!_disposed) {
        notifyListeners();
      }
      completion.complete();
    }
  }

  /// Reads the table again shortly, so a burst of edits costs one read.
  void invalidate() {
    if (_disposed || viewId.isEmpty) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(settle, () {
      _timer = null;
      unawaited(load());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _reloadRequested = false;
    unawaited(_subscription?.cancel());
    _subscription = null;
    // Initializing a shared editor does not grant an owned lease.
    // CloseView would evict the same editor a grid/tab may still be using.
    super.dispose();
  }
}

Future<void> _initializeChartView(String viewId) async {
  // GetAllRows always calls get_or_init_view_editor for this exact view.
  // GetDatabase can instead join a different view's in-flight open, and its
  // large-table sort notifications can trigger an endless chart refresh loop.
  // This bulk metadata read uses the non-notifying filter/sort path instead.
  await _readViewRows(viewId);
}

/// Bulk reads only, with injectable reads for offline lifecycle regressions.
/// The text read loads the cells before view filters are evaluated. GetAllRows
/// supplies membership and order for this exact view, preventing get_loaded_rows'
/// empty-view fallback from including other rows. These reads are not a
/// transaction, and initialization's earlier membership is not a filter result
/// we can reuse before the text read has loaded the cells.
@visibleForTesting
Future<ChartTable> readChartTable(
  String viewId, {
  Future<RepeatedRowTextPB> Function(String viewId)? readRows,
  Future<List<RowMetaPB>> Function(String viewId)? readViewRows,
  Future<List<FieldPB>> Function(String viewId, List<String> fieldIds)?
      readFields,
}) async {
  final rows = await (readRows ?? _readRows)(viewId);
  final viewRows = await (readViewRows ?? _readViewRows)(viewId);
  final fields = await (readFields ?? _readFields)(
    viewId,
    List<String>.of(rows.fieldIds),
  );
  return chartTableFromRowText(
    rows,
    fields,
    rowIds: viewRows.map((row) => row.id),
  );
}

Future<RepeatedRowTextPB> _readRows(String viewId) async =>
    (await DatabaseEventGetRowsAsText(
      DatabaseViewIdPB(value: viewId),
    ).send())
        .fold((rows) => rows, (error) => throw StateError(error.msg));

Future<List<RowMetaPB>> _readViewRows(String viewId) async =>
    (await DatabaseEventGetAllRows(DatabaseViewIdPB(value: viewId)).send())
        .fold(
      (rows) => rows.items,
      (error) => throw StateError(error.msg),
    );

Future<List<FieldPB>> _readFields(String viewId, List<String> fieldIds) async =>
    (await DatabaseEventGetFields(
      GetFieldPayloadPB(
        viewId: viewId,
        fieldIds: RepeatedFieldIdPB(
          items: fieldIds.map((id) => FieldIdPB(fieldId: id)),
        ),
      ),
    ).send())
        .fold((fields) => fields.items, (error) => throw StateError(error.msg));

/// Keep the row payload's field order, not the order of a separate schema
/// request. Real blank database rows still count, unlike blank CSV lines.
ChartTable chartTableFromRowText(
  RepeatedRowTextPB rows,
  List<FieldPB> fields, {
  Iterable<String>? rowIds,
}) {
  final names = {for (final field in fields) field.id: field.name};
  final rowById = {for (final row in rows.rows) row.rowId: row};
  final selectedRows = rowIds == null
      ? rows.rows
      : [
          for (final id in rowIds)
            if (rowById.containsKey(id)) rowById[id]!,
        ];
  return ChartTable.fromRows(
    [
      [for (final id in rows.fieldIds) names[id] ?? id],
      for (final row in selectedRows) List<String>.of(row.cells),
    ],
    columnIds: List<String>.of(rows.fieldIds),
    keepEmptyRows: true,
  );
}
