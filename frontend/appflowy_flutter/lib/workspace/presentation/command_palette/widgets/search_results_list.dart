import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/search_result_list_bloc.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_ask_ai_entrance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'search_result_cell.dart';
import 'page_inspection_panel.dart';
import 'search_layout.dart';

class SearchResultList extends StatefulWidget {
  const SearchResultList({
    required this.cachedViews,
    required this.resultItems,
    required this.resultSummaries,
    super.key,
  });

  final Map<String, ViewPB> cachedViews;
  final List<SearchResultItem> resultItems;
  final List<SearchSummaryPB> resultSummaries;

  @override
  State<SearchResultList> createState() => _SearchResultListState();
}

class _SearchResultListState extends State<SearchResultList> {
  late final SearchResultListBloc bloc;
  ViewPB? narrowFolderView;

  @override
  void initState() {
    super.initState();
    bloc = SearchResultListBloc();
    _syncSelection();
  }

  @override
  void didUpdateWidget(covariant SearchResultList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final folderId = narrowFolderView?.id;
    if (folderId != null &&
        !widget.resultItems.any((item) => item.id == folderId)) {
      narrowFolderView = null;
    }
    _syncSelection();
  }

  @override
  void dispose() {
    bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: bloc,
      child: BlocListener<SearchResultListBloc, SearchResultListState>(
        listener: (context, state) {
          final pageId = state.openPageId;
          if (pageId != null && pageId.isNotEmpty) {
            FlowyOverlay.pop(context);
            pageId.navigateTo();
          }
        },
        child: BlocBuilder<SearchResultListBloc, SearchResultListState>(
          builder: (context, state) {
            final selectedResult = _selectedResult(state);
            final selectedView = selectedResult == null
                ? null
                : widget.cachedViews[selectedResult.id];
            return LayoutBuilder(
              builder: (context, constrains) {
                final maxWidth = constrains.maxWidth;
                final hidePreview = maxWidth < commandPalettePreviewBreakpoint;
                final listWidth =
                    hidePreview ? maxWidth : commandPaletteListWidth(maxWidth);
                final narrowFolder = narrowFolderView == null
                    ? null
                    : widget.cachedViews[narrowFolderView!.id] ??
                        narrowFolderView;
                if (hidePreview && narrowFolder != null) {
                  return PageInspectionPanel(
                    view: narrowFolder,
                    cachedViews: widget.cachedViews,
                    currentUserId: context
                        .read<UserWorkspaceBloc?>()
                        ?.state
                        .userProfile
                        .id,
                    onOpen: (view) => bloc.add(
                      SearchResultListEvent.openPage(pageId: view.id),
                    ),
                    onClose: () => FlowyOverlay.pop(context),
                    onBack: () => setState(() => narrowFolderView = null),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hidePreview && selectedView != null)
                      Expanded(
                        child: PageInspectionPanel(
                          view: selectedView,
                          cachedViews: widget.cachedViews,
                          currentUserId: context
                              .read<UserWorkspaceBloc?>()
                              ?.state
                              .userProfile
                              .id,
                          onOpen: (view) => bloc.add(
                            SearchResultListEvent.openPage(
                              pageId: view.id,
                            ),
                          ),
                          onClose: () => FlowyOverlay.pop(context),
                        ),
                      ),
                    SizedBox(
                      key: const ValueKey(
                        'command-palette-search-results-panel',
                      ),
                      width: listWidth,
                      child: _buildResultsSection(context, hidePreview),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: theme.spacing.s,
        horizontal: theme.spacing.m,
      ),
      child: Text(
        LocaleKeys.commandPalette_bestMatches.tr(),
        style: theme.textStyle.body
            .enhanced(color: theme.textColorScheme.secondary)
            .copyWith(
              letterSpacing: 0.2,
              height: 22 / 16,
            ),
      ),
    );
  }

  Widget _buildResultsSection(BuildContext context, bool hidePreview) {
    final workspaceState = context.read<UserWorkspaceBloc?>()?.state;
    final showAskingAI =
        workspaceState?.userProfile.workspaceType == WorkspaceTypePB.ServerW;
    final resultItems = _visibleResultItems;
    if (resultItems.isEmpty) return const SizedBox.shrink();
    return ScrollControllerBuilder(
      builder: (context, controller) {
        final hoveredId = bloc.state.hoveredResult?.id;
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSectionHeader(context),
                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: resultItems.length,
                          itemBuilder: (_, index) {
                            final item = resultItems[index];
                            return SearchResultCell(
                              key: ValueKey(item.id),
                              item: item,
                              isNarrowWindow: hidePreview,
                              view: widget.cachedViews[item.id],
                              isHovered: hoveredId == item.id,
                              onFolderSelected: hidePreview
                                  ? (view) =>
                                      setState(() => narrowFolderView = view)
                                  : null,
                              query: context
                                  .read<CommandPaletteBloc?>()
                                  ?.state
                                  .query,
                            );
                          },
                        ),
                        VSpace(16),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<SearchResultItem> get _visibleResultItems {
    if (widget.cachedViews.isEmpty) {
      return widget.resultItems;
    }
    return widget.resultItems
        .where((item) => widget.cachedViews.containsKey(item.id))
        .toList();
  }

  SearchResultItem? _selectedResult(SearchResultListState state) {
    final selected = state.hoveredResult;
    if (selected == null) {
      return null;
    }
    for (final item in _visibleResultItems) {
      if (item.id == selected.id) {
        return item;
      }
    }
    return null;
  }

  void _syncSelection() {
    final visibleItems = _visibleResultItems;
    final selectedId = bloc.state.hoveredResult?.id;
    if (selectedId != null &&
        visibleItems.any((item) => item.id == selectedId)) {
      return;
    }
    if (visibleItems.isNotEmpty) {
      bloc.add(
        SearchResultListEvent.onHoverResult(
          item: visibleItems.first,
          userHovered: false,
        ),
      );
    }
  }
}
