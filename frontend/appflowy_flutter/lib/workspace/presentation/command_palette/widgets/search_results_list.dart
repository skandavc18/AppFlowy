import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/command_palette/search_result_list_bloc.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_ask_ai_entrance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'search_result_cell.dart';
import 'command_results_list.dart';
import 'page_inspection_panel.dart';
import 'search_layout.dart';

class SearchResultList extends StatefulWidget {
  const SearchResultList({
    required this.cachedViews,
    required this.resultItems,
    required this.resultSummaries,
    this.commands = const [],
    this.onRunCommand,
    this.currentWorkspaceId,
    this.currentWorkspaceName,
    this.currentWorkspaceIcon,
    this.currentWorkspaceCover,
    super.key,
  });

  final Map<String, ViewPB> cachedViews;
  final List<SearchResultItem> resultItems;
  final List<SearchSummaryPB> resultSummaries;

  /// The commands whose names also answer to the query, offered above the pages.
  final List<PaletteCommand> commands;
  final ValueChanged<PaletteCommand>? onRunCommand;
  final String? currentWorkspaceId;
  final String? currentWorkspaceName;
  final String? currentWorkspaceIcon;
  final PageStyleCover? currentWorkspaceCover;

  @override
  State<SearchResultList> createState() => _SearchResultListState();
}

class _SearchResultListState extends State<SearchResultList> {
  late final SearchResultListBloc bloc;
  late Map<String, ViewPB> cachedViews;
  ViewPB? narrowFolderView;

  @override
  void initState() {
    super.initState();
    bloc = SearchResultListBloc();
    _syncCachedViews();
    _syncSelection();
  }

  @override
  void didUpdateWidget(covariant SearchResultList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCachedViews();
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
            final view = cachedViews[pageId];
            view == null ? pageId.navigateTo() : view.navigateTo();
          }
        },
        child: BlocBuilder<SearchResultListBloc, SearchResultListState>(
          builder: (context, state) {
            final selectedResult = _selectedResult(state);
            final selectedView =
                selectedResult == null ? null : cachedViews[selectedResult.id];
            return LayoutBuilder(
              builder: (context, constrains) {
                final maxWidth = constrains.maxWidth;
                final hidePreview = maxWidth < commandPalettePreviewBreakpoint;
                // Nothing to preview when only commands matched, so the list
                // takes the whole box rather than leaving it half empty.
                final listOnly = _visibleResultItems.isEmpty;
                final listWidth = hidePreview || listOnly
                    ? maxWidth
                    : commandPaletteListWidth(maxWidth);
                final narrowFolder = narrowFolderView == null
                    ? null
                    : cachedViews[narrowFolderView!.id] ?? narrowFolderView;
                if (hidePreview && narrowFolder != null) {
                  return PageInspectionPanel(
                    view: narrowFolder,
                    cachedViews: cachedViews,
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
                          cachedViews: cachedViews,
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

  Widget _buildSectionHeader(BuildContext context) =>
      CommandPaletteSectionHeader(
        label: LocaleKeys.commandPalette_bestMatches.tr(),
      );

  Widget _buildResultsSection(BuildContext context, bool hidePreview) {
    final resultItems = _visibleResultItems;
    final commands = widget.commands;
    final onRunCommand = widget.onRunCommand;
    final showCommands = commands.isNotEmpty && onRunCommand != null;
    if (resultItems.isEmpty && !showCommands) return const SizedBox.shrink();
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
                    SearchAskAiEntrance(),
                    if (showCommands)
                      CommandResultsList(
                        commands: commands,
                        onRun: onRunCommand,
                        grouped: false,
                      ),
                    if (resultItems.isNotEmpty)
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
                                view: cachedViews[item.id],
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
                        ],
                      ),
                    VSpace(16),
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
    if (cachedViews.isEmpty) {
      return widget.resultItems;
    }
    return widget.resultItems
        .where((item) => cachedViews.containsKey(item.id))
        .toList();
  }

  void _syncCachedViews() {
    cachedViews = widget.cachedViews;
    final workspaceId = widget.currentWorkspaceId;
    final workspaceRoot = workspaceId == null ? null : cachedViews[workspaceId];
    if (workspaceId == null || workspaceRoot == null) {
      return;
    }
    cachedViews = {
      ...cachedViews,
      workspaceId: workspaceRoot.asWorkspaceRootFolder(
        workspaceId: workspaceId,
        name: widget.currentWorkspaceName ?? workspaceRoot.name,
        icon: widget.currentWorkspaceIcon,
        cover: widget.currentWorkspaceCover,
      ),
    };
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
