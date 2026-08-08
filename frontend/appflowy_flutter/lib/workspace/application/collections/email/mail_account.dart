import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:flutter/foundation.dart';

/// How the mailbox proves who it is.
enum MailAuthKind {
  /// An ordinary password, or a provider-issued app password.
  password,

  /// An OAuth 2.0 access token, presented as IMAP's `XOAUTH2`.
  oauth;

  static MailAuthKind fromValue(Object? value) {
    for (final kind in MailAuthKind.values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return MailAuthKind.password;
  }
}

/// The mailbox a connected account reads, when that account has one.
///
/// This is the join between the two halves: a Google account signed in for
/// Drive is the same account Gmail is read with, so the connection is what
/// the mailbox names rather than a password of its own.
MailProvider? mailProviderForService(ProviderService service) =>
    switch (service) {
      ProviderService.gmail => MailProvider.gmail,
      ProviderService.outlookMail => MailProvider.outlook,
      _ => null,
    };

/// The servers people actually use, so nobody has to look up a host name.
enum MailProvider {
  gmail,
  outlook,
  icloud,
  yahoo,
  fastmail,
  proton,
  custom;

  static MailProvider fromValue(Object? value) {
    for (final provider in MailProvider.values) {
      if (provider.name == value) {
        return provider;
      }
    }
    return MailProvider.custom;
  }

  String get label => switch (this) {
        MailProvider.gmail => 'Gmail',
        MailProvider.outlook => 'Outlook',
        MailProvider.icloud => 'iCloud',
        MailProvider.yahoo => 'Yahoo',
        MailProvider.fastmail => 'Fastmail',
        MailProvider.proton => 'Proton Mail Bridge',
        MailProvider.custom => 'Other server',
      };

  String get host => switch (this) {
        MailProvider.gmail => 'imap.gmail.com',
        MailProvider.outlook => 'outlook.office365.com',
        MailProvider.icloud => 'imap.mail.me.com',
        MailProvider.yahoo => 'imap.mail.yahoo.com',
        MailProvider.fastmail => 'imap.fastmail.com',
        // The bridge runs on the machine itself and speaks plain IMAP.
        MailProvider.proton => '127.0.0.1',
        MailProvider.custom => '',
      };

  int get port => this == MailProvider.proton ? 1143 : 993;

  /// Proton's bridge listens locally without TLS; everything else is
  /// implicit TLS on 993 and must stay that way.
  bool get useSsl => this != MailProvider.proton;

  /// Whether the provider refuses an account password outright and wants a
  /// separately issued one. Saying so up front saves a failed sign-in.
  ///
  /// Only ever asked of a server AppFlowy cannot sign in to properly: Gmail
  /// and Outlook go through OAuth now, and an app password there is a worse
  /// answer than the one already available.
  bool get needsAppPassword => switch (this) {
        MailProvider.gmail => true,
        MailProvider.icloud => true,
        MailProvider.yahoo => true,
        MailProvider.outlook => false,
        MailProvider.fastmail => true,
        MailProvider.proton => false,
        MailProvider.custom => false,
      };

  /// The connection this mailbox signs in through, when it can sign in the way
  /// the rest of the application does.
  ProviderService? get oauthService => switch (this) {
        MailProvider.gmail => ProviderService.gmail,
        MailProvider.outlook => ProviderService.outlookMail,
        _ => null,
      };

  bool get signsInWithAccount => oauthService != null;

  /// Where the provider issues those passwords, for the panel to link to.
  String? get appPasswordUrl => switch (this) {
        MailProvider.gmail => 'https://myaccount.google.com/apppasswords',
        MailProvider.icloud => 'https://account.apple.com/account/manage',
        MailProvider.yahoo => 'https://login.yahoo.com/account/security',
        MailProvider.fastmail => 'https://app.fastmail.com/settings/security',
        _ => null,
      };
}

/// Everything needed to reach a mailbox, minus the secret.
///
/// The password is deliberately not a field: it lives in the secret store,
/// which keeps it out of the collection's `extra` and out of anything that
/// gets written to disk in the clear.
@immutable
class MailAccount {
  const MailAccount({
    required this.id,
    required this.provider,
    required this.host,
    required this.port,
    required this.username,
    this.mailbox = 'INBOX',
    this.useSsl = true,
    this.authKind = MailAuthKind.password,
    this.connectionId = '',
    this.rememberSecret = true,
    this.syncLimit = 200,
    this.sinceDays = 90,
    this.lastUid = 0,
    this.uidValidity = 0,
    this.lastSyncAt,
    this.lastError,
  });

  final String id;
  final MailProvider provider;
  final String host;
  final int port;
  final String username;
  final String mailbox;
  final bool useSsl;
  final MailAuthKind authKind;

  /// The connected account this mailbox signs in with, for an OAuth mailbox.
  ///
  /// Empty for a server that still takes a password of its own.
  final String connectionId;

  /// Whether the secret may be kept between sessions.
  final bool rememberSecret;

  /// How many messages one sync may bring down, so a first run against a
  /// mailbox of forty thousand does not run all afternoon.
  final int syncLimit;

  /// How far back the first sync reaches. Later syncs go by UID instead.
  final int sinceDays;

  /// The highest UID already taken, so a sync only asks for what is new.
  final int lastUid;

  /// The mailbox's UID generation. IMAP says a server may renumber, and when
  /// it does every remembered UID is meaningless.
  final int uidValidity;

  final DateTime? lastSyncAt;
  final String? lastError;

  bool get isConfigured => host.isNotEmpty && username.isNotEmpty;

  bool get hasSynced => lastSyncAt != null;

  /// Whether the token comes from a connected account rather than a password.
  bool get usesConnection =>
      authKind == MailAuthKind.oauth && connectionId.isNotEmpty;

  MailAccount copyWith({
    MailProvider? provider,
    String? host,
    int? port,
    String? username,
    String? mailbox,
    bool? useSsl,
    MailAuthKind? authKind,
    String? connectionId,
    bool? rememberSecret,
    int? syncLimit,
    int? sinceDays,
    int? lastUid,
    int? uidValidity,
    DateTime? lastSyncAt,
    String? lastError,
    bool clearError = false,
  }) =>
      MailAccount(
        id: id,
        provider: provider ?? this.provider,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        mailbox: mailbox ?? this.mailbox,
        useSsl: useSsl ?? this.useSsl,
        authKind: authKind ?? this.authKind,
        connectionId: connectionId ?? this.connectionId,
        rememberSecret: rememberSecret ?? this.rememberSecret,
        syncLimit: syncLimit ?? this.syncLimit,
        sinceDays: sinceDays ?? this.sinceDays,
        lastUid: lastUid ?? this.lastUid,
        uidValidity: uidValidity ?? this.uidValidity,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastError: clearError ? null : lastError ?? this.lastError,
      );

  /// The settings a provider brings with it, keeping whatever the reader has
  /// already typed.
  MailAccount withProvider(MailProvider provider) => copyWith(
        provider: provider,
        host: provider == MailProvider.custom ? host : provider.host,
        port: provider.port,
        useSsl: provider.useSsl,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'provider': provider.name,
        'host': host,
        'port': port,
        'username': username,
        'mailbox': mailbox,
        if (!useSsl) 'ssl': false,
        if (authKind != MailAuthKind.password) 'auth': authKind.name,
        if (connectionId.isNotEmpty) 'connection': connectionId,
        if (!rememberSecret) 'remember': false,
        'limit': syncLimit,
        'since_days': sinceDays,
        if (lastUid > 0) 'last_uid': lastUid,
        if (uidValidity > 0) 'uid_validity': uidValidity,
        if (lastSyncAt != null) 'last_sync': lastSyncAt!.millisecondsSinceEpoch,
        if (lastError != null) 'last_error': lastError,
      };

  static MailAccount? fromJson(Map<String, dynamic> values) {
    final id = values['id'];
    final host = values['host'];
    final username = values['username'];
    if (id is! String || id.isEmpty || host is! String || username is! String) {
      return null;
    }
    return MailAccount(
      id: id,
      provider: MailProvider.fromValue(values['provider']),
      host: host,
      port: values['port'] is int ? values['port'] as int : 993,
      username: username,
      mailbox: values['mailbox'] is String &&
              (values['mailbox'] as String).isNotEmpty
          ? values['mailbox'] as String
          : 'INBOX',
      useSsl: values['ssl'] != false,
      authKind: MailAuthKind.fromValue(values['auth']),
      connectionId:
          values['connection'] is String ? values['connection'] as String : '',
      rememberSecret: values['remember'] != false,
      syncLimit: values['limit'] is int ? values['limit'] as int : 200,
      sinceDays: values['since_days'] is int ? values['since_days'] as int : 90,
      lastUid: values['last_uid'] is int ? values['last_uid'] as int : 0,
      uidValidity:
          values['uid_validity'] is int ? values['uid_validity'] as int : 0,
      lastSyncAt: values['last_sync'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              values['last_sync'] as int,
              isUtc: true,
            )
          : null,
      lastError: values['last_error'] is String &&
              (values['last_error'] as String).isNotEmpty
          ? values['last_error'] as String
          : null,
    );
  }

  /// A fresh account for [provider], identified by when it was made so the
  /// secret store has a stable key to hang the password off.
  static MailAccount forProvider(MailProvider provider, {String? id}) =>
      MailAccount(
        id: id ?? 'mail-${DateTime.now().microsecondsSinceEpoch}',
        provider: provider,
        host: provider.host,
        port: provider.port,
        username: '',
        useSsl: provider.useSsl,
      );

  /// A mailbox read with an already connected account.
  ///
  /// The id is derived from the connection, so re-binding the same account to
  /// the same collection replaces the mailbox rather than stacking a second
  /// one up, and there is no password anywhere in it.
  static MailAccount forConnection({
    required String connectionId,
    required MailProvider provider,
    required String username,
    String mailbox = 'INBOX',
  }) =>
      MailAccount(
        id: 'mail-$connectionId',
        provider: provider,
        host: provider.host,
        port: provider.port,
        username: username,
        mailbox: mailbox,
        useSsl: provider.useSsl,
        authKind: MailAuthKind.oauth,
        connectionId: connectionId,
      );
}
