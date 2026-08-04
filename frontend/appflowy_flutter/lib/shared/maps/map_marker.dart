import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// One thing on the map.
///
/// A pin carries enough of its row to draw the preview card without going back
/// to the database, so hovering costs nothing.
@immutable
class AppMapPin {
  const AppMapPin({
    required this.id,
    required this.point,
    required this.title,
    this.subtitle = '',
    this.icon,
    this.color,
    this.status = '',
    this.tags = const [],
    this.coverUrl,
    this.properties = const {},
    this.lastModified,
  });

  final String id;
  final LatLng point;
  final String title;
  final String subtitle;

  /// The row's own icon, drawn inside the marker.
  final String? icon;

  /// What colour the marker takes, usually from a select column.
  final Color? color;
  final String status;
  final List<String> tags;
  final String? coverUrl;

  /// The handful of columns worth showing on the preview card.
  final Map<String, String> properties;
  final DateTime? lastModified;

  @override
  bool operator ==(Object other) => other is AppMapPin && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Pins that are close enough together to be drawn as one.
@immutable
class MapCluster {
  const MapCluster({
    required this.screen,
    required this.center,
    required this.pins,
  });

  /// Where the bubble is drawn.
  final Offset screen;

  /// The middle of everything in it, which is where clicking zooms to.
  final LatLng center;
  final List<AppMapPin> pins;

  bool get isSingle => pins.length == 1;

  int get count => pins.length;

  AppMapPin get first => pins.first;

  /// A key that only changes when the grouping does, so markers are not
  /// rebuilt while panning.
  String get id => isSingle ? first.id : 'cluster:${pins.length}:${first.id}';

  /// The box the cluster covers, which is what a click should zoom to fit.
  LatLngBounds get bounds => LatLngBounds.around(pins.map((pin) => pin.point));
}

/// How near two pins must be, in pixels, before they are drawn as one.
const double defaultClusterRadius = 62;

/// Groups pins that would otherwise sit on top of each other.
///
/// Grouping happens in screen space, not in degrees, so the same pins fall
/// apart naturally as the map is zoomed in — a degree radius would cluster
/// differently near the poles and would not follow the zoom at all.
///
/// Pins outside the view are dropped first, which is what keeps a table of
/// thousands of rows drawing only what can be seen.
List<MapCluster> clusterPins(
  Iterable<AppMapPin> pins,
  MapCamera camera, {
  double radius = defaultClusterRadius,
  bool enabled = true,
  double margin = 160,
}) {
  final visible = <AppMapPin, Offset>{};
  for (final pin in pins) {
    if (!pin.point.isValid) {
      continue;
    }
    final at = camera.toScreen(pin.point);
    if (at.dx < -margin ||
        at.dy < -margin ||
        at.dx > camera.size.width + margin ||
        at.dy > camera.size.height + margin) {
      continue;
    }
    visible[pin] = at;
  }

  if (!enabled || radius <= 0) {
    return [
      for (final entry in visible.entries)
        MapCluster(
          screen: entry.value,
          center: entry.key.point,
          pins: [entry.key],
        ),
    ];
  }

  final cells = <int, List<AppMapPin>>{};
  final columns = (camera.size.width / radius).ceil() + 4;
  for (final entry in visible.entries) {
    final column = (entry.value.dx / radius).floor();
    final row = (entry.value.dy / radius).floor();
    // One integer per cell keeps the map small and the lookup cheap.
    cells.putIfAbsent(row * (columns + 8) + column, () => []).add(entry.key);
  }

  final clusters = <MapCluster>[];
  for (final group in cells.values) {
    if (group.length == 1) {
      final pin = group.first;
      clusters.add(
        MapCluster(screen: visible[pin]!, center: pin.point, pins: group),
      );
      continue;
    }
    var x = 0.0;
    var y = 0.0;
    for (final pin in group) {
      final at = visible[pin]!;
      x += at.dx;
      y += at.dy;
    }
    final middle = Offset(x / group.length, y / group.length);
    clusters.add(
      MapCluster(
        screen: middle,
        center: camera.toLatLng(middle),
        pins: List.unmodifiable(group),
      ),
    );
  }

  // Bigger groups last so they are drawn on top of the single pins.
  clusters.sort((a, b) => a.count.compareTo(b.count));
  return clusters;
}

/// The cluster or pin under a point, if any.
MapCluster? clusterAt(
  List<MapCluster> clusters,
  Offset position, {
  double reach = 22,
}) {
  MapCluster? best;
  var nearest = reach * reach;
  // Later clusters are drawn on top, so they are tested first.
  for (final cluster in clusters.reversed) {
    final delta = cluster.screen - position;
    // The marker's point is at its bottom, so its body sits above the anchor.
    final adjusted = Offset(delta.dx, delta.dy + reach * 0.8);
    final distance = adjusted.dx * adjusted.dx + adjusted.dy * adjusted.dy;
    if (distance <= nearest) {
      nearest = distance;
      best = cluster;
    }
  }
  return best;
}
