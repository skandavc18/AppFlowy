import 'dart:async';
import 'dart:io';

import 'package:flowy_infra_ui/widget/history_swipe.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Standalone offline native fixture: never imports shared/base.dart, app main,
// auth, preferences, a workspace, or a live browser profile. No cursor warping.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUp(() => binding.platformDispatcher.semanticsEnabledTestValue = true);
  tearDown(() => binding.platformDispatcher.clearSemanticsEnabledTestValue());

  testWidgets(
    'site owns native pan/pinch; articles retain browser gestures',
    (tester) async {
      final baselineHandles = binding.debugOutstandingSemanticsHandles;
      final semantics = tester.ensureSemantics();
      WebViewEnvironment? environment;
      HttpServer? server;
      CustomPlatformViewController? native;
      var creatingEnvironment = false;
      var mountingView = false;
      final index = ValueNotifier(0);
      final size = ValueNotifier(const Size(600, 500));
      final report = <String, dynamic>{
        'case': 'webview_site_gestures',
        'mode': kReleaseMode ? 'release' : 'debug',
        'quiescent': false,
        'measurement_complete': false,
        'cleanup_complete': false,
        'native_dispose_ack': false,
        'environment_dispose_ack': false,
        'semantics_handles_before_body': baselineHandles,
        'cleanup_stage': 'body',
      };
      binding.reportData = report;
      try {
        expect(Platform.isWindows, isTrue);
        expect(
          const bool.fromEnvironment('WEBVIEW_SITE_GESTURES_CONSENT'),
          isTrue,
          reason: 'Coordinator must arrange isolated native execution first.',
        );
        for (final key in [
          'WEBVIEW2_USER_DATA_FOLDER',
          'WEBVIEW2_BROWSER_EXECUTABLE_FOLDER',
          'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS',
        ]) {
          if ((Platform.environment[key] ?? '').isNotEmpty) {
            throw StateError(
              'External WebView overrides prevent an isolated fixture.',
            );
          }
        }
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) {
          request.response.headers.contentType = ContentType.html;
          request.response.write(_html);
          unawaited(request.response.close());
        });
        final root =
            await Directory.systemTemp.createTemp('webview_site_gestures_');
        creatingEnvironment = true;
        final isolatedEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: root.path),
        );
        environment = isolatedEnvironment;
        creatingEnvironment = false;
        final base = 'http://127.0.0.1:${server.port}';
        final created = Completer<InAppWebViewController>();
        var loaded = Completer<void>();
        final webview = InAppWebView(
          webViewEnvironment: isolatedEnvironment,
          initialUrlRequest: URLRequest(url: WebUri('$base/one')),
          initialSettings: InAppWebViewSettings(
            disableHorizontalScroll: true,
            // ignore: avoid_redundant_argument_values
            allowsBackForwardNavigationGestures: true,
          ),
          onWebViewCreated: (controller) => created.complete(controller),
          onLoadStop: (_, __) {
            if (!loaded.isCompleted) loaded.complete();
          },
          onPermissionRequest: (_, request) async =>
              PermissionResponse(resources: request.resources),
        );
        mountingView = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ValueListenableBuilder<Size>(
                  valueListenable: size,
                  child: webview,
                  builder: (_, size, child) => SizedBox.fromSize(
                    size: size,
                    child: ValueListenableBuilder<int>(
                      valueListenable: index,
                      child: child,
                      builder: (_, index, child) => IndexedStack(
                        index: index,
                        children: [
                          child!,
                          const ColoredBox(color: Color(0xfff8f5ef)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        native = tester
            .state<CustomPlatformViewState>(find.byType(CustomPlatformView))
            .controller;
        final controller =
            await created.future.timeout(const Duration(seconds: 20));
        await loaded.future.timeout(const Duration(seconds: 20));
        await tester.pump();
        final texture = tester.widget<Texture>(
          find.descendant(
            of: find.byType(InAppWebView),
            matching: find.byType(Texture),
          ),
        );
        final channel = MethodChannel(
          'com.pichillilorenzo/custom_platform_view_${texture.textureId}',
        );
        await channel.invokeMethod<void>(
          '_startTextureLifecycleProbe',
          'offline-fixture-v1',
        );
        final f = _NativeFixture(tester, controller, channel);
        Future<void> load(String path) async {
          loaded = Completer<void>();
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri('$base$path')),
          );
          await loaded.future.timeout(const Duration(seconds: 10));
          await f.idle();
          await tester.pump();
        }

        await load('/two');
        expect(await controller.canGoBack(), isTrue);

        // Exercises the production CDP query, including real listener metadata.
        for (final region in [
          (const Offset(300, 110), true), // touch-action:none canvas
          (const Offset(40, 280), true), // horizontal scroller
          (const Offset(240, 280), true), // addEventListener pointer handler
          (const Offset(410, 280), true), // open shadow root
          (const Offset(300, 430), false), // ordinary article
        ]) {
          expect(
            await channel.invokeMethod<bool>(
              'querySiteGesturePolicy',
              [region.$1.dx, region.$1.dy],
            ),
            region.$2,
          );
        }
        final mapPoint = f.point(const Offset(300, 110));
        final articlePoint = f.point(const Offset(300, 430));
        await tester.sendEventToBinding(PointerHoverEvent(position: mapPoint));
        final before = await f.diagnostics();
        final gesture = await f.start(mapPoint);
        for (var i = 1; i <= 12; i++) {
          await gesture.update(
            pan: Offset(i * 3.0, i * 1.0),
            scale: 1 + i / 12,
          );
        }
        await gesture.end();
        await f.idle();
        final map = await f.snapshot();
        expect(map['zoom'] as num, greaterThan(1.5));
        expect((map['panX'] as num).abs(), greaterThan(10));
        expect(map['untrusted'], 0);
        expect(map['clicks'], 0);
        expect(map['twoContactMoves'] as num, greaterThan(0));
        expect((await f.diagnostics())['zoomFactor'], before['zoomFactor']);
        expect((await controller.getUrl())!.path, '/two');
        final after = await f.diagnostics();
        for (final key in ['cursorX', 'cursorY', 'cursorVisible']) {
          expect(
            after[key],
            before[key],
            reason: 'Trackpad must not warp/hide the mouse',
          );
        }
        report['map_zoom'] = map['zoom'];
        report['browser_zoom_unchanged'] = true;

        // Start as a genuine one-contact pan, then change into a paired pinch.
        final mixed = await f.start(mapPoint);
        await mixed.update(pan: const Offset(24, 0));
        await f.idle();
        await mixed.update(pan: const Offset(36, 0), scale: 1.5);
        await mixed.update(pan: const Offset(44, 8), scale: 2);
        await mixed.end();
        await f.idle();
        final mixedState = await f.snapshot();
        expect(mixedState['cancels'] as num, greaterThan(0));
        expect(mixedState['clicks'], 0);
        expect(mixedState['zoom'] as num, greaterThan(map['zoom'] as num));
        expect((await f.diagnostics())['zoomFactor'], before['zoomFactor']);

        final tiny = await f.start(mapPoint);
        await tiny.update(pan: const Offset(1, 1), scale: 1.005);
        await tiny.end();
        await f.idle();
        expect((await f.snapshot())['clicks'], 0);

        for (final interruption in ['cancel', 'hidden', 'resize']) {
          report['interruption_under_test'] = interruption;
          final starts = (await f.snapshot())['starts'] as num;
          final interrupted = await f.start(mapPoint);
          await interrupted.update(scale: 1.5);
          await f.idle();
          await f.untilDom(
            () async => ((await f.snapshot())['starts'] as num) > starts,
            '$interruption: paired contact must exist before interruption',
          );
          final cancels = (await f.snapshot())['cancels'] as num;
          if (interruption == 'cancel') {
            await interrupted.cancel();
          } else if (interruption == 'hidden') {
            index.value = 1;
            await tester.pump();
            await interrupted.update(scale: 2);
            await interrupted.end();
            index.value = 0;
            await tester.pump();
          } else {
            size.value = const Size(580, 480);
            await tester.pump();
            await interrupted.update(scale: 2);
            await interrupted.end();
            size.value = const Size(600, 500);
            await tester.pump();
          }
          await f.idle();
          await f.untilDom(
            () async => ((await f.snapshot())['cancels'] as num) > cancels,
            '$interruption: DOM cancellation acknowledgement',
          );
          final state = await f.snapshot();
          expect(
            state['cancels'] as num,
            greaterThan(cancels),
            reason: interruption,
          );
          expect(state['clicks'], 0);
        }

        // Navigation fences the old stream even before Dart receives the event.
        final navigating = await f.start(mapPoint);
        await navigating.update(scale: 1.5);
        await load('/three');
        await navigating.update(scale: 2);
        await navigating.end();
        await f.idle();
        expect((await f.snapshot())['starts'], 0);
        expect((await f.snapshot())['clicks'], 0);

        // Real history entries, not synthetic pushState availability.
        for (final step in [(120.0, '/two'), (-120.0, '/three')]) {
          final history = await f.start(articlePoint);
          for (var i = 1; i <= 6; i++) {
            await history.update(pan: Offset(step.$1 * i / 6, 0));
          }
          await history.end();
          await f.settleHistory();
          expect((await controller.getUrl())!.path, step.$2);
          expect((await f.snapshot())['clicks'], 0);
        }

        final normalZoom = (await f.diagnostics())['zoomFactor'] as double;
        final articlePinch = await f.start(articlePoint);
        await articlePinch.update(scale: 1.5);
        final zoomDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (((await f.diagnostics())['zoomFactor'] as num) <= normalZoom) {
          if (DateTime.now().isAfter(zoomDeadline)) {
            throw StateError('Ordinary-page pinch did not change browser zoom');
          }
          await tester.pump(const Duration(milliseconds: 10));
        }
        await articlePinch.end();
        await f.idle();
        final enlarged = (await f.diagnostics())['zoomFactor'] as double;
        expect(enlarged, greaterThan(normalZoom));
        await channel.invokeMethod<void>('setZoomScale', normalZoom / enlarged);

        // Wheel and ordinary mouse still use native SendMouseInput. Physical
        // touchscreen preservation is covered by the unchanged six-value path
        // and package tests; this fixture does not inject OS touch/move the mouse.
        await tester
            .sendEventToBinding(PointerHoverEvent(position: articlePoint));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: articlePoint,
            scrollDelta: const Offset(0, 20),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final wheel = await f.snapshot();
        expect(wheel['wheels'] as num, greaterThan(0));
        // Chromium converts Windows wheel detents using platform scroll
        // settings; DOM deltaY is not the native mouseData value (20 * 6).
        expect(wheel['lastWheelY'] as num, greaterThan(0));
        report['dom_wheel_delta_y'] = wheel['lastWheelY'];
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
        );
        try {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: articlePoint,
              scrollDelta: const Offset(0, 20),
            ),
          );
        } finally {
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          (await f.snapshot())['wheels'] as num,
          greaterThan(wheel['wheels'] as num),
        );
        // No synthetic pan/pinch has caused a click. A real mouse click still can.
        expect((await f.snapshot())['clicks'], 0);
        await tester.tapAt(articlePoint, kind: PointerDeviceKind.mouse);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect((await f.snapshot())['clicks'], 1);
        expect(tester.takeException(), isNull);
        report['dom_history_wheel_mouse_checks'] = true;
        report['measurement_complete'] = true;
      } finally {
        try {
          report['cleanup_stage'] = 'native_view';
          if (creatingEnvironment) {
            throw StateError(
              'Environment creation has no final reply; cleanup is not proven.',
            );
          }
          final views = find.byType(CustomPlatformView, skipOffstage: false);
          if (native == null && views.evaluate().isNotEmpty) {
            native = tester.state<CustomPlatformViewState>(views).controller;
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          if (mountingView && native == null) {
            throw StateError(
              'Missing native disposal owner; cleanup unproven.',
            );
          }
          await native?.dispose();
          report['texture_lifecycle'] = native?.disposalDiagnostics;
          report['native_dispose_ack'] = native != null;
          report['cleanup_stage'] = 'environment';
          final ownedEnvironment = environment;
          if (ownedEnvironment != null) {
            await MethodChannel(
              'com.pichillilorenzo/flutter_webview_environment_${ownedEnvironment.id}',
            ).invokeMethod<void>('dispose');
            report['environment_dispose_ack'] = true;
          }
          if (native != null) {
            expect(native.disposalDiagnostics?['schema'], 1);
            expect(native.disposalDiagnostics?['stages'], [0, 1, 2, 3, 4, 5]);
          }
          report['quiescent'] = native != null && ownedEnvironment != null;
        } finally {
          try {
            await server?.close(force: true);
          } finally {
            index.dispose();
            size.dispose();
            semantics.dispose();
            report['semantics_handles_after_body'] =
                binding.debugOutstandingSemanticsHandles;
            expect(binding.debugOutstandingSemanticsHandles, baselineHandles);
          }
        }
        report['remaining_transient_callbacks'] =
            binding.transientCallbackCount;
        expect(binding.transientCallbackCount, 0);
        report['cleanup_stage'] = 'complete';
        report['cleanup_complete'] = report['quiescent'] == true;
        // Leave only the isolated temporary profile for OS cleanup; no app data
        // is reset or deleted, and no native app/window close is requested here.
      }
    },
    timeout: Timeout.none,
  );
}

class _NativeFixture {
  _NativeFixture(this.tester, this.controller, this.channel);
  final WidgetTester tester;
  final InAppWebViewController controller;
  final MethodChannel channel;
  final clock = Stopwatch()..start();
  int nextPointer = 100;

  Offset point(Offset local) =>
      tester.getTopLeft(find.byType(InAppWebView)) + local;
  Future<Map<dynamic, dynamic>> diagnostics() async => (await channel
      .invokeMapMethod('_getSiteGestureDiagnostics', 'offline-fixture-v1')
      .timeout(const Duration(seconds: 5)))!;

  Future<void> idle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while ((await diagnostics())['idle'] != true) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Native input slot did not drain');
      }
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> untilDom(Future<bool> Function() ready, String phase) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!await ready()) {
      if (DateTime.now().isAfter(deadline)) throw StateError(phase);
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<_Gesture> start(Offset point) async {
    await idle();
    // History completion updates flags before its IgnorePointer is rebuilt.
    // A test's next gesture must wait for the actual input surface, not flags.
    await tester.pump();
    final target = tester.renderObject(find.byType(CustomPlatformView));
    expect(
      tester
          .hitTestOnBinding(point)
          .path
          .any((entry) => identical(entry.target, target)),
      isTrue,
    );
    final pointer = nextPointer++;
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
      pointer: pointer,
    );
    await gesture.panZoomStart(point, timeStamp: clock.elapsed);
    // Allow the ONE start-policy query to settle, without per-frame DOM reads.
    await idle();
    return _Gesture(this, gesture, point, pointer);
  }

  Future<Map<dynamic, dynamic>> snapshot() async => Map<dynamic, dynamic>.from(
        await controller
            .evaluateJavascript(source: 'window.fixtureSnapshot()')
            .timeout(const Duration(seconds: 5)) as Map,
      );

  Future<void> settleHistory() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    do {
      await tester.pump(const Duration(milliseconds: 20));
      final surface =
          tester.widget<HistorySwipeSurface>(find.byType(HistorySwipeSurface));
      if (!surface.controller.isActive && surface.pageReady) return;
    } while (DateTime.now().isBefore(deadline));
    throw StateError('History transition did not complete');
  }
}

class _Gesture {
  _Gesture(this.fixture, this.gesture, this.point, this.pointer);
  final _NativeFixture fixture;
  final TestGesture gesture;
  final Offset point;
  final int pointer;

  Future<void> update({Offset pan = Offset.zero, double scale = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await gesture.panZoomUpdate(
      point,
      pan: pan,
      scale: scale,
      timeStamp: fixture.clock.elapsed,
    );
  }

  Future<void> end() async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await gesture.panZoomEnd(timeStamp: fixture.clock.elapsed);
  }

  // Match cancelPointer's synthesized event, but preserve TEST provenance.
  // Live binding classifies its deferred queue as device input and does not
  // deliver it to the test recognizers. Trackpad kind is invalid for cancel.
  Future<void> cancel() => fixture.tester.sendEventToBinding(
        PointerCancelEvent(pointer: pointer, position: point),
      );
}

const _html = '''<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
<style>
body{margin:0;height:5000px;padding-top:350px;background:#f8f5ef;color:#302c26}
#map{position:fixed;top:0;left:0;width:100%;height:220px;touch-action:none;background:#ddd3c1}
#scroller{position:fixed;top:250px;left:10px;width:100px;height:60px;overflow-x:auto}
#scroller div{width:600px;height:40px}
#handler{position:fixed;top:250px;left:200px;width:100px;height:60px}
#shadow{position:fixed;top:250px;left:370px;width:100px;height:60px}
</style></head><body><canvas id="map" width="600" height="220"></canvas>
<div id="scroller"><div>Local horizontal content</div></div>
<div id="handler">Pointer handler</div><div id="shadow"></div>
<article>Offline ordinary article with browser-owned pan and history.</article>
<script>
const state={zoom:1,panX:0,panY:0,starts:0,cancels:0,ends:0,clicks:0,
  twoContactMoves:0,untrusted:0,wheels:0,lastWheelY:0};
const map=document.getElementById('map'), ctx=map.getContext('2d');
let baseDistance=0,baseZoom=1,lastCenter=null;
const center=ts=>({x:Array.from(ts).reduce((s,t)=>s+t.clientX,0)/ts.length,
  y:Array.from(ts).reduce((s,t)=>s+t.clientY,0)/ts.length});
const distance=ts=>Math.hypot(ts[0].clientX-ts[1].clientX,ts[0].clientY-ts[1].clientY);
const draw=()=>{ctx.clearRect(0,0,600,220);ctx.save();ctx.translate(300+state.panX,110+state.panY);
  ctx.scale(state.zoom,state.zoom);ctx.strokeStyle='#61735c';ctx.strokeRect(-40,-30,80,60);ctx.restore();};
map.addEventListener('touchstart',e=>{state.starts++;if(!e.isTrusted)state.untrusted++;
  e.preventDefault();lastCenter=center(e.touches);
  if(e.touches.length===2){baseDistance=distance(e.touches);baseZoom=state.zoom;}},{passive:false});
map.addEventListener('touchmove',e=>{if(!e.isTrusted)state.untrusted++;e.preventDefault();
  const c=center(e.touches);if(lastCenter){state.panX+=c.x-lastCenter.x;state.panY+=c.y-lastCenter.y;}
  lastCenter=c;if(e.touches.length===2&&baseDistance>0){state.twoContactMoves++;
    state.zoom=baseZoom*distance(e.touches)/baseDistance;}draw();},{passive:false});
map.addEventListener('touchend',()=>{state.ends++;lastCenter=null;});
map.addEventListener('touchcancel',()=>{state.cancels++;lastCenter=null;});
document.addEventListener('click',()=>state.clicks++);
document.addEventListener('wheel',e=>{state.wheels++;state.lastWheelY=e.deltaY;},{passive:true});
document.getElementById('handler').addEventListener('pointermove',()=>{});
document.getElementById('shadow').attachShadow({mode:'open'}).innerHTML=
  '<div style="width:100px;height:60px;touch-action:none">Shadow region</div>';
window.fixtureSnapshot=()=>({...state});draw();
</script></body></html>''';
