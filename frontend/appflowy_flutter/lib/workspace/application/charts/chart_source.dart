import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_codec.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter/foundation.dart';

/// How long a table is left alone after a change before it is read again.
const _settle = Duration(milliseconds: 400);

/// Reads a table for charting.
///
/// The whole table comes back in one call as the database's own export, so a
/// chart never walks the rows a cell at a time — and the values are exactly
/// what the table displays, which is what a person is charting.
class ChartSource extends ChangeNotifier {
  ChartSource({required this.viewId, this.settle = _settle});

  final String viewId;
  final Duration settle;

  ChartTable _table = ChartTable.empty;
  Timer? _timer;
  String? _error;
  bool _loading = false;
  bool _disposed = false;

  ChartTable get table => _table;
  String? get error => _error;
  bool get isLoading => _loading;

  /// Reads the table now.
  Future<void> load() async {
    if (_loading || viewId.isEmpty) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final exported = await DatabaseEventExportCSV(
        DatabaseViewIdPB()..value = viewId,
      ).send();
      if (_disposed) {
        return;
      }
      exported.fold(
        (data) {
          _table = ChartTable.fromRows(parseDelimitedText(data.data));
          _error = null;
        },
        (failure) {
          _error = failure.msg;
          Log.warn('Could not read the table $viewId for a chart: $failure');
        },
      );
    } on Object catch (error) {
      _error = '$error';
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

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
