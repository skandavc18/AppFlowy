import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_request_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Standalone WebView2 fixture. Only fixture-owned loopback resources are sent
/// over HTTP. Remote names below are URLPattern inputs, NEVER fetch targets.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUp(() => binding.platformDispatcher.semanticsEnabledTestValue = true);
  tearDown(() => binding.platformDispatcher.clearSemanticsEnabledTestValue());

  testWidgets(
    'native URLPattern boundaries and visible-only Reader capture',
    (tester) async {
      final baselineHandles = binding.debugOutstandingSemanticsHandles;
      final semantics = tester.ensureSemantics();
      WebViewEnvironment? environment;
      CustomPlatformViewController? native;
      HttpServer? server;
      StreamSubscription<HttpRequest>? subscription;
      var creatingEnvironment = false;
      var mountingView = false;
      final requests = <String>[];
      final session = BookmarkReadingSession();
      final blocking = BookmarkBlockingSession();
      final owner = Object();
      final report = <String, dynamic>{
        'case': 'browser_reader_blocking',
        'mode': kReleaseMode ? 'release' : 'debug',
        'measurement_complete': false,
        'cleanup_complete': false,
        'quiescent': false,
        'native_dispose_ack': false,
        'environment_dispose_ack': false,
        'semantics_handles_before_body': baselineHandles,
        'cleanup_stage': 'body',
      };
      binding.reportData = report;
      try {
        expect(Platform.isWindows, isTrue);
        expect(
          const bool.fromEnvironment('BROWSER_READER_BLOCKING_CONSENT'),
          isTrue,
        );
        for (final key in [
          'WEBVIEW2_USER_DATA_FOLDER',
          'WEBVIEW2_BROWSER_EXECUTABLE_FOLDER',
          'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS',
        ]) {
          if ((Platform.environment[key] ?? '').isNotEmpty) {
            throw StateError(
              'External WebView overrides prevent fixture isolation.',
            );
          }
        }
        final localServer =
            await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server = localServer;
        subscription = localServer.listen((request) {
          requests.add(request.uri.path);
          request.response.headers
              .set(HttpHeaders.cacheControlHeader, 'no-store');
          request.response.headers.set(
              'Content-Security-Policy',
              "default-src 'none'; script-src 'self'; "
                  "style-src 'unsafe-inline'; img-src 'self'; connect-src 'self'; "
                  "base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
          if (request.uri.path == '/blocked/ad.js') {
            request.response.headers.contentType =
                ContentType('application', 'javascript');
            request.response.write(
              'window.fixtureScriptLoads=(window.fixtureScriptLoads||0)+1;',
            );
          } else if (request.uri.path == '/image-not-in-reader') {
            request.response.statusCode = HttpStatus.noContent;
          } else {
            request.response.headers.contentType = ContentType.html;
            request.response.write(
                '''<!doctype html><html><head><title>Local fixture</title></head><body>
            ${request.uri.path == '/gated' ? '<div class="paywall">Sign in to continue</div>' : ''}
            <article><h1>Ordinary visible article</h1>
              <p>This is visible article prose with enough detail to select as the reader content.</p>
              <p style="display:none">HIDDEN_PAYLOAD</p>
              <form><input value="FORM_SECRET">FORM_TEXT</form>
              <script type="application/ld+json">{"articleBody":"SCRIPT_PAYLOAD"}</script>
              <img src="/image-not-in-reader" alt="Image">
            </article></body></html>''');
          }
          unawaited(request.response.close());
        });
        final origin = 'http://127.0.0.1:${localServer.port}';
        final root =
            await Directory.systemTemp.createTemp('browser_reader_blocking_');
        creatingEnvironment = true;
        final isolatedEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: '${root.path}/profile',
          ),
        );
        environment = isolatedEnvironment;
        creatingEnvironment = false;
        final created = Completer<InAppWebViewController>();
        final blankLoaded = Completer<void>();
        var captureInvocations = 0;
        String? capturedHtml;
        mountingView = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InAppWebView(
                webViewEnvironment: isolatedEnvironment,
                initialUrlRequest: URLRequest(url: WebUri('about:blank')),
                initialUserScripts: UnmodifiableListView([
                  UserScript(
                    source: bookmarkPopupActivationScript,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                ]),
                onWebViewCreated: (controller) {
                  session.attach(owner, (source) async {
                    final result =
                        await controller.evaluateJavascript(source: source);
                    if (source == bookmarkVisibleArticleScript) {
                      captureInvocations++;
                      capturedHtml = result is String
                          ? (jsonDecode(result) as Map)['html'] as String?
                          : null;
                    }
                    return result;
                  });
                  created.complete(controller);
                },
                onLoadStart: (_, url) =>
                    session.navigationStarted(url?.toString()),
                onLoadStop: (_, url) {
                  if (url?.toString() == 'about:blank' &&
                      !blankLoaded.isCompleted) {
                    blankLoaded.complete();
                  }
                  session.navigationFinished(url?.toString());
                },
                onPermissionRequest: (_, request) async =>
                    PermissionResponse(resources: request.resources),
                onCreateWindow: (_, __) async => false,
              ),
            ),
          ),
        );
        native = tester
            .state<CustomPlatformViewState>(find.byType(CustomPlatformView))
            .controller;
        await _pumpUntil(
          tester,
          () => created.isCompleted && blankLoaded.isCompleted,
        );
        final controller = await created.future;
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
        final patterns = BookmarkRequestPolicy.blockedUrls('$origin/article');
        Future<void> install(List<String> values) =>
            BookmarkRequestPolicy.install(
              values,
              (parameters) => controller.callDevToolsProtocolMethod(
                methodName: 'Network.setBlockedURLs',
                parameters: parameters,
              ),
            );
        await controller.callDevToolsProtocolMethod(
          methodName: 'Network.enable',
        );
        await controller.callDevToolsProtocolMethod(
          methodName: 'Network.setCacheDisabled',
          parameters: {'cacheDisabled': true},
        );
        final requestUrls = <String, String>{};
        final failures = <String, String>{};
        await controller.addDevToolsProtocolEventListener(
          eventName: 'Network.requestWillBeSent',
          callback: (data) {
            if (data is Map &&
                data['requestId'] is String &&
                data['request'] is Map) {
              final url = (data['request'] as Map)['url'];
              if (url is String) requestUrls[data['requestId'] as String] = url;
            }
          },
        );
        await controller.addDevToolsProtocolEventListener(
          eventName: 'Network.loadingFailed',
          callback: (data) {
            if (data is Map &&
                data['requestId'] is String &&
                data['blockedReason'] is String) {
              failures[data['requestId'] as String] =
                  data['blockedReason'] as String;
            }
          },
        );
        // Production startup ordering, including its malformed-BlockPattern
        // capability probe. Unsupported runtimes fail closed before navigation.
        expect(
          await blocking.apply(
            enabled: true,
            firstPartyUrl: '$origin/article',
            install: install,
            isCurrent: () => true,
            navigate: () async {
              expectSync(
                requests,
                isEmpty,
                reason: 'No target request before policy ACK',
              );
              await controller.loadUrl(
                urlRequest: URLRequest(url: WebUri('$origin/article')),
              );
            },
          ),
          isTrue,
        );
        report['capability_probe_and_install'] = true;
        await _pumpUntil(
          tester,
          () => session.ready && session.url == '$origin/article',
        );

        // Every production domain, exact/subdomain/port and strict boundaries.
        // These strings never enter loadUrl, fetch, script.src or DNS.
        final cases = <String, bool>{
          for (final domain in BookmarkRequestPolicy.domains) ...{
            'https://$domain/ad': true,
            'http://a.b.$domain:8443/ad': true,
            'https://${domain.toUpperCase()}/ad': true,
            'https://$domain.evil.invalid/ad': false,
            'https://not$domain/ad': false,
            'https://$domain@safe.invalid/ad': false,
            '$origin/story/foo.$domain/path': false,
            '$origin/?return=https://ads.$domain/path': false,
            'wss://$domain/ad': false,
          },
          'https://maps.googleapis.com/maps/api/js': false,
          'https://accounts.google.com/login': false,
          'https://checkout.stripe.com/pay': false,
        };
        expect(
          await controller.evaluateJavascript(
            source: '''(() => {
        const patterns = ${jsonEncode(patterns)}.map(p => new URLPattern(p));
        return ${jsonEncode(cases.keys.toList())}.map(url => patterns.some(p => p.test(url)));
      })()''',
          ),
          cases.values.toList(),
        );
        for (final domain in BookmarkRequestPolicy.domains) {
          final exempt =
              BookmarkRequestPolicy.blockedUrls('https://news.$domain/story');
          expect(
            await controller.evaluateJavascript(
              source: '''(() => {
          const patterns = ${jsonEncode(exempt)}.map(p => new URLPattern(p));
          return ['https://$domain/ad','http://a.b.$domain:8080/ad']
            .some(url => patterns.some(p => p.test(url)));
        })()''',
            ),
            isFalse,
          );
        }
        report['runtime_boundary_cases'] = cases.length;
        expect(
          await controller.evaluateJavascript(
            source: "window.open('about:blank') === null",
          ),
          isTrue,
        );

        final capture = await session.capture();
        expect(capture, isNotNull);
        final snapshot = capture!;
        expect(
          captureInvocations,
          1,
          reason: 'Real visible-DOM capture script was invoked',
        );
        expect(capturedHtml, contains('visible article prose'));
        for (final excluded in [
          'HIDDEN_PAYLOAD',
          'FORM_SECRET',
          'FORM_TEXT',
          'SCRIPT_PAYLOAD',
          '<form',
          '<script',
        ]) {
          expect(capturedHtml, isNot(contains(excluded)));
        }
        expect(snapshot.article.plainText, contains('visible article prose'));
        for (final secret in [
          'HIDDEN_PAYLOAD',
          'FORM_SECRET',
          'FORM_TEXT',
          'SCRIPT_PAYLOAD',
        ]) {
          expect(snapshot.article.markdown, isNot(contains(secret)));
          expect(snapshot.article.plainText, isNot(contains(secret)));
        }
        expect(
          snapshot.article.markdown,
          isNot(contains('/image-not-in-reader')),
        );
        // Fixture-owned text roundtrip, not a claim about workspace snapshot UI.
        final offline = File('${root.path}/article.md');
        await offline.writeAsString(snapshot.article.markdown, flush: true);
        expect(await offline.readAsString(), snapshot.article.markdown);
        report['visible_reader_and_local_text_roundtrip'] = true;

        // A test-only local URLPattern proves real CDP enforcement, independently
        // of the production domain list. Broken policy can ONLY hit our server.
        var received = 0;
        var blockedCount = 0;
        for (final (index, enabled) in [true, false, true, false].indexed) {
          expect(
            await blocking.apply(
              enabled: enabled,
              firstPartyUrl: '$origin/article',
              install: (values) => install(
                values.isEmpty
                    ? const []
                    : [
                        ...values,
                        '$origin/blocked/*',
                      ],
              ),
              navigate: () async {},
              isCurrent: () => true,
            ),
            isTrue,
          );
          final target = '$origin/blocked/ad.js?attempt=$index';
          final result = await controller.callAsyncJavaScript(
            functionBody: '''
          return await new Promise(resolve => {
            const script=document.createElement('script');
            script.onload=()=>{script.remove();resolve('loaded');};
            script.onerror=()=>{script.remove();resolve('error');};
            script.src=${jsonEncode(target)}; document.head.appendChild(script);
          });
        ''',
          );
          expect(result?.error, isNull);
          expect(result?.value, enabled ? 'error' : 'loaded');
          if (enabled) {
            await _pumpUntil(
              tester,
              () => failures.entries.any(
                (event) =>
                    event.value == 'inspector' &&
                    requestUrls[event.key] == target,
              ),
            );
            blockedCount++;
          } else {
            received++;
            expect(
              await controller.evaluateJavascript(
                source: 'window.fixtureScriptLoads',
              ),
              received,
            );
          }
          expect(
            requests.where((path) => path == '/blocked/ad.js').length,
            received,
            reason:
                'Blocked resources never reach the server; opt-out really clears policy',
          );
        }
        report['inspector_blocked_local_requests'] = blockedCount;
        report['server_received_after_opt_out'] = received;
        await controller.removeDevToolsProtocolEventListener(
          eventName: 'Network.requestWillBeSent',
        );
        await controller.removeDevToolsProtocolEventListener(
          eventName: 'Network.loadingFailed',
        );
        await controller.callDevToolsProtocolMethod(
          methodName: 'Network.disable',
        );

        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri('$origin/gated')),
        );
        await _pumpUntil(
          tester,
          () => session.ready && session.url == '$origin/gated',
        );
        expect(session.isCurrent(snapshot), isFalse);
        expect(
          await session.capture(),
          isNull,
          reason: 'Never remove the access gate',
        );
        expect(captureInvocations, 2);
        expect(capturedHtml, isNull);
        report['paywall_capture_rejected'] = true;
        expect(tester.takeException(), isNull);
        report['measurement_complete'] = true;
      } finally {
        try {
          report['cleanup_stage'] = 'native_view';
          if (creatingEnvironment) {
            throw StateError('No environment creation ACK; cleanup unproven.');
          }
          final views = find.byType(CustomPlatformView, skipOffstage: false);
          if (native == null && views.evaluate().isNotEmpty) {
            native = tester.state<CustomPlatformViewState>(views).controller;
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          if (mountingView && native == null) {
            throw StateError('Missing native disposal owner.');
          }
          // No timeout converts an outstanding native operation into completion.
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
            blocking.close();
            session.dispose();
            await server?.close(force: true);
            await subscription?.cancel();
          } finally {
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
        // Only this fixture's new temp directory remains for OS cleanup.
      }
    },
    timeout: Timeout.none,
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  final clock = Stopwatch()..start();
  while (!done() && clock.elapsed < const Duration(seconds: 12)) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(done(), isTrue, reason: 'Bounded native readiness deadline');
}
