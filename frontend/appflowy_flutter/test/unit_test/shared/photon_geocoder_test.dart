import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_location.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/photon_geocoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Synthetic fixtures only: no test contacts a geocoding service.
const _privateText = 'synthetic-private-place-and-token';

Map<String, Object?> _feature({
  Object? longitude = 13.3888599,
  Object? latitude = 52.5170365,
  Object? properties = const {
    'name': 'Berlin',
    'state': 'Berlin',
    'country': 'Germany',
    'osm_type': 'N',
    'osm_id': 240109189,
  },
}) =>
    {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      },
      'properties': properties,
    };

String _body(List<Object?> features) => jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });

http.Response _response(List<Object?> features) => http.Response.bytes(
      utf8.encode(_body(features)),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Matcher _safeFailure(String message) => isA<FormatException>()
    .having((error) => error.message, 'message', contains(message))
    .having((error) => error.source, 'source', isNull)
    .having((error) => error.offset, 'offset', isNull)
    .having(
      (error) => error.toString(),
      'privacy-safe message',
      isNot(contains(_privateText)),
    );

PhotonGeocoder _geocoder(
  http.Client client, {
  Uri? endpoint,
  _Clock? clock,
  Duration requestTimeout = PhotonGeocoder.defaultTimeout,
}) {
  final time = clock ?? _Clock();
  final geocoder = PhotonGeocoder(
    client: client,
    endpoint: endpoint,
    requestTimeout: requestTimeout,
    now: time.now,
    delay: time.delay,
  );
  addTearDown(client.close);
  addTearDown(geocoder.dispose);
  return geocoder;
}

void main() {
  group('Photon request contract', () {
    test('uses HTTPS and sends only the trimmed place query, limit, and lang',
        () async {
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'photon.komoot.io');
          expect(request.url.path, '/api/');
          expect(request.url.userInfo, isEmpty);
          expect(request.url.hasFragment, isFalse);
          expect(request.url.queryParameters, {
            'q': 'Montréal & Québec? #city',
            'limit': '6',
            'lang': 'en',
          });
          expect(request.body, isEmpty);
          expect(request.headers['authorization'], isNull);
          expect(request.headers['cookie'], isNull);
          expect(request.headers['user-agent'], contains('AppFlowy'));
          expect(request.followRedirects, isFalse);
          return _response([_feature()]);
        }),
      );

      expect(
        await geocoder.search('  Montréal & Québec? #city  '),
        hasLength(1),
      );
      expect(calls, 1);
    });

    test('supports a custom HTTPS endpoint without changing query parameters',
        () async {
      final geocoder = _geocoder(
        MockClient((request) async {
          expect(request.url.host, 'photon.example.test');
          expect(request.url.path, '/custom/api/');
          expect(request.url.queryParameters, {
            'q': 'Oslo',
            'limit': '2',
            'lang': 'en',
          });
          return _response([]);
        }),
        endpoint: Uri.https('photon.example.test', '/custom/api/'),
      );
      expect(await geocoder.search('Oslo', limit: 2), isEmpty);
    });

    test('rejects insecure or decorated endpoints without exposing their value',
        () {
      for (final endpoint in [
        Uri.parse('http://photon.example.test/api/'),
        Uri.parse('https:///api/'),
        Uri.parse('https://user:$_privateText@photon.example.test/api/'),
        Uri.parse('https://photon.example.test/api/?key=$_privateText'),
        Uri.parse('https://photon.example.test/api/#$_privateText'),
      ]) {
        expect(
          () => PhotonGeocoder(endpoint: endpoint),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'privacy-safe message',
              isNot(contains(_privateText)),
            ),
          ),
        );
      }
    });

    test('skips empty, one-character, and nonpositive-limit requests',
        () async {
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((_) async {
          calls++;
          return _response([]);
        }),
      );
      expect(await geocoder.search('  '), isEmpty);
      expect(await geocoder.search(' A '), isEmpty);
      expect(await geocoder.search('Berlin', limit: 0), isEmpty);
      expect(await geocoder.search('Berlin', limit: -1), isEmpty);
      expect(calls, 0);
      expect(await geocoder.search('Ås'), isEmpty);
      expect(calls, 1);
    });

    test('bounds query length and the effective requested and returned limit',
        () async {
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((request) async {
          calls++;
          expect(
            request.url.queryParameters['limit'],
            '${PhotonGeocoder.maxResults}',
          );
          return _response(
            List.generate(PhotonGeocoder.maxResults + 5, (_) => _feature()),
          );
        }),
      );
      await expectLater(
        geocoder.search('a' * (PhotonGeocoder.maxQueryLength + 1)),
        throwsA(_safeFailure('too long')),
      );
      expect(calls, 0);
      final found = await geocoder.search('Berlin', limit: 1000);
      expect(found, hasLength(PhotonGeocoder.maxResults));
      await geocoder.search('Berlin', limit: PhotonGeocoder.maxResults);
      expect(calls, 1);
    });
  });

  group('Photon GeoJSON', () {
    test('preserves coordinate precision and builds a deduplicated address',
        () async {
      const longitude = 13.239514674078611;
      const latitude = 52.51467945123456;
      final geocoder = _geocoder(
        MockClient(
          (_) async => _response([
            _feature(
              longitude: longitude,
              latitude: latitude,
              properties: {
                'name': '  Hôpital de São José  ',
                'street': 'Rue de l’Église',
                'housenumber': '12A',
                'postcode': '00123',
                'district': 'Vieille Ville',
                'city': 'Montréal',
                'county': 'montréal',
                'state': 'Québec',
                'country': 'Canada',
                'osm_type': 'W',
                'osm_id': 38862723,
              },
            ),
          ]),
        ),
      );
      final place = (await geocoder.search('Synthetic hospital')).single;
      expect(place.point.longitude, longitude);
      expect(place.point.latitude, latitude);
      expect(place.name, 'Hôpital de São José');
      expect(
        place.address,
        'Hôpital de São José, 12A Rue de l’Église, Vieille Ville, '
        'Montréal, Québec, 00123, Canada',
      );
      expect(place.placeId, 'osm:W:38862723');
    });

    test('handles missing and mistyped optional properties and Unicode names',
        () async {
      final geocoder = _geocoder(
        MockClient(
          (_) async => _response([
            _feature(properties: {'city': '東京', 'country': '日本'}),
            _feature(properties: {}),
            _feature(
              properties: {
                'name': 7,
                'street': false,
                'city': 'Zürich',
                'osm_type': 'R',
                'osm_id': '1682248',
              },
            ),
            _feature(
              properties: {
                'name': 'Unter den Linden',
                'street': 'Unter den Linden',
                'housenumber': '3',
                'city': 'Berlin',
                'state': ' berlin ',
                'osm_type': 'unknown',
                'osm_id': 1,
              },
            ),
          ]),
        ),
      );
      final places = await geocoder.search('Synthetic places');
      expect(places[0].name, '東京');
      expect(places[0].address, '東京, 日本');
      expect(places[0].placeId, isNull);
      expect(places[1].name, '52.5170365, 13.3888599');
      expect(places[1].point, const LatLng(52.5170365, 13.3888599));
      expect(places[2].name, 'Zürich');
      expect(places[2].placeId, 'osm:R:1682248');
      expect(places[3].address, '3 Unter den Linden, Berlin');
      expect(places[3].placeId, isNull);
    });

    test('skips malformed records rather than manufacturing points', () async {
      final features = <Object?>[
        null,
        1,
        'not a feature',
        [],
        {},
        _feature()..remove('geometry'),
        _feature()..['type'] = 'Polygon',
        _feature(properties: null),
        _feature(properties: 'not an object'),
        _feature(longitude: null),
        _feature(latitude: null),
        _feature(longitude: '13.4'),
        _feature(latitude: '52.5'),
        _feature(longitude: 180.0001),
        _feature(longitude: -180.0001),
        _feature(latitude: 90.0001),
        _feature(latitude: -90.0001),
      ];
      for (final coordinates in <Object?>[
        null,
        '13, 52',
        [],
        [13],
        [13, 52, 'not an altitude'],
        [13, 52, 10, 20],
      ]) {
        features.add(
          _feature()
            ..['geometry'] = {'type': 'Point', 'coordinates': coordinates},
        );
      }
      features.add(
        _feature()
          ..['geometry'] = {
            'type': 'LineString',
            'coordinates': [13, 52],
          },
      );
      features.add(_feature(longitude: 180, latitude: 90));
      features.add(_feature(longitude: -180, latitude: -90));
      features.add(
        _feature()
          ..['geometry'] = {
            'type': 'Point',
            'coordinates': [13, 52, 100],
          },
      );
      final geocoder = _geocoder(MockClient((_) async => _response(features)));
      final results = await geocoder.search('Synthetic malformed records');
      expect(results.map((result) => result.point), const [
        LatLng(90, 180),
        LatLng(-90, -180),
        LatLng(52, 13),
      ]);
    });

    test('skips numeric overflow producing nonfinite coordinates', () async {
      final body = _body([
        _feature(longitude: 'positive-overflow'),
        _feature(latitude: 'negative-overflow'),
        _feature(),
      ])
          .replaceAll('"positive-overflow"', '1e999')
          .replaceAll('"negative-overflow"', '-1e999');
      final geocoder = _geocoder(
        MockClient((_) async => http.Response(body, 200)),
      );
      final results = await geocoder.search('Synthetic numeric overflow');
      expect(results, hasLength(1));
      expect(results.single.point, const LatLng(52.5170365, 13.3888599));
    });

    test('honors the result limit after invalid records have been skipped',
        () async {
      final geocoder = _geocoder(
        MockClient(
          (_) async => _response([
            _feature(latitude: 999),
            _feature(properties: {'name': 'First'}),
            _feature(properties: {'name': 'Second'}),
            _feature(properties: {'name': 'Third'}),
          ]),
        ),
      );
      final results = await geocoder.search('Synthetic ranking', limit: 2);
      expect(results.map((result) => result.name), ['First', 'Second']);
    });

    test('accepts the documented envelope without an optional collection type',
        () async {
      final geocoder = _geocoder(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'features': [_feature()],
            }),
            200,
          ),
        ),
      );
      expect(await geocoder.search('Berlin'), hasLength(1));
    });

    final malformedBodies = [
      '',
      'not-json $_privateText',
      '<html>$_privateText</html>',
      '[]',
      'null',
      '{}',
      '{"error":"$_privateText"}',
      '{"features":null}',
      '{"features":{}}',
      '{"type":"Point","features":[]}',
    ];
    for (var index = 0; index < malformedBodies.length; index++) {
      test('rejects malformed response $index with a source-free error',
          () async {
        final geocoder = _geocoder(
          MockClient((_) async => http.Response(malformedBodies[index], 200)),
        );
        await expectLater(
          geocoder.search(_privateText),
          throwsA(_safeFailure('invalid place-search response')),
        );
      });
    }

    test('rejects invalid UTF-8 without exposing parser source', () async {
      final geocoder = _geocoder(
        MockClient((_) async => http.Response.bytes([0xff, 0xfe], 200)),
      );
      await expectLater(
        geocoder.search(_privateText),
        throwsA(_safeFailure('invalid place-search response')),
      );
    });
  });

  group('Photon failures and bounded responses', () {
    for (final status in [302, 400, 403, 429, 500, 503]) {
      test('surfaces HTTP $status instead of returning a fake empty result',
          () async {
        var calls = 0;
        final geocoder = _geocoder(
          MockClient((request) async {
            calls++;
            expect(request.followRedirects, isFalse);
            return http.Response(
              _privateText,
              status,
              headers: {'location': 'http://example.test/$_privateText'},
            );
          }),
        );
        await expectLater(
          geocoder.search(_privateText),
          throwsA(_safeFailure(status == 429 ? 'rate-limited' : 'unavailable')),
        );
        expect(calls, 1); // No retry and no Nominatim fallback.
      });
    }

    test('sanitizes transport exceptions that include the query URI', () async {
      final geocoder = _geocoder(
        MockClient((request) async {
          throw http.ClientException(_privateText, request.url);
        }),
      );
      await expectLater(
        geocoder.search(_privateText),
        throwsA(_safeFailure('unavailable')),
      );
    });

    test('sanitizes transport FormatExceptions rather than trusting their text',
        () async {
      final geocoder = _geocoder(
        MockClient((_) async {
          throw const FormatException(_privateText, _privateText);
        }),
      );
      await expectLater(
        geocoder.search(_privateText),
        throwsA(_safeFailure('unavailable')),
      );
    });

    test('rejects a declared oversized body without waiting to read it',
        () async {
      var cancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(controller.close);
      final geocoder = _geocoder(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            controller.stream,
            200,
            contentLength: PhotonGeocoder.maxResponseBytes + 1,
          ),
        ),
      );
      await expectLater(
        geocoder.search('Synthetic oversized response'),
        throwsA(_safeFailure('too large')),
      );
      expect(cancelled, isTrue);
      expect(controller.hasListener, isFalse);
    });

    test('HTTP failures cancel unread response streams', () async {
      var cancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(controller.close);
      final geocoder = _geocoder(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            controller.stream,
            503,
          ),
        ),
      );
      await expectLater(
        geocoder.search(_privateText),
        throwsA(_safeFailure('unavailable')),
      );
      expect(cancelled, isTrue);
      expect(controller.hasListener, isFalse);
    });

    test('enforces the byte bound even when content length is understated',
        () async {
      final geocoder = _geocoder(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            Stream.fromIterable([
              Uint8List(PhotonGeocoder.maxResponseBytes),
              Uint8List(1),
            ]),
            200,
            contentLength: 1,
          ),
        ),
      );
      await expectLater(
        geocoder.search('Synthetic oversized stream'),
        throwsA(_safeFailure('too large')),
      );
    });

    test('surfaces streaming transport errors safely', () async {
      final geocoder = _geocoder(
        MockClient.streaming(
          (request, _) async => http.StreamedResponse(
            Stream.error(http.ClientException(_privateText, request.url)),
            200,
          ),
        ),
      );
      await expectLater(
        geocoder.search(_privateText),
        throwsA(_safeFailure('unavailable')),
      );
    });

    test('header timeout does not cache failure or block the next call',
        () async {
      final lateResponse = Completer<http.Response>();
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((_) async {
          calls++;
          if (calls == 1) return lateResponse.future;
          return _response([_feature()]);
        }),
        // A zero-duration deadline exercises timeout without a real sleep.
        requestTimeout: Duration.zero,
      );
      await expectLater(
        geocoder.search(_privateText),
        throwsA(_safeFailure('timed out')),
      );
      final recovered = await geocoder.search(_privateText);
      expect(recovered.single.name, 'Berlin');
      expect(calls, 2);
      lateResponse.complete(
        _response(
          [
            _feature(properties: {'name': 'Late'}),
          ],
        ),
      );
      final cached = await geocoder.search(_privateText);
      expect(cached.single.name, 'Berlin');
      expect(calls, 2);
    });

    test('discards a late response stream after the header deadline', () async {
      final lateResponse = Completer<http.StreamedResponse>();
      final cancelled = Completer<void>();
      final controller = StreamController<List<int>>(
        onCancel: cancelled.complete,
      );
      addTearDown(controller.close);
      final geocoder = _geocoder(
        MockClient.streaming((_, __) => lateResponse.future),
        requestTimeout: Duration.zero,
      );
      await expectLater(
        geocoder.search(_privateText),
        throwsA(_safeFailure('timed out')),
      );
      lateResponse.complete(http.StreamedResponse(controller.stream, 200));
      await cancelled.future;
      expect(controller.hasListener, isFalse);
    });

    test('the deadline also cancels a stalled response body', () async {
      var cancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(controller.close);
      final geocoder = _geocoder(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            controller.stream,
            200,
          ),
        ),
        requestTimeout: Duration.zero,
      );
      await expectLater(
        geocoder.search(_privateText),
        throwsA(_safeFailure('timed out')),
      );
      expect(cancelled, isTrue);
      expect(controller.hasListener, isFalse);
    });
  });

  group('Photon cache and scheduling', () {
    test('shares identical in-flight searches and caches immutable results',
        () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((_) {
          calls++;
          started.complete();
          return response.future;
        }),
      );
      final first = geocoder.search(' Berlin ');
      final second = geocoder.search('Berlin');
      expect(identical(first, second), isTrue);
      await started.future;
      expect(calls, 1);
      response.complete(_response([_feature()]));
      final results = await Future.wait([first, second]);
      expect(identical(results[0], results[1]), isTrue);
      expect(() => results[0].clear(), throwsUnsupportedError);
      expect(identical(await geocoder.search('Berlin'), results[0]), isTrue);
      expect(calls, 1);
    });

    test('keeps cache and in-flight entries distinct by effective limit',
        () async {
      final limits = <String?>[];
      final geocoder = _geocoder(
        MockClient((request) async {
          limits.add(request.url.queryParameters['limit']);
          return _response([_feature(), _feature()]);
        }),
      );
      final one = geocoder.search('Berlin', limit: 1);
      final six = geocoder.search('Berlin');
      expect(identical(one, six), isFalse);
      expect(await one, hasLength(1));
      expect(await six, hasLength(2));
      await geocoder.search('Berlin', limit: 1);
      await geocoder.search('Berlin');
      expect(limits, ['1', '6']);
    });

    test('caches genuine empty results', () async {
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((_) async {
          calls++;
          return _response([]);
        }),
      );
      expect(await geocoder.search('Synthetic missing place'), isEmpty);
      expect(await geocoder.search('Synthetic missing place'), isEmpty);
      expect(calls, 1);
    });

    test('evicts the least recently used query at the 100-entry bound',
        () async {
      expect(PhotonGeocoder.cacheCapacity, 100);
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((_) async {
          calls++;
          return _response([_feature()]);
        }),
      );
      for (var index = 0; index < PhotonGeocoder.cacheCapacity; index++) {
        await geocoder.search('Synthetic place $index');
      }
      expect(calls, PhotonGeocoder.cacheCapacity);
      await geocoder.search('Synthetic place 0');
      await geocoder.search('Synthetic place ${PhotonGeocoder.cacheCapacity}');
      await geocoder.search('Synthetic place 0');
      expect(calls, PhotonGeocoder.cacheCapacity + 1);
      await geocoder.search('Synthetic place 1');
      expect(calls, PhotonGeocoder.cacheCapacity + 2);
    });

    test('paces request starts, accounting for time spent in the previous call',
        () async {
      final clock = _Clock();
      final starts = <DateTime>[];
      final geocoder = _geocoder(
        MockClient((_) async {
          starts.add(clock.now());
          if (starts.length == 1) {
            clock.advance(const Duration(milliseconds: 200));
          }
          return _response([]);
        }),
        clock: clock,
      );
      await Future.wait([
        geocoder.search('First city'),
        geocoder.search('Second city'),
        geocoder.search('Third city'),
      ]);
      expect(starts[1].difference(starts[0]), PhotonGeocoder.minimumInterval);
      expect(starts[2].difference(starts[1]), PhotonGeocoder.minimumInterval);
      expect(clock.delays, [
        PhotonGeocoder.minimumInterval - const Duration(milliseconds: 200),
        PhotonGeocoder.minimumInterval,
      ]);
      await geocoder.search('Second city');
      expect(clock.delays, hasLength(2));
    });

    test('a backwards clock correction cannot create an unbounded wait',
        () async {
      final clock = _Clock();
      final geocoder = _geocoder(
        MockClient((_) async => _response([])),
        clock: clock,
      );
      await geocoder.search('First city');
      clock.advance(const Duration(hours: -1));
      await geocoder.search('Second city');
      expect(clock.delays, [PhotonGeocoder.minimumInterval]);
    });

    test('bounds distinct pending searches while still allowing deduplication',
        () async {
      final response = Completer<http.Response>();
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((_) async {
          calls++;
          if (calls == 1) return response.future;
          return _response([]);
        }),
      );
      final pending = [
        for (var index = 0; index < PhotonGeocoder.maxPendingSearches; index++)
          geocoder.search('Synthetic pending $index'),
      ];
      expect(
        identical(geocoder.search('Synthetic pending 0'), pending.first),
        isTrue,
      );
      await expectLater(
        geocoder.search('Synthetic overflow'),
        throwsA(_safeFailure('busy')),
      );
      response.complete(_response([]));
      await Future.wait(pending);
      expect(calls, PhotonGeocoder.maxPendingSearches);
      await geocoder.search('Synthetic overflow');
      expect(calls, PhotonGeocoder.maxPendingSearches + 1);
    });

    test(
        'an HTTP failure does not poison queued work or cache the failed query',
        () async {
      final response = Completer<http.Response>();
      final queries = <String?>[];
      final geocoder = _geocoder(
        MockClient((request) async {
          queries.add(request.url.queryParameters['q']);
          if (queries.length == 1) return response.future;
          return _response([_feature()]);
        }),
      );
      final failure = expectLater(
        geocoder.search('First city'),
        throwsA(_safeFailure('unavailable')),
      );
      final queued = geocoder.search('Second city');
      response.complete(http.Response(_privateText, 503));
      await failure;
      expect(await queued, hasLength(1));
      expect(await geocoder.search('First city'), hasLength(1));
      expect(queries, ['First city', 'Second city', 'First city']);
    });

    test('a scheduling failure cannot poison the next search', () async {
      final clock = _Clock();
      var waits = 0;
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _response([]);
      });
      final geocoder = PhotonGeocoder(
        client: client,
        now: clock.now,
        delay: (duration) async {
          waits++;
          if (waits == 1) throw StateError(_privateText);
          await clock.delay(duration);
        },
      );
      addTearDown(client.close);
      addTearDown(geocoder.dispose);
      await geocoder.search('First city');
      await expectLater(
        geocoder.search('Second city'),
        throwsA(_safeFailure('unavailable')),
      );
      expect(await geocoder.search('Third city'), isEmpty);
      expect(calls, 2);
    });
  });

  group('Photon lookup and lifecycle', () {
    test('looks up the first search result, or null for a genuine no-match',
        () async {
      final geocoder = _geocoder(
        MockClient((request) async {
          expect(request.url.queryParameters['limit'], '1');
          return request.url.queryParameters['q'] == 'Missing'
              ? _response([])
              : _response([
                  _feature(),
                  _feature(properties: {'name': 'Second'}),
                ]);
        }),
      );
      final result = await geocoder.lookUp(parseMapLocation('Berlin'));
      expect(result?.name, 'Berlin');
      expect(await geocoder.lookUp(parseMapLocation('Missing')), isNull);
      expect(await geocoder.lookUp(MapLocation.empty), isNull);
    });

    test('uses existing and typed coordinates locally without rounding',
        () async {
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((_) async {
          calls++;
          return _response([]);
        }),
      );
      const point = LatLng(51.1234567890123, -0.1234567890123);
      final known = await geocoder.lookUp(
        const MapLocation(
          point: point,
          label: 'Known place',
          placeId: 'kept-id',
        ),
      );
      expect(known?.point, point);
      expect(known?.name, 'Known place');
      expect(known?.address, 'Known place');
      expect(known?.placeId, 'kept-id');
      final typed = await geocoder.lookUp(
        const MapLocation(query: '51.1234567890123, -0.1234567890123'),
      );
      expect(typed?.point, point);
      expect(typed?.name, '51.1234567890123, -0.1234567890123');
      expect(calls, 0);
      for (final invalid in const [
        LatLng(91, 0),
        LatLng(0, 181),
        LatLng(double.nan, 0),
        LatLng(0, double.infinity),
      ]) {
        await expectLater(
          geocoder.lookUp(MapLocation(point: invalid)),
          throwsA(_safeFailure('coordinates')),
        );
      }
      expect(calls, 0);
    });

    test('malformed map links cannot expose parser source or trigger a request',
        () async {
      var calls = 0;
      final geocoder = _geocoder(
        MockClient((_) async {
          calls++;
          return _response([]);
        }),
      );
      await expectLater(
        geocoder.lookUp(
          const MapLocation(
            query: 'https://example.test/place/$_privateText%25',
          ),
        ),
        throwsA(_safeFailure('could not be read')),
      );
      expect(calls, 0);
    });

    test('dispose rejects queued work without closing an injected client',
        () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      var calls = 0;
      final client = _TrackedClient((_) {
        calls++;
        started.complete();
        return response.future;
      });
      final geocoder = _geocoder(client);
      final first = expectLater(
        geocoder.search('First city'),
        throwsA(_safeFailure('closed')),
      );
      final queued = expectLater(
        geocoder.search('Second city'),
        throwsA(_safeFailure('closed')),
      );
      await started.future;
      geocoder.dispose();
      geocoder.dispose();
      expect(client.closed, isFalse);
      response.complete(_response([_feature()]));
      await first;
      await queued;
      await expectLater(
        geocoder.search('First city'),
        throwsA(_safeFailure('closed')),
      );
      await expectLater(
        geocoder.lookUp(const MapLocation(point: LatLng(0, 0))),
        throwsA(_safeFailure('closed')),
      );
      expect(calls, 1);
      expect(client.closed, isFalse);
    });

    test('closes owned clients after both success and timeout, then recovers',
        () async {
      final clock = _Clock();
      final lateResponse = Completer<http.Response>();
      final clients = <_TrackedClient>[];
      await http.runWithClient(
        () async {
          final geocoder = PhotonGeocoder(
            now: clock.now,
            delay: clock.delay,
            requestTimeout: Duration.zero,
          );
          addTearDown(geocoder.dispose);
          await expectLater(
            geocoder.search('First city'),
            throwsA(_safeFailure('timed out')),
          );
          expect(clients.single.closed, isTrue);
          expect(await geocoder.search('Second city'), hasLength(1));
          expect(clients, hasLength(2));
          expect(clients.every((client) => client.closed), isTrue);
          lateResponse.complete(_response([]));
        },
        () {
          final first = clients.isEmpty;
          final client = _TrackedClient(
            (_) async {
              if (first) return lateResponse.future;
              return _response([_feature()]);
            },
          );
          clients.add(client);
          return client;
        },
      );
    });
  });

  group('AstrologyLocationService geocoder seam', () {
    test('maps Photon longitude/latitude to the correct coordinate timezone',
        () async {
      const latitude = 40.7128123456789;
      const longitude = -74.0060123456789;
      final service = AstrologyLocationService(
        geocoder: _geocoder(
          MockClient((request) async {
            expect(request.url.queryParameters['q'], 'New York');
            return _response([
              _feature(
                longitude: longitude,
                latitude: latitude,
                properties: {
                  'name': 'New York',
                  'city': 'New York',
                  'state': 'New York',
                  'country': 'United States',
                },
              ),
            ]);
          }),
        ),
      );
      final place = (await service.search('  New York  ')).single;
      expect(place.name, 'New York, United States');
      expect(place.latitude, latitude);
      expect(place.longitude, longitude);
      expect(place.timeZone, 'America/New_York');
      expect(place.isDeviceLocation, isFalse);
    });

    test('honors an explicit geocoder and preserves the two-character API',
        () async {
      final injected = _RecordingGeocoder(const [
        GeocodeResult(point: LatLng(51.5074, -0.1278), name: 'Injected place'),
      ]);
      final service = AstrologyLocationService(geocoder: injected);
      expect(await service.search('  '), isEmpty);
      expect(await service.search(' A '), isEmpty);
      expect(injected.queries, isEmpty);
      final place = (await service.search('  Ås  ')).single;
      expect(injected.queries, ['Ås']);
      expect(injected.limits, [6]);
      expect(place.name, 'Injected place');
      expect(place.latitude, 51.5074);
      expect(place.longitude, -0.1278);
      expect(place.timeZone, 'Europe/London');
    });

    test('surfaces provider failures through the unchanged search API',
        () async {
      final service = AstrologyLocationService(
        geocoder: _geocoder(
          MockClient((_) async => http.Response(_privateText, 429)),
        ),
      );
      await expectLater(
        service.search(_privateText),
        throwsA(_safeFailure('rate-limited')),
      );
    });

    test('default service instances share the Photon provider and query cache',
        () async {
      var calls = 0;
      final clients = <_TrackedClient>[];
      await http.runWithClient(
        () async {
          final first = AstrologyLocationService();
          final second = AstrologyLocationService();
          const query = 'Synthetic shared Photon default fixture';
          expect(await first.search(query), hasLength(1));
          expect(await second.search(query), hasLength(1));
          expect(
            await AstrologyLocationService.instance.search(query),
            hasLength(1),
          );
        },
        () {
          final client = _TrackedClient((request) async {
            calls++;
            expect(request.url.scheme, 'https');
            expect(request.url.host, 'photon.komoot.io');
            expect(request.url.path, '/api/');
            expect(request.url.queryParameters.keys, ['q', 'limit', 'lang']);
            return _response([_feature()]);
          });
          clients.add(client);
          return client;
        },
      );
      expect(calls, 1);
      expect(clients.single.closed, isTrue);
    });
  });
}

class _Clock {
  DateTime value = DateTime.utc(2026);
  final List<Duration> delays = [];

  DateTime now() => value;

  void advance(Duration duration) => value = value.add(duration);

  Future<void> delay(Duration duration) async {
    delays.add(duration);
    advance(duration);
  }
}

class _TrackedClient extends MockClient {
  _TrackedClient(super.fn);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _RecordingGeocoder implements MapGeocoder {
  _RecordingGeocoder(this.results);

  final List<GeocodeResult> results;
  final List<String> queries = [];
  final List<int> limits = [];

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) async {
    queries.add(query);
    limits.add(limit);
    return results;
  }

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) async =>
      throw StateError('The service must use its injected search method.');
}
