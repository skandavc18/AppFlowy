import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:flutter/foundation.dart';

/// Somewhere a row says it is.
///
/// A location column is written by people, so it holds whatever was to hand:
/// a pair of coordinates, a pasted Google Maps link, a place id, or just the
/// name of a town. Everything that already carries a point is used as it is;
/// only the rest has to be looked up.
@immutable
class MapLocation {
  const MapLocation({
    this.point,
    this.query = '',
    this.placeId,
    this.label = '',
  });

  static const empty = MapLocation();

  /// Where it is, when that is already known.
  final LatLng? point;

  /// What to look up when it is not.
  final String query;

  /// Google's own id for the place, when one was given.
  final String? placeId;

  /// What to call it on the map.
  final String label;

  bool get isEmpty => point == null && query.isEmpty && placeId == null;

  bool get needsLookUp => point == null && !isEmpty;

  MapLocation withPoint(LatLng found, {String? name}) => MapLocation(
        point: found,
        query: query,
        placeId: placeId,
        label: name == null || name.isEmpty ? label : name,
      );

  @override
  bool operator ==(Object other) =>
      other is MapLocation &&
      other.point == point &&
      other.query == query &&
      other.placeId == placeId &&
      other.label == label;

  @override
  int get hashCode => Object.hash(point, query, placeId, label);
}

final _coordinates = RegExp(
  r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*[°]?\s*([NnSs])?\s*[,;/ ]\s*'
  r'(-?\d{1,3}(?:\.\d+)?)\s*[°]?\s*([EeWw])?\s*$',
);

/// The pin a Google Maps link is really about, which is not the `@` centre.
final _placePin = RegExp(r'!3d(-?\d{1,3}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)');
final _atCentre = RegExp(r'@(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)');
final _placeIdParam = RegExp(r'place_id:([A-Za-z0-9_\-]+)');
final _bareGooglePlaceId =
    RegExp(r'^(?:ChIJ|EiQ|GhIJ|EicR|Ei8)[A-Za-z0-9_\-]{8,}$');

/// Reads whatever a location cell holds.
MapLocation parseMapLocation(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return MapLocation.empty;
  }

  final pair = _coordinates.firstMatch(value);
  if (pair != null) {
    final point = _pointFrom(
      pair.group(1),
      pair.group(2),
      pair.group(3),
      pair.group(4),
    );
    if (point != null) {
      return MapLocation(point: point, label: value);
    }
  }

  if (_looksLikeUrl(value)) {
    return _fromUrl(value);
  }

  if (_bareGooglePlaceId.hasMatch(value)) {
    return MapLocation(placeId: value, query: value, label: value);
  }

  final byId = _placeIdParam.firstMatch(value);
  if (byId != null) {
    return MapLocation(placeId: byId.group(1), query: value, label: value);
  }

  // A town, a country, a street — something to be looked up.
  return MapLocation(query: value, label: value);
}

MapLocation _fromUrl(String value) {
  final uri = Uri.tryParse(value);
  final name = uri == null ? value : _nameFromMapsPath(uri) ?? value;

  final pin = _placePin.firstMatch(value);
  if (pin != null) {
    final point = _pointFrom(pin.group(1), null, pin.group(2), null);
    if (point != null) {
      return MapLocation(point: point, label: name, query: value);
    }
  }

  final byId = _placeIdParam.firstMatch(value);
  if (byId != null) {
    return MapLocation(placeId: byId.group(1), query: value, label: name);
  }

  if (uri != null) {
    for (final key in const ['q', 'query', 'll', 'daddr', 'center']) {
      final param = uri.queryParameters[key];
      if (param == null || param.isEmpty) {
        continue;
      }
      final parsed = parseMapLocation(param);
      if (parsed.point != null) {
        return MapLocation(point: parsed.point, label: name, query: value);
      }
      if (parsed.placeId != null) {
        return MapLocation(
          placeId: parsed.placeId,
          label: name,
          query: value,
        );
      }
      // A named place in the query is still better to search for than the URL.
      return MapLocation(query: param, label: name);
    }
  }

  final centre = _atCentre.firstMatch(value);
  if (centre != null) {
    final point = _pointFrom(centre.group(1), null, centre.group(2), null);
    if (point != null) {
      return MapLocation(point: point, label: name, query: value);
    }
  }

  // A short link has nothing in it to read; the name in the path is the best
  // thing left to search for.
  final path = uri == null ? null : _nameFromMapsPath(uri);
  return MapLocation(query: path ?? value, label: name);
}

String? _nameFromMapsPath(Uri uri) {
  final segments = uri.pathSegments;
  final index = segments.indexOf('place');
  if (index < 0 || index + 1 >= segments.length) {
    return null;
  }
  final name = Uri.decodeComponent(segments[index + 1]).replaceAll('+', ' ');
  return name.trim().isEmpty ? null : name.trim();
}

bool _looksLikeUrl(String value) {
  final lower = value.toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('geo:');
}

LatLng? _pointFrom(
  String? latitude,
  String? latitudeSign,
  String? longitude,
  String? longitudeSign,
) {
  final lat = double.tryParse(latitude ?? '');
  final lon = double.tryParse(longitude ?? '');
  if (lat == null || lon == null) {
    return null;
  }
  final south = (latitudeSign ?? '').toUpperCase() == 'S';
  final west = (longitudeSign ?? '').toUpperCase() == 'W';
  final signedLat = south ? -lat.abs() : lat;
  final signedLon = west ? -lon.abs() : lon;
  if (signedLat.abs() > 90 || signedLon.abs() > 180) {
    return null;
  }
  return LatLng(signedLat, signedLon);
}
