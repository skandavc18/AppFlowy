// Adapted from pdfrx's MIT-licensed physics interaction delegate.
// Copyright (c) 2018 @espresso3389 (Takashi Kawasaki)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';

const pdfWheelScrollMultiplier = 1.0;
const _pdfBoundaryEpsilon = 0.5;

@visibleForTesting
double pdfKineticDecay({
  required double friction,
  required double elapsedSeconds,
}) =>
    premiumKineticDecay(
      friction: friction,
      elapsedSeconds: elapsedSeconds,
    );

@visibleForTesting
Offset pdfKineticFrameDisplacement({
  required Offset velocity,
  required double friction,
  required double elapsedSeconds,
}) {
  return premiumKineticFrameDisplacement(
    velocity: velocity,
    friction: friction,
    elapsedSeconds: elapsedSeconds,
  );
}

@visibleForTesting
Offset pdfKineticFrameVelocity({
  required Offset velocity,
  required double friction,
  required double elapsedSeconds,
}) =>
    premiumKineticFrameVelocity(
      velocity: velocity,
      friction: friction,
      elapsedSeconds: elapsedSeconds,
    );

@visibleForTesting
Offset pdfWheelVelocityImpulse({
  required Offset scrollDelta,
  required PointerDeviceKind kind,
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
  double multiplier = pdfWheelScrollMultiplier,
}) =>
    premiumKineticVelocityImpulse(
      delta: -scrollDelta * multiplier,
      kind: kind,
      config: config,
    );

@visibleForTesting
Offset applyPdfTrackpadPan({
  required Offset currentTranslation,
  required Offset panDelta,
}) =>
    currentTranslation + panDelta;

/// Claims wheel/trackpad signals across the full PDF embed before an ancestor
/// editor scroll view can consume them.
///
/// Nested scrollables (such as the thumbnail sidebar) are deeper in the hit
/// test path and therefore retain priority through [PointerSignalResolver].
class PdfEmbedScrollGuard extends StatelessWidget {
  const PdfEmbedScrollGuard({
    super.key,
    required this.onPointerSignal,
    this.onPointerPanZoomStart,
    this.onPointerPanZoomUpdate,
    this.onPointerPanZoomEnd,
    required this.child,
  });

  final void Function(PointerSignalEvent event) onPointerSignal;
  final void Function(PointerPanZoomStartEvent event)? onPointerPanZoomStart;
  final void Function(PointerPanZoomUpdateEvent event)? onPointerPanZoomUpdate;
  final void Function(PointerPanZoomEndEvent event)? onPointerPanZoomEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listener = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            onPointerSignal,
          );
        }
      },
      child: child,
    );

    if (onPointerPanZoomUpdate == null) {
      return listener;
    }

    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      gestures: <Type, GestureRecognizerFactory>{
        _PdfTrackpadPanZoomGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                _PdfTrackpadPanZoomGestureRecognizer>(
          _PdfTrackpadPanZoomGestureRecognizer.new,
          (recognizer) => recognizer
            ..onStart = onPointerPanZoomStart
            ..onUpdate = onPointerPanZoomUpdate
            ..onEnd = onPointerPanZoomEnd,
        ),
      },
      child: listener,
    );
  }
}

/// Claims precision-trackpad streams before editor and resize recognizers.
/// Regular mouse/touch pointers never enter this recognizer.
class _PdfTrackpadPanZoomGestureRecognizer
    extends OneSequenceGestureRecognizer {
  _PdfTrackpadPanZoomGestureRecognizer()
      : super(supportedDevices: const {PointerDeviceKind.trackpad});

  void Function(PointerPanZoomStartEvent event)? onStart;
  void Function(PointerPanZoomUpdateEvent event)? onUpdate;
  void Function(PointerPanZoomEndEvent event)? onEnd;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    resolve(GestureDisposition.rejected);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart?.call(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      onUpdate?.call(event);
    } else if (event is PointerPanZoomEndEvent) {
      onEnd?.call(event);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'PDF trackpad pan/zoom';
}

/// Vsynced wheel and precision-trackpad momentum for the pdfrx 1.x matrix.
///
/// Wheel impulses and trackpad release velocity share AppFlowy's global
/// exponential decay model. Pointer movement remains direct while fingers are
/// down, then continues naturally after release.
class PdfPreviewScrollPhysics {
  PdfPreviewScrollPhysics({
    required TickerProvider vsync,
    PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
    bool kineticEnabled = true,
    this.multiplier = pdfWheelScrollMultiplier,
  })  : _vsync = vsync,
        _kineticModel = PremiumKineticScrollModel(config: config),
        _kineticEnabled = kineticEnabled;

  final TickerProvider _vsync;
  final double multiplier;

  PdfViewerController? _controller;
  final PremiumKineticScrollModel _kineticModel;
  bool _kineticEnabled;
  Ticker? _ticker;
  Duration? _lastFrameTime;
  VelocityTracker? _trackpadVelocityTracker;

  void attach(PdfViewerController controller) {
    _controller = controller;
  }

  void configure({
    required PremiumScrollPhysicsConfig config,
    required bool kineticEnabled,
  }) {
    if (_kineticModel.config == config && _kineticEnabled == kineticEnabled) {
      return;
    }
    stop();
    _kineticModel.configure(config);
    _kineticEnabled = kineticEnabled;
  }

  void scroll(
    Offset scrollDelta, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) {
    final controller = _controller;
    if (controller == null || !controller.isReady) {
      return;
    }

    _trackpadVelocityTracker = null;
    final translationDelta = -scrollDelta * multiplier;
    if (!_kineticEnabled) {
      stop();
      _applyTranslation(
        _translationOf(controller.value) + translationDelta,
      );
      return;
    }

    final immediateDelta = _kineticModel.addWheelDelta(
      translationDelta,
      kind: kind,
    );
    if (immediateDelta != Offset.zero) {
      _applyTranslation(
        _translationOf(controller.value) + immediateDelta,
      );
    }
    _startTicker();
  }

  void beginTrackpadPan(PointerPanZoomStartEvent event) {
    stop();
    _trackpadVelocityTracker =
        MacOSScrollViewFlingVelocityTracker(PointerDeviceKind.trackpad)
          ..addPosition(event.timeStamp, Offset.zero);
  }

  void updateTrackpadPan(PointerPanZoomUpdateEvent event) {
    _trackpadVelocityTracker ??=
        MacOSScrollViewFlingVelocityTracker(PointerDeviceKind.trackpad);
    _trackpadVelocityTracker!.addPosition(event.timeStamp, event.localPan);
    panBy(event.localPanDelta);
  }

  void endTrackpadPan(PointerPanZoomEndEvent event) {
    final tracker = _trackpadVelocityTracker;
    _trackpadVelocityTracker = null;
    if (!_kineticEnabled || tracker == null) {
      return;
    }

    final releaseVelocity = tracker.getVelocity().pixelsPerSecond;
    _kineticModel.beginRelease(releaseVelocity);
    _startTicker();
  }

  /// Applies high-resolution trackpad deltas directly while fingers are down.
  void panBy(Offset panDelta) {
    final controller = _controller;
    if (controller == null || !controller.isReady) {
      return;
    }

    _cancelTicker();
    _applyTranslation(
      applyPdfTrackpadPan(
        currentTranslation: _translationOf(controller.value),
        panDelta: panDelta,
      ),
    );
  }

  /// Applies an incremental trackpad pinch while keeping the focal point under
  /// the pointer. This replaces the pdfrx recognizer that the embed guard wins.
  void scaleBy(Offset globalFocalPoint, double scaleDelta) {
    final controller = _controller;
    if (controller == null ||
        !controller.isReady ||
        !scaleDelta.isFinite ||
        scaleDelta <= 0 ||
        (scaleDelta - 1).abs() < 0.0001) {
      return;
    }

    _cancelTicker();
    final oldZoom = controller.currentZoom;
    final newZoom = (oldZoom * scaleDelta)
        .clamp(controller.minScale, controller.params.maxScale)
        .toDouble();
    if ((newZoom - oldZoom).abs() < 0.0001) {
      return;
    }

    final localFocalPoint = controller.globalToLocal(globalFocalPoint) ??
        Offset(controller.viewSize.width / 2, controller.viewSize.height / 2);
    final translation = _translationOf(controller.value);
    final documentFocalPoint = Offset(
      (localFocalPoint.dx - translation.dx) / oldZoom,
      (localFocalPoint.dy - translation.dy) / oldZoom,
    );
    final nextTranslation = Offset(
      localFocalPoint.dx - documentFocalPoint.dx * newZoom,
      localFocalPoint.dy - documentFocalPoint.dy * newZoom,
    );
    final matrix = controller.value.clone()
      ..setEntry(0, 0, newZoom)
      ..setEntry(1, 1, newZoom)
      ..setTranslationRaw(nextTranslation.dx, nextTranslation.dy, 0);
    controller.value = controller.makeMatrixInSafeRange(matrix);
  }

  void stop() {
    _trackpadVelocityTracker = null;
    _cancelTicker();
  }

  void _cancelTicker() {
    _ticker?.dispose();
    _ticker = null;
    _kineticModel.stop();
    _lastFrameTime = null;
  }

  void _startTicker() {
    if (_ticker != null || !_kineticModel.isActive) {
      return;
    }
    _lastFrameTime = null;
    _ticker = _vsync.createTicker(_onTick)..start();
  }

  void dispose() {
    stop();
    _controller = null;
  }

  void _onTick(Duration elapsed) {
    final controller = _controller;
    if (controller == null || !controller.isReady) {
      _cancelTicker();
      return;
    }

    if (_lastFrameTime == null) {
      _lastFrameTime = elapsed;
      return;
    }
    final elapsedSeconds =
        (elapsed - _lastFrameTime!).inMicroseconds / 1000000.0;
    _lastFrameTime = elapsed;

    final currentTranslation = _translationOf(controller.value);
    final frame = _kineticModel.advance(elapsedSeconds);
    final requestedTranslation = currentTranslation + frame.displacement;
    final actualTranslation = _applyTranslation(requestedTranslation);
    _kineticModel.stopAxes(
      horizontal: (actualTranslation.dx - requestedTranslation.dx).abs() >
          _pdfBoundaryEpsilon,
      vertical: (actualTranslation.dy - requestedTranslation.dy).abs() >
          _pdfBoundaryEpsilon,
    );
    if (!_kineticModel.isActive) {
      _cancelTicker();
    }
  }

  Offset _applyTranslation(Offset requestedTranslation) {
    final controller = _controller;
    if (controller == null || !controller.isReady) {
      return requestedTranslation;
    }

    final matrix = controller.value.clone()
      ..setTranslationRaw(
        requestedTranslation.dx,
        requestedTranslation.dy,
        0,
      );
    controller.value = controller.makeMatrixInSafeRange(matrix);
    return _translationOf(controller.value);
  }

  Offset _translationOf(Matrix4 matrix) {
    final translation = matrix.getTranslation();
    return Offset(translation.x, translation.y);
  }
}
