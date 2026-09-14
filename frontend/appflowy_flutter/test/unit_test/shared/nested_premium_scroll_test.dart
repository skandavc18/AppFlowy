import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final wrapBehavior in [false, true]) {
    testWidgets(
      'nested scopes scale distance and velocity only once '
      '(wrapped behavior: $wrapBehavior)',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        late BuildContext scrollContext;
        await tester.pumpWidget(
          _app(
            wrapBehavior: wrapBehavior,
            child: Builder(
              builder: (context) {
                scrollContext = context;
                return _list(controller);
              },
            ),
          ),
        );

        expect(
          controller.position.physics.applyPhysicsToUserOffset(
            controller.position,
            100,
          ),
          closeTo(60, 0.001),
        );
        final tracker = ScrollConfiguration.of(scrollContext)
            .velocityTrackerBuilder(scrollContext)(
          const PointerPanZoomStartEvent(pointer: 1),
        );
        for (var sample = 0; sample <= 4; sample++) {
          tracker.addPosition(
            Duration(milliseconds: sample * 10),
            Offset(10.0 * sample, -20.0 * sample),
          );
        }
        expect(
          tracker.getVelocityEstimate()!.pixelsPerSecond,
          const Offset(600, -1200),
        );
      },
    );

    testWidgets(
      'inner scopes respect the global opt-out '
      '(wrapped behavior: $wrapBehavior)',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            enabled: false,
            wrapBehavior: wrapBehavior,
            child: _list(controller),
          ),
        );

        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(ListView)),
            scrollDelta: const Offset(0, 80),
          ),
        );
        expect(controller.offset, 80);
        expect(
          controller.position.physics,
          isNot(isA<PremiumKineticScrollPhysics>()),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(controller.offset, 80);
      },
    );
  }

  testWidgets('a live global toggle reaches an already nested view', (
    tester,
  ) async {
    final controller = ScrollController();
    final enabled = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (_, value, __) => _app(
          enabled: value,
          wrapBehavior: true,
          child: _list(controller),
        ),
      ),
    );

    for (final value in [false, true, false]) {
      enabled.value = value;
      await tester.pump();
      expect(
        controller.position.physics.applyPhysicsToUserOffset(
          controller.position,
          100,
        ),
        closeTo(value ? 60 : 100, 0.001),
      );
    }
  });

  testWidgets('nested scopes preserve reduced-motion fallback', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const _WindowsScrollBehavior(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: PremiumScrollScope(
            enabled: true,
            child: PremiumScrollScope(enabled: true, child: _list(controller)),
          ),
        ),
      ),
    );
    expect(controller.position.physics, isA<ClampingScrollPhysics>());
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView)),
        scrollDelta: const Offset(0, 80),
      ),
    );
    expect(controller.offset, 80);
  });

  testWidgets('nested scopes preserve exact mouse wheel distance', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(child: _list(controller)));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView)),
        scrollDelta: const Offset(0, 80),
      ),
    );
    expect(controller.offset, 0);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(controller.offset, closeTo(80, 0.11));
  });
}

Widget _list(ScrollController controller) => ListView.builder(
      controller: controller,
      itemCount: 100,
      itemExtent: 40,
      itemBuilder: (_, index) => Text('Item $index'),
    );

Widget _app({
  required Widget child,
  bool enabled = true,
  bool wrapBehavior = false,
}) =>
    MaterialApp(
      scrollBehavior: const _WindowsScrollBehavior(),
      home: PremiumScrollScope(
        enabled: enabled,
        child: Builder(
          builder: (context) {
            final nested = PremiumScrollScope(enabled: true, child: child);
            return wrapBehavior
                ? ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                    ),
                    child: nested,
                  )
                : nested;
          },
        ),
      ),
    );

class _WindowsScrollBehavior extends MaterialScrollBehavior {
  const _WindowsScrollBehavior();

  @override
  TargetPlatform getPlatform(BuildContext context) => TargetPlatform.windows;

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      (_) => _FixedVelocityTracker();
}

class _FixedVelocityTracker extends VelocityTracker {
  _FixedVelocityTracker() : super.withKind(PointerDeviceKind.trackpad);

  @override
  VelocityEstimate getVelocityEstimate() => const VelocityEstimate(
        pixelsPerSecond: Offset(1000, -2000),
        confidence: 1,
        duration: Duration(milliseconds: 20),
        offset: Offset(10, -20),
      );
}
