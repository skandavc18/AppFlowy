import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The line under a title: favicon, site, date and reading time.
class BookmarkByline extends StatelessWidget {
  const BookmarkByline({
    super.key,
    required this.entry,
    required this.theme,
    this.showFavicon = true,
    this.showDate = true,
  });

  final BookmarkEntry entry;
  final BookmarkTheme theme;
  final bool showFavicon;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final metadata = entry.metadata;
    final parts = <String>[
      if (metadata.siteName?.isNotEmpty ?? false)
        metadata.siteName!
      else if (entry.host != null)
        entry.host!,
      if (showDate) bookmarkDateLabel(entry.timelineDate),
      if (metadata.readingMinutes != null)
        LocaleKeys.collections_bookmark_minuteRead
            .tr(args: ['${metadata.readingMinutes}']),
    ];

    return Row(
      children: [
        if (showFavicon) ...[
          BookmarkFavicon(entry: entry, theme: theme, size: 14),
          const SizedBox(width: BookmarkMetrics.space1 + 2),
        ],
        Expanded(
          child: Text(
            parts.join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.meta,
          ),
        ),
      ],
    );
  }
}

/// The tags on a card, plus the states worth calling out.
class BookmarkTagRow extends StatelessWidget {
  const BookmarkTagRow({
    super.key,
    required this.entry,
    required this.theme,
    this.maxTags = 3,
    this.onTagTapped,
  });

  final BookmarkEntry entry;
  final BookmarkTheme theme;
  final int maxTags;
  final ValueChanged<String>? onTagTapped;

  @override
  Widget build(BuildContext context) {
    final metadata = entry.metadata;
    final tags = metadata.tags.take(maxTags).toList();
    final hidden = metadata.tags.length - tags.length;
    if (tags.isEmpty && !metadata.hasSnapshot) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: BookmarkMetrics.space1 + 2,
      runSpacing: BookmarkMetrics.space1,
      children: [
        if (metadata.hasSnapshot)
          BookmarkChip(
            label: LocaleKeys.collections_bookmark_offline.tr(),
            theme: theme,
            icon: Icons.cloud_done_rounded,
          ),
        for (final tag in tags)
          BookmarkChip(
            label: tag,
            theme: theme,
            onTap: onTagTapped == null ? null : () => onTagTapped!(tag),
          ),
        if (hidden > 0)
          Text(
            '+$hidden',
            style: theme.meta,
          ),
      ],
    );
  }
}

/// A saved link, drawn as a card.
///
/// One card is used by the grid and the shelf so a library never shows two
/// different ideas of what a bookmark looks like.
class BookmarkCard extends StatefulWidget {
  const BookmarkCard({
    super.key,
    required this.entry,
    required this.theme,
    required this.onOpen,
    this.onContextMenu,
    this.onTagTapped,
    this.onToggleStar,
    this.showDescription = true,
    this.width,
    this.compact = false,
    this.working = false,
  });

  final BookmarkEntry entry;
  final BookmarkTheme theme;
  final VoidCallback onOpen;
  final ValueChanged<Offset>? onContextMenu;
  final ValueChanged<String>? onTagTapped;
  final VoidCallback? onToggleStar;
  final bool showDescription;
  final double? width;
  final bool compact;
  final bool working;

  @override
  State<BookmarkCard> createState() => _BookmarkCardState();
}

class _BookmarkCardState extends State<BookmarkCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final entry = widget.entry;
    final metadata = entry.metadata;
    final description = metadata.description ?? metadata.excerpt;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTapDown: widget.onContextMenu == null
            ? null
            : (details) => widget.onContextMenu!(details.globalPosition),
        child: AnimatedContainer(
          duration: BookmarkMetrics.hover,
          curve: BookmarkMetrics.curve,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          width: widget.width,
          child: ViewerCard(
            reactsToPointer: false,
            color: theme.panel,
            elevation: _hovered
                ? ViewerCardElevation.raised
                : ViewerCardElevation.resting,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _cover(theme, entry),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    BookmarkMetrics.space3 + 2,
                    BookmarkMetrics.space3,
                    BookmarkMetrics.space3 + 2,
                    BookmarkMetrics.space3 + 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.title,
                        maxLines: widget.compact ? 2 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.cardTitle,
                      ),
                      if (widget.showDescription &&
                          !widget.compact &&
                          description != null) ...[
                        const SizedBox(height: BookmarkMetrics.space2 - 2),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.body,
                        ),
                      ],
                      const SizedBox(height: BookmarkMetrics.space2 + 2),
                      BookmarkByline(entry: entry, theme: theme),
                      if (!widget.compact) ...[
                        const SizedBox(height: BookmarkMetrics.space2),
                        BookmarkTagRow(
                          entry: entry,
                          theme: theme,
                          onTagTapped: widget.onTagTapped,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BookmarkTheme theme, BookmarkEntry entry) => AspectRatio(
        aspectRatio: BookmarkMetrics.coverRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BookmarkCover(entry: entry, theme: theme),
            if (widget.working)
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(BookmarkMetrics.space2),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: theme.accent,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: BookmarkMetrics.space2 - 2,
              right: BookmarkMetrics.space2 - 2,
              child: AnimatedOpacity(
                duration: BookmarkMetrics.hover,
                opacity: _hovered || entry.metadata.starred ? 1 : 0,
                child: _StarButton(
                  theme: theme,
                  starred: entry.metadata.starred,
                  onPressed: widget.onToggleStar,
                ),
              ),
            ),
            if (entry.metadata.readState == BookmarkReadState.read)
              Positioned(
                top: BookmarkMetrics.space2 - 2,
                left: BookmarkMetrics.space2 - 2,
                child: _ReadBadge(theme: theme),
              )
            else if (entry.metadata.readProgress > 0)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  value: entry.metadata.readProgress,
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                  color: theme.accent,
                ),
              ),
          ],
        ),
      );
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    required this.theme,
    required this.starred,
    this.onPressed,
  });

  final BookmarkTheme theme;
  final bool starred;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.34),
              shape: BoxShape.circle,
            ),
            child: Icon(
              starred ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 15,
              color: starred ? const Color(0xFFFFC53D) : Colors.white,
            ),
          ),
        ),
      );
}

class _ReadBadge extends StatelessWidget {
  const _ReadBadge({required this.theme});

  final BookmarkTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 13,
          color: Colors.white,
        ),
      );
}

/// A date as a library reads it: relative while it is recent, then absolute.
String bookmarkDateLabel(DateTime date) {
  final now = DateTime.now();
  final difference = now.difference(date);
  if (difference.inSeconds < 90) {
    return 'just now';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  }
  if (date.year == now.year) {
    return DateFormat.MMMd().format(date);
  }
  return DateFormat.yMMMd().format(date);
}

/// A month heading, as a timeline and a shelf both need it.
String bookmarkMonthLabel(String key) {
  final parts = key.split('-');
  if (parts.length != 2) {
    return key;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null) {
    return key;
  }
  final date = DateTime(year, month);
  return year == DateTime.now().year
      ? DateFormat.MMMM().format(date)
      : DateFormat.yMMMM().format(date);
}
