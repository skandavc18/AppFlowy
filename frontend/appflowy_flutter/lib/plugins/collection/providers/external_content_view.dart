import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_context_menu.dart';
import 'package:appflowy/plugins/collection/providers/external_file_stage.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

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

  final Widget? header;

  @override
  State<ExternalContentView> createState() => _ExternalContentViewState();
}

class _ExternalContentViewState extends State<ExternalContentView> {
  final List<ProviderNode> trail = <ProviderNode>[];

  String? get containerId => trail.isEmpty ? widget.parentId : trail.last.id;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = widget.palette;
    final nodes = controller.isSearching
        ? controller.nodes
        : controller.childrenOf(containerId);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => unawaited(
        showExternalBackgroundMenu(
          context,
          controller: controller,
          containerId: containerId,
          position: details.globalPosition,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) widget.header!,
          if (trail.isNotEmpty)
            _Trail(
              trail: trail,
              palette: palette,
              onSelect: (index) {
                setState(() => trail.removeRange(index + 1, trail.length));
              },
              onRoot: () => setState(trail.clear),
            ),
          Expanded(
            child: nodes.isEmpty
                ? _empty(palette, controller)
                : widget.layout.isGrid
                    ? _grid(nodes, palette)
                    : _list(nodes, palette),
          ),
        ],
      ),
    );
  }

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
        controller.isSearching
            ? LocaleKeys.providers_noMatches.tr()
            : LocaleKeys.providers_nothingHere.tr(),
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _grid(List<ProviderNode> nodes, CollectionPalette palette) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        const padding = 24.0;
        final available = constraints.maxWidth - padding * 2;
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

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(padding, 4, padding, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: height,
          ),
          itemCount: nodes.length,
          itemBuilder: (context, index) => _Card(
            node: nodes[index],
            controller: widget.controller,
            palette: palette,
            showName: widget.layout == ExternalLayout.gallery,
            onTap: () => _open(nodes[index]),
            onContextMenu: (position) => _showItemMenu(nodes[index], position),
          ),
        );
      },
    );
  }

  Widget _list(List<ProviderNode> nodes, CollectionPalette palette) {
    final compact = widget.layout == ExternalLayout.compact;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
      itemExtent: widget.layout.rowHeight + 2,
      itemCount: nodes.length,
      itemBuilder: (context, index) => _Row(
        node: nodes[index],
        controller: widget.controller,
        palette: palette,
        compact: compact,
        onTap: () => _open(nodes[index]),
        onContextMenu: (position) => _showItemMenu(nodes[index], position),
      ),
    );
  }

  void _open(ProviderNode node) {
    if (node.isFolder) {
      final handler = widget.onOpenContainer;
      if (handler != null) {
        handler(node);
        return;
      }
      setState(() => trail.add(node));
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
            color: palette.hover.withValues(alpha: hovered ? 1 : 0),
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
