import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_card.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_context_menu.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_grid_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_host.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_toolbar.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_state.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The reading list: one column of wide rows, newest first.
class BookmarkFeedView extends StatelessWidget {
  const BookmarkFeedView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) => BookmarkHost(
        collection: collection,
        builder: (context, controller, theme) => BookmarkScaffold(
          collection: collection,
          controller: controller,
          theme: theme,
          showGrouping: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookmarkFilterBar(controller: controller, theme: theme),
              Expanded(
                child: _Feed(
                  collection: collection,
                  controller: controller,
                  theme: theme,
                ),
              ),
            ],
          ),
        ),
      );
}

class _Feed extends StatefulWidget {
  const _Feed({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final BookmarkController controller;
  final BookmarkTheme theme;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.entries.isEmpty) {
      return bookmarkEmptyView(
        context: context,
        controller: controller,
        collection: widget.collection,
        theme: widget.theme,
      );
    }

    final groups = controller.groups();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => showBookmarkBackgroundMenu(
        context: context,
        controller: controller,
        collection: widget.collection,
        position: details.globalPosition,
      ),
      child: BookmarkScrollArea(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: BookmarkMetrics.space8),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: BookmarkMetrics.feedWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in groups) ...[
                    if (group.label.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          BookmarkMetrics.gutter,
                          BookmarkMetrics.space4,
                          BookmarkMetrics.gutter,
                          BookmarkMetrics.space2,
                        ),
                        child: Row(
                          children: [
                            Text(
                              _label(group.label).toUpperCase(),
                              style: widget.theme.sectionLabel,
                            ),
                            const SizedBox(width: BookmarkMetrics.space2),
                            Text(
                              '${group.entries.length}',
                              style: widget.theme.meta,
                            ),
                          ],
                        ),
                      ),
                    for (final entry in group.entries)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          BookmarkMetrics.gutter,
                          0,
                          BookmarkMetrics.gutter,
                          BookmarkMetrics.space3,
                        ),
                        child: BookmarkFeedRow(
                          key: ValueKey(entry.id),
                          entry: entry,
                          theme: widget.theme,
                          controller: controller,
                          collection: widget.collection,
                          showDescription: controller.settings.showDescriptions,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _label(String raw) =>
      widget.controller.settings.grouping == BookmarkGrouping.month
          ? bookmarkMonthLabel(raw)
          : raw;
}

/// One saved link, as a wide row.
class BookmarkFeedRow extends StatefulWidget {
  const BookmarkFeedRow({
    super.key,
    required this.entry,
    required this.theme,
    required this.controller,
    required this.collection,
    this.showDescription = true,
  });

  final BookmarkEntry entry;
  final BookmarkTheme theme;
  final BookmarkController controller;
  final CollectionViewContext collection;
  final bool showDescription;

  @override
  State<BookmarkFeedRow> createState() => _BookmarkFeedRowState();
}

class _BookmarkFeedRowState extends State<BookmarkFeedRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final entry = widget.entry;
    final metadata = entry.metadata;
    final description = metadata.description ?? metadata.excerpt;
    final read = metadata.readState == BookmarkReadState.read;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => openBookmarkReader(
          context: context,
          entry: entry,
          controller: widget.controller,
          collection: widget.collection,
        ),
        onSecondaryTapDown: (details) => showBookmarkMenu(
          context: context,
          entry: entry,
          controller: widget.controller,
          collection: widget.collection,
          position: details.globalPosition,
        ),
        child: ViewerCard(
          reactsToPointer: false,
          color: theme.panel,
          elevation: _hovered
              ? ViewerCardElevation.raised
              : ViewerCardElevation.resting,
          child: Opacity(
            opacity: read ? 0.74 : 1,
            child: SizedBox(
              height: BookmarkMetrics.feedRowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: BookmarkMetrics.feedThumbWidth,
                    child: BookmarkCover(entry: entry, theme: theme),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        BookmarkMetrics.space4,
                        BookmarkMetrics.space3,
                        BookmarkMetrics.space2,
                        BookmarkMetrics.space3,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.cardTitle,
                                ),
                              ),
                              AnimatedOpacity(
                                duration: BookmarkMetrics.hover,
                                opacity: _hovered ? 1 : 0,
                                child: IgnorePointer(
                                  ignoring: !_hovered,
                                  child: Row(
                                    children: [
                                      BookmarkAction(
                                        icon: metadata.starred
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        tooltip: metadata.starred
                                            ? LocaleKeys
                                                .collections_bookmark_unstar
                                                .tr()
                                            : LocaleKeys
                                                .collections_bookmark_star
                                                .tr(),
                                        theme: theme,
                                        size: 24,
                                        active: metadata.starred,
                                        onPressed: () =>
                                            widget.controller.setStarred(
                                          entry,
                                          !metadata.starred,
                                        ),
                                      ),
                                      BookmarkAction(
                                        icon: Icons.open_in_new_rounded,
                                        tooltip: LocaleKeys
                                            .collections_bookmark_openInBrowser
                                            .tr(),
                                        theme: theme,
                                        size: 24,
                                        onPressed: () =>
                                            openBookmarkInBrowser(entry),
                                      ),
                                      Builder(
                                        builder: (context) => BookmarkAction(
                                          icon: Icons.more_horiz_rounded,
                                          tooltip: LocaleKeys
                                              .collections_bookmark_open
                                              .tr(),
                                          theme: theme,
                                          size: 24,
                                          onPressed: () => showBookmarkMenu(
                                            context: context,
                                            entry: entry,
                                            controller: widget.controller,
                                            collection: widget.collection,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (widget.showDescription &&
                              description != null) ...[
                            const SizedBox(height: 3),
                            Expanded(
                              child: Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.body,
                              ),
                            ),
                          ] else
                            const Spacer(),
                          const SizedBox(height: BookmarkMetrics.space2 - 2),
                          Row(
                            children: [
                              Flexible(
                                child: BookmarkByline(
                                  entry: entry,
                                  theme: theme,
                                ),
                              ),
                              if (metadata.tags.isNotEmpty ||
                                  metadata.hasSnapshot) ...[
                                const SizedBox(width: BookmarkMetrics.space3),
                                BookmarkTagRow(
                                  entry: entry,
                                  theme: theme,
                                  maxTags: 2,
                                  onTagTapped:
                                      widget.controller.toggleTagFilter,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
