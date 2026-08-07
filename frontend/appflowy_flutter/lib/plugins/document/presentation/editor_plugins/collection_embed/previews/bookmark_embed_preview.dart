import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_artwork.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

abstract final class BookmarkEmbedStyles {
  static const featured = 'featured';
  static const list = 'list';
  static const thumbnails = 'thumbnails';
  static const cards = 'cards';
  static const magazine = 'magazine';
}

CollectionEmbedDefinition buildBookmarkEmbedDefinition() =>
    CollectionEmbedDefinition(
      kind: CollectionKind.bookmark,
      mediumHeight: 262,
      largeHeight: 400,
      styles: const [
        CollectionEmbedStyle(
          id: BookmarkEmbedStyles.cards,
          labelKey: LocaleKeys.collections_embed_styles_linkCards,
          icon: Icons.view_agenda_rounded,
          supportsColumns: true,
        ),
        CollectionEmbedStyle(
          id: BookmarkEmbedStyles.featured,
          labelKey: LocaleKeys.collections_embed_styles_featured,
          icon: Icons.star_rounded,
        ),
        CollectionEmbedStyle(
          id: BookmarkEmbedStyles.list,
          labelKey: LocaleKeys.collections_embed_styles_linkList,
          icon: Icons.format_list_bulleted_rounded,
        ),
        CollectionEmbedStyle(
          id: BookmarkEmbedStyles.thumbnails,
          labelKey: LocaleKeys.collections_embed_styles_thumbnailGrid,
          icon: Icons.grid_view_rounded,
          supportsColumns: true,
        ),
        CollectionEmbedStyle(
          id: BookmarkEmbedStyles.magazine,
          labelKey: LocaleKeys.collections_embed_styles_magazine,
          icon: Icons.auto_awesome_mosaic_rounded,
        ),
      ],
      builder: (context, embed) => BookmarkEmbedPreview(embed: embed),
    );

class BookmarkEmbedPreview extends StatelessWidget {
  const BookmarkEmbedPreview({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  Widget build(BuildContext context) {
    if (embed.controller.isLoading && embed.children.isEmpty) {
      return const CollectionEmbedSpinner();
    }
    final entries = bookmarkEntriesFrom(embed.slice());
    if (entries.isEmpty) {
      return CollectionEmbedEmpty(
        theme: embed.theme,
        icon: Icons.bookmark_border_rounded,
        message: LocaleKeys.collections_embed_empty.tr(),
        compact: embed.size.isCompact,
      );
    }
    return switch (embed.style) {
      BookmarkEmbedStyles.featured =>
        _Featured(embed: embed, entries: entries),
      BookmarkEmbedStyles.list => _Rows(embed: embed, entries: entries),
      BookmarkEmbedStyles.thumbnails =>
        _Thumbnails(embed: embed, entries: entries),
      BookmarkEmbedStyles.magazine =>
        _Magazine(embed: embed, entries: entries),
      _ => _Cards(embed: embed, entries: entries),
    };
  }
}

/// The site's own mark: its picture when it has one, otherwise its initial in
/// a hue derived from the host so a wall of links is still scannable.
class _SiteMark extends StatelessWidget {
  const _SiteMark({
    required this.embed,
    required this.entry,
    this.size = 34,
    this.radius = 8,
  });

  final CollectionEmbedContext embed;
  final BookmarkEntry entry;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final host = entry.host ?? entry.url;
    final hue = collectionObjectHue(host, dark: theme.isDark);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              hue.withValues(alpha: theme.isDark ? 0.26 : 0.16),
              theme.sunken,
            ),
          ),
          child: Center(
            child: Text(
              host.isEmpty ? '?' : host.replaceFirst('www.', '')[0].toUpperCase(),
              style: TextStyle(
                color: hue,
                fontSize: size * 0.44,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards({required this.embed, required this.entries});

  final CollectionEmbedContext embed;
  final List<BookmarkEntry> entries;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = embed.settings.columns ??
              (constraints.maxWidth / 250).floor().clamp(1, 4);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            physics: const ClampingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              mainAxisExtent: embed.size.isCompact ? 62 : 76,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) =>
                _LinkCard(embed: embed, entry: entries[index]),
          );
        },
      );
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.embed, required this.entry});

  final CollectionEmbedContext embed;
  final BookmarkEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    return CollectionEmbedTappable(
      onTap: () => embed.onOpenObject(entry.view),
      onSecondaryTap: embed.onShowMenu,
      lift: 1.5,
      builder: (context, hovered) => AnimatedContainer(
        duration: CollectionEmbedMetrics.hover,
        curve: CollectionEmbedMetrics.ease,
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: hovered ? theme.raised : theme.sunken,
          borderRadius:
              BorderRadius.circular(CollectionEmbedMetrics.innerRadius),
        ),
        child: Row(
          children: [
            _SiteMark(embed: embed, entry: entry, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: embed.size.isCompact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.face(
                      context,
                      size: 12.5,
                      color: hovered ? theme.textPrimary : theme.textBody,
                      weightAxis: 580,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    bookmarkDisplayUrl(entry.url, maxLength: 46),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.caption(context, size: 10.5),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              opacity: hovered ? 1 : 0,
              duration: CollectionEmbedMetrics.hover,
              child: Icon(
                Icons.north_east_rounded,
                size: 14,
                color: theme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.embed, required this.entries});

  final CollectionEmbedContext embed;
  final List<BookmarkEntry> entries;

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        physics: const ClampingScrollPhysics(),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return CollectionObjectRow(
            view: entry.view,
            theme: embed.theme,
            leading: _SiteMark(embed: embed, entry: entry, size: 20, radius: 5),
            subtitle: embed.settings.showMetadata
                ? bookmarkDisplayUrl(entry.url, maxLength: 60)
                : null,
            height: embed.settings.showMetadata ? 38 : 30,
            onTap: () => embed.onOpenObject(entry.view),
            onSecondaryTap: embed.onShowMenu,
          );
        },
      );
}

/// One link given the whole widget, with the rest offered underneath.
class _Featured extends StatefulWidget {
  const _Featured({required this.embed, required this.entries});

  final CollectionEmbedContext embed;
  final List<BookmarkEntry> entries;

  @override
  State<_Featured> createState() => _FeaturedState();
}

class _FeaturedState extends State<_Featured> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final embed = widget.embed;
    final theme = embed.theme;
    final entries = widget.entries;
    final entry = entries[index.clamp(0, entries.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CollectionEmbedTappable(
            onTap: () => embed.onOpenObject(entry.view),
            onSecondaryTap: embed.onShowMenu,
            lift: 0,
            builder: (context, hovered) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  CollectionEmbedMetrics.innerRadius,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CollectionArtwork(
                      view: entry.view,
                      theme: theme,
                      userProfile: embed.userProfile,
                      fallback: DecoratedBox(
                        decoration: BoxDecoration(color: theme.sunken),
                        child: Center(
                          child: _SiteMark(
                            embed: embed,
                            entry: entry,
                            size: 46,
                            radius: 12,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0),
                                Colors.black.withValues(alpha: 0.72),
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                entry.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                bookmarkDisplayUrl(entry.url),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.74),
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (entries.length > 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              physics: const ClampingScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) => CollectionEmbedTappable(
                onTap: () => setState(() => index = i),
                lift: 0,
                growth: 1.08,
                builder: (context, hovered) => AnimatedContainer(
                  duration: CollectionEmbedMetrics.hover,
                  width: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: i == index
                          ? theme.accent
                          : theme.accent.withValues(alpha: 0),
                      width: 1.4,
                    ),
                  ),
                  padding: const EdgeInsets.all(1.5),
                  child: _SiteMark(
                    embed: embed,
                    entry: entries[i],
                    size: 20,
                    radius: 4,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Thumbnails extends StatelessWidget {
  const _Thumbnails({required this.embed, required this.entries});

  final CollectionEmbedContext embed;
  final List<BookmarkEntry> entries;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = embed.settings.columns ??
              (constraints.maxWidth / 150).floor().clamp(2, 6);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            physics: const ClampingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 9,
              mainAxisSpacing: 10,
              childAspectRatio: 0.94,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return CollectionObjectCard(
                view: entry.view,
                theme: embed.theme,
                userProfile: embed.userProfile,
                decodeWidth: constraints.maxWidth / columns,
                onTap: () => embed.onOpenObject(entry.view),
                onSecondaryTap: embed.onShowMenu,
              );
            },
          );
        },
      );
}

/// A lead story with a column of headlines beside it.
class _Magazine extends StatelessWidget {
  const _Magazine({required this.embed, required this.entries});

  final CollectionEmbedContext embed;
  final List<BookmarkEntry> entries;

  @override
  Widget build(BuildContext context) {
    final rest = entries.skip(1).take(4).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: _Featured(embed: embed, entries: entries.take(1).toList()),
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  for (final entry in rest)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _LinkCard(embed: embed, entry: entry),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
