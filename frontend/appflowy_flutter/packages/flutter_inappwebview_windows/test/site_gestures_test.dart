import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';

import 'support/platform_view_lifecycle.dart';

void main() {
  testWidgets('automatic site pinch and horizontal pan bypass browser/history',
      (tester) async {
    final f = await _Fixture.mount(tester);
    await f.start();
    await f.move(10000, const Offset(20, 0), scale: 1.5);
    await f.move(20000, const Offset(30, 10), scale: 1.5);
    await f.end(30000);
    expect(f.callsFor('querySiteGesturePolicyState'), hasLength(1));
    expect(f.callsFor('setZoomScale'), isEmpty);
    expect(f.callsFor('navigateHistory'), isEmpty);
    expect(f.packets.map((p) => p.length), [10, 10, 10, 8]);
    final start = f.packets[0];
    final first = f.packets[1];
    final last = f.packets[2];
    expect((start[9] as double) - (start[3] as double), 48);
    expect((first[9] as double) - (first[3] as double), 72);
    expect(last[2], (first[2] as double) + 10);
    expect(last[3], (first[3] as double) + 10);
    expect(f.packets.map((p) => p[6]), [1000000, 1010000, 1020000, 1030000]);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets(
      'late pinch uses the last actual contact time, not original start',
      (tester) async {
    final f = await _Fixture.mount(tester);
    await f.start();
    await f.move(10000, const Offset(20, 0));
    await f.move(20000, const Offset(20, 0)); // no dispatched movement
    await f.move(30000, const Offset(30, 0), scale: 1.5);
    final pairs = f.packets.where((p) => p.length == 10).toList();
    expect(pairs, hasLength(2));
    expect(pairs[0][1], InAppWebViewPointerEventKind.down.index);
    expect(pairs[0][6], 1010000);
    expect(pairs[0][7], 20000);
    expect(pairs[1][6], 1030000);
    // Native queue tests assert touchCancel ACK precedes this paired Start.
    expect(f.callsFor('setZoomScale'), isEmpty);
    await f.end(40000);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('a tiny gesture never starts a click-producing contact',
      (tester) async {
    final f = await _Fixture.mount(tester);
    await f.start();
    await f.move(10000, const Offset(1, 1), scale: 1.005);
    await f.end(20000);
    expect(f.packets, isEmpty);
    expect(f.callsFor('setPointerButton'), isEmpty);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('article history and browser zoom still work', (tester) async {
    final f = await _Fixture.mount(tester, site: false);
    await f.start();
    await f.move(10000, const Offset(120, 0));
    await f.end(20000);
    await tester.pumpAndSettle();
    expect(f.callsFor('navigateHistory').single.arguments, false);
    expect(f.packets, isEmpty);
    // A successful native traversal sends navigationStarting/Completed; its
    // method reply alone does not mean the destination has arrived/painted.
    await f.navigation();
    f.currentPage = 0;
    await f.navigationCompleted();
    await tester.pumpAndSettle();
    expect(f.history.isActive, isFalse);
    expect(f.history.isSettling, isFalse);
    await f.start(origin: 2000000);
    await f.move(10000, Offset.zero, scale: 1.25);
    await f.end(20000);
    expect(f.callsFor('setZoomScale').single.arguments, 1.25);
    expect(f.packets, isEmpty);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('pending policy keeps only latest sample with its original time',
      (tester) async {
    final f = await _Fixture.mount(tester);
    f.policy = Completer<bool?>();
    await f.start();
    for (var i = 1; i <= 100; i++) {
      await f.move(i * 100, Offset(i / 5, 0), scale: 1 + i / 100);
    }
    expect(f.packets, isEmpty);
    expect(f.callsFor('querySiteGesturePolicyState'), hasLength(1));
    f.policy!.complete(true);
    await tester.pump();
    expect(f.packets, hasLength(2));
    expect(f.packets[0][6], 1000000);
    expect(f.packets[1][6], 1010000);
    expect(f.packets[0][7] as int, greaterThanOrEqualTo(10000));
    expect(f.packets[1][7] as int, greaterThanOrEqualTo(0));
    await f.end(20000);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  for (final interruption in ['navigation', 'end', 'hidden']) {
    testWidgets('$interruption invalidates a pending policy without replay',
        (tester) async {
      final f = await _Fixture.mount(tester);
      f.policy = Completer<bool?>();
      await f.start();
      await f.move(10000, const Offset(120, 0), scale: 1.5);
      switch (interruption) {
        case 'navigation':
          await f.navigation();
          break;
        case 'end':
          await f.end(20000);
          break;
        case 'hidden':
          f.index.value = 1;
          await tester.pump();
          break;
      }
      f.policy!.complete(true);
      await tester.pump();
      expect(f.packets, isEmpty);
      expect(f.callsFor('setZoomScale'), isEmpty);
      expect(f.callsFor('navigateHistory'), isEmpty);
      expect(f.callsFor('cancelTrackpadGesture'), isNotEmpty);
      await f.dispose();
    }, timeout: platformViewTestTimeout);
  }

  testWidgets(
      'timed-out query recovers only fresh samples without history or zoom',
      (tester) async {
    final f = await _Fixture.mount(tester);
    f.policy = Completer<dynamic>();
    await f.start();
    await f.move(10000, const Offset(120, 0), scale: 1.5);
    await tester.pump(const Duration(milliseconds: 151));
    await f.move(200000, const Offset(240, 0), scale: 2);
    expect(f.packets, isEmpty);
    expect(f.callsFor('siteGestureFallbackReady'), isEmpty);
    expect(f.callsFor('cancelTrackpadGesture'), isEmpty);
    f.policy!
        .complete(false); // Late 'ordinary' answer cannot authorize history.
    await tester.pump();
    expect(f.packets, isEmpty);
    await f.move(210000, const Offset(250, 0), scale: 2);
    await tester.pump(); // State-only readiness, not a second Runtime.evaluate.
    await f.move(220000, const Offset(260, 0), scale: 2); // Fresh baseline.
    expect(f.packets, isEmpty);
    await f.move(230000, const Offset(280, 0), scale: 2); // Actual 20px pan.
    expect(f.packets, hasLength(2));
    expect(f.packets.first[6], 1220000);
    expect(f.packets.last[2], (f.packets.first[2] as double) + 20);
    expect(f.packets.map((p) => p.length), [9, 9]);
    expect(f.packets.map((p) => p.last), [f.epoch, f.epoch]);
    await f.move(240000, const Offset(280, 0), scale: 2.4);
    expect(f.packets.where((p) => p.length == 11), hasLength(2));
    await f.end(250000);
    expect(f.callsFor('querySiteGesturePolicyState'), hasLength(1));
    expect(f.callsFor('setZoomScale'), isEmpty);
    expect(f.callsFor('navigateHistory'), isEmpty);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('busy unknown retries state on new samples with one actual probe',
      (tester) async {
    final f = await _Fixture.mount(tester);
    f.policy = Completer<dynamic>()
      ..complete({'status': 'indeterminate', 'epoch': f.epoch});
    f.readyReply = Completer<bool?>();
    await f.start();
    for (var i = 1; i <= 100; i++) {
      await f.move(i * 1000, Offset(0, -i.toDouble()));
    }
    expect(f.callsFor('siteGestureFallbackReady'), hasLength(1));
    expect(f.packets, isEmpty);
    f.readyReply!.complete(false);
    await tester.pump();
    f.readyReply = Completer<bool?>()..complete(true);
    await f.move(110000, const Offset(0, -110));
    await tester.pump();
    await f.move(120000, const Offset(0, -120));
    await f.move(130000, const Offset(0, -140));
    expect(f.packets, hasLength(2));
    expect(f.packets.first[6], 1120000);
    expect(f.packets.last[3], (f.packets.first[3] as double) - 20);
    expect(f.callsFor('querySiteGesturePolicyState'), hasLength(1));
    expect(f.callsFor('siteGestureFallbackReady'), hasLength(2));
    await f.end(140000);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  for (final phase in ['query', 'readiness']) {
    testWidgets('native invalidation during $phase is not UNKNOWN recovery',
        (tester) async {
      final f = await _Fixture.mount(tester);
      f.policy = Completer<dynamic>()
        ..complete({
          'status': phase == 'query' ? 'invalidated' : 'indeterminate',
          'epoch': f.epoch,
        });
      f.readyReply = Completer<bool?>()..complete(null);
      await f.start();
      await f.move(10000, const Offset(120, 0), scale: 1.5);
      await tester.pump();
      await f.move(20000, const Offset(140, 0), scale: 2);
      await f.end(30000);
      expect(f.packets, isEmpty);
      expect(f.callsFor('setZoomScale'), isEmpty);
      expect(f.callsFor('navigateHistory'), isEmpty);
      await f.dispose();
    }, timeout: platformViewTestTimeout);
  }

  for (final interruption in [
    'navigation',
    'end',
    'hidden',
    'cancel',
    'resize',
    'pause',
    'detach'
  ]) {
    testWidgets(
        '$interruption retires fallback readiness and tiny tail cannot click',
        (tester) async {
      final f = await _Fixture.mount(tester);
      f.policy = Completer<dynamic>()
        ..complete({'status': 'indeterminate', 'epoch': f.epoch});
      f.readyReply = Completer<bool?>();
      await f.start();
      await f.move(10000, const Offset(0, -20));
      switch (interruption) {
        case 'navigation':
          await f.navigation();
          break;
        case 'end':
          await f.end(20000);
          break;
        case 'hidden':
          f.index.value = 1;
          await tester.pump();
          break;
        case 'cancel':
          await f.cancel();
          break;
        case 'resize':
          f.size.value = 280;
          await tester.pump();
          await tester.pump();
          break;
        case 'detach':
          final state = tester
              .state<CustomPlatformViewState>(find.byType(CustomPlatformView));
          f.reparent.value = true;
          await tester.pump();
          expect(
              tester.state<CustomPlatformViewState>(
                  find.byType(CustomPlatformView)),
              same(state));
          expect(tester.getCenter(find.byType(CustomPlatformView)), f.point);
          break;
        case 'pause':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          break;
      }
      f.readyReply!.complete(true);
      await tester.pump();
      if (interruption != 'cancel' && interruption != 'end') {
        await f.move(30000, const Offset(0, -40));
        await f.move(40000, const Offset(0, -60));
        await f.end(50000);
      }
      expect(f.packets, isEmpty);
      expect(f.callsFor('setZoomScale'), isEmpty);
      expect(f.callsFor('navigateHistory'), isEmpty);
      await f.dispose();
    }, timeout: platformViewTestTimeout);
  }

  for (final interruption in [
    'cancel',
    'navigation',
    'hidden',
    'resize',
    'pause',
    'detach'
  ]) {
    testWidgets('$interruption cancels an active pair and ignores stale tail',
        (tester) async {
      final f = await _Fixture.mount(tester);
      await f.start();
      await f.move(10000, Offset.zero, scale: 1.5);
      switch (interruption) {
        case 'cancel':
          await f.cancel();
          break;
        case 'navigation':
          await f.navigation();
          break;
        case 'hidden':
          f.index.value = 1;
          await tester.pump();
          await f.move(20000, const Offset(20, 0), scale: 1.5);
          break;
        case 'resize':
          f.size.value = 280;
          await tester.pump();
          await tester.pump();
          break;
        case 'detach':
          final state = tester
              .state<CustomPlatformViewState>(find.byType(CustomPlatformView));
          f.reparent.value = true;
          await tester.pump();
          expect(
              tester.state<CustomPlatformViewState>(
                  find.byType(CustomPlatformView)),
              same(state));
          break;
        case 'pause':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          break;
      }
      expect(f.packets.map((p) => p[1]), [
        InAppWebViewPointerEventKind.down.index,
        InAppWebViewPointerEventKind.update.index,
        InAppWebViewPointerEventKind.leave.index,
      ]);
      expect(f.packets.last[1], InAppWebViewPointerEventKind.leave.index);
      final count = f.packets.length;
      if (interruption != 'cancel') {
        await f.move(30000, const Offset(30, 0), scale: 2);
        await f.end(40000);
      }
      expect(f.packets, hasLength(count));
      expect(f.callsFor('setZoomScale'), isEmpty);
      await f.dispose();
    }, timeout: platformViewTestTimeout);
  }

  testWidgets('manual scope enables both-disabled hosts without policy queries',
      (tester) async {
    final f = await _Fixture.mount(tester, manual: true, bothDisabled: true);
    await f.start();
    await f.move(10000, const Offset(20, 20), scale: 1.5);
    await f.end(20000);
    expect(f.callsFor('querySiteGesturePolicyState'), isEmpty);
    expect(f.packets, hasLength(3));
    expect(f.packets.first.length, 10);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets('unmount cancels paired native contacts before disposal ACK',
      (tester) async {
    final f = await _Fixture.mount(tester);
    f.disposeAck = Completer<void>();
    await f.start();
    await f.move(10000, Offset.zero, scale: 1.5);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(f.packets.map((p) => p[1]), [
      InAppWebViewPointerEventKind.down.index,
      InAppWebViewPointerEventKind.update.index,
      InAppWebViewPointerEventKind.leave.index,
    ]);
    expect(f.packets.map((p) => p[6]), [1000000, 1010000, 1010000]);
    expect(f.packets.map((p) => p.length), [10, 10, 8]);
    expect(f.callsFor('setPointerButton'), isEmpty);
    expect(f.callsFor('navigateHistory'), isEmpty);
    expect(tester.takeException(), isNull);
    f.disposeAck!.complete();
    await f.end(20000);
    await f.dispose();
    expect(f.packets, hasLength(3));
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('wheel modified wheel mouse and six-value touch stay unchanged',
      (tester) async {
    final f = await _Fixture.mount(tester);
    for (final modified in [false, true]) {
      if (modified) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft);
      }
      await tester.sendEventToBinding(PointerScrollEvent(
          position: f.point, scrollDelta: const Offset(12.25, 0.125)));
      if (modified) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft);
      }
    }
    expect(f.callsFor('setScrollDelta').map((c) => c.arguments), [
      [0.0, -0.125],
      [0.0, -0.125]
    ]);
    await tester.tapAt(f.point, kind: PointerDeviceKind.mouse);
    expect(f.callsFor('setPointerButton').map((c) => c.arguments), [
      {'button': 1, 'isDown': true},
      {'button': 1, 'isDown': false},
    ]);
    final touch =
        await tester.startGesture(f.point, kind: PointerDeviceKind.touch);
    await touch.moveBy(const Offset(0, -20));
    await touch.up();
    expect(f.packets.map((p) => p.length), everyElement(6));
    expect(f.packets, hasLength(3));
    expect(f.callsFor('querySiteGesturePolicyState'), isEmpty);
    await f.dispose();
  }, timeout: platformViewTestTimeout);

  testWidgets(
      'late query cannot resurrect disposed view; disposal waits for ACK',
      (tester) async {
    final f = await _Fixture.mount(tester);
    f.policy = Completer<bool?>();
    f.disposeAck = Completer<void>();
    await f.start();
    await f.move(10000, Offset.zero, scale: 1.5);
    final native = tester
        .state<CustomPlatformViewState>(find.byType(CustomPlatformView))
        .controller;
    await tester.pumpWidget(const SizedBox.shrink());
    var completed = false;
    final disposal = native.dispose();
    unawaited(disposal.then<void>((_) {
      completed = true;
    }));
    expect(native.dispose(), same(disposal));
    await drainPlatformViewUntil(
        tester, () => f.disposals == 1, 'native dispose request');
    expect(completed, isFalse);
    f.policy!.complete(true);
    await tester.pump();
    expect(f.packets, isEmpty);
    f.disposeAck!.complete();
    await drainPlatformViewUntil(
        tester, () => completed, 'native ACK and stream closure');
    await disposal;
    expect(completed, isTrue);
    expect(f.disposals, 1);
    await f.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('completed fixture cleanup does not pump or unmount a newer tree',
      (tester) async {
    final f = await _Fixture.mount(tester);
    await f.dispose();
    expect(f._disposed, isTrue);
    expect(f.disposals, 1);
    const replacement = SizedBox(key: ValueKey('after-fixture'));
    await tester.pumpWidget(replacement);
    var pumped = false;
    tester.binding.addPostFrameCallback((_) => pumped = true);
    tester.binding.scheduleFrame();
    await f.dispose();
    expect(find.byKey(replacement.key!), findsOneWidget);
    expect(pumped, isFalse);
    expect(f.disposals, 1);
    await tester.pump();
    expect(pumped, isTrue);
  }, timeout: platformViewTestTimeout);

  testWidgets('teardown drains owned pending replies when body omits cleanup',
      (tester) async {
    late _Fixture f;
    // Runs after the fixture's teardown, but before binding.postTest.
    addTearDown(() {
      expect(f._disposed, isTrue);
      expect(f.disposals, 1);
      expect(f.disposeAck!.isCompleted, isTrue);
      expect(f.policy!.isCompleted, isTrue);
    });
    f = await _Fixture.mount(tester);
    f.disposeAck = Completer<void>();
    f.policy = Completer<bool?>();
    await f.start();
    await f.move(10000, Offset.zero, scale: 1.5);
    expect(f.packets, isEmpty);
    expect(f._disposed, isFalse);
    // Deliberately leave cleanup to the same fallback used after body failure.
  }, timeout: platformViewTestTimeout);

  for (final settling in [false, true]) {
    for (final reattach in [false, true]) {
      testWidgets(
          'history teardown settling=$settling reattach=$reattach does not notify unmounting children',
          (tester) async {
        final f = await _Fixture.mount(tester, site: false);
        final state = tester
            .state<CustomPlatformViewState>(find.byType(CustomPlatformView));
        await f.start();
        await f.move(10000, const Offset(120, 0));
        await tester.pump();
        expect(f.history.isActive, isTrue);
        if (settling) {
          await f.end(20000);
          await tester.pump();
          expect(f.history.isSettling, isTrue);
        }
        if (reattach) {
          f.reparent.value = true;
          await tester.pump();
          expect(
              tester.state<CustomPlatformViewState>(
                  find.byType(CustomPlatformView)),
              same(state));
          await tester.pumpAndSettle();
          expect(f.history.isActive, isFalse);
          expect(f.history.isSettling, isFalse);
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
        if (!settling) await f.end(20000);
        expect(f.callsFor('navigateHistory'), isEmpty);
        expect(f.packets, isEmpty);
        expect(tester.takeException(), isNull);
        if (reattach) {
          await f.start(origin: 2000000);
          await f.move(10000, Offset.zero, scale: 1.25);
          await f.end(20000);
          expect(f.callsFor('setZoomScale').single.arguments, 1.25);
        }
        await f.dispose();
      }, timeout: platformViewTestTimeout);
    }
  }
}

class _Fixture {
  _Fixture(this.tester, this.site);
  final WidgetTester tester;
  final bool site;
  final calls = <MethodCall>[];
  final index = ValueNotifier(0);
  final size = ValueNotifier(300.0);
  final reparent = ValueNotifier(false);
  Completer<dynamic>? policy;
  Completer<bool?>? readyReply;
  int epoch = 7;
  int currentPage = 1;
  int disposals = 0;
  CustomPlatformViewController? native;
  final Zone _ownerZone = Zone.current;
  Zone? _disposalZone;
  bool _disposed = false;
  Completer<void>? disposeAck;
  Offset previousPan = Offset.zero;
  late Offset point;
  int origin = 1000000;
  static const manager =
      MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
  static const view =
      MethodChannel('com.pichillilorenzo/custom_platform_view_91');
  static const events =
      MethodChannel('com.pichillilorenzo/custom_platform_view_91_events');

  List<MethodCall> callsFor(String method) =>
      calls.where((c) => c.method == method).toList();
  List<List<dynamic>> get packets => callsFor('setPointerUpdate')
      .map((c) => c.arguments as List<dynamic>)
      .toList();

  HistorySwipeController get history => tester
      .widget<HistorySwipeSurface>(find.byType(HistorySwipeSurface))
      .controller;

  static Future<_Fixture> mount(WidgetTester tester,
      {bool site = true,
      bool manual = false,
      bool bothDisabled = false}) async {
    final f = _Fixture(tester, site);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (call.method == 'createInAppWebView') return 91;
      if (call.method == 'dispose') {
        expectSync(call.arguments, {'id': 91});
        f.disposals++;
        await f.disposeAck?.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(view, (call) async {
      f.calls.add(call);
      if (call.method == 'querySiteGesturePolicyState') {
        final value = f.policy == null ? site : await f.policy!.future;
        return value is bool
            ? {'status': value ? 'site' : 'browser', 'epoch': f.epoch}
            : value;
      }
      if (call.method == 'siteGestureFallbackReady')
        return f.readyReply?.future ?? true;
      if (call.method == 'getHistoryState') {
        return {
          'back': true,
          'forward': true,
          'loading': false,
          'current': f.currentPage,
          'previous': 0,
          'next': 2
        };
      }
      if (call.method == 'navigateHistory') return true;
      return null;
    });
    addTearDown(() async {
      try {
        // Successful body cleanup must not pump again in the teardown zone.
        if (!f._disposed) {
          if (f.policy != null && !f.policy!.isCompleted)
            f.policy!.complete(null);
          if (f.readyReply != null && !f.readyReply!.isCompleted)
            f.readyReply!.complete(null);
          if (f.disposeAck != null && !f.disposeAck!.isCompleted)
            f.disposeAck!.complete();
          await f.dispose();
        }
      } finally {
        messenger.setMockMethodCallHandler(manager, null);
        messenger.setMockMethodCallHandler(view, null);
        messenger.setMockMethodCallHandler(events, null);
        f.index.dispose();
        f.size.dispose();
        f.reparent.dispose();
      }
    });
    Widget child = CustomPlatformView(creationParams: {
      'initialSettings': {
        'disableHorizontalScroll': true,
        'disableVerticalScroll': bothDisabled,
        'allowsBackForwardNavigationGestures': true
      },
    });
    if (manual)
      child =
          WindowsWebViewGestureScope(preferWebsiteGestures: true, child: child);
    final retained = KeyedSubtree(
      key: GlobalKey(),
      child: ValueListenableBuilder<double>(
        valueListenable: f.size,
        child: child,
        builder: (_, size, child) => SizedBox.square(
            dimension: size,
            child: ValueListenableBuilder<int>(
                valueListenable: f.index,
                child: child,
                builder: (_, index, child) => IndexedStack(
                        index: index,
                        children: [
                          child!,
                          const ColoredBox(color: Colors.black)
                        ]))),
      ),
    );
    await tester.pumpWidget(MaterialApp(
        home: Center(
      child: ValueListenableBuilder<bool>(
          valueListenable: f.reparent,
          child: retained,
          builder: (_, reparent, child) => reparent
              ? Align(child: child)
              : Padding(padding: EdgeInsets.zero, child: child)),
    )));
    f.native = tester
        .state<CustomPlatformViewState>(find.byType(CustomPlatformView))
        .controller;
    await awaitPlatformViewReady(tester, f.native!);
    await tester.pumpAndSettle();
    f.point = tester.getCenter(find.byType(CustomPlatformView));
    return f;
  }

  Future<void> start({int origin = 1000000}) async {
    this.origin = origin;
    previousPan = Offset.zero;
    await tester.sendEventToBinding(PointerPanZoomStartEvent(
        pointer: 7,
        device: 7,
        position: point,
        timeStamp: Duration(microseconds: origin)));
    await tester.pump();
  }

  Future<void> move(int elapsed, Offset pan, {double scale = 1}) async {
    await tester.sendEventToBinding(PointerPanZoomUpdateEvent(
        pointer: 7,
        device: 7,
        position: point,
        pan: pan,
        panDelta: pan - previousPan,
        scale: scale,
        timeStamp: Duration(microseconds: origin + elapsed)));
    previousPan = pan;
  }

  Future<void> end(int elapsed) =>
      tester.sendEventToBinding(PointerPanZoomEndEvent(
          pointer: 7,
          device: 7,
          position: point,
          timeStamp: Duration(microseconds: origin + elapsed)));

  Future<void> navigation() async {
    tester.binding.channelBuffers.push(
        events.name,
        const StandardMethodCodec()
            .encodeSuccessEnvelope({'type': 'navigationStarting'}),
        (_) {});
    await tester.pump();
  }

  Future<void> navigationCompleted() async {
    tester.binding.channelBuffers.push(
        events.name,
        const StandardMethodCodec()
            .encodeSuccessEnvelope({'type': 'navigationCompleted'}),
        (_) {});
    await tester.pump();
  }

  Future<void> cancel() async {
    // Flutter does not allow PointerCancelEvent(kind: trackpad). Its own
    // cancelPointer emits a synthetic cancel routed by the tracked pointer ID.
    tester.binding.cancelPointer(7);
    await tester.pump();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    // Capture our still-mounted controller even if mount failed before ready.
    final mountedView = find.byType(CustomPlatformView, skipOffstage: false);
    final isMounted = mountedView.evaluate().isNotEmpty;
    if (native == null && isMounted) {
      native = tester.state<CustomPlatformViewState>(mountedView).controller;
    }
    // A still-mounted view starts disposal in this unmount's zone; an already
    // unmounted view was retired by the body/framework in the owner's zone.
    _disposalZone ??= isMounted ? Zone.current : _ownerZone;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final controller = native;
    if (controller != null) {
      await awaitPlatformViewDisposal(tester, controller,
          ownerZone: _disposalZone!);
    }
    // Only latch after unmount and successful ACK/stream closure (or no view).
    _disposed = true;
    expect(tester.takeException(), isNull);
  }
}
