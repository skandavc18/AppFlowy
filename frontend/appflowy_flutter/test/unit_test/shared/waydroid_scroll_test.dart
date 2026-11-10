import 'dart:math' as math;

import 'package:appflowy/shared/scrolling/premium_coast.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/waydroid_scroll.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waydroid's display: 2048x1280 at density 213, 120 Hz.
const _waydroidPixelRatio = 213 / 160;
const _frame = Duration(microseconds: 8333);
const _listKey = ValueKey('waydroid-list');

void main() {
  group('detection', () {
    test('recognises Waydroid build properties', () {
      expect(
        WaydroidDetection.isWaydroidDevice(
          manufacturer: 'Waydroid',
          model: 'WayDroid x86_64 Device',
          product: 'lineage_waydroid_x86_64',
        ),
        isTrue,
      );
      expect(
        WaydroidDetection.isWaydroidDevice(product: 'lineage_waydroid_x86_64'),
        isTrue,
      );
      expect(
        WaydroidDetection.isWaydroidDevice(
          manufacturer: 'Google',
          brand: 'google',
          model: 'Pixel 6',
          product: 'oriole',
          device: 'oriole',
          hardware: 'oriole',
        ),
        isFalse,
      );
    });

    test('is off off Android and never blocks', () {
      WaydroidDetection.ensureStarted();
      expect(WaydroidDetection.isWaydroid, isFalse);
    });

    test('Android scroll unit is 64 dp in whole physical pixels', () {
      expect(androidScrollUnit(_waydroidPixelRatio), closeTo(63.85, 0.01));
      expect(androidScrollUnit(1), 64);
      expect(androidScrollUnit(3), 64);
    });

    testWidgets('touches are resampled 5 ms behind the frame, as Android does', (
      tester,
    ) async {
      final binding = GestureBinding.instance;
      final enabled = binding.resamplingEnabled;
      final offset = binding.samplingOffset;
      addTearDown(() {
        binding
          ..resamplingEnabled = enabled
          ..samplingOffset = offset;
      });
      WaydroidDetection.paceTouches();
      expect(binding.resamplingEnabled, isTrue);
      expect(binding.samplingOffset, const Duration(milliseconds: -5));
    });
  });

  group('acceleration inversion', () {
    for (final hz in [60.0, 90.0, 120.0, 125.0]) {
      test('recovers every raw notch at $hz Hz', () {
        var events = 0;
        for (final speed in [40.0, 120.0, 250.0, 400.0, 700.0, 1500, 4000]) {
          for (var seed = 0; seed < 4; seed++) {
            final pipeline = _Pipeline(hz: hz, seed: seed);
            final decoder = AndroidWheelAccelerationDecoder();
            for (final event in pipeline.run(_steady(speed.toDouble()), 1)) {
              expect(
                decoder.decode(event.stampUs, event.delta / _Pipeline.unit),
                event.notches,
                reason: '$speed px/s, seed $seed at ${event.stampUs} us',
              );
              events++;
            }
          }
        }
        expect(events, greaterThan(1000));
      });
    }

    test('recovers notches through reversals, pauses and flicks', () {
      final decoder = AndroidWheelAccelerationDecoder();
      final pipeline = _Pipeline(seed: 7);
      final profiles = [
        _flick(2500),
        _slowingStop(1200, stopIn: 0.2),
        _reversal(600, 0.25),
        _steady(90),
      ];
      var offset = 0.0;
      for (final profile in profiles) {
        // A second's rest between gestures lets Android's tracker reset.
        for (final event in pipeline.run(
          (t) => offset + profile(t),
          1,
          from: pipeline.elapsed,
        )) {
          expect(
            decoder.decode(event.stampUs, event.delta / _Pipeline.unit),
            event.notches,
          );
        }
        offset += profile(1);
        pipeline.elapsed += 2;
      }
    });

    test('Android amplifies a medium swipe several times over', () {
      // The problem being solved: at 300-600 px/s of finger travel every
      // 10 px notch reaches Flutter as up to four 64 px units.
      final events = _Pipeline().run(_steady(500), 0.5);
      final reported = events.fold<double>(0, (sum, e) => sum + e.delta);
      final raw = events.fold<int>(0, (sum, e) => sum + e.notches);
      expect(reported / (raw * waydroidNotchDistance), greaterThan(15));
    });
  });

  group('motion model', () {
    for (final hz in [60.0, 120.0]) {
      for (final speed in [100.0, 400.0, 1500.0]) {
        test('follows a $speed px/s swipe one to one at $hz Hz', () {
          final run = _model(_slowingStop(speed, steadyFor: 0.6), 0.9, hz: hz);
          final notches = run.received;
          // The page ends where the notches took it, give or take the half
          // notch it may drift while a slowing stream's notch is late.
          expect(run.shown.last, inInclusiveRange(notches - 0.01, notches + 8));
          expect(notches, closeTo(run.finger, waydroidNotchDistance));
          // While the fingers move steadily the page moves at their speed.
          final steady = run.steps(from: 0.25, to: 0.55);
          final mean = steady.reduce((a, b) => a + b) / steady.length;
          expect(mean * 120, closeTo(speed, speed * 0.06));
        });
      }
    }

    test('steady swipes move every frame without steps', () {
      for (final hz in [60.0, 120.0]) {
        for (final speed in [100.0, 250.0, 400.0, 700.0, 1500.0]) {
          final run = _model(_steady(speed), 0.6, hz: hz);
          final steps = run.steps(from: 0.2, to: 0.55);
          final expected = speed / 120;
          // 60 Hz input carries half as many, coarser packets.
          final ripple = hz < 100 ? 0.18 : 0.09;
          for (var i = 0; i < steps.length; i++) {
            expect(steps[i], greaterThan(expected * 0.75), reason: '$speed');
            expect(steps[i], lessThan(expected * 1.25), reason: '$speed');
            if (i > 0) {
              expect(
                (steps[i] - steps[i - 1]).abs(),
                lessThan(math.max(ripple * expected, 0.15)),
                reason: '$speed px/s at $hz Hz, frame $i: '
                    '${steps[i - 1]} then ${steps[i]}',
              );
            }
          }
        }
      }
    });

    test('a fast lift coasts on premium coast physics from the page speed', () {
      for (final hz in [60.0, 120.0]) {
        for (final peak in [1000.0, 2000.0, 3500.0]) {
          final run = _model(_flick(peak), 0.3, seconds: 2.2, hz: hz);
          expect(run.coastStarts, isNotEmpty, reason: '$peak px/s at $hz Hz');
          final coastFrom = run.coastStarts.last;
          expect(coastFrom, greaterThan(run.lastNotch));
          final launch = run.velocities[coastFrom];
          // At 60 Hz the last packet holds only part of a frame's travel,
          // which slows the page a little before the stream's end is judged.
          expect(launch, closeTo(peak, peak * 0.3), reason: '$peak at $hz');
          // Velocity-continuous into the coast.
          final before = run.shown[coastFrom] - run.shown[coastFrom - 1];
          final after = run.shown[coastFrom + 1] - run.shown[coastFrom];
          expect((after - before).abs(), lessThan(peak / 120 * 0.1));
          final travel = run.shown.last - run.shown[coastFrom];
          expect(
            travel,
            closeTo(
              premiumCoastDistance(launch),
              premiumCoastDistance(launch) * 0.02,
            ),
          );
          expect(run.received, lessThan(run.shown.last - 200));
        }
      }
    });

    test('fingers that slow to a stop do not coast', () {
      for (final hz in [60.0, 120.0]) {
        final profiles = {
          '800 in 150 ms': _slowingStop(800),
          '1500 in 120 ms': _slowingStop(1500, stopIn: 0.12),
          '1500 in 250 ms': _slowingStop(1500, stopIn: 0.25),
          '2500 in 150 ms': _slowingStop(2500),
          '600 in 100 ms': _slowingStop(600, stopIn: 0.1),
          '1500 in 40 ms': _slowingStop(1500, stopIn: 0.04),
          'steady 300': _steady(300),
        };
        for (final MapEntry(key: name, value: profile) in profiles.entries) {
          final run = _model(profile, 0.6, seconds: 1.6, hz: hz);
          // A notch arriving late mid-slowdown may start a coast that the
          // next notch catches at once; once the last notch is in, none.
          expect(
            run.coastStarts.where((f) => f > run.lastNotch),
            isEmpty,
            reason: '$name at $hz Hz',
          );
          // It ends where the notches took it, within the notch the fingers
          // were last somewhere in.
          expect(
            run.shown.last,
            inInclusiveRange(run.received - 0.01, run.received + 10),
            reason: '$name at $hz Hz',
          );
          expect(run.shown.last, run.shown[run.shown.length - 30]);
        }
      }
    });

    test('a slowing stream eases out instead of stopping and starting', () {
      for (final hz in [60.0, 120.0]) {
        for (final profile in [_slowingStop(800), _slowingStop(400)]) {
          final steps = _model(profile, 0.6, hz: hz).steps(from: 0, to: 1);
          final fastest = steps.indexOf(steps.reduce(math.max));
          final stoppedAt = steps.indexWhere((step) => step < 0.005, fastest);
          expect(stoppedAt, greaterThan(fastest));
          // Once the page has stopped it stays stopped.
          for (final step in steps.skip(stoppedAt)) {
            expect(step, lessThan(0.005), reason: '$hz Hz');
          }
        }
      }
    });

    test('reversing follows the fingers back', () {
      final run = _model(_reversal(600, 0.3), 0.9, seconds: 1.4);
      expect(run.coastStarts.where((f) => f > run.lastNotch), isEmpty);
      expect(run.shown.last, closeTo(run.received, 10));
      final peakAt = run.shown.indexOf(run.shown.reduce(math.max));
      // The page turns within ~60 ms of the fingers.
      expect(run.time(peakAt), lessThan(0.3 + 0.08));
      final steps = run.steps(from: 0, to: 1.4);
      for (var i = 1; i < steps.length; i++) {
        expect((steps[i] - steps[i - 1]).abs(), lessThan(3));
      }
    });

    test('notches during a coast catch it like a touch-down', () {
      // A flick lifts at 120 ms; at 400 ms new fingers push on at 800 px/s
      // during its coast; at 900 ms, during the next coast, they pull back.
      double finger(double t) =>
          _flick(2000)(t) +
          _steady(800)((t - 0.4).clamp(0.0, 0.3)) -
          _slowingStop(600, steadyFor: 0.15)((t - 0.9).clamp(0.0, 0.4));
      final events = _Pipeline().run(finger, 1.3);
      final motion = WaydroidScrollMotion();
      final startUs = events.first.stampUs - 1000;
      final shown = <double>[0];
      final coasting = <bool>[false];
      var e = 0;
      int? pushedAt;
      int? pulledAt;
      for (var f = 1; f < 200; f++) {
        final nowUs = startUs + f * 8333;
        while (e < events.length && events[e].stampUs <= nowUs) {
          final late = events[e].stampUs - startUs;
          if (late > 380000 && pushedAt == null) pushedAt = f;
          if (late > 880000 && pulledAt == null) pulledAt = f;
          motion.addNotches(
            events[e].stampUs,
            events[e].notches * waydroidNotchDistance,
          );
          e++;
        }
        motion.advance(nowUs, 1 / 120);
        shown.add(motion.shown);
        coasting.add(motion.isReleased);
      }
      double step(int f) => shown[f] - shown[f - 1];
      expect(coasting[pushedAt! - 1], isTrue);
      expect(coasting[pulledAt! - 1], isTrue);
      // Pushing on carries on from the page's speed, without a jolt...
      for (var f = pushedAt; f < pushedAt + 6; f++) {
        expect((step(f) - step(f - 1)).abs(), lessThan(1.5));
      }
      // ...and the coast's own momentum is dropped: within 150 ms the page
      // moves at the fingers' 800 px/s, not the coast's.
      expect(step(pushedAt + 18) * 120, closeTo(800, 120));
      // Pulling back stops the page, then follows the fingers.
      expect(step(pulledAt + 1), lessThanOrEqualTo(0.01));
      expect(shown.last, lessThan(shown[pulledAt] - 60));
    });

    test('a page pressed against an edge drops notches into it', () {
      final motion = WaydroidScrollMotion();
      motion.addNotches(0, 10);
      motion.advance(8333, 1 / 120);
      motion.hitEdge(motion.shown);
      expect(motion.velocity, 0);
      expect(motion.received, motion.shown);
      motion.addNotches(16000, -10);
      var shown = motion.shown;
      for (var f = 2; f < 40; f++) {
        motion.advance(f * 8333, 1 / 120);
        expect(motion.shown, lessThanOrEqualTo(shown + 1e-9));
        shown = motion.shown;
      }
      // The lone notch is followed, plus at most the half notch the page may
      // drift past a stream's total.
      expect(motion.shown, inInclusiveRange(-15.01, -9.99));
    });
  });

  group('scrolling', () {
    setUp(() => WaydroidDetection.debugIsWaydroid = true);
    tearDown(() => WaydroidDetection.debugIsWaydroid = null);

    testWidgets('touchpad swipes scroll one to one', (tester) async {
      final controller = await _mount(tester);
      final pipeline = _Pipeline();
      for (final speed in [150.0, 500.0, 1500.0]) {
        final start = controller.offset;
        final events = pipeline.run(
          _slowingStop(speed, steadyFor: 0.3),
          0.6,
          from: pipeline.elapsed,
        );
        pipeline.elapsed += 3;
        await _play(tester, events, seconds: 1.4);
        final notches = events.fold<int>(0, (s, e) => s + e.notches) *
            waydroidNotchDistance;
        expect(controller.offset - start, closeTo(notches, 8));
        expect(notches, closeTo(_slowingStop(speed, steadyFor: 0.3)(0.6), 10));
        expect(controller.position.isScrollingNotifier.value, isFalse);
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('frames advance smoothly at 120 Hz', (tester) async {
      final controller = await _mount(tester);
      final offsets = await _play(
        tester,
        _Pipeline().run(_steady(600), 0.6),
        seconds: 0.6,
        controller: controller,
      );
      final steps = [
        for (var i = 30; i < 70; i++) offsets[i] - offsets[i - 1],
      ];
      for (var i = 0; i < steps.length; i++) {
        expect(steps[i], inInclusiveRange(4, 6), reason: 'frame $i');
        if (i > 0) expect((steps[i] - steps[i - 1]).abs(), lessThan(0.5));
      }
    });

    testWidgets('a flick coasts and a coast continues velocity', (
      tester,
    ) async {
      final controller = await _mount(tester);
      final events = _Pipeline().run(_flick(2000), 0.15);
      final offsets = await _play(
        tester,
        events,
        seconds: 1.5,
        controller: controller,
      );
      final notches =
          events.fold<int>(0, (s, e) => s + e.notches) * waydroidNotchDistance;
      expect(controller.offset - 1000, greaterThan(notches + 400));
      for (var i = 2; i < offsets.length; i++) {
        final step = offsets[i] - offsets[i - 1];
        final previous = offsets[i - 1] - offsets[i - 2];
        expect((step - previous).abs(), lessThan(4), reason: 'frame $i');
      }
      await tester.pumpAndSettle(_frame);
      expect(controller.position.isScrollingNotifier.value, isFalse);
    });

    testWidgets('a slow stop settles without coasting', (tester) async {
      final controller = await _mount(tester);
      final events = _Pipeline().run(_slowingStop(800), 0.6);
      await _play(tester, events, seconds: 0.8);
      final settled = controller.offset;
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.offset, settled);
      final notches =
          events.fold<int>(0, (s, e) => s + e.notches) * waydroidNotchDistance;
      expect(settled - 1000, inInclusiveRange(notches - 0.01, notches + 10));
    });

    testWidgets('edges stop the page and release it at once', (tester) async {
      final controller = await _mount(tester, initialOffset: 200);
      final pipeline = _Pipeline();
      // A flick toward the top would carry far past it.
      await _play(
        tester,
        pipeline.run((t) => -_flick(2000)(t), 0.15),
        seconds: 1,
      );
      expect(controller.offset, 0);
      expect(controller.position.outOfRange, isFalse);
      expect(controller.position.isScrollingNotifier.value, isFalse);
      // Pushed against the edge, then straight back down: nothing pushed
      // into the edge is owed back first.
      final events = pipeline.run(
        (t) =>
            -_steady(400)(math.min(t, 0.2)) +
            _steady(400)(math.max(0, t - 0.2)),
        0.5,
        from: 2,
      );
      await _play(tester, events, seconds: 0.9);
      final down = events
              .where((e) => e.notches > 0)
              .fold<int>(0, (s, e) => s + e.notches) *
          waydroidNotchDistance;
      expect(controller.offset, closeTo(down, 8));
      // And the bottom edge.
      controller.jumpTo(controller.position.maxScrollExtent - 100);
      await _play(
        tester,
        pipeline.run(_flick(2000), 0.15, from: 4),
        seconds: 1,
      );
      expect(controller.offset, controller.position.maxScrollExtent);
      expect(controller.position.isScrollingNotifier.value, isFalse);
    });

    testWidgets('horizontal and shift-wheel notches scroll sideways', (
      tester,
    ) async {
      final controller = await _mount(tester, axis: Axis.horizontal);
      final events = _Pipeline().run(_slowingStop(500, steadyFor: 0.3), 0.6);
      await _play(tester, events, seconds: 1.2, horizontal: true);
      final notches =
          events.fold<int>(0, (s, e) => s + e.notches) * waydroidNotchDistance;
      expect(controller.offset - 1000, closeTo(notches, 8));
    });

    testWidgets('vertical lists in a tab view scroll; tabs snap to pages', (
      tester,
    ) async {
      tester.view.devicePixelRatio = _waydroidPixelRatio;
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.display.resetRefreshRate);
      final page = PageController();
      addTearDown(page.dispose);
      final lists = [ScrollController(), ScrollController()];
      for (final list in lists) {
        addTearDown(list.dispose);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumScrollScope(
            enabled: true,
            child: PageView(
              key: _listKey,
              controller: page,
              children: [
                for (final list in lists)
                  ListView.builder(
                    controller: list,
                    itemExtent: 40,
                    itemCount: 500,
                    itemBuilder: (_, i) => Text('Row $i'),
                  ),
              ],
            ),
          ),
        ),
      );
      final pipeline = _Pipeline();
      final events = pipeline.run(_slowingStop(500, steadyFor: 0.3), 0.6);
      await _play(tester, events, seconds: 1.2);
      final notches =
          events.fold<int>(0, (s, e) => s + e.notches) * waydroidNotchDistance;
      expect(lists.first.offset, closeTo(notches, 8));
      expect(page.offset, 0);
      // A sideways flick turns the page and lands on it.
      await _play(
        tester,
        pipeline.run(_flick(2000), 0.12, from: 2),
        seconds: 1,
        horizontal: true,
      );
      await tester.pumpAndSettle();
      expect(page.page, 1);
    });

    testWidgets('coordinated nested views share notches with the header', (
      tester,
    ) async {
      tester.view.devicePixelRatio = _waydroidPixelRatio;
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.display.resetRefreshRate);
      final nestedKey = GlobalKey<NestedScrollViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumScrollScope(
            enabled: true,
            child: Center(
              child: SizedBox(
                width: 400,
                height: 500,
                child: PremiumCoordinatedScrollScope(
                  child: NestedScrollView(
                    key: nestedKey,
                    headerSliverBuilder: (_, __) => const [
                      SliverToBoxAdapter(child: SizedBox(height: 160)),
                    ],
                    body: ListView.builder(
                      key: _listKey,
                      itemExtent: 40,
                      itemCount: 500,
                      itemBuilder: (_, i) => Text('Row $i'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final events = _Pipeline().run(_slowingStop(600, steadyFor: 0.4), 0.7);
      await _play(tester, events, seconds: 1.4);
      final nested = nestedKey.currentState!;
      final notches =
          events.fold<int>(0, (s, e) => s + e.notches) * waydroidNotchDistance;
      // The header scrolls away first, then the body, as one distance.
      expect(nested.outerController.offset, 160);
      expect(
        nested.outerController.offset + nested.innerController.offset,
        inInclusiveRange(notches - 0.5, notches + 10),
      );
    });

    testWidgets('touch drags follow the finger as on Android', (tester) async {
      Future<List<double>> drag() async {
        final controller = await _mount(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_listKey)),
        );
        final offsets = <double>[];
        for (var i = 0; i < 10; i++) {
          await gesture.moveBy(const Offset(0, -12));
          await tester.pump(_frame);
          offsets.add(controller.offset);
        }
        await gesture.up();
        for (var i = 0; i < 60; i++) {
          await tester.pump(_frame);
          offsets.add(controller.offset);
        }
        return offsets;
      }

      final waydroid = await drag();
      WaydroidDetection.debugIsWaydroid = false;
      await tester.pumpWidget(const SizedBox());
      final android = await drag();
      expect(waydroid, android);
    });

    // In Waydroid a touch is the host's touchpad, played as a finger: its
    // release coasts as the desktop app's touchpad does, not as a phone fling.
    testWidgets('touch flings coast on the desktop touchpad physics', (
      tester,
    ) async {
      const speed = 2400.0;
      Future<double> fling() async {
        final controller = await _mount(tester);
        final gesture = await tester.createGesture();
        var time = Duration.zero;
        await gesture.down(
          tester.getCenter(find.byKey(_listKey)),
          timeStamp: time,
        );
        for (var i = 0; i < 12; i++) {
          time += _frame;
          await gesture.moveBy(
            Offset(0, -speed * _frame.inMicroseconds / 1e6),
            timeStamp: time,
          );
          await tester.pump(_frame);
        }
        await gesture.up(timeStamp: time);
        final released = controller.offset;
        await tester.pumpAndSettle(_frame);
        return controller.offset - released;
      }

      final waydroid = await fling();
      WaydroidDetection.debugIsWaydroid = false;
      await tester.pumpWidget(const SizedBox());
      final android = await fling();
      final coast = premiumCoastDistance(speed);
      expect(waydroid, closeTo(coast, coast * 0.03));
      expect((android - waydroid).abs(), greaterThan(coast * 0.1));
    });
  });

  testWidgets('mouse wheels elsewhere keep premium wheel smoothing', (
    tester,
  ) async {
    expect(WaydroidDetection.isWaydroid, isFalse);
    final controller = await _mount(tester);
    final point = tester.getCenter(find.byKey(_listKey));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, 64)),
    );
    // Queued, not jumped to, and then scrolled exactly.
    expect(controller.offset, 1000);
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(controller.offset, inExclusiveRange(1000, 1064));
    await tester.pumpAndSettle(_frame);
    expect(controller.offset, closeTo(1064, 0.11));
  });
}

/// Finger position in host pixels after [t] seconds.
typedef _Finger = double Function(double t);

_Finger _steady(double speed) => (t) => speed * t;

/// Accelerates to [peak] in 80 ms, holds it for 40 ms, then lifts.
_Finger _flick(double peak) => (t) {
      const accelerate = 0.08;
      if (t < accelerate) return peak * t * t / (2 * accelerate);
      return peak * accelerate / 2 + peak * math.min(t - accelerate, 0.04);
    };

/// Moves at [speed] for [steadyFor], then slows evenly to rest in [stopIn].
_Finger _slowingStop(
  double speed, {
  double steadyFor = 0.2,
  double stopIn = 0.15,
}) =>
    (t) {
      if (t < steadyFor) return speed * t;
      final s = math.min(t - steadyFor, stopIn);
      return speed * steadyFor + speed * s - speed / (2 * stopIn) * s * s;
    };

/// Down at [speed] for [turnAt], back up, then easing to rest.
_Finger _reversal(double speed, double turnAt) => (t) {
      if (t < turnAt) return speed * t;
      return speed * turnAt -
          _slowingStop(speed, steadyFor: turnAt)(t - turnAt);
    };

class _WheelEvent {
  const _WheelEvent(this.stampUs, this.delta, this.notches);

  /// Flutter's stamp: Android's event time in whole milliseconds.
  final int stampUs;

  /// Flutter's scroll delta in logical pixels.
  final double delta;

  /// The raw notches Waydroid sent.
  final int notches;
}

/// Waydroid's hardware composer and Android 13's wheel acceleration,
/// modelled independently of the code under test.
class _Pipeline {
  _Pipeline({this.hz = 120, int seed = 0}) : _random = math.Random(seed);

  static const unit = 85 / _waydroidPixelRatio;
  static const _bootNs = 10000000000;

  final double hz;
  final math.Random _random;

  /// Seconds of host time already played.
  double elapsed = 0;

  double _accumulator = 0;
  int? _lastNs;
  final _samples = <(int, double)>[];
  double _raw = 0;

  List<_WheelEvent> run(_Finger finger, double seconds, {double from = 0}) {
    final events = <_WheelEvent>[];
    final frame = 1 / hz;
    var previous = finger(0);
    for (var k = 1; k * frame <= seconds + 1e-9; k++) {
      final t = k * frame;
      final x = finger(t);
      // wl_fixed_t carries 1/256 px.
      final value = ((x - previous) * 256).round() / 256;
      previous = x;
      if (value == 0) continue;
      _accumulator += value / 10;
      final notches = _accumulator.truncate();
      if (notches == 0) continue;
      _accumulator -= notches;
      // The composer stamps an event as it processes it.
      final ns = _bootNs +
          ((from + t + 0.0005 + _random.nextDouble() * 0.0015) * 1e9).round();
      final scale = _accelerate(ns, notches.toDouble());
      events.add(
        _WheelEvent((ns ~/ 1000000) * 1000, notches * scale * unit, notches),
      );
    }
    return events;
  }

  /// VelocityControl::move with WheelVelocityControlParameters 1/15/50/4.
  double _accelerate(int ns, double notches) {
    final last = _lastNs;
    if (last != null && ns >= last + 500000000) {
      _samples.clear();
      _raw = 0;
    } else if (last != null && ns >= last + 40000000) {
      // VelocityTracker: pointer assumed stopped.
      _samples.clear();
    }
    _lastNs = ns;
    _raw += notches;
    _samples.add((ns, _raw));
    if (_samples.length > 20) _samples.removeAt(0);
    final velocity = _leastSquaresVelocity(ns);
    if (velocity == null) return 1;
    final speed = velocity.abs();
    if (speed >= 50) return 4;
    if (speed > 15) return 1 + (speed - 15) / 35 * 3;
    return 1;
  }

  /// LeastSquaresVelocityTrackerStrategy, degree 2, unweighted.
  double? _leastSquaresVelocity(int nowNs) {
    final t = <double>[];
    final y = <double>[];
    for (var i = _samples.length - 1; i >= 0; i--) {
      final age = nowNs - _samples[i].$1;
      if (age > 100000000) break;
      t.add(-age / 1e9);
      y.add(_samples[i].$2);
    }
    if (t.length < 2) return null;
    if (t.length == 2) return (y[0] - y[1]) / (t[0] - t[1]);
    var sx = 0.0, sx2 = 0.0, sx3 = 0.0, sx4 = 0.0;
    var sy = 0.0, sxy = 0.0, sx2y = 0.0;
    for (var i = 0; i < t.length; i++) {
      sx += t[i];
      sx2 += t[i] * t[i];
      sx3 += t[i] * t[i] * t[i];
      sx4 += t[i] * t[i] * t[i] * t[i];
      sy += y[i];
      sxy += t[i] * y[i];
      sx2y += t[i] * t[i] * y[i];
    }
    final n = t.length;
    final a = sx2 - sx * sx / n;
    final b = sxy - sx * sy / n;
    final c = sx3 - sx * sx2 / n;
    final d = sx2y - sx2 * sy / n;
    final e = sx4 - sx2 * sx2 / n;
    return (b * e - d * c) / (a * e - c * c);
  }
}

class _ModelRun {
  _ModelRun(this.startUs);

  final int startUs;
  final shown = <double>[];
  final velocities = <double>[];
  double received = 0;
  double finger = 0;
  final coastStarts = <int>[];
  int lastNotch = 0;

  int? get coastStart => coastStarts.isEmpty ? null : coastStarts.first;

  double time(int frame) => frame / 120;

  /// Per-frame steps between [from] and [to] seconds.
  List<double> steps({required double from, required double to}) => [
        for (var i = math.max(1, (from * 120).round());
            i < math.min(shown.length, (to * 120).round());
            i++)
          shown[i] - shown[i - 1],
      ];
}

/// Plays [finger] for [duration] through the pipeline, the decoder and the
/// motion model at 120 Hz for [seconds].
_ModelRun _model(
  _Finger finger,
  double duration, {
  double seconds = 1.2,
  double hz = 120,
}) {
  final pipeline = _Pipeline(hz: hz);
  final events = pipeline.run(finger, duration);
  final decoder = AndroidWheelAccelerationDecoder();
  final motion = WaydroidScrollMotion();
  final run = _ModelRun(_Pipeline._bootNs ~/ 1000)..finger = finger(duration);
  var e = 0;
  for (var f = 0; f < seconds * 120; f++) {
    final nowUs = run.startUs + f * 8333;
    while (e < events.length && events[e].stampUs <= nowUs) {
      final notches = decoder.decode(
        events[e].stampUs,
        events[e].delta / _Pipeline.unit,
      );
      motion.addNotches(events[e].stampUs, notches * waydroidNotchDistance);
      run.received += notches * waydroidNotchDistance;
      run.lastNotch = f;
      e++;
    }
    final wasReleased = motion.isReleased;
    motion.advance(nowUs, 1 / 120);
    if (motion.isReleased && !wasReleased) run.coastStarts.add(f);
    run.shown.add(motion.shown);
    run.velocities.add(motion.velocity);
  }
  return run;
}

Future<ScrollController> _mount(
  WidgetTester tester, {
  double initialOffset = 1000,
  Axis axis = Axis.vertical,
}) async {
  tester.view.devicePixelRatio = _waydroidPixelRatio;
  tester.view.display.refreshRate = 120;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.display.resetRefreshRate);
  final controller = ScrollController(initialScrollOffset: initialOffset);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: PremiumScrollScope(
        enabled: true,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 500,
            child: ListView.builder(
              key: _listKey,
              controller: controller,
              scrollDirection: axis,
              itemExtent: 40,
              itemCount: 2000,
              itemBuilder: (_, index) => Text('Row $index'),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

/// Delivers [events] at the frames following their stamps, as the UI thread
/// receives input between frames, pumping 120 Hz frames for [seconds].
/// Returns the scroll offset after every frame.
Future<List<double>> _play(
  WidgetTester tester,
  List<_WheelEvent> events, {
  required double seconds,
  bool horizontal = false,
  ScrollController? controller,
}) async {
  final point = tester.getCenter(find.byKey(_listKey));
  final offsets = <double>[];
  final firstUs = events.isEmpty ? 0 : events.first.stampUs;
  var e = 0;
  for (var f = 0; f < seconds * 120; f++) {
    final nowUs = firstUs + f * _frame.inMicroseconds;
    while (e < events.length && events[e].stampUs <= nowUs) {
      final delta = events[e].delta;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          timeStamp: Duration(microseconds: events[e].stampUs),
          device: 3,
          position: point,
          scrollDelta: horizontal ? Offset(delta, 0) : Offset(0, delta),
        ),
      );
      e++;
    }
    await tester.pump(_frame);
    if (controller != null) offsets.add(controller.offset);
  }
  return offsets;
}
