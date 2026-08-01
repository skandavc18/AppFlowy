import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_feed_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_grid_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_shelf_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_timeline_view.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

/// The stable identifiers a bookmark library's views are stored under.
abstract final class BookmarkViewIds {
  static const grid = 'bookmark_grid';
  static const feed = 'bookmark_feed';
  static const shelf = 'bookmark_shelf';
  static const timeline = 'bookmark_timeline';
}

/// The views a bookmark library ships with.
List<CollectionViewDefinition> bookmarkCollectionViews() => [
      CollectionViewDefinition(
        id: BookmarkViewIds.grid,
        labelKey: LocaleKeys.collections_bookmark_grid,
        icon: Icons.grid_view_rounded,
        builder: (context, collection) =>
            BookmarkGridView(collection: collection),
      ),
      CollectionViewDefinition(
        id: BookmarkViewIds.feed,
        labelKey: LocaleKeys.collections_bookmark_feed,
        icon: Icons.view_agenda_rounded,
        builder: (context, collection) =>
            BookmarkFeedView(collection: collection),
      ),
      CollectionViewDefinition(
        id: BookmarkViewIds.shelf,
        labelKey: LocaleKeys.collections_bookmark_shelf,
        icon: Icons.view_carousel_rounded,
        builder: (context, collection) =>
            BookmarkShelfView(collection: collection),
      ),
      CollectionViewDefinition(
        id: BookmarkViewIds.timeline,
        labelKey: LocaleKeys.collections_bookmark_timeline,
        icon: Icons.timeline_rounded,
        builder: (context, collection) =>
            BookmarkTimelineView(collection: collection),
      ),
    ];
