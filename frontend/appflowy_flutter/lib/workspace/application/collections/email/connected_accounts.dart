import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/email/mail_account.dart';
import 'package:flutter/foundation.dart';

/// One connected account, as the settings panel sees it.
///
/// The mailbox itself keeps the whole account in its own collection; this is
/// only what a list needs to name it, so a reader can find the account they
/// mean without opening every collection first.
@immutable
class ConnectedAccount {
  const ConnectedAccount({
    required this.id,
    required this.provider,
    required this.host,
    required this.username,
    required this.mailbox,
    this.collectionId = '',
    this.collectionName = '',
    this.lastSyncAt,
  });

  final String id;
  final MailProvider provider;
  final String host;
  final String username;
  final String mailbox;

  /// Where the mailbox that owns this account lives.
  final String collectionId;
  final String collectionName;

  final DateTime? lastSyncAt;

  ConnectedAccount copyWith({String? collectionName}) => ConnectedAccount(
        id: id,
        provider: provider,
        host: host,
        username: username,
        mailbox: mailbox,
        collectionId: collectionId,
        collectionName: collectionName ?? this.collectionName,
        lastSyncAt: lastSyncAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'provider': provider.name,
        'host': host,
        'username': username,
        'mailbox': mailbox,
        if (collectionId.isNotEmpty) 'collection': collectionId,
        if (collectionName.isNotEmpty) 'collection_name': collectionName,
        if (lastSyncAt != null) 'last_sync': lastSyncAt!.millisecondsSinceEpoch,
      };

  static ConnectedAccount? fromJson(Map<String, dynamic> values) {
    final id = values['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return ConnectedAccount(
      id: id,
      provider: MailProvider.fromValue(values['provider']),
      host: values['host'] is String ? values['host'] as String : '',
      username:
          values['username'] is String ? values['username'] as String : '',
      mailbox: values['mailbox'] is String ? values['mailbox'] as String : '',
      collectionId:
          values['collection'] is String ? values['collection'] as String : '',
      collectionName: values['collection_name'] is String
          ? values['collection_name'] as String
          : '',
      lastSyncAt: values['last_sync'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              values['last_sync'] as int,
              isUtc: true,
            )
          : null,
    );
  }

  static ConnectedAccount fromAccount(
    MailAccount account, {
    String collectionId = '',
    String collectionName = '',
  }) =>
      ConnectedAccount(
        id: account.id,
        provider: account.provider,
        host: account.host,
        username: account.username,
        mailbox: account.mailbox,
        collectionId: collectionId,
        collectionName: collectionName,
        lastSyncAt: account.lastSyncAt,
      );
}

/// The list of accounts the application is joined to.
///
/// Kept beside the mailboxes rather than inside them so one settings panel can
/// show them all. It holds no secret — only the secret store does.
class ConnectedAccountRegistry {
  const ConnectedAccountRegistry({KeyValueStorage? storage})
      : _storage = storage;

  static const storageKey = 'appflowy_connected_mail_accounts';

  final KeyValueStorage? _storage;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  Future<List<ConnectedAccount>> all() async {
    final raw = await _kv?.get(storageKey);
    if (raw == null || raw.isEmpty) {
      return const <ConnectedAccount>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <ConnectedAccount>[];
      }
      final accounts = <ConnectedAccount>[];
      for (final entry in decoded) {
        if (entry is Map) {
          final account =
              ConnectedAccount.fromJson(Map<String, dynamic>.from(entry));
          if (account != null) {
            accounts.add(account);
          }
        }
      }
      return accounts;
    } catch (_) {
      return const <ConnectedAccount>[];
    }
  }

  Future<void> upsert(ConnectedAccount account) async {
    final accounts = await all();
    final next = <ConnectedAccount>[
      for (final existing in accounts)
        if (existing.id != account.id) existing,
      account,
    ];
    await _write(next);
  }

  Future<void> remove(String id) async {
    final accounts = await all();
    await _write(accounts.where((account) => account.id != id).toList());
  }

  Future<void> _write(List<ConnectedAccount> accounts) async {
    final storage = _kv;
    if (storage == null) {
      return;
    }
    await storage.set(
      storageKey,
      jsonEncode(accounts.map((account) => account.toJson()).toList()),
    );
  }
}
