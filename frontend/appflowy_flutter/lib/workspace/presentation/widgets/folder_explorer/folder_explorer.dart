import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_kind_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
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
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/breadcrumb_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_toolbar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_tree.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
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
  late final WorkspaceExplorerController controller;
  late final bool ownsController;
  late FolderExplorerPresentation presentation;
  Timer? searchDebounce;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    presentation = widget.initialPresentation ??
        (widget.embedded
            ? FolderExplorerPresentation.tree
            : FolderExplorerPresentation.gallery);
    controller = widget.controller ??
        WorkspaceExplorerController(
          root: widget.rootView,
          repository: service,
        );
    unawaited(controller.initialize());
  }

  @override
  void didUpdateWidget(covariant FolderExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootView.id == widget.rootView.id) {
      controller.updateRoot(widget.rootView);
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    previewCache.clear();
    searchController.dispose();
    if (ownsController) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final palette = FolderExplorerPalette.of(context);
        if (presentation == FolderExplorerPresentation.gallery &&
            !widget.embedded) {
          return _buildGalleryShell(context, palette);
        }
        return _buildExplorerShell(context, palette);
      },
    );
  }

  Widget _buildGalleryShell(
    BuildContext context,
    FolderExplorerPalette palette,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final header = widget.showHeader
        ? FolderGalleryHeader(
            controller: controller,
            userProfile: context.read<UserWorkspaceBloc?>()?.state.userProfile,
            workspace:
                context.watch<UserWorkspaceBloc?>()?.state.currentWorkspace,
            searchController: searchController,
            onSearchChanged: _scheduleSearch,
            onNavigate: (id) => unawaited(_navigateTo(id)),
            onAddFile: (action) => unawaited(
              _createFileOfKind(
                action,
                parentId: controller.currentFolder.id,
              ),
            ),
            onCreateCollection: (kind) => unawaited(
              _createCollection(kind, parentId: controller.currentFolder.id),
            ),
            onCreateDatabase: (kind) => unawaited(
              _createDatabase(kind, parentId: controller.currentFolder.id),
            ),
            onMore: (position) => unawaited(_showBackgroundMenu(position)),
          )
        : null;
    final errorMessage = controller.errorMessage;
    final errorBanner = errorMessage == null
        ? null
        : _ExplorerErrorBanner(
            message: errorMessage,
            onDismiss: controller.clearError,
            spacious: true,
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              palette.accent.withValues(alpha: isDark ? 0.018 : 0.012),
              palette.background,
            ),
            palette.background,
          ],
          stops: const [0, 0.42],
        ),
      ),
      child: PremiumScrollScope(
        enabled: true,
        child: _buildGallery(
          context,
          header: header,
          errorBanner: errorBanner,
        ),
      ),
    );
  }

  Widget _buildExplorerShell(
    BuildContext context,
    FolderExplorerPalette palette,
  ) {
    return ViewerCard(
      color: palette.background,
      borderRadius: BorderRadius.circular(widget.embedded ? 13 : 0),
      // Only an embed floats above a page; the full-window explorer already
      // owns its background.
      elevation: widget.embedded
          ? ViewerCardElevation.resting
          : ViewerCardElevation.flush,
      clipBehavior: widget.embedded ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader) _buildHeader(context),
          if (widget.showControls) _buildControls(context),
          if (controller.errorMessage case final message?)
            _ExplorerErrorBanner(
              message: message,
              onDismiss: controller.clearError,
            ),
          Expanded(
            child: PremiumScrollScope(
              enabled: true,
              child: _buildPresentation(context),
            ),
          ),
          if (widget.showFooter) _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildPresentation(BuildContext context) {
    if (presentation == FolderExplorerPresentation.tree) {
      return ExplorerTree(
        controller: controller,
        onOpen: _openView,
        onNavigate: (id) => unawaited(_navigateTo(id)),
        onContextMenu: _showContextMenu,
        onBackgroundContextMenu: (position) =>
            unawaited(_showBackgroundMenu(position)),
        onRequestDelete: _confirmDelete,
      );
    }
    return _buildGallery(context);
  }

  Widget _buildGallery(
    BuildContext context, {
    Widget? header,
    Widget? errorBanner,
  }) {
    return FolderGallery(
      controller: controller,
      previewCache: previewCache,
      userProfile: context.read<UserWorkspaceBloc?>()?.state.userProfile,
      header: header,
      errorBanner: errorBanner,
      onOpen: _openView,
      onNavigate: (id) => unawaited(_navigateTo(id)),
      onContextMenu: _showContextMenu,
      onBackgroundContextMenu: (position) =>
          unawaited(_showBackgroundMenu(position)),
      onRequestDelete: _confirmDelete,
      onRename: _beginGalleryRename,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final root = controller.root;
    final modified = root.lastEdited;
    final metadata = [
      LocaleKeys.workspaceFolderExplorer_fileCount.tr(
        args: [controller.visibleFileCount.toString()],
      ),
      LocaleKeys.workspaceFolderExplorer_folderCount.tr(
        args: [controller.visibleFolderCount.toString()],
      ),
      if (modified != null)
        LocaleKeys.workspaceFolderExplorer_modifiedAt.tr(
          args: [DateFormat.yMMMd().add_jm().format(modified)],
        ),
    ].join('  ·  ');
    final titleStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: widget.embedded ? 16 : 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    );
    final title = root.name.isEmpty
        ? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr()
        : root.name;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.embedded ? 18 : 24,
        widget.embedded ? 16 : 24,
        widget.embedded ? 18 : 24,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: WorkspaceItemIcon(
              item: root,
              expanded: true,
              color: palette.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkspaceInlineEditableText(
                  key: const ValueKey('folder-explorer-title'),
                  text: title,
                  editingValue: root.name,
                  editing: controller.editingId == root.id,
                  onSubmitted: controller.commitRename,
                  onCancelled: controller.cancelEditing,
                  onTap: () => controller.beginRename(root.id),
                  style: titleStyle,
                ),
                const SizedBox(height: 3),
                Text(
                  controller.breadcrumbs
                      .map((item) => item.name)
                      .where((name) => name.isNotEmpty)
                      .join(' / '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(color: palette.border),
          top: widget.showHeader
              ? BorderSide(color: palette.border.withValues(alpha: 0.55))
              : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
        child: Column(
          children: [
            ExplorerToolbar(
              searchController: searchController,
              onNewFile: (action) => unawaited(
                _createFileOfKind(
                  action,
                  parentId: presentation == FolderExplorerPresentation.gallery
                      ? controller.currentFolder.id
                      : null,
                ),
              ),
              onNewFolder: () => controller.beginCreate(
                WorkspaceExplorerDraftKind.folder,
                parentId: presentation == FolderExplorerPresentation.gallery
                    ? controller.currentFolder.id
                    : null,
              ),
              onCreateCollection: (kind) => unawaited(
                _createCollection(
                  kind,
                  parentId: presentation == FolderExplorerPresentation.gallery
                      ? controller.currentFolder.id
                      : null,
                ),
              ),
              onCreateDatabase: (kind) => unawaited(
                _createDatabase(
                  kind,
                  parentId: presentation == FolderExplorerPresentation.gallery
                      ? controller.currentFolder.id
                      : null,
                ),
              ),
              onPaste: controller.canPaste
                  ? () => unawaited(controller.paste())
                  : null,
              onRefresh: () {
                previewCache.clear();
                unawaited(controller.refresh());
              },
              onMore: _showMoreMenu,
              onSearchChanged: _scheduleSearch,
              canPaste: controller.canPaste,
              isSearching: controller.isSearching,
              trailing: widget.embedded
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onConnectSource != null) ...[
                          _ConnectSourceButton(
                            onPressed: widget.onConnectSource!,
                          ),
                          const SizedBox(width: 6),
                        ],
                        _ExplorerPresentationToggle(
                          presentation: presentation,
                          onChanged: (value) {
                            if (presentation != value) {
                              setState(() => presentation = value);
                            }
                          },
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 4),
            BreadcrumbBar(
              items: controller.breadcrumbs,
              onSelected: (id) => unawaited(_navigateTo(id)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final selected = controller.selection.length;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.66),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Text(
        selected > 0
            ? LocaleKeys.workspaceFolderExplorer_selectedCount.tr(
                args: [selected.toString()],
              )
            : LocaleKeys.workspaceFolderExplorer_itemCount.tr(
                args: [controller.rows.length.toString()],
              ),
        style: TextStyle(fontSize: 10.5, color: palette.textMuted),
      ),
    );
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
    CollectionKind? collectionKind;
    final action = await showExplorerContextMenu(
      context: context,
      globalPosition: position,
      item: item,
      canPaste: controller.canPaste,
      isFavorite: controller.viewForId(item.id)?.isFavorite ?? false,
      knowledgeMode: presentation == FolderExplorerPresentation.gallery,
      onCreateCollection: (kind) => collectionKind = kind,
      previewMode:
          controller.viewForId(item.id)?.previewMode ?? ViewPreviewMode.cover,
    );
    if (!mounted) {
      return;
    }
    if (collectionKind != null) {
      await _createCollection(collectionKind!, parentId: item.id);
      return;
    }
    if (action == null) {
      return;
    }
    switch (action) {
      case ExplorerContextAction.open:
        if (item.isFolder) {
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
    if (!mounted) {
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
    if (presentation == FolderExplorerPresentation.gallery && item.isFolder) {
      await _navigateTo(item.id);
      _beginGalleryCreate(kind, parentId: item.id);
      return;
    }
    controller.beginCreate(kind, parentId: item.id);
  }

  Future<void> _createFileInside(
    WorkspaceExplorerItem item,
    Offset position,
  ) async {
    final policy = widget.contentPolicy;
    final action = await showWorkspaceFileKindMenu(
      context: context,
      globalPosition: position,
      kinds: policy?.fileKinds,
      onCreateCollection: policy != null && !policy.allowsCollections
          ? null
          : (kind) => unawaited(_createCollection(kind, parentId: item.id)),
      onCreateDatabase: policy != null && !policy.allowsTables
          ? null
          : (kind) => unawaited(_createDatabase(kind, parentId: item.id)),
    );
    if (action == null || !mounted) {
      return;
    }
    if (presentation == FolderExplorerPresentation.gallery && item.isFolder) {
      await _navigateTo(item.id);
    }
    await _createFileOfKind(action, parentId: item.id);
  }

  Future<void> _createFileOfKind(
    WorkspaceFileMenuAction action, {
    String? parentId,
  }) async {
    final view = await controller.createFileOfKind(action, parentId: parentId);
    if (view != null && mounted) {
      _openView(view);
    }
  }

  Future<void> _createCollection(
    CollectionKind kind, {
    String? parentId,
  }) async {
    final created = await const CollectionService().createCollection(
      parentViewId: parentId ?? controller.currentFolder.id,
      kind: kind,
      name: CollectionRegistry.typeFor(kind).defaultName,
    );
    if (!mounted) {
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
    final view = await createWorkspaceDatabase(
      parentViewId: parentId ?? controller.currentFolder.id,
      kind: kind,
    );
    if (view != null && mounted) {
      _openView(view);
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

  Future<void> _showMoreMenu() async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset(box.size.width - 220, 76));
    final action = await showAppMenu<_ExplorerMoreAction>(
      context: context,
      globalPosition: origin,
      entries: [
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_importFile.tr(),
          icon: Icons.upload_file_rounded,
          value: _ExplorerMoreAction.importFile,
        ),
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_selectAll.tr(),
          icon: Icons.select_all_rounded,
          value: _ExplorerMoreAction.selectAll,
        ),
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_properties.tr(),
          icon: Icons.info_outline_rounded,
          value: _ExplorerMoreAction.properties,
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ExplorerMoreAction.importFile:
        await _importFile();
      case _ExplorerMoreAction.selectAll:
        controller.selectAll();
      case _ExplorerMoreAction.properties:
        await _showProperties(controller.currentFolder);
    }
  }

  /// The menu behind the toolbar's "more" button and behind a right click on
  /// empty space, so a folder can be filled from wherever the pointer is.
  Future<void> _showBackgroundMenu(Offset position) async {
    final knowledgeMode = presentation == FolderExplorerPresentation.gallery;
    final policy = widget.contentPolicy;
    WorkspaceFileMenuAction? kind;
    CollectionKind? collectionKind;
    WorkspaceTableKind? databaseLayout;
    final action = await showAppMenu<_GalleryMenuAction>(
      context: context,
      globalPosition: position,
      entries: [
        if (policy == null || policy.fileKinds.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
            icon: workspaceAddFileIcon,
            submenu: workspaceFileKindEntries(
              kinds: policy?.fileKinds,
              onSelected: (action) => kind = action,
            ),
          ),
        if (policy == null || policy.allowsFolders)
          AppMenuItem(
            label: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
            icon: workspaceAddFolderIcon,
            value: _GalleryMenuAction.newFolder,
          ),
        if (policy == null || policy.allowsTables)
          AppMenuItem(
            label: LocaleKeys.collections_database_table.tr(),
            icon: Icons.table_rows_rounded,
            submenu: databaseLayoutEntries(
              onSelected: (selected) => databaseLayout = selected,
            ),
          ),
        if (policy == null || policy.allowsCollections)
          AppMenuItem(
            label: LocaleKeys.collections_newCollection.tr(),
            icon: collectionAddIcon,
            submenu: collectionKindEntries(
              onSelected: (selected) => collectionKind = selected,
            ),
          ),
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_importFile.tr(),
          icon: Icons.arrow_downward_rounded,
          value: _GalleryMenuAction.importFile,
        ),
        if (controller.canPaste)
          AppMenuItem(
            label: LocaleKeys.workspaceFolderExplorer_paste.tr(),
            icon: Icons.content_paste_rounded,
            value: _GalleryMenuAction.paste,
          ),
        const AppMenuSeparator(),
        if (widget.onConnectSource != null)
          AppMenuItem(
            label: LocaleKeys.providers_connectThisFolder.tr(),
            icon: Icons.cloud_sync_rounded,
            value: _GalleryMenuAction.connectSource,
          ),
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_refresh.tr(),
          icon: Icons.refresh_rounded,
          value: _GalleryMenuAction.refresh,
        ),
        AppMenuItem(
          label: GalleryCardSizeStore.value.label,
          icon: Icons.tune_rounded,
          value: _GalleryMenuAction.cardSize,
        ),
        AppMenuItem(
          label: knowledgeMode
              ? LocaleKeys.workspaceFolderExplorer_treeView.tr()
              : LocaleKeys.workspaceFolderExplorer_galleryView.tr(),
          icon: knowledgeMode
              ? Icons.account_tree_rounded
              : Icons.grid_view_rounded,
          value: _GalleryMenuAction.switchPresentation,
        ),
      ],
    );
    if (!mounted) {
      return;
    }
    if (kind != null) {
      await _createFileOfKind(kind!, parentId: controller.currentFolder.id);
      return;
    }
    if (collectionKind != null) {
      await _createCollection(collectionKind!);
      return;
    }
    if (databaseLayout != null) {
      await _createDatabase(databaseLayout!);
      return;
    }
    if (action == null) {
      return;
    }
    switch (action) {
      case _GalleryMenuAction.addFile:
        break;
      case _GalleryMenuAction.newFolder:
        _beginGalleryCreate(
          WorkspaceExplorerDraftKind.folder,
          parentId: controller.currentFolder.id,
        );
      case _GalleryMenuAction.importFile:
        await _importFile();
      case _GalleryMenuAction.paste:
        await controller.paste(parentId: controller.currentFolder.id);
      case _GalleryMenuAction.refresh:
        previewCache.clear();
        await controller.refresh();
      case _GalleryMenuAction.cardSize:
        await showGalleryCardSizeMenu(
          context: context,
          globalPosition: position,
        );
      case _GalleryMenuAction.switchPresentation:
        setState(
          () => presentation = knowledgeMode
              ? FolderExplorerPresentation.tree
              : FolderExplorerPresentation.gallery,
        );
      case _GalleryMenuAction.connectSource:
        widget.onConnectSource?.call();
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker().pickFiles(
      dialogTitle: LocaleKeys.workspaceFolderExplorer_importDialogTitle.tr(),
      allowMultiple: true,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty || !mounted) {
      return;
    }
    final userProfile = context.read<UserWorkspaceBloc?>()?.state.userProfile;
    final parentId = controller.selectedOrCurrentFolderId;
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null || path.isEmpty) {
        controller.showError(
          LocaleKeys.workspaceFolderExplorer_localFileUnavailable.tr(),
        );
        return;
      }
      final imported = await service.importBinaryFile(
        parentViewId: parentId,
        file: XFile(path, name: picked.name),
        userProfile: userProfile,
      );
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
    if (controller.selection.isEmpty) {
      return;
    }
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
    if (confirmed ?? false) {
      final ids = controller.selection.ids.toList(growable: false);
      await controller.deleteSelection();
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
              WorkspaceItemIcon(item: item, size: 20),
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

/// Offers to back this folder with a service.
///
/// It sits on the toolbar rather than only in the background menu: a folder
/// that can be a Google Drive folder has to say so where somebody looking at
/// the folder will see it.
class _ConnectSourceButton extends StatefulWidget {
  const _ConnectSourceButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_ConnectSourceButton> createState() => _ConnectSourceButtonState();
}

class _ConnectSourceButtonState extends State<_ConnectSourceButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Tooltip(
      message: LocaleKeys.providers_connectThisFolder.tr(),
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: palette.hover.withValues(alpha: hovered ? 1 : 0.48),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border.withValues(alpha: 0.7)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_sync_rounded,
                  size: 15,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  LocaleKeys.providers_connect.tr(),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontVariations: const [FontVariation.weight(570)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExplorerPresentationToggle extends StatelessWidget {
  const _ExplorerPresentationToggle({
    required this.presentation,
    required this.onChanged,
  });

  final FolderExplorerPresentation presentation;
  final ValueChanged<FolderExplorerPresentation> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.hover.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ExplorerPresentationButton(
            selected: presentation == FolderExplorerPresentation.gallery,
            icon: Icons.grid_view_rounded,
            tooltip: LocaleKeys.workspaceFolderExplorer_galleryView.tr(),
            onPressed: () => onChanged(FolderExplorerPresentation.gallery),
          ),
          _ExplorerPresentationButton(
            selected: presentation == FolderExplorerPresentation.tree,
            icon: Icons.account_tree_rounded,
            tooltip: LocaleKeys.workspaceFolderExplorer_treeView.tr(),
            onPressed: () => onChanged(FolderExplorerPresentation.tree),
          ),
        ],
      ),
    );
  }
}

class _ExplorerPresentationButton extends StatelessWidget {
  const _ExplorerPresentationButton({
    required this.selected,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 27,
          height: 23,
          decoration: BoxDecoration(
            color: selected ? palette.floatingSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.shadow.withValues(alpha: 0.10),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 14.5,
            color: selected ? palette.accent : palette.textMuted,
          ),
        ),
      ),
    );
  }
}

enum _ExplorerMoreAction {
  importFile,
  selectAll,
  properties,
}

enum _GalleryMenuAction {
  addFile,
  newFolder,
  importFile,
  paste,
  refresh,
  cardSize,
  switchPresentation,
  connectSource,
}

class _ExplorerErrorBanner extends StatelessWidget {
  const _ExplorerErrorBanner({
    required this.message,
    required this.onDismiss,
    this.spacious = false,
  });

  final String message;
  final VoidCallback onDismiss;
  final bool spacious;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Container(
      margin: spacious
          ? EdgeInsets.symmetric(
              horizontal: KnowledgeGalleryLayout.minimumHorizontalPadding,
            )
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(spacious ? 12 : 0),
      ),
      padding: EdgeInsets.only(
        left: spacious ? 16 : 14,
        right: 5,
      ),
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
