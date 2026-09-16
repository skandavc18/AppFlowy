import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters only pointer-scroll axes disabled by WebView settings', () {
    const delta = Offset(12, 40);

    expect(
      filterScrollDeltaForSettings(delta, {
        'initialSettings': {
          'disableHorizontalScroll': false,
          'disableVerticalScroll': true,
        },
      }),
      const Offset(12, 0),
    );
    expect(
      filterScrollDeltaForSettings(delta, {
        'initialSettings': {
          'disableHorizontalScroll': true,
          'disableVerticalScroll': true,
        },
      }),
      Offset.zero,
    );
    expect(filterScrollDeltaForSettings(delta, null), delta);
    expect(
      hasEnabledWebViewScrollAxis({
        'initialSettings': {
          'disableHorizontalScroll': true,
          'disableVerticalScroll': true,
        },
      }),
      isFalse,
    );
    expect(hasEnabledWebViewScrollAxis(null), isTrue);
  });

  test('trackpad direct deltas are scaled and bounded', () {
    expect(
      webViewTrackpadDirectDelta(const Offset(10, -20)),
      const Offset(10, -20),
    );
    final bounded = webViewTrackpadDirectDelta(const Offset(100, -100));
    expect(bounded.dx, closeTo(48, 0.0001));
    expect(bounded.dy, closeTo(-48, 0.0001));
  });

  testWidgets('routes trackpad input through native touch manipulation', (
    tester,
  ) async {
    const textureId = 42;
    const managerChannel = MethodChannel(
      'com.pichillilorenzo/flutter_inappwebview_manager',
    );
    const viewChannel = MethodChannel(
      'com.pichillilorenzo/custom_platform_view_$textureId',
    );
    const eventChannel = MethodChannel(
      'com.pichillilorenzo/custom_platform_view_${textureId}_events',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final viewCalls = <MethodCall>[];
    final parentScrollController = ScrollController();

    messenger.setMockMethodCallHandler(managerChannel, (call) async {
      if (call.method == 'createInAppWebView') {
        return textureId;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(viewChannel, (call) async {
      viewCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(eventChannel, (_) async => null);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      parentScrollController.dispose();
      messenger.setMockMethodCallHandler(managerChannel, null);
      messenger.setMockMethodCallHandler(viewChannel, null);
      messenger.setMockMethodCallHandler(eventChannel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: SingleChildScrollView(
            controller: parentScrollController,
            child: const Column(
              children: [
                SizedBox.square(
                  dimension: 200,
                  child: CustomPlatformView(),
                ),
                SizedBox(height: 800),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final position = tester.getCenter(find.byType(CustomPlatformView));
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(
        pointer: 7,
        device: 7,
        position: position,
        timeStamp: Duration.zero,
      ),
    );
    for (final update in <({Duration time, double pan, double delta})>[
      (
        time: const Duration(milliseconds: 10),
        pan: -10,
        delta: -10,
      ),
      (
        time: const Duration(milliseconds: 20),
        pan: -25,
        delta: -15,
      ),
      (
        time: const Duration(milliseconds: 30),
        pan: -45,
        delta: -20,
      ),
    ]) {
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 7,
          device: 7,
          position: position,
          timeStamp: update.time,
          pan: Offset(-268, -108 + update.pan),
          panDelta: Offset(0, update.delta),
        ),
      );
    }
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(
        pointer: 7,
        device: 7,
        position: position,
        timeStamp: const Duration(milliseconds: 35),
      ),
    );
    final pointerCalls =
        viewCalls.where((call) => call.method == 'setPointerUpdate').toList();
    expect(pointerCalls, hasLength(5));
    expect(
      pointerCalls.map((call) => (call.arguments as List)[1]),
      [
        InAppWebViewPointerEventKind.down.index,
        InAppWebViewPointerEventKind.update.index,
        InAppWebViewPointerEventKind.update.index,
        InAppWebViewPointerEventKind.update.index,
        InAppWebViewPointerEventKind.up.index,
      ],
    );
    expect(
      pointerCalls.map((call) => (call.arguments as List)[3]),
      [100.0, 90.0, 75.0, 55.0, 55.0],
    );
    expect(
      viewCalls.where((call) => call.method == 'setScrollDelta'),
      isEmpty,
    );
    expect(parentScrollController.offset, 0);
  });

  testWidgets('trackpad contact does not hide or replace the mouse cursor', (
    tester,
  ) async {
    const id = 44;
    const manager =
        MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
    const view = MethodChannel('com.pichillilorenzo/custom_platform_view_$id');
    const events =
        MethodChannel('com.pichillilorenzo/custom_platform_view_${id}_events');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(manager,
        (call) async => call.method == 'createInAppWebView' ? id : null);
    messenger.setMockMethodCallHandler(view, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      messenger.setMockMethodCallHandler(manager, null);
      messenger.setMockMethodCallHandler(view, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    await tester.pumpWidget(const MaterialApp(
      home: Center(
          child: SizedBox.square(
        dimension: 300,
        child: CustomPlatformView(creationParams: {
          'initialSettings': {'disableHorizontalScroll': true},
        }),
      )),
    ));
    await tester.pump();
    Future<void> cursor(String value) async {
      tester.binding.channelBuffers.push(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'type': 'cursorChanged',
          'value': value,
        }),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    MouseCursor actualCursor() => tester
        .widget<MouseRegion>(
          find.byWidgetPredicate(
              (widget) => widget is MouseRegion && widget.child is Texture),
        )
        .cursor;
    await cursor('click');
    expect(actualCursor(), SystemMouseCursors.click);
    final anchor = tester.getCenter(find.byType(CustomPlatformView));
    final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pan.panZoomStart(anchor);
    await tester.pump();
    await cursor('none');
    expect(actualCursor(), SystemMouseCursors.click);
    await pan.panZoomUpdate(anchor, pan: const Offset(-20, -35));
    await tester.pump();
    await cursor('text');
    expect(actualCursor(), SystemMouseCursors.click);
    await pan.panZoomEnd();
    await tester.pump();
    // A cursor event received during the pan may not be repeated by WebView2.
    expect(actualCursor(), SystemMouseCursors.text);
    final points =
        calls.where((call) => call.method == 'setPointerUpdate').toList();
    expect(
        points.map((call) => (call.arguments as List)[2]), everyElement(150.0));
    expect(points.map((call) => (call.arguments as List)[3]),
        [150.0, 115.0, 115.0]);
    expect(calls.last.method, 'setCursorPos');
    expect(calls.last.arguments, [150.0, 150.0]);
    await cursor('basic');
    expect(actualCursor(), SystemMouseCursors.basic);

    // A click at a new position must not use the scrolling contact/old hover.
    final click = anchor + const Offset(25, 20);
    await tester.tapAt(click, kind: PointerDeviceKind.mouse);
    final button =
        calls.indexWhere((call) => call.method == 'setPointerButton');
    expect(calls[button - 1].method, 'setCursorPos');
    expect(calls[button - 1].arguments, [175.0, 170.0]);

    // Cancelling a contact and removing its view must not rebuild a disposed
    // widget or leave the renderer in the middle of a touch gesture.
    await pan.panZoomStart(anchor);
    await pan.panZoomUpdate(anchor, pan: const Offset(0, -20));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final lastContact =
        calls.lastWhere((call) => call.method == 'setPointerUpdate');
    expect((lastContact.arguments as List)[1],
        InAppWebViewPointerEventKind.leave.index);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in <({
    String name,
    List<Offset> pans,
    double scale,
    double rotation,
    bool? forward
  })>[
    (
      name: 'right back',
      pans: [Offset(24, 1), Offset(144, 4)],
      scale: 1,
      rotation: 0,
      forward: false
    ),
    (
      name: 'left forward',
      pans: [Offset(-24, 1), Offset(-144, 4)],
      scale: 1,
      rotation: 0,
      forward: true
    ),
    (
      name: 'short',
      pans: [Offset(24, 0), Offset(80, 0)],
      scale: 1,
      rotation: 0,
      forward: null
    ),
    (
      name: 'undone',
      pans: [Offset(24, 0), Offset(144, 0), Offset(20, 0)],
      scale: 1,
      rotation: 0,
      forward: null
    ),
    (
      name: 'vertical',
      pans: [Offset(0, -20), Offset(160, -25)],
      scale: 1,
      rotation: 0,
      forward: null
    ),
    (
      name: 'diagonal',
      pans: [Offset(20, -20), Offset(160, -25)],
      scale: 1,
      rotation: 0,
      forward: null
    ),
    (
      name: 'pinch',
      pans: [Offset(24, 0), Offset(144, 0)],
      scale: 1.1,
      rotation: 0,
      forward: null
    ),
    (
      name: 'rotate',
      pans: [Offset(24, 0), Offset(144, 0)],
      scale: 1,
      rotation: 0.1,
      forward: null
    ),
  ]) {
    testWidgets('bookmark history: ${scenario.name}', (tester) async {
      const id = 45;
      const manager =
          MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
      const view =
          MethodChannel('com.pichillilorenzo/custom_platform_view_$id');
      const events = MethodChannel(
          'com.pichillilorenzo/custom_platform_view_${id}_events');
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(manager,
          (call) async => call.method == 'createInAppWebView' ? id : null);
      messenger.setMockMethodCallHandler(view, (call) async {
        calls.add(call);
        if (call.method == 'getHistoryState') {
          return {'back': true, 'forward': true};
        }
        return call.method == 'navigateHistory' ? true : null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        messenger.setMockMethodCallHandler(manager, null);
        messenger.setMockMethodCallHandler(view, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      await tester.pumpWidget(const MaterialApp(
          home: Center(
              child: SizedBox.square(
        dimension: 300,
        child: CustomPlatformView(creationParams: {
          'initialSettings': {
            'disableHorizontalScroll': true,
            'allowsBackForwardNavigationGestures': true,
          },
        }),
      ))));
      await tester.pumpAndSettle();
      final point = tester.getCenter(find.byType(CustomPlatformView));
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pan.panZoomStart(point);
      await tester.pump();
      expect(calls.where((call) => call.method == 'setPointerUpdate'), isEmpty);
      for (var i = 0; i < scenario.pans.length; i++) {
        await pan.panZoomUpdate(
          point,
          pan: scenario.pans[i],
          scale: scenario.scale,
          rotation: scenario.rotation,
          timeStamp: Duration(milliseconds: (i + 1) * 16),
        );
        await tester.pump();
      }
      expect(calls.where((call) => call.method == 'navigateHistory'), isEmpty);
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      final navigation =
          calls.where((call) => call.method == 'navigateHistory').toList();
      expect(navigation, hasLength(scenario.forward == null ? 0 : 1));
      if (scenario.forward != null) {
        expect(navigation.single.arguments, scenario.forward);
        expect(
            calls.where((call) => call.method == 'setPointerUpdate'), isEmpty);
      }
      if (scenario.name == 'pinch') {
        expect(
            calls.where((call) => call.method == 'setZoomScale'), hasLength(1));
        expect(
            calls.where((call) => call.method == 'setPointerUpdate'), isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching bookmark tabs cancels an unfinished history swipe',
      (tester) async {
    const id = 46;
    const manager =
        MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
    const view = MethodChannel('com.pichillilorenzo/custom_platform_view_$id');
    const events =
        MethodChannel('com.pichillilorenzo/custom_platform_view_${id}_events');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(manager,
        (call) async => call.method == 'createInAppWebView' ? id : null);
    messenger.setMockMethodCallHandler(view, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final selected = ValueNotifier(0);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      selected.dispose();
      messenger.setMockMethodCallHandler(manager, null);
      messenger.setMockMethodCallHandler(view, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder(
      valueListenable: selected,
      builder: (_, value, __) => IndexedStack(index: value, children: const [
        CustomPlatformView(creationParams: {
          'initialSettings': {
            'disableHorizontalScroll': true,
            'allowsBackForwardNavigationGestures': true,
          }
        }),
        SizedBox.expand(),
      ]),
    )));
    await tester.pumpAndSettle();
    final point = tester.getCenter(find.byType(CustomPlatformView));
    final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pan.panZoomStart(point);
    await pan.panZoomUpdate(point, pan: const Offset(120, 0));
    selected.value = 1;
    await tester.pumpAndSettle();
    await pan.panZoomEnd();
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'navigateHistory'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes a platform view that finishes creating late', (
    tester,
  ) async {
    const textureId = 43;
    const managerChannel = MethodChannel(
      'com.pichillilorenzo/flutter_inappwebview_manager',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final creation = Completer<int>();
    final managerCalls = <MethodCall>[];

    messenger.setMockMethodCallHandler(managerChannel, (call) async {
      managerCalls.add(call);
      if (call.method == 'createInAppWebView') {
        return creation.future;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(managerChannel, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.square(
          dimension: 200,
          child: CustomPlatformView(),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    creation.complete(textureId);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final disposeCalls =
        managerCalls.where((call) => call.method == 'dispose').toList();
    expect(disposeCalls, hasLength(1));
    expect(disposeCalls.single.arguments, {'id': textureId});
  });
}
