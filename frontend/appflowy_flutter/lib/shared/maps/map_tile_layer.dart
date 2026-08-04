import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_tile_cache.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:flutter/rendering.dart';

/// The tile grid that best matches the camera's zoom.
int tileZoomFor(MapCamera camera, int maxZoom) =>
    camera.zoom.round().clamp(0, maxZoom);

/// Every tile that touches the view, plus a ring around it so a small pan does
/// not show blank edges.
List<MapTile> visibleTiles(MapCamera camera, int zoom, {int margin = 1}) {
  final scale = math.pow(2, camera.zoom - zoom).toDouble();
  final tileSide = mapTileSize * scale;
  final world = mapWorldSize(zoom.toDouble()) * scale;
  final middle = projectLatLng(camera.center) * world;

  final left = middle.dx - camera.size.width / 2;
  final top = middle.dy - camera.size.height / 2;

  final firstX = (left / tileSide).floor() - margin;
  final firstY = (top / tileSide).floor() - margin;
  final lastX = ((left + camera.size.width) / tileSide).ceil() + margin;
  final lastY = ((top + camera.size.height) / tileSide).ceil() + margin;

  final tiles = <MapTile>[];
  for (var y = firstY; y <= lastY; y++) {
    for (var x = firstX; x <= lastX; x++) {
      final tile = MapTile(x, y, zoom);
      if (tile.isOnEarth) {
        tiles.add(tile);
      }
    }
  }
  return tiles;
}

/// Where a tile is drawn on screen.
Rect tileRect(MapTile tile, MapCamera camera, int zoom) {
  final scale = math.pow(2, camera.zoom - zoom).toDouble();
  final tileSide = mapTileSize * scale;
  final world = mapWorldSize(zoom.toDouble()) * scale;
  final middle = projectLatLng(camera.center) * world;
  final left = tile.x * tileSide - middle.dx + camera.size.width / 2;
  final top = tile.y * tileSide - middle.dy + camera.size.height / 2;
  // A hair of overlap hides the seam anti-aliasing leaves between tiles.
  return Rect.fromLTWH(left, top, tileSide + 0.5, tileSide + 0.5);
}

/// Paints the basemap.
///
/// A tile that has not arrived yet is stood in for by the matching piece of a
/// tile from further out, scaled up. That is what stops a zoom from flashing
/// empty, and it costs nothing because those tiles are already in hand.
class MapTilePainter extends CustomPainter {
  MapTilePainter({
    required this.camera,
    required this.provider,
    required this.style,
    required this.cache,
    required this.background,
  }) : super(repaint: cache);

  final MapCamera camera;
  final MapTileProvider provider;
  final MapStyleName style;
  final MapTileCache cache;
  final Color background;

  /// How many grids further out to look for a stand-in.
  static const _fallbackDepth = 4;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final zoom = tileZoomFor(camera, provider.maxZoom);
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..isAntiAlias = false;

    for (final tile in visibleTiles(camera, zoom)) {
      final rect = tileRect(tile, camera, zoom);
      final image = cache.peek(provider, style, tile);
      if (image != null) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          paint,
        );
        continue;
      }
      _paintFallback(canvas, tile, rect, paint);
    }
  }

  void _paintFallback(Canvas canvas, MapTile tile, Rect rect, Paint paint) {
    for (var step = 1; step <= _fallbackDepth; step++) {
      final zoom = tile.z - step;
      if (zoom < 0) {
        return;
      }
      final span = 1 << step;
      final parent = MapTile(tile.x >> step, tile.y >> step, zoom);
      final image = cache.peek(provider, style, parent);
      if (image == null) {
        continue;
      }
      // The piece of the parent that covers exactly this tile.
      final pieceWidth = image.width / span;
      final pieceHeight = image.height / span;
      final column = tile.x - (parent.x << step);
      final row = tile.y - (parent.y << step);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          column * pieceWidth,
          row * pieceHeight,
          pieceWidth,
          pieceHeight,
        ),
        rect,
        paint,
      );
      return;
    }
  }

  @override
  bool shouldRepaint(MapTilePainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.style != style ||
      oldDelegate.background != background ||
      oldDelegate.provider.kind != provider.kind;
}

/// Asks for every tile the view needs.
///
/// Only what is on screen is fetched, which is what lets a map hold thousands
/// of rows without downloading the world.
void requestVisibleTiles({
  required MapCamera camera,
  required MapTileProvider provider,
  required MapStyleName style,
  required MapTileCache cache,
}) {
  if (camera.size.isEmpty) {
    return;
  }
  final zoom = tileZoomFor(camera, provider.maxZoom);
  for (final tile in visibleTiles(camera, zoom)) {
    cache.request(provider, style, tile);
  }
}

/// Keeps a picture of the map for the moment a screenshot is wanted.
typedef MapImageSink = void Function(ui.Image image);
