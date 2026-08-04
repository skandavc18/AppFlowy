import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:flutter/foundation.dart';

/// How a table is put on the map.
///
/// Columns are named by field id rather than by heading, so renaming a column
/// does not lose the map.
@immutable
class MapSpec {
  const MapSpec({
    this.locationColumns = const [],
    this.titleColumn = '',
    this.subtitleColumn = '',
    this.colorColumn = '',
    this.propertyColumns = const [],
    this.provider = MapProviderKind.google,
    this.style,
    this.clustering = true,
    this.center,
    this.zoom,
  });

  /// Where a row says it is. More than one is allowed, and the first that
  /// holds anything wins — a table often has both an address and coordinates.
  final List<String> locationColumns;

  final String titleColumn;
  final String subtitleColumn;

  /// The column whose value decides a marker's colour, usually a status.
  final String colorColumn;

  /// The handful of columns worth showing on the preview card.
  final List<String> propertyColumns;

  final MapProviderKind provider;

  /// The basemap. Null follows the application's appearance.
  final MapStyleName? style;

  final bool clustering;

  /// Where the map was left.
  final LatLng? center;
  final double? zoom;

  bool get isConfigured => locationColumns.isNotEmpty;

  MapSpec copyWith({
    List<String>? locationColumns,
    String? titleColumn,
    String? subtitleColumn,
    String? colorColumn,
    List<String>? propertyColumns,
    MapProviderKind? provider,
    MapStyleName? style,
    bool clearStyle = false,
    bool? clustering,
    LatLng? center,
    double? zoom,
  }) {
    return MapSpec(
      locationColumns: locationColumns ?? this.locationColumns,
      titleColumn: titleColumn ?? this.titleColumn,
      subtitleColumn: subtitleColumn ?? this.subtitleColumn,
      colorColumn: colorColumn ?? this.colorColumn,
      propertyColumns: propertyColumns ?? this.propertyColumns,
      provider: provider ?? this.provider,
      style: clearStyle ? null : (style ?? this.style),
      clustering: clustering ?? this.clustering,
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
    );
  }

  Map<String, Object?> toJson() => {
        if (locationColumns.isNotEmpty) 'location': locationColumns,
        if (titleColumn.isNotEmpty) 'title': titleColumn,
        if (subtitleColumn.isNotEmpty) 'subtitle': subtitleColumn,
        if (colorColumn.isNotEmpty) 'color': colorColumn,
        if (propertyColumns.isNotEmpty) 'properties': propertyColumns,
        if (provider != MapProviderKind.google) 'provider': provider.id,
        if (style != null) 'style': style!.name,
        if (!clustering) 'clustering': false,
        if (center != null) 'lat': center!.latitude,
        if (center != null) 'lng': center!.longitude,
        if (zoom != null) 'zoom': zoom,
      };

  static MapSpec fromJson(Map<String, dynamic> values) {
    final latitude = (values['lat'] as num?)?.toDouble();
    final longitude = (values['lng'] as num?)?.toDouble();
    return MapSpec(
      locationColumns: _strings(values['location']),
      titleColumn: values['title'] as String? ?? '',
      subtitleColumn: values['subtitle'] as String? ?? '',
      colorColumn: values['color'] as String? ?? '',
      propertyColumns: _strings(values['properties']),
      provider: MapProviderKind.fromId(values['provider'] as String?),
      style: _style(values['style'] as String?),
      clustering: values['clustering'] != false,
      center: latitude == null || longitude == null
          ? null
          : LatLng.clamped(latitude, longitude),
      zoom: (values['zoom'] as num?)?.toDouble(),
    );
  }

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.whereType<String>())
      : const <String>[];

  static MapStyleName? _style(String? name) {
    if (name == null) {
      return null;
    }
    for (final style in MapStyleName.values) {
      if (style.name == name) {
        return style;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is MapSpec &&
      listEquals(other.locationColumns, locationColumns) &&
      other.titleColumn == titleColumn &&
      other.subtitleColumn == subtitleColumn &&
      other.colorColumn == colorColumn &&
      listEquals(other.propertyColumns, propertyColumns) &&
      other.provider == provider &&
      other.style == style &&
      other.clustering == clustering &&
      other.center == center &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(locationColumns),
        titleColumn,
        subtitleColumn,
        colorColumn,
        Object.hashAll(propertyColumns),
        provider,
        style,
        clustering,
        center,
        zoom,
      );
}
