// The AppFlowy password that seals a sync folder.
//
// Everything sync writes into the folder — the workspace, attached files,
// settings, accounts, passwords and keys, even which computers take part — is
// sealed with a key only somebody who knows the password can derive. The
// service holding the folder sees file names made of random ids, sizes and
// times, nothing more.
//
// Each epoch has one clear file, its vault: the salt and the cost of turning
// the password into the key, and a verifier proving a password right. The
// password itself is never written into the folder; each computer keeps the
// derived key in its own keyring once the password has been typed there.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/workspace/application/backup/backup_crypto.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Raised when something sealed cannot be opened: the wrong key, or bytes
/// somebody changed.
class SyncSealError implements Exception {
  const SyncSealError(this.detail);

  final String detail;

  @override
  String toString() => 'SyncSealError: $detail';
}

/// The clear record that lets a passphrase become a folder's key.
@immutable
class SyncVault {
  const SyncVault({
    required this.id,
    required this.salt,
    required this.iterations,
    required this.verifier,
    required this.createdAt,
    this.device = '',
  });

  /// Reads a vault, or returns null for anything else — including one written
  /// by a newer version.
  static SyncVault? tryParse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map || decoded['format'] != syncFormat) {
        return null;
      }
      final id = decoded['id'];
      final salt = decoded['salt'];
      final iterations = decoded['iterations'];
      final verifier = decoded['verifier'];
      if (id is! String ||
          id.isEmpty ||
          salt is! String ||
          salt.isEmpty ||
          iterations is! int ||
          iterations < 1 ||
          verifier is! String ||
          verifier.isEmpty) {
        return null;
      }
      final created = decoded['created_at'];
      return SyncVault(
        id: id,
        salt: salt,
        iterations: iterations,
        verifier: verifier,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          created is int ? created : 0,
          isUtc: true,
        ),
        device: decoded['device'] is String ? decoded['device'] as String : '',
      );
    } on Object {
      return null;
    }
  }

  /// Stands for one passphrase and salt; a folder sealed again gets a new one.
  final String id;

  /// Base64.
  final String salt;
  final int iterations;
  final String verifier;
  final DateTime createdAt;
  final String device;

  String encode() => const JsonEncoder.withIndent('  ').convert({
        'format': syncFormat,
        'id': id,
        'salt': salt,
        'iterations': iterations,
        'verifier': verifier,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        if (device.isNotEmpty) 'device': device,
      });

  /// A new vault for [passphrase], and its key.
  ///
  /// The derivation is slow on purpose, so it runs on another thread.
  static Future<(SyncVault, SyncKey)> create({
    required String passphrase,
    required DateTime now,
    String device = '',
    int iterations = defaultKeyIterations,
  }) async {
    final id = randomSyncToken(16);
    final salt = newEncryptionSalt();
    final key = SyncKey(
      vaultId: id,
      bytes: await _derive(passphrase, salt, iterations),
    );
    final vault = SyncVault(
      id: id,
      salt: base64Encode(salt),
      iterations: iterations,
      verifier: key.sealText(_verifierPhrase(id), context: 'vault'),
      createdAt: now,
      device: device,
    );
    return (vault, key);
  }

  /// The key [passphrase] gives, or null when it is the wrong passphrase.
  Future<SyncKey?> unlock(String passphrase) async {
    final Uint8List saltBytes;
    try {
      saltBytes = Uint8List.fromList(base64Decode(salt));
    } on FormatException {
      return null;
    }
    final key = SyncKey(
      vaultId: id,
      bytes: await _derive(passphrase, saltBytes, iterations),
    );
    return accepts(key) ? key : null;
  }

  /// Whether [key] is this vault's key.
  bool accepts(SyncKey key) {
    if (key.vaultId != id) {
      return false;
    }
    try {
      return key.openText(verifier, context: 'vault') == _verifierPhrase(id);
    } on SyncSealError {
      return false;
    }
  }

  static String _verifierPhrase(String id) => 'appflowy-sync-vault:$id';

  static Future<Uint8List> _derive(
    String passphrase,
    Uint8List salt,
    int iterations,
  ) =>
      Isolate.run(
        () => deriveKeyFromPassphrase(
          passphrase: passphrase,
          salt: salt,
          iterations: iterations,
        ),
      );
}

/// A folder's unlocked key.
///
/// Each use gets a key of its own, derived from this one, so what seals a
/// workspace can never be mistaken for what names a file.
class SyncKey {
  SyncKey({required this.vaultId, required Uint8List bytes})
      : _bytes = Uint8List.fromList(bytes),
        _textKey = _subkey(bytes, 'afsync:text'),
        _fileKey = _subkey(bytes, 'afsync:file'),
        _nameKey = _subkey(bytes, 'afsync:blob-name');

  /// Reads a key kept with [encode].
  static SyncKey? decode(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return null;
      }
      final vault = decoded['vault'];
      final key = decoded['key'];
      if (vault is! String || vault.isEmpty || key is! String) {
        return null;
      }
      final bytes = base64Decode(key);
      return bytes.length == encryptionKeyLength
          ? SyncKey(vaultId: vault, bytes: Uint8List.fromList(bytes))
          : null;
    } on Object {
      return null;
    }
  }

  final String vaultId;
  final Uint8List _bytes;
  final Uint8List _textKey;
  final Uint8List _fileKey;
  final Uint8List _nameKey;

  /// The key as a computer keeps it in its keyring. A secret.
  String encode() =>
      jsonEncode({'vault': vaultId, 'key': base64Encode(_bytes)});

  /// Seals [plaintext], bound to [context]: it opens only with the same one.
  String sealText(String plaintext, {required String context}) => sealBytes(
        key: _textKey,
        plaintext: Uint8List.fromList(utf8.encode(plaintext)),
        context: 'afsync:$context',
      );

  /// Opens what [sealText] sealed with the same [context].
  String openText(String sealed, {required String context}) {
    try {
      return utf8.decode(
        openBytes(
          key: _textKey,
          value: sealed.trim(),
          context: 'afsync:$context',
        ),
      );
    } on Object {
      throw const SyncSealError('Something in the sync folder did not open.');
    }
  }

  /// Seals [source] into [destination], on another thread.
  Future<void> sealFile(File source, File destination) => sealBackupFile(
        source: source,
        destination: destination,
        key: _fileKey,
      );

  /// Opens what [sealFile] sealed, on another thread.
  Future<void> openFile(File source, File destination) async {
    try {
      await openBackupFile(
        source: source,
        destination: destination,
        key: _fileKey,
      );
    } on BackupCipherError {
      throw const SyncSealError('A file in the sync folder did not open.');
    }
  }

  /// The name an attached file with [hash] has in the folder: its own hash
  /// would tell anybody who has the same file that it is there.
  String blobName(String hash) =>
      Hmac(sha256, _nameKey).convert(utf8.encode(hash)).toString();

  static Uint8List _subkey(Uint8List key, String label) => Uint8List.fromList(
        Hmac(sha256, key).convert(utf8.encode(label)).bytes,
      );
}

/// Whether [file] is sealed the way [SyncKey.sealFile] seals: every sealed
/// sync file starts like a sealed backup.
Future<bool> isSealedSyncFile(File file) => looksLikeSealedBackup(file);

/// Where a computer keeps the keys of the folders it has unlocked.
abstract class SyncKeyKeeper {
  Future<SyncKey?> read(String vaultId);

  Future<void> write(SyncKey key);

  Future<void> forget(String vaultId);
}

/// Keeps keys with the other secrets: in the keyring on Linux, sealed by
/// Windows on Windows, for the session elsewhere.
class SecretStoreKeyKeeper implements SyncKeyKeeper {
  SecretStoreKeyKeeper([ProviderSecretStore? store])
      : _store = store ?? ProviderSecretStore();

  /// Never synced: it is what everything synced is sealed with.
  static const String idPrefix = 'appflowy-sync-key-';

  final ProviderSecretStore _store;

  @override
  Future<SyncKey?> read(String vaultId) async {
    final kept = await _store.read('$idPrefix$vaultId');
    final key = kept == null || kept.isEmpty ? null : SyncKey.decode(kept);
    return key?.vaultId == vaultId ? key : null;
  }

  @override
  Future<void> write(SyncKey key) =>
      _store.write('$idPrefix${key.vaultId}', key.encode());

  @override
  Future<void> forget(String vaultId) => _store.forget('$idPrefix$vaultId');
}

/// Keeps keys in memory, for tests.
class MemoryKeyKeeper implements SyncKeyKeeper {
  final Map<String, SyncKey> keys = {};

  @override
  Future<SyncKey?> read(String vaultId) async => keys[vaultId];

  @override
  Future<void> write(SyncKey key) async => keys[key.vaultId] = key;

  @override
  Future<void> forget(String vaultId) async => keys.remove(vaultId);
}
