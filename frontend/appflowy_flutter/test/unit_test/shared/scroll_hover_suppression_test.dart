import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:appflowy/shared/scrolling/scroll_hover_suppression.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MouseTrackerAnnotation;
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);
const _point = Offset(120, 100);

void main() {
  testWidgets(
      'stationary mouse exits once through trackpad and ballistic scroll',
      (tester) async {
    final controller = ScrollController();
    final hover = _HoverLog();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final pan = await tester.createGesture(
      pointer: 83,
      kind: PointerDeviceKind.trackpad,
    );
    try {
      await tester.pumpWidget(
        _host(
          ScrollHoverSuppression(
            child: _rows(controller: controller, hover: hover),
          ),
        ),
      );
      await mouse.addPointer(location: const Offset(500, 400));
      await mouse.moveTo(_point);
      await tester.pump();
      expect(hover.enters, hasLength(1));
      expect(hover.exits, isEmpty);
      final initialHovers = hover.hovers;

      await pan.panZoomStart(_point);
      await _panStep(tester, pan, _point, 1);
      expect(controller.position.isScrollingNotifier.value, isTrue);
      expect(hover.counts, (1, 1, initialHovers));
      for (var step = 2; step <= 8; step++) {
        await _panStep(tester, pan, _point, step);
        expect(hover.counts, (1, 1, initialHovers));
      }
      final releaseOffset = controller.offset;
      expect(releaseOffset, greaterThan(200));
      await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 129));
      await tester.pump();
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(_frame);
        expect(controller.position.isScrollingNotifier.value, isTrue);
        expect(hover.counts, (1, 1, initialHovers));
      }
      expect(controller.offset, greaterThan(releaseOffset));

      // An actual hover event must not reach a retained MouseRegion either.
      await mouse.moveTo(_point + const Offset(1, 0));
      expect(hover.counts, (1, 1, initialHovers));
      await tester.pumpAndSettle();
      expect(controller.position.isScrollingNotifier.value, isFalse);
      expect(hover.counts, (2, 1, initialHovers));
      expect(hover.enters.last, isNot(hover.enters.first));
      await mouse.moveTo(_point);
      expect(hover.counts, (2, 1, initialHovers + 1));
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('wheel, pan and coasting clicks match the original ($kind)',
        (tester) async {
      final original =
          await _exerciseInput(tester, suppressed: false, kind: kind);
      final suppressed =
          await _exerciseInput(tester, suppressed: true, kind: kind);
      expect(original.wheels, [const Offset(3, 24), const Offset(-2, 36)]);
      expect(suppressed.wheels, original.wheels);
      expect(original.pans, List.filled(6, const Offset(0, -40)));
      expect(suppressed.pans, original.pans);
      expect(suppressed.offsets.length, original.offsets.length);
      for (var i = 0; i < original.offsets.length; i++) {
        expect(suppressed.offsets[i], closeTo(original.offsets[i], 0.001));
      }
      expect(original.downs, 1);
      expect(original.taps, 1);
      expect(suppressed.downs, original.downs);
      expect(suppressed.taps, original.taps);
      expect(suppressed.stopped, original.stopped);
      if (kind == PointerDeviceKind.touch) expect(suppressed.stopped, isTrue);
    });
  }

  testWidgets('activation retains child state, geometry and semantic tap label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = ScrollController();
    final probeKey = GlobalKey<_BuildProbeState>();
    const actionKey = ValueKey('semantic-action');
    final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    try {
      await tester.pumpWidget(
        _host(
          ScrollHoverSuppression(
            child: _BuildProbe(
              key: probeKey,
              child: SingleChildScrollView(
                controller: controller,
                physics: const ClampingScrollPhysics(),
                child: Semantics(
                  key: actionKey,
                  container: true,
                  label: 'Open item',
                  button: true,
                  onTap: () {},
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () {},
                    child: const SizedBox(width: 320, height: 1600),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final element = probeKey.currentContext;
      final state = probeKey.currentState!;
      final renderObject = element!.findRenderObject();
      final size = tester.getSize(find.byKey(probeKey));
      final builds = state.builds;
      final node = tester.getSemantics(find.byKey(actionKey));
      void expectRetained() {
        expect(probeKey.currentContext, same(element));
        expect(probeKey.currentState, same(state));
        expect(element.findRenderObject(), same(renderObject));
        expect(tester.getSize(find.byKey(probeKey)), size);
        expect(state.builds, builds);
        expect(state.disposed, isFalse);
        expect(tester.getSemantics(find.byKey(actionKey)), same(node));
        expect(
          node,
          matchesSemantics(
            label: 'Open item',
            isButton: true,
            hasTapAction: true,
          ),
        );
      }

      expectRetained();
      await pan.panZoomStart(_point);
      await _panStep(tester, pan, _point, 1);
      await _panStep(tester, pan, _point, 2);
      expect(controller.position.isScrollingNotifier.value, isTrue);
      expectRetained();
      await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 33));
      await tester.pumpAndSettle();
      expectRetained();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      semantics.dispose();
    }
  });

  testWidgets('nested native viewport notifications never toggle page hover',
      (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    final hover = _HoverLog();
    final notifications = <(Type, int)>[];
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final pan = await tester.createGesture(
      pointer: 84,
      kind: PointerDeviceKind.trackpad,
    );
    try {
      await tester.pumpWidget(
        _host(
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              notifications.add((notification.runtimeType, notification.depth));
              return false;
            },
            child: ScrollHoverSuppression(
              child: MouseRegion(
                onEnter: (_) => hover.enters.add(0),
                onExit: (_) => hover.exits.add(0),
                onHover: (_) => hover.hovers++,
                child: SingleChildScrollView(
                  controller: outer,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 160,
                        child: _rows(controller: inner, hover: _HoverLog()),
                      ),
                      const SizedBox(height: 2000),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      const pagePoint = Offset(120, 210);
      await mouse.addPointer(location: const Offset(500, 400));
      await mouse.moveTo(pagePoint);
      await tester.pump();
      await pan.panZoomStart(_point);
      for (var step = 1; step <= 4; step++) {
        await _panStep(tester, pan, _point, step);
        expect(hover.counts, (1, 0, 1));
      }
      expect(inner.offset, greaterThan(0));
      expect(outer.offset, 0);
      await mouse.moveTo(pagePoint + const Offset(1, 0));
      expect(hover.counts, (1, 0, 2));
      await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 65));
      await tester.pumpAndSettle();
      expect(notifications, contains((ScrollStartNotification, 1)));
      expect(notifications, contains((ScrollEndNotification, 1)));
      expect(hover.counts, (1, 0, 2));

      await pan.panZoomStart(pagePoint);
      await _panStep(tester, pan, pagePoint, 1);
      expect(notifications, contains((ScrollStartNotification, 0)));
      expect(hover.counts, (1, 1, 2));
      // A nested end must not release an already-suppressed parent.
      inner.jumpTo(0);
      await tester.pump();
      await mouse.moveTo(pagePoint);
      expect(hover.counts, (1, 1, 2));
      await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 17));
      await tester.pumpAndSettle();
      expect(hover.counts, (2, 1, 2));
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      outer.dispose();
      inner.dispose();
    }
  });

  testWidgets('only start/end change suppression and notifications bubble',
      (tester) async {
    late BuildContext source;
    final hover = _HoverLog();
    var bubbled = 0;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await tester.pumpWidget(
        _host(
          NotificationListener<ScrollNotification>(
            onNotification: (_) {
              bubbled++;
              return false;
            },
            child: ScrollHoverSuppression(
              child: Builder(
                builder: (context) {
                  source = context;
                  return _hoverRegion(hover);
                },
              ),
            ),
          ),
        ),
      );
      await mouse.addPointer(location: const Offset(500, 400));
      await mouse.moveTo(_point);
      await tester.pump();
      void updates() {
        ScrollUpdateNotification(
          metrics: _metrics,
          context: source,
          scrollDelta: 12,
        ).dispatch(source);
        OverscrollNotification(
          metrics: _metrics,
          context: source,
          overscroll: 12,
        ).dispatch(source);
        UserScrollNotification(
          metrics: _metrics,
          context: source,
          direction: ScrollDirection.idle,
        ).dispatch(source);
      }

      updates();
      await tester.pump();
      expect(hover.counts, (1, 0, 1));
      _notify(source, true);
      _notify(source, true);
      await tester.pump();
      expect(hover.counts, (1, 1, 1));
      updates();
      await tester.pump();
      await mouse.moveTo(_point + const Offset(1, 0));
      expect(hover.counts, (1, 1, 1));
      _notify(source, false);
      _notify(source, false);
      await tester.pump();
      expect(hover.counts, (2, 1, 1));
      expect(bubbled, 10);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final gate in ['none', 'inside', 'outside']) {
    testWidgets(
        'composed transforms and TapRegion identity (scroll gate: $gate)',
        (tester) async {
      late BuildContext source;
      final annotation = _AnnotatedTarget();
      final plain = _PointerLog();
      final probeKey = GlobalKey();
      const mouseKey = ValueKey('mouse-region');
      const tapKey = ValueKey('tap-region');
      const targetKey = ValueKey('scaled-target');
      Offset? localDown;
      var hovers = 0;
      var taps = 0;
      var inside = 0;
      var outside = 0;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        final body = MouseRegion(
          key: mouseKey,
          onHover: (_) => hovers++,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Transform.scale(
              scale: 0.75,
              alignment: Alignment.topLeft,
              child: TapRegion(
                key: tapKey,
                onTapInside: (_) => inside++,
                onTapOutside: (_) => outside++,
                child: _HitTarget(
                  key: probeKey,
                  target: annotation,
                  child: _HitTarget(
                    target: plain,
                    child: Listener(
                      onPointerDown: (event) => localDown = event.localPosition,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps++,
                        child: const SizedBox(
                          key: targetKey,
                          width: 80,
                          height: 60,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final suppression = ScrollHoverSuppression(
          child: Builder(
            builder: (context) {
              source = context;
              return gate == 'inside'
                  ? ScrollGestureGate(blocked: true, child: body)
                  : body;
            },
          ),
        );
        await tester.pumpWidget(
          _host(
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: Transform.scale(
                  scale: 1.5,
                  alignment: Alignment.topLeft,
                  child: gate == 'outside'
                      ? ScrollGestureGate(blocked: true, child: suppression)
                      : suppression,
                ),
              ),
            ),
          ),
        );
        final point = tester.getCenter(find.byKey(targetKey));
        final region =
            tester.renderObject<RenderMouseRegion>(find.byKey(mouseKey));
        final tapRegion =
            tester.renderObject<RenderTapRegion>(find.byKey(tapKey));
        await mouse.addPointer(location: const Offset(500, 400));
        await mouse.moveTo(point);
        await tester.pump();
        final before = tester.hitTestOnBinding(point).path.toList();
        expect(
          before.any((entry) => identical(entry.target, annotation)),
          isTrue,
        );
        _notify(source, true);
        await tester.pump();
        final after = tester.hitTestOnBinding(point).path.toList();
        expect(
          after.any((entry) => identical(entry.target, annotation)),
          isFalse,
        );
        expect(after.any((entry) => identical(entry.target, region)), isFalse);
        expect(
          after.any((entry) => identical(entry.target, tapRegion)),
          isTrue,
        );
        if (gate == 'none') {
          // Every non-annotation identity, entry shape and transform survives.
          for (final entry in before) {
            if (entry.target is MouseTrackerAnnotation) continue;
            final replayed = after.singleWhere(
              (candidate) => identical(candidate.target, entry.target),
            );
            for (var i = 0; i < 16; i++) {
              expect(
                replayed.transform!.storage[i],
                closeTo(entry.transform!.storage[i], 0.00001),
              );
            }
            if (entry is BoxHitTestEntry) {
              expect(replayed, isA<BoxHitTestEntry>());
              expect(
                (replayed as BoxHitTestEntry).localPosition,
                entry.localPosition,
              );
            } else {
              expect(replayed, isNot(isA<BoxHitTestEntry>()));
            }
          }
        }
        final plainHovers = plain.hovers;
        await mouse.moveTo(point + const Offset(1, 0));
        expect(hovers, 1);
        expect(annotation.events.hovers, 1);
        expect(plain.hovers, plainHovers + 1);
        await tester.tapAt(point);
        for (final local in [
          localDown!,
          annotation.events.down!.localPosition,
          plain.down!.localPosition,
        ]) {
          expect(local.dx, closeTo(40, 0.001));
          expect(local.dy, closeTo(30, 0.001));
        }
        if (gate == 'none') {
          final probe =
              tester.renderObject<_RenderHitTarget>(find.byKey(probeKey));
          expect(annotation.events.entry, same(probe.lastEntry));
        }
        expect(taps, 1);
        expect(inside, 1);
        expect(outside, 0);
        _notify(source, false);
        await tester.pump();
        await mouse.moveTo(point);
        expect(hovers, 2);
        expect(annotation.events.hovers, 2);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('build-time lifecycle notifications coalesce to the latest state',
      (tester) async {
    final requests = ValueNotifier<List<bool>>(const []);
    final hover = _HoverLog();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await tester.pumpWidget(
        _host(
          ScrollHoverSuppression(
            child: ValueListenableBuilder<List<bool>>(
              valueListenable: requests,
              builder: (context, values, child) {
                for (final value in values) {
                  _notify(context, value);
                }
                return child!;
              },
              child: _hoverRegion(hover),
            ),
          ),
        ),
      );
      await mouse.addPointer(location: const Offset(500, 400));
      await mouse.moveTo(_point);
      await tester.pump();
      requests.value = [true, false, true];
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(hover.counts, (1, 1, 1));
      requests.value = [false, true, false];
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(hover.counts, (2, 1, 1));
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      requests.dispose();
    }
  });

  testWidgets('disposal discards a pending lifecycle update', (tester) async {
    late NotificationListenerCallback<ScrollNotification> notify;
    var notified = false;
    await tester.pumpWidget(
      _host(
        ScrollHoverSuppression(
          child: _OnDispose(
            onDispose: () {
              // Invoke the listener directly: a deactivated context cannot
              // dispatch notifications, but the ancestor is not disposed yet.
              notify(ScrollStartNotification(metrics: _metrics, context: null));
              notified = true;
            },
          ),
        ),
      ),
    );
    notify = tester
        .widget<NotificationListener<ScrollNotification>>(
          find.descendant(
            of: find.byType(ScrollHoverSuppression),
            matching: find.byType(NotificationListener<ScrollNotification>),
          ),
        )
        .onNotification!;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(notified, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          height: 240,
          child: ScrollConfiguration(
            behavior: const ScrollBehavior().copyWith(
              scrollbars: false,
              overscroll: false,
            ),
            child: child,
          ),
        ),
      ),
    );

Widget _rows({
  required ScrollController controller,
  required _HoverLog hover,
  VoidCallback? onTap,
  PointerDownEventListener? onPointerDown,
}) =>
    ListView.builder(
      controller: controller,
      physics: const ClampingScrollPhysics(),
      itemExtent: 40,
      itemCount: 200,
      itemBuilder: (_, index) => MouseRegion(
        onEnter: (_) => hover.enters.add(index),
        onExit: (_) => hover.exits.add(index),
        onHover: (_) => hover.hovers++,
        child: Listener(
          onPointerDown: onPointerDown,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Text('Row $index'),
          ),
        ),
      ),
    );

Widget _hoverRegion(_HoverLog hover) => MouseRegion(
      onEnter: (_) => hover.enters.add(0),
      onExit: (_) => hover.exits.add(0),
      onHover: (_) => hover.hovers++,
      child: const SizedBox.expand(),
    );

class _HoverLog {
  final enters = <int>[];
  final exits = <int>[];
  var hovers = 0;

  (int, int, int) get counts => (enters.length, exits.length, hovers);
}

Future<void> _panStep(
  WidgetTester tester,
  TestGesture pan,
  Offset point,
  int step,
) async {
  await pan.panZoomUpdate(
    point,
    pan: Offset(0, -40.0 * step),
    timeStamp: Duration(milliseconds: step * 16),
  );
  await tester.pump(_frame);
}

class _InputLog {
  final wheels = <Offset>[];
  final pans = <Offset>[];
  final offsets = <double>[];
  var downs = 0;
  var taps = 0;
  var stopped = false;
}

Future<_InputLog> _exerciseInput(
  WidgetTester tester, {
  required bool suppressed,
  required PointerDeviceKind kind,
}) async {
  final controller = ScrollController();
  final log = _InputLog();
  final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  try {
    final child = Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) log.wheels.add(event.scrollDelta);
      },
      onPointerPanZoomUpdate: (event) => log.pans.add(event.panDelta),
      child: _rows(
        controller: controller,
        hover: _HoverLog(),
        onTap: () => log.taps++,
        onPointerDown: (_) => log.downs++,
      ),
    );
    await tester.pumpWidget(
      _host(suppressed ? ScrollHoverSuppression(child: child) : child),
    );
    for (final delta in [const Offset(3, 24), const Offset(-2, 36)]) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: _point, scrollDelta: delta),
      );
      await tester.pump();
      log.offsets.add(controller.offset);
    }
    expect(controller.offset, 60);
    await pan.panZoomStart(_point);
    for (var step = 1; step <= 6; step++) {
      await _panStep(tester, pan, _point, step);
      log.offsets.add(controller.offset);
    }
    await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 97));
    await tester.pump();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(_frame);
      log.offsets.add(controller.offset);
    }
    expect(controller.position.isScrollingNotifier.value, isTrue);
    await tester.tapAt(_point, kind: kind);
    await tester.pump();
    log.stopped = !controller.position.isScrollingNotifier.value;
    await tester.pumpAndSettle();
    return log;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }
}

ScrollMetrics get _metrics => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 2000,
      pixels: 0,
      viewportDimension: 240,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

void _notify(BuildContext context, bool scrolling) {
  final ScrollNotification notification = scrolling
      ? ScrollStartNotification(metrics: _metrics, context: context)
      : ScrollEndNotification(metrics: _metrics, context: context);
  notification.dispatch(context);
}

class _BuildProbe extends StatefulWidget {
  const _BuildProbe({super.key, required this.child});

  final Widget child;

  @override
  State<_BuildProbe> createState() => _BuildProbeState();
}

class _BuildProbeState extends State<_BuildProbe> {
  var builds = 0;
  var disposed = false;

  @override
  Widget build(BuildContext context) {
    builds++;
    return widget.child;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _PointerLog implements HitTestTarget {
  PointerDownEvent? down;
  HitTestEntry? entry;
  var hovers = 0;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerHoverEvent) hovers++;
    if (event is PointerDownEvent) {
      down = event;
      this.entry = entry;
    }
  }
}

class _AnnotatedTarget extends MouseTrackerAnnotation implements HitTestTarget {
  final events = _PointerLog();

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) =>
      events.handleEvent(event, entry);
}

class _HitTarget extends SingleChildRenderObjectWidget {
  const _HitTarget({super.key, required this.target, required super.child});

  final HitTestTarget target;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitTarget(target);
}

class _RenderHitTarget extends RenderProxyBox {
  _RenderHitTarget(this.target);

  final HitTestTarget target;
  HitTestEntry? lastEntry;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final hit = super.hitTestChildren(result, position: position);
    if (hit) {
      lastEntry = HitTestEntry(target);
      result.add(lastEntry!);
    }
    return hit;
  }
}

class _OnDispose extends StatefulWidget {
  const _OnDispose({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_OnDispose> createState() => _OnDisposeState();
}

class _OnDisposeState extends State<_OnDispose> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
