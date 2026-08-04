import 'dart:ui';

import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _london = LatLng(51.5074, -0.1278);
const _newYork = LatLng(40.7128, -74.0060);

MapCamera _camera({LatLng center = _london, double zoom = 10}) => MapCamera(
      center: center,
      zoom: zoom,
      size: const Size(800, 600),
    );

AppMapPin _pin(String id, LatLng point) =>
    AppMapPin(id: id, point: point, title: id);

void main() {
  group('reading a place off the world', () {
    test('a point projects and comes back the same', () {
      for (final point in const [
        _london,
        _newYork,
        LatLng(-33.8688, 151.2093),
      ]) {
        final back = unprojectWorld(projectLatLng(point));
        expect(back.latitude, closeTo(point.latitude, 1e-9));
        expect(back.longitude, closeTo(point.longitude, 1e-9));
      }
    });

    test('the equator sits halfway down and Greenwich halfway across', () {
      final origin = projectLatLng(const LatLng(0, 0));
      expect(origin.dx, closeTo(0.5, 1e-9));
      expect(origin.dy, closeTo(0.5, 1e-9));
    });

    test('the poles are pulled back to what the projection can draw', () {
      final north = LatLng.clamped(96, 0);
      expect(north.latitude, closeTo(mercatorLimit, 1e-9));
    });

    test('longitude wraps rather than stopping', () {
      expect(LatLng.clamped(0, 190).longitude, closeTo(-170, 1e-9));
      expect(LatLng.clamped(0, -190).longitude, closeTo(170, 1e-9));
    });

    test('two known cities are about the right distance apart', () {
      final metres = distanceBetween(_london, _newYork);
      expect(metres / 1000, closeTo(5570, 40));
    });
  });

  group('what the map is looking at', () {
    test('the centre lands in the middle of the view', () {
      final camera = _camera();
      final at = camera.toScreen(_london);
      expect(at.dx, closeTo(400, 1e-6));
      expect(at.dy, closeTo(300, 1e-6));
    });

    test('a screen point and a place agree with each other', () {
      final camera = _camera();
      const somewhere = Offset(613, 122);
      final back = camera.toScreen(camera.toLatLng(somewhere));
      expect(back.dx, closeTo(somewhere.dx, 1e-6));
      expect(back.dy, closeTo(somewhere.dy, 1e-6));
    });

    test('dragging moves the map with the hand', () {
      final camera = _camera();
      final moved = camera.panned(const Offset(100, 0));
      // Dragging right shows what was to the west, so the centre goes west.
      expect(moved.center.longitude, lessThan(camera.center.longitude));
      final back = moved.panned(const Offset(-100, 0));
      expect(back.center.longitude, closeTo(camera.center.longitude, 1e-9));
    });

    test('zooming holds whatever is under the pointer still', () {
      final camera = _camera();
      const pointer = Offset(700, 140);
      final anchor = camera.toLatLng(pointer);
      final zoomed = camera.zoomedTo(camera.zoom + 2, focus: pointer);
      final after = zoomed.toScreen(anchor);
      expect(after.dx, closeTo(pointer.dx, 0.5));
      expect(after.dy, closeTo(pointer.dy, 0.5));
    });

    test('zooming without a focus keeps the centre', () {
      final camera = _camera();
      final zoomed = camera.zoomedTo(14);
      expect(zoomed.center, camera.center);
      expect(zoomed.zoom, 14);
    });

    test('zoom cannot run past its limits', () {
      expect(_camera().zoomedTo(99).zoom, maxMapZoom);
      expect(_camera().zoomedTo(-99).zoom, minMapZoom);
    });

    test('fitting a box shows every corner of it', () {
      final bounds = LatLngBounds.around(const [_london, _newYork]);
      final fitted = _camera().fittedTo(bounds);
      final view = fitted.bounds;
      expect(view.west, lessThanOrEqualTo(bounds.west + 1e-6));
      expect(view.east, greaterThanOrEqualTo(bounds.east - 1e-6));
      expect(view.south, lessThanOrEqualTo(bounds.south + 1e-6));
      expect(view.north, greaterThanOrEqualTo(bounds.north - 1e-6));
    });

    test('fitting a single place gives a readable street zoom', () {
      final fitted = _camera().fittedTo(LatLngBounds.around(const [_london]));
      expect(fitted.zoom, 15);
      expect(fitted.center.latitude, closeTo(_london.latitude, 1e-6));
    });
  });

  group('pins that would sit on top of each other', () {
    test('near pins become one bubble and far ones stay apart', () {
      final camera = _camera(zoom: 2);
      final clusters = clusterPins(
        [
          _pin('a', _london),
          _pin('b', const LatLng(51.5080, -0.1270)),
          _pin('c', const LatLng(51.5090, -0.1260)),
          _pin('far', _newYork),
        ],
        camera,
      );

      expect(clusters.length, 2);
      final biggest = clusters.last;
      expect(biggest.count, 3);
      expect(biggest.isSingle, isFalse);
    });

    test('zooming in breaks a group apart', () {
      final pins = [
        _pin('a', _london),
        _pin('b', const LatLng(51.5300, -0.1000)),
      ];
      expect(clusterPins(pins, _camera(zoom: 5)).length, 1);
      expect(clusterPins(pins, _camera(zoom: 14)).length, 2);
    });

    test('pins beyond the edge of the view are not drawn at all', () {
      final clusters = clusterPins(
        [_pin('a', _london), _pin('away', _newYork)],
        _camera(zoom: 12),
      );
      expect(clusters.length, 1);
      expect(clusters.single.first.id, 'a');
    });

    test('clustering can be turned off and every pin stands alone', () {
      final clusters = clusterPins(
        [
          _pin('a', _london),
          _pin('b', const LatLng(51.5075, -0.1279)),
        ],
        _camera(zoom: 4),
        enabled: false,
      );
      expect(clusters.length, 2);
    });

    test('a cluster knows the box it covers', () {
      final clusters = clusterPins(
        [
          _pin('a', const LatLng(51.50, -0.13)),
          _pin('b', const LatLng(51.51, -0.12)),
        ],
        _camera(zoom: 4),
      );
      final bounds = clusters.single.bounds;
      expect(bounds.south, closeTo(51.50, 1e-9));
      expect(bounds.north, closeTo(51.51, 1e-9));
    });

    test('the pin under the pointer is the one found', () {
      final camera = _camera(zoom: 12);
      final clusters = clusterPins([_pin('a', _london)], camera);
      final at = camera.toScreen(_london);
      expect(clusterAt(clusters, at)?.first.id, 'a');
      expect(clusterAt(clusters, at + const Offset(300, 300)), isNull);
    });
  });

  group('reading a location cell', () {
    test('a plain pair of coordinates', () {
      final location = parseMapLocation('51.5074, -0.1278');
      expect(location.point?.latitude, closeTo(51.5074, 1e-9));
      expect(location.point?.longitude, closeTo(-0.1278, 1e-9));
      expect(location.needsLookUp, isFalse);
    });

    test('coordinates written with compass points', () {
      final location = parseMapLocation('51.5074 N, 0.1278 W');
      expect(location.point?.latitude, closeTo(51.5074, 1e-9));
      expect(location.point?.longitude, closeTo(-0.1278, 1e-9));
    });

    test('a Google Maps link uses the pin, not the middle of the view', () {
      final location = parseMapLocation(
        'https://www.google.com/maps/place/Googleplex/@37.4220,-122.0841,17z/'
        'data=!3m1!4b1!4m5!3m4!1s0x0:0x0!3d37.4219983!4d-122.0839934',
      );
      expect(location.point?.latitude, closeTo(37.4219983, 1e-9));
      expect(location.point?.longitude, closeTo(-122.0839934, 1e-9));
      expect(location.label, 'Googleplex');
    });

    test('a link with only a centre falls back to it', () {
      final location = parseMapLocation(
        'https://www.google.com/maps/@37.4219999,-122.0840575,17z',
      );
      expect(location.point?.latitude, closeTo(37.4219999, 1e-9));
    });

    test('a query link is read', () {
      final location =
          parseMapLocation('https://maps.google.com/?q=48.8584,2.2945');
      expect(location.point?.latitude, closeTo(48.8584, 1e-9));
    });

    test('a place id is kept for looking up', () {
      final location = parseMapLocation(
        'https://www.google.com/maps/place/?q=place_id:ChIJN1t_tDeuEmsRUsoyG83frY4',
      );
      expect(location.placeId, 'ChIJN1t_tDeuEmsRUsoyG83frY4');
      expect(location.needsLookUp, isTrue);
    });

    test('a bare place id is recognised on its own', () {
      final location = parseMapLocation('ChIJN1t_tDeuEmsRUsoyG83frY4');
      expect(location.placeId, 'ChIJN1t_tDeuEmsRUsoyG83frY4');
    });

    test('an address is left to be looked up', () {
      final location = parseMapLocation('10 Downing Street, London');
      expect(location.point, isNull);
      expect(location.query, '10 Downing Street, London');
      expect(location.needsLookUp, isTrue);
    });

    test('an empty cell is nothing at all', () {
      expect(parseMapLocation('   ').isEmpty, isTrue);
      expect(parseMapLocation('   ').needsLookUp, isFalse);
    });

    test('nonsense that looks like numbers is not taken for a place', () {
      expect(parseMapLocation('999, 999').point, isNull);
    });
  });

  group('where the pictures come from', () {
    test('a tile east of the grid wraps round the world', () {
      expect(const MapTile(-1, 3, 2).wrapped.x, 3);
      expect(const MapTile(4, 3, 2).wrapped.x, 0);
    });

    test('a tile above the north pole is not on the earth', () {
      expect(const MapTile(0, -1, 2).isOnEarth, isFalse);
      expect(const MapTile(0, 3, 2).isOnEarth, isTrue);
    });

    test('without a key the map still has somewhere to get tiles', () {
      final provider = resolveMapProvider(
        preferred: MapProviderKind.google,
        style: MapStyleName.light,
      );
      expect(provider.kind, isNot(MapProviderKind.google));
      expect(
        provider.tileUri(const MapTile(1, 2, 3), MapStyleName.light),
        isNotNull,
      );
    });

    test('with a key Google is used', () {
      final provider = resolveMapProvider(
        preferred: MapProviderKind.google,
        style: MapStyleName.light,
        apiKey: 'test-key',
      );
      expect(provider.kind, MapProviderKind.google);
      // Nothing is drawn until a session has been opened.
      expect(
        provider.tileUri(const MapTile(1, 2, 3), MapStyleName.light),
        isNull,
      );
    });

    test('every keyless provider names who to credit', () {
      for (final provider in const [
        OpenStreetMapTileProvider(),
        CartoTileProvider(),
      ]) {
        expect(provider.attribution, isNotEmpty);
        expect(provider.headers['User-Agent'], isNotNull);
      }
    });

    test('the dark and light basemaps are different pictures', () {
      const provider = CartoTileProvider();
      const tile = MapTile(1, 2, 3);
      expect(
        provider.tileUri(tile, MapStyleName.dark).toString(),
        isNot(provider.tileUri(tile, MapStyleName.light).toString()),
      );
    });
  });
}
