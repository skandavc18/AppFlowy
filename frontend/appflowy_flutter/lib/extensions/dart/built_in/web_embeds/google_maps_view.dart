import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/extensions/presentation/web_embed_widgets.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

/// One place a Google Maps link marks: what it is called, where it is, or
/// both.
@immutable
class GoogleMapsStop {
  const GoogleMapsStop({this.name, this.point});

  /// What the link calls it, and what is looked up when [point] is unknown.
  final String? name;
  final LatLng? point;

  @override
  bool operator ==(Object other) =>
      other is GoogleMapsStop && other.name == name && other.point == point;

  @override
  int get hashCode => Object.hash(name, point);

  @override
  String toString() => 'GoogleMapsStop($name, $point)';
}

/// What a Google Maps link shows, read off its address: enough for the
/// application's own map to draw it where Google's embedded map cannot be
/// shown.
@immutable
class GoogleMapsTarget {
  const GoogleMapsTarget({
    this.stops = const [],
    this.centre,
    this.zoom,
    this.travelMode,
  });

  /// The place a place link is about, or a route's start and end. Empty for
  /// a link that only looks at an area.
  final List<GoogleMapsStop> stops;

  /// Where the shared view was looking.
  final LatLng? centre;
  final double? zoom;

  /// How a route is travelled, as Google's `dirflg` names it: `d`riving,
  /// `w`alking, `b`icycling or public t`r`ansit.
  final String? travelMode;

  bool get isEmpty => stops.isEmpty && centre == null;

  static const _parameter = 'google_maps_target';

  /// [link]'s target, when the provider could read one off its address.
  static GoogleMapsTarget? of(WebEmbedLink link) {
    final raw = link.parameters[_parameter];
    if (raw == null) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map) {
        return null;
      }
      final stops = json['stops'];
      final zoom = json['zoom'];
      final mode = json['mode'];
      final target = GoogleMapsTarget(
        stops: [
          if (stops is List)
            for (final stop in stops)
              if (stop is Map)
                GoogleMapsStop(
                  name: stop['name'] is String ? stop['name'] as String : null,
                  point: _readPoint(stop['point']),
                ),
        ],
        centre: _readPoint(json['centre']),
        zoom: zoom is num ? zoom.toDouble() : null,
        travelMode: mode is String ? mode : null,
      );
      return target.isEmpty ? null : target;
    } on FormatException {
      return null;
    }
  }

  /// What a [WebEmbedLink] carries this target in.
  Map<String, String> toParameters() => isEmpty
      ? const {}
      : {
          _parameter: jsonEncode({
            'stops': [
              for (final stop in stops)
                {
                  if (stop.name != null) 'name': stop.name,
                  if (stop.point != null) 'point': _writePoint(stop.point!),
                },
            ],
            if (centre != null) 'centre': _writePoint(centre!),
            if (zoom != null) 'zoom': zoom,
            if (travelMode != null) 'mode': travelMode,
          }),
        };

  static List<double> _writePoint(LatLng point) =>
      [point.latitude, point.longitude];

  static LatLng? _readPoint(Object? value) {
    if (value is! List || value.length != 2) {
      return null;
    }
    final lat = value[0];
    final lng = value[1];
    if (lat is! num || lng is! num) {
      return null;
    }
    final point = LatLng(lat.toDouble(), lng.toDouble());
    return point.isValid ? point : null;
  }
}

/// A Google Maps link drawn on the application's own map, for a device with
/// no renderer to show Google's embedded map in.
///
/// A place the link only names is looked up the way a map block looks one
/// up, nearest the view it was shared from. A click on a pin opens the link
/// in the browser.
class GoogleMapsNativeView extends StatefulWidget {
  const GoogleMapsNativeView({
    super.key,
    required this.link,
    required this.target,
    this.options = const WebEmbedViewOptions(),
    this.geocoder,
  });

  final WebEmbedLink link;
  final GoogleMapsTarget target;
  final WebEmbedViewOptions options;

  /// Null uses the geocoder for the key configured in Settings.
  final MapGeocoder? geocoder;

  /// Keeps the map's own controls under the host's floating toolbar.
  static const double toolbarClearance = 40;

  /// Room left on the right for the host's floating toolbar.
  static const double toolbarWidth = 150;

  /// The pins at a route's two ends.
  static const Color startColor = Color(0xFF10B981);
  static const Color endColor = Color(0xFFEF4444);

  /// Why [target] has nothing on the map: none of its places could be found.
  static String unplacedMessage(GoogleMapsTarget target) {
    final names = [
      for (final stop in target.stops)
        if (stop.name != null) '“${stop.name}”',
    ];
    return names.isEmpty
        ? 'This place could not be found on the map.'
        : '${names.join(' and ')} could not be found on the map.';
  }

  @override
  State<GoogleMapsNativeView> createState() => _GoogleMapsNativeViewState();
}

class _GoogleMapsNativeViewState extends State<GoogleMapsNativeView> {
  /// Null while a stop is still being looked up.
  List<AppMapPin>? _pins;
  int _lookUp = 0;

  @override
  void initState() {
    super.initState();
    _placeStops();
  }

  @override
  void didUpdateWidget(covariant GoogleMapsNativeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link ||
        oldWidget.options.reloadToken != widget.options.reloadToken) {
      _placeStops();
    }
  }

  void _placeStops() {
    final lookUp = ++_lookUp;
    final stops = widget.target.stops;
    if (stops.every((stop) => stop.point != null)) {
      _pins = _pinsFor([
        for (final stop in stops)
          GeocodeResult(point: stop.point!, name: stop.name ?? ''),
      ]);
      return;
    }
    _pins = null;
    final geocoder = widget.geocoder ?? resolveGeocoder();
    final near = widget.target.centre;
    unawaited(
      Future.wait([
        for (final stop in stops)
          stop.point != null
              ? Future<GeocodeResult?>.value(
                  GeocodeResult(point: stop.point!, name: stop.name ?? ''),
                )
              : lookUpGoogleMapsPlace(stop.name ?? '', geocoder, near: near),
      ]).then((found) {
        if (mounted && lookUp == _lookUp) {
          setState(() => _pins = _pinsFor(found));
        }
      }),
    );
  }

  List<AppMapPin> _pinsFor(List<GeocodeResult?> found) {
    final stops = widget.target.stops;
    final route = stops.length > 1;
    return [
      for (var index = 0; index < stops.length; index++)
        if (found[index] case final place?)
          AppMapPin(
            id: 'stop-$index',
            point: place.point,
            title: stops[index].name ?? place.point.label,
            subtitle:
                route ? (index == 0 ? 'Start' : 'Destination') : place.address,
            color: route
                ? (index == 0
                    ? GoogleMapsNativeView.startColor
                    : GoogleMapsNativeView.endColor)
                : null,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pins = _pins;
    if (pins == null) {
      return WebEmbedLoadingPlaceholder(link: widget.link);
    }
    final target = widget.target;
    final route = pins.length > 1;
    final centre = route
        ? LatLngBounds.around(pins.map((pin) => pin.point)).center
        : pins.isEmpty
            ? target.centre
            : pins.first.point;
    if (centre == null) {
      return WebEmbedFailure(
        url: widget.link.url,
        message: GoogleMapsNativeView.unplacedMessage(target),
        onRetry: () => setState(_placeStops),
      );
    }
    final palette = mapPaletteOf(context);
    final title = widget.link.title ?? (route ? null : pins.firstOrNull?.title);
    return IgnorePointer(
      ignoring: !widget.options.interactive,
      child: Stack(
        children: [
          Positioned.fill(
            child: AppMapView(
              // The camera is only read when the map is made, so another link
              // or a reload makes a new one, looking where the link looks.
              key: ValueKey('${widget.link.url} ${widget.options.reloadToken}'),
              pins: pins,
              initialCenter: centre,
              initialZoom:
                  (target.zoom ?? 15).clamp(minMapZoom, maxMapZoom).toDouble(),
              autoFit: route,
              clustering: false,
              onPinTap: (_) => unawaited(afLaunchUrlString(widget.link.url)),
              padding: const EdgeInsets.only(
                top: GoogleMapsNativeView.toolbarClearance,
              ),
            ),
          ),
          if (title != null && title.isNotEmpty)
            Positioned(
              left: 12,
              top: 12,
              right: GoogleMapsNativeView.toolbarWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: GoogleMapsTitleChip(
                  title: title,
                  icon: widget.link.icon,
                  palette: palette,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Places already found, by what was asked, so a map drawn again does not
/// ask again. Misses are not kept, so they are asked again.
final _lookUps = <String, Future<GeocodeResult?>>{};

/// How far from the shared view a match may be and still be the place the
/// link means.
const _nearEnough = 50000.0;

/// The place [name] most likely means.
///
/// A name alone can be any of several places, so with [near], the view the
/// link was shared from, the match nearest to it is taken, and none at all
/// when every match is far away.
Future<GeocodeResult?> lookUpGoogleMapsPlace(
  String name,
  MapGeocoder geocoder, {
  LatLng? near,
}) {
  final query = name.trim();
  if (query.isEmpty) {
    return Future.value();
  }
  final key = '${near?.label ?? ''}|$query';
  final known = _lookUps[key];
  if (known != null) {
    return known;
  }
  late final Future<GeocodeResult?> lookUp;
  lookUp = _nearest(query, geocoder, near).then((found) {
    if (found == null && identical(_lookUps[key], lookUp)) {
      _lookUps.remove(key);
    }
    return found;
  });
  _lookUps[key] = lookUp;
  while (_lookUps.length > 256) {
    _lookUps.remove(_lookUps.keys.first);
  }
  return lookUp;
}

Future<GeocodeResult?> _nearest(
  String query,
  MapGeocoder geocoder,
  LatLng? near,
) async {
  final List<GeocodeResult> found;
  try {
    found = await geocoder.search(query, limit: near == null ? 1 : 5);
  } on Object {
    return null;
  }
  if (near == null) {
    return found.firstOrNull;
  }
  GeocodeResult? best;
  var closest = _nearEnough;
  for (final place in found) {
    final distance = distanceBetween(near, place.point);
    if (distance <= closest) {
      best = place;
      closest = distance;
    }
  }
  return best;
}

/// Forgets every place found, so a test starts from nothing.
@visibleForTesting
void debugForgetGoogleMapsLookUps() => _lookUps.clear();

/// The place's name over the top left of the map, clear of the host's
/// toolbar on the right.
class GoogleMapsTitleChip extends StatelessWidget {
  const GoogleMapsTitleChip({
    super.key,
    required this.title,
    required this.icon,
    required this.palette,
  });

  final String title;
  final IconData icon;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.floating.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(MapMetrics.controlRadius),
        boxShadow: palette.chromeShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.2,
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
                fontVariations: flowyFontVariationsForWeight(FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
