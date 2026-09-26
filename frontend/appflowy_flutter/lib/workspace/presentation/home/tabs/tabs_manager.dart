import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TabsManager extends StatefulWidget {
  const TabsManager({super.key, required this.onIndexChanged});

  final void Function(int) onIndexChanged;

  @override
  State<TabsManager> createState() => _TabsManagerState();
}

class _TabsManagerState extends State<TabsManager> {
  final _scrollController = ScrollController();
  int _revealGeneration = 0;
  bool _dragging = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        if (state.pages == 0) {
          return const SizedBox.shrink();
        }

        // One continuous title surface; the selected tab meets the page below.
        return ColoredBox(
          key: const ValueKey('workspace-tab-rail'),
          color: SidebarPalette.of(context).background,
          child: SizedBox(
            height: HomeSizes.tabBarHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The caption always owns a separate native drag target. A
                // narrow pane moves '+' into overflow, never offscreen, and
                // gives the remaining width to the unchanged scrolling tabs.
                final roomy = constraints.maxWidth >= HomeSizes.tabPaneMinWidth;
                final trailingSpace = roomy ? WorkspaceTokens.space2 : 0.0;
                final room = math.max(
                  0.0,
                  constraints.maxWidth -
                      (roomy ? 2 : 1) * WorkspaceTokens.controlHeight -
                      (roomy ? WorkspaceTokens.space6 : 0) -
                      trailingSpace,
                );
                final pinned =
                    state.pageManagers.where((pm) => pm.isPinned).length;
                final regularWidth =
                    ((room - pinned * HomeSizes.pinnedTabWidth) /
                            math.max(1, state.pages - pinned))
                        .clamp(HomeSizes.tabBarMinWidth, HomeSizes.tabBarWidth)
                        .toDouble();
                final widths = [
                  for (final pm in state.pageManagers)
                    pm.isPinned ? HomeSizes.pinnedTabWidth : regularWidth,
                ];
                final total = widths.fold(0.0, (sum, width) => sum + width);
                _revealCurrent(state.currentIndex, widths);

                return Row(
                  children: [
                    // Below one pinned face, showing a few pixels of tab
                    // padding is misleading. The adjacent menu still exposes
                    // every real tab and all its commands at this width.
                    if (room >= 48)
                      SizedBox(
                        width: math.min(room, total),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: ReorderableListView.builder(
                            scrollDirection: Axis.horizontal,
                            scrollController: _scrollController,
                            padding: EdgeInsets.zero,
                            buildDefaultDragHandles: false,
                            itemCount: state.pages,
                            // Widths are known even for unbuilt tabs. Let a
                            // distant reveal skip laying out intervening tabs.
                            itemExtentBuilder: (index, _) =>
                                index < widths.length ? widths[index] : null,
                            onReorderStart: (_) => _dragging = true,
                            onReorderEnd: (_) => _dragging = false,
                            onReorder: (oldIndex, newIndex) {
                              _dragging = false;
                              context
                                  .read<TabsBloc>()
                                  .reorderTab(oldIndex, newIndex);
                            },
                            proxyDecorator: (child, index, animation) {
                              final palette = WorkspacePalette.of(context);
                              return Material(
                                color: palette.elevatedSurface,
                                borderRadius: BorderRadius.circular(
                                  HomeSizes.tabCornerRadius,
                                ),
                                child: child,
                              );
                            },
                            itemBuilder: (context, index) {
                              final pm = state.pageManagers[index];
                              return SizedBox(
                                key: ObjectKey(pm),
                                width: widths[index],
                                child: ReorderableDragStartListener(
                                  index: index,
                                  child: FlowyTab(
                                    key: ValueKey('tab-${pm.plugin.id}'),
                                    pageManager: pm,
                                    isCurrent: state.currentPageManager == pm,
                                    isAllPinned: state.isAllPinned,
                                    showSeparator: index < state.pages - 1 &&
                                        index != state.currentIndex &&
                                        index + 1 != state.currentIndex,
                                    onTap: () => widget.onIndexChanged(index),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    if (roomy) const TabsNewTabButton(),
                    const Expanded(child: WindowDragTarget()),
                    TabsOverflowButton(
                      onIndexChanged: widget.onIndexChanged,
                      includeTabActions: state.pages == 1 || !roomy,
                    ),
                    SizedBox(width: trailingSpace),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _revealCurrent(int index, List<double> widths) {
    final generation = ++_revealGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _revealGeneration ||
          _dragging ||
          !_scrollController.hasClients ||
          index < 0 ||
          index >= widths.length) {
        return;
      }
      final position = _scrollController.position;
      final start = widths.take(index).fold(0.0, (sum, width) => sum + width);
      final end = start + widths[index];
      final maxExtent = math.max(
        position.minScrollExtent,
        widths.fold(0.0, (sum, width) => sum + width) -
            position.viewportDimension,
      );
      final target = (start < position.pixels
              ? start
              : end > position.pixels + position.viewportDimension
                  ? end - position.viewportDimension
                  : position.pixels)
          .clamp(position.minScrollExtent, maxExtent);
      if ((target - position.pixels).abs() < 0.5) return;
      final duration = WorkspaceTokens.motion(
        context,
        WorkspaceTokens.hoverDuration,
      );
      // The lazy sliver can underestimate its extent after seeing narrow
      // pinned tabs first, even with itemExtentBuilder. An animation would
      // stop at that temporary boundary; jump to the known offset so the
      // destination is laid out without another selection or reveal retry.
      if (duration == Duration.zero || target > position.maxScrollExtent) {
        _scrollController.jumpTo(target);
      } else {
        unawaited(
          _scrollController.animateTo(
            target,
            duration: duration,
            curve: WorkspaceTokens.curve,
          ),
        );
      }
    });
  }
}

/// New tabs open Home without a picker or creating a persisted workspace page.
Future<void> openWorkspaceTab(
  BuildContext context, {
  bool newTab = true,
}) async {
  final tabs = context.read<TabsBloc>();
  final workspace = context.read<UserWorkspaceBloc?>();
  final settings = context.read<HomeSettingBloc?>();
  final workspaceId = workspace?.state.currentWorkspace?.workspaceId ??
      settings?.state.workspaceSetting.workspaceId;
  final userId = workspace?.state.userProfile.id;
  if (workspaceId == null || workspaceId.isEmpty || tabs.isClosed) return;
  try {
    await tabs.openHome(
      workspaceId: workspaceId,
      newTab: newTab,
      isCurrent: () =>
          context.mounted &&
          (workspace == null ||
              (!workspace.isClosed &&
                  workspace.state.userProfile.id == userId &&
                  (workspace.state.currentWorkspace?.workspaceId ??
                          settings?.state.workspaceSetting.workspaceId) ==
                      workspaceId)),
    );
  } catch (error, stackTrace) {
    Log.error('Could not open a workspace tab', error, stackTrace);
    if (context.mounted) {
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
      );
    }
  }
}

class TabsNewTabButton extends StatelessWidget {
  const TabsNewTabButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('new-workspace-tab'),
        icon: const DSWorkspaceGlyph.named('plus'),
        style: _tabControlStyle(context),
        tooltip: LocaleKeys.disclosureAction_openNewTab.tr(),
        onPressed: () => unawaited(openWorkspaceTab(context)),
      );
}

ButtonStyle _tabControlStyle(BuildContext context) =>
    WorkspaceChrome.controlStyle(context).copyWith(
      fixedSize: const WidgetStatePropertyAll(
        Size.square(WorkspaceTokens.controlHeight),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

/// Open-page navigation, plus pin/close commands for the lone-tab state.
class TabsOverflowButton extends StatelessWidget {
  const TabsOverflowButton({
    super.key,
    this.onIndexChanged,
    this.includeTabActions = false,
  });

  final ValueChanged<int>? onIndexChanged;
  final bool includeTabActions;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _show(context),
        },
        child: IconButton(
          key: const ValueKey('open-tabs-menu'),
          icon: const DSWorkspaceGlyph.named('caret-down'),
          tooltip: LocaleKeys.workspaceChrome_openTabs.tr(),
          style: _tabControlStyle(context),
          onPressed: () => _show(context),
        ),
      );

  void _show(BuildContext context) => unawaited(
        showAppMenuForWidget<void>(
          context: context,
          entries: entries(context),
          width: 280,
        ),
      );

  List<AppMenuEntry> entries(BuildContext context) {
    final tabs = context.read<TabsBloc>();
    final state = tabs.state;
    final current = state.currentPageManager;
    return [
      AppMenuHeader(LocaleKeys.workspaceChrome_openTabs.tr()),
      for (final pm in state.pageManagers)
        AppMenuItem(
          label: pm.plugin.widgetBuilder.viewName ??
              LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
          iconWidget: DSWorkspaceGlyph.named(
            pm.isPinned ? 'push-pin' : 'file-text',
            size: 17,
          ),
          selected: pm == current,
          onSelected: () {
            if (!context.mounted || tabs.isClosed) return;
            final index = tabs.state.pageManagers.indexOf(pm);
            if (index < 0) return;
            if (onIndexChanged != null) {
              onIndexChanged!(index);
            } else {
              FocusScope.of(context).unfocus();
              tabs.add(TabsEvent.selectTab(index));
            }
          },
        ),
      if (includeTabActions) ...[
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.disclosureAction_openNewTab.tr(),
          iconWidget: const DSWorkspaceGlyph.named('plus', size: 17),
          onSelected: () {
            if (context.mounted) unawaited(openWorkspaceTab(context));
          },
        ),
        AppMenuItem(
          label: current.isPinned
              ? LocaleKeys.tabMenu_unpinTab.tr()
              : LocaleKeys.tabMenu_pinTab.tr(),
          iconWidget: const DSWorkspaceGlyph.named('push-pin', size: 17),
          onSelected: () {
            if (!tabs.isClosed && tabs.state.pageManagers.contains(current)) {
              tabs.add(TabsEvent.togglePin(current.tabId));
            }
          },
        ),
        AppMenuItem(
          label: LocaleKeys.tabMenu_close.tr(),
          iconWidget: const DSWorkspaceGlyph.named('x', size: 17),
          onSelected: () {
            if (!tabs.isClosed && tabs.state.pageManagers.contains(current)) {
              tabs.add(TabsEvent.closeTab(current.tabId));
            }
          },
        ),
        AppMenuItem(
          label: LocaleKeys.tabMenu_closeOthers.tr(),
          enabled: state.pageManagers.any(
            (manager) => manager != current && !manager.isPinned,
          ),
          onSelected: () {
            if (!tabs.isClosed && tabs.state.pageManagers.contains(current)) {
              tabs.add(TabsEvent.closeOtherTabs(current.tabId));
            }
          },
        ),
      ],
    ];
  }
}
