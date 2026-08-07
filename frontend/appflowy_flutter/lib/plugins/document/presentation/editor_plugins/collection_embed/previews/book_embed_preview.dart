import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_artwork.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/cover_flip.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/plugins/collection/views/book/book_views.dart';
import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

abstract final class BookEmbedStyles {
  static const cover = 'cover';
  static const shelf = 'shelf';
  static const contents = 'contents';
}

CollectionEmbedDefinition buildBookEmbedDefinition() =>
    CollectionEmbedDefinition(
      kind: CollectionKind.book,
      defaultItemLimit: 8,
      compactHeight: 148,
      mediumHeight: 288,
      largeHeight: 440,
      showsHeading: false,
      styles: const [
        CollectionEmbedStyle(
          id: BookEmbedStyles.cover,
          labelKey: LocaleKeys.collections_embed_styles_bookCover,
          icon: Icons.menu_book_rounded,
        ),
        CollectionEmbedStyle(
          id: BookEmbedStyles.shelf,
          labelKey: LocaleKeys.collections_embed_styles_bookshelf,
          icon: Icons.shelves,
          supportsColumns: true,
        ),
        CollectionEmbedStyle(
          id: BookEmbedStyles.contents,
          labelKey: LocaleKeys.collections_embed_styles_bookContents,
          icon: Icons.toc_rounded,
        ),
      ],
      builder: (context, embed) => BookEmbedPreview(embed: embed),
    );

class BookEmbedPreview extends StatefulWidget {
  const BookEmbedPreview({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  State<BookEmbedPreview> createState() => _BookEmbedPreviewState();
}

class _BookEmbedPreviewState extends State<BookEmbedPreview>
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

  BookReadingState get reading => BookReadingState.fromJson(
        Map<String, dynamic>.from(
          embed.collection.collection?.stateFor(bookStateKey) ??
              const <String, dynamic>{},
        ),
      );

  List<BookChapter> get chapters => bookChaptersFrom(embed.children);

  @override
  Widget build(BuildContext context) {
    if (embed.controller.isLoading && embed.children.isEmpty) {
      return const CollectionEmbedSpinner();
    }
    return switch (embed.style) {
      BookEmbedStyles.shelf => _Shelf(embed: embed, chapters: chapters),
      BookEmbedStyles.contents =>
        _Contents(embed: embed, chapters: chapters, reading: reading),
      _ => _CoverStage(
          embed: embed,
          chapters: chapters,
          reading: reading,
          flip: flip,
          onToggle: _toggle,
        ),
    };
  }

  void _toggle() {
    if (flip.status == AnimationStatus.completed ||
        flip.status == AnimationStatus.forward) {
      flip.reverse();
    } else {
      flip.forward();
    }
  }
}

/// The default reading: a book standing on the page, which opens.
class _CoverStage extends StatelessWidget {
  const _CoverStage({
    required this.embed,
    required this.chapters,
    required this.reading,
    required this.flip,
    required this.onToggle,
  });

  final CollectionEmbedContext embed;
  final List<BookChapter> chapters;
  final BookReadingState reading;
  final AnimationController flip;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final progress = reading.overallProgress(chapters);
    final compact = embed.size.isCompact;

    return Padding(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 0.68,
            child: AnimatedBuilder(
              animation: flip,
              builder: (context, _) => CoverFlip(
                progress: flip.value,
                spineColor: theme.accent,
                cover: CollectionEmbedTappable(
                  onTap: onToggle,
                  lift: 0,
                  growth: 1.02,
                  builder: (context, hovered) => _BookCover(
                    embed: embed,
                    chapters: chapters,
                  ),
                ),
                contents: _OpenPages(
                  embed: embed,
                  chapters: chapters,
                  reading: reading,
                  onClose: onToggle,
                ),
              ),
            ),
          ),
          SizedBox(width: compact ? 12 : 18),
          Expanded(
            child: _BookFacts(
              embed: embed,
              chapters: chapters,
              reading: reading,
              progress: progress,
              onOpenBook: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.embed, required this.chapters});

  final CollectionEmbedContext embed;
  final List<BookChapter> chapters;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final artwork = _coverSource(embed, chapters);
    if (artwork != null) {
      return CollectionArtwork(
        view: artwork,
        theme: theme,
        userProfile: embed.userProfile,
        fallback: _generated(context),
      );
    }
    return _generated(context);
  }

  Widget _generated(BuildContext context) => GeneratedBookCover(
        title: embed.collection.name.isEmpty
            ? LocaleKeys.collections_untitled.tr()
            : embed.collection.name,
        author: embed.theme.typeLabel,
        hue: embed.theme.accent,
        dark: embed.theme.isDark,
      );
}

ViewPB? _coverSource(
  CollectionEmbedContext embed,
  List<BookChapter> chapters,
) {
  final chosen = embed.settings.coverId;
  if (chosen != null) {
    for (final view in embed.children) {
      if (view.id == chosen) {
        return view;
      }
    }
  }
  if (viewHasArtwork(embed.collection)) {
    return embed.collection;
  }
  for (final chapter in chapters) {
    if (viewHasArtwork(chapter.view)) {
      return chapter.view;
    }
  }
  return null;
}

class _BookFacts extends StatelessWidget {
  const _BookFacts({
    required this.embed,
    required this.chapters,
    required this.reading,
    required this.progress,
    required this.onOpenBook,
  });

  final CollectionEmbedContext embed;
  final List<BookChapter> chapters;
  final BookReadingState reading;
  final double progress;
  final VoidCallback onOpenBook;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final readable = chapters.where((chapter) => !chapter.isPart).length;
    final finished = reading.finishedCount(chapters);
    final compact = embed.size.isCompact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          embed.collection.name.isEmpty
              ? LocaleKeys.collections_untitled.tr()
              : embed.collection.name,
          maxLines: compact ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: theme.face(
            context,
            size: compact ? 15 : 19,
            color: theme.textPrimary,
            weightAxis: 650,
            tracking: -0.3,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        if (embed.settings.showMetadata) ...[
          Row(
            children: [
              CollectionEmbedMeta(
                theme: theme,
                icon: Icons.menu_book_rounded,
                label: readable == 1
                    ? LocaleKeys.collections_book_oneChapter.tr()
                    : LocaleKeys.collections_book_chapterCount
                        .tr(args: ['$readable']),
              ),
              if (readable > 0) ...[
                CollectionEmbedMetaDot(theme: theme),
                Flexible(
                  child: CollectionEmbedMeta(
                    theme: theme,
                    label: progress <= 0
                        ? LocaleKeys.collections_book_unread.tr()
                        : LocaleKeys.collections_book_percentRead
                            .tr(args: ['${(progress * 100).round()}']),
                    color: progress > 0 ? theme.accent : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (readable > 0)
            CollectionEmbedProgress(theme: theme, value: progress),
          if (readable > 0 && !compact) ...[
            const SizedBox(height: 6),
            Text(
              LocaleKeys.collections_book_finishedCount
                  .tr(args: ['$finished', '$readable']),
              style: theme.caption(context),
            ),
          ],
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _BookAction(
              theme: theme,
              label: progress > 0
                  ? LocaleKeys.collections_book_continueReading.tr()
                  : LocaleKeys.collections_book_startReading.tr(),
              icon: Icons.auto_stories_rounded,
              primary: true,
              onTap: onOpenBook,
            ),
            _BookAction(
              theme: theme,
              label: LocaleKeys.collections_book_openInWorkspace.tr(),
              icon: Icons.open_in_new_rounded,
              onTap: embed.onOpenCollection,
            ),
          ],
        ),
      ],
    );
  }
}

class _BookAction extends StatelessWidget {
  const _BookAction({
    required this.theme,
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final CollectionEmbedTheme theme;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => CollectionEmbedTappable(
        onTap: onTap,
        lift: 0,
        builder: (context, hovered) => AnimatedContainer(
          duration: CollectionEmbedMetrics.hover,
          curve: CollectionEmbedMetrics.ease,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: primary
                ? (hovered
                    ? Color.alphaBlend(
                        theme.accent.withValues(alpha: 0.08),
                        theme.accentWash,
                      )
                    : theme.accentWash)
                : (hovered ? theme.rowHover : theme.rowHover.withValues(alpha: 0)),
            borderRadius:
                BorderRadius.circular(CollectionEmbedMetrics.controlRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: primary ? theme.accent : theme.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.face(
                  context,
                  size: 12,
                  color: primary ? theme.accent : theme.textBody,
                  weightAxis: 570,
                ),
              ),
            ],
          ),
        ),
      );
}

/// What is behind the cover: a real table of contents.
class _OpenPages extends StatelessWidget {
  const _OpenPages({
    required this.embed,
    required this.chapters,
    required this.reading,
    required this.onClose,
  });

  final CollectionEmbedContext embed;
  final List<BookChapter> chapters;
  final BookReadingState reading;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final page = theme.isPaper || !theme.isDark
        ? const Color(0xFFFBF7EF)
        : Color.alphaBlend(Colors.white.withValues(alpha: 0.05), theme.sunken);
    final ink = theme.isDark ? const Color(0xFFE8E2D6) : const Color(0xFF3A332A);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: page,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleKeys.collections_book_contents.tr().toUpperCase(),
                    style: theme.face(
                      context,
                      size: 9.5,
                      color: ink.withValues(alpha: 0.55),
                      weightAxis: 650,
                      tracking: 1.4,
                    ),
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
          Expanded(
            child: chapters.isEmpty
                ? CollectionEmbedEmpty(
                    theme: theme,
                    compact: true,
                    icon: Icons.menu_book_rounded,
                    message: LocaleKeys.collections_book_emptyTitle.tr(),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    physics: const ClampingScrollPhysics(),
                    itemCount: chapters.length,
                    itemBuilder: (context, index) => _ContentsRow(
                      embed: embed,
                      chapter: chapters[index],
                      reading: reading,
                      ink: ink,
                      dense: true,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The index as its own preview style, for a book read from the page.
class _Contents extends StatelessWidget {
  const _Contents({
    required this.embed,
    required this.chapters,
    required this.reading,
  });

  final CollectionEmbedContext embed;
  final List<BookChapter> chapters;
  final BookReadingState reading;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    if (chapters.isEmpty) {
      return CollectionEmbedEmpty(
        theme: theme,
        icon: Icons.menu_book_rounded,
        message: LocaleKeys.collections_book_emptyTitle.tr(),
        compact: embed.size.isCompact,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      physics: const ClampingScrollPhysics(),
      itemCount: chapters.length,
      itemBuilder: (context, index) => _ContentsRow(
        embed: embed,
        chapter: chapters[index],
        reading: reading,
        ink: theme.textBody,
      ),
    );
  }
}

class _ContentsRow extends StatelessWidget {
  const _ContentsRow({
    required this.embed,
    required this.chapter,
    required this.reading,
    required this.ink,
    this.dense = false,
  });

  final CollectionEmbedContext embed;
  final BookChapter chapter;
  final BookReadingState reading;
  final Color ink;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    if (chapter.isPart) {
      return Padding(
        padding: EdgeInsets.fromLTRB(8, dense ? 10 : 14, 8, 5),
        child: Text(
          chapter.name.toUpperCase(),
          style: theme.face(
            context,
            size: 9.5,
            color: ink.withValues(alpha: 0.5),
            weightAxis: 660,
            tracking: 1.2,
          ),
        ),
      );
    }
    final progress = reading.progressFor(chapter.id);
    final finished = reading.isFinished(chapter.id);
    return CollectionEmbedTappable(
      onTap: () => embed.onOpenObject(chapter.view),
      onSecondaryTap: embed.onShowMenu,
      lift: 0,
      builder: (context, hovered) => AnimatedContainer(
        duration: CollectionEmbedMetrics.hover,
        curve: CollectionEmbedMetrics.ease,
        height: dense ? 28 : 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hovered
              ? ink.withValues(alpha: 0.06)
              : ink.withValues(alpha: 0),
          borderRadius:
              BorderRadius.circular(CollectionEmbedMetrics.controlRadius),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '${chapter.index + 1}',
                style: theme.face(
                  context,
                  size: dense ? 10 : 11,
                  color: ink.withValues(alpha: 0.42),
                  weightAxis: 600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                chapter.name.isEmpty
                    ? LocaleKeys.collections_book_untitledChapter.tr()
                    : chapter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.face(
                  context,
                  size: dense ? 11.5 : 12.5,
                  color: ink.withValues(alpha: finished ? 0.6 : 0.95),
                  weightAxis: 550,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (finished)
              Icon(
                Icons.check_circle_rounded,
                size: dense ? 12 : 14,
                color: theme.accent.withValues(alpha: 0.8),
              )
            else if (progress > 0)
              SizedBox(
                width: 34,
                child: CollectionEmbedProgress(
                  theme: theme,
                  value: progress,
                  height: 2.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Several books standing together, the way they do on a shelf.
class _Shelf extends StatelessWidget {
  const _Shelf({required this.embed, required this.chapters});

  final CollectionEmbedContext embed;
  final List<BookChapter> chapters;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    // A shelf shows what the book actually contains: its parts if it has
    // them, otherwise its chapters, each standing as its own volume.
    final parts = chapters.where((chapter) => chapter.isPart).toList();
    final volumes = parts.isNotEmpty ? parts : chapters;
    if (volumes.isEmpty) {
      return CollectionEmbedEmpty(
        theme: theme,
        icon: Icons.shelves,
        message: LocaleKeys.collections_book_emptyTitle.tr(),
        compact: embed.size.isCompact,
      );
    }
    final limit = embed.settings.itemLimit ?? embed.definition.defaultItemLimit;
    final shown = volumes.length <= limit ? volumes : volumes.take(limit).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = embed.settings.columns ??
            (constraints.maxWidth / 118).floor().clamp(2, 8);
        final gap = 14.0;
        final width =
            ((constraints.maxWidth - 28 - gap * (columns - 1)) / columns)
                .clamp(52.0, 190.0);
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: Wrap(
            spacing: gap,
            runSpacing: 16,
            children: [
              for (final volume in shown)
                SizedBox(
                  width: width,
                  child: _ShelfVolume(
                    embed: embed,
                    chapter: volume,
                    width: width,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ShelfVolume extends StatelessWidget {
  const _ShelfVolume({
    required this.embed,
    required this.chapter,
    required this.width,
  });

  final CollectionEmbedContext embed;
  final BookChapter chapter;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final hue = collectionObjectHue(chapter.id, dark: theme.isDark);
    return CollectionEmbedTappable(
      onTap: () => embed.onOpenObject(chapter.view),
      onSecondaryTap: embed.onShowMenu,
      lift: 5,
      growth: 1.02,
      builder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 0.68,
            child: AnimatedContainer(
              duration: CollectionEmbedMetrics.hover,
              curve: CollectionEmbedMetrics.ease,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: theme.shadow.withValues(
                      alpha: theme.isDark
                          ? (hovered ? 0.44 : 0.30)
                          : (hovered ? 0.22 : 0.13),
                    ),
                    blurRadius: hovered ? 20 : 10,
                    offset: Offset(0, hovered ? 9 : 4),
                    spreadRadius: -3,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    viewHasArtwork(chapter.view)
                        ? CollectionArtwork(
                            view: chapter.view,
                            theme: theme,
                            userProfile: embed.userProfile,
                            decodeWidth: width,
                          )
                        : GeneratedBookCover(
                            title: chapter.name,
                            hue: hue,
                            dark: theme.isDark,
                          ),
                    // The spine: the darker strip a book always has on the
                    // side it is bound.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: (width * 0.07).clamp(3.0, 9.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.30),
                              Colors.black.withValues(alpha: 0.05),
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
          const SizedBox(height: 8),
          Text(
            chapter.name.isEmpty
                ? LocaleKeys.collections_book_untitledChapter.tr()
                : chapter.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.face(
              context,
              size: 11.5,
              color: hovered ? theme.textPrimary : theme.textBody,
              weightAxis: 580,
            ),
          ),
        ],
      ),
    );
  }
}
