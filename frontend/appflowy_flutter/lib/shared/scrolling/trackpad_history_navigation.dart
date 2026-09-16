import 'dart:async';

import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Desktop two-finger history navigation. No mouse/touch drags or wheel events
/// are converted to navigation. A gesture commits once, on release, after 96px
/// of deliberate horizontal movement (right = Back, left = Forward).
class TrackpadHistoryNavigation extends StatefulWidget {
  const TrackpadHistoryNavigation({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.navigationToken,
    required this.child,
    this.pageKey,
    this.previewKey,
    this.previewScope,
    this.allowPreviews = true,
    this.enabled = true,
    this.animateChild = true,
  });

  final bool Function() canGoBack;
  final bool Function() canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  /// Invalidates gestures if a tab/page/workspace changes before release.
  final Object Function() navigationToken;
  final Widget child;
  final Object? pageKey;
  final Object? Function(bool forward)? previewKey;
  final Object? previewScope;
  final bool allowPreviews;
  final bool enabled;

  /// When false, place [HistorySwipePageSurface] around only the page pane.
  /// The gesture host can then include a stationary sidebar as well.
  final bool animateChild;

  @override
  State<TrackpadHistoryNavigation> createState() =>
      _TrackpadHistoryNavigationState();
}

class _TrackpadHistoryNavigationState extends State<TrackpadHistoryNavigation>
    with WidgetsBindingObserver {
  final _swipe = HistorySwipeController();
  _HistorySwipeRecognizer? _recognizer;
  int? _boundaryPointer;
  Object? _boundaryToken;
  Offset _boundaryPan = Offset.zero;
  double _boundaryDirection = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancelBoundary();
      _recognizer?.cancel();
      _swipe.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _swipe.dispose();
    super.dispose();
  }

  bool _canStart(PointerPanZoomStartEvent event) {
    if (!mounted ||
        !widget.enabled ||
        _swipe.isSettling ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    return !hit.path.any(
      (entry) =>
          entry.target is _RenderHistoryExclusion ||
          PremiumScrollExclusion.isHitTestTarget(entry.target),
    );
  }

  // Some reading previews deliberately own BOTH scroll axes (including code
  // blocks inside HTML). Never steal their pan or turn it into navigation.
  // An explicit marker lets us observe a boundary gesture for feedback only;
  // generic PDFs, maps, tables and bookmark website history remain untouched.
  void _startBoundary(PointerPanZoomStartEvent event) {
    if (!mounted ||
        !widget.enabled ||
        _swipe.isSettling ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    if (!hit.path
            .any((entry) => entry.target is _RenderHistoryBoundaryFeedback) ||
        !hit.path.any(
          (entry) => PremiumScrollExclusion.isHitTestTarget(entry.target),
        )) {
      return;
    }
    _swipe.cancel();
    _boundaryPointer = event.pointer;
    _boundaryToken = widget.navigationToken();
    _boundaryPan = Offset.zero;
    _boundaryDirection = 0;
  }

  void _updateBoundary(PointerPanZoomUpdateEvent event) {
    if (event.pointer != _boundaryPointer) return;
    if (!event.localPanDelta.isFinite ||
        !event.scale.isFinite ||
        !event.rotation.isFinite ||
        (event.scale - 1).abs() > .01 ||
        event.rotation.abs() > .01 ||
        widget.navigationToken() != _boundaryToken ||
        ModalRoute.of(context)?.isCurrent == false) {
      _cancelBoundary();
      return;
    }
    _boundaryPan += event.localPanDelta;
    if (_boundaryDirection == 0) {
      if (_boundaryPan.dx.abs() < 12 && _boundaryPan.dy.abs() < 12) return;
      final forward = _boundaryPan.dx < 0;
      if (_boundaryPan.dx.abs() < 2 * _boundaryPan.dy.abs() ||
          (forward ? widget.canGoForward() : widget.canGoBack())) {
        _cancelBoundary();
        return;
      }
      _boundaryDirection = _boundaryPan.dx.sign;
      _swipe.begin(forward: forward, available: false);
    }
    _swipe.update(_boundaryPan.dx * _boundaryDirection);
  }

  void _endBoundary(PointerPanZoomEndEvent event) {
    if (event.pointer != _boundaryPointer) return;
    final token = _boundaryToken;
    final direction = _boundaryDirection;
    _boundaryPointer = null;
    _boundaryToken = null;
    if (direction != 0 && token != null) _end(direction < 0, token, false);
  }

  void _cancelBoundary() {
    if (_boundaryPointer == null) return;
    _boundaryPointer = null;
    _boundaryToken = null;
    _swipe.cancel();
  }

  void _update(bool forward, double distance, Object token) {
    if (!_swipe.isActive) {
      _swipe.begin(
        forward: forward,
        available: forward ? widget.canGoForward() : widget.canGoBack(),
        target: widget.previewKey?.call(forward),
      );
    }
    _swipe.update(distance);
  }

  void _end(bool forward, Object token, bool commit) {
    // Leave the gesture arena before a page can dispose its old scrollables.
    scheduleMicrotask(() {
      if (!mounted) return;
      if (!widget.enabled ||
          widget.navigationToken() != token ||
          ModalRoute.of(context)?.isCurrent == false) {
        _swipe.cancel();
        return;
      }
      unawaited(
        _swipe.finish(
          commit: commit,
          isValid: () =>
              mounted &&
              widget.enabled &&
              widget.navigationToken() == token &&
              ModalRoute.of(context)?.isCurrent != false &&
              (forward ? widget.canGoForward() : widget.canGoBack()),
          navigate: () => (forward ? widget.onForward : widget.onBack)(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform != TargetPlatform.windows &&
        platform != TargetPlatform.linux &&
        platform != TargetPlatform.macOS) {
      return widget.child;
    }
    return _HistoryNavigationScope(
      controller: _swipe,
      pageKey: widget.pageKey,
      previewScope: widget.previewScope,
      allowPreviews: widget.allowPreviews,
      child: ScrollConfiguration(
        behavior: _HistoryScrollBehavior(ScrollConfiguration.of(context)),
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          gestures: {
            _HistorySwipeRecognizer:
                GestureRecognizerFactoryWithHandlers<_HistorySwipeRecognizer>(
              _HistorySwipeRecognizer.new,
              (recognizer) {
                _recognizer = recognizer
                  ..canStart = _canStart
                  ..navigationToken = widget.navigationToken
                  ..onUpdate = _update
                  ..onEnd = _end
                  ..onCancel = _swipe.cancel;
              },
            ),
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerPanZoomStart: _startBoundary,
            onPointerPanZoomUpdate: _updateBoundary,
            onPointerPanZoomEnd: _endBoundary,
            onPointerCancel: (event) {
              if (event.pointer == _boundaryPointer) _cancelBoundary();
            },
            child: widget.animateChild
                ? HistorySwipePageSurface(child: widget.child)
                : widget.child,
          ),
        ),
      ),
    );
  }
}

/// Paint target for a history host that also covers stationary navigation UI.
class HistorySwipePageSurface extends StatelessWidget {
  const HistorySwipePageSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_HistoryNavigationScope>();
    if (scope == null) return child;
    return HistorySwipeSurface(
      controller: scope.controller,
      pageKey: scope.pageKey,
      scope: scope.previewScope,
      allowPreviews: scope.allowPreviews,
      child: child,
    );
  }
}

class _HistoryNavigationScope extends InheritedWidget {
  const _HistoryNavigationScope({
    required this.controller,
    required this.pageKey,
    required this.previewScope,
    required this.allowPreviews,
    required super.child,
  });

  final HistorySwipeController controller;
  final Object? pageKey;
  final Object? previewScope;
  final bool allowPreviews;

  @override
  bool updateShouldNotify(_HistoryNavigationScope oldWidget) =>
      controller != oldWidget.controller ||
      pageKey != oldWidget.pageKey ||
      previewScope != oldWidget.previewScope ||
      allowPreviews != oldWidget.allowPreviews;
}

/// Opts a custom reading surface into feedback at workspace history boundaries.
/// It observes input only: the viewer still owns pan, wheel and zoom events.
class HistorySwipeBoundaryFeedback extends SingleChildRenderObjectWidget {
  const HistorySwipeBoundaryFeedback({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHistoryBoundaryFeedback();
}

class _RenderHistoryBoundaryFeedback extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    hitTestChildren(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class _HistorySwipeRecognizer extends OneSequenceGestureRecognizer {
  _HistorySwipeRecognizer()
      : super(supportedDevices: const {PointerDeviceKind.trackpad});

  late bool Function(PointerPanZoomStartEvent) canStart;
  late Object Function() navigationToken;
  late void Function(bool forward, double distance, Object token) onUpdate;
  late void Function(bool forward, Object token, bool commit) onEnd;
  late VoidCallback onCancel;
  int? _pointer;
  Object? _token;
  Offset _pan = Offset.zero;
  double _direction = 0;
  bool _won = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) => false;

  @override
  void addAllowedPointer(PointerDownEvent event) {}

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      _pointer == null &&
      canStart(event) &&
      super.isPointerPanZoomAllowed(event);

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    // Dismiss the previous boundary cue before classifying this new gesture.
    onCancel();
    _pointer = event.pointer;
    _pan = Offset.zero;
    _direction = 0;
    _won = false;
    _token = navigationToken();
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerPanZoomUpdateEvent) {
      if (!event.scale.isFinite ||
          !event.rotation.isFinite ||
          (event.scale - 1).abs() > 0.01 ||
          event.rotation.abs() > 0.01 ||
          navigationToken() != _token ||
          !event.localPanDelta.isFinite) {
        _reject();
        return;
      }
      _pan += event.localPanDelta;
      if (_direction == 0 && (_pan.dx.abs() >= 12 || _pan.dy.abs() >= 12)) {
        if (_pan.dx.abs() < 2 * _pan.dy.abs()) {
          _reject();
          return;
        }
        _direction = _pan.dx.sign;
        resolve(GestureDisposition.accepted);
      }
      _reportProgress();
    } else if (event is PointerPanZoomEndEvent) {
      final commit = _won &&
          _direction != 0 &&
          _pan.dx * _direction >= 96 &&
          _pan.dx.abs() >= 2 * _pan.dy.abs() &&
          navigationToken() == _token;
      final forward = _direction < 0;
      final token = _token;
      final hadDirection = _won && _direction != 0;
      _clear();
      if (hadDirection && token != null) {
        onEnd(forward, token, commit);
      } else {
        onCancel();
      }
    } else if (event is PointerCancelEvent) {
      _reject();
    }
  }

  void _reject() {
    resolve(GestureDisposition.rejected);
    _clear();
    onCancel();
  }

  void cancel() {
    if (_pointer != null) _reject();
  }

  void _reportProgress() {
    if (_won && _direction != 0 && _token != null) {
      onUpdate(_direction < 0, _pan.dx * _direction, _token!);
    }
  }

  void _clear() {
    final pointer = _pointer;
    _pointer = null;
    _token = null;
    _won = false;
    if (pointer != null) stopTrackingPointer(pointer);
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == _pointer) {
      _won = true;
      _reportProgress();
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointer) {
      _clear();
      onCancel();
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'two-finger history swipe';
}

/// For surfaces that own free panning rather than navigation.
class HistorySwipeExclusion extends SingleChildRenderObjectWidget {
  const HistorySwipeExclusion({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHistoryExclusion();
}

class _RenderHistoryExclusion extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    hitTestChildren(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class _HistoryScrollBehavior extends NoScrollbarBehavior {
  const _HistoryScrollBehavior(super.parent);

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      parent.buildScrollbar(context, child, details);

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final decorated = parent.buildOverscrollIndicator(context, child, details);
    // Horizontal scrolling owns the whole gesture, even at its boundary.
    // Reaching a table's edge must never unexpectedly leave the page.
    return axisDirectionToAxis(details.direction) == Axis.horizontal
        ? HistorySwipeExclusion(child: decorated)
        : decorated;
  }
}
