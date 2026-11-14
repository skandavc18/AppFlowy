import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/maps/app_location_popup.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/google/google_map_surface.dart';
import 'package:appflowy/shared/maps/google/google_maps_pages.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_tile_layer.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chart_appearance_test_support.dart';

const _key = 'demo-key';

const _pins = [
  AppMapPin(id: 'akshaya', point: LatLng(12.93293, 77.57145), title: 'Akshaya'),
  AppMapPin(id: 'lalbagh', point: LatLng(12.9507, 77.5848), title: 'Lalbagh'),
];

/// Stands in for the WebKitGTK view: remembers what it was told to run.
class _FakePage implements GoogleMapsPage {
  final _messages = StreamController<String>.broadcast();
  final scripts = <String>[];
  var disposed = false;

  void post(Map<String, Object?> message) => _messages.add(jsonEncode(message));

  Iterable<String> calls(String method) =>
      scripts.where((script) => script.contains('appflowySurface.$method('));

  /// What the page was last told to show, by `start` or `show`.
  Map<String, Object?> config(String method) {
    final script = calls(method).last;
    final start = script.indexOf('$method(') + method.length + 1;
    return jsonDecode(script.substring(start, script.lastIndexOf(');')))
        as Map<String, Object?>;
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> run(String script) async => scripts.add(script);

  @override
  Future<void> reload(Uri url) async {}

  // Hit, as the web view's texture is.
  @override
  Widget build(BuildContext context) => const ColoredBox(
        key: ValueKey('google-page'),
        color: Color(0x00000000),
        child: SizedBox.expand(),
      );

  @override
  Future<void> dispose() async => disposed = true;
}

final _opened = <_FakePage>[];

final _pages = GoogleMapsPages(
  address: () async => Uri.parse('http://127.0.0.1:1/token/surface.html'),
  open: (url) async {
    final page = _FakePage();
    _opened.add(page);
    return page;
  },
  isSupported: () async => true,
);

Widget _map({
  AppMapController? controller,
  ValueChanged<AppMapPin>? onPinTap,
  ValueChanged<LatLng>? onPointTap,
  ValueChanged<MapViewport>? onViewportChanged,
  void Function(Offset, LatLng)? onContextMenu,
}) =>
    Center(
      child: SizedBox(
        width: 640,
        height: 420,
        child: AppMapView(
          controller: controller,
          pins: _pins,
          initialCenter: const LatLng(12.95, 77.58),
          initialZoom: 12,
          autoFit: false,
          onPinTap: onPinTap,
          onPointTap: onPointTap,
          onViewportChanged: onViewportChanged,
          onContextMenu: onContextMenu,
        ),
      ),
    );

/// Pumps [child] once translations have loaded, and lets the map find out
/// that Google's map can be drawn.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String appearance = 'light',
}) async {
  await tester.pumpWidget(chartAppearanceApp(appearance, const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(chartAppearanceApp(appearance, child));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

/// Has the page start, as WebKit does once it has loaded, and draw.
Future<_FakePage> _start(WidgetTester tester) async {
  final page = _opened.last;
  page.post({'type': 'ready'});
  await tester.pump();
  page.post({'type': 'shown'});
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return page;
}

/// Closes the map and the pages kept for the next one.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  GoogleMapSurface.debugReset();
}

void main() {
  setUpChartAppearanceFixtures();

  setUp(() async {
    _opened.clear();
    GoogleMapSurface.debugPages = _pages;
    GoogleTileProvider.debugRefuse(_key);
    await MapsSettings.instance.setApiKey(_key);
  });

  tearDown(() async {
    GoogleMapSurface.debugPages = null;
    GoogleMapSurface.debugReset();
    GoogleTileProvider.debugForgetRefusals();
    GoogleMapsRefusals.debugForget();
    await MapsSettings.instance.setApiKey('');
  });

  testWidgets(
      "a key Google serves no tiles for draws Google's own map, with the "
      "app's pins", (tester) async {
    await _pump(tester, _map(), appearance: 'paper');

    expect(find.byType(GoogleMapSurface), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is MapTilePainter,
      ),
      findsNothing,
    );
    final page = await _start(tester);
    final config = page.config('start');

    expect(config['key'], _key);
    expect(config['camera'], {'lat': 12.95, 'lng': 77.58, 'zoom': 12.0});
    expect((config['look']! as Map)['name'], 'paper');
    // Paper keeps its warm surfaces: no pure white.
    expect(
      jsonEncode(config['look']).toLowerCase(),
      isNot(contains('#ffffff')),
    );
    final pins = config['pins']! as List;
    expect(pins.map((pin) => (pin as Map)['id']), ['akshaya', 'lalbagh']);
    expect(pins.map((pin) => (pin as Map)['badge']), ['A', 'L']);

    await _finish(tester);
  });

  testWidgets("what happens on Google's map reaches the map's host",
      (tester) async {
    final tapped = <String>[];
    final points = <LatLng>[];
    final viewports = <MapViewport>[];
    final menus = <(Offset, LatLng)>[];
    await _pump(
      tester,
      _map(
        onPinTap: (pin) => tapped.add(pin.id),
        onPointTap: points.add,
        onViewportChanged: viewports.add,
        onContextMenu: (at, point) => menus.add((at, point)),
      ),
    );
    final page = await _start(tester);
    // A click picks a place, which the page shows with a crosshair.
    expect(page.config('start')['picking'], isTrue);

    page
      ..post({'type': 'pin', 'id': 'lalbagh'})
      ..post({'type': 'point', 'lat': 12.9, 'lng': 77.5})
      ..post({'type': 'camera', 'lat': 12.96, 'lng': 77.59, 'zoom': 13.5})
      ..post({'type': 'menu', 'lat': 12.9, 'lng': 77.5, 'x': 10, 'y': 20});
    await tester.pump();

    expect(tapped, ['lalbagh']);
    expect(points, [const LatLng(12.9, 77.5)]);
    expect(viewports.single.center, const LatLng(12.96, 77.59));
    expect(viewports.single.zoom, 13.5);
    final origin = tester.getTopLeft(find.byType(GoogleMapSurface));
    expect(menus.single.$1, origin + const Offset(10, 20));

    // A group opens by framing everything in it.
    page.post({
      'type': 'cluster',
      'ids': ['akshaya', 'lalbagh'],
    });
    await tester.pump();
    expect(page.calls('fly'), hasLength(1));

    await _finish(tester);
  });

  testWidgets(
      "hovering a pin shows its card over Google's map, and keeps the pin "
      'lifted while the card is shown', (tester) async {
    await _pump(tester, _map());
    final page = await _start(tester);

    page.post({'type': 'hover', 'id': 'akshaya', 'x': 320, 'y': 260});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AppLocationPopup), findsOneWidget);
    expect(page.calls('setHeld').last, contains('setHeld("akshaya")'));

    page.post({'type': 'hover'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AppLocationPopup), findsNothing);
    expect(page.calls('setHeld').last, contains('setHeld(null)'));

    await _finish(tester);
  });

  testWidgets("the app's controls and its host move Google's map",
      (tester) async {
    final controller = AppMapController();
    addTearDown(controller.dispose);
    await _pump(tester, _map(controller: controller));
    final page = await _start(tester);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    controller.moveTo(const LatLng(12.97, 77.59), zoom: 15);
    await tester.pump();

    expect(page.calls('zoomBy'), [
      contains('zoomBy(1.0)'),
      contains('zoomBy(-1.0)'),
    ]);
    expect(
      page.calls('fly').single,
      contains('fly(12.97,77.59,15.0,true)'),
    );

    await _finish(tester);
  });

  testWidgets(
      "two fingers move Google's map by what they moved, wherever the map "
      'sits in the window', (tester) async {
    await _pump(tester, _map());
    final page = await _start(tester);
    final surface = find.byType(GoogleMapSurface);
    final middle = tester.getCenter(surface);
    final local = middle - tester.getTopLeft(surface);
    // The map is well away from the window's corner.
    expect(tester.getTopLeft(surface), isNot(Offset.zero));

    final fingers =
        await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await fingers.panZoomStart(middle);
    await fingers.panZoomUpdate(middle, pan: const Offset(30, 0));
    await fingers.panZoomUpdate(middle, pan: const Offset(60, 10));
    await fingers.panZoomEnd();
    await tester.pump();

    expect(
      page.calls('gestureStart').single,
      contains('gestureStart(${local.dx},${local.dy})'),
    );
    expect(page.calls('gesture'), [
      contains('gesture(1.0,30.0,0.0)'),
      contains('gesture(1.0,60.0,10.0)'),
    ]);
    expect(page.calls('gestureEnd'), hasLength(1));

    await _finish(tester);
  });

  testWidgets(
      "a key Google refuses draws the app's own map, and is not tried again",
      (tester) async {
    await _pump(tester, _map());
    final page = _opened.single;
    page.post({'type': 'ready'});
    await tester.pump();
    page.post({'type': 'refused', 'detail': 'OverQuotaMapError'});
    await tester.pump();
    await tester.pump();

    expect(find.byType(GoogleMapSurface), findsNothing);
    expect(page.disposed, isTrue);
    expect(GoogleMapsRefusals.isRefused(_key), isTrue);

    // The next map does not ask Google again.
    await _pump(tester, _map());
    expect(find.byType(GoogleMapSurface), findsNothing);
    expect(_opened, hasLength(1));

    await _finish(tester);
  });

  testWidgets(
      "a map opened again shows itself on the page Google's map already "
      'loaded in', (tester) async {
    await _pump(tester, _map());
    final page = await _start(tester);

    await tester.pumpWidget(chartAppearanceApp('light', const SizedBox()));
    expect(page.calls('park'), hasLength(1));
    expect(page.disposed, isFalse);

    await tester.pumpWidget(chartAppearanceApp('light', _map()));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(_opened, hasLength(1));
    expect(page.config('show')['pins'], hasLength(2));

    await _finish(tester);
    expect(page.disposed, isTrue);
  });
}
