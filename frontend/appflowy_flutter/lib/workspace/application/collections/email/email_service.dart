import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// Maintains the envelope a stored message carries.
///
/// A message is an ordinary child view, so renaming, moving and deleting are
/// already the workspace's job; only the summary and the reader's own marks
/// belong here.
class EmailService {
  const EmailService();

  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required EmailMetadata metadata,
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
