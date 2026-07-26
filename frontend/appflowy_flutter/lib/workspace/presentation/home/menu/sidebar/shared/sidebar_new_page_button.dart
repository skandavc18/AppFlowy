import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
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
                  trailing: Icons.chevron_right_rounded,
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

    if (kind == _WorkspaceRootItemKind.file) {
      final action = await showWorkspaceFileKindMenu(
        context: context,
        globalPosition: _menuAnchor(),
      );
      if (action == null || !mounted) {
        return;
      }
      final createdFile = await createWorkspaceFile(
        parentViewId: parentId,
        action: action,
        section: section,
      );
      if (createdFile == null || !mounted) {
        return;
      }
      createdFile.fold(
        (view) => context.read<TabsBloc>().openPlugin(view),
        (error) => showSnackBarMessage(context, error.msg),
      );
      return;
    }

    const service = WorkspaceItemService();
    final created = await service.createFolder(
      parentViewId: parentId,
      name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
      section: section,
    );
    if (!mounted) {
      return;
    }
    created.fold(
      (view) => context.read<TabsBloc>().openPlugin(view),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  Offset _menuAnchor() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return Offset.zero;
    }
    return box.localToGlobal(Offset(0, box.size.height));
  }
}

enum _WorkspaceRootItemKind {
  folder,
  file,
}

class _RootItemLabel extends StatelessWidget {
  const _RootItemLabel({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        if (trailing != null) Icon(trailing, size: 16),
      ],
    );
  }
}
