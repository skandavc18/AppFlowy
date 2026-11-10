import 'dart:math' as math;

import 'package:appflowy/shared/scrolling/premium_coast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the coast keeps macOS momentum and glides as long as mac-ui does', () {
    expect(premiumCoastFriction, 2.0);
    expect(premiumCoastDeceleration, 250);
    expect(premiumCoastDistance(1000), closeTo(362.7, 0.1));
    expect(premiumCoastDuration(1000), closeTo(1.099, 0.001));
    expect(premiumCoastDistance(3000), closeTo(1298.8, 0.1));
    expect(premiumCoastDuration(3000), closeTo(1.609, 0.001));
    expect(premiumCoastDistance(8000), closeTo(3739.1, 0.1));
    expect(premiumCoastDuration(8000), closeTo(2.087, 0.001));
    expect(premiumCoastDistance(-1000), closeTo(-362.7, 0.1));
    expect(premiumCoastDistance(0), 0);
    // The desktop's own glide (500 ms decay, stopping at 125 px/s) lasts as
    // long; this one eases to rest instead of halting.
    for (final velocity in [1000.0, 3000.0, 8000.0]) {
      expect(
        premiumCoastDuration(velocity),
        closeTo(0.5 * math.log(velocity / 125), 0.06),
      );
    }
  });

  test('a slow lift drifts briefly, then settles', () {
    final coast = PremiumCoastSimulation(position: 0, velocity: 150);
    expect(coast.finalX, closeTo(25.7, 0.1));
    expect(coast.duration, closeTo(0.394, 0.001));
    expect(coast.isDone(coast.duration), isTrue);
    expect(coast.x(1), coast.finalX);
  });

  test('the simulation follows its closed form and stops exactly', () {
    for (final velocity in [-4800.0, -700.0, 90.0, 1000.0, 8000.0]) {
      final coast = PremiumCoastSimulation(position: 50, velocity: velocity);
      expect(coast.x(0), 50);
      expect(coast.dx(0), closeTo(velocity, 1e-9));
      expect(coast.x(coast.duration), closeTo(coast.finalX, 1e-9));
      expect(coast.dx(coast.duration), 0);
      expect(coast.x(coast.duration + 5), coast.finalX);
      expect(coast.isDone(coast.duration), isTrue);
      expect(coast.isDone(coast.duration * 0.5), isFalse);
      var previous = coast.dx(0).abs();
      for (var frame = 1; frame * 0.004 < coast.duration; frame++) {
        final speed = coast.dx(frame * 0.004).abs();
        expect(speed, lessThan(previous));
        previous = speed;
      }
    }
  });

  test('a coast restarted from its own trajectory continues it exactly', () {
    final first = PremiumCoastSimulation(position: 0, velocity: -2600);
    for (final restart in [0.05, 0.3, 0.7]) {
      final resumed = PremiumCoastSimulation(
        position: first.x(restart),
        velocity: first.dx(restart),
      );
      expect(resumed.duration, closeTo(first.duration - restart, 1e-9));
      for (final time in [0.0, 0.01, 0.1, 0.4, 2.0]) {
        expect(resumed.x(time), closeTo(first.x(restart + time), 1e-6));
        expect(resumed.dx(time), closeTo(first.dx(restart + time), 1e-6));
      }
    }
  });

  test('the launch velocity for a distance inverts the travelled distance', () {
    for (final velocity in [0.01, 3.0, 150.0, 1000.0, -2400.0, 8000.0, 6e4]) {
      final distance = premiumCoastDistance(velocity);
      expect(
        premiumCoastVelocity(distance),
        closeTo(velocity, velocity.abs() * 1e-9),
      );
    }
    expect(premiumCoastVelocity(0), 0);
    // Without a constant share the coast is linear in its velocity.
    expect(premiumCoastVelocity(-250, deceleration: 0), -500);
    expect(premiumCoastDistance(500, deceleration: 0), 250);
  });

  test('timeAtX finds every point the coast passes, and only those', () {
    final coast = PremiumCoastSimulation(position: 100, velocity: -1800);
    for (final target in [100.0, 60.0, -200.0, coast.finalX + 0.001]) {
      expect(coast.x(coast.timeAtX(target)), closeTo(target, 1e-6));
    }
    expect(coast.timeAtX(coast.finalX - 1), double.infinity);
    expect(coast.timeAtX(101), double.infinity);
    final exponential = PremiumCoastSimulation(
      position: 0,
      velocity: 600,
      deceleration: 0,
    );
    expect(exponential.x(exponential.timeAtX(200)), closeTo(200, 1e-9));
    expect(exponential.timeAtX(300), double.infinity);
  });

  test('braking to rest lands exactly on a nearer edge', () {
    for (final (velocity, distance) in [
      (3000.0, 400.0),
      (-1200.0, 50.0),
      (8000.0, 0.5),
    ]) {
      final deceleration = premiumCoastDecelerationToRest(
        velocity: velocity,
        distance: distance,
      );
      expect(deceleration, greaterThan(premiumCoastDeceleration));
      final landing = PremiumCoastSimulation(
        position: 0,
        velocity: velocity,
        deceleration: deceleration,
      );
      expect(landing.finalX.abs(), lessThanOrEqualTo(distance));
      expect(landing.finalX.abs(), closeTo(distance, distance * 1e-9));
      expect(landing.dx(landing.duration), 0);
    }
    // The viscous share alone already stops short of a distant edge.
    expect(
      premiumCoastDecelerationToRest(velocity: 1000, distance: 600),
      0,
    );
  });

  test('the web view twin is generated from the same constants', () {
    final script = buildPremiumCoastJavaScript(
      friction: 2.5,
      deceleration: 1000,
    );
    expect(script, contains('const coastFriction = 2.5;'));
    expect(script, contains('const coastDrift = 400.0;'));
    expect(script, contains('const coastStep = (speed, seconds) =>'));
    expect(script, contains('const coastDistance = speed =>'));
  });
}
