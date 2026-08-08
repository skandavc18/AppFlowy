import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_flow.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;

/// The one way a provider talks to a service.
///
/// It owns the three things every provider would otherwise get subtly wrong:
/// attaching the credentials, refreshing them exactly once when they expire,
/// and turning whatever the service answered into a [ProviderFailure] the
/// interface already knows how to draw. A raw response body never escapes it.
class ProviderTransport {
  ProviderTransport({
    required this.connectionId,
    http.Client? client,
    ProviderConnections? connections,
    OAuthFlow? oauth,
  })  : _client = client ?? http.Client(),
        _connections = connections ?? ProviderConnections.instance,
        _oauth = oauth ?? OAuthFlow();

  /// A stranger's server decides how much it sends; nothing is read past this
  /// without an explicit larger cap from the caller.
  static const defaultMaxBytes = 32 << 20;

  static const _requestTimeout = Duration(seconds: 30);
  static const _downloadTimeout = Duration(minutes: 5);

  final String connectionId;
  final http.Client _client;
  final ProviderConnections _connections;
  final OAuthFlow _oauth;

  ProviderCredentials? _credentials;
  Future<ProviderCredentials>? _refreshing;

  Future<ProviderCredentials> credentials() async {
    final cached = _credentials;
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    final stored = await _connections.credentialsFor(connectionId);
    if (stored == null) {
      throw const ProviderFailure.authExpired('No token is stored.');
    }
    if (!stored.isExpired) {
      _credentials = stored;
      return stored;
    }
    if (!stored.canRefresh) {
      throw const ProviderFailure.authExpired('The token has expired.');
    }
    return _refresh(stored);
  }

  Future<ProviderCredentials> _refresh(ProviderCredentials expired) {
    // One refresh at a time: a screen that fires six reads at once must not
    // spend six refresh tokens, and most services invalidate the old one.
    return _refreshing ??= () async {
      try {
        final connection = _connections.byId(connectionId);
        final endpoints = connection == null
            ? null
            : OAuthServices.forService(connection.service);
        final app = connection == null
            ? null
            : await OAuthAppRegistry.instance.read(connection.service);
        if (endpoints == null || app == null) {
          Log.warn(
            'Cannot renew a sign in: '
            '${connection == null ? 'the connection is gone' : app == null ? 'no application identity is stored' : 'the service does not refresh'}.',
          );
          throw const ProviderFailure.authExpired('Cannot renew this sign in.');
        }

        final renewed = await _oauth.refresh(
          endpoints: endpoints,
          app: app,
          refreshToken: expired.refreshToken,
        );
        await _connections.updateCredentials(connectionId, renewed);
        _credentials = renewed;
        return renewed;
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// A JSON request. Returns the decoded body, never the raw response.
  Future<Object?> json(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
    Map<String, String>? query,
  }) async {
    final response = await send(
      url,
      method: method,
      headers: {
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        ...?headers,
      },
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      query: query,
    );
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } catch (error) {
      Log.warn('A provider answered with something other than JSON: $error');
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'The service answered with something unreadable.',
      );
    }
  }

  /// A form-encoded request, for the services that still want one.
  Future<Object?> form(
    String url,
    Map<String, String> fields, {
    String method = 'POST',
  }) async {
    final response = await send(
      url,
      method: method,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: utf8.encode(
        fields.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      ),
    );
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  /// One request, with the credentials attached and one retry after a refresh.
  Future<http.Response> send(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    List<int>? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    var response = await _sendOnce(
      url,
      method: method,
      headers: headers,
      body: body,
      query: query,
      authenticated: authenticated,
    );

    if (response.statusCode == 401 && authenticated) {
      final stored =
          _credentials ?? await _connections.credentialsFor(connectionId);
      if (stored != null && stored.canRefresh) {
        await _refresh(stored);
        response = await _sendOnce(
          url,
          method: method,
          headers: headers,
          body: body,
          query: query,
          authenticated: authenticated,
        );
      }
    }

    if (response.statusCode >= 400) {
      throw ProviderFailure.fromStatusCode(
        response.statusCode,
        retryAfterHeader: response.headers['retry-after'] ??
            response.headers['x-ratelimit-reset'],
      );
    }
    return response;
  }

  Future<http.Response> _sendOnce(
    String url, {
    required String method,
    Map<String, String>? headers,
    List<int>? body,
    Map<String, String>? query,
    required bool authenticated,
  }) async {
    var uri = Uri.parse(url);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }

    final request = http.Request(method, uri)
      ..followRedirects = true
      ..maxRedirects = 6;
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (authenticated) {
      request.headers.addAll((await credentials()).authorizationHeaders);
    }
    if (body != null) {
      request.bodyBytes = Uint8List.fromList(body);
    }

    try {
      final streamed = await _client.send(request).timeout(_requestTimeout);
      return await http.Response.fromStream(streamed);
    } on ProviderFailure {
      rethrow;
    } on SocketException {
      throw const ProviderFailure.offline();
    } on HttpException {
      throw const ProviderFailure.offline();
    } on TimeoutException {
      throw const ProviderFailure.offline('The service did not answer.');
    }
  }

  /// Reads bytes with a hard cap, so a large file cannot be pulled into memory
  /// whole just because a service offered it.
  Future<Uint8List> bytes(
    String url, {
    Map<String, String>? headers,
    int maxBytes = defaultMaxBytes,
    bool authenticated = true,
  }) async {
    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = true
      ..maxRedirects = 6;
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (authenticated) {
      request.headers.addAll((await credentials()).authorizationHeaders);
    }

    try {
      final streamed = await _client.send(request).timeout(_requestTimeout);
      if (streamed.statusCode >= 400) {
        await streamed.stream.drain<void>();
        throw ProviderFailure.fromStatusCode(
          streamed.statusCode,
          retryAfterHeader: streamed.headers['retry-after'],
        );
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(_downloadTimeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const ProviderFailure(
            ProviderStatus.error,
            detail: 'The file is larger than AppFlowy will read in one go.',
          );
        }
      }
      return builder.takeBytes();
    } on ProviderFailure {
      rethrow;
    } on SocketException {
      throw const ProviderFailure.offline();
    } on TimeoutException {
      throw const ProviderFailure.offline('The download stalled.');
    }
  }

  /// Streams a download straight to [destination], for anything big enough
  /// that holding it in memory would be silly.
  Future<void> download(
    String url,
    File destination, {
    Map<String, String>? headers,
    int maxBytes = 512 << 20,
    void Function(int received, int? total)? onProgress,
    bool authenticated = true,
  }) async {
    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = true
      ..maxRedirects = 6;
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (authenticated) {
      request.headers.addAll((await credentials()).authorizationHeaders);
    }

    // Stage beside the destination and rename, so a cancelled download never
    // leaves a half file that later reads as a corrupt one.
    final staging = File('${destination.path}.part');
    await destination.parent.create(recursive: true);

    try {
      final streamed = await _client.send(request).timeout(_requestTimeout);
      if (streamed.statusCode >= 400) {
        await streamed.stream.drain<void>();
        throw ProviderFailure.fromStatusCode(streamed.statusCode);
      }

      final sink = staging.openWrite();
      var received = 0;
      try {
        await for (final chunk in streamed.stream.timeout(_downloadTimeout)) {
          received += chunk.length;
          if (received > maxBytes) {
            throw const ProviderFailure(
              ProviderStatus.error,
              detail: 'The file is larger than AppFlowy will download.',
            );
          }
          sink.add(chunk);
          onProgress?.call(received, streamed.contentLength);
        }
      } finally {
        await sink.close();
      }
      await staging.rename(destination.path);
    } on ProviderFailure {
      await _discard(staging);
      rethrow;
    } on SocketException {
      await _discard(staging);
      throw const ProviderFailure.offline();
    } on TimeoutException {
      await _discard(staging);
      throw const ProviderFailure.offline('The download stalled.');
    }
  }

  static Future<void> _discard(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // A leftover staging file is not worth reporting.
    }
  }

  void close() {
    _client.close();
    _oauth.close();
  }
}

/// A working access token for [connectionId], renewed if it had expired.
///
/// For the one thing that is not an HTTP request: IMAP presents the same token
/// as `XOAUTH2`, and it must go through the same renewal as everything else or
/// mail would be the only feature that expires after an hour.
Future<String?> providerAccessToken(String connectionId) async {
  final transport = ProviderTransport(connectionId: connectionId);
  try {
    return (await transport.credentials()).accessToken;
  } on ProviderFailure catch (failure) {
    Log.warn('No usable token for a connection: ${failure.status.name}');
    return null;
  } catch (error) {
    Log.warn('No usable token for a connection: $error');
    return null;
  } finally {
    transport.close();
  }
}
