import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_scroll_physics.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final kinetic in [false, true]) {
    testWidgets(
        'inactive custom viewers leave wheel and trackpad to page '
        '(kinetic: $kinetic)', (tester) async {
      final page = ScrollController();
      final blocked = ValueNotifier(true);
      addTearDown(page.dispose);
      addTearDown(blocked.dispose);
      var wheels = 0;
      var pans = 0;
      var clicks = 0;
      final childKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumScrollScope(
            enabled: kinetic,
            child: SingleChildScrollView(
              controller: page,
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: blocked,
                    builder: (_, value, child) => ScrollGestureGate(
                      blocked: value,
                      child: child!,
                    ),
                    child: PremiumScrollExclusion(
                      child: PdfEmbedScrollGuard(
                        onPointerSignal: (_) => wheels++,
                        onPointerPanZoomUpdate: (_) => pans++,
                        child: GestureDetector(
                          key: childKey,
                          behavior: HitTestBehavior.opaque,
                          onTap: () => clicks++,
                          child: const SizedBox(width: 500, height: 320),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      final element = childKey.currentContext;
      final position = tester.getCenter(find.byKey(childKey));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 40),
        ),
      );
      await tester.pumpAndSettle();
      expect(page.offset, closeTo(40, 0.11));
      expect(wheels, 0);
      await _pan(tester, position);
      expect(page.offset, greaterThan(40));
      expect(pans, 0);
      page.jumpTo(0);
      await tester.pump();
      // The gate proxies pointer targets but still delivers the actual click.
      await tester.tapAt(position);
      await tester.pumpAndSettle();
      expect(clicks, 1);

      blocked.value = false;
      await tester.pump();
      expect(childKey.currentContext, same(element));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 40),
        ),
      );
      await _pan(tester, position);
      expect(wheels, 1);
      expect(pans, greaterThan(0));
      expect(page.offset, 0);
      blocked.value = true;
      await tester.pump();
      final previousPans = pans;
      await _pan(tester, position);
      expect(page.offset, greaterThan(0));
      expect(pans, previousPans);
      expect(childKey.currentContext, same(element));
    });
  }

  testWidgets('text fields retain inside-tap identity through the gate', (
    tester,
  ) async {
    final focus = FocusNode();
    final text = TextEditingController();
    addTearDown(focus.dispose);
    addTearDown(text.dispose);
    var outside = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ScrollGestureGate(
              blocked: true,
              child: SizedBox(
                width: 260,
                child: TextField(
                  controller: text,
                  focusNode: focus,
                  onTapOutside: (_) => outside++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(TextField)));
    await tester.pump();
    expect(outside, 0);
    expect(focus.hasPrimaryFocus, isTrue);
    tester.testTextInput.enterText('still editable');
    await tester.pump();
    expect(text.text, 'still editable');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('scaled clicks and stable mouse annotations survive filtering', (
    tester,
  ) async {
    Offset? localPosition;
    var enters = 0;
    var exits = 0;
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Padding(
          padding: const EdgeInsets.only(left: 90, top: 70),
          child: Align(
            alignment: Alignment.topLeft,
            child: Transform.scale(
              scale: 1.5,
              alignment: Alignment.topLeft,
              child: ScrollGestureGate(
                blocked: true,
                child: MouseRegion(
                  onEnter: (_) => enters++,
                  onExit: (_) => exits++,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Listener(
                      onPointerDown: (event) =>
                          localPosition = event.localPosition,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => clicks++,
                        child: const SizedBox(
                          key: ValueKey('transformed-target'),
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
        ),
      ),
    );
    final point =
        tester.getCenter(find.byKey(const ValueKey('transformed-target')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(point);
    await tester.pump();
    for (var move = 0; move < 5; move++) {
      await mouse.moveTo(point + Offset(move.toDouble(), 0));
      await tester.pump();
    }
    expect(enters, 1);
    expect(exits, 0);
    await tester.tapAt(point);
    expect(localPosition!.dx, closeTo(40, 0.001));
    expect(localPosition!.dy, closeTo(30, 0.001));
    expect(clicks, 1);
    await mouse.removePointer();
  });
}

Future<void> _pan(WidgetTester tester, Offset position) async {
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(
      pointer: 83,
      device: 83,
      position: position,
    ),
  );
  for (var step = 1; step <= 3; step++) {
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 83,
        device: 83,
        position: position,
        pan: Offset(0, -20.0 * step),
        panDelta: const Offset(0, -20),
        timeStamp: Duration(milliseconds: step * 10),
      ),
    );
  }
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      pointer: 83,
      device: 83,
      position: position,
      pan: const Offset(0, -60),
      timeStamp: const Duration(milliseconds: 200),
    ),
  );
  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      pointer: 83,
      device: 83,
      position: position,
      timeStamp: const Duration(milliseconds: 201),
    ),
  );
  await tester.pumpAndSettle();
}
