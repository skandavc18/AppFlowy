import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/shared/maps/app_location_popup.dart';
import 'package:appflowy/shared/maps/app_map_marker.dart';
import 'package:appflowy/shared/maps/app_map_toolbar.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/shared/maps/map_tile_cache.dart';
import 'package:appflowy/shared/maps/map_tile_layer.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Drives a map from outside it.
///
/// The view owns the camera; this is how a host asks it to move, so a table
/// can frame its rows or a block can be sent to a saved place.
class AppMapController extends ChangeNotifier {
  _AppMapViewState? _view;

  MapCamera? get camera => _view?._camera;

  void moveTo(LatLng center, {double? zoom, bool animate = true}) =>
      _view?._moveTo(center, zoom: zoom, animate: animate);

  void fit(LatLngBounds bounds, {bool animate = true}) =>
      _view?._fit(bounds, animate: animate);

  void zoomBy(double delta) => _view?._zoomBy(delta);

  /// Frames everything on the map again.
  void resetView() => _view?._resetView();

  @override
  void dispose() {
    _view = null;
    super.dispose();
  }
}

/// Where the map was left, so a host can put it back.
@immutable
class MapViewport {
  const MapViewport({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;
}

/// A live, interactive map drawn by the application itself.
///
/// Everything here is Flutter: the basemap is painted from tiles onto the
/// canvas and the markers are widgets, so it runs on every platform the app
/// runs on — including Windows, where no Google Maps SDK exists — and animates
/// at the display's own rate because nothing is crossing a platform boundary.
class AppMapView extends StatefulWidget {
  const AppMapView({
    super.key,
    this.pins = const [],
    this.controller,
    this.provider = MapProviderKind.google,
    this.apiKey = '',
    this.style,
    this.clustering = true,
    this.initialCenter,
    this.initialZoom,
    this.selectedPinId,
    this.highlightedPinIds,
    this.onPinTap,
    this.onPinHover,
    this.onViewportChanged,
    this.onContextMenu,
    this.onPointTap,
    this.onSearch,
    this.onSuggestPins,
    this.showControls = true,
    this.showSearch = false,
    this.showPopup = true,
    this.onFullscreen,
    this.isFullscreen = false,
    this.searchHint = 'Search this map',
    this.emptyHint = '',
    this.onEmptyHintTap,
    this.padding = EdgeInsets.zero,
    this.autoFit = true,
  });

  final List<AppMapPin> pins;
  final AppMapController? controller;
  final MapProviderKind provider;
  final String apiKey;

  /// The basemap to draw. Null follows the application's appearance.
  final MapStyleName? style;

  final bool clustering;
  final LatLng? initialCenter;
  final double? initialZoom;
  final String? selectedPinId;

  /// Pins that matched a search; everything else is faded back.
  final Set<String>? highlightedPinIds;

  final ValueChanged<AppMapPin>? onPinTap;
  final ValueChanged<AppMapPin?>? onPinHover;
  final ValueChanged<MapViewport>? onViewportChanged;
  final void Function(Offset globalPosition, LatLng point)? onContextMenu;

  /// Where on the earth a plain click landed.
  final ValueChanged<LatLng>? onPointTap;

  final Future<LatLng?> Function(String query)? onSearch;

  /// Rows already on the map that match what is being typed in the search box.
  final List<MapSuggestion> Function(String query)? onSuggestPins;

  final bool showControls;
  final bool showSearch;
  final bool showPopup;
  final VoidCallback? onFullscreen;
  final bool isFullscreen;
  final String searchHint;

  /// Shown over the middle when there is nothing to plot.
  final String emptyHint;

  /// Makes that hint the way out of whatever is missing.
  final VoidCallback? onEmptyHintTap;

  /// Keeps the controls clear of a host's own chrome.
  final EdgeInsets padding;

  /// Frames the pins the first time they arrive.
  final bool autoFit;

  @override
  State<AppMapView> createState() => _AppMapViewState();
}

class _AppMapViewState extends State<AppMapView> with TickerProviderStateMixin {
  static const _defaultCenter = LatLng(25, 5);
  static const _defaultZoom = 2.4;

  late MapCamera _camera = MapCamera(
    center: widget.initialCenter ?? _defaultCenter,
    zoom: widget.initialZoom ?? _defaultZoom,
    size: Size.zero,
  );

  final MapTileCache _cache = MapTileCache();
  final FocusNode _focus = FocusNode(debugLabel: 'AppMapView');

  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: MapMetrics.fly,
  )..addListener(_onFly);

  MapCamera? _flyFrom;
  MapCamera? _flyTo;

  List<MapCluster> _clusters = const [];
  MapCluster? _hovered;
  Timer? _hoverOut;
  bool _pointerOnPopup = false;
  bool _searching = false;
  bool _fitted = false;
  Offset? _doubleTapAt;
  Offset? _tappedAt;

  /// The camera and the anchor as the current pinch began.
  MapCamera? _gestureCamera;
  Offset _gestureFocus = Offset.zero;

  MapTileProvider? _provider;
  MapStyleName _style = MapStyleName.light;

  @override
  void initState() {
    super.initState();
    widget.controller?._view = this;
  }

  @override
  void didUpdateWidget(AppMapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._view = null;
      widget.controller?._view = this;
    }
    if (old.provider != widget.provider || old.apiKey != widget.apiKey) {
      _provider = null;
    }
    if (!identical(old.pins, widget.pins) &&
        old.pins.length != widget.pins.length) {
      // New rows arriving should be framed, but only the first time — after
      // that the person's own view is the one that matters.
      if (!_fitted && widget.autoFit) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _resetView());
      }
    }
  }

  @override
  void dispose() {
    widget.controller?._view = null;
    _hoverOut?.cancel();
    _fly.dispose();
    _cache.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- movement

  void _apply(MapCamera camera, {bool notify = true}) {
    if (camera == _camera) {
      return;
    }
    setState(() => _camera = camera);
    if (notify) {
      widget.onViewportChanged?.call(
        MapViewport(center: camera.center, zoom: camera.zoom),
      );
    }
  }

  void _onFly() {
    final from = _flyFrom;
    final to = _flyTo;
    if (from == null || to == null) {
      return;
    }
    final t = Curves.easeInOutCubic.transform(_fly.value);
    _apply(lerpCamera(from, to, t), notify: _fly.isCompleted);
  }

  void _glideTo(MapCamera target) {
    _flyFrom = _camera;
    _flyTo = target;
    _fly
      ..stop()
      ..value = 0
      ..forward();
  }

  void _moveTo(LatLng center, {double? zoom, bool animate = true}) {
    final target = _camera.copyWith(center: center, zoom: zoom ?? _camera.zoom);
    if (animate) {
      _glideTo(target);
    } else {
      _apply(target);
    }
  }

  void _fit(LatLngBounds bounds, {bool animate = true}) {
    if (_camera.size.isEmpty) {
      return;
    }
    final target = _camera.fittedTo(bounds.padded(0.16));
    if (animate) {
      _glideTo(target);
    } else {
      _apply(target);
    }
  }

  void _zoomBy(double delta, {Offset? focus}) {
    _fly.stop();
    _apply(_camera.zoomedTo(_camera.zoom + delta, focus: focus));
  }

  void _resetView() {
    final points = widget.pins.map((pin) => pin.point).where((p) => p.isValid);
    if (points.isEmpty) {
      _glideTo(
        _camera.copyWith(
          center: widget.initialCenter ?? _defaultCenter,
          zoom: widget.initialZoom ?? _defaultZoom,
        ),
      );
      return;
    }
    _fitted = true;
    _fit(LatLngBounds.around(points));
  }

  // ---------------------------------------------------------------- gestures

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _gestureCamera != null) {
      return;
    }
    _fly.stop();
    // A notch is about 120; a quarter of a zoom level per notch is the step
    // both Google and Apple settle on.
    final steps = -event.scrollDelta.dy / 120;
    _zoomBy(steps * 0.42, focus: event.localPosition);
  }

  /// Every frame of a pinch is worked out from the camera the pinch started
  /// with, never from the frame before it.
  ///
  /// A pinch reports its scale and its focal point as totals since it began,
  /// so folding them in one step at a time compounds every rounding error and
  /// the map creeps away from the fingers.
  void _onScaleStart(ScaleStartDetails details) {
    _fly.stop();
    _gestureCamera = _camera;
    // A trackpad anchors on the cursor, which can be resting anywhere — even
    // off the map. Zooming about a point outside the view throws it away.
    final size = _camera.size;
    _gestureFocus = size.isEmpty
        ? details.localFocalPoint
        : Offset(
            details.localFocalPoint.dx.clamp(0.0, size.width),
            details.localFocalPoint.dy.clamp(0.0, size.height),
          );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final start = _gestureCamera;
    if (start == null) {
      return;
    }
    // A gesture is a zoom or a drag, never a blend of the two: a trackpad
    // reports a wandering focal point throughout a pinch, and following it
    // is what slides the map out from under the fingers.
    if ((details.scale - 1).abs() > 0.008) {
      _apply(
        start.zoomedTo(
          start.zoom + math.log(details.scale) / math.ln2,
          focus: _gestureFocus,
        ),
        notify: false,
      );
      return;
    }
    _apply(
      start.panned(details.localFocalPoint - _gestureFocus),
      notify: false,
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureCamera = null;
    _settle();
  }

  void _settle() {
    widget.onViewportChanged?.call(
      MapViewport(center: _camera.center, zoom: _camera.zoom),
    );
  }

  void _onDoubleTap() {
    _zoomBy(1, focus: _doubleTapAt);
  }

  void _onTap() {
    _focus.requestFocus();
    final at = _tappedAt;
    if (at != null) {
      widget.onPointTap?.call(_camera.toLatLng(at));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    const step = 90.0;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _apply(_camera.panned(const Offset(step, 0)));
      case LogicalKeyboardKey.arrowRight:
        _apply(_camera.panned(const Offset(-step, 0)));
      case LogicalKeyboardKey.arrowUp:
        _apply(_camera.panned(const Offset(0, step)));
      case LogicalKeyboardKey.arrowDown:
        _apply(_camera.panned(const Offset(0, -step)));
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
        _zoomBy(1);
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        _zoomBy(-1);
      case LogicalKeyboardKey.digit0:
        _resetView();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onMarkerTap(MapCluster cluster) {
    _focus.requestFocus();
    if (cluster.isSingle) {
      widget.onPinTap?.call(cluster.first);
      return;
    }
    // Opening a group means going in far enough to see it come apart.
    final bounds = cluster.bounds;
    if (bounds.isEmpty) {
      _glideTo(
        _camera.copyWith(center: cluster.center, zoom: _camera.zoom + 2),
      );
    } else {
      _fit(bounds);
    }
  }

  void _onMarkerEnter(MapCluster cluster) {
    _hoverOut?.cancel();
    if (_hovered?.id == cluster.id) {
      return;
    }
    setState(() => _hovered = cluster);
    widget.onPinHover?.call(cluster.isSingle ? cluster.first : null);
  }

  void _onMarkerExit() {
    _hoverOut?.cancel();
    // A moment's grace so the pointer can travel from the pin to the card.
    _hoverOut = Timer(const Duration(milliseconds: 130), () {
      if (!mounted || _pointerOnPopup) {
        return;
      }
      setState(() => _hovered = null);
      widget.onPinHover?.call(null);
    });
  }

  Future<void> _onSearch(String query) async {
    final search = widget.onSearch;
    if (search == null || query.trim().isEmpty) {
      return;
    }
    setState(() => _searching = true);
    try {
      final found = await search(query);
      if (!mounted || found == null) {
        return;
      }
      _moveTo(found, zoom: _camera.zoom < 11 ? 13 : _camera.zoom);
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  void _onSuggestionPicked(MapSuggestion suggestion) {
    _fly.stop();
    // A pin is already framed by the map; a looked-up address needs taking to.
    final zoom = suggestion.isPin
        ? math.max(_camera.zoom, 14.0)
        : (_camera.zoom < 11 ? 13.0 : _camera.zoom);
    _moveTo(suggestion.point, zoom: zoom);
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final palette = mapPaletteOf(context);
    _style = widget.style ?? palette.defaultStyle;
    _provider ??= resolveMapProvider(
      preferred: widget.provider,
      style: _style,
      apiKey: widget.apiKey,
    );
    final provider = _provider!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _camera.size && !size.isEmpty) {
          // Sizing happens during layout, so the camera catches up next frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() => _camera = _camera.copyWith(size: size));
            if (!_fitted && widget.autoFit && widget.pins.isNotEmpty) {
              _resetView();
            }
          });
        }

        requestVisibleTiles(
          camera: _camera,
          provider: provider,
          style: _style,
          cache: _cache,
        );
        _clusters = clusterPins(
          widget.pins,
          _camera,
          enabled: widget.clustering,
        );

        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: _onScroll,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _tappedAt = details.localPosition,
              onTap: _onTap,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onDoubleTapDown: (details) =>
                  _doubleTapAt = details.localPosition,
              onDoubleTap: _onDoubleTap,
              onSecondaryTapUp: widget.onContextMenu == null
                  ? null
                  : (details) => widget.onContextMenu!(
                        details.globalPosition,
                        _camera.toLatLng(details.localPosition),
                      ),
              child: ClipRect(
                // Every child below is positioned, and positioned children do
                // not size a Stack — without this the map collapses to nothing
                // wherever its host hands it a loose width.
                child: SizedBox.expand(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: MapTilePainter(
                              camera: _camera,
                              provider: provider,
                              style: _style,
                              cache: _cache,
                              background: palette.canvas,
                            ),
                          ),
                        ),
                      ),
                      ..._buildMarkers(palette),
                      if (widget.showPopup) _buildPopup(palette),
                      if (widget.pins.isEmpty && widget.emptyHint.isNotEmpty)
                        _buildEmpty(palette),
                      if (widget.showSearch && widget.onSearch != null)
                        Positioned(
                          left: MapMetrics.controlInset + widget.padding.left,
                          top: MapMetrics.controlInset + widget.padding.top,
                          child: AppMapSearchField(
                            palette: palette,
                            hintText: widget.searchHint,
                            busy: _searching,
                            onSubmitted: _onSearch,
                            suggestPins: widget.onSuggestPins,
                            onPicked: _onSuggestionPicked,
                          ),
                        ),
                      if (widget.showControls)
                        Positioned(
                          right: MapMetrics.controlInset + widget.padding.right,
                          top: MapMetrics.controlInset + widget.padding.top,
                          child: AppMapToolbar(
                            palette: palette,
                            canZoomIn: _camera.zoom < maxMapZoom,
                            canZoomOut: _camera.zoom > minMapZoom,
                            onZoomIn: () => _zoomBy(1),
                            onZoomOut: () => _zoomBy(-1),
                            onResetView: _resetView,
                            onFullscreen: widget.onFullscreen,
                            isFullscreen: widget.isFullscreen,
                          ),
                        ),
                      Positioned(
                        right:
                            MapMetrics.attributionInset + widget.padding.right,
                        bottom:
                            MapMetrics.attributionInset + widget.padding.bottom,
                        child: MapAttribution(
                          text: provider.attribution,
                          palette: palette,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildMarkers(MapPalette palette) {
    final highlighted = widget.highlightedPinIds;
    return [
      for (final cluster in _clusters)
        Builder(
          builder: (context) {
            final size = AppMapMarker.sizeOf(cluster);
            final selected = cluster.isSingle &&
                widget.selectedPinId != null &&
                cluster.first.id == widget.selectedPinId;
            final dimmed = highlighted != null &&
                !cluster.pins.any((pin) => highlighted.contains(pin.id));
            return Positioned(
              // A pin points at its place with its tip; a bubble is centred.
              left: cluster.screen.dx - size.width / 2,
              top: cluster.isSingle
                  ? cluster.screen.dy - size.height
                  : cluster.screen.dy - size.height / 2,
              width: size.width,
              height: size.height,
              child: AppMapMarker(
                key: ValueKey(cluster.id),
                cluster: cluster,
                palette: palette,
                selected: selected,
                hovered: _hovered?.id == cluster.id,
                dimmed: dimmed,
                onTap: () => _onMarkerTap(cluster),
                onEnter: () => _onMarkerEnter(cluster),
                onExit: _onMarkerExit,
              ),
            );
          },
        ),
    ];
  }

  Widget _buildPopup(MapPalette palette) {
    final hovered = _hovered;
    if (hovered == null || !hovered.isSingle || _camera.size.isEmpty) {
      return const SizedBox.shrink();
    }
    final pin = hovered.first;
    // The pin's tip is at its point and its body stands above it.
    final top = hovered.screen.dy - MapMetrics.markerHeight;
    const estimatedHeight = 210.0;
    final above = top - MapMetrics.popupGap > estimatedHeight;
    var left = hovered.screen.dx - MapMetrics.popupWidth / 2;
    final rightMost =
        (_camera.size.width - MapMetrics.popupWidth - 8).clamp(8.0, 1e6);
    left = left.clamp(8.0, rightMost.toDouble());

    return Positioned(
      left: left,
      top: above ? null : hovered.screen.dy + MapMetrics.popupGap,
      bottom: above ? _camera.size.height - top + MapMetrics.popupGap : null,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('popup:${pin.id}'),
        tween: Tween(begin: 0, end: 1),
        duration: MapMetrics.popup,
        curve: Curves.easeOutCubic,
        builder: (context, shown, child) => Opacity(
          opacity: shown,
          child: Transform.translate(
            offset: Offset(0, (1 - shown) * (above ? 6 : -6)),
            child: child,
          ),
        ),
        child: AppLocationPopup(
          pin: pin,
          palette: palette,
          footnote: pin.point.label,
          onOpen: widget.onPinTap == null ? null : () => widget.onPinTap!(pin),
          onEnter: () {
            _pointerOnPopup = true;
            _hoverOut?.cancel();
          },
          onExit: () {
            _pointerOnPopup = false;
            _onMarkerExit();
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(MapPalette palette) {
    final actionable = widget.onEmptyHintTap != null;
    return Center(
      child: MouseRegion(
        cursor:
            actionable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.onEmptyHintTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: palette.floating.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(11),
              boxShadow: palette.chromeShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.emptyHint,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: actionable ? palette.accent : palette.textMuted,
                  ),
                ),
                if (actionable) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: palette.accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
