import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_context_menu.dart';
import 'package:appflowy/plugins/collection/views/album/album_host.dart';
import 'package:appflowy/plugins/collection/views/album/album_thumbnail.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Everything in the album that plays, as a queue with a player above it.
class AlbumPlaylistView extends StatelessWidget {
  const AlbumPlaylistView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) {
    return AlbumHost(
      collection: collection,
      needsDates: false,
      builder: (context, controller, palette) {
        final playable = controller.playable;
        return AlbumScaffold(
          controller: controller,
          palette: palette,
          padded: false,
          leading: albumArrangementControls(
            context: context,
            controller: controller,
            palette: palette,
            showTileSize: false,
          ),
          child: playable.isEmpty
              ? AlbumEmptyState(
                  palette: palette,
                  icon: Icons.queue_music_rounded,
                  title: LocaleKeys.collections_album_nothingToPlay.tr(),
                  description: LocaleKeys
                      .collections_album_nothingToPlayDescription
                      .tr(),
                )
              : _Playlist(
                  controller: controller,
                  palette: palette,
                  items: playable,
                  parentViewId: collection.collectionView.id,
                  onOpenInWorkspace: (item) => collection.onOpen(item.view),
                ),
        );
      },
    );
  }
}

class _Playlist extends StatefulWidget {
  const _Playlist({
    required this.controller,
    required this.palette,
    required this.items,
    required this.parentViewId,
    required this.onOpenInWorkspace,
  });

  final AlbumController controller;
  final CollectionPalette palette;
  final List<AlbumMediaItem> items;
  final String parentViewId;
  final ValueChanged<AlbumMediaItem> onOpenInWorkspace;

  @override
  State<_Playlist> createState() => _PlaylistState();
}

class _PlaylistState extends State<_Playlist> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    final selected = widget.controller.state.selectedId;
    final position = widget.items.indexWhere((item) => item.id == selected);
    index = position < 0 ? 0 : position;
  }

  @override
  void didUpdateWidget(covariant _Playlist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (index >= widget.items.length) {
      index = 0;
    }
  }

  AlbumMediaItem? get current =>
      index >= 0 && index < widget.items.length ? widget.items[index] : null;

  void _play(int position) {
    if (position < 0 || position >= widget.items.length) {
      return;
    }
    setState(() => index = position);
    widget.controller.select(widget.items[position].id);
  }

  void _itemMenu(AlbumMediaItem item, Offset position) {
    showAlbumItemMenu(
      context: context,
      globalPosition: position,
      controller: widget.controller,
      palette: widget.palette,
      item: item,
      onOpen: () => _play(widget.items.indexOf(item)),
      onOpenInfo: () => _play(widget.items.indexOf(item)),
      onSlideshowFromHere: () => _play(widget.items.indexOf(item)),
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
      onSlideshow: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final item = current;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) => item == null
                ? _backgroundMenu(details.globalPosition)
                : _itemMenu(item, details.globalPosition),
            child: ColoredBox(
              color: palette.background,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 22, 20, 24),
                child: item == null
                    ? const SizedBox.shrink()
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LocaleKeys.collections_album_nowPlaying
                              .tr()
                              .toUpperCase(),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 9.5,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: item.kind == AlbumMediaKind.audio
                                    ? 620
                                    : 1180,
                              ),
                              child: FileMediaPlayer(
                                key: ValueKey('playlist-${item.id}'),
                                url: item.path,
                                name: item.name,
                                kind: item.kind == AlbumMediaKind.audio
                                    ? FileMediaKind.audio
                                    : FileMediaKind.video,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            AlbumToolbarButton(
                              palette: palette,
                              icon: Icons.skip_previous_rounded,
                              tooltip:
                                  LocaleKeys.collections_album_previous.tr(),
                              onPressed:
                                  index > 0 ? () => _play(index - 1) : null,
                            ),
                            AlbumToolbarButton(
                              palette: palette,
                              icon: Icons.skip_next_rounded,
                              tooltip: LocaleKeys.collections_album_next.tr(),
                              onPressed: index < widget.items.length - 1
                                  ? () => _play(index + 1)
                                  : null,
                            ),
                            const Spacer(),
                            AlbumToolbarButton(
                              palette: palette,
                              icon: Icons.open_in_new_rounded,
                              tooltip: LocaleKeys
                                  .collections_album_openInWorkspace
                                  .tr(),
                              onPressed: () => widget.onOpenInWorkspace(item),
                            ),
                          ],
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ),
        Container(
          width: 316,
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(left: BorderSide(color: palette.border, width: 0.6)),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) =>
                _backgroundMenu(details.globalPosition),
            child: PremiumScrollScope(
              enabled: true,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: widget.items.length,
                itemBuilder: (context, position) => _QueueRow(
                  item: widget.items[position],
                  palette: palette,
                  number: position + 1,
                  playing: position == index,
                  onTap: () => _play(position),
                  onContextMenu: _itemMenu,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QueueRow extends StatefulWidget {
  const _QueueRow({
    required this.item,
    required this.palette,
    required this.number,
    required this.playing,
    required this.onTap,
    required this.onContextMenu,
  });

  final AlbumMediaItem item;
  final CollectionPalette palette;
  final int number;
  final bool playing;
  final VoidCallback onTap;
  final void Function(AlbumMediaItem item, Offset position) onContextMenu;

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
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
        onTap: widget.onTap,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(widget.item, details.globalPosition),
        child: AnimatedContainer(
          duration: AlbumMetrics.motion,
          curve: AlbumMetrics.curve,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: widget.playing
                ? palette.accentSoft
                : hovered
                    ? palette.hover
                    : palette.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: widget.playing
                    ? Icon(
                        Icons.equalizer_rounded,
                        size: 14,
                        color: palette.accent,
                      )
                    : Text(
                        '${widget.number}',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11,
                        ),
                      ),
              ),
              SizedBox(
                width: 52,
                height: 40,
                child: AlbumThumbnail(
                  item: widget.item,
                  palette: palette,
                  decodeWidth: 64,
                  radius: 6,
                  showKindBadge: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.playing
                        ? palette.textPrimary
                        : palette.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight:
                        widget.playing ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
