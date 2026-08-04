import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// Creates and maintains the tables in a database collection.
///
/// A table is an ordinary AppFlowy database view, so there is nothing here but
/// the folder call: renaming, moving, deleting and every database tool already
/// work on it.
class DatabaseTableService {
  const DatabaseTableService();

  Future<FlowyResult<ViewPB, FlowyError>> createTable({
    required String parentViewId,
    ViewLayoutPB layout = ViewLayoutPB.Grid,
    String? name,
    ViewSectionPB? section,
  }) =>
      ViewBackendService.createView(
        layoutType: layout,
        parentViewId: parentViewId,
        name: (name?.trim().isNotEmpty ?? false) ? name!.trim() : 'Table',
        section: section,
      );

  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) =>
      ViewBackendService.updateView(viewId: viewId, name: name);

  Future<FlowyResult<void, FlowyError>> delete(String viewId) =>
      ViewBackendService.deleteView(viewId: viewId);

  Future<FlowyResult<void, FlowyError>> duplicate(ViewPB view) =>
      ViewBackendService.duplicate(
        view: view,
        openAfterDuplicate: false,
        includeChildren: true,
        syncAfterDuplicate: false,
      );
}

/// The label a layout is offered under when a table is created.
String databaseLayoutLabel(ViewLayoutPB layout) => switch (layout) {
      ViewLayoutPB.Board => 'Board',
      ViewLayoutPB.Calendar => 'Calendar',
      _ => 'Grid',
    };
