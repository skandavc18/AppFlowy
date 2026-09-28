import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/platform_view_lifecycle.dart';

void main() {
  testWidgets(
      'no scope preserves exact filtered wheel channel and owns resolver',
      (tester) async {
    final f = await _WheelFixture.mount(tester);
    await f.wheel(const Offset(12.25, 0.125));
    expect(f.scrolls, [
      [0.0, -0.125]
    ]);
    expect(f.parent.offset, 0);
    expect(
        f.calls.where((call) => call.method == 'querySiteGesturePolicyState'),
        isEmpty);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets(
      'scope consumes header before filtering and prevents parent double wheel',
      (tester) async {
    var remainingHeader = 25.0;
    final received = <PointerScrollEvent>[];
    final f = await _WheelFixture.mount(tester, transform: (event) {
      received.add(event);
      if (HardwareKeyboard.instance.isControlPressed ||
          event.scrollDelta.dy <= 0) {
        return event.scrollDelta;
      }
      final consumed = event.scrollDelta.dy.clamp(0.0, remainingHeader);
      remainingHeader -= consumed;
      return Offset(event.scrollDelta.dx, event.scrollDelta.dy - consumed);
    });
    final target = tester.renderObject(find.byType(CustomPlatformView));
    final hit = tester.hitTestOnBinding(f.point);
    expect(hit.path.any((entry) => identical(entry.target, target)), isTrue);
    await f.wheel(const Offset(12.25, 10));
    expect(f.scrolls, isEmpty);
    expect(remainingHeader, 15);
    await f.wheel(const Offset(12.25, 20));
    expect(f.scrolls, [
      [0.0, -5.0]
    ]);
    expect(remainingHeader, 0);
    await f.wheel(const Offset(12.25, -8));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await f.wheel(const Offset(12.25, 20));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    expect(f.scrolls, [
      [0.0, -5.0],
      [0.0, 8.0],
      [0.0, -20.0]
    ]);
    expect(received.map((event) => event.scrollDelta), [
      const Offset(12.25, 10),
      const Offset(12.25, 20),
      const Offset(12.25, -8),
      const Offset(12.25, 20),
    ]);
    expect(received.map((event) => event.timeStamp),
        everyElement(const Duration(seconds: 1)));
    expect(f.parent.offset, 0);
    expect(tester.renderObject(find.byType(CustomPlatformView)), same(target));
    // The scope is inherited-only: the original native target still re-hits,
    // so a later native trackpad query is not invalidated by wrapper identities.
    await tester.sendEventToBinding(PointerPanZoomStartEvent(
        pointer: 7,
        device: 7,
        position: f.point,
        timeStamp: const Duration(seconds: 2)));
    await tester.pump();
    await tester.sendEventToBinding(PointerPanZoomUpdateEvent(
        pointer: 7,
        device: 7,
        position: f.point,
        pan: const Offset(0, -20),
        panDelta: const Offset(0, -20),
        timeStamp: const Duration(milliseconds: 2010)));
    await tester.sendEventToBinding(PointerPanZoomEndEvent(
        pointer: 7,
        device: 7,
        position: f.point,
        timeStamp: const Duration(milliseconds: 2020)));
    expect(received, hasLength(4));
    expect(
        f.calls.where((call) => call.method == 'querySiteGesturePolicyState'),
        hasLength(1));
    expect(
        f.calls
            .where((call) => call.method == 'setPointerUpdate')
            .map((call) => (call.arguments as List)[6]),
        [2000000, 2010000, 2020000]);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets(
      'blocked native delivery leaves scope untouched and Flutter scrolls',
      (tester) async {
    var transforms = 0;
    final f =
        await _WheelFixture.mount(tester, blocked: true, transform: (event) {
      transforms++;
      return Offset.zero;
    });
    await f.wheel(const Offset(0, 40));
    expect(transforms, 0);
    expect(f.scrolls, isEmpty);
    expect(f.parent.offset, 40);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('both disabled axes without scope leave wheel to Flutter',
      (tester) async {
    final f = await _WheelFixture.mount(tester, bothDisabled: true);
    await f.wheel(const Offset(0, 40));
    expect(f.scrolls, isEmpty);
    expect(f.parent.offset, 40);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('both disabled axes with scope consume only in winning callback',
      (tester) async {
    final deltas = <Offset>[];
    final f = await _WheelFixture.mount(tester, bothDisabled: true,
        transform: (event) {
      deltas.add(event.scrollDelta);
      return event.scrollDelta;
    });
    await f.wheel(const Offset(12.25, 40));
    expect(deltas, [const Offset(12.25, 40)]);
    expect(f.scrolls, isEmpty);
    expect(f.parent.offset, 0);
    await f.dispose();
  }, timeout: platformViewTestTimeout);
}

class _WheelFixture {
  _WheelFixture(this.tester);
  final WidgetTester tester;
  final parent = ScrollController();
  final calls = <MethodCall>[];
  CustomPlatformViewController? native;
  final Zone _ownerZone = Zone.current;
  Zone? _disposalZone;
  bool _disposed = false;
  late Offset point;
  static const manager =
      MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
  static const view =
      MethodChannel('com.pichillilorenzo/custom_platform_view_93');
  static const events =
      MethodChannel('com.pichillilorenzo/custom_platform_view_93_events');

  List<dynamic> get scrolls => calls
      .where((call) => call.method == 'setScrollDelta')
      .map((call) => call.arguments)
      .toList();

  static Future<_WheelFixture> mount(
    WidgetTester tester, {
    Offset Function(PointerScrollEvent)? transform,
    bool blocked = false,
    bool bothDisabled = false,
  }) async {
    final f = _WheelFixture(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    addTearDown(() async {
      try {
        if (!f._disposed) await f.dispose();
      } finally {
        f.parent.dispose();
        messenger.setMockMethodCallHandler(manager, null);
        messenger.setMockMethodCallHandler(view, null);
        messenger.setMockMethodCallHandler(events, null);
      }
    });
    messenger.setMockMethodCallHandler(manager,
        (call) async => call.method == 'createInAppWebView' ? 93 : null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(view, (call) async {
      f.calls.add(call);
      if (call.method == 'querySiteGesturePolicyState') {
        return {'status': 'browser', 'epoch': 7};
      }
      return null;
    });
    Widget child = CustomPlatformView(creationParams: {
      'initialSettings': {
        'disableHorizontalScroll': true,
        'disableVerticalScroll': bothDisabled,
      },
    });
    if (transform != null) {
      child = WindowsWebViewWheelScope(transform: transform, child: child);
    }
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
      width: 300,
      height: 400,
      child: SingleChildScrollView(
        controller: f.parent,
        child: Column(children: [
          // Models suppressed native delivery without importing application code.
          IgnorePointer(
              ignoring: blocked,
              child: SizedBox.square(dimension: 300, child: child)),
          const SizedBox(height: 800),
        ]),
      ),
    ))));
    f.native = tester
        .state<CustomPlatformViewState>(find.byType(CustomPlatformView))
        .controller;
    await awaitPlatformViewReady(tester, f.native!);
    await tester.pumpAndSettle();
    f.point = tester.getCenter(find.byType(CustomPlatformView));
    return f;
  }

  Future<void> wheel(Offset delta) async {
    await tester.sendEventToBinding(PointerScrollEvent(
        position: point,
        scrollDelta: delta,
        timeStamp: const Duration(seconds: 1)));
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
      await awaitPlatformViewDisposal(tester, controller,
          ownerZone: _disposalZone!);
    }
    _disposed = true;
    expect(tester.takeException(), isNull);
  }
}
