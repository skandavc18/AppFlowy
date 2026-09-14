import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _desktop = TargetPlatformVariant({
  TargetPlatform.windows,
  TargetPlatform.linux,
});
const _listKey = ValueKey('desktop-kinetic-list');
const _frame = Duration(microseconds: 8333);

void main() {
  for (final tail in [-1.0, 0.0, 1.0]) {
    testWidgets(
      'trackpad release follows the recent tail, not an extrapolated curve: $tail',
      (tester) async {
        await _mount(tester);
        final tracker = _tracker(tester);
        var pan = Offset.zero;
        tracker.addPosition(Duration.zero, pan);
        for (var sample = 1; sample <= 8; sample++) {
          pan += Offset(0, sample <= 5 ? -30 : tail);
          tracker.addPosition(Duration(milliseconds: sample * 8), pan);
        }
        expect(
          tracker.getVelocityEstimate()!.pixelsPerSecond.dy,
          closeTo(tail / 0.008 * 0.60, 0.001),
          reason: 'Slow, stopped, and reversed tails must not inherit a '
              'speed boost from the fast part of the gesture.',
        );
      },
      variant: _desktop,
    );
  }

  testWidgets(
    'a timestamp gap discards stale trackpad momentum',
    (tester) async {
      await _mount(tester);
      final tracker = _tracker(tester);
      for (var sample = 0; sample < 5; sample++) {
        tracker.addPosition(
          Duration(milliseconds: sample * 8),
          Offset(0, -30.0 * sample),
        );
      }
      // Input can be delivered together after expensive native/embed work.
      // The event clock still records that the fingers stopped moving.
      tracker.addPosition(
        const Duration(milliseconds: 150),
        const Offset(0, -120),
      );
      expect(tracker.getVelocityEstimate()!.pixelsPerSecond, Offset.zero);
    },
    variant: _desktop,
  );

  testWidgets(
    'desktop coast is bounded and never adds previous-fling momentum',
    (tester) async {
      final controller = await _mount(tester);
      final physics = controller.position.physics;
      expect(physics.maxFlingVelocity, 4800);
      for (final velocity in [-4800.0, -1200.0, 1200.0, 4800.0]) {
        expect(physics.carriedMomentum(velocity), 0);
        final simulation = physics.createBallisticSimulation(
          controller.position,
          velocity,
        )!;
        expect(simulation.dx(0), closeTo(velocity, 0.001));
        expect(simulation.dx(0.05).abs(), lessThan(velocity.abs()));
        expect(simulation.isDone(2), isTrue);
      }
    },
    variant: _desktop,
  );

  testWidgets(
    'restarting a coast for changed embed extents preserves its trajectory',
    (tester) async {
      final controller = await _mount(tester);
      final physics = controller.position.physics;
      final first = physics.createBallisticSimulation(
        controller.position,
        1800,
      )!;
      const restartTime = 0.12;
      final changed = controller.position.copyWith(
        pixels: first.x(restartTime),
        maxScrollExtent: controller.position.maxScrollExtent + 600,
      );
      final resumed = physics.createBallisticSimulation(
        changed,
        first.dx(restartTime),
      )!;
      for (final time in [0.0, 0.008333, 0.04, 0.1]) {
        expect(resumed.x(time), closeTo(first.x(restartTime + time), 0.01));
        expect(resumed.dx(time), closeTo(first.dx(restartTime + time), 0.01));
      }
    },
    variant: _desktop,
  );

  testWidgets(
    'an abrupt slowdown or reversal cannot release faster or the wrong way',
    (tester) async {
      await _mount(tester);
      for (final tail in [-1.0, 0.0, 1.0]) {
        final tracker = _tracker(tester);
        for (var sample = 0; sample <= 5; sample++) {
          tracker.addPosition(
            Duration(milliseconds: sample * 8),
            Offset(0, -30.0 * sample),
          );
        }
        tracker.addPosition(
          const Duration(milliseconds: 48),
          Offset(0, -150 + tail),
        );
        final velocity = tracker.getVelocityEstimate()!.pixelsPerSecond.dy;
        expect(velocity.abs(), lessThanOrEqualTo(tail.abs() / 0.008 * 0.60));
        expect(velocity == 0 || velocity.sign == tail.sign, isTrue);
      }
    },
    variant: _desktop,
  );

  testWidgets(
    'empty and duplicate-timestamp input cannot manufacture a fling',
    (tester) async {
      await _mount(tester);
      final tracker = _tracker(tester);
      expect(tracker.getVelocityEstimate(), isNull);
      for (var sample = 0; sample <= 5; sample++) {
        tracker.addPosition(Duration.zero, Offset(0, -30.0 * sample));
      }
      expect(tracker.getVelocityEstimate()!.pixelsPerSecond, Offset.zero);
      tracker.addPosition(const Duration(milliseconds: 100), const Offset(0, -200));
      tracker.addPosition(const Duration(milliseconds: 90), const Offset(0, -220));
      expect(tracker.getVelocityEstimate()!.pixelsPerSecond, Offset.zero);
    },
    variant: _desktop,
  );

  testWidgets(
    'identical swipes do not compound an existing coast',
    (tester) async {
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      for (var gesture = 0; gesture < 3; gesture++) {
        await _start(tester, point);
        final start = controller.offset;
        for (var step = 1; step <= 8; step++) {
          await _update(tester, point, step, -20);
        }
        expect(controller.offset - start, closeTo(160 * 0.60, 0.01));
        final release = controller.offset;
        await _end(tester, point, _frame * 8 + const Duration(milliseconds: 1));
        await tester.pump();
        final simulation = controller.position.physics.createBallisticSimulation(
          controller.position,
          20 / (_frame.inMicroseconds / 1e6) * 0.60,
        )!;
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.offset, closeTo(simulation.x(0.1), 0.01));
        expect(controller.offset, greaterThan(release));
      }
      // Resting new fingers stop the old coast before another pan develops.
      await _start(tester, point);
      final held = controller.offset;
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.offset, held);
      await _end(tester, point, const Duration(milliseconds: 201));
      await tester.pumpAndSettle(_frame);
      expect(controller.offset, held);
    },
    variant: _desktop,
  );

  for (final fps in [60, 120]) {
    testWidgets(
      'coasting displacement decays at $fps Hz without a late surge',
      (tester) async {
        final controller = await _mount(tester);
        final point = tester.getCenter(find.byKey(_listKey));
        await _start(tester, point);
        for (var step = 1; step <= 8; step++) {
          await _update(tester, point, step, -20);
        }
        await _end(tester, point, _frame * 8 + const Duration(milliseconds: 1));
        await tester.pump();
        var previous = controller.offset;
        var previousDelta = double.infinity;
        for (var frame = 0; frame < fps; frame++) {
          await tester.pump(Duration(microseconds: (1e6 / fps).round()));
          final delta = controller.offset - previous;
          expect(delta, greaterThanOrEqualTo(0));
          expect(delta, lessThanOrEqualTo(previousDelta + 0.01));
          previousDelta = delta;
          previous = controller.offset;
        }
        await tester.pumpAndSettle(_frame);
        expect(controller.position.outOfRange, isFalse);
      },
      variant: _desktop,
    );
  }

  testWidgets(
    'both ballistic edges bounce symmetrically and preserve spring restarts',
    (tester) async {
      final controller = await _mount(tester);
      final physics = controller.position.physics;
      final top = controller.position.copyWith(pixels: 20);
      final bottom = controller.position.copyWith(
        pixels: controller.position.maxScrollExtent - 20,
      );
      final upward = physics.createBallisticSimulation(top, -4800)!;
      final downward = physics.createBallisticSimulation(bottom, 4800)!;
      var bounced = false;
      for (var sample = 0; sample <= 240; sample++) {
        final time = sample / 120;
        expect(
          upward.x(time),
          closeTo(bottom.maxScrollExtent - downward.x(time), 0.001),
        );
        expect(upward.x(time), greaterThan(-120));
        bounced |= upward.x(time) < 0;
      }
      expect(bounced, isTrue);
      expect(upward.x(2), closeTo(0, 0.01));
      const restart = 0.1;
      final resumed = physics.createBallisticSimulation(
        top.copyWith(pixels: upward.x(restart)),
        upward.dx(restart),
      )!;
      for (final time in [0.0, 0.02, 0.1, 0.2]) {
        expect(resumed.x(time), closeTo(upward.x(restart + time), 0.01));
        expect(resumed.dx(time), closeTo(upward.dx(restart + time), 0.01));
      }
    },
    variant: _desktop,
  );

  testWidgets(
    'a batched end-only pause does not release stale momentum',
    (tester) async {
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      for (var step = 1; step <= 8; step++) {
        await _update(tester, point, step, -20);
      }
      final stopped = controller.offset;
      // No stationary update and no UI-thread wait: only the end packet's
      // timestamp tells us that the gesture has been still for over 40ms.
      await _end(tester, point, const Duration(milliseconds: 250));
      await tester.pumpAndSettle(_frame);
      expect(controller.offset, closeTo(stopped, 0.01));
    },
    variant: _desktop,
  );

  testWidgets(
    'inward edge releases continue smoothly through layout restarts',
    (tester) async {
      final controller = await _mount(tester);
      final physics = controller.position.physics;
      for (final bottom in [false, true]) {
        final edge = bottom ? controller.position.maxScrollExtent : 0.0;
        final metrics = controller.position.copyWith(
          pixels: edge + (bottom ? 20 : -20),
        );
        final motion = physics.createBallisticSimulation(metrics, bottom ? -1200 : 1200)!;
        const restart = 0.1;
        final newPixels = motion.x(restart);
        expect(bottom ? newPixels < edge : newPixels > edge, isTrue);
        final resumed = physics.createBallisticSimulation(
          metrics.copyWith(pixels: newPixels),
          motion.dx(restart),
        )!;
        for (final time in [0.0, 0.02, 0.1, 0.2]) {
          expect(resumed.x(time), closeTo(motion.x(restart + time), 0.01));
          expect(resumed.dx(time), closeTo(motion.dx(restart + time), 0.01));
        }
      }
    },
    variant: _desktop,
  );

  for (final fallback in [
    (enabled: false, reducedMotion: false),
    (enabled: true, reducedMotion: true),
  ]) {
    testWidgets(
      'native clamping is retained when premium motion is disabled: $fallback',
      (tester) async {
        final controller = await _mount(
          tester,
          initialOffset: 0,
          enabled: fallback.enabled,
          reducedMotion: fallback.reducedMotion,
        );
        expect(controller.position.physics, isA<ClampingScrollPhysics>());
        final point = tester.getCenter(find.byKey(_listKey));
        await _start(tester, point);
        for (var step = 1; step <= 5; step++) {
          await _update(tester, point, step, 30);
        }
        await _end(tester, point, const Duration(milliseconds: 42));
        await tester.pumpAndSettle(_frame);
        expect(controller.offset, 0);
      },
      variant: _desktop,
    );
  }

  for (final physics in [
    const NeverScrollableScrollPhysics(),
    const ClampingScrollPhysics(),
  ]) {
    testWidgets(
      'explicit widget physics still control scrolling: $physics',
      (tester) async {
        final controller = await _mount(tester, initialOffset: 0, physics: physics);
        expect(controller.position.physics.runtimeType, physics.runtimeType);
        final point = tester.getCenter(find.byKey(_listKey));
        await _start(tester, point);
        for (var step = 1; step <= 5; step++) {
          await _update(tester, point, step, 30);
        }
        await _end(tester, point, const Duration(milliseconds: 42));
        await tester.pumpAndSettle(_frame);
        expect(controller.offset, 0);
        await tester.sendEventToBinding(
          PointerScrollEvent(position: point, scrollDelta: const Offset(0, 80)),
        );
        await tester.pumpAndSettle(_frame);
        expect(
          controller.offset,
          closeTo(physics is NeverScrollableScrollPhysics ? 0 : 80, 0.11),
        );
      },
      variant: _desktop,
    );
  }

  testWidgets(
    'native macOS and mobile physics and estimators remain unchanged',
    (tester) async {
      final controller = await _mount(tester);
      final context = tester.element(find.byKey(_listKey));
      final native = const MaterialScrollBehavior().getScrollPhysics(context);
      final actual = controller.position.physics;
      expect(actual, isA<PremiumKineticScrollPhysics>());
      expect(actual.parent.runtimeType, native.runtimeType);
      expect(actual.maxFlingVelocity, native.maxFlingVelocity);
      expect(actual.carriedMomentum(1200), native.carriedMomentum(1200));
      expect(actual.applyPhysicsToUserOffset(controller.position, 100), 100);
      final nativeTracker = const MaterialScrollBehavior().velocityTrackerBuilder(context)(
        const PointerPanZoomStartEvent(pointer: 61, device: 61),
      );
      expect(_tracker(tester).runtimeType, nativeTracker.runtimeType);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.fuchsia,
    }),
  );

  for (final bottom in [false, true]) {
    testWidgets(
      'trackpad edge pull resists and springs back: bottom=$bottom',
      (tester) async {
        final controller = await _mount(tester, initialOffset: 0);
        final position = controller.position;
        final edge = bottom ? position.maxScrollExtent : position.minScrollExtent;
        controller.jumpTo(edge);
        await tester.pumpAndSettle();
        final point = tester.getCenter(find.byKey(_listKey));
        final direction = bottom ? -1.0 : 1.0;
        await _start(tester, point);
        for (var step = 1; step <= 6; step++) {
          await _update(tester, point, step, direction * 30);
        }
        final pulled = controller.offset;
        final outside = (pulled - edge).abs();
        expect(bottom ? pulled > edge : pulled < edge, isTrue);
        expect(outside, inExclusiveRange(0, 180 * 0.60));
        // Hold before release: the spring must return even with zero velocity.
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            pointer: 61,
            device: 61,
            position: point,
            pan: Offset(0, direction * 180),
            timeStamp: const Duration(milliseconds: 200),
          ),
        );
        await _end(tester, point, const Duration(milliseconds: 201));
        await tester.pump(_frame);
        await tester.pump(const Duration(milliseconds: 80));
        expect((controller.offset - edge).abs(), lessThan(outside));
        await tester.pumpAndSettle(_frame);
        expect(controller.offset, closeTo(edge, 0.01));
        expect(position.isScrollingNotifier.value, isFalse);
      },
      variant: _desktop,
    );

    testWidgets(
      'mouse wheel never leaves an elastic page stranded: bottom=$bottom',
      (tester) async {
        final controller = await _mount(tester, initialOffset: 0);
        final position = controller.position;
        final edge = bottom ? position.maxScrollExtent : position.minScrollExtent;
        controller.jumpTo(edge + (bottom ? -10 : 10));
        await tester.pumpAndSettle();
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byKey(_listKey)),
            scrollDelta: Offset(0, bottom ? 120 : -120),
          ),
        );
        await tester.pumpAndSettle(_frame);
        expect(controller.offset, closeTo(edge, 0.01));
        expect(position.outOfRange, isFalse);
        expect(position.isScrollingNotifier.value, isFalse);
      },
      variant: _desktop,
    );
  }
}

Future<ScrollController> _mount(
  WidgetTester tester, {
  double initialOffset = 1000,
  bool enabled = true,
  bool reducedMotion = false,
  ScrollPhysics? physics,
}) async {
  final controller = ScrollController(initialScrollOffset: initialOffset);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: PremiumScrollScope(
          enabled: enabled,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: ListView.builder(
                key: _listKey,
                controller: controller,
                physics: physics,
                itemExtent: 40,
                itemCount: 300,
                itemBuilder: (_, index) => Text('Generated item $index'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

VelocityTracker _tracker(WidgetTester tester) {
  final context = tester.element(find.byKey(_listKey));
  return ScrollConfiguration.of(context).velocityTrackerBuilder(context)(
    const PointerPanZoomStartEvent(pointer: 61, device: 61),
  );
}

Future<void> _start(WidgetTester tester, Offset point) =>
    tester.sendEventToBinding(
      PointerPanZoomStartEvent(pointer: 61, device: 61, position: point),
    );

Future<void> _update(
  WidgetTester tester,
  Offset point,
  int step,
  double delta,
) async {
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      pointer: 61,
      device: 61,
      position: point,
      pan: Offset(0, delta * step),
      panDelta: Offset(0, delta),
      timeStamp: _frame * step,
    ),
  );
  await tester.pump(_frame);
}

Future<void> _end(WidgetTester tester, Offset point, Duration time) =>
    tester.sendEventToBinding(
      PointerPanZoomEndEvent(
        pointer: 61,
        device: 61,
        position: point,
        timeStamp: time,
      ),
    );