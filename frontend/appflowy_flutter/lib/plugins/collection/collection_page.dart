import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_add_menu.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_content_policy.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/breadcrumb_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
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
  List<ViewPB> ancestors = const [];
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
    unawaited(_loadAncestors());
  }

  /// The folders the collection lives in, so it is placed in the workspace the
  /// same way a page or a folder is.
  Future<void> _loadAncestors() async {
    final result =
        await const WorkspaceItemService().getAncestors(widget.view.id);
    if (!mounted) {
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
      controller.updateRoot(widget.view);
    } else {
      unawaited(_loadAncestors());
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
        final view =
            definition.viewById(activeViewId) ?? definition.defaultView;
        return DecoratedBox(
          decoration: BoxDecoration(color: palette.background),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, palette, definition, view),
              Expanded(
                child: view.builder(context, _viewContext(view)),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CollectionMetrics.headerHorizontalPadding,
        CollectionMetrics.headerTopPadding,
        CollectionMetrics.headerHorizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ancestors.isNotEmpty) ...[
            _CollectionAncestors(
              ancestors: ancestors,
              palette: palette,
              onOpen: _openView,
            ),
            const SizedBox(height: 8),
          ] else ...[
            // A collection at the root has no chain above it, so the
            // workspace itself says where it lives.
            _WorkspaceCrumb(palette: palette),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 11, bottom: 2),
                child: Icon(
                  definition.icon,
                  size: CollectionMetrics.identityIconSize,
                  color: palette.accent,
                ),
              ),
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
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        fontVariations: const [FontVariation.weight(650)],
                        letterSpacing: -0.35,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(definition),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
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
              const SizedBox(width: 6),
              _CollectionAddButton(
                palette: palette,
                onPressed: _showAddMenu,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              CollectionViewSwitcher(
                palette: palette,
                views: definition.views,
                activeViewId: activeView.id,
                onChanged: _setActiveView,
              ),
              if (nested) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: BreadcrumbBar(
                    items: controller.breadcrumbs,
                    onSelected: (id) => unawaited(controller.navigateTo(id)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
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
    final definition = CollectionRegistry.typeFor(metadata.kind);
    final choice = await showCollectionAddMenu(
      context: context,
      globalPosition: position,
      policy: CollectionContentPolicy.of(metadata.kind),
    );
    if (choice == null || !mounted) {
      return;
    }
    // The collection page has no inline draft row, so the object is created
    // outright rather than asked for and left waiting for a name.
    final created = await applyCollectionAddChoice(
      context,
      choice: choice,
      collection: _viewContext(
        definition.viewById(activeViewId) ?? definition.defaultView,
      ),
      parentId: parentId,
    );
    if (created != null && mounted && choice is CollectionAddTable) {
      _openView(created);
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

/// The adaptive views a collection offers, as one segmented control.
/// The adaptive views a collection offers, as one row of tabs.
///
/// An underline rather than a pill: the row has to read as navigation sitting
/// on the page, not as a control floating above it.
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
    return SizedBox(
      height: CollectionMetrics.switcherHeight,
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
        ? palette.textPrimary
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
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: hovered && !widget.selected
                    ? palette.hover
                    : palette.hover.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.definition.icon, size: 14.5, color: foreground),
                  const SizedBox(width: 7),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.5,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
                      fontVariations: [
                        FontVariation.weight(widget.selected ? 620 : 545),
                      ],
                    ),
                    child: Text(widget.definition.label),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                height: 2,
                decoration: BoxDecoration(
                  color: widget.selected
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
    required this.controller,
    required this.palette,
    required this.onChanged,
  });

  final TextEditingController controller;
  final CollectionPalette palette;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final field = Color.alphaBlend(palette.hover, palette.background);
    return SizedBox(
      width: CollectionMetrics.searchFieldWidth,
      height: CollectionMetrics.searchFieldHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        cursorWidth: 1.4,
        cursorColor: palette.accent,
        style: TextStyle(color: palette.textPrimary, fontSize: 12.5),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: field,
          hoverColor: field,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 15,
            color: palette.textMuted,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          hintText: LocaleKeys.collections_searchPlaceholder.tr(),
          hintStyle: TextStyle(color: palette.textMuted, fontSize: 12.5),
          // A shade, not an outlined box.
          border: _border,
          enabledBorder: _border,
          focusedBorder: _border,
        ),
      ),
    );
  }

  OutlineInputBorder get _border => OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide.none,
      );
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
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: CollectionMetrics.searchFieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: hovered ? 0.16 : 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 15, color: palette.accent),
              const SizedBox(width: 5),
              Text(
                LocaleKeys.collections_add.tr(),
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontVariations: const [FontVariation.weight(600)],
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
