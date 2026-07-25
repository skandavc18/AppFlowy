import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
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
          PopupMenuButton<_WorkspaceRootItemKind>(
            tooltip:
                LocaleKeys.workspaceFolderExplorer_createWorkspaceItem.tr(),
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.over,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: Theme.of(context).iconTheme.color,
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _WorkspaceRootItemKind.folder,
                height: 36,
                child: _RootItemLabel(
                  icon: Icons.create_new_folder_outlined,
                  label: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
                ),
              ),
              PopupMenuItem(
                value: _WorkspaceRootItemKind.file,
                height: 36,
                child: _RootItemLabel(
                  icon: Icons.note_add_outlined,
                  label: LocaleKeys.workspaceFolderExplorer_newFile.tr(),
                ),
              ),
            ],
            onSelected: (kind) => unawaited(_createWorkspaceRootItem(kind)),
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

  Future<void> _createWorkspaceRootItem(
    _WorkspaceRootItemKind kind,
  ) async {
    final workspaceState = context.read<UserWorkspaceBloc>().state;
    final space = context.read<SpaceBloc>().state.currentSpace;
    final workspaceId = workspaceState.currentWorkspace?.workspaceId;
    final parentId = space?.id ?? workspaceId;
    if (parentId == null || parentId.isEmpty) {
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      );
      return;
    }
    final section = space == null
        ? workspaceState.isCollabWorkspaceOn
            ? ViewSectionPB.Private
            : ViewSectionPB.Public
        : null;
    const service = WorkspaceItemService();
    final result = switch (kind) {
      _WorkspaceRootItemKind.folder => service.createFolder(
          parentViewId: parentId,
          name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
          section: section,
        ),
      _WorkspaceRootItemKind.file => service.createTextFile(
          parentViewId: parentId,
          name: LocaleKeys.workspaceFolderExplorer_untitledFile.tr(),
          section: section,
        ),
    };
    final created = await result;
    if (!mounted) {
      return;
    }
    created.fold(
      (view) => context.read<TabsBloc>().openPlugin(view),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }
}

enum _WorkspaceRootItemKind {
  folder,
  file,
}

class _RootItemLabel extends StatelessWidget {
  const _RootItemLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 9),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
