import 'package:appflowy/plugins/collection/views/bookmark/bookmark_card.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_context_menu.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_grid_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_host.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_toolbar.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_state.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

/// The shelf: one row per site, tag or month, browsed sideways.
///
/// A library is usually remembered by where something came from rather than
/// by when it was saved, which is what a shelf is for.
class BookmarkShelfView extends StatelessWidget {
  const BookmarkShelfView({super.key, required this.collection});

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
                child: _Shelves(
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

class _Shelves extends StatefulWidget {
  const _Shelves({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final BookmarkController controller;
  final BookmarkTheme theme;

  @override
  State<_Shelves> createState() => _ShelvesState();
}

class _ShelvesState extends State<_Shelves> {
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

    // A shelf without rows is a wall, so grouping is forced on here.
    final grouping = controller.settings.grouping == BookmarkGrouping.none
        ? BookmarkGrouping.site
        : controller.settings.grouping;
    final groups = controller.groups(grouping: grouping);

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
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: BookmarkMetrics.space8),
          itemCount: groups.length,
          itemBuilder: (context, index) => _Shelf(
            group: groups[index],
            controller: controller,
            collection: widget.collection,
            theme: widget.theme,
            grouping: grouping,
          ),
        ),
      ),
    );
  }
}

class _Shelf extends StatefulWidget {
  const _Shelf({
    required this.group,
    required this.controller,
    required this.collection,
    required this.theme,
    required this.grouping,
  });

  final BookmarkGroup group;
  final BookmarkController controller;
  final CollectionViewContext collection;
  final BookmarkTheme theme;
  final BookmarkGrouping grouping;

  @override
  State<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<_Shelf> {
  final ScrollController _row = ScrollController();

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final group = widget.group;
    final label = widget.grouping == BookmarkGrouping.month
        ? bookmarkMonthLabel(group.label)
        : group.label;

    return Padding(
      padding: const EdgeInsets.only(bottom: BookmarkMetrics.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BookmarkMetrics.gutter,
              BookmarkMetrics.space3,
              BookmarkMetrics.gutter,
              BookmarkMetrics.space3,
            ),
            child: Row(
              children: [
                if (widget.grouping == BookmarkGrouping.site)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: BookmarkMetrics.space2,
                    ),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: siteHue(group.label),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Text(
                  label.toUpperCase(),
                  style: theme.sectionLabel,
                ),
                const SizedBox(width: BookmarkMetrics.space2),
                Text('${group.entries.length}', style: theme.meta),
                const Spacer(),
                if (widget.grouping == BookmarkGrouping.site)
                  BookmarkAction(
                    icon: Icons.filter_alt_rounded,
                    tooltip: group.label,
                    theme: theme,
                    size: 24,
                    active: widget.controller.state.activeSite == group.label,
                    onPressed: () => widget.controller.setSiteFilter(
                      widget.controller.state.activeSite == group.label
                          ? null
                          : group.label,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 236,
            child: BookmarkScrollArea(
              controller: _row,
              child: ListView.separated(
                controller: _row,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: BookmarkMetrics.gutter,
                ),
                itemCount: group.entries.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: BookmarkMetrics.space3),
                itemBuilder: (context, index) {
                  final entry = group.entries[index];
                  return BookmarkCard(
                    key: ValueKey(entry.id),
                    entry: entry,
                    theme: theme,
                    width: BookmarkMetrics.shelfCardWidth,
                    compact: true,
                    working: widget.controller.isWorkingOn(entry.id),
                    onOpen: () => openBookmarkReader(
                      context: context,
                      entry: entry,
                      controller: widget.controller,
                      collection: widget.collection,
                    ),
                    onToggleStar: () => widget.controller
                        .setStarred(entry, !entry.metadata.starred),
                    onContextMenu: (position) => showBookmarkMenu(
                      context: context,
                      entry: entry,
                      controller: widget.controller,
                      collection: widget.collection,
                      position: position,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
