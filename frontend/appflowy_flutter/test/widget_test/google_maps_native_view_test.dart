import 'package:appflowy/extensions/dart/built_in/web_embeds/google_maps_view.dart';
import 'package:appflowy/extensions/dart/built_in/web_embeds/google_maps_web_view.dart';
import 'package:appflowy/extensions/dart/built_in/web_embeds/web_embed_sites.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/extensions/presentation/web_embed_widgets.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_tile_layer.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chart_appearance_test_support.dart';

const _extension = 'test.google_maps';
const _place =
    'https://www.google.com/maps/place/Eiffel+Tower/@48.8583701,2.2919064,17z/data=!3m1!4b1!4m6!3m5!1s0x47e66e2964e34e2d:0x8ddca9ee380ef7e0!8m2!3d48.8583701!4d2.2944813';
const _route =
    'https://www.google.com/maps/dir/Paris/Lyon/@46.3,3.5,7z/data=!3m1!4b1!4m14!4m13!1m5!1m1!1s0x47e66e1f06e2b70f:0x40b82c3688c9460!2m2!1d2.3522219!2d48.856614!1m5!1m1!1s0x47f4ea516ae88797:0x408ab2ae4bb21f0!2m2!1d4.835659!2d45.764043!3e0';
const _unplaceable = 'Pages cannot be shown in place on this device.';

/// Answers every search with [places], and remembers what it was asked.
class _Geocoder implements MapGeocoder {
  _Geocoder(this.places);

  final List<GeocodeResult> places;
  final List<String> asked = [];

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) async =>
      places.firstOrNull;

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) async {
    asked.add(query);
    return places.take(limit).toList();
  }
}

WebEmbedLink _link(String url) => ExtensionWebEmbedRegistry.recognize(url)!;

/// Pumps [child] at an embed's size once translations have loaded.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String appearance = 'light',
}) async {
  await tester.pumpWidget(chartAppearanceApp(appearance, const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    chartAppearanceApp(
      appearance,
      Center(child: SizedBox(width: 640, height: 420, child: child)),
    ),
  );
}

void main() {
  setUpChartAppearanceFixtures();

  setUp(() {
    for (final site in webEmbedSites()) {
      ExtensionWebEmbedRegistry.register(_extension, site);
    }
    debugCanShowWebEmbedPagesOverride = false;
    debugForgetGoogleMapsLookUps();
  });

  tearDown(() {
    ExtensionWebEmbedRegistry.unregisterAll(_extension);
    debugCanShowWebEmbedPagesOverride = null;
  });

  testWidgets(
      'a shared place is drawn on the app\'s own map where no page can be '
      'shown, in every appearance', (tester) async {
    for (final appearance in chartAppearances) {
      await _pump(
        tester,
        WebEmbedSurface(link: _link(_place)),
        appearance: appearance,
      );
      await tester.pump();

      expect(find.byType(GoogleMapsNativeView), findsOneWidget);
      expect(find.text(_unplaceable), findsNothing);
      final map = tester.widget<AppMapView>(find.byType(AppMapView));
      expect(map.pins.single.point, const LatLng(48.8583701, 2.2944813));
      expect(map.initialZoom, 17);

      // The name sits on the map's own floating surface, and the basemap
      // follows the appearance: paper keeps its warm stationery throughout.
      final chip = find
          .ancestor(
            of: find.text('Eiffel Tower'),
            matching: find.byType(Container),
          )
          .first;
      final palette = mapPaletteOf(tester.element(chip));
      final decoration = tester.widget<Container>(chip).decoration!;
      expect(
        (decoration as BoxDecoration).color,
        palette.floating.withValues(alpha: 0.92),
        reason: appearance,
      );
      final basemap = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<MapTilePainter>()
          .single;
      expect(basemap.style, palette.defaultStyle, reason: appearance);
      if (appearance == 'paper') {
        expect(palette.floating, PaperTheme.popupBackground);
        expect(basemap.style, MapStyleName.paper);
      }
    }
  });

  testWidgets('Google\'s own map stays wherever a page can be shown',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (built) {
          context = built;
          return const SizedBox();
        },
      ),
    );
    final place = _link(_place);
    const options = WebEmbedViewOptions();

    debugCanShowWebEmbedPagesOverride = true;
    expect(
      place.provider.buildView(context, place, options),
      isA<WebEmbedFrame>(),
    );

    debugCanShowWebEmbedPagesOverride = false;
    expect(
      place.provider.buildView(context, place, options),
      isA<GoogleMapsEmbedView>(),
    );
    // My Maps say nothing the app's map could draw.
    final myMap = _link('https://www.google.com/maps/d/viewer?mid=1AbCdEfGh');
    expect(
      myMap.provider.buildView(context, myMap, options),
      isA<WebEmbedFrame>(),
    );
  });

  testWidgets('a route is drawn as its two ends, framed together',
      (tester) async {
    await _pump(tester, WebEmbedSurface(link: _link(_route)));
    await tester.pump();

    final map = tester.widget<AppMapView>(find.byType(AppMapView));
    expect(map.pins.map((pin) => pin.title), ['Paris', 'Lyon']);
    expect(map.pins.map((pin) => pin.subtitle), ['Start', 'Destination']);
    expect(map.autoFit, isTrue);
    expect(find.text('Paris to Lyon'), findsOneWidget);
  });

  testWidgets('a place the link only names is looked up near its view',
      (tester) async {
    final geocoder = _Geocoder(const [
      GeocodeResult(
        point: LatLng(33.6609, -95.5555),
        name: 'Paris',
        address: 'Paris, Texas',
      ),
      GeocodeResult(
        point: LatLng(48.8566, 2.3522),
        name: 'Paris',
        address: 'Paris, France',
      ),
    ]);
    final link =
        _link('https://www.google.com/maps/place/Paris/@48.85,2.35,12z');
    await _pump(
      tester,
      GoogleMapsNativeView(
        link: link,
        target: GoogleMapsTarget.of(link)!,
        geocoder: geocoder,
      ),
    );
    expect(find.byType(WebEmbedLoadingPlaceholder), findsOneWidget);
    await tester.pump();

    final pin = tester.widget<AppMapView>(find.byType(AppMapView)).pins.single;
    expect(pin.point, const LatLng(48.8566, 2.3522));
    expect(pin.subtitle, 'Paris, France');
    expect(geocoder.asked, ['Paris']);
  });

  testWidgets('a place that cannot be found says so and can be asked again',
      (tester) async {
    final geocoder = _Geocoder(const []);
    final link =
        _link('https://www.google.com/maps/search/?api=1&query=Nowhere+Hall');
    await _pump(
      tester,
      GoogleMapsNativeView(
        link: link,
        target: GoogleMapsTarget.of(link)!,
        geocoder: geocoder,
      ),
    );
    await tester.pump();

    expect(
      find.text('“Nowhere Hall” could not be found on the map.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(geocoder.asked, ['Nowhere Hall', 'Nowhere Hall']);
  });

  testWidgets(
      'a short link that cannot be followed offers to try again instead of a '
      'page that cannot be shown', (tester) async {
    // The test binding answers every request with an error, as a resolver
    // that points the short link's host nowhere leaves it unfollowed.
    await _pump(
      tester,
      WebEmbedSurface(link: _link('https://maps.app.goo.gl/AbCdEf123')),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Google Maps would not say where this link leads.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(_unplaceable), findsNothing);
  });
}
