import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/share_section_type.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_plugin.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_title/view_title_bar_bloc.dart';
import 'package:appflowy/workspace/application/view_title/view_title_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/rename_view_popover.dart';
import 'package:appflowy/workspace/presentation/widgets/workspace_breadcrumb_children.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';

/// The shell owns the complete path beside its tab rail. Page-local callers can
/// still omit their own title with hideCurrentView without hiding it here too.
class ViewTitleBarScope extends InheritedWidget {
  const ViewTitleBarScope({super.key, required super.child});

  static bool includesCurrentView(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ViewTitleBarScope>() != null;

  @override
  bool updateShouldNotify(ViewTitleBarScope oldWidget) => false;
}

// space name > ... > view_title
class ViewTitleBar extends StatelessWidget {
  const ViewTitleBar({
    super.key,
    required this.view,
    this.hideCurrentView = false,
  });

  final ViewPB view;
  final bool hideCurrentView;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ViewTitleBarBloc(
            view: view,
          ),
        ),
      ],
      child: BlocBuilder<PageAccessLevelBloc, PageAccessLevelState>(
        buildWhen: (previous, current) =>
            previous.isLoadingLockStatus != current.isLoadingLockStatus ||
            previous.isEditable != current.isEditable ||
            previous.sectionType != current.sectionType,
        builder: (context, pageAccessLevelState) {
          return BlocConsumer<ViewTitleBarBloc, ViewTitleBarState>(
            listener: (context, state) {
              // update the page section type when the space permission is changed
              final spacePermission = state.ancestors
                  .firstWhereOrNull(
                    (ancestor) => ancestor.isSpace,
                  )
                  ?.spacePermission;
              if (spacePermission == null) {
                return;
              }
              final sectionType = switch (spacePermission) {
                SpacePermission.publicToAll => SharedSectionType.public,
                SpacePermission.private => SharedSectionType.private,
              };
              final bloc = context.read<PageAccessLevelBloc>();
              if (!bloc.isClosed && !bloc.state.isShared) {
                bloc.add(
                  PageAccessLevelEvent.updateSectionType(sectionType),
                );
              }
            },
            builder: (context, state) {
              return LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(
                      child: WorkspaceBreadcrumbs(
                        view: view,
                        ancestors: state.ancestors,
                        showCurrentView: !hideCurrentView ||
                            ViewTitleBarScope.includesCurrentView(context),
                        isDeleted: state.isDeleted,
                        isEditable: pageAccessLevelState.isEditable,
                        isGuest: context
                                .read<UserWorkspaceBloc>()
                                .state
                                .currentWorkspace
                                ?.role ==
                            AFRolePB.Guest,
                        onUpdated: () {
                          if (context.mounted) {
                            context
                                .read<ViewTitleBarBloc>()
                                .add(const ViewTitleBarEvent.reload());
                          }
                        },
                      ),
                    ),
                    // Access metadata must never displace the actual path.
                    // The underlying permission/update listeners stay above.
                    if (constraints.maxWidth >=
                        400 * MediaQuery.textScalerOf(context).scale(14) / 14)
                      _buildSectionIcon(context, pageAccessLevelState),
                    // Keep the permission listener alive at compact widths.
                    // Lock commands also live in the page's context actions;
                    // this status label must not squeeze out '/' and '>'.
                    Offstage(
                      offstage: constraints.maxWidth < 160,
                      child: ExcludeFocus(
                        excluding: constraints.maxWidth < 160,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.35,
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: _buildLockPageStatus(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLockPageStatus(BuildContext context) {
    return BlocConsumer<PageAccessLevelBloc, PageAccessLevelState>(
      listenWhen: (previous, current) =>
          previous.isLoadingLockStatus == current.isLoadingLockStatus &&
          current.isLoadingLockStatus == false,
      listener: (context, state) {
        if (state.isLocked) {
          showToastNotification(
            message: LocaleKeys.lockPage_pageLockedToast.tr(),
          );
        }
      },
      builder: (context, state) {
        if (state.isLocked) {
          return LockedPageStatus();
        } else if (!state.isLocked && state.lockCounter > 0) {
          return ReLockedPageStatus();
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSectionIcon(
    BuildContext context,
    PageAccessLevelState pageAccessLevelState,
  ) {
    final theme = AppFlowyTheme.of(context);
    final state = context.read<UserWorkspaceBloc>().state;

    if (state.currentWorkspace?.workspaceType == WorkspaceTypePB.LocalW) {
      return const SizedBox.shrink();
    }

    final iconName = switch (pageAccessLevelState.sectionType) {
      SharedSectionType.public => 'users',
      SharedSectionType.private => 'lock',
      SharedSectionType.shared => 'share',
      SharedSectionType.unknown =>
        throw UnsupportedError('Unknown section type'),
    };

    final icon = DSWorkspaceGlyph.named(
      iconName,
      color: theme.iconColorScheme.tertiary,
      size: 16,
    );

    final text = switch (pageAccessLevelState.sectionType) {
      SharedSectionType.public => 'Team space',
      SharedSectionType.private => 'Private',
      SharedSectionType.shared => 'Shared',
      SharedSectionType.unknown =>
        throw UnsupportedError('Unknown section type'),
    };

    final workspaceName = state.currentWorkspace?.name;
    final tooltipText = switch (pageAccessLevelState.sectionType) {
      SharedSectionType.public => 'Everyone at $workspaceName has access',
      SharedSectionType.private => 'Only you have access',
      SharedSectionType.shared => '',
      SharedSectionType.unknown =>
        throw UnsupportedError('Unknown section type'),
    };

    return FlowyTooltip(
      message: tooltipText,
      child: Row(
        textBaseline: TextBaseline.alphabetic,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        children: [
          HSpace(theme.spacing.xs),
          icon,
          const HSpace(4.0), // ask designer to provide the spacing
          Text(
            text,
            style: theme.textStyle.caption
                .enhanced(color: theme.textColorScheme.tertiary),
          ),
          HSpace(theme.spacing.xs),
        ],
      ),
    );
  }
}

/// Visible breadcrumb records, in path order. The backend includes the current
/// view in its response; match by id rather than dropping the last/first entry
/// blindly. A loading, failed or root-only response still names the open item.
List<ViewPB> workspaceBreadcrumbViews({
  required ViewPB view,
  required List<ViewPB> ancestors,
  bool showCurrentView = true,
  bool isGuest = false,
}) {
  final current =
      ancestors.lastWhereOrNull((item) => item.id == view.id) ?? view;
  final seen = <String>{};
  return [
    for (final ancestor in ancestors)
      if (ancestor.id != view.id &&
          ancestor.parentViewId.isNotEmpty &&
          (!isGuest || !ancestor.isSpace) &&
          seen.add(ancestor.id))
        ancestor,
    if (showCurrentView) current,
  ];
}

/// Presentation only: breadcrumb listeners and access checks belong to the
/// existing title bar. It never opens/rebuilds a page to obtain its label.
class WorkspaceBreadcrumbs extends StatefulWidget {
  const WorkspaceBreadcrumbs({
    super.key,
    required this.view,
    required this.ancestors,
    this.showCurrentView = true,
    this.isDeleted = false,
    this.isEditable = false,
    this.isGuest = false,
    this.onUpdated,
    this.repository = const WorkspaceItemService(),
    this.onNavigate,
  });

  final ViewPB view;
  final List<ViewPB> ancestors;
  final bool showCurrentView;
  final bool isDeleted;
  final bool isEditable;
  final bool isGuest;
  final VoidCallback? onUpdated;
  final WorkspaceItemRepository repository;
  final ValueChanged<ViewPB>? onNavigate;

  @override
  State<WorkspaceBreadcrumbs> createState() => _WorkspaceBreadcrumbsState();
}

class _WorkspaceBreadcrumbsState extends State<WorkspaceBreadcrumbs> {
  final _menus = WorkspaceBreadcrumbMenuController();
  UserWorkspaceBloc? _workspace;
  TabsBloc? _tabs;
  PageNotifier? _page;
  StreamSubscription<UserWorkspaceState>? _workspaceSubscription;
  StreamSubscription<TabsState>? _tabsSubscription;
  int _bindingRevision = 0;
  bool _active = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspace = context.read<UserWorkspaceBloc?>();
    final tabs = context.read<TabsBloc?>();
    final page = context.read<PageNotifier?>();
    if (!identical(workspace, _workspace)) {
      unawaited(_workspaceSubscription?.cancel());
      _workspace = workspace;
      _workspaceSubscription = workspace?.stream.listen(
        (_) => _invalidate(),
        onDone: _invalidate,
      );
    }
    if (!identical(tabs, _tabs)) {
      unawaited(_tabsSubscription?.cancel());
      _tabs = tabs;
      _tabsSubscription = tabs?.stream.listen(
        (_) => _invalidate(),
        onDone: _invalidate,
      );
    }
    if (!identical(page, _page)) {
      _page?.removeListener(_invalidate);
      _page = page;
      page?.addListener(_invalidate);
    }
    _invalidate();
  }

  @override
  void didUpdateWidget(WorkspaceBreadcrumbs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view ||
        !listEquals(oldWidget.ancestors, widget.ancestors) ||
        oldWidget.isDeleted != widget.isDeleted ||
        oldWidget.isGuest != widget.isGuest ||
        oldWidget.showCurrentView != widget.showCurrentView ||
        !identical(oldWidget.repository, widget.repository)) {
      _invalidate();
    }
  }

  @override
  void deactivate() {
    _active = false;
    _invalidate();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    _page?.removeListener(_invalidate);
    unawaited(_workspaceSubscription?.cancel());
    unawaited(_tabsSubscription?.cancel());
    _menus.dispose();
    super.dispose();
  }

  void _invalidate() {
    _bindingRevision++;
    _menus.dismiss();
  }

  bool Function() _captureBinding() {
    final revision = _bindingRevision;
    final plugin = _page?.plugin;
    final manager = _tabs?.state.currentPageManager;
    final workspaceId = _workspace?.state.currentWorkspace?.workspaceId;
    final role = _workspace?.state.currentWorkspace?.role;
    final userId = _workspace?.state.userProfile.id;
    return () =>
        mounted &&
        _active &&
        _tabs?.isClosed != true &&
        _workspace?.isClosed != true &&
        revision == _bindingRevision &&
        identical(plugin, _page?.plugin) &&
        identical(manager, _tabs?.state.currentPageManager) &&
        workspaceId == _workspace?.state.currentWorkspace?.workspaceId &&
        role == _workspace?.state.currentWorkspace?.role &&
        userId == _workspace?.state.userProfile.id;
  }

  void _navigate(ViewPB view, String workspaceId) {
    if (widget.onNavigate != null) {
      widget.onNavigate!(view);
    } else if (view.isSpace) {
      // A space has real children but no document body. Do not turn it into a
      // stored folder or look up the sidebar-local SpaceBloc from the shell.
      context.read<TabsBloc>().add(
            TabsEvent.openPlugin(
              plugin: WorkspaceFolderPlugin(view: view),
              view: view,
              setLatest: false,
            ),
          );
    } else {
      context.read<TabsBloc>().openPlugin(
            view,
            setLatest: view.id != workspaceId,
          );
    }
  }

  void _showChildren(
    BuildContext anchor,
    ViewPB parent,
    String workspaceId,
    bool isGuest,
    bool Function() isCurrent, {
    List<ViewPB>? ancestors,
  }) {
    if (!isCurrent()) return;
    unawaited(
      _menus.show(
        context: anchor,
        parent: parent,
        workspaceId: workspaceId,
        isGuest: isGuest,
        repository: widget.repository,
        isCurrent: isCurrent,
        ancestors: ancestors,
        onSelected: (view) => _navigate(view, workspaceId),
      ),
    );
  }

  Widget _childrenButton(
    ViewPB parent,
    String workspaceId,
    bool isGuest,
    bool Function() isCurrent,
  ) =>
      Builder(
        builder: (anchor) {
          void show() =>
              _showChildren(anchor, parent, workspaceId, isGuest, isCurrent);
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): show,
              const SingleActivator(LogicalKeyboardKey.arrowRight): show,
            },
            child: IconButton(
              key: ValueKey('breadcrumb-children-${parent.id}'),
              tooltip:
                  '${LocaleKeys.workspaceFolderExplorer_folderExplorer.tr()}: ${parent.nameOrDefault}',
              style: _breadcrumbControlStyle(context),
              icon: const DSWorkspaceGlyph.named('caret-right', size: 12),
              onPressed: show,
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final workspace =
        context.watch<UserWorkspaceBloc?>()?.state.currentWorkspace;
    final suppliedRoot = widget.ancestors.firstWhereOrNull(
          (view) => view.parentViewId.isEmpty,
        ) ??
        (widget.view.isWorkspaceRootFolder ? widget.view : null);
    final workspaceId = workspace?.workspaceId ?? suppliedRoot?.id ?? '';
    final name = workspace?.name.trim().isNotEmpty == true
        ? workspace!.name
        : suppliedRoot?.name.trim().isNotEmpty == true
            ? suppliedRoot!.name
            : LocaleKeys.workspace_defaultName.tr();
    final root = workspaceRootFolderView(
      workspaceId: workspaceId,
      name: name,
      icon: workspace?.icon ?? '',
    );
    final isGuest = widget.isGuest || workspace?.role == AFRolePB.Guest;
    final views = (widget.isDeleted
            ? [
                widget.ancestors
                        .lastWhereOrNull((item) => item.id == widget.view.id) ??
                    widget.view,
              ]
            : workspaceBreadcrumbViews(
                view: widget.view,
                ancestors: widget.ancestors,
                showCurrentView: widget.showCurrentView ||
                    ViewTitleBarScope.includesCurrentView(context),
                isGuest: isGuest,
              ))
        .where((view) => view.id != workspaceId)
        .toList(growable: false);
    final isCurrent = _captureBinding();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final narrow = constraints.maxWidth < 240 * scale;
        final compact = constraints.maxWidth < 128 * scale;
        final collapse = views.length > 3 ||
            constraints.maxWidth < 40 + views.length * 80 * scale;
        final visible = compact || views.isEmpty
            ? <ViewPB>[]
            : collapse
                ? [views.last]
                : views;
        final path =
            [name, ...views.map((view) => view.nameOrDefault)].join(' / ');
        return Tooltip(
          key: const ValueKey('workspace-current-path'),
          message: path,
          excludeFromSemantics: true,
          child: Row(
            children: [
              Tooltip(
                key: const ValueKey('breadcrumb-root-tooltip'),
                message: compact ? path : name,
                excludeFromSemantics: true,
                child: TextButton(
                  key: const ValueKey('breadcrumb-workspace-root'),
                  style: _breadcrumbControlStyle(context),
                  onPressed: workspaceId.isEmpty || isGuest
                      ? null
                      : () {
                          if (isCurrent()) _navigate(root, workspaceId);
                        },
                  child: Text('/', semanticsLabel: name),
                ),
              ),
              _childrenButton(root, workspaceId, isGuest, isCurrent),
              if (widget.isDeleted && !compact) ...[
                const Flexible(child: TrashBreadcrumb()),
              ],
              if (collapse && views.length > 1 && !compact) ...[
                ViewAncestorMenu(
                  views: views.sublist(0, views.length - 1),
                  onSelected: (parent) {
                    if (isCurrent()) _navigate(parent, workspaceId);
                  },
                  onShowMenu: (anchor) => _showChildren(
                    anchor,
                    root,
                    workspaceId,
                    isGuest,
                    isCurrent,
                    ancestors: views.sublist(0, views.length - 1),
                  ),
                ),
                _childrenButton(
                  views[views.length - 2],
                  workspaceId,
                  isGuest,
                  isCurrent,
                ),
              ],
              for (var i = 0; i < visible.length; i++) ...[
                Flexible(
                  flex: i == visible.length - 1 ? 2 : 1,
                  child: ViewTitle(
                    key: ValueKey(visible[i].id),
                    view: visible[i],
                    showIcon: !narrow,
                    tooltip: visible[i].id == widget.view.id ? path : null,
                    navigable: visible[i].id != widget.view.id,
                    behavior: visible[i].id == widget.view.id &&
                            !widget.isDeleted &&
                            !widget.view.isLocked &&
                            widget.isEditable
                        ? ViewTitleBehavior.editable
                        : ViewTitleBehavior.uneditable,
                    onNavigate: (view) {
                      if (isCurrent()) _navigate(view, workspaceId);
                    },
                    onUpdated: () => widget.onUpdated?.call(),
                  ),
                ),
                if (visible[i].id != widget.view.id)
                  _childrenButton(visible[i], workspaceId, isGuest, isCurrent),
              ],
            ],
          ),
        );
      },
    );
  }
}

ButtonStyle _breadcrumbControlStyle(BuildContext context) =>
    WorkspaceChrome.controlStyle(context).copyWith(
      minimumSize: const WidgetStatePropertyAll(Size(20, 32)),
      fixedSize: const WidgetStatePropertyAll(Size(20, 32)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

/// The hidden portion of a deep breadcrumb remains navigable by mouse or key.
class ViewAncestorMenu extends StatelessWidget {
  const ViewAncestorMenu({
    super.key,
    required this.views,
    required this.onSelected,
    this.onShowMenu,
  });

  final List<ViewPB> views;
  final ValueChanged<ViewPB> onSelected;
  final ValueChanged<BuildContext>? onShowMenu;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _show(context),
        },
        child: IconButton(
          key: const ValueKey('breadcrumb-ancestors'),
          icon: const DSWorkspaceGlyph.named('dots-three', size: 16),
          tooltip: LocaleKeys.workspaceChrome_ancestors.tr(),
          style: WorkspaceChrome.controlStyle(context).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size.square(24)),
            fixedSize: const WidgetStatePropertyAll(Size.square(24)),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _show(context),
        ),
      );

  void _show(BuildContext context) {
    if (onShowMenu != null) {
      onShowMenu!(context);
      return;
    }
    unawaited(
      showAppMenuForWidget<void>(
        context: context,
        width: 280,
        placement: AppMenuPlacement.below,
        entries: [
          for (final view in views)
            AppMenuItem(
              label: view.nameOrDefault,
              iconWidget: WorkspaceBreadcrumbIcon(view: view),
              onSelected: () => onSelected(view),
            ),
        ],
      ),
    );
  }
}

class TrashBreadcrumb extends StatelessWidget {
  const TrashBreadcrumb({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FlowyButton(
        useIntrinsicWidth: true,
        margin: const EdgeInsets.symmetric(horizontal: 6.0),
        onTap: () {
          getIt<MenuSharedState>().latestOpenView = null;
          getIt<TabsBloc>().add(
            TabsEvent.openPlugin(
              plugin: makePlugin(pluginType: PluginType.trash),
            ),
          );
        },
        text: Row(
          children: [
            const DSWorkspaceGlyph.named('trash', size: 14),
            const HSpace(4.0),
            FlowyText.regular(
              LocaleKeys.trash_text.tr(),
              fontSize: 14.0,
              overflow: TextOverflow.ellipsis,
              figmaLineHeight: 18.0,
            ),
          ],
        ),
      ),
    );
  }
}

enum ViewTitleBehavior {
  editable,
  uneditable,
}

class ViewTitle extends StatefulWidget {
  const ViewTitle({
    super.key,
    required this.view,
    this.behavior = ViewTitleBehavior.editable,
    required this.onUpdated,
    this.showIcon = true,
    this.navigable = true,
    this.onNavigate,
    this.tooltip,
  });

  final ViewPB view;
  final ViewTitleBehavior behavior;
  final VoidCallback onUpdated;
  final bool showIcon;
  final bool navigable;
  final ValueChanged<ViewPB>? onNavigate;
  final String? tooltip;

  @override
  State<ViewTitle> createState() => _ViewTitleState();
}

class _ViewTitleState extends State<ViewTitle> {
  final popoverController = PopoverController();
  final textEditingController = TextEditingController();

  @override
  void dispose() {
    textEditingController.dispose();
    popoverController.close();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditable = widget.behavior == ViewTitleBehavior.editable;

    return BlocProvider(
      create: (_) => ViewTitleBloc(view: widget.view)
        ..add(
          const ViewTitleEvent.initial(),
        ),
      child: BlocConsumer<ViewTitleBloc, ViewTitleState>(
        listenWhen: (previous, current) {
          if (previous.view == null || current.view == null) {
            return false;
          }

          return previous.view != current.view;
        },
        listener: (_, state) {
          _resetTextEditingController(state);
          widget.onUpdated();
        },
        builder: (context, state) {
          // root view
          if (widget.view.parentViewId.isEmpty) {
            return _buildIconAndName(context, state, false);
          } else if (widget.view.isSpace) {
            return _buildSpaceTitle(context, state);
          } else if (isEditable) {
            return _buildEditableViewTitle(context, state);
          } else {
            return _buildUnEditableViewTitle(context, state);
          }
        },
      ),
    );
  }

  Widget _buildSpaceTitle(BuildContext context, ViewTitleState state) {
    return _buildUnEditableViewTitle(context, state);
  }

  Widget _buildUnEditableViewTitle(BuildContext context, ViewTitleState state) {
    if (!widget.navigable) return _buildIconAndName(context, state, false);
    return TextButton(
      style: _titleStyle(context),
      onPressed: () {
        final view = state.view ?? widget.view;
        if (widget.onNavigate != null) {
          widget.onNavigate!(view);
        } else {
          context.read<TabsBloc>().openPlugin(view);
        }
      },
      child: _buildIconAndName(context, state, false),
    );
  }

  Widget _buildEditableViewTitle(BuildContext context, ViewTitleState state) {
    return AppFlowyPopover(
      constraints: const BoxConstraints(
        maxWidth: 300,
        maxHeight: 44,
      ),
      controller: popoverController,
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 6),
      popupBuilder: (context) {
        // icon + textfield
        _resetTextEditingController(state);
        return RenameViewPopover(
          view: widget.view,
          name: widget.view.name,
          popoverController: popoverController,
          icon: DSWorkspaceGlyph.adapt(widget.view.defaultIcon(), size: 16),
          emoji: state.icon,
        );
      },
      child: TextButton(
        style: _titleStyle(context),
        onPressed: popoverController.show,
        child: _buildIconAndName(context, state, true),
      ),
    );
  }

  Widget _buildIconAndName(
    BuildContext context,
    ViewTitleState state,
    bool isEditable,
  ) {
    final view = state.view ?? widget.view;
    final spaceIcon = view.buildSpaceIconSvg(context);
    final icon =
        state.icon.isNotEmpty ? state.icon : view.icon.toEmojiIconData();
    final name =
        state.view == null ? widget.view.nameOrDefault : view.nameOrDefault;
    return Tooltip(
      message: widget.tooltip ?? name,
      excludeFromSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showIcon && icon.isNotEmpty) ...[
            RawEmojiIconWidget(emoji: icon, emojiSize: 14.0),
            const HSpace(4.0),
          ],
          if (widget.showIcon && view.isSpace && spaceIcon != null) ...[
            SpaceIcon(
              dimension: 14,
              svgSize: 8.5,
              space: view,
              cornerRadius: 4,
            ),
            const HSpace(6.0),
          ],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
                color: isEditable
                    ? WorkspacePalette.of(context).primaryText
                    : WorkspacePalette.of(context).secondaryText,
              ).copyWith(fontSize: 13, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  void _resetTextEditingController(ViewTitleState state) {
    textEditingController
      ..text = state.name
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: state.name.length,
      );
  }

  ButtonStyle _titleStyle(BuildContext context) =>
      WorkspaceChrome.controlStyle(context).copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

class LockedPageStatus extends StatelessWidget {
  const LockedPageStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFFD95A0B);
    return FlowyTooltip(
      message: LocaleKeys.lockPage_lockTooltip.tr(),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: BorderSide(color: color),
            borderRadius: BorderRadius.circular(6),
          ),
          color: context.lockedPageButtonBackground,
        ),
        child: FlowyButton(
          useIntrinsicWidth: true,
          margin: const EdgeInsets.symmetric(
            horizontal: 4.0,
            vertical: 4.0,
          ),
          iconPadding: 4.0,
          text: FlowyText.regular(
            LocaleKeys.lockPage_lockPage.tr(),
            color: color,
            fontSize: 12.0,
          ),
          hoverColor: color.withValues(alpha: 0.1),
          leftIcon: DSWorkspaceGlyph.named(
            'lock',
            color: color,
            role: WorkspaceGlyphRole.preserveInk,
          ),
          onTap: () => context.read<PageAccessLevelBloc>().add(
                const PageAccessLevelEvent.unlock(),
              ),
        ),
      ),
    );
  }
}

class ReLockedPageStatus extends StatelessWidget {
  const ReLockedPageStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final iconColor = const Color(0xFF8F959E);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          side: BorderSide(color: iconColor),
          borderRadius: BorderRadius.circular(6),
        ),
        color: context.lockedPageButtonBackground,
      ),
      child: FlowyButton(
        useIntrinsicWidth: true,
        margin: const EdgeInsets.symmetric(
          horizontal: 4.0,
          vertical: 4.0,
        ),
        iconPadding: 4.0,
        text: FlowyText.regular(
          LocaleKeys.lockPage_reLockPage.tr(),
          fontSize: 12.0,
        ),
        leftIcon: DSWorkspaceGlyph.named(
          'lock-open',
          color: iconColor,
          role: WorkspaceGlyphRole.preserveInk,
        ),
        onTap: () => context.read<PageAccessLevelBloc>().add(
              const PageAccessLevelEvent.lock(),
            ),
      ),
    );
  }
}

extension on BuildContext {
  Color get lockedPageButtonBackground {
    if (Theme.of(this).brightness == Brightness.light &&
        PaperTheme.isEnabled(this)) {
      return PaperTheme.popupBackground;
    }
    return PremiumThemeExtension.maybeOf(this)?.surface ??
        Theme.of(this).colorScheme.surface;
  }
}
