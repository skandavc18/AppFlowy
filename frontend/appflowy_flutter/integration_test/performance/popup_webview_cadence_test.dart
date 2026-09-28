import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Offline, standalone fixture. No app main/auth/preferences, real URLs, pixels,
// user profile, OS input, or browser flag experiments. See the adjacent runbook.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final nativeCleanup = Completer<bool>();
  setUp(() {
    // Windows can request accessibility after first paint. Establish the
    // binding-owned platform handle BEFORE testWidgets snapshots its count;
    // an extra tester-owned handle cannot stabilize that separate owner.
    binding.platformDispatcher.semanticsEnabledTestValue = true;
  });
  tearDown(() {
    binding.platformDispatcher.clearSemanticsEnabledTestValue();
    // A preflight failure or unfinished cleanup is never a safe-close signal.
    if (!nativeCleanup.isCompleted) nativeCleanup.complete(false);
  });
  if (const bool.fromEnvironment('WEBVIEW_CADENCE_NATIVE_REPORT')) {
    unawaited(_writeNativeReport(binding, nativeCleanup.future));
  }

  testWidgets('offline WebView DOM versus texture cadence', (tester) async {
    // Flutter verifies handle ownership before tearDown runs. Keep native
    // accessibility stable, but release our handle inside this test body.
    final semanticsHandlesBefore = binding.debugOutstandingSemanticsHandles;
    final semantics = tester.ensureSemantics();
    try {
      expect(Platform.isWindows, isTrue);
      expect(
        const bool.fromEnvironment('WEBVIEW_CADENCE_CONSENT'),
        isTrue,
        reason:
            'Coordinator must obtain consent and close the app before running.',
      );
      for (final key in [
        'WEBVIEW2_USER_DATA_FOLDER',
        'WEBVIEW2_BROWSER_EXECUTABLE_FOLDER',
        'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS',
      ]) {
        if ((Platform.environment[key] ?? '').isNotEmpty) {
          throw StateError(
              'External WebView override prevents isolated measurement.');
        }
      }
      final referenceHz = double.parse(
        const String.fromEnvironment('PERF_REFERENCE_HZ', defaultValue: '60'),
      );
      expect(referenceHz.isFinite && referenceHz > 0, isTrue);
      final logging =
          PlatformInAppWebViewController.debugLoggingSettings.enabled;
      final environmentLogging =
          PlatformWebViewEnvironment.debugLoggingSettings.enabled;
      PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
      PlatformWebViewEnvironment.debugLoggingSettings.enabled = false;
      WebViewEnvironment? environment;
      var environmentCreationPending = false;
      CustomPlatformViewController? nativeController;
      var mountingView = false;
      final size = ValueNotifier(const Size(600, 500));
      final loaded = Completer<void>();
      final created = Completer<InAppWebViewController>();
      final report = <String, dynamic>{
        'run': _runLabel,
        'schema': 2,
        'fixture_revision': 3,
        'semantics_handles_before_body': semanticsHandlesBefore,
        'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
        'reference_hz': referenceHz,
        'dart_version': Platform.version.split(' ').first,
        'phases': <Map<String, dynamic>>[],
        'claim': 'callback_cadence_not_monitor_presentation',
      };
      binding.reportData = report;
      try {
        final root =
            await Directory.systemTemp.createTemp('appflowy_texture_cadence_');
        environmentCreationPending = true;
        environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: root.path,
            // Exactly the current BookmarkWebEnvironment argument, not a new
            // performance flag. Only its profile is substituted with a temp one.
            additionalBrowserArguments:
                '--disable-features=CalculateNativeWinOcclusion',
          ),
        ).timeout(const Duration(seconds: 20));
        environmentCreationPending = false;
        final webview = InAppWebView(
          webViewEnvironment: environment,
          initialData: InAppWebViewInitialData(data: _html),
          initialSettings: InAppWebViewSettings(
            disableHorizontalScroll: true,
            // ignore: avoid_redundant_argument_values
            allowsBackForwardNavigationGestures: true,
          ),
          onWebViewCreated: (controller) {
            if (!created.isCompleted) created.complete(controller);
          },
          onLoadStop: (_, __) {
            if (!loaded.isCompleted) loaded.complete();
          },
          onPermissionRequest: (_, request) async =>
              PermissionResponse(resources: request.resources),
        );
        mountingView = true;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<Size>(
                valueListenable: size,
                child: webview,
                builder: (_, value, child) => SizedBox(
                  width: value.width,
                  height: value.height,
                  child: child,
                ),
              ),
            ),
          ),
        ));
        nativeController = tester
            .state<CustomPlatformViewState>(find.byType(CustomPlatformView))
            .controller;
        final controller =
            await created.future.timeout(const Duration(seconds: 20));
        await loaded.future.timeout(const Duration(seconds: 20));
        await tester.pump();
        final texture = tester.widget<Texture>(find.descendant(
          of: find.byType(InAppWebView),
          matching: find.byType(Texture),
        ));
        final channel = MethodChannel(
            'com.pichillilorenzo/custom_platform_view_${texture.textureId}');
        await channel
            .invokeMethod<void>(
                '_startTextureLifecycleProbe', 'offline-fixture-v1')
            .timeout(const Duration(seconds: 5));
        final version = await controller
            .callDevToolsProtocolMethod(
              methodName: 'Browser.getVersion',
            )
            .timeout(const Duration(seconds: 5));
        // Allowlist runtime facts; do not include userAgent or arbitrary replies.
        report['chromium_product'] = version?['product'];
        report['chromium_js_version'] = version?['jsVersion'];
        report['display_hz'] =
            binding.platformDispatcher.views.first.display.refreshRate;
        report['device_pixel_ratio'] = tester.view.devicePixelRatio;

        // Warm the same view once. No per-frame JS bridge calls.
        await _startDom(controller, animate: true, durationMs: 1000);
        await _finishDom(controller);
        for (final phase in [
          'idle_before',
          'animation',
          'native_wheel_text',
          'resize_animation',
          'idle_after'
        ]) {
          final timings = <ui.FrameTiming>[];
          var timingsTruncated = false;
          void onTimings(List<ui.FrameTiming> values) {
            for (final value in values) {
              if (timings.length < 4096) {
                timings.add(value);
              } else {
                timingsTruncated = true;
              }
            }
          }

          // Idle flush lets previous Flutter timing batches retire; it is not
          // part of the measured window and does not request Flutter frames.
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          await channel
              .invokeMethod<void>(
                  '_startTextureCadenceProbe', 'offline-fixture-v1')
              .timeout(const Duration(seconds: 5));
          binding.addTimingsCallback(onTimings);
          Map<String, dynamic>? native;
          try {
            final animate = phase == 'animation' || phase == 'resize_animation';
            await _startDom(controller, animate: animate, durationMs: 4000);
            final inputTimes = <double>[];
            final clock = Stopwatch()..start();
            if (phase == 'native_wheel_text') {
              final point = tester.getCenter(find.byType(InAppWebView));
              await tester
                  .sendEventToBinding(PointerHoverEvent(position: point));
              // Fixed synthetic wheel workload. JS observes scrollY but NEVER
              // assigns it. SendMouseInput/Chromium still own scroll animation.
              for (var i = 0; i < 50; i++) {
                inputTimes.add(clock.elapsedMicroseconds / 1000);
                await tester.sendEventToBinding(PointerScrollEvent(
                  position: point,
                  scrollDelta: const Offset(0, 20),
                  timeStamp: clock.elapsed,
                ));
                await Future<void>.delayed(const Duration(milliseconds: 40));
              }
            } else if (phase == 'resize_animation') {
              for (final value in [
                const Size(520, 420),
                const Size(640, 480),
                const Size(600, 500)
              ]) {
                await Future<void>.delayed(const Duration(milliseconds: 700));
                inputTimes.add(clock.elapsedMicroseconds / 1000);
                size.value = value;
                await tester.pump();
              }
            }
            final dom = await _finishDom(controller);
            final raw = await channel
                .invokeMapMethod<String, dynamic>('_stopTextureCadenceProbe')
                .timeout(const Duration(seconds: 5));
            expect(raw, isNotNull);
            native = raw!;
            // FrameTiming delivery may be batched. These timings supplement the
            // native measurements; they do not force or prove texture redraws.
            await Future<void>.delayed(const Duration(milliseconds: 1100));
            final phaseReport = <String, dynamic>{
              'phase': phase,
              'dom': dom,
              'dom_cadence': _cadence(_numbers(dom['raf_ms']), referenceHz),
              'native': native,
              'native_summary': _nativeSummary(native, referenceHz),
              'input_or_resize_ms': inputTimes,
              'flutter_timings_truncated': timingsTruncated,
              'flutter_build_ms': _distribution(timings
                  .map((t) => t.buildDuration.inMicroseconds / 1000)
                  .toList()),
              'flutter_raster_ms': _distribution(timings
                  .map((t) => t.rasterDuration.inMicroseconds / 1000)
                  .toList()),
              'flutter_raster_finish_cadence': _cadence(
                timings
                    .map((t) =>
                        t.timestampInMicroseconds(ui.FramePhase.rasterFinish) /
                        1000)
                    .toList(),
                referenceHz,
              ),
            };
            (report['phases'] as List).add(phaseReport);
            expect(native['schema'], 1);
            expect(native['expired'], isFalse);
            expect(native['truncated'], isFalse);
            expect(dom['truncated'], isFalse);
            expect(dom['hidden'], isFalse);
            expect(dom['completed'], isTrue);
            expect(dom['marker_out_of_bounds'], 0);
            expect(dom['marker_samples'], _numbers(dom['raf_ms']).length);
            expect(dom['elapsed_ms'] as num, greaterThanOrEqualTo(4000));
            expect(_numbers(dom['raf_ms']).length, greaterThan(2));
            final events = (native['events'] as List).cast<List>();
            if (!phase.startsWith('idle')) {
              expect(events.where((e) => e[0] == 1), isNotEmpty);
              expect(events.where((e) => e[0] == 4 || e[0] == 5), isNotEmpty);
            }
            if (phase == 'native_wheel_text') {
              expect(
                  (dom['end_scroll_y'] as num) - (dom['start_scroll_y'] as num),
                  greaterThan(0));
            }
            if (phase == 'resize_animation') {
              expect(events.where((e) => e[0] == 6), isNotEmpty);
            }
          } finally {
            binding.removeTimingsCallback(onTimings);
            if (native == null) {
              await channel
                  .invokeMethod<void>('_stopTextureCadenceProbe')
                  .timeout(const Duration(seconds: 5));
            }
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        try {
          if (environmentCreationPending) {
            // A timeout does not cancel the native creation callback. Without its
            // environment ID, neither cleanup nor safe window close is proven.
            throw StateError('Native environment creation has no final reply.');
          }
          // Save the controller even if mounting failed before the normal lookup.
          final platformViews = find.byType(CustomPlatformView);
          if (nativeController == null && platformViews.evaluate().isNotEmpty) {
            nativeController =
                tester.state<CustomPlatformViewState>(platformViews).controller;
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          if (mountingView && nativeController == null) {
            throw StateError(
                'Native controller cleanup could not be observed.');
          }
          final disposalClock = Stopwatch()..start();
          await nativeController
              ?.dispose()
              .timeout(const Duration(seconds: 10));
          report['controller_dispose_ms'] =
              disposalClock.elapsedMicroseconds / 1000;
          report['texture_lifecycle'] = nativeController?.disposalDiagnostics;
          if (environment != null) {
            // Dispose only the fixture's actual native environment ID.
            await MethodChannel(
                    'com.pichillilorenzo/flutter_webview_environment_${environment.id}')
                .invokeMethod<void>('dispose')
                .timeout(const Duration(seconds: 5));
          }
          report['environment_dispose_ack'] = environment != null ? 1 : 0;
          // Validate instrumentation after cleanup, so even an early failure
          // before probe arming cannot strand the fixture's environment.
          if (nativeController != null) {
            expect(nativeController.disposalDiagnostics?['schema'], 1);
            expect(nativeController.disposalDiagnostics?['stages'],
                [0, 1, 2, 3, 4, 5]);
          }
          report['quiescent'] = true;
          if (!nativeCleanup.isCompleted) nativeCleanup.complete(true);
        } finally {
          if (!nativeCleanup.isCompleted) nativeCleanup.complete(false);
          size.dispose();
          PlatformInAppWebViewController.debugLoggingSettings.enabled = logging;
          PlatformWebViewEnvironment.debugLoggingSettings.enabled =
              environmentLogging;
        }
        // Native processes can retain locks. Never reset/delete an app profile;
        // this fixture's temporary directory is intentionally left for OS cleanup.
      }
    } finally {
      semantics.dispose();
      binding.reportData?['semantics_handles_after_body'] =
          binding.debugOutstandingSemanticsHandles;
      expect(binding.debugOutstandingSemanticsHandles, semanticsHandlesBefore);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

String get _runLabel =>
    Platform.environment['WEBVIEW_CADENCE_TRIAL'] ??
    const String.fromEnvironment('PERF_RUN', defaultValue: 'baseline');

Future<void> _writeNativeReport(
  IntegrationTestWidgetsFlutterBinding binding,
  Future<bool> nativeCleanup,
) async {
  final passed = await binding.allTestsPassed.future;
  // The framework may report an asynchronous failure before native cleanup
  // finishes. Its result alone is not a disposal barrier.
  final quiescent = await nativeCleanup;
  final run = _runLabel;
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(run)) {
    throw StateError('Invalid offline cadence trial label.');
  }
  final file = File('build/performance/popup_webview_cadence_$run.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      ...?binding.reportData,
      'success': passed,
      'quiescent': quiescent,
      'results': binding.results.map(
        (name, result) => MapEntry(name, result.toString()),
      ),
    }),
    flush: true,
  );
  // A failed test can still be safely cleaned up, but .done is NOT success.
  // Never invite normal window close with a pending native unregister.
  if (quiescent) {
    await File('${file.path}.done').writeAsString('quiescent', flush: true);
  }
}

Future<void> _startDom(
  InAppWebViewController controller, {
  required bool animate,
  required int durationMs,
}) async {
  final result = await controller
      .evaluateJavascript(
        source:
            'window.__cadenceResult = window.__measureCadence($durationMs, $animate); true;',
      )
      .timeout(const Duration(seconds: 5));
  expect(result, isTrue);
}

Future<Map<String, dynamic>> _finishDom(
    InAppWebViewController controller) async {
  final result = await controller
      .callAsyncJavaScript(
        functionBody: 'return await window.__cadenceResult;',
      )
      .timeout(const Duration(seconds: 8));
  expect(result?.error, isNull);
  return Map<String, dynamic>.from(result!.value as Map);
}

List<double> _numbers(dynamic values) =>
    (values as List).map((v) => (v as num).toDouble()).toList();

Map<String, dynamic> _distribution(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  double? percentile(double fraction) =>
      sorted.isEmpty ? null : sorted[(fraction * sorted.length).ceil() - 1];
  return {
    'count': values.length,
    'median': percentile(0.5),
    'p95': percentile(0.95)
  };
}

Map<String, dynamic> _cadence(List<double> timestamps, double referenceHz) {
  final gaps = <double>[];
  for (var i = 1; i < timestamps.length; i++) {
    gaps.add(timestamps[i] - timestamps[i - 1]);
  }
  final span = timestamps.length < 2 ? 0.0 : timestamps.last - timestamps.first;
  return {
    'samples': timestamps.length,
    'interval_ms': _distribution(gaps),
    'fps_over_sample_span': span <= 0 ? null : gaps.length * 1000 / span,
    // Estimate relative to an explicitly declared reference, NOT an observed
    // count of dropped compositor/present frames. Idle gaps are intentional.
    'estimated_missed_reference_slots': gaps.fold<int>(
        0,
        (sum, gap) =>
            sum + math.max(0, (gap * referenceHz / 1000).round() - 1)),
  };
}

Map<String, dynamic> _nativeSummary(Map<String, dynamic> raw, double hz) {
  final events = (raw['events'] as List).cast<List>();
  final callbacks = events.where((e) => e[0] == 4 || e[0] == 5).toList();
  final seen = <int>{};
  final unique = callbacks
      .where((e) => (e[2] as int) > 0 && seen.add(e[2] as int))
      .toList();
  final captures = events.where((e) => e[0] == 1).toList();
  final captureTimes = <int, double>{
    for (final event in captures) event[2] as int: (event[1] as num).toDouble(),
  };
  final captureAges = <double>[];
  for (final event in callbacks) {
    final capturedAt = captureTimes[event[2]];
    if (capturedAt != null) {
      captureAges.add((event[1] as num).toDouble() - capturedAt);
    }
  }
  List<double> times(Iterable<List> rows) =>
      rows.map((e) => (e[1] as num).toDouble()).toList();
  return {
    'arrival': _cadence(times(events.where((e) => e[0] == 0)), hz),
    'capture': _cadence(times(captures), hz),
    'notification_attempt': _cadence(times(events.where((e) => e[0] == 3)), hz),
    'texture_callback': _cadence(times(callbacks), hz),
    'unique_capture_texture_callback': _cadence(times(unique), hz),
    'callback_work_ms':
        _distribution(callbacks.map((e) => (e[3] as num).toDouble()).toList()),
    'capture_to_callback_ms': _distribution(captureAges),
    'cap_drops': events.where((e) => e[0] == 2).length,
    'repeated_capture_callbacks':
        callbacks.where((e) => (e[2] as int) > 0).length - unique.length,
    'pre_probe_capture_callbacks': callbacks.where((e) => e[2] == 0).length,
    // Includes coalescing, cap drops and stop-window tail. Not GPU drops.
    'captures_without_callback_in_window':
        captures.where((e) => !seen.contains(e[2])).length,
    'pool_recreate_attempts': events.where((e) => e[0] == 6).length,
  };
}

const _html = '''
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<style>
html{color-scheme:light}body{margin:0;background:#f8f5ef;color:#302c26;font:18px/1.7 sans-serif}
article{max-width:70ch;margin:auto;padding:24px}p{border-bottom:1px solid #ddd3c1}
#marker{position:fixed;left:0;top:12px;width:18vw;height:10px;background:#6b8061;will-change:transform;transform:translateX(41vw)}
@media(max-width:550px){article{font-size:16px;padding:12px}}
</style></head><body><div id="marker"></div><article id="text"></article><script>
const article = document.getElementById('text');
for(let i=0;i<600;i++){
  const p=document.createElement('p');
  p.textContent='Synthetic reading paragraph '+i+'. A deterministic offline text workload with wrapping lines and native scrolling.';
  article.appendChild(p);
}
window.__measureCadence=(duration,animate)=>new Promise(resolve=>{
  const stamps=[]; const start=performance.now(); const startY=scrollY;
  const marker=document.getElementById('marker');
  let done=false, raf=0, truncated=false, markerSamples=0, markerOutOfBounds=0;
  const finish=(completed)=>{
    if(done)return; done=true; cancelAnimationFrame(raf); clearTimeout(deadline);
    resolve({raf_ms:stamps,elapsed_ms:performance.now()-start,completed,
      truncated,hidden:document.hidden,start_scroll_y:startY,end_scroll_y:scrollY,
      marker_samples:markerSamples,marker_out_of_bounds:markerOutOfBounds,
      viewport_width:innerWidth,viewport_height:innerHeight});
  };
  const deadline=setTimeout(()=>finish(false),duration+2000);
  const frame=(t)=>{
    if(done)return;
    if(stamps.length<2048)stamps.push(t-start);else{truncated=true;finish(false);return;}
    // Viewport-relative units remain bounded even BETWEEN rAFs during resize.
    // Left spans 5..77vw; the complete 18vw marker stays within 5..95vw.
    if(animate)marker.style.transform='translateX('+(41+Math.sin((t-start)/500)*36)+'vw)';
    const bounds=marker.getBoundingClientRect(); markerSamples++;
    if(bounds.left<0 || bounds.right>innerWidth || bounds.width<=0)markerOutOfBounds++;
    if(t-start>=duration){finish(true);return;}
    raf=requestAnimationFrame(frame);
  };
  raf=requestAnimationFrame(frame);
});
</script></body></html>
''';
