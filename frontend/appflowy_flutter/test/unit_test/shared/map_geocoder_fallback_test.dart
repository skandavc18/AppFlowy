import 'dart:convert';

import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _openMapParis = GeocodeResult(
  point: LatLng(48.8566, 2.3522),
  name: 'Paris',
);

/// Stands in for the keyless service, and remembers what it was asked.
class _OpenMap implements MapGeocoder {
  final searched = <String>[];
  final lookedUp = <MapLocation>[];

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) async {
    lookedUp.add(location);
    return _openMapParis;
  }

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) async {
    searched.add(query);
    return const [_openMapParis];
  }
}

/// Google's three services, each answering with what it is given.
class _Google {
  _Google({
    http.Response Function(http.Request request)? places,
    http.Response Function(http.Request request)? geocoding,
    http.Response Function(http.Request request)? legacy,
  })  : _places = places ?? ((_) => _denied()),
        _geocoding = geocoding ?? ((_) => _denied()),
        _legacy = legacy ?? ((_) => _legacyStatus('REQUEST_DENIED'));

  final http.Response Function(http.Request request) _places;
  final http.Response Function(http.Request request) _geocoding;
  final http.Response Function(http.Request request) _legacy;
  final asked = <http.Request>[];

  Iterable<String> get hosts => asked.map((request) => request.url.host);

  late final geocoder = GoogleGeocoder(
    apiKey: 'demo-key',
    client: MockClient((request) async {
      asked.add(request);
      return switch (request.url.host) {
        'places.googleapis.com' => _places(request),
        'geocode.googleapis.com' => _geocoding(request),
        _ => _legacy(request),
      };
    }),
  );
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// How the newer services turn a key away.
http.Response _denied() => _json(
      {
        'error': {
          'code': 403,
          'status': 'PERMISSION_DENIED',
          'details': [
            {'reason': 'SERVICE_DISABLED'},
          ],
        },
      },
      403,
    );

http.Response _spent() => _json(
      {
        'error': {'code': 429, 'status': 'RESOURCE_EXHAUSTED'},
      },
      429,
    );

/// The legacy API reports most outcomes, refusals included, inside a 200.
http.Response _legacyStatus(String status) =>
    _json({'status': status, 'results': const []});

http.Response _place(String name, String address, double lat, double lng) =>
    _json({
      'places': [
        {
          'id': 'place-$name',
          'displayName': {'text': name, 'languageCode': 'en'},
          'formattedAddress': address,
          'location': {'latitude': lat, 'longitude': lng},
        },
      ],
    });

http.Response _geocode(String address, double lat, double lng) => _json({
      'results': [
        {
          'placeId': 'geocode-1',
          'formattedAddress': address,
          'location': {'latitude': lat, 'longitude': lng},
        },
      ],
    });

void main() {
  group('a Maps Demo Key', () {
    test('searches with Places, naming each place as Google does', () async {
      final google = _Google(
        places: (request) {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/places:searchText');
          expect(request.headers['X-Goog-Api-Key'], 'demo-key');
          expect(request.headers['X-Goog-FieldMask'], contains('location'));
          expect(jsonDecode(request.body)['textQuery'], 'Akshaya Hall');
          return _place(
            'Akshaya Hall',
            'R.S. Arcade, Basavanagudi, Bengaluru',
            12.93293,
            77.57145,
          );
        },
      );
      final openMap = _OpenMap();
      final geocoder =
          FallbackGeocoder(primary: google.geocoder, fallback: openMap);

      final found = (await geocoder.search('Akshaya Hall')).single;

      expect(found.name, 'Akshaya Hall');
      expect(found.address, 'R.S. Arcade, Basavanagudi, Bengaluru');
      expect(found.point, const LatLng(12.93293, 77.57145));
      expect(found.source, GeocodeSource.google);
      expect(google.hosts, ['places.googleapis.com']);
      expect(openMap.searched, isEmpty);
    });

    test('looks written places up with Geocoding first', () async {
      final google = _Google(
        geocoding: (request) {
          // The address is one path segment, so a slash in it cannot
          // reach another endpoint.
          expect(
            request.url.pathSegments,
            ['v4', 'geocode', 'address', 'Flat 2/14, Jayanagar'],
          );
          return _geocode('Flat 2/14, Jayanagar, Bengaluru', 12.93, 77.58);
        },
      );

      final found = await google.geocoder
          .lookUp(parseMapLocation('Flat 2/14, Jayanagar'));

      expect(found?.name, 'Flat 2/14');
      expect(found?.point, const LatLng(12.93, 77.58));
      expect(found?.source, GeocodeSource.google);
      expect(google.hosts, ['geocode.googleapis.com']);
    });

    test('finds a place id from a pasted link with Place Details', () async {
      final google = _Google(
        places: (request) {
          expect(request.method, 'GET');
          expect(request.url.pathSegments, ['v1', 'places', 'ChIJabc']);
          return _json({
            'id': 'ChIJabc',
            'displayName': {'text': 'Lalbagh'},
            'formattedAddress': 'Mavalli, Bengaluru',
            'location': {'latitude': 12.9507, 'longitude': 77.5848},
          });
        },
      );

      final found = await google.geocoder
          .lookUp(const MapLocation(placeId: 'ChIJabc', query: 'Lalbagh'));

      expect(found?.name, 'Lalbagh');
      expect(found?.placeId, 'ChIJabc');
      expect(google.hosts, ['places.googleapis.com']);
    });

    test('a service the key does not have is not asked again', () async {
      final google = _Google(
        geocoding: (_) => _geocode('Jayanagar, Bengaluru', 12.93, 77.58),
      );

      await google.geocoder.search('Jayanagar');
      await google.geocoder.search('Basavanagudi');

      // Places refused the key once; Geocoding answered both times; the
      // legacy API was never needed.
      expect(google.hosts, [
        'places.googleapis.com',
        'geocode.googleapis.com',
        'geocode.googleapis.com',
      ]);
      expect(google.geocoder.isRefused, isFalse);
    });
  });

  group('a configured Google key that cannot search', () {
    test('searches OpenStreetMap instead, and is not asked again', () async {
      final google = _Google();
      final openMap = _OpenMap();
      final geocoder =
          FallbackGeocoder(primary: google.geocoder, fallback: openMap);

      expect(await geocoder.search('Paris'), const [_openMapParis]);
      expect(google.geocoder.isRefused, isTrue);
      expect(google.asked, hasLength(3));

      expect(await geocoder.search('Lyon'), const [_openMapParis]);
      expect(google.asked, hasLength(3));
      expect(openMap.searched, ['Paris', 'Lyon']);
    });

    test('an invalid key counts as refused too', () async {
      final invalid = _json(
        {
          'error': {
            'code': 400,
            'status': 'INVALID_ARGUMENT',
            'details': [
              {'reason': 'API_KEY_INVALID'},
            ],
          },
        },
        400,
      );
      final google = _Google(
        places: (_) => invalid,
        geocoding: (_) => invalid,
        legacy: (_) => http.Response('Forbidden', 403),
      );

      expect(await google.geocoder.search('Paris'), isEmpty);
      expect(google.geocoder.isRefused, isTrue);
    });

    test('looking a written place up falls back as well', () async {
      final google = _Google();
      final openMap = _OpenMap();
      final geocoder =
          FallbackGeocoder(primary: google.geocoder, fallback: openMap);
      final location = parseMapLocation('10 Downing Street, London');

      expect(await geocoder.lookUp(location), same(_openMapParis));
      expect(openMap.lookedUp, [location]);
    });
  });

  test(
      "a spent daily quota rests Google rather than giving up on it, and "
      "OpenStreetMap answers meanwhile", () async {
    final google = _Google(
      places: (_) => _spent(),
      geocoding: (_) => _spent(),
      legacy: (_) => _legacyStatus('OVER_QUERY_LIMIT'),
    );
    final openMap = _OpenMap();
    final geocoder =
        FallbackGeocoder(primary: google.geocoder, fallback: openMap);

    expect(await geocoder.search('Paris'), const [_openMapParis]);
    expect(await geocoder.search('Lyon'), const [_openMapParis]);

    expect(google.asked, hasLength(3));
    expect(google.geocoder.isRefused, isFalse);
    expect(openMap.searched, ['Paris', 'Lyon']);
  });

  test(
      'what Google cannot find is asked of OpenStreetMap, without giving '
      'up on Google', () async {
    final google = _Google(
      places: (_) => _json(const {}),
      geocoding: (_) => _json({'results': const []}),
      legacy: (_) => _legacyStatus('ZERO_RESULTS'),
    );
    final openMap = _OpenMap();
    final geocoder =
        FallbackGeocoder(primary: google.geocoder, fallback: openMap);

    expect(await geocoder.search('Atlantis'), const [_openMapParis]);
    expect(google.geocoder.isRefused, isFalse);

    await geocoder.search('Lemuria');
    expect(google.asked, hasLength(6));
    expect(openMap.searched, ['Atlantis', 'Lemuria']);
  });

  test('a place found by Google is remembered as Google\'s', () {
    const found = GeocodeResult(
      point: LatLng(12.93, 77.58),
      name: 'Jayanagar',
      source: GeocodeSource.google,
    );

    final read = GeocodeResult.fromJson(found.toJson());

    expect(read?.source, GeocodeSource.google);
    expect(
      GeocodeResult.fromJson(_openMapParis.toJson())?.source,
      GeocodeSource.openStreetMap,
    );
  });

  test('a keyed geocoder falls back to the one shared keyless geocoder', () {
    final keyed = resolveGeocoder(apiKey: 'shared-key');

    expect(keyed, isA<FallbackGeocoder>());
    expect((keyed as FallbackGeocoder).fallback, same(resolveGeocoder()));
    expect(resolveGeocoder(apiKey: 'shared-key'), same(keyed));

    // Another keyless fallback still shares what Google said about the key.
    final other = resolveGeocoder(apiKey: 'shared-key', keyless: _OpenMap());
    expect((other as FallbackGeocoder).primary, same(keyed.primary));
  });
}
