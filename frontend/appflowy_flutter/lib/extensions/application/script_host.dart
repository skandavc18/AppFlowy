import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// What a script produced, or why it did not.
@immutable
class ScriptOutcome {
  const ScriptOutcome.ok(this.value)
      : error = '',
        isError = false;

  const ScriptOutcome.failed(this.error)
      : value = null,
        isError = true;

  final Object? value;
  final String error;
  final bool isError;
}

/// Runs an extension's glue JavaScript.
///
/// ⚠️⚠️ **The sandbox is the CSP, not a policy.** A `Worker` created under
/// `default-src 'none'; connect-src 'none'` has no network, no filesystem and
/// no DOM — it physically cannot reach anything. Every effect an extension has
/// therefore travels back through Dart, where the permission checks live. That
/// is why a script step needs no permission of its own: it is inert.
///
/// One page is kept for the life of the app and a fresh `Worker` is made per
/// call, so no state leaks between two runs and a runaway script is ended by
/// terminating its worker rather than the host.
class ScriptHost {
  ScriptHost();

  static final ScriptHost instance = ScriptHost();

  /// A script gets this long before its worker is ended.
  static const runTimeout = Duration(seconds: 20);

  static const _handlerName = 'afScript';

  /// The page announces itself; a load event can arrive before its script has
  /// run, so readiness is polled rather than assumed.
  static const _readyTimeout = Duration(seconds: 10);
  static const _readyPoll = Duration(milliseconds: 120);

  HeadlessInAppWebView? _headless;
  Future<bool>? _starting;
  var _nextId = 0;
  final Map<String, Completer<ScriptOutcome>> _waiting = {};

  static bool get isSupported =>
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS;

  bool get isReady => _headless != null;

  Future<bool> ensureReady() {
    if (_headless != null) {
      return Future.value(true);
    }
    return _starting ??= _start();
  }

  Future<bool> _start() async {
    if (!isSupported) {
      return false;
    }
    try {
      final loaded = Completer<void>();
      final headless = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(data: _pageHtml),
        initialSettings: InAppWebViewSettings(transparentBackground: true),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: _handlerName,
            callback: _onResult,
          );
        },
        onLoadStop: (_, __) {
          if (!loaded.isCompleted) {
            loaded.complete();
          }
        },
        onReceivedError: (_, __, ___) {
          if (!loaded.isCompleted) {
            loaded.complete();
          }
        },
        // ⚠️ Left unanswered, a permission request dereferences null in the
        // Windows plugin and takes the renderer down. Nothing is granted.
        onPermissionRequest: (_, request) async =>
            PermissionResponse(resources: request.resources),
      );
      await headless.run();
      await loaded.future.timeout(_readyTimeout);

      final controller = headless.webViewController;
      if (controller == null) {
        await headless.dispose();
        return false;
      }
      if (!await _waitForPage(controller)) {
        await headless.dispose();
        return false;
      }
      _headless = headless;
      return true;
    } on Object catch (error) {
      Log.warn('The script host could not be started: $error');
      return false;
    } finally {
      _starting = null;
    }
  }

  /// ⚠️ `onLoadStop` can fire before the page's own script has been installed,
  /// and `evaluateJavascript` answers null for a context that is not there yet
  /// — never an exception. So readiness has to be asked for, repeatedly.
  Future<bool> _waitForPage(InAppWebViewController controller) async {
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final answer = await controller.evaluateJavascript(
        source: 'window.__afScriptReady === true;',
      );
      if (answer == true) {
        return true;
      }
      await Future<void>.delayed(_readyPoll);
    }
    Log.warn('The script host page never became ready.');
    return false;
  }

  void _onResult(List<dynamic> arguments) {
    if (arguments.isEmpty) {
      return;
    }
    final raw = arguments.first;
    Map<String, Object?> payload;
    if (raw is Map) {
      payload = Map<String, Object?>.from(raw);
    } else if (raw is String) {
      final decoded = jsonDecode(raw);
      payload = decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } else {
      return;
    }

    final id = '${payload['id'] ?? ''}';
    final waiting = _waiting.remove(id);
    if (waiting == null || waiting.isCompleted) {
      return;
    }
    if (payload['ok'] == true) {
      waiting.complete(ScriptOutcome.ok(payload['value']));
    } else {
      waiting.complete(
        ScriptOutcome.failed('${payload['error'] ?? 'the script failed'}'),
      );
    }
  }

  /// Runs [source] with [input] in scope. The script returns a value.
  Future<ScriptOutcome> run({
    required String source,
    Object? input,
    List<String> libraries = const [],
    Duration timeout = runTimeout,
  }) async {
    if (!await ensureReady()) {
      return const ScriptOutcome.failed(
        'Scripts cannot be run on this device.',
      );
    }
    final controller = _headless?.webViewController;
    if (controller == null) {
      return const ScriptOutcome.failed('The script host is not running.');
    }

    final id = 's${_nextId++}';
    final completer = Completer<ScriptOutcome>();
    _waiting[id] = completer;

    try {
      final worker = buildWorkerSource(source: source, libraries: libraries);
      await controller.evaluateJavascript(
        source: '__afRun(${jsonEncode(id)}, ${jsonEncode(worker)}, '
            '${jsonEncode(jsonEncode(input))});',
      );
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          unawaited(
            controller
                .evaluateJavascript(source: '__afCancel(${jsonEncode(id)});')
                .catchError((Object _) => null),
          );
          return ScriptOutcome.failed(
            'The script did not finish within ${timeout.inSeconds} seconds.',
          );
        },
      );
    } on Object catch (error) {
      return ScriptOutcome.failed('$error');
    } finally {
      _waiting.remove(id);
    }
  }

  /// The worker's whole program: the libraries, then the script wrapped in a
  /// function that is handed `input`.
  ///
  /// ⚠️ The script is inserted as SOURCE, never through `new Function`. Eval
  /// would need `unsafe-eval` in the page's policy, which is exactly the
  /// loophole the policy exists to close.
  @visibleForTesting
  static String buildWorkerSource({
    required String source,
    List<String> libraries = const [],
  }) {
    final buffer = StringBuffer();
    for (final library in libraries) {
      buffer
        ..writeln(library)
        ..writeln(';');
    }
    buffer
      ..writeln('function __afUser(input) {')
      ..writeln(source)
      ..writeln('}')
      ..writeln('self.onmessage = function (event) {')
      ..writeln('  try {')
      ..writeln('    Promise.resolve(__afUser(event.data)).then(')
      ..writeln('      function (value) {')
      ..writeln('        self.postMessage({ ok: true, value: value });')
      ..writeln('      },')
      ..writeln('      function (error) {')
      ..writeln(
          '        self.postMessage({ ok: false, error: String(error && error.message || error) });')
      ..writeln('      }')
      ..writeln('    );')
      ..writeln('  } catch (error) {')
      ..writeln(
          '    self.postMessage({ ok: false, error: String(error && error.message || error) });')
      ..writeln('  }')
      ..writeln('};');
    return buffer.toString();
  }

  Future<void> dispose() async {
    for (final waiting in _waiting.values) {
      if (!waiting.isCompleted) {
        waiting.complete(const ScriptOutcome.failed('The host was stopped.'));
      }
    }
    _waiting.clear();
    final headless = _headless;
    _headless = null;
    await headless?.dispose();
  }
}

/// ⚠️ `connect-src 'none'` is what makes a script inert. Do not relax it:
/// every capability an extension has is meant to travel back through Dart.
const String _pageHtml = '''
<!doctype html>
<html>
<head>
<meta http-equiv="Content-Security-Policy"
 content="default-src 'none'; script-src 'unsafe-inline' blob:; worker-src blob:; connect-src 'none'">
</head>
<body>
<script>
(function () {
  var live = {};

  function report(id, payload) {
    var worker = live[id];
    if (worker) {
      try { worker.terminate(); } catch (e) {}
      if (worker.__url) { try { URL.revokeObjectURL(worker.__url); } catch (e) {} }
      delete live[id];
    }
    var message = { id: id };
    for (var key in payload) { message[key] = payload[key]; }
    window.flutter_inappwebview.callHandler('afScript', JSON.stringify(message));
  }

  window.__afRun = function (id, workerSource, inputJson) {
    try {
      var url = URL.createObjectURL(
        new Blob([workerSource], { type: 'text/javascript' })
      );
      var worker = new Worker(url);
      worker.__url = url;
      live[id] = worker;
      worker.onmessage = function (event) { report(id, event.data || {}); };
      worker.onerror = function (event) {
        report(id, { ok: false, error: event.message || 'the script failed' });
      };
      worker.postMessage(JSON.parse(inputJson));
    } catch (error) {
      report(id, { ok: false, error: String(error && error.message || error) });
    }
  };

  window.__afCancel = function (id) {
    var worker = live[id];
    if (!worker) { return; }
    try { worker.terminate(); } catch (e) {}
    if (worker.__url) { try { URL.revokeObjectURL(worker.__url); } catch (e) {} }
    delete live[id];
  };

  window.__afScriptReady = true;
})();
</script>
</body>
</html>
''';
