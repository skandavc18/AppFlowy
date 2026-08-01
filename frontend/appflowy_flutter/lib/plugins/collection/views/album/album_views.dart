import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/album/album_filmstrip_view.dart';
import 'package:appflowy/plugins/collection/views/album/album_map_view.dart';
import 'package:appflowy/plugins/collection/views/album/album_playlist_view.dart';
import 'package:appflowy/plugins/collection/views/album/album_wall_view.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

abstract final class AlbumViewIds {
  static const gallery = 'album_gallery';
  static const masonry = 'album_masonry';
  static const timeline = 'album_timeline';
  static const filmstrip = 'album_filmstrip';
  static const playlist = 'album_playlist';
  static const map = 'album_map';
}

List<CollectionViewDefinition> albumCollectionViews() => [
      CollectionViewDefinition(
        id: AlbumViewIds.gallery,
        labelKey: LocaleKeys.collections_album_gallery,
        icon: Icons.grid_view_rounded,
        builder: (context, collection) => AlbumWallView(
          collection: collection,
          layout: AlbumWallLayout.grid,
        ),
      ),
      CollectionViewDefinition(
        id: AlbumViewIds.masonry,
        labelKey: LocaleKeys.collections_album_masonry,
        icon: Icons.dashboard_rounded,
        builder: (context, collection) => AlbumWallView(
          collection: collection,
          layout: AlbumWallLayout.masonry,
        ),
      ),
      CollectionViewDefinition(
        id: AlbumViewIds.timeline,
        labelKey: LocaleKeys.collections_album_timeline,
        icon: Icons.calendar_month_rounded,
        builder: (context, collection) => AlbumWallView(
          collection: collection,
          layout: AlbumWallLayout.timeline,
        ),
      ),
      CollectionViewDefinition(
        id: AlbumViewIds.filmstrip,
        labelKey: LocaleKeys.collections_album_filmstrip,
        icon: Icons.view_carousel_rounded,
        builder: (context, collection) =>
            AlbumFilmstripView(collection: collection),
      ),
      CollectionViewDefinition(
        id: AlbumViewIds.playlist,
        labelKey: LocaleKeys.collections_album_playlist,
        icon: Icons.queue_music_rounded,
        builder: (context, collection) =>
            AlbumPlaylistView(collection: collection),
      ),
      CollectionViewDefinition(
        id: AlbumViewIds.map,
        labelKey: LocaleKeys.collections_album_map,
        icon: Icons.place_rounded,
        builder: (context, collection) => AlbumMapView(collection: collection),
      ),
    ];
