import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// One account, connected once and reused everywhere.
///
/// Nothing secret lives here: this is the part that is safe to write down.
/// The token itself is held by [ProviderSecretStore] under [id].
@immutable
class ProviderConnection {
  const ProviderConnection({
    required this.id,
    required this.service,
    required this.accountLabel,
    this.accountId = '',
    this.host = '',
    this.scopes = const <String>[],
    this.services = const <ProviderService>{},
    this.connectedAt,
    this.expiresAt,
    this.avatarUrl = '',
  });

  final String id;

  /// The capability this account was first signed in for. Kept because it is
  /// what the stored id and the token endpoints are derived from.
  final ProviderService service;

  /// Everything this one sign in covers.
  ///
  /// A Google account signed in once carries Drive, Photos, Calendar and mail
  /// together, so they are one account rather than four.
  final Set<ProviderService> services;

  /// What to show in the connections list: an email address, a login, a host.
  final String accountLabel;

  /// The service's own id for the account, when it gives one.
  final String accountId;

  /// The server, for a self-hosted service.
  final String host;

  final List<String> scopes;
  final DateTime? connectedAt;

  /// When the access token stops working. Refreshing is what keeps a
  /// connection alive; this is only used to decide when to bother.
  final DateTime? expiresAt;

  final String avatarUrl;

  ProviderServiceInfo get info => ProviderServices.of(service);

  ProviderAccountFamily get family => info.family;

  /// Everything this account can be used for, the first one included.
  Set<ProviderService> get covered => {service, ...services};

  bool covers(ProviderService service) => covered.contains(service);

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!.subtract(_slack));

  static const _slack = Duration(minutes: 2);

  ProviderConnection copyWith({
    String? accountLabel,
    String? accountId,
    String? host,
    List<String>? scopes,
    Set<ProviderService>? services,
    DateTime? expiresAt,
    String? avatarUrl,
  }) =>
      ProviderConnection(
        id: id,
        service: service,
        accountLabel: accountLabel ?? this.accountLabel,
        accountId: accountId ?? this.accountId,
        host: host ?? this.host,
        scopes: scopes ?? this.scopes,
        services: services ?? this.services,
        connectedAt: connectedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'service': service.name,
        'label': accountLabel,
        if (accountId.isNotEmpty) 'account_id': accountId,
        if (host.isNotEmpty) 'host': host,
        if (scopes.isNotEmpty) 'scopes': scopes,
        if (covered.length > 1) 'services': [for (final s in covered) s.name],
        if (connectedAt != null)
          'connected_at': connectedAt!.millisecondsSinceEpoch,
        if (expiresAt != null) 'expires_at': expiresAt!.millisecondsSinceEpoch,
        if (avatarUrl.isNotEmpty) 'avatar': avatarUrl,
      };

  static ProviderConnection? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final values = Map<String, dynamic>.from(value);
    final id = values['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final service = ProviderService.fromValue(values['service']);
    if (service.isLocal) {
      return null;
    }
    return ProviderConnection(
      id: id,
      service: service,
      accountLabel: values['label'] is String ? values['label'] as String : '',
      accountId:
          values['account_id'] is String ? values['account_id'] as String : '',
      host: values['host'] is String ? values['host'] as String : '',
      scopes: values['scopes'] is List
          ? List<String>.from((values['scopes'] as List).whereType<String>())
          : const <String>[],
      services: _services(values['services']),
      connectedAt: _date(values['connected_at']),
      expiresAt: _date(values['expires_at']),
      avatarUrl: values['avatar'] is String ? values['avatar'] as String : '',
    );
  }

  static DateTime? _date(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  static Set<ProviderService> _services(Object? value) {
    if (value is! List) {
      return const <ProviderService>{};
    }
    final services = <ProviderService>{};
    for (final name in value.whereType<String>()) {
      final service = ProviderService.fromValue(name);
      if (!service.isLocal) {
        services.add(service);
      }
    }
    return services;
  }
}

/// The secret half of a connection, kept apart on purpose.
@immutable
class ProviderCredentials {
  const ProviderCredentials({
    required this.accessToken,
    this.refreshToken = '',
    this.tokenType = 'Bearer',
    this.expiresAt,
    this.idToken = '',
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final DateTime? expiresAt;

  /// The OIDC id token, when the service returned one.
  ///
  /// Deliberately not stored: it is read once, straight after the exchange, to
  /// find out whose account this is. It says nothing a later request could not
  /// ask for, and keeping it would be keeping a second credential for nothing.
  final String idToken;

  bool get canRefresh => refreshToken.isNotEmpty;

  bool get isExpired =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes: 2)));

  /// The header a request carries. Immich wants its own header name, which is
  /// why the type is part of the credential rather than assumed.
  Map<String, String> get authorizationHeaders => tokenType == 'x-api-key'
      ? {'x-api-key': accessToken}
      : {'Authorization': '$tokenType $accessToken'};

  String encode() => jsonEncode({
        'access': accessToken,
        if (refreshToken.isNotEmpty) 'refresh': refreshToken,
        'type': tokenType,
        if (expiresAt != null) 'expires': expiresAt!.millisecondsSinceEpoch,
      });

  static ProviderCredentials? decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final values = jsonDecode(raw);
      if (values is! Map) {
        return null;
      }
      final access = values['access'];
      if (access is! String || access.isEmpty) {
        return null;
      }
      final expires = values['expires'];
      return ProviderCredentials(
        accessToken: access,
        refreshToken:
            values['refresh'] is String ? values['refresh'] as String : '',
        tokenType:
            values['type'] is String ? values['type'] as String : 'Bearer',
        expiresAt: expires is int
            ? DateTime.fromMillisecondsSinceEpoch(expires)
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Every connected account, in one place, so a person signs in once.
///
/// This is deliberately a singleton with a [ValueNotifier]: an embed picker, a
/// collection header and the settings page all have to agree the moment a
/// connection is added or dropped.
class ProviderConnections extends ChangeNotifier {
  ProviderConnections({
    KeyValueStorage? storage,
    ProviderSecretStore? secrets,
  })  : _storage = storage,
        secrets = secrets ?? ProviderSecretStore(storage: storage);

  static final ProviderConnections instance = ProviderConnections();

  static const storageKey = 'appflowy_provider_connections';

  final KeyValueStorage? _storage;
  final ProviderSecretStore secrets;

  final List<ProviderConnection> _connections = <ProviderConnection>[];
  bool _loaded = false;
  Future<void>? _loading;

  List<ProviderConnection> get all =>
      List<ProviderConnection>.unmodifiable(_connections);

  bool get isLoaded => _loaded;

  /// Whether a connection survives a restart on this machine.
  bool get canPersistSecrets => secrets.canPersist;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future<void>.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _kv?.get(storageKey);
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      if (decoded is List) {
        final stored = decoded
            .map(ProviderConnection.fromJson)
            .whereType<ProviderConnection>();
        // Keep anything already in hand: a connection made while this read was
        // in flight must not be thrown away by it.
        for (final connection in stored) {
          final index = _connections.indexWhere((c) => c.id == connection.id);
          if (index < 0) {
            _connections.add(connection);
          } else {
            _connections[index] = connection;
          }
        }
      }
    } catch (error) {
      Log.warn('Unable to read the connected services: $error');
    } finally {
      _loaded = true;
      _loading = null;
      notifyListeners();
    }
  }

  List<ProviderConnection> forService(ProviderService service) =>
      _connections.where((c) => c.covers(service)).toList(growable: false);

  /// The account already signed in for this family, if there is one.
  ///
  /// Used to join a new permission to an existing sign in rather than stacking
  /// a second account beside it — and to keep that account's ID, because every
  /// collection and page embed already names it.
  ProviderConnection? accountFor(
    ProviderAccountFamily family, {
    String accountId = '',
    String host = '',
  }) {
    for (final connection in _connections) {
      if (connection.family != family || connection.host != host) {
        continue;
      }
      if (accountId.isEmpty || connection.accountId == accountId) {
        return connection;
      }
    }
    return null;
  }

  ProviderConnection? byId(String id) {
    for (final connection in _connections) {
      if (connection.id == id) {
        return connection;
      }
    }
    return null;
  }

  bool isConnected(ProviderService service) =>
      _connections.any((c) => c.service == service);

  /// Adds or replaces a connection and seals its credentials.
  ///
  /// ⚠️ The list is read lazily, so it MUST be loaded before it is changed:
  /// adding to a list that has not been read yet and writing it back destroys
  /// every connection already stored. That is what made an account signed in
  /// once come back needing a sign in.
  Future<void> upsert(
    ProviderConnection connection,
    ProviderCredentials credentials,
  ) async {
    await ensureLoaded();
    await secrets.write(connection.id, credentials.encode());
    final index = _connections.indexWhere((c) => c.id == connection.id);
    if (index < 0) {
      _connections.add(connection);
    } else {
      _connections[index] = connection;
    }
    await _write();
    notifyListeners();
  }

  /// Replaces the stored token after a refresh, leaving the account alone.
  Future<void> updateCredentials(
    String connectionId,
    ProviderCredentials credentials,
  ) async {
    await ensureLoaded();
    await secrets.write(connectionId, credentials.encode());
    final index = _connections.indexWhere((c) => c.id == connectionId);
    if (index >= 0) {
      _connections[index] =
          _connections[index].copyWith(expiresAt: credentials.expiresAt);
      await _write();
      notifyListeners();
    }
  }

  Future<ProviderCredentials?> credentialsFor(String connectionId) async =>
      ProviderCredentials.decode(await secrets.read(connectionId));

  /// Whether the token for [connectionId] is still on this machine. It will not
  /// be after a restart on a platform that cannot seal it.
  Future<bool> hasCredentials(String connectionId) => secrets.has(connectionId);

  Future<void> remove(String connectionId) async {
    await ensureLoaded();
    await secrets.forget(connectionId);
    _connections.removeWhere((c) => c.id == connectionId);
    await _write();
    notifyListeners();
  }

  Future<void> _write() async {
    try {
      await _kv?.set(
        storageKey,
        jsonEncode([for (final c in _connections) c.toJson()]),
      );
    } catch (error) {
      Log.warn('Unable to save the connected services: $error');
    }
  }

  /// A stable id for a connection, so reconnecting the same account replaces
  /// it rather than stacking a second one up.
  ///
  /// Keyed on the account FAMILY, because one sign in covers everything that
  /// account can do. An id stored before that was true is reused as it is —
  /// see [accountFor] — since collections and page embeds already name it.
  static String idFor(
    ProviderService service, {
    String host = '',
    String account = '',
  }) {
    final parts = [
      ProviderServices.of(service).family.name,
      if (host.isNotEmpty) Uri.tryParse(host)?.host ?? host,
      if (account.isNotEmpty) account,
    ];
    return parts.join('|').toLowerCase();
  }
}

/// One person's account with one service family, and all it is signed in for.
///
/// A connection is per capability — signing in for Drive and for Photos makes
/// two of them — but they are one Google account, and the settings page has to
/// say so or somebody is left counting the same account four times.
@immutable
class ProviderAccountGroup {
  const ProviderAccountGroup({
    required this.family,
    required this.label,
    required this.host,
    required this.connections,
  });

  final ProviderAccountFamily family;
  final String label;
  final String host;
  final List<ProviderConnection> connections;

  ProviderConnection get primary => connections.first;

  Set<ProviderService> get services => {
        for (final connection in connections) ...connection.covered,
      };

  /// The services this family offers that this account is not signed in for.
  List<ProviderServiceInfo> get missing => [
        for (final info in ProviderServices.forFamily(family))
          if (!services.contains(info.service)) info,
      ];

  /// The earliest sign in, so the row reads "connected since" rather than
  /// changing every time another capability is added.
  DateTime? get connectedAt {
    DateTime? earliest;
    for (final connection in connections) {
      final at = connection.connectedAt;
      if (at != null && (earliest == null || at.isBefore(earliest))) {
        earliest = at;
      }
    }
    return earliest;
  }
}

/// Gathers connections into the accounts they actually belong to.
///
/// Two connections are the same account when they are the same family, the
/// same server and the same person — which is the service's own id when it
/// gives one, and the label it answered with when it does not.
List<ProviderAccountGroup> groupProviderAccounts(
  List<ProviderConnection> connections,
) {
  final order = <String>[];
  final groups = <String, List<ProviderConnection>>{};

  for (final connection in connections) {
    final info = connection.info;
    final identity = connection.accountId.isNotEmpty
        ? connection.accountId
        : connection.accountLabel;
    final key =
        '${info.family.name}|${connection.host}|$identity'.toLowerCase();
    if (!groups.containsKey(key)) {
      order.add(key);
      groups[key] = <ProviderConnection>[];
    }
    groups[key]!.add(connection);
  }

  return [
    for (final key in order)
      ProviderAccountGroup(
        family: groups[key]!.first.info.family,
        label: groups[key]!.first.accountLabel,
        host: groups[key]!.first.host,
        connections: groups[key]!,
      ),
  ];
}
