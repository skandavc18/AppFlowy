import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_web_view.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bookmark_reader_test_localizations.dart';

const _url = 'https://news.example/article';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fetchFonts = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await BookmarkReaderTestLocalizations.initialize();
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fetchFonts);

  testWidgets(
    'real WebView widget starts blank; acknowledged policy precedes target load and opt-out reload',
    (tester) async {
      final fixture = _Fixture(tester);
      try {
        await fixture.mount();
        expect(
          (fixture.creations.single['initialUrlRequest'] as Map)['url'],
          'about:blank',
        );
        expect(fixture.events, ['probe', 'install']);
        expect(fixture.shield.onPressed, isNull);
        fixture.gate.complete();
        await fixture.pump();
        expect(fixture.events, ['probe', 'install', 'load']);
        expect(fixture.loads.single, _url);
        fixture.shield.onPressed!();
        await fixture.pump();
        expect(fixture.events, ['probe', 'install', 'load', 'clear', 'reload']);
        expect(fixture.creations, hasLength(1));
        expect(fixture.shield.active, isFalse);
      } finally {
        await fixture.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final change in ['navigation', 'dispose']) {
    testWidgets(
      '$change during installation forbids a late target load',
      (tester) async {
        final fixture = _Fixture(tester);
        try {
          await fixture.mount();
          if (change == 'dispose') {
            await tester.pumpWidget(const SizedBox.shrink());
          } else {
            await fixture
                .event('onLoadStart', {'url': 'https://news.example/other'});
          }
          fixture.gate.complete();
          await fixture.pump();
          expect(fixture.loads, isEmpty);
        } finally {
          await fixture.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'old CDP is unavailable, but explicit off recreates and navigates',
    (tester) async {
      final fixture = _Fixture(tester)..supportsPatterns = false;
      try {
        await fixture.mount();
        expect(fixture.loads, isEmpty);
        expect(fixture.shield.active, isFalse);
        fixture.shield.onPressed!();
        await fixture.pump();
        expect(fixture.loads, [_url]);
        expect(fixture.shield.active, isFalse);
      } finally {
        await fixture.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final kind in [
    'unsolicited',
    'unknown',
    'null',
    'external',
    'unsafe',
    'inactive',
    'covered',
  ]) {
    testWidgets(
      '$kind popup awaits rejectWindow and never loads a second page',
      (tester) async {
        final fixture = _Fixture(tester);
        final ack = fixture.rejectGate = Completer<bool>();
        try {
          await fixture.mount();
          fixture.gate.complete();
          await fixture.pump();
          if (kind == 'inactive') {
            fixture.active.value = false;
            await fixture.pump();
          }
          if (kind == 'covered') {
            unawaited(
              showDialog<void>(
                context: tester.element(find.byType(BookmarkWebPage)),
                builder: (_) => const AlertDialog(content: Text('Newer route')),
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
          }
          final uri = switch (kind) {
            'null' => null,
            'external' => 'mailto:reader@example.com',
            'unsafe' => 'file:///C:/private.txt',
            _ => 'https://news.example/followed',
          };
          var completed = false;
          final reply = fixture
              .send(
            'onCreateWindow',
            CreateWindowAction(
              windowId: 902,
              isForMainFrame: true,
              request: URLRequest(url: uri == null ? null : WebUri(uri)),
              hasGesture: kind == 'unknown' ? null : kind != 'unsolicited',
            ).toMap(),
          )
              .then((value) {
            completed = true;
            return value;
          });
          await fixture.pump();
          expect(fixture.rejected, [902]);
          expect(
            completed,
            isFalse,
            reason: 'Handled reply must wait for rejection ACK.',
          );
          expect(fixture.loads, [_url]);
          ack.complete(true);
          expect(await fixture.waitFor(reply), isTrue);
          expect(
            fixture.external.map((uri) => uri.toString()).toList(),
            kind == 'external' ? ['mailto:reader@example.com'] : isEmpty,
          );
          expect(fixture.creations, hasLength(1));
        } finally {
          await fixture.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'activated HTTP popup delegates once to native same-view fallback',
    (tester) async {
      final fixture = _Fixture(tester);
      try {
        await fixture.mount();
        fixture.gate.complete();
        await fixture.pump();
        final reply = await fixture.event(
          'onCreateWindow',
          CreateWindowAction(
            windowId: 903,
            isForMainFrame: true,
            hasGesture: true,
            request: URLRequest(url: WebUri('https://news.example/followed')),
          ).toMap(),
        );
        expect(
          reply,
          isFalse,
          reason: 'Windows owns the single same-view navigation.',
        );
        expect(fixture.rejected, isEmpty);
        expect(
          fixture.loads,
          [_url],
          reason: 'Dart must not also issue loadUrl.',
        );
        expect(fixture.external, isEmpty);
        expect(fixture.creations, hasLength(1));
      } finally {
        await fixture.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'stalled rejection reaches deadline but never enables fallback',
    (tester) async {
      final fixture = _Fixture(tester)..rejectGate = Completer<bool>();
      try {
        await fixture.mount();
        fixture.gate.complete();
        await fixture.pump();
        var completed = false;
        final reply = fixture
            .send(
          'onCreateWindow',
          CreateWindowAction(
            windowId: 904,
            isForMainFrame: true,
            hasGesture: false,
            request: URLRequest(url: WebUri('https://news.example/popup')),
          ).toMap(),
        )
            .then((value) {
          completed = true;
          return value;
        });
        await fixture.pump();
        await tester
            .pump(bookmarkReaderDeadline - const Duration(milliseconds: 1));
        expect(completed, isFalse);
        await tester.pump(const Duration(milliseconds: 1));
        expect(await fixture.waitFor(reply), isTrue);
        fixture.rejectGate!.complete(true);
        await fixture.pump();
        expect(fixture.rejected, [904]);
        expect(fixture.loads, [_url]);
      } finally {
        await fixture.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'website gestures toggle retains native view, history defaults and clear Find controls',
    (tester) async {
      final fixture = _Fixture(tester);
      final semantics = tester.ensureSemantics();
      try {
        await fixture.mount();
        fixture.gate.complete();
        await fixture.pump();
        final native = tester
            .state<CustomPlatformViewState>(find.byType(CustomPlatformView));
        final scopeElement =
            tester.element(find.byType(WindowsWebViewGestureScope));
        final settings = Map<Object?, Object?>.from(
          fixture.creations.single['initialSettings'] as Map,
        );
        expect(settings['allowsBackForwardNavigationGestures'], isTrue);
        expect(settings['disableHorizontalScroll'], isTrue);
        expect(fixture.gestures.active, isFalse);
        expect(fixture.gestures.tooltip, BookmarkReaderStrings.gesturesAuto);
        expect(
          WindowsWebViewGestureScope.maybeOf(native.context)!
              .preferWebsiteGestures,
          isFalse,
        );
        final toggle = find.byKey(const ValueKey('bookmark-website-gestures'));
        await tester.tap(toggle);
        await fixture.pump();
        expect(fixture.gestures.active, isTrue);
        expect(fixture.gestures.tooltip, BookmarkReaderStrings.gesturesSite);
        expect(
          WindowsWebViewGestureScope.maybeOf(native.context)!
              .preferWebsiteGestures,
          isTrue,
        );
        expect(tester.state(find.byType(CustomPlatformView)), same(native));
        expect(
          tester.element(find.byType(WindowsWebViewGestureScope)),
          same(scopeElement),
        );
        expect(fixture.creations, hasLength(1));
        expect(fixture.creations.single['initialSettings'], settings);
        expect(fixture.settingWrites, isEmpty);
        expect(fixture.loads, [_url]);
        expect(fixture.events.where((event) => event == 'reload'), isEmpty);
        // Exercise the actual button semantics, not just a tooltip widget.
        final button = find.descendant(
          of: toggle,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.button == true,
          ),
        );
        expect(button, findsOneWidget);
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.label, BookmarkReaderStrings.gesturesSite);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(ContextualFindRegion.dispatch(native.context), isTrue);
        await fixture.pump();
        final bar = tester.getRect(find.byType(FindReplaceBar));
        for (final key in [
          'bookmark-website-gestures',
          'bookmark-ad-blocking',
        ]) {
          final control = find.byKey(ValueKey(key));
          expect(bar.overlaps(tester.getRect(control)), isFalse);
          expect(control.hitTestable(), findsOneWidget);
        }
        await tester.tap(toggle);
        await fixture.pump();
        expect(
          WindowsWebViewGestureScope.maybeOf(native.context)!
              .preferWebsiteGestures,
          isFalse,
        );
        expect(fixture.creations, hasLength(1));
      } finally {
        semantics.dispose();
        await fixture.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

// Real vendored Windows Dart adapter, fake native channels only. This fixture
// proves callback ordering, NOT actual network/CDP enforcement or native pixels.
class _Fixture {
  _Fixture(this.tester) {
    final old = InAppWebViewPlatform.instance;
    WindowsInAppWebViewPlatform.registerWith();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (call.method == 'dispose') {
        disposedIds.add((call.arguments as Map)['id'] as int);
        return null;
      }
      if (call.method != 'createInAppWebView') return null;
      creations.add(Map<Object?, Object?>.from(call.arguments as Map));
      id++;
      web = MethodChannel('com.pichillilorenzo/flutter_inappwebview_$id');
      final input =
          MethodChannel('com.pichillilorenzo/custom_platform_view_$id');
      final nativeEvents = MethodChannel(
        'com.pichillilorenzo/custom_platform_view_${id}_events',
      );
      channels.addAll([web, input, nativeEvents]);
      messenger.setMockMethodCallHandler(input, (call) async {
        if (call.method == 'querySiteGesturePolicyState') {
          return {'status': 'browser', 'epoch': 1};
        }
        if (call.method == 'getHistoryState') {
          return {
            'current': _url,
            'back': true,
            'forward': false,
            'loading': false,
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(nativeEvents, (_) async => null);
      messenger.setMockMethodCallHandler(web, (call) async {
        if (call.method == 'rejectWindow') {
          rejected.add((call.arguments as Map)['windowId'] as int);
          return rejectGate == null ? true : await rejectGate!.future;
        }
        if (call.method == 'setSettings') settingWrites.add(call.arguments);
        if (call.method == 'callDevToolsProtocolMethod') {
          final args = call.arguments as Map;
          if (args['methodName'] != 'Network.setBlockedURLs') return '{}';
          final raw = args.values
              .whereType<String>()
              .firstWhere((v) => v.startsWith('{'));
          final parameters = jsonDecode(raw) as Map;
          final patterns = parameters['urlPatterns'] as List;
          if (patterns.isNotEmpty && (patterns.first as Map).isEmpty) {
            events.add('probe');
            if (supportsPatterns) {
              throw PlatformException(code: 'invalid-parameters');
            }
            return '{}';
          }
          if (patterns.isEmpty) {
            events.add('clear');
          } else {
            events.add('install');
            await gate.future;
          }
          return '{}';
        }
        if (call.method == 'loadUrl') {
          events.add('load');
          loads.add(
            ((call.arguments as Map)['urlRequest'] as Map)['url'] as String,
          );
        }
        if (call.method == 'reload') events.add('reload');
        return null;
      });
      return id;
    });
    addTearDown(() {
      for (final channel in [manager, ...channels]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      if (old != null) InAppWebViewPlatform.instance = old;
    });
  }

  static const manager =
      MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
  final WidgetTester tester;
  final gate = Completer<void>();
  Completer<bool>? rejectGate;
  final active = ValueNotifier(true);
  final external = <Uri>[];
  final rejected = <int>[];
  final disposedIds = <int>[];
  final settingWrites = <Object?>[];
  final nativeControllers = <CustomPlatformViewController>{};
  final events = <String>[];
  final loads = <String>[];
  final creations = <Map<Object?, Object?>>[];
  final channels = <MethodChannel>[];
  bool supportsPatterns = true;
  int id = 710;
  late MethodChannel web;
  BookmarkAction get shield => tester.widget<BookmarkAction>(
        find.byKey(const ValueKey('bookmark-ad-blocking')),
      );
  BookmarkAction get gestures => tester.widget<BookmarkAction>(
        find.byKey(const ValueKey('bookmark-website-gestures')),
      );

  Future<void> mount() async {
    await tester.pumpWidget(
      BookmarkReaderTestLocalizations.wrap(
        theme: DesktopAppearance().getThemeData(
          AppTheme.fallback,
          Brightness.light,
          'DM Sans',
          builtInCodeFontFamily,
        ),
        home: Scaffold(
          body: ContextualFindScope(
            child: ValueListenableBuilder<bool>(
              valueListenable: active,
              builder: (context, active, _) => BookmarkWebPage(
                url: _url,
                theme: bookmarkThemeOf(context),
                environmentLoader: () async => null,
                active: active,
                onOpenExternally: external.add,
              ),
            ),
          ),
        ),
      ),
    );
    var ready = false;
    for (var turn = 0; turn < 12 && !ready; turn++) {
      await pump();
      ready = supportsPatterns
          ? events.contains('install')
          : events.contains('probe') &&
              find
                  .byKey(const ValueKey('bookmark-ad-blocking'))
                  .evaluate()
                  .isNotEmpty &&
              shield.onPressed != null;
    }
    expect(
      ready,
      isTrue,
      reason: 'Localized native host must reach its policy gate.',
    );
    expect(creations, hasLength(1));
  }

  Future<dynamic> send(String name, Map<String, dynamic> arguments) {
    final completion = Completer<dynamic>();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        web.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(name, arguments)), (reply) {
      try {
        completion.complete(const StandardMethodCodec().decodeEnvelope(reply!));
      } on Object catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  Future<dynamic> event(String name, Map<String, dynamic> arguments) =>
      waitFor(send(name, arguments));

  Future<dynamic> waitFor(Future<dynamic> future) async {
    var done = false;
    dynamic value;
    Object? error;
    unawaited(
      future.then<void>(
        (result) {
          value = result;
          done = true;
        },
        onError: (Object caught) {
          error = caught;
          done = true;
        },
      ),
    );
    for (var turn = 0; turn < 12 && !done; turn++) {
      await pump();
    }
    expect(
      done,
      isTrue,
      reason: 'Native fixture ACK must complete in bounded turns.',
    );
    if (error != null) throw error!;
    return value;
  }

  Future<void> pump() async {
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump();
    for (final state in tester.stateList<CustomPlatformViewState>(
      find.byType(CustomPlatformView, skipOffstage: false),
    )) {
      nativeControllers.add(state.controller);
    }
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!gate.isCompleted) gate.complete();
    if (rejectGate != null && !rejectGate!.isCompleted) {
      rejectGate!.complete(true);
    }
    await pump();
    for (final controller in nativeControllers) {
      await waitFor(controller.dispose());
    }
    expect(disposedIds, hasLength(creations.length));
    active.dispose();
    expect(tester.takeException(), isNull);
  }
}
