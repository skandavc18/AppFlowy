import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Maps' page for [point]. Needs no key.
Uri googleMapsLink(LatLng point) =>
    Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${point.latitude},${point.longitude}',
    });

/// The page that shows [point] in the map service the application uses:
/// Google Maps once a key is configured, OpenStreetMap otherwise.
Uri mapsLinkFor(LatLng point, {int zoom = 15}) {
  if (MapsSettings.instance.hasGoogleKey) {
    return googleMapsLink(point);
  }
  final lat = point.latitude;
  final lng = point.longitude;
  return Uri.parse(
    'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=$zoom/$lat/$lng',
  );
}

/// Opens [point] in the browser, in the service [mapsLinkFor] picks.
Future<void> openInMaps(LatLng point, {int zoom = 15}) async {
  await launchUrl(
    mapsLinkFor(point, zoom: zoom),
    mode: LaunchMode.externalApplication,
  );
}
