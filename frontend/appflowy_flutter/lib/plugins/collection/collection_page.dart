import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/breadcrumb_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  });

  final ViewPB view;
  final ValueChanged<ViewPB>? onOpen;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  static const _service = CollectionService();

  final TextEditingController searchController = TextEditingController();
  late final WorkspaceExplorerController controller;
  late CollectionMetadata metadata;
  late String activeViewId;
  Timer? searchDebounce;

  @override
  void initState() {
    super.initState();
    metadata = widget.view.collection ??
        const CollectionMetadata(kind: CollectionKind.book);
    activeViewId =
        CollectionRegistry.resolveView(metadata.kind, metadata.activeViewId).id;
    controller = WorkspaceExplorerController(
      root: widget.view,
      repository: const WorkspaceItemService(),
    );
    unawaited(controller.initialize());
  }

  @override
  void didUpdateWidget(covariant CollectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id == widget.view.id) {
      controller.updateRoot(widget.view);
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final palette = CollectionPalette.of(context, metadata.kind);
        final definition = CollectionRegistry.typeFor(metadata.kind);
        final view = definition.viewById(activeViewId) ?? definition.defaultView;
        return DecoratedBox(
          decoration: BoxDecoration(color: palette.background),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, palette, definition, view),
              Expanded(
                child: view.builder(
                  context,
                  CollectionViewContext(
                    collectionView: _currentView,
                    metadata: metadata,
                    definition: view,
                    explorer: controller,
                    onOpen: _openView,
                    onStateChanged: (state) =>
                        unawaited(_persistViewState(view.id, state)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CollectionMetrics.headerHorizontalPadding,
        CollectionMetrics.headerTopPadding,
        CollectionMetrics.headerHorizontalPadding,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: CollectionMetrics.identityTileSize,
                height: CollectionMetrics.identityTileSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(
                    CollectionMetrics.identityTileRadius,
                  ),
                  border: Border.all(color: palette.accentBorder, width: 0.6),
                ),
                child: Icon(
                  definition.icon,
                  size: CollectionMetrics.identityIconSize,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WorkspaceInlineEditableText(
                      key: const ValueKey('collection-title'),
                      text: title,
                      editingValue: root.name,
                      editing: controller.editingId == root.id,
                      onSubmitted: controller.commitRename,
                      onCancelled: controller.cancelEditing,
                      onDoubleTap: () => controller.beginRename(root.id),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(definition),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _CollectionSearchField(
                controller: searchController,
                palette: palette,
                onChanged: _scheduleSearch,
              ),
              const SizedBox(width: 8),
              _CollectionAddButton(
                palette: palette,
                onPressed: _showAddMenu,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CollectionViewSwitcher(
                palette: palette,
                views: definition.views,
                activeViewId: activeView.id,
                onChanged: _setActiveView,
              ),
              if (nested) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: BreadcrumbBar(
                    items: controller.breadcrumbs,
                    onSelected: (id) => unawaited(controller.navigateTo(id)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
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

  Future<void> _setActiveView(String id) async {
    if (id == activeViewId) {
      return;
    }
    setState(() => activeViewId = id);
    final next = metadata.copyWith(activeViewId: id);
    metadata = next;
    await _service.updateMetadata(view: _currentView, metadata: next);
  }

  Future<void> _persistViewState(
    String viewId,
    Map<String, dynamic> state,
  ) async {
    final next = metadata.withStateFor(viewId, state);
    if (!mounted) {
      return;
    }
    setState(() => metadata = next);
    await _service.updateMetadata(view: _currentView, metadata: next);
  }

  Future<void> _showAddMenu(Offset position) async {
    final parentId = controller.currentFolder.id;
    final action = await showAppMenu<WorkspaceFileMenuAction>(
      context: context,
      globalPosition: position,
      width: WorkspaceFileKindMenuStyle.width,
      entries: [
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
          icon: workspaceAddFolderIcon,
          onSelected: () => controller.beginCreate(
            WorkspaceExplorerDraftKind.folder,
            parentId: parentId,
          ),
        ),
        ...workspaceFileKindEntries(),
      ],
    );
    if (action == null) {
      return;
    }
    await controller.createFileOfKind(action, parentId: parentId);
  }
}

/// The adaptive views a collection offers, as one segmented control.
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
    return Container(
      height: CollectionMetrics.switcherHeight,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(CollectionMetrics.switcherRadius),
        border: Border.all(color: palette.border, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final view in views)
            _CollectionViewSegment(
              palette: palette,
              definition: view,
              selected: view.id == activeViewId,
              onTap: () => onChanged(view.id),
            ),
        ],
      ),
    );
  }
}

class _CollectionViewSegment extends StatefulWidget {
  const _CollectionViewSegment({
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
  State<_CollectionViewSegment> createState() => _CollectionViewSegmentState();
}

class _CollectionViewSegmentState extends State<_CollectionViewSegment> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final foreground = widget.selected
        ? palette.accent
        : hovered
            ? palette.textPrimary
            : palette.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.accentSoft
                : hovered
                    ? palette.hover
                    : Colors.transparent,
            borderRadius:
                BorderRadius.circular(CollectionMetrics.switcherSegmentRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.definition.icon, size: 15, color: foreground),
              const SizedBox(width: 6),
              Text(
                widget.definition.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionSearchField extends StatelessWidget {
  const _CollectionSearchField({
    required this.controller,
    required this.palette,
    required this.onChanged,
  });

  final TextEditingController controller;
  final CollectionPalette palette;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CollectionMetrics.searchFieldWidth,
      height: CollectionMetrics.searchFieldHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: palette.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.surface,
          hoverColor: palette.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: palette.textMuted,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          hintText: LocaleKeys.collections_searchPlaceholder.tr(),
          hintStyle: TextStyle(color: palette.textMuted, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: palette.border, width: 0.6),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: palette.border, width: 0.6),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: palette.accentBorder),
          ),
        ),
      ),
    );
  }
}

class _CollectionAddButton extends StatefulWidget {
  const _CollectionAddButton({required this.palette, required this.onPressed});

  final CollectionPalette palette;
  final ValueChanged<Offset> onPressed;

  @override
  State<_CollectionAddButton> createState() => _CollectionAddButtonState();
}

class _CollectionAddButtonState extends State<_CollectionAddButton> {
  final GlobalKey anchor = GlobalKey();
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: AnimatedContainer(
          key: anchor,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          height: CollectionMetrics.searchFieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.08),
                    palette.accentSoft,
                  )
                : palette.accentSoft,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: palette.accentBorder, width: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: palette.accent),
              const SizedBox(width: 5),
              Text(
                LocaleKeys.collections_add.tr(),
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open() {
    final box = anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    widget.onPressed(box.localToGlobal(Offset(0, box.size.height + 6)));
  }
}
