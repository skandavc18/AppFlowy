import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart';
import 'package:appflowy/plugins/database/find/database_find_host.dart';
import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/document/presentation/compact_mode_event.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/database/database_view_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

import 'desktop/setting_menu.dart';
import 'desktop/tab_bar_header.dart';
import 'mobile/mobile_tab_bar_header.dart';

abstract class DatabaseTabBarItemBuilder {
  const DatabaseTabBarItemBuilder();

  /// Returns the content of the tab bar item. The content is shown when the tab
  /// bar item is selected. It can be any kind of database view.
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  );

  /// Returns the setting bar of the tab bar item. The setting bar is shown on the
  /// top right conner when the tab bar item is selected.
  Widget settingBar(
    BuildContext context,
    DatabaseController controller,
  );

  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  );

  /// A grid or board grows with its rows instead of filling the box it is in.
  bool get growsWithContent => false;

  /// Should be called in case a builder has resources it
  /// needs to dispose of.
  ///
  // If we add any logic in this method, add @mustCallSuper !
  void dispose() {}
}

class DatabaseTabBarView extends StatefulWidget {
  const DatabaseTabBarView({
    super.key,
    required this.view,
    required this.shrinkWrap,
    required this.showActions,
    this.initialRowId,
    this.actionBuilder,
    this.node,
    this.showPageDecoration = false,
    this.embedHeight,
  });

  final ViewPB view;
  final bool shrinkWrap;
  final BlockComponentActionBuilder? actionBuilder;
  final bool showActions;
  final Node? node;
  final bool showPageDecoration;

  /// The embedding block's fixed height, tab header included. Null when the
  /// block grows with its content.
  final double? embedHeight;

  /// Used to open a Row on plugin load
  ///
  final String? initialRowId;

  @override
  State<DatabaseTabBarView> createState() => _DatabaseTabBarViewState();
}

class _DatabaseTabBarViewState extends State<DatabaseTabBarView> {
  bool enableCompactMode = false;
  bool initialed = false;
  StreamSubscription<CompactModeEvent>? compactModeSubscription;

  String get compactModeId => widget.node?.id ?? widget.view.id;

  @override
  void initState() {
    super.initState();
    if (widget.node != null) {
      enableCompactMode =
          widget.node!.attributes[DatabaseBlockKeys.enableCompactMode] ?? false;
      setState(() {
        initialed = true;
      });
    } else {
      fetchLocalCompactMode(compactModeId).then((v) {
        if (mounted) {
          setState(() {
            enableCompactMode = v;
            initialed = true;
          });
        }
      });
      compactModeSubscription =
          compactModeEventBus.on<CompactModeEvent>().listen((event) {
        if (event.id != widget.view.id) return;
        updateLocalCompactMode(event.enable);
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
    compactModeSubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (!initialed) return Center(child: CircularProgressIndicator());
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final editorState = context.read<EditorState?>();
        final maxDocWidth = editorState?.editorStyle.maxWidth ?? maxWidth;
        final paddingLeft = max(0, maxWidth - maxDocWidth) / 2;
        return MultiBlocProvider(
          providers: [
            BlocProvider<DatabaseTabBarBloc>(
              create: (_) => DatabaseTabBarBloc(
                view: widget.view,
                compactModeId: compactModeId,
                enableCompactMode: enableCompactMode,
              )..add(const DatabaseTabBarEvent.initial()),
            ),
            BlocProvider<ViewBloc>(
              create: (_) => ViewBloc(view: widget.view)
                ..add(
                  const ViewEvent.initial(),
                ),
            ),
          ],
          child: BlocBuilder<DatabaseTabBarBloc, DatabaseTabBarState>(
            builder: (innerContext, state) => _buildTabBarView(
              context,
              innerContext,
              state,
              paddingLeft: paddingLeft,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabBarView(
    BuildContext context,
    BuildContext innerContext,
    DatabaseTabBarState state, {
    required double paddingLeft,
  }) {
    final tab = state.tabBars[state.selectedIndex];
    final layout = tab.layout;
    final controller = state.tabBarControllerByViewId[tab.viewId]!.controller;
    final tabBarBloc = innerContext.read<DatabaseTabBarBloc>();
    final databseBuilderSize = context.read<DatabasePluginWidgetBuilderSize>();
    final horizontalPadding = databseBuilderSize.horizontalPadding;
    final showActionWrapper = widget.showActions &&
        widget.actionBuilder != null &&
        widget.node != null;
    final showPageDecoration =
        widget.showPageDecoration && widget.node == null && !widget.shrinkWrap;
    final coordinateVerticalScroll = showPageDecoration &&
        (layout == ViewLayoutPB.Grid ||
            layout == ViewLayoutPB.Calendar ||
            layout == ViewLayoutPB.Board);
    final Widget child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPageDecoration && !coordinateVerticalScroll)
          BlocBuilder<ViewBloc, ViewState>(
            builder: (context, viewState) => DatabasePageDecoration(
              view: viewState.view,
              userProfile:
                  context.read<UserWorkspaceBloc?>()?.state.userProfile,
              horizontalPadding: horizontalPadding + paddingLeft,
            ),
          ),
        if (UniversalPlatform.isMobile) const VSpace(12),
        ValueListenableBuilder<bool>(
          valueListenable: state.tabBarControllerByViewId[state.parentView.id]!
              .controller.isLoading,
          builder: (_, value, ___) {
            if (value) {
              return const SizedBox.shrink();
            }

            Widget child = UniversalPlatform.isDesktop
                ? const TabBarHeader()
                : const MobileTabBarHeader();

            if (innerContext.watch<ViewBloc>().state.view.isLocked) {
              child = ExcludeFocus(
                child: IgnorePointer(child: child),
              );
            }

            if (showActionWrapper) {
              child = BlockComponentActionWrapper(
                node: widget.node!,
                actionBuilder: widget.actionBuilder!,
                child: Padding(
                  padding: EdgeInsets.only(right: horizontalPadding),
                  child: child,
                ),
              );
            }

            if (UniversalPlatform.isDesktop) {
              child = Container(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding + paddingLeft,
                  0,
                  horizontalPadding,
                  0,
                ),
                child: child,
              );
            }

            return child;
          },
        ),
        pageSettingBarExtensionFromState(context, state),
        wrapContent(
          layout: layout,
          growsWithContent: tab.builder.growsWithContent,
          child: Padding(
            // Only the header carries the block's action gutter, so
            // only then does the content below need to line up with
            // it.
            padding: showActionWrapper
                ? EdgeInsets.only(left: 42 - horizontalPadding)
                : EdgeInsets.zero,
            child: Provider(
              create: (_) => DatabasePluginWidgetBuilderSize(
                horizontalPadding: horizontalPadding,
                paddingLeftWithMaxDocumentWidth: paddingLeft,
                verticalPadding: databseBuilderSize.verticalPadding,
                coordinateVerticalScroll: coordinateVerticalScroll,
                showScrollbars: databseBuilderSize.showScrollbars,
              ),
              child: pageContentFromState(context, state),
            ),
          ),
        ),
      ],
    );

    Widget content = child;
    if (coordinateVerticalScroll) {
      content = NestedScrollView(
        key: const ValueKey('database-page-scroll-view'),
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: BlocBuilder<ViewBloc, ViewState>(
              builder: (context, viewState) => DatabasePageDecoration(
                view: viewState.view,
                userProfile:
                    context.read<UserWorkspaceBloc?>()?.state.userProfile,
                horizontalPadding: horizontalPadding + paddingLeft,
              ),
            ),
          ),
        ],
        body: child,
      );
    }

    return DatabaseFindHost(
      view: tab.view,
      isActive: () {
        if (!mounted || tabBarBloc.isClosed) return false;
        final current = tabBarBloc.state;
        return current.parentView.id == widget.view.id &&
            current.selectedIndex >= 0 &&
            current.selectedIndex < current.tabBars.length &&
            current.tabBars[current.selectedIndex].viewId == tab.viewId &&
            identical(
              current.tabBarControllerByViewId[tab.viewId]?.controller,
              controller,
            );
      },
      child: content,
    );
  }

  Future<bool> fetchLocalCompactMode(String compactModeId) async {
    Set<String> compactModeIds = {};
    try {
      final localIds = await getIt<KeyValueStorage>().get(
        KVKeys.compactModeIds,
      );
      final List<dynamic> decodedList = jsonDecode(localIds ?? '');
      compactModeIds = Set.from(decodedList.map((item) => item as String));
    } catch (e) {
      Log.warn('fetch local compact mode from id :$compactModeId failed', e);
    }
    return compactModeIds.contains(compactModeId);
  }

  Future<void> updateLocalCompactMode(bool enableCompactMode) async {
    Set<String> compactModeIds = {};
    try {
      final localIds = await getIt<KeyValueStorage>().get(
        KVKeys.compactModeIds,
      );
      final List<dynamic> decodedList = jsonDecode(localIds ?? '');
      compactModeIds = Set.from(decodedList.map((item) => item as String));
    } catch (e) {
      Log.warn('get compact mode ids failed', e);
    }
    if (enableCompactMode) {
      compactModeIds.add(compactModeId);
    } else {
      compactModeIds.remove(compactModeId);
    }
    await getIt<KeyValueStorage>().set(
      KVKeys.compactModeIds,
      jsonEncode(compactModeIds.toList()),
    );
  }

  Widget wrapContent({
    required ViewLayoutPB layout,
    required Widget child,
    bool growsWithContent = false,
  }) {
    if (widget.shrinkWrap) {
      // The block frame is embedHeight tall and also holds the tab header.
      if (widget.embedHeight != null) {
        return Expanded(
          child: growsWithContent
              ? SingleChildScrollView(primary: false, child: child)
              : child,
        );
      }
      if (layout.shrinkWrappable) {
        return child;
      }

      return SizedBox(
        height: layout.pluginHeight,
        child: child,
      );
    }

    return Expanded(child: child);
  }

  Widget pageContentFromState(BuildContext context, DatabaseTabBarState state) {
    final tab = state.tabBars[state.selectedIndex];
    final controller = state.tabBarControllerByViewId[tab.viewId]!.controller;

    return tab.builder.content(
      context,
      tab.view,
      controller,
      widget.shrinkWrap,
      widget.initialRowId,
    );
  }

  Widget pageSettingBarExtensionFromState(
    BuildContext context,
    DatabaseTabBarState state,
  ) {
    if (state.tabBars.length < state.selectedIndex) {
      return const SizedBox.shrink();
    }
    final tabBar = state.tabBars[state.selectedIndex];
    final controller =
        state.tabBarControllerByViewId[tabBar.viewId]!.controller;
    final extension = tabBar.builder.settingBarExtension(context, controller);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal:
            context.read<DatabasePluginWidgetBuilderSize>().horizontalPadding,
      ),
      child: PreviewToolbar(
        // Filter/sort editors exist only while explicitly toggled open. Like
        // search, their fields and legacy popovers stay visible until closed.
        keepVisible: extension is DatabaseViewSettingExtension,
        child: extension,
      ),
    );
  }
}

/// One full-page decoration owner for alternative table renderers. Embeds
/// leave decoration to their parent. The header/body occupy permanent slots:
/// cover edits, permissions, text scale and renderer mode never reparent them.
class DatabasePageDecorationHost extends StatefulWidget {
  const DatabasePageDecorationHost({
    super.key,
    required this.view,
    required this.builder,
    this.enabled = true,
    this.listenerFactory = _databaseDecorationListener,
  });

  final ViewPB view;
  final Widget Function(ViewPB view) builder;
  final bool enabled;

  /// Only the notification boundary is replaceable in offline host tests.
  final ViewListener Function(String viewId) listenerFactory;

  @override
  State<DatabasePageDecorationHost> createState() =>
      _DatabasePageDecorationHostState();
}

ViewListener _databaseDecorationListener(String viewId) =>
    ViewListener(viewId: viewId);

class _DatabasePageDecorationHostState
    extends State<DatabasePageDecorationHost> {
  late ViewPB _view;
  ViewListener? _listener;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant DatabasePageDecorationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.listenerFactory != widget.listenerFactory) {
      _bind();
    } else if (oldWidget.view != widget.view) {
      _view = widget.view;
    }
  }

  void _bind() {
    final generation = ++_generation;
    unawaited(_listener?.stop());
    _listener = null;
    _view = widget.view;
    if (!widget.enabled || _view.id.isEmpty) return;
    final viewId = _view.id;
    _listener = widget.listenerFactory(viewId)
      ..start(
        onViewUpdated: (view) {
          if (!mounted ||
              generation != _generation ||
              view.id != viewId ||
              widget.view.id != viewId) {
            return;
          }
          setState(() => _view = view);
        },
      );
  }

  void _onDecorationChanged(ViewPB view) {
    if (!mounted || view.id != _view.id) return;
    setState(() => _view = view);
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_listener?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DatabaseFindHost(
        view: _view,
        isActive: () => mounted && _view.id == widget.view.id,
        delegateToNativeChild: true,
        child: _buildDecoratedContent(context),
      );

  Widget _buildDecoratedContent(BuildContext context) {
    final child = widget.builder(_view);
    if (!widget.enabled) return child;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            // Keep an operable content pane on short/scaled windows. Only the
            // identity scrolls here; no new scroll controller owns the viewer.
            constraints: BoxConstraints(
              maxHeight: constraints.hasBoundedHeight
                  ? constraints.maxHeight / 2
                  : double.infinity,
            ),
            child: SingleChildScrollView(
              key: const ValueKey('database-decoration-scroll'),
              primary: false,
              child: DatabasePageDecoration(
                // A true target change owns a new title draft and action
                // generation; decoration updates on the same page do not.
                key: ValueKey(('database-page-decoration', _view.id)),
                view: _view,
                onViewChanged: _onDecorationChanged,
                userProfile:
                    context.read<UserWorkspaceBloc?>()?.state.userProfile,
                horizontalPadding: 40,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class DatabasePageDecoration extends StatefulWidget {
  const DatabasePageDecoration({
    super.key,
    required this.view,
    required this.userProfile,
    required this.horizontalPadding,
    this.onViewChanged,
  });

  final ViewPB view;
  final UserProfilePB? userProfile;
  final double horizontalPadding;
  final ValueChanged<ViewPB>? onViewChanged;

  @override
  State<DatabasePageDecoration> createState() => _DatabasePageDecorationState();
}

class _DatabasePageDecorationState extends State<DatabasePageDecoration> {
  bool editingTitle = false;
  ViewPB? locallyUpdatedView;

  bool get _canEdit {
    final view = locallyUpdatedView ?? widget.view;
    final access = context.read<PageAccessLevelBloc?>();
    return !view.isLocked &&
        (access?.view.id != view.id || access!.state.isEditable);
  }

  @override
  void didUpdateWidget(covariant DatabasePageDecoration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      locallyUpdatedView = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = locallyUpdatedView ?? widget.view;
    final showsCover = AutomaticViewCover.showsCover(view);
    final cover = view.cover;
    final icon = view.icon.toEmojiIconData();
    final opticalRole =
        isColorfulViewIcon(icon) ? IconOpticalRole.header : null;
    context.watch<PageAccessLevelBloc?>();
    final canEdit = _canEdit;
    final titleIcon = SizedBox.square(
      key: const ValueKey('database-page-title-icon'),
      dimension: opticalRole != null
          ? IconOpticalSize.resolve(
              role: opticalRole,
              baseSize: WorkspaceTokens.pageIconSize,
            ).slotSize
          : WorkspaceTokens.pageIconSize,
      child: Center(
        child: MediaQuery.withNoTextScaling(
          child: icon.isNotEmpty
              ? RawEmojiIconWidget(
                  emoji: icon,
                  emojiSize: WorkspaceTokens.pageIconSize,
                  opticalRole: opticalRole,
                  lineHeight: 1,
                )
              : WorkspaceGlyph.adapt(
                  view.defaultIcon(
                    size: const Size.square(WorkspaceTokens.pageIconSize),
                  ),
                  size: WorkspaceTokens.pageIconSize,
                ),
        ),
      ),
    );
    return PreviewToolbarRegion(
      child: ViewDecorationActions(
        view: view,
        userProfile: widget.userProfile,
        onViewChanged: _updateView,
        visible: false,
        showIconAction: canEdit,
        showCoverAction: canEdit,
        showDownloadAction: showsCover,
        hasCover: showsCover,
        markCoverChosen: true,
        layoutBuilder: (iconActions, coverActions, pageActions) =>
            LayoutBuilder(
          builder: (context, constraints) => WorkspacePageHeader(
            maxWidth: double.infinity,
            contentInset: min(
              max(20.0, widget.horizontalPadding),
              constraints.maxWidth / 4,
            ),
            cover: showsCover && cover != null && !cover.isNone
                ? ViewCoverImage(
                    cover: cover,
                    userProfile: widget.userProfile,
                    width: double.infinity,
                  )
                : null,
            coverActions: coverActions,
            coverView: view,
            coverBinding: widget.view.id,
            coverEditable: canEdit && showsCover,
            canResizeCover: () =>
                mounted &&
                _canEdit &&
                samePageCoverSource(view, locallyUpdatedView ?? widget.view) &&
                AutomaticViewCover.showsCover(
                    locallyUpdatedView ?? widget.view),
            isSameCoverTarget: (fresh) =>
                fresh.layout == view.layout &&
                AutomaticViewCover.showsCover(fresh),
            onCoverHeightChanged: (height) {
              final latest = locallyUpdatedView ?? widget.view;
              if (mounted && _canEdit && samePageCoverSource(view, latest)) {
                _updateView(PageCoverHeight.applyTo(latest, height));
              }
            },
            identity: WorkspacePageIdentity(
              key: const ValueKey('database-page-identity'),
              icon: canEdit
                  ? ViewIconPicker(
                      view: view,
                      onViewChanged: _updateView,
                      child: titleIcon,
                    )
                  : titleIcon,
              iconActions: iconActions,
              title: ExcludeFocus(
                excluding: !canEdit,
                child: IgnorePointer(
                  ignoring: !canEdit,
                  child: DatabaseFindAnchor(
                    target: DatabaseFindTarget.title(view.id),
                    child: WorkspaceInlineEditableText(
                      key: const ValueKey('database-page-title'),
                      text: view.nameOrDefault,
                      editingValue: view.name,
                      editing: editingTitle,
                      onSubmitted: _rename,
                      onCancelled: _cancelRename,
                      onTap: canEdit ? _beginRename : null,
                      maxLines: 2,
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.pageTitle,
                        compact: constraints.maxWidth < 600,
                      ),
                    ),
                  ),
                ),
              ),
              actions: pageActions,
            ),
          ),
        ),
      ),
    );
  }

  void _updateView(ViewPB view) {
    if (mounted && view.id == widget.view.id) {
      setState(() => locallyUpdatedView = view);
      widget.onViewChanged?.call(view);
    }
  }

  void _beginRename() {
    if (!editingTitle) {
      setState(() => editingTitle = true);
    }
  }

  void _cancelRename() {
    if (editingTitle) {
      setState(() => editingTitle = false);
    }
  }

  Future<bool> _rename(String name) async {
    // An access change may blur a retained draft. Refuse that auto-submit
    // without discarding the editor, and never write merely on unlocking it.
    if (!_canEdit) return false;
    if (name == widget.view.name) {
      _cancelRename();
      return true;
    }
    final result = await ViewBackendService.updateView(
      viewId: widget.view.id,
      name: name,
    );
    if (!mounted) {
      return false;
    }
    return result.fold(
      (updated) {
        _updateView(updated);
        context.read<ViewBloc?>()?.add(ViewEvent.viewDidUpdate(result));
        context
            .read<ViewInfoBloc?>()
            ?.add(ViewInfoEvent.titleChanged(updated.name));
        _cancelRename();
        return true;
      },
      (error) {
        showSnapBar(context, error.msg);
        return false;
      },
    );
  }
}

class DatabaseTabBarViewPlugin extends Plugin {
  DatabaseTabBarViewPlugin({
    required ViewPB view,
    required PluginType pluginType,
    this.initialRowId,
  })  : _pluginType = pluginType,
        notifier = ViewPluginNotifier(view: view);

  @override
  final ViewPluginNotifier notifier;

  final PluginType _pluginType;
  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  /// Used to open a Row on plugin load
  ///
  final String? initialRowId;

  @override
  PluginWidgetBuilder get widgetBuilder => DatabasePluginWidgetBuilder(
        bloc: _viewInfoBloc,
        pageAccessLevelBloc: _pageAccessLevelBloc,
        notifier: notifier,
        initialRowId: initialRowId,
      );

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => _pluginType;

  @override
  void init() {
    _viewInfoBloc = ViewInfoBloc(view: notifier.view)
      ..add(const ViewInfoEvent.started());
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

const kDatabasePluginWidgetBuilderHorizontalPadding = 'horizontal_padding';
const kDatabasePluginWidgetBuilderShowActions = 'show_actions';
const kDatabasePluginWidgetBuilderActionBuilder = 'action_builder';
const kDatabasePluginWidgetBuilderNode = 'node';
const kDatabasePluginWidgetBuilderEmbedHeight = 'embed_height';

class DatabasePluginWidgetBuilderSize {
  const DatabasePluginWidgetBuilderSize({
    required this.horizontalPadding,
    this.verticalPadding = 16.0,
    this.paddingLeftWithMaxDocumentWidth = 0.0,
    this.coordinateVerticalScroll = false,
    this.showScrollbars = true,
  });

  final double horizontalPadding;
  final double verticalPadding;
  final double paddingLeftWithMaxDocumentWidth;
  final bool coordinateVerticalScroll;

  /// Embedded cards can retain both scrolling axes without visible rails.
  /// Ordinary database pages keep their established scrollbar behavior.
  final bool showScrollbars;

  double get paddingLeft => paddingLeftWithMaxDocumentWidth + horizontalPadding;
}

class DatabasePluginWidgetBuilder extends PluginWidgetBuilder {
  DatabasePluginWidgetBuilder({
    required this.bloc,
    required this.pageAccessLevelBloc,
    required this.notifier,
    this.initialRowId,
  });

  final ViewInfoBloc bloc;
  final PageAccessLevelBloc pageAccessLevelBloc;
  final ViewPluginNotifier notifier;

  /// Used to open a Row on plugin load
  ///
  final String? initialRowId;

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem {
    return BlocProvider.value(
      value: pageAccessLevelBloc,
      child: ViewTitleBar(
        key: ValueKey(notifier.view.id),
        view: notifier.view,
        hideCurrentView: true,
      ),
    );
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    notifier.isDeleted.addListener(() {
      final deletedView = notifier.isDeleted.value;
      if (deletedView != null && deletedView.hasIndex()) {
        context.onDeleted?.call(notifier.view, deletedView.index);
      }
    });

    final horizontalPadding =
        data?[kDatabasePluginWidgetBuilderHorizontalPadding] as double? ??
            GridSize.horizontalHeaderPadding + 40;
    final BlockComponentActionBuilder? actionBuilder =
        data?[kDatabasePluginWidgetBuilderActionBuilder];
    final bool showActions =
        data?[kDatabasePluginWidgetBuilderShowActions] ?? false;
    final Node? node = data?[kDatabasePluginWidgetBuilderNode];
    final double? embedHeight =
        data?[kDatabasePluginWidgetBuilderEmbedHeight] as double?;

    return BlocProvider<PageAccessLevelBloc>.value(
      value: pageAccessLevelBloc,
      child: Provider(
        create: (context) => DatabasePluginWidgetBuilderSize(
          horizontalPadding: horizontalPadding,
        ),
        child: DatabaseTabBarView(
          key: ValueKey(notifier.view.id),
          view: notifier.view,
          shrinkWrap: shrinkWrap,
          initialRowId: initialRowId,
          actionBuilder: actionBuilder,
          showActions: showActions,
          node: node,
          showPageDecoration: node == null,
          embedHeight: embedHeight,
        ),
      ),
    );
  }

  @override
  List<NavigationItem> get navigationItems => [this];

  @override
  Widget? get rightBarItem {
    final view = notifier.view;
    return MultiBlocProvider(
      providers: [
        BlocProvider<ViewInfoBloc>.value(
          value: bloc,
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: Row(
        children: [
          ShareButton(key: ValueKey(view.id), view: view),
          const HSpace(10),
          ViewFavoriteButton(view: view),
          const HSpace(4),
          MoreViewActions(view: view),
        ],
      ),
    );
  }

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;
}
