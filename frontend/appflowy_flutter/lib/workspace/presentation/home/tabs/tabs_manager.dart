import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

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
        if (state.pages <= 1) {
          final space = const SizedBox.expand();
          return UniversalPlatform.isWindows
              ? DragToMoveArea(child: space)
              : const SizedBox.shrink();
        }

        return SizedBox(
          height: HomeSizes.tabBarHeight,
          child: MoveWindowDetector(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final room = math.max(0.0, constraints.maxWidth - 40);
                final pinned =
                    state.pageManagers.where((pm) => pm.isPinned).length;
                final regularWidth =
                    ((room - pinned * 48) / math.max(1, state.pages - pinned))
                        .clamp(144.0, HomeSizes.tabBarWidth)
                        .toDouble();
                final widths = [
                  for (final pm in state.pageManagers)
                    pm.isPinned ? 48.0 : regularWidth,
                ];
                final total = widths.fold(0.0, (sum, width) => sum + width);
                _revealCurrent(state.currentIndex, widths);

                return Row(
                  children: [
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
                          onReorderStart: (_) => _dragging = true,
                          onReorderEnd: (_) => _dragging = false,
                          onReorder: (oldIndex, newIndex) {
                            _dragging = false;
                            context
                                .read<TabsBloc>()
                                .reorderTab(oldIndex, newIndex);
                          },
                          proxyDecorator: (child, index, animation) {
                            final palette =
                                PremiumThemeExtension.maybeOf(context);
                            return Material(
                              color: palette?.sidebar ??
                                  Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
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
                                  onTap: () => widget.onIndexChanged(index),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: UniversalPlatform.isWindows
                          ? DragToMoveArea(child: const SizedBox.expand())
                          : const SizedBox.expand(),
                    ),
                    AppMenuIconButton(
                      key: const ValueKey('open-tabs-menu'),
                      icon: Icons.keyboard_arrow_down_rounded,
                      tooltip: LocaleKeys.workspaceChrome_openTabs.tr(),
                      size: 32,
                      width: 280,
                      entries: () => [
                        AppMenuHeader(LocaleKeys.workspaceChrome_openTabs.tr()),
                        for (final pm
                            in context.read<TabsBloc>().state.pageManagers)
                          AppMenuItem(
                            label: pm.plugin.widgetBuilder.viewName ??
                                LocaleKeys.menuAppHeader_defaultNewPageName
                                    .tr(),
                            icon: pm.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.tab_rounded,
                            selected: pm ==
                                context
                                    .read<TabsBloc>()
                                    .state
                                    .currentPageManager,
                            onSelected: () {
                              if (!mounted) return;
                              final index = context
                                  .read<TabsBloc>()
                                  .state
                                  .pageManagers
                                  .indexOf(pm);
                              if (index >= 0) widget.onIndexChanged(index);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
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
          index >= widths.length) {
        return;
      }
      final position = _scrollController.position;
      final start = widths.take(index).fold(0.0, (sum, width) => sum + width);
      final end = start + widths[index];
      final target = (start < position.pixels
              ? start
              : end > position.pixels + position.viewportDimension
                  ? end - position.viewportDimension
                  : position.pixels)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 0.5) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(target);
      } else {
        unawaited(
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }
}
