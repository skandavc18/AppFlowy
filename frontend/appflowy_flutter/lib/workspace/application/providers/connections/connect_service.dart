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
    OAuthAppRegistry? apps,
  })  : _client = client ?? http.Client(),
        _connections = connections ?? ProviderConnections.instance,
        _oauth = oauth ?? OAuthFlow(),
        _apps = apps ?? OAuthAppRegistry.instance;

  final http.Client _client;
  final ProviderConnections _connections;
  final OAuthFlow _oauth;
  final OAuthAppRegistry _apps;

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
  ///
  /// One round trip asks for everything the account can do, so signing in to
  /// Google covers Drive, Photos, Calendar and mail together. What comes back
  /// joins the account already signed in rather than standing beside it.
  ///
  /// [preferAccountId] names the account being added to. Null means whichever
  /// account of this family is already signed in, which is what a plain
  /// "sign in again" wants; an empty string means a NEW account, so it starts
  /// from this service's own permissions instead of inheriting another
  /// person's. Any other value makes the sign in for that account alone.
  ///
  /// [reconnectId] is the connection a collection or page embed names, when
  /// this sign in is to bring it back. The sign in is then for that
  /// connection's account, and its token lands under that very id — even when
  /// the connection had been removed in the meantime.
  Future<ProviderConnection> connectWithOAuth({
    required ProviderService service,
    bool requestWriteAccess = false,
    String? preferAccountId,
    String? reconnectId,
  }) async {
    final endpoints = OAuthServices.forService(service);
    if (endpoints == null) {
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'That service does not sign in this way.',
      );
    }

    final app = await _apps.read(service);
    if (app == null || !app.isConfigured) {
      throw const ProviderFailure(
        ProviderStatus.authExpired,
        detail: 'No application identity is configured for this service.',
      );
    }

    await _connections.ensureLoaded();
    final family = ProviderServices.of(service).family;
    // A family that issues one token per capability keeps them in separate
    // connections, so only the one holding this capability may be joined.
    final scoped = family.sharesOneGrant ? null : service;
    final reviving =
        reconnectId == null || reconnectId.isEmpty ? null : reconnectId;
    final bound = reviving == null ? null : _connections.byId(reviving);
    final expected = expectedAccountFor(
      service,
      preferAccountId: preferAccountId,
      reconnectId: reviving,
      bound: bound,
    );
    final existing = preferAccountId != null && preferAccountId.isEmpty
        ? null
        : bound ??
            _connections.accountFor(
              family,
              accountId: expected ?? preferAccountId ?? '',
              service: scoped,
            );

    // Only ask for write access when somebody has said they want to write.
    // Asking for it up front is how an application ends up holding a
    // permission it never uses.
    final writeScopes =
        requestWriteAccess ? OAuthServices.writeScopesFor(service) : null;
    final scopes = <String>{
      ...OAuthServices.scopesForAccount(service),
      // A permission already granted must be asked for again or it is dropped.
      ...?existing?.scopes,
      ...?writeScopes?.scopes,
    }.toList();

    final credentials = await _oauth.authorize(
      endpoints: endpoints,
      app: app,
      scopeOverride: scopes,
      loginHint: expected == null
          ? null
          : _loginHint(family, expected, bound ?? existing),
    );

    final account = await _identify(service, '', credentials);
    // The browser offers whichever account it is signed in to. Storing that
    // one would leave the thing being reconnected on the token that failed,
    // and quietly add an account nobody asked for.
    if (expected != null &&
        account.id.toLowerCase() != expected.toLowerCase()) {
      Log.warn('A sign in came back as an account nobody asked for.');
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: oauthWrongAccount,
      );
    }

    // Only an account that was checked may land under the id a collection
    // names.
    final reconnecting = expected == null ? null : reviving;
    final joined = _connections.accountFor(
          family,
          accountId: account.id,
          service: scoped,
        ) ??
        (reconnecting == null ? null : bound);
    final connection = ProviderConnection(
      // Keep the id an account already has: every collection and page embed
      // bound to it names that id. One that was removed gets back the id its
      // collection still names, so it reads again without being bound anew.
      id: joined?.id ??
          reconnecting ??
          ProviderConnections.idFor(service, account: account.id),
      service: joined?.service ?? service,
      accountLabel: account.label,
      accountId: account.id,
      scopes: scopes,
      services: {
        ...?joined?.covered,
        ...OAuthServices.servicesGrantedBy(service, scopes),
      },
      connectedAt: joined?.connectedAt ?? DateTime.now(),
      expiresAt: credentials.expiresAt,
      avatarUrl: account.avatarUrl,
    );

    final renewed = <ProviderConnection>[
      connection,
      // The same account under the ids it was signed in with before one sign
      // in covered everything: the same grant, so the same token.
      for (final other in _connections.sharingGrantWith(connection))
        other.copyWith(
          accountLabel: account.label,
          scopes: scopes,
          expiresAt: credentials.expiresAt,
          avatarUrl: account.avatarUrl,
        ),
    ];
    // The connection this was asked to bring back takes the token whatever
    // else holds it, including when it was removed and only a collection still
    // names it.
    if (reconnecting != null && !renewed.any((c) => c.id == reconnecting)) {
      renewed.add(
        bound?.copyWith(
              accountLabel: account.label,
              accountId: account.id,
              scopes: scopes,
              expiresAt: credentials.expiresAt,
              avatarUrl: account.avatarUrl,
            ) ??
            ProviderConnection(
              id: reconnecting,
              service: service,
              accountLabel: account.label,
              accountId: account.id,
              scopes: scopes,
              services: {service},
              connectedAt: DateTime.now(),
              expiresAt: credentials.expiresAt,
              avatarUrl: account.avatarUrl,
            ),
      );
    }

    await _connections.upsertAll(renewed, credentials);
    return connection;
  }

  /// Whose account a sign in is for, or null when any account will do.
  ///
  /// A connection being brought back says so itself or, once removed, through
  /// the id its collection still names. Otherwise [preferAccountId] does, but
  /// only for a family that is one account under one id: Microsoft is asked
  /// who signed in two ways, Graph for OneDrive and the id token for mail, and
  /// the two need not agree on one person's id.
  static String? expectedAccountFor(
    ProviderService service, {
    String? preferAccountId,
    String? reconnectId,
    ProviderConnection? bound,
  }) {
    final String? named;
    if (bound != null && bound.accountId.isNotEmpty) {
      named = bound.accountId;
    } else if (reconnectId != null && reconnectId.isNotEmpty) {
      named = ProviderConnections.accountIdIn(reconnectId, service);
    } else if (ProviderServices.of(service).family.sharesOneGrant) {
      named = preferAccountId;
    } else {
      named = null;
    }
    return named == null || named.isEmpty ? null : named;
  }

  /// What the browser is told about the account being signed in for, so it
  /// opens on that account rather than on whichever one it last used.
  ///
  /// Google takes the account's own id; Microsoft wants the address it signs
  /// in with. Box has no such parameter.
  static String? _loginHint(
    ProviderAccountFamily family,
    String accountId,
    ProviderConnection? known,
  ) {
    final label = known?.accountLabel ?? '';
    return switch (family) {
      ProviderAccountFamily.google => accountId,
      ProviderAccountFamily.microsoft when label.contains('@') => label,
      _ => null,
    };
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
    // Microsoft issues a token for one resource at a time, so an IMAP token
    // cannot ask Graph who it belongs to. The id token, which came back in the
    // same exchange, already says.
    if (service == ProviderService.outlookMail) {
      final claims = readIdTokenClaims(credentials.idToken);
      final email = _string(
        claims['email'],
        _string(claims['preferred_username'], _string(claims['upn'])),
      );
      if (email.isEmpty) {
        throw const ProviderFailure(
          ProviderStatus.error,
          detail: 'Microsoft did not say which account signed in.',
        );
      }
      return _Account(
        id: _string(claims['oid'], email),
        label: email,
        avatarUrl: '',
        scopes: const <String>[],
      );
    }

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
      ProviderService.googlePhotos ||
      ProviderService.googleDrive ||
      ProviderService.googleCalendar ||
      ProviderService.gmail =>
        (
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
      ProviderService.outlookMail => throw StateError('answered above'),
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
