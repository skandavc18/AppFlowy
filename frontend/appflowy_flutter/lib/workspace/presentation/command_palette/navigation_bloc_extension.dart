import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

extension NavigationBlocExtension on String {
  void navigateTo() {
    getIt<ActionNavigationBloc>().add(
      ActionNavigationEvent.performAction(
        action: NavigationAction(objectId: this),
        showErrorToast: true,
      ),
    );
  }
}

extension ViewNavigationBlocExtension on ViewPB {
  void navigateTo() {
    if (isWorkspaceRootFolder) {
      getIt<TabsBloc>().openPlugin(this, setLatest: false);
      return;
    }
    id.navigateTo();
  }
}
