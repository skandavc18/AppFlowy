import 'dart:math' as math;

import 'package:flutter/physics.dart';

/// Viscous share of a release coast's deceleration, in inverse seconds: the
/// share of its speed macOS momentum loses every second
/// (UIScrollView.decelerationRate.normal, 0.998 per millisecond).
const double premiumCoastFriction = 2.0;

/// Constant share of a release coast's deceleration, in logical pixels per
/// second squared.
///
/// macOS momentum keeps the decay above and simply ends once it has slowed to
/// about 125 px/s (where the desktop's own glide stops too). This constant
/// share brings the coast to rest smoothly around there instead: a 1000 px/s
/// flick travels about 360 px and settles after 1.1 s, a 3000 px/s one about
/// 1300 px.
const double premiumCoastDeceleration = 250.0;

/// A release coast slowed by a viscous and a constant share of deceleration:
/// dv/dt = -friction * v - deceleration.
///
/// The viscous share is macOS momentum; the constant share lets the coast
/// settle in finite time instead of creeping at a few pixels a second. The
/// deceleration depends only on the current velocity, so a coast restarted
/// from any point of its own trajectory (Flutter restarts ballistic activities
/// when lazy content changes the scroll extent) continues it exactly.
class PremiumCoastSimulation extends Simulation {
  PremiumCoastSimulation({
    required this.position,
    required this.velocity,
    this.friction = premiumCoastFriction,
    this.deceleration = premiumCoastDeceleration,
    super.tolerance,
  })  : assert(friction > 0),
        assert(deceleration >= 0),
        duration = premiumCoastDuration(
          velocity,
          friction: friction,
          deceleration: deceleration,
        ),
        finalX = position +
            premiumCoastDistance(
              velocity,
              friction: friction,
              deceleration: deceleration,
            );

  final double position;
  final double velocity;
  final double friction;
  final double deceleration;

  /// Seconds until the coast stops; infinite without a constant share.
  final double duration;

  /// Where the coast comes to rest.
  final double finalX;

  double get _drift => deceleration / friction;

  double _travelled(double time) {
    final t = math.min(time, duration);
    if (t <= 0) return 0;
    return (velocity.abs() + _drift) / friction * _oneMinusExp(friction * t) -
        _drift * t;
  }

  @override
  double x(double time) =>
      time >= duration ? finalX : position + velocity.sign * _travelled(time);

  @override
  double dx(double time) {
    if (time >= duration) return 0;
    final speed =
        (velocity.abs() + _drift) * math.exp(-friction * math.max(0.0, time)) -
            _drift;
    return velocity.sign * math.max(0.0, speed);
  }

  @override
  bool isDone(double time) =>
      time >= duration || dx(time).abs() < tolerance.velocity;

  /// When the coast reaches [target], or infinity if it stops before it.
  double timeAtX(double target) {
    final distance = (target - position) * velocity.sign;
    if (velocity == 0 || distance < 0) {
      return target == position ? 0 : double.infinity;
    }
    final total = (finalX - position).abs();
    if (distance >= total) {
      return deceleration > 0 && distance == total ? duration : double.infinity;
    }
    if (deceleration == 0) {
      return -math.log(1 - distance * friction / velocity.abs()) / friction;
    }
    // Travel only grows until the coast stops, so bisection cannot miss.
    var early = 0.0;
    var late = duration;
    for (var i = 0; i < 64; i++) {
      final middle = (early + late) / 2;
      if (_travelled(middle) < distance) {
        early = middle;
      } else {
        late = middle;
      }
    }
    return (early + late) / 2;
  }
}

/// Seconds a coast at [velocity] takes to stop; infinite without a constant
/// share of deceleration.
double premiumCoastDuration(
  double velocity, {
  double friction = premiumCoastFriction,
  double deceleration = premiumCoastDeceleration,
}) {
  if (deceleration == 0) {
    return velocity == 0 ? 0 : double.infinity;
  }
  return _log1p(friction * velocity.abs() / deceleration) / friction;
}

/// How far, signed, a coast at [velocity] travels before it stops.
double premiumCoastDistance(
  double velocity, {
  double friction = premiumCoastFriction,
  double deceleration = premiumCoastDeceleration,
}) {
  final speed = velocity.abs();
  if (speed == 0) return 0;
  final distance = deceleration == 0
      ? speed / friction
      : deceleration /
          (friction * friction) *
          _uMinusLog1p(friction * speed / deceleration);
  return velocity.sign * distance;
}

/// The velocity whose coast travels exactly [distance], signed: the inverse of
/// [premiumCoastDistance].
double premiumCoastVelocity(
  double distance, {
  double friction = premiumCoastFriction,
  double deceleration = premiumCoastDeceleration,
}) {
  if (distance == 0) return 0;
  if (deceleration == 0) return distance * friction;
  // With u = friction * speed / deceleration the distance is
  // deceleration / friction² * (u - ln(1 + u)): solve that for u. The
  // function is convex and increasing, so Newton's method started above the
  // root descends onto it without overshooting. ln(1 + u) <= √u places the
  // start above the root.
  final target = distance.abs() * friction * friction / deceleration;
  final root = (1 + math.sqrt(1 + 4 * target)) / 2;
  var u = root * root;
  for (var i = 0; i < 100; i++) {
    final step = (_uMinusLog1p(u) - target) * (1 + u) / u;
    u -= step;
    if (step.abs() <= 1e-14 * u) break;
  }
  return distance.sign * u * deceleration / friction;
}

/// The constant share of deceleration with which a coast at [velocity] and
/// [friction] stops after exactly [distance]: zero if the viscous share alone
/// stops it sooner.
double premiumCoastDecelerationToRest({
  required double velocity,
  required double distance,
  double friction = premiumCoastFriction,
}) {
  final speed = velocity.abs();
  if (speed == 0) return 0;
  if (distance <= 0) return double.infinity;
  // The distance is speed / friction * (1 - ln(1 + u) / u) with
  // u = friction * speed / deceleration, a share rising from 0 to 1 with u.
  final share = distance * friction / speed;
  if (share >= 1) return 0;
  double shareAt(double u) => _uMinusLog1p(u) / u;
  var low = 0.0;
  var high = 1.0;
  while (shareAt(high) < share && high < 1e300) {
    high *= 2;
  }
  for (var i = 0; i < 100; i++) {
    final middle = (low + high) / 2;
    if (middle == low || middle == high) break;
    if (shareAt(middle) < share) {
      low = middle;
    } else {
      high = middle;
    }
  }
  // The lower bound brakes a hair harder: the coast never passes [distance].
  return friction * speed / (low > 0 ? low : high);
}

/// JavaScript twin of [PremiumCoastSimulation] for coasts that animate inside
/// a web view. Declares `coastStep(speed, seconds)`, returning the distance a
/// coast at `speed` travels in `seconds` and the speed it has left, and
/// `coastDistance(speed)`, how far it travels before it stops.
String buildPremiumCoastJavaScript({
  double friction = premiumCoastFriction,
  double deceleration = premiumCoastDeceleration,
}) =>
    '''
const coastFriction = $friction;
const coastDrift = ${deceleration / friction};
const coastStep = (speed, seconds) => {
  const stopsAfter = coastDrift > 0
    ? Math.log1p(speed / coastDrift) / coastFriction
    : Infinity;
  const time = Math.max(0, Math.min(seconds, stopsAfter));
  const kept = Math.exp(-coastFriction * time);
  return {
    distance: (speed + coastDrift) / coastFriction * -Math.expm1(-coastFriction * time) -
      coastDrift * time,
    speed: time < seconds ? 0 : Math.max(0, (speed + coastDrift) * kept - coastDrift),
  };
};
const coastDistance = speed => coastDrift > 0
  ? speed / coastFriction - coastDrift / coastFriction * Math.log1p(speed / coastDrift)
  : speed / coastFriction;
''';

double _oneMinusExp(double x) =>
    x < 1e-5 ? x - x * x / 2 + x * x * x / 6 : 1 - math.exp(-x);

double _log1p(double x) =>
    x < 1e-5 ? x - x * x / 2 + x * x * x / 3 : math.log(1 + x);

/// u - ln(1 + u), without the cancellation of subtracting nearly equal terms.
double _uMinusLog1p(double u) => u < 1e-4
    ? u * u / 2 - u * u * u / 3 + u * u * u * u / 4
    : u - math.log(1 + u);
