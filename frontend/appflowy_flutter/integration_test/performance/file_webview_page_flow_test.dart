import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/collection/views/email/email_body_view.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/markdown_preview_fonts.dart';
import 'package:appflowy/shared/document_viewer/native_file_page_scroll.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';

// Standalone offline native fixture. No app main, integration base, live
// profile, auth, workspace service, remote URL, or platform preferences.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUp(() => binding.platformDispatcher.semanticsEnabledTestValue = true);
  tearDown(() => binding.platformDispatcher.clearSemanticsEnabledTestValue());

  for (final format in ['html', 'markdown', 'email']) {
    testWidgets('$format: native vertical page flow and late ACK fencing',
        (tester) async {
      expect(Platform.isWindows, isTrue);
      expect(
          const bool.fromEnvironment('FILE_WEBVIEW_PAGE_FLOW_CONSENT'), isTrue,
          reason: 'Coordinator must arrange isolated native execution.');
      for (final name in [
        'WEBVIEW2_USER_DATA_FOLDER',
        'WEBVIEW2_BROWSER_EXECUTABLE_FOLDER',
        'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS'
      ]) {
        if ((Platform.environment[name] ?? '').isNotEmpty) {
          throw StateError(
              'External WebView configuration defeats profile isolation.');
        }
      }
      final baselineHandles = binding.debugOutstandingSemanticsHandles;
      final semantics = tester.ensureSemantics();
      final chrome = StandaloneFileChromeController();
      final oldFetching = GoogleFonts.config.allowRuntimeFetching;
      GoogleFonts.config.allowRuntimeFetching = false;
      WebViewEnvironment? environment;
      CustomPlatformViewController? native;
      _HeldAckController? heldTransport;
      var creatingEnvironment = false;
      var mountingView = false;
      final report = <String, dynamic>{
        'case': 'file_webview_page_flow_$format',
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
        final root =
            await Directory.systemTemp.createTemp('file_webview_page_flow_');
        final name = format == 'markdown' ? 'offline.md' : 'offline.html';
        final file = File('${root.path}/$name');
        await file.writeAsString(format == 'markdown' ? _markdown : _html);
        if (format == 'markdown') await loadMarkdownPreviewFontFaces();
        creatingEnvironment = true;
        final isolatedEnvironment = await WebViewEnvironment.create(
            settings: WebViewEnvironmentSettings(
                userDataFolder: '${root.path}/profile'));
        environment = isolatedEnvironment;
        creatingEnvironment = false;
        InAppWebViewController? controller;
        var created = 0;
        mountingView = true;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.light().copyWith(platform: TargetPlatform.windows),
          home: AppFlowyTheme(
            data: AppFlowyDefaultTheme().light(),
            child: Scaffold(
                body: PremiumScrollScope(
              enabled: true,
              child: Center(
                  child: SizedBox(
                width: 720,
                height: 680,
                child: NativeFileWebViewEnvironment(
                  environment: isolatedEnvironment,
                  onCreated: (value) {
                    controller = value;
                    created++;
                  },
                  child: StandaloneFileScope(
                    canvas: const Color(0xfff8f5ef),
                    rendererName: name,
                    displayName: 'Offline file',
                    chrome: chrome,
                    canEdit: () => false,
                    canRead: () => true,
                    editable: false,
                    available: true,
                    child: StandaloneFilePage(
                      header: SizedBox(
                          key: const ValueKey('native-file-header'),
                          height: 200,
                          child: Row(children: [
                            const Text('Offline file'),
                            const Spacer(),
                            TextButton(
                                key: const ValueKey('native-file-tools'),
                                onPressed: () {},
                                child: const Text('Tools'))
                          ])),
                      body: LayoutBuilder(
                          builder: (context, constraints) => format == 'email'
                              ? EmailBodyView(
                                  html: prepareHtmlPreviewDocument(_html),
                                  theme: emailThemeOf(context))
                              : FilePreview(
                                  file: file,
                                  name: name,
                                  kind: format == 'markdown'
                                      ? FilePreviewKind.markdown
                                      : FilePreviewKind.html,
                                  metadata: const {},
                                  onMetadataChanged: (_) {},
                                  editable: false,
                                  framed: false,
                                  height: constraints.maxHeight)),
                    ),
                  ),
                ),
              )),
            )),
          ),
        ));
        await _until(tester, () async => controller != null);
        final web = controller!;
        native = tester
            .state<CustomPlatformViewState>(find.byType(CustomPlatformView))
            .controller;
        final texture = tester.widget<Texture>(find.descendant(
            of: find.byType(InAppWebView), matching: find.byType(Texture)));
        final channel = MethodChannel(
            'com.pichillilorenzo/custom_platform_view_${texture.textureId}');
        await channel.invokeMethod<void>(
            '_startTextureLifecycleProbe', 'offline-fixture-v1');
        await _until(
            tester,
            () async =>
                await web.evaluateJavascript(
                    source:
                        'typeof globalThis.${NativeFilePageScrollBridge.runtime} === "object"') ==
                true);
        final page =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        final bodyElement = tester.element(find.byType(InAppWebView));
        final initialSize = tester.getSize(find.byType(InAppWebView));
        final header = find.byKey(const ValueKey('native-file-header'),
            skipOffstage: false);
        final tools = find.byKey(const ValueKey('native-file-tools'),
            skipOffstage: false);
        final headerRect = tester.getRect(header);
        final toolsRect = tester.getRect(tools);
        final point =
            tester.getRect(find.byType(StandaloneFilePage)).bottomCenter -
                const Offset(0, 30);
        final bridge = tester
            .widget<NativeFilePageScroll>(find.byType(NativeFilePageScroll))
            .bridge;
        final transport = _HeldAckController(web);
        heldTransport = transport;
        // Only the transport's return is delayable. The production bridge, native
        // WebView, local server, sanitized document and actual DOM mover remain real.
        bridge.attach(transport);
        expect(await bridge.install(kinetic: false), isTrue);
        await web.evaluateJavascript(source: '''
window.__fixtureWheel = {count:0, delta:0, prevented:false};
document.addEventListener('wheel', e => {
  window.__fixtureWheel = {count:window.__fixtureWheel.count+1,
    delta:e.deltaY*(e.deltaMode===1?16:e.deltaMode===2?innerHeight:1),
    prevented:e.defaultPrevented};
}, {capture:true, passive:true});
''');
        Future<double> top() async => (await web.evaluateJavascript(
                source: 'document.scrollingElement.scrollTop') as num)
            .toDouble();
        Future<void> idle() => _until(tester, () async {
              final nativeState = await channel.invokeMapMethod(
                  '_getSiteGestureDiagnostics', 'offline-fixture-v1');
              if (nativeState?['idle'] != true) return false;
              return await web.evaluateJavascript(
                      source:
                          '(() => {const s=globalThis.${NativeFilePageScrollBridge.runtime}.snapshot();'
                          'return !s.busy && !s.pending && !s.active;})()') ==
                  true;
            });
        Future<double> wheel(double delta, {bool wait = true}) async {
          final before = (await web.evaluateJavascript(
                  source: 'window.__fixtureWheel.count') as num)
              .toInt();
          await tester.sendEventToBinding(PointerHoverEvent(position: point));
          await tester.sendEventToBinding(PointerScrollEvent(
              position: point, scrollDelta: Offset(0, delta)));
          await _until(
              tester,
              () async =>
                  (await web.evaluateJavascript(
                      source: 'window.__fixtureWheel.count') as num) >
                  before);
          if (wait) await idle();
          return (await web.evaluateJavascript(
                  source: 'window.__fixtureWheel.delta') as num)
              .toDouble();
        }

        final first = await wheel(5);
        expect(first, inExclusiveRange(0, 200));
        expect(await top(), 0);
        expect(page.outerController.offset, closeTo(first, .01));
        await tester.pump();
        expect(
            tester.getRect(header).top, closeTo(headerRect.top - first, .01));
        expect(tester.getRect(tools).top, closeTo(toolsRect.top - first, .01));
        expect(tester.getRect(tools).right, toolsRect.right);
        final second = await wheel(120);
        expect(page.outerController.offset, 200);
        expect(await top(), closeTo(first + second - 200, 1));
        await tester.pump();
        expect(header.hitTestable(), findsNothing);
        expect(tester.getSize(find.byType(InAppWebView)), initialSize);
        expect(tester.element(find.byType(InAppWebView)), same(bodyElement));
        expect(created, 1);

        // Native selection remains available and is not rebuilt by scrolling.
        await web.evaluateJavascript(source: '''
(() => {const range=document.createRange(); range.selectNodeContents(document.getElementById('selection'));
const selection=getSelection(); selection.removeAllRanges(); selection.addRange(range);})();
''');
        expect(
            await web.evaluateJavascript(source: 'getSelection().toString()'),
            'Selection survives page flow');
        await wheel(5);
        expect(
            await web.evaluateJavascript(source: 'getSelection().toString()'),
            'Selection survives page flow');

        // A nested scroll pane is NOT the page boundary: both it and the root
        // must drain before any reverse remainder can reveal the Flutter header.
        await web.evaluateJavascript(source: '''
    (() => { const pane=document.createElement('div'); pane.id='nested-pane';
    pane.style.cssText='position:fixed;inset:0;overflow-y:auto;background:inherit';
    pane.innerHTML='<div style="height:3000px">Local nested content</div>';
    document.body.appendChild(pane); pane.scrollTop=30;
    document.scrollingElement.scrollTop=50; })();
    ''');
        final nestedReverse = await wheel(-40);
        expect(
            await web.evaluateJavascript(
                source: 'document.getElementById("nested-pane").scrollTop'),
            0);
        expect(await top(), 0);
        expect(page.outerController.offset,
            closeTo((280 + nestedReverse).clamp(0, 200), 1));
        await web.evaluateJavascript(
            source: 'document.getElementById("nested-pane").remove();');
        page.outerController.jumpTo(200);
        await tester.pump();

        // Delayed REAL native measurement: body reaches zero before the header
        // moves. Release promptly; deadline behavior is a separate case below.
        await web.evaluateJavascript(
            source: 'document.scrollingElement.scrollTop = 40;');
        final measured = Completer<void>();
        transport.gate = Completer<void>();
        transport.measured = measured;
        // Finish guarded pointer dispatch/pumping before inspecting the held
        // native ACK. Measurement can complete before wheel's pump returns.
        final reverseDelta = await wheel(-40, wait: false);
        await measured.future.timeout(const Duration(seconds: 5));
        expect(page.outerController.offset, 200);
        expect(await top(), 0);
        transport.gate!.complete();
        transport.gate = null;
        await idle();
        expect(
            page.outerController.offset, closeTo(200 + reverseDelta + 40, 1));
        report['measured_reverse_before_header'] = true;

        // A timeout must NOT declare native work complete or reveal the header.
        page.outerController.jumpTo(200);
        await tester.pump();
        await web.evaluateJavascript(
            source: 'document.scrollingElement.scrollTop = 20;');
        transport.gate = Completer<void>();
        transport.measured = Completer<void>();
        await wheel(-40, wait: false);
        await transport.measured!.future.timeout(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 300));
        expect(transport.active, 1);
        expect(page.outerController.offset, 200);
        transport.gate!.complete();
        transport.gate = null;
        await idle();
        expect(page.outerController.offset, 200);
        expect(transport.maximumActive, 1);
        report['late_ack_discarded'] = true;

        // Same-view navigation invalidates the document token, not the renderer.
        final oldDocument = await web.evaluateJavascript(
            source:
                'globalThis.${NativeFilePageScrollBridge.runtime}.snapshot().documentId');
        if (format == 'email') {
          await web.loadData(data: prepareHtmlPreviewDocument(_html));
        } else {
          await web.reload();
        }
        await _until(
            tester,
            () async =>
                await web.evaluateJavascript(
                        source:
                            'globalThis.${NativeFilePageScrollBridge.runtime}?.snapshot().documentId') !=
                    oldDocument &&
                await web.evaluateJavascript(
                        source:
                            'typeof globalThis.${NativeFilePageScrollBridge.runtime} === "object"') ==
                    true);
        expect(created, 1);
        expect(tester.element(find.byType(InAppWebView)), same(bodyElement));

        // Real native precision-pan path (not direct calls to a Dart delegate).
        page.outerController.jumpTo(0);
        await tester.pump();
        await web.evaluateJavascript(source: '''
      window.__fixturePan = {starts:0, moves:0, cancels:0, ends:0};
      for (const [event, key] of [['touchstart','starts'], ['touchmove','moves'],
          ['touchcancel','cancels'], ['touchend','ends']]) {
        document.addEventListener(event, () => window.__fixturePan[key]++,
          {capture:true, passive:true});
      }
      ''');
        final panSamples = <Object?>[];
        report['pan_samples'] = panSamples;
        final clock = Stopwatch()..start();
        final pan = await tester.createGesture(
            kind: PointerDeviceKind.trackpad, pointer: 71);
        await pan.panZoomStart(point, timeStamp: clock.elapsed);
        await _until(
            tester,
            () async =>
                (await channel.invokeMapMethod('_getSiteGestureDiagnostics',
                    'offline-fixture-v1'))?['idle'] ==
                true);
        for (var i = 1; i <= 12; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await pan.panZoomUpdate(point,
              pan: Offset(0, -i * 24.0), timeStamp: clock.elapsed);
          await idle();
          panSamples.add({
            'sample': i,
            'header': page.outerController.offset,
            'dom': await web.evaluateJavascript(
                source:
                    '({...window.__fixturePan, ...globalThis.${NativeFilePageScrollBridge.runtime}.snapshot(), top:document.scrollingElement.scrollTop})'),
          });
          if (page.outerController.offset < 200) expect(await top(), 0);
        }
        await pan.panZoomEnd(timeStamp: clock.elapsed);
        await idle();
        expect(page.outerController.offset, greaterThan(0));
        expect(created, 1);
        expect(tester.getSize(find.byType(InAppWebView)), initialSize);

        // Explicit physical keys are mandatory in native Release fixtures.
        final beforeModified = page.outerController.offset;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(PointerScrollEvent(
            position: point, scrollDelta: const Offset(0, 5)));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(page.outerController.offset, beforeModified);
        expect(tester.takeException(), isNull);
        report['renderer_instances'] = created;
        report['maximum_native_consumptions'] = transport.maximumActive;
        report['measurement_complete'] = true;
      } catch (error, stack) {
        // Preserve the first failure even if a later cleanup assertion fails.
        // This fixture contains only local synthetic content, not user data.
        report['body_error_type'] = error.runtimeType.toString();
        debugPrint('Native file page-flow $format failed: $error\n$stack');
        rethrow;
      } finally {
        try {
          report['cleanup_stage'] = 'held_ack';
          if (creatingEnvironment)
            throw StateError(
                'No environment creation ACK; disposal cannot be proven.');
          final pending = heldTransport?.gate;
          if (pending != null && !pending.isCompleted) pending.complete();
          await heldTransport?.drained;
          report['remaining_held_ack_calls'] = heldTransport?.active ?? 0;
          expect(heldTransport?.active ?? 0, 0);
          report['cleanup_stage'] = 'native_view';
          if (native == null &&
              find
                  .byType(CustomPlatformView, skipOffstage: false)
                  .evaluate()
                  .isNotEmpty) {
            native = tester
                .state<CustomPlatformViewState>(
                    find.byType(CustomPlatformView, skipOffstage: false))
                .controller;
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          if (mountingView && native == null)
            throw StateError('Missing native disposal owner.');
          await native?.dispose();
          report['texture_lifecycle'] = native?.disposalDiagnostics;
          report['native_dispose_ack'] = native != null;
          report['cleanup_stage'] = 'environment';
          final ownedEnvironment = environment;
          if (ownedEnvironment != null) {
            await MethodChannel(
                    'com.pichillilorenzo/flutter_webview_environment_${ownedEnvironment.id}')
                .invokeMethod<void>('dispose');
            report['environment_dispose_ack'] = true;
          }
          if (native != null) {
            expect(native.disposalDiagnostics?['schema'], 1);
            expect(native.disposalDiagnostics?['stages'], [0, 1, 2, 3, 4, 5]);
          }
          report['quiescent'] = native != null && ownedEnvironment != null;
        } finally {
          chrome.dispose();
          GoogleFonts.config.allowRuntimeFetching = oldFetching;
          semantics.dispose();
          report['semantics_handles_after_body'] =
              binding.debugOutstandingSemanticsHandles;
          expect(binding.debugOutstandingSemanticsHandles, baselineHandles);
        }
        report['remaining_transient_callbacks'] =
            binding.transientCallbackCount;
        expect(binding.transientCallbackCount, 0);
        report['cleanup_stage'] = 'complete';
        report['cleanup_complete'] = report['quiescent'] == true;
        // Leave only the isolated temp profile to OS cleanup, never live data.
      }
    }, timeout: Timeout.none);
  }
}

Future<void> _until(WidgetTester tester, Future<bool> Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline))
      throw StateError('Native fixture readiness deadline');
    await tester.pump(const Duration(milliseconds: 10));
  }
}

class _HeldAckController extends Fake implements InAppWebViewController {
  _HeldAckController(this.native);
  final InAppWebViewController native;
  Completer<void>? gate;
  Completer<void>? measured;
  int active = 0;
  int maximumActive = 0;
  Completer<void>? _drained;
  Future<void> get drained => active == 0 ? Future.value() : _drained!.future;
  @override
  void addJavaScriptHandler(
          {required String handlerName,
          required JavaScriptHandlerCallback callback}) =>
      native.addJavaScriptHandler(handlerName: handlerName, callback: callback);
  @override
  JavaScriptHandlerCallback? removeJavaScriptHandler(
          {required String handlerName}) =>
      native.removeJavaScriptHandler(handlerName: handlerName);
  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    if (!source.contains('?.consumeVertical(')) {
      return native.evaluateJavascript(
          source: source, contentWorld: contentWorld);
    }
    if (active++ == 0) _drained = Completer<void>();
    if (active > maximumActive) maximumActive = active;
    final pending = gate;
    try {
      final result = await native.evaluateJavascript(
          source: source, contentWorld: contentWorld);
      if (measured?.isCompleted == false) measured!.complete();
      await pending?.future;
      return result;
    } finally {
      active--;
      if (active == 0) _drained!.complete();
    }
  }
}

const _html = '''<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0}body{height:9000px;font:16px sans-serif}
#selection{margin:0;padding:20px}article{height:8800px}</style></head><body>
<p id="selection">Selection survives page flow</p><article>Offline rendered file body</article>
</body></html>''';

final _markdown = '<p id="selection">Selection survives page flow</p>\n\n'
    '# Offline rendered Markdown\n\n${List.generate(500, (i) => 'Paragraph $i. Local reading content.\n\n').join()}';
