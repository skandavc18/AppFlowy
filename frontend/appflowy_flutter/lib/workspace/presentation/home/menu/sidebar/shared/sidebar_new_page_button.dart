import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarNewPageButton extends StatefulWidget {
  const SidebarNewPageButton({
    super.key,
  });

  @override
  State<SidebarNewPageButton> createState() => _SidebarNewPageButtonState();
}

class _SidebarNewPageButtonState extends State<SidebarNewPageButton> {
  @override
  void initState() {
    super.initState();
    createNewPageNotifier.addListener(_createNewPage);
  }

  @override
  void dispose() {
    createNewPageNotifier.removeListener(_createNewPage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HomeSizes.sidebarHorizontalInset,
      ),
      height: HomeSizes.newPageSectionHeight,
      child: Row(
        children: [
          Expanded(
            child: FlowyButton(
              onTap: () async => _createNewPage(),
              leftIcon: FlowySvg(
                FlowySvgs.edit_s,
                color: Theme.of(context).iconTheme.color,
                size: const Size.square(HomeSizes.sidebarActionIconSize),
              ),
              leftIconSize: const Size.square(HomeSizes.sidebarActionIconSize),
              iconPadding: HomeSizes.sidebarActionIconTextSpacing,
              margin: const EdgeInsets.symmetric(
                horizontal: HomeSizes.sidebarButtonHorizontalMargin,
              ),
              text: SidebarText(
                LocaleKeys.newPageText.tr(),
              ),
            ),
          ),
          PopoverActionList<PopoverAction>(
            direction: PopoverDirection.bottomWithRightAligned,
            offset: const Offset(0, 6),
            constraints: const BoxConstraints(minWidth: 200),
            actions: [
              WorkspaceItemAddAction(WorkspaceItemAddKind.folder),
              WorkspaceFileAddAction(
                onCreate: (action) => unawaited(_createWorkspaceRootFile(action)),
              ),
            ],
            buildChild: (popover) => FlowyIconButton(
              width: 24,
              iconPadding: const EdgeInsets.all(3),
              tooltipText:
                  LocaleKeys.workspaceFolderExplorer_createWorkspaceItem.tr(),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: Theme.of(context).iconTheme.color,
              ),
              onPressed: popover.show,
            ),
            onSelected: (action, popover) {
              popover.close();
              if (action is WorkspaceItemAddAction) {
                unawaited(_createWorkspaceRootFolder());
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createNewPage() async {
    // if the workspace is collaborative, create the view in the private section by default.
    final section = context.read<UserWorkspaceBloc>().state.isCollabWorkspaceOn
        ? ViewSectionPB.Private
        : ViewSectionPB.Public;
    final spaceState = context.read<SpaceBloc>().state;
    if (spaceState.spaces.isNotEmpty) {
      context.read<SpaceBloc>().add(
            const SpaceEvent.createPage(
              name: '',
              index: 0,
              layout: ViewLayoutPB.Document,
              openAfterCreate: true,
            ),
          );
    } else {
      context.read<SidebarSectionsBloc>().add(
            SidebarSectionsEvent.createRootViewInSection(
              name: '',
              viewSection: section,
              index: 0,
            ),
          );
    }
  }

  Future<void> _createWorkspaceRootFolder() async {
    final parent = _resolveParent();
    if (parent == null) {
      return;
    }
    const service = WorkspaceItemService();
    final created = await service.createFolder(
      parentViewId: parent.id,
      name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
      section: parent.section,
    );
    if (!mounted) {
      return;
    }
    created.fold(
      (view) => context.read<TabsBloc>().openPlugin(view),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  Future<void> _createWorkspaceRootFile(WorkspaceFileMenuAction action) async {
    final parent = _resolveParent();
    if (parent == null) {
      return;
    }
    final created = await createWorkspaceFile(
      parentViewId: parent.id,
      action: action,
      section: parent.section,
    );
    if (created == null || !mounted) {
      return;
    }
    created.fold(
      (view) => context.read<TabsBloc>().openPlugin(view),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  /// Where a root item belongs: the open space, or the workspace itself.
  ({String id, ViewSectionPB? section})? _resolveParent() {
    final workspaceState = context.read<UserWorkspaceBloc>().state;
    final space = context.read<SpaceBloc>().state.currentSpace;
    final parentId = space?.id ?? workspaceState.currentWorkspace?.workspaceId;
    if (parentId == null || parentId.isEmpty) {
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      );
      return null;
    }
    return (
      id: parentId,
      section: space == null
          ? workspaceState.isCollabWorkspaceOn
              ? ViewSectionPB.Private
              : ViewSectionPB.Public
          : null,
    );
  }
}
