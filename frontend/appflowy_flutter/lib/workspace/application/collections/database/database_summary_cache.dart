import 'dart:async';

import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/field/type_option/type_option_data_parser.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/workspace/application/collections/database/database_schema.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// How many tables are read at once when a collection catches up.
const _summaryBatchSize = 4;

/// Reads what each table holds without drawing it.
///
/// A summary opens the same [DatabaseController] a grid uses, takes its fields
/// and its row count, and closes it again — so the schema panel and the
/// relation map are built from the real database rather than a second model.
class DatabaseSummaryCache {
  final Map<String, DatabaseTableSummary> _summaries = {};
  final Map<String, Future<DatabaseTableSummary?>> _inFlight = {};

  DatabaseTableSummary? summaryFor(String viewId) => _summaries[viewId];

  List<DatabaseTableSummary> summariesFor(Iterable<String> viewIds) => [
        for (final id in viewIds)
          if (_summaries[id] != null) _summaries[id]!,
      ];

  /// Reads [views] a few at a time — opening a whole collection at once holds
  /// one backend subscription per table.
  Future<void> readAll(
    List<ViewPB> views, {
    void Function()? onProgress,
  }) async {
    final pending = views.where((view) => !_summaries.containsKey(view.id));
    final queue = pending.toList();
    for (var index = 0; index < queue.length; index += _summaryBatchSize) {
      final batch = queue.skip(index).take(_summaryBatchSize);
      await Future.wait(batch.map(read));
      onProgress?.call();
    }
  }

  Future<DatabaseTableSummary?> read(ViewPB view) {
    final cached = _summaries[view.id];
    if (cached != null) {
      return Future.value(cached);
    }
    return _inFlight[view.id] ??= _read(view).whenComplete(
      () => _inFlight.removeWhere((key, _) => key == view.id),
    );
  }

  /// Forgets a table so the next read sees the columns as they are now.
  void invalidate(String viewId) => _summaries.remove(viewId);

  void clear() => _summaries.clear();

  Future<DatabaseTableSummary?> _read(ViewPB view) async {
    final controller = DatabaseController(view: view);
    try {
      final opened = await controller.open();
      final failed = opened.fold((_) => false, (error) {
        Log.warn('Could not read the table ${view.name}: $error');
        return true;
      });
      if (failed) {
        return null;
      }
      final databaseId = await DatabaseViewBackendService(viewId: view.id)
          .getDatabaseId()
          .then((result) => result.fold((id) => id, (_) => ''));
      final summary = DatabaseTableSummary(
        viewId: view.id,
        databaseId: databaseId,
        fields: [
          for (final field in controller.fieldController.fieldInfos)
            DatabaseFieldSummary(
              id: field.id,
              name: field.name,
              type: field.fieldType,
              isPrimary: field.isPrimary,
              relatedDatabaseId: _relatedDatabaseId(field.field),
            ),
        ],
        rowCount: controller.rowCache.rowInfos.length,
      );
      _summaries[view.id] = summary;
      return summary;
    } on Object catch (error) {
      Log.warn('Could not read the table ${view.name}: $error');
      return null;
    } finally {
      unawaited(controller.dispose());
    }
  }

  static String? _relatedDatabaseId(FieldPB field) {
    if (field.fieldType != FieldType.Relation) {
      return null;
    }
    try {
      final option =
          RelationTypeOptionDataParser().fromBuffer(field.typeOptionData);
      return option.databaseId.isEmpty ? null : option.databaseId;
    } on Object {
      // A column whose options cannot be read is reported as unlinked rather
      // than failing the whole summary.
      return null;
    }
  }
}
