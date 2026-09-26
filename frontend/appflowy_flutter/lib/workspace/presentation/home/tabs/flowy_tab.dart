import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

class FlowyTab extends StatefulWidget {
  const FlowyTab({
    super.key,
    required this.pageManager,
    required this.isCurrent,
    required this.onTap,
    required this.isAllPinned,
    this.showSeparator = false,
    this.canClose = true,
  });

  final PageManager pageManager;
  final bool isCurrent;
  final VoidCallback onTap;

  /// Signifies whether all tabs are pinned
  ///
  final bool isAllPinned;
  final bool showSeparator;
  // The drag feedback is rebuilt in the root overlay, outside TabsBloc.
  // Carry this presentation value rather than looking the bloc up in build.
  final bool canClose;

  @override
  State<FlowyTab> createState() => _FlowyTabState();
}

class _FlowyTabState extends State<FlowyTab> {
  final controller = PopoverController();
  final _closeButtonKey = GlobalKey();
  bool _focused = false;
  bool _hasFocus = false;

  @override
  void dispose() {
    controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final surface = palette.background;
    final accent = palette.focus;
    final canClose = widget.canClose;
    const corners = BorderRadius.vertical(
      top: Radius.circular(HomeSizes.tabCornerRadius),
    );
    return Padding(
      padding: EdgeInsets.zero,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onFocusChange: (value) => setState(() => _hasFocus = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          selected: widget.isCurrent,
          onTap: widget.onTap,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: corners,
              border: Border.all(
                color: _focused ? accent : accent.withValues(alpha: 0),
              ),
            ),
            child: DecoratedBox(
              key: const ValueKey('workspace-tab-face'),
              decoration: BoxDecoration(
                color:
                    widget.isCurrent ? surface : surface.withValues(alpha: 0),
                borderRadius: corners,
              ),
              child: _wrapInTooltip(
                widget.pageManager.plugin.widgetBuilder.viewName,
                child: FlowyHover(
                  resetHoverOnRebuild: false,
                  style: HoverStyle(
                    borderRadius: corners,
                    backgroundColor: widget.isCurrent
                        ? surface
                        : surface.withValues(alpha: 0),
                    hoverColor: widget.isCurrent ? surface : palette.hover,
                  ),
                  builder: (context, isHovering) {
                    final closeVisible = canClose;
                    return Stack(
                      children: [
                        AppFlowyPopover(
                          controller: controller,
                          offset: const Offset(4, 4),
                          triggerActions: PopoverTriggerFlags.secondaryClick,
                          showAtCursor: true,
                          popupBuilder: (_) => BlocProvider.value(
                            value: context.read<TabsBloc>(),
                            child: TabMenu(
                              controller: controller,
                              pageId: widget.pageManager.tabId,
                              isPinned: widget.pageManager.isPinned,
                              isAllPinned: widget.isAllPinned,
                            ),
                          ),
                          child: ChangeNotifierProvider.value(
                            value: widget.pageManager.notifier,
                            child: Consumer<PageNotifier>(
                              builder: (context, value, _) => Listener(
                                // Select on down without delaying a reorder;
                                // a close target must not select a background tab.
                                onPointerDown: (event) {
                                  if (event.buttons == kPrimaryButton &&
                                      !(closeVisible &&
                                          _isCloseTarget(event.position))) {
                                    widget.onTap();
                                  } else if (event.buttons ==
                                          kMiddleMouseButton &&
                                      canClose) {
                                    _closeTab(context);
                                  }
                                },
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  // Reordering and trackpad panning keep their
                                  // existing recognizers in the strip above.
                                  onTap: () {},
                                  child: SizedBox(
                                    height: HomeSizes.tabHeight,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: widget.pageManager.isPinned
                                            ? 6
                                            : 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: DefaultTextStyle(
                                              style: WorkspaceTypography.style(
                                                context,
                                                WorkspaceTextRole.metadata,
                                                color: widget.isCurrent
                                                    ? palette.primaryText
                                                    : palette.secondaryText,
                                              ).copyWith(
                                                fontSize: 13,
                                                height: 1.2,
                                              ),
                                              child: widget.pageManager.notifier
                                                  .tabBarWidget(
                                                widget.pageManager.plugin.id,
                                                widget.pageManager.isPinned,
                                              ),
                                            ),
                                          ),
                                          if (canClose) ...[
                                            const SizedBox(width: 4),
                                            Visibility(
                                              visible: closeVisible,
                                              maintainSize: true,
                                              maintainAnimation: true,
                                              maintainState: true,
                                              child: SizedBox(
                                                key: _closeButtonKey,
                                                width: 24,
                                                height: 24,
                                                child: IconButton(
                                                  tooltip: LocaleKeys
                                                      .tabMenu_close
                                                      .tr(),
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints
                                                          .tightFor(
                                                    width: 24,
                                                    height: 24,
                                                  ),
                                                  style: IconButton.styleFrom(
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    foregroundColor:
                                                        palette.secondaryText,
                                                    hoverColor: palette.hover,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                  ),
                                                  onPressed: () =>
                                                      _closeTab(context),
                                                  icon: const DSWorkspaceGlyph
                                                      .named('x', size: 16),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.showSeparator && !isHovering && !_hasFocus)
                          PositionedDirectional(
                            end: 0,
                            top: 11,
                            bottom: 11,
                            child: IgnorePointer(
                              child: SizedBox(
                                width: 1,
                                child: ColoredBox(
                                  color: palette.border.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isCloseTarget(Offset globalPosition) {
    final box =
        _closeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    return box != null &&
        box.hasSize &&
        (Offset.zero & box.size).contains(box.globalToLocal(globalPosition));
  }

  void _closeTab(BuildContext context) => context
      .read<TabsBloc>()
      .add(TabsEvent.closeTab(widget.pageManager.tabId));

  Widget _wrapInTooltip(String? viewName, {required Widget child}) {
    if (viewName != null) {
      return FlowyTooltip(
        message: viewName,
        child: child,
      );
    }

    return child;
  }
}

@visibleForTesting
class TabMenu extends StatelessWidget {
  const TabMenu({
    super.key,
    required this.controller,
    required this.pageId,
    required this.isPinned,
    required this.isAllPinned,
  });

  final PopoverController controller;
  final String pageId;
  final bool isPinned;
  final bool isAllPinned;

  @override
  Widget build(BuildContext context) {
    return SeparatedColumn(
      separatorBuilder: () => const VSpace(4),
      mainAxisSize: MainAxisSize.min,
      children: [
        FlowyButton(
          text: FlowyText.regular(LocaleKeys.tabMenu_close.tr()),
          onTap: () => _closeTab(context),
        ),
        Opacity(
          opacity: isAllPinned ? 0.5 : 1,
          child: _wrapInTooltip(
            shouldWrap: true,
            message: isAllPinned
                ? LocaleKeys.tabMenu_closeOthersDisabledHint.tr()
                : LocaleKeys.tabMenu_closeOthersHint.tr(),
            child: FlowyButton(
              text: FlowyText.regular(
                LocaleKeys.tabMenu_closeOthers.tr(),
              ),
              onTap: () => _closeOtherTabs(context),
              disable: isAllPinned,
            ),
          ),
        ),
        const Divider(height: 0.5),
        FlowyButton(
          text: FlowyText.regular(
            isPinned
                ? LocaleKeys.tabMenu_unpinTab.tr()
                : LocaleKeys.tabMenu_pinTab.tr(),
          ),
          onTap: () => _togglePin(context),
        ),
      ],
    );
  }

  Widget _wrapInTooltip({
    required bool shouldWrap,
    String? message,
    required Widget child,
  }) {
    if (shouldWrap) {
      return FlowyTooltip(
        message: message,
        child: child,
      );
    }

    return child;
  }

  void _closeTab(BuildContext context) {
    context.read<TabsBloc>().add(TabsEvent.closeTab(pageId));
    controller.close();
  }

  void _closeOtherTabs(BuildContext context) {
    context.read<TabsBloc>().add(TabsEvent.closeOtherTabs(pageId));
    controller.close();
  }

  void _togglePin(BuildContext context) {
    context.read<TabsBloc>().add(TabsEvent.togglePin(pageId));
    controller.close();
  }
}
