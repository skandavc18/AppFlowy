import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy_backend/log.dart';

import 'workflow_scheduler.dart';

/// Listens on this computer only, so other apps and scripts here can start a
/// workflow with an HTTP request.
///
/// ⚠️ Bound to the loopback address, never to every interface: a webhook is a
/// way for this machine to talk to AppFlowy, not a door for the network. The
/// address carries a long random secret, so a web page in a browser cannot
/// guess its way to a workflow either.
class WorkflowWebhookServer {
  WorkflowWebhookServer({
    required this.handler,
    this.preferredPort = defaultPort,
  });

  static const defaultPort = 43117;

  /// A webhook carries a notification, not a file.
  static const maximumBodyBytes = 1024 * 1024;

  static const _withheldHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
  };

  final Future<WorkflowWebhookAnswer> Function(
    String workflowId,
    String token,
    Map<String, Object?> payload,
  ) handler;
  final int preferredPort;

  HttpServer? _server;
  Future<int?>? _starting;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  String addressFor(String workflowId, String token) =>
      'http://127.0.0.1:${port == 0 ? preferredPort : port}'
      '/hooks/$workflowId/$token';

  /// Starts listening; the port it got, or null when it could not listen.
  Future<int?> start() {
    final server = _server;
    if (server != null) {
      return Future.value(server.port);
    }
    return _starting ??= _start();
  }

  Future<int?> _start() async {
    try {
      HttpServer server;
      try {
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          preferredPort,
        );
      } on SocketException {
        // Something else has the usual port. Any free one still works; the
        // address shown in the editor follows it.
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }
      server.autoCompress = false;
      server.idleTimeout = const Duration(seconds: 30);
      server.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object error) =>
            Log.warn('The workflow webhook listener failed: $error'),
      );
      _server = server;
      return server.port;
    } on Object catch (error) {
      Log.warn('Workflow webhooks could not listen: $error');
      return null;
    } finally {
      _starting = null;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set('cache-control', 'no-store');
      final segments = request.uri.pathSegments;
      if (segments.length != 3 || segments.first != 'hooks') {
        await _answer(response, 404, {'ok': false, 'error': 'Not found.'});
        return;
      }
      const methods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'};
      if (!methods.contains(request.method)) {
        await _answer(
          response,
          405,
          {'ok': false, 'error': 'Use GET, POST, PUT, PATCH or DELETE.'},
        );
        return;
      }
      // The body is read even when it is too large, so the sender gets the
      // answer rather than a reset connection — but only up to a point.
      var tooLarge = request.contentLength > maximumBodyBytes;
      var seen = 0;
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 20))) {
        seen += chunk.length;
        if (tooLarge || seen > maximumBodyBytes) {
          tooLarge = true;
          if (seen > 8 * maximumBodyBytes) {
            break;
          }
          continue;
        }
        bytes.addAll(chunk);
      }
      if (tooLarge) {
        await _answer(response, 413, {'ok': false, 'error': 'Too large.'});
        return;
      }
      final payload = <String, Object?>{
        'method': request.method,
        'query': request.uri.queryParameters,
        'headers': _headersOf(request.headers),
        'body': _decodeBody(
          utf8.decode(bytes, allowMalformed: true),
          request.headers.contentType,
        ),
        'receivedAt': DateTime.now().toIso8601String(),
      };
      final answer = await handler(segments[1], segments[2], payload);
      await _answer(response, answer.status, answer.body);
    } on Object catch (error) {
      Log.warn('A workflow webhook request failed: $error');
      try {
        await _answer(response, 500, {'ok': false, 'error': 'Failed.'});
      } on Object {
        // The connection is already gone.
      }
    }
  }

  static Map<String, String> _headersOf(HttpHeaders headers) {
    final values = <String, String>{};
    headers.forEach((name, list) {
      final key = name.toLowerCase();
      if (_withheldHeaders.contains(key) || values.length >= 40) {
        return;
      }
      final joined = list.join(', ');
      values[key] =
          joined.length > 500 ? '${joined.substring(0, 500)}…' : joined;
    });
    return values;
  }

  static Object? _decodeBody(String text, ContentType? type) {
    if (text.isEmpty) {
      return const <String, Object?>{};
    }
    final mime = type?.mimeType ?? '';
    final trimmed = text.trimLeft();
    if (mime.contains('json') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[')) {
      try {
        return jsonDecode(text);
      } on FormatException {
        return text;
      }
    }
    if (mime == 'application/x-www-form-urlencoded') {
      try {
        return Uri.splitQueryString(text);
      } on Object {
        return text;
      }
    }
    return text;
  }

  static Future<void> _answer(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await response.close();
  }
}
