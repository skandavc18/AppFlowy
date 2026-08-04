import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A place that was found.
@immutable
class GeocodeResult {
  const GeocodeResult({
    required this.point,
    required this.name,
    this.address = '',
    this.placeId,
  });

  final LatLng point;
  final String name;
  final String address;
  final String? placeId;

  Map<String, Object?> toJson() => {
        'lat': point.latitude,
        'lng': point.longitude,
        'name': name,
        if (address.isNotEmpty) 'address': address,
        if (placeId != null) 'place_id': placeId,
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
    );
  }
}

/// Turns what someone wrote into a place on the map.
abstract class MapGeocoder {
  Future<GeocodeResult?> lookUp(MapLocation location);

  Future<List<GeocodeResult>> search(String query, {int limit = 6});
}

/// Google's Geocoding API. Used whenever a key is configured.
class GoogleGeocoder implements MapGeocoder {
  GoogleGeocoder({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) async {
    final results = await _ask(
      location.placeId != null
          ? {'place_id': location.placeId!}
          : {'address': location.query},
    );
    return results.isEmpty ? null : results.first;
  }

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) async {
    final results = await _ask({'address': query});
    return results.take(limit).toList();
  }

  Future<List<GeocodeResult>> _ask(Map<String, String> query) async {
    if (apiKey.isEmpty) {
      return const [];
    }
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        ...query,
        'key': apiKey,
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return const [];
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['status'] != 'OK') {
        return const [];
      }
      final results = body['results'];
      if (results is! List) {
        return const [];
      }
      return results.whereType<Map>().map(_readResult).nonNulls.toList();
    } on Object catch (error) {
      Log.warn('Google could not find a place: $error');
      return const [];
    }
  }

  GeocodeResult? _readResult(Map result) {
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
    );
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

/// The key a location is remembered under.
String geocodeKeyFor(MapLocation location) =>
    location.placeId != null ? 'id:${location.placeId}' : 'q:${location.query}';

/// The geocoder to use, given whether a key has been configured.
///
/// The same one is handed back every time. Nominatim allows one request a
/// second from an application, and that budget is only kept if every caller
/// queues behind the same instance — a fresh one per lookup means the search
/// box and the map race each other into being turned away.
MapGeocoder resolveGeocoder({String apiKey = ''}) => _geocoders.putIfAbsent(
      apiKey,
      () =>
          apiKey.isEmpty ? NominatimGeocoder() : GoogleGeocoder(apiKey: apiKey),
    );

final Map<String, MapGeocoder> _geocoders = {};
