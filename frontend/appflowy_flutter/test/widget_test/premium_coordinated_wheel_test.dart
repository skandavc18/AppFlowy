import 'dart:math' as math;

import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(microseconds: 8333);
const _header = ValueKey('coordinated-wheel-header');
const _content = ValueKey('coordinated-wheel-content');
const _native = ValueKey('coordinated-native-embed');
const _headerExtent = 160.0;

void main() {
  for (final config in [
    const PremiumScrollPhysicsConfig(),
    const PremiumScrollPhysicsConfig(
      maxWheelDelta: 60,
      maxWheelQueuedDistance: 90,
      maxWheelScrollVelocity: 360,
      wheelSmoothingRate: 9,
      wheelStopDistance: 0.05,
    ),
  ]) {
    testWidgets(
      'each frame applies one shared wheel step through header and body '
      '(rate: ${config.wheelSmoothingRate})',
      (tester) async {
        tester.view.display.refreshRate = 120;
        addTearDown(tester.view.display.resetRefreshRate);
        final fixture = await _mount(tester, config: config);
        fixture.nested.outerController.jumpTo(130);
        await tester.pumpAndSettle();
        final body = fixture.bodyKey.currentState!;
        body.draft.text = 'keep this unsaved draft';
        body.draft.selection =
            const TextSelection(baseOffset: 2, extentOffset: 8);
        final bodyPosition = fixture.nested.innerController.position;
        final headerElement =
            tester.element(find.byKey(_header, skipOffstage: false));
        final headerTop =
            tester.getTopLeft(find.byKey(_header, skipOffstage: false)).dy;
        final contentTop = tester.getTopLeft(find.byKey(_content)).dy;
        final builds = body.builds;
        fixture.updates = 0;

        await _wheel(tester, fixture, 120);
        expect(
          fixture.distance,
          130,
          reason: 'No native full-notch jump before vsync.',
        );
        expect(fixture.rawSignals, 1);
        expect(fixture.updates, 0);
        var remaining =
            normalizePremiumWheelDistance(delta: 120, config: config);
        var expected = 130.0;
        var frames = 0;
        while (remaining.abs() > config.wheelStopDistance && frames++ < 200) {
          final step = premiumWheelFrameDisplacement(
            remainingDistance: remaining,
            elapsedSeconds:
                _frame.inMicroseconds / Duration.microsecondsPerSecond,
            config: config,
          );
          remaining -= step;
          expected += step;
          final before = fixture.distance;
          await tester.pump(_frame);
          expect(fixture.distance, closeTo(expected, 0.0001));
          expect(fixture.distance - before, closeTo(step, 0.0001));
          expect(fixture.updates, closeTo(expected - 130, 0.0001));
          expect(
            fixture.nested.outerController.offset,
            closeTo(math.min(expected, _headerExtent), 0.0001),
          );
          expect(
            fixture.nested.innerController.offset,
            closeTo(math.max(0, expected - _headerExtent), 0.0001),
          );
          expect(
            tester.getTopLeft(find.byKey(_content)).dy,
            closeTo(contentTop - (expected - 130), 0.001),
          );
          expect(
            tester.getTopLeft(find.byKey(_header, skipOffstage: false)).dy,
            closeTo(
              headerTop - (fixture.nested.outerController.offset - 130),
              0.001,
            ),
          );
          expect(
            tester.element(find.byKey(_header, skipOffstage: false)),
            same(headerElement),
          );
          expect(fixture.nested.innerController.position, same(bodyPosition));
          expect(fixture.bodyKey.currentState, same(body));
          expect(body.builds, builds);
          expect(body.draft.text, 'keep this unsaved draft');
          expect(
            body.draft.selection,
            const TextSelection(baseOffset: 2, extentOffset: 8),
          );
          expect(fixture.mounts, 1);
          expect(fixture.disposals, 0);
        }
        expect(frames, lessThan(200));
        expect(fixture.nested.innerController.offset, greaterThan(0));
        expect(
          fixture.rawSignals,
          1,
          reason: 'Frame deltas are not replayed pointer events.',
        );
        final settled = fixture.distance;
        await tester.pumpAndSettle(const Duration(milliseconds: 8));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          fixture.distance,
          settled,
          reason: 'No snap or extra ballistic tail.',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(fixture.disposals, 1);
      },
    );
  }

  for (final burst in [false, true]) {
    testWidgets('header/body input shares one queue (bounded burst: $burst)',
        (tester) async {
      final fixture = await _mount(tester);
      final deltas = burst ? List.filled(10, 120.0) : [40.0, 60.0];
      for (var i = 0; i < deltas.length; i++) {
        await _wheel(tester, fixture, deltas[i], header: i.isEven);
      }
      expect(fixture.distance, 0);
      await tester.pump(_frame);
      expect(fixture.distance, inExclusiveRange(0, 40));
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      expect(fixture.distance, closeTo(burst ? 240 : 100, 0.11));
      expect(fixture.rawSignals, deltas.length);
      expect(fixture.mounts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('reversal drops the pending direction without an input-time jump',
      (tester) async {
    final fixture = await _mount(tester);
    fixture.nested.innerController.jumpTo(140);
    await tester.pumpAndSettle();
    await _wheel(tester, fixture, 120);
    await tester.pump(_frame);
    await tester.pump(_frame);
    final reversalOffset = fixture.distance;
    await _wheel(tester, fixture, -40);
    expect(fixture.distance, reversalOffset);
    await tester.pump(_frame);
    expect(fixture.distance, lessThan(reversalOffset));
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(fixture.distance, closeTo(reversalOffset - 40, 0.11));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('viewport resize keeps queued distance and mounted body',
      (tester) async {
    final fixture = await _mount(tester);
    fixture.nested.innerController.jumpTo(40);
    await tester.pumpAndSettle();
    final before = fixture.distance;
    final body = fixture.bodyKey.currentState;
    final position = fixture.nested.innerController.position;
    await _wheel(tester, fixture, 120);
    await tester.pump(_frame);
    final intermediate = fixture.distance;
    fixture.resize(height: 520);
    await tester.pump();
    expect(fixture.distance, intermediate);
    expect(position.viewportDimension, 520);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(fixture.distance, closeTo(before + 120, 0.11));
    expect(fixture.bodyKey.currentState, same(body));
    expect(fixture.nested.innerController.position, same(position));
    expect(fixture.mounts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a replacement body does not inherit old queued input or lose its new notch',
      (tester) async {
    final fixture = await _mount(tester);
    final retiredBody = fixture.bodyKey.currentState!;
    await _wheel(tester, fixture, 120);
    await tester.pump(_frame);
    fixture.replaceBody();
    await tester.pump();
    final before = fixture.distance;
    expect(retiredBody.mounted, isFalse);
    await _wheel(tester, fixture, 40);
    expect(fixture.distance, before);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(fixture.distance, closeTo(before + 40, 0.11));
    expect(
      fixture.mounts,
      2,
      reason: 'Only the explicit test-host replacement mounts a new body.',
    );
    expect(fixture.disposals, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'floating headers retain native reverse priority during smoothing',
      (tester) async {
    final fixture = await _mount(tester, floatHeaderSlivers: true);
    fixture.nested.innerController.jumpTo(140);
    await tester.pumpAndSettle();
    expect(fixture.distance, 300);
    await _wheel(tester, fixture, -80);
    expect(fixture.distance, 300);
    await tester.pump(_frame);
    expect(fixture.nested.outerController.offset, inExclusiveRange(80, 160));
    expect(fixture.nested.innerController.offset, 140);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(fixture.nested.outerController.offset, closeTo(80, 0.11));
    expect(fixture.nested.innerController.offset, 140);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reversed matching axes preserve native wheel direction',
      (tester) async {
    final fixture = await _mount(tester, reverse: true);
    await _wheel(tester, fixture, -80);
    expect(fixture.distance, 0);
    await tester.pump(_frame);
    expect(fixture.distance, inExclusiveRange(0, 80));
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(fixture.nested.outerController.offset, closeTo(80, 0.11));
    expect(fixture.nested.innerController.offset, closeTo(0, 1e-10));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('content shrink clamps to live bounds and discards the old tail',
      (tester) async {
    final fixture = await _mount(tester);
    fixture.nested.innerController.jumpTo(300);
    await tester.pumpAndSettle();
    await _wheel(tester, fixture, 120);
    await tester.pump(_frame);
    fixture.resize(bodyExtent: 100);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(fixture.distance, _headerExtent);
    expect(fixture.nested.innerController.position.outOfRange, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(fixture.distance, _headerExtent);
    expect(fixture.mounts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final interrupt in [
    'jump',
    'mouse down',
    'pan start',
    'precision signal',
    'inertia cancel',
  ]) {
    testWidgets('$interrupt cancels a pending coordinated wheel',
        (tester) async {
      final fixture = await _mount(tester);
      await _wheel(tester, fixture, 120);
      await tester.pump(_frame);
      final point = _point(tester, fixture);
      TestGesture? gesture;
      switch (interrupt) {
        case 'jump':
          fixture.nested.outerController.jumpTo(30);
        case 'mouse down':
          gesture =
              await tester.startGesture(point, kind: PointerDeviceKind.mouse);
        case 'pan start':
          gesture =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await gesture.panZoomStart(point);
        case 'precision signal':
          final before = fixture.distance;
          await _wheel(tester, fixture, 4, kind: PointerDeviceKind.trackpad);
          expect(fixture.distance, closeTo(before + 4, 0.001));
        case 'inertia cancel':
          await tester.sendEventToBinding(
            PointerScrollInertiaCancelEvent(position: point),
          );
      }
      final stopped = fixture.distance;
      await tester.pump(const Duration(milliseconds: 100));
      expect(fixture.distance, stopped);
      if (interrupt == 'pan start') {
        await gesture!.panZoomEnd();
      } else {
        await gesture?.up();
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 8));
      expect(fixture.distance, stopped);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('detaching a moving coordinator disposes its off-position ticker',
      (tester) async {
    final fixture = await _mount(tester);
    await _wheel(tester, fixture, 120);
    await tester.pump(_frame);
    expect(fixture.distance, inExclusiveRange(0, 120));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    expect(fixture.disposals, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a programmatic animation takes over without a wheel tail',
      (tester) async {
    final fixture = await _mount(tester);
    await _wheel(tester, fixture, 120);
    await tester.pump(_frame);
    final animation = fixture.nested.outerController.animateTo(
      60,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    await animation;
    expect(fixture.distance, 60);
    await tester.pump(const Duration(milliseconds: 500));
    expect(fixture.distance, 60);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('PageScrollPhysics remains native inside a marked coordinator',
      (tester) async {
    final fixture = await _mount(tester, physics: const PageScrollPhysics());
    await _wheel(tester, fixture, 80);
    expect(fixture.distance, 80);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(fixture.distance, 80);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inactive native embed yields; activated embed consumes once',
      (tester) async {
    final blocked = ValueNotifier(true);
    addTearDown(blocked.dispose);
    final received = <double>[];
    final fixture = await _mount(
      tester,
      leading: ValueListenableBuilder<bool>(
        valueListenable: blocked,
        builder: (_, value, child) =>
            ScrollGestureGate(blocked: value, child: child!),
        child: PremiumScrollExclusion(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (_) => received.add(event.scrollDelta.dy),
                );
              }
            },
            child: const SizedBox(key: _native, width: 400, height: 120),
          ),
        ),
      ),
    );
    final element = tester.element(find.byKey(_native));
    await _wheel(tester, fixture, 80, target: find.byKey(_native));
    expect(fixture.distance, 0);
    await tester.pump(_frame);
    expect(fixture.distance, inExclusiveRange(0, 80));
    expect(received, isEmpty);
    blocked.value = false;
    await tester.pump();
    final before = fixture.distance;
    await _wheel(tester, fixture, 80, target: find.byKey(_native));
    expect(received, [80]);
    await tester.pumpAndSettle(const Duration(milliseconds: 8));
    expect(
      fixture.distance,
      before,
      reason: 'The native owner must not inherit an old page tail.',
    );
    expect(tester.element(find.byKey(_native)), same(element));
    expect(fixture.mounts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the opt-in leaves real touch drags and release unchanged',
      (tester) async {
    final native = await _touchTrace(tester, coordinated: false);
    final coordinated = await _touchTrace(tester, coordinated: true);
    expect(coordinated, orderedEquals(native));
    expect(coordinated.last, greaterThan(_headerExtent));
    expect(tester.takeException(), isNull);
  });
}

Future<_FixtureState> _mount(
  WidgetTester tester, {
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
  ScrollPhysics? physics,
  Widget? leading,
  bool coordinated = true,
  bool floatHeaderSlivers = false,
  bool reverse = false,
}) async {
  final key = GlobalKey<_FixtureState>();
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const _WindowsBehavior().copyWith(scrollbars: false),
      home: Material(
        child: PremiumScrollScope(
          enabled: true,
          config: config,
          child: Center(
            child: _Fixture(
              key: key,
              physics: physics,
              leading: leading,
              coordinated: coordinated,
              floatHeaderSlivers: floatHeaderSlivers,
              reverse: reverse,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

class _Fixture extends StatefulWidget {
  const _Fixture({
    super.key,
    this.physics,
    this.leading,
    required this.coordinated,
    required this.floatHeaderSlivers,
    required this.reverse,
  });

  final ScrollPhysics? physics;
  final Widget? leading;
  final bool coordinated;
  final bool floatHeaderSlivers;
  final bool reverse;

  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  final nestedKey = GlobalKey<NestedScrollViewState>();
  GlobalKey<_RetainedBodyState> bodyKey = GlobalKey<_RetainedBodyState>();
  double height = 400;
  double bodyExtent = 2000;
  int mounts = 0;
  int disposals = 0;
  int rawSignals = 0;
  double updates = 0;

  NestedScrollViewState get nested => nestedKey.currentState!;
  double get distance =>
      nested.outerController.offset + nested.innerController.offset;

  void resize({double? height, double? bodyExtent}) => setState(() {
        this.height = height ?? this.height;
        this.bodyExtent = bodyExtent ?? this.bodyExtent;
      });

  void replaceBody() => setState(() {
        bodyKey = GlobalKey<_RetainedBodyState>();
      });

  @override
  Widget build(BuildContext context) {
    final view = NestedScrollView(
      key: nestedKey,
      floatHeaderSlivers: widget.floatHeaderSlivers,
      reverse: widget.reverse,
      headerSliverBuilder: (_, __) => [
        const SliverToBoxAdapter(
          child: SizedBox(key: _header, height: _headerExtent),
        ),
      ],
      body: _RetainedBody(key: bodyKey, fixture: this),
    );
    return SizedBox(
      width: 600,
      height: height,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) rawSignals++;
        },
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            updates += notification.scrollDelta ?? 0;
            return false;
          },
          child: widget.coordinated
              ? PremiumCoordinatedScrollScope(child: view)
              : view,
        ),
      ),
    );
  }
}

class _RetainedBody extends StatefulWidget {
  const _RetainedBody({super.key, required this.fixture});

  final _FixtureState fixture;

  @override
  State<_RetainedBody> createState() => _RetainedBodyState();
}

class _RetainedBodyState extends State<_RetainedBody> {
  final draft = TextEditingController(text: 'draft');
  int builds = 0;

  @override
  void initState() {
    super.initState();
    widget.fixture.mounts++;
  }

  @override
  void dispose() {
    widget.fixture.disposals++;
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    return SingleChildScrollView(
      controller: PrimaryScrollController.of(context),
      primary: false,
      reverse: widget.fixture.widget.reverse,
      physics: widget.fixture.widget.physics,
      child: SizedBox(
        key: _content,
        height: widget.fixture.bodyExtent,
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.fixture.widget.leading != null)
              widget.fixture.widget.leading!,
            SizedBox(width: 200, child: TextField(controller: draft)),
          ],
        ),
      ),
    );
  }
}

class _WindowsBehavior extends MaterialScrollBehavior {
  const _WindowsBehavior();

  @override
  TargetPlatform getPlatform(BuildContext context) => TargetPlatform.windows;
}

Offset _point(
  WidgetTester tester,
  _FixtureState fixture, {
  bool header = false,
  Finder? target,
}) {
  final viewport = tester.getRect(find.byKey(fixture.nestedKey));
  final hit =
      target ?? (header ? find.byKey(_header) : find.byKey(fixture.bodyKey));
  final visible = tester.getRect(hit).intersect(viewport);
  expect(visible.isEmpty, isFalse);
  return visible.center;
}

Future<void> _wheel(
  WidgetTester tester,
  _FixtureState fixture,
  double delta, {
  bool header = false,
  Finder? target,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) =>
    tester.sendEventToBinding(
      PointerScrollEvent(
        position: _point(tester, fixture, header: header, target: target),
        scrollDelta: Offset(0, delta),
        kind: kind,
      ),
    );

Future<List<double>> _touchTrace(
  WidgetTester tester, {
  required bool coordinated,
}) async {
  final fixture = await _mount(tester, coordinated: coordinated);
  final gesture = await tester.startGesture(_point(tester, fixture));
  final trace = <double>[];
  for (var frame = 1; frame <= 16; frame++) {
    await gesture.moveBy(
      const Offset(0, -24),
      timeStamp: Duration(milliseconds: frame * 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
    trace.add(fixture.distance);
  }
  await gesture.up(timeStamp: const Duration(milliseconds: 400));
  await tester.pumpAndSettle(const Duration(milliseconds: 8));
  trace.add(fixture.distance);
  await tester.pumpWidget(const SizedBox.shrink());
  return trace;
}
