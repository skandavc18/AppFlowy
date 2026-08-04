import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

/// The side of one map tile in pixels at its natural scale.
const double mapTileSize = 256;

/// Web Mercator cannot describe the poles, and stops here.
const double mercatorLimit = 85.05112878;

const double minMapZoom = 1;
const double maxMapZoom = 20;

/// A point on the earth.
@immutable
class LatLng {
  const LatLng(this.latitude, this.longitude);

  /// Pulls a point back inside the range the projection can draw.
  factory LatLng.clamped(double latitude, double longitude) {
    var lon = longitude;
    if (lon.isNaN || lon.isInfinite) {
      lon = 0;
    }
    // Longitude wraps rather than stopping.
    while (lon > 180) {
      lon -= 360;
    }
    while (lon < -180) {
      lon += 360;
    }
    final lat = latitude.isNaN || latitude.isInfinite
        ? 0.0
        : latitude.clamp(-mercatorLimit, mercatorLimit).toDouble();
    return LatLng(lat, lon);
  }

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      !latitude.isNaN &&
      !longitude.isNaN;

  /// "51.50740, -0.12780" — precise enough to find, short enough to read.
  String get label =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  @override
  bool operator ==(Object other) =>
      other is LatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLng($label)';
}

/// A rectangle of the earth.
@immutable
class LatLngBounds {
  const LatLngBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  /// The smallest box holding every point given.
  factory LatLngBounds.around(Iterable<LatLng> points) {
    var south = 90.0;
    var north = -90.0;
    var west = 180.0;
    var east = -180.0;
    var found = false;
    for (final point in points) {
      if (!point.isValid) {
        continue;
      }
      found = true;
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    if (!found) {
      return const LatLngBounds(south: 0, west: 0, north: 0, east: 0);
    }
    return LatLngBounds(south: south, west: west, north: north, east: east);
  }

  final double south;
  final double west;
  final double north;
  final double east;

  LatLng get center => LatLng.clamped((south + north) / 2, (west + east) / 2);

  bool get isEmpty => south == north && west == east;

  bool contains(LatLng point) =>
      point.latitude >= south &&
      point.latitude <= north &&
      point.longitude >= west &&
      point.longitude <= east;

  /// Grows the box by a fraction of its own size, so pins are not on the edge.
  LatLngBounds padded(double fraction) {
    final height = (north - south).abs();
    final width = (east - west).abs();
    // A single point has no size to grow by, so give it a small window.
    final growY = height < 1e-9 ? 0.01 : height * fraction;
    final growX = width < 1e-9 ? 0.01 : width * fraction;
    return LatLngBounds(
      south: (south - growY).clamp(-mercatorLimit, mercatorLimit).toDouble(),
      north: (north + growY).clamp(-mercatorLimit, mercatorLimit).toDouble(),
      west: (west - growX).clamp(-180, 180).toDouble(),
      east: (east + growX).clamp(-180, 180).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LatLngBounds &&
      other.south == south &&
      other.west == west &&
      other.north == north &&
      other.east == east;

  @override
  int get hashCode => Object.hash(south, west, north, east);
}

/// The width of the whole world in pixels at this zoom.
double mapWorldSize(double zoom) => mapTileSize * math.pow(2, zoom);

/// Where a point sits on the world square, as a fraction from the top left.
///
/// This is the Web Mercator projection every tile server draws in, so a tile's
/// address is just this fraction multiplied out at the tile grid's size.
Offset projectLatLng(LatLng point) {
  final lat = point.latitude.clamp(-mercatorLimit, mercatorLimit).toDouble();
  final radians = lat * math.pi / 180;
  final x = (point.longitude + 180) / 360;
  final y =
      (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) / 2;
  return Offset(x, y.clamp(0.0, 1.0));
}

/// The point a fraction of the way across the world square.
LatLng unprojectWorld(Offset fraction) {
  final x = fraction.dx - fraction.dx.floorToDouble();
  final y = fraction.dy.clamp(0.0, 1.0);
  final longitude = x * 360 - 180;
  final n = math.pi * (1 - 2 * y);
  final latitude = 180 / math.pi * math.atan(_sinh(n));
  return LatLng.clamped(latitude, longitude);
}

double _sinh(double value) => (math.exp(value) - math.exp(-value)) / 2;

/// What the map is looking at.
@immutable
class MapCamera {
  const MapCamera({
    required this.center,
    required this.zoom,
    required this.size,
  });

  final LatLng center;
  final double zoom;
  final Size size;

  /// Where a point falls on screen.
  Offset toScreen(LatLng point) {
    final world = mapWorldSize(zoom);
    final at = projectLatLng(point) * world;
    final middle = projectLatLng(center) * world;
    return Offset(
      at.dx - middle.dx + size.width / 2,
      at.dy - middle.dy + size.height / 2,
    );
  }

  /// What sits under a point on screen.
  LatLng toLatLng(Offset screen) {
    final world = mapWorldSize(zoom);
    final middle = projectLatLng(center) * world;
    final at = Offset(
      screen.dx - size.width / 2 + middle.dx,
      screen.dy - size.height / 2 + middle.dy,
    );
    return unprojectWorld(Offset(at.dx / world, at.dy / world));
  }

  /// The stretch of earth on screen.
  LatLngBounds get bounds {
    final topLeft = toLatLng(Offset.zero);
    final bottomRight = toLatLng(Offset(size.width, size.height));
    return LatLngBounds(
      south: math.min(topLeft.latitude, bottomRight.latitude),
      north: math.max(topLeft.latitude, bottomRight.latitude),
      west: math.min(topLeft.longitude, bottomRight.longitude),
      east: math.max(topLeft.longitude, bottomRight.longitude),
    );
  }

  MapCamera copyWith({LatLng? center, double? zoom, Size? size}) => MapCamera(
        center: center ?? this.center,
        zoom: (zoom ?? this.zoom).clamp(minMapZoom, maxMapZoom).toDouble(),
        size: size ?? this.size,
      );

  /// Drags the map by a distance on screen.
  MapCamera panned(Offset delta) {
    final world = mapWorldSize(zoom);
    final middle = projectLatLng(center) * world;
    final moved = Offset(middle.dx - delta.dx, middle.dy - delta.dy);
    return copyWith(
      center: unprojectWorld(Offset(moved.dx / world, moved.dy / world)),
    );
  }

  /// Zooms while holding whatever is under [focus] still.
  ///
  /// Without the anchor a wheel zoom drifts away from the pointer, which is
  /// what makes a map feel like it is fighting back.
  MapCamera zoomedTo(double newZoom, {Offset? focus}) {
    final clamped = newZoom.clamp(minMapZoom, maxMapZoom).toDouble();
    if (focus == null || clamped == zoom) {
      return copyWith(zoom: clamped);
    }
    final anchor = toLatLng(focus);
    final zoomed = copyWith(zoom: clamped);
    final drift = zoomed.toScreen(anchor) - focus;
    return zoomed.panned(-drift);
  }

  /// The closest view that shows the whole box.
  MapCamera fittedTo(LatLngBounds bounds, {double padding = 48}) {
    if (size.isEmpty) {
      return copyWith(center: bounds.center);
    }
    final southWest = projectLatLng(LatLng(bounds.south, bounds.west));
    final northEast = projectLatLng(LatLng(bounds.north, bounds.east));
    final spanX = (northEast.dx - southWest.dx).abs();
    final spanY = (southWest.dy - northEast.dy).abs();
    final usableWidth = math.max(1.0, size.width - padding * 2);
    final usableHeight = math.max(1.0, size.height - padding * 2);

    // A single pin has no span, so keep a readable street-level zoom.
    var fitted = maxMapZoom;
    if (spanX > 1e-9) {
      fitted = math.min(fitted, _zoomFor(usableWidth, spanX));
    }
    if (spanY > 1e-9) {
      fitted = math.min(fitted, _zoomFor(usableHeight, spanY));
    }
    if (spanX <= 1e-9 && spanY <= 1e-9) {
      fitted = 15;
    }
    return copyWith(center: bounds.center, zoom: fitted);
  }

  static double _zoomFor(double pixels, double span) =>
      math.log(pixels / (mapTileSize * span)) / math.ln2;

  @override
  bool operator ==(Object other) =>
      other is MapCamera &&
      other.center == center &&
      other.zoom == zoom &&
      other.size == size;

  @override
  int get hashCode => Object.hash(center, zoom, size);
}

/// Eases one view into another.
///
/// The middle is moved across the projected world rather than by latitude, so
/// a long journey travels in a straight line on screen instead of curving.
MapCamera lerpCamera(MapCamera from, MapCamera to, double t) {
  final zoom = from.zoom + (to.zoom - from.zoom) * t;
  final start = projectLatLng(from.center);
  final end = projectLatLng(to.center);
  final middle = Offset(
    start.dx + (end.dx - start.dx) * t,
    start.dy + (end.dy - start.dy) * t,
  );
  return MapCamera(
    center: unprojectWorld(middle),
    zoom: zoom.clamp(minMapZoom, maxMapZoom).toDouble(),
    size: to.size,
  );
}

/// Roughly how far apart two points are, in metres.
double distanceBetween(LatLng a, LatLng b) {
  const earthRadius = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(lat1) * math.cos(lat2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
}
