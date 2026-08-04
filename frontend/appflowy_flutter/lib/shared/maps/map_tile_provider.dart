import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One square of the map grid.
@immutable
class MapTile {
  const MapTile(this.x, this.y, this.z);

  final int x;
  final int y;
  final int z;

  /// The world repeats east to west, so an x outside the grid wraps round.
  MapTile get wrapped {
    final span = 1 << z;
    var wrappedX = x % span;
    if (wrappedX < 0) {
      wrappedX += span;
    }
    return MapTile(wrappedX, y, z);
  }

  bool get isOnEarth {
    final span = 1 << z;
    return y >= 0 && y < span;
  }

  @override
  bool operator ==(Object other) =>
      other is MapTile && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '$z/$x/$y';
}

/// The look of the basemap.
enum MapStyleName {
  streets,
  light,
  dark,
  paper,
  satellite;

  bool get isDark => this == MapStyleName.dark;
}

/// Which service draws the map.
///
/// The application is not tied to one: adding Apple, Mapbox or HERE means
/// writing one more [MapTileProvider] and listing it here, and nothing that
/// draws or interacts with the map has to change.
enum MapProviderKind {
  google,
  openStreetMap,
  carto;

  String get id => name;

  static MapProviderKind fromId(String? id) =>
      MapProviderKind.values.firstWhere(
        (kind) => kind.id == id,
        orElse: () => MapProviderKind.google,
      );
}

/// Where the map's pictures come from.
abstract class MapTileProvider {
  const MapTileProvider();

  MapProviderKind get kind;

  /// The line of credit the licence requires to be shown on the map.
  String get attribution;

  int get maxZoom;

  bool supports(MapStyleName style);

  /// The address of one tile, or null while the provider is not ready.
  Uri? tileUri(MapTile tile, MapStyleName style);

  /// Servers identify callers by this; OpenStreetMap requires a real one.
  Map<String, String> get headers => const {};

  /// Does any handshake the service needs before it will serve tiles.
  Future<void> warmUp(MapStyleName style) async {}
}

/// OpenStreetMap's own tiles. Needs no key, so this is what a fresh
/// installation draws.
class OpenStreetMapTileProvider extends MapTileProvider {
  const OpenStreetMapTileProvider();

  @override
  MapProviderKind get kind => MapProviderKind.openStreetMap;

  @override
  String get attribution => '© OpenStreetMap contributors';

  @override
  int get maxZoom => 19;

  @override
  bool supports(MapStyleName style) => style == MapStyleName.streets;

  @override
  Map<String, String> get headers => const {
        // Their policy requires an application that can be identified.
        'User-Agent': 'AppFlowy/0.11 (https://appflowy.io)',
      };

  @override
  Uri? tileUri(MapTile tile, MapStyleName style) {
    final at = tile.wrapped;
    return Uri.parse(
      'https://tile.openstreetmap.org/${at.z}/${at.x}/${at.y}.png',
    );
  }
}

/// CARTO's basemaps, which come in a light and a dark cut — the two the
/// application's own appearances need. Also keyless.
class CartoTileProvider extends MapTileProvider {
  const CartoTileProvider();

  @override
  MapProviderKind get kind => MapProviderKind.carto;

  @override
  String get attribution => '© OpenStreetMap contributors © CARTO';

  @override
  int get maxZoom => 20;

  @override
  bool supports(MapStyleName style) => style != MapStyleName.satellite;

  @override
  Map<String, String> get headers => const {
        'User-Agent': 'AppFlowy/0.11 (https://appflowy.io)',
      };

  @override
  Uri? tileUri(MapTile tile, MapStyleName style) {
    final at = tile.wrapped;
    final sheet = switch (style) {
      MapStyleName.dark => 'dark_all',
      // Paper wants warm and quiet; voyager is the softest of the three.
      MapStyleName.paper => 'voyager_nolabels',
      MapStyleName.streets => 'voyager',
      _ => 'light_all',
    };
    return Uri.parse(
      'https://basemaps.cartocdn.com/rastertiles/$sheet/${at.z}/${at.x}/${at.y}@2x.png',
    );
  }
}

/// Google's own map pictures, through the Map Tiles API.
///
/// Google will not serve a tile without a session first, so the provider opens
/// one lazily and draws nothing until it has. Without an API key there is
/// nothing to open, and the map falls back to a keyless provider.
class GoogleTileProvider extends MapTileProvider {
  GoogleTileProvider({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  final Map<MapStyleName, String> _sessions = {};
  final Map<MapStyleName, Future<void>> _opening = {};

  @override
  MapProviderKind get kind => MapProviderKind.google;

  @override
  String get attribution => '© Google';

  @override
  int get maxZoom => 20;

  @override
  bool supports(MapStyleName style) => apiKey.isNotEmpty;

  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Uri? tileUri(MapTile tile, MapStyleName style) {
    final session = _sessions[style];
    if (session == null || apiKey.isEmpty) {
      return null;
    }
    final at = tile.wrapped;
    return Uri.parse(
      'https://tile.googleapis.com/v1/2dtiles/${at.z}/${at.x}/${at.y}'
      '?session=$session&key=$apiKey',
    );
  }

  @override
  Future<void> warmUp(MapStyleName style) {
    if (apiKey.isEmpty || _sessions.containsKey(style)) {
      return Future.value();
    }
    return _opening[style] ??= _openSession(style).whenComplete(() {
      _opening.remove(style);
    });
  }

  Future<void> _openSession(MapStyleName style) async {
    try {
      final response = await _client.post(
        Uri.parse('https://tile.googleapis.com/v1/createSession?key=$apiKey'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mapType': style == MapStyleName.satellite ? 'satellite' : 'roadmap',
          'language': 'en-US',
          'region': 'US',
          if (style == MapStyleName.dark) 'scale': 'scaleFactor2x',
        }),
      );
      if (response.statusCode != 200) {
        Log.warn('Google map tiles refused a session: ${response.statusCode}');
        return;
      }
      final body = jsonDecode(response.body);
      final session = body is Map ? body['session'] : null;
      if (session is String && session.isNotEmpty) {
        _sessions[style] = session;
      }
    } on Object catch (error) {
      Log.warn('Could not open a Google map tile session: $error');
    }
  }
}

/// Picks the provider that can actually draw the wanted look.
///
/// Google is the default and is used whenever a key is configured; the keyless
/// providers keep the map working out of the box.
MapTileProvider resolveMapProvider({
  required MapProviderKind preferred,
  required MapStyleName style,
  String apiKey = '',
}) {
  if (preferred == MapProviderKind.google && apiKey.isNotEmpty) {
    return GoogleTileProvider(apiKey: apiKey);
  }
  if (preferred == MapProviderKind.openStreetMap &&
      const OpenStreetMapTileProvider().supports(style)) {
    return const OpenStreetMapTileProvider();
  }
  if (const CartoTileProvider().supports(style)) {
    return const CartoTileProvider();
  }
  return const OpenStreetMapTileProvider();
}
