import 'dart:async';

import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

ScrollMetrics _metrics({
  double pixels = 0,
  required double maxScrollExtent,
  double viewportDimension = 600,
}) =>
    FixedScrollMetrics(
      pixels: pixels,
      minScrollExtent: 0,
      maxScrollExtent: maxScrollExtent,
      viewportDimension: viewportDimension,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 2,
    );

void main() {
  group('DocumentScrollPhysics', () {
    final physics = DocumentScrollPhysics(
      parent: DocumentScrollPhysics.platformBase(TargetPlatform.windows),
    );

    test('clamps on Windows and Linux, bounces only where native', () {
      expect(
        DocumentScrollPhysics.platformBase(TargetPlatform.windows),
        isA<ClampingScrollPhysics>(),
      );
      expect(
        DocumentScrollPhysics.platformBase(TargetPlatform.linux),
        isA<ClampingScrollPhysics>(),
      );
      expect(
        DocumentScrollPhysics.platformBase(TargetPlatform.macOS),
        isA<BouncingScrollPhysics>(),
      );
      expect(DocumentScrollPhysics.platformBounces(TargetPlatform.macOS), true);
      expect(
        DocumentScrollPhysics.platformBounces(TargetPlatform.windows),
        false,
      );
    });

    test('settles without overshoot: the spring is critically damped', () {
      final spring = physics.spring;
      final critical = 2 * (spring.mass * spring.stiffness).abs();
      // damping^2 == 4 * mass * stiffness at critical damping.
      expect(
        spring.damping * spring.damping,
        closeTo(2 * critical, 0.01),
      );
      expect(
        SpringSimulation(spring, 0, 100, 0).x(10),
        closeTo(100, 0.5),
      );
    });

    test('stays responsive without artificial acceleration', () {
      expect(physics.minFlingVelocity, lessThan(50));
      expect(physics.dragStartDistanceMotionThreshold, lessThanOrEqualTo(3.5));
      expect(physics.maxFlingVelocity, documentScrollPhysicsConfig.maxVelocity);
      // Focus traversal must never move the reading position on its own.
      expect(physics.allowImplicitScrolling, isFalse);
    });

    test('a fling decelerates smoothly and never leaves the document', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final simulation = physics.createBallisticSimulation(
        _metrics(pixels: 100, maxScrollExtent: 4000),
        2400,
      )!;

      // Momentum carries well past the release point.
      expect(simulation.x(0.1), greaterThan(150));
      // Velocity decays continuously; it is never cut off abruptly.
      final early = simulation.dx(0.05);
      final mid = simulation.dx(0.4);
      final late = simulation.dx(1.2);
      expect(early, greaterThan(mid));
      expect(mid, greaterThan(late));
      expect(late, greaterThanOrEqualTo(0));
      // And it comes to rest.
      expect(simulation.dx(6).abs(), lessThan(20));
    });

    test('lands exactly on the edge instead of colliding with it', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final metrics = _metrics(pixels: 3950, maxScrollExtent: 4000);
      final simulation = physics.createBallisticSimulation(metrics, 4000)!;
      expect(simulation.x(4), lessThanOrEqualTo(4000.5));
    });

    test('out of range settles back with the shared spring', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final simulation = physics.createBallisticSimulation(
        _metrics(pixels: 4080, maxScrollExtent: 4000),
        0,
      );
      expect(simulation, isA<ScrollSpringSimulation>());
      expect(simulation!.x(2), closeTo(4000, 1));
    });

    test('a resting position produces no simulation', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        physics.createBallisticSimulation(
          _metrics(maxScrollExtent: 4000),
          0,
        ),
        isNull,
      );
      expect(
        physics.createBallisticSimulation(
          _metrics(pixels: 4000, maxScrollExtent: 4000),
          800,
        ),
        isNull,
      );
    });

    test('applyTo preserves the tuning through the parent chain', () {
      const custom = DocumentScrollPhysics(flingFriction: 3.4);
      final applied = custom.applyTo(const ClampingScrollPhysics());
      expect(applied.flingFriction, 3.4);
      expect(applied.parent, isA<ClampingScrollPhysics>());
    });
  });

  group('DocumentScrollController', () {
    testWidgets('page and line steps move by predictable distances',
        (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentViewport.list(
            controller: controller,
            itemCount: 200,
            itemBuilder: (context, index) => SizedBox(
              height: 40,
              child: Text('row $index'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.isReady, isTrue);
      expect(controller.progress, 0);

      final viewport = controller.position.viewportDimension;
      unawaited(controller.pageDown());
      await tester.pumpAndSettle();
      expect(
        controller.offset,
        closeTo(viewport * (1 - DocumentScrollController.pageOverlap), 1),
      );

      final afterPage = controller.offset;
      unawaited(controller.lineDown());
      await tester.pumpAndSettle();
      expect(
        controller.offset,
        closeTo(afterPage + DocumentScrollController.lineStep, 1),
      );

      unawaited(controller.jumpToEnd());
      await tester.pumpAndSettle();
      expect(controller.progress, closeTo(1, 0.001));

      unawaited(controller.jumpToStart());
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
    });

    test('reports no progress before it is attached', () {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);
      expect(controller.isReady, isFalse);
      expect(controller.progress, 0);
    });
  });

  group('DocumentScrollScope', () {
    testWidgets('installs the premium kinetic behaviour', (tester) async {
      late ScrollBehavior behavior;
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScrollScope(
            child: Builder(
              builder: (context) {
                behavior = ScrollConfiguration.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(behavior, isA<PremiumScrollBehavior>());
    });

    testWidgets('never nests a second premium behaviour', (tester) async {
      late ScrollBehavior outer;
      late ScrollBehavior inner;
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumScrollScope(
            enabled: true,
            child: Builder(
              builder: (context) {
                outer = ScrollConfiguration.of(context);
                return DocumentScrollScope(
                  child: Builder(
                    builder: (context) {
                      inner = ScrollConfiguration.of(context);
                      return const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Doubling the behaviour would square the desktop manipulation scale.
      expect(outer, isA<PremiumScrollBehavior>());
      expect(inner, same(outer));
    });
  });

  group('DocumentViewport', () {
    testWidgets('every renderer scrolls through one implementation',
        (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentViewport.child(
            controller: controller,
            child: const SizedBox(height: 3000),
          ),
        ),
      );

      final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
      expect(scrollable.physics, isA<DocumentScrollPhysics>());
      expect(scrollable.controller, same(controller));
      // The document owns its overlay scrollbar; no Material one is added.
      expect(find.byType(DocumentScrollbar), findsOneWidget);
    });

    testWidgets('centres the reading measure and keeps generous margins',
        (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentViewport.child(
            controller: controller,
            child: const SizedBox(key: ValueKey('body'), height: 400),
          ),
        ),
      );

      final body = tester.getRect(find.byKey(const ValueKey('body')));
      final expected = DocumentViewerTheme.readingWidth -
          DocumentViewerTheme.readingPadding.horizontal;
      expect(body.width, closeTo(expected, 1));
      expect(body.center.dx, closeTo(800, 1));
    });
  });
}
