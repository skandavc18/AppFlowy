import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_transfer_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/favorites/favorite_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_folder_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_section_folder.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarFolder extends StatelessWidget {
  const SidebarFolder({
    super.key,
    this.isHoverEnabled = true,
    required this.userProfile,
  });

  final bool isHoverEnabled;
  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    const sectionPadding = 10.0;
    return ValueListenableBuilder(
      valueListenable: getIt<MenuSharedState>().notifier,
      builder: (context, value, child) {
        return SidebarBackgroundContextMenu(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VSpace(4.0),
              // favorite
              BlocBuilder<FavoriteBloc, FavoriteState>(
                builder: (context, state) {
                  if (state.views.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return FavoriteFolder(
                    views: state.views.map((e) => e.item).toList(),
                  );
                },
              ),
              // public or private
              BlocBuilder<SidebarSectionsBloc, SidebarSectionsState>(
                builder: (context, state) {
                  // only show public and private section if the workspace is collaborative and not local
                  final isCollaborativeWorkspace = context
                      .read<UserWorkspaceBloc>()
                      .state
                      .isCollabWorkspaceOn;

                  // only show public and private section if the workspace is collaborative
                  return Column(
                    children: isCollaborativeWorkspace
                        ? [
                            // public
                            const VSpace(sectionPadding),
                            PublicSectionFolder(
                              views: state.section.publicViews,
                            ),

                            // private
                            const VSpace(sectionPadding),
                            PrivateSectionFolder(
                              views: state.section.privateViews,
                            ),
                          ]
                        : [
                            // personal
                            const VSpace(sectionPadding),
                            BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
                              buildWhen: (previous, current) =>
                                  previous.currentWorkspace?.name !=
                                      current.currentWorkspace?.name ||
                                  previous.currentWorkspace?.icon !=
                                      current.currentWorkspace?.icon,
                              builder: (context, workspaceState) {
                                final workspaceName = workspaceState
                                    .currentWorkspace?.name
                                    .trim();
                                return PersonalSectionFolder(
                                  title: workspaceName == null ||
                                          workspaceName.isEmpty
                                      ? LocaleKeys.sideBar_personal.tr()
                                      : workspaceName,
                                  views: state.section.publicViews,
                                );
                              },
                            ),
                          ],
                  );
                },
              ),
              const VSpace(80),
            ],
          ),
        );
      },
    );
  }
}

class SidebarBackgroundContextMenu extends StatelessWidget {
  const SidebarBackgroundContextMenu({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clipboard = WorkspaceItemClipboard.instance;
    return AnimatedBuilder(
      animation: clipboard,
      builder: (context, _) {
        final actions = <SidebarRootAction>[
          ...SidebarRootCreateKind.values.map(SidebarRootCreateAction.new),
          if (clipboard.hasData) SidebarRootPasteAction(),
        ];
        return PopoverActionList<SidebarRootAction>(
          actions: actions,
          direction: PopoverDirection.bottomWithLeftAligned,
          constraints: const BoxConstraints(minWidth: 190),
          showAtCursor: true,
          onSelected: (action, popover) {
            popover.close();
            unawaited(_handleAction(context, action, clipboard));
          },
          buildChild: (popover) => Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: Listener(
                  key: const ValueKey('sidebar-empty-context-target'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    if (event.buttons == kSecondaryMouseButton) {
                      popover.showAt(event.position);
                    }
                  },
                ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    SidebarRootAction action,
    WorkspaceItemClipboard clipboard,
  ) async {
    if (action is SidebarRootCreateAction) {
      final view = await createSidebarRootItem(
        context,
        spaceType: FolderSpaceType.public,
        kind: action.kind,
      );
      if (view != null && context.mounted) {
        context.read<TabsBloc>().openPlugin(view);
      }
      return;
    }

    final workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      );
      return;
    }
    final result = await WorkspaceItemTransferService(
      clipboard: clipboard,
    ).pasteTo(destinationId: workspaceId);
    if (!context.mounted) {
      return;
    }
    result.fold(
      (_) => showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_pastedSuccessfully.tr(),
      ),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }
}

class PrivateSectionFolder extends SectionFolder {
  PrivateSectionFolder({super.key, required super.views})
      : super(
          title: LocaleKeys.sideBar_private.tr(),
          spaceType: FolderSpaceType.private,
          expandButtonTooltip: LocaleKeys.sideBar_clickToHidePrivate.tr(),
          addButtonTooltip: LocaleKeys.sideBar_addAPageToPrivate.tr(),
        );
}

class PublicSectionFolder extends SectionFolder {
  PublicSectionFolder({super.key, required super.views})
      : super(
          title: LocaleKeys.sideBar_workspace.tr(),
          spaceType: FolderSpaceType.public,
          expandButtonTooltip: LocaleKeys.sideBar_clickToHideWorkspace.tr(),
          addButtonTooltip: LocaleKeys.sideBar_addAPageToWorkspace.tr(),
        );
}

class PersonalSectionFolder extends SectionFolder {
  PersonalSectionFolder({
    super.key,
    required super.title,
    required super.views,
  }) : super(
          spaceType: FolderSpaceType.public,
          expandButtonTooltip: LocaleKeys.sideBar_clickToHidePersonal.tr(),
          addButtonTooltip: LocaleKeys.sideBar_addAPage.tr(),
          isWorkspaceRoot: true,
        );
}
