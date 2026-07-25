import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

abstract final class ViewCoverService {
  static Future<FlowyResult<void, FlowyError>> updateCover({
    required ViewPB view,
    required PageStyleCover cover,
  }) async {
    try {
      return ViewBackendService.updateView(
        viewId: view.id,
        extra: ViewCoverCodec.mergeCover(view.extra, cover),
      );
    } on FormatException catch (error) {
      return FlowyResult.failure(
        FlowyError(
          code: ErrorCode.ViewDataInvalid,
          msg: 'Unable to preserve existing view metadata: ${error.message}',
        ),
      );
    }
  }
}
