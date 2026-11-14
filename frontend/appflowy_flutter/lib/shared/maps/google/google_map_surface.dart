import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/maps/google/google_map_surface_page.dart';
import 'package:appflowy/shared/maps/google/google_maps_pages.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:appflowy_linux_webview/appflowy_linux_webview.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Moves a [GoogleMapSurface] for the map that hosts it.
class GoogleMapSurfaceController {
  _GoogleMapSurfaceState? _surface;

  /// Takes the map to [camera]'s centre and zoom.
  void fly(MapCamera camera, {bool animate = true}) =>
      _surface?._fly(camera, animate: animate);

  /// Zooms in or out about the middle of the map.
  void zoomBy(double delta) => _surface?._zoomBy(delta);
}

/// Google's own map under the application's map chrome, drawn by the Maps
/// JavaScript API in a web view ([googleMapSurfaceHtml]).
///
/// The app's map shows this when a Google key is configured but Google will
/// not hand the app its map tiles, as with a Maps Demo Key. The host keeps
/// its own controls, search and preview cards; the pins are drawn by the page
/// so they never lag behind the map. [onFailed] is told when Google turns the
/// key away, cannot be reached or does not draw within [deadline], for the
/// host to draw its own map instead.
class GoogleMapSurface extends StatefulWidget {
  const GoogleMapSurface({
    super.key,
    required this.apiKey,
    required this.controller,
    required this.camera,
    required this.pins,
    required this.style,
    required this.onCamera,
    required this.onHover,
    required this.onPinTap,
    required this.onClusterTap,
    required this.onFailed,
    this.clustering = true,
    this.selectedPinId,
    this.highlightedPinIds,
    this.heldPinId,
    this.onPointTap,
    this.onContextMenu,
  });

  final String apiKey;
  final GoogleMapSurfaceController controller;

  /// Where the map looks when it starts.
  final MapCamera camera;
  final List<AppMapPin> pins;
  final MapStyleName style;
  final bool clustering;
  final String? selectedPinId;

  /// Pins that matched a search; everything else is faded back.
  final Set<String>? highlightedPinIds;

  /// A pin kept lifted, as while its preview card is being read.
  final String? heldPinId;

  /// Where the map came to rest.
  final void Function(LatLng center, double zoom) onCamera;

  /// The pin under the pointer and where its point is, or nulls once there is
  /// none.
  final void Function(String? pinId, Offset? at) onHover;
  final ValueChanged<String> onPinTap;

  /// A group of pins was clicked.
  final ValueChanged<List<String>> onClusterTap;
  final ValueChanged<GoogleMapsFailure> onFailed;

  /// Where a plain click landed. Set while a click picks a place, which the
  /// map shows with a crosshair.
  final ValueChanged<LatLng>? onPointTap;
  final void Function(Offset globalPosition, LatLng point)? onContextMenu;

  /// How long Google's map may take to draw before the app's own is shown.
  static const Duration deadline = Duration(seconds: 30);

  /// Stands in for the Linux web view, so tests reach Google's map anywhere.
  @visibleForTesting
  static GoogleMapsPages? debugPages;

  static final GoogleMapsPages _linux =
      GoogleMapsPages.linux(name: 'surface.html', html: googleMapSurfaceHtml);

  static GoogleMapsPages get _pages => debugPages ?? _linux;

  static GoogleMapsPages? _checked;
  static bool? _supported;
  static Future<bool>? _checking;

  /// Finds out whether Google's map can be drawn here. [canDraw] knows once
  /// this has completed.
  static Future<bool> checkSupport() {
    final pages = _pages;
    if (!identical(pages, _checked)) {
      _checked = pages;
      _supported = null;
      _checking = null;
    }
    return _checking ??= () async {
      var supported = false;
      try {
        supported = await pages.isSupported();
      } on Object {
        supported = false;
      }
      if (identical(pages, _checked)) {
        _supported = supported;
      }
      return supported;
    }();
  }

  /// Whether Google's map is known to be drawable here with [apiKey].
  static bool canDraw(String apiKey) =>
      apiKey.isNotEmpty &&
      identical(_pages, _checked) &&
      _supported == true &&
      !GoogleMapsRefusals.isRefused(apiKey);

  /// Forgets what was found out, and closes the pages kept for reuse.
  @visibleForTesting
  static void debugReset() {
    _checked = null;
    _supported = null;
    _checking = null;
    _SurfacePool.instance.clear();
  }

  @override
  State<GoogleMapSurface> createState() => _GoogleMapSurfaceState();
}

class _GoogleMapSurfaceState extends State<GoogleMapSurface> {
  static const _trackpad = LinuxWebViewTrackpad(onUpdate: _keepPan);

  // Two-finger pans move the map through [_onPanZoomUpdate], never the page.
  static Offset _keepPan(Offset _) => Offset.zero;

  _SurfacePage? _page;
  StreamSubscription<String>? _messages;
  Timer? _deadline;
  MapPalette? _palette;
  String? _language;
  bool _opened = false;

  /// Whether the page has been told what to show.
  bool _started = false;
  bool _shown = false;

  /// Whether the cover is still over the page: until it has faded out after
  /// the map drew.
  bool _covered = true;
  bool _failed = false;
  bool _closed = false;

  /// Where to look, when asked before the page was told what to show.
  MapCamera? _target;

  /// How far the fingers have moved since the two-finger gesture began.
  Offset _gesturePan = Offset.zero;

  Map<String, Object?> _look = const {};
  String _lookSent = '';
  List<Map<String, Object?>> _pins = const [];
  String _pinsSent = '[]';

  @override
  void initState() {
    super.initState();
    widget.controller._surface = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _palette = mapPaletteOf(context);
    _language = Localizations.maybeLocaleOf(context)?.languageCode;
    // Pins take their colours from the palette as well.
    _sendLook();
    _sendPins();
    if (!_opened) {
      _opened = true;
      _open();
    }
  }

  @override
  void didUpdateWidget(GoogleMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      if (identical(oldWidget.controller._surface, this)) {
        oldWidget.controller._surface = null;
      }
      widget.controller._surface = this;
    }
    if (oldWidget.style != widget.style) {
      _sendLook();
    }
    if (!identical(oldWidget.pins, widget.pins)) {
      _sendPins();
    }
    if (oldWidget.clustering != widget.clustering) {
      _call('setClustering', [widget.clustering]);
    }
    if (oldWidget.selectedPinId != widget.selectedPinId) {
      _call('setSelected', [widget.selectedPinId]);
    }
    if (!setEquals(oldWidget.highlightedPinIds, widget.highlightedPinIds)) {
      _call('setHighlighted', [widget.highlightedPinIds?.toList()]);
    }
    if (oldWidget.heldPinId != widget.heldPinId) {
      _call('setHeld', [widget.heldPinId]);
    }
    if ((oldWidget.onPointTap == null) != (widget.onPointTap == null)) {
      _call('setPicking', [widget.onPointTap != null]);
    }
  }

  @override
  void dispose() {
    _closed = true;
    if (identical(widget.controller._surface, this)) {
      widget.controller._surface = null;
    }
    _deadline?.cancel();
    unawaited(_messages?.cancel());
    final page = _page;
    _page = null;
    if (page != null) {
      if (!_failed && page.hasMap) {
        _SurfacePool.instance.park(page);
      } else {
        unawaited(page.page.dispose());
      }
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ page

  void _open() {
    final pages = GoogleMapSurface._pages;
    final pooled = _SurfacePool.instance.take(widget.apiKey, pages);
    if (pooled != null) {
      // Google's map is already loaded in it; showing something else there
      // costs nothing against the key's daily quota.
      _attach(pooled);
      _started = true;
      _run(googleMapSurfaceCall('show', [_config()]));
      return;
    }
    unawaited(_create(pages));
  }

  Future<void> _create(GoogleMapsPages pages) async {
    try {
      final url = await pages.address();
      final page = await pages.open(url);
      if (!mounted || _closed) {
        await page.dispose();
        return;
      }
      setState(
        () => _attach(
          _SurfacePage(page, apiKey: widget.apiKey, pages: pages),
        ),
      );
    } on Object catch (error) {
      _fail(GoogleMapsFailure('$error', refused: false));
    }
  }

  void _attach(_SurfacePage page) {
    _page = page;
    _messages = page.page.messages.listen(_onMessage);
    _deadline?.cancel();
    _deadline = Timer(GoogleMapSurface.deadline, () {
      if (!_shown) {
        _fail(const GoogleMapsFailure('timeout', refused: false));
      }
    });
  }

  void _fail(GoogleMapsFailure failure) {
    if (!mounted || _closed || _failed) {
      return;
    }
    _failed = true;
    _deadline?.cancel();
    widget.onFailed(failure);
  }

  Map<String, Object?> _config() {
    final camera = _target ?? widget.camera;
    final language = _language;
    return {
      'key': widget.apiKey,
      if (language != null && language.isNotEmpty) 'language': language,
      'camera': {
        'lat': camera.center.latitude,
        'lng': camera.center.longitude,
        'zoom': camera.zoom,
      },
      'look': _look,
      'pins': _pins,
      'clustering': widget.clustering,
      'selected': widget.selectedPinId,
      'highlighted': widget.highlightedPinIds?.toList(),
      'held': widget.heldPinId,
      'picking': widget.onPointTap != null,
    };
  }

  void _sendLook() {
    final palette = _palette;
    if (palette == null) {
      return;
    }
    final look = googleMapSurfaceLook(palette, widget.style);
    final encoded = jsonEncode(look);
    if (encoded == _lookSent) {
      return;
    }
    _look = look;
    _lookSent = encoded;
    _run('window.appflowySurface && window.appflowySurface.setLook($encoded);');
  }

  void _sendPins() {
    final palette = _palette;
    if (palette == null) {
      return;
    }
    // Hosts hand over a new list on every build; only a real change is sent.
    final pins = googleMapSurfacePins(widget.pins, palette);
    final encoded = jsonEncode(pins);
    if (encoded == _pinsSent) {
      return;
    }
    _pins = pins;
    _pinsSent = encoded;
    _run('window.appflowySurface && window.appflowySurface.setPins($encoded);');
  }

  void _call(String method, [List<Object?> arguments = const []]) =>
      _run(googleMapSurfaceCall(method, arguments));

  void _run(String script) {
    final page = _page;
    if (_started && !_closed && page != null) {
      unawaited(page.page.run(script));
    }
  }

  // -------------------------------------------------------------- commands

  void _fly(MapCamera camera, {required bool animate}) {
    if (!_started) {
      _target = camera;
      return;
    }
    _call('fly', [
      camera.center.latitude,
      camera.center.longitude,
      camera.zoom,
      animate,
    ]);
  }

  void _zoomBy(double delta) => _call('zoomBy', [delta]);

  // -------------------------------------------------------------- messages

  void _onMessage(String text) {
    if (!mounted || _closed) {
      return;
    }
    final Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (message is! Map) {
      return;
    }
    switch (message['type']) {
      case 'ready':
        // Also after the web process restarted and loaded the page again.
        _started = true;
        _page?.hasMap = false;
        _run(googleMapSurfaceCall('start', [_config()]));
      case 'shown':
        _deadline?.cancel();
        _page?.hasMap = true;
        if (!_shown) {
          setState(() => _shown = true);
        }
      case 'refused':
        _fail(GoogleMapsFailure(_textOf(message['detail']), refused: true));
      case 'unavailable':
        _fail(GoogleMapsFailure(_textOf(message['detail']), refused: false));
      case 'camera':
        final point = _pointOf(message);
        final zoom = _numberOf(message['zoom']);
        if (point != null && zoom != null) {
          widget.onCamera(point, zoom);
        }
      case 'hover':
        final id = message['id'];
        final x = _numberOf(message['x']);
        final y = _numberOf(message['y']);
        if (id is String && x != null && y != null) {
          widget.onHover(id, Offset(x, y));
        } else {
          widget.onHover(null, null);
        }
      case 'pin':
        final id = message['id'];
        if (id is String) {
          widget.onPinTap(id);
        }
      case 'cluster':
        final ids = message['ids'];
        if (ids is List) {
          widget.onClusterTap(ids.whereType<String>().toList());
        }
      case 'point':
        final point = _pointOf(message);
        if (point != null) {
          widget.onPointTap?.call(point);
        }
      case 'menu':
        final point = _pointOf(message);
        final x = _numberOf(message['x']);
        final y = _numberOf(message['y']);
        final box = context.findRenderObject();
        if (point != null &&
            x != null &&
            y != null &&
            box is RenderBox &&
            box.hasSize) {
          widget.onContextMenu?.call(box.localToGlobal(Offset(x, y)), point);
        }
    }
  }

  static String _textOf(Object? value) => value is String ? value : '';

  static double? _numberOf(Object? value) {
    final number = value is num ? value.toDouble() : null;
    return number != null && number.isFinite ? number : null;
  }

  static LatLng? _pointOf(Map message) {
    final lat = _numberOf(message['lat']);
    final lng = _numberOf(message['lng']);
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  // ----------------------------------------------------------------- input

  /// A wheel zooms about the pointer, a quarter of a zoom level a notch, as
  /// the app's own map does; nothing of it scrolls the page.
  Offset _onWheel(PointerScrollEvent event) {
    final dy = event.scrollDelta.dy;
    if (dy.isFinite && dy != 0) {
      _call('wheel', [
        -dy / 120 * 0.42,
        event.localPosition.dx,
        event.localPosition.dy,
      ]);
    }
    return Offset.zero;
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _gesturePan = Offset.zero;
    _call('gestureStart', [event.localPosition.dx, event.localPosition.dy]);
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    // Summed from the deltas: Flutter maps a pan's total into the view as if
    // it were a position, which shifts it by wherever the map sits.
    final pan = _gesturePan + event.localPanDelta;
    if (!event.scale.isFinite || !pan.isFinite) {
      return;
    }
    _gesturePan = pan;
    _call('gesture', [event.scale, pan.dx, pan.dy]);
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) => _call('gestureEnd');

  @override
  Widget build(BuildContext context) {
    final palette = _palette ?? mapPaletteOf(context);
    final page = _page;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: palette.canvas)),
        if (page != null)
          Positioned.fill(
            child: Listener(
              onPointerPanZoomStart: _onPanZoomStart,
              onPointerPanZoomUpdate: _onPanZoomUpdate,
              onPointerPanZoomEnd: _onPanZoomEnd,
              child: LinuxWebViewScrollScope(
                transform: _onWheel,
                trackpad: _trackpad,
                child: page.page.build(context),
              ),
            ),
          ),
        if (_covered)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _shown,
              child: AnimatedOpacity(
                opacity: _shown ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                onEnd: () {
                  if (mounted && _shown) {
                    setState(() => _covered = false);
                  }
                },
                child: ColoredBox(color: palette.canvas),
              ),
            ),
          ),
      ],
    );
  }
}

/// A page and what has been drawn in it.
class _SurfacePage {
  _SurfacePage(this.page, {required this.apiKey, required this.pages});

  final GoogleMapsPage page;
  final String apiKey;
  final GoogleMapsPages pages;

  /// Whether Google's map has drawn in it, so it can show something else
  /// without loading again.
  bool hasMap = false;
}

/// Pages with Google's map already loaded, kept a while for the next map.
///
/// A Maps Demo Key allows a hundred map loads a day and every new page is a
/// load, so switching between a table's views or reopening a document would
/// spend them within the hour. A page put aside is shown again instead.
class _SurfacePool {
  _SurfacePool._();

  static final _SurfacePool instance = _SurfacePool._();

  static const _capacity = 2;
  static const _keepFor = Duration(minutes: 3);

  final Map<_SurfacePage, Timer> _idle = {};

  _SurfacePage? take(String apiKey, GoogleMapsPages pages) {
    final found = _idle.keys.firstWhereOrNull(
      (page) => page.apiKey == apiKey && identical(page.pages, pages),
    );
    if (found != null) {
      _idle.remove(found)?.cancel();
    }
    return found;
  }

  void park(_SurfacePage page) {
    unawaited(page.page.run(googleMapSurfaceCall('park')));
    _idle[page] = Timer(_keepFor, () => _drop(page));
    while (_idle.length > _capacity) {
      _drop(_idle.keys.first);
    }
  }

  void _drop(_SurfacePage page) {
    _idle.remove(page)?.cancel();
    unawaited(page.page.dispose());
  }

  void clear() {
    for (final page in _idle.keys.toList()) {
      _drop(page);
    }
  }
}
