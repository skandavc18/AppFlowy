import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// Talks to the backend about rollup columns.
///
/// A rollup is a text column that carries settings saying which relation to
/// follow and what to read on the far side. The backend keeps the text filled
/// in, so everything that already knows how to show text — the grid, the row
/// page, sorting, filtering, export — needs no changes.
class RollupBackendService {
  const RollupBackendService();

  /// The settings a column carries. An empty relation means it is an ordinary
  /// column, not a rollup.
  static Future<FlowyResult<RollupSettingsPB, FlowyError>> getSettings({
    required String viewId,
    required String fieldId,
  }) {
    final payload = RollupFieldPB()
      ..viewId = viewId
      ..fieldId = fieldId;

    return DatabaseEventGetRollupSettings(payload).send();
  }

  /// Saves the settings and fills the column in straight away.
  static Future<FlowyResult<RollupResultPB, FlowyError>> updateSettings({
    required String viewId,
    required String fieldId,
    required String relationFieldId,
    required String targetFieldId,
    required String aggregation,
  }) {
    final payload = RollupSettingsPB()
      ..viewId = viewId
      ..fieldId = fieldId
      ..relationFieldId = relationFieldId
      ..targetFieldId = targetFieldId
      ..aggregation = aggregation;

    return DatabaseEventUpdateRollupSettings(payload).send();
  }

  /// The columns a rollup can read once it follows the given relation.
  static Future<FlowyResult<List<FieldPB>, FlowyError>> getTargets({
    required String viewId,
    required String relationFieldId,
  }) {
    final payload = RollupFieldPB()
      ..viewId = viewId
      ..fieldId = relationFieldId;

    return DatabaseEventGetRollupTargets(payload).send().fold(
          (repeated) => FlowySuccess(repeated.items),
          (error) => FlowyFailure(error),
        );
  }

  /// Refills every rollup column of a view.
  static Future<FlowyResult<RollupResultPB, FlowyError>> recalculate({
    required String viewId,
  }) {
    final payload = DatabaseViewIdPB()..value = viewId;

    return DatabaseEventRecalculateRollups(payload).send();
  }
}
