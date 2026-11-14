import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Who found a place, and so who has to be credited where it is shown.
enum GeocodeSource { google, openStreetMap }

/// A place that was found.
@immutable
class GeocodeResult {
  const GeocodeResult({
    required this.point,
    required this.name,
    this.address = '',
    this.placeId,
    this.source = GeocodeSource.openStreetMap,
  });

  final LatLng point;
  final String name;
  final String address;
  final String? placeId;
  final GeocodeSource source;

  Map<String, Object?> toJson() => {
        'lat': point.latitude,
        'lng': point.longitude,
        'name': name,
        if (address.isNotEmpty) 'address': address,
        if (placeId != null) 'place_id': placeId,
        if (source == GeocodeSource.google) 'source': 'google',
      };

  static GeocodeResult? fromJson(Map<String, dynamic> values) {
    final lat = (values['lat'] as num?)?.toDouble();
    final lng = (values['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      return null;
    }
    return GeocodeResult(
      point: LatLng(lat, lng),
      name: values['name'] as String? ?? '',
      address: values['address'] as String? ?? '',
      placeId: values['place_id'] as String?,
      source: values['source'] == 'google'
          ? GeocodeSource.google
          : GeocodeSource.openStreetMap,
    );
  }
}

/// Turns what someone wrote into a place on the map.
abstract class MapGeocoder {
  Future<GeocodeResult?> lookUp(MapLocation location);

  Future<List<GeocodeResult>> search(String query, {int limit = 6});
}

/// Google's place search. Used whenever a key is configured.
///
/// Three of Google's services can answer, and a key may be allowed some and
/// not others: a Maps Demo Key has Places API (New) and Geocoding API v4 but
/// not the legacy Geocoding API, and an older key can be the other way round.
/// Each is asked in turn. One that turns the key away is not asked again, and
/// one whose daily quota is spent is left to rest rather than asked on every
/// keystroke.
///
/// Searches go to Places first, which ranks by relevance and by where the
/// person is. Places written in a table go to Geocoding first, which is made
/// for addresses, so the two share the work between their quotas.
class GoogleGeocoder implements MapGeocoder {
  GoogleGeocoder({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  final _places = _GoogleService('Places API');
  final _geocoding = _GoogleService('Geocoding API');
  final _legacy = _GoogleService('legacy Geocoding API');

  static const _timeout = Duration(seconds: 12);
  static const _placeFields = 'id,displayName,formattedAddress,location';

  /// Whether Google has turned the key away for every service that can
  /// answer. It is not asked again.
  bool get isRefused =>
      _places.refused && _geocoding.refused && _legacy.refused;

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) async {
    final placeId = location.placeId;
    if (placeId != null) {
      final found = await _placeDetails(placeId) ??
          await _geocodePlace(placeId) ??
          _first(await _askLegacy({'place_id': placeId}));
      if (found != null) {
        return found;
      }
    }
    final query = location.query.trim();
    if (query.isEmpty) {
      return null;
    }
    return _first(await _geocodeAddress(query)) ??
        _first(await _searchText(query, 1)) ??
        _first(await _askLegacy({'address': query}));
  }

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) async {
    final text = query.trim();
    if (text.isEmpty) {
      return const [];
    }
    for (final ask in [
      () => _searchText(text, limit),
      () => _geocodeAddress(text),
      () => _askLegacy({'address': text}),
    ]) {
      final found = await ask();
      if (found.isNotEmpty) {
        return found.take(limit).toList();
      }
    }
    return const [];
  }

  /// Places API (New) Text Search: names and addresses alike.
  Future<List<GeocodeResult>> _searchText(String query, int limit) async {
    final body = await _ask(
      _places,
      () => _client.post(
        Uri.https('places.googleapis.com', '/v1/places:searchText'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask':
              _placeFields.split(',').map((field) => 'places.$field').join(','),
        },
        body: jsonEncode({
          'textQuery': query,
          'maxResultCount': limit.clamp(1, 20),
        }),
      ),
    );
    final places = body is Map ? body['places'] : null;
    if (places is! List) {
      return const [];
    }
    return places.whereType<Map>().map(_readPlace).nonNulls.toList();
  }

  /// Places API (New) Place Details, for a place id from a pasted link.
  Future<GeocodeResult?> _placeDetails(String placeId) async {
    final body = await _ask(
      _places,
      () => _client.get(
        Uri(
          scheme: 'https',
          host: 'places.googleapis.com',
          pathSegments: ['v1', 'places', placeId],
        ),
        headers: {'X-Goog-Api-Key': apiKey, 'X-Goog-FieldMask': _placeFields},
      ),
    );
    return body is Map ? _readPlace(body) : null;
  }

  /// Geocoding API v4, for an address written out.
  Future<List<GeocodeResult>> _geocodeAddress(String query) async {
    final body = await _ask(
      _geocoding,
      () => _client.get(
        Uri(
          scheme: 'https',
          host: 'geocode.googleapis.com',
          // A path segment, so a slash in the address cannot change the path.
          pathSegments: ['v4', 'geocode', 'address', query],
        ),
        headers: {'X-Goog-Api-Key': apiKey},
      ),
    );
    final results = body is Map ? body['results'] : null;
    if (results is! List) {
      return const [];
    }
    return results.whereType<Map>().map(_readGeocode).nonNulls.toList();
  }

  /// Geocoding API v4, for a place id.
  Future<GeocodeResult?> _geocodePlace(String placeId) async {
    final body = await _ask(
      _geocoding,
      () => _client.get(
        Uri(
          scheme: 'https',
          host: 'geocode.googleapis.com',
          pathSegments: ['v4', 'geocode', 'places', placeId],
        ),
        headers: {'X-Goog-Api-Key': apiKey},
      ),
    );
    return body is Map ? _readGeocode(body) : null;
  }

  /// Asks one of the newer services, which answer in plain HTTP statuses.
  Future<Object?> _ask(
    _GoogleService service,
    Future<http.Response> Function() send,
  ) async {
    if (apiKey.isEmpty || !service.isAvailable) {
      return null;
    }
    try {
      final response = await send().timeout(_timeout);
      final status = response.statusCode;
      if (status == 200) {
        return jsonDecode(response.body);
      }
      final reason = _errorOf(response.body) ?? 'HTTP $status';
      if (status == 429) {
        service.rest(_GoogleService.quotaRest, reason);
      } else if (status == 401 ||
          status == 403 ||
          (status == 400 && reason.contains('API_KEY'))) {
        service.refuse(reason);
      } else if (status >= 500) {
        service.rest(_GoogleService.troubleRest, reason);
      }
      // Otherwise a request it could not use, or a place it does not know:
      // nothing was found.
      return null;
    } on Object catch (error) {
      service.rest(_GoogleService.troubleRest, '$error');
      return null;
    }
  }

  /// The legacy Geocoding API, which reports most outcomes, refusals
  /// included, inside a 200 response.
  Future<List<GeocodeResult>> _askLegacy(Map<String, String> query) async {
    if (apiKey.isEmpty || !_legacy.isAvailable) {
      return const [];
    }
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        ...query,
        'key': apiKey,
      });
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        final status = response.statusCode;
        if (status == 429) {
          _legacy.rest(_GoogleService.quotaRest, 'HTTP $status');
        } else if (status >= 400 && status < 500) {
          _legacy.refuse('HTTP $status');
        } else {
          _legacy.rest(_GoogleService.troubleRest, 'HTTP $status');
        }
        return const [];
      }
      final body = jsonDecode(response.body);
      if (body is! Map) {
        return const [];
      }
      final status = body['status'];
      if (status != 'OK') {
        final reason = '$status ${body['error_message'] ?? ''}'.trim();
        if (status == 'REQUEST_DENIED' || status == 'OVER_DAILY_LIMIT') {
          _legacy.refuse(reason);
        } else if (status == 'OVER_QUERY_LIMIT') {
          _legacy.rest(_GoogleService.quotaRest, reason);
        }
        return const [];
      }
      final results = body['results'];
      if (results is! List) {
        return const [];
      }
      return results.whereType<Map>().map(_readLegacy).nonNulls.toList();
    } on Object catch (error) {
      _legacy.rest(_GoogleService.troubleRest, '$error');
      return const [];
    }
  }

  static GeocodeResult? _first(List<GeocodeResult> found) =>
      found.isEmpty ? null : found.first;

  static GeocodeResult? _readPlace(Map place) {
    final point = _pointOf(place['location']);
    if (point == null) {
      return null;
    }
    final displayName = place['displayName'];
    final name = displayName is Map ? displayName['text'] as String? : null;
    final address = place['formattedAddress'] as String? ?? '';
    return GeocodeResult(
      point: point,
      name: name ?? address.split(',').first.trim(),
      address: address,
      placeId: place['id'] as String?,
      source: GeocodeSource.google,
    );
  }

  static GeocodeResult? _readGeocode(Map result) {
    final point = _pointOf(result['location']);
    if (point == null) {
      return null;
    }
    final address = result['formattedAddress'] as String? ?? '';
    return GeocodeResult(
      point: point,
      name: address.split(',').first.trim(),
      address: address,
      placeId: result['placeId'] as String?,
      source: GeocodeSource.google,
    );
  }

  static GeocodeResult? _readLegacy(Map result) {
    final geometry = result['geometry'];
    final location = geometry is Map ? geometry['location'] : null;
    if (location is! Map) {
      return null;
    }
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      return null;
    }
    final address = result['formatted_address'] as String? ?? '';
    return GeocodeResult(
      point: LatLng(lat, lng),
      name: address.split(',').first.trim(),
      address: address,
      placeId: result['place_id'] as String?,
      source: GeocodeSource.google,
    );
  }

  static LatLng? _pointOf(Object? location) {
    if (location is! Map) {
      return null;
    }
    final lat = (location['latitude'] as num?)?.toDouble();
    final lng = (location['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      return null;
    }
    final point = LatLng(lat, lng);
    return point.isValid ? point : null;
  }

  /// Google's own name for an error, like `PERMISSION_DENIED
  /// SERVICE_DISABLED`, where the body gives one.
  static String? _errorOf(String body) {
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      if (error is! Map) {
        return null;
      }
      final details = error['details'];
      final reasons = [
        if (error['status'] is String) error['status'] as String,
        if (details is List)
          for (final detail in details.whereType<Map>())
            if (detail['reason'] is String) detail['reason'] as String,
      ];
      return reasons.isEmpty ? error['message'] as String? : reasons.join(' ');
    } on FormatException {
      return null;
    }
  }
}

/// What one of Google's services has said about the key so far.
class _GoogleService {
  _GoogleService(this.name);

  final String name;

  /// A spent daily quota comes back, but not within minutes.
  static const quotaRest = Duration(minutes: 30);

  /// Anything else that went wrong is worth trying again soon.
  static const troubleRest = Duration(minutes: 1);

  bool refused = false;
  DateTime? _restingUntil;

  bool get isAvailable {
    final until = _restingUntil;
    return !refused && (until == null || DateTime.now().isAfter(until));
  }

  void refuse(String reason) {
    if (refused) {
      return;
    }
    refused = true;
    Log.warn('Google refused the maps key for the $name ($reason).');
  }

  void rest(Duration duration, String reason) {
    final until = _restingUntil;
    final resting = until != null && DateTime.now().isBefore(until);
    _restingUntil = DateTime.now().add(duration);
    if (!resting) {
      Log.warn(
        'The $name is not answering ($reason); asking again in '
        '${duration.inMinutes} min.',
      );
    }
  }
}

/// OpenStreetMap's search, which needs no key and so keeps addresses working
/// out of the box.
///
/// Their policy allows one request a second from an application that names
/// itself, so requests are queued rather than fired off together.
class NominatimGeocoder implements MapGeocoder {
  NominatimGeocoder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _minimumGap = Duration(milliseconds: 1100);
  Future<void> _queue = Future.value();
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) async {
    final results = await search(location.query, limit: 1);
    return results.isEmpty ? null : results.first;
  }

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) {
    if (query.trim().isEmpty) {
      return Future.value(const []);
    }
    final completer = Completer<List<GeocodeResult>>();
    _queue = _queue.then((_) async {
      final since = DateTime.now().difference(_lastCall);
      if (since < _minimumGap) {
        await Future<void>.delayed(_minimumGap - since);
      }
      _lastCall = DateTime.now();
      completer.complete(await _ask(query, limit));
    });
    return completer.future;
  }

  Future<List<GeocodeResult>> _ask(String query, int limit) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '$limit',
        'addressdetails': '0',
      });
      final response = await _client.get(
        uri,
        headers: const {'User-Agent': 'AppFlowy/0.11 (https://appflowy.io)'},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        // Being turned away reads exactly like a place that does not exist,
        // and the two want different things done about them.
        Log.warn(
          'OpenStreetMap refused a search with ${response.statusCode}: $query',
        );
        return const [];
      }
      final body = jsonDecode(response.body);
      if (body is! List) {
        return const [];
      }
      return body
          .whereType<Map>()
          .map((place) {
            final lat = double.tryParse('${place['lat']}');
            final lon = double.tryParse('${place['lon']}');
            if (lat == null || lon == null) {
              return null;
            }
            final display = place['display_name'] as String? ?? '';
            return GeocodeResult(
              point: LatLng(lat, lon),
              name: place['name'] as String? ?? display.split(',').first.trim(),
              address: display,
            );
          })
          .nonNulls
          .toList();
    } on Object catch (error) {
      Log.warn('Could not find a place: $error');
      return const [];
    }
  }
}

/// Remembers what was found, so opening a table twice does not look every
/// address up twice.
class GeocodeCache {
  GeocodeCache._();

  static final GeocodeCache instance = GeocodeCache._();

  static const _storageKey = 'appflowy_geocode_cache';
  static const _capacity = 2000;

  final Map<String, GeocodeResult> _found = {};
  bool _loaded = false;
  Timer? _save;

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      final stored = await getIt<KeyValueStorage>().get(_storageKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final values = jsonDecode(stored);
      if (values is! Map) {
        return;
      }
      for (final entry in values.entries) {
        final value = entry.value;
        if (value is! Map) {
          continue;
        }
        final result = GeocodeResult.fromJson(Map<String, dynamic>.from(value));
        if (result != null) {
          _found['${entry.key}'] = result;
        }
      }
    } on Object catch (error) {
      Log.warn('Could not read the places already found: $error');
    }
  }

  GeocodeResult? peek(String key) => _found[key];

  void remember(String key, GeocodeResult result) {
    if (_found.length >= _capacity) {
      _found.remove(_found.keys.first);
    }
    _found[key] = result;
    _scheduleSave();
  }

  void _scheduleSave() {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 3), () async {
      if (!getIt.isRegistered<KeyValueStorage>()) {
        return;
      }
      try {
        await getIt<KeyValueStorage>().set(
          _storageKey,
          jsonEncode({
            for (final entry in _found.entries) entry.key: entry.value.toJson(),
          }),
        );
      } on Object catch (error) {
        Log.warn('Could not store the places found: $error');
      }
    });
  }
}

/// Google first, while it answers; OpenStreetMap whenever it does not.
///
/// A key that cannot search must not leave every search empty: whatever Google
/// refuses or cannot find is asked of the keyless service instead.
class FallbackGeocoder implements MapGeocoder {
  FallbackGeocoder({required this.primary, required this.fallback});

  final GoogleGeocoder primary;
  final MapGeocoder fallback;

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) async {
    if (!primary.isRefused) {
      final found = await primary.lookUp(location);
      if (found != null) {
        return found;
      }
    }
    return fallback.lookUp(location);
  }

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) async {
    if (!primary.isRefused) {
      final found = await primary.search(query, limit: limit);
      if (found.isNotEmpty) {
        return found;
      }
    }
    return fallback.search(query, limit: limit);
  }
}

/// The key a location is remembered under.
String geocodeKeyFor(MapLocation location) =>
    location.placeId != null ? 'id:${location.placeId}' : 'q:${location.query}';

/// The geocoder for [apiKey], or for the key configured in Settings when none
/// is given.
///
/// The same one is handed back every time. Nominatim allows one request a
/// second from an application, and that budget is only kept if every caller
/// queues behind the same instance — a fresh one per lookup means the search
/// box and the map race each other into being turned away. A keyed geocoder
/// falls back to that same keyless one, or to [keyless] where a caller needs
/// another (search-as-you-type is not allowed on Nominatim), and every
/// geocoder for a key shares what Google has said about it.
MapGeocoder resolveGeocoder({String? apiKey, MapGeocoder? keyless}) {
  final key = apiKey ?? MapsSettings.instance.apiKey;
  final fallback = keyless ?? (_nominatim ??= NominatimGeocoder());
  if (key.isEmpty) {
    return fallback;
  }
  return _keyed.putIfAbsent(
    (key, fallback),
    () => FallbackGeocoder(
      primary: _google.putIfAbsent(key, () => GoogleGeocoder(apiKey: key)),
      fallback: fallback,
    ),
  );
}

NominatimGeocoder? _nominatim;
final Map<String, GoogleGeocoder> _google = {};
final Map<(String, MapGeocoder), FallbackGeocoder> _keyed = {};
