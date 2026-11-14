import 'dart:convert';
import 'dart:ui' show Color, ColorFilter;

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

  /// How this provider's pictures are toned to suit [style], for a provider
  /// with only one look of its own. Null draws them as they come.
  ColorFilter? toneFor(MapStyleName style) => null;

  /// Does any handshake the service needs before it will serve tiles.
  Future<void> warmUp(MapStyleName style) async {}
}

/// OpenStreetMap's own tiles. Needs no key, so this is what a map draws until
/// a Google key is configured.
///
/// There is one street map, in full colour; the application's light, dark and
/// paper looks are toned from it as it is drawn.
class OpenStreetMapTileProvider extends MapTileProvider {
  const OpenStreetMapTileProvider();

  @override
  MapProviderKind get kind => MapProviderKind.openStreetMap;

  @override
  String get attribution => '© OpenStreetMap contributors';

  @override
  int get maxZoom => 19;

  @override
  bool supports(MapStyleName style) => style != MapStyleName.satellite;

  @override
  Map<String, String> get headers => const {
        // Their policy requires an application that can be identified.
        'User-Agent': 'AppFlowy/0.11 (https://appflowy.io)',
      };

  @override
  ColorFilter? toneFor(MapStyleName style) => switch (style) {
        MapStyleName.light => _MapTones.light,
        MapStyleName.dark => _MapTones.dark,
        MapStyleName.paper => _MapTones.paper,
        _ => null,
      };

  @override
  Uri? tileUri(MapTile tile, MapStyleName style) {
    final at = tile.wrapped;
    return Uri.parse(
      'https://tile.openstreetmap.org/${at.z}/${at.x}/${at.y}.png',
    );
  }
}

/// The application's looks, toned from a full-colour street map.
abstract final class _MapTones {
  /// Softened, so the map sits back behind what is pinned on it.
  static final light = ColorFilter.matrix(
    _mix(_saturate(0.55), _flat(const Color(0xFFFFFFFF)), 0.1),
  );

  /// Lightness turned over with the hues kept, settled onto the dark canvas
  /// and quietened.
  static final dark = ColorFilter.matrix(
    _then(
      _then(_then(_invert, _hueTurn), _scale(0.85, 22)),
      _saturate(0.75),
    ),
  );

  /// Warm and quiet: a sepia ramp from the paper's ink to its sheet, with a
  /// little of the map's own colour left to tell water and parks apart.
  static final paper = ColorFilter.matrix(
    _mix(
      _ramp(const Color(0xFF3B352E), const Color(0xFFFBF5E9)),
      _identity,
      0.28,
    ),
  );

  static const _r = 0.2126;
  static const _g = 0.7152;
  static const _b = 0.0722;

  static const _identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static const _invert = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  /// Hues turned half way round, lightness kept.
  static const _hueTurn = <double>[
    -0.574, 1.43, 0.144, 0, 0, //
    0.426, 0.43, 0.144, 0, 0, //
    0.426, 1.43, -0.856, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static List<double> _saturate(double s) => [
        _r * (1 - s) + s, _g * (1 - s), _b * (1 - s), 0, 0, //
        _r * (1 - s), _g * (1 - s) + s, _b * (1 - s), 0, 0, //
        _r * (1 - s), _g * (1 - s), _b * (1 - s) + s, 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _scale(double factor, double offset) => [
        factor, 0, 0, 0, offset, //
        0, factor, 0, 0, offset, //
        0, 0, factor, 0, offset, //
        0, 0, 0, 1, 0, //
      ];

  /// Every colour drawn as [color].
  static List<double> _flat(Color color) => [
        0, 0, 0, 0, color.r * 255, //
        0, 0, 0, 0, color.g * 255, //
        0, 0, 0, 0, color.b * 255, //
        0, 0, 0, 1, 0, //
      ];

  /// Lightness laid onto a ramp from [dark] to [light].
  static List<double> _ramp(Color dark, Color light) => [
        for (final (low, high) in [
          (dark.r, light.r),
          (dark.g, light.g),
          (dark.b, light.b),
        ]) ...[
          (high - low) * _r,
          (high - low) * _g,
          (high - low) * _b,
          0,
          low * 255,
        ],
        0, 0, 0, 1, 0, //
      ];

  /// [a] and [b] blended, [t] of the way to [b].
  static List<double> _mix(List<double> a, List<double> b, double t) => [
        for (var i = 0; i < 20; i++) a[i] * (1 - t) + b[i] * t,
      ];

  /// [first], then [second].
  static List<double> _then(List<double> first, List<double> second) {
    double at(List<double> m, int row, int column) =>
        row == 4 ? (column == 4 ? 1 : 0) : m[row * 5 + column];
    return [
      for (var row = 0; row < 4; row++)
        for (var column = 0; column < 5; column++)
          [
            for (var k = 0; k < 5; k++)
              at(second, row, k) * at(first, k, column),
          ].reduce((sum, value) => sum + value),
    ];
  }
}

/// CARTO's basemaps, which come in a light and a dark cut.
///
/// CARTO now answers every tile asked for without an API key with a notice
/// instead of the map, so it is only used when asked for by name.
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
/// nothing to open, and the map falls back to a keyless provider — as it does
/// when Google turns the key away (a demo key, one without the Map Tiles API)
/// or cannot be reached, rather than staying blank.
class GoogleTileProvider extends MapTileProvider {
  GoogleTileProvider({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  final Map<MapStyleName, String> _sessions = {};
  final Map<MapStyleName, Future<void>> _opening = {};

  /// Keys Google refused this session; they are not offered again.
  static final Set<String> _refusedKeys = {};

  /// Whether Google will not serve its map tiles for [apiKey], as with a Maps
  /// Demo Key, which has no Map Tiles API. Known once a map has asked.
  static bool isRefusedKey(String apiKey) => _refusedKeys.contains(apiKey);

  @visibleForTesting
  static void debugForgetRefusals() => _refusedKeys.clear();

  @visibleForTesting
  static void debugRefuse(String apiKey) => _refusedKeys.add(apiKey);

  /// Any other failure is worth retrying, but not on every frame.
  static const _retryAfter = Duration(minutes: 1);
  DateTime? _failedAt;

  MapStyleName _lastStyle = MapStyleName.streets;

  bool get _usingFallback {
    if (_refusedKeys.contains(apiKey)) {
      return true;
    }
    final failedAt = _failedAt;
    return failedAt != null &&
        DateTime.now().difference(failedAt) < _retryAfter;
  }

  static MapTileProvider _fallbackFor(MapStyleName style) =>
      const OpenStreetMapTileProvider();

  @override
  MapProviderKind get kind =>
      _usingFallback ? _fallbackFor(_lastStyle).kind : MapProviderKind.google;

  @override
  String get attribution =>
      _usingFallback ? _fallbackFor(_lastStyle).attribution : '© Google';

  @override
  int get maxZoom => _usingFallback ? _fallbackFor(_lastStyle).maxZoom : 20;

  @override
  Map<String, String> get headers =>
      _usingFallback ? _fallbackFor(_lastStyle).headers : const {};

  @override
  ColorFilter? toneFor(MapStyleName style) =>
      _usingFallback ? _fallbackFor(style).toneFor(style) : null;

  @override
  bool supports(MapStyleName style) => apiKey.isNotEmpty;

  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Uri? tileUri(MapTile tile, MapStyleName style) {
    _lastStyle = style;
    if (_usingFallback) {
      return _fallbackFor(style).tileUri(tile, style);
    }
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
    _lastStyle = style;
    if (apiKey.isEmpty || _usingFallback || _sessions.containsKey(style)) {
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
        final refused = response.statusCode >= 400 &&
            response.statusCode < 500 &&
            response.statusCode != 429;
        if (!refused) {
          _failedAt = DateTime.now();
        }
        if (!refused || _refusedKeys.add(apiKey)) {
          Log.warn(
            'Google map tiles refused a session (${response.statusCode}); '
            'drawing OpenStreetMap tiles instead.',
          );
        }
        return;
      }
      final body = jsonDecode(response.body);
      final session = body is Map ? body['session'] : null;
      if (session is String && session.isNotEmpty) {
        _sessions[style] = session;
      }
    } on Object catch (error) {
      _failedAt = DateTime.now();
      Log.warn('Could not open a Google map tile session: $error');
    }
  }
}

/// Picks the provider that can actually draw the wanted look.
///
/// Google is the default and is used whenever a key is configured; without
/// one OpenStreetMap keeps the map working out of the box. CARTO is only used
/// when asked for by name.
MapTileProvider resolveMapProvider({
  required MapProviderKind preferred,
  required MapStyleName style,
  String apiKey = '',
}) {
  if (preferred == MapProviderKind.google && apiKey.isNotEmpty) {
    return GoogleTileProvider(apiKey: apiKey);
  }
  if (preferred == MapProviderKind.carto &&
      const CartoTileProvider().supports(style)) {
    return const CartoTileProvider();
  }
  return const OpenStreetMapTileProvider();
}
