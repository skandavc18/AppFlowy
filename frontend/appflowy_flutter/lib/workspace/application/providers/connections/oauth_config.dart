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

  static const googleCalendar = OAuthEndpoints(
    authorization: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    // Read only until somebody actually asks to write, exactly like Drive.
    scopes: [
      'https://www.googleapis.com/auth/calendar.readonly',
      'https://www.googleapis.com/auth/calendar.events.readonly',
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

  static const googleCalendarWrite = OAuthWriteScopes([
    'https://www.googleapis.com/auth/calendar.events',
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

  /// Gmail over IMAP.
  ///
  /// `https://mail.google.com/` is the only scope Google accepts for IMAP —
  /// the narrower `gmail.readonly` scope works for the REST API and is refused
  /// by the IMAP server. The Gmail API must be enabled in the Cloud project.
  static const gmail = OAuthEndpoints(
    authorization: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    scopes: ['https://mail.google.com/', 'openid', 'email'],
    extraAuthorizationParameters: {
      'access_type': 'offline',
      'prompt': 'consent',
    },
    wantsClientSecret: true,
    registrationUrl: 'https://console.cloud.google.com/apis/credentials',
  );

  /// Outlook and Microsoft 365 over IMAP.
  ///
  /// ⚠️ Microsoft's v2 endpoint will only issue a token for ONE resource at a
  /// time, so this must not ask for a Graph scope beside the Outlook one —
  /// mixing them is refused outright. That is also why the account is named
  /// from the id token rather than from `graph.microsoft.com/v1.0/me`.
  static const outlookMail = OAuthEndpoints(
    authorization:
        'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    token: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    scopes: [
      'offline_access',
      'openid',
      'email',
      'https://outlook.office.com/IMAP.AccessAsUser.All',
    ],
    registrationUrl:
        'https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade',
  );

  static OAuthEndpoints? forService(ProviderService service) =>
      switch (service) {
        ProviderService.googlePhotos => googlePhotos,
        ProviderService.googleDrive => googleDrive,
        ProviderService.googleCalendar => googleCalendar,
        ProviderService.oneDrive => oneDrive,
        ProviderService.box => box,
        ProviderService.gmail => gmail,
        ProviderService.outlookMail => outlookMail,
        _ => null,
      };

  static OAuthWriteScopes? writeScopesFor(ProviderService service) =>
      switch (service) {
        ProviderService.googleDrive => googleDriveWrite,
        ProviderService.googleCalendar => googleCalendarWrite,
        ProviderService.oneDrive => oneDriveWrite,
        ProviderService.box => boxWrite,
        _ => null,
      };

  /// Whether [scopes] carry the permission a write needs.
  ///
  /// A service that signs in with a personal token has no scopes of its own
  /// here — what the token may do was decided when it was made — so it is
  /// taken at its word.
  static bool grantsWrite(ProviderService service, List<String> scopes) {
    final write = writeScopesFor(service);
    if (write == null) {
      return true;
    }
    return write.scopes.every(scopes.contains);
  }

  /// Everything one account can be asked for in a single sign in.
  ///
  /// This is what makes "sign in to Google once" true rather than four browser
  /// round trips: the read scopes of every capability that account offers, in
  /// one request. A family whose token endpoint will not carry them together
  /// answers with just [service]'s own scopes.
  static List<String> scopesForAccount(ProviderService service) {
    final endpoints = forService(service);
    if (endpoints == null) {
      return const <String>[];
    }
    final family = ProviderServices.of(service).family;
    if (!family.sharesOneGrant) {
      return endpoints.scopes;
    }
    final scopes = <String>{...endpoints.scopes};
    for (final info in ProviderServices.forFamily(family)) {
      scopes.addAll(forService(info.service)?.scopes ?? const <String>[]);
    }
    return scopes.toList(growable: false);
  }

  /// The capabilities [scopes] actually reach.
  ///
  /// Read from what the service granted rather than from what was asked for:
  /// a consent screen is a place where somebody can untick things.
  static Set<ProviderService> servicesGrantedBy(
    ProviderService service,
    List<String> scopes,
  ) {
    final family = ProviderServices.of(service).family;
    if (!family.sharesOneGrant) {
      return {service};
    }
    return {
      service,
      for (final info in ProviderServices.forFamily(family))
        if ((forService(info.service)?.scopes ?? const <String>[])
            .where((scope) => !_ambient.contains(scope))
            .every(scopes.contains))
          info.service,
    };
  }

  /// Scopes every service in a family asks for, so they say nothing about
  /// which capability was granted.
  static const _ambient = {'openid', 'email', 'profile', 'offline_access'};
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
///
/// ⚠️ It is stored per ACCOUNT FAMILY, not per service: one Google Cloud
/// client covers Drive, Photos, Calendar and Gmail, and asking for the same
/// client id four times would be asking the same question four times.
class OAuthAppRegistry {
  OAuthAppRegistry({KeyValueStorage? storage}) : _storage = storage;

  static final OAuthAppRegistry instance = OAuthAppRegistry();

  static const storageKeyPrefix = 'appflowy_oauth_app_';

  final KeyValueStorage? _storage;
  final Map<ProviderAccountFamily, OAuthApp> _cache = {};

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  static String keyFor(ProviderAccountFamily family) =>
      '$storageKeyPrefix${family.name}';

  Future<OAuthApp?> read(ProviderService service) =>
      readFamily(ProviderServices.of(service).family);

  Future<OAuthApp?> readFamily(ProviderAccountFamily family) async {
    final cached = _cache[family];
    if (cached != null) {
      return cached;
    }

    final raw = await _kv?.get(keyFor(family));
    final app = raw == null || raw.isEmpty
        ? await _adoptPerServiceApp(family)
        : OAuthApp.fromJson(_decode(raw));
    if (app != null) {
      _cache[family] = app;
    }
    return app;
  }

  /// Takes over a client id stored before identities were shared.
  ///
  /// Whichever of the family's services was configured first is adopted for
  /// the whole family, so nobody has to paste their client id again.
  Future<OAuthApp?> _adoptPerServiceApp(ProviderAccountFamily family) async {
    for (final info in ProviderServices.forFamily(family)) {
      final raw = await _kv?.get('$storageKeyPrefix${info.service.name}');
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final app = OAuthApp.fromJson(_decode(raw));
      if (app != null) {
        await _kv?.set(keyFor(family), jsonEncode(app.toJson()));
        return app;
      }
    }
    return null;
  }

  Future<void> write(ProviderService service, OAuthApp app) =>
      writeFamily(ProviderServices.of(service).family, app);

  Future<void> writeFamily(ProviderAccountFamily family, OAuthApp app) async {
    _cache[family] = app;
    await _kv?.set(keyFor(family), jsonEncode(app.toJson()));
  }

  Future<void> clear(ProviderService service) =>
      clearFamily(ProviderServices.of(service).family);

  Future<void> clearFamily(ProviderAccountFamily family) async {
    _cache.remove(family);
    await _kv?.remove(keyFor(family));
    for (final info in ProviderServices.forFamily(family)) {
      await _kv?.remove('$storageKeyPrefix${info.service.name}');
    }
  }

  static Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
