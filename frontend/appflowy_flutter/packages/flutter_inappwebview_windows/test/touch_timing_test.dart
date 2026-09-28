import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/platform_view_lifecycle.dart';

void main() {
  testWidgets('vertical classification retains original start and known age',
      (tester) async {
    final fixture = await _Fixture.mount(tester, history: true);
    await fixture.start(1000000);
    await fixture.move(1010000, const Offset(0, -5));
    expect(fixture.packets, isEmpty);
    await fixture.move(1030000, const Offset(0, -20));
    await fixture.end(1040000);
    expect(fixture.packets.map((packet) => packet[6]),
        [1000000, 1030000, 1040000]);
    expect(fixture.packets.map((packet) => packet[7]), [30000, 0, 0]);
    expect(fixture.packets.map((packet) => packet[3]), [150.0, 130.0, 130.0]);
    await fixture.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('delayed channel replies never retime or reorder input samples',
      (tester) async {
    final fixture = await _Fixture.mount(tester);
    final held = fixture.pointerReply = Completer<void>();
    const origin = 9000000000000000;
    await fixture.start(origin);
    await fixture.move(origin + 10000, const Offset(0, -10));
    expect(fixture.packets, isEmpty); // Below the no-click contact threshold.
    await fixture.move(origin + 20000, const Offset(0, -25));
    await fixture.move(origin + 30000, const Offset(0, -45));
    await fixture.end(origin + 35000);
    // The host native queue, not Dart futures, serializes CDP processing.
    expect(fixture.packets.map((packet) => packet[6]), [
      origin,
      origin + 20000,
      origin + 30000,
      origin + 35000
    ]);
    expect(fixture.packets.map((packet) => packet[3]),
      [150.0, 125.0, 105.0, 105.0]);
    expect(fixture.packets.map((packet) => packet[7]), [20000, 0, 0, 0]);
    await tester.pump(const Duration(seconds: 2));
    held.complete();
    await tester.pump();
    expect(fixture.packets, hasLength(4));
    await fixture.dispose();
  }, timeout: platformViewTestTimeout);

  for (final history in [false, true]) {
    testWidgets('navigation cancels input without waiting for load ($history)',
        (tester) async {
      final fixture = await _Fixture.mount(tester, history: history);
      await fixture.start(1000000);
      await fixture.move(1010000, const Offset(0, -20));
      await fixture.navigationStarting();
      expect(fixture.packets.last[1], InAppWebViewPointerEventKind.leave.index);
      final count = fixture.packets.length;
      await fixture.move(1020000, const Offset(0, -40));
      await fixture.end(1030000);
      expect(fixture.packets, hasLength(count));
      // NavigationCompleted has deliberately NOT been delivered. A new valid
      // gesture is usable; network load completion is not an input gate.
      await fixture.start(2000000);
      await fixture.move(2010000, const Offset(0, -20));
      await fixture.end(2020000);
      expect(fixture.packets.length, count + 3);
      expect(fixture.packets.last[1], InAppWebViewPointerEventKind.up.index);
      await fixture.dispose();
    }, timeout: platformViewTestTimeout);
  }

  testWidgets('horizontal history and pinch never synthesize touch contacts',
      (tester) async {
    final fixture = await _Fixture.mount(tester, history: true);
    await fixture.start(1000000);
    await fixture.move(1010000, const Offset(80, 0));
    await fixture.end(1020000);
    await tester.pumpAndSettle();
    expect(fixture.packets, isEmpty);
    await fixture.start(2000000);
    await fixture.move(2010000, Offset.zero, scale: 1.2);
    await fixture.end(2020000);
    expect(fixture.packets, isEmpty);
    expect(
        fixture.calls
            .where((call) => call.method == 'setZoomScale')
            .single
            .arguments,
        closeTo(1.2, 0.0001));
    await fixture.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('touchscreen retains six arguments and its original positions',
      (tester) async {
    final fixture = await _Fixture.mount(tester);
    final touch =
        await tester.startGesture(fixture.point, kind: PointerDeviceKind.touch);
    await touch.moveBy(const Offset(2, -15));
    await touch.up();
    expect(fixture.packets, hasLength(3));
    expect(fixture.packets.map((packet) => packet.length), everyElement(6));
    expect(fixture.packets.map((packet) => packet[2]), [150.0, 152.0, 152.0]);
    expect(fixture.packets.map((packet) => packet[3]), [150.0, 135.0, 135.0]);
    expect(fixture.packets.map((packet) => packet[0]),
        isNot(contains(0x3ffffffe)));
    await fixture.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('wheel preserves filtered deltas and cancels an interrupted pan',
      (tester) async {
    final fixture = await _Fixture.mount(tester);
    await fixture.start(1000000);
    await fixture.move(1010000, const Offset(0, -20));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: fixture.point,
      scrollDelta: const Offset(12.25, 0.125),
      timeStamp: const Duration(seconds: 2),
    ));
    expect(fixture.packets.last[1], InAppWebViewPointerEventKind.leave.index);
    expect(
        fixture.calls
            .where((call) => call.method == 'setScrollDelta')
            .single
            .arguments,
        [0.0, -0.125]);
    await fixture.end(2020000);
    expect(
        fixture.packets.where(
            (packet) => packet[1] == InAppWebViewPointerEventKind.up.index),
        isEmpty);
    await fixture.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('replacement gesture ignores the previous pointer release',
      (tester) async {
    final fixture = await _Fixture.mount(tester);
    await fixture.start(1000000);
    await fixture.move(1010000, const Offset(0, -20));
    await fixture.start(2000000, pointer: 8);
    expect(fixture.packets.map((packet) => packet[1]), [
      InAppWebViewPointerEventKind.down.index,
      InAppWebViewPointerEventKind.update.index,
      InAppWebViewPointerEventKind.leave.index,
    ]);
    await fixture.end(1020000);
    expect(fixture.packets, hasLength(3));
    await fixture.move(2010000, const Offset(0, -10), pointer: 8);
    expect(fixture.packets, hasLength(3));
    await fixture.move(2020000, const Offset(0, -20), pointer: 8);
    await fixture.end(2030000, pointer: 8);
    expect(fixture.packets.map((packet) => packet[6]),
        [1000000, 1010000, 1010000, 2000000, 2020000, 2030000]);
    expect(fixture.packets.last[6], 2030000);
    expect(fixture.packets.last[1], InAppWebViewPointerEventKind.up.index);
    await fixture.dispose();
  }, timeout: platformViewTestTimeout);
}

class _Fixture {
  _Fixture(this.tester);
  static const _id = 81;
  static const _manager =
      MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
  static const _view =
      MethodChannel('com.pichillilorenzo/custom_platform_view_$_id');
  static const _events =
      MethodChannel('com.pichillilorenzo/custom_platform_view_${_id}_events');
  final WidgetTester tester;
  final calls = <MethodCall>[];
  Completer<void>? pointerReply;
  CustomPlatformViewController? native;
  final Zone _ownerZone = Zone.current;
  Zone? _disposalZone;
  bool _disposed = false;
  Offset previousPan = Offset.zero;

  Offset get point => tester.getCenter(find.byType(CustomPlatformView));
  List<List<dynamic>> get packets => calls
      .where((call) => call.method == 'setPointerUpdate')
      .map((call) => call.arguments as List<dynamic>)
      .toList();

  static Future<_Fixture> mount(WidgetTester tester,
      {bool history = false}) async {
    final fixture = _Fixture(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_manager,
        (call) async => call.method == 'createInAppWebView' ? _id : null);
    messenger.setMockMethodCallHandler(_events, (_) async => null);
    messenger.setMockMethodCallHandler(_view, (call) async {
      fixture.calls.add(call);
      if (call.method == 'querySiteGesturePolicyState') {
        return {'status': 'browser', 'epoch': 7};
      }
      if (call.method == 'getHistoryState') {
        return {'back': false, 'forward': false, 'loading': false};
      }
      if (call.method == 'setPointerUpdate') await fixture.pointerReply?.future;
      return null;
    });
    addTearDown(() async {
      try {
        if (!fixture._disposed) {
          if (fixture.pointerReply != null && !fixture.pointerReply!.isCompleted) {
            fixture.pointerReply!.complete();
          }
          await fixture.dispose();
        }
      } finally {
        messenger.setMockMethodCallHandler(_manager, null);
        messenger.setMockMethodCallHandler(_view, null);
        messenger.setMockMethodCallHandler(_events, null);
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: Center(
          child: SizedBox.square(
        dimension: 300,
        child: CustomPlatformView(creationParams: {
          'initialSettings': {
            'disableHorizontalScroll': true,
            'allowsBackForwardNavigationGestures': history,
          },
        }),
      )),
    ));
    fixture.native = tester.state<CustomPlatformViewState>(
      find.byType(CustomPlatformView)).controller;
    await awaitPlatformViewReady(tester, fixture.native!);
    await tester.pumpAndSettle();
    return fixture;
  }

  Future<void> start(int micros, {int pointer = 7}) async {
    previousPan = Offset.zero;
    await tester.sendEventToBinding(PointerPanZoomStartEvent(
      pointer: pointer,
      device: pointer,
      position: point,
      timeStamp: Duration(microseconds: micros),
    ));
    await tester.pump(); // Deliver the policy reply, without changing input time.
  }

  Future<void> move(int micros, Offset pan,
      {int pointer = 7, double scale = 1}) async {
    await tester.sendEventToBinding(PointerPanZoomUpdateEvent(
      pointer: pointer,
      device: pointer,
      position: point,
      timeStamp: Duration(microseconds: micros),
      pan: pan,
      panDelta: pan - previousPan,
      scale: scale,
    ));
    previousPan = pan;
  }

  Future<void> end(int micros, {int pointer = 7}) => tester.sendEventToBinding(
        PointerPanZoomEndEvent(
          pointer: pointer,
          device: pointer,
          position: point,
          timeStamp: Duration(microseconds: micros),
        ),
      );

  Future<void> navigationStarting() async {
    tester.binding.channelBuffers.push(
      _events.name,
      const StandardMethodCodec()
          .encodeSuccessEnvelope({'type': 'navigationStarting'}),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final mountedView = find.byType(CustomPlatformView, skipOffstage: false);
    final isMounted = mountedView.evaluate().isNotEmpty;
    if (native == null && isMounted) {
      native = tester.state<CustomPlatformViewState>(mountedView).controller;
    }
    _disposalZone ??= isMounted ? Zone.current : _ownerZone;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final controller = native;
    if (controller != null) {
      await awaitPlatformViewDisposal(tester, controller, ownerZone: _disposalZone!);
    }
    _disposed = true;
    expect(tester.takeException(), isNull);
  }
}
