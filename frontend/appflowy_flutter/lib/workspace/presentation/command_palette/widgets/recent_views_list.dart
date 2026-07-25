import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/recent/recent_views_bloc.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_icon.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_recent_view_cell.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fixnum/fixnum.dart';

import 'page_inspection_panel.dart';
import 'search_ask_ai_entrance.dart';
import 'search_layout.dart';

class RecentViewsList extends StatelessWidget {
  const RecentViewsList({
    required this.onSelected,
    required this.filter,
    required this.cachedViews,
    required this.currentUserId,
    this.currentWorkspaceId,
    this.currentWorkspaceName,
    this.currentWorkspaceIcon,
    this.currentWorkspaceCover,
    super.key,
  });

  final VoidCallback onSelected;
  final CommandPaletteFilter filter;
  final Map<String, ViewPB> cachedViews;
  final Int64? currentUserId;
  final String? currentWorkspaceId;
  final String? currentWorkspaceName;
  final String? currentWorkspaceIcon;
  final PageStyleCover? currentWorkspaceCover;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          RecentViewsBloc()..add(const RecentViewsEvent.initial()),
      child: BlocBuilder<RecentViewsBloc, RecentViewsState>(
        builder: (context, state) {
          final visibleViews = _visibleViews(state);
          final selectedView = _selectedView(state, visibleViews);
          return LayoutBuilder(
            builder: (context, constrains) {
              final maxWidth = constrains.maxWidth;
              final hidePreview = maxWidth < commandPalettePreviewBreakpoint;
              final listWidth =
                  hidePreview ? maxWidth : commandPaletteListWidth(maxWidth);
              return Row(
                children: [
                  if (!hidePreview && selectedView != null)
                    Expanded(child: buildPreview(context, selectedView)),
                  buildLeftPanel(
                    visibleViews,
                    selectedView,
                    context,
                    hidePreview,
                    listWidth,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget buildLeftPanel(
    List<ViewPB> visibleViews,
    ViewPB? selectedView,
    BuildContext context,
    bool hidePreview,
    double width,
  ) {
    final workspaceState = context.read<UserWorkspaceBloc?>()?.state;
    final showAskingAI =
        workspaceState?.userProfile.workspaceType == WorkspaceTypePB.ServerW;
    return SizedBox(
      key: const ValueKey('command-palette-recent-list-panel'),
      width: width,
      child: Align(
        alignment: Alignment.topLeft,
        child: ScrollControllerBuilder(
          builder: (context, controller) {
            return Padding(
              padding: EdgeInsets.only(right: hidePreview ? 0 : 6),
              child: FlowyScrollbar(
                controller: controller,
                thumbVisibility: false,
                child: SingleChildScrollView(
                  controller: controller,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: hidePreview ? 0 : 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showAskingAI) SearchAskAiEntrance(),
                        buildTitle(context),
                        buildViewList(
                          visibleViews,
                          selectedView,
                          context,
                          hidePreview,
                        ),
                        VSpace(16),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget buildTitle(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.m,
        vertical: theme.spacing.s,
      ),
      child: Text(
        LocaleKeys.sideBar_recent.tr(),
        style: theme.textStyle.body
            .enhanced(color: theme.textColorScheme.secondary)
            .copyWith(
              letterSpacing: 0.2,
              height: 22 / 16,
            ),
      ),
    );
  }

  Widget buildViewList(
    List<ViewPB> recentViews,
    ViewPB? selectedView,
    BuildContext context,
    bool hidePreview,
  ) {
    if (recentViews.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recentViews.length,
      itemBuilder: (_, index) {
        final view = recentViews[index];

        return SearchRecentViewCell(
          key: ValueKey(view.id),
          icon: SizedBox.square(
            dimension: 20,
            child: Center(child: view.buildIcon(context)),
          ),
          view: view,
          onSelected: onSelected,
          isNarrowWindow: hidePreview,
          isSelected: selectedView?.id == view.id,
        );
      },
    );
  }

  Widget buildPreview(BuildContext context, ViewPB selectedView) {
    return PageInspectionPanel(
      view: selectedView,
      cachedViews: {
        ...cachedViews,
        selectedView.id: selectedView,
      },
      currentUserId: currentUserId,
      onOpen: (view) {
        view.navigateTo();
        onSelected();
      },
      onClose: () => FlowyOverlay.pop(context),
    );
  }

  List<ViewPB> _visibleViews(RecentViewsState state) {
    final recentViews = state.views
        .map((entry) => _normalizedView(entry.item))
        .toSet()
        .toList();
    final viewsById = <String, ViewPB>{
      ...cachedViews,
      for (final view in recentViews) view.id: view,
    };
    return recentViews
        .where(
          (view) => filter.matchesRecentView(
            view: view,
            cachedViews: viewsById,
            currentUserId: currentUserId,
          ),
        )
        .toList();
  }

  ViewPB _normalizedView(ViewPB view) {
    final cachedView = cachedViews[view.id] ?? view;
    final workspaceId = currentWorkspaceId;
    if (workspaceId == null) {
      return cachedView;
    }
    return cachedView.asWorkspaceRootFolder(
      workspaceId: workspaceId,
      name: currentWorkspaceName ?? cachedView.name,
      icon: currentWorkspaceIcon,
      cover: currentWorkspaceCover,
    );
  }

  ViewPB? _selectedView(
    RecentViewsState state,
    List<ViewPB> visibleViews,
  ) {
    final hoveredView = state.hoveredView;
    if (hoveredView != null) {
      for (final view in visibleViews) {
        if (view.id == hoveredView.id) {
          return view;
        }
      }
    }
    return visibleViews.isEmpty ? null : visibleViews.first;
  }
}
