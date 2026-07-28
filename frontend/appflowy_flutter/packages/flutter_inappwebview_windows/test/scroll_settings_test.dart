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
      const Offset(5.5, -11),
    );
    final bounded = webViewTrackpadDirectDelta(const Offset(100, -100));
    expect(bounded.dx, closeTo(26.4, 0.0001));
    expect(bounded.dy, closeTo(-26.4, 0.0001));
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
      [100.0, 94.5, 86.25, 75.25, 75.25],
    );
    expect(
      viewCalls.where(
        (call) =>
            call.method == 'setScrollDelta' ||
            call.method == 'setTrackpadScrollDelta',
      ),
      isEmpty,
    );
    expect(parentScrollController.offset, 0);
    expect(
      viewCalls.any((call) => call.method == 'setCursorPos'),
      isTrue,
    );
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
