import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final enabled in [false, true]) {
    for (final reducedMotion in [false, true]) {
      testWidgets(
        'overlay inherits scrolling: enabled=$enabled reduced=$reducedMotion',
        (tester) async {
          final controller = ScrollController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _app(
              enabled: enabled,
              reducedMotion: reducedMotion,
              child: PremiumScrollScope(
                // Nested surfaces must not override the application setting.
                enabled: true,
                child: _list(controller),
              ),
            ),
          );

          final kinetic = enabled && !reducedMotion;
          expect(
            controller.position.physics.applyPhysicsToUserOffset(
              controller.position,
              100,
            ),
            closeTo(kinetic ? 60 : 100, 0.001),
          );
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(find.byType(ListView)),
              scrollDelta: const Offset(0, 80),
            ),
          );
          expect(controller.offset, kinetic ? 0 : 80);
          await tester.pumpAndSettle(const Duration(milliseconds: 8));
          expect(controller.offset, closeTo(80, 0.11));
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  testWidgets(
    'overlay entries retain the same scrolling configuration',
    (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final key = GlobalKey<FlowyOverlayState>();
      await tester.pumpWidget(
        _app(
          enabled: true,
          overlayKey: key,
          child: const SizedBox.expand(),
        ),
      );
      key.currentState!.insertCustom(
        identifier: 'scroll-test',
        widget: Align(
          child: SizedBox(width: 300, height: 240, child: _list(controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        controller.position.physics.applyPhysicsToUserOffset(
          controller.position,
          100,
        ),
        closeTo(60, 0.001),
      );
      key.currentState!.remove('scroll-test');
      await tester.pumpAndSettle();
      expect(controller.hasClients, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Widget _app({
  required bool enabled,
  required Widget child,
  bool reducedMotion = false,
  GlobalKey<FlowyOverlayState>? overlayKey,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: PremiumScrollScope(
          enabled: enabled,
          child: FlowyOverlay(key: overlayKey, child: child),
        ),
      ),
    );

Widget _list(ScrollController controller) => ListView.builder(
      controller: controller,
      itemCount: 100,
      itemExtent: 40,
      itemBuilder: (_, index) => Text('Generated row $index'),
    );
