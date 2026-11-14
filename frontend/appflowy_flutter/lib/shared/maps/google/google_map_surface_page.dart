import 'dart:convert';

import 'package:appflowy/shared/maps/google/google_maps_look.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:flutter/painting.dart';

/// The page that draws the application's own maps — tables, map blocks,
/// location pickers — on Google's map, through the Maps JavaScript API.
///
/// It is used where Google will not hand the app its map tiles (a Maps Demo
/// Key has no Map Tiles API) and a web view can show the page (Linux). The
/// pins, groups, hover and selection are drawn here, on Google's map, so
/// they never lag behind it; the app keeps its own controls, search and
/// preview cards over the top.
///
/// The page holds no key. It posts `ready` until the view hands it the key
/// and what to show through `appflowySurface.start`. It posts back, as JSON
/// with a `type`:
///
/// * `shown`: the map has drawn what it was last told to show.
/// * `refused`: Google turned the key away (a refused key, a spent daily
///   quota), with Google's reason as `detail`.
/// * `unavailable`: the API could not be loaded, as when offline.
/// * `camera`: where the map came to rest: `lat`, `lng` and `zoom`.
/// * `hover`: the pin under the pointer, as `id` with its point at `x`, `y`
///   in the page, or no `id` once there is none.
/// * `pin`: a pin was clicked, as `id`. `cluster`: a group was, with the
///   `ids` in it.
/// * `point`: the map itself was clicked, at `lat`, `lng`.
/// * `menu`: the map was right-clicked, at `lat`, `lng` and `x`, `y`.
const googleMapSurfaceHtml = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Map</title>
<style>
  html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; -webkit-user-select: none; user-select: none; }
  #map { position: absolute; inset: 0; }
  .af-marker { position: absolute; left: 0; top: 0; cursor: pointer; }
  .af-pin { width: 30px; height: 38px; }
  .af-fall { width: 100%; height: 100%; }
  .af-drop > .af-fall { animation: af-drop 420ms cubic-bezier(0.34, 1.56, 0.64, 1) both; }
  @keyframes af-drop { from { opacity: 0; transform: translateY(-22px); } to { opacity: 1; transform: none; } }
  .af-body { position: relative; width: 100%; height: 100%; box-sizing: border-box; transform-origin: 50% 100%; transition: transform 140ms cubic-bezier(0.215, 0.61, 0.355, 1), opacity 140ms ease, background-color 140ms ease; }
  .af-shape { position: absolute; left: 0; top: 0; overflow: visible; filter: drop-shadow(0 2px 2px var(--af-shadow)); transition: filter 140ms ease; }
  .af-ring { fill: #fff; transition: fill 140ms ease; }
  .af-badge { position: absolute; left: 0; right: 0; top: 6px; height: 15px; display: flex; align-items: center; justify-content: center; color: #fff; font: 700 12.9px/1 Inter, system-ui, sans-serif; text-shadow: 0 1px 1px rgba(0, 0, 0, 0.2); pointer-events: none; }
  .af-badge.af-icon { font-size: 13.8px; font-weight: 400; text-shadow: none; }
  .af-pin.af-lifted .af-body { transform: translateY(-4px); }
  .af-pin.af-lifted .af-shape { filter: drop-shadow(0 4px 4px var(--af-shadow)); }
  .af-pin.af-selected .af-body { transform: scale(1.18); }
  .af-pin.af-selected.af-lifted .af-body { transform: translateY(-4px) scale(1.18); }
  .af-pin.af-selected .af-ring { fill: var(--af-accent); }
  .af-dimmed .af-body { opacity: 0.32; }
  .af-group .af-body { border-radius: 50%; padding: 4px; background-color: var(--af-accent-soft); transform-origin: 50% 50%; }
  .af-group.af-lifted .af-body { background-color: var(--af-accent-softer); }
  .af-core { width: 100%; height: 100%; box-sizing: border-box; border-radius: 50%; border: 1.6px solid #fff; background: var(--af-accent); box-shadow: 0 3px 8px -1px var(--af-shadow); display: flex; align-items: center; justify-content: center; color: #fff; font: 700 12px/1 Inter, system-ui, sans-serif; }
  .af-core.af-big { font-size: 13.5px; }
</style>
</head>
<body>
<div id="map"></div>
<script>
(() => {
  'use strict';

  const post = (message) => {
    try {
      window.webkit.messageHandlers.appflowyLinuxWebViewMessage.postMessage(JSON.stringify(message));
    } catch (_) {
      // Not inside AppFlowy.
    }
  };

  // As the app's own map works them out, so both behave alike.
  const LIMIT = 85.05112878;
  const MIN_ZOOM = 1;
  const MAX_ZOOM = 20;
  const RADIUS = 62;
  const FLY_MS = 560;
  const PIN_W = 30;
  const PIN_H = 38;

  let config = null;
  let library = null;
  let map = null;
  let layer = null;
  let failed = false;

  let pins = [];
  let pinsById = new Map();
  let clustering = true;
  let selected = null;
  let highlighted = null;
  let held = null;
  let hovered = null;
  let hoveredElement = null;
  let picking = false;
  let gesture = null;
  let flight = 0;
  let flightTarget = null;
  let shownPending = false;
  let shownTimer = 0;
  let tracking = 0;
  let gradients = 0;

  const fail = (type, reason) => {
    if (failed) return;
    failed = true;
    post({ type, detail: reason == null ? '' : String(reason) });
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

  const escape = (text) => String(text).replace(/[&<>"']/g, (c) => '&#' + c.charCodeAt(0) + ';');
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const clampZoom = (zoom) => clamp(zoom, MIN_ZOOM, MAX_ZOOM);
  const worldSize = (zoom) => 256 * Math.pow(2, zoom);

  function project(lat, lng) {
    const radians = clamp(lat, -LIMIT, LIMIT) * Math.PI / 180;
    const y = (1 - Math.log(Math.tan(radians) + 1 / Math.cos(radians)) / Math.PI) / 2;
    return { x: (lng + 180) / 360, y: clamp(y, 0, 1) };
  }

  function unproject(x, y) {
    const n = Math.PI * (1 - 2 * clamp(y, 0, 1));
    return {
      lat: clamp(180 / Math.PI * Math.atan(Math.sinh(n)), -LIMIT, LIMIT),
      lng: (x - Math.floor(x)) * 360 - 180,
    };
  }

  function viewSize() {
    const element = document.getElementById('map');
    return { w: element.clientWidth, h: element.clientHeight };
  }

  function cameraNow() {
    const centre = map.getCenter();
    return { lat: centre.lat(), lng: centre.lng(), zoom: map.getZoom() };
  }

  function toScreen(camera, lat, lng) {
    const size = viewSize();
    const world = worldSize(camera.zoom);
    const at = project(lat, lng);
    const middle = project(camera.lat, camera.lng);
    return { x: (at.x - middle.x) * world + size.w / 2, y: (at.y - middle.y) * world + size.h / 2 };
  }

  function toLatLng(camera, x, y) {
    const size = viewSize();
    const world = worldSize(camera.zoom);
    const middle = project(camera.lat, camera.lng);
    return unproject(middle.x + (x - size.w / 2) / world, middle.y + (y - size.h / 2) / world);
  }

  function panned(camera, dx, dy) {
    const world = worldSize(camera.zoom);
    const middle = project(camera.lat, camera.lng);
    const at = unproject(middle.x - dx / world, middle.y - dy / world);
    return { lat: at.lat, lng: at.lng, zoom: camera.zoom };
  }

  // Zooms while holding whatever is under (x, y) still.
  function zoomedAround(camera, zoom, x, y) {
    const clamped = clampZoom(zoom);
    if (x == null || y == null || clamped === camera.zoom) {
      return { lat: camera.lat, lng: camera.lng, zoom: clamped };
    }
    const anchor = toLatLng(camera, x, y);
    const zoomed = { lat: camera.lat, lng: camera.lng, zoom: clamped };
    const at = toScreen(zoomed, anchor.lat, anchor.lng);
    return panned(zoomed, x - at.x, y - at.y);
  }

  function apply(camera) {
    const center = { lat: camera.lat, lng: camera.lng };
    const zoom = clampZoom(camera.zoom);
    if (typeof map.moveCamera === 'function') {
      map.moveCamera({ center, zoom });
    } else {
      map.setCenter(center);
      map.setZoom(zoom);
    }
  }

  function stopFlight() {
    if (flight) cancelAnimationFrame(flight);
    flight = 0;
    flightTarget = null;
  }

  // Moves across the projected world rather than by latitude, so a long
  // journey travels in a straight line on screen.
  function fly(target, animate) {
    stopFlight();
    const to = { lat: target.lat, lng: target.lng, zoom: clampZoom(target.zoom) };
    if (!animate) {
      apply(to);
      return;
    }
    const from = cameraNow();
    const a = project(from.lat, from.lng);
    const b = project(to.lat, to.lng);
    const started = performance.now();
    flightTarget = to;
    const step = (now) => {
      const t = Math.min(1, (now - started) / FLY_MS);
      const eased = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
      const at = unproject(a.x + (b.x - a.x) * eased, a.y + (b.y - a.y) * eased);
      apply({ lat: at.lat, lng: at.lng, zoom: from.zoom + (to.zoom - from.zoom) * eased });
      if (t < 1) {
        flight = requestAnimationFrame(step);
      } else {
        flight = 0;
        flightTarget = null;
      }
    };
    flight = requestAnimationFrame(step);
  }

  // ------------------------------------------------------------- markers

  function clusterDiameter(count) {
    return clamp(34 + Math.log(count) * 7.5, 34, 60);
  }

  // Grouped on a grid fixed to the world rather than to the screen, so the
  // same pins stay together while the map is dragged.
  function clusterPins(camera) {
    const size = viewSize();
    const world = worldSize(camera.zoom);
    const middle = project(camera.lat, camera.lng);
    const cx = middle.x * world;
    const cy = middle.y * world;
    // A view to every side, so a drag finds its pins already there.
    const left = cx - size.w * 1.5 - 160;
    const right = cx + size.w * 1.5 + 160;
    const top = cy - size.h * 1.5 - 160;
    const bottom = cy + size.h * 1.5 + 160;
    const groups = [];
    const cells = new Map();
    for (const pin of pins) {
      const at = project(pin.lat, pin.lng);
      const px = at.x * world;
      const py = at.y * world;
      if (px < left || px > right || py < top || py > bottom) continue;
      const key = clustering
        ? Math.floor(px / RADIUS) + ':' + Math.floor(py / RADIUS)
        : pin.id;
      let group = cells.get(key);
      if (!group) {
        group = { pins: [], x: 0, y: 0 };
        cells.set(key, group);
        groups.push(group);
      }
      group.pins.push(pin);
      group.x += px;
      group.y += py;
    }
    const clusters = groups.map((group) => {
      if (group.pins.length === 1) {
        const pin = group.pins[0];
        return { id: pin.id, lat: pin.lat, lng: pin.lng, pins: group.pins };
      }
      const centre = unproject(group.x / group.pins.length / world, group.y / group.pins.length / world);
      return {
        id: 'cluster:' + group.pins.length + ':' + group.pins[0].id,
        lat: centre.lat,
        lng: centre.lng,
        pins: group.pins,
      };
    });
    // Bigger groups last, so they are drawn over the single pins.
    clusters.sort((a, b) => a.pins.length - b.pins.length);
    return { clusters, zoom: camera.zoom, cx, cy, w: size.w, h: size.h };
  }

  function pinMarkup(pin) {
    const id = 'af-gradient-' + gradients++;
    return '<div class="af-fall"><div class="af-body">' +
      '<svg class="af-shape" width="' + PIN_W + '" height="' + PIN_H + '" viewBox="0 0 30 38" aria-hidden="true">' +
      '<defs><linearGradient id="' + id + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="' + escape(pin.fillTop) + '"/>' +
      '<stop offset="1" stop-color="' + escape(pin.fill) + '"/></linearGradient></defs>' +
      '<rect class="af-ring" width="30" height="31" rx="11"/>' +
      '<path class="af-ring" d="M9.5 30 L15 38 L20.5 30 Z"/>' +
      '<rect x="2" y="2" width="26" height="27" rx="9" fill="url(#' + id + ')"/>' +
      '<path d="M11.4 29 L15 34.8 L18.6 29 Z" fill="' + escape(pin.fill) + '"/></svg>' +
      '<span class="af-badge' + (pin.icon ? ' af-icon' : '') + '">' + escape(pin.badge) + '</span>' +
      '</div></div>';
  }

  function groupMarkup(count) {
    const side = clusterDiameter(count);
    return '<div class="af-fall"><div class="af-body" style="width:' + side + 'px;height:' + side + 'px">' +
      '<div class="af-core' + (side < 40 ? '' : ' af-big') + '">' + (count > 999 ? '999+' : count) + '</div>' +
      '</div></div>';
  }

  function signatureOf(cluster) {
    if (cluster.pins.length > 1) return 'g' + cluster.pins.length;
    const pin = cluster.pins[0];
    return 'p' + pin.fill + '|' + pin.fillTop + '|' + pin.badge + '|' + (pin.icon ? 1 : 0);
  }

  function layerClass(OverlayView) {
    return class Layer extends OverlayView {
      constructor() {
        super();
        this.root = null;
        this.elements = new Map();
        this.grouping = null;
        this.dirty = true;
      }

      onAdd() {
        const root = document.createElement('div');
        root.style.position = 'absolute';
        root.style.left = '0';
        root.style.top = '0';
        this.root = root;
        this.getPanes().overlayMouseTarget.append(root);
      }

      // Called by Google whenever the view changes.
      draw() {
        const projection = this.getProjection();
        if (!projection || !this.root || !map) return;
        const camera = cameraNow();
        const grouping = this.grouping;
        const size = viewSize();
        const world = worldSize(camera.zoom);
        const middle = project(camera.lat, camera.lng);
        if (this.dirty || !grouping || grouping.zoom !== camera.zoom ||
            grouping.w !== size.w || grouping.h !== size.h ||
            Math.abs(middle.x * world - grouping.cx) > size.w ||
            Math.abs(middle.y * world - grouping.cy) > size.h) {
          this.dirty = false;
          this.regroup(camera);
        }
        for (const element of this.elements.values()) {
          const cluster = element.afCluster;
          const at = projection.fromLatLngToDivPixel(new google.maps.LatLng(cluster.lat, cluster.lng));
          if (!at) continue;
          const single = cluster.pins.length === 1;
          const side = single ? 0 : clusterDiameter(cluster.pins.length);
          const x = single ? at.x - PIN_W / 2 : at.x - side / 2;
          const y = single ? at.y - PIN_H : at.y - side / 2;
          element.style.transform = 'translate(' + x + 'px,' + y + 'px)';
        }
        scheduleTrack();
      }

      regroup(camera) {
        this.grouping = clusterPins(camera);
        const keep = new Set();
        this.grouping.clusters.forEach((cluster, index) => {
          keep.add(cluster.id);
          let element = this.elements.get(cluster.id);
          const signature = signatureOf(cluster);
          if (!element) {
            element = makeElement(cluster);
            element.afSignature = signature;
            this.elements.set(cluster.id, element);
            this.root.append(element);
          } else if (element.afSignature !== signature) {
            element.afSignature = signature;
            element.innerHTML = cluster.pins.length === 1
              ? pinMarkup(cluster.pins[0])
              : groupMarkup(cluster.pins.length);
          }
          element.afCluster = cluster;
          element.afOrder = index;
        });
        for (const [id, element] of this.elements) {
          if (keep.has(id)) continue;
          if (element === hoveredElement) leave(element);
          element.remove();
          this.elements.delete(id);
        }
        restyle();
      }

      refresh() {
        this.dirty = true;
        this.draw();
      }

      onRemove() {
        if (this.root) this.root.remove();
        this.root = null;
        this.elements.clear();
      }
    };
  }

  function makeElement(cluster) {
    const single = cluster.pins.length === 1;
    const element = document.createElement('div');
    element.className = 'af-marker af-drop ' + (single ? 'af-pin' : 'af-group');
    element.innerHTML = single ? pinMarkup(cluster.pins[0]) : groupMarkup(cluster.pins.length);
    element.addEventListener('animationend', () => element.classList.remove('af-drop'), { once: true });
    element.addEventListener('mouseenter', () => enter(element));
    element.addEventListener('mouseleave', () => leave(element));
    element.addEventListener('click', (event) => {
      event.stopPropagation();
      const target = element.afCluster;
      if (target.pins.length === 1) {
        post({ type: 'pin', id: target.id });
      } else {
        post({ type: 'cluster', ids: target.pins.map((pin) => pin.id) });
      }
    });
    element.addEventListener('contextmenu', (event) => {
      event.preventDefault();
      event.stopPropagation();
      menuAt(event.clientX, event.clientY);
    });
    library.OverlayView.preventMapHitsAndGesturesFrom(element);
    return element;
  }

  function restyle() {
    if (!layer) return;
    for (const element of layer.elements.values()) {
      const cluster = element.afCluster;
      const single = cluster.pins.length === 1;
      const isSelected = single && selected != null && cluster.id === selected;
      const lifted = element === hoveredElement || (single && held != null && cluster.id === held);
      const dimmed = highlighted != null && !cluster.pins.some((pin) => highlighted.has(pin.id));
      element.classList.toggle('af-selected', isSelected);
      element.classList.toggle('af-lifted', lifted);
      element.classList.toggle('af-dimmed', dimmed);
      element.style.zIndex = String(lifted ? 1000002 : isSelected ? 1000001 : element.afOrder + 1);
    }
  }

  function enter(element) {
    hoveredElement = element;
    const cluster = element.afCluster;
    hovered = cluster.pins.length === 1 ? cluster.id : null;
    restyle();
    if (hovered) {
      reportHover();
    } else {
      post({ type: 'hover' });
    }
  }

  function leave(element) {
    if (hoveredElement !== element) return;
    hoveredElement = null;
    const was = hovered;
    hovered = null;
    restyle();
    if (was) post({ type: 'hover' });
  }

  function reportHover() {
    const pin = hovered && pinsById.get(hovered);
    const projection = layer && layer.getProjection();
    if (!pin || !projection) return;
    const at = projection.fromLatLngToContainerPixel(new google.maps.LatLng(pin.lat, pin.lng));
    if (at) post({ type: 'hover', id: pin.id, x: at.x, y: at.y });
  }

  // A preview card follows its pin while the map moves under it.
  function scheduleTrack() {
    if (!hovered || tracking) return;
    tracking = requestAnimationFrame(() => {
      tracking = 0;
      reportHover();
    });
  }

  function menuAt(x, y) {
    if (!map) return;
    const at = toLatLng(cameraNow(), x, y);
    post({ type: 'menu', lat: at.lat, lng: at.lng, x, y });
  }

  // ----------------------------------------------------------------- state

  function setPins(list) {
    pins = Array.isArray(list) ? list : [];
    pinsById = new Map(pins.map((pin) => [pin.id, pin]));
    if (hovered && !pinsById.has(hovered)) {
      hovered = null;
      post({ type: 'hover' });
    }
    if (layer) layer.refresh();
  }

  function setLook(look) {
    config.look = look;
    const style = document.documentElement.style;
    style.setProperty('--af-accent', look.accent);
    style.setProperty('--af-accent-soft', look.accentSoft);
    style.setProperty('--af-accent-softer', look.accentSofter);
    style.setProperty('--af-shadow', look.shadow);
    if (map) map.setOptions({ styles: look.styles, mapTypeId: look.mapType });
  }

  function setPicking(on) {
    picking = !!on;
    if (map) map.setOptions({ draggableCursor: picking ? 'crosshair' : null });
  }

  function configure(next) {
    clustering = next.clustering !== false;
    selected = next.selected == null ? null : next.selected;
    highlighted = Array.isArray(next.highlighted) ? new Set(next.highlighted) : null;
    held = next.held == null ? null : next.held;
    setLook(next.look);
    setPicking(next.picking);
    setPins(next.pins);
  }

  function markShown() {
    if (!shownPending) return;
    shownPending = false;
    clearTimeout(shownTimer);
    post({ type: 'shown' });
  }

  async function create() {
    library = await google.maps.importLibrary('maps');
    if (failed) return;
    const camera = config.camera;
    const look = config.look;
    map = new library.Map(document.getElementById('map'), {
      center: { lat: camera.lat, lng: camera.lng },
      zoom: clampZoom(camera.zoom),
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
      isFractionalZoomEnabled: true,
      mapTypeId: look.mapType,
      styles: look.styles,
      backgroundColor: look.background,
      disableDefaultUI: true,
      gestureHandling: 'greedy',
      keyboardShortcuts: true,
      clickableIcons: false,
      draggableCursor: picking ? 'crosshair' : null,
    });
    map.addListener('tilesloaded', markShown);
    map.addListener('idle', () => {
      const camera = cameraNow();
      post({ type: 'camera', lat: camera.lat, lng: camera.lng, zoom: camera.zoom });
      if (shownPending) {
        // Nothing new to load still counts as drawn.
        clearTimeout(shownTimer);
        shownTimer = setTimeout(markShown, 800);
      }
    });
    map.addListener('dragstart', stopFlight);
    map.addListener('click', (event) => {
      if (event.latLng) post({ type: 'point', lat: event.latLng.lat(), lng: event.latLng.lng() });
    });
    map.addListener('contextmenu', (event) => {
      const dom = event.domEvent;
      if (dom && typeof dom.clientX === 'number') {
        if (typeof dom.preventDefault === 'function') dom.preventDefault();
        menuAt(dom.clientX, dom.clientY);
      } else if (event.latLng && layer && layer.getProjection()) {
        const at = layer.getProjection().fromLatLngToContainerPixel(event.latLng);
        if (at) menuAt(at.x, at.y);
      }
    });
    const Layer = layerClass(library.OverlayView);
    layer = new Layer();
    layer.setMap(map);
  }

  window.appflowySurface = {
    start(next) {
      if (config) return;
      config = next;
      shownPending = true;
      configure(next);
      window.appflowySurfaceLoaded = () => {
        create().catch((error) => fail('unavailable', (error && error.message) || error));
      };
      const query = new URLSearchParams({
        key: config.key,
        v: 'weekly',
        loading: 'async',
        callback: 'appflowySurfaceLoaded',
      });
      if (config.language) query.set('language', config.language);
      const script = document.createElement('script');
      script.src = 'https://maps.googleapis.com/maps/api/js?' + query.toString();
      script.async = true;
      script.onerror = () => fail('unavailable', 'The Maps JavaScript API could not be loaded.');
      document.head.append(script);
    },

    // Shows something else on a map that is already loaded, as when a pooled
    // page is handed to another view: loading again would count against the
    // key's daily quota.
    show(next) {
      if (!config) {
        this.start(next);
        return;
      }
      stopFlight();
      gesture = null;
      hovered = null;
      hoveredElement = null;
      config.camera = next.camera;
      shownPending = true;
      configure(next);
      if (map) {
        apply(next.camera);
        clearTimeout(shownTimer);
        shownTimer = setTimeout(markShown, 800);
      }
    },

    park() {
      stopFlight();
      gesture = null;
      hovered = null;
      hoveredElement = null;
      held = null;
      highlighted = null;
      selected = null;
      setPins([]);
    },

    setPins,
    setLook(look) { if (config) setLook(look); },
    setPicking,
    setSelected(id) { selected = id == null ? null : id; restyle(); },
    setHighlighted(ids) { highlighted = Array.isArray(ids) ? new Set(ids) : null; restyle(); },
    setHeld(id) { held = id == null ? null : id; restyle(); },
    setClustering(on) {
      clustering = on !== false;
      if (layer) layer.refresh();
    },

    fly(lat, lng, zoom, animate) {
      if (!map) {
        if (config) config.camera = { lat, lng, zoom };
        return;
      }
      fly({ lat, lng, zoom }, animate !== false);
    },

    zoomBy(delta) {
      if (!map) return;
      const base = flightTarget || cameraNow();
      fly(zoomedAround(base, base.zoom + delta), true);
    },

    wheel(delta, x, y) {
      if (!map || gesture) return;
      stopFlight();
      const camera = cameraNow();
      apply(zoomedAround(camera, camera.zoom + delta, x, y));
    },

    // Every frame of a pinch is worked out from the view it started with.
    // A gesture is a zoom or a drag, never a blend of the two.
    gestureStart(x, y) {
      if (!map) return;
      stopFlight();
      const size = viewSize();
      gesture = { start: cameraNow(), x: clamp(x, 0, size.w), y: clamp(y, 0, size.h) };
    },

    gesture(scale, dx, dy) {
      if (!map || !gesture) return;
      const start = gesture.start;
      if (Math.abs(scale - 1) > 0.008) {
        apply(zoomedAround(start, start.zoom + Math.log2(scale), gesture.x, gesture.y));
      } else {
        apply(panned(start, dx, dy));
      }
    },

    gestureEnd() {
      gesture = null;
    },
  };

  // Said again until the app answers, in case it was not yet listening.
  let announced = 0;
  const announce = () => {
    if (config || announced++ >= 50) return;
    post({ type: 'ready' });
    setTimeout(announce, 300);
  };
  announce();
})();
</script>
</body>
</html>
''';

/// A call to the page's `appflowySurface`, with [arguments] as JSON.
String googleMapSurfaceCall(
  String method, [
  List<Object?> arguments = const [],
]) =>
    'window.appflowySurface && window.appflowySurface.$method('
    '${arguments.map(jsonEncode).join(',')});';

/// How the map looks: Google's map styled for [style], and the marker colours
/// of [palette].
Map<String, Object?> googleMapSurfaceLook(
  MapPalette palette,
  MapStyleName style,
) =>
    {
      'name': style.name,
      'styles': googleMapsStylesFor(style),
      'mapType': style == MapStyleName.satellite ? 'hybrid' : 'roadmap',
      'background': googleMapsHex(palette.canvas),
      'accent': googleMapsHex(palette.accent),
      'accentSoft': _rgba(palette.accent, 0.24),
      'accentSofter': _rgba(palette.accent, 0.32),
      'shadow': _rgba(palette.shadow, palette.isDark ? 0.55 : 0.28),
    };

/// The pins as the page draws them, coloured as the app's own map colours
/// them.
List<Map<String, Object?>> googleMapSurfacePins(
  Iterable<AppMapPin> pins,
  MapPalette palette,
) =>
    [
      for (final pin in pins)
        if (pin.point.isValid) _pin(pin, palette),
    ];

Map<String, Object?> _pin(AppMapPin pin, MapPalette palette) {
  final fill = pin.color ??
      palette.swatchFor(pin.status.isNotEmpty ? pin.status : pin.title);
  final icon = pin.icon;
  final hasIcon = icon != null && icon.isNotEmpty;
  return {
    'id': pin.id,
    'lat': pin.point.latitude,
    'lng': pin.point.longitude,
    'fill': googleMapsHex(fill),
    'fillTop': googleMapsHex(Color.lerp(fill, const Color(0xFFFFFFFF), 0.16)!),
    'badge': hasIcon ? icon : _initial(pin.title),
    'icon': hasIcon,
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

String _rgba(Color color, double alpha) {
  int channel(double value) => (value * 255).round().clamp(0, 255);
  return 'rgba(${channel(color.r)}, ${channel(color.g)}, ${channel(color.b)}, '
      '$alpha)';
}
