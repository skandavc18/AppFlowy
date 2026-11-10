import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'frame_synced_scroll_pan.dart';
import 'premium_coast.dart';
import 'waydroid_scroll.dart';

/// Tunable constants for AppFlowy's application-wide kinetic scrolling.
@immutable
class PremiumScrollPhysicsConfig {
  const PremiumScrollPhysicsConfig({
    this.friction = 5.0,
    this.wheelAcceleration = 8.0,
    this.precisionAcceleration = 14.0,
    this.maxVelocity = 8000.0,
    this.momentumRetention = 0.92,
    this.directionChangeRetention = 0.20,
    this.maxWheelDelta = 120.0,
    this.maxPrecisionDelta = 48.0,
    this.precisionDeltaThreshold = 24.0,
    this.minimumVelocity = 18.0,
    this.stopVelocity = 8.0,
    this.immediateResponse = 0.22,
    this.wheelSmoothingRate = 16.0,
    this.maxWheelScrollVelocity = 6000.0,
    this.maxWheelQueuedDistance = 1200.0,
    this.wheelStopDistance = 0.1,
    this.desktopDirectManipulationScale = 1.0,
    this.desktopCoastFriction = premiumCoastFriction,
    this.desktopCoastDeceleration = premiumCoastDeceleration,
    this.desktopFramePacing = true,
  })  : assert(friction > 0),
        assert(wheelAcceleration > 0),
        assert(precisionAcceleration > 0),
        assert(maxVelocity > 0),
        assert(momentumRetention >= 0 && momentumRetention <= 1),
        assert(
          directionChangeRetention >= 0 && directionChangeRetention <= 1,
        ),
        assert(maxWheelDelta > 0),
        assert(maxPrecisionDelta > 0),
        assert(precisionDeltaThreshold > 0),
        assert(minimumVelocity >= 0),
        assert(stopVelocity > 0),
        assert(immediateResponse >= 0 && immediateResponse <= 1),
        assert(wheelSmoothingRate > 0),
        assert(maxWheelScrollVelocity > 0),
        assert(maxWheelQueuedDistance > 0),
        assert(wheelStopDistance > 0),
        assert(desktopCoastFriction > 0),
        assert(desktopCoastDeceleration >= 0),
        assert(
          desktopDirectManipulationScale > 0 &&
              desktopDirectManipulationScale <= 1,
        );

  /// Exponential velocity decay in inverse seconds.
  final double friction;

  /// Velocity impulse per logical mouse-wheel pixel.
  final double wheelAcceleration;

  /// Velocity impulse for high-resolution wheels and pointer scroll tracks.
  final double precisionAcceleration;

  /// Fastest release or wheel momentum, in logical pixels/second.
  final double maxVelocity;
  final double momentumRetention;
  final double directionChangeRetention;
  final double maxWheelDelta;
  final double maxPrecisionDelta;
  final double precisionDeltaThreshold;
  final double minimumVelocity;
  final double stopVelocity;

  /// Fraction of each wheel delta reserved for low-latency response.
  ///
  /// Used by custom embedded surfaces such as the PDF matrix viewer. Regular
  /// Flutter scroll positions use the exact-distance wheel settings below.
  final double immediateResponse;

  /// Exponential response rate for discrete mouse-wheel distance.
  final double wheelSmoothingRate;

  /// Maximum speed of smoothed mouse-wheel movement in logical pixels/second.
  final double maxWheelScrollVelocity;

  /// Maximum unconsumed mouse-wheel distance, preventing a long artificial
  /// coast after a rapid burst of notches.
  final double maxWheelQueuedDistance;

  /// Imperceptible residual distance discarded when a wheel animation ends.
  final double wheelStopDistance;

  /// Scales direct pan/drag distance on Windows and Linux desktop builds.
  ///
  /// One-to-one keeps content under the fingers, as on macOS and in Edge: the
  /// platform has already applied the user's scroll speed and acceleration,
  /// and scaling it again made pages heavier than every other app. Native
  /// macOS and mobile movement are never scaled.
  final double desktopDirectManipulationScale;

  /// Viscous share of the desktop release coast's deceleration, in inverse
  /// seconds (see [PremiumCoastSimulation]). Embedded viewers' wheel impulses
  /// decay with [friction] instead.
  final double desktopCoastFriction;

  /// Constant share of the desktop release coast's deceleration, in logical
  /// pixels/second², which lets a coast settle instead of creeping.
  final double desktopCoastDeceleration;

  /// Play coarse trackpad drag packets across high-refresh frames by their
  /// input timestamps, a short adaptive delay behind the fingers, never
  /// predicting unreceived distance.
  final bool desktopFramePacing;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PremiumScrollPhysicsConfig &&
          other.friction == friction &&
          other.wheelAcceleration == wheelAcceleration &&
          other.precisionAcceleration == precisionAcceleration &&
          other.maxVelocity == maxVelocity &&
          other.momentumRetention == momentumRetention &&
          other.directionChangeRetention == directionChangeRetention &&
          other.maxWheelDelta == maxWheelDelta &&
          other.maxPrecisionDelta == maxPrecisionDelta &&
          other.precisionDeltaThreshold == precisionDeltaThreshold &&
          other.minimumVelocity == minimumVelocity &&
          other.stopVelocity == stopVelocity &&
          other.immediateResponse == immediateResponse &&
          other.wheelSmoothingRate == wheelSmoothingRate &&
          other.maxWheelScrollVelocity == maxWheelScrollVelocity &&
          other.maxWheelQueuedDistance == maxWheelQueuedDistance &&
          other.wheelStopDistance == wheelStopDistance &&
          other.desktopDirectManipulationScale ==
              desktopDirectManipulationScale &&
          other.desktopCoastFriction == desktopCoastFriction &&
          other.desktopCoastDeceleration == desktopCoastDeceleration &&
          other.desktopFramePacing == desktopFramePacing;

  @override
  int get hashCode => Object.hashAll([
        friction,
        wheelAcceleration,
        precisionAcceleration,
        maxVelocity,
        momentumRetention,
        directionChangeRetention,
        maxWheelDelta,
        maxPrecisionDelta,
        precisionDeltaThreshold,
        minimumVelocity,
        stopVelocity,
        immediateResponse,
        wheelSmoothingRate,
        maxWheelScrollVelocity,
        maxWheelQueuedDistance,
        wheelStopDistance,
        desktopDirectManipulationScale,
        desktopCoastFriction,
        desktopCoastDeceleration,
        desktopFramePacing,
      ]);

  PremiumScrollPhysicsConfig copyWith({double? immediateResponse}) =>
      PremiumScrollPhysicsConfig(
        friction: friction,
        wheelAcceleration: wheelAcceleration,
        precisionAcceleration: precisionAcceleration,
        maxVelocity: maxVelocity,
        momentumRetention: momentumRetention,
        directionChangeRetention: directionChangeRetention,
        maxWheelDelta: maxWheelDelta,
        maxPrecisionDelta: maxPrecisionDelta,
        precisionDeltaThreshold: precisionDeltaThreshold,
        minimumVelocity: minimumVelocity,
        stopVelocity: stopVelocity,
        immediateResponse: immediateResponse ?? this.immediateResponse,
        wheelSmoothingRate: wheelSmoothingRate,
        maxWheelScrollVelocity: maxWheelScrollVelocity,
        maxWheelQueuedDistance: maxWheelQueuedDistance,
        wheelStopDistance: wheelStopDistance,
        desktopDirectManipulationScale: desktopDirectManipulationScale,
        desktopCoastFriction: desktopCoastFriction,
        desktopCoastDeceleration: desktopCoastDeceleration,
        desktopFramePacing: desktopFramePacing,
      );
}

/// Applies premium scrolling to every descendant Flutter [Scrollable].
///
/// Flutter tickers are synchronized to the engine frame scheduler (the native
/// equivalent of requestAnimationFrame), so this supports high-refresh-rate
/// displays without timers or per-event layout work.
///
/// Nested scopes inherit the outer scope's settings, including its opt-out.
/// Surfaces with their own scrolling should use [PremiumScrollExclusion].
class PremiumScrollScope extends StatelessWidget {
  const PremiumScrollScope({
    super.key,
    required this.enabled,
    required this.child,
    this.config = const PremiumScrollPhysicsConfig(),
  });

  final bool enabled;
  final PremiumScrollPhysicsConfig config;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A ScrollBehavior can be hidden behind copyWith or a viewer-specific
    // delegate. Track ownership independently so an embedded scope neither
    // scales trackpad distance/velocity twice nor overrides the global toggle.
    if (context.dependOnInheritedWidgetOfExactType<_PremiumScrollOwner>() !=
        null) {
      return child;
    }
    WaydroidDetection.ensureStarted();

    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    final kineticEnabled = enabled && !reducedMotion;

    return _PremiumScrollOwner(
      child: ScrollConfiguration(
        behavior: PremiumScrollBehavior(
          delegate: ScrollConfiguration.of(context),
          config: config,
          kineticEnabled: kineticEnabled,
        ),
        child: kineticEnabled ? _PremiumScrollDispatcher(child: child) : child,
      ),
    );
  }
}

class _PremiumScrollOwner extends InheritedWidget {
  const _PremiumScrollOwner({required super.child});

  @override
  bool updateShouldNotify(_PremiumScrollOwner oldWidget) => false;
}

/// Opts one [NestedScrollView] into smoothed, coordinated mouse-wheel routing.
///
/// Wrap the owning [NestedScrollView] itself, not just its body. Only regions
/// using that view's exact [NestedScrollViewState.innerController] or
/// [NestedScrollViewState.outerController] opt in. Independent secondary and
/// horizontal controllers, and other nested views below it, keep their existing
/// behavior; this is not a subtree-wide [PremiumScrollExclusion].
///
/// Header and body share one premium wheel queue. Its incremental frame deltas
/// go through the outer position's public [ScrollPosition.pointerScroll], so
/// Flutter still distributes travel between the header and body. Writing either
/// position's pixels directly would bypass that coordination. Exhausted or
/// unsupported coordinators leave the original event to native routing, rather
/// than smoothing an ancestor or replaying an already consumed packet.
///
/// Touch/trackpad physics and frame pacing are unchanged. This marker does not
/// enable premium scrolling or override its global/reduced-motion opt-out.
class PremiumCoordinatedScrollScope extends InheritedWidget {
  const PremiumCoordinatedScrollScope({
    super.key,
    required NestedScrollView super.child,
  });

  static NestedScrollViewState? _ownerForController(
    BuildContext context,
    ScrollController? controller,
  ) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PremiumCoordinatedScrollScope>();
    if (scope == null || controller == null) return null;
    final nested = context.findAncestorStateOfType<NestedScrollViewState>();
    // Checking the owning widget as well as the controllers keeps an embedded,
    // independently coordinated view from implicitly inheriting this opt-in.
    return nested != null &&
            identical(scope.child, nested.widget) &&
            (identical(controller, nested.innerController) ||
                identical(controller, nested.outerController))
        ? nested
        : null;
  }

  @override
  bool updateShouldNotify(PremiumCoordinatedScrollScope oldWidget) =>
      !identical(child, oldWidget.child);
}

/// Adds controlled desktop coasting and elastic edges without a second input
/// engine. Native macOS/mobile physics and discrete wheel routing are retained.
class PremiumScrollBehavior extends ScrollBehavior {
  const PremiumScrollBehavior({
    required this.delegate,
    this.config = const PremiumScrollPhysicsConfig(),
    this.kineticEnabled = true,
  });

  final ScrollBehavior delegate;
  final PremiumScrollPhysicsConfig config;
  final bool kineticEnabled;

  @override
  Set<PointerDeviceKind> get dragDevices => delegate.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      delegate.pointerAxisModifiers;

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      delegate.getPlatform(context);

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) {
    return delegate.getMultitouchDragStrategy(context);
  }

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    final platformBuilder = delegate.velocityTrackerBuilder(context);
    final platform = getPlatform(context);
    if (!kineticEnabled ||
        (platform != TargetPlatform.windows &&
            platform != TargetPlatform.linux)) {
      return platformBuilder;
    }

    return (event) => _ScaledVelocityTracker(
          event is PointerPanZoomStartEvent
              ? _DesktopTrackpadVelocityTracker(
                  context
                      .findAncestorRenderObjectOfType<
                          _RenderPremiumScrollDispatcher>()
                      ?._panSessions[event.pointer],
                )
              : platformBuilder(event),
          config.desktopDirectManipulationScale,
        );
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platformPhysics = delegate.getScrollPhysics(context);
    final platform = getPlatform(context);
    // In Waydroid every touch is a laptop touchpad's two-finger scroll, which
    // a host bridge plays as a finger: it coasts and stretches at the edges as
    // the desktop app's touchpad does, not as a phone's fling.
    final desktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        (platform == TargetPlatform.android && WaydroidDetection.isWaydroid);
    final directManipulationScale = switch (platform) {
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        config.desktopDirectManipulationScale,
      _ => 1.0,
    };
    return kineticEnabled
        ? PremiumKineticScrollPhysics(
            config: config,
            directManipulationScale: directManipulationScale,
            parent: desktop
                ? _DesktopElasticScrollPhysics(
                    config: config,
                    parent: platformPhysics,
                  )
                : platformPhysics,
          )
        : platformPhysics;
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return delegate.buildScrollbar(context, child, details);
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final decorated = delegate.buildOverscrollIndicator(
      context,
      child,
      details,
    );
    if (!kineticEnabled) {
      return decorated;
    }
    return _PremiumScrollRegion(
      controller: details.controller,
      axisDirection: details.direction,
      pointerAxisModifiers: pointerAxisModifiers,
      config: config,
      paceTrackpad: config.desktopFramePacing &&
          (getPlatform(context) == TargetPlatform.windows ||
              getPlatform(context) == TargetPlatform.linux),
      child: NotificationListener<ScrollNotification>(
        onNotification: _RenderPremiumScrollRegion._trackDrag,
        child: decorated,
      ),
    );
  }

  @override
  bool shouldNotify(covariant ScrollBehavior oldDelegate) {
    return oldDelegate is! PremiumScrollBehavior ||
        oldDelegate.config != config ||
        oldDelegate.kineticEnabled != kineticEnabled ||
        oldDelegate.delegate.runtimeType != delegate.runtimeType ||
        delegate.shouldNotify(oldDelegate.delegate);
  }
}

/// Trackpad motion a Scrollable's drag recognizer dropped before its drag
/// began, in user-offset terms, waiting for that drag's first update.
final _trackpadDragLeads = Expando<double>('trackpad drag lead');

/// Whether a ballistic simulation for [metrics] is a drag's release: the drag
/// is still the activity while it hands over.
bool _releasedFromDrag(ScrollMetrics metrics) =>
    metrics is ScrollPosition &&
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    metrics.activity is DragScrollActivity;

double _takeTrackpadDragLead(ScrollMetrics metrics) {
  if (metrics is! ScrollPosition) return 0;
  final lead = _trackpadDragLeads[metrics];
  _trackpadDragLeads[metrics] = null;
  return lead ?? 0;
}

/// Marker physics for enabled premium wheel handling.
///
/// Scales direct input once, before edge resistance. The selected parent owns
/// the sole ballistic simulation; no wheel impulses are added to trackpad pans.
class PremiumKineticScrollPhysics extends ScrollPhysics {
  const PremiumKineticScrollPhysics({
    required this.config,
    this.directManipulationScale = 1.0,
    super.parent,
  }) : assert(
          directManipulationScale > 0 && directManipulationScale <= 1,
        );

  final PremiumScrollPhysicsConfig config;
  final double directManipulationScale;

  // Precision pans should respond immediately, including small reversals.
  @override
  double? get dragStartDistanceMotionThreshold =>
      parent is _DesktopElasticScrollPhysics
          ? null
          : super.dragStartDistanceMotionThreshold;

  @override
  PremiumKineticScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PremiumKineticScrollPhysics(
      config: config,
      directManipulationScale: directManipulationScale,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final paced = FrameSyncedScrollPan.filterOffset(
      position,
      offset + _takeTrackpadDragLead(position),
    );
    if (paced == 0) return 0;
    return super.applyPhysicsToUserOffset(
      position,
      paced * directManipulationScale,
    );
  }
}

/// Physics layered above [PremiumKineticScrollPhysics] that pass user offsets
/// to their parent unchanged and start any release coast of their own from
/// [FrameSyncedScrollPan.takeRelease]. Trackpad pacing reaches through them,
/// so a page with its own coast still scrolls like every other page.
abstract interface class PremiumPacedOuterPhysics {}

/// The premium physics trackpad pacing can drive beneath [physics]: every
/// physics above it must hand user offsets down unchanged and either take
/// the release hand-over or leave the coast to the premium physics.
PremiumKineticScrollPhysics? _pacedPhysicsOf(ScrollPhysics physics) {
  ScrollPhysics? current = physics;
  while (current is PremiumPacedOuterPhysics ||
      current.runtimeType == AlwaysScrollableScrollPhysics ||
      current.runtimeType == RangeMaintainingScrollPhysics) {
    current = current!.parent;
  }
  return current is PremiumKineticScrollPhysics ? current : null;
}

/// Use macOS's rubber band and a critically damped return, but not iOS's
/// repeated-fling boost or the 8x desktop fling speed allowance.
class _DesktopElasticScrollPhysics extends BouncingScrollPhysics {
  const _DesktopElasticScrollPhysics({
    required this.config,
    super.parent,
  }) : super(decelerationRate: ScrollDecelerationRate.fast);

  final PremiumScrollPhysicsConfig config;

  /// UIScrollView's rubber-band constant: just past an edge the page follows
  /// this share of the fingers' travel, ever less as it stretches.
  static const _rubberBand = 0.55;

  /// How far past an edge the page stretches for [travel] pixels of finger
  /// travel past it, in a viewport [extent] long. It never reaches [extent].
  static double _stretch(double travel, double extent) =>
      extent * (1 - 1 / (1 + _rubberBand * travel / extent));

  /// The finger travel past an edge that stretches the page [stretch] pixels.
  static double _travel(double stretch, double extent) {
    final clamped = math.min(stretch, extent * 0.99);
    return extent / _rubberBand * clamped / (extent - clamped);
  }

  @override
  _DesktopElasticScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _DesktopElasticScrollPhysics(
        config: config,
        parent: buildParent(ancestor),
      );

  @override
  double get maxFlingVelocity => config.maxVelocity;

  @override
  double carriedMomentum(double existingVelocity) => 0;

  /// How fast the rubber band stretches per pixel of finger travel, a
  /// [overscrollFraction] of the viewport past an edge.
  @override
  double frictionFactor(double overscrollFraction) =>
      _rubberBand * math.pow(1 - overscrollFraction.clamp(0.0, 1.0), 2);

  /// The rubber band's return: critically damped, the quickest return that
  /// never swings past the edge, and about as quick as macOS's (95% of the
  /// way back in a quarter of a second). A page reaching an edge at v px/s
  /// stretches about v / 54 px past it, in 50 ms.
  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 1, stiffness: 400, damping: 40);

  /// The stretch depends only on how far past the edge the fingers are, as on
  /// macOS: pulling back eases the band exactly as pulling out stretched it,
  /// and a movement that crosses the edge is split there. Flutter's fast rate
  /// eased it one-to-one, so the page sprang back twice as fast as it went.
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final extent = position.viewportDimension;
    if (!extent.isFinite || extent <= 0) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    final min = position.minScrollExtent;
    final max = math.max(position.maxScrollExtent, min);
    final pixels = position.pixels;
    final target = pixels - offset;
    if (pixels >= min && pixels <= max && target >= min && target <= max) {
      return offset;
    }
    // Where the fingers are, in scroll offsets: past an edge they are further
    // out than the stretched page.
    final fingers = pixels < min
        ? min - _travel(min - pixels, extent)
        : pixels > max
            ? max + _travel(pixels - max, extent)
            : pixels;
    final moved = fingers - offset;
    final page = moved < min
        ? min - _stretch(min - moved, extent)
        : moved > max
            ? max + _stretch(moved - max, extent)
            : moved;
    return pixels - page;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange && _releasedFromDrag(position)) {
      // Past an edge the page moved at the rubber band's rate, not the
      // fingers'. Launched at the fingers' speed, it lurched outward the
      // moment they lifted; it carries on at its own speed instead.
      final stretch = math.max(
        position.minScrollExtent - position.pixels,
        position.pixels - position.maxScrollExtent,
      );
      final extent = position.viewportDimension;
      velocity *= extent > 0 ? frictionFactor(stretch / extent) : _rubberBand;
    }
    // Motion the fingers made before lifting that frame pacing has not shown
    // yet: the coast travels it too, starting from what is on screen, rather
    // than the content jumping to it in one frame.
    final release = FrameSyncedScrollPan.releaseOf(position);
    final launch = release?.launch(
          velocity,
          friction: config.desktopCoastFriction,
          deceleration: config.desktopCoastDeceleration,
        ) ??
        velocity;
    final platformTolerance = toleranceFor(position);
    final tolerance = Tolerance(
      distance: platformTolerance.distance,
      velocity: math.min(platformTolerance.velocity, config.stopVelocity),
    );
    if (!position.outOfRange && launch.abs() < tolerance.velocity) {
      return null;
    }
    FrameSyncedScrollPan.takeRelease(position);
    final coast = _DesktopCoastSimulation(
      position: position.pixels,
      velocity: launch,
      leadingExtent: position.minScrollExtent,
      trailingExtent: position.maxScrollExtent,
      friction: config.desktopCoastFriction,
      deceleration: config.desktopCoastDeceleration,
      spring: spring,
      tolerance: tolerance,
    );
    return release?.leading(coast) ?? coast;
  }
}

/// Coasts on [PremiumCoastSimulation], then rubber-bands at an edge.
///
/// The coast's deceleration and the spring both depend only on current
/// position and velocity. Restarting after lazy item/viewport dimensions
/// change therefore cannot re-accelerate the coast. Flutter 3.27's fast
/// bouncing simulation uses a time-dependent constant-deceleration term
/// instead.
class _DesktopCoastSimulation extends Simulation {
  _DesktopCoastSimulation({
    required double position,
    required double velocity,
    required double leadingExtent,
    required double trailingExtent,
    required double friction,
    required double deceleration,
    required SpringDescription spring,
    required super.tolerance,
  }) {
    if (position < leadingExtent || position > trailingExtent) {
      final edge = position.clamp(leadingExtent, trailingExtent);
      _motion = ScrollSpringSimulation(
        spring,
        position,
        edge,
        velocity,
        tolerance: tolerance,
      );
      // A deliberate inward release can cross the boundary instead of merely
      // relaxing toward it. Once inside, friction must own the rest of the
      // trajectory even when no layout happens to restart the activity there.
      if (velocity * (position - edge) < 0) {
        final returning = SpringSimulation(
          spring,
          position,
          edge,
          velocity,
          tolerance: tolerance,
        );
        final outsideSign = (position - edge).sign;
        var upper = 1 / 120;
        bool hasCrossed(double time) =>
            (returning.x(time) - edge) * outsideSign < 0;
        while (upper < 2 && !hasCrossed(upper) && !returning.isDone(upper)) {
          upper *= 2;
        }
        if (hasCrossed(upper)) {
          var lower = 0.0;
          // Resolve the transition once, not in frame callbacks. The desktop
          // spring is at least critically damped, so it can cross this edge
          // at most once.
          for (var iteration = 0; iteration < 32; iteration++) {
            final middle = (lower + upper) / 2;
            if (hasCrossed(middle)) {
              upper = middle;
            } else {
              lower = middle;
            }
          }
          _transitionTime = (lower + upper) / 2;
          _continuation = _DesktopCoastSimulation(
            position: edge,
            velocity: returning.dx(_transitionTime),
            leadingExtent: leadingExtent,
            trailingExtent: trailingExtent,
            friction: friction,
            deceleration: deceleration,
            spring: spring,
            tolerance: tolerance,
          );
        }
      }
      return;
    }

    final coast = PremiumCoastSimulation(
      position: position,
      velocity: velocity,
      friction: friction,
      deceleration: deceleration,
      tolerance: tolerance,
    );
    _motion = coast;
    final double edge;
    if (velocity > 0 && coast.finalX > trailingExtent) {
      edge = trailingExtent;
    } else if (velocity < 0 && coast.finalX < leadingExtent) {
      edge = leadingExtent;
    } else {
      return;
    }
    _transitionTime = coast.timeAtX(edge);
    // The spring takes over at the coast's own speed, so the page decelerates
    // into the edge instead of jolting: clamping that speed halved it in one
    // frame. The critically damped spring keeps even a flick at the fastest
    // release velocity within about 150 px of the edge.
    _continuation = ScrollSpringSimulation(
      spring,
      edge,
      edge,
      coast.dx(_transitionTime),
      tolerance: tolerance,
    );
  }

  late final Simulation _motion;
  Simulation? _continuation;
  double _transitionTime = double.infinity;

  @override
  double x(double time) => time >= _transitionTime
      ? _continuation!.x(time - _transitionTime)
      : _motion.x(time);

  @override
  double dx(double time) => time >= _transitionTime
      ? _continuation!.dx(time - _transitionTime)
      : _motion.dx(time);

  @override
  bool isDone(double time) => time >= _transitionTime
      ? _continuation!.isDone(time - _transitionTime)
      : _motion.isDone(time);
}

class _DesktopPanSession {
  _DesktopPanSession(this.lastInputAt, this.pans);

  Duration lastInputAt;
  Duration? endedAt;
  final List<FrameSyncedScrollPan> pans;

  void update(PointerPanZoomUpdateEvent event) {
    final interval = (event.timeStamp - lastInputAt).inMicroseconds;
    lastInputAt = event.timeStamp;
    if (event.scale != 1 || event.rotation != 0) {
      finish();
      return;
    }
    for (final pan in pans) {
      pan.receive(event.timeStamp, interval);
    }
  }

  void finish({bool flush = true}) {
    for (final pan in pans) {
      pan.dispose(flush: flush);
    }
  }

  void release(Duration stamp) {
    for (final pan in pans) {
      pan.release(stamp);
    }
  }
}

/// The release velocity of a desktop trackpad pan, estimated from the stream a
/// compositor actually delivers.
///
/// Quadratic fitting can invent a reverse fling when a fast pan slows down, so
/// recent segment speeds are weighted as Flutter's macOS tracker does (0.15,
/// 0.65, 0.2, newest last) and the result never exceeds the faster of the last
/// two. Segments span at least 4 ms: a compositor that has not yet locked onto
/// the display's frames delivers bursts of tiny steps stamped in whole
/// milliseconds, and a zero-length segment would read as standing still. One
/// short last step (a paced hand-off ending between frames) weighs only a
/// fifth, while a last segment under a tenth of the one before is an abrupt
/// stop. A timestamp gap resets history even when delayed events arrive in one
/// UI-thread batch, and a reversal at the end releases nothing.
class _DesktopTrackpadVelocityTracker extends VelocityTracker {
  _DesktopTrackpadVelocityTracker(this._session)
      : super.withKind(PointerDeviceKind.trackpad);

  static const _gap = Duration(milliseconds: 40);
  static const _minSegment = Duration(milliseconds: 4);
  static const _horizon = Duration(milliseconds: 100);
  static const _none = VelocityEstimate(
    pixelsPerSecond: Offset.zero,
    confidence: 1,
    duration: Duration.zero,
    offset: Offset.zero,
  );

  final _DesktopPanSession? _session;
  final _samples = <(Duration, Offset)>[];

  @override
  void addPosition(Duration time, Offset position) {
    if (_samples.isNotEmpty) {
      final interval = time - _samples.last.$1;
      if (interval > _gap || interval < Duration.zero) _samples.clear();
    }
    _samples.add((time, position));
    while (_samples.length > 1 && time - _samples.first.$1 > _horizon) {
      _samples.removeAt(0);
    }
  }

  @override
  VelocityEstimate? getVelocityEstimate() {
    if (_samples.isEmpty) return null;
    final newest = _samples.last;
    final endedAt = _session?.endedAt;
    if (endedAt != null && endedAt - newest.$1 > _gap) return _none;

    final points = [newest];
    for (var i = _samples.length - 2; i >= 0 && points.length < 4; i--) {
      if (points.last.$1 - _samples[i].$1 >= _minSegment) {
        points.add(_samples[i]);
      }
    }
    if (points.length < 2) return _none;
    // Newest segment first.
    final speeds = [
      for (var i = 0; i + 1 < points.length; i++)
        (points[i].$2 - points[i + 1].$2) *
            (Duration.microsecondsPerSecond /
                (points[i].$1 - points[i + 1].$1).inMicroseconds),
    ];
    final latest = speeds.first;
    final previous = speeds.length > 1 ? speeds[1] : latest;
    final oldest = speeds.length > 2 ? speeds[2] : previous;
    final weighted = latest * 0.2 + previous * 0.65 + oldest * 0.15;
    double axis(double weighted, double latest, double previous) {
      if (latest == 0 || latest.sign != weighted.sign) return 0;
      if (latest.abs() < previous.abs() / 10) return latest;
      return weighted.sign *
          math.min(weighted.abs(), math.max(latest.abs(), previous.abs()));
    }

    final first = _samples.first;
    return VelocityEstimate(
      pixelsPerSecond: Offset(
        axis(weighted.dx, latest.dx, previous.dx),
        axis(weighted.dy, latest.dy, previous.dy),
      ),
      confidence: 1,
      duration: newest.$1 - first.$1,
      offset: newest.$2 - first.$2,
    );
  }
}

/// Keeps the release velocity in the same coordinate scale as direct desktop
/// manipulation. Scaling at the tracker boundary happens exactly once; a
/// ballistic restart after a content-dimension change therefore preserves the
/// current simulation velocity instead of multiplying it again.
class _ScaledVelocityTracker extends VelocityTracker {
  _ScaledVelocityTracker(this.delegate, this.scale)
      : assert(scale > 0 && scale <= 1),
        super.withKind(delegate.kind);

  final VelocityTracker delegate;
  final double scale;

  @override
  void addPosition(Duration time, Offset position) {
    delegate.addPosition(time, position);
  }

  @override
  VelocityEstimate? getVelocityEstimate() {
    final estimate = delegate.getVelocityEstimate();
    if (estimate == null) {
      return null;
    }
    return VelocityEstimate(
      pixelsPerSecond: estimate.pixelsPerSecond * scale,
      confidence: estimate.confidence,
      duration: estimate.duration,
      offset: estimate.offset * scale,
    );
  }
}

/// Position follows x(t) = x0 + v0/f * (1 - e^(-ft)).
/// Velocity therefore decays continuously and never uses linear easing.
@visibleForTesting
class PremiumKineticScrollSimulation extends Simulation {
  PremiumKineticScrollSimulation({
    required this.position,
    required this.velocity,
    required this.friction,
    required this.stopVelocity,
  })  : assert(friction > 0),
        assert(stopVelocity > 0);

  final double position;
  final double velocity;
  final double friction;
  final double stopVelocity;

  @override
  double x(double time) {
    return position + velocity / friction * (1 - math.exp(-friction * time));
  }

  @override
  double dx(double time) => velocity * math.exp(-friction * time);

  @override
  bool isDone(double time) => dx(time).abs() < stopVelocity;
}

const premiumKineticMaximumFrameIntervalSeconds = 1 / 30;

@immutable
class PremiumKineticScrollFrame {
  const PremiumKineticScrollFrame({
    required this.displacement,
    required this.velocity,
  });

  final Offset displacement;
  final Offset velocity;
}

/// Renderer-independent kinetic state shared by embedded document viewers.
///
/// Renderers provide their own frame scheduler and apply [displacement] to
/// their native surface. Wheel impulses keep their retention, acceleration,
/// friction and stopping behavior; a trackpad release coasts like every page
/// (see [PremiumCoastSimulation]).
class PremiumKineticScrollModel {
  PremiumKineticScrollModel({
    PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
  }) : _config = config;

  PremiumScrollPhysicsConfig _config;
  Offset _velocity = Offset.zero;
  bool _coasting = false;

  PremiumScrollPhysicsConfig get config => _config;
  Offset get velocity => _velocity;
  bool get isActive => _velocity != Offset.zero;

  void configure(PremiumScrollPhysicsConfig config) {
    if (_config != config) {
      _config = config;
      stop();
    }
  }

  Offset addWheelDelta(
    Offset delta, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) {
    _coasting = false;
    final impulse = premiumKineticVelocityImpulse(
      delta: delta,
      kind: kind,
      config: _config,
    );
    _velocity = Offset(
      _accumulateAxis(_velocity.dx, impulse.dx),
      _accumulateAxis(_velocity.dy, impulse.dy),
    );
    return delta * _config.immediateResponse;
  }

  void beginRelease(Offset releaseVelocity) {
    _velocity = Offset(
      releaseVelocity.dx
          .clamp(-_config.maxVelocity, _config.maxVelocity)
          .toDouble(),
      releaseVelocity.dy
          .clamp(-_config.maxVelocity, _config.maxVelocity)
          .toDouble(),
    );
    if (_velocity.distance < _config.minimumVelocity) {
      _velocity = Offset.zero;
    }
    _coasting = isActive;
  }

  PremiumKineticScrollFrame advance(double elapsedSeconds) {
    if (!isActive || elapsedSeconds <= 0) {
      return PremiumKineticScrollFrame(
        displacement: Offset.zero,
        velocity: _velocity,
      );
    }
    final frameSeconds = math.min(
      elapsedSeconds,
      premiumKineticMaximumFrameIntervalSeconds,
    );
    final Offset displacement;
    if (_coasting) {
      // The deceleration acts along the motion, so the direction is kept.
      final speed = _velocity.distance;
      final coast = PremiumCoastSimulation(
        position: 0,
        velocity: speed,
        friction: _config.desktopCoastFriction,
        deceleration: _config.desktopCoastDeceleration,
      );
      displacement = _velocity * (coast.x(frameSeconds) / speed);
      _velocity *= coast.dx(frameSeconds) / speed;
    } else {
      displacement = premiumKineticFrameDisplacement(
        velocity: _velocity,
        friction: _config.friction,
        elapsedSeconds: frameSeconds,
      );
      _velocity = premiumKineticFrameVelocity(
        velocity: _velocity,
        friction: _config.friction,
        elapsedSeconds: frameSeconds,
      );
    }
    if (_velocity.distance < _config.stopVelocity) {
      stop();
    }
    return PremiumKineticScrollFrame(
      displacement: displacement,
      velocity: _velocity,
    );
  }

  void stopAxes({bool horizontal = false, bool vertical = false}) {
    _velocity = Offset(
      horizontal ? 0 : _velocity.dx,
      vertical ? 0 : _velocity.dy,
    );
    if (!isActive) _coasting = false;
  }

  void stop() {
    _velocity = Offset.zero;
    _coasting = false;
  }

  double _accumulateAxis(double existingVelocity, double impulse) {
    if (impulse == 0) {
      return existingVelocity;
    }
    return accumulatePremiumScrollVelocity(
      existingVelocity: existingVelocity,
      impulse: impulse,
      config: _config,
    );
  }
}

const premiumKineticJavaScriptObjectName = '__appFlowyPremiumKineticScroll';

/// Builds the renderer-local frame loop used by embedded browser surfaces.
///
/// Input crosses the platform boundary once. Every animation frame after that
/// runs next to the rendered document with the same equations and constants as
/// [PremiumKineticScrollModel].
String buildPremiumKineticScrollEngineScript({
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
}) =>
    '''
(() => {
  const objectName = '$premiumKineticJavaScriptObjectName';
  const previous = globalThis[objectName];
  if (previous && typeof previous.dispose === 'function') {
    previous.dispose();
  }

  const config = Object.freeze({
    friction: ${config.friction},
    wheelAcceleration: ${config.wheelAcceleration},
    precisionAcceleration: ${config.precisionAcceleration},
    maxVelocity: ${config.maxVelocity},
    momentumRetention: ${config.momentumRetention},
    directionChangeRetention: ${config.directionChangeRetention},
    maxWheelDelta: ${config.maxWheelDelta},
    maxPrecisionDelta: ${config.maxPrecisionDelta},
    precisionDeltaThreshold: ${config.precisionDeltaThreshold},
    minimumVelocity: ${config.minimumVelocity},
    stopVelocity: ${config.stopVelocity},
    immediateResponse: ${config.immediateResponse},
    maximumFrameInterval:
      $premiumKineticMaximumFrameIntervalSeconds,
    boundaryEpsilon: 0.5
  });
  ${buildPremiumCoastJavaScript(friction: config.desktopCoastFriction, deceleration: config.desktopCoastDeceleration)}
  const state = {
    velocityX: 0,
    velocityY: 0,
    residualX: 0,
    residualY: 0,
    horizontalTarget: null,
    verticalTarget: null,
    coasting: false,
    frame: 0,
    lastTime: 0
  };
  const clamp = (value, minimum, maximum) =>
    Math.max(minimum, Math.min(maximum, value));
  const finite = value => Number.isFinite(value) ? value : 0;
  const accumulate = (velocity, impulse) => {
    if (!impulse) return velocity;
    const retained = !velocity
      ? 0
      : Math.sign(velocity) === Math.sign(impulse)
        ? velocity * config.momentumRetention
        : velocity * config.directionChangeRetention;
    return clamp(
      retained + impulse,
      -config.maxVelocity,
      config.maxVelocity
    );
  };
  const axisImpulse = (delta, trackpad) => {
    const precision =
      trackpad || Math.abs(delta) < config.precisionDeltaThreshold;
    const limit = precision
      ? config.maxPrecisionDelta
      : config.maxWheelDelta;
    const acceleration = precision
      ? config.precisionAcceleration
      : config.wheelAcceleration;
    return clamp(delta, -limit, limit) * acceleration;
  };
  const documentScrolls = horizontal => {
    const root = document.scrollingElement || document.documentElement;
    if (!root) return false;
    return (horizontal
      ? root.scrollWidth - root.clientWidth
      : root.scrollHeight - root.clientHeight) > 1;
  };
  const dominant = { h: { value: undefined, at: 0 }, v: { value: undefined, at: 0 } };
  // A single-page application often leaves the document itself unscrollable
  // and moves one big pane instead; without this the page cannot be moved.
  // The search reads every element, so a miss is remembered too.
  const dominantScroller = horizontal => {
    const slot = horizontal ? dominant.h : dominant.v;
    const now = Date.now();
    if (slot.value !== undefined &&
        now - slot.at < 1500 &&
        (slot.value === null || slot.value.isConnected)) {
      return slot.value;
    }
    let best = null;
    let bestArea = 0;
    const candidates = document.body
      ? document.body.querySelectorAll('*')
      : [];
    for (const element of candidates) {
      const extent = horizontal
        ? element.scrollWidth - element.clientWidth
        : element.scrollHeight - element.clientHeight;
      if (extent <= 1) continue;
      const style = getComputedStyle(element);
      const overflow = horizontal ? style.overflowX : style.overflowY;
      if (overflow !== 'auto' && overflow !== 'scroll') continue;
      const rect = element.getBoundingClientRect();
      const area = rect.width * rect.height;
      if (area > bestArea) {
        bestArea = area;
        best = element;
      }
    }
    slot.value = best;
    slot.at = now;
    return best;
  };
  const findScrollTarget = (positionX, positionY, horizontal) => {
    let element = Number.isFinite(positionX) && Number.isFinite(positionY)
      ? document.elementFromPoint(positionX, positionY)
      : null;
    while (element && element !== document.documentElement) {
      const scrollExtent = horizontal
        ? element.scrollWidth - element.clientWidth
        : element.scrollHeight - element.clientHeight;
      if (scrollExtent > 1) {
        const style = getComputedStyle(element);
        const overflow = horizontal ? style.overflowX : style.overflowY;
        if (overflow === 'auto' || overflow === 'scroll') {
          return element;
        }
      }
      element = element.parentElement;
    }
    return documentScrolls(horizontal) ? null : dominantScroller(horizontal);
  };
  const updateHorizontalTarget = (positionX, positionY) => {
    const target = findScrollTarget(positionX, positionY, true);
    if (target !== state.horizontalTarget) {
      state.velocityX = 0;
      state.residualX = 0;
      state.horizontalTarget = target;
    }
  };
  const updateVerticalTarget = (positionX, positionY) => {
    const target = findScrollTarget(positionX, positionY, false);
    if (target !== state.verticalTarget) {
      state.velocityY = 0;
      state.residualY = 0;
      state.verticalTarget = target;
    }
  };
  const move = (deltaX, deltaY) => {
    const requestedX = finite(deltaX) + state.residualX;
    const requestedY = finite(deltaY) + state.residualY;
    const horizontalTarget =
      state.horizontalTarget && state.horizontalTarget.isConnected
        ? state.horizontalTarget
        : null;
    const verticalTarget =
      state.verticalTarget && state.verticalTarget.isConnected
        ? state.verticalTarget
        : null;
    const beforeX = horizontalTarget
      ? horizontalTarget.scrollLeft
      : window.scrollX;
    const beforeY = verticalTarget
      ? verticalTarget.scrollTop
      : window.scrollY;
    if (!horizontalTarget && !verticalTarget) {
      window.scrollBy(requestedX, requestedY);
    } else if (horizontalTarget &&
        verticalTarget &&
        horizontalTarget === verticalTarget) {
      horizontalTarget.scrollBy(requestedX, requestedY);
    } else {
      if (horizontalTarget) {
        horizontalTarget.scrollBy(requestedX, 0);
      } else {
        window.scrollBy(requestedX, 0);
      }
      if (verticalTarget) {
        verticalTarget.scrollBy(0, requestedY);
      } else {
        window.scrollBy(0, requestedY);
      }
    }
    const actualX = (horizontalTarget
      ? horizontalTarget.scrollLeft
      : window.scrollX) - beforeX;
    const actualY = (verticalTarget
      ? verticalTarget.scrollTop
      : window.scrollY) - beforeY;
    const tolerance = Math.max(
      config.boundaryEpsilon,
      1 / Math.max(window.devicePixelRatio, 1) + Number.EPSILON
    );
    const blockedX = Math.abs(actualX - requestedX) > tolerance;
    const blockedY = Math.abs(actualY - requestedY) > tolerance;
    state.residualX = blockedX ? 0 : requestedX - actualX;
    state.residualY = blockedY ? 0 : requestedY - actualY;
    return { blockedX, blockedY };
  };
  const halt = () => {
    if (state.frame) cancelAnimationFrame(state.frame);
    state.frame = 0;
    state.lastTime = 0;
    state.velocityX = 0;
    state.velocityY = 0;
    state.residualX = 0;
    state.residualY = 0;
    state.coasting = false;
  };
  const stop = () => {
    halt();
    state.horizontalTarget = null;
    state.verticalTarget = null;
  };
  const tick = time => {
    state.frame = 0;
    if (!state.lastTime) {
      state.lastTime = time;
      state.frame = requestAnimationFrame(tick);
      return;
    }

    const elapsed = Math.min(
      Math.max((time - state.lastTime) / 1000, 0),
      config.maximumFrameInterval
    );
    state.lastTime = time;
    if (state.coasting) {
      // A trackpad release coasts like every page, along its direction.
      const speed = Math.hypot(state.velocityX, state.velocityY);
      const step = coastStep(speed, elapsed);
      const movement = move(
        state.velocityX / speed * step.distance,
        state.velocityY / speed * step.distance
      );
      state.velocityX =
        movement.blockedX ? 0 : state.velocityX / speed * step.speed;
      state.velocityY =
        movement.blockedY ? 0 : state.velocityY / speed * step.speed;
    } else {
      const decay = Math.exp(-config.friction * elapsed);
      const displacementX =
        state.velocityX / config.friction * (1 - decay);
      const displacementY =
        state.velocityY / config.friction * (1 - decay);
      const movement = move(displacementX, displacementY);

      state.velocityX =
        movement.blockedX
          ? 0
          : state.velocityX * decay;
      state.velocityY =
        movement.blockedY
          ? 0
          : state.velocityY * decay;
    }
    if (Math.hypot(state.velocityX, state.velocityY) <
        config.stopVelocity) {
      stop();
      return;
    }
    state.frame = requestAnimationFrame(tick);
  };
  const start = () => {
    if (!state.frame &&
        Math.hypot(state.velocityX, state.velocityY) >=
          config.stopVelocity) {
      state.lastTime = 0;
      state.frame = requestAnimationFrame(tick);
    }
  };

  globalThis[objectName] = {
    wheel(deltaX, deltaY, trackpad, positionX, positionY) {
      deltaX = finite(deltaX);
      deltaY = finite(deltaY);
      if (deltaX) updateHorizontalTarget(positionX, positionY);
      if (deltaY) updateVerticalTarget(positionX, positionY);
      state.coasting = false;
      move(
        deltaX * config.immediateResponse,
        deltaY * config.immediateResponse
      );
      state.velocityX = accumulate(
        state.velocityX,
        axisImpulse(deltaX, trackpad === true)
      );
      state.velocityY = accumulate(
        state.velocityY,
        axisImpulse(deltaY, trackpad === true)
      );
      start();
    },
    beginPan(positionX, positionY) {
      stop();
      updateHorizontalTarget(positionX, positionY);
      updateVerticalTarget(positionX, positionY);
    },
    pan(deltaX, deltaY, positionX, positionY) {
      if (deltaX) updateHorizontalTarget(positionX, positionY);
      if (deltaY) updateVerticalTarget(positionX, positionY);
      move(deltaX, deltaY);
    },
    release(velocityX, velocityY) {
      state.velocityX = clamp(
        finite(velocityX),
        -config.maxVelocity,
        config.maxVelocity
      );
      state.velocityY = clamp(
        finite(velocityY),
        -config.maxVelocity,
        config.maxVelocity
      );
      if (Math.hypot(state.velocityX, state.velocityY) <
          config.minimumVelocity) {
        halt();
        return;
      }
      state.coasting = true;
      start();
    },
    stop,
    snapshot() {
      return {
        velocityX: state.velocityX,
        velocityY: state.velocityY,
        residualX: state.residualX,
        residualY: state.residualY,
        horizontalTarget:
          state.horizontalTarget ? state.horizontalTarget.tagName : null,
        verticalTarget:
          state.verticalTarget ? state.verticalTarget.tagName : null,
        active: state.frame !== 0,
        scrollX: window.scrollX,
        scrollY: window.scrollY
      };
    },
    dispose() {
      stop();
      delete globalThis[objectName];
    }
  };
})();
''';

String buildPremiumKineticWheelCommand(
  Offset delta, {
  required PointerDeviceKind kind,
  Offset? position,
}) =>
    'globalThis.$premiumKineticJavaScriptObjectName.wheel('
    '${_javaScriptNumber(delta.dx)},${_javaScriptNumber(delta.dy)},'
    '${kind == PointerDeviceKind.trackpad}'
    '${_javaScriptPosition(position)});';

String buildPremiumKineticBeginPanCommand({Offset? position}) =>
    'globalThis.$premiumKineticJavaScriptObjectName.beginPan('
    '${_javaScriptCoordinates(position)});';

String buildPremiumKineticPanCommand(Offset delta, {Offset? position}) =>
    'globalThis.$premiumKineticJavaScriptObjectName.pan('
    '${_javaScriptNumber(delta.dx)},${_javaScriptNumber(delta.dy)}'
    '${_javaScriptPosition(position)});';

String buildPremiumKineticReleaseCommand(Offset velocity) =>
    'globalThis.$premiumKineticJavaScriptObjectName.release('
    '${_javaScriptNumber(velocity.dx)},${_javaScriptNumber(velocity.dy)});';

String buildPremiumKineticStopCommand() =>
    'globalThis.$premiumKineticJavaScriptObjectName.stop();';

String _javaScriptPosition(Offset? position) =>
    position == null ? '' : ',${_javaScriptCoordinates(position)}';

String _javaScriptCoordinates(Offset? position) => position == null
    ? ''
    : '${_javaScriptNumber(position.dx)},'
        '${_javaScriptNumber(position.dy)}';

String _javaScriptNumber(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Must be finite');
  }
  return value.toString();
}

double premiumKineticDecay({
  required double friction,
  required double elapsedSeconds,
}) =>
    math.exp(-friction * elapsedSeconds);

Offset premiumKineticFrameDisplacement({
  required Offset velocity,
  required double friction,
  required double elapsedSeconds,
}) =>
    velocity /
    friction *
    (1 -
        premiumKineticDecay(
          friction: friction,
          elapsedSeconds: elapsedSeconds,
        ));

Offset premiumKineticFrameVelocity({
  required Offset velocity,
  required double friction,
  required double elapsedSeconds,
}) =>
    velocity *
    premiumKineticDecay(
      friction: friction,
      elapsedSeconds: elapsedSeconds,
    );

Offset premiumKineticVelocityImpulse({
  required Offset delta,
  required PointerDeviceKind kind,
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
}) =>
    Offset(
      premiumScrollVelocityImpulse(
        delta: delta.dx,
        kind: kind,
        config: config,
      ),
      premiumScrollVelocityImpulse(
        delta: delta.dy,
        kind: kind,
        config: config,
      ),
    );

double premiumScrollVelocityImpulse({
  required double delta,
  required PointerDeviceKind kind,
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
}) {
  final isPrecisionInput = kind == PointerDeviceKind.trackpad ||
      delta.abs() < config.precisionDeltaThreshold;
  final limit =
      isPrecisionInput ? config.maxPrecisionDelta : config.maxWheelDelta;
  final acceleration = isPrecisionInput
      ? config.precisionAcceleration
      : config.wheelAcceleration;
  return delta.clamp(-limit, limit) * acceleration;
}

double accumulatePremiumScrollVelocity({
  required double existingVelocity,
  required double impulse,
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
}) {
  final retainedVelocity = existingVelocity == 0
      ? 0.0
      : existingVelocity.sign == impulse.sign
          ? existingVelocity * config.momentumRetention
          : existingVelocity * config.directionChangeRetention;
  return (retainedVelocity + impulse).clamp(
    -config.maxVelocity,
    config.maxVelocity,
  );
}

@visibleForTesting
double normalizePremiumWheelDistance({
  required double delta,
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
}) {
  return delta.clamp(-config.maxWheelDelta, config.maxWheelDelta).toDouble();
}

const _maximumWheelFrameIntervalSeconds = 1 / 30;

/// Returns one frame of bounded exponential movement toward the unconsumed
/// wheel distance. The returned displacement never exceeds [remainingDistance]
/// and never amplifies the operating-system delta.
@visibleForTesting
double premiumWheelFrameDisplacement({
  required double remainingDistance,
  required double elapsedSeconds,
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
}) {
  if (remainingDistance == 0 || elapsedSeconds <= 0) {
    return 0;
  }
  final frameSeconds = math.min(
    elapsedSeconds,
    _maximumWheelFrameIntervalSeconds,
  );
  final decay = math.exp(-config.wheelSmoothingRate * frameSeconds);
  final exponentialStep = remainingDistance * (1 - decay);
  final maximumStep = config.maxWheelScrollVelocity * frameSeconds;
  return exponentialStep.clamp(-maximumStep, maximumStep).toDouble();
}

class _PremiumScrollDispatcher extends SingleChildRenderObjectWidget {
  const _PremiumScrollDispatcher({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPremiumScrollDispatcher()..view = View.maybeOf(context);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPremiumScrollDispatcher renderObject,
  ) {
    renderObject.view = View.maybeOf(context);
  }
}

class _RenderPremiumScrollDispatcher extends RenderProxyBox {
  final _panSessions = <int, _DesktopPanSession>{};

  /// The view whose device pixel ratio Android's scroll unit is scaled by.
  FlutterView? view;

  /// Android's wheel acceleration state per input device, horizontal and
  /// vertical, replayed to recover Waydroid's raw notches.
  final _waydroidDecoders = <int,
      (AndroidWheelAccelerationDecoder, AndroidWheelAccelerationDecoder)>{};

  /// The logical distance Waydroid's notches in [event] scrolled.
  ///
  /// Every wheel event is decoded, wherever it is routed, so that the
  /// replayed acceleration stays in step with Android's.
  Offset _decodeWaydroidNotches(PointerScrollEvent event) {
    final unit = androidScrollUnit(view?.devicePixelRatio ?? 1);
    final (horizontal, vertical) = _waydroidDecoders.putIfAbsent(
      event.device,
      () => (
        AndroidWheelAccelerationDecoder(),
        AndroidWheelAccelerationDecoder(),
      ),
    );
    final stampUs = event.timeStamp.inMicroseconds;
    return Offset(
      horizontal.decode(stampUs, event.scrollDelta.dx / unit) *
          waydroidNotchDistance,
      vertical.decode(stampUs, event.scrollDelta.dy / unit) *
          waydroidNotchDistance,
    );
  }

  void _stopWaydroidStreams({_RenderPremiumScrollRegion? except}) {
    for (final region in _hitRegions) {
      if (!identical(region, except)) region.stopWaydroid();
    }
  }

  /// Routes Waydroid touchpad notches like wheel input, but to a stream that
  /// keeps to its scrollable until it ends and that plays them as continuous
  /// motion with a release coast.
  void _routeWaydroidScroll(PointerScrollEvent event, Offset distance) {
    final resolver = GestureBinding.instance.pointerSignalResolver;
    for (final region in _hitRegions) {
      if (region.continuesWaydroidStream(event, distance)) {
        resolver.register(
          event,
          (_) => region.addWaydroidNotches(event, distance),
        );
        return;
      }
    }
    for (final region in _hitRegions) {
      if (region.coordinatesWheel(event, delta: distance)) {
        final owner = region.coordinatedWheelOwner;
        final candidate =
            owner?.coordinatedCandidateFor(event, delta: distance);
        _cancelCoordinatedWheels(except: candidate == null ? null : owner);
        if (candidate != null && owner != null) {
          _stopWaydroidStreams(except: owner);
          resolver.register(
            event,
            (_) => owner.startWaydroidStream(event, candidate),
          );
        }
        return;
      }
      final candidate = region.candidateFor(event, delta: distance);
      if (candidate == null) continue;
      _cancelCoordinatedWheels();
      // New fingers moving stop any other coast, as a touch-down would.
      _stopWaydroidStreams(except: region);
      resolver.register(
        event,
        (_) => region.startWaydroidStream(event, candidate),
      );
      return;
    }
    _cancelCoordinatedWheels();
  }

  List<_RenderPremiumScrollRegion> _hitRegions = const [];
  bool _hitPremiumExclusion = false;

  void _cancelCoordinatedWheels({_RenderPremiumScrollRegion? except}) {
    for (final region in _hitRegions) {
      if (!identical(region, except)) region.cancelCoordinatedWheel();
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }

    // Register before descendants so wheel routing runs before Flutter's
    // immediate Scrollable.pointerScroll listener.
    result.add(BoxHitTestEntry(this, position));
    final hitChild = hitTestChildren(result, position: position);
    _hitRegions = result.path
        .map((entry) => entry.target)
        .whereType<_RenderPremiumScrollRegion>()
        .toList(growable: false);
    _hitPremiumExclusion = result.path
        .map((entry) => entry.target)
        .whereType<_RenderPremiumScrollExclusion>()
        .isNotEmpty;
    return hitChild || true;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    // Hit-test delivery precedes the gesture router's release calculation.
    // Flutter's tracker samples updates, not the end packet, and its stopwatch
    // cannot detect an event-time pause when packets are delivered in a batch.
    if (event is PointerPanZoomStartEvent) {
      _cancelCoordinatedWheels();
      _panSessions.remove(event.pointer)?.finish(flush: false);
      _panSessions[event.pointer] = _DesktopPanSession(
        event.timeStamp,
        _hitPremiumExclusion
            ? []
            : [
                for (final region in _hitRegions)
                  ...region.prepareTrackpadPan(startedAt: event.timeStamp),
              ],
      );
    } else if (event is PointerPanZoomUpdateEvent) {
      _panSessions[event.pointer]?.update(event);
    } else if (event is PointerPanZoomEndEvent) {
      final session = _panSessions.remove(event.pointer);
      session?.endedAt = event.timeStamp;
      session?.release(event.timeStamp);
    } else if (event is PointerCancelEvent) {
      _cancelCoordinatedWheels();
      _panSessions.remove(event.pointer)?.finish(flush: false);
    } else if (event is PointerDownEvent) {
      _cancelCoordinatedWheels();
      for (final region in _hitRegions) {
        region.cancelTrackpadPans(flush: true);
        region.stopWaydroid();
      }
    }
    if (event is PointerScrollEvent &&
        event.kind == PointerDeviceKind.mouse &&
        WaydroidDetection.isWaydroid) {
      final distance = _decodeWaydroidNotches(event);
      if (_hitPremiumExclusion) {
        _cancelCoordinatedWheels();
      } else if (distance != Offset.zero) {
        _routeWaydroidScroll(event, distance);
      }
      return;
    }
    if (_hitPremiumExclusion) {
      if (event is PointerScrollEvent ||
          event is PointerScrollInertiaCancelEvent) {
        _cancelCoordinatedWheels();
      }
      return;
    }

    if (event is PointerScrollEvent) {
      for (final region in _hitRegions) {
        if (region.coordinatesWheel(event)) {
          final owner = region.coordinatedWheelOwner;
          final candidate = event.kind == PointerDeviceKind.mouse
              ? owner?.coordinatedCandidateFor(event)
              : null;
          _cancelCoordinatedWheels(except: candidate == null ? null : owner);
          if (candidate != null && owner != null) {
            GestureBinding.instance.pointerSignalResolver.register(
              event,
              (_) => owner.startKineticScroll(event, candidate),
            );
          }
          // A body at zero can still move its header. Only a fully exhausted
          // coordinator falls back; stop the premium ancestor search either
          // way, leaving native boundary/unsupported-input handling intact.
          return;
        }
        final candidate = region.candidateFor(event);
        if (candidate == null) {
          continue;
        }
        _cancelCoordinatedWheels();
        // Precision trackpads already provide direct pan/zoom updates and a
        // platform velocity estimate. Let Flutter consume those unchanged.
        if (event.kind != PointerDeviceKind.mouse) {
          return;
        }
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          (_) => region.startKineticScroll(event, candidate),
        );
        return;
      }
      _cancelCoordinatedWheels();
    } else if (event is PointerScrollInertiaCancelEvent) {
      for (final region in _hitRegions) {
        region.resetMomentumTracking(stopActivity: true);
      }
    }
  }

  @override
  void detach() {
    for (final session in _panSessions.values) {
      session.finish(flush: false);
    }
    _panSessions.clear();
    super.detach();
  }
}

class _PremiumScrollRegion extends SingleChildRenderObjectWidget {
  const _PremiumScrollRegion({
    required this.controller,
    required this.axisDirection,
    required this.pointerAxisModifiers,
    required this.config,
    required this.paceTrackpad,
    required super.child,
  });

  final ScrollController? controller;
  final AxisDirection axisDirection;
  final Set<LogicalKeyboardKey> pointerAxisModifiers;
  final PremiumScrollPhysicsConfig config;
  final bool paceTrackpad;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPremiumScrollRegion(
      controller: controller,
      axisDirection: axisDirection,
      pointerAxisModifiers: pointerAxisModifiers,
      config: config,
      paceTrackpad: paceTrackpad,
      coordinatedView: PremiumCoordinatedScrollScope._ownerForController(
        context,
        controller,
      ),
      scrollable: context.findAncestorStateOfType<ScrollableState>(),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPremiumScrollRegion renderObject,
  ) {
    renderObject
      ..controller = controller
      ..scrollable = context.findAncestorStateOfType<ScrollableState>()
      ..axisDirection = axisDirection
      ..pointerAxisModifiers = pointerAxisModifiers
      ..paceTrackpad = paceTrackpad
      ..coordinatedView =
          PremiumCoordinatedScrollScope._ownerForController(context, controller)
      ..config = config;
  }
}

class _PremiumScrollCandidate {
  const _PremiumScrollCandidate({
    required this.position,
    required this.delta,
    this.coordinatedView,
  });

  final ScrollPosition position;
  final double delta;
  final NestedScrollViewState? coordinatedView;
}

// Read live geometry, not a cached combined extent: collapsing the header and
// resizing the viewport both change the inner range. Page snapping and mixed
// axes retain native handling rather than becoming a pixel-distance animation.
List<ScrollPosition>? _coordinatedWheelPositions(NestedScrollViewState view) {
  if (!view.mounted || view.outerController.positions.length != 1) return null;
  final outer = view.outerController.position;
  final positions = [outer, ...view.innerController.positions];
  for (final position in positions) {
    if (!position.hasPixels ||
        !position.hasContentDimensions ||
        position.outOfRange ||
        position.axisDirection != outer.axisDirection) {
      return null;
    }
    for (ScrollPhysics? physics = position.physics;
        physics != null;
        physics = physics.parent) {
      if (physics is PageScrollPhysics) return null;
    }
  }
  return positions;
}

bool _canScrollCoordinated(Iterable<ScrollPosition> positions, double delta) =>
    delta != 0 &&
    positions.any(
      (position) =>
          position.physics.shouldAcceptUserOffset(position) &&
          (delta > 0
              ? position.pixels < position.maxScrollExtent
              : position.pixels > position.minScrollExtent),
    );

class _RenderPremiumScrollRegion extends RenderProxyBox {
  _RenderPremiumScrollRegion({
    required ScrollController? controller,
    required AxisDirection axisDirection,
    required this.pointerAxisModifiers,
    required PremiumScrollPhysicsConfig config,
    required this.paceTrackpad,
    required NestedScrollViewState? coordinatedView,
    required this.scrollable,
  })  : _controller = controller,
        _axisDirection = axisDirection,
        _coordinatedView = coordinatedView,
        _config = config;

  _PremiumWheelScrollActivity? _activeActivity;
  _WaydroidStream? _waydroid;
  final _panBindings = <FrameSyncedScrollPan>{};
  bool paceTrackpad;
  ScrollableState? scrollable;

  /// Where the latest trackpad pan over this region began, in local
  /// coordinates. A trackpad pan never moves the pointer itself.
  Offset? _trackpadPanOrigin;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerPanZoomStartEvent) {
      _trackpadPanOrigin = event.localPosition;
    }
  }

  /// Until another recognizer (two-finger history swipe, a nested scroll
  /// view) gives the pan up, a Scrollable's drag recognizer holds its motion
  /// back, then starts the drag where the fingers have got to and drops that
  /// motion (DragStartBehavior.start). That made every scroll start sticky and
  /// left the page behind the fingers for the whole gesture. Trackpads have no
  /// touch slop to hide, so the dropped motion is handed to the first update.
  static bool _trackDrag(ScrollNotification notification) {
    if (notification.depth == 0 &&
        (notification is ScrollStartNotification ||
            notification is ScrollEndNotification)) {
      notification.context
          ?.findAncestorRenderObjectOfType<_RenderPremiumScrollRegion>()
          ?._trackDragOf(notification);
    }
    return false;
  }

  void _trackDragOf(ScrollNotification notification) {
    final position = scrollable?.position;
    if (position == null) return;
    _trackpadDragLeads[position] = null;
    // A nested scroll view's coordinator splits one drag between positions
    // itself; a lead added inside one of them would be replayed by the other.
    if (notification is! ScrollStartNotification ||
        position is! ScrollPositionWithSingleContext) {
      return;
    }
    final details = notification.dragDetails;
    final origin = _trackpadPanOrigin;
    if (details == null ||
        details.kind != PointerDeviceKind.trackpad ||
        origin == null) {
      return;
    }
    final dropped = details.localPosition - origin;
    final lead = switch (position.axisDirection) {
      AxisDirection.down => dropped.dy,
      AxisDirection.up => -dropped.dy,
      AxisDirection.right => dropped.dx,
      AxisDirection.left => -dropped.dx,
    };
    if (lead != 0 && lead.isFinite) _trackpadDragLeads[position] = lead;
  }

  NestedScrollViewState? get coordinatedView => _coordinatedView;
  NestedScrollViewState? _coordinatedView;
  set coordinatedView(NestedScrollViewState? value) {
    if (identical(_coordinatedView, value)) return;
    cancelCoordinatedWheel();
    _coordinatedView = value;
  }

  void cancelCoordinatedWheel() {
    final activity = _activeActivity;
    if (activity?.coordinatedView != null) activity!.cancelMomentum();
  }

  _RenderPremiumScrollRegion? get coordinatedWheelOwner {
    final view = coordinatedView;
    if (view == null || !view.mounted) return null;
    RenderObject? current = this;
    while (current != null) {
      if (current is _RenderPremiumScrollRegion &&
          identical(current.coordinatedView, view) &&
          identical(current.controller, view.outerController)) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  List<FrameSyncedScrollPan> prepareTrackpadPan({Duration? startedAt}) {
    final controller = _controller;
    if (!attached || !paceTrackpad || controller == null) return [];
    // A controller may drive several views. Only this region's Scrollable is
    // a candidate; a pan over another view must not discard its pending input.
    final position = scrollable?.position;
    final premium = position == null ? null : _pacedPhysicsOf(position.physics);
    if (position is! ScrollPositionWithSingleContext ||
        !controller.positions.contains(position) ||
        premium == null ||
        !position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return [];
    }
    final context = position.context.notificationContext;
    final refreshRate = context == null
        ? 60.0
        : View.maybeOf(context)?.display.refreshRate ?? 60.0;
    if (!refreshRate.isFinite || refreshRate <= 90) return [];
    late final FrameSyncedScrollPan pan;
    pan = FrameSyncedScrollPan(
      controller: controller,
      position: position,
      refreshRate: refreshRate,
      directScale: premium.directManipulationScale,
      onDispose: () => _panBindings.remove(pan),
      startedAt: startedAt,
    );
    _panBindings.add(pan);
    return [pan];
  }

  void cancelTrackpadPans({bool flush = false}) {
    for (final pan in _panBindings.toList()) {
      pan.dispose(flush: flush);
    }
  }

  ScrollController? get controller => _controller;
  ScrollController? _controller;
  set controller(ScrollController? value) {
    if (_controller == value) {
      return;
    }
    _controller = value;
    resetMomentumTracking(stopActivity: true);
  }

  AxisDirection get axisDirection => _axisDirection;
  AxisDirection _axisDirection;
  set axisDirection(AxisDirection value) {
    if (_axisDirection == value) {
      return;
    }
    _axisDirection = value;
    resetMomentumTracking(stopActivity: true);
  }

  Set<LogicalKeyboardKey> pointerAxisModifiers;

  PremiumScrollPhysicsConfig get config => _config;
  PremiumScrollPhysicsConfig _config;
  set config(PremiumScrollPhysicsConfig value) {
    if (_config == value) {
      return;
    }
    _config = value;
    resetMomentumTracking(stopActivity: true);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    hitTestChildren(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  /// [delta], when given, replaces the event's own scroll delta: Waydroid
  /// notches are routed by the distance they actually scroll.
  bool coordinatesWheel(PointerScrollEvent event, {Offset? delta}) =>
      coordinatedView != null && _eventDelta(event, axisDirection, delta) != 0;

  _PremiumScrollCandidate? coordinatedCandidateFor(
    PointerScrollEvent event, {
    Offset? delta,
  }) {
    final view = coordinatedView;
    if (!attached || view == null) return null;
    final positions = _coordinatedWheelPositions(view);
    final axisDelta = _eventDelta(event, axisDirection, delta);
    if (positions == null || !_canScrollCoordinated(positions, axisDelta)) {
      return null;
    }
    return _PremiumScrollCandidate(
      position: positions.first,
      delta: axisDelta,
      coordinatedView: view,
    );
  }

  _PremiumScrollCandidate? candidateFor(
    PointerScrollEvent event, {
    Offset? delta,
  }) {
    final scrollController = controller;
    if (scrollController == null || !scrollController.hasClients) {
      return null;
    }

    for (final position in scrollController.positions) {
      if (!position.hasContentDimensions ||
          !position.physics.shouldAcceptUserOffset(position)) {
        continue;
      }
      final axisDelta = _eventDelta(event, position.axisDirection, delta);
      if (axisDelta == 0) {
        continue;
      }
      final target = (position.pixels + axisDelta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target != position.pixels) {
        return _PremiumScrollCandidate(position: position, delta: axisDelta);
      }
    }
    return null;
  }

  double _eventDelta(
    PointerScrollEvent event,
    AxisDirection direction, [
    Offset? scrollDelta,
  ]) {
    final flipAxes = event.kind == PointerDeviceKind.mouse &&
        HardwareKeyboard.instance.logicalKeysPressed
            .any(pointerAxisModifiers.contains);
    final axis = flipAxes
        ? flipAxis(axisDirectionToAxis(direction))
        : axisDirectionToAxis(direction);
    final delta = scrollDelta ?? event.scrollDelta;
    final axisDelta = switch (axis) {
      Axis.horizontal => delta.dx,
      Axis.vertical => delta.dy,
    };
    return axisDirectionIsReversed(direction) ? -axisDelta : axisDelta;
  }

  /// Whether Waydroid notches scrolling [distance] continue the stream this
  /// region is playing. A stream keeps to its scrollable, as a drag does,
  /// even while pressed against an edge, until it has ended.
  bool continuesWaydroidStream(PointerScrollEvent event, Offset distance) {
    final stream = _waydroid;
    return attached &&
        stream != null &&
        stream.isLive(event.timeStamp) &&
        _eventDelta(event, stream.axisDirection, distance) != 0;
  }

  void addWaydroidNotches(PointerScrollEvent event, Offset distance) {
    final stream = _waydroid;
    if (stream == null || !attached) return;
    stream.add(
      event.timeStamp,
      _eventDelta(event, stream.axisDirection, distance),
    );
  }

  void startWaydroidStream(
    PointerScrollEvent event,
    _PremiumScrollCandidate candidate,
  ) {
    if (!attached) return;
    resetMomentumTracking(stopActivity: true);
    _waydroid?.dispose();
    final position = candidate.position;
    final stream = _waydroid = _WaydroidStream(
      position: position,
      axisDirection: candidate.coordinatedView == null
          ? position.axisDirection
          : axisDirection,
      coordinatedView: candidate.coordinatedView,
      onDisposed: (disposed) {
        if (identical(_waydroid, disposed)) _waydroid = null;
      },
    );
    stream.add(event.timeStamp, candidate.delta);
  }

  /// Stops Waydroid motion where it is, as a touch-down would.
  void stopWaydroid() => _waydroid?.stop();

  void startKineticScroll(
    PointerScrollEvent event,
    _PremiumScrollCandidate candidate,
  ) {
    final position = candidate.position;
    if (position is! ScrollActivityDelegate) {
      position.pointerScroll(candidate.delta);
      return;
    }
    final delegate = position as ScrollActivityDelegate;

    final distance = normalizePremiumWheelDistance(
      delta: candidate.delta,
      config: config,
    );
    if (position is ScrollPositionWithSingleContext) {
      // This activity replaces pointerScroll, so it must preserve the same
      // direction state without using pointerScroll's immediate pixel jump.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      position.updateUserScrollDirection(
        candidate.delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward,
      );
    }

    final activeActivity = _activeActivity;
    if (activeActivity != null &&
        activeActivity.canReuse &&
        identical(activeActivity.delegate, position) &&
        identical(activeActivity.coordinatedView, candidate.coordinatedView)) {
      activeActivity.addScrollDistance(distance);
      return;
    }

    cancelCoordinatedWheel();
    _launchActivity(
      position,
      delegate,
      distance,
      coordinatedView: candidate.coordinatedView,
    );
  }

  void _launchActivity(
    ScrollPosition position,
    ScrollActivityDelegate delegate,
    double distance, {
    NestedScrollViewState? coordinatedView,
  }) {
    if (!attached || !position.hasPixels || distance == 0) {
      delegate.goBallistic(0);
      resetMomentumTracking();
      return;
    }

    final coordinatedPositions = coordinatedView == null
        ? <ScrollPosition>[]
        : _coordinatedWheelPositions(coordinatedView);
    if (coordinatedPositions == null) return;
    if (coordinatedView != null) {
      // Stop native motion without moving either viewport. The wheel queue
      // lives on the outer region, not on either position: pointerScroll itself
      // replaces both native activities on each call.
      position.pointerScroll(0);
    }

    final notificationContext = position.context.notificationContext;
    final reportedRefreshRate = notificationContext == null
        ? 60.0
        : View.maybeOf(notificationContext)?.display.refreshRate ?? 60.0;
    final refreshRate = reportedRefreshRate.isFinite && reportedRefreshRate > 0
        ? reportedRefreshRate
        : 60.0;
    final initialFrameDuration = Duration(
      microseconds: math.max(
        1,
        (Duration.microsecondsPerSecond / refreshRate).round(),
      ),
    );

    late final _PremiumWheelScrollActivity activity;
    activity = _PremiumWheelScrollActivity(
      delegate,
      vsync: position.context.vsync,
      config: config,
      initialFrameDuration: initialFrameDuration,
      coordinatedView: coordinatedView,
      coordinatedPositions: coordinatedPositions,
      onDispose: (disposedActivity) {
        if (identical(_activeActivity, disposedActivity)) {
          _activeActivity = null;
        }
      },
    )..addScrollDistance(distance);
    _activeActivity = activity;
    if (coordinatedView == null) position.beginActivity(activity);
  }

  void resetMomentumTracking({bool stopActivity = false}) {
    if (stopActivity) {
      cancelTrackpadPans();
      _waydroid?.dispose();
    }
    final activeActivity = _activeActivity;
    _activeActivity = null;
    if (stopActivity) {
      activeActivity?.cancelMomentum();
    }
  }

  @override
  void detach() {
    resetMomentumTracking(stopActivity: true);
    super.detach();
  }
}

class _PremiumWheelScrollActivity extends ScrollActivity {
  _PremiumWheelScrollActivity(
    super.delegate, {
    required TickerProvider vsync,
    required this.config,
    required this.initialFrameDuration,
    required this.onDispose,
    this.coordinatedView,
    this.coordinatedPositions = const [],
  }) {
    _ticker = vsync.createTicker(_tick)..start();
    for (final position in coordinatedPositions) {
      position.addListener(_nativeScrollTookOver);
      position.isScrollingNotifier.addListener(_nativeScrollTookOver);
    }
  }

  final PremiumScrollPhysicsConfig config;
  final Duration initialFrameDuration;
  final ValueChanged<_PremiumWheelScrollActivity> onDispose;
  final NestedScrollViewState? coordinatedView;
  final List<ScrollPosition> coordinatedPositions;

  late final Ticker _ticker;
  Duration? _lastElapsed;
  double _remainingDistance = 0;
  bool _isDisposed = false;
  bool _applyingCoordinatedDelta = false;

  bool get canReuse =>
      !_isDisposed &&
      (coordinatedView == null ||
          _hasSameCoordinatedPositions(
            _coordinatedWheelPositions(coordinatedView!),
          ));

  bool _hasSameCoordinatedPositions(List<ScrollPosition>? positions) =>
      positions != null &&
      positions.length == coordinatedPositions.length &&
      positions.every(coordinatedPositions.contains);

  void addScrollDistance(double distance) {
    if (_isDisposed || distance == 0) {
      return;
    }
    // Reversing the wheel immediately discards the old queued direction rather
    // than making the user fight synthetic momentum.
    final nextDistance =
        _remainingDistance != 0 && _remainingDistance.sign != distance.sign
            ? distance
            : _remainingDistance + distance;
    _remainingDistance = nextDistance.clamp(
      -config.maxWheelQueuedDistance,
      config.maxWheelQueuedDistance,
    );
  }

  void cancelMomentum() {
    if (!_isDisposed) {
      if (coordinatedView == null) {
        delegate.goBallistic(0);
      } else {
        dispose();
      }
    }
  }

  void _nativeScrollTookOver() {
    // Programmatic jumps/animations and native input take ownership. Layout
    // corrections do not notify position listeners, so viewport resizing alone
    // does not discard queued input or restart its easing.
    if (!_applyingCoordinatedDelta) dispose();
  }

  void _tickCoordinated(double displacement) {
    final positions = _coordinatedWheelPositions(coordinatedView!);
    if (positions == null ||
        !_hasSameCoordinatedPositions(positions) ||
        !_canScrollCoordinated(positions, displacement)) {
      dispose();
      return;
    }
    _applyingCoordinatedDelta = true;
    try {
      // Exactly one public coordinator call per frame, never setPixels on the
      // inner or outer position and never redispatch the pointer event.
      positions.first.pointerScroll(displacement);
    } finally {
      _applyingCoordinatedDelta = false;
    }
    if (_isDisposed) return;
    _remainingDistance -= displacement;
    if (_remainingDistance.abs() <= config.wheelStopDistance ||
        !_canScrollCoordinated(positions, _remainingDistance)) {
      dispose();
    }
  }

  void _tick(Duration elapsed) {
    if (_isDisposed) {
      return;
    }

    final previousElapsed = _lastElapsed;
    _lastElapsed = elapsed;
    final frameDuration = previousElapsed == null
        ? elapsed == Duration.zero
            ? initialFrameDuration
            : elapsed
        : elapsed - previousElapsed;
    if (frameDuration <= Duration.zero) {
      return;
    }

    if (_remainingDistance.abs() <= config.wheelStopDistance) {
      cancelMomentum();
      return;
    }

    final elapsedSeconds =
        frameDuration.inMicroseconds / Duration.microsecondsPerSecond;
    final displacement = premiumWheelFrameDisplacement(
      remainingDistance: _remainingDistance,
      elapsedSeconds: elapsedSeconds,
      config: config,
    );
    if (displacement == 0) {
      return;
    }

    if (coordinatedView != null) {
      _tickCoordinated(displacement);
      return;
    }

    if (delegate is! ScrollPosition) {
      delegate.goIdle();
      return;
    }
    final position = delegate as ScrollPosition;
    if (!position.hasPixels) {
      delegate.goIdle();
      return;
    }
    // Mouse-wheel distance is exact and bounded even when direct-manipulation
    // physics allow elastic overscroll. Never leave an idle position outside
    // its range, or convert the unused wheel queue into a second fling.
    if (position.outOfRange) {
      delegate.goBallistic(0);
      return;
    }
    final requested = position.pixels + displacement;
    final target = requested.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final overscroll = delegate.setPixels(target);
    if (overscroll != 0 || target != requested) {
      delegate.goBallistic(0);
      return;
    }
    _remainingDistance -= displacement;

    if (_remainingDistance.abs() <= config.wheelStopDistance) {
      delegate.goBallistic(0);
    }
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => (_remainingDistance * config.wheelSmoothingRate).clamp(
        -config.maxWheelScrollVelocity,
        config.maxWheelScrollVelocity,
      );

  @override
  void dispatchOverscrollNotification(
    ScrollMetrics metrics,
    BuildContext context,
    double overscroll,
  ) {
    OverscrollNotification(
      metrics: metrics,
      context: context,
      overscroll: overscroll,
      velocity: velocity,
    ).dispatch(context);
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _ticker.dispose();
    for (final position in coordinatedPositions) {
      position.removeListener(_nativeScrollTookOver);
      position.isScrollingNotifier.removeListener(_nativeScrollTookOver);
    }
    onDispose(this);
    super.dispose();
  }
}

bool _snapsToPages(ScrollPosition position) {
  for (ScrollPhysics? physics = position.physics;
      physics != null;
      physics = physics.parent) {
    if (physics is PageScrollPhysics) return true;
  }
  return false;
}

/// A Waydroid touchpad stream bound to the scroll position it started on: the
/// motion it plays and the frame driver playing it.
///
/// Notch timing follows the input device's own stamps, mapped onto this
/// clock with the fastest delivery seen, as [FrameSyncedScrollPan] does, so a
/// busy UI thread delivering notches in bursts changes nothing.
class _WaydroidStream {
  _WaydroidStream({
    required this.position,
    required this.axisDirection,
    required this.onDisposed,
    this.coordinatedView,
  }) : pageSnapping = coordinatedView == null && _snapsToPages(position);

  final ScrollPosition position;
  final AxisDirection axisDirection;
  final NestedScrollViewState? coordinatedView;
  final ValueChanged<_WaydroidStream> onDisposed;

  /// Pages snap with their own physics when the stream ends, as after a
  /// touch drag, instead of coasting freely.
  final bool pageSnapping;

  final motion = WaydroidScrollMotion();
  final Stopwatch _clock = GestureBinding.instance.samplingClock.stopwatch()
    ..start();
  int _offsetUs = 0;
  bool _hasOffset = false;
  _WaydroidScrollActivity? _driver;
  bool _disposed = false;

  int get clockUs => _clock.elapsedMicroseconds;

  /// Input time minus this clock's time.
  int get offsetUs => _offsetUs;

  bool get _attached =>
      position.hasPixels &&
      (position.context.notificationContext?.mounted ?? false);

  /// Whether a notch stamped [stamp] belongs to this stream.
  bool isLive(Duration stamp) {
    if (_disposed || !_attached) return false;
    return motion.continues(stamp.inMicroseconds);
  }

  void add(Duration stamp, double delta) {
    if (_disposed || delta == 0 || !_attached) return;
    final stampUs = stamp.inMicroseconds;
    final lateness = _clock.elapsedMicroseconds - stampUs;
    if (!_hasOffset || lateness < _offsetUs) {
      _offsetUs = lateness;
      _hasOffset = true;
    }
    final position = this.position;
    if (position is ScrollPositionWithSingleContext) {
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      position.updateUserScrollDirection(
        delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward,
      );
    }
    motion.addNotches(stampUs, delta);
    _drive();
  }

  void _drive() {
    if (_disposed || !motion.isActive) return;
    final driver = _driver;
    if (driver != null && !driver.isDisposed) return;
    final position = this.position;
    if (position is! ScrollActivityDelegate || !position.hasContentDimensions) {
      motion.stop();
      return;
    }
    var coordinatedPositions = const <ScrollPosition>[];
    final view = coordinatedView;
    if (view != null) {
      final positions = _coordinatedWheelPositions(view);
      if (positions == null ||
          !_canScrollCoordinated(positions, motion.received - motion.shown)) {
        motion.hitEdge(0);
        return;
      }
      coordinatedPositions = positions;
      // Stop native motion without moving either viewport.
      position.pointerScroll(0);
    } else {
      final pending = motion.received - motion.shown;
      if (!motion.isCoasting &&
          (pending > 0
              ? position.pixels >= position.maxScrollExtent
              : position.pixels <= position.minScrollExtent)) {
        // Pressed against an edge: nothing to play.
        motion.hitEdge(0);
        return;
      }
    }
    final notificationContext = position.context.notificationContext;
    final refreshRate = notificationContext == null
        ? 60.0
        : View.maybeOf(notificationContext)?.display.refreshRate ?? 60.0;
    final activity = _driver = _WaydroidScrollActivity(
      position as ScrollActivityDelegate,
      stream: this,
      vsync: position.context.vsync,
      initialFrameDuration: Duration(
        microseconds: (Duration.microsecondsPerSecond /
                (refreshRate.isFinite && refreshRate > 0 ? refreshRate : 60))
            .round(),
      ),
      coordinatedPositions: coordinatedPositions,
    );
    if (view == null) position.beginActivity(activity);
  }

  /// Stops the motion where it is, as a touch-down would.
  void stop() {
    motion.stop();
    _driver?.end();
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    _clock.stop();
    onDisposed(this);
  }
}

/// Plays a [_WaydroidStream]'s motion frame by frame: as the position's
/// activity, or for a coordinated [NestedScrollView] through the outer
/// position's public pointerScroll, as coordinated wheels are.
class _WaydroidScrollActivity extends ScrollActivity {
  _WaydroidScrollActivity(
    super.delegate, {
    required this.stream,
    required TickerProvider vsync,
    required this.initialFrameDuration,
    this.coordinatedPositions = const [],
  }) {
    _ticker = vsync.createTicker(_tick)..start();
    for (final position in coordinatedPositions) {
      position.addListener(_nativeScrollTookOver);
      position.isScrollingNotifier.addListener(_nativeScrollTookOver);
    }
  }

  final _WaydroidStream stream;
  final Duration initialFrameDuration;
  final List<ScrollPosition> coordinatedPositions;

  late final Ticker _ticker;
  Duration? _lastElapsed;
  int? _tickBaseUs;
  bool _isDisposed = false;
  bool _ending = false;
  bool _applying = false;

  bool get isDisposed => _isDisposed;

  bool get _coordinated => stream.coordinatedView != null;

  void _tick(Duration elapsed) {
    if (_isDisposed) return;
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    final frame = previous == null ? initialFrameDuration : elapsed - previous;
    if (frame <= Duration.zero) return;
    // Frame timestamps tick evenly even when this callback runs late.
    final baseUs = _tickBaseUs ??= stream.clockUs - elapsed.inMicroseconds;
    final nowUs = baseUs + elapsed.inMicroseconds - stream.offsetUs;
    final motion = stream.motion;
    final displacement = motion.advance(
      nowUs,
      math.min(
        frame.inMicroseconds / Duration.microsecondsPerSecond,
        _maximumWheelFrameIntervalSeconds,
      ),
    );
    if (stream.pageSnapping && motion.isCoasting) {
      // A page released moving settles on the next page, by its physics.
      final velocity = motion.velocity;
      motion.stop();
      _ending = true;
      delegate.goBallistic(velocity);
      return;
    }
    if (displacement != 0) {
      _coordinated ? _applyCoordinated(displacement) : _apply(displacement);
      if (_isDisposed) return;
    }
    if (!motion.isActive) end();
  }

  void _apply(double displacement) {
    final position = delegate as ScrollPosition;
    final motion = stream.motion;
    if (!position.hasPixels ||
        !position.hasContentDimensions ||
        position.outOfRange) {
      motion.stop();
      return;
    }
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    final requested = position.pixels + displacement;
    if (requested >= min && requested <= max) {
      delegate.setPixels(requested);
      return;
    }
    if (motion.isCoasting) {
      // A coast reaches an edge as a fling does: the platform's overscroll
      // indication takes its speed, or elastic physics spring back from it.
      final velocity = motion.velocity;
      delegate.setPixels(requested);
      motion.hitEdge(requested - position.pixels);
      if (position.outOfRange) {
        _ending = true;
        delegate.goBallistic(velocity);
      }
      return;
    }
    // Followed notches stop at the edge, as wheel distance does.
    final target = requested.clamp(min, max);
    if (target != position.pixels) delegate.setPixels(target);
    motion.hitEdge(requested - target);
  }

  void _applyCoordinated(double displacement) {
    final positions = _coordinatedWheelPositions(stream.coordinatedView!);
    if (positions == null ||
        positions.length != coordinatedPositions.length ||
        !positions.every(coordinatedPositions.contains) ||
        !_canScrollCoordinated(positions, displacement)) {
      stream.motion.hitEdge(displacement);
      return;
    }
    _applying = true;
    try {
      // One public coordinator call per frame, never setPixels on either
      // position, so header and body share the distance.
      positions.first.pointerScroll(displacement);
    } finally {
      _applying = false;
    }
  }

  void _nativeScrollTookOver() {
    if (!_applying) dispose();
  }

  /// Hands the position back once the motion has ended.
  void end() {
    if (_isDisposed) return;
    _ending = true;
    final Object position = delegate;
    if (!_coordinated &&
        position is ScrollPosition &&
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        identical(position.activity, this)) {
      delegate.goBallistic(0);
    } else {
      dispose();
    }
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => stream.motion.velocity;

  @override
  void dispatchOverscrollNotification(
    ScrollMetrics metrics,
    BuildContext context,
    double overscroll,
  ) {
    OverscrollNotification(
      metrics: metrics,
      context: context,
      overscroll: overscroll,
      velocity: velocity,
    ).dispatch(context);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _ticker.dispose();
    for (final position in coordinatedPositions) {
      position.removeListener(_nativeScrollTookOver);
      position.isScrollingNotifier.removeListener(_nativeScrollTookOver);
    }
    // Another activity took over (a touch, a jump): the motion ends there.
    if (!_ending) stream.motion.stop();
    super.dispose();
  }
}

/// Marks a custom embedded surface (for example the PDF viewer) as the owner of
/// its own pointer-signal and pan/zoom physics.
class PremiumScrollExclusion extends SingleChildRenderObjectWidget {
  const PremiumScrollExclusion({super.key, required super.child});

  /// Custom viewers also own horizontal pan gestures; page history must not
  /// compete with them. Inactive embed gates remove this target themselves.
  static bool isHitTestTarget(HitTestTarget target) =>
      target is _RenderPremiumScrollExclusion;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPremiumScrollExclusion();
  }
}

class _RenderPremiumScrollExclusion extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    hitTestChildren(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
