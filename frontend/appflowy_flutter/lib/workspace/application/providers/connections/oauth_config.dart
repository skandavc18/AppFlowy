import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:flutter/foundation.dart';

/// The endpoints one service authenticates against.
@immutable
class OAuthEndpoints {
  const OAuthEndpoints({
    required this.authorization,
    required this.token,
    required this.scopes,
    this.usesPkce = true,
    this.wantsClientSecret = false,
    this.extraAuthorizationParameters = const <String, String>{},
    this.registrationUrl = '',
  });

  final String authorization;
  final String token;

  /// The narrowest set of permissions that still does the job.
  ///
  /// Read scopes only, everywhere. A write scope is asked for separately, when
  /// somebody actually turns writing on for a collection.
  final List<String> scopes;

  final bool usesPkce;

  /// Whether the token endpoint refuses the exchange without a client secret.
  ///
  /// ⚠️ Google does, even for a Desktop app client using PKCE — its console
  /// issues a secret for that client type and `oauth2.googleapis.com/token`
  /// answers `400 invalid_client` without it. Box does too. Microsoft is the
  /// only one here that is a true public client and must NOT be sent one.
  final bool wantsClientSecret;

  final Map<String, String> extraAuthorizationParameters;

  /// Where somebody registers their own application, for the settings page.
  final String registrationUrl;
}

/// The write scopes a service wants, asked for only when writing is turned on.
@immutable
class OAuthWriteScopes {
  const OAuthWriteScopes(this.scopes);

  final List<String> scopes;
}

abstract final class OAuthServices {
  static const googlePhotos = OAuthEndpoints(
    authorization: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    // The Picker scope is the only one that still reaches somebody's own
    // photos. `photoslibrary.readonly` was removed on 31 March 2025 and now
    // answers 403 for every application.
    scopes: [
      'https://www.googleapis.com/auth/photospicker.mediaitems.readonly',
      'openid',
      'email',
    ],
    extraAuthorizationParameters: {
      'access_type': 'offline',
      'prompt': 'consent',
    },
    wantsClientSecret: true,
    registrationUrl: 'https://console.cloud.google.com/apis/credentials',
  );

  static const googleDrive = OAuthEndpoints(
    authorization: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    scopes: [
      'https://www.googleapis.com/auth/drive.readonly',
      'openid',
      'email',
    ],
    extraAuthorizationParameters: {
      'access_type': 'offline',
      'prompt': 'consent',
    },
    wantsClientSecret: true,
    registrationUrl: 'https://console.cloud.google.com/apis/credentials',
  );

  static const googleDriveWrite = OAuthWriteScopes([
    'https://www.googleapis.com/auth/drive',
  ]);

  static const oneDrive = OAuthEndpoints(
    authorization:
        'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    token: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    scopes: [
      'offline_access',
      'openid',
      'email',
      'Files.Read',
      'Files.Read.All',
      'User.Read',
    ],
    registrationUrl:
        'https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade',
  );

  static const oneDriveWrite = OAuthWriteScopes(['Files.ReadWrite.All']);

  static const box = OAuthEndpoints(
    authorization: 'https://account.box.com/api/oauth2/authorize',
    token: 'https://api.box.com/oauth2/token',
    scopes: ['root_readonly'],
    wantsClientSecret: true,
    registrationUrl: 'https://app.box.com/developers/console',
  );

  static const boxWrite = OAuthWriteScopes(['root_readwrite']);

  static OAuthEndpoints? forService(ProviderService service) =>
      switch (service) {
        ProviderService.googlePhotos => googlePhotos,
        ProviderService.googleDrive => googleDrive,
        ProviderService.oneDrive => oneDrive,
        ProviderService.box => box,
        _ => null,
      };

  static OAuthWriteScopes? writeScopesFor(ProviderService service) =>
      switch (service) {
        ProviderService.googleDrive => googleDriveWrite,
        ProviderService.oneDrive => oneDriveWrite,
        ProviderService.box => boxWrite,
        _ => null,
      };
}

/// The application identity a service is asked to authenticate.
@immutable
class OAuthApp {
  const OAuthApp({
    required this.clientId,
    this.clientSecret = '',
    this.tenant = '',
  });

  final String clientId;

  /// Only ever set for a service that refuses to work without one. It is not a
  /// user password and is stored the same way any other setting is.
  final String clientSecret;

  /// Microsoft's directory, for an application that is not multi-tenant.
  final String tenant;

  bool get isConfigured => clientId.isNotEmpty;

  Map<String, Object?> toJson() => {
        'client_id': clientId,
        if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
        if (tenant.isNotEmpty) 'tenant': tenant,
      };

  static OAuthApp? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final clientId = value['client_id'];
    if (clientId is! String || clientId.isEmpty) {
      return null;
    }
    return OAuthApp(
      clientId: clientId,
      clientSecret: value['client_secret'] is String
          ? value['client_secret'] as String
          : '',
      tenant: value['tenant'] is String ? value['tenant'] as String : '',
    );
  }
}

/// Which application identity is used for each service.
///
/// AppFlowy ships no registered application for Google, Microsoft or Box: an
/// application identity belongs to whoever runs it, and shipping one would put
/// every installation's quota and consent screen in one basket. Somebody who
/// wants those services registers their own desktop application — free, and a
/// few minutes — and pastes its client id into Settings ▸ Connections.
class OAuthAppRegistry {
  OAuthAppRegistry({KeyValueStorage? storage}) : _storage = storage;

  static final OAuthAppRegistry instance = OAuthAppRegistry();

  static const storageKeyPrefix = 'appflowy_oauth_app_';

  final KeyValueStorage? _storage;
  final Map<ProviderService, OAuthApp> _cache = {};

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  Future<OAuthApp?> read(ProviderService service) async {
    final cached = _cache[service];
    if (cached != null) {
      return cached;
    }
    final raw = await _kv?.get('$storageKeyPrefix${service.name}');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final app = OAuthApp.fromJson(_decode(raw));
    if (app != null) {
      _cache[service] = app;
    }
    return app;
  }

  Future<void> write(ProviderService service, OAuthApp app) async {
    _cache[service] = app;
    await _kv?.set(
      '$storageKeyPrefix${service.name}',
      jsonEncode(app.toJson()),
    );
  }

  Future<void> clear(ProviderService service) async {
    _cache.remove(service);
    await _kv?.remove('$storageKeyPrefix${service.name}');
  }

  static Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
