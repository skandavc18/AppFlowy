import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy/shared/find_replace/webview_find.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

String _installation() => buildWebViewFindInstallScript(
      matchColor: '#ffe599',
      currentColor: '#e0ad42',
      currentTextColor: '#221c14',
    );

void main() {
  group('native result decoding', () {
    test('accepts maps and repeated JSON encodings without losing zeroes', () {
      for (final result in [
        {'count': 12, 'index': 3, 'invalid': false},
        {'count': 0, 'index': 0, 'invalid': false},
        {'count': 0, 'index': 0, 'invalid': true},
      ]) {
        Object value = result;
        for (var depth = 0; depth < 4; depth++) {
          final parsed = WebViewFindResult.fromJavaScript(value);
          expect(parsed.count, result['count']);
          expect(parsed.index, result['index']);
          expect(parsed.invalid, result['invalid']);
          value = jsonEncode(value);
        }
      }
      // Preserve the original parser's nullable/invalid-only public contract.
      expect(WebViewFindResult.fromJavaScript(null).count, 0);
      expect(
        WebViewFindResult.fromJavaScript({'invalid': true}).invalid,
        isTrue,
      );
    });

    test('malformed payloads and exception envelopes are not false zeroes', () {
      for (final value in <Object>[
        '{not json',
        jsonEncode('{not json'),
        {'error': 'ReferenceError: document is not defined'},
        {'count': -1, 'index': 0},
        {'count': 1, 'index': 2},
        {'count': 1.5, 'index': 1},
        {'count': double.nan, 'index': 0},
        {'count': 1, 'index': 1, 'invalid': 'false'},
        [1, 2],
        true,
      ]) {
        expect(
          () => WebViewFindResult.fromJavaScript(value),
          throwsFormatException,
          reason: '$value',
        );
      }
    });
  });

  test('typed-before-ready query retries using the latest options', () async {
    final bridge = _Bridge();
    final session = WebViewFindSession()
      ..attach(bridge.evaluate)
      ..open()
      ..setQuery('old', const FindOptions());
    addTearDown(session.dispose);
    expect(await session.find(), isNull);
    expect(bridge.calls, isEmpty);
    expect(session.pending, isTrue);

    final pending = session.install(_installation());
    session.setQuery('a.b', const FindOptions(wholeWord: true));
    bridge.calls.single.complete(jsonEncode(jsonEncode(true)));
    await Future<void>.value();
    expect(bridge.calls, hasLength(2));
    expect(
      bridge.calls.last.source,
      buildWebViewFindCommand('a.b', const FindOptions(wholeWord: true)),
    );
    bridge.calls.last
        .complete(jsonEncode(jsonEncode({'count': 2, 'index': 1})));
    final result = await pending;
    expect(result?.count, 2);
    expect(result?.index, 1);
    expect(session.ready, isTrue);
    expect(session.pending, isFalse);
  });

  test('query change invalidates old counts BEFORE the next debounce fires',
      () async {
    final (session, bridge) = await _ready();
    addTearDown(session.dispose);
    session
      ..open()
      ..setQuery('alpha', const FindOptions());
    final old = session.find();
    final oldCall = bridge.calls.last;
    session.setQuery('beta', const FindOptions(caseSensitive: true));
    oldCall.complete({'count': 99, 'index': 1});
    expect(await old, isNull);
    expect(session.pending, isTrue);
    final current = session.find();
    expect(
      bridge.calls.last.source,
      buildWebViewFindCommand(
        'beta',
        const FindOptions(caseSensitive: true),
      ),
    );
    bridge.calls.last.complete({'count': 1, 'index': 1});
    expect((await current)?.count, 1);
  });

  test('late navigation cannot overwrite a newer move or query', () async {
    final (session, bridge) = await _ready();
    addTearDown(session.dispose);
    session
      ..open()
      ..setQuery('alpha', const FindOptions());
    final first = session.find();
    bridge.calls.last.complete({'count': 3, 'index': 1});
    await first;
    final earlier = session.move(forward: true);
    final earlierCall = bridge.calls.last;
    final later = session.move(forward: true);
    bridge.calls.last.complete({'count': 3, 'index': 3});
    expect((await later)?.index, 3);
    earlierCall.complete({'count': 3, 'index': 2});
    expect(await earlier, isNull);

    final obsolete = session.move(forward: false);
    final obsoleteCall = bridge.calls.last;
    session.setQuery('beta', const FindOptions());
    final current = session.move(forward: true);
    // Do not move through alpha's marks while beta is still pending.
    expect(
      bridge.calls.last.source,
      buildWebViewFindCommand('beta', const FindOptions()),
    );
    bridge.calls.last.complete({'count': 0, 'index': 0});
    expect((await current)?.count, 0);
    obsoleteCall.complete({'count': 3, 'index': 2});
    expect(await obsolete, isNull);
  });

  test('a new document rejects the old response even on the same controller',
      () async {
    final (session, bridge) = await _ready();
    addTearDown(session.dispose);
    session
      ..open()
      ..setQuery('same query', const FindOptions());
    final old = session.find();
    final oldCall = bridge.calls.last;
    session.attach(bridge.evaluate);
    final install = session.install(_installation());
    bridge.calls.last.complete(true);
    await Future<void>.value();
    bridge.calls.last.complete({'count': 4, 'index': 1});
    expect((await install)?.count, 4);
    oldCall.complete({'count': 400, 'index': 1});
    expect(await old, isNull);
  });

  test('obsolete installation cannot declare a new document ready', () async {
    final bridge = _Bridge();
    final session = WebViewFindSession()..attach(bridge.evaluate);
    addTearDown(session.dispose);
    final old = session.install(_installation());
    final oldCall = bridge.calls.last;
    session.attach(bridge.evaluate);
    final current = session.install(_installation());
    bridge.calls.last.complete(null);
    await current;
    oldCall.complete(true);
    expect(await old, isNull);
    expect(session.ready, isFalse);

    final first = session.install(_installation());
    final firstCall = bridge.calls.last;
    final last = session.install(_installation());
    bridge.calls.last.complete(true);
    await last;
    firstCall.complete(false);
    await first;
    expect(session.ready, isTrue);
  });

  test('null is pending, but a successful zero or invalid regex is a result',
      () async {
    final (session, bridge) = await _ready();
    addTearDown(session.dispose);
    session
      ..open()
      ..setQuery('missing', const FindOptions());
    final missingEngine = session.find();
    bridge.calls.last.complete('null');
    expect(await missingEngine, isNull);
    expect(session.ready, isFalse);
    expect(session.pending, isTrue);
    final retry = session.install(_installation());
    bridge.calls.last.complete(true);
    await Future<void>.value();
    bridge.calls.last.complete({'count': 0, 'index': 0});
    final zero = await retry;
    expect(zero, isNotNull);
    expect(zero?.count, 0);
    expect(session.pending, isFalse);

    session.setQuery('[', const FindOptions(useRegex: true));
    final invalid = session.find();
    bridge.calls.last.complete({'count': 0, 'index': 0, 'invalid': true});
    expect((await invalid)?.invalid, isTrue);
    expect(session.pending, isFalse);
  });

  test('close, deactivation invalidation and disposal reject in-flight work',
      () async {
    final (session, bridge) = await _ready();
    session
      ..open()
      ..setQuery('alpha', const FindOptions());
    final pending = session.find();
    final call = bridge.calls.last;
    final close = session.close();
    expect(bridge.calls.last.source, buildWebViewFindClearCommand());
    bridge.calls.last.complete(true);
    await close;
    call.complete({'count': 3, 'index': 1});
    expect(await pending, isNull);
    expect(session.pending, isFalse);
    session.open();
    final inactive = session.find();
    session.invalidatePending();
    bridge.calls.last.complete({'count': 3, 'index': 1});
    expect(await inactive, isNull);
    final disposed = session.find();
    session.dispose();
    bridge.calls.last.complete({'count': 3, 'index': 1});
    expect(await disposed, isNull);
    expect(session.ready, isFalse);
  });

  test('evaluation and decoding errors reach the caller unchanged', () async {
    final (session, bridge) = await _ready();
    addTearDown(session.dispose);
    session
      ..open()
      ..setQuery('alpha', const FindOptions());
    final pending = session.find();
    final error = PlatformException(code: 'javascript_exception');
    final checked = expectLater(pending, throwsA(same(error)));
    bridge.calls.last.response.completeError(error);
    await checked;
    expect(session.pending, isTrue);
    final malformed = session.find();
    final checkedMalformed = expectLater(malformed, throwsFormatException);
    bridge.calls.last.complete({'exceptionDetails': 'bad script'});
    await checkedMalformed;
    expect(session.pending, isTrue);
  });

  test('commands quote queries/options and retain case-insensitive defaults',
      () {
    const query = 'a.b "quoted" \\ path\nline\u2028 </script>';
    final literal = buildWebViewFindCommand(query, const FindOptions());
    expect(literal, contains(jsonEncode(RegExp.escape(query))));
    expect(literal, contains('"gmi"'));
    expect(
      buildWebViewFindCommand(query, const FindOptions(useRegex: true)),
      contains(jsonEncode(query)),
    );
    expect(
      buildWebViewFindCommand(
        'Alpha',
        const FindOptions(caseSensitive: true),
      ),
      contains('"gm"'),
    );
    expect(
      buildWebViewFindMoveCommand(forward: false),
      contains('.move(false)'),
    );
  });

  test(
    'Windows binding and ordinary channel only open the current owner',
    () async {
      final controller = _NativeBridge();
      final world = ContentWorld.world(name: 'find-test-isolated');
      var current = true;
      var opened = 0;
      await installWebViewFindOpenBridge(
        controller,
        contentWorld: world,
        onFind: () => opened++,
        isCurrent: () => current,
      );
      expect(
        controller.methods,
        ['Runtime.bindingCalled', 'Runtime.addBinding'],
      );
      expect(controller.parameters, {
        'name': webViewFindBindingName,
        'executionContextName': world.name,
      });
      controller.nativeEvent!(
        {'name': 'other', 'payload': webViewFindOpenHandlerName},
      );
      expect(opened, 0);
      controller.nativeEvent!({
        'name': webViewFindBindingName,
        'payload': webViewFindOpenHandlerName,
      });
      controller.handler!([]);
      expect(opened, 2);
      current = false;
      controller.handler!([]);
      controller.nativeEvent!({
        'name': webViewFindBindingName,
        'payload': webViewFindOpenHandlerName,
      });
      expect(opened, 2);
    },
    skip: !Platform.isWindows,
  );
}

Future<(WebViewFindSession, _Bridge)> _ready() async {
  final bridge = _Bridge();
  final session = WebViewFindSession()..attach(bridge.evaluate);
  final ready = session.install(_installation());
  bridge.calls.single.complete(true);
  await ready;
  return (session, bridge);
}

// Only the asynchronous platform boundary is simulated. Every source string
// and the request/query/document sequencing above are production code.
class _Bridge {
  final calls = <_Call>[];
  Future<Object?> evaluate(String source) {
    final call = _Call(source);
    calls.add(call);
    return call.response.future;
  }
}

class _Call {
  _Call(this.source);
  final String source;
  final response = Completer<Object?>();
  void complete(Object? value) => response.complete(value);
}

class _NativeBridge extends Fake implements InAppWebViewController {
  JavaScriptHandlerCallback? handler;
  Function(dynamic)? nativeEvent;
  final methods = <String>[];
  Map<String, dynamic>? parameters;

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    expect(handlerName, webViewFindOpenHandlerName);
    handler = callback;
  }

  @override
  Future<void> addDevToolsProtocolEventListener({
    required String eventName,
    required Function(dynamic data) callback,
  }) async {
    methods.add(eventName);
    nativeEvent = callback;
  }

  @override
  Future<dynamic> callDevToolsProtocolMethod({
    required String methodName,
    Map<String, dynamic>? parameters,
  }) async {
    methods.add(methodName);
    this.parameters = parameters;
    return <String, Object?>{};
  }
}
