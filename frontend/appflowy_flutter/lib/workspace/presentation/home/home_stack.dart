import 'dart:async';
import 'dart:math';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_host.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/startup_profile.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/home/home_bloc.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/encryption/protected_view_gate.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/navigation.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:appflowy/workspace/presentation/home/workspace_navigation_controls.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderIndexedStack;
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

import 'home_layout.dart';

typedef NavigationCallback = void Function(String id);

abstract class HomeStackDelegate {
  void didDeleteStackWidget(ViewPB view, int? index);
}

class HomeStack extends StatefulWidget {
  const HomeStack({
    super.key,
    required this.delegate,
    required this.layout,
    required this.userProfile,
  });

  final HomeStackDelegate delegate;
  final HomeLayout layout;
  final UserProfilePB userProfile;

  @override
  State<HomeStack> createState() => _HomeStackState();
}

class _HomeStackState extends State<HomeStack> with WindowListener {
  @override
  Widget build(BuildContext context) {
    return BlocProvider<TabsBloc>.value(
      value: getIt<TabsBloc>(),
      child: BlocConsumer<TabsBloc, TabsState>(
        listenWhen: (previous, current) =>
            previous.currentPageManager != current.currentPageManager,
        listener: (context, _) => FocusScope.of(context).unfocus(),
        builder: (context, state) => Column(
          children: [
            HistorySwipeExclusion(
              // The shell (and its tab scroll controller) survives selection.
              // Only the path below is keyed to the borrowed page notifier.
              child: ChangeNotifierProvider<PageNotifier>.value(
                value: state.currentPageManager.notifier,
                child: HomeTopBar(
                  layout: widget.layout,
                  tabs: _buildTabs(context),
                ),
              ),
            ),
            Expanded(
              child: HistorySwipePageSurface(
                child: _PageHostIndexedStack(
                  index: state.currentIndex,
                  children: state.pageManagers
                      .map(
                        (pm) => LayoutBuilder(
                          // Moving tabs must move the existing editor subtree,
                          // not reassign its state to whichever tab replaced it.
                          key: ObjectKey(pm),
                          builder: (context, constraints) {
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      // Chrome belongs to the shell, not the
                                      // selected page. Keep this column/slot
                                      // stable so tab/sidebar changes never
                                      // reparent the editor below it.
                                      const SizedBox.shrink(),
                                      Expanded(
                                        child: PageStack(
                                          pageManager: pm,
                                          delegate: widget.delegate,
                                          userProfile: widget.userProfile,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                HistorySwipeExclusion(
                                  child: SecondaryView(
                                    pageManager: pm,
                                    adaptedPercentageWidth:
                                        constraints.maxWidth * 3 / 7,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) => TabsManager(
        onIndexChanged: (index) {
          final tabs = context.read<TabsBloc>();
          if (tabs.state.currentIndex != index) {
            FocusScope.of(context).unfocus();
            tabs.add(TabsEvent.selectTab(index));
          }
        },
      );

  @override
  void onWindowFocus() {
    // https://pub.dev/packages/window_manager#windows
    // must call setState once when the window is focused
    setState(() {});
  }
}

/// IndexedStack inserts unkeyed Visibility wrappers above its children. A key
/// on the page below those wrappers cannot retain it when tabs move. Key the
/// wrappers at the sibling reconciliation boundary instead, without GlobalKey
/// reparenting or changing indexed layout, painting, semantics or visibility.
class _PageHostIndexedStack extends Stack {
  _PageHostIndexedStack({
    required this.index,
    required List<Widget> children,
  }) : super(
          children: [
            for (var i = 0; i < children.length; i++)
              Visibility.maintain(
                key: children[i].key,
                visible: i == index,
                child: children[i],
              ),
          ],
        );

  final int index;

  @override
  RenderIndexedStack createRenderObject(BuildContext context) =>
      RenderIndexedStack(
        index: index,
        alignment: alignment,
        textDirection: Directionality.of(context),
        fit: fit,
        clipBehavior: clipBehavior,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderIndexedStack renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.index = index;
  }

  @override
  MultiChildRenderObjectElement createElement() =>
      _PageHostIndexedStackElement(this);
}

class _PageHostIndexedStackElement extends MultiChildRenderObjectElement {
  _PageHostIndexedStackElement(_PageHostIndexedStack super.widget);

  @override
  _PageHostIndexedStack get widget => super.widget as _PageHostIndexedStack;

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    if (children.isNotEmpty) visitor(children.elementAt(widget.index));
  }
}

class PageStack extends StatefulWidget {
  const PageStack({
    super.key,
    required this.pageManager,
    required this.delegate,
    required this.userProfile,
  });

  final PageManager pageManager;
  final HomeStackDelegate delegate;
  final UserProfilePB userProfile;

  @override
  State<PageStack> createState() => _PageStackState();
}

class _PageStackState extends State<PageStack>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      key: const ValueKey('workspace-page-canvas'),
      color: WorkspacePalette.of(context).background,
      child: FocusTraversalGroup(
        child: ContextualFindScope(
          child: widget.pageManager.stackWidget(
            userProfile: widget.userProfile,
            onDeleted: (view, index) {
              widget.delegate.didDeleteStackWidget(view, index);
            },
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class SecondaryView extends StatefulWidget {
  const SecondaryView({
    super.key,
    required this.pageManager,
    required this.adaptedPercentageWidth,
  });

  final PageManager pageManager;
  final double adaptedPercentageWidth;

  @override
  State<SecondaryView> createState() => _SecondaryViewState();
}

class _SecondaryViewState extends State<SecondaryView>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final overlayController = OverlayPortalController();
  final layerLink = LayerLink();

  late final ValueNotifier<double> widthNotifier;

  late final AnimationController animationController;
  late final CurvedAnimation curveAnimation;
  late Animation<double> widthAnimation;
  late final Animation<Offset> offsetAnimation;

  late bool hasSecondaryView;

  @override
  void initState() {
    super.initState();
    widget.pageManager.showSecondaryPluginNotifier
        .addListener(onShowSecondaryChanged);
    final width = widget.pageManager.showSecondaryPluginNotifier.value
        ? max(450.0, widget.adaptedPercentageWidth)
        : 0.0;
    widthNotifier = ValueNotifier<double>(width)
      ..addListener(updateWidthAnimation);

    animationController = AnimationController(
      duration: WorkspaceTokens.transitionDuration,
      value: widget.pageManager.showSecondaryPluginNotifier.value ? 1 : 0,
      vsync: this,
    );
    // Reuse one curve: allocating a CurvedAnimation on every resize leaves
    // another status listener attached to the controller each time.
    curveAnimation = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOut,
    );

    widthAnimation = Tween<double>(
      begin: 0.0,
      end: width,
    ).animate(curveAnimation);
    offsetAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(curveAnimation);

    widget.pageManager.secondaryNotifier.addListener(onSecondaryViewChanged);
    onSecondaryViewChanged();

    overlayController.show();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    animationController.duration = WorkspaceTokens.motion(
      context,
      WorkspaceTokens.transitionDuration,
    );
    if (animationController.duration == Duration.zero &&
        animationController.isAnimating) {
      animationController.value =
          widget.pageManager.showSecondaryPluginNotifier.value ? 1 : 0;
    }
  }

  @override
  void dispose() {
    widget.pageManager.showSecondaryPluginNotifier
        .removeListener(onShowSecondaryChanged);
    widget.pageManager.secondaryNotifier.removeListener(onSecondaryViewChanged);
    curveAnimation.dispose();
    animationController.dispose();
    widthNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLightMode = Theme.of(context).isLightMode;
    return OverlayPortal(
      controller: overlayController,
      overlayChildBuilder: (context) {
        return ValueListenableBuilder(
          valueListenable: widget.pageManager.showSecondaryPluginNotifier,
          builder: (context, isShowing, child) {
            return CompositedTransformFollower(
              link: layerLink,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0.0, 120.0),
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: AnimatedSwitcher(
                  duration: WorkspaceTokens.motion(
                    context,
                    WorkspaceTokens.hoverDuration,
                  ),
                  transitionBuilder: (child, animation) {
                    return NonClippingSizeTransition(
                      sizeFactor: animation,
                      axis: Axis.horizontal,
                      axisAlignment: -1,
                      child: child,
                    );
                  },
                  child: isShowing || !hasSecondaryView
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: () => widget.pageManager
                              .showSecondaryPluginNotifier.value = true,
                          child: Container(
                            height: 36,
                            width: 36,
                            decoration: BoxDecoration(
                              borderRadius: getBorderRadius(),
                              color: WorkspacePalette.of(context).background,
                              boxShadow: [
                                BoxShadow(
                                  offset: const Offset(0, 4),
                                  blurRadius: 20,
                                  color: isLightMode
                                      ? const Color(0x1F1F2329)
                                      : Theme.of(context)
                                          .shadowColor
                                          .withValues(alpha: 0.08),
                                ),
                              ],
                            ),
                            child: FlowyHover(
                              style: HoverStyle(
                                borderRadius: getBorderRadius(),
                                border: getBorder(context),
                              ),
                              child: const Center(
                                child: FlowySvg(
                                  FlowySvgs.rename_s,
                                  size: Size.square(16.0),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            );
          },
        );
      },
      child: CompositedTransformTarget(
        link: layerLink,
        child: Container(
          color: WorkspacePalette.of(context).background,
          child: FocusTraversalGroup(
            child: ValueListenableBuilder(
              valueListenable: widthNotifier,
              builder: (context, value, child) {
                return AnimatedBuilder(
                  animation: Listenable.merge([
                    widthAnimation,
                    offsetAnimation,
                  ]),
                  builder: (context, child) {
                    return Container(
                      width: widthAnimation.value,
                      alignment: Alignment(
                        offsetAnimation.value.dx,
                        offsetAnimation.value.dy,
                      ),
                      child: OverflowBox(
                        alignment: AlignmentDirectional.centerStart,
                        maxWidth: value,
                        child: SecondaryViewResizer(
                          pageManager: widget.pageManager,
                          notifier: widthNotifier,
                          child: Column(
                            children: [
                              widget.pageManager.stackSecondaryTopBar(value),
                              Expanded(
                                child: widget.pageManager
                                    .stackSecondaryWidget(value),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  BoxBorder getBorder(BuildContext context) {
    final isLightMode = Theme.of(context).isLightMode;
    final borderSide = BorderSide(
      color: isLightMode
          ? const Color(0x141F2329)
          : Theme.of(context).dividerColor,
    );

    return Border(
      left: borderSide,
      top: borderSide,
      bottom: borderSide,
    );
  }

  BorderRadius getBorderRadius() {
    return const BorderRadius.only(
      topLeft: Radius.circular(12.0),
      bottomLeft: Radius.circular(12.0),
    );
  }

  void onSecondaryViewChanged() {
    hasSecondaryView = widget.pageManager.secondaryNotifier.plugin.pluginType !=
        PluginType.blank;
  }

  void onShowSecondaryChanged() async {
    final showing = widget.pageManager.showSecondaryPluginNotifier.value;
    if (showing) {
      widthNotifier.value = max(450.0, widget.adaptedPercentageWidth);
    }
    updateWidthAnimation();
    try {
      await (showing
              ? animationController.forward()
              : animationController.reverse())
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted &&
        !showing &&
        !widget.pageManager.showSecondaryPluginNotifier.value) {
      setState(() => widthNotifier.value = 0.0);
    }
  }

  void updateWidthAnimation() {
    widthAnimation = Tween<double>(
      begin: 0.0,
      end: widthNotifier.value,
    ).animate(curveAnimation);
  }

  @override
  bool get wantKeepAlive => true;
}

class SecondaryViewResizer extends StatefulWidget {
  const SecondaryViewResizer({
    super.key,
    required this.pageManager,
    required this.notifier,
    required this.child,
  });

  final PageManager pageManager;
  final ValueNotifier<double> notifier;
  final Widget child;

  @override
  State<SecondaryViewResizer> createState() => _SecondaryViewResizerState();
}

class _SecondaryViewResizerState extends State<SecondaryViewResizer> {
  final overlayController = OverlayPortalController();
  final layerLink = LayerLink();

  bool isHover = false;
  bool isDragging = false;
  Timer? showHoverTimer;

  @override
  void dispose() {
    showHoverTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    overlayController.show();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: overlayController,
      overlayChildBuilder: (context) {
        // A closed pane must not leave an invisible resize target over the
        // live page, nor reserve a one-pixel rule in a zero-width row.
        if (widget.notifier.value <= 0) return const SizedBox.shrink();
        return CompositedTransformFollower(
          showWhenUnlinked: false,
          link: layerLink,
          targetAnchor: Alignment.center,
          followerAnchor: Alignment.center,
          child: Center(
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              onEnter: (_) {
                showHoverTimer?.cancel();
                showHoverTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) setState(() => isHover = true);
                });
              },
              onExit: (_) {
                showHoverTimer?.cancel();
                setState(() => isHover = false);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => setState(() => isDragging = true),
                onHorizontalDragUpdate: (details) {
                  final newWidth = MediaQuery.sizeOf(context).width -
                      details.globalPosition.dx;
                  if (newWidth >= 450.0) {
                    widget.notifier.value = newWidth;
                  }
                },
                onHorizontalDragEnd: (_) => setState(() => isDragging = false),
                onHorizontalDragCancel: () =>
                    setState(() => isDragging = false),
                child: TweenAnimationBuilder(
                  tween: ColorTween(
                    end: isHover || isDragging
                        ? WorkspacePalette.of(context).focus
                        : WorkspacePalette.of(context)
                            .focus
                            .withValues(alpha: 0),
                  ),
                  duration: WorkspaceTokens.motion(
                    context,
                    WorkspaceTokens.hoverDuration,
                  ),
                  builder: (context, color, child) {
                    return SizedBox(
                      width: 11,
                      child: Center(
                        child: Container(
                          color: color,
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CompositedTransformTarget(
            link: layerLink,
            child: Container(
              width: widget.notifier.value > 0 ? 1 : 0,
              color: WorkspacePalette.of(context).border,
            ),
          ),
          Flexible(child: widget.child),
        ],
      ),
    );
  }
}

class FadingIndexedStack extends StatefulWidget {
  const FadingIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 250),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  FadingIndexedStackState createState() => FadingIndexedStackState();
}

class FadingIndexedStackState extends State<FadingIndexedStack> {
  double _targetOpacity = 1;

  @override
  void initState() {
    super.initState();
    initToastWithContext(context);
  }

  @override
  void didUpdateWidget(FadingIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _targetOpacity = 0;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) {
        if (mounted) setState(() => _targetOpacity = 1);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: _targetOpacity > 0
          ? WorkspaceTokens.motion(context, widget.duration)
          : Duration.zero,
      tween: Tween(begin: 0, end: _targetOpacity),
      builder: (_, value, child) => Opacity(opacity: value, child: child),
      child: IndexedStack(index: widget.index, children: widget.children),
    );
  }
}

abstract mixin class NavigationItem {
  String? get viewName;
  Widget get leftBarItem;
  Widget? get rightBarItem => null;
  Widget tabBarItem(String pluginId, [bool shortForm = false]);

  NavigationCallback get action => (id) => throw UnimplementedError();
}

class PageNotifier extends ChangeNotifier {
  PageNotifier({Plugin? plugin})
      : _plugin = plugin ?? makePlugin(pluginType: PluginType.blank);

  Plugin _plugin;
  bool _disposed = false;

  Widget get titleWidget => _plugin.widgetBuilder.leftBarItem;

  Widget tabBarWidget(
    String pluginId, [
    bool shortForm = false,
  ]) =>
      _plugin.widgetBuilder.tabBarItem(pluginId, shortForm);

  void setPlugin(
    Plugin newPlugin, {
    required bool setLatest,
    bool disposeExisting = true,
  }) {
    if (!identical(newPlugin, plugin) && disposeExisting) {
      _plugin.dispose();
    }

    // Set the plugin view as the latest view.
    if (setLatest && newPlugin.id.isNotEmpty) {
      FolderEventSetLatestView(ViewIdPB(value: newPlugin.id)).send();
    }

    _plugin = newPlugin;
    notifyListeners();
  }

  Plugin get plugin => _plugin;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _plugin.dispose();
    } finally {
      super.dispose();
    }
  }
}

// PageManager manages the view for one Tab
class PageManager {
  PageManager({Plugin? plugin})
      : _notifier = PageNotifier(plugin: plugin),
        _secondaryNotifier = PageNotifier(plugin: BlankPagePlugin());

  static int _nextTabId = 0;
  final String tabId = 'workspace-tab-${_nextTabId++}';

  final PageNotifier _notifier;
  final PageNotifier _secondaryNotifier;
  bool _disposed = false;

  PageNotifier get notifier => _notifier;
  PageNotifier get secondaryNotifier => _secondaryNotifier;

  bool isPinned = false;

  final showSecondaryPluginNotifier = ValueNotifier(false);

  Plugin get plugin => _notifier.plugin;

  void setPlugin(Plugin newPlugin, bool setLatest, [bool init = true]) {
    if (init && !identical(newPlugin, plugin)) {
      newPlugin.init();
    }
    _notifier.setPlugin(newPlugin, setLatest: setLatest);
  }

  void setSecondaryPlugin(Plugin newPlugin) {
    if (!identical(newPlugin, _secondaryNotifier.plugin)) {
      newPlugin.init();
    }
    _secondaryNotifier.setPlugin(newPlugin, setLatest: false);
  }

  void expandSecondaryPlugin() {
    _notifier.setPlugin(_secondaryNotifier.plugin, setLatest: true);
    _secondaryNotifier.setPlugin(
      BlankPagePlugin(),
      setLatest: false,
      disposeExisting: false,
    );
  }

  void showSecondaryPlugin() {
    showSecondaryPluginNotifier.value = true;
  }

  void hideSecondaryPlugin() {
    showSecondaryPluginNotifier.value = false;
  }

  Widget stackTopBar({required HomeLayout layout}) {
    return ChangeNotifierProvider.value(
      key: ObjectKey(_notifier),
      value: _notifier,
      child: HomeTopBar(layout: layout),
    );
  }

  Widget stackWidget({
    required UserProfilePB userProfile,
    required Function(ViewPB, int?) onDeleted,
  }) {
    return ChangeNotifierProvider.value(
      value: _notifier,
      child: Consumer<PageNotifier>(
        builder: (_, notifier, __) {
          if (notifier.plugin.pluginType == PluginType.blank) {
            return const BlankPage();
          }

          return FadingIndexedStack(
            index: getIt<PluginSandbox>().indexOf(notifier.plugin.pluginType),
            children: getIt<PluginSandbox>().supportPluginTypes.map(
              (pluginType) {
                if (pluginType == notifier.plugin.pluginType) {
                  final builder = notifier.plugin.widgetBuilder;
                  final pluginWidget = builder.buildWidget(
                    context: PluginContext(
                      onDeleted: onDeleted,
                      userProfile: userProfile,
                    ),
                    shrinkWrap: false,
                  );

                  return Padding(
                    padding: builder.contentPadding,
                    // Every kind of page gets its history here, so it is one
                    // feature rather than one per plugin. The same is true of
                    // the workspace key: one wrapper covers a protected page,
                    // table, folder, collection or file.
                    child: ProtectedViewGate(
                      viewId: notifier.plugin.id,
                      child: PageVersionHost(
                        viewId: notifier.plugin.id,
                        child: StartupProfileFrame(
                          phase: 'page_host_frame',
                          child: pluginWidget,
                        ),
                      ),
                    ),
                  );
                }

                return const BlankPage();
              },
            ).toList(),
          );
        },
      ),
    );
  }

  Widget stackSecondaryWidget(double width) {
    return ValueListenableBuilder(
      valueListenable: showSecondaryPluginNotifier,
      builder: (context, value, child) {
        if (width == 0.0) {
          return const SizedBox.shrink();
        }

        return child!;
      },
      child: ChangeNotifierProvider.value(
        value: _secondaryNotifier,
        child: Selector<PageNotifier, PluginWidgetBuilder>(
          selector: (context, notifier) => notifier.plugin.widgetBuilder,
          builder: (_, widgetBuilder, __) {
            return widgetBuilder.buildWidget(
              context: PluginContext(),
              shrinkWrap: false,
            );
          },
        ),
      ),
    );
  }

  Widget stackSecondaryTopBar(double width) {
    return ValueListenableBuilder(
      valueListenable: showSecondaryPluginNotifier,
      builder: (context, value, child) {
        if (width == 0.0) {
          return const SizedBox.shrink();
        }

        return child!;
      },
      child: ChangeNotifierProvider.value(
        value: _secondaryNotifier,
        child: Selector<PageNotifier, PluginWidgetBuilder>(
          selector: (context, notifier) => notifier.plugin.widgetBuilder,
          builder: (_, widgetBuilder, __) {
            return const HomeSecondaryTopBar();
          },
        ),
      ),
    );
  }

  void dispose() {
    // Immutable TabsState snapshots share managers. Releasing an old snapshot
    // must not dispose a closed tab's plugins a second time.
    if (_disposed) return;
    _disposed = true;
    try {
      _notifier.dispose();
    } finally {
      try {
        _secondaryNotifier.dispose();
      } finally {
        showSecondaryPluginNotifier.dispose();
      }
    }
  }
}

class HomeTopBar extends StatefulWidget {
  const HomeTopBar({super.key, required this.layout, this.tabs});

  final HomeLayout layout;
  final Widget? tabs;

  @override
  State<HomeTopBar> createState() => _HomeTopBarState();
}

class _HomeTopBarState extends State<HomeTopBar>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);

    final palette = WorkspacePalette.of(context);
    return Column(
      key: const ValueKey('workspace-shell-header'),
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowTitleBar(
          key: const ValueKey('workspace-title-bar'),
          height: HomeSizes.tabBarHeight,
          backgroundColor: SidebarPalette.of(context).background,
          showCaptionButtons:
              UniversalPlatform.isWindows || UniversalPlatform.isLinux,
          leftChildren: [
            SizedBox(width: widget.layout.menuSpacing),
            const WorkspaceNavigationControls(),
            const SizedBox(width: WorkspaceTokens.space1),
          ],
          title: widget.tabs ?? const WindowDragTarget(),
        ),
        PreviewToolbarRegion(
          child: ColoredBox(
            color: palette.background,
            child: SizedBox(
              key: const ValueKey('workspace-context-header'),
              height: HomeSizes.contextBarHeight,
              child: DefaultTextStyle(
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                ),
                child: Consumer<PageNotifier>(
                  builder: (context, notifier, _) {
                    final plugin = notifier.plugin;
                    final actions = plugin.widgetBuilder.rightBarItem;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(14) / 14;
                        final compact = constraints.maxWidth < 800 * textScale;
                        final actionWidth = actions == null
                            ? 0.0
                            : compact
                                ? WorkspaceTokens.controlHeight
                                : min(320.0, constraints.maxWidth * 0.25);
                        return Row(
                          children: [
                            const SizedBox(width: WorkspaceTokens.space3),
                            Expanded(
                              key: const ValueKey('workspace-context-path'),
                              child: Row(
                                key: ObjectKey(notifier),
                                children: const [FlowyNavigation()],
                              ),
                            ),
                            if (actions != null) ...[
                              const SizedBox(width: WorkspaceTokens.space1),
                              HomeContextActions(
                                source: notifier,
                                actionIdentity: plugin,
                                compact: compact,
                                maxWidth: actionWidth,
                                child: actions,
                              ),
                            ],
                            const SizedBox(width: WorkspaceTokens.space3),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// Plugin actions keep their own providers and callbacks. A narrow caption
/// presents them in a local popover rather than squeezing the breadcrumb or
/// introducing another toolbar band. Only chrome moves, never the page body.
class HomeContextActions extends StatefulWidget {
  const HomeContextActions({
    super.key,
    required this.source,
    required this.actionIdentity,
    required this.child,
    required this.compact,
    this.maxWidth = 400,
  });

  final PageNotifier source;

  /// The plugin owns the actions' providers. rightBarItem itself is rebuilt
  /// on ordinary shell updates and is not a page-lifetime identity.
  final Plugin actionIdentity;
  final Widget child;
  final bool compact;
  final double maxWidth;

  @override
  State<HomeContextActions> createState() => _HomeContextActionsState();
}

class _HomeContextActionsState extends State<HomeContextActions> {
  final _popover = PopoverController();
  VoidCallback? _releaseToolbar;
  Plugin? _openIdentity;
  int _popoverGeneration = 0;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_onSourceChanged);
  }

  @override
  void didUpdateWidget(HomeContextActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = !identical(oldWidget.source, widget.source);
    if (sourceChanged) {
      oldWidget.source.removeListener(_onSourceChanged);
      widget.source.addListener(_onSourceChanged);
    }
    if (sourceChanged ||
        !identical(oldWidget.actionIdentity, widget.actionIdentity) ||
        (oldWidget.compact && !widget.compact)) {
      _dismissPopover();
    }
  }

  @override
  void deactivate() {
    _active = false;
    _dismissPopover();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    widget.source.removeListener(_onSourceChanged);
    _dismissPopover();
    super.dispose();
  }

  bool get _sourceIsCurrent =>
      mounted &&
      _active &&
      widget.compact &&
      !widget.source._disposed &&
      identical(widget.source.plugin, widget.actionIdentity);

  void _onSourceChanged() {
    // Ctrl+N replaces the plugin without replacing its PageNotifier. Close
    // before the next overlay build can borrow the disposed plugin's blocs.
    if (!_sourceIsCurrent) _dismissPopover();
  }

  void _afterBuild(VoidCallback callback) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    } else {
      callback();
    }
  }

  void _releaseToolbarHold() {
    final release = _releaseToolbar;
    _releaseToolbar = null;
    if (release != null) _afterBuild(release);
  }

  void _dismissPopover() {
    final generation = ++_popoverGeneration;
    _openIdentity = null;
    _releaseToolbarHold();
    // LayoutBuilder can update this widget during layout. Neither the root
    // overlay nor an ancestor reveal scope may be invalidated at that point.
    _afterBuild(() {
      if (generation == _popoverGeneration) _popover.close();
    });
  }

  void _showPopover(PageNotifier source, Plugin identity) {
    if (!_sourceIsCurrent ||
        !identical(source, widget.source) ||
        !identical(identity, widget.actionIdentity)) {
      return;
    }
    _dismissPopover();
    final generation = _popoverGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sourceIsCurrent || generation != _popoverGeneration) return;
      _openIdentity = identity;
      // Programmatic PopoverController.show does not call onOpen.
      _releaseToolbar = PreviewToolbarRegion.hold(context);
      _popover.show();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _actions() => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: widget.child,
        ),
      );

  Widget _popupActions() {
    // An inserted overlay first builds on a later frame. Its source may have
    // been disposed even though the caption has not unmounted yet.
    if (!_sourceIsCurrent || !identical(_openIdentity, widget.actionIdentity)) {
      _dismissPopover();
      return const SizedBox.shrink();
    }
    // Overlays are outside the page's provider branch. Borrow the shell's
    // instances (never create/dispose them here), just as the plugin already
    // carries its own access/view blocs in rightBarItem.
    final page = context.read<PageNotifier?>();
    final tabs = context.read<TabsBloc?>();
    final home = context.read<HomeBloc?>();
    final settings = context.read<HomeSettingBloc?>();
    final workspace = context.read<UserWorkspaceBloc?>();
    final favorites = context.read<FavoriteBloc?>();
    final reminders = context.read<ReminderBloc?>();
    final providers = [
      if (page != null) ChangeNotifierProvider<PageNotifier>.value(value: page),
      if (tabs != null) BlocProvider<TabsBloc>.value(value: tabs),
      if (home != null) BlocProvider<HomeBloc>.value(value: home),
      if (settings != null)
        BlocProvider<HomeSettingBloc>.value(value: settings),
      if (workspace != null)
        BlocProvider<UserWorkspaceBloc>.value(value: workspace),
      if (favorites != null) BlocProvider<FavoriteBloc>.value(value: favorites),
      if (reminders != null) BlocProvider<ReminderBloc>.value(value: reminders),
    ];
    final child = SizedBox(
      width: min(360.0, max(0.0, MediaQuery.sizeOf(context).width - 48)),
      height: WorkspaceTokens.headerHeight,
      child: Center(child: _actions()),
    );
    return providers.isEmpty
        ? child
        : MultiProvider(providers: providers, child: child);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.compact) {
      return PreviewToolbar(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: _actions(),
        ),
      );
    }
    final source = widget.source;
    final identity = widget.actionIdentity;
    return AppFlowyPopover(
      controller: _popover,
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.bottomWithRightAligned,
      animationDuration: WorkspaceTokens.motion(
        context,
        WorkspaceTokens.entranceDuration,
      ),
      onClose: () {
        _popoverGeneration++;
        _openIdentity = null;
        _releaseToolbarHold();
      },
      popupBuilder: (_) => _popupActions(),
      child: SidebarIconButton(
        key: const ValueKey('workspace-context-actions'),
        icon: SidebarIcon.more,
        dimension: WorkspaceTokens.controlHeight,
        tooltip: LocaleKeys.button_more.tr(),
        onPressed: () => _showPopover(source, identity),
      ),
    );
  }
}

class HomeSecondaryTopBar extends StatelessWidget {
  const HomeSecondaryTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WorkspacePalette.of(context).background,
      ),
      height: WorkspaceTokens.headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HomeInsets.topBarTitleHorizontalPadding,
          vertical: HomeInsets.topBarTitleVerticalPadding,
        ),
        child: Row(
          children: [
            FlowyIconButton(
              width: 24,
              tooltipText: LocaleKeys.sideBar_closeSidebar.tr(),
              radius: const BorderRadius.all(Radius.circular(8.0)),
              icon: const FlowySvg(
                FlowySvgs.show_menu_s,
                size: Size.square(16),
              ),
              onPressed: () {
                getIt<TabsBloc>().add(const TabsEvent.closeSecondaryPlugin());
              },
            ),
            const HSpace(8.0),
            FlowyIconButton(
              width: 24,
              tooltipText: LocaleKeys.sideBar_expandSidebar.tr(),
              radius: const BorderRadius.all(Radius.circular(8.0)),
              icon: const FlowySvg(
                FlowySvgs.full_view_s,
                size: Size.square(16),
              ),
              onPressed: () {
                getIt<TabsBloc>().add(const TabsEvent.expandSecondaryPlugin());
              },
            ),
            Expanded(
              child: Consumer<PageNotifier>(
                builder: (context, notifier, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final plugin = notifier.plugin;
                    final actions = plugin.widgetBuilder.rightBarItem;
                    return Row(
                      children: [
                        const Expanded(child: WindowDragTarget()),
                        if (actions != null)
                          HomeContextActions(
                            source: notifier,
                            actionIdentity: plugin,
                            compact: constraints.maxWidth < 420,
                            maxWidth: constraints.maxWidth * 0.8,
                            child: actions,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A version of Flutter's built in SizeTransition widget that clips the child
/// more sparingly than the original.
class NonClippingSizeTransition extends AnimatedWidget {
  const NonClippingSizeTransition({
    super.key,
    this.axis = Axis.vertical,
    required Animation<double> sizeFactor,
    this.axisAlignment = 0.0,
    this.fixedCrossAxisSizeFactor,
    this.child,
  })  : assert(
          fixedCrossAxisSizeFactor == null || fixedCrossAxisSizeFactor >= 0.0,
        ),
        super(listenable: sizeFactor);

  /// [Axis.horizontal] if [sizeFactor] modifies the width, otherwise
  /// [Axis.vertical].
  final Axis axis;

  /// The animation that controls the (clipped) size of the child.
  ///
  /// The width or height (depending on the [axis] value) of this widget will be
  /// its intrinsic width or height multiplied by [sizeFactor]'s value at the
  /// current point in the animation.
  ///
  /// If the value of [sizeFactor] is less than one, the child will be clipped
  /// in the appropriate axis.
  Animation<double> get sizeFactor => listenable as Animation<double>;

  /// Describes how to align the child along the axis that [sizeFactor] is
  /// modifying.
  ///
  /// A value of -1.0 indicates the top when [axis] is [Axis.vertical], and the
  /// start when [axis] is [Axis.horizontal]. The start is on the left when the
  /// text direction in effect is [TextDirection.ltr] and on the right when it
  /// is [TextDirection.rtl].
  ///
  /// A value of 1.0 indicates the bottom or end, depending upon the [axis].
  ///
  /// A value of 0.0 (the default) indicates the center for either [axis] value.
  final double axisAlignment;

  /// The factor by which to multiply the cross axis size of the child.
  ///
  /// If the value of [fixedCrossAxisSizeFactor] is less than one, the child
  /// will be clipped along the appropriate axis.
  ///
  /// If `null` (the default), the cross axis size is as large as the parent.
  final double? fixedCrossAxisSizeFactor;

  /// The widget below this widget in the tree.
  ///
  /// {@macro flutter.widgets.ProxyWidget.child}
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final AlignmentDirectional alignment;
    final Edge edge;
    if (axis == Axis.vertical) {
      alignment = AlignmentDirectional(-1.0, axisAlignment);
      edge = switch (axisAlignment) { -1.0 => Edge.bottom, _ => Edge.top };
    } else {
      alignment = AlignmentDirectional(axisAlignment, -1.0);
      edge = switch (axisAlignment) { -1.0 => Edge.right, _ => Edge.left };
    }
    return ClipRect(
      clipper: EdgeRectClipper(edge: edge, margin: 20),
      child: Align(
        alignment: alignment,
        heightFactor: axis == Axis.vertical
            ? max(sizeFactor.value, 0.0)
            : fixedCrossAxisSizeFactor,
        widthFactor: axis == Axis.horizontal
            ? max(sizeFactor.value, 0.0)
            : fixedCrossAxisSizeFactor,
        child: child,
      ),
    );
  }
}

class EdgeRectClipper extends CustomClipper<Rect> {
  const EdgeRectClipper({
    required this.edge,
    required this.margin,
  });

  final Edge edge;
  final double margin;

  @override
  Rect getClip(Size size) {
    return switch (edge) {
      Edge.left =>
        Rect.fromLTRB(0.0, -margin, size.width + margin, size.height + margin),
      Edge.right =>
        Rect.fromLTRB(-margin, -margin, size.width, size.height + margin),
      Edge.top =>
        Rect.fromLTRB(-margin, 0.0, size.width + margin, size.height + margin),
      Edge.bottom => Rect.fromLTRB(-margin, -margin, size.width, size.height),
    };
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

enum Edge {
  left,
  top,
  right,
  bottom;

  bool get isHorizontal => switch (this) {
        left || right => true,
        _ => false,
      };

  bool get isVertical => !isHorizontal;
}
