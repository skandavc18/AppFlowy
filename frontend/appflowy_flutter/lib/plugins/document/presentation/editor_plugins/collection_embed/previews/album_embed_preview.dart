import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/album/album_lightbox.dart';
import 'package:appflowy/plugins/collection/views/album/album_thumbnail.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/cover_flip.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

abstract final class AlbumEmbedStyles {
  static const cover = 'cover';
  static const grid = 'grid';
  static const slideshow = 'slideshow';
  static const collage = 'collage';
  static const timeline = 'timeline';
}

CollectionEmbedDefinition buildAlbumEmbedDefinition() =>
    CollectionEmbedDefinition(
      kind: CollectionKind.album,
      defaultItemLimit: 12,
      compactHeight: 150,
      mediumHeight: 300,
      largeHeight: 460,
      showsHeading: false,
      styles: const [
        CollectionEmbedStyle(
          id: AlbumEmbedStyles.cover,
          labelKey: LocaleKeys.collections_embed_styles_albumCover,
          icon: Icons.photo_album_rounded,
        ),
        CollectionEmbedStyle(
          id: AlbumEmbedStyles.grid,
          labelKey: LocaleKeys.collections_embed_styles_photoGrid,
          icon: Icons.grid_on_rounded,
          supportsColumns: true,
        ),
        CollectionEmbedStyle(
          id: AlbumEmbedStyles.slideshow,
          labelKey: LocaleKeys.collections_embed_styles_slideshow,
          icon: Icons.slideshow_rounded,
        ),
        CollectionEmbedStyle(
          id: AlbumEmbedStyles.collage,
          labelKey: LocaleKeys.collections_embed_styles_collage,
          icon: Icons.dashboard_rounded,
        ),
        CollectionEmbedStyle(
          id: AlbumEmbedStyles.timeline,
          labelKey: LocaleKeys.collections_embed_styles_albumTimeline,
          icon: Icons.calendar_view_day_rounded,
        ),
      ],
      builder: (context, embed) => AlbumEmbedPreview(embed: embed),
    );

class AlbumEmbedPreview extends StatefulWidget {
  const AlbumEmbedPreview({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  State<AlbumEmbedPreview> createState() => _AlbumEmbedPreviewState();
}

class _AlbumEmbedPreviewState extends State<AlbumEmbedPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController flip = AnimationController(
    vsync: this,
    duration: CollectionEmbedMetrics.flip,
    reverseDuration: const Duration(milliseconds: 460),
  );

  @override
  void dispose() {
    flip.dispose();
    super.dispose();
  }

  CollectionEmbedContext get embed => widget.embed;

  List<AlbumMediaItem> get media => albumMediaFrom(embed.children);

  @override
  Widget build(BuildContext context) {
    if (embed.controller.isLoading && embed.children.isEmpty) {
      return const CollectionEmbedSpinner();
    }
    final items = _limited(media);
    if (items.isEmpty) {
      return CollectionEmbedEmpty(
        theme: embed.theme,
        icon: Icons.photo_library_rounded,
        message: LocaleKeys.collections_album_emptyTitle.tr(),
        compact: embed.size.isCompact,
      );
    }
    return switch (embed.style) {
      AlbumEmbedStyles.grid => _Grid(embed: embed, items: items),
      AlbumEmbedStyles.slideshow => _Slideshow(embed: embed, items: items),
      AlbumEmbedStyles.collage => _Collage(embed: embed, items: items),
      AlbumEmbedStyles.timeline => _Timeline(embed: embed, items: items),
      _ => _AlbumCoverStage(embed: embed, items: items, flip: flip),
    };
  }

  List<AlbumMediaItem> _limited(List<AlbumMediaItem> all) {
    final limit = embed.settings.itemLimit ?? embed.definition.defaultItemLimit;
    return all.length <= limit ? all : all.take(limit).toList();
  }
}

/// Opens the application's own picture viewer on the item that was clicked.
///
/// The lightbox reads its media from an [AlbumController], so the widget
/// builds a throwaway one over the slice it is showing and drops it when the
/// viewer closes — nothing about the album is duplicated.
void openAlbumItem(
  BuildContext context,
  CollectionEmbedContext embed,
  List<AlbumMediaItem> items,
  int index,
) {
  if (items.isEmpty) {
    return;
  }
  final safe = index.clamp(0, items.length - 1);
  final controller = AlbumController(
    initialState: const <String, dynamic>{},
    onPersist: (_) {},
  )..setItems(items);
  unawaited(
    showAlbumLightbox(
      context: context,
      controller: controller,
      palette: embed.theme.palette,
      startId: items[safe].id,
      onOpenInWorkspace: (item) => embed.onOpenObject(item.view),
    ).whenComplete(controller.dispose),
  );
}

/// The album as a physical object: a cover that opens onto the pictures.
class _AlbumCoverStage extends StatelessWidget {
  const _AlbumCoverStage({
    required this.embed,
    required this.items,
    required this.flip,
  });

  final CollectionEmbedContext embed;
  final List<AlbumMediaItem> items;
  final AnimationController flip;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final chosen = embed.settings.coverId;
    final cover = items.firstWhere(
      (item) => item.id == chosen,
      orElse: () => items.first,
    );

    return Padding(
      padding: EdgeInsets.all(embed.size.isCompact ? 12 : 16),
      child: AnimatedBuilder(
        animation: flip,
        builder: (context, _) => CoverFlip(
          progress: flip.value,
          spineColor: theme.accent,
          cover: CollectionEmbedTappable(
            onTap: () => flip.forward(),
            lift: 0,
            growth: 1.008,
            builder: (context, hovered) => Stack(
              fit: StackFit.expand,
              children: [
                AlbumThumbnail(
                  item: cover,
                  palette: theme.palette,
                  radius: 4,
                  showKindBadge: false,
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0.45, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        embed.collection.name.isEmpty
                            ? LocaleKeys.collections_untitled.tr()
                            : embed.collection.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: embed.size.isCompact ? 14 : 18,
                          height: 1.2,
                          letterSpacing: -0.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (embed.settings.showMetadata) ...[
                        const SizedBox(height: 3),
                        Text(
                          items.length == 1
                              ? LocaleKeys.collections_album_onePhoto.tr()
                              : LocaleKeys.collections_album_itemCount
                                  .tr(args: ['${embed.children.length}']),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hovered)
                  const Center(
                    child: _OpenAlbumBadge(),
                  ),
              ],
            ),
          ),
          contents: _AlbumPages(
            embed: embed,
            items: items,
            onClose: flip.reverse,
          ),
        ),
      ),
    );
  }
}

class _OpenAlbumBadge extends StatelessWidget {
  const _OpenAlbumBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              LocaleKeys.collections_embed_openAlbum.tr(),
              style: const TextStyle(color: Colors.white, fontSize: 11.5),
            ),
          ],
        ),
      );
}

class _AlbumPages extends StatelessWidget {
  const _AlbumPages({
    required this.embed,
    required this.items,
    required this.onClose,
  });

  final CollectionEmbedContext embed;
  final List<AlbumMediaItem> items;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.sunken,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    embed.collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.title(context, size: 12.5),
                  ),
                ),
                CollectionEmbedButton(
                  theme: theme,
                  icon: Icons.close_rounded,
                  size: 22,
                  iconSize: 14,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(child: _Grid(embed: embed, items: items, padding: 8)),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.embed,
    required this.items,
    this.padding = 14,
  });

  final CollectionEmbedContext embed;
  final List<AlbumMediaItem> items;
  final double padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = embed.settings.columns ??
              (constraints.maxWidth / 118).floor().clamp(2, 8);
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(padding, 6, padding, padding),
            physics: const ClampingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => CollectionEmbedTappable(
              onTap: () => openAlbumItem(context, embed, items, index),
              onSecondaryTap: embed.onShowMenu,
              lift: 0,
              growth: 1.03,
              builder: (context, hovered) => AlbumThumbnail(
                item: items[index],
                palette: embed.theme.palette,
                radius: 7,
                decodeWidth: constraints.maxWidth / columns,
              ),
            ),
          );
        },
      );
}

/// Photos cycling on their own, the way a photo frame does.
class _Slideshow extends StatefulWidget {
  const _Slideshow({required this.embed, required this.items});

  final CollectionEmbedContext embed;
  final List<AlbumMediaItem> items;

  @override
  State<_Slideshow> createState() => _SlideshowState();
}

class _SlideshowState extends State<_Slideshow> {
  int index = 0;
  bool playing = true;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant _Slideshow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (index >= widget.items.length) {
      index = 0;
    }
  }

  void _restart() {
    timer?.cancel();
    if (!playing || widget.items.length < 2) {
      return;
    }
    timer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _step(1),
    );
  }

  void _step(int delta) {
    if (!mounted || widget.items.isEmpty) {
      return;
    }
    setState(
      () => index = (index + delta + widget.items.length) % widget.items.length,
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.embed.theme;
    final item = widget.items[index.clamp(0, widget.items.length - 1)];
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: CollectionEmbedMetrics.reveal,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: CollectionEmbedTappable(
            key: ValueKey(item.id),
            onTap: () =>
                openAlbumItem(context, widget.embed, widget.items, index),
            onSecondaryTap: widget.embed.onShowMenu,
            lift: 0,
            builder: (context, hovered) => AlbumThumbnail(
              item: item,
              palette: theme.palette,
              radius: 0,
              showKindBadge: false,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 62,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 10,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 11.5,
                  ),
                ),
              ),
              _SlideshowControl(
                icon: Icons.chevron_left_rounded,
                onTap: () => _step(-1),
              ),
              _SlideshowControl(
                icon: playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onTap: () {
                  setState(() => playing = !playing);
                  _restart();
                },
              ),
              _SlideshowControl(
                icon: Icons.chevron_right_rounded,
                onTap: () => _step(1),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 4,
          child: Row(
            children: [
              for (var i = 0; i < math.min(widget.items.length, 12); i++)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: i == index ? 0.9 : 0.32),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlideshowControl extends StatelessWidget {
  const _SlideshowControl({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CollectionEmbedTappable(
        onTap: onTap,
        lift: 0,
        growth: 1.1,
        builder: (context, hovered) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(
            icon,
            size: 18,
            color: Colors.white.withValues(alpha: hovered ? 1 : 0.72),
          ),
        ),
      );
}

/// One large picture with a few smaller ones around it — the asymmetric
/// arrangement a printed album uses, not a uniform grid.
class _Collage extends StatelessWidget {
  const _Collage({required this.embed, required this.items});

  final CollectionEmbedContext embed;
  final List<AlbumMediaItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final shown = items.take(5).toList();
    Widget tile(int index, {double radius = 8}) => CollectionEmbedTappable(
          onTap: () => openAlbumItem(context, embed, items, index),
          onSecondaryTap: embed.onShowMenu,
          lift: 0,
          growth: 1.02,
          builder: (context, hovered) => AlbumThumbnail(
            item: shown[index],
            palette: theme.palette,
            radius: radius,
            showKindBadge: false,
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: shown.length == 1
          ? tile(0, radius: 12)
          : Row(
              children: [
                Expanded(flex: 3, child: tile(0, radius: 12)),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Expanded(child: tile(1)),
                      if (shown.length > 2) ...[
                        const SizedBox(height: 6),
                        Expanded(
                          child: shown.length > 3
                              ? Row(
                                  children: [
                                    Expanded(child: tile(2)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: shown.length > 4
                                          ? Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                tile(3),
                                                if (items.length > 5)
                                                  _MoreOverlay(
                                                    theme: theme,
                                                    count: items.length - 4,
                                                  ),
                                              ],
                                            )
                                          : tile(3),
                                    ),
                                  ],
                                )
                              : tile(2),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _MoreOverlay extends StatelessWidget {
  const _MoreOverlay({required this.theme, required this.count});

  final CollectionEmbedTheme theme;
  final int count;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius:
                BorderRadius.circular(CollectionEmbedMetrics.tileRadius),
          ),
          child: Center(
            child: Text(
              '+$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
}

/// Photos grouped by the day they were taken.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.embed, required this.items});

  final CollectionEmbedContext embed;
  final List<AlbumMediaItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final groups = <String, List<AlbumMediaItem>>{};
    for (final item in items) {
      final date = item.modifiedAt;
      final label = date == null
          ? LocaleKeys.collections_album_undated.tr()
          : DateFormat.yMMMd().format(date);
      groups.putIfAbsent(label, () => <AlbumMediaItem>[]).add(item);
    }
    final labels = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      physics: const ClampingScrollPhysics(),
      itemCount: labels.length,
      itemBuilder: (context, index) {
        final label = labels[index];
        final group = groups[label]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 12, bottom: 6),
              child: Text(
                label,
                style: theme.label(context, color: theme.textMuted),
              ),
            ),
            SizedBox(
              height: 66,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                itemCount: group.length,
                separatorBuilder: (_, __) => const SizedBox(width: 5),
                itemBuilder: (context, i) => SizedBox(
                  width: 66,
                  child: CollectionEmbedTappable(
                    onTap: () => openAlbumItem(
                      context,
                      embed,
                      items,
                      items.indexOf(group[i]),
                    ),
                    onSecondaryTap: embed.onShowMenu,
                    lift: 0,
                    growth: 1.05,
                    builder: (context, hovered) => AlbumThumbnail(
                      item: group[i],
                      palette: theme.palette,
                      radius: 7,
                      decodeWidth: 66,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
