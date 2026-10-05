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

/// Google's Geocoding API, answering every request with [answer].
class _Google {
  _Google(this.answer);

  final http.Response Function() answer;
  final asked = <Uri>[];

  late final geocoder = GoogleGeocoder(
    apiKey: 'demo-key',
    client: MockClient((request) async {
      asked.add(request.url);
      return answer();
    }),
  );
}

/// Google reports most outcomes, refusals included, inside a 200 response.
http.Response _status(String status, {List<Object?> results = const []}) =>
    http.Response(
      jsonEncode({
        'status': status,
        'results': results,
        if (status == 'REQUEST_DENIED')
          'error_message':
              'This API project is not authorized to use this API.',
      }),
      200,
    );

void main() {
  group('a configured Google key that cannot search', () {
    test('searches OpenStreetMap instead, and is not asked again', () async {
      final google = _Google(() => _status('REQUEST_DENIED'));
      final openMap = _OpenMap();
      final geocoder =
          FallbackGeocoder(primary: google.geocoder, fallback: openMap);

      expect(await geocoder.search('Paris'), const [_openMapParis]);
      expect(google.geocoder.isRefused, isTrue);

      expect(await geocoder.search('Lyon'), const [_openMapParis]);
      expect(google.asked, hasLength(1));
      expect(openMap.searched, ['Paris', 'Lyon']);
    });

    test('a key turned away outright counts as refused too', () async {
      final google = _Google(() => http.Response('Forbidden', 403));
      final openMap = _OpenMap();
      final geocoder =
          FallbackGeocoder(primary: google.geocoder, fallback: openMap);

      expect(await geocoder.search('Paris'), const [_openMapParis]);
      expect(google.geocoder.isRefused, isTrue);
    });

    test('looking a written place up falls back as well', () async {
      final google = _Google(() => _status('REQUEST_DENIED'));
      final openMap = _OpenMap();
      final geocoder =
          FallbackGeocoder(primary: google.geocoder, fallback: openMap);
      final location = parseMapLocation('10 Downing Street, London');

      expect(await geocoder.lookUp(location), same(_openMapParis));
      expect(openMap.lookedUp, [location]);
    });
  });

  group('a Google key that works', () {
    test('what Google finds is used', () async {
      final google = _Google(
        () => _status(
          'OK',
          results: [
            {
              'formatted_address': '10 Downing St, London SW1A 2AA, UK',
              'geometry': {
                'location': {'lat': 51.5034, 'lng': -0.1276},
              },
              'place_id': 'downing',
            },
          ],
        ),
      );
      final openMap = _OpenMap();
      final geocoder =
          FallbackGeocoder(primary: google.geocoder, fallback: openMap);

      final found = await geocoder.search('10 Downing Street');

      expect(found.single.name, '10 Downing St');
      expect(found.single.point.latitude, 51.5034);
      expect(found.single.placeId, 'downing');
      final address = google.asked.single.queryParameters['address'];
      expect(address, '10 Downing Street');
      expect(openMap.searched, isEmpty);
    });

    test(
        'what Google cannot find is asked of OpenStreetMap, without giving '
        'up on Google', () async {
      final google = _Google(() => _status('ZERO_RESULTS'));
      final openMap = _OpenMap();
      final geocoder =
          FallbackGeocoder(primary: google.geocoder, fallback: openMap);

      expect(await geocoder.search('Atlantis'), const [_openMapParis]);
      expect(google.geocoder.isRefused, isFalse);

      await geocoder.search('Lemuria');
      expect(google.asked, hasLength(2));
      expect(openMap.searched, ['Atlantis', 'Lemuria']);
    });
  });

  test('a keyed geocoder falls back to the one shared keyless geocoder', () {
    final keyed = resolveGeocoder(apiKey: 'shared-key');

    expect(keyed, isA<FallbackGeocoder>());
    expect((keyed as FallbackGeocoder).fallback, same(resolveGeocoder()));
    expect(resolveGeocoder(apiKey: 'shared-key'), same(keyed));
  });
}
