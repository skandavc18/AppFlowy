import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Tunable constants for AppFlowy's application-wide kinetic scrolling.
@immutable
class PremiumScrollPhysicsConfig {
  const PremiumScrollPhysicsConfig({
    this.friction = 5.0,
    this.wheelAcceleration = 8.0,
    this.precisionAcceleration = 14.0,
    this.maxVelocity = 4800.0,
    this.momentumRetention = 0.92,
    this.directionChangeRetention = 0.20,
    this.maxWheelDelta = 120.0,
    this.maxPrecisionDelta = 48.0,
    this.precisionDeltaThreshold = 24.0,
    this.minimumVelocity = 18.0,
    this.stopVelocity = 8.0,
    this.immediateResponse = 0.22,
    this.wheelSmoothingRate = 16.0,
    this.maxWheelScrollVelocity = 1000.0,
    this.maxWheelQueuedDistance = 240.0,
    this.wheelStopDistance = 0.1,
    this.desktopDirectManipulationScale = 0.55,
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
  /// Flutter forwards precision-trackpad pan deltas directly. A conservative
  /// scale keeps small movements precise and prevents desktop content from
  /// outrunning the user's fingers. Native macOS and mobile movement remain
  /// unchanged.
  final double desktopDirectManipulationScale;

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
              desktopDirectManipulationScale;

  @override
  int get hashCode => Object.hash(
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
      );
}

/// Applies premium scrolling to every descendant Flutter [Scrollable].
///
/// Flutter tickers are synchronized to the engine frame scheduler (the native
/// equivalent of requestAnimationFrame), so this supports high-refresh-rate
/// displays without timers or per-event layout work.
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
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    final kineticEnabled = enabled && !reducedMotion;

    return ScrollConfiguration(
      behavior: PremiumScrollBehavior(
        delegate: ScrollConfiguration.of(context),
        config: config,
        kineticEnabled: kineticEnabled,
      ),
      child: kineticEnabled ? _PremiumScrollDispatcher(child: child) : child,
    );
  }
}

/// Preserves Flutter's native drag/trackpad physics and registers each
/// scrollable with the discrete mouse-wheel dispatcher.
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
          platformBuilder(event),
          config.desktopDirectManipulationScale,
        );
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platformPhysics = delegate.getScrollPhysics(context);
    final platform = getPlatform(context);
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
            parent: platformPhysics,
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
      child: decorated,
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

/// Marker physics for enabled premium wheel handling.
///
/// Drag, touch, and precision-trackpad behavior deliberately defer to the
/// platform physics supplied by Flutter. In particular, this avoids layering
/// another velocity curve on top of [PointerPanZoomEvent] input.
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
    return super.applyPhysicsToUserOffset(position, offset) *
        directManipulationScale;
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
/// their native surface. The impulse, retention, acceleration, friction, and
/// stopping behavior remain identical.
class PremiumKineticScrollModel {
  PremiumKineticScrollModel({
    PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
  }) : _config = config;

  PremiumScrollPhysicsConfig _config;
  Offset _velocity = Offset.zero;

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
    final displacement = premiumKineticFrameDisplacement(
      velocity: _velocity,
      friction: _config.friction,
      elapsedSeconds: frameSeconds,
    );
    _velocity = premiumKineticFrameVelocity(
      velocity: _velocity,
      friction: _config.friction,
      elapsedSeconds: frameSeconds,
    );
    if (_velocity.distance < _config.stopVelocity) {
      _velocity = Offset.zero;
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
  }

  void stop() {
    _velocity = Offset.zero;
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
  const state = {
    velocityX: 0,
    velocityY: 0,
    residualX: 0,
    residualY: 0,
    horizontalTarget: null,
    verticalTarget: null,
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
  const findScrollTarget = (positionX, positionY, horizontal) => {
    if (!Number.isFinite(positionX) || !Number.isFinite(positionY)) {
      return null;
    }
    let element = document.elementFromPoint(positionX, positionY);
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
    return null;
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
  const stop = () => {
    if (state.frame) cancelAnimationFrame(state.frame);
    state.frame = 0;
    state.lastTime = 0;
    state.velocityX = 0;
    state.velocityY = 0;
    state.residualX = 0;
    state.residualY = 0;
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
        stop();
        return;
      }
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
    return _RenderPremiumScrollDispatcher();
  }
}

class _RenderPremiumScrollDispatcher extends RenderProxyBox {
  List<_RenderPremiumScrollRegion> _hitRegions = const [];
  bool _hitPremiumExclusion = false;

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
    if (_hitPremiumExclusion) {
      return;
    }

    if (event is PointerScrollEvent) {
      for (final region in _hitRegions) {
        final candidate = region.candidateFor(event);
        if (candidate == null) {
          continue;
        }
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
    } else if (event is PointerScrollInertiaCancelEvent) {
      for (final region in _hitRegions) {
        region.resetMomentumTracking(stopActivity: true);
      }
    }
  }
}

class _PremiumScrollRegion extends SingleChildRenderObjectWidget {
  const _PremiumScrollRegion({
    required this.controller,
    required this.axisDirection,
    required this.pointerAxisModifiers,
    required this.config,
    required super.child,
  });

  final ScrollController? controller;
  final AxisDirection axisDirection;
  final Set<LogicalKeyboardKey> pointerAxisModifiers;
  final PremiumScrollPhysicsConfig config;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPremiumScrollRegion(
      controller: controller,
      axisDirection: axisDirection,
      pointerAxisModifiers: pointerAxisModifiers,
      config: config,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPremiumScrollRegion renderObject,
  ) {
    renderObject
      ..controller = controller
      ..axisDirection = axisDirection
      ..pointerAxisModifiers = pointerAxisModifiers
      ..config = config;
  }
}

class _PremiumScrollCandidate {
  const _PremiumScrollCandidate({
    required this.position,
    required this.delta,
  });

  final ScrollPosition position;
  final double delta;
}

class _RenderPremiumScrollRegion extends RenderProxyBox {
  _RenderPremiumScrollRegion({
    required ScrollController? controller,
    required AxisDirection axisDirection,
    required this.pointerAxisModifiers,
    required PremiumScrollPhysicsConfig config,
  })  : _controller = controller,
        _axisDirection = axisDirection,
        _config = config;

  _PremiumWheelScrollActivity? _activeActivity;

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

  _PremiumScrollCandidate? candidateFor(PointerScrollEvent event) {
    final scrollController = controller;
    if (scrollController == null || !scrollController.hasClients) {
      return null;
    }

    for (final position in scrollController.positions) {
      if (!position.hasContentDimensions ||
          !position.physics.shouldAcceptUserOffset(position)) {
        continue;
      }
      final delta = _eventDelta(event, position.axisDirection);
      if (delta == 0) {
        continue;
      }
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target != position.pixels) {
        return _PremiumScrollCandidate(position: position, delta: delta);
      }
    }
    return null;
  }

  double _eventDelta(PointerScrollEvent event, AxisDirection direction) {
    final flipAxes = event.kind == PointerDeviceKind.mouse &&
        HardwareKeyboard.instance.logicalKeysPressed
            .any(pointerAxisModifiers.contains);
    final axis = flipAxes
        ? flipAxis(axisDirectionToAxis(direction))
        : axisDirectionToAxis(direction);
    final delta = switch (axis) {
      Axis.horizontal => event.scrollDelta.dx,
      Axis.vertical => event.scrollDelta.dy,
    };
    return axisDirectionIsReversed(direction) ? -delta : delta;
  }

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
        !activeActivity.isDisposed &&
        identical(activeActivity.delegate, position)) {
      activeActivity.addScrollDistance(distance);
      return;
    }

    _launchActivity(position, delegate, distance);
  }

  void _launchActivity(
    ScrollPosition position,
    ScrollActivityDelegate delegate,
    double distance,
  ) {
    if (!attached || !position.hasPixels || distance == 0) {
      delegate.goBallistic(0);
      resetMomentumTracking();
      return;
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
      onDispose: (disposedActivity) {
        if (identical(_activeActivity, disposedActivity)) {
          _activeActivity = null;
        }
      },
    )..addScrollDistance(distance);
    _activeActivity = activity;
    position.beginActivity(activity);
  }

  void resetMomentumTracking({bool stopActivity = false}) {
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
  }) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  final PremiumScrollPhysicsConfig config;
  final Duration initialFrameDuration;
  final ValueChanged<_PremiumWheelScrollActivity> onDispose;

  late final Ticker _ticker;
  Duration? _lastElapsed;
  double _remainingDistance = 0;
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

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
      delegate.goIdle();
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
      delegate.goIdle();
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

    if (delegate is! ScrollPosition) {
      delegate.goIdle();
      return;
    }
    final position = delegate as ScrollPosition;
    if (!position.hasPixels) {
      delegate.goIdle();
      return;
    }
    final overscroll = delegate.setPixels(position.pixels + displacement);
    if (overscroll != 0) {
      delegate.goIdle();
      return;
    }
    _remainingDistance -= displacement;

    if (_remainingDistance.abs() <= config.wheelStopDistance) {
      delegate.goIdle();
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
    onDispose(this);
    super.dispose();
  }
}

/// Marks a custom embedded surface (for example the PDF viewer) as the owner of
/// its own pointer-signal and pan/zoom physics.
class PremiumScrollExclusion extends SingleChildRenderObjectWidget {
  const PremiumScrollExclusion({super.key, required super.child});

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
