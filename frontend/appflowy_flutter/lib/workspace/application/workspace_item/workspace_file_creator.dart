import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';

/// Runs one entry of the "New file" menu under [parentViewId].
///
/// Returns `null` when the picker is cancelled or the optional host gate closes.
Future<FlowyResult<ViewPB, FlowyError>?> createWorkspaceFile({
  required String parentViewId,
  required WorkspaceFileMenuAction action,
  ViewSectionPB? section,
  String? name,
  bool Function()? canWrite,
}) async {
  if (canWrite != null && !canWrite()) return null;
  const service = WorkspaceItemService();
  if (action.source == WorkspaceFileSource.create) {
    final created = await service.createBlankFile(
      parentViewId: parentViewId,
      kind: action.kind,
      name: name,
      section: section,
    );
    return canWrite?.call() == false ? null : created;
  }

  final extensions = action.kind.pickerExtensions;
  final result = await getIt<FilePickerService>().pickFiles(
    dialogTitle: 'Upload ${action.kind.label.toLowerCase()}',
    type: extensions.isEmpty ? FileType.any : FileType.custom,
    allowedExtensions: extensions.isEmpty ? null : extensions,
  );
  final picked = result?.files.firstOrNull;
  if (picked == null || (canWrite != null && !canWrite())) {
    return null;
  }

  final imported = await service.importBinaryFile(
    parentViewId: parentViewId,
    file: picked.xFile,
    section: section,
  );
  return canWrite?.call() == false ? null : imported;
}
