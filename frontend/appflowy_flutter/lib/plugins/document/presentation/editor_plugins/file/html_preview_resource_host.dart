import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

/// Gives a sanitized, in-memory document a real origin for relative resources.
/// WebView2 NavigateToString ignores InAppWebViewInitialData.baseUrl. A base
/// element cannot fix that for file resources (and our CSP forbids one).
///
/// Each mounted preview owns a loopback port and an unguessable path. Only
/// passive resources below its directory are served, never directory listings,
/// arbitrary documents, parent paths or symlinks escaping that directory.
/// HTML and credentials are never written to disk or sent to a remote server.
class HtmlPreviewResourceHost {
  HtmlPreviewResourceHost({required String directory})
      : _directory = Directory(directory).absolute,
        _token = base64UrlEncode(
          List<int>.generate(24, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', '');

  final Directory _directory;
  final String _token;
  Future<HttpServer>? _starting;
  HttpServer? _server;
  String? _root;
  String _html = '';
  String _documentName = '';
  int _revision = 0;
  bool _disposed = false;

  Future<Uri> load(String sanitizedHtml) async {
    if (_disposed) throw StateError('The preview has been closed.');
    final name = '__document_${++_revision}.html';
    _documentName = name;
    _html = sanitizedHtml;
    final server = await (_starting ??= _start());
    if (_disposed) throw StateError('The preview has been closed.');
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [_token, name],
    );
  }

  Future<HttpServer> _start() async {
    _root = await _directory.resolveSymbolicLinks();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_disposed) {
      await server.close(force: true);
      throw StateError('The preview has been closed.');
    }
    _server = server;
    server.listen((request) => unawaited(_serve(request)));
    return server;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final server = _server;
      final root = _root;
      final host = server == null ? '' : '127.0.0.1:${server.port}';
      final origin = request.headers.value('Origin');
      final segments = request.uri.pathSegments;
      response.headers
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('Referrer-Policy', 'no-referrer')
        ..set('Cross-Origin-Resource-Policy', 'same-origin')
        ..set(
            'Content-Security-Policy',
            "script-src 'none'; connect-src 'none'; "
                "object-src 'none'; frame-src 'none'; worker-src 'none'; "
                "base-uri 'none'; form-action 'none'");
      if (_disposed ||
          root == null ||
          request.headers.value(HttpHeaders.hostHeader) != host ||
          (origin != null && origin != 'http://$host') ||
          segments.length < 2 ||
          segments.first != _token) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        return;
      }
      if (segments.length == 2 && segments[1] == _documentName) {
        response.headers.contentType = ContentType.html;
        if (request.method == 'GET') response.write(_html);
        return;
      }
      final relative = segments.skip(1).toList();
      if (relative.any(
        (segment) =>
            segment.isEmpty ||
            segment == '..' ||
            segment == '.' ||
            segment.contains(RegExp(r'[\\/:\x00]')),
      )) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final path = p.normalize(p.joinAll([root, ...relative]));
      final type = lookupMimeType(path);
      if (!p.isWithin(root, path) || !_isPassive(type)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final resolved = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      response.headers.contentType = ContentType.parse(type!);
      if (request.method == 'GET') {
        await response.addStream(File(resolved).openRead());
      }
    } on FileSystemException {
      try {
        response.statusCode = HttpStatus.notFound;
      } on Object {
        // Headers may already have been sent before the file disappeared.
      }
    } on Object {
      // A renderer can close a request while switching pages. Never leave an
      // unhandled async error or include filesystem paths in the HTTP response.
    } finally {
      try {
        await response.close();
      } on Object {
        // The client may already have disconnected.
      }
    }
  }

  static bool _isPassive(String? type) =>
      type != null &&
      (type.startsWith('image/') ||
          type.startsWith('font/') ||
          type.startsWith('audio/') ||
          type.startsWith('video/') ||
          const {
            'text/css',
            'application/font-woff',
            'application/vnd.ms-fontobject',
            'application/x-font-ttf',
            'application/x-font-opentype',
          }.contains(type));

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _html = '';
    final starting = _starting;
    if (starting == null) return;
    try {
      final server = await starting;
      await server.close(force: true);
    } on Object {
      // A pending start disposes its own server if the view has gone away.
    }
    _server = null;
  }
}
