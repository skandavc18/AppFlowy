import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kinetic simulation decays exponentially without an abrupt stop', () {
    final simulation = PremiumKineticScrollSimulation(
      position: 100,
      velocity: 1000,
      friction: 5,
      stopVelocity: 8,
    );

    expect(simulation.x(0), 100);
    expect(simulation.dx(0), 1000);
    expect(simulation.x(0.1), greaterThan(100));
    expect(simulation.x(0.5), greaterThan(simulation.x(0.1)));
    expect(simulation.dx(0.5), lessThan(simulation.dx(0.1)));
    expect(simulation.x(10), closeTo(300, 0.001));
    expect(simulation.isDone(0.5), isFalse);
    expect(simulation.isDone(1), isTrue);
  });

  test('wheel impulses normalize standard and high-resolution input', () {
    const config = PremiumScrollPhysicsConfig();

    expect(
      premiumScrollVelocityImpulse(
        delta: 80,
        kind: PointerDeviceKind.mouse,
      ),
      640,
    );
    expect(
      premiumScrollVelocityImpulse(
        delta: 10,
        kind: PointerDeviceKind.mouse,
      ),
      140,
    );
    expect(
      premiumScrollVelocityImpulse(
        delta: 500,
        kind: PointerDeviceKind.mouse,
      ),
      config.maxWheelDelta * config.wheelAcceleration,
    );
  });

  test('consecutive impulses preserve momentum and damp reversals', () {
    final continued = accumulatePremiumScrollVelocity(
      existingVelocity: 600,
      impulse: 400,
    );
    final reversed = accumulatePremiumScrollVelocity(
      existingVelocity: 600,
      impulse: -400,
    );

    expect(continued, greaterThan(400));
    expect(continued, closeTo(952, 0.001));
    expect(reversed, closeTo(-280, 0.001));
  });

  test('embedded kinetic model retains PDF wheel momentum and reversals', () {
    final model = PremiumKineticScrollModel();

    expect(
      model.addWheelDelta(const Offset(0, 20)),
      const Offset(0, 4.4),
    );
    expect(model.velocity.dy, 280);
    model.addWheelDelta(const Offset(0, 30));
    expect(model.velocity.dy, closeTo(497.6, 0.001));
    model.addWheelDelta(const Offset(0, -40));
    expect(model.velocity.dy, closeTo(-220.48, 0.001));
  });

  test('embedded kinetic frames use shared decay and cap delayed frames', () {
    final model = PremiumKineticScrollModel()
      ..beginRelease(const Offset(0, 1000));
    final frame = model.advance(1 / 60);

    expect(frame.displacement.dy, closeTo(15.9911, 0.001));
    expect(frame.velocity.dy, closeTo(920.044, 0.001));

    final delayedModel = PremiumKineticScrollModel()
      ..beginRelease(const Offset(0, 1000));
    final delayedFrame = delayedModel.advance(0.2);
    expect(
      delayedFrame.displacement,
      premiumKineticFrameDisplacement(
        velocity: const Offset(0, 1000),
        friction: delayedModel.config.friction,
        elapsedSeconds: premiumKineticMaximumFrameIntervalSeconds,
      ),
    );
  });

  test('embedded release limits and boundary cancellation match PDF', () {
    final model = PremiumKineticScrollModel()
      ..beginRelease(const Offset(1000, -6000));

    expect(model.velocity, const Offset(1000, -4800));
    model.stopAxes(vertical: true);
    expect(model.velocity, const Offset(1000, 0));
    model.beginRelease(const Offset(10, 0));
    expect(model.isActive, isFalse);
  });

  test('browser kinetic engine is generated from the shared configuration', () {
    const config = PremiumScrollPhysicsConfig(
      friction: 7,
      wheelAcceleration: 9,
      precisionAcceleration: 13,
      maxVelocity: 4200,
    );
    final script = buildPremiumKineticScrollEngineScript(config: config);

    expect(script, contains('friction: 7.0'));
    expect(script, contains('wheelAcceleration: 9.0'));
    expect(script, contains('precisionAcceleration: 13.0'));
    expect(script, contains('maxVelocity: 4200.0'));
    expect(
      script,
      contains(
        'state.velocityY / config.friction * (1 - decay)',
      ),
    );
    expect(script, contains('Math.exp(-config.friction * elapsed)'));
    expect(script, contains('requestAnimationFrame(tick)'));
    expect(
      script,
      contains('element.scrollHeight - element.clientHeight'),
    );
    expect(script, contains('verticalTarget.scrollBy(0, requestedY)'));
    expect(script, isNot(contains('setTimeout')));
    expect(
      buildPremiumKineticWheelCommand(
        const Offset(-12.5, 120),
        kind: PointerDeviceKind.mouse,
        position: const Offset(80, 40),
      ),
      'globalThis.__appFlowyPremiumKineticScroll.wheel('
      '-12.5,120.0,false,80.0,40.0);',
    );
    expect(
      buildPremiumKineticPanCommand(
        const Offset(4, -8),
        position: const Offset(25, 50),
      ),
      'globalThis.__appFlowyPremiumKineticScroll.pan('
      '4.0,-8.0,25.0,50.0);',
    );
    expect(
      buildPremiumKineticReleaseCommand(const Offset(600, -900)),
      'globalThis.__appFlowyPremiumKineticScroll.release(600.0,-900.0);',
    );
  });

  test('mouse-wheel normalization never amplifies operating-system distance',
      () {
    const config = PremiumScrollPhysicsConfig();

    expect(normalizePremiumWheelDistance(delta: 4), 4);
    expect(normalizePremiumWheelDistance(delta: 80), 80);
    expect(
      normalizePremiumWheelDistance(delta: 500),
      config.maxWheelDelta,
    );
    expect(
      normalizePremiumWheelDistance(delta: -500),
      -config.maxWheelDelta,
    );
  });

  test('wheel frames use exponential decay with a conservative speed cap', () {
    const config = PremiumScrollPhysicsConfig();
    final highRefreshStep = premiumWheelFrameDisplacement(
      remainingDistance: 120,
      elapsedSeconds: 1 / 120,
    );
    final uncappedStep = premiumWheelFrameDisplacement(
      remainingDistance: 40,
      elapsedSeconds: 1 / 120,
    );
    final delayedFrameStep = premiumWheelFrameDisplacement(
      remainingDistance: 120,
      elapsedSeconds: 0.2,
    );

    expect(
      highRefreshStep,
      closeTo(config.maxWheelScrollVelocity / 120, 0.001),
    );
    expect(
      uncappedStep,
      closeTo(40 * (1 - 0.875173), 0.001),
    );
    expect(
      delayedFrameStep,
      closeTo(config.maxWheelScrollVelocity / 30, 0.001),
    );
  });

  test('drag and trackpad flings delegate to platform ballistic physics', () {
    const parent = ClampingScrollPhysics();
    const physics = PremiumKineticScrollPhysics(
      config: PremiumScrollPhysicsConfig(),
      parent: parent,
    );
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 2000,
      pixels: 500,
      viewportDimension: 400,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final nativeSimulation = parent.createBallisticSimulation(metrics, 1200);
    final premiumSimulation = physics.createBallisticSimulation(metrics, 1200);

    expect(premiumSimulation, isNotNull);
    expect(premiumSimulation.runtimeType, nativeSimulation.runtimeType);
    expect(premiumSimulation!.x(0.1), closeTo(nativeSimulation!.x(0.1), 0.001));
    expect(premiumSimulation.dx(0.1), closeTo(nativeSimulation.dx(0.1), 0.001));
    expect(physics.carriedMomentum(1200), parent.carriedMomentum(1200));
    expect(physics.maxFlingVelocity, parent.maxFlingVelocity);
  });

  test('desktop direct manipulation is slower without losing precision', () {
    const config = PremiumScrollPhysicsConfig();
    final physics = PremiumKineticScrollPhysics(
      config: config,
      directManipulationScale: config.desktopDirectManipulationScale,
      parent: const ClampingScrollPhysics(),
    );
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 2000,
      pixels: 500,
      viewportDimension: 400,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(
      physics.applyPhysicsToUserOffset(metrics, 100),
      closeTo(55, 0.001),
    );
    expect(
      physics.applyPhysicsToUserOffset(metrics, 0.25),
      closeTo(0.1375, 0.001),
    );

    final reapplied = physics.applyTo(const RangeMaintainingScrollPhysics());
    expect(
      reapplied.directManipulationScale,
      config.desktopDirectManipulationScale,
    );
  });

  testWidgets('desktop release velocity matches direct manipulation scale', (
    tester,
  ) async {
    late GestureVelocityTrackerBuilder trackerBuilder;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            trackerBuilder = PremiumScrollBehavior(
              delegate: const _WindowsVelocityScrollBehavior(),
            ).velocityTrackerBuilder(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final tracker = trackerBuilder(
      const PointerPanZoomStartEvent(pointer: 31),
    );
    final estimate = tracker.getVelocityEstimate()!;

    expect(estimate.pixelsPerSecond, const Offset(550, -1100));
    expect(estimate.offset, const Offset(5.5, -11));
    expect(estimate.duration, const Duration(milliseconds: 20));
    expect(estimate.confidence, 0.9);
  });

  testWidgets('wheel offsets advance only on smooth 120Hz frames', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: ListView.builder(
          key: const ValueKey('high-refresh-list'),
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('high-refresh-list')),
        ),
        scrollDelta: const Offset(0, 80),
      ),
    );

    // Input packets only enqueue velocity; they never force pixels between
    // display frames.
    expect(controller.offset, 0);

    // Ignore the first step because the test display reports its own refresh
    // rate. Every subsequent sample uses an explicit 120 Hz frame interval.
    await tester.pump(const Duration(microseconds: 8333));
    var previousOffset = controller.offset;
    final frameDeltas = <double>[];
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(microseconds: 8333));
      final currentOffset = controller.offset;
      frameDeltas.add(currentOffset - previousOffset);
      previousOffset = currentOffset;
    }

    for (var frame = 0; frame < frameDeltas.length; frame++) {
      expect(frameDeltas[frame], greaterThan(0));
      expect(
        frameDeltas[frame],
        lessThanOrEqualTo(
          const PremiumScrollPhysicsConfig().maxWheelScrollVelocity / 120 +
              0.01,
        ),
      );
      if (frame > 0) {
        final ratio = frameDeltas[frame] / frameDeltas[frame - 1];
        expect(ratio, inInclusiveRange(0.87, 0.88));
      }
    }

    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(controller.offset, closeTo(80, 0.11));
  });

  testWidgets('precision pointer-scroll packets retain native distance', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: ListView.builder(
          key: const ValueKey('precision-pointer-list'),
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.trackpad,
        position: tester.getCenter(
          find.byKey(const ValueKey('precision-pointer-list')),
        ),
        scrollDelta: const Offset(0, 4),
      ),
    );
    await tester.pump();

    expect(controller.offset, 4);
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.offset, 4);
  });

  testWidgets('trackpad pan uses direct Flutter drag movement', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    try {
      await tester.pumpWidget(
        _scrollApp(
          enabled: true,
          child: ListView.builder(
            key: const ValueKey('native-trackpad-list'),
            controller: controller,
            itemCount: 100,
            itemExtent: 40,
            itemBuilder: (_, index) => Text('Item $index'),
          ),
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    final position = tester.getCenter(
      find.byKey(const ValueKey('native-trackpad-list')),
    );
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(
        pointer: 21,
        device: 21,
        position: position,
      ),
    );
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 21,
        device: 21,
        position: position,
        pan: const Offset(0, -40),
        panDelta: const Offset(0, -40),
        timeStamp: const Duration(milliseconds: 10),
      ),
    );
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 21,
        device: 21,
        position: position,
        pan: const Offset(0, -80),
        panDelta: const Offset(0, -40),
        timeStamp: const Duration(milliseconds: 20),
      ),
    );
    final directOffset = controller.offset;
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(
        pointer: 21,
        device: 21,
        position: position,
        timeStamp: const Duration(milliseconds: 21),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(directOffset, closeTo(80 * 0.55, 0.001));
    expect(controller.offset, greaterThanOrEqualTo(directOffset));
    expect(
      controller.position.physics.parent,
      isA<ClampingScrollPhysics>(),
    );
  });

  testWidgets('wheel animation updates the viewport without widget rebuilds', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var builds = 0;

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: Builder(
          builder: (context) {
            builds++;
            return ListView.builder(
              key: const ValueKey('no-rebuild-list'),
              controller: controller,
              itemCount: 100,
              itemExtent: 40,
              itemBuilder: (_, index) => Text('Item $index'),
            );
          },
        ),
      ),
    );
    final initialBuilds = builds;

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('no-rebuild-list')),
        ),
        scrollDelta: const Offset(0, 80),
      ),
    );
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(microseconds: 8333));
    }

    expect(controller.offset, greaterThan(0));
    expect(builds, initialBuilds);
  });

  testWidgets('wheel reversal discards queued momentum immediately', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: ListView.builder(
          key: const ValueKey('wheel-reversal-list'),
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );
    final pointerPosition = tester.getCenter(
      find.byKey(const ValueKey('wheel-reversal-list')),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: pointerPosition,
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump(const Duration(microseconds: 8333));
    final offsetBeforeReversal = controller.offset;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: pointerPosition,
        scrollDelta: const Offset(0, -40),
      ),
    );
    await tester.pump(const Duration(microseconds: 8333));

    expect(controller.offset, lessThan(offsetBeforeReversal));
  });

  testWidgets('rapid wheel bursts leave only a short bounded queue', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: ListView.builder(
          key: const ValueKey('bounded-wheel-list'),
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );
    final pointerPosition = tester.getCenter(
      find.byKey(const ValueKey('bounded-wheel-list')),
    );
    for (var notch = 0; notch < 6; notch++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointerPosition,
          scrollDelta: const Offset(0, 120),
        ),
      );
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 8));

    expect(
      controller.offset,
      closeTo(
        const PremiumScrollPhysicsConfig().maxWheelQueuedDistance,
        0.11,
      ),
    );
  });

  testWidgets('consecutive wheel packets share one scroll activity', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var starts = 0;
    var ends = 0;

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              starts++;
            } else if (notification is ScrollEndNotification) {
              ends++;
            }
            return false;
          },
          child: ListView.builder(
            key: const ValueKey('continuous-wheel-list'),
            controller: controller,
            itemCount: 100,
            itemExtent: 40,
            itemBuilder: (_, index) => Text('Item $index'),
          ),
        ),
      ),
    );

    final pointerPosition = tester.getCenter(
      find.byKey(const ValueKey('continuous-wheel-list')),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: pointerPosition,
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.pump(const Duration(microseconds: 8333));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: pointerPosition,
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.pump(const Duration(microseconds: 8333));

    expect(starts, 1);
    expect(ends, 0);

    await tester.pumpAndSettle(const Duration(milliseconds: 8));

    expect(starts, 1);
    expect(ends, 1);
  });

  testWidgets('wheel distance smooths across frames without amplification', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: ListView.builder(
          key: const ValueKey('kinetic-list'),
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('kinetic-list')),
        ),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final firstFrameOffset = controller.offset;
    await tester.pump(const Duration(milliseconds: 120));
    final coastingOffset = controller.offset;
    await tester.pumpAndSettle(const Duration(milliseconds: 8));

    expect(firstFrameOffset, greaterThan(0));
    expect(coastingOffset, greaterThan(firstFrameOffset));
    expect(controller.offset, greaterThan(coastingOffset));
    expect(controller.offset, lessThan(controller.position.maxScrollExtent));
  });

  testWidgets('queued wheel distance survives dynamically appended content', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var itemCount = 30;
    late StateSetter update;

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ListView.builder(
              key: const ValueKey('dynamic-kinetic-list'),
              controller: controller,
              itemCount: itemCount,
              itemExtent: 40,
              itemBuilder: (_, index) => Text('Item $index'),
            );
          },
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('dynamic-kinetic-list')),
        ),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 32));
    final beforeAppend = controller.offset;

    update(() => itemCount = 80);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 120));

    expect(controller.offset, greaterThan(beforeAppend));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deepest nested scrollable owns kinetic wheel input', (
    tester,
  ) async {
    final outerController = ScrollController();
    final innerController = ScrollController();
    addTearDown(outerController.dispose);
    addTearDown(innerController.dispose);

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: SingleChildScrollView(
          key: const ValueKey('outer-scroll'),
          controller: outerController,
          child: Column(
            children: [
              SizedBox(
                height: 220,
                child: ListView.builder(
                  key: const ValueKey('inner-scroll'),
                  controller: innerController,
                  itemCount: 40,
                  itemExtent: 36,
                  itemBuilder: (_, index) => Text('Nested $index'),
                ),
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    );

    final position = tester.getCenter(
      find.byKey(const ValueKey('inner-scroll')),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    expect(innerController.offset, greaterThan(0));
    expect(outerController.offset, 0);

    innerController.jumpTo(innerController.position.maxScrollExtent);
    await tester.pump();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    expect(outerController.offset, greaterThan(0));
  });

  testWidgets('reduced motion falls back to immediate native wheel input', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        reducedMotion: true,
        child: ListView.builder(
          key: const ValueKey('reduced-motion-list'),
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('reduced-motion-list')),
        ),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump();
    final immediateOffset = controller.offset;
    await tester.pump(const Duration(milliseconds: 250));

    expect(immediateOffset, 80);
    expect(controller.offset, immediateOffset);
    expect(controller.position.physics, isA<ClampingScrollPhysics>());
    expect(
      controller.position.physics,
      isNot(isA<PremiumKineticScrollPhysics>()),
    );
  });

  testWidgets('disabled kinetic scrolling uses native behavior', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scrollApp(
        enabled: false,
        child: ListView.builder(
          key: const ValueKey('disabled-kinetic-list'),
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('disabled-kinetic-list')),
        ),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump();

    expect(controller.offset, 80);
    expect(controller.position.physics, isA<ClampingScrollPhysics>());
    expect(
      controller.position.physics,
      isNot(isA<PremiumKineticScrollPhysics>()),
    );
  });

  testWidgets('custom embedded scrolling can exclude the global engine', (
    tester,
  ) async {
    final outerController = ScrollController();
    addTearDown(outerController.dispose);
    var embeddedSignals = 0;

    await tester.pumpWidget(
      _scrollApp(
        enabled: true,
        child: SingleChildScrollView(
          controller: outerController,
          child: Column(
            children: [
              PremiumScrollExclusion(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (_) => embeddedSignals++,
                      );
                    }
                  },
                  child: const SizedBox(
                    key: ValueKey('custom-scroll-embed'),
                    width: 400,
                    height: 220,
                  ),
                ),
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('custom-scroll-embed')),
        ),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(embeddedSignals, 1);
    expect(outerController.offset, 0);
  });
}

Widget _scrollApp({
  required bool enabled,
  required Widget child,
  bool reducedMotion = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: PremiumScrollScope(
        enabled: enabled,
        child: SizedBox(width: 400, height: 300, child: child),
      ),
    ),
  );
}

class _WindowsVelocityScrollBehavior extends ScrollBehavior {
  const _WindowsVelocityScrollBehavior();

  @override
  TargetPlatform getPlatform(BuildContext context) => TargetPlatform.windows;

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    return (_) => _FixedVelocityTracker();
  }
}

class _FixedVelocityTracker extends VelocityTracker {
  _FixedVelocityTracker() : super.withKind(PointerDeviceKind.trackpad);

  @override
  VelocityEstimate getVelocityEstimate() {
    return const VelocityEstimate(
      pixelsPerSecond: Offset(1000, -2000),
      confidence: 0.9,
      duration: Duration(milliseconds: 20),
      offset: Offset(10, -20),
    );
  }
}
