import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// The reasons a sign in can fail that AppFlowy names itself.
///
/// They travel in [ProviderFailure.detail] beside the standard OAuth codes, so
/// one mapping in the interface turns any of them into a sentence.
const oauthClientIdRequired = 'appflowy_client_id_required';
const oauthClientSecretRequired = 'appflowy_client_secret_required';
const oauthGrantRevoked = 'appflowy_grant_revoked';

/// What a token endpoint says when it refuses, as RFC 6749 §5.2 defines it.
@immutable
class OAuthError {
  const OAuthError({required this.code, this.description = ''});

  /// One of `invalid_client`, `invalid_grant`, `invalid_scope`, and so on.
  final String code;

  /// The service's own prose. Logged, never rendered.
  final String description;
}

/// Reads the error out of a token endpoint's answer.
///
/// This is the difference between "HTTP 400" and "the client secret is
/// missing": the body is a documented, machine-readable shape from a service
/// the person deliberately configured, and it is the only thing that says what
/// to correct.
OAuthError? readOAuthError(String body) {
  if (body.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return null;
    }
    final code = decoded['error'];
    // Some services nest it one level down under `error`.
    if (code is Map) {
      final nested = code['message'] ?? code['status'];
      return nested is String && nested.isNotEmpty
          ? OAuthError(code: _clamp(nested))
          : null;
    }
    if (code is! String || code.isEmpty) {
      return null;
    }
    final description = decoded['error_description'];
    return OAuthError(
      code: _clamp(code),
      description: description is String ? _clamp(description) : '',
    );
  } catch (_) {
    return null;
  }
}

/// A service decides how long these are, so nothing unbounded is carried.
String _clamp(String value) {
  final line = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length > 200 ? '${line.substring(0, 200)}…' : line;
}

/// The authorization code flow with PKCE, over a loopback redirect.
///
/// This is the flow every one of these services documents for a desktop
/// application, and the reason it is safe without a client secret: the browser
/// hands the code back to a socket only this process is listening on, and the
/// code is worthless without the verifier that never left the process.
///
/// Nothing about this flow ever sees a password.
class OAuthFlow {
  OAuthFlow({http.Client? client}) : _client = client ?? http.Client();

  /// Long enough to sign in and pick an account, short enough that a forgotten
  /// browser tab does not leave a socket open all day.
  static const timeout = Duration(minutes: 5);

  final http.Client _client;

  /// Runs the whole round trip and returns the credentials, or throws a
  /// [ProviderFailure] the interface can render.
  Future<ProviderCredentials> authorize({
    required OAuthEndpoints endpoints,
    required OAuthApp app,
    List<String>? scopeOverride,
  }) async {
    if (!app.isConfigured) {
      throw const ProviderFailure(
        ProviderStatus.authExpired,
        detail: oauthClientIdRequired,
      );
    }
    // Catch a missing secret here rather than after a whole browser round
    // trip: the token endpoint would only answer `invalid_client` anyway.
    if (endpoints.wantsClientSecret && app.clientSecret.isEmpty) {
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: oauthClientSecretRequired,
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/appflowy-oauth';
    final verifier = _randomToken(64);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomToken(24);

    try {
      final authorizationUrl = _authorizationUrl(
        endpoints: endpoints,
        app: app,
        redirectUri: redirectUri,
        challenge: challenge,
        state: state,
        scopes: scopeOverride ?? endpoints.scopes,
      );

      final opened = await launchUrl(
        authorizationUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const ProviderFailure(
          ProviderStatus.error,
          detail: 'Unable to open a browser for sign in.',
        );
      }

      final code = await _awaitCode(server, state).timeout(
        timeout,
        onTimeout: () => throw const ProviderFailure(
          ProviderStatus.error,
          detail: 'Sign in was not completed.',
        ),
      );

      return await _exchange(
        endpoints: endpoints,
        app: app,
        redirectUri: redirectUri,
        verifier: verifier,
        code: code,
      );
    } finally {
      await server.close(force: true);
    }
  }

  /// Trades a refresh token for a new access token.
  ///
  /// A service that answers 400 here has revoked the grant, which is an expired
  /// connection rather than an error — the way out is to sign in again.
  Future<ProviderCredentials> refresh({
    required OAuthEndpoints endpoints,
    required OAuthApp app,
    required String refreshToken,
  }) async {
    final response = await _post(endpoints.token, {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': app.clientId,
      if (app.clientSecret.isNotEmpty) 'client_secret': app.clientSecret,
    });

    if (response.statusCode == 400 || response.statusCode == 401) {
      throw ProviderFailure.authExpired(
        readOAuthError(response.body)?.code ?? oauthGrantRevoked,
      );
    }
    if (response.statusCode >= 400) {
      throw ProviderFailure.fromStatusCode(
        response.statusCode,
        retryAfterHeader: response.headers['retry-after'],
      );
    }

    // Google only returns a refresh token the first time, so the old one has
    // to be carried forward or the connection dies at the next expiry.
    return _credentialsFrom(response.body, fallbackRefreshToken: refreshToken);
  }

  void close() => _client.close();

  Uri _authorizationUrl({
    required OAuthEndpoints endpoints,
    required OAuthApp app,
    required String redirectUri,
    required String challenge,
    required String state,
    required List<String> scopes,
  }) {
    final base = Uri.parse(
      app.tenant.isEmpty
          ? endpoints.authorization
          : endpoints.authorization.replaceFirst('/common/', '/${app.tenant}/'),
    );
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'client_id': app.clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'state': state,
        if (endpoints.usesPkce) ...{
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
        },
        ...endpoints.extraAuthorizationParameters,
      },
    );
  }

  Future<String> _awaitCode(HttpServer server, String state) async {
    await for (final request in server) {
      if (request.uri.path != '/appflowy-oauth') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }

      final query = request.uri.queryParameters;
      final code = query['code'];
      final error = query['error_description'] ?? query['error'];

      // A mismatched state means the answer did not come from the request this
      // process started, so it is refused rather than used.
      final stateMatches = query['state'] == state;

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          _closingPage(
            ok: stateMatches && code != null && code.isNotEmpty,
          ),
        );
      await request.response.close();

      if (!stateMatches) {
        throw const ProviderFailure(
          ProviderStatus.error,
          detail: 'The sign in answer did not match the request.',
        );
      }
      if (code == null || code.isEmpty) {
        throw ProviderFailure(
          ProviderStatus.error,
          detail: error ?? 'Sign in was cancelled.',
        );
      }
      return code;
    }
    throw const ProviderFailure(
      ProviderStatus.error,
      detail: 'The sign in window closed before it finished.',
    );
  }

  Future<ProviderCredentials> _exchange({
    required OAuthEndpoints endpoints,
    required OAuthApp app,
    required String redirectUri,
    required String verifier,
    required String code,
  }) async {
    final response = await _post(endpoints.token, {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': app.clientId,
      if (endpoints.usesPkce) 'code_verifier': verifier,
      if (app.clientSecret.isNotEmpty) 'client_secret': app.clientSecret,
    });

    if (response.statusCode >= 400) {
      final failure = readOAuthError(response.body);
      // The description is the service's own words, so it is logged rather
      // than shown; the code is what the interface turns into a sentence.
      Log.warn(
        'Token exchange refused: HTTP ${response.statusCode} '
        '${failure?.code ?? ''} ${failure?.description ?? ''}',
      );
      throw ProviderFailure(
        ProviderStatus.error,
        detail: failure?.code ?? 'HTTP ${response.statusCode}',
      );
    }
    return _credentialsFrom(response.body);
  }

  Future<http.Response> _post(String url, Map<String, String> body) async {
    try {
      return await _client
          .post(
            Uri.parse(url),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const ProviderFailure.offline();
    } on TimeoutException {
      throw const ProviderFailure.offline('The service did not answer.');
    }
  }

  static ProviderCredentials _credentialsFrom(
    String body, {
    String fallbackRefreshToken = '',
  }) {
    Map<String, dynamic> values;
    try {
      final decoded = jsonDecode(body);
      values = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      values = {};
    }

    final access = values['access_token'];
    if (access is! String || access.isEmpty) {
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'The service did not return a token.',
      );
    }

    final expiresIn = values['expires_in'];
    final refresh = values['refresh_token'];
    return ProviderCredentials(
      accessToken: access,
      refreshToken: refresh is String && refresh.isNotEmpty
          ? refresh
          : fallbackRefreshToken,
      tokenType: values['token_type'] is String
          ? _normalizeTokenType(values['token_type'] as String)
          : 'Bearer',
      expiresAt: expiresIn is int
          ? DateTime.now().add(Duration(seconds: expiresIn))
          : expiresIn is String && int.tryParse(expiresIn) != null
              ? DateTime.now().add(Duration(seconds: int.parse(expiresIn)))
              : null,
    );
  }

  /// Services spell it `bearer`, `Bearer` and `BEARER`; a header has to be one
  /// of them.
  static String _normalizeTokenType(String raw) =>
      raw.toLowerCase() == 'bearer' ? 'Bearer' : raw;

  static String _randomToken(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '').substring(0, length);
  }

  /// The page the browser is left on. Deliberately plain and self-contained —
  /// it loads nothing, so nothing about the sign in leaves the machine.
  static String _closingPage({required bool ok}) => '''
<!doctype html>
<html><head><meta charset="utf-8"><title>AppFlowy</title>
<style>
  html,body{height:100%;margin:0}
  body{display:flex;align-items:center;justify-content:center;
    font:15px/1.6 -apple-system,"Segoe UI Variable Text","Segoe UI",system-ui,sans-serif;
    background:#faf9f7;color:#1f2328}
  main{text-align:center;max-width:24rem;padding:2rem}
  h1{font-size:1.1rem;font-weight:600;margin:0 0 .35rem}
  p{margin:0;color:#57606a}
</style></head>
<body><main>
<h1>${ok ? 'Connected' : 'Sign in was not completed'}</h1>
<p>${ok ? 'You can close this tab and go back to AppFlowy.' : 'Nothing was changed. You can close this tab.'}</p>
</main></body></html>
''';
}
