import 'package:appflowy/shared/scrolling/frame_synced_scroll_pan.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _listKey = ValueKey('paced-scroll');
const _packetInterval = Duration(microseconds: 16666);
const _frameInterval = Duration(microseconds: 8333);
const _desktop =
    TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.linux});

void main() {
  testWidgets(
    '60Hz trackpad distance advances on intervening 120Hz frames',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      var previous = controller.offset;
      for (var step = 1; step <= 12; step++) {
        await _update(tester, point, step, -24);
        await tester.pump(_frameInterval);
        final halfway = controller.offset;
        await tester.pump(_frameInterval);
        final complete = controller.offset;
        if (step > 1) {
          expect(halfway, greaterThan(previous));
          expect(complete, greaterThan(halfway));
        }
        expect(complete, lessThanOrEqualTo(1000 + step * 24 * _gain + 0.001));
        previous = complete;
      }
      await _stopWithoutFling(tester, point, -24 * 12);
      expect(controller.offset, closeTo(1000 + 12 * 24 * _gain, 0.01));
      expect(controller.position.isScrollingNotifier.value, isFalse);
    },
    variant: _desktop,
  );

  testWidgets(
    'pending distance finishes before release without an artificial tail',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      for (var step = 1; step <= 3; step++) {
        await _update(tester, point, step, -24);
        await tester.pump(_frameInterval);
        if (step < 3) await tester.pump(_frameInterval);
      }
      final beforeRelease = controller.offset;
      expect(beforeRelease, lessThan(1000 + 72 * _gain));
      // The root end timestamp marks a pause, even with no stationary update.
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(
          pointer: 71,
          device: 71,
          position: point,
          timeStamp: const Duration(milliseconds: 200),
        ),
      );
      expect(controller.offset, closeTo(1000 + 72 * _gain, 0.01));
      final released = controller.offset;
      await tester.pumpAndSettle(_frameInterval);
      expect(controller.offset, released);
    },
    variant: _desktop,
  );

  for (final mode in ['60Hz', 'disabled', 'reduced', 'opt-out', 'explicit']) {
    testWidgets(
      'pacing leaves $mode input synchronous',
      (tester) async {
        tester.view.display.refreshRate = mode == '60Hz' ? 60 : 120;
        addTearDown(tester.view.display.resetRefreshRate);
        final controller = await _mount(
          tester,
          enabled: mode != 'disabled',
          reducedMotion: mode == 'reduced',
          config:
              PremiumScrollPhysicsConfig(desktopFramePacing: mode != 'opt-out'),
          physics: mode == 'explicit' ? const ClampingScrollPhysics() : null,
        );
        final point = tester.getCenter(find.byKey(_listKey));
        await _start(tester, point);
        await _update(tester, point, 1, -24);
        final gain = mode == 'disabled' || mode == 'reduced' ? 1.0 : _gain;
        expect(controller.offset, closeTo(1000 + 24 * gain, 0.01));
        final received = controller.offset;
        await tester.pump(_frameInterval);
        expect(controller.offset, received);
        await _stopWithoutFling(tester, point, -24);
      },
      variant: _desktop,
    );
  }

  testWidgets(
    '120Hz trackpad packets bypass the coarse-input buffer',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      for (var step = 1; step <= 6; step++) {
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            pointer: 71,
            device: 71,
            position: point,
            pan: Offset(0, -24.0 * step),
            panDelta: const Offset(0, -24),
            timeStamp: _frameInterval * step,
          ),
        );
        expect(controller.offset, closeTo(1000 + step * 24 * _gain, 0.01));
        await tester.pump(_frameInterval);
      }
      await _stopWithoutFling(tester, point, -144);
    },
    variant: _desktop,
  );

  testWidgets(
    'opposite packets preserve total distance without a leftover coast',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      await _update(tester, point, 1, -24);
      await tester.pump(_frameInterval);
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 71,
          device: 71,
          position: point,
          panDelta: const Offset(0, 24),
          timeStamp: _packetInterval * 2,
        ),
      );
      expect(controller.offset, closeTo(1000, 0.01));
      await _stopWithoutFling(tester, point, 0);
      expect(controller.offset, closeTo(1000, 0.01));
    },
    variant: _desktop,
  );

  for (final takeover in ['jump', 'inertia-cancel', 'unmount']) {
    testWidgets(
      'pending interpolation stops on $takeover',
      (tester) async {
        tester.view.display.refreshRate = 120;
        addTearDown(tester.view.display.resetRefreshRate);
        final controller = await _mount(tester);
        final point = tester.getCenter(find.byKey(_listKey));
        await _start(tester, point);
        await _update(tester, point, 1, -24);
        await tester.pump(_frameInterval);
        if (takeover == 'jump') {
          controller.jumpTo(600);
        } else if (takeover == 'inertia-cancel') {
          await tester.sendEventToBinding(
            PointerScrollInertiaCancelEvent(position: point),
          );
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        final stopped = controller.hasClients ? controller.offset : 0.0;
        await tester.pump(const Duration(milliseconds: 100));
        if (controller.hasClients) expect(controller.offset, stopped);
        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(
            pointer: 71,
            device: 71,
            position: point,
            timeStamp: const Duration(milliseconds: 200),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      variant: _desktop,
    );
  }

  testWidgets(
    'a delayed frame drains only received input with no ongoing ticker',
    (tester) async {
      tester.view.display.refreshRate = 144;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      await _update(tester, point, 1, -24);
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.offset, closeTo(1000 + 24 * _gain, 0.01));
      final settled = controller.offset;
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.offset, settled);
      await _stopWithoutFling(tester, point, -24);
      expect(tester.binding.transientCallbackCount, 0);
    },
    variant: _desktop,
  );

  testWidgets(
    'coarse release keeps the original bounded velocity estimate',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      for (var step = 1; step <= 6; step++) {
        await _update(tester, point, step, -24);
        await tester.pump(_packetInterval);
      }
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(
          pointer: 71,
          device: 71,
          position: point,
          timeStamp: _packetInterval * 6 + const Duration(milliseconds: 1),
        ),
      );
      final released = controller.offset;
      expect(released, closeTo(1000 + 144 * _gain, 0.01));
      final motion = controller.position.physics.createBallisticSimulation(
        controller.position,
        24 * _gain / (_packetInterval.inMicroseconds / 1e6),
      )!;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.offset, closeTo(motion.x(0.1), 0.01));
      await tester.pumpAndSettle(_frameInterval);
    },
    variant: _desktop,
  );

  testWidgets(
    'new packets never postpone an older packet deadline',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      await _update(tester, point, 1, -100);
      await tester.pump(const Duration(milliseconds: 8));
      await tester.pump(const Duration(milliseconds: 7));
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 71,
          device: 71,
          position: point,
          pan: const Offset(0, -101),
          panDelta: const Offset(0, -1),
          timeStamp: _packetInterval * 2,
        ),
      );
      await tester.pump(const Duration(microseconds: 1667));
      expect(controller.offset, greaterThanOrEqualTo(1000 + 100 * _gain));
      expect(controller.offset, lessThanOrEqualTo(1000 + 101 * _gain));
      await _stopWithoutFling(tester, point, -101);
      expect(controller.offset, closeTo(1000 + 101 * _gain, 0.01));
    },
    variant: _desktop,
  );

  testWidgets(
    'cancelled trackpad candidate never buffers a later touch drag',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 71,
          device: 71,
          position: point,
          pan: const Offset(24, 0),
          panDelta: const Offset(24, 0),
          timeStamp: _packetInterval,
        ),
      );
      await tester.sendEventToBinding(
        PointerCancelEvent(pointer: 71, device: 71, position: point),
      );
      final touch = await tester.startGesture(point);
      await touch.moveBy(const Offset(0, -40));
      final before = controller.offset;
      await touch.moveBy(const Offset(0, -24));
      expect(controller.offset - before, closeTo(24 * _gain, 0.01));
      await touch.cancel();
      await tester.pumpAndSettle();
    },
    variant: _desktop,
  );

  testWidgets(
    'shared controllers do not let one view discard another views input',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = ScrollController(initialScrollOffset: 1000);
      addTearDown(controller.dispose);
      final positions = <int, ScrollPosition>{};
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior:
              const MaterialScrollBehavior().copyWith(scrollbars: false),
          home: PremiumScrollScope(
            enabled: true,
            child: Row(
              children: [
                for (var view = 0; view < 2; view++)
                  Expanded(
                    child: ListView.builder(
                      key: ValueKey(view),
                      controller: controller,
                      itemCount: 100,
                      itemExtent: 40,
                      itemBuilder: (context, index) {
                        positions[view] = Scrollable.of(context).position;
                        return Text('View $view row $index');
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final a = tester.getCenter(find.byKey(const ValueKey(0)));
      final b = tester.getCenter(find.byKey(const ValueKey(1)));
      await _start(tester, a);
      await _update(tester, a, 1, -24);
      await tester.pump(_frameInterval);
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 72, device: 72, position: b),
      );
      await _stopWithoutFling(tester, a, -24);
      expect(positions[0]!.pixels, closeTo(1000 + 24 * _gain, 0.01));
      expect(positions[1]!.pixels, 1000);
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 72, device: 72, position: b),
      );
      await tester.pumpAndSettle();
    },
    variant: _desktop,
  );

  testWidgets(
    'a release listener can dispose the buffer reentrantly exactly once',
    (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);
      final controller = await _mount(tester);
      final point = tester.getCenter(find.byKey(_listKey));
      await _start(tester, point);
      await _update(tester, point, 1, -24);
      await tester.pump(_packetInterval);
      var disposals = 0;
      final buffer = FrameSyncedScrollPan(
        controller: controller,
        position: controller.position as ScrollPositionWithSingleContext,
        refreshRate: 120,
        directScale: _gain,
        onDispose: () => disposals++,
      )..inputIntervalUs = _packetInterval.inMicroseconds;
      final before = controller.offset;
      (controller.position as ScrollPositionWithSingleContext)
          .applyUserOffset(-24);
      await tester.pump(_frameInterval);
      void interrupt() => buffer.dispose();
      controller.addListener(interrupt);
      try {
        expect(() => buffer.dispose(flush: true), returnsNormally);
        expect(disposals, 1);
        expect(controller.offset, closeTo(before + 24 * _gain, 0.01));
        expect(tester.takeException(), isNull);
      } finally {
        controller.removeListener(interrupt);
        buffer.dispose();
        await _stopWithoutFling(tester, point, -24);
      }
    },
    variant: _desktop,
  );
}

double get _gain =>
    const PremiumScrollPhysicsConfig().desktopDirectManipulationScale;

Future<ScrollController> _mount(
  WidgetTester tester, {
  bool enabled = true,
  bool reducedMotion = false,
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
  ScrollPhysics? physics,
}) async {
  final controller = ScrollController(initialScrollOffset: 1000);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: PremiumScrollScope(
          enabled: enabled,
          config: config,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: ListView.builder(
                key: _listKey,
                controller: controller,
                physics: physics,
                itemCount: 200,
                itemExtent: 40,
                itemBuilder: (_, index) => Text('Generated row $index'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

Future<void> _start(WidgetTester tester, Offset point) =>
    tester.sendEventToBinding(
      PointerPanZoomStartEvent(pointer: 71, device: 71, position: point),
    );

Future<void> _update(
  WidgetTester tester,
  Offset point,
  int step,
  double delta,
) =>
    tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 71,
        device: 71,
        position: point,
        pan: Offset(0, delta * step),
        panDelta: Offset(0, delta),
        timeStamp: _packetInterval * step,
      ),
    );

Future<void> _stopWithoutFling(
  WidgetTester tester,
  Offset point,
  double pan,
) async {
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      pointer: 71,
      device: 71,
      position: point,
      pan: Offset(0, pan),
      timeStamp: const Duration(milliseconds: 400),
    ),
  );
  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      pointer: 71,
      device: 71,
      position: point,
      timeStamp: const Duration(milliseconds: 401),
    ),
  );
  await tester.pumpAndSettle(_frameInterval);
}
