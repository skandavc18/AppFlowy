import 'dart:convert';

import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:flutter/painting.dart';

import 'google_maps_view.dart';

/// The page that draws a Google Maps link with Google's own map, through the
/// Maps JavaScript API, where the app has no other way to show it (Linux).
///
/// The page holds no key. Once it posts `ready`, the view hands it the key
/// and what to show through `appflowyMap.start`, so the page the loopback
/// port serves carries nothing private. It posts back:
///
/// * `shown`: the map has drawn.
/// * `refused`: Google turned the key away (a refused key, a spent daily
///   quota, an API that is not on), with Google's reason.
/// * `unavailable`: the API could not be loaded, as when offline.
/// * `unplaced`: none of the link's places could be found.
/// * `open`: a pin was clicked.
///
/// Only APIs a Maps Demo Key includes are used: the map itself, the Place
/// class for a place the link only names, and Compute Routes for a route.
const googleMapsPageHtml = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Google Maps</title>
<style>
  html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
  #map { position: absolute; inset: 0; }
  .appflowy-pin { position: absolute; width: 30px; height: 38px; transform: translate(-50%, -100%); cursor: pointer; }
  .appflowy-pin svg { display: block; overflow: visible; transform-origin: 50% 100%; transition: transform 140ms cubic-bezier(0.2, 0.8, 0.2, 1); filter: drop-shadow(0 3px 3px rgba(0, 0, 0, 0.28)); }
  .appflowy-pin:hover svg { transform: translateY(-4px); }
</style>
</head>
<body>
<div id="map"></div>
<script>
(() => {
  'use strict';

  const post = (type, detail) => {
    try {
      window.webkit.messageHandlers.appflowyLinuxWebViewMessage.postMessage(
        JSON.stringify({ type, detail: detail == null ? null : String(detail) }));
    } catch (_) {
      // Not inside AppFlowy.
    }
  };

  let config = null;
  let library = null;
  let map = null;
  let Pin = null;
  let stops = [];
  let path = null;
  let drawn = [];
  let failed = false;

  const fail = (type, reason) => {
    if (failed) return;
    failed = true;
    post(type, reason);
  };

  // Google names a refused key, a spent quota or an API that is not on in an
  // error on the console; a refused key also reaches gm_authFailure.
  const consoleError = console.error.bind(console);
  console.error = (...parts) => {
    const text = parts.map((part) => (part && part.message) || String(part)).join(' ');
    const match = /Google Maps JavaScript API error: ([A-Za-z]+)/.exec(text);
    if (match) fail('refused', match[1]);
    consoleError(...parts);
  };
  window.gm_authFailure = () => fail('refused', 'AuthFailure');

  const toLatLng = (point) => new google.maps.LatLng(point[0], point[1]);
  const escape = (text) => String(text).replace(/[&<>"']/g, (c) => '&#' + c.charCodeAt(0) + ';');

  let gradients = 0;
  // The application's own marker: a rounded tile on a short point, with the
  // place's initial.
  const pinSvg = (stop) => {
    const id = 'appflowy-pin-' + gradients++;
    return '<svg width="30" height="38" viewBox="0 0 30 38" xmlns="http://www.w3.org/2000/svg">' +
      '<defs><linearGradient id="' + id + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="' + escape(stop.fillTop) + '"/>' +
      '<stop offset="1" stop-color="' + escape(stop.fill) + '"/></linearGradient></defs>' +
      '<rect width="30" height="31" rx="11" fill="#fff"/>' +
      '<path d="M9.5 30 L15 38 L20.5 30 Z" fill="#fff"/>' +
      '<rect x="2" y="2" width="26" height="27" rx="9" fill="url(#' + id + ')"/>' +
      '<path d="M11.4 29 L15 34.8 L18.6 29 Z" fill="' + escape(stop.fill) + '"/>' +
      '<text x="15" y="14.6" dominant-baseline="central" text-anchor="middle" ' +
      'font-family="Inter, system-ui, sans-serif" font-size="12.5" font-weight="700" fill="#fff">' +
      escape(stop.initial) + '</text></svg>';
  };

  window.appflowyMap = {
    start(next) {
      if (config) return;
      config = next;
      window.appflowyMapLoaded = () => {
        show().catch((error) => fail('unavailable', (error && error.message) || error));
      };
      const query = new URLSearchParams({
        key: config.key,
        v: 'weekly',
        loading: 'async',
        callback: 'appflowyMapLoaded',
      });
      if (config.language) query.set('language', config.language);
      const script = document.createElement('script');
      script.src = 'https://maps.googleapis.com/maps/api/js?' + query.toString();
      script.async = true;
      script.onerror = () => fail('unavailable', 'The Maps JavaScript API could not be loaded.');
      document.head.append(script);
    },

    setLook(look) {
      if (!config) return;
      config.look = look;
      if (map) {
        map.setOptions({ styles: look.styles });
        draw();
      }
    },

    // The app draws its own zoom and reset controls over the map, in its own
    // colours.
    zoomBy(delta) {
      if (map) map.setZoom(Math.round(map.getZoom() + delta));
    },

    resetView() {
      if (map) frame();
    },
  };

  async function show() {
    if (failed) return;
    library = await google.maps.importLibrary('maps');
    const target = config.target;
    const single = target.stops.length === 1;
    const known = target.stops.find((stop) => stop.point);
    const centre = (single && known && known.point) || target.centre || (known && known.point) || null;
    map = new library.Map(document.getElementById('map'), {
      center: toLatLng(centre || [20, 0]),
      zoom: centre ? (target.zoom || 15) : 2,
      styles: config.look.styles,
      backgroundColor: config.look.background,
      colorScheme: 'LIGHT',
      disableDefaultUI: true,
      gestureHandling: 'greedy',
      clickableIcons: false,
    });
    google.maps.event.addListenerOnce(map, 'tilesloaded', () => post('shown'));
    Pin = pinClass(library.OverlayView);
    if (single) {
      stops = await placeOne(target);
    } else if (target.stops.length > 1) {
      stops = await placeRoute(target);
    }
    if (failed) return;
    if (!stops.length && !centre) {
      post('unplaced');
      return;
    }
    draw();
    frame();
  }

  // A place the link only names is searched for near the view it was shared
  // from.
  async function placeOne(target) {
    const stop = target.stops[0];
    const point = stop.point || await search(stop.name, target.centre);
    return point ? [Object.assign({}, stop, { point })] : [];
  }

  // A route's ends and path, from Compute Routes, which also places ends
  // the link only names.
  async function placeRoute(target) {
    const from = target.stops[0];
    const to = target.stops[target.stops.length - 1];
    const route = await computeRoute(from, to, target.mode);
    const legs = (route && route.legs) || [];
    const at = (location) => location && location.latLng
      ? [location.latLng.latitude, location.latLng.longitude]
      : null;
    const start = from.point || at(legs.length ? legs[0].startLocation : null) ||
      await search(from.name, target.centre);
    const end = to.point || at(legs.length ? legs[legs.length - 1].endLocation : null) ||
      await search(to.name, target.centre);
    if (route && route.polyline && route.polyline.encodedPolyline) {
      try {
        const geometry = await google.maps.importLibrary('geometry');
        path = geometry.encoding.decodePath(route.polyline.encodedPolyline);
      } catch (_) {
        path = null;
      }
    }
    return [
      start && Object.assign({}, from, { point: start }),
      end && Object.assign({}, to, { point: end }),
    ].filter(Boolean);
  }

  async function computeRoute(from, to, mode) {
    const waypoint = (stop) => stop.point
      ? { location: { latLng: { latitude: stop.point[0], longitude: stop.point[1] } } }
      : { address: stop.name };
    try {
      const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': config.key,
          'X-Goog-FieldMask': 'routes.polyline.encodedPolyline,routes.legs.startLocation,routes.legs.endLocation',
        },
        body: JSON.stringify({
          origin: waypoint(from),
          destination: waypoint(to),
          travelMode: { d: 'DRIVE', w: 'WALK', b: 'BICYCLE', r: 'TRANSIT' }[mode] || 'DRIVE',
        }),
      });
      if (!response.ok) return null;
      const body = await response.json();
      return (body.routes && body.routes[0]) || null;
    } catch (_) {
      return null;
    }
  }

  async function search(text, near) {
    if (!text) return null;
    try {
      const places = await google.maps.importLibrary('places');
      const request = { textQuery: text, fields: ['location'], maxResultCount: 1 };
      if (near) request.locationBias = { lat: near[0], lng: near[1] };
      const found = await places.Place.searchByText(request);
      const location = found.places && found.places[0] && found.places[0].location;
      return location ? [location.lat(), location.lng()] : null;
    } catch (_) {
      return null;
    }
  }

  function draw() {
    for (const item of drawn) item.setMap(null);
    drawn = [];
    const look = config.look;
    if (path && path.length > 1) {
      drawn.push(new library.Polyline({
        map, path, clickable: false, zIndex: 1,
        strokeColor: look.casing, strokeOpacity: 0.85, strokeWeight: 8,
      }));
      drawn.push(new library.Polyline({
        map, path, clickable: false, zIndex: 2,
        strokeColor: look.route, strokeOpacity: 1, strokeWeight: 4.5,
      }));
    }
    for (const stop of stops) drawn.push(new Pin(stop));
  }

  // The link's own view: its place at the link's zoom, or a route and its
  // ends together, clear of the place's name and the app's controls.
  function frame() {
    const target = config.target;
    if (target.stops.length === 1 && stops.length) {
      map.setCenter(toLatLng(stops[0].point));
      map.setZoom(target.zoom || 15);
      return;
    }
    const bounds = new google.maps.LatLngBounds();
    let count = 0;
    for (const stop of stops) {
      bounds.extend(toLatLng(stop.point));
      count++;
    }
    for (const point of path || []) {
      bounds.extend(point);
      count++;
    }
    if (count > 1) {
      map.fitBounds(bounds, { top: 72, right: 72, bottom: 48, left: 48 });
    } else if (count === 1) {
      map.setCenter(bounds.getCenter());
      map.setZoom(target.zoom || 15);
    } else if (target.centre) {
      map.setCenter(toLatLng(target.centre));
      map.setZoom(target.zoom || 15);
    }
  }

  function pinClass(OverlayView) {
    return class Pin extends OverlayView {
      constructor(stop) {
        super();
        this.stop = stop;
        this.element = null;
        this.setMap(map);
      }

      onAdd() {
        const element = document.createElement('div');
        element.className = 'appflowy-pin';
        element.title = this.stop.name || '';
        element.innerHTML = pinSvg(this.stop);
        element.addEventListener('click', (event) => {
          event.stopPropagation();
          post('open');
        });
        OverlayView.preventMapHitsAndGesturesFrom(element);
        this.getPanes().overlayMouseTarget.append(element);
        this.element = element;
      }

      draw() {
        const projection = this.getProjection();
        const at = projection && projection.fromLatLngToDivPixel(toLatLng(this.stop.point));
        if (at && this.element) {
          this.element.style.left = at.x + 'px';
          this.element.style.top = at.y + 'px';
        }
      }

      onRemove() {
        if (this.element) this.element.remove();
        this.element = null;
      }
    };
  }

  // Said again until the app answers, in case it was not yet listening.
  let announced = 0;
  const announce = () => {
    if (config || announced++ >= 50) return;
    post('ready');
    setTimeout(announce, 300);
  };
  announce();
})();
</script>
</body>
</html>
''';

/// What `appflowyMap.start` is given: the key, what [target] shows and how
/// it looks in [palette].
Map<String, Object?> googleMapsPageConfig({
  required String apiKey,
  required GoogleMapsTarget target,
  required MapPalette palette,
  String? language,
}) {
  final route = target.stops.length > 1;
  return {
    'key': apiKey,
    if (language != null && language.isNotEmpty) 'language': language,
    'target': {
      'stops': [
        for (var index = 0; index < target.stops.length; index++)
          _stop(
            target.stops[index],
            route
                ? (index == 0
                    ? GoogleMapsNativeView.startColor
                    : GoogleMapsNativeView.endColor)
                : null,
            palette,
          ),
      ],
      if (target.centre != null)
        'centre': [target.centre!.latitude, target.centre!.longitude],
      if (target.zoom != null) 'zoom': target.zoom,
      if (target.travelMode != null) 'mode': target.travelMode,
    },
    'look': googleMapsPageLook(palette),
  };
}

/// How the map looks in [palette]: Google's own map in light, toned to the
/// warm dark chrome in dark and to the stationery in paper.
Map<String, Object?> googleMapsPageLook(MapPalette palette) {
  final style = palette.defaultStyle;
  return {
    'name': style.name,
    'styles': switch (style) {
      MapStyleName.dark => _darkStyles,
      MapStyleName.paper => _paperStyles,
      _ => const <Object>[],
    },
    'background': _hex(palette.canvas),
    'route': _hex(palette.accent),
    'casing': _hex(palette.isDark ? const Color(0xFF1D1A17) : palette.floating),
  };
}

/// The script that hands the page what to show.
String googleMapsStartScript(Map<String, Object?> config) =>
    'window.appflowyMap && window.appflowyMap.start(${jsonEncode(config)});';

/// The script that restyles a map that is already showing.
String googleMapsLookScript(Map<String, Object?> look) =>
    'window.appflowyMap && window.appflowyMap.setLook(${jsonEncode(look)});';

/// The script that zooms the map in or out by [steps].
String googleMapsZoomScript(int steps) =>
    'window.appflowyMap && window.appflowyMap.zoomBy($steps);';

/// The script that puts the map back on the link's own view.
const googleMapsResetScript =
    'window.appflowyMap && window.appflowyMap.resetView();';

/// A stop and its pin, coloured as the application's own map colours it.
Map<String, Object?> _stop(
  GoogleMapsStop stop,
  Color? color,
  MapPalette palette,
) {
  final point = stop.point;
  final title = stop.name ?? point?.label ?? '';
  final fill = color ?? palette.swatchFor(title);
  return {
    if (stop.name != null) 'name': stop.name,
    if (point != null) 'point': [point.latitude, point.longitude],
    'fill': _hex(fill),
    'fillTop': _hex(Color.lerp(fill, const Color(0xFFFFFFFF), 0.16)!),
    'initial': _initial(title),
  };
}

/// The first letter of [title], or a dot: a digit would read as a count.
String _initial(String title) {
  final trimmed = title.trim();
  if (!RegExp(r'^\p{L}', unicode: true).hasMatch(trimmed)) {
    return '·';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

String _hex(Color color) {
  String channel(double value) =>
      (value * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}';
}

/// Google's map in the warm near-black of the dark chrome.
const _darkStyles = <Map<String, Object>>[
  {
    'elementType': 'geometry',
    'stylers': [
      {'color': '#25221f'},
    ],
  },
  {
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#a39a8f'},
    ],
  },
  {
    'elementType': 'labels.text.stroke',
    'stylers': [
      {'color': '#1d1a17'},
    ],
  },
  {
    'elementType': 'labels.icon',
    'stylers': [
      {'saturation': -60},
      {'lightness': -25},
    ],
  },
  {
    'featureType': 'administrative',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#4a433c'},
    ],
  },
  {
    'featureType': 'administrative.locality',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#d2c8bc'},
    ],
  },
  {
    'featureType': 'landscape.man_made',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#2b2724'},
    ],
  },
  {
    'featureType': 'poi',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#2d2925'},
    ],
  },
  {
    'featureType': 'poi',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#8c8379'},
    ],
  },
  {
    'featureType': 'poi.park',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#22301f'},
    ],
  },
  {
    'featureType': 'poi.park',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#6f8a62'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#3b3631'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#2a2622'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#9a9187'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#5a4c3c'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#3a3128'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#c9b9a3'},
    ],
  },
  {
    'featureType': 'transit',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#332e29'},
    ],
  },
  {
    'featureType': 'transit.station',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#a39a8f'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#16202a'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#566a7b'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'labels.text.stroke',
    'stylers': [
      {'color': '#16202a'},
    ],
  },
];

/// Google's map on the paper's warm stationery, with no pure white.
const _paperStyles = <Map<String, Object>>[
  {
    'elementType': 'geometry',
    'stylers': [
      {'color': '#f2e9da'},
    ],
  },
  {
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#6c6258'},
    ],
  },
  {
    'elementType': 'labels.text.stroke',
    'stylers': [
      {'color': '#fbf5e9'},
    ],
  },
  {
    'elementType': 'labels.icon',
    'stylers': [
      {'saturation': -55},
      {'lightness': 10},
    ],
  },
  {
    'featureType': 'administrative',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#d6c7b1'},
    ],
  },
  {
    'featureType': 'administrative.locality',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#3b352e'},
    ],
  },
  {
    'featureType': 'landscape.man_made',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#ece2d1'},
    ],
  },
  {
    'featureType': 'poi',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#e9dfcc'},
    ],
  },
  {
    'featureType': 'poi',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#918577'},
    ],
  },
  {
    'featureType': 'poi.park',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#dde2c4'},
    ],
  },
  {
    'featureType': 'poi.park',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#7a8660'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#fdf8ee'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#e4d7c3'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#7d7266'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#f0d9b5'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#dcc39a'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#6c6258'},
    ],
  },
  {
    'featureType': 'transit',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#e2d5c0'},
    ],
  },
  {
    'featureType': 'transit.station',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#918577'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#cfdad6'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#7b8d8c'},
    ],
  },
];
