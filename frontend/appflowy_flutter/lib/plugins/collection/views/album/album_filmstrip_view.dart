import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_context_menu.dart';
import 'package:appflowy/plugins/collection/views/album/album_host.dart';
import 'package:appflowy/plugins/collection/views/album/album_lightbox.dart';
import 'package:appflowy/plugins/collection/views/album/album_thumbnail.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One large stage with the rest of the album running beneath it.
class AlbumFilmstripView extends StatelessWidget {
  const AlbumFilmstripView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) {
    return AlbumHost(
      collection: collection,
      builder: (context, controller, palette) => AlbumScaffold(
        controller: controller,
        palette: palette,
        padded: false,
        leading: albumArrangementControls(
          context: context,
          controller: controller,
          palette: palette,
          showTileSize: false,
        ),
        trailing: [
          AlbumToolbarButton(
            palette: palette,
            icon: Icons.slideshow_rounded,
            tooltip: LocaleKeys.collections_album_playSlideshow.tr(),
            onPressed: controller.ordered.isEmpty
                ? null
                : () => showAlbumLightbox(
                      context: context,
                      controller: controller,
                      palette: palette,
                      startId: controller.state.selectedId ??
                          controller.ordered.first.id,
                      startSlideshow: true,
                      onOpenInWorkspace: (item) => collection.onOpen(item.view),
                    ),
          ),
        ],
        child: controller.isEmpty
            ? AlbumEmptyState(
                palette: palette,
                icon: Icons.photo_library_rounded,
                title: LocaleKeys.collections_album_emptyTitle.tr(),
                description: LocaleKeys.collections_album_emptyDescription.tr(),
              )
            : _Filmstrip(
                controller: controller,
                palette: palette,
                parentViewId: collection.collectionView.id,
                onOpenInWorkspace: (item) => collection.onOpen(item.view),
              ),
      ),
    );
  }
}

class _Filmstrip extends StatefulWidget {
  const _Filmstrip({
    required this.controller,
    required this.palette,
    required this.parentViewId,
    required this.onOpenInWorkspace,
  });

  final AlbumController controller;
  final CollectionPalette palette;
  final String parentViewId;
  final ValueChanged<AlbumMediaItem> onOpenInWorkspace;

  @override
  State<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<_Filmstrip> {
  static const stripHeight = 108.0;

  final ScrollController stripController = ScrollController();
  late int index;

  @override
  void initState() {
    super.initState();
    index = widget.controller.indexOf(widget.controller.state.selectedId);
    _prime();
  }

  @override
  void didUpdateWidget(covariant _Filmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (index >= widget.controller.ordered.length) {
      index = 0;
    }
  }

  @override
  void dispose() {
    stripController.dispose();
    super.dispose();
  }

  void _prime() {
    final item = current;
    if (item != null) {
      unawaited(widget.controller.ensureMetadata(item));
    }
  }

  AlbumMediaItem? get current {
    final items = widget.controller.ordered;
    return index >= 0 && index < items.length ? items[index] : null;
  }

  void _select(int next) {
    final items = widget.controller.ordered;
    if (items.isEmpty) {
      return;
    }
    final resolved = next.clamp(0, items.length - 1);
    setState(() => index = resolved);
    widget.controller.select(items[resolved].id);
    unawaited(widget.controller.ensureMetadata(items[resolved]));
    _revealInStrip(resolved);
  }

  void _revealInStrip(int position) {
    if (!stripController.hasClients) {
      return;
    }
    const extent = stripHeight * 0.78 + AlbumMetrics.spacing;
    final target = position * extent -
        stripController.position.viewportDimension / 2 +
        extent / 2;
    unawaited(
      stripController.animateTo(
        target.clamp(0.0, stripController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _openLightbox(AlbumMediaItem item, {bool showInfo = false}) {
    showAlbumLightbox(
      context: context,
      controller: widget.controller,
      palette: widget.palette,
      startId: item.id,
      startWithInfo: showInfo,
      onOpenInWorkspace: widget.onOpenInWorkspace,
    );
  }

  void _itemMenu(AlbumMediaItem item, Offset position) {
    showAlbumItemMenu(
      context: context,
      globalPosition: position,
      controller: widget.controller,
      palette: widget.palette,
      item: item,
      onOpen: () => _openLightbox(item),
      onOpenInfo: () => _openLightbox(item, showInfo: true),
      onSlideshowFromHere: () => showAlbumLightbox(
        context: context,
        controller: widget.controller,
        palette: widget.palette,
        startId: item.id,
        startSlideshow: true,
        onOpenInWorkspace: widget.onOpenInWorkspace,
      ),
      onOpenInWorkspace: widget.onOpenInWorkspace,
    );
  }

  void _backgroundMenu(Offset position) {
    showAlbumBackgroundMenu(
      context: context,
      globalPosition: position,
      controller: widget.controller,
      palette: widget.palette,
      parentViewId: widget.parentViewId,
      showTileSize: false,
      onSlideshow: () {
        final first = widget.controller.visual.firstOrNull;
        if (first != null) {
          showAlbumLightbox(
            context: context,
            controller: widget.controller,
            palette: widget.palette,
            startId: first.id,
            startSlideshow: true,
            onOpenInWorkspace: widget.onOpenInWorkspace,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final items = widget.controller.ordered;
    final item = current;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: item == null
                    ? const SizedBox.shrink()
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (details) =>
                            _itemMenu(item, details.globalPosition),
                        child: _Stage(
                          item: item,
                          palette: palette,
                          onOpenFullscreen: () => _openLightbox(item),
                        ),
                      ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: _StripArrow(
                  palette: palette,
                  icon: Icons.chevron_left_rounded,
                  onPressed: index > 0 ? () => _select(index - 1) : null,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _StripArrow(
                  palette: palette,
                  icon: Icons.chevron_right_rounded,
                  onPressed: index < items.length - 1
                      ? () => _select(index + 1)
                      : null,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: stripHeight,
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(top: BorderSide(color: palette.border, width: 0.6)),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) =>
                _backgroundMenu(details.globalPosition),
            child: ListView.separated(
              controller: stripController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AlbumMetrics.gutter,
                vertical: 12,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AlbumMetrics.spacing),
              itemBuilder: (context, position) {
                final selected = position == index;
                return GestureDetector(
                  onTap: () => _select(position),
                  onSecondaryTapDown: (details) =>
                      _itemMenu(items[position], details.globalPosition),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: AlbumMetrics.motion,
                      curve: AlbumMetrics.curve,
                      width: stripHeight * 0.78,
                      padding: EdgeInsets.all(selected ? 2 : 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: selected
                            ? Border.all(color: palette.accent, width: 2)
                            : null,
                      ),
                      child: AlbumThumbnail(
                        item: items[position],
                        palette: palette,
                        decodeWidth: stripHeight,
                        radius: 7,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.item,
    required this.palette,
    required this.onOpenFullscreen,
  });

  final AlbumMediaItem item;
  final CollectionPalette palette;
  final VoidCallback onOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 20, 56, 16),
        child: Column(
          children: [
            Expanded(
              child: item.kind == AlbumMediaKind.image
                  ? GestureDetector(
                      onDoubleTap: onOpenFullscreen,
                      child: item.isLocal
                          ? Image.file(
                              File(item.path),
                              errorBuilder: (context, _, __) => Icon(
                                Icons.broken_image_rounded,
                                size: 30,
                                color: palette.textMuted,
                              ),
                            )
                          : Icon(
                              Icons.cloud_off_rounded,
                              size: 30,
                              color: palette.textMuted,
                            ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              item.kind == AlbumMediaKind.audio ? 560 : 1180,
                        ),
                        child: FileMediaPlayer(
                          key: ValueKey('filmstrip-${item.id}'),
                          url: item.path,
                          name: item.name,
                          kind: item.kind == AlbumMediaKind.audio
                              ? FileMediaKind.audio
                              : FileMediaKind.video,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _StripArrow extends StatelessWidget {
  const _StripArrow({
    required this.palette,
    required this.icon,
    this.onPressed,
  });

  final CollectionPalette palette;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: AlbumToolbarButton(
        palette: palette,
        icon: icon,
        tooltip: icon == Icons.chevron_left_rounded
            ? LocaleKeys.collections_album_previous.tr()
            : LocaleKeys.collections_album_next.tr(),
        onPressed: onPressed,
      ),
    );
  }
}
