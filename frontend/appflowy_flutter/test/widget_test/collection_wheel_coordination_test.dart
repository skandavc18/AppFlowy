import 'dart:math' as math;

import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _header = ValueKey('wheel-fixture-header');
const _main = ValueKey('wheel-fixture-main');
const _secondary = ValueKey('wheel-fixture-secondary');
const _custom = ValueKey('wheel-fixture-custom');
const _headerExtent = 160.0;

void main() {
  for (final mode in ['premium', 'disabled', 'reduced motion']) {
    testWidgets(
        '$mode: body wheels distribute exact distance in both directions',
        (tester) async {
      final key = GlobalKey<NestedScrollViewState>();
      await tester.pumpWidget(
        _app(
          _nestedView(key),
          enabled: mode != 'disabled',
          reducedMotion: mode == 'reduced motion',
        ),
      );
      await tester.pump();
      final nested = key.currentState!;
      final header = find.byKey(_header, skipOffstage: false);
      final headerElement = tester.element(header);
      final headerTop = tester.getTopLeft(header).dy;
      final body = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(_main),
          matching: find.byType(Scrollable),
        ),
      );
      expect(nested.outerController.position.maxScrollExtent, _headerExtent);
      expect(nested.innerController.positions, hasLength(1));
      expect(body.position, same(nested.innerController.position));
      final physics = nested.innerController.position.physics;
      if (mode == 'premium') {
        expect(physics, isA<PremiumKineticScrollPhysics>());
        expect(
          physics.applyPhysicsToUserOffset(
            nested.innerController.position,
            100,
          ),
          closeTo(60, 0.001),
          reason:
              'Coordinated wheel smoothing must not replace trackpad physics.',
        );
      } else {
        expect(physics, isNot(isA<PremiumKineticScrollPhysics>()));
      }

      for (final delta in [80.0, 120.0, 90.0, -60.0, -80.0, -110.0, -80.0]) {
        final before = _distance(nested);
        final expected = math.max(0.0, before + delta);
        await _wheel(tester, key, Offset(0, delta));
        if (mode == 'premium') {
          expect(_distance(nested), before);
          await tester.pump(const Duration(milliseconds: 8));
          if (expected != before) {
            expect(
              _distance(nested),
              inExclusiveRange(
                math.min(before, expected),
                math.max(before, expected),
              ),
            );
          }
        } else {
          // Disabled/reduced-motion input still reaches native pointerScroll
          // immediately, with neither premium limits nor a queued tail.
          _expectOffsets(nested, expected);
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 8));
        _expectOffsets(nested, expected);
        expect(tester.element(header), same(headerElement));
        expect(tester.renderObject(header).attached, isTrue);
        expect(
          tester.getTopLeft(header).dy,
          closeTo(headerTop - nested.outerController.offset, 0.001),
        );
        await tester.pump(const Duration(milliseconds: 32));
        _expectOffsets(nested, expected);
        expect(nested.innerController.position, same(body.position));
        expect(nested.innerController.positions, hasLength(1));
        expect(
          nested.outerController.position.isScrollingNotifier.value,
          isFalse,
        );
        expect(
          nested.innerController.position.isScrollingNotifier.value,
          isFalse,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final bodyExtent in [80.0, 2000.0]) {
    testWidgets('wheel boundaries clamp once (body extent: $bodyExtent)',
        (tester) async {
      final key = GlobalKey<NestedScrollViewState>();
      await tester.pumpWidget(_app(_nestedView(key, bodyExtent: bodyExtent)));
      await tester.pump();
      final nested = key.currentState!;
      // Collapsing the header grows the body viewport by the same amount.
      // Initial inner extents therefore overestimate the final trailing edge.
      final maximum = math.max(_headerExtent, bodyExtent - 400 + _headerExtent);
      expect(maximum, greaterThanOrEqualTo(_headerExtent));
      if (bodyExtent == 80) {
        expect(nested.innerController.position.maxScrollExtent, 0);
      }
      nested.innerController
          .jumpTo(nested.innerController.position.maxScrollExtent);
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      for (final delta in [80.0, -10000.0, 10000.0, -80.0]) {
        final expected =
            (_distance(nested) + normalizePremiumWheelDistance(delta: delta))
                .clamp(0.0, maximum)
                .toDouble();
        await _wheel(tester, key, Offset(0, delta));
        await tester.pumpAndSettle(const Duration(milliseconds: 8));
        _expectOffsets(nested, expected);
        expect(nested.outerController.position.outOfRange, isFalse);
        expect(nested.innerController.position.outOfRange, isFalse);
      }
      nested.outerController.jumpTo(20);
      await tester.pump();
      await _wheel(tester, key, const Offset(0, -10000));
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      _expectOffsets(nested, 0);
      await _wheel(tester, key, const Offset(0, -80));
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      _expectOffsets(nested, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('wheel over the header also uses its real coordinator',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    await tester.pumpWidget(_app(_nestedView(key)));
    await tester.pump();
    final nested = key.currentState!;
    await _wheel(tester, key, const Offset(0, 80), target: find.byKey(_header));
    _expectOffsets(nested, 0);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    _expectOffsets(nested, 80);
    final beforeSecondNotch = _distance(nested);
    await _wheel(
      tester,
      key,
      const Offset(0, 120),
      target: find.byKey(_header),
    );
    expect(_distance(nested), beforeSecondNotch);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    _expectOffsets(nested, beforeSecondNotch + 120);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an empty body with no attached inner still retreats the header',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    await tester.pumpWidget(
      _app(_nestedView(key, body: const SizedBox.expand())),
    );
    await tester.pump();
    final nested = key.currentState!;
    expect(nested.innerController.hasClients, isFalse);
    await _wheel(tester, key, const Offset(0, 80), target: find.byKey(key));
    expect(nested.outerController.offset, 0);
    await tester.pump(const Duration(milliseconds: 8));
    expect(nested.outerController.offset, inExclusiveRange(0, 80));
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(nested.outerController.offset, closeTo(80, 0.11));
    expect(nested.innerController.hasClients, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'an exhausted coordinator stops the entire smooth candidate chain',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    final ancestor = ScrollController();
    addTearDown(ancestor.dispose);
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          controller: ancestor,
          child: Column(
            children: [
              SizedBox(height: 400, child: _nestedView(key)),
              const SizedBox(height: 800),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final nested = key.currentState!;
    nested.innerController
        .jumpTo(nested.innerController.position.maxScrollExtent);
    await tester.pump();
    final before = _distance(nested);
    await _wheel(tester, key, const Offset(0, 80));
    // Both owned positions decline at their trailing boundary. Native routing
    // may bubble to the ancestor, but premium must NOT pick it and enqueue.
    expect(ancestor.offset, 80);
    expect(_distance(nested), before);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(ancestor.offset, 80);
    expect(_distance(nested), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unrelated body controller keeps premium smoothing',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    // A matching label is deliberately not a matching controller identity.
    final independent = ScrollController(debugLabel: 'inner');
    addTearDown(independent.dispose);
    await tester.pumpWidget(
      _app(_nestedView(key, independentBodyController: independent)),
    );
    await tester.pump();
    final nested = key.currentState!;
    expect(nested.innerController.hasClients, isFalse);
    await _wheel(tester, key, const Offset(0, 80));
    await _expectSmoothedNotch(tester, independent);
    expect(nested.outerController.offset, 0);
    expect(nested.innerController.hasClients, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a crossing packet clamps once before the next native parent packet',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    final ancestor = ScrollController();
    addTearDown(ancestor.dispose);
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          controller: ancestor,
          child: Column(
            children: [
              SizedBox(height: 400, child: _nestedView(key)),
              const SizedBox(height: 800),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final nested = key.currentState!;
    nested.innerController
        .jumpTo(nested.innerController.position.maxScrollExtent);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    nested.innerController
        .jumpTo(nested.innerController.position.maxScrollExtent - 15);
    await tester.pump();
    final before = _distance(nested);
    await _wheel(tester, key, const Offset(0, 80));
    expect(_distance(nested), before);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(_distance(nested), closeTo(before + 15, 0.001));
    expect(
      ancestor.offset,
      0,
      reason: 'Do not replay a consumed packet or its unused tail.',
    );
    await _wheel(tester, key, const Offset(0, 80));
    expect(
      ancestor.offset,
      80,
      reason: 'An exhausted coordinator yields the next original packet.',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(ancestor.offset, 80);
    expect(_distance(nested), closeTo(before + 15, 0.001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a secondary pane smooths, then yields to the coordinated queue',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    final secondary = ScrollController(debugLabel: 'outer');
    addTearDown(secondary.dispose);
    await tester.pumpWidget(
      _app(_nestedView(key, leading: _secondaryList(secondary))),
    );
    await tester.pump();
    final nested = key.currentState!;
    await _wheel(
      tester,
      key,
      const Offset(0, 80),
      target: find.byKey(_secondary),
    );
    await _expectSmoothedNotch(tester, secondary);
    _expectOffsets(nested, 0);
    secondary.jumpTo(secondary.position.maxScrollExtent);
    await tester.pump();
    await _wheel(
      tester,
      key,
      const Offset(0, 80),
      target: find.byKey(_secondary),
    );
    _expectOffsets(nested, 0);
    expect(secondary.offset, secondary.position.maxScrollExtent);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    _expectOffsets(nested, 80);
    expect(nested.innerController.positions, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final shift in [false, true]) {
    testWidgets('horizontal secondary wheel stays smooth (Shift: $shift)',
        (tester) async {
      final key = GlobalKey<NestedScrollViewState>();
      final horizontal = ScrollController();
      addTearDown(horizontal.dispose);
      await tester.pumpWidget(
        _app(
          _nestedView(
            key,
            leading: _secondaryList(horizontal, axis: Axis.horizontal),
          ),
        ),
      );
      await tester.pump();
      final nested = key.currentState!;
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      try {
        await _wheel(
          tester,
          key,
          shift ? const Offset(0, 80) : const Offset(80, 0),
          target: find.byKey(_secondary),
        );
        await _expectSmoothedNotch(tester, horizontal);
        _expectOffsets(nested, 0);
      } finally {
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      // The very same hit point still routes a vertical wheel to the page.
      await _wheel(
        tester,
        key,
        const Offset(0, 40),
        target: find.byKey(_secondary),
      );
      _expectOffsets(nested, 0);
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      _expectOffsets(nested, 40);
      expect(horizontal.offset, closeTo(80, 0.11));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a horizontal ancestor is not blocked by vertical owned regions',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1200,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: 600, child: _nestedView(key)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _wheel(tester, key, const Offset(80, 0));
    await _expectSmoothedNotch(tester, horizontal);
    _expectOffsets(key.currentState!, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('coordinated smoothing honors pointer axis modifiers',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    await tester.pumpWidget(_app(_nestedView(key)));
    await tester.pump();
    await _wheel(tester, key, const Offset(80, 0));
    _expectOffsets(key.currentState!, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      await _wheel(tester, key, const Offset(80, 0));
      _expectOffsets(key.currentState!, 0);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    _expectOffsets(key.currentState!, 80);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final embedded in [false, true]) {
    testWidgets(
        'an unmarked NestedScrollView is unchanged (embedded: $embedded)',
        (tester) async {
      final key = GlobalKey<NestedScrollViewState>();
      final hostKey = GlobalKey<NestedScrollViewState>();
      final unmarked = _nestedView(key, coordinated: false);
      await tester.pumpWidget(
        _app(
          embedded
              ? _nestedView(
                  hostKey,
                  // An independently hosted database does not borrow the
                  // collection's controller or inherit its wheel opt-in.
                  body: PrimaryScrollController.none(child: unmarked),
                )
              : unmarked,
        ),
      );
      await tester.pump();
      final nested = key.currentState!;
      await _wheel(tester, key, const Offset(0, 80));
      await _expectSmoothedNotch(tester, nested.innerController);
      expect(nested.outerController.offset, 0);
      if (embedded) {
        expect(hostKey.currentState!.outerController.offset, 0);
        expect(hostKey.currentState!.innerController.hasClients, isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'the owning widget can rebuild without losing the controller match',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (_, __, ___) => _nestedView(key),
        ),
      ),
    );
    await tester.pump();
    final nested = key.currentState!;
    final inner = nested.innerController;
    await _wheel(tester, key, const Offset(0, 80));
    _expectOffsets(nested, 0);
    revision.value++;
    await tester.pump(const Duration(milliseconds: 8));
    expect(key.currentState, same(nested));
    expect(nested.innerController, same(inner));
    final intermediate = _distance(nested);
    expect(intermediate, inExclusiveRange(0, 80));
    await _wheel(tester, key, const Offset(0, 120));
    expect(_distance(nested), intermediate);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    _expectOffsets(nested, 200);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a custom excluded surface remains the sole wheel consumer',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    final received = <Offset>[];
    await tester.pumpWidget(
      _app(
        _nestedView(
          key,
          leading: PremiumScrollExclusion(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) => received.add(event.scrollDelta),
                  );
                }
              },
              child: const SizedBox(key: _custom, height: 120, width: 400),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _wheel(tester, key, const Offset(0, 80), target: find.byKey(_custom));
    expect(received, [const Offset(0, 80)]);
    _expectOffsets(key.currentState!, 0);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(received, hasLength(1));
    _expectOffsets(key.currentState!, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'precision pointer signals still take the native coordinated path',
      (tester) async {
    final key = GlobalKey<NestedScrollViewState>();
    await tester.pumpWidget(_app(_nestedView(key)));
    await tester.pump();
    await _wheel(
      tester,
      key,
      const Offset(0, 4),
      kind: PointerDeviceKind.trackpad,
    );
    _expectOffsets(key.currentState!, 4);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    _expectOffsets(key.currentState!, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'the wheel marker leaves real trackpad pan trajectories unchanged',
      (tester) async {
    final unmarked = await _panTrace(tester, coordinated: false);
    final marked = await _panTrace(tester, coordinated: true);
    expect(marked, orderedEquals(unmarked));
    expect(marked.last, greaterThan(_headerExtent));
    expect(tester.takeException(), isNull);
  });
}

// Mirrors the production borrowing path, but uses fixed geometry and no
// backend, assets or IO. Every duration below advances the widget-test clock;
// no runAsync, timers, real-time delays or native processes are needed.
Widget _nestedView(
  GlobalKey<NestedScrollViewState> key, {
  bool coordinated = true,
  double bodyExtent = 2000,
  ScrollController? independentBodyController,
  Widget? leading,
  Widget? body,
}) {
  final view = NestedScrollView(
    key: key,
    headerSliverBuilder: (_, __) => [
      const SliverToBoxAdapter(
        child: SizedBox(key: _header, height: _headerExtent),
      ),
    ],
    body: body ??
        Builder(
          builder: (context) => CollectionPageScrollScope(
            controller: PrimaryScrollController.of(context),
            child: Builder(
              builder: (context) => SingleChildScrollView(
                key: _main,
                controller: independentBodyController ??
                    CollectionPageScrollScope.maybeOf(context),
                primary: false,
                child: SizedBox(
                  height: bodyExtent,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: leading ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
  );
  return coordinated ? PremiumCoordinatedScrollScope(child: view) : view;
}

Widget _secondaryList(
  ScrollController controller, {
  Axis axis = Axis.vertical,
}) =>
    SizedBox(
      height: 120,
      child: ListView.builder(
        key: _secondary,
        controller: controller,
        primary: false,
        scrollDirection: axis,
        itemExtent: 40,
        itemCount: 30,
        itemBuilder: (_, index) => Text('$index'),
      ),
    );

Widget _app(Widget child, {bool enabled = true, bool reducedMotion = false}) =>
    MaterialApp(
      scrollBehavior:
          const _WindowsScrollBehavior().copyWith(scrollbars: false),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: PremiumScrollScope(
          enabled: enabled,
          child: Center(child: SizedBox(width: 600, height: 400, child: child)),
        ),
      ),
    );

class _WindowsScrollBehavior extends MaterialScrollBehavior {
  const _WindowsScrollBehavior();

  @override
  TargetPlatform getPlatform(BuildContext context) => TargetPlatform.windows;
}

Offset _point(
  WidgetTester tester,
  GlobalKey<NestedScrollViewState> key, {
  Finder? target,
}) {
  final viewport = find.byKey(key);
  final hit =
      target ?? find.descendant(of: viewport, matching: find.byKey(_main));
  var visible = tester.getRect(hit).intersect(tester.getRect(viewport));
  // An independently nested fixture has two clipping viewports. Its own
  // viewport center alone can lie below the containing collection's edge.
  for (final ancestor in find
      .ancestor(of: viewport, matching: find.byType(NestedScrollView))
      .evaluate()) {
    final box = ancestor.findRenderObject()! as RenderBox;
    visible = visible.intersect(box.localToGlobal(Offset.zero) & box.size);
  }
  expect(visible.isEmpty, isFalse);
  return visible.center;
}

Future<void> _wheel(
  WidgetTester tester,
  GlobalKey<NestedScrollViewState> key,
  Offset delta, {
  Finder? target,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) =>
    tester.sendEventToBinding(
      PointerScrollEvent(
        position: _point(tester, key, target: target),
        scrollDelta: delta,
        kind: kind,
      ),
    );

double _distance(NestedScrollViewState nested) =>
    nested.outerController.offset + nested.innerController.offset;

void _expectOffsets(NestedScrollViewState nested, double distance) {
  final outer = math.min(distance, _headerExtent);
  // The shared premium wheel policy drops at most wheelStopDistance (0.1px).
  expect(nested.outerController.offset, closeTo(outer, 0.11));
  expect(nested.innerController.offset, closeTo(distance - outer, 0.11));
  expect(_distance(nested), closeTo(distance, 0.11));
}

Future<void> _expectSmoothedNotch(
  WidgetTester tester,
  ScrollController controller,
) async {
  expect(controller.offset, 0, reason: 'Unrelated wheels must still enqueue.');
  await tester.pump(const Duration(milliseconds: 8));
  expect(controller.offset, inExclusiveRange(0, 80));
  await tester.pumpAndSettle(const Duration(milliseconds: 8));
  expect(controller.offset, closeTo(80, 0.11));
}

Future<List<double>> _panTrace(
  WidgetTester tester, {
  required bool coordinated,
}) async {
  final key = GlobalKey<NestedScrollViewState>();
  await tester.pumpWidget(_app(_nestedView(key, coordinated: coordinated)));
  await tester.pump();
  final nested = key.currentState!;
  final point = _point(tester, key);
  final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  final trace = <double>[];
  await pan.panZoomStart(point);
  for (var frame = 1; frame <= 24; frame++) {
    await pan.panZoomUpdate(
      point,
      pan: Offset(0, -24.0 * frame),
      timeStamp: Duration(milliseconds: frame * 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
    trace.add(_distance(nested));
  }
  await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 500));
  await tester.pumpAndSettle(const Duration(milliseconds: 8));
  trace.add(_distance(nested));
  await tester.pumpWidget(const SizedBox.shrink());
  return trace;
}
