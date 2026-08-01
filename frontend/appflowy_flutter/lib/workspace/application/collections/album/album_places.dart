import 'dart:math' as math;

import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:flutter/foundation.dart';

/// A spot on the map, and everything that was photographed there.
@immutable
class AlbumPlace {
  const AlbumPlace({
    required this.latitude,
    required this.longitude,
    required this.items,
  });

  final double latitude;
  final double longitude;
  final List<AlbumMediaItem> items;

  int get count => items.length;

  /// "51.50740, -0.12780" — precise enough to find, short enough to read.
  String get label =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

@immutable
class AlbumPlacePoint {
  const AlbumPlacePoint({
    required this.item,
    required this.latitude,
    required this.longitude,
  });

  final AlbumMediaItem item;
  final double latitude;
  final double longitude;
}

/// Groups pictures taken near each other into one pin.
///
/// A degree of latitude is about 111 km everywhere, so a plain degree radius
/// is a good enough neighbourhood for a photo album and costs none of the
/// machinery a proper geodesic clustering would.
List<AlbumPlace> clusterAlbumPlaces(
  List<AlbumPlacePoint> points, {
  double radiusDegrees = 0.35,
}) {
  if (points.isEmpty) {
    return const [];
  }

  final centroids = <List<double>>[];
  final buckets = <List<AlbumMediaItem>>[];
  final sums = <List<double>>[];

  for (final point in points) {
    if (point.latitude.abs() > 90 || point.longitude.abs() > 180) {
      continue;
    }
    var matched = -1;
    var best = double.infinity;
    for (var index = 0; index < centroids.length; index++) {
      final distance = _distance(
        point.latitude,
        point.longitude,
        centroids[index][0],
        centroids[index][1],
      );
      if (distance <= radiusDegrees && distance < best) {
        best = distance;
        matched = index;
      }
    }
    if (matched < 0) {
      centroids.add([point.latitude, point.longitude]);
      sums.add([point.latitude, point.longitude]);
      buckets.add([point.item]);
      continue;
    }
    buckets[matched].add(point.item);
    sums[matched][0] += point.latitude;
    sums[matched][1] += point.longitude;
    final size = buckets[matched].length;
    centroids[matched] = [sums[matched][0] / size, sums[matched][1] / size];
  }

  final places = [
    for (var index = 0; index < buckets.length; index++)
      AlbumPlace(
        latitude: centroids[index][0],
        longitude: centroids[index][1],
        items: List.unmodifiable(buckets[index]),
      ),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return List.unmodifiable(places);
}

/// Longitude wraps, so two points either side of the date line are close.
double _distance(double lat1, double lon1, double lat2, double lon2) {
  final dLat = lat1 - lat2;
  var dLon = (lon1 - lon2).abs();
  if (dLon > 180) {
    dLon = 360 - dLon;
  }
  // Meridians converge towards the poles.
  final scale = math.cos((lat1 + lat2) / 2 * math.pi / 180).abs();
  final scaled = dLon * (scale < 0.05 ? 0.05 : scale);
  return math.sqrt(dLat * dLat + scaled * scaled);
}
