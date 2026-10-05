import 'package:appflowy/shared/maps/app_map_marker.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_links.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_tile_layer.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:appflowy/shared/slides/slide_property_view.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _delhi = LatLng(28.6139, 77.209);
const _key = 'configured-key';

void main() {
  tearDown(() async {
    await MapsSettings.instance.setApiKey('');
    GoogleTileProvider.debugForgetRefusals();
  });

  group('the Google key configured in Settings', () {
    testWidgets('draws a map that was not handed a key of its own',
        (tester) async {
      await MapsSettings.instance.setApiKey(_key);
      await tester.pumpWidget(
        _host(const AppMapView(initialCenter: _delhi, initialZoom: 12)),
      );
      await tester.pump();
      expect(_providerOf(tester), _google);

      // Clearing the key in Settings goes straight back to the keyless maps.
      await MapsSettings.instance.setApiKey('');
      await tester.pump();
      expect(_providerOf(tester), isNot(isA<GoogleTileProvider>()));
    });

    testWidgets('draws the location previews of table views and slides',
        (tester) async {
      await MapsSettings.instance.setApiKey(_key);
      const value = '28.61390, 77.20900';
      final previews = <String, WidgetBuilder>{
        'table': (context) => TablePropertyView(
              property: const TableProperty(
                fieldId: 'place',
                name: 'Place',
                value: value,
                kind: TablePropertyKind.location,
              ),
              palette: tableViewPaletteOf(context),
              live: true,
            ),
        'slide': (context) => SlidePropertyView(
              property: const SlideProperty(
                fieldId: 'place',
                name: 'Place',
                value: value,
                kind: SlidePropertyKind.location,
              ),
              palette: slidePaletteOf(context),
              live: true,
            ),
      };
      for (final preview in previews.entries) {
        await tester.pumpWidget(_host(Builder(builder: preview.value)));
        await tester.pump();
        expect(find.byType(AppMapView), findsOneWidget, reason: preview.key);
        expect(_providerOf(tester), _google, reason: preview.key);
      }
    });

    test('looks places up', () async {
      await MapsSettings.instance.setApiKey(_key);

      final geocoder = resolveGeocoder();

      expect(geocoder, isA<FallbackGeocoder>());
      expect((geocoder as FallbackGeocoder).primary.apiKey, _key);
    });

    test('opens places in Google Maps', () async {
      expect(mapsLinkFor(_delhi).host, 'www.openstreetmap.org');

      await MapsSettings.instance.setApiKey(_key);
      final link = mapsLinkFor(_delhi);

      expect(link.host, 'www.google.com');
      expect(link.queryParameters['query'], '28.6139,77.209');
    });
  });

  group("a pin's badge", () {
    testWidgets('is the first letter of the place, never a digit',
        (tester) async {
      for (final title in {
        'Paris': 'P',
        'école': 'É',
        '東京': '東',
        '28.61390, 77.20900': '·',
        '221B Baker Street': '·',
        '-33.86880, 151.20930': '·',
        '   ': '·',
      }.entries) {
        await tester.pumpWidget(
          _host(
            _marker([AppMapPin(id: 'pin', point: _delhi, title: title.key)]),
          ),
        );
        await tester.pump(MapMetrics.drop);
        expect(_markerText(tester), title.value, reason: title.key);
      }
    });

    testWidgets('leaves numbers to the bubbles that count pins',
        (tester) async {
      await tester.pumpWidget(
        _host(
          _marker(const [
            AppMapPin(id: 'a', point: _delhi, title: 'Agra'),
            AppMapPin(id: 'b', point: _delhi, title: 'Bhopal'),
          ]),
        ),
      );
      await tester.pump(MapMetrics.drop);
      expect(_markerText(tester), '2');
    });
  });
}

final _google = isA<GoogleTileProvider>().having(
  (provider) => provider.apiKey,
  'apiKey',
  _key,
);

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 420, height: 320, child: child),
        ),
      ),
    );

Widget _marker(List<AppMapPin> pins) => Builder(
      builder: (context) => Center(
        child: AppMapMarker(
          cluster: MapCluster(screen: Offset.zero, center: _delhi, pins: pins),
          palette: mapPaletteOf(context),
        ),
      ),
    );

String? _markerText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(AppMapMarker),
        matching: find.byType(Text),
      ),
    )
    .data;

MapTileProvider _providerOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is MapTilePainter,
    ),
  );
  return (paint.painter! as MapTilePainter).provider;
}
