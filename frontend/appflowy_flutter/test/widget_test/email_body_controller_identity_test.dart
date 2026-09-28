import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/collection/views/email/email_body_view.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/shared/document_viewer/native_file_page_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'email accepts distinct wrappers sharing a platform on load stop and start',
    (tester) async {
      final fixture = _Fixture(tester);
      try {
        await fixture.mount();
        final otherWrapper = fixture.wrap(fixture.controller);
        expect(otherWrapper, isNot(same(fixture.created)));
        expect(otherWrapper == fixture.created, isFalse);
        expect(otherWrapper.platform, same(fixture.created.platform));

        fixture.callbacks.onLoadStop!(otherWrapper, WebUri('about:blank'));
        await tester.pump();
        final document = fixture.installedDocument();
        await fixture.expectActiveDocument(document);

        fixture.controller.sources.clear();
        fixture.callbacks.onLoadStart!(otherWrapper, WebUri('about:blank'));
        fixture.bridge.cancel();
        await tester.pump();
        expect(
          fixture.controller.sources,
          isEmpty,
          reason: 'An accepted load start must retire the old document token.',
        );

        fixture.callbacks.onLoadStop!(otherWrapper, WebUri('about:blank'));
        await tester.pump();
        final nextDocument = fixture.installedDocument();
        expect(nextDocument, isNot(document));
        await fixture.expectActiveDocument(nextDocument);
      } finally {
        await fixture.dispose();
      }
    },
    // EmailBodyView uses dart:io Platform.isWindows, not a target override.
    skip: !Platform.isWindows,
  );

  for (final event in ['start', 'stop']) {
    testWidgets(
      'email ignores stale load $event from a different platform with the same ID',
      (tester) async {
        final fixture = _Fixture(tester);
        try {
          await fixture.mount();
          // Seed using the ORIGINAL wrapper so each stale-callback regression
          // is independent of the shared-wrapper load-stop failure above.
          fixture.callbacks.onLoadStop!(
            fixture.created,
            WebUri('about:blank'),
          );
          await tester.pump();
          final document = fixture.installedDocument();
          await fixture.expectActiveDocument(document);

          final stalePlatform = _Controller();
          final stale = fixture.wrap(stalePlatform);
          expect(stale.platform, isNot(same(fixture.created.platform)));
          expect(stale.getViewId(), fixture.created.getViewId());
          fixture.controller.sources.clear();
          final callback = event == 'start'
              ? fixture.callbacks.onLoadStart!
              : fixture.callbacks.onLoadStop!;
          callback(stale, WebUri('about:blank'));
          await tester.pump();
          expect(fixture.controller.sources, isEmpty);
          expect(stalePlatform.sources, isEmpty);
          await fixture.expectActiveDocument(document);
        } finally {
          await fixture.dispose();
        }
      },
      skip: !Platform.isWindows,
    );
  }
}

// Only the plugin surface/controller are fake. EmailBodyView supplies the real
// lifecycle callbacks, and its real NativeFilePageScrollBridge emits the JS.
class _Fixture {
  _Fixture(this.tester) {
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = _WebViewPlatform();
    addTearDown(() {
      // The plugin setter cannot restore null in an unregistered test isolate.
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
  }

  final WidgetTester tester;
  final controller = _Controller();
  late PlatformInAppWebViewWidgetCreationParams callbacks;
  late InAppWebViewController created;
  late NativeFilePageScrollBridge bridge;

  InAppWebViewController wrap(_Controller platform) =>
      callbacks.controllerFromPlatform!(platform) as InAppWebViewController;

  Future<void> mount() async {
    await tester.pumpWidget(
      MaterialApp(
        // No route transition/backstop timer is needed for this identity test.
        builder: (context, _) => EmailBodyView(
          html: '<html><body>Controller identity regression</body></html>',
          theme: emailThemeOf(context),
        ),
      ),
    );
    expect(find.byType(EmailBodyView), findsOneWidget);
    callbacks =
        tester.widget<InAppWebView>(find.byType(InAppWebView)).platform.params;
    bridge = tester
        .widget<NativeFilePageScroll>(
          find.byType(NativeFilePageScroll),
        )
        .bridge;
    created = wrap(controller);
    callbacks.onWebViewCreated!(created);
    expect(controller.handlers, contains(NativeFilePageScrollBridge.handler));
    expect(controller.sources, isEmpty);
  }

  String installedDocument() {
    expect(controller.sources, hasLength(1));
    final source = controller.sources.single;
    expect(source,
        contains("const key = '${NativeFilePageScrollBridge.runtime}';"));
    expect(source, contains('globalThis[key] = {'));
    expect(controller.worlds.last, ContentWorld.PAGE);
    // Inspect the actual evaluateJavascript payload, never production source.
    final token = RegExp(r'const documentId = ("[^"]+");').firstMatch(source);
    expect(token, isNotNull);
    return jsonDecode(token!.group(1)!) as String;
  }

  Future<void> expectActiveDocument(String document) async {
    controller.sources.clear();
    // cancel() emits JS only while the real bridge retains a document token.
    // Thus a stale load-start that silently invalidates is observable here.
    bridge.cancel();
    await tester.pump();
    expect(controller.sources, [
      'globalThis.${NativeFilePageScrollBridge.runtime}?.cancel('
          '${jsonEncode(document)},-1);',
    ]);
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.handlers, isEmpty);
    expect(tester.takeException(), isNull);
  }
}

class _WebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) =>
      _WebViewSurface(params);
}

class _WebViewSurface extends PlatformInAppWebViewWidget {
  _WebViewSurface(PlatformInAppWebViewWidgetCreationParams params)
      : super.implementation(params);

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _Controller extends Fake implements PlatformInAppWebViewController {
  final sources = <String>[];
  final worlds = <ContentWorld?>[];
  final handlers = <String, JavaScriptHandlerCallback>{};

  @override
  int get id => 7;

  @override
  int getViewId() => id;

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) =>
      handlers[handlerName] = callback;

  @override
  JavaScriptHandlerCallback? removeJavaScriptHandler({
    required String handlerName,
  }) =>
      handlers.remove(handlerName);

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    sources.add(source);
    worlds.add(contentWorld);
    return true;
  }
}
