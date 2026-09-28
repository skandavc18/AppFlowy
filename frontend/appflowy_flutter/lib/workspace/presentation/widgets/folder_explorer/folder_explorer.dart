import 'dart:async';

import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_kind_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_content_policy.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_service.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_tree.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_browser_presentations.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_permissions.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum FolderExplorerPresentation {
  gallery,
  tree,
}

class FolderExplorer extends StatefulWidget {
  const FolderExplorer({
    super.key,
    required this.rootView,
    this.embedded = false,
    this.showHeader = true,
    this.showControls = true,
    this.showFooter = true,
    this.onOpen,
    this.controller,
    this.initialPresentation,
    this.initialViewMode,
    this.onViewModeChanged,
    this.contentPolicy,
    this.onConnectSource,
  });

  final ViewPB rootView;
  final bool embedded;
  final bool showHeader;

  /// Whether the toolbar and breadcrumb strip are drawn. A host that supplies
  /// its own chrome — the collection page — turns them off.
  final bool showControls;
  final bool showFooter;
  final ValueChanged<ViewPB>? onOpen;
  final WorkspaceExplorerController? controller;
  final FolderExplorerPresentation? initialPresentation;
  final FileBrowserViewMode? initialViewMode;

  /// Borrowing hosts persist in their own view state. Without a callback a
  /// borrowed graph keeps the choice in this session; an owned folder saves
  /// just the mode in its existing ViewPB.extra.
  final ValueChanged<FileBrowserViewMode>? onViewModeChanged;

  /// What the host will hold. A collection narrows every add affordance to
  /// the types it is for; a plain folder leaves this null and takes anything.
  final CollectionContentPolicy? contentPolicy;

  /// Offers to back this folder with an external service. Null for a host that
  /// already has its own way of choosing that, such as the collection page.
  final VoidCallback? onConnectSource;

  @override
  State<FolderExplorer> createState() => _FolderExplorerState();
}

class _FolderExplorerState extends State<FolderExplorer> {
  final WorkspaceItemService service = const WorkspaceItemService();
  final FavoriteService favoriteService = FavoriteService();
  final FolderGalleryPreviewCache previewCache = FolderGalleryPreviewCache();
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode(debugLabel: 'folder-search');
  late final WorkspaceExplorerController controller;
  late final bool ownsController;
  late final VoidCallback releaseWriteGuard;
  bool active = true;
  String? workspaceId;
  late FileBrowserViewMode presentation;
  Future<void> _presentationWrites = Future.value();
  Timer? searchDebounce;
  final _headerKey = GlobalKey(debugLabel: 'folder-page-header');
  final _scrollControllers = <FileBrowserViewMode, ScrollController>{};

  ScrollController get _pageScroll => _scrollControllers.putIfAbsent(
        presentation,
        () => FileBrowserScrollController(),
      );

  bool _canEditView(ViewPB view, {bool identity = false}) {
    if (!active || !mounted) return false;
    final access = context.read<PageAccessLevelBloc?>();
    if (access?.view.id == view.id && access!.isClosed) return false;
    return canEditFolderExplorerView(
      view,
      pageAccess: access?.state,
      workspace: context.read<UserWorkspaceBloc?>()?.state.currentWorkspace,
      identity: identity,
    );
  }

  bool _canWriteInHost() {
    if (!active || !mounted || widget.rootView.id != controller.root.id) {
      return false;
    }
    final workspace = context.read<UserWorkspaceBloc?>();
    if (workspaceId != null &&
        (workspace?.isClosed == true ||
            workspace?.state.currentWorkspace?.workspaceId != workspaceId)) {
      return false;
    }
    return _canEditView(controller.viewForId(controller.root.id)!) &&
        _canEditView(controller.viewForId(controller.currentFolder.id)!);
  }

  bool _canRenameInHost(String id) {
    final view = controller.viewForId(id);
    return view != null && _canEditView(view, identity: true);
  }

  bool Function() _writeContinuation(String parentId) {
    final folderId = controller.currentFolder.id;
    final rootId = widget.rootView.id;
    return () =>
        active &&
        mounted &&
        widget.rootView.id == rootId &&
        controller.currentFolder.id == folderId &&
        controller.canWriteTo(parentId);
  }

  @override
  void initState() {
    super.initState();
    searchFocusNode.addListener(_searchFocusChanged);
    ownsController = widget.controller == null;
    presentation = widget.initialViewMode ??
        (widget.initialPresentation == null
            ? FileBrowserViewSettings.fromExtra(
                widget.rootView.extra,
                fallback: widget.embedded
                    ? FileBrowserViewMode.tree
                    : FileBrowserViewMode.gallery,
              )
            : widget.initialPresentation == FolderExplorerPresentation.tree
                ? FileBrowserViewMode.tree
                : FileBrowserViewMode.gallery);
    controller = widget.controller ??
        WorkspaceExplorerController(
          root: widget.rootView,
          repository: service,
        );
    releaseWriteGuard = controller.restrictWrites(
      canWrite: _canWriteInHost,
      canRename: _canRenameInHost,
    );
    if (ownsController) {
      unawaited(controller.initialize());
    } else {
      // A borrowed graph can notify its owning collection. Do not load it
      // while that ancestor is mounting this view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && active) unawaited(controller.initialize());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    workspaceId ??=
        context.read<UserWorkspaceBloc?>()?.state.currentWorkspace?.workspaceId;
  }

  @override
  void deactivate() {
    active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    active = true;
  }

  @override
  void didUpdateWidget(covariant FolderExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialViewMode != widget.initialViewMode &&
        widget.initialViewMode != null &&
        controller.editingId == null &&
        controller.draft == null) {
      presentation = widget.initialViewMode!;
    }
    // The collection already supplied this snapshot from its graph. Writing
    // it back while building creates a parent -> child -> parent rebuild loop.
    if (ownsController &&
        oldWidget.rootView.id == widget.rootView.id &&
        oldWidget.rootView != widget.rootView) {
      controller.updateRoot(widget.rootView);
    }
  }

  @override
  void dispose() {
    active = false;
    releaseWriteGuard();
    searchDebounce?.cancel();
    previewCache.clear();
    searchFocusNode
      ..removeListener(_searchFocusChanged)
      ..dispose();
    searchController.dispose();
    for (final scroll in _scrollControllers.values) {
      scroll.dispose();
    }
    if (ownsController) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild affordances on permission changes without replacing the graph,
    // selection, preview cache, or the currently mounted presentation.
    context.watch<PageAccessLevelBloc?>();
    context.watch<UserWorkspaceBloc?>();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final palette = FolderExplorerPalette.of(context);
        final shell = _buildShell(context, palette);
        // A borrowing host owns its own Find. Do not mask it with a disabled
        // descendant region when this folder supplies no search controls.
        if (!widget.showControls) return shell;
        return ContextualFindRegion(
          debugLabel: 'Folder explorer',
          enabled: widget.showControls,
          isActive: () => mounted && active && widget.showControls,
          findFocusNode: searchFocusNode,
          findOpen:
              searchFocusNode.hasFocus || searchController.text.isNotEmpty,
          onFind: _showSearch,
          onDismiss: _dismissSearch,
          child: shell,
        );
      },
    );
  }

  Widget _buildShell(
    BuildContext context,
    FolderExplorerPalette palette,
  ) {
    return ViewerCard(
      key: const ValueKey('folder-explorer-shell'),
      color: palette.background,
      borderRadius: BorderRadius.circular(widget.embedded ? 13 : 0),
      elevation: widget.embedded
          ? ViewerCardElevation.resting
          : ViewerCardElevation.flush,
      clipBehavior: widget.embedded ? Clip.antiAlias : Clip.none,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = FolderExplorerLayout.horizontalPadding(
            constraints.maxWidth,
            embedded: widget.embedded,
          );
          final header = KeyedSubtree(
            key: _headerKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (FileBrowserPageHeader.maybeOf(context) case final header?)
                  header,
                if (widget.showHeader || widget.showControls)
                  FolderGalleryHeader(
                    key: const ValueKey('folder-explorer-header'),
                    controller: controller,
                    viewMode: presentation,
                    onViewModeChanged: _setPresentation,
                    showHeader: widget.showHeader,
                    showControls: widget.showControls,
                    contentInset: horizontal,
                    contentPolicy: widget.contentPolicy,
                    userProfile:
                        context.read<UserWorkspaceBloc?>()?.state.userProfile,
                    workspace: context
                        .read<UserWorkspaceBloc?>()
                        ?.state
                        .currentWorkspace,
                    searchController: searchController,
                    searchFocusNode: searchFocusNode,
                    onSearchChanged: _scheduleSearch,
                    onNavigate: (id) => unawaited(_navigateTo(id)),
                    onAddFile: (action) => unawaited(
                      _createFileOfKind(
                        action,
                        parentId: presentation == FileBrowserViewMode.tree
                            ? null
                            : controller.currentFolder.id,
                      ),
                    ),
                    onCreateCollection: (kind) => unawaited(
                      _createCollection(
                        kind,
                        parentId: controller.currentFolder.id,
                      ),
                    ),
                    onCreateDatabase: (kind) => unawaited(
                      _createDatabase(
                        kind,
                        parentId: controller.currentFolder.id,
                      ),
                    ),
                    onNewFolder: () => _beginGalleryCreate(
                      WorkspaceExplorerDraftKind.folder,
                      parentId: presentation == FileBrowserViewMode.tree
                          ? controller.selectedOrCurrentFolderId
                          : controller.currentFolder.id,
                    ),
                    onPaste: controller.canPaste
                        ? () => unawaited(controller.paste())
                        : null,
                    onRefresh: () {
                      previewCache.clear();
                      unawaited(controller.refresh());
                    },
                    onConnectSource: widget.onConnectSource != null &&
                            controller.canRename(controller.root.id)
                        ? _connectSource
                        : null,
                    onMore: (position) =>
                        unawaited(_showBackgroundMenu(position)),
                  ),
                if (controller.errorMessage case final message?)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    child: _ExplorerErrorBanner(
                      message: message,
                      onDismiss: controller.clearError,
                    ),
                  ),
              ],
            ),
          );
          final footer = widget.showFooter
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  child: _buildFooter(context),
                )
              : null;
          return SizedBox.expand(
            key: const ValueKey('folder-explorer-content'),
            child: PremiumScrollScope(
              enabled: true,
              child: _buildPresentation(context, header, footer, horizontal),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresentation(
    BuildContext context,
    Widget header,
    Widget? footer,
    double horizontal,
  ) {
    if (presentation == FileBrowserViewMode.tree) {
      return ExplorerTree(
        header: header,
        footer: footer,
        scrollController: _pageScroll,
        horizontalPadding: horizontal,
        controller: controller,
        onOpen: _openView,
        onNavigate: (id) => unawaited(_navigateTo(id)),
        onContextMenu: _showContextMenu,
        onBackgroundContextMenu: (position) =>
            unawaited(_showBackgroundMenu(position)),
        onRequestDelete: _confirmDelete,
      );
    }
    if (presentation != FileBrowserViewMode.gallery &&
        presentation != FileBrowserViewMode.thumbnails) {
      return FolderBrowserPresentation(
        header: header,
        footer: footer,
        scrollController: _pageScroll,
        horizontalPadding: horizontal,
        controller: controller,
        mode: presentation,
        onOpen: _openView,
        onNavigate: (id) => unawaited(_navigateTo(id)),
        onContextMenu: _showContextMenu,
        onBackgroundContextMenu: (position) =>
            unawaited(_showBackgroundMenu(position)),
        onRequestDelete: _confirmDelete,
      );
    }
    return _buildGallery(context, header, footer, horizontal);
  }

  void _setPresentation(FileBrowserViewMode mode) {
    // Do not throw away an unfinished native inline rename/draft.
    if (!mounted ||
        !active ||
        presentation == mode ||
        controller.editingId != null ||
        controller.draft != null) {
      return;
    }
    setState(() => presentation = mode);
    if (!controller.canWrite || controller.root.readsFromService) return;
    if (widget.onViewModeChanged != null) {
      widget.onViewModeChanged!(mode);
    } else if (ownsController) {
      _presentationWrites =
          _presentationWrites.then((_) => _persistPresentation(mode));
    }
  }

  Future<void> _persistPresentation(FileBrowserViewMode mode) async {
    final rootId = widget.rootView.id;
    bool current() =>
        mounted &&
        active &&
        widget.rootView.id == rootId &&
        presentation == mode &&
        _canWriteInHost() &&
        !controller.root.readsFromService;
    if (!current()) return;
    try {
      final result = await ViewBackendService.getView(rootId);
      final live = result.fold<ViewPB?>((view) => view, (_) => null);
      if (!current() ||
          live == null ||
          live.id != rootId ||
          !_canEditView(live)) {
        return;
      }
      final extra = FileBrowserViewSettings.mergeExtra(live.extra, mode);
      final saved =
          await ViewBackendService.updateView(viewId: rootId, extra: extra);
      if (!current()) return;
      saved.fold(
        // UpdateView may return an empty ACK, not a populated ViewPB.
        (_) => controller
            .updateView(ViewPB.fromBuffer(live.writeToBuffer())..extra = extra),
        (error) => controller.showError(error.msg),
      );
    } catch (_) {
      if (current()) {
        controller.showError('Unable to save the folder presentation.');
      }
    }
  }

  Widget _buildGallery(
    BuildContext context,
    Widget header,
    Widget? footer,
    double horizontal,
  ) {
    return FolderGallery(
      header: header,
      footer: footer,
      scrollController: _pageScroll,
      controller: controller,
      thumbnails: presentation == FileBrowserViewMode.thumbnails,
      horizontalPadding: horizontal,
      previewCache: previewCache,
      userProfile: context.read<UserWorkspaceBloc?>()?.state.userProfile,
      onOpen: _openView,
      onNavigate: (id) => unawaited(_navigateTo(id)),
      onContextMenu: _showContextMenu,
      onBackgroundContextMenu: (position) =>
          unawaited(_showBackgroundMenu(position)),
      onRequestDelete: _confirmDelete,
      onRename: _beginGalleryRename,
    );
  }

  Widget _buildFooter(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final selected = controller.selection.length;
    return Container(
      key: const ValueKey('folder-explorer-status'),
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(vertical: 5),
      alignment: Alignment.centerLeft,
      child: Text(
        selected > 0
            ? LocaleKeys.workspaceFolderExplorer_selectedCount.tr(
                args: [selected.toString()],
              )
            : LocaleKeys.workspaceFolderExplorer_itemCount.tr(
                args: [controller.rows.length.toString()],
              ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: palette.textMuted),
      ),
    );
  }

  void _searchFocusChanged() {
    if (mounted) setState(() {});
  }

  void _showSearch() {
    if (!mounted || !active || !widget.showControls) return;
    searchFocusNode.requestFocus();
    final field = searchFocusNode.context;
    if (field != null && field.mounted) {
      unawaited(Scrollable.ensureVisible(field));
    }
  }

  void _dismissSearch() {
    _clearPendingSearch();
    searchFocusNode.unfocus();
    controller.search('');
  }

  void _scheduleSearch(String query) {
    searchDebounce?.cancel();
    searchDebounce = Timer(
      const Duration(milliseconds: 180),
      () => controller.search(query),
    );
    setState(() {});
  }

  Future<void> _navigateTo(String id) async {
    _clearPendingSearch();
    await controller.navigateTo(id);
  }

  void _clearPendingSearch() {
    searchDebounce?.cancel();
    searchDebounce = null;
    searchController.clear();
  }

  void _openView(ViewPB view) {
    if (widget.onOpen != null) {
      widget.onOpen!(view);
      return;
    }
    context.read<TabsBloc>().openPlugin(view);
  }

  Future<void> _showContextMenu(
    WorkspaceExplorerItem item,
    Offset position,
  ) async {
    final selectedIds = controller.selection.ids.toList(growable: false);
    final canContinue = _writeContinuation(item.id);
    final action = await showExplorerContextMenu(
      context: context,
      globalPosition: position,
      item: item,
      canPaste: controller.clipboard.hasData,
      canWrite: controller.canWriteTo(item.id) && controller.canMutateSelection,
      canRename: controller.canRename(item.id),
      isFavorite: controller.viewForId(item.id)?.isFavorite ?? false,
      knowledgeMode: presentation == FileBrowserViewMode.gallery ||
          presentation == FileBrowserViewMode.thumbnails,
      onCreateCollection: (kind) {
        if (canContinue()) {
          unawaited(_createCollection(kind, parentId: item.id));
        }
      },
      previewMode:
          controller.viewForId(item.id)?.previewMode ?? ViewPreviewMode.cover,
    );
    if (!mounted) {
      return;
    }
    if (action == null) {
      return;
    }
    if (action.requiresWrite &&
        (!canContinue() ||
            !controller.canMutateSelection ||
            selectedIds.length != controller.selection.length ||
            !selectedIds.every(controller.selection.contains))) {
      return;
    }
    switch (action) {
      case ExplorerContextAction.open:
        if (item.isBrowsable) {
          await _navigateTo(item.id);
        } else {
          final view = controller.viewForId(item.id);
          if (view != null) {
            _openView(view);
          }
        }
      case ExplorerContextAction.reveal:
        _clearPendingSearch();
        await controller.revealItem(item.id);
      case ExplorerContextAction.rename:
        controller.beginRename(item.id);
      case ExplorerContextAction.favorite:
        await _toggleFavorite(item.id);
      case ExplorerContextAction.duplicate:
        await controller.duplicateSelection();
      case ExplorerContextAction.copy:
        controller.copySelection();
      case ExplorerContextAction.cut:
        controller.cutSelection();
      case ExplorerContextAction.paste:
        await controller.paste(parentId: item.id);
      case ExplorerContextAction.delete:
        await _confirmDelete();
      case ExplorerContextAction.newFile:
        await _createFileInside(item, position);
      case ExplorerContextAction.newFolder:
        await _beginCreateInside(item, WorkspaceExplorerDraftKind.folder);
      case ExplorerContextAction.copyPath:
        await _copyPath(item.id);
      case ExplorerContextAction.properties:
        await _showProperties(item);
      case ExplorerContextAction.togglePreviewMode:
        await _togglePreviewMode(item.id);
    }
  }

  Future<void> _togglePreviewMode(String viewId) async {
    final canContinue = _writeContinuation(viewId);
    if (!canContinue()) return;
    final view = controller.viewForId(viewId);
    if (view == null) {
      controller.showError(
        LocaleKeys.workspaceFolderExplorer_itemUnavailable.tr(),
      );
      return;
    }
    final mode = view.previewMode == ViewPreviewMode.cover
        ? ViewPreviewMode.content
        : ViewPreviewMode.cover;
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      extra: ViewPreviewModeCodec.merge(view.extra, mode),
    );
    if (!canContinue()) {
      return;
    }
    result.fold(
      (updated) {
        previewCache.invalidate(updated.id);
        controller.updateView(updated);
      },
      (error) => controller.showError(error.msg),
    );
  }

  Future<void> _beginCreateInside(
    WorkspaceExplorerItem item,
    WorkspaceExplorerDraftKind kind,
  ) async {
    if (!controller.canWriteTo(item.id)) return;
    if (presentation != FileBrowserViewMode.tree && item.isBrowsable) {
      await _navigateTo(item.id);
      if (!mounted || !controller.canWriteTo(item.id)) return;
      _beginGalleryCreate(kind, parentId: item.id);
      return;
    }
    controller.beginCreate(kind, parentId: item.id);
  }

  Future<void> _createFileInside(
    WorkspaceExplorerItem item,
    Offset position,
  ) async {
    final canContinue = _writeContinuation(item.id);
    if (!canContinue()) return;
    final policy = widget.contentPolicy;
    final action = await showWorkspaceFileKindMenu(
      context: context,
      globalPosition: position,
      kinds: policy?.fileKinds,
      onCreateCollection: policy != null && !policy.allowsCollections
          ? null
          : (kind) {
              if (canContinue()) {
                unawaited(_createCollection(kind, parentId: item.id));
              }
            },
      onCreateDatabase: policy != null && !policy.allowsTables
          ? null
          : (kind) {
              if (canContinue()) {
                unawaited(_createDatabase(kind, parentId: item.id));
              }
            },
    );
    if (action == null || !canContinue()) {
      return;
    }
    if (presentation != FileBrowserViewMode.tree && item.isBrowsable) {
      await _navigateTo(item.id);
    }
    if (!mounted || !controller.canWriteTo(item.id)) return;
    await _createFileOfKind(action, parentId: item.id);
  }

  Future<void> _createFileOfKind(
    WorkspaceFileMenuAction action, {
    String? parentId,
  }) async {
    final targetId = parentId ?? controller.selectedOrCurrentFolderId;
    final canContinue = _writeContinuation(targetId);
    if (!canContinue()) return;
    final view = await controller.createFileOfKind(action, parentId: targetId);
    if (view != null && canContinue()) {
      _openView(view);
    }
  }

  Future<void> _createCollection(
    CollectionKind kind, {
    String? parentId,
  }) async {
    final targetId = parentId ?? controller.currentFolder.id;
    final canContinue = _writeContinuation(targetId);
    if (!canContinue()) return;
    final created = await const CollectionService().createCollection(
      parentViewId: targetId,
      kind: kind,
      name: CollectionRegistry.typeFor(kind).defaultName,
    );
    if (!canContinue()) {
      return;
    }
    created.fold(
      _openView,
      (error) => controller.showError(error.msg),
    );
  }

  Future<void> _createDatabase(
    WorkspaceTableKind kind, {
    String? parentId,
  }) async {
    final targetId = parentId ?? controller.currentFolder.id;
    final canContinue = _writeContinuation(targetId);
    if (!canContinue()) return;
    final view = await createWorkspaceDatabase(
      parentViewId: targetId,
      kind: kind,
      canWrite: canContinue,
    );
    if (view != null && canContinue()) {
      _openView(view);
    }
  }

  Future<void> _createExtensionTable(
    ExtensionTableView view, {
    String? parentId,
  }) async {
    final targetId = parentId ?? controller.currentFolder.id;
    final canContinue = _writeContinuation(targetId);
    if (!canContinue()) return;
    final created = await createWorkspaceExtensionTable(
      parentViewId: targetId,
      view: view,
      canWrite: canContinue,
    );
    if (created != null && canContinue()) {
      _openView(created);
    }
  }

  void _beginGalleryCreate(
    WorkspaceExplorerDraftKind kind, {
    required String parentId,
  }) {
    controller.beginCreate(
      kind,
      parentId: parentId,
      suggestedName: kind == WorkspaceExplorerDraftKind.folder
          ? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr()
          : LocaleKeys.workspaceFolderExplorer_untitledNote.tr(),
    );
  }

  void _beginGalleryRename(String id) {
    if (!controller.canRename(id)) return;
    controller.selection.selectOnly(id);
    controller.beginRename(id);
  }

  Future<void> _toggleFavorite(String id) async {
    final result = await favoriteService.toggleFavorite(id);
    result.fold(
      (_) {
        previewCache.invalidate(id);
        unawaited(controller.refresh());
      },
      (error) => controller.showError(error.msg),
    );
  }

  /// The menu behind the toolbar's "more" button and behind a right click on
  /// empty space, so a folder can be filled from wherever the pointer is.
  Future<void> _showBackgroundMenu(Offset position) async {
    final parentId = controller.currentFolder.id;
    final canContinue = _writeContinuation(parentId);
    final canWrite = canContinue();
    final policy = widget.contentPolicy;
    final action = await showAppMenu<_GalleryMenuAction>(
      context: context,
      globalPosition: position,
      entries: [
        if (policy == null || policy.fileKinds.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
            icon: workspaceAddFileIcon,
            enabled: canWrite,
            submenu: workspaceFileKindEntries(
              kinds: policy?.fileKinds,
              onSelected: (action) {
                if (canContinue()) {
                  unawaited(_createFileOfKind(action, parentId: parentId));
                }
              },
            ),
          ),
        if (policy == null || policy.allowsFolders)
          AppMenuItem(
            label: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
            icon: workspaceAddFolderIcon,
            value: _GalleryMenuAction.newFolder,
            enabled: canWrite,
          ),
        if (policy == null || policy.allowsTables)
          AppMenuItem(
            label: LocaleKeys.collections_database_table.tr(),
            icon: Icons.table_rows_rounded,
            enabled: canWrite,
            submenu: databaseLayoutEntries(
              onSelected: (kind) {
                if (canContinue()) {
                  unawaited(_createDatabase(kind, parentId: parentId));
                }
              },
              onExtensionSelected: (view) {
                if (canContinue()) {
                  unawaited(_createExtensionTable(view, parentId: parentId));
                }
              },
            ),
          ),
        if (policy == null || policy.allowsCollections)
          AppMenuItem(
            label: LocaleKeys.collections_newCollection.tr(),
            icon: collectionAddIcon,
            enabled: canWrite,
            submenu: collectionKindEntries(
              onSelected: (kind) {
                if (canContinue()) {
                  unawaited(_createCollection(kind, parentId: parentId));
                }
              },
            ),
          ),
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_importFile.tr(),
          icon: Icons.arrow_downward_rounded,
          value: _GalleryMenuAction.importFile,
          enabled: canWrite,
        ),
        if (controller.clipboard.hasData)
          AppMenuItem(
            label: LocaleKeys.workspaceFolderExplorer_paste.tr(),
            icon: Icons.content_paste_rounded,
            value: _GalleryMenuAction.paste,
            enabled: canWrite && controller.canPaste,
          ),
        const AppMenuSeparator(),
        if (widget.onConnectSource != null)
          AppMenuItem(
            label: LocaleKeys.providers_connectThisFolder.tr(),
            icon: Icons.cloud_sync_rounded,
            value: _GalleryMenuAction.connectSource,
            enabled: controller.canRename(controller.root.id),
          ),
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_refresh.tr(),
          icon: Icons.refresh_rounded,
          value: _GalleryMenuAction.refresh,
        ),
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_selectAll.tr(),
          icon: Icons.select_all_rounded,
          value: _GalleryMenuAction.selectAll,
        ),
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_properties.tr(),
          icon: Icons.info_outline_rounded,
          value: _GalleryMenuAction.properties,
        ),
        if (presentation == FileBrowserViewMode.gallery)
          AppMenuItem(
            label: GalleryCardSizeStore.value.label,
            icon: Icons.tune_rounded,
            value: _GalleryMenuAction.cardSize,
          ),
        ...fileBrowserViewEntries(
          selected: presentation,
          onChanged: _setPresentation,
        ),
      ],
    );
    if (!mounted) {
      return;
    }
    if (action == null) {
      return;
    }
    switch (action) {
      case _GalleryMenuAction.addFile:
        break;
      case _GalleryMenuAction.newFolder:
        if (!canContinue()) return;
        _beginGalleryCreate(
          WorkspaceExplorerDraftKind.folder,
          parentId: parentId,
        );
      case _GalleryMenuAction.importFile:
        if (canContinue()) await _importFile(parentId: parentId);
      case _GalleryMenuAction.paste:
        if (canContinue()) await controller.paste(parentId: parentId);
      case _GalleryMenuAction.refresh:
        previewCache.clear();
        await controller.refresh();
      case _GalleryMenuAction.cardSize:
        await showGalleryCardSizeMenu(
          context: context,
          globalPosition: position,
        );
      case _GalleryMenuAction.connectSource:
        _connectSource();
      case _GalleryMenuAction.selectAll:
        controller.selectAll();
      case _GalleryMenuAction.properties:
        await _showProperties(controller.currentFolder);
    }
  }

  void _connectSource() {
    if (mounted && active && controller.canRename(controller.root.id)) {
      widget.onConnectSource?.call();
    }
  }

  Future<void> _importFile({String? parentId}) async {
    final targetId = parentId ?? controller.selectedOrCurrentFolderId;
    final canContinue = _writeContinuation(targetId);
    if (!canContinue()) return;
    final result = await FilePicker().pickFiles(
      dialogTitle: LocaleKeys.workspaceFolderExplorer_importDialogTitle.tr(),
      allowMultiple: true,
      lockParentWindow: true,
    );
    if (!mounted || result == null || result.files.isEmpty || !canContinue()) {
      return;
    }
    final userProfile = context.read<UserWorkspaceBloc?>()?.state.userProfile;
    for (final picked in result.files) {
      if (!canContinue()) return;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        controller.showError(
          LocaleKeys.workspaceFolderExplorer_localFileUnavailable.tr(),
        );
        return;
      }
      final imported = await service.importBinaryFile(
        parentViewId: targetId,
        file: XFile(path, name: picked.name),
        userProfile: userProfile,
      );
      if (!canContinue()) return;
      final shouldContinue = imported.fold(
        (_) => true,
        (error) {
          controller.showError(error.msg);
          return false;
        },
      );
      if (!shouldContinue) {
        return;
      }
    }
    await controller.refresh();
  }

  Future<void> _confirmDelete() async {
    final canContinue = _writeContinuation(controller.currentFolder.id);
    if (!canContinue() ||
        !controller.canMutateSelection ||
        controller.selection.isEmpty) {
      return;
    }
    final ids = controller.selection.ids.toList(growable: false);
    final count = controller.selection.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final palette = FolderExplorerPalette.of(context);
        return AlertDialog(
          backgroundColor: palette.floatingSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: palette.border),
          ),
          title: Text(
            count == 1
                ? LocaleKeys.workspaceFolderExplorer_deleteItemTitle.tr()
                : LocaleKeys.workspaceFolderExplorer_deleteItemsTitle.tr(
                    args: [count.toString()],
                  ),
          ),
          content: Text(
            LocaleKeys.workspaceFolderExplorer_deleteDescription.tr(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(LocaleKeys.workspaceFolderExplorer_cancel.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: palette.danger),
              child: Text(LocaleKeys.workspaceFolderExplorer_delete.tr()),
            ),
          ],
        );
      },
    );
    if ((confirmed ?? false) &&
        canContinue() &&
        controller.canMutateSelection &&
        ids.length == controller.selection.length &&
        ids.every(controller.selection.contains)) {
      await controller.deleteSelection();
      if (!canContinue()) return;
      for (final id in ids) {
        previewCache.invalidate(id);
      }
    }
  }

  Future<void> _copyPath(String id) async {
    await Clipboard.setData(
      ClipboardData(text: controller.relativePathFor(id)),
    );
  }

  Future<void> _showProperties(WorkspaceExplorerItem item) {
    final metadata = item.metadata;
    final rows = <(String, String)>[
      (
        LocaleKeys.workspaceFolderExplorer_name.tr(),
        item.name.isEmpty
            ? LocaleKeys.workspaceFolderExplorer_untitled.tr()
            : item.name,
      ),
      (
        LocaleKeys.workspaceFolderExplorer_path.tr(),
        controller.relativePathFor(item.id),
      ),
      (
        LocaleKeys.workspaceFolderExplorer_kind.tr(),
        _kindLabel(item.kind),
      ),
      if (metadata?.mimeType case final mime?)
        (LocaleKeys.workspaceFolderExplorer_type.tr(), mime),
      if (metadata?.size case final size?)
        (LocaleKeys.workspaceFolderExplorer_size.tr(), _formatBytes(size)),
      if (item.lastEdited case final modified?)
        (
          LocaleKeys.workspaceFolderExplorer_modified.tr(),
          DateFormat.yMMMd().add_jm().format(modified),
        ),
    ];
    return showDialog<void>(
      context: context,
      builder: (context) {
        final palette = FolderExplorerPalette.of(context);
        return AlertDialog(
          backgroundColor: palette.floatingSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: palette.border),
          ),
          title: Row(
            children: [
              WorkspaceItemIcon(
                item: item,
                view: controller.viewForId(item.id),
                size: 20,
              ),
              const SizedBox(width: 9),
              Text(LocaleKeys.workspaceFolderExplorer_properties.tr()),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(
                            row.$1,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            row.$2,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LocaleKeys.workspaceFolderExplorer_done.tr()),
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _kindLabel(WorkspaceExplorerItemKind kind) => switch (kind) {
        WorkspaceExplorerItemKind.folder =>
          LocaleKeys.workspaceFolderExplorer_folder.tr(),
        WorkspaceExplorerItemKind.file =>
          LocaleKeys.workspaceFolderExplorer_file.tr(),
        WorkspaceExplorerItemKind.document =>
          LocaleKeys.workspaceFolderExplorer_page.tr(),
        WorkspaceExplorerItemKind.database =>
          LocaleKeys.workspaceFolderExplorer_database.tr(),
      };
}

enum _GalleryMenuAction {
  addFile,
  newFolder,
  importFile,
  paste,
  refresh,
  cardSize,
  connectSource,
  selectAll,
  properties,
}

class _ExplorerErrorBanner extends StatelessWidget {
  const _ExplorerErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.only(left: 14, right: 5),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: palette.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: palette.danger),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 15),
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}
