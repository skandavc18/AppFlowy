import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_card.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_context_menu.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_dialogs.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_host.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_toolbar.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The card wall: every saved link with its picture, title and site.
class BookmarkGridView extends StatelessWidget {
  const BookmarkGridView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) => BookmarkHost(
        collection: collection,
        builder: (context, controller, theme) => BookmarkScaffold(
          collection: collection,
          controller: controller,
          theme: theme,
          showDensity: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookmarkFilterBar(controller: controller, theme: theme),
              Expanded(
                child: _Wall(
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

class _Wall extends StatefulWidget {
  const _Wall({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final BookmarkController controller;
  final BookmarkTheme theme;

  @override
  State<_Wall> createState() => _WallState();
}

class _WallState extends State<_Wall> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = widget.theme;
    final entries = controller.entries;

    if (entries.isEmpty) {
      return bookmarkEmptyView(
        context: context,
        controller: controller,
        collection: widget.collection,
        theme: theme,
      );
    }

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final target = controller.settings.density.cardWidth;
            final available = constraints.maxWidth - BookmarkMetrics.gutter * 2;
            final columns = ((available + BookmarkMetrics.space4) /
                    (target + BookmarkMetrics.space4))
                .round()
                .clamp(1, 8);
            final width =
                (available - BookmarkMetrics.space4 * (columns - 1)) / columns;

            return SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                BookmarkMetrics.gutter,
                BookmarkMetrics.space1,
                BookmarkMetrics.gutter,
                BookmarkMetrics.space8,
              ),
              child: Wrap(
                spacing: BookmarkMetrics.space4,
                runSpacing: BookmarkMetrics.space4,
                children: [
                  for (final entry in entries)
                    BookmarkCard(
                      key: ValueKey(entry.id),
                      entry: entry,
                      theme: theme,
                      width: width,
                      showDescription: controller.settings.showDescriptions,
                      working: controller.isWorkingOn(entry.id),
                      onOpen: () => openBookmarkReader(
                        context: context,
                        entry: entry,
                        controller: controller,
                        collection: widget.collection,
                      ),
                      onToggleStar: () => controller.setStarred(
                        entry,
                        !entry.metadata.starred,
                      ),
                      onTagTapped: controller.toggleTagFilter,
                      onContextMenu: (position) => showBookmarkMenu(
                        context: context,
                        entry: entry,
                        controller: controller,
                        collection: widget.collection,
                        position: position,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What every bookmark view shows when it has nothing to show.
Widget bookmarkEmptyView({
  required BuildContext context,
  required BookmarkController controller,
  required CollectionViewContext collection,
  required BookmarkTheme theme,
}) {
  final filtered = controller.all.isNotEmpty;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapDown: (details) => showBookmarkBackgroundMenu(
      context: context,
      controller: controller,
      collection: collection,
      position: details.globalPosition,
    ),
    child: BookmarkEmptyState(
      theme: theme,
      icon: filtered ? Icons.search_off_rounded : Icons.bookmark_add_rounded,
      title: filtered
          ? LocaleKeys.collections_bookmark_noMatches.tr()
          : LocaleKeys.collections_bookmark_empty.tr(),
      message: filtered
          ? LocaleKeys.collections_bookmark_noMatchesDescription.tr()
          : LocaleKeys.collections_bookmark_emptyDescription.tr(),
      action: filtered
          ? BookmarkAction(
              icon: Icons.filter_alt_off_rounded,
              tooltip: LocaleKeys.collections_bookmark_clearFilters.tr(),
              theme: theme,
              label: LocaleKeys.collections_bookmark_clearFilters.tr(),
              onPressed: controller.clearFilters,
            )
          : Builder(
              builder: (context) => BookmarkAction(
                icon: Icons.add_link_rounded,
                tooltip: LocaleKeys.collections_bookmark_addLink.tr(),
                theme: theme,
                label: LocaleKeys.collections_bookmark_addLink.tr(),
                active: true,
                onPressed: () => showAddBookmarkDialog(
                  context: context,
                  collection: collection,
                  controller: controller,
                ),
              ),
            ),
    ),
  );
}
