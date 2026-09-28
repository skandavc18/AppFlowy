import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_context_menu.dart';
import 'package:appflowy/plugins/collection/providers/external_file_stage.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How external content is laid out.
///
/// The same four readings a workspace folder has, so a Drive folder and a
/// workspace folder are looked at in exactly the same ways.
enum ExternalLayout {
  gallery,
  thumbnail,
  list,
  compact;

  IconData get icon => switch (this) {
        ExternalLayout.gallery => Icons.grid_view_rounded,
        ExternalLayout.thumbnail => Icons.apps_rounded,
        ExternalLayout.list => Icons.view_list_rounded,
        ExternalLayout.compact => Icons.reorder_rounded,
      };

  String get label => switch (this) {
        ExternalLayout.gallery => LocaleKeys.providers_layout_gallery.tr(),
        ExternalLayout.thumbnail => LocaleKeys.providers_layout_thumbnail.tr(),
        ExternalLayout.list => LocaleKeys.providers_layout_list.tr(),
        ExternalLayout.compact => LocaleKeys.providers_layout_compact.tr(),
      };

  bool get isGrid => this == gallery || this == thumbnail;

  /// The width a card aims for. The row count is derived from it so a card is
  /// never stretched half again its size to fill a line.
  double get targetWidth => switch (this) {
        ExternalLayout.gallery => 232,
        ExternalLayout.thumbnail => 148,
        _ => 0,
      };

  double get rowHeight => this == compact ? 30 : 40;
}

/// Everything a service holds, drawn the way the workspace draws its own.
///
/// It takes [ProviderNode]s rather than workspace items on purpose: nothing in
/// here knows which service answered, so one file serves Immich, Google
/// Photos, Drive, OneDrive and Box.
class ExternalContentView extends StatefulWidget {
  const ExternalContentView({
    super.key,
    required this.controller,
    required this.palette,
    this.layout = ExternalLayout.gallery,
    this.onLayoutChanged,
    this.parentId,
    this.onOpenContainer,
    this.onAllowChanges,
    this.header,
  });

  final ProviderController controller;
  final CollectionPalette palette;
  final ExternalLayout layout;
  final ValueChanged<ExternalLayout>? onLayoutChanged;

  /// Which container is being shown. Null is the collection's own root.
  final String? parentId;

  /// What opening a folder means. When null the view navigates itself.
  final ValueChanged<ProviderNode>? onOpenContainer;

  /// Offered when the binding is read only, so writing is reachable from
  /// where somebody notices they cannot write.
  final VoidCallback? onAllowChanges;

  final Widget? header;

  @override
  State<ExternalContentView> createState() => _ExternalContentViewState();
}

class _ExternalContentViewState extends State<ExternalContentView> {
  final List<ProviderNode> trail = <ProviderNode>[];
  final _findController = TextEditingController();
  final _findFocusNode = FocusNode(debugLabel: 'Search this external folder');
  bool _findOpen = false;
  int _findEpoch = 0;
  ModalRoute<dynamic>? _route;

  String? get containerId => trail.isEmpty ? widget.parentId : trail.last.id;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if ((_route != null && _route != route) ||
        !_hasCurrentRoute ||
        !TickerMode.of(context)) {
      _resetFind(afterBuild: true);
    }
    _route = route;
  }

  @override
  void didUpdateWidget(ExternalContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.parentId != widget.parentId) {
      trail.clear();
      _resetFind(afterBuild: true);
    }
  }

  @override
  void dispose() {
    _findController.dispose();
    _findFocusNode.dispose();
    super.dispose();
  }

  void _resetFind({bool afterBuild = false}) {
    _findOpen = false;
    final epoch = ++_findEpoch;
    _findFocusNode.unfocus();
    if (afterBuild) {
      // The old field (including selection overlays) may still be listening
      // during dependency/target rebuilds. Hide it now, notify only afterwards.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _findEpoch) _findController.clear();
      });
    } else {
      _findController.clear();
    }
  }

  void _dismissFind() {
    if (mounted) setState(_resetFind);
  }

  bool get _hasCurrentRoute {
    final seen = <ModalRoute<dynamic>>{};
    var route = ModalRoute.of(context);
    while (route != null && seen.add(route)) {
      if (!route.isCurrent) return false;
      final navigator = route.navigator;
      route = navigator != null && navigator.mounted
          ? ModalRoute.of(navigator.context)
          : null;
    }
    return true;
  }

  bool _isCurrentFolder(ProviderController controller, String? folder) =>
      mounted &&
      identical(widget.controller, controller) &&
      containerId == folder &&
      TickerMode.of(context) &&
      _hasCurrentRoute;

  void _openFind(ProviderController controller, String? folder) {
    if (!_isCurrentFolder(controller, folder)) return;
    // An explicit reopen can precede a queued lifecycle clear.
    if (!_findOpen) _findController.clear();
    final epoch = ++_findEpoch;
    setState(() => _findOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _findEpoch || !_findOpen) return;
      if (!_isCurrentFolder(controller, folder)) {
        _dismissFind();
        return;
      }
      _findFocusNode.requestFocus();
      _findController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findController.text.length,
      );
      _watchFind(epoch, controller, folder);
    });
  }

  void _watchFind(int epoch, ProviderController controller, String? folder) {
    if (!mounted || epoch != _findEpoch || !_findOpen) return;
    if (!_isCurrentFolder(controller, folder)) {
      _dismissFind();
      return;
    }
    // A non-opaque root dialog need not change a nested route or its ticker.
    // Observe existing frames while open; never schedule frames or provider IO.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _watchFind(epoch, controller, folder),
    );
  }

  void _changeFolder(VoidCallback navigate) {
    setState(() {
      _resetFind();
      navigate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = widget.palette;
    final folder = containerId;
    // Local Find must not invoke the provider's global/network search, or
    // accidentally filter cached siblings from a different folder.
    final loaded = controller.isSearching && !_findOpen
        ? controller.nodes
        : controller.childrenOf(folder);
    final query = _findOpen ? _findController.text.trim().toLowerCase() : '';
    final nodes = query.isEmpty
        ? loaded
        : loaded.where((node) {
            return node.name.toLowerCase().contains(query) ||
                node.kind.name.contains(query) ||
                (node.mimeType?.toLowerCase().contains(query) ?? false);
          }).toList(growable: false);

    return ContextualFindRegion(
      debugLabel: 'External folder',
      onFind: () => _openFind(controller, folder),
      onDismiss: _dismissFind,
      findOpen: _findOpen,
      findFocusNode: _findFocusNode,
      isActive: () => _isCurrentFolder(controller, folder),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) => unawaited(
          showExternalBackgroundMenu(
            context,
            controller: controller,
            containerId: containerId,
            position: details.globalPosition,
            onAllowChanges: widget.onAllowChanges,
          ),
        ),
        child: FileBrowserScrollView(
          controller: CollectionPageScrollScope.maybeOf(context),
          scrollKey: PageStorageKey('external-content-${widget.layout.name}'),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (FileBrowserPageHeader.maybeOf(context) case final header?)
                header,
              if (widget.header != null) widget.header!,
              if (_findOpen) _findBar(palette),
              if (trail.isNotEmpty)
                _Trail(
                  trail: trail,
                  palette: palette,
                  onSelect: (index) {
                    _changeFolder(
                      () => trail.removeRange(index + 1, trail.length),
                    );
                  },
                  onRoot: () => _changeFolder(trail.clear),
                ),
            ],
          ),
          slivers: [
            if (nodes.isEmpty)
              SliverFillRemaining(
                  hasScrollBody: false, child: _empty(palette, controller))
            else if (widget.layout.isGrid)
              _grid(nodes, palette)
            else
              _list(nodes, palette),
          ],
        ),
      ),
    );
  }

  Widget _findBar(CollectionPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _dismissFind,
          },
          child: Row(
            children: [
              Expanded(
                child: TextEntryShortcuts(
                  child: TextField(
                    key: const ValueKey('external-folder-find'),
                    controller: _findController,
                    focusNode: _findFocusNode,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: TextStyle(color: palette.textPrimary, fontSize: 13),
                    cursorColor: palette.accent,
                    decoration: InputDecoration(
                      labelText: 'Search this folder',
                      hintText: 'Name or type',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelStyle: TextStyle(color: palette.textSecondary),
                      hintStyle: TextStyle(color: palette.textMuted),
                      isDense: true,
                      filled: true,
                      fillColor: palette.surface,
                      hoverColor: palette.hover,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      prefixIcon: WorkspaceGlyph(
                        Icons.search_rounded,
                        size: 16,
                        color: palette.textMuted,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          WorkspaceChrome.controlRadius,
                        ),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              WorkspaceControlButton(
                icon: Icons.close_rounded,
                tooltip: 'Close folder search',
                onPressed: _dismissFind,
              ),
            ],
          ),
        ),
      );

  /// The menu a row or a card shows, so both offer exactly the same thing.
  void _showItemMenu(ProviderNode node, Offset position) => unawaited(
        showExternalItemMenu(
          context,
          controller: widget.controller,
          node: node,
          position: position,
          onOpen: () => _open(node),
        ),
      );

  Widget _empty(CollectionPalette palette, ProviderController controller) {
    if (controller.isLoadingContainer(containerId)) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Center(
      child: Text(
        _findOpen && _findController.text.trim().isNotEmpty
            ? 'No matches in this folder'
            : controller.isSearching && !_findOpen
                ? LocaleKeys.providers_noMatches.tr()
                : LocaleKeys.providers_nothingHere.tr(),
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _grid(List<ProviderNode> nodes, CollectionPalette palette) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        const padding = 24.0;
        final available = constraints.crossAxisExtent - padding * 2;
        // Rounding rather than flooring: a row that fits 2.9 cards becomes 3
        // narrow ones, not 2 that overshoot their target by half again.
        final columns =
            ((available + spacing) / (widget.layout.targetWidth + spacing))
                .round()
                .clamp(1, 10);
        final width = (available - spacing * (columns - 1)) / columns;
        final height = widget.layout == ExternalLayout.thumbnail
            ? width
            : width * 1.06 + 44;

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(padding, 4, padding, 28),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              mainAxisExtent: height,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _Card(
                key: ValueKey(nodes[index].id),
                node: nodes[index],
                controller: widget.controller,
                palette: palette,
                showName: widget.layout == ExternalLayout.gallery,
                onTap: () => _open(nodes[index]),
                onContextMenu: (position) =>
                    _showItemMenu(nodes[index], position),
              ),
              childCount: nodes.length,
              findChildIndexCallback: (key) {
                final index =
                    nodes.indexWhere((node) => ValueKey(node.id) == key);
                return index < 0 ? null : index;
              },
            ),
          ),
        );
      },
    );
  }

  Widget _list(List<ProviderNode> nodes, CollectionPalette palette) {
    final compact = widget.layout == ExternalLayout.compact;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
      sliver: SliverFixedExtentList(
        itemExtent: widget.layout.rowHeight + 2,
        delegate: SliverChildBuilderDelegate(
          (context, index) => _Row(
            key: ValueKey(nodes[index].id),
            node: nodes[index],
            controller: widget.controller,
            palette: palette,
            compact: compact,
            onTap: () => _open(nodes[index]),
            onContextMenu: (position) => _showItemMenu(nodes[index], position),
          ),
          childCount: nodes.length,
          findChildIndexCallback: (key) {
            final index = nodes.indexWhere((node) => ValueKey(node.id) == key);
            return index < 0 ? null : index;
          },
        ),
      ),
    );
  }

  void _open(ProviderNode node) {
    if (node.isFolder) {
      final handler = widget.onOpenContainer;
      if (handler != null) {
        _dismissFind();
        handler(node);
        return;
      }
      _changeFolder(() => trail.add(node));
      unawaited(widget.controller.ensureLoaded(node.id));
      return;
    }

    unawaited(
      showExternalFile(
        context,
        controller: widget.controller,
        node: node,
        siblings: widget.controller.childrenOf(containerId),
      ),
    );
  }
}

class _Card extends StatefulWidget {
  const _Card({
    super.key,
    required this.node,
    required this.controller,
    required this.palette,
    required this.showName,
    required this.onTap,
    required this.onContextMenu,
  });

  final ProviderNode node;
  final ProviderController controller;
  final CollectionPalette palette;
  final bool showName;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final palette = widget.palette;
    final thumbnail = widget.controller.thumbnailFor(node.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ViewerCard(
                  reactsToPointer: false,
                  elevation: hovered
                      ? ViewerCardElevation.raised
                      : ViewerCardElevation.resting,
                  color: thumbnail == null ? palette.surface : null,
                  child: _Artwork(
                    node: node,
                    palette: palette,
                    thumbnail: thumbnail,
                  ),
                ),
              ),
              if (widget.showName) ...[
                const SizedBox(height: 8),
                Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                    fontVariations: const [FontVariation.weight(560)],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitleFor(node),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.node,
    required this.palette,
    required this.thumbnail,
  });

  final ProviderNode node;
  final CollectionPalette palette;
  final String? thumbnail;

  @override
  Widget build(BuildContext context) {
    if (thumbnail != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(thumbnail!),
            fit: BoxFit.cover,
            // A cached thumbnail that has been swept while the wall was open
            // falls back to the glyph rather than a broken image box.
            errorBuilder: (_, __, ___) => _Glyph(node: node, palette: palette),
          ),
          if (node.kind == ProviderNodeKind.video)
            const Center(child: _PlayBadge()),
        ],
      );
    }
    return _Glyph(node: node, palette: palette);
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.node, required this.palette});

  final ProviderNode node;
  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) {
    final hue = _hueFor(node, palette);
    return ColoredBox(
      color: hue.withValues(alpha: 0.09),
      child: Center(
        child: Icon(providerNodeGlyph(node), size: 30, color: hue),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          size: 22,
          color: Colors.white,
        ),
      );
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.node,
    required this.controller,
    required this.palette,
    required this.compact,
    required this.onTap,
    required this.onContextMenu,
  });

  final ProviderNode node;
  final ProviderController controller;
  final CollectionPalette palette;
  final bool compact;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final palette = widget.palette;
    final thumbnail = widget.controller.thumbnailFor(node.id);
    final glyphSize = widget.compact ? 20.0 : 26.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 10),
          decoration: BoxDecoration(
            color: hovered ? palette.hover : palette.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: glyphSize,
                height: glyphSize,
                child: thumbnail == null
                    ? Icon(
                        providerNodeGlyph(node),
                        size: widget.compact ? 15 : 17,
                        color: _hueFor(node, palette),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.file(
                          File(thumbnail),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            providerNodeGlyph(node),
                            size: 15,
                            color: _hueFor(node, palette),
                          ),
                        ),
                      ),
              ),
              SizedBox(width: widget.compact ? 8 : 11),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: widget.compact ? 12.5 : 13.5,
                  ),
                ),
              ),
              if (!widget.compact) ...[
                SizedBox(
                  width: 72,
                  child: Text(
                    node.byteSize == null
                        ? ''
                        : formatProviderBytes(node.byteSize!),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 84,
                  child: Text(
                    providerRelativeTime(node.modifiedAt ?? node.createdAt),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Trail extends StatelessWidget {
  const _Trail({
    required this.trail,
    required this.palette,
    required this.onSelect,
    required this.onRoot,
  });

  final List<ProviderNode> trail;
  final CollectionPalette palette;
  final ValueChanged<int> onSelect;
  final VoidCallback onRoot;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
        child: Row(
          children: [
            _Crumb(
              label: LocaleKeys.providers_root.tr(),
              palette: palette,
              onTap: onRoot,
            ),
            for (var index = 0; index < trail.length; index++) ...[
              Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: palette.textMuted,
              ),
              Flexible(
                child: _Crumb(
                  label: trail[index].name,
                  palette: palette,
                  onTap: () => onSelect(index),
                ),
              ),
            ],
          ],
        ),
      );
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final CollectionPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textSecondary, fontSize: 11.5),
            ),
          ),
        ),
      );
}

/// The glyph one node wears. Deliberately the same family the workspace uses
/// for its own files.
IconData providerNodeGlyph(ProviderNode node) => switch (node.kind) {
      ProviderNodeKind.folder => Icons.folder_rounded,
      ProviderNodeKind.album => Icons.photo_album_rounded,
      ProviderNodeKind.image => Icons.image_rounded,
      ProviderNodeKind.video => Icons.movie_rounded,
      ProviderNodeKind.audio => Icons.audiotrack_rounded,
      ProviderNodeKind.pdf => Icons.picture_as_pdf_rounded,
      ProviderNodeKind.document => Icons.description_rounded,
      ProviderNodeKind.spreadsheet => Icons.table_chart_rounded,
      ProviderNodeKind.presentation => Icons.slideshow_rounded,
      ProviderNodeKind.markup => Icons.article_rounded,
      ProviderNodeKind.code => Icons.code_rounded,
      ProviderNodeKind.archive => Icons.folder_zip_rounded,
      ProviderNodeKind.other => Icons.insert_drive_file_rounded,
    };

Color _hueFor(ProviderNode node, CollectionPalette palette) =>
    switch (node.kind) {
      ProviderNodeKind.folder || ProviderNodeKind.album => palette.accent,
      ProviderNodeKind.image ||
      ProviderNodeKind.video =>
        const Color(0xFF7C5CD3),
      ProviderNodeKind.pdf => const Color(0xFFC2483C),
      ProviderNodeKind.spreadsheet => const Color(0xFF2E8B57),
      ProviderNodeKind.code => const Color(0xFF3B82F6),
      _ => palette.textMuted,
    };

String _subtitleFor(ProviderNode node) {
  if (node.isFolder) {
    final count = node.childCount;
    return count == null
        ? LocaleKeys.providers_noun_folder.tr()
        : LocaleKeys.providers_itemCount.tr(args: ['$count']);
  }
  final parts = <String>[
    if (node.byteSize != null) formatProviderBytes(node.byteSize!),
    providerRelativeTime(node.modifiedAt ?? node.createdAt),
  ];
  return parts.join(' · ');
}

/// Bytes, in the units a person reads.
String formatProviderBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}
