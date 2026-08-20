import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;

/// Serves one extension's island assets from loopback.
///
/// ⚠️⚠️ **One server per extension, so one ORIGIN per extension.** Two islands
/// sharing a port would share `localStorage`, `sessionStorage` and every other
/// same-origin store, which is exactly the leak the folder layout is meant to
/// prevent.
///
/// ⚠️ Assets cannot be loaded from `file://` — modules, workers and fonts are
/// all refused there — which is why this exists at all rather than pointing the
/// view at a path.
class IslandServer {
  IslandServer._(this.extensionId, this.root);

  static final Map<String, IslandServer> _servers = {};

  static const _tokenBytes = 18;

  /// The page can load what shipped with it and nothing else. `connect-src
  /// 'none'` is the whole sandbox: every effect has to travel back through the
  /// bridge, where the permission checks live.
  static const contentSecurityPolicy = "default-src 'none'; "
      "script-src 'self' 'unsafe-inline'; "
      "style-src 'self' 'unsafe-inline'; "
      "img-src 'self' data: blob:; "
      "font-src 'self' data:; "
      "media-src 'self' data: blob:; "
      "connect-src 'none'; "
      "form-action 'none'; "
      "base-uri 'none'";

  final String extensionId;
  final String root;

  final Random _random = Random.secure();
  HttpServer? _server;
  Future<HttpServer>? _starting;
  String? _token;

  /// The server for [extensionId], reading from that extension's folder.
  static IslandServer of(String extensionId, String extensionFolder) {
    final held = _servers[extensionId];
    if (held != null && held.root == extensionFolder) {
      return held;
    }
    held?.dispose();
    return _servers[extensionId] = IslandServer._(extensionId, extensionFolder);
  }

  static Future<void> disposeAll() async {
    final servers = _servers.values.toList();
    _servers.clear();
    for (final server in servers) {
      await server.dispose();
    }
  }

  /// Where [island]'s `index.html` can be reached, starting the server if it
  /// is not up. Null when that island has no page.
  Future<Uri?> urlFor(String island) async {
    final folder = _islandRoot(island);
    if (folder == null || !File(p.join(folder, 'index.html')).existsSync()) {
      return null;
    }
    final server = await _ensureServer();
    final token = _token ??= _newToken();
    return Uri.parse(
      'http://127.0.0.1:${server.port}/$token/$island/index.html',
    );
  }

  String? _islandRoot(String island) {
    final web = p.join(root, 'web');
    return _safeJoin(web, island);
  }

  Future<HttpServer> _ensureServer() {
    final existing = _server;
    if (existing != null) {
      return Future.value(existing);
    }
    return _starting ??= _start();
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(_serve(request)));
    _server = server;
    _starting = null;
    return server;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final token = _token;
      if (token == null ||
          segments.isEmpty ||
          segments.first != token ||
          request.method != 'GET') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final relative = segments.skip(1).join('/');
      if (relative == '__af/bridge.js') {
        response.headers
          ..contentType = ContentType('text', 'javascript', charset: 'utf-8')
          ..set(HttpHeaders.cacheControlHeader, 'no-store');
        response.write(islandBridgeScript);
        await response.close();
        return;
      }

      final target = _safeJoin(p.join(root, 'web'), relative);
      final file = target == null ? null : File(target);
      if (file == null || !file.existsSync()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      response.headers
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('Cross-Origin-Opener-Policy', 'same-origin');

      // The policy and the bridge are put into the page as it is served, so an
      // island's own index.html stays a plain HTML file with nothing to
      // remember.
      if (p.extension(file.path).toLowerCase() == '.html') {
        response.headers.contentType = ContentType.html;
        response.write(
          injectIslandHead(await file.readAsString(), token: token),
        );
        await response.close();
        return;
      }

      response.headers.contentType = _contentTypeFor(file.path);
      await response.addStream(file.openRead());
      await response.close();
    } on Object catch (error) {
      Log.warn('An island could not be served: $error');
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } on Object catch (_) {
        // The connection has already gone.
      }
    }
  }

  String _newToken() {
    final bytes = List<int>.generate(_tokenBytes, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Puts the policy and the bridge at the top of the document.
  static String injectIslandHead(String html, {required String token}) {
    final head = '<meta http-equiv="Content-Security-Policy" '
        'content="$contentSecurityPolicy">'
        '<script src="/$token/__af/bridge.js"></script>';

    final at = html.toLowerCase().indexOf('<head>');
    if (at >= 0) {
      return html.replaceRange(at + 6, at + 6, head);
    }
    final htmlAt = html.toLowerCase().indexOf('<html');
    if (htmlAt >= 0) {
      final close = html.indexOf('>', htmlAt);
      if (close > 0) {
        return html.replaceRange(close + 1, close + 1, '<head>$head</head>');
      }
    }
    return '$head$html';
  }

  /// ⚠️ Refuses anything that climbs out of [root]. An island's folder name
  /// and every asset path come from a file on disk, so neither is trusted.
  static String? _safeJoin(String root, String relative) {
    if (relative.isEmpty) {
      return p.normalize(root);
    }
    final normalised =
        p.normalize(p.join(root, relative.replaceAll(r'\', '/')));
    return p.isWithin(root, normalised) || normalised == p.normalize(root)
        ? normalised
        : null;
  }

  static ContentType _contentTypeFor(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.js' || '.mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
        '.css' => ContentType('text', 'css', charset: 'utf-8'),
        '.json' => ContentType('application', 'json', charset: 'utf-8'),
        '.svg' => ContentType('image', 'svg+xml', charset: 'utf-8'),
        '.png' => ContentType('image', 'png'),
        '.jpg' || '.jpeg' => ContentType('image', 'jpeg'),
        '.gif' => ContentType('image', 'gif'),
        '.webp' => ContentType('image', 'webp'),
        '.woff2' => ContentType('font', 'woff2'),
        '.woff' => ContentType('font', 'woff'),
        '.ttf' => ContentType('font', 'ttf'),
        _ => ContentType.binary,
      };

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    _starting = null;
    _token = null;
    await server?.close(force: true);
  }
}

/// What an island can do, served from the extension's own origin.
///
/// Everything here is a message to Dart. The page has no outbound reach of its
/// own, so this is the entire surface.
const String islandBridgeScript = '''
(function () {
  var pending = {};
  var listeners = {};
  var nextId = 0;
  var readyQueue = [];
  var started = false;

  function post(message) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('afIsland', JSON.stringify(message));
      return true;
    }
    return false;
  }

  function flush() {
    while (readyQueue.length && post(readyQueue[0])) {
      readyQueue.shift();
    }
    if (readyQueue.length) {
      setTimeout(flush, 60);
    }
  }

  function send(message) {
    if (!post(message)) {
      readyQueue.push(message);
      setTimeout(flush, 60);
    }
  }

  var af = {
    /// Runs one of this extension's actions and answers with what it produced.
    call: function (action, args) {
      var id = 'c' + nextId++;
      return new Promise(function (resolve, reject) {
        pending[id] = { resolve: resolve, reject: reject };
        send({ kind: 'call', id: id, action: action, args: args || {} });
      });
    },

    /// The last value written under a key, without waiting.
    data: {},

    /// Called whenever a key changes.
    on: function (key, handler) {
      (listeners[key] = listeners[key] || []).push(handler);
      send({ kind: 'watch', key: key });
      return function () {
        listeners[key] = (listeners[key] || []).filter(function (h) {
          return h !== handler;
        });
      };
    },

    /// The block's own stored settings.
    settings: {},

    /// Theme tokens, also set as CSS custom properties.
    theme: {},

    /// Asks the host to remember a setting on this block.
    setSetting: function (key, value) {
      af.settings[key] = value;
      send({ kind: 'setting', key: key, value: value });
    },

    /// Raised once the host has handed over settings, data and the theme.
    onReady: function (handler) {
      if (started) { handler(); } else { readyHandlers.push(handler); }
    }
  };

  var readyHandlers = [];

  window.__afIslandResolve = function (id, ok, payload) {
    var waiting = pending[id];
    if (!waiting) { return; }
    delete pending[id];
    if (ok) { waiting.resolve(payload); } else { waiting.reject(new Error(payload)); }
  };

  window.__afIslandData = function (key, value) {
    af.data[key] = value;
    (listeners[key] || []).forEach(function (handler) {
      try { handler(value, key); } catch (e) {}
    });
  };

  window.__afIslandTheme = function (tokens) {
    af.theme = tokens || {};
    var root = document.documentElement;
    for (var name in af.theme) {
      root.style.setProperty('--af-' + name, af.theme[name]);
    }
    (listeners['__theme'] || []).forEach(function (handler) {
      try { handler(af.theme); } catch (e) {}
    });
  };

  window.__afIslandStart = function (settings, theme) {
    af.settings = settings || {};
    window.__afIslandTheme(theme);
    started = true;
    readyHandlers.forEach(function (handler) {
      try { handler(); } catch (e) {}
    });
    readyHandlers = [];
  };

  window.af = af;
  send({ kind: 'ready' });
})();
''';
