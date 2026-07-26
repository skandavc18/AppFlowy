import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Signs [payload] the way ONLYOFFICE expects (HS256, no extra headers).
String officeJwt(Map<String, Object?> payload, String secret) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  final header = encode(const {'alg': 'HS256', 'typ': 'JWT'});
  final body = encode(payload);
  final signature =
      Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$header.$body'));
  return '$header.$body.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
}

/// A document that the local bridge is currently serving.
class BridgedOfficeDocument {
  const BridgedOfficeDocument({
    required this.downloadUrl,
    required this.callbackUrl,
    required this.token,
  });

  final String downloadUrl;
  final String callbackUrl;
  final String token;
}

class _BridgeEntry {
  _BridgeEntry({
    required this.file,
    required this.onSaved,
    required this.secret,
  });

  final File file;
  final Future<void> Function(Uint8List bytes) onSaved;
  final String secret;
}

/// Serves office documents to a self hosted ONLYOFFICE Docs instance.
///
/// The document server runs out of process — usually in Docker — so it cannot
/// read the file from disk. The bridge hands it one unguessable URL to fetch
/// the document and one to post the edited copy back to.
class OfficeDocumentBridge {
  OfficeDocumentBridge._();

  static final OfficeDocumentBridge instance = OfficeDocumentBridge._();

  static const _tokenBytes = 24;

  HttpServer? _server;
  Future<HttpServer>? _starting;
  final Map<String, _BridgeEntry> _entries = {};
  final Random _random = Random.secure();

  int? get port => _server?.port;

  /// Publishes [file] and returns the URLs the editor configuration needs.
  Future<BridgedOfficeDocument> publish({
    required File file,
    required String host,
    required String secret,
    required Future<void> Function(Uint8List bytes) onSaved,
  }) async {
    final server = await _ensureServer();
    final token = _newToken();
    _entries[token] = _BridgeEntry(
      file: file,
      onSaved: onSaved,
      secret: secret,
    );
    final origin = 'http://$host:${server.port}';
    return BridgedOfficeDocument(
      downloadUrl: '$origin/documents/$token/${_safeName(file)}',
      callbackUrl: '$origin/documents/$token/callback',
      token: token,
    );
  }

  void revoke(String token) => _entries.remove(token);

  Future<void> shutdown() async {
    _entries.clear();
    final server = _server;
    _server = null;
    _starting = null;
    await server?.close(force: true);
  }

  String _safeName(File file) =>
      Uri.encodeComponent(p.basename(file.path)).replaceAll('%20', '_');

  String _newToken() {
    final bytes = List<int>.generate(
      _tokenBytes,
      (_) => _random.nextInt(256),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<HttpServer> _ensureServer() {
    final running = _server;
    if (running != null) {
      return Future.value(running);
    }
    return _starting ??= _start();
  }

  Future<HttpServer> _start() async {
    // The document server reaches this from another host (or a container), so
    // the socket cannot be limited to loopback. Every request has to carry the
    // random token that was handed out for exactly one document.
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen(
      _handle,
      onError: (Object error) => Log.error('Office bridge failed: $error'),
    );
    _server = server;
    Log.info('Office document bridge listening on port ${server.port}');
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length < 3 || segments.first != 'documents') {
      await _reject(request, HttpStatus.notFound);
      return;
    }
    final entry = _entries[segments[1]];
    if (entry == null) {
      await _reject(request, HttpStatus.notFound);
      return;
    }

    if (segments[2] == 'callback') {
      await _handleCallback(request, entry);
      return;
    }
    if (request.method != 'GET') {
      await _reject(request, HttpStatus.methodNotAllowed);
      return;
    }
    await _serveDocument(request, entry);
  }

  Future<void> _serveDocument(HttpRequest request, _BridgeEntry entry) async {
    try {
      final bytes = await entry.file.readAsBytes();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.binary
        ..headers.set(
          HttpHeaders.contentDisposition,
          'attachment; filename="${p.basename(entry.file.path)}"',
        )
        ..add(bytes);
    } on FileSystemException catch (error) {
      Log.error('Office bridge could not read the document: $error');
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  Future<void> _handleCallback(
    HttpRequest request,
    _BridgeEntry entry,
  ) async {
    if (request.method != 'POST') {
      await _reject(request, HttpStatus.methodNotAllowed);
      return;
    }

    Map<String, dynamic> body;
    try {
      final raw = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(raw);
      body = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (error) {
      Log.error('Office bridge received an unreadable callback: $error');
      await _reply(request, {'error': 1});
      return;
    }

    if (!_isCallbackTrusted(request, body, entry.secret)) {
      Log.error('Office bridge rejected an unsigned callback.');
      await _reply(request, {'error': 1});
      return;
    }

    final payload = body['payload'];
    if (payload is Map) {
      body = Map<String, dynamic>.from(payload);
    }

    final status = body['status'];
    // 2 = ready to save, 6 = force saved while the session is still open.
    if (status == 2 || status == 6) {
      final url = body['url'];
      if (url is String && url.isNotEmpty) {
        await _downloadInto(entry, url);
      }
    }
    await _reply(request, {'error': 0});
  }

  /// ONLYOFFICE signs the callback with the same secret when JWT is enabled.
  bool _isCallbackTrusted(
    HttpRequest request,
    Map<String, dynamic> body,
    String secret,
  ) {
    if (secret.isEmpty) {
      return true;
    }
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    final token = header != null && header.startsWith('Bearer ')
        ? header.substring(7)
        : body['token'] as String?;
    if (token == null || token.isEmpty) {
      return false;
    }
    final parts = token.split('.');
    if (parts.length != 3) {
      return false;
    }
    final expected = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('${parts[0]}.${parts[1]}'));
    final actual = base64Url.encode(expected.bytes).replaceAll('=', '');
    return _constantTimeEquals(actual, parts[2].replaceAll('=', ''));
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var mismatch = 0;
    for (var i = 0; i < a.length; i++) {
      mismatch |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return mismatch == 0;
  }

  Future<void> _downloadInto(_BridgeEntry entry, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 60));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await entry.onSaved(response.bodyBytes);
      } else {
        Log.error(
          'Office bridge could not fetch the saved document '
          '(${response.statusCode}).',
        );
      }
    } catch (error) {
      Log.error('Office bridge could not fetch the saved document: $error');
    }
  }

  Future<void> _reject(HttpRequest request, int status) async {
    request.response.statusCode = status;
    await request.response.close();
  }

  Future<void> _reply(HttpRequest request, Map<String, Object?> body) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }
}
