import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_folder_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_icon.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SectionFolder extends StatefulWidget {
  const SectionFolder({
    super.key,
    required this.title,
    required this.spaceType,
    required this.views,
    this.isHoverEnabled = true,
    required this.expandButtonTooltip,
    required this.addButtonTooltip,
    this.isWorkspaceRoot = false,
  });

  final String title;
  final FolderSpaceType spaceType;
  final List<ViewPB> views;
  final bool isHoverEnabled;
  final String expandButtonTooltip;
  final String addButtonTooltip;
  final bool isWorkspaceRoot;

  @override
  State<SectionFolder> createState() => _SectionFolderState();
}

class _SectionFolderState extends State<SectionFolder> {
  final isHovered = ValueNotifier(false);

  @override
  void dispose() {
    isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: BlocProvider<FolderBloc>(
        create: (_) => FolderBloc(type: widget.spaceType)
          ..add(const FolderEvent.initial()),
        child: BlocBuilder<FolderBloc, FolderState>(
          builder: (context, state) => Column(
            children: [
              _buildHeader(context),
              // Pages
              const VSpace(2.0),
              ..._buildViews(context, state, isHovered),
              // Add a placeholder if there are no views
              _buildDraggablePlaceholder(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final workspace = context.watch<UserWorkspaceBloc>().state.currentWorkspace;
    return FolderHeader(
      title: widget.title,
      isExpanded: context.watch<FolderBloc>().state.isExpanded,
      expandButtonTooltip: widget.expandButtonTooltip,
      addButtonTooltip: widget.addButtonTooltip,
      onPressed: () => _handleHeaderPressed(context, workspace),
      onCreate: (kind) => _createRootItem(context, kind),
      leading: widget.isWorkspaceRoot && workspace != null
          ? WorkspaceIcon(
              workspaceIcon: workspace.icon,
              workspaceName: workspace.name,
              iconSize: 22,
              isEditable: true,
              fontSize: 12,
              emojiSize: 18,
              borderRadius: 6,
              figmaLineHeight: 18,
              showBorder: false,
              onSelected: (result) => context.read<UserWorkspaceBloc>().add(
                    UserWorkspaceEvent.updateWorkspaceIcon(
                      workspaceId: workspace.workspaceId,
                      icon: result.emoji,
                    ),
                  ),
            )
          : null,
      onRename: widget.isWorkspaceRoot ? _renameWorkspace : null,
    );
  }

  void _handleHeaderPressed(
    BuildContext context,
    UserWorkspacePB? workspace,
  ) {
    if (!widget.isWorkspaceRoot) {
      context.read<FolderBloc>().add(const FolderEvent.expandOrUnExpand());
      return;
    }
    if (workspace == null || workspace.workspaceId.isEmpty) {
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      );
      return;
    }
    context
        .read<FolderBloc>()
        .add(const FolderEvent.expandOrUnExpand(isExpanded: true));
    context.read<TabsBloc>().openPlugin(
          workspaceRootFolderView(
            workspaceId: workspace.workspaceId,
            name: workspace.name,
            icon: workspace.icon,
          ),
          setLatest: false,
        );
  }

  Future<bool> _renameWorkspace(String rawName) async {
    final name = rawName.trim();
    final bloc = context.read<UserWorkspaceBloc>();
    final workspace = bloc.state.currentWorkspace;
    if (workspace == null || name.isEmpty) {
      return false;
    }
    if (workspace.name == name) {
      return true;
    }
    final completion = bloc.stream.firstWhere(
      (state) =>
          state.actionResult?.actionType == WorkspaceActionType.rename &&
          state.actionResult?.isLoading == false,
    );
    bloc.add(
      UserWorkspaceEvent.renameWorkspace(
        workspaceId: workspace.workspaceId,
        name: name,
      ),
    );
    final result = (await completion).actionResult?.result;
    return result?.fold(
          (_) => true,
          (error) {
            if (mounted) {
              showSnackBarMessage(context, error.msg);
            }
            return false;
          },
        ) ??
        false;
  }

  Future<void> _createRootItem(
    BuildContext context,
    SidebarRootCreateKind kind,
  ) async {
    final view = await createSidebarRootItem(
      context,
      spaceType: widget.spaceType,
      kind: kind,
    );
    if (view == null || !context.mounted) {
      return;
    }
    context
        .read<FolderBloc>()
        .add(const FolderEvent.expandOrUnExpand(isExpanded: true));
    context.read<TabsBloc>().openPlugin(view);
  }

  Iterable<Widget> _buildViews(
    BuildContext context,
    FolderState state,
    ValueNotifier<bool> isHovered,
  ) {
    if (!state.isExpanded) {
      return [];
    }

    return widget.views.map(
      (view) => ViewItem(
        key: ValueKey('${widget.spaceType.name} ${view.id}'),
        spaceType: widget.spaceType,
        engagedInExpanding: true,
        isFirstChild: view.id == widget.views.first.id,
        view: view,
        level: 0,
        leftPadding: HomeSpaceViewSizes.leftPadding,
        isFeedback: false,
        isHovered: isHovered,
        enableRightClickContext: true,
        onSelected: (viewContext, view) {
          if (HardwareKeyboard.instance.isControlPressed) {
            context.read<TabsBloc>().openTab(view);
          }

          context.read<TabsBloc>().openPlugin(view);
        },
        onTertiarySelected: (viewContext, view) =>
            context.read<TabsBloc>().openTab(view),
        isHoverEnabled: widget.isHoverEnabled,
      ),
    );
  }

  Widget _buildDraggablePlaceholder(BuildContext context) {
    if (widget.views.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final parentViewId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
    return ViewItem(
      spaceType: widget.spaceType,
      view: ViewPB(parentViewId: parentViewId ?? ''),
      level: 0,
      leftPadding: HomeSpaceViewSizes.leftPadding,
      isFeedback: false,
      onSelected: (_, __) {},
      isHoverEnabled: widget.isHoverEnabled,
      isPlaceholder: true,
    );
  }
}

Future<ViewPB?> createSidebarRootItem(
  BuildContext context, {
  required FolderSpaceType spaceType,
  required SidebarRootCreateKind kind,
}) async {
  final workspaceId =
      context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
  if (workspaceId == null || workspaceId.isEmpty) {
    showSnackBarMessage(
      context,
      LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
    );
    return null;
  }

  final section = spaceType.toViewSectionPB;
  final result = switch (kind) {
    SidebarRootCreateKind.folder => const WorkspaceItemService().createFolder(
        parentViewId: workspaceId,
        name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
        section: section,
      ),
    SidebarRootCreateKind.page => ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        parentViewId: workspaceId,
        name: '',
        section: section,
      ),
    SidebarRootCreateKind.table => ViewBackendService.createView(
        layoutType: ViewLayoutPB.Grid,
        parentViewId: workspaceId,
        name: LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
        section: section,
      ),
  };
  final created = await result;
  if (!context.mounted) {
    return null;
  }
  return created.fold(
    (view) => view,
    (error) {
      showSnackBarMessage(context, error.msg);
      return null;
    },
  );
}
