import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// Creates and maintains collections.
///
/// Collections reference the objects that already exist in the workspace, so
/// everything below the collection itself is handled by the ordinary workspace
/// item plumbing.
class CollectionService {
  const CollectionService();

  static const _items = WorkspaceItemService();

  Future<FlowyResult<ViewPB, FlowyError>> createCollection({
    required String parentViewId,
    required CollectionKind kind,
    required String name,
    ViewSectionPB? section,
  }) {
    return ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: name,
      section: section,
      extra: CollectionMetadata.newExtra(kind),
    );
  }

  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String viewId) =>
      _items.getChildren(viewId);

  /// Rewrites the collection envelope on [view], leaving every other key in
  /// `extra` (workspace item, cover, font) untouched.
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required CollectionMetadata metadata,
  }) {
    return ViewBackendService.updateView(
      viewId: view.id,
      extra: metadata.mergeIntoExtra(view.extra),
    );
  }

  Future<FlowyResult<ViewPB, FlowyError>> setActiveView({
    required ViewPB view,
    required String adaptiveViewId,
  }) {
    final metadata = view.collection;
    if (metadata == null) {
      return Future.value(
        FlowyResult.failure(
          FlowyError(msg: 'The view is not a collection.'),
        ),
      );
    }
    return updateMetadata(
      view: view,
      metadata: metadata.copyWith(activeViewId: adaptiveViewId),
    );
  }

  Future<FlowyResult<ViewPB, FlowyError>> setViewState({
    required ViewPB view,
    required String adaptiveViewId,
    required Map<String, dynamic> state,
  }) {
    final metadata = view.collection;
    if (metadata == null) {
      return Future.value(
        FlowyResult.failure(
          FlowyError(msg: 'The view is not a collection.'),
        ),
      );
    }
    return updateMetadata(
      view: view,
      metadata: metadata.withStateFor(adaptiveViewId, state),
    );
  }
}
