import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/document_viewer/native_file_page_scroll.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

const _header = ValueKey('native-page-header');
const _body = ValueKey('native-page-body');
const _right = ValueKey('native-page-right-tools');

void main() {
  fileControlTestSetup();
  for (final mode in fileControlAppearances) {
    testWidgets('$mode normal Premium root: real bridge ACK/clipping/retention',
        (tester) async {
      final bridge = NativeFilePageScrollBridge();
      final transport = _Transport();
      final editing = TextEditingController(text: 'retained draft');
      final gate = ValueNotifier(false);
      try {
        await mountFileControls(
            tester,
            PremiumScrollScope(
                enabled: true,
                child: StandaloneFilePage(
                  header: SizedBox(
                      key: _header,
                      height: 200,
                      child: Row(children: [
                        const Text('Identity'),
                        const Spacer(),
                        TextButton(
                            key: _right,
                            onPressed: () {},
                            child: const Text('Tools'))
                      ])),
                  body: ValueListenableBuilder<bool>(
                      valueListenable: gate,
                      builder: (_, blocked, child) =>
                          ScrollGestureGate(blocked: blocked, child: child!),
                      child: NativeFilePageScroll(
                          bridge: bridge,
                          child: SizedBox.expand(
                              key: _body,
                              child: TextField(controller: editing)))),
                )),
            mode: mode);
        bridge.attach(transport);
        expect(await bridge.install(kinetic: false), isTrue);
        final page =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        final initialHeader = tester.getRect(find.byKey(_header));
        final initialTools = tester.getRect(find.byKey(_right));
        final bodySize = tester.getSize(find.byKey(_body));
        final bodyElement = tester.element(find.byKey(_body));
        editing.selection = const TextSelection(baseOffset: 1, extentOffset: 6);
        final point =
            tester.getRect(find.byType(StandaloneFilePage)).bottomCenter -
                const Offset(0, 30);
        Future<void> input() async {
          await tester.sendEventToBinding(PointerScrollEvent(
              position: point, scrollDelta: const Offset(0, 1)));
          await tester.pump();
        }

        await input();
        expect(page.outerController.offset, 0,
            reason:
                'Native wrapper excludes both root Premium and Flutter wheel consumption');
        final first = transport.input(60);
        await tester.pump();
        expect((await first as Map)['actual'], 60);
        expect(page.outerController.offset, 60);
        expect(transport.moves, isEmpty);
        expect(tester.getRect(find.byKey(_header)).top, initialHeader.top - 60);
        expect(tester.getRect(find.byKey(_right)).top, initialTools.top - 60);
        expect(tester.getRect(find.byKey(_right)).right, initialTools.right);

        final down = transport.input(180);
        await tester.pump();
        expect(page.outerController.offset, 200);
        expect(transport.moves.single.delta, 40);
        transport.moves.last.reply.complete(40);
        await tester.pump();
        expect((await down as Map)['actual'], 180);
        expect(find.byKey(_header, skipOffstage: false).hitTestable(),
            findsNothing);
        expect(tester.getSize(find.byKey(_body)), bodySize);
        final fractional = transport.input(-1);
        transport.moves.last.reply.complete({'actual': -0.8, 'atStart': false});
        await tester.pump();
        expect((await fractional as Map)['actual'], -0.8);
        expect(page.outerController.offset, 200,
            reason:
                'Rounded interior movement is not permission to reveal chrome');
        final reverse = transport.input(-70);
        await tester.pump();
        expect(page.outerController.offset, 200);
        transport.moves.last.reply.complete(-40);
        await tester.pump();
        expect((await reverse as Map)['actual'], -70);
        expect(page.outerController.offset, 170);
        expect(tester.element(find.byKey(_body)), same(bodyElement));
        expect(editing.text, 'retained draft');
        expect(editing.selection,
            const TextSelection(baseOffset: 1, extentOffset: 6));

        // Deactivation filters the ENTIRE native target; stale DOM callbacks
        // cannot bypass the gate even though this renderer stays mounted.
        final late = transport.input(-30);
        await tester.pump();
        final lateMove = transport.moves.last;
        gate.value = true;
        await tester.pump();
        lateMove.reply.complete(0);
        await tester.pump();
        expect(await late, isNull);
        expect(page.outerController.offset, 170);
        expect(await transport.input(-20), isNull);
        expect(tester.takeException(), isNull);
      } finally {
        bridge.dispose();
        transport.finishPending();
        try {
          await unmountFileControls(tester);
        } finally {
          gate.dispose();
          editing.dispose();
        }
      }
    });
  }

  testWidgets('same controller navigation fences old ACK and old DOM message',
      (tester) async {
    final bridge = NativeFilePageScrollBridge();
    final transport = _Transport();
    try {
      bridge.bind(null, () => true);
      bridge.attach(transport);
      await bridge.install();
      final oldDocument = transport.document;
      final old = transport.input(-30);
      bridge.invalidate();
      await bridge.install();
      transport.moves.single.reply.complete(0);
      await tester.pump();
      expect(await old, isNull);
      expect(await transport.handler!([oldDocument, 1, -20, 'input']), isNull);
      final current = transport.input(-10);
      transport.moves.last.reply.complete(-10);
      await tester.pump();
      expect((await current as Map)['actual'], -10);
    } finally {
      bridge.dispose();
      transport.finishPending();
      await tester.pump();
    }
  });

  testWidgets(
      'control settlement never releases the real body consumption slot',
      (tester) async {
    final bridge = NativeFilePageScrollBridge();
    final transport = _Transport()..holdCancellation = true;
    try {
      bridge.bind(null, () => true);
      bridge.attach(transport);
      await bridge.install();
      final old = transport.input(-1);
      bridge.cancel();
      bridge.cancel();
      bridge.cancel();
      final next = transport.input(-2, gesture: 2);
      expect(transport.controls, hasLength(1));
      expect(transport.moves, hasLength(1));
      transport.controls.first.complete(null);
      await tester.pump();
      expect(transport.controls, hasLength(2),
          reason: 'one coalesced control follow-up');
      transport.controls.last.complete(null);
      await tester.pump();
      expect(transport.moves, hasLength(1),
          reason: 'body call is still actually in flight');
      transport.moves.first.reply.complete(0);
      await tester.pump();
      expect(await old, isNull);
      expect(transport.moves, hasLength(2));
      transport.moves.last.reply.complete({'actual': -1.6, 'atStart': false});
      await tester.pump();
      expect((await next as Map)['actual'], -1.6);
    } finally {
      bridge.dispose();
      transport.finishPending();
      await tester.pump();
    }
  });

  testWidgets('missing boundary evidence is not a successful body ACK',
      (tester) async {
    final bridge = NativeFilePageScrollBridge();
    final transport = _Transport();
    try {
      bridge.bind(null, () => true, devicePixelRatio: 1.25);
      bridge.attach(transport);
      await bridge.install();
      final rounded = transport.input(-0.01);
      transport.moves.last.reply.complete({'actual': -0.8, 'atStart': false});
      await tester.pump();
      expect((await rounded as Map)['actual'], -0.8);
      for (final invalid in [
        null,
        {'actual': 0},
        {'actual': 0, 'atStart': 'true'}
      ]) {
        final pending = transport.input(-1);
        transport.moves.last.reply.complete(invalid);
        await tester.pump();
        expect(await pending, isNull);
      }
    } finally {
      bridge.dispose();
      transport.finishPending();
      await tester.pump();
    }
  });

  for (final mode in fileControlAppearances) {
    testWidgets(
        '$mode Office wheel hook preserves targets and gated parent scrolling',
        (tester) async {
      final received = <Offset>[];
      final originals = <PointerScrollEvent>[];
      final resolved = <PointerScrollEvent>[];
      final targetKey = GlobalKey();
      final gate = ValueNotifier(false);
      var clicks = 0;
      var panStarts = 0;
      var panUpdates = 0;
      try {
        await mountFileControls(
            tester,
            PremiumScrollScope(
                enabled: true,
                child: StandaloneFilePage(
                  header: const SizedBox(height: 100),
                  body: ValueListenableBuilder<bool>(
                    valueListenable: gate,
                    builder: (_, blocked, child) =>
                        ScrollGestureGate(blocked: blocked, child: child!),
                    child: PremiumScrollExclusion(
                        child: NativeFilePageHeaderWheel(
                      child: StandaloneFilePageBoundary(
                        enabled: true,
                        child: Builder(
                            builder: (context) => Listener(
                                  key: targetKey,
                                  behavior: HitTestBehavior.opaque,
                                  // Faithful input seam: the real Windows native widget's
                                  // resolver/channel path is verified in wheel_scope_test.
                                  // Never simulate the old hit proxy by changing this event.
                                  onPointerSignal: (signal) {
                                    if (signal is! PointerScrollEvent) return;
                                    originals.add(signal);
                                    final scope =
                                        WindowsWebViewWheelScope.maybeOf(
                                            context);
                                    GestureBinding
                                        .instance.pointerSignalResolver
                                        .register(signal, (_) {
                                      resolved.add(signal);
                                      received.add(scope?.transform(signal) ??
                                          signal.scrollDelta);
                                    });
                                  },
                                  onPointerDown: (_) => clicks++,
                                  onPointerPanZoomStart: (_) => panStarts++,
                                  onPointerPanZoomUpdate: (_) => panUpdates++,
                                  child: const SizedBox.expand(key: _body),
                                )),
                      ),
                    )),
                  ),
                )),
            mode: mode);
        final page =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        final point =
            tester.getRect(find.byType(StandaloneFilePage)).bottomCenter -
                const Offset(0, 30);
        final target = targetKey.currentContext!.findRenderObject();
        void expectOriginalTarget() {
          final hit = tester.hitTestOnBinding(point);
          expect(hit.path.where((entry) => identical(entry.target, target)),
              hasLength(1));
          expect(targetKey.currentContext!.findRenderObject(), same(target));
        }

        Future<void> wheel(Offset delta) async {
          await tester.sendEventToBinding(PointerScrollEvent(
            position: point,
            scrollDelta: delta,
            device: 19,
            timeStamp: const Duration(seconds: 7),
          ));
          await tester.pump();
        }

        expectOriginalTarget();
        await wheel(const Offset(0, 40));
        expect(page.outerController.offset, 40,
            reason:
                'Unsaturated header proves the parent did not consume twice');
        expect(received, [Offset.zero]);
        page.outerController.jumpTo(0);
        await tester.pump();
        received.clear();
        originals.clear();
        resolved.clear();
        await wheel(const Offset(3.25, 140));
        expect(page.outerController.offset, 100);
        expect(received, [const Offset(3.25, 40)]);
        expect(originals.single.scrollDelta, const Offset(3.25, 140));
        expect(resolved.single, same(originals.single));
        expect(resolved.single.device, 19);
        expect(resolved.single.timeStamp, const Duration(seconds: 7));
        expect(resolved.single.position, point);
        expectOriginalTarget();
        await wheel(const Offset(0, -50));
        expect(page.outerController.offset, 100,
            reason:
                'Opaque Office cannot acknowledge actual reverse canvas travel');
        expect(received.last, const Offset(0, -50));
        await wheel(const Offset(30, 0));
        expect(received.last, const Offset(30, 0));
        for (final keys in [
          (LogicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlLeft),
          (LogicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaLeft),
          (LogicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftLeft),
        ]) {
          await tester.sendKeyDownEvent(keys.$1, physicalKey: keys.$2);
          try {
            await wheel(const Offset(0, 25));
            expect(received.last, const Offset(0, 25));
          } finally {
            await tester.sendKeyUpEvent(keys.$1, physicalKey: keys.$2);
          }
        }
        await tester.tapAt(point, kind: PointerDeviceKind.mouse);
        expect(clicks, 1);
        final gesture =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await gesture.panZoomStart(point);
        try {
          await gesture.panZoomUpdate(point,
              pan: const Offset(0, -20), scale: 1.2, rotation: 0.1);
          expect(panStarts, 1);
          expect(panUpdates, 1);
        } finally {
          await gesture.panZoomEnd();
        }
        expectOriginalTarget();
        expect(received, hasLength(6),
            reason: 'pan/pinch/click never enter the wheel hook');

        page.outerController.jumpTo(0);
        gate.value = true;
        await tester.pump();
        final count = received.length;
        await wheel(const Offset(0, 40));
        await tester.pump(const Duration(seconds: 1));
        expect(received, hasLength(count),
            reason: 'gate prevents the hook callback');
        expect(originals, hasLength(count),
            reason: 'native listener is also filtered');
        expect(page.outerController.offset, greaterThan(0),
            reason: 'parent owns gated input');
        expect(targetKey.currentContext!.findRenderObject(), same(target));
        gate.value = false;
        await tester.pump();
        expectOriginalTarget();
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await unmountFileControls(tester);
        } finally {
          gate.dispose();
        }
      }
    });
  }
}

class _Move {
  _Move(this.delta);
  final double delta;
  final reply = Completer<Object?>();
}

class _Transport extends Fake implements InAppWebViewController {
  JavaScriptHandlerCallback? handler;
  String document = '';
  final moves = <_Move>[];
  final controls = <Completer<Object?>>[];
  bool holdCancellation = false;
  Future<dynamic> input(double delta, {int gesture = 1}) async =>
      handler!([document, gesture, delta, 'input']);
  void finishPending() {
    holdCancellation = false;
    for (final pending in [...controls, ...moves.map((move) => move.reply)]) {
      if (!pending.isCompleted) pending.complete(null);
    }
  }

  @override
  void addJavaScriptHandler(
      {required String handlerName,
      required JavaScriptHandlerCallback callback}) {
    handler = callback;
  }

  @override
  JavaScriptHandlerCallback? removeJavaScriptHandler(
          {required String handlerName}) =>
      handler;
  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    if (source.contains('const documentId =')) {
      final quoted = RegExp(r'const documentId = ("[^"]+");')
          .firstMatch(source)!
          .group(1)!;
      document = jsonDecode(quoted) as String;
      return true;
    }
    if (source.contains('?.consumeVertical(')) {
      final args = source.substring(
          source.indexOf('?.consumeVertical(') + '?.consumeVertical('.length,
          source.lastIndexOf(');'));
      final values = jsonDecode('[$args]') as List;
      final move = _Move((values[2] as num).toDouble());
      moves.add(move);
      // Numeric fixture replies represent the original verified-boundary
      // cases. Structured replies exercise interior rounding and bad metadata.
      return move.reply.future.then(
          (value) => value is num ? {'actual': value, 'atStart': true} : value);
    }
    if (source.contains('?.cancel(') && holdCancellation) {
      final reply = Completer<Object?>();
      controls.add(reply);
      return reply.future;
    }
    return null;
  }
}
