import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Standalone, offline WebView2 verification. Deliberately does not import main,
// integration_test/shared, SharedPreferences, auth, or an AppFlowy controller.
// No SetCursorPos/SendInput/window-manager calls: all input is synthetic Flutter
// input delivered only to the fixture's own view. No live URLs or page content
// are read, written, captured, or reported.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native creation/events can complete between pumps. Let their scheduled
  // frames run while waiting for event futures, not polling page state.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'offline popup: original timing, cold cancellation and navigation recovery',
    (tester) async {
      expect(Platform.isWindows, isTrue);
      if ((Platform.environment['WEBVIEW2_USER_DATA_FOLDER'] ?? '')
          .isNotEmpty) {
        throw StateError(
          'Remove the external WebView2 profile override before this isolated test.',
        );
      }
      final root =
          await Directory.systemTemp.createTemp('appflowy_popup_scroll_');
      final logging =
          PlatformInAppWebViewController.debugLoggingSettings.enabled;
      PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
      final environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: root.path),
      ).timeout(const Duration(seconds: 20));
      final fixture = _NativeFixture(environment);
      final report = <String, dynamic>{
        'run': const String.fromEnvironment(
          'PERF_RUN',
          defaultValue: 'popup_webview_scrolling',
        ),
        'kind': 'isolated_native_regression_not_site_performance',
        'timestamp_probe': <Map<String, Object>>[],
        'cold_probe': <Map<String, Object>>[],
      };
      binding.reportData = report;
      try {
        await tester.pumpWidget(fixture.widget());
        await fixture.created.future.timeout(const Duration(seconds: 20));
        await fixture.loaded.future.timeout(const Duration(seconds: 20));
        await fixture.frames();
        final point = tester.getCenter(find.byType(InAppWebView));

        // The first touch handler blocks its own renderer for 80ms. Moves/end
        // generated at 10/20/30/35ms reach the native queue while start is held.
        // It may coalesce moves, but each surviving position must keep its own
        // time, not the 80ms+ callback time. touch-action:none is probe-only;
        // it keeps DOM events observable without a scrolling touch cancellation.
        final original = await fixture.burst(tester, point, pointer: 10);
        report['timestamp_probe'] = original;
        expect(original.first['type'], 'touchstart');
        expect(original.last['type'], 'touchend');
        expect(
          original.where((sample) => sample['type'] == 'touchcancel'),
          isEmpty,
        );
        final start = (original.first['timeMs']! as num).toDouble();
        final startY = (original.first['y']! as num).toDouble();
        final moves =
            original.where((sample) => sample['type'] == 'touchmove').toList();
        expect(moves, isNotEmpty);
        for (final move in moves) {
          final distance = startY - (move['y']! as num).toDouble();
          final expectedMs = distance < 17.5
              ? 10.0
              : distance < 35
                  ? 20.0
                  : 30.0;
          expect((move['timeMs']! as num) - start, closeTo(expectedMs, 1));
        }
        expect(startY - (moves.last['y']! as num), closeTo(45, 1));
        expect((original.last['timeMs']! as num) - start, closeTo(35, 1));

        // More than the queue's 250ms freshness bound. There must be no replay
        // of the unsent movement/release after the held start acknowledges.
        await fixture.load(holdStartMs: 600);
        final cold = await fixture.burst(tester, point, pointer: 11);
        report['cold_probe'] = cold;
        expect(
          cold.map((sample) => sample['type']),
          ['touchstart', 'touchcancel'],
        );
        final coldY = await fixture.scrollY();
        await fixture.frames();
        expect(await fixture.scrollY(), coldY);

        // Keep the same native view/environment across navigation. An old Dart
        // gesture must not inject a move/end into the new document.
        await fixture.load(holdStartMs: 0);
        final began = fixture.events.stream.firstWhere(
          (sample) => sample['type'] == 'touchstart',
        );
        await fixture.start(tester, point, pointer: 12);
        await fixture.move(
          tester,
          point,
          pointer: 12,
          timeMs: 10,
          pan: -20,
          delta: -20,
        );
        await began.timeout(const Duration(seconds: 5));
        await fixture.load(holdStartMs: 80, nativeScroll: true);
        fixture.samples.clear();
        await fixture.move(
          tester,
          point,
          pointer: 12,
          timeMs: 20,
          pan: -40,
          delta: -20,
        );
        await fixture.end(tester, point, pointer: 12);
        await fixture.frames();
        expect(
          fixture.samples.where((sample) => sample['type'] != 'touchcancel'),
          isEmpty,
        );
        expect(await fixture.scrollY(), 0);

        // Native scroll semantics are back on. No JavaScript scroll engine or
        // wheel conversion: the ordinary trackpad stream must move Chromium.
        final recovered = await fixture.burst(tester, point, pointer: 13);
        await fixture.frames();
        final scrollY = await fixture.scrollY();
        report['recovered_probe'] = recovered;
        report['recovered_scroll_y'] = scrollY;
        report['native_view_creations'] = fixture.createCount;
        expect(scrollY, greaterThan(0));
        expect(fixture.createCount, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        // The vendored environment wrapper's dispose channel uses a static ID;
        // use this fixture's actual native ID, never a shared app environment.
        await MethodChannel(
          'com.pichillilorenzo/flutter_webview_environment_${environment.id}',
        ).invokeMethod<void>('dispose').timeout(const Duration(seconds: 5));
        await fixture.events.close();
        PlatformInAppWebViewController.debugLoggingSettings.enabled = logging;
        // WebView2 may still hold profile locks. Leave only this temporary
        // profile for the OS to clean; never delete or reset an app profile.
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _NativeFixture {
  _NativeFixture(this.environment);
  final WebViewEnvironment environment;
  final created = Completer<void>();
  Completer<void> loaded = Completer<void>();
  final events = StreamController<Map<String, Object>>.broadcast();
  final samples = <Map<String, Object>>[];
  late InAppWebViewController controller;
  int createCount = 0;

  Widget widget() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 500,
              child: InAppWebView(
                webViewEnvironment: environment,
                initialData: InAppWebViewInitialData(data: _html(80, false)),
                initialSettings: InAppWebViewSettings(
                  disableHorizontalScroll: true,
                  // ignore: avoid_redundant_argument_values
                  allowsBackForwardNavigationGestures: true,
                ),
                onPermissionRequest: (_, request) async =>
                    PermissionResponse(resources: request.resources),
                onWebViewCreated: (value) {
                  controller = value;
                  createCount++;
                  value.addJavaScriptHandler(
                    handlerName: 'popupTouchProbe',
                    callback: (arguments) {
                      final value = arguments.single as Map;
                      final sample = <String, Object>{
                        'type': value['type'] as String,
                        'timeMs': value['timeMs'] as num,
                        'y': value['y'] as num,
                      };
                      samples.add(sample);
                      events.add(sample);
                    },
                  );
                  if (!created.isCompleted) created.complete();
                },
                onLoadStop: (_, __) {
                  if (!loaded.isCompleted) loaded.complete();
                },
              ),
            ),
          ),
        ),
      );

  Future<void> load({
    required int holdStartMs,
    bool nativeScroll = false,
  }) async {
    loaded = Completer<void>();
    await controller.loadData(data: _html(holdStartMs, nativeScroll));
    await loaded.future.timeout(const Duration(seconds: 10));
    await frames();
    samples.clear();
  }

  Future<void> frames() async {
    final result = await controller.callAsyncJavaScript(
      functionBody: '''
await new Promise(requestAnimationFrame);
await new Promise(requestAnimationFrame);
return true;
''',
    ).timeout(const Duration(seconds: 5));
    expect(result?.value, isTrue);
  }

  Future<num> scrollY() async => (await controller
      .evaluateJavascript(
        source: 'window.scrollY',
      )
      .timeout(const Duration(seconds: 5))) as num;

  Future<List<Map<String, Object>>> burst(
    WidgetTester tester,
    Offset point, {
    required int pointer,
  }) async {
    samples.clear();
    final terminal = events.stream.firstWhere(
      (sample) =>
          sample['type'] == 'touchend' || sample['type'] == 'touchcancel',
    );
    await start(tester, point, pointer: pointer);
    await move(
      tester,
      point,
      pointer: pointer,
      timeMs: 10,
      pan: -10,
      delta: -10,
    );
    await move(
      tester,
      point,
      pointer: pointer,
      timeMs: 20,
      pan: -25,
      delta: -15,
    );
    await move(
      tester,
      point,
      pointer: pointer,
      timeMs: 30,
      pan: -45,
      delta: -20,
    );
    await end(tester, point, pointer: pointer);
    await terminal.timeout(const Duration(seconds: 5));
    await frames();
    return List.of(samples);
  }

  Future<void> start(
    WidgetTester tester,
    Offset point, {
    required int pointer,
  }) =>
      tester.sendEventToBinding(
        PointerPanZoomStartEvent(
          pointer: pointer,
          device: pointer,
          position: point,
          timeStamp: Duration(seconds: pointer),
        ),
      );

  Future<void> move(
    WidgetTester tester,
    Offset point, {
    required int pointer,
    required int timeMs,
    required double pan,
    required double delta,
  }) =>
      tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: pointer,
          device: pointer,
          position: point,
          timeStamp: Duration(seconds: pointer, milliseconds: timeMs),
          pan: Offset(0, pan),
          panDelta: Offset(0, delta),
        ),
      );

  Future<void> end(WidgetTester tester, Offset point, {required int pointer}) =>
      tester.sendEventToBinding(
        PointerPanZoomEndEvent(
          pointer: pointer,
          device: pointer,
          position: point,
          timeStamp: Duration(seconds: pointer, milliseconds: 35),
        ),
      );
}

String _html(int holdStartMs, bool nativeScroll) => '''
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<style>body{margin:0;height:12000px;touch-action:${nativeScroll ? 'auto' : 'none'};
background:linear-gradient(#f8f5ef,#94a68f)}</style></head><body><script>
for (const type of ['touchstart','touchmove','touchend','touchcancel']) {
  document.addEventListener(type, (event) => {
    const point = event.changedTouches[0];
    const sample = {type, timeMs:event.timeStamp, y:point ? point.clientY : 0};
    if (type === 'touchstart') {
      const until = performance.now() + $holdStartMs;
      while (performance.now() < until) { /* bounded renderer-load fixture */ }
    }
    window.flutter_inappwebview.callHandler('popupTouchProbe', sample);
  }, {passive:false});
}
</script></body></html>
''';
