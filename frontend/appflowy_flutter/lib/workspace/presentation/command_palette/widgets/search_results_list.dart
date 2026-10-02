import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/command_palette/palette_setting.dart';
import 'package:appflowy/workspace/application/command_palette/search_result_list_bloc.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart'
    show SettingsPage;
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_setting_cell.dart';
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
    this.settings = const [],
    this.onOpenSettingPicker,
    this.onOpenSettingsPage,
    this.highlightFirstCommand = false,
    this.currentWorkspaceId,
    this.currentWorkspaceName,
    this.currentWorkspaceIcon,
    this.currentWorkspaceCover,
    this.query,
    this.contentSearch = false,
    this.metadataOnly = false,
    this.canUseResult,
    super.key,
  });

  final Map<String, ViewPB> cachedViews;
  final List<SearchResultItem> resultItems;
  final List<SearchSummaryPB> resultSummaries;

  /// The commands whose names also answer to the query, offered above the pages.
  final List<PaletteCommand> commands;
  final ValueChanged<PaletteCommand>? onRunCommand;

  /// The settings that answer to the query, changed right in their rows.
  final List<PaletteSetting> settings;
  final ValueChanged<PaletteSetting>? onOpenSettingPicker;
  final ValueChanged<SettingsPage>? onOpenSettingsPage;

  /// Marks the first command as the one Enter runs, when it is the best
  /// answer to what was typed — a command handed a name, say.
  final bool highlightFirstCommand;
  final String? currentWorkspaceId;
  final String? currentWorkspaceName;
  final String? currentWorkspaceIcon;
  final PageStyleCover? currentWorkspaceCover;
  final String? query;
  final bool contentSearch;
  final bool metadataOnly;
  final bool Function(String viewId)? canUseResult;

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
            if (ModalRoute.of(context)?.isCurrent == false) return;
            if (!_visibleResultItems.any((item) => item.id == pageId) ||
                !(widget.canUseResult?.call(pageId) ?? true)) {
              return;
            }
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
                  final narrowResult = _visibleResultItems
                      .where((item) => item.id == narrowFolder.id)
                      .firstOrNull;
                  return PageInspectionPanel(
                    view: narrowFolder,
                    query: _query,
                    matchingSnippet: narrowResult?.content,
                    contentSearch: widget.contentSearch,
                    metadataOnly: widget.metadataOnly,
                    canUseView: widget.canUseResult,
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
                    SizedBox(
                      key: const ValueKey(
                        'command-palette-search-results-panel',
                      ),
                      width: listWidth,
                      child: _buildResultsSection(context, hidePreview),
                    ),
                    if (!hidePreview && selectedView != null)
                      Expanded(
                        child: PageInspectionPanel(
                          view: selectedView,
                          query: _query,
                          matchingSnippet: selectedResult?.content,
                          contentSearch: widget.contentSearch,
                          metadataOnly: widget.metadataOnly,
                          canUseView: widget.canUseResult,
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
    final settings = widget.settings;
    final onOpenPicker = widget.onOpenSettingPicker;
    final onOpenSettings = widget.onOpenSettingsPage;
    final showSettings =
        settings.isNotEmpty && onOpenPicker != null && onOpenSettings != null;
    if (resultItems.isEmpty && !showCommands && !showSettings) {
      return const SizedBox.shrink();
    }
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
                    if (!widget.contentSearch) SearchAskAiEntrance(),
                    if (showCommands)
                      CommandResultsList(
                        commands: commands,
                        onRun: onRunCommand,
                        grouped: false,
                        query: _query,
                        highlightFirst: widget.highlightFirstCommand,
                      ),
                    if (showSettings)
                      PaletteSettingsList(
                        settings: settings,
                        onOpenPicker: onOpenPicker,
                        onOpenSettings: onOpenSettings,
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
                                cachedViews: cachedViews,
                                contentSearch: widget.contentSearch,
                                isHovered: hoveredId == item.id,
                                onPreviewSelected:
                                    widget.contentSearch && hidePreview
                                        ? () => setState(() {
                                              narrowFolderView =
                                                  cachedViews[item.id];
                                            })
                                        : null,
                                onFolderSelected: hidePreview
                                    ? (view) =>
                                        setState(() => narrowFolderView = view)
                                    : null,
                                query: _query,
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
    if (cachedViews.isEmpty && !widget.contentSearch) {
      return widget.resultItems;
    }
    return widget.resultItems
        .where((item) => cachedViews.containsKey(item.id))
        .where((item) => widget.canUseResult?.call(item.id) ?? true)
        .toList();
  }

  String get _query =>
      widget.query ?? context.read<CommandPaletteBloc?>()?.state.query ?? '';

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
