import 'package:appflowy/features/page_access_level/logic/page_access_level_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';

/// A presentation gate, not a replacement for backend authorization of each
/// selected child or destination. Standalone/synthetic hosts may omit access.
bool canEditFolderExplorerView(
  ViewPB view, {
  PageAccessLevelState? pageAccess,
  UserWorkspacePB? workspace,
  bool identity = false,
}) {
  if (view.isLocked ||
      (pageAccess?.view.id == view.id && !pageAccess!.isEditable)) {
    return false;
  }
  if (workspace == null || workspace.workspaceId != view.id) {
    return true;
  }
  return workspace.workspaceType == WorkspaceTypePB.LocalW ||
      workspace.role == AFRolePB.Owner ||
      (!identity && workspace.role == AFRolePB.Member);
}
