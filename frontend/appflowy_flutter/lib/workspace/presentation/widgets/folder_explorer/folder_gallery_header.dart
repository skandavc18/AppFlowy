import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/presentation/widgets/workspace_cover_actions.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_content_policy.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_permissions.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FolderGalleryHeader extends StatefulWidget {
  const FolderGalleryHeader({
    super.key,
    required this.controller,
    required this.searchController,
    required this.onSearchChanged,
    required this.onNavigate,
    required this.onAddFile,
    required this.onCreateCollection,
    required this.onCreateDatabase,
    required this.onMore,
    this.onImportFromService,
    this.onMountService,
    this.userProfile,
    this.workspace,
    this.viewMode = FileBrowserViewMode.gallery,
    this.onViewModeChanged,
    this.searchFocusNode,
    this.showHeader = true,
    this.showControls = true,
    this.contentInset,
    this.contentPolicy,
    this.onNewFolder,
    this.onPaste,
    this.onRefresh,
    this.onConnectSource,
  });

  final WorkspaceExplorerController controller;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onNavigate;
  final ValueChanged<WorkspaceFileMenuAction> onAddFile;
  final ValueChanged<CollectionKind> onCreateCollection;
  final ValueChanged<WorkspaceTableKind> onCreateDatabase;
  final ValueChanged<Offset> onMore;
  final ValueChanged<ProviderServiceInfo>? onImportFromService;
  final ValueChanged<ProviderServiceInfo>? onMountService;
  final UserProfilePB? userProfile;
  final UserWorkspacePB? workspace;
  final FileBrowserViewMode viewMode;
  final ValueChanged<FileBrowserViewMode>? onViewModeChanged;

  /// Borrowed by the field, never disposed here. A folder's Find region can
  /// reveal/focus search without replacing this header or its text controller.
  final FocusNode? searchFocusNode;
  final bool showHeader;
  final bool showControls;
  final double? contentInset;
  final CollectionContentPolicy? contentPolicy;
  final VoidCallback? onNewFolder;
  final VoidCallback? onPaste;
  final VoidCallback? onRefresh;
  final VoidCallback? onConnectSource;

  @override
  State<FolderGalleryHeader> createState() => _FolderGalleryHeaderState();
}

class _FolderGalleryHeaderState extends State<FolderGalleryHeader> {
  FocusNode? _ownedSearchFocusNode;
  FocusNode get searchFocusNode =>
      widget.searchFocusNode ??
      (_ownedSearchFocusNode ??= FocusNode(debugLabel: 'folder-header-search'));
  bool searchExpanded = false;
  bool hasWorkspaceCoverOverride = false;
  String? workspaceCoverOverrideId;
  PageStyleCover? workspaceCoverOverride;
  VoidCallback? _releaseMoreMenu;
  bool _moreMenuSettling = false;
  bool _moreMenuCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    searchFocusNode.addListener(_onSearchFocusChanged);
    widget.searchController.addListener(_onSearchTextChanged);
  }

  void _onSearchTextChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {
      searchExpanded =
          searchFocusNode.hasFocus || widget.searchController.text.isNotEmpty;
    });
    if (!searchFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !searchFocusNode.hasFocus) return;
      final fieldContext = searchFocusNode.context;
      if (fieldContext != null && fieldContext.mounted) {
        unawaited(Scrollable.ensureVisible(fieldContext));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMoreMenuReleaseCheck();
  }

  void _scheduleMoreMenuReleaseCheck() {
    if (_releaseMoreMenu == null || _moreMenuCheckScheduled) return;
    _moreMenuCheckScheduled = true;
    // Focus can still refer to a deactivated popup while the tree is being
    // updated. Inspect ancestry only after that frame has finished detaching it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moreMenuCheckScheduled = false;
      _releaseMoreMenuIfCurrent();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _releaseMoreMenuIfCurrent() {
    if (!mounted || _releaseMoreMenu == null) return;
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent != false;
    if (_moreMenuSettling || !routeIsCurrent) return;
    // A root-navigator menu can cover a still-current nested page route. Its
    // native focus scope is the close signal in that case, not a timer.
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext?.findAncestorWidgetOfExactType<AppMenuScope>() != null) {
      return;
    }
    final release = _releaseMoreMenu;
    _releaseMoreMenu = null;
    if (release == null) return;
    FocusManager.instance.removeListener(_onMoreMenuFocusChanged);
    release();
  }

  void _onMoreMenuFocusChanged() => _scheduleMoreMenuReleaseCheck();

  bool _canEditCurrentFolder({bool identity = false}) {
    if (!mounted) return false;
    final controller = widget.controller;
    final id = controller.currentFolder.id;
    if (!(identity ? controller.canRename(id) : controller.canWriteTo(id))) {
      return false;
    }
    final view = controller.viewForId(id);
    final currentWorkspace =
        context.read<UserWorkspaceBloc?>()?.state.currentWorkspace;
    return view != null &&
        canEditFolderExplorerView(
          view,
          pageAccess: context.read<PageAccessLevelBloc?>()?.state,
          workspace:
              currentWorkspace?.workspaceId == widget.workspace?.workspaceId
                  ? currentWorkspace ?? widget.workspace
                  : widget.workspace,
          identity: identity,
        );
  }

  @override
  void didUpdateWidget(covariant FolderGalleryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchFocusNode != widget.searchFocusNode) {
      (oldWidget.searchFocusNode ?? _ownedSearchFocusNode)
          ?.removeListener(_onSearchFocusChanged);
      searchFocusNode.addListener(_onSearchFocusChanged);
    }
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController.removeListener(_onSearchTextChanged);
      widget.searchController.addListener(_onSearchTextChanged);
    }
    if (oldWidget.workspace?.workspaceId != widget.workspace?.workspaceId) {
      hasWorkspaceCoverOverride = false;
      workspaceCoverOverrideId = null;
      workspaceCoverOverride = null;
      return;
    }
    if (oldWidget.workspace?.cover != widget.workspace?.cover &&
        WorkspaceCoverCodec.decode(widget.workspace?.cover ?? '') ==
            workspaceCoverOverride) {
      hasWorkspaceCoverOverride = false;
      workspaceCoverOverrideId = null;
      workspaceCoverOverride = null;
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onMoreMenuFocusChanged);
    final release = _releaseMoreMenu;
    _releaseMoreMenu = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    searchFocusNode.removeListener(_onSearchFocusChanged);
    widget.searchController.removeListener(_onSearchTextChanged);
    _ownedSearchFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = FolderExplorerPalette.of(context);
    final folder = controller.currentFolder;
    final folderView = controller.viewForId(folder.id);
    context.watch<PageAccessLevelBloc?>();
    context.watch<UserWorkspaceBloc?>();
    final isWorkspaceRoot = widget.workspace?.workspaceId == folder.id;
    final rootWorkspace = isWorkspaceRoot ? widget.workspace : null;
    final storedWorkspaceCover = !isWorkspaceRoot
        ? null
        : WorkspaceCoverCodec.decode(widget.workspace!.cover);
    final workspaceCover = hasWorkspaceCoverOverride &&
            workspaceCoverOverrideId == rootWorkspace?.workspaceId
        ? workspaceCoverOverride
        : storedWorkspaceCover;
    final stats = [
      LocaleKeys.workspaceFolderExplorer_fileCount.tr(
        args: [controller.visibleFileCount.toString()],
      ),
      LocaleKeys.workspaceFolderExplorer_folderCount.tr(
        args: [controller.visibleFolderCount.toString()],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = widget.contentInset ??
            FolderExplorerLayout.horizontalPadding(constraints.maxWidth);
        final cover = isWorkspaceRoot ? workspaceCover : folderView?.cover;
        final canEditIdentity = _canEditCurrentFolder(identity: true);
        final canAddContent = _canEditCurrentFolder();
        final keepVisible = searchExpanded || controller.query.isNotEmpty;
        final availableWidth = (constraints.maxWidth - horizontal * 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        final actionStrip = widget.showControls
            ? WorkspaceActionRow(
                key: const ValueKey('folder-explorer-actions'),
                keepVisible: keepVisible ||
                    widget.searchController.text.isNotEmpty ||
                    searchFocusNode.hasFocus,
                // Mode navigation stays available; the standalone options
                // fallback remains a contextual action, as before.
                leading: widget.onViewModeChanged != null
                    ? _buildViewSwitcher(
                        context,
                        availableWidth: availableWidth,
                      )
                    : null,
                children: _buildActions(
                  context,
                  palette,
                  availableWidth: availableWidth,
                  canAddContent: canAddContent,
                ),
              )
            : null;
        if (!widget.showHeader) {
          return Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showControls && controller.breadcrumbs.length > 1)
                  _GalleryBreadcrumbs(
                    items: controller.breadcrumbs,
                    onSelected: widget.onNavigate,
                  ),
                if (actionStrip != null) actionStrip,
              ],
            ),
          );
        }
        // Native iconActions include Add Cover when the identity is coverless.
        // Keep decoration children empty: the shell owns the single stable
        // page action strip instead of mounting a second native pageActions row.
        Widget buildHeader(
          Widget? iconActions,
          Widget? coverActions,
          Widget? _,
        ) =>
            WorkspacePageHeader(
              // The shell inset already contains its centered outer margin.
              // Applying a second max-width here would count that margin twice.
              maxWidth: double.infinity,
              contentInset: horizontal,
              overlapIcon: rootWorkspace != null || folderView != null,
              leading: widget.showControls && controller.breadcrumbs.length > 1
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Keep the explorer's existing context outside the
                        // picture/icon overlap; navigation ownership is unchanged.
                        _GalleryBreadcrumbs(
                          items: controller.breadcrumbs,
                          onSelected: widget.onNavigate,
                        ),
                        const SizedBox(height: WorkspaceTokens.space4),
                      ],
                    )
                  : null,
              cover: cover != null && !cover.isNone
                  ? ViewCoverImage(
                      cover: cover,
                      userProfile: widget.userProfile,
                      width: double.infinity,
                    )
                  : null,
              coverActions: coverActions,
              identity: _GalleryHeading(
                key: const ValueKey('folder-gallery-heading'),
                folder: folder,
                view: folderView,
                workspace: rootWorkspace,
                stats: stats,
                compact: constraints.maxWidth < 600,
                canEdit: canEditIdentity,
                editing: controller.editingId == folder.id,
                onRename: () {
                  if (_canEditCurrentFolder(identity: true)) {
                    controller.beginRename(folder.id);
                  }
                },
                onSubmitted: (name) {
                  if (!_canEditCurrentFolder(identity: true)) {
                    return Future.value(false);
                  }
                  return rootWorkspace == null
                      ? controller.commitRename(name)
                      : _renameWorkspace(name);
                },
                onCancelled: controller.cancelEditing,
                onViewChanged: controller.updateView,
                iconActions: iconActions,
                actions: actionStrip,
              ),
            );
        return PreviewToolbarRegion(
          child: rootWorkspace != null
              ? WorkspaceCoverActions(
                  workspace: rootWorkspace,
                  userProfile: widget.userProfile,
                  visible: keepVisible,
                  editable: canEditIdentity,
                  showIconAction: true,
                  layoutBuilder: buildHeader,
                  onCoverChanged: (cover) => _setWorkspaceCoverOverride(
                    rootWorkspace,
                    cover,
                  ),
                )
              : folderView != null
                  ? ViewDecorationActions(
                      view: folderView,
                      userProfile: widget.userProfile,
                      onViewChanged: controller.updateView,
                      visible: keepVisible,
                      showIconAction: canEditIdentity,
                      showCoverAction: canEditIdentity,
                      showDownloadAction: true,
                      layoutBuilder: buildHeader,
                    )
                  : buildHeader(
                      null,
                      null,
                      null,
                    ),
        );
      },
    );
  }

  void _showViewOptions(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null) return;
    // Standalone callers can keep delegating to their existing options menu.
    _showMoreMenu(buttonContext, box.localToGlobal(Offset(0, box.size.height)));
  }

  void _showMoreMenu(BuildContext buttonContext, Offset position) {
    if (_releaseMoreMenu != null) return;
    // The owning explorer opens its menu from a context above this region and
    // exposes a void callback. Follow the existing route's lifetime without
    // changing that callback, the menu, or any of its mutation guards.
    _releaseMoreMenu = PreviewToolbarRegion.hold(buttonContext);
    _moreMenuSettling = true;
    FocusManager.instance.addListener(_onMoreMenuFocusChanged);
    try {
      widget.onMore(position);
    } finally {
      // Also release for callbacks that intentionally do not open a route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Let the newly built popup apply autofocus before checking its owner.
        scheduleMicrotask(() {
          if (!mounted) return;
          _moreMenuSettling = false;
          _scheduleMoreMenuReleaseCheck();
        });
      });
    }
  }

  void _setWorkspaceCoverOverride(
    UserWorkspacePB workspace,
    PageStyleCover? cover,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      hasWorkspaceCoverOverride = true;
      workspaceCoverOverrideId = workspace.workspaceId;
      workspaceCoverOverride = cover;
    });
  }

  Future<bool> _renameWorkspace(String rawName) async {
    final workspace = widget.workspace;
    final name = rawName.trim();
    if (workspace == null ||
        name.isEmpty ||
        !_canEditCurrentFolder(identity: true) ||
        widget.controller.currentFolder.id != workspace.workspaceId) {
      return false;
    }
    if (workspace.name == name) {
      widget.controller.cancelEditing();
      return true;
    }

    final bloc = context.read<UserWorkspaceBloc>();
    final completion = bloc.stream.firstWhere(
      (state) =>
          state.actionResult?.actionType == WorkspaceActionType.rename &&
          state.actionResult?.isLoading == false,
    );
    bloc.add(
      UserWorkspaceEvent.renameWorkspace(
        workspaceId: workspace.workspaceId,
        name: name,
      ),
    );
    final result = (await completion).actionResult?.result;
    if (!mounted ||
        widget.workspace?.workspaceId != workspace.workspaceId ||
        widget.controller.currentFolder.id != workspace.workspaceId ||
        !_canEditCurrentFolder(identity: true)) {
      return false;
    }
    return result?.fold(
          (_) {
            widget.controller.cancelEditing();
            return true;
          },
          (error) {
            showSnapBar(context, error.msg);
            return false;
          },
        ) ??
        false;
  }

  Widget _buildViewSwitcher(
    BuildContext context, {
    required double availableWidth,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final compactControls = availableWidth < 400 * scale;
    return SizedBox(
      key: const ValueKey('folder-gallery-view-switcher'),
      // Different mode labels must not move search or wrap the action strip.
      width: (compactControls ? 40.0 : 164 * scale).clamp(0.0, availableWidth),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: widget.onViewModeChanged != null
            ? FileBrowserViewButton(
                mode: widget.viewMode,
                onChanged: widget.onViewModeChanged!,
                compact: compactControls,
              )
            : Builder(
                builder: (buttonContext) => TextButton(
                  onPressed: () => _showViewOptions(buttonContext),
                  style: WorkspaceChrome.controlStyle(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WorkspaceGlyph(widget.viewMode.icon, size: 16),
                      if (!compactControls) ...[
                        const SizedBox(width: WorkspaceTokens.space2),
                        Flexible(
                          child: Text(
                            widget.viewMode.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WorkspaceTypography.style(
                              context,
                              WorkspaceTextRole.metadata,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    FolderExplorerPalette palette, {
    required double availableWidth,
    required bool canAddContent,
  }) {
    final showSearch = !widget.showHeader ||
        searchExpanded ||
        widget.searchController.text.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final policy = widget.contentPolicy;
    return [
      if (widget.onViewModeChanged == null)
        _buildViewSwitcher(context, availableWidth: availableWidth),
      AnimatedContainer(
        key: const ValueKey('folder-gallery-search'),
        duration: WorkspaceTokens.motion(
          context,
          WorkspaceTokens.transitionDuration,
        ),
        curve: WorkspaceTokens.curve,
        width: showSearch ? availableWidth.clamp(0.0, 238.0).toDouble() : 40,
        height: (MediaQuery.textScalerOf(context).scale(14) * 1.5 + 12)
            .clamp(40.0, double.infinity)
            .toDouble(),
        decoration: BoxDecoration(
          color: !showSearch
              ? palette.hover.withValues(alpha: 0)
              : isDark
                  ? Color.alphaBlend(
                      palette.accent.withValues(alpha: 0.10),
                      palette.surface,
                    )
                  : palette.hover.withValues(alpha: palette.hover.a * 0.52),
          borderRadius: BorderRadius.circular(13),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Row(
            children: [
              _GalleryControl(
                icon: Icons.search_rounded,
                semanticLabel:
                    LocaleKeys.workspaceFolderExplorer_searchCollection.tr(),
                foregroundColor: isDark ? palette.accent : null,
                onPressed: _showSearch,
              ),
              Expanded(
                // Retain the actual field when collapsed. Explicit Find can
                // focus it; Tab skips it until it is painted.
                child: FocusTraversalGroup(
                  descendantsAreTraversable: showSearch,
                  child: Offstage(
                    offstage: !showSearch,
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.escape):
                            _dismissSearch,
                      },
                      child: TextEntryShortcuts(
                        child: TextField(
                          key: const ValueKey('folder-explorer-search-field'),
                          controller: widget.searchController,
                          focusNode: searchFocusNode,
                          onChanged: widget.onSearchChanged,
                          onTapOutside: (_) => _collapseSearch(),
                          cursorColor: palette.accent,
                          textInputAction: TextInputAction.search,
                          style: WorkspaceTypography.style(
                            context,
                            WorkspaceTextRole.body,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            hintText: LocaleKeys
                                .workspaceFolderExplorer_searchCollection
                                .tr(),
                            hintStyle: TextStyle(
                              color: palette.textMuted,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showSearch && widget.searchController.text.isNotEmpty)
                _GalleryControl(
                  icon: Icons.close_rounded,
                  semanticLabel: LocaleKeys.workspaceFolderExplorer_cancel.tr(),
                  onPressed: _clearSearch,
                  compact: true,
                ),
            ],
          ),
        ),
      ),
      if (canAddContent && (policy == null || policy.fileKinds.isNotEmpty))
        Builder(
          key: const ValueKey('folder-gallery-add'),
          builder: (buttonContext) => _GalleryControl(
            icon: Icons.add_rounded,
            label: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
            semanticLabel: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
            primary: true,
            onPressed: !canAddContent
                ? null
                : () async {
                    final folderId = widget.controller.currentFolder.id;
                    bool canCreate() =>
                        mounted &&
                        widget.controller.currentFolder.id == folderId &&
                        _canEditCurrentFolder();
                    if (!canCreate()) return;
                    final box = buttonContext.findRenderObject() as RenderBox?;
                    if (box == null) {
                      return;
                    }
                    final action = await showWorkspaceFileKindMenu(
                      context: buttonContext,
                      globalPosition:
                          box.localToGlobal(Offset(0, box.size.height + 4)),
                      kinds: policy?.fileKinds,
                      onCreateCollection: policy != null &&
                              !policy.allowsCollections
                          ? null
                          : (kind) {
                              if (canCreate()) widget.onCreateCollection(kind);
                            },
                      onCreateDatabase: policy != null && !policy.allowsTables
                          ? null
                          : (kind) {
                              if (canCreate()) widget.onCreateDatabase(kind);
                            },
                      onImportFromService: widget.onImportFromService == null
                          ? null
                          : (info) {
                              if (canCreate()) {
                                widget.onImportFromService!(info);
                              }
                            },
                      onMountService: widget.onMountService == null
                          ? null
                          : (info) {
                              if (canCreate()) widget.onMountService!(info);
                            },
                    );
                    if (action != null && canCreate()) {
                      widget.onAddFile(action);
                    }
                  },
          ),
        ),
      if (canAddContent &&
          widget.onNewFolder != null &&
          (policy?.allowsFolders ?? true))
        _GalleryControl(
          icon: workspaceAddFolderIcon,
          semanticLabel: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
          onPressed: widget.onNewFolder,
        ),
      if (canAddContent && widget.onPaste != null)
        _GalleryControl(
          icon: Icons.content_paste_rounded,
          semanticLabel: LocaleKeys.workspaceFolderExplorer_paste.tr(),
          onPressed: widget.onPaste,
        ),
      if (widget.onRefresh != null)
        _GalleryControl(
          icon: Icons.refresh_rounded,
          semanticLabel: LocaleKeys.workspaceFolderExplorer_refresh.tr(),
          onPressed: widget.onRefresh,
        ),
      if (widget.onConnectSource != null)
        _GalleryControl(
          icon: Icons.cloud_sync_rounded,
          semanticLabel: LocaleKeys.providers_connectThisFolder.tr(),
          onPressed: widget.onConnectSource,
        ),
      Builder(
        key: const ValueKey('folder-gallery-options'),
        builder: (buttonContext) => _GalleryControl(
          icon: Icons.more_horiz_rounded,
          semanticLabel: LocaleKeys.workspaceFolderExplorer_more.tr(),
          onPressed: () {
            final box = buttonContext.findRenderObject() as RenderBox;
            _showMoreMenu(
              buttonContext,
              box.localToGlobal(Offset(box.size.width, box.size.height)),
            );
          },
        ),
      ),
    ];
  }

  void _showSearch() {
    if (!searchExpanded) {
      setState(() => searchExpanded = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          searchFocusNode.requestFocus();
        }
      });
      return;
    }
    searchFocusNode.requestFocus();
  }

  void _collapseSearch() {
    if (widget.searchController.text.isEmpty && searchExpanded) {
      searchFocusNode.unfocus();
      setState(() => searchExpanded = false);
    }
  }

  void _dismissSearch() {
    widget.searchController.clear();
    widget.onSearchChanged('');
    searchFocusNode.unfocus();
    setState(() => searchExpanded = false);
  }

  void _clearSearch() {
    widget.searchController.clear();
    widget.onSearchChanged('');
    searchFocusNode.requestFocus();
    setState(() {});
  }
}

class _GalleryHeading extends StatelessWidget {
  const _GalleryHeading({
    super.key,
    required this.folder,
    required this.view,
    required this.workspace,
    required this.stats,
    required this.editing,
    required this.onRename,
    required this.onSubmitted,
    required this.onCancelled,
    required this.onViewChanged,
    required this.iconActions,
    required this.actions,
    required this.canEdit,
    required this.compact,
  });

  final WorkspaceExplorerItem folder;
  final ViewPB? view;
  final UserWorkspacePB? workspace;
  final List<String> stats;
  final bool editing;
  final VoidCallback onRename;
  final Future<bool> Function(String name) onSubmitted;
  final VoidCallback onCancelled;
  final ValueChanged<ViewPB> onViewChanged;
  final Widget? iconActions;
  final Widget? actions;
  final bool canEdit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final rawTitle = workspace?.name ?? folder.name;
    final title = rawTitle.isEmpty
        ? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr()
        : rawTitle;
    final icon = view?.icon.toEmojiIconData();
    final opticalRole = icon != null && isColorfulViewIcon(icon)
        ? IconOpticalRole.header
        : null;
    final Widget? titleIcon;
    if (workspace case final currentWorkspace?) {
      final workspaceIcon =
          EmojiIconData.fromStorageString(currentWorkspace.icon);
      final opticalSize = isColorfulViewIcon(workspaceIcon)
          ? IconOpticalSize.resolve(
              role: IconOpticalRole.header,
              baseSize: WorkspaceTokens.pageIconSize,
            )
          : null;
      titleIcon = MediaQuery.withNoTextScaling(
        child: WorkspaceIcon(
          key: const ValueKey('workspace-gallery-icon'),
          workspaceIcon: currentWorkspace.icon,
          workspaceName: currentWorkspace.name,
          documentId: currentWorkspace.workspaceId,
          iconSize: opticalSize?.slotSize ?? WorkspaceTokens.pageIconSize,
          isEditable: canEdit,
          fontSize: 25,
          emojiSize: opticalSize?.artworkSize ?? WorkspaceTokens.pageIconSize,
          borderRadius: 14,
          figmaLineHeight:
              opticalSize?.artworkSize ?? WorkspaceTokens.pageIconSize,
          showBorder: false,
          onSelected: (result) => context.read<UserWorkspaceBloc>().add(
                UserWorkspaceEvent.updateWorkspaceIcon(
                  workspaceId: currentWorkspace.workspaceId,
                  icon: result.toStorageString(),
                ),
              ),
        ),
      );
    } else if (view case final currentView?) {
      titleIcon = ViewIconPicker(
        view: currentView,
        onViewChanged: onViewChanged,
        child: SizedBox.square(
          key: const ValueKey('folder-gallery-title-icon'),
          dimension: opticalRole != null
              ? IconOpticalSize.resolve(
                  role: opticalRole,
                  baseSize: WorkspaceTokens.pageIconSize,
                ).slotSize
              : WorkspaceTokens.pageIconSize,
          child: Center(
            child: MediaQuery.withNoTextScaling(
              child: icon != null && icon.isNotEmpty
                  ? RawEmojiIconWidget(
                      emoji: icon,
                      emojiSize: WorkspaceTokens.pageIconSize,
                      opticalRole: opticalRole,
                      lineHeight: 1,
                    )
                  : const WorkspaceGlyph(
                      Icons.folder_rounded,
                      size: WorkspaceTokens.pageIconSize,
                    ),
            ),
          ),
        ),
      );
    } else {
      titleIcon = null;
    }
    return WorkspacePageIdentity(
      icon: ExcludeFocus(
        excluding: !canEdit,
        child: IgnorePointer(
          ignoring: !canEdit,
          child: titleIcon ?? const SizedBox.shrink(),
        ),
      ),
      iconActions: iconActions,
      title: ExcludeFocus(
        excluding: !canEdit,
        child: IgnorePointer(
          ignoring: !canEdit,
          child: WorkspaceInlineEditableText(
            key: const ValueKey('folder-gallery-title'),
            text: title,
            editingValue: rawTitle,
            editing: editing,
            onSubmitted: onSubmitted,
            onCancelled: onCancelled,
            onTap: canEdit ? onRename : null,
            maxLines: 2,
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.pageTitle,
              compact: compact,
            ),
          ),
        ),
      ),
      metadata: Wrap(
        spacing: WorkspaceTokens.space3,
        runSpacing: WorkspaceTokens.space1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var index = 0; index < stats.length; index++) ...[
            if (index > 0)
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
              ),
            Text(
              stats[index],
            ),
          ],
        ],
      ),
      actions: actions,
    );
  }
}

class _GalleryBreadcrumbs extends StatelessWidget {
  const _GalleryBreadcrumbs({
    required this.items,
    required this.onSelected,
  });

  final List<WorkspaceExplorerItem> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.length <= 1) {
      return const SizedBox.shrink();
    }
    final ancestors = items.sublist(0, items.length - 1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < ancestors.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: FolderExplorerPalette.of(context)
                      .textMuted
                      .withValues(alpha: 0.52),
                ),
              ),
            _GalleryBreadcrumb(
              item: ancestors[index],
              current: false,
              onPressed: () => onSelected(ancestors[index].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _GalleryBreadcrumb extends StatelessWidget {
  const _GalleryBreadcrumb({
    required this.item,
    required this.current,
    required this.onPressed,
  });

  final WorkspaceExplorerItem item;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: current ? null : onPressed,
      style: WorkspaceChrome.controlStyle(context),
      child: Text(
        item.name.isEmpty
            ? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr()
            : item.name,
        style: WorkspaceTypography.style(context, WorkspaceTextRole.metadata),
      ),
    );
  }
}

class _GalleryControl extends StatelessWidget {
  const _GalleryControl({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.label,
    this.primary = false,
    this.compact = false,
    this.foregroundColor,
  });

  final IconData icon;
  final String? label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool primary;
  final bool compact;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final foreground = onPressed == null
        ? palette.textMuted.withValues(alpha: 0.45)
        : primary
            ? palette.accent
            : foregroundColor ?? palette.textSecondary;
    final style = WorkspaceChrome.controlStyle(
      context,
      accent: foreground,
    );
    if (label == null) {
      return SizedBox.square(
        dimension: compact ? 32 : 40,
        child: IconButton(
          tooltip: semanticLabel,
          onPressed: onPressed,
          style: style,
          icon: WorkspaceGlyph(icon, size: 17, color: foreground),
        ),
      );
    }
    return Tooltip(
      message: semanticLabel,
      excludeFromSemantics: true,
      child: TextButton(
        onPressed: onPressed,
        style: style,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceGlyph(icon, size: 17, color: foreground),
            const SizedBox(width: 7),
            Flexible(child: Text(label!)),
          ],
        ),
      ),
    );
  }
}
