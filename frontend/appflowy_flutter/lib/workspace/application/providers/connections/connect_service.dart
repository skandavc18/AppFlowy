import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_flow.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;

/// Connects an account, once, for the whole application.
///
/// Every path through this class ends the same way: a token in the sealed
/// store and a [ProviderConnection] describing the account. Nothing else in the
/// application authenticates, which is what makes "sign in once and reuse it"
/// true rather than aspirational.
class ProviderConnector {
  ProviderConnector({
    http.Client? client,
    ProviderConnections? connections,
    OAuthFlow? oauth,
  })  : _client = client ?? http.Client(),
        _connections = connections ?? ProviderConnections.instance,
        _oauth = oauth ?? OAuthFlow();

  final http.Client _client;
  final ProviderConnections _connections;
  final OAuthFlow _oauth;

  /// Connects a service that issues its own token: Immich, GitHub, GitLab.
  ///
  /// The token is verified before anything is stored, so a mistyped one is
  /// reported here rather than as a broken collection later.
  Future<ProviderConnection> connectWithToken({
    required ProviderService service,
    required String token,
    String host = '',
    List<String> scopes = const <String>[],
  }) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw const ProviderFailure(
        ProviderStatus.authExpired,
        detail: 'No token was given.',
      );
    }
    // A token goes into an HTTP header. A line break in one would let the rest
    // of the header be written by whoever supplied it.
    if (trimmed.contains('\n') || trimmed.contains('\r')) {
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'That does not look like a token.',
      );
    }

    final normalizedHost = _normalizeHost(service, host);
    final credentials = ProviderCredentials(
      accessToken: trimmed,
      tokenType: service == ProviderService.immich ? 'x-api-key' : 'Bearer',
    );

    final account = await _identify(service, normalizedHost, credentials);
    final connection = ProviderConnection(
      id: ProviderConnections.idFor(
        service,
        host: normalizedHost,
        account: account.id,
      ),
      service: service,
      accountLabel: account.label,
      accountId: account.id,
      host: normalizedHost,
      scopes: scopes.isEmpty ? account.scopes : scopes,
      connectedAt: DateTime.now(),
      avatarUrl: account.avatarUrl,
    );

    await _connections.upsert(connection, credentials);
    return connection;
  }

  /// Connects a service that signs in through a browser.
  Future<ProviderConnection> connectWithOAuth({
    required ProviderService service,
    bool requestWriteAccess = false,
  }) async {
    final endpoints = OAuthServices.forService(service);
    if (endpoints == null) {
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'That service does not sign in this way.',
      );
    }

    final app = await OAuthAppRegistry.instance.read(service);
    if (app == null || !app.isConfigured) {
      throw const ProviderFailure(
        ProviderStatus.authExpired,
        detail: 'No application identity is configured for this service.',
      );
    }

    // Only ask for write access when somebody has said they want to write.
    // Asking for it up front is how an application ends up holding a
    // permission it never uses.
    final writeScopes =
        requestWriteAccess ? OAuthServices.writeScopesFor(service) : null;
    final scopes = writeScopes == null
        ? endpoints.scopes
        : <String>{...endpoints.scopes, ...writeScopes.scopes}.toList();

    final credentials = await _oauth.authorize(
      endpoints: endpoints,
      app: app,
      scopeOverride: scopes,
    );

    final account = await _identify(service, '', credentials);
    final connection = ProviderConnection(
      id: ProviderConnections.idFor(service, account: account.id),
      service: service,
      accountLabel: account.label,
      accountId: account.id,
      scopes: scopes,
      connectedAt: DateTime.now(),
      expiresAt: credentials.expiresAt,
      avatarUrl: account.avatarUrl,
    );

    await _connections.upsert(connection, credentials);
    return connection;
  }

  /// Asks the service who the token belongs to.
  ///
  /// Every service has exactly one cheap endpoint for this, and its answer is
  /// what the connections list shows — a connection labelled with a truncated
  /// token would be useless.
  Future<_Account> _identify(
    ProviderService service,
    String host,
    ProviderCredentials credentials,
  ) async {
    final request = switch (service) {
      ProviderService.immich => (
          url: '${_immichApi(host)}/users/me',
          label: (Map<String, dynamic> body) =>
              _string(body['email']).isNotEmpty
                  ? _string(body['email'])
                  : _string(body['name'], 'Immich'),
          id: (Map<String, dynamic> body) => _string(body['id']),
          avatar: (Map<String, dynamic> body) => '',
        ),
      ProviderService.github => (
          url: '${_gitHubApi(host)}/user',
          label: (Map<String, dynamic> body) =>
              _string(body['login'], 'GitHub'),
          id: (Map<String, dynamic> body) => _string(body['login']),
          avatar: (Map<String, dynamic> body) => _string(body['avatar_url']),
        ),
      ProviderService.gitlab => (
          url: '${_gitLabApi(host)}/user',
          label: (Map<String, dynamic> body) =>
              _string(body['username'], 'GitLab'),
          id: (Map<String, dynamic> body) => _string(body['username']),
          avatar: (Map<String, dynamic> body) => _string(body['avatar_url']),
        ),
      ProviderService.googlePhotos || ProviderService.googleDrive => (
          url: 'https://openidconnect.googleapis.com/v1/userinfo',
          label: (Map<String, dynamic> body) =>
              _string(body['email'], _string(body['name'], 'Google')),
          id: (Map<String, dynamic> body) => _string(body['sub']),
          avatar: (Map<String, dynamic> body) => _string(body['picture']),
        ),
      ProviderService.oneDrive => (
          url: 'https://graph.microsoft.com/v1.0/me',
          label: (Map<String, dynamic> body) => _string(
                body['userPrincipalName'],
                _string(body['displayName'], 'Microsoft'),
              ),
          id: (Map<String, dynamic> body) => _string(body['id']),
          avatar: (Map<String, dynamic> body) => '',
        ),
      ProviderService.box => (
          url: 'https://api.box.com/2.0/users/me',
          label: (Map<String, dynamic> body) =>
              _string(body['login'], _string(body['name'], 'Box')),
          id: (Map<String, dynamic> body) => _string(body['id']),
          avatar: (Map<String, dynamic> body) => '',
        ),
      ProviderService.local => throw const ProviderFailure(
          ProviderStatus.error,
          detail: 'The workspace does not need connecting.',
        ),
    };

    final body = await _get(request.url, credentials);
    return _Account(
      id: request.id(body),
      label: request.label(body),
      avatarUrl: request.avatar(body),
      scopes: const <String>[],
    );
  }

  Future<Map<String, dynamic>> _get(
    String url,
    ProviderCredentials credentials,
  ) async {
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          ...credentials.authorizationHeaders,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode >= 400) {
        Log.warn('A connection check was refused: HTTP ${response.statusCode}');
        throw ProviderFailure.fromStatusCode(response.statusCode);
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on ProviderFailure {
      rethrow;
    } on SocketException {
      throw const ProviderFailure.offline();
    } on TimeoutException {
      throw const ProviderFailure.offline('The service did not answer.');
    } catch (error) {
      Log.warn('A connection check failed: $error');
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'The service answered with something unreadable.',
      );
    }
  }

  /// Whatever somebody typed, turned into a base address, or refused.
  ///
  /// A server address is the one field here that becomes a URL, so anything
  /// that is not plain `https://host[:port]` is rejected rather than repaired.
  static String _normalizeHost(ProviderService service, String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) {
      if (ProviderServices.of(service).needsHost &&
          service != ProviderService.gitlab) {
        throw const ProviderFailure(
          ProviderStatus.error,
          detail: 'A server address is needed.',
        );
      }
      return '';
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'That is not a server address.',
      );
    }

    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  static String _immichApi(String host) {
    final base = host.replaceAll(RegExp(r'/+$'), '');
    return base.endsWith('/api') ? base : '$base/api';
  }

  static String _gitHubApi(String host) => host.isEmpty
      ? 'https://api.github.com'
      : '${host.replaceAll(RegExp(r'/+$'), '')}/api/v3';

  static String _gitLabApi(String host) =>
      '${(host.isEmpty ? 'https://gitlab.com' : host).replaceAll(RegExp(r'/+$'), '')}/api/v4';

  static String _string(Object? value, [String fallback = '']) =>
      value is String && value.isNotEmpty ? value : fallback;

  void close() {
    _client.close();
    _oauth.close();
  }
}

class _Account {
  const _Account({
    required this.id,
    required this.label,
    required this.avatarUrl,
    required this.scopes,
  });

  final String id;
  final String label;
  final String avatarUrl;
  final List<String> scopes;
}
