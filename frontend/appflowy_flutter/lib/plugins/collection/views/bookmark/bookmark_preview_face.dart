import 'dart:math' as math;

import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:flutter/material.dart';

/// A saved link drawn as a preview: the page's own picture, or its site's hue
/// when it offered none, over the site and what the page says about itself.
///
/// It reads only what was saved with the link, so it never waits on the
/// network to have something to show; the picture and the site icon fill in
/// when they arrive and fall back quietly when they do not.
class BookmarkPreviewFace extends StatelessWidget {
  const BookmarkPreviewFace({super.key, required this.entry});

  final BookmarkEntry entry;

  static const _padding = EdgeInsets.fromLTRB(12, 9, 12, 10);
  static const _siteGap = 6.0;
  static const _faviconSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final theme = bookmarkThemeOf(context);
    final metadata = entry.metadata;
    final host = entry.host ?? bookmarkDisplayUrl(entry.url);
    final summary = _summary(metadata);
    final bodyStyle = theme.body.copyWith(fontSize: 12, height: 1.42);
    final cover = BookmarkCover(
      key: const ValueKey('bookmark-preview-cover'),
      entry: entry,
      theme: theme,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Too short for words under the picture: the picture alone says more.
        if (constraints.hasBoundedHeight && constraints.maxHeight < 112) {
          return cover;
        }
        final site = Row(
          key: const ValueKey('bookmark-preview-site'),
          children: [
            BookmarkFavicon(entry: entry, theme: theme, size: _faviconSize),
            const SizedBox(width: _siteGap),
            Expanded(
              child: Text(
                host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.metaStrong,
              ),
            ),
          ],
        );
        final words = LayoutBuilder(
          builder: (context, area) {
            final scaler = MediaQuery.textScalerOf(context);
            final line = scaler.scale(bodyStyle.fontSize!) * bodyStyle.height!;
            final siteHeight = math.max(
              _faviconSize,
              scaler.scale(theme.metaStrong.fontSize ?? 11.5) * 1.3,
            );
            final room = area.maxHeight - siteHeight - _siteGap;
            final lines = room.isFinite ? (room / line).floor() : 4;
            // The site line always fits: at a large text size in a short card
            // it is clipped rather than overflowing the card.
            return ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                minHeight: 0,
                maxHeight: area.hasBoundedHeight
                    ? math.max(area.maxHeight, siteHeight)
                    : double.infinity,
                child: Column(
                  mainAxisSize: area.hasBoundedHeight
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    site,
                    if (summary.isNotEmpty && lines > 0) ...[
                      const SizedBox(height: _siteGap),
                      Flexible(
                        child: Text(
                          summary,
                          key: const ValueKey('bookmark-preview-summary'),
                          maxLines: math.min(lines, 8),
                          overflow: TextOverflow.ellipsis,
                          style: bodyStyle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
        final face = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: cover),
            Expanded(
              flex: 4,
              child: Padding(padding: _padding, child: words),
            ),
          ],
        );
        return constraints.hasBoundedHeight
            ? face
            : SizedBox(height: 240, child: face);
      },
    );
  }

  /// What the page says about itself, or where it lives when it said nothing.
  String _summary(BookmarkMetadata metadata) {
    for (final text in [metadata.description, metadata.excerpt]) {
      final value = text?.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return bookmarkDisplayUrl(metadata.url, maxLength: 120);
  }
}
