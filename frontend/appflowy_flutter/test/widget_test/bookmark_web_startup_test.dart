import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_web_view.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Exercise the workspace's vendored adapter without changing app dependencies.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// Real BookmarkWebPage + real Windows Dart adapter; only the native channel is
// faked. No app startup, SharedPreferences, auth, backend, disk or network IO.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fetchFonts = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fetchFonts);

  _test('first create awaits the shared environment and reopen reuses it',
      (tester) async {
    final fixture = _Fixture(tester);
    await fixture.mount();
    fixture.open();
    await fixture.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.environments, hasLength(1));
    expect(fixture.created, isEmpty);
    expect(find.byType(InAppWebView), findsNothing);
    final environmentId = fixture.environments.single['id'];
    fixture.environmentGate.complete();
    await fixture.pump();
    expect(fixture.created, hasLength(1));
    expect(fixture.created.single['webViewEnvironmentId'], environmentId);
    await fixture.close();
    fixture.open();
    await fixture.pump();
    await tester.pump(const Duration(milliseconds: 221));
    await fixture.pump();
    expect(fixture.created, hasLength(2));
    expect(fixture.created.last['webViewEnvironmentId'], environmentId);
    expect(fixture.environments, hasLength(1));
    await fixture.dispose();
    expect(fixture.disposed, hasLength(2));
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    _test(
        '$appearance: resolved fallback mounts once and permits pre-load input',
        (tester) async {
      final ready = Completer<WebViewEnvironment?>();
      var preparations = 0;
      final fixture = _Fixture(
        tester,
        loader: () {
          preparations++;
          return ready.future;
        },
      );
      await fixture.mount(appearance: appearance);
      fixture.open();
      await fixture.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(
        spinner.color,
        tester
            .widget<BookmarkWebPage>(find.byType(BookmarkWebPage))
            .theme
            .accent,
      );
      expect(fixture.created, isEmpty);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(BookmarkWebPage)),
          scrollDelta: const Offset(0, 12),
        ),
      );
      await fixture.pump();
      expect(fixture.input, isEmpty);
      ready.complete(null); // Resolved platform fallback, not "still pending".
      await fixture.pump();
      expect(fixture.created, hasLength(1));
      expect(fixture.created.single['webViewEnvironmentId'], isNull);
      expect(
        (fixture.created.single['initialUrlRequest'] as Map)['url'],
        'about:blank',
      );
      expect(fixture.policyEvents, ['probe', 'install', 'load']);
      expect(fixture.loads, ['https://popup-test.invalid/']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        fixture.input.where((call) => call.method == 'setScrollDelta'),
        isEmpty,
        reason:
            'Input over an absent WebView must not be replayed on readiness.',
      );
      // No onLoadStop/DOMContentLoaded/native readiness event has fired.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(InAppWebView)),
          scrollDelta: const Offset(0, 12),
        ),
      );
      await fixture.pump();
      expect(
        fixture.input.where((call) => call.method == 'setScrollDelta'),
        hasLength(1),
      );
      expect(
        fixture.input
            .singleWhere((call) => call.method == 'setScrollDelta')
            .arguments,
        [0.0, -12.0],
      );
      // Trackpad input waits for native hit-region policy, not onLoadStop.
      // Monotonic samples also retain the adapter's actual 12px intent slop.
      final policy = fixture.gesturePolicyGate = Completer<bool>();
      final point = tester.getCenter(find.byType(InAppWebView));
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pan.panZoomStart(
        point,
        timeStamp: const Duration(microseconds: 100),
      );
      await pan.panZoomUpdate(
        point,
        pan: const Offset(0, -8),
        timeStamp: const Duration(microseconds: 200),
      );
      await fixture.pump();
      expect(
        fixture.input
            .where((call) => call.method == 'querySiteGesturePolicyState'),
        hasLength(1),
      );
      expect(
        fixture.input.where((call) => call.method == 'setPointerUpdate'),
        isEmpty,
        reason: 'Unacknowledged policy must not dispatch the buffered sample.',
      );
      policy.complete(false); // Browser-owned region, not website gestures.
      await tester.pump(const Duration(microseconds: 100));
      await fixture.pump();
      expect(
        fixture.input.where((call) => call.method == 'setPointerUpdate'),
        isEmpty,
        reason: '8px remains below the 12px intent threshold after the ACK.',
      );
      await pan.panZoomUpdate(
        point,
        pan: const Offset(0, -12),
        timeStamp: const Duration(microseconds: 300),
      );
      await fixture.pump();
      expect(
        fixture.input.where((call) => call.method == 'setPointerUpdate'),
        hasLength(2),
      );
      await pan.panZoomEnd(timeStamp: const Duration(microseconds: 400));
      await fixture.pump();
      final packets = fixture.input
          .where((call) => call.method == 'setPointerUpdate')
          .map((call) => call.arguments as List)
          .toList();
      expect(packets, hasLength(3));
      expect(packets.map((packet) => packet.length), [8, 8, 8]);
      expect(packets.map((packet) => packet[1]), [1, 5, 4]); // down/update/up
      expect(packets.map((packet) => packet[6]), [100, 300, 400]);
      expect(packets[1][3], (packets[0][3] as double) - 12);
      expect(packets[2][3], packets[1][3]);
      fixture.pageSize.value = const Size(460, 440);
      await fixture.pump();
      expect(preparations, 1);
      expect(fixture.created, hasLength(1));
      expect(fixture.loads, ['https://popup-test.invalid/']);
      await fixture.dispose();
    });
  }

  _test('timeout shows retry and retry observes the same pending preparation',
      (tester) async {
    final ready = Completer<WebViewEnvironment?>();
    var preparations = 0;
    final fixture = _Fixture(
      tester,
      loader: () {
        preparations++;
        return ready.future;
      },
    );
    await fixture.mount();
    fixture.open();
    await fixture.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(find.byType(BookmarkEmptyState), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(fixture.created, isEmpty);
    await tester.tap(
      find.descendant(
        of: find.byType(BookmarkEmptyState),
        matching: find.byType(TextButton),
      ),
    );
    await fixture.pump();
    expect(preparations, 1);
    expect(fixture.created, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete(null);
    await fixture.pump();
    expect(preparations, 1);
    expect(fixture.created, hasLength(1));
    expect(find.byType(BookmarkEmptyState), findsNothing);
    await fixture.dispose();
  });

  _test('closing before readiness cannot be resurrected at the 320ms backstop',
      (tester) async {
    final ready = Completer<WebViewEnvironment?>();
    final fixture = _Fixture(tester, loader: () => ready.future);
    await fixture.mount();
    fixture.open(slow: true);
    await fixture.pump();
    await tester.pump(const Duration(milliseconds: 250));
    fixture.navigator.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 100));
    // The long reverse is still mounted when the old backstop would fire.
    expect(find.byType(BookmarkWebPage, skipOffstage: false), findsOneWidget);
    ready.complete(null);
    await fixture.pump();
    expect(fixture.created, isEmpty);
    expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.created, isEmpty);
    await fixture.dispose();
  });

  _test(
      'a loaded page retires before reverse and never remounts during closing',
      (tester) async {
    final fixture = _Fixture(tester, loader: () => Future.value());
    await fixture.mount();
    fixture.open(slow: true);
    await fixture.pump();
    await tester.pump(const Duration(milliseconds: 1001));
    await fixture.pump();
    expect(fixture.created, hasLength(1));
    fixture.navigator.currentState!.pop();
    await fixture.pump();
    expect(fixture.disposed, hasLength(1));
    expect(find.byType(BookmarkWebPage, skipOffstage: false), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await fixture.pump();
    expect(fixture.created, hasLength(1));
    expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
    await fixture.dispose();
  });

  _test('a page first mounted after route completion still observes reverse',
      (tester) async {
    final fixture = _Fixture(tester, loader: () => Future.value());
    fixture.visible.value = false;
    await fixture.mount();
    fixture.open();
    await fixture.pump();
    await tester.pump(const Duration(milliseconds: 221));
    fixture.visible.value = true;
    await fixture.pump();
    expect(fixture.created, hasLength(1));
    fixture.navigator.currentState!.pop();
    await fixture.pump();
    // This assertion precedes route disposal. Merely cleaning up on unmount
    // would pass after pumpAndSettle and miss the late-listener bug.
    expect(find.byType(BookmarkWebPage, skipOffstage: false), findsOneWidget);
    expect(fixture.disposed, hasLength(1));
    expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
    await fixture.dispose();
  });

  _test('unmount rejects a late environment result', (tester) async {
    final ready = Completer<WebViewEnvironment?>();
    final fixture = _Fixture(tester, loader: () => ready.future);
    await fixture.mount();
    fixture.open();
    await fixture.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete(null);
    await fixture.pump();
    expect(fixture.created, isEmpty);
    await fixture.dispose();
  });

  _test(
      'a native create finishing after close is disposed without reattachment',
      (tester) async {
    final fixture = _Fixture(tester, loader: () => Future.value());
    fixture.creationGate = Completer<void>();
    await fixture.mount();
    fixture.open();
    await fixture.pump();
    await tester.pump(const Duration(milliseconds: 221));
    await fixture.pump();
    expect(fixture.created, hasLength(1));
    await fixture.close();
    fixture.creationGate!.complete();
    await fixture.pump();
    expect(fixture.disposed, hasLength(1));
    expect(find.byType(InAppWebView, skipOffstage: false), findsNothing);
    expect(fixture.input, isEmpty);
    await fixture.dispose();
  });

  _test('environment readiness does not bypass minimum surface dimensions',
      (tester) async {
    final fixture = _Fixture(tester, loader: () => Future.value());
    fixture.pageSize.value = const Size(32, 32);
    await fixture.mount();
    fixture.open();
    await fixture.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.created, isEmpty);
    fixture.pageSize.value = const Size(500, 480);
    await fixture.pump();
    expect(fixture.created, hasLength(1));
    await fixture.dispose();
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      timeout: const Timeout(Duration(seconds: 30)),
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

class _Fixture {
  _Fixture(this.tester, {this.loader}) {
    final oldPlatform = InAppWebViewPlatform.instance;
    WindowsInAppWebViewPlatform.registerWith();
    final messenger = tester.binding.defaultBinaryMessenger;
    final oldLogging =
        PlatformInAppWebViewController.debugLoggingSettings.enabled;
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    messenger.setMockMethodCallHandler(_environments, (call) async {
      if (call.method == 'create') {
        environments.add(Map<Object?, Object?>.from(call.arguments as Map));
        await environmentGate.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_manager, (call) async {
      if (call.method == 'createInAppWebView') {
        created.add(Map<Object?, Object?>.from(call.arguments as Map));
        final id = created.length + 200;
        final inputChannel =
            MethodChannel('com.pichillilorenzo/custom_platform_view_$id');
        final events = MethodChannel(
          'com.pichillilorenzo/custom_platform_view_${id}_events',
        );
        final web =
            MethodChannel('com.pichillilorenzo/flutter_inappwebview_$id');
        channels.addAll([inputChannel, events, web]);
        messenger.setMockMethodCallHandler(inputChannel, (call) async {
          input.add(call);
          if (call.method == 'querySiteGesturePolicyState') {
            return gesturePolicyGate == null
                ? false
                : await gesturePolicyGate!.future;
          }
          if (call.method == 'getHistoryState') {
            return {'back': false, 'forward': false, 'loading': true};
          }
          return null;
        });
        messenger.setMockMethodCallHandler(events, (_) async => null);
        messenger.setMockMethodCallHandler(web, (call) async {
          if (call.method == 'callDevToolsProtocolMethod') {
            final args = call.arguments as Map;
            if (args['methodName'] != 'Network.setBlockedURLs') return '{}';
            final parameters =
                jsonDecode(args['parametersAsJson'] as String) as Map;
            expectSync(parameters['urls'], isEmpty);
            final patterns = parameters['urlPatterns'] as List;
            if (patterns.length == 1 && (patterns.single as Map).isEmpty) {
              policyEvents.add('probe');
              throw PlatformException(
                code: 'invalid-parameters',
                message:
                    'Invalid parameters: urlPattern and block are required',
              );
            }
            expectSync(patterns, isNotEmpty);
            for (final pattern in patterns.cast<Map>()) {
              expectSync(pattern['urlPattern'], isA<String>());
              expectSync(pattern['block'], isTrue);
            }
            policyEvents.add('install');
            return '{}';
          }
          if (call.method == 'loadUrl') {
            expectSync(policyEvents.last, 'install');
            policyEvents.add('load');
            loads.add(
              ((call.arguments as Map)['urlRequest'] as Map)['url'] as String,
            );
          }
          return null;
        });
        await creationGate?.future;
        return id;
      }
      if (call.method == 'dispose') {
        disposed.add((call.arguments as Map)['id'] as int);
      }
      return null;
    });
    addTearDown(() {
      for (final channel in [_manager, _environments, ...channels]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      PlatformInAppWebViewController.debugLoggingSettings.enabled = oldLogging;
      // The platform-interface setter refuses null even though its getter is
      // nullable before registration. This test isolate has no native plugin.
      if (oldPlatform != null) InAppWebViewPlatform.instance = oldPlatform;
    });
  }

  static const _manager =
      MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
  static const _environments =
      MethodChannel('com.pichillilorenzo/flutter_webview_environment');
  final WidgetTester tester;
  final Future<WebViewEnvironment?> Function()? loader;
  final navigator = GlobalKey<NavigatorState>();
  final visible = ValueNotifier(true);
  final pageSize = ValueNotifier(const Size(500, 480));
  final environmentGate = Completer<void>();
  Completer<void>? creationGate;
  Completer<bool>? gesturePolicyGate;
  final policyEvents = <String>[];
  final loads = <String>[];
  final environments = <Map<Object?, Object?>>[];
  final created = <Map<Object?, Object?>>[];
  final disposed = <int>[];
  final input = <MethodCall>[];
  final channels = <MethodChannel>[];

  Future<void> mount({String appearance = 'light'}) async {
    final theme = DesktopAppearance().getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: theme,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
  }

  void open({bool slow = false}) {
    unawaited(
      navigator.currentState!.push<void>(
        RawDialogRoute<void>(
          transitionDuration: Duration(milliseconds: slow ? 1000 : 220),
          barrierDismissible: false,
          pageBuilder: (context, _, __) => Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, shown, _) => !shown
                  ? const SizedBox.shrink()
                  : ValueListenableBuilder<Size>(
                      valueListenable: pageSize,
                      builder: (context, size, _) => SizedBox.fromSize(
                        size: size,
                        child: BookmarkWebPage(
                          url: 'https://popup-test.invalid/',
                          theme: bookmarkThemeOf(context),
                          environmentLoader: loader,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pump() async {
    await tester.pump();
    // EventChannel stream cancellation may complete in the real event zone.
    // Flush it without advancing the fake route clock or waiting on a timer.
    await tester.runAsync(() async {});
    await tester.pump();
  }

  Future<void> close() async {
    navigator.currentState!.pop();
    await pump();
    await tester.pump(const Duration(milliseconds: 1001));
    await pump();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pump();
    visible.dispose();
    pageSize.dispose();
    expect(tester.takeException(), isNull);
  }
}
