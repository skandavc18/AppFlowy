import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'standalone_file_scope.dart';

/// One retained, naturally sized header and a bounded renderer. Borrowable
/// vertical lists use the nested primary controller. Controller/matrix-owned
/// renderers opt into [StandaloneFileScrollRegion] at their input boundary.
class StandaloneFilePage extends StatefulWidget {
  const StandaloneFilePage(
      {super.key,
      required this.header,
      required this.body,
      this.nativeBodyGestures = false});

  final Widget header;
  final Widget body;

  /// Matrix-owned photos keep their scale recognizer, including zoomed pans.
  /// The outer drag must not win at a smaller slop than that native recognizer.
  final bool nativeBodyGestures;

  @override
  State<StandaloneFilePage> createState() => _StandaloneFilePageState();
}

class _StandaloneFilePageState extends State<StandaloneFilePage> {
  final _outer = ScrollController(debugLabel: 'Whole file page');

  @override
  void dispose() {
    _outer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PremiumCoordinatedScrollScope(
        child: NestedScrollView(
          key: const ValueKey('workspace-file-page-scroll'),
          controller: _outer,
          scrollBehavior: widget.nativeBodyGestures
              ? ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  dragDevices: ScrollConfiguration.of(context)
                      .dragDevices
                      .difference({PointerDeviceKind.trackpad}),
                )
              : null,
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: StandaloneFilePageScroll(
                outer: _outer,
                inner: _outer,
                chrome: StandaloneFileScope.maybeOf(context)?.chrome,
                child: StandaloneFileScrollRegion(
                  enabled: widget.nativeBodyGestures,
                  consumeBody: (_) => 0,
                  child: widget.header,
                ),
              ),
            ),
          ],
          body: Builder(
            builder: (context) => StandaloneFilePageScroll(
              outer: _outer,
              inner: PrimaryScrollController.of(context),
              chrome: StandaloneFileScope.maybeOf(context)?.chrome,
              child: PrimaryScrollController(
                controller: PrimaryScrollController.of(context),
                automaticallyInheritForPlatforms: const <TargetPlatform>{},
                child: widget.body,
              ),
            ),
          ),
        ),
      );
}

/// Positive deltas move down the page. A delegate returns ACTUAL consumption,
/// not requested travel. Reverse travel drains the body before revealing the
/// header. Never invoke this from a post-consumption ScrollNotification.
class StandaloneFilePageScroll extends InheritedWidget {
  const StandaloneFilePageScroll({
    super.key,
    required this.outer,
    required this.inner,
    this.chrome,
    required super.child,
  });

  final ScrollController outer;
  final ScrollController inner;
  final StandaloneFileChromeController? chrome;

  static StandaloneFilePageScroll? maybeOf(BuildContext context) {
    final page =
        context.dependOnInheritedWidgetOfExactType<StandaloneFilePageScroll>();
    final boundary = context
        .dependOnInheritedWidgetOfExactType<StandaloneFilePageBoundary>();
    if (boundary?.enabled == false ||
        !identical(page?.chrome, StandaloneFileScope.maybeOf(context)?.chrome))
      return null;
    return page;
  }

  static double move(ScrollController controller, double delta) {
    if (controller.positions.length != 1) return 0;
    final position = controller.position;
    if (!position.hasContentDimensions) return 0;
    final before = position.pixels;
    final next = (before + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next != before) controller.jumpTo(next);
    return position.pixels - before;
  }

  double consume(double delta, double Function(double) body) {
    if (!delta.isFinite || delta == 0) return 0;
    if (delta > 0) {
      final header = move(outer, delta);
      return header + body(delta - header);
    }
    final content = body(delta);
    return content + move(outer, delta - content);
  }

  @override
  bool updateShouldNotify(StandaloneFilePageScroll oldWidget) =>
      outer != oldWidget.outer ||
      inner != oldWidget.inner ||
      chrome != oldWidget.chrome;
}

/// Prevents a bare/nested renderer from borrowing an enclosing file's adapter.
/// It changes input eligibility only; the renderer subtree stays mounted.
class StandaloneFilePageBoundary extends InheritedWidget {
  const StandaloneFilePageBoundary({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  @override
  bool updateShouldNotify(StandaloneFilePageBoundary oldWidget) =>
      enabled != oldWidget.enabled;
}

/// A renderer-local boundary for an explicitly owned primary vertical
/// controller. It does not inspect descendants, reparent controls, or claim
/// mouse/touch selection. Horizontal and modified-wheel input remain native.
/// The hit entry precedes the child's wheel resolver, avoiding delta replay.
class StandaloneFileScrollRegion extends StatefulWidget {
  const StandaloneFileScrollRegion({
    super.key,
    this.controller,
    this.consumeBody,
    required this.child,
    this.enabled = true,
    this.trackpad = true,
    this.stopWheelOnNativePan = false,
  });

  final ScrollController? controller;
  final double Function(double)? consumeBody;
  final Widget child;
  final bool enabled;
  final bool trackpad;

  /// A matrix-owned photo keeps native scale recognition, but a new pan/pinch
  /// must cancel the page adapter's queued wheel motion before native delivery.
  final bool stopWheelOnNativePan;

  /// Inactive embed gates must filter this entry as well as premium markers.
  static bool isHitTestTarget(HitTestTarget target) =>
      target is _FileInputRenderBox;

  /// Called by an owning embed gate when its previously hit surface disengages.
  /// Cancel the local wheel/release owner without delivering filtered input.
  static void cancelMotion(HitTestTarget target) {
    if (target is _FileInputRenderBox) target.onCancel();
  }

  @override
  State<StandaloneFileScrollRegion> createState() =>
      _StandaloneFileScrollRegionState();
}

class _StandaloneFileScrollRegionState extends State<StandaloneFileScrollRegion>
    with TickerProviderStateMixin {
  final _trackpad = _FileVerticalTrackpad();
  final _motion = PremiumKineticScrollModel(
    config: const PremiumScrollPhysicsConfig(),
  );
  Ticker? _ticker;
  Duration? _lastFrame;
  bool _smooth = false;
  StandaloneFilePageScroll? _page;
  bool get _enabled =>
      widget.enabled &&
      (widget.controller != null || widget.consumeBody != null) &&
      _page != null;

  double _consume(double delta) =>
      _page?.consume(
        delta,
        widget.consumeBody ??
            (remaining) =>
                StandaloneFilePageScroll.move(widget.controller!, remaining),
      ) ??
      0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page = StandaloneFilePageScroll.maybeOf(context);
    final behavior = ScrollConfiguration.of(context);
    _stop();
    _motion.configure(behavior is PremiumScrollBehavior
        ? behavior.config
        : const PremiumScrollPhysicsConfig());
    _smooth = !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        (behavior is! PremiumScrollBehavior || behavior.kineticEnabled);
  }

  void _stop() {
    _ticker?.dispose();
    _ticker = null;
    _lastFrame = null;
    _motion.stop();
  }

  void _cancelInput() {
    _stop();
    _trackpad.enabled = false;
  }

  void _takeOver() {
    _stop();
    final controller = widget.controller;
    if (controller != null && controller.positions.length == 1) {
      controller.jumpTo(controller.offset);
    }
    final outer = _page?.outer;
    if (outer != null && outer.positions.length == 1)
      outer.jumpTo(outer.offset);
  }

  void _startMotion() {
    if (_ticker != null || !_motion.isActive) return;
    _ticker = createTicker((elapsed) {
      if (!mounted || !_enabled) {
        _stop();
        return;
      }
      final previous = _lastFrame;
      _lastFrame = elapsed;
      if (previous == null) return;
      final frame =
          _motion.advance((elapsed - previous).inMicroseconds / 1000000);
      final actual = _consume(frame.displacement.dy);
      _motion.stopAxes(vertical: (actual - frame.displacement.dy).abs() > 0.5);
      if (!_motion.isActive) _stop();
    })
      ..start();
  }

  void _signal(PointerSignalEvent event) {
    if (event is PointerScrollInertiaCancelEvent) {
      _stop();
      return;
    }
    final keys = HardwareKeyboard.instance;
    if (!_enabled ||
        event is! PointerScrollEvent ||
        keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isShiftPressed ||
        event.scrollDelta.dy.abs() <= event.scrollDelta.dx.abs()) {
      _stop();
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !_enabled) return;
      if (!_smooth) {
        _takeOver();
        _consume(event.scrollDelta.dy);
      } else {
        if (_ticker == null) _takeOver();
        final immediate = _motion.addWheelDelta(
          Offset(0, event.scrollDelta.dy),
          kind: event.kind,
        );
        if (immediate.dy != 0) _consume(immediate.dy);
        _startMotion();
      }
    });
  }

  @override
  void deactivate() {
    _stop();
    super.deactivate();
  }

  @override
  void didUpdateWidget(covariant StandaloneFileScrollRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller || !widget.enabled) _stop();
    _trackpad.enabled = _enabled && widget.trackpad;
  }

  @override
  void dispose() {
    _stop();
    _trackpad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FileInputBoundary(
        enabled: _enabled,
        onSignal: _signal,
        onPointerDown: _stop,
        onCancel: _cancelInput,
        onPanStart: (event) {
          if (widget.stopWheelOnNativePan) _stop();
          _trackpad.enabled = _enabled && widget.trackpad;
          _trackpad.onBegin = _takeOver;
          _trackpad.onDelta = (delta) => _consume(delta);
          _trackpad.onRelease = (velocity) {
            if (!_enabled || !_smooth) return;
            _motion.beginRelease(Offset(0, velocity));
            _startMotion();
          };
          // Register BEFORE the child's Scrollable receives the start. Only
          // this trackpad candidate wins a vertical stream; native mouse/touch
          // selection and horizontal/pinch candidates are left alone.
          if (_trackpad.enabled) _trackpad.addPointerPanZoom(event);
        },
        // Keep this subtree stable when eligibility changes. The boundary
        // omits just this marker from its hit path when it has no page owner.
        child: PremiumScrollExclusion(
          child: _FileControllerScrollRegion(
            controller: widget.controller,
            child: widget.child,
          ),
        ),
      );
}

/// Advertise the explicitly owned controller even when the native child omits
/// its overscroll decoration (EditableText does this). Otherwise Premium sees
/// only the enclosing NestedScrollView and takes a wheel the child can consume.
/// This is an ordinary scroll region, NOT an exclusion or a file-page adapter:
/// live position physics/range still decide eligibility and boundary fallback.
/// Keep it mounted across adapter enable/disable transitions to retain editors.
class _FileControllerScrollRegion extends StatelessWidget {
  const _FileControllerScrollRegion({
    required this.controller,
    required this.child,
  });

  final ScrollController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (controller == null) return child;
    return NotificationListener<OverscrollIndicatorNotification>(
      // This extra routing decoration must not add a second glow/stretch.
      onNotification: (notification) {
        notification.disallowIndicator();
        return false;
      },
      child: ScrollConfiguration.of(context).buildOverscrollIndicator(
        context,
        child,
        ScrollableDetails(
          direction: AxisDirection.down,
          controller: controller,
        ),
      ),
    );
  }
}

/// Trackpad only: no touch drag interception, no synthetic caret/pointer events,
/// one release owner across header and content, never a second native fling.
class _FileVerticalTrackpad extends OneSequenceGestureRecognizer {
  bool enabled = false;
  VoidCallback? onBegin;
  ValueChanged<double>? onDelta;
  ValueChanged<double>? onRelease;
  bool _accepted = false;
  Offset _pending = Offset.zero;
  Offset _total = Offset.zero;
  VelocityTracker? _velocity;
  Duration _lastInput = Duration.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) =>
      resolve(GestureDisposition.rejected);

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (!enabled) return;
    _accepted = false;
    _pending = Offset.zero;
    _total = Offset.zero;
    _lastInput = event.timeStamp;
    _velocity = MacOSScrollViewFlingVelocityTracker(PointerDeviceKind.trackpad)
      ..addPosition(event.timeStamp, Offset.zero);
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      if (!enabled || (event.scale - 1).abs() > 0.001 || event.rotation != 0) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
      _pending += event.localPanDelta;
      _total += event.localPanDelta;
      _lastInput = event.timeStamp;
      _velocity?.addPosition(event.timeStamp, _total);
      if (!_accepted) {
        if (_pending.distance < 1) return;
        if (_pending.dx.abs() >= _pending.dy.abs()) {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          return;
        }
        _accepted = true;
        resolve(GestureDisposition.accepted);
        onBegin?.call();
      }
      onDelta?.call(-_pending.dy);
      _pending = Offset.zero;
    } else if (event is PointerPanZoomEndEvent || event is PointerCancelEvent) {
      if (_accepted &&
          event is PointerPanZoomEndEvent &&
          event.timeStamp - _lastInput <= const Duration(milliseconds: 100)) {
        onRelease?.call(-(_velocity?.getVelocity().pixelsPerSecond.dy ?? 0));
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) => stopTrackingPointer(pointer);
  @override
  void didStopTrackingLastPointer(int pointer) {
    _accepted = false;
    _velocity = null;
  }

  @override
  String get debugDescription => 'whole file vertical trackpad';
}

class _FileInputBoundary extends SingleChildRenderObjectWidget {
  const _FileInputBoundary(
      {required this.enabled,
      required this.onSignal,
      required this.onPanStart,
      required this.onPointerDown,
      required this.onCancel,
      required super.child});
  final bool enabled;
  final PointerSignalEventListener onSignal;
  final PointerPanZoomStartEventListener onPanStart;
  final VoidCallback onPointerDown;
  final VoidCallback onCancel;

  @override
  RenderObject createRenderObject(BuildContext context) => _FileInputRenderBox(
      enabled, onSignal, onPanStart, onPointerDown, onCancel);
  @override
  void updateRenderObject(
      BuildContext context, _FileInputRenderBox renderObject) {
    renderObject.enabled = enabled;
    renderObject.onSignal = onSignal;
    renderObject.onPanStart = onPanStart;
    renderObject.onPointerDown = onPointerDown;
    renderObject.onCancel = onCancel;
  }
}

class _FileInputRenderBox extends RenderProxyBox {
  _FileInputRenderBox(this.enabled, this.onSignal, this.onPanStart,
      this.onPointerDown, this.onCancel);
  bool enabled;
  PointerSignalEventListener onSignal;
  PointerPanZoomStartEventListener onPanStart;
  VoidCallback onPointerDown;
  VoidCallback onCancel;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (enabled) {
      result.add(BoxHitTestEntry(this, position));
      super.hitTestChildren(result, position: position);
      return true;
    }
    // Drop our marker as it is added, before transforms are attached. Sharing
    // the result retains original Box/Sliver/custom entry subtypes verbatim.
    super.hitTestChildren(_FileHitTestResult(result, child!),
        position: position);
    return true;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerSignalEvent) onSignal(event);
    if (event is PointerPanZoomStartEvent) onPanStart(event);
    if (event is PointerDownEvent) onPointerDown();
    if (event is PointerCancelEvent) onCancel();
  }
}

class _FileHitTestResult extends BoxHitTestResult {
  _FileHitTestResult(BoxHitTestResult result, this.marker) : super.wrap(result);

  final HitTestTarget marker;

  @override
  void add(HitTestEntry entry) {
    if (!identical(entry.target, marker)) super.add(entry);
  }
}
