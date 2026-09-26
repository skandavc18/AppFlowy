import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_add_menu.dart';
import 'package:appflowy/plugins/collection/collection_icon_button.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_repository_view.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/external_collection_host.dart';
import 'package:appflowy/plugins/collection/providers/external_import.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/collection/providers/source_picker.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_optical_size.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_content_policy.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/breadcrumb_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The full window presentation of a collection.
///
/// The page owns the identity, the object graph and the view switcher; the
/// adaptive view registered for the collection type owns everything below it.
class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    required this.view,
    this.onOpen,
    this.controller,
    this.shellOwnsBreadcrumbs,
    this.service = const CollectionService(),
  });

  final ViewPB view;
  final ValueChanged<ViewPB>? onOpen;
  final CollectionService service;

  /// An embedding host may lend its already-loaded graph. It stays host-owned;
  /// key the page when replacing this controller or the collection identity.
  final WorkspaceExplorerController? controller;

  /// Null detects the full-page shell; standalone hosts retain navigation.
  final bool? shellOwnsBreadcrumbs;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode(debugLabel: 'collection-search');
  final GlobalKey _searchFieldKey = GlobalKey();
  late final WorkspaceExplorerController controller;
  late final bool ownsController;
  late CollectionMetadata metadata;
  late String activeViewId;
  List<ViewPB> ancestors = const [];
  Timer? searchDebounce;
  bool searchExpanded = false;
  bool _ancestorsRequested = false;
  bool _metadataRebuildScheduled = false;

  bool get _shellOwnsBreadcrumbs =>
      widget.shellOwnsBreadcrumbs ??
      (context.read<PageNotifier?>()?.plugin.id == widget.view.id &&
          context.findAncestorWidgetOfExactType<PageStack>() != null);

  bool get _canEdit {
    final access = context.read<PageAccessLevelBloc?>();
    return !_currentView.isLocked &&
        (access?.view.id != _currentView.id || access!.state.isEditable);
  }

  @override
  void initState() {
    super.initState();
    metadata = widget.view.collection ??
        const CollectionMetadata(kind: CollectionKind.book);
    activeViewId =
        CollectionRegistry.resolveView(metadata.kind, metadata.activeViewId).id;
    ownsController = widget.controller == null;
    controller = widget.controller ??
        WorkspaceExplorerController(
          root: widget.view,
          repository: const WorkspaceItemService(),
        );
    if (ownsController) unawaited(controller.initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_shellOwnsBreadcrumbs && !_ancestorsRequested) {
      _ancestorsRequested = true;
      unawaited(_loadAncestors());
    }
  }

  /// The folders the collection lives in, so it is placed in the workspace the
  /// same way a page or a folder is.
  Future<void> _loadAncestors() async {
    final viewId = widget.view.id;
    final result = await const WorkspaceItemService().getAncestors(viewId);
    if (!mounted || widget.view.id != viewId) {
      return;
    }
    result.fold(
      (views) => setState(() {
        ancestors = [
          for (final view in views)
            if (view.id != widget.view.id) view,
        ];
      }),
      (_) {},
    );
  }

  @override
  void didUpdateWidget(covariant CollectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id == widget.view.id) {
      if (oldWidget.view != widget.view) {
        controller.updateRoot(widget.view);
      }
    } else if (!_shellOwnsBreadcrumbs) {
      unawaited(_loadAncestors());
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<PageAccessLevelBloc?>();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final palette = CollectionPalette.of(context, metadata.kind);
        final definition = CollectionRegistry.typeFor(metadata.kind);
        final view = _viewFor(definition);
        return ContextualFindRegion(
          debugLabel: 'Collection search',
          onFind: _showSearch,
          onDismiss: _closeSearch,
          findOpen: searchExpanded || controller.query.isNotEmpty,
          findFocusNode: searchFocusNode,
          child: WorkspaceSurface(
            kind: WorkspaceSurfaceKind.canvas,
            radius: 0,
            child: ProviderSourceUpdate(
              onChanged: (source) => unawaited(_persistSource(source)),
              child: ProviderReconnectRequest(
                onReconnect: (source) => unawaited(_reconnect(source)),
                child: PremiumCoordinatedScrollScope(
                  child: NestedScrollView(
                    key: const ValueKey('collection-page-scroll-view'),
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverToBoxAdapter(
                        child: _buildHeader(context, palette, definition, view),
                      ),
                    ],
                    body: Builder(
                      // Resolve BELOW NestedScrollView, not from the page's own
                      // context. Only opted-in main scrollers borrow this owner.
                      builder: (context) => CollectionPageScrollScope(
                        controller: PrimaryScrollController.of(context),
                        child: Builder(
                          builder: (context) =>
                              view.builder(context, _viewContext(view)),
                        ),
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
  }

  CollectionViewContext _viewContext(CollectionViewDefinition definition) =>
      CollectionViewContext(
        collectionView: _currentView,
        metadata: metadata,
        definition: definition,
        explorer: controller,
        onOpen: _openView,
        onOpenView: (id) => unawaited(_setActiveView(id)),
        onStateChanged: (key, state) =>
            unawaited(_persistViewState(key, state)),
      );

  Widget _buildHeader(
    BuildContext context,
    CollectionPalette palette,
    CollectionTypeDefinition definition,
    CollectionViewDefinition activeView,
  ) {
    final root = controller.root;
    final title = root.name.trim().isEmpty
        ? LocaleKeys.collections_untitled.tr()
        : root.name;
    final nested = controller.breadcrumbs.length > 1;
    final current = _currentView;
    final cover = current.cover;
    final canEdit = _canEdit;
    return PreviewToolbarRegion(
      child: LayoutBuilder(
        builder: (headerContext, constraints) => ViewDecorationActions(
          view: current,
          visible: searchExpanded || controller.query.isNotEmpty,
          showIconAction: canEdit,
          showCoverAction: canEdit,
          showDownloadAction: true,
          leading: CollectionViewSwitcher(
            palette: palette,
            views: [
              for (final view in definition.views)
                if (view.availableFor(current.source)) view,
            ],
            activeViewId: activeView.id,
            onChanged: _setActiveView,
          ),
          userProfile: context.read<UserWorkspaceBloc?>()?.state.userProfile,
          onViewChanged: (updated) {
            final latest = _currentView;
            if (!_canEdit || updated.id != latest.id) return;
            final cover = updated.cover;
            controller.updateView(
              ViewPB()
                ..mergeFromMessage(latest)
                ..icon = updated.icon
                ..extra = cover == null
                    ? latest.extra
                    : ViewCoverCodec.mergeCover(latest.extra, cover),
            );
          },
          layoutBuilder: (iconActions, coverActions, pageActions) =>
              WorkspacePageHeader(
            maxWidth: double.infinity,
            contentInset: CollectionMetrics.gutter,
            leading: _shellOwnsBreadcrumbs
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ancestors.isNotEmpty)
                        _CollectionAncestors(
                          ancestors: ancestors,
                          palette: palette,
                          onOpen: _openView,
                        )
                      else
                        _WorkspaceCrumb(palette: palette),
                      const SizedBox(height: WorkspaceTokens.space6),
                    ],
                  ),
            cover: cover != null && !cover.isNone
                ? ViewCoverImage(
                    cover: cover,
                    userProfile:
                        context.read<UserWorkspaceBloc?>()?.state.userProfile,
                    width: double.infinity,
                  )
                : null,
            coverActions: coverActions,
            identity: WorkspacePageIdentity(
              key: const ValueKey('collection-page-identity'),
              icon: ExcludeFocus(
                excluding: !canEdit,
                child: IgnorePointer(
                  ignoring: !canEdit,
                  child: CollectionIconButton(
                    key: const ValueKey('collection-header-icon'),
                    view: current,
                    iconSize: CollectionMetrics.pageIconSize,
                    opticalRole: IconOpticalRole.header,
                    onViewChanged: (updated) => controller.updateView(
                      ViewPB()
                        ..mergeFromMessage(_currentView)
                        ..icon = updated.icon,
                    ),
                  ),
                ),
              ),
              iconActions: iconActions,
              title: ExcludeFocus(
                excluding: !canEdit,
                child: IgnorePointer(
                  ignoring: !canEdit,
                  child: WorkspaceInlineEditableText(
                    key: const ValueKey('collection-title'),
                    text: title,
                    editingValue: root.name,
                    maxLines: 2,
                    editing: controller.editingId == root.id,
                    onSubmitted: (name) => _canEdit
                        ? controller.commitRename(name)
                        : Future.value(false),
                    onCancelled: controller.cancelEditing,
                    onDoubleTap:
                        canEdit ? () => controller.beginRename(root.id) : null,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.pageTitle,
                      compact: constraints.maxWidth < 600,
                    ),
                  ),
                ),
              ),
              description: Text(definition.description),
              metadata: Wrap(
                spacing: WorkspaceTokens.space3,
                runSpacing: WorkspaceTokens.space2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_subtitle(definition)),
                  if (current.source.isRemote)
                    ProviderBadge(
                      source: current.source,
                      palette: palette,
                      detail: current.source.remoteName,
                      onTap: canEdit ? () => unawaited(_changeSource()) : null,
                    ),
                ],
              ),
              actions: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pageActions != null) pageActions,
                  if (nested) ...[
                    const SizedBox(height: WorkspaceTokens.space2),
                    // This is navigation INSIDE the collection, not the
                    // workspace ancestor trail owned by the shell.
                    BreadcrumbBar(
                      items: controller.breadcrumbs,
                      onSelected: (id) => unawaited(controller.navigateTo(id)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          children: [
            if (searchExpanded || controller.query.isNotEmpty)
              SizedBox(
                key: const ValueKey('collection-search'),
                width: (constraints.maxWidth - CollectionMetrics.gutter * 2)
                    .clamp(0.0, CollectionMetrics.searchFieldWidth)
                    .toDouble(),
                child: _CollectionSearchField(
                  key: _searchFieldKey,
                  controller: searchController,
                  focusNode: searchFocusNode,
                  palette: palette,
                  onChanged: _scheduleSearch,
                  onClose: _closeSearch,
                ),
              )
            else
              IconButton(
                tooltip: LocaleKeys.collections_searchPlaceholder.tr(),
                onPressed: _showSearch,
                style: WorkspaceChrome.controlStyle(context),
                icon: const WorkspaceGlyph(Icons.search_rounded),
              ),
            if (canEdit) ...[
              _CollectionAddButton(
                key: const ValueKey('collection-add'),
                palette: palette,
                onPressed: _showAddMenu,
              ),
              if (ProviderServices.hasRemoteOptions(metadata.kind))
                _SourceButton(
                  key: const ValueKey('collection-source'),
                  palette: palette,
                  source: current.source,
                  onPressed: _changeSource,
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSearch() {
    setState(() => searchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !searchExpanded) return;
      final field = _searchFieldKey.currentContext?.findRenderObject();
      if (field != null && field.attached) {
        // Reveal the whole control only when clipped. Top-aligning the inner
        // EditableText moves even a visible field, clips its decoration and
        // triggers a second native caret scroll that blocks pointer input.
        // Include the native scroll padding before handing focus to the field.
        field.showOnScreen(
          rect: _CollectionSearchField.scrollPadding.inflateRect(
            field.paintBounds,
          ),
        );
      }
      searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    searchDebounce?.cancel();
    searchController.clear();
    unawaited(controller.search(''));
    setState(() => searchExpanded = false);
  }

  String _subtitle(CollectionTypeDefinition definition) {
    final count = controller.rows.length;
    return [
      definition.label,
      count == 1
          ? LocaleKeys.collections_oneObject.tr()
          : LocaleKeys.collections_objectCount.tr(args: ['$count']),
    ].join('  ·  ');
  }

  void _openView(ViewPB view) {
    final onOpen = widget.onOpen;
    if (onOpen != null) {
      onOpen(view);
      return;
    }
    context.read<TabsBloc>().openPlugin(view);
  }

  /// The collection as the controller last saw it, so a rename or an icon
  /// change made elsewhere is not written back over.
  ViewPB get _currentView =>
      controller.viewForId(widget.view.id) ?? widget.view;

  void _scheduleSearch(String query) {
    searchDebounce?.cancel();
    searchDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(controller.search(query)),
    );
  }

  /// The view to show, ignoring one that no longer applies.
  ///
  /// A collection that was pointed at a service and then brought back home
  /// would otherwise be left looking at an empty pane.
  CollectionViewDefinition _viewFor(CollectionTypeDefinition definition) {
    final stored = definition.viewById(activeViewId);
    if (stored != null && stored.availableFor(_currentView.source)) {
      return stored;
    }
    return definition.defaultView;
  }

  Future<void> _setActiveView(String id) async {
    if (id == activeViewId) {
      return;
    }
    setState(() => activeViewId = id);
    final next = metadata.copyWith(activeViewId: id);
    metadata = next;
    await widget.service.updateMetadata(view: _currentView, metadata: next);
  }

  Future<void> _persistViewState(
    String viewId,
    Map<String, dynamic> state,
  ) async {
    final next = metadata.withStateFor(viewId, state);
    if (!mounted) {
      return;
    }
    // Readers flush their final position/time from dispose. Persist that
    // value immediately, but never dirty an ancestor while the tree is locked.
    metadata = next;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_metadataRebuildScheduled) {
        _metadataRebuildScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _metadataRebuildScheduled = false;
          if (mounted) setState(() {});
        });
      }
    } else {
      setState(() {});
    }
    await widget.service.updateMetadata(view: _currentView, metadata: next);
  }

  /// Asks what the collection should be backed by, and rebinds it.
  Future<void> _changeSource() async {
    if (!_canEdit) return;
    final view = _currentView;
    final previous = view.source;
    final chosen = await showCollectionSourcePicker(
      context,
      kind: metadata.kind,
      current: previous,
    );
    if (chosen == null || !mounted || chosen.cacheKey == previous.cacheKey) {
      return;
    }

    // Everything cached for the old binding is about content this collection
    // no longer shows, so it goes with the binding rather than lingering.
    if (previous.isRemote) {
      unawaited(ProviderCache.instance.evict(previous.cacheKey));
    }
    await _persistSource(chosen);
  }

  Future<void> _persistSource(CollectionSource source) async {
    final view = _currentView;
    await ViewBackendService.updateView(
      viewId: view.id,
      extra: source.mergeIntoExtra(view.extra),
    );
    if (!mounted) {
      return;
    }
    // The explorer holds the view every adaptive view reads, so it has to be
    // told or the switcher would keep handing out the old binding.
    controller.updateView(
      ViewPB()
        ..mergeFromMessage(view)
        ..extra = source.mergeIntoExtra(view.extra),
    );
    setState(() {});
  }

  Future<void> _showAddMenu(Offset position) async {
    if (!_canEdit) return;
    final parentId = controller.currentFolder.id;
    final definition = CollectionRegistry.typeFor(metadata.kind);
    final choice = await showCollectionAddMenu(
      context: context,
      globalPosition: position,
      policy: CollectionContentPolicy.of(metadata.kind),
      onImportFromService: (info) =>
          unawaited(_importFromService(info, parentId: parentId)),
    );
    if (choice == null || !mounted) {
      return;
    }
    // The collection page has no inline draft row, so the object is created
    // outright rather than asked for and left waiting for a name.
    final created = await applyCollectionAddChoice(
      context,
      choice: choice,
      collection: _viewContext(_viewFor(definition)),
      parentId: parentId,
    );
    if (created != null && mounted && choice is CollectionAddTable) {
      _openView(created);
    }
  }

  /// Signs in again to the account this collection reads through.
  Future<void> _reconnect(CollectionSource source) async {
    await reconnectProviderAccount(context, info: source.info);
    if (mounted) {
      setState(() {});
    }
  }

  /// Copies objects out of a connected service into this collection.
  /// This is how an album takes more photos out of a library later: the
  /// pictures become workspace files, so they outlive the picking session
  /// that produced them.
  Future<void> _importFromService(
    ProviderServiceInfo info, {
    required String parentId,
  }) async {
    final imported = await importFromService(
      context,
      parentViewId: parentId,
      info: info,
    );
    if (imported > 0 && mounted) {
      await controller.refresh();
    }
  }
}

/// Where the collection sits in the workspace, above its own name.
class _CollectionAncestors extends StatelessWidget {
  const _CollectionAncestors({
    required this.ancestors,
    required this.palette,
    required this.onOpen,
  });
  final List<ViewPB> ancestors;
  final CollectionPalette palette;
  final ValueChanged<ViewPB> onOpen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < ancestors.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 13,
                  color: palette.textMuted.withValues(alpha: 0.55),
                ),
              ),
            _CollectionAncestor(
              view: ancestors[index],
              palette: palette,
              onOpen: () => onOpen(ancestors[index]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The workspace a collection sits directly in.
class _WorkspaceCrumb extends StatelessWidget {
  const _WorkspaceCrumb({required this.palette});

  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) {
    final workspace =
        context.watch<UserWorkspaceBloc?>()?.state.currentWorkspace;
    final name = workspace?.name.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.workspaces_rounded,
          size: 13,
          color: palette.textMuted,
        ),
        const SizedBox(width: 5),
        Text(
          name?.isNotEmpty == true ? name! : LocaleKeys.sideBar_workspace.tr(),
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11.5,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _CollectionAncestor extends StatefulWidget {
  const _CollectionAncestor({
    required this.view,
    required this.palette,
    required this.onOpen,
  });
  final ViewPB view;
  final CollectionPalette palette;
  final VoidCallback onOpen;

  @override
  State<_CollectionAncestor> createState() => _CollectionAncestorState();
}

class _CollectionAncestorState extends State<_CollectionAncestor> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final name = widget.view.name.trim().isEmpty
        ? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr()
        : widget.view.name;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceItemIcon.fromView(
              view: widget.view,
              size: 13,
              color: hovered ? palette.textSecondary : palette.textMuted,
            ),
            const SizedBox(width: 5),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: hovered ? palette.textPrimary : palette.textMuted,
                fontSize: 11.5,
                height: 1.2,
              ),
              child: Text(name),
            ),
          ],
        ),
      ),
    );
  }
}

/// The adaptive views a collection offers, all visible without scrolling.
///
/// Native buttons wrap at the actual pane width/text scale. Navigation stays
/// visible independently of the contextual actions sharing its row.
class CollectionViewSwitcher extends StatelessWidget {
  const CollectionViewSwitcher({
    super.key,
    required this.palette,
    required this.views,
    required this.activeViewId,
    required this.onChanged,
  });

  final CollectionPalette palette;
  final List<CollectionViewDefinition> views;
  final String activeViewId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (views.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: const ValueKey('collection-view-tabs'),
      spacing: WorkspaceTokens.space1,
      runSpacing: WorkspaceTokens.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final view in views)
          _CollectionViewSegment(
            key: ValueKey(view.id),
            palette: palette,
            definition: view,
            selected: view.id == activeViewId,
            onTap: () => onChanged(view.id),
          ),
      ],
    );
  }
}

class _CollectionViewSegment extends StatelessWidget {
  const _CollectionViewSegment({
    super.key,
    required this.palette,
    required this.definition,
    required this.selected,
    required this.onTap,
  });

  final CollectionPalette palette;
  final CollectionViewDefinition definition;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? palette.textPrimary : palette.textSecondary;
    return Semantics(
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Stack(
          children: [
            TextButton(
              onPressed: onTap,
              style: WorkspaceChrome.controlStyle(context).copyWith(
                foregroundColor: WidgetStatePropertyAll(foreground),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WorkspaceGlyph(definition.icon, size: 15, color: foreground),
                  const SizedBox(width: 7),
                  Flexible(child: Text(definition.label)),
                ],
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                height: 2,
                decoration: BoxDecoration(
                  color: selected
                      ? palette.accent
                      : palette.accent.withValues(alpha: 0),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionSearchField extends StatelessWidget {
  const _CollectionSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.palette,
    required this.onChanged,
    required this.onClose,
  });

  static const scrollPadding = EdgeInsets.all(20);

  final TextEditingController controller;
  final FocusNode focusNode;
  final CollectionPalette palette;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final field = Color.alphaBlend(palette.hover, palette.background);
    return SizedBox(
      width: CollectionMetrics.searchFieldWidth,
      height: MediaQuery.textScalerOf(context).scale(13) + 20,
      child: TextEntryShortcuts(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          cursorWidth: 1.4,
          cursorColor: palette.accent,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 12.5,
            height: 1.2,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: field,
            hoverColor: field,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            prefixIcon: WorkspaceGlyph(
              Icons.search_rounded,
              size: 15,
              color: palette.textMuted,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            suffixIcon: IconButton(
              tooltip: LocaleKeys.button_close.tr(),
              onPressed: onClose,
              style: WorkspaceChrome.controlStyle(context).copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              icon: const WorkspaceGlyph(Icons.close_rounded, size: 16),
            ),
            hintText: LocaleKeys.collections_searchPlaceholder.tr(),
            hintStyle: TextStyle(
              color: palette.textMuted,
              fontSize: 12.5,
              height: 1.2,
            ),
            // A shade, not an outlined box.
            border: _border,
            enabledBorder: _border,
            focusedBorder:
                _border.copyWith(borderSide: BorderSide(color: palette.accent)),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder get _border => OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorkspaceChrome.controlRadius),
        borderSide: BorderSide(color: palette.accent.withValues(alpha: 0)),
      );
}

/// Where the collection's content comes from, and how to change it.
///
/// It sits beside the search field rather than in a menu because binding a
/// collection to a service is a first-class choice, not a setting.
class _SourceButton extends StatelessWidget {
  const _SourceButton({
    super.key,
    required this.palette,
    required this.source,
    required this.onPressed,
  });

  final CollectionPalette palette;
  final CollectionSource source;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final info = source.info;
    final remote = source.isRemote;
    return Tooltip(
      message: LocaleKeys.providers_changeSource.tr(),
      child: TextButton(
        onPressed: () async {
          final release = PreviewToolbarRegion.hold(context);
          try {
            await onPressed();
          } finally {
            release();
          }
        },
        style: WorkspaceChrome.controlStyle(
          context,
          accent: remote ? info.accent : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceGlyph(
              remote ? info.icon : Icons.cloud_sync_rounded,
              size: 15,
              color: remote ? info.accent : palette.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                remote ? info.label : LocaleKeys.providers_connect.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionAddButton extends StatefulWidget {
  const _CollectionAddButton({
    super.key,
    required this.palette,
    required this.onPressed,
  });

  final CollectionPalette palette;
  final Future<void> Function(Offset) onPressed;

  @override
  State<_CollectionAddButton> createState() => _CollectionAddButtonState();
}

class _CollectionAddButtonState extends State<_CollectionAddButton> {
  final GlobalKey anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return TextButton(
      key: anchor,
      onPressed: _open,
      style: WorkspaceChrome.controlStyle(context, accent: palette.accent),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceGlyph(Icons.add_rounded, size: 15, color: palette.accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              LocaleKeys.collections_add.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open() async {
    final box = anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final release = PreviewToolbarRegion.hold(context);
    try {
      await widget.onPressed(box.localToGlobal(Offset(0, box.size.height + 6)));
    } finally {
      release();
    }
  }
}
