import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Holds the map pictures that have been fetched.
///
/// Tiles are only asked for while they are on screen, kept in a bounded set so
/// a long pan cannot grow without limit, and requested once however many times
/// a frame asks for them.
class MapTileCache extends ChangeNotifier {
  MapTileCache({this.capacity = 400, http.Client? client})
      : _client = client ?? http.Client();

  final int capacity;
  final http.Client _client;

  final LinkedHashMap<String, ui.Image> _tiles = LinkedHashMap();
  final Set<String> _loading = {};
  final Map<String, DateTime> _failed = {};
  bool _disposed = false;

  /// Whether a fetch failure has already been reported.
  ///
  /// A basemap that will not load is silent otherwise — the map simply stays
  /// blank — but one line is enough; there are hundreds of tiles.
  bool _reportedFailure = false;

  /// How long a tile that failed is left alone before being tried again.
  static const _retryAfter = Duration(seconds: 20);

  static String keyFor(
    MapTileProvider provider,
    MapStyleName style,
    MapTile tile,
  ) {
    final at = tile.wrapped;
    return '${provider.kind.id}|${style.name}|${at.z}/${at.x}/${at.y}';
  }

  /// The picture for a tile if it is already here. Never starts a fetch, so it
  /// is safe to call from inside a paint.
  ui.Image? peek(
    MapTileProvider provider,
    MapStyleName style,
    MapTile tile,
  ) {
    final key = keyFor(provider, style, tile);
    final image = _tiles.remove(key);
    if (image == null) {
      return null;
    }
    // Touching a tile keeps it from being the next one dropped.
    _tiles[key] = image;
    return image;
  }

  bool isLoading(MapTileProvider provider, MapStyleName style, MapTile tile) =>
      _loading.contains(keyFor(provider, style, tile));

  /// Fetches a tile unless it is already here, on its way, or recently failed.
  void request(
    MapTileProvider provider,
    MapStyleName style,
    MapTile tile,
  ) {
    if (_disposed || !tile.isOnEarth) {
      return;
    }
    final key = keyFor(provider, style, tile);
    if (_tiles.containsKey(key) || _loading.contains(key)) {
      return;
    }
    final failedAt = _failed[key];
    if (failedAt != null && DateTime.now().difference(failedAt) < _retryAfter) {
      return;
    }
    final uri = provider.tileUri(tile, style);
    if (uri == null) {
      // The provider is not ready; warming it up will bring us back here.
      unawaited(
        provider.warmUp(style).then((_) {
          if (!_disposed) {
            notifyListeners();
          }
        }),
      );
      return;
    }
    _loading.add(key);
    unawaited(_fetch(key, uri, provider.headers));
  }

  Future<void> _fetch(String key, Uri uri, Map<String, String> headers) async {
    try {
      final response = await _client.get(uri, headers: headers);
      if (_disposed) {
        return;
      }
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        _note('$uri answered ${response.statusCode}');
        _failed[key] = DateTime.now();
        return;
      }
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _failed.remove(key);
      _store(key, frame.image);
    } on Object catch (error) {
      _note('$uri could not be read: $error');
      _failed[key] = DateTime.now();
    } finally {
      _loading.remove(key);
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  void _note(String message) {
    if (_reportedFailure) {
      return;
    }
    _reportedFailure = true;
    Log.warn('[Map] no basemap: $message');
  }

  void _store(String key, ui.Image image) {
    _tiles[key] = image;
    while (_tiles.length > capacity) {
      final oldest = _tiles.keys.first;
      _tiles.remove(oldest)?.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _tiles.values) {
      image.dispose();
    }
    _tiles.clear();
    _client.close();
    super.dispose();
  }
}
