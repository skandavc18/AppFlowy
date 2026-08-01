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
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The timeline: saved links down one thread, newest first.
class BookmarkTimelineView extends StatelessWidget {
  const BookmarkTimelineView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) => BookmarkHost(
        collection: collection,
        builder: (context, controller, theme) => BookmarkScaffold(
          collection: collection,
          controller: controller,
          theme: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookmarkFilterBar(controller: controller, theme: theme),
              Expanded(
                child: _Timeline(
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

/// One line of the timeline: either a date heading or a bookmark.
sealed class _Line {
  const _Line();
}

class _DateLine extends _Line {
  const _DateLine(this.date);

  final DateTime date;
}

class _EntryLine extends _Line {
  const _EntryLine(this.entry, {required this.last});

  final BookmarkEntry entry;
  final bool last;
}

class _Timeline extends StatefulWidget {
  const _Timeline({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final BookmarkController controller;
  final BookmarkTheme theme;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
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

    final lines = _buildLines(controller.entries);
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
          itemCount: lines.length,
          itemBuilder: (context, index) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: switch (lines[index]) {
                final _DateLine line =>
                  _Heading(date: line.date, theme: widget.theme),
                final _EntryLine line => _Row(
                    entry: line.entry,
                    last: line.last,
                    controller: controller,
                    collection: widget.collection,
                    theme: widget.theme,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The entries are already in the order the settings ask for; the headings
  /// are inserted wherever the day changes.
  List<_Line> _buildLines(List<BookmarkEntry> entries) {
    final lines = <_Line>[];
    DateTime? day;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final date = entry.timelineDate;
      final entryDay = DateTime(date.year, date.month, date.day);
      if (day == null || entryDay != day) {
        day = entryDay;
        lines.add(_DateLine(entryDay));
      }
      final nextDate =
          i + 1 < entries.length ? entries[i + 1].timelineDate : null;
      final last = nextDate == null ||
          DateTime(nextDate.year, nextDate.month, nextDate.day) != entryDay;
      lines.add(_EntryLine(entry, last: last));
    }
    return lines;
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.date, required this.theme});

  final DateTime date;
  final BookmarkTheme theme;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(date).inDays;
    final label = switch (difference) {
      0 => 'Today',
      1 => 'Yesterday',
      _ when date.year == now.year => DateFormat.MMMMd().format(date),
      _ => DateFormat.yMMMMd().format(date),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BookmarkMetrics.gutter,
        BookmarkMetrics.space5,
        BookmarkMetrics.gutter,
        BookmarkMetrics.space2,
      ),
      child: Row(
        children: [
          const SizedBox(width: BookmarkMetrics.timelineRailWidth),
          Text(label.toUpperCase(), style: theme.sectionLabel),
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.entry,
    required this.last,
    required this.controller,
    required this.collection,
    required this.theme,
  });

  final BookmarkEntry entry;
  final bool last;
  final BookmarkController controller;
  final CollectionViewContext collection;
  final BookmarkTheme theme;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final entry = widget.entry;
    final metadata = entry.metadata;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BookmarkMetrics.gutter,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: BookmarkMetrics.timelineRailWidth,
              child: _Rail(
                date: entry.timelineDate,
                theme: theme,
                hue: siteHue(entry.host ?? ''),
                last: widget.last,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: BookmarkMetrics.space3),
                child: MouseRegion(
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
                      child: Padding(
                        padding:
                            const EdgeInsets.all(BookmarkMetrics.space3 + 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    entry.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.cardTitle,
                                  ),
                                  if (metadata.description != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      metadata.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.body,
                                    ),
                                  ],
                                  const SizedBox(
                                    height: BookmarkMetrics.space2,
                                  ),
                                  BookmarkByline(
                                    entry: entry,
                                    theme: theme,
                                    showDate: false,
                                  ),
                                ],
                              ),
                            ),
                            if (metadata.imageUrl != null) ...[
                              const SizedBox(width: BookmarkMetrics.space3),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 108,
                                  height: 68,
                                  child: BookmarkCover(
                                    entry: entry,
                                    theme: theme,
                                  ),
                                ),
                              ),
                            ],
                            AnimatedOpacity(
                              duration: BookmarkMetrics.hover,
                              opacity: _hovered ? 1 : 0,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: BookmarkMetrics.space1,
                                ),
                                child: IgnorePointer(
                                  ignoring: !_hovered,
                                  child: BookmarkAction(
                                    icon: Icons.open_in_new_rounded,
                                    tooltip: LocaleKeys
                                        .collections_bookmark_openInBrowser
                                        .tr(),
                                    theme: theme,
                                    size: 24,
                                    onPressed: () =>
                                        openBookmarkInBrowser(entry),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.date,
    required this.theme,
    required this.hue,
    required this.last,
  });

  final DateTime date;
  final BookmarkTheme theme;
  final Color hue;
  final bool last;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                top: BookmarkMetrics.space3,
                right: BookmarkMetrics.space3,
              ),
              child: Text(
                DateFormat.jm().format(date),
                textAlign: TextAlign.right,
                style: theme.meta,
              ),
            ),
          ),
          SizedBox(
            width: BookmarkMetrics.space4,
            child: Column(
              children: [
                const SizedBox(height: BookmarkMetrics.space4),
                Container(
                  width: BookmarkMetrics.timelineDotSize,
                  height: BookmarkMetrics.timelineDotSize,
                  decoration: BoxDecoration(
                    color: hue,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.panel, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: last
                        ? Colors.transparent
                        : theme.textFaint.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
