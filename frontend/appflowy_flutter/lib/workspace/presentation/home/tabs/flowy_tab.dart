import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
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
  });

  final PageManager pageManager;
  final bool isCurrent;
  final VoidCallback onTap;

  /// Signifies whether all tabs are pinned
  ///
  final bool isAllPinned;

  @override
  State<FlowyTab> createState() => _FlowyTabState();
}

class _FlowyTabState extends State<FlowyTab> {
  final controller = PopoverController();
  final _closeButtonKey = GlobalKey();
  bool _focused = false;

  @override
  void dispose() {
    controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final surface = palette?.surface ?? theme.colorScheme.surface;
    final accent = palette?.accent ?? theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
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
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _focused ? accent : accent.withValues(alpha: 0),
              ),
            ),
            child: _wrapInTooltip(
              widget.pageManager.plugin.widgetBuilder.viewName,
              child: FlowyHover(
                resetHoverOnRebuild: false,
                style: HoverStyle(
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor:
                      widget.isCurrent ? surface : surface.withValues(alpha: 0),
                  hoverColor: widget.isCurrent
                      ? surface
                      : palette?.hover ?? theme.hoverColor,
                ),
                builder: (context, isHovering) => AppFlowyPopover(
                  controller: controller,
                  offset: const Offset(4, 4),
                  triggerActions: PopoverTriggerFlags.secondaryClick,
                  showAtCursor: true,
                  popupBuilder: (_) => BlocProvider.value(
                    value: context.read<TabsBloc>(),
                    child: TabMenu(
                      controller: controller,
                      pageId: widget.pageManager.plugin.id,
                      isPinned: widget.pageManager.isPinned,
                      isAllPinned: widget.isAllPinned,
                    ),
                  ),
                  child: ChangeNotifierProvider.value(
                    value: widget.pageManager.notifier,
                    child: Consumer<PageNotifier>(
                      builder: (context, value, _) => Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.pageManager.isPinned ? 6 : 10,
                        ),
                        // We use a Listener to avoid gesture detector onPanStart debounce
                        child: Listener(
                          onPointerDown: (event) {
                            final closeVisible =
                                isHovering || _focused || widget.isCurrent;
                            if (event.buttons == kPrimaryButton &&
                                !(closeVisible &&
                                    _isCloseTarget(event.position))) {
                              widget.onTap();
                            } else if (event.buttons == kMiddleMouseButton &&
                                !widget.pageManager.isPinned) {
                              _closeTab(context);
                            }
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            // Claim taps, but leave dragging to the tab strip's
                            // reorder recognizer (and trackpad panning to scroll).
                            onTap: () {},
                            child: SizedBox(
                              height: HomeSizes.tabBarHeight - 8,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: widget.pageManager.notifier
                                        .tabBarWidget(
                                      widget.pageManager.plugin.id,
                                      widget.pageManager.isPinned,
                                    ),
                                  ),
                                  if (!widget.pageManager.isPinned) ...[
                                    const SizedBox(width: 4),
                                    Visibility(
                                      visible: isHovering ||
                                          _focused ||
                                          widget.isCurrent,
                                      maintainSize: true,
                                      maintainAnimation: true,
                                      maintainState: true,
                                      child: SizedBox(
                                        key: _closeButtonKey,
                                        width: 24,
                                        height: 24,
                                        child: FlowyIconButton(
                                          width: 24,
                                          height: 24,
                                          tooltipText:
                                              LocaleKeys.tabMenu_close.tr(),
                                          onPressed: () => _closeTab(context),
                                          icon: const FlowySvg(
                                            FlowySvgs.close_s,
                                            size: Size.square(16),
                                          ),
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
      .add(TabsEvent.closeTab(widget.pageManager.plugin.id));

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
        Opacity(
          opacity: isPinned ? 0.5 : 1,
          child: _wrapInTooltip(
            shouldWrap: isPinned,
            message: LocaleKeys.tabMenu_closeDisabledHint.tr(),
            child: FlowyButton(
              text: FlowyText.regular(LocaleKeys.tabMenu_close.tr()),
              onTap: () => _closeTab(context),
              disable: isPinned,
            ),
          ),
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
