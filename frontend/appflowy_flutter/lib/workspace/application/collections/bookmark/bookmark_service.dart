import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// Creates and maintains saved links.
///
/// A bookmark is an ordinary child view carrying the bookmark envelope, so
/// there is nothing here but the envelope: renaming, moving and deleting are
/// already the workspace's job.
class BookmarkService {
  const BookmarkService();

  Future<FlowyResult<ViewPB, FlowyError>> createBookmark({
    required String parentViewId,
    required String url,
    String? name,
    ViewSectionPB? section,
  }) {
    final address = normalizeBookmarkUrl(url);
    if (address == null) {
      return Future.value(
        FlowyResult.failure(FlowyError(msg: 'Not a web address: $url')),
      );
    }
    return ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: (name?.trim().isNotEmpty ?? false)
          ? name!.trim()
          : bookmarkHost(address) ?? untitledBookmarkName,
      section: section,
      extra: BookmarkMetadata.newExtra(address),
    );
  }

  /// Rewrites the bookmark envelope on [view], leaving every other key in
  /// `extra` untouched.
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required BookmarkMetadata metadata,
  }) =>
      ViewBackendService.updateView(
        viewId: view.id,
        extra: metadata.mergeIntoExtra(view.extra),
      );

  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) =>
      ViewBackendService.updateView(viewId: viewId, name: name);

  Future<FlowyResult<void, FlowyError>> delete(List<String> viewIds) =>
      ViewBackendService.deleteViews(viewIds: viewIds);
}
