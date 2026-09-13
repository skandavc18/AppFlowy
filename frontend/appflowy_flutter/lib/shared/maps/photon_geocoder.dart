import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:http/http.dart' as http;

/// Keyless place search using Photon, whose public demo permits
/// search-as-you-type at reasonable volume, without an availability guarantee.
/// Only the place query, result limit, and language are sent; callers must not
/// include names or birth dates. Results are cached only in this instance's
/// memory, never in the persistent [GeocodeCache]. There is no provider fallback.
///
/// Reuse an instance to share its cache and pacing. UI callers should also
/// debounce typing and display Photon/OpenStreetMap attribution.
class PhotonGeocoder implements MapGeocoder {
  /// An injected [client] remains caller-owned. Otherwise each request owns a
  /// short-lived client, allowing timeouts to close stalled connections with
  /// the existing HTTP package. [now] and [delay] allow deterministic tests.
  PhotonGeocoder({
    http.Client? client,
    Uri? endpoint,
    this.requestTimeout = defaultTimeout,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  })  : _client = client,
        _endpoint = _validateEndpoint(
          endpoint ?? Uri.https('photon.komoot.io', '/api/'),
        ),
        _now = now ?? DateTime.now,
        _delay = delay ?? _wait {
    if (requestTimeout.isNegative) {
      throw ArgumentError('Photon request timeout must not be negative.');
    }
  }

  static const defaultLimit = 6;
  static const maxResults = 20;
  static const cacheCapacity = 100;
  static const maxPendingSearches = 4;
  static const maxQueryLength = 512;
  static const maxResponseBytes = 256 * 1024;
  static const defaultTimeout = Duration(seconds: 10);

  /// A conservative local pacing choice, not a published Photon quota.
  static const minimumInterval = Duration(milliseconds: 750);

  final Duration requestTimeout;
  final http.Client? _client;
  final Uri _endpoint;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final Map<(String, int), List<GeocodeResult>> _cache = {};
  final Map<(String, int), Future<List<GeocodeResult>>> _inFlight = {};
  Future<void> _queue = Future<void>.value();
  DateTime? _lastStartedAt;
  http.Client? _activeOwnedClient;
  bool _disposed = false;

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) async {
    _ensureOpen();
    final LatLng? point;
    try {
      point = location.point ?? parseMapLocation(location.query).point;
    } on Object {
      throw const _PhotonFailure(
        'Place location could not be read. Use coordinates or a city.',
      );
    }
    if (point != null) {
      if (!point.isValid) {
        throw const _PhotonFailure(
          'Place coordinates must be finite and within latitude/longitude bounds.',
        );
      }
      final label = location.label.trim();
      final name =
          label.isEmpty ? '${point.latitude}, ${point.longitude}' : label;
      return GeocodeResult(
        point: point,
        name: name,
        address: name,
        placeId: location.placeId,
      );
    }
    final results = await search(location.query, limit: 1);
    return results.isEmpty ? null : results.first;
  }

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = defaultLimit}) {
    if (_disposed) {
      return Future.error(
        const _PhotonFailure('Place search has been closed.'),
      );
    }
    final text = query.trim();
    // Explicit two-character searches are supported; the UI sets its own
    // higher threshold for automatic suggestions.
    if (text.length < 2 || limit <= 0) return Future.value(const []);
    if (text.length > maxQueryLength) {
      return Future.error(
        const _PhotonFailure('Place query is too long. Use a city or address.'),
      );
    }
    final count = limit.clamp(1, maxResults).toInt();
    final key = (text, count);
    final cached = _cache.remove(key);
    if (cached != null) {
      // Map insertion order gives a small least-recently-used cache.
      _cache[key] = cached;
      return Future.value(cached);
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    if (_inFlight.length >= maxPendingSearches) {
      return Future.error(
        const _PhotonFailure('Place search is busy. Wait a moment and retry.'),
      );
    }

    final completed = Completer<List<GeocodeResult>>();
    _inFlight[key] = completed.future;
    // Only a bounded number of operations may join this queue. Each operation
    // catches its own failure so neither errors nor timeouts poison the tail.
    _queue = _queue.then((_) async {
      try {
        _ensureOpen();
        final last = _lastStartedAt;
        if (last != null) {
          final remaining = minimumInterval - _now().difference(last);
          if (remaining > Duration.zero) {
            // A wall-clock correction must not stall the queue indefinitely.
            await _delay(
              remaining > minimumInterval ? minimumInterval : remaining,
            ).timeout(defaultTimeout);
          }
        }
        _ensureOpen();
        _lastStartedAt = _now();
        final results = await _ask(text, count);
        _ensureOpen();
        _cache[key] = results;
        if (_cache.length > cacheCapacity) _cache.remove(_cache.keys.first);
        completed.complete(results);
      } on _PhotonFailure catch (error, stack) {
        completed.completeError(error, stack);
      } on Object catch (_, stack) {
        completed.completeError(
          const _PhotonFailure('Place search is unavailable. Try again later.'),
          stack,
        );
      } finally {
        _inFlight.removeWhere((pendingKey, _) => pendingKey == key);
      }
    });
    return completed.future;
  }

  Future<List<GeocodeResult>> _ask(String query, int limit) async {
    final client = _client ?? http.Client();
    if (_client == null) _activeOwnedClient = client;
    StreamIterator<List<int>>? chunks;
    var finished = false;

    Future<List<int>> readResponse() async {
      final request = http.Request(
        'GET',
        _endpoint.replace(
          queryParameters: {'q': query, 'limit': '$limit', 'lang': 'en'},
        ),
      )
        // Do not forward place queries to an unexpected or insecure redirect.
        ..followRedirects = false
        ..headers.addAll(const {
          'Accept': 'application/json',
          'User-Agent': 'AppFlowy/0.11 (Photon place search)',
        });
      final response = await client.send(request);
      if (finished) {
        // An injected client can finish sending after our deadline. Discard
        // its late response without reading it or repopulating the cache.
        _discard(response.stream);
        return const [];
      }
      if (response.statusCode == 429) {
        _discard(response.stream);
        throw const _PhotonFailure(
          'Place search is rate-limited by Photon. Wait a moment and retry.',
        );
      }
      if (response.statusCode != 200) {
        _discard(response.stream);
        throw _PhotonFailure(
          'Place search is unavailable (Photon HTTP ${response.statusCode}). '
          'Try again later.',
        );
      }
      if ((response.contentLength ?? 0) > maxResponseBytes) {
        _discard(response.stream);
        throw const _PhotonFailure(
          'Photon place-search response is too large.',
        );
      }
      final iterator = StreamIterator<List<int>>(response.stream);
      chunks = iterator;
      final bytes = BytesBuilder(copy: false);
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const _PhotonFailure(
            'Photon place-search response is too large.',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    try {
      // One deadline covers both response headers and the entire body, even
      // when a server keeps sending small chunks without finishing.
      final bytes = await readResponse().timeout(requestTimeout);
      return _readResults(bytes, limit);
    } on TimeoutException {
      throw const _PhotonFailure('Place search timed out. Please try again.');
    } on _PhotonFailure {
      rethrow;
    } on Object {
      // Transport errors can include the complete URI. Never expose those,
      // response bodies, or JSON parser source excerpts to logs or callers.
      throw const _PhotonFailure(
        'Place search is unavailable. Try again later.',
      );
    } finally {
      finished = true;
      final iterator = chunks;
      if (iterator != null) _finishCancellation(iterator.cancel());
      if (_client == null && identical(_activeOwnedClient, client)) {
        _activeOwnedClient = null;
        client.close();
      }
    }
  }

  List<GeocodeResult> _readResults(List<int> bytes, int limit) {
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const _PhotonFailure(
        'Photon returned an invalid place-search response.',
      );
    }
    if (body is! Map ||
        (body.containsKey('type') && body['type'] != 'FeatureCollection')) {
      throw const _PhotonFailure(
        'Photon returned an invalid place-search response.',
      );
    }
    final features = body['features'];
    if (features is! List) {
      throw const _PhotonFailure(
        'Photon returned an invalid place-search response.',
      );
    }
    final results = <GeocodeResult>[];
    for (final feature in features) {
      final result = _readFeature(feature);
      if (result == null) continue;
      results.add(result);
      if (results.length == limit) break;
    }
    return List<GeocodeResult>.unmodifiable(results);
  }

  GeocodeResult? _readFeature(Object? feature) {
    if (feature is! Map ||
        (feature.containsKey('type') && feature['type'] != 'Feature')) {
      return null;
    }
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    if (geometry is! Map || properties is! Map || geometry['type'] != 'Point') {
      return null;
    }
    final coordinates = geometry['coordinates'];
    if (coordinates is! List ||
        coordinates.length < 2 ||
        coordinates.length > 3 ||
        !coordinates.every((value) => value is num && value.isFinite)) {
      return null;
    }
    // GeoJSON is longitude first. Do not clamp, round, or invent coordinates.
    final longitude = (coordinates[0] as num).toDouble();
    final latitude = (coordinates[1] as num).toDouble();
    final point = LatLng(latitude, longitude);
    if (!point.isValid) return null;

    String text(String key) {
      final value = properties[key];
      return value is String ? value.trim() : '';
    }

    final name = text('name');
    final street = text('street');
    final house = text('housenumber');
    final streetAddress = [house, street].where((s) => s.isNotEmpty).join(' ');
    final parts = <String>[];
    final seen = <String>{};
    for (final part in [
      if (name.toLowerCase() != street.toLowerCase() || house.isEmpty) name,
      streetAddress,
      text('district'),
      text('city'),
      text('county'),
      text('state'),
      text('postcode'),
      text('country'),
    ]) {
      if (part.isNotEmpty && seen.add(part.toLowerCase())) parts.add(part);
    }
    final address = parts.isEmpty
        ? '${point.latitude}, ${point.longitude}'
        : parts.join(', ');
    final osmType = text('osm_type').toUpperCase();
    final osmId = properties['osm_id'];
    final id = osmId is int ? '$osmId' : text('osm_id');
    final hasId = const ['N', 'W', 'R'].contains(osmType) &&
        RegExp(r'^[1-9][0-9]*$').hasMatch(id);
    return GeocodeResult(
      point: point,
      name: name.isNotEmpty ? name : parts.firstOrNull ?? address,
      address: address,
      placeId: hasId ? 'osm:$osmType:$id' : null,
    );
  }

  /// Clears the in-memory cache, rejects queued/new work, and closes any
  /// active owned client. A borrowed client's active request may finish (or
  /// time out), but cannot add results after disposal. This is idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cache.clear();
    _activeOwnedClient?.close();
    _activeOwnedClient = null;
  }

  void _ensureOpen() {
    if (_disposed) throw const _PhotonFailure('Place search has been closed.');
  }

  static Uri _validateEndpoint(Uri endpoint) {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment) {
      throw ArgumentError(
        'Photon endpoint must use HTTPS without credentials, query, or fragment.',
      );
    }
    return endpoint;
  }

  static Future<void> _wait(Duration duration) =>
      Future<void>.delayed(duration);

  static void _discard(Stream<List<int>> stream) {
    // StreamIterator.cancel before its first moveNext never subscribes, so an
    // unread response needs an actual subscription to cancel its transport.
    _finishCancellation(
      stream.listen(null, onError: (Object _, StackTrace __) {}).cancel(),
    );
  }

  static void _finishCancellation(Future<dynamic> cancellation) {
    // Cancellation must not stall the bounded queue or leak a transport error.
    unawaited(
      cancellation.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      ),
    );
  }
}

/// Only locally authored, privacy-safe messages may bypass error sanitizing.
class _PhotonFailure extends FormatException {
  const _PhotonFailure(super.message);
}
