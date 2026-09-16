import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:ffi/ffi.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

// Offline native regression: no AppFlowy startup, backend, preferences or
// live bookmark cookies. Exercise the same Windows texture/input bridge.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'webview trackpad scrolling leaves the physical cursor in place',
    (tester) async {
      expect(Platform.isWindows && !kIsWeb, isTrue);
      final native = _NativeCursor();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_fixturePage);
        unawaited(request.response.close());
      });
      final baseUrl = 'http://127.0.0.1:${server.port}';
      final root = await Directory.systemTemp.createTemp('appflowy_pointer_');
      final environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: root.path),
      );
      InAppWebViewController? controller;
      var workspaceNavigation = 0;
      final loaded = Completer<void>();
      Completer<void>? navigationLoaded;
      final samples = <Map<String, Object>>[];
      binding.reportData = {
        'run': const String.fromEnvironment(
          'PERF_RUN',
          defaultValue: 'webview_pointer',
        ),
        'samples': samples,
      };
      final originalCursor = native.position;
      try {
        await windowManager.ensureInitialized();
        await windowManager.setSize(const Size(1100, 800));
        await windowManager.setPosition(const Offset(40, 40));
        await windowManager.show();
        await windowManager.focus();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrackpadHistoryNavigation(
                canGoBack: () => true,
                canGoForward: () => true,
                onBack: () => workspaceNavigation++,
                onForward: () => workspaceNavigation++,
                navigationToken: () => 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(160, 80, 40, 40),
                  child: PremiumScrollExclusion(
                    child: InAppWebView(
                      webViewEnvironment: environment,
                      initialSettings: InAppWebViewSettings(
                        disableHorizontalScroll: true,
                        // Match the bookmark's explicit navigation capability.
                        // ignore: avoid_redundant_argument_values
                        allowsBackForwardNavigationGestures: true,
                      ),
                      initialUrlRequest: URLRequest(url: WebUri('$baseUrl/')),
                      onWebViewCreated: (value) => controller = value,
                      onLoadStop: (_, __) {
                        if (!loaded.isCompleted) loaded.complete();
                        final pending = navigationLoaded;
                        if (pending != null && !pending.isCompleted) {
                          pending.complete();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!loaded.isCompleted && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(loaded.isCompleted, isTrue);
        await tester.pumpAndSettle();
        final point = tester.getCenter(find.byType(InAppWebView));
        native.moveToClientPoint(point, tester.view.devicePixelRatio);
        await tester.pump(const Duration(milliseconds: 100));
        final anchor = native.position;
        // ignore: avoid_print
        print(
          'Physical anchor after native hover: $anchor; Flutter point $point',
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: point);
        await mouse.moveTo(point);
        await tester.pump();
        // ignore: avoid_print
        print('After Flutter hover: ${native.position}');
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await pan.panZoomStart(point);
        await tester.pump();
        // ignore: avoid_print
        print('After pan start: ${native.position}');
        expect(native.position, anchor);
        for (var step = 1; step <= 20; step++) {
          await pan.panZoomUpdate(
            point,
            pan: Offset(0, -8.0 * step),
            timeStamp: Duration(milliseconds: step * 16),
          );
          await tester.pump(const Duration(milliseconds: 16));
          final cursor = native.position;
          samples.add({'step': step, 'x': cursor.dx, 'y': cursor.dy});
        }
        await pan.panZoomEnd(
          timeStamp: const Duration(milliseconds: 321),
        );
        await tester.pump(const Duration(milliseconds: 200));
        final scrollY = await controller!.evaluateJavascript(source: 'scrollY');
        binding.reportData!['anchor'] = [anchor.dx, anchor.dy];
        binding.reportData!['after'] = [native.position.dx, native.position.dy];
        binding.reportData!['scroll_y'] = scrollY;
        // ignore: avoid_print
        print('Native cursor: $anchor -> ${native.position}; scrollY=$scrollY; '
            'samples=$samples');
        expect(scrollY, isA<num>());
        expect(scrollY as num, greaterThan(0));
        expect(native.position, anchor);
        for (final sample in samples) {
          expect(Offset(sample['x'] as double, sample['y'] as double), anchor);
        }

        // Real navigations matter: WebView2 does not expose script-created,
        // unactivated pushState entries as navigable Back/Forward entries.
        // The server is loopback-only and never touches real bookmark data.
        for (final path in ['/one', '/two']) {
          navigationLoaded = Completer<void>();
          await controller!
              .loadUrl(urlRequest: URLRequest(url: WebUri('$baseUrl$path')));
          final until = DateTime.now().add(const Duration(seconds: 10));
          while (
              !navigationLoaded.isCompleted && DateTime.now().isBefore(until)) {
            await tester.pump(const Duration(milliseconds: 25));
          }
          expect(navigationLoaded.isCompleted, isTrue);
          await tester.pumpAndSettle();
        }
        final visited = <String>[];
        expect(await controller!.canGoBack(), isTrue);
        for (final navigation in [
          (120.0, '/one'),
          (120.0, '/'),
          (120.0, '/'), // no Back entry: stay inside this bookmark
          (-120.0, '/one'),
          (-120.0, '/two'),
          (-120.0, '/two'), // no Forward entry
        ]) {
          final available = navigation.$1 > 0
              ? await controller!.canGoBack()
              : await controller!.canGoForward();
          final startSurface = tester.widget<HistorySwipeSurface>(
            find.descendant(
              of: find.byType(InAppWebView),
              matching: find.byType(HistorySwipeSurface),
            ),
          );
          final reducedMotion =
              MediaQuery.of(tester.element(find.byType(InAppWebView)))
                  .disableAnimations;
          // ignore: avoid_print
          print(
              'Swipe starting: key=${startSurface.pageKey}, ready=${startSurface.pageReady}, '
              'active=${startSurface.controller.isActive}, reduced=$reducedMotion, available=$available');
          final swipe =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await swipe.panZoomStart(point);
          for (var step = 1; step <= 6; step++) {
            await swipe.panZoomUpdate(
              point,
              pan: Offset(navigation.$1 * step / 6, 0),
              timeStamp: Duration(milliseconds: step * 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
            expect(native.position, anchor);
            final sheet = tester.widget<Transform>(
              find.descendant(
                of: find.byType(InAppWebView),
                matching: find.byKey(const ValueKey('history-swipe-sheet')),
              ),
            );
            final dx = sheet.transform.getTranslation().x;
            final debugSurface = tester.widget<HistorySwipeSurface>(
              find.descendant(
                of: find.byType(InAppWebView),
                matching: find.byType(HistorySwipeSurface),
              ),
            );
            // ignore: avoid_print
            print(
                'Swipe frame $step: dx=$dx key=${debugSurface.pageKey} ready=${debugSurface.pageReady} '
                'active=${debugSurface.controller.isActive}, settling=${debugSurface.controller.isSettling}');
            if (available) {
              expect(dx, closeTo(navigation.$1 * step / 6, .1));
            } else {
              expect(dx.abs(), inExclusiveRange(0, 64));
              expect(
                find.text(
                  navigation.$1 > 0 ? 'No previous page' : 'No next page',
                ),
                findsOneWidget,
              );
            }
          }
          await swipe.panZoomEnd(timeStamp: const Duration(milliseconds: 97));
          final until = DateTime.now().add(const Duration(seconds: 5));
          String? path;
          do {
            await tester.pump(const Duration(milliseconds: 25));
            path = await controller!
                .evaluateJavascript(source: 'location.pathname') as String?;
          } while (path != navigation.$2 && DateTime.now().isBefore(until));
          expect(path, navigation.$2);
          expect(native.position, anchor);
          visited.add(path!);
          // URL changes and release-animation completion are independent.
          // Wait for the actual transition, not an arbitrary delay.
          final surface = tester.widget<HistorySwipeSurface>(
            find.descendant(
              of: find.byType(InAppWebView),
              matching: find.byType(HistorySwipeSurface),
            ),
          );
          final settledBy = DateTime.now().add(const Duration(seconds: 4));
          while (surface.controller.isActive &&
              DateTime.now().isBefore(settledBy)) {
            await tester.pump(const Duration(milliseconds: 25));
          }
          expect(surface.controller.isActive, isFalse);
          // The reset is scheduled after endOfFrame. Paint it before starting
          // another synthetic pointer so it cannot hit last frame's blocker.
          await tester.pump();
          final restingSheet = tester.widget<Transform>(
            find.descendant(
              of: find.byType(InAppWebView),
              matching: find.byKey(const ValueKey('history-swipe-sheet')),
            ),
          );
          expect(restingSheet.transform.getTranslation().x, 0);
        }
        expect(
          await controller!.evaluateJavascript(source: 'window.swipeClicks'),
          0,
        );
        expect(workspaceNavigation, 0);
        binding.reportData!['history_visits'] = visited;
        binding.reportData!['workspace_swipes_from_webview'] =
            workspaceNavigation;
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        try {
          // The current package's environment wrapper binds its static object's
          // channel ID instead of the created environment's ID. Dispose the
          // isolated environment through its actual native channel.
          await MethodChannel(
            'com.pichillilorenzo/flutter_webview_environment_${environment.id}',
          ).invokeMethod<void>('dispose');
        } finally {
          native.moveTo(originalCursor);
          await server.close(force: true);
        }
        // The isolated WebView2 profile can retain a native lock briefly after
        // disposal. Leave it in system temp rather than touch live app storage.
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

const _fixturePage = '<!doctype html><html><head><style>'
    'body{margin:0;height:12000px;background:linear-gradient(#f8f5ef,#8fa3b5)}'
    'a{display:block;margin:80px;width:200px;height:60px}'
    '</style></head><body><a href="#target">Link</a>'
    '<p>Offline cursor and history regression</p><script>'
    'window.swipeClicks=0;document.addEventListener("click",()=>window.swipeClicks++);'
    '</script></body></html>';

final class _Point extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

class _NativeCursor {
  final _user32 = DynamicLibrary.open('user32.dll');

  Offset get position {
    final point = calloc<_Point>();
    try {
      final get = _user32.lookupFunction<Int32 Function(Pointer<_Point>),
          int Function(Pointer<_Point>)>('GetPhysicalCursorPos');
      if (get(point) == 0) throw StateError('Cannot read the native cursor');
      return Offset(point.ref.x.toDouble(), point.ref.y.toDouble());
    } finally {
      calloc.free(point);
    }
  }

  void moveTo(Offset point) {
    final set = _user32.lookupFunction<Int32 Function(Int32, Int32),
        int Function(int, int)>('SetPhysicalCursorPos');
    if (set(point.dx.round(), point.dy.round()) == 0) {
      throw StateError('Cannot position the native test cursor');
    }
  }

  void moveToClientPoint(Offset offset, double scale) {
    // Focus can remain on VS Code during automation. Only use this process's
    // Flutter child HWND, never a terminal or whichever window has focus.
    final runnerClass = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final viewClass = 'FLUTTERVIEW'.toNativeUtf16();
    final process = calloc<Uint32>();
    final point = calloc<_Point>();
    try {
      final find = _user32.lookupFunction<
          IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
          int Function(
            int,
            int,
            Pointer<Utf16>,
            Pointer<Utf16>,
          )>(
        'FindWindowExW',
      );
      final owner = _user32.lookupFunction<
          Uint32 Function(IntPtr, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
      var runner = 0;
      var window = 0;
      while ((runner = find(0, runner, runnerClass, nullptr)) != 0) {
        owner(runner, process);
        if (process.value == pid) {
          window = find(runner, 0, viewClass, nullptr);
          break;
        }
      }
      if (window == 0) throw StateError('Cannot locate the test Flutter view');
      point.ref
        ..x = (offset.dx * scale).round()
        ..y = (offset.dy * scale).round();
      final toScreen = _user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<_Point>),
          int Function(int, Pointer<_Point>)>('ClientToScreen');
      if (toScreen(window, point) == 0) throw StateError('No test window');
      final target = Offset(point.ref.x.toDouble(), point.ref.y.toDouble());
      moveTo(target);
      if (position != target) {
        throw StateError('Test cursor was clipped to a screen edge');
      }
    } finally {
      calloc.free(point);
      calloc.free(process);
      calloc.free(viewClass);
      calloc.free(runnerClass);
    }
  }
}
