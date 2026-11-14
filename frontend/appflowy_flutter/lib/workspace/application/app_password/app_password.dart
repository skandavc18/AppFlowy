// The AppFlowy password.
//
// One password for everything AppFlowy seals: the sync folder, the copies a
// backup takes, the settings kept with a self-hosted server and, unless it was
// given one of its own, the workspace key that protects pages.
//
// Each computer keeps the password in its keyring, so what seals in the
// background never has to ask, and beside it a check value the password is
// proved against, so one typed later can be told right or wrong. Neither ever
// travels: another computer learns the password by having it typed there,
// usually when it first opens the sync folder sealed with it.

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// What the password is checked against on this computer.
@immutable
class AppPasswordRecord {
  const AppPasswordRecord({
    required this.salt,
    required this.iterations,
    required this.verifier,
    required this.changedAt,
  });

  static AppPasswordRecord? tryParse(String? text) {
    if (text == null || text.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return null;
      }
      final salt = decoded['salt'];
      final iterations = decoded['iterations'];
      final verifier = decoded['verifier'];
      final changed = decoded['changed_at'];
      if (salt is! String ||
          salt.isEmpty ||
          iterations is! int ||
          iterations < 1 ||
          verifier is! String ||
          verifier.isEmpty ||
          changed is! int) {
        return null;
      }
      return AppPasswordRecord(
        salt: salt,
        iterations: iterations,
        verifier: verifier,
        changedAt: DateTime.fromMillisecondsSinceEpoch(changed, isUtc: true),
      );
    } on Object {
      return null;
    }
  }

  /// Base64.
  final String salt;
  final int iterations;
  final String verifier;
  final DateTime changedAt;

  String encode() => jsonEncode({
        'salt': salt,
        'iterations': iterations,
        'verifier': verifier,
        'changed_at': changedAt.toUtc().millisecondsSinceEpoch,
      });

  static const _verifierPhrase = 'appflowy-password-v1';
  static const _context = 'app-password';

  /// A record for [password]. The derivation is slow on purpose, so it runs
  /// on another thread.
  static Future<AppPasswordRecord> make(
    String password, {
    required DateTime now,
    int iterations = defaultKeyIterations,
  }) =>
      Isolate.run(() => _makeSync(password, now, iterations));

  static AppPasswordRecord _makeSync(
    String password,
    DateTime now,
    int iterations,
  ) {
    final salt = newEncryptionSalt();
    final key = deriveKeyFromPassphrase(
      passphrase: password,
      salt: salt,
      iterations: iterations,
    );
    return AppPasswordRecord(
      salt: base64Encode(salt),
      iterations: iterations,
      verifier: sealText(
        key: key,
        plaintext: _verifierPhrase,
        context: _context,
      ),
      changedAt: now,
    );
  }

  /// Whether [password] is the one this record was made from.
  Future<bool> accepts(String password) => _accepts(this, password);

  // Static, so the closure sent to the other thread holds only the record
  // and the password.
  static Future<bool> _accepts(AppPasswordRecord record, String password) =>
      Isolate.run(() => _acceptsSync(record, password));

  static bool _acceptsSync(AppPasswordRecord record, String password) {
    try {
      final key = deriveKeyFromPassphrase(
        passphrase: password,
        salt: Uint8List.fromList(base64Decode(record.salt)),
        iterations: record.iterations,
      );
      return openText(key: key, value: record.verifier, context: _context) ==
          _verifierPhrase;
    } on Object {
      return false;
    }
  }
}

/// The AppFlowy password, as what seals things asks for it.
abstract class AppPasswordSource {
  /// The password, when this computer knows it.
  Future<String?> current();

  /// [password] opened something sealed with the AppFlowy password — a sync
  /// folder, the settings kept with a server — so it is the AppFlowy password
  /// now, here too.
  ///
  /// Nothing is re-keyed: whatever follows the password was re-keyed on the
  /// computer where it was changed, and arrives that way.
  Future<void> adopt(String password);
}

/// The AppFlowy password on this computer.
class AppPassword extends ChangeNotifier implements AppPasswordSource {
  AppPassword({
    KeyValueStorage? storage,
    ProviderSecretStore? secrets,
    this.iterations = defaultKeyIterations,
    DateTime Function()? clock,
  })  : _storage = storage,
        _secrets = secrets ?? ProviderSecretStore(),
        _clock = clock ?? DateTime.now;

  static final AppPassword instance = AppPassword();

  /// The check value, in this computer's settings. Never synced.
  static const storageKey = 'appflowy_app_password';

  /// The password, in the keyring. Never synced.
  static const secretId = 'appflowy-app-password';

  static const int minimumLength = minimumPassphraseLength;

  /// How hard a new password is made to guess.
  final int iterations;

  final KeyValueStorage? _storage;
  final ProviderSecretStore _secrets;
  final DateTime Function() _clock;

  AppPasswordRecord? _record;
  String? _password;
  Future<void>? _loading;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  /// Whether an AppFlowy password has been chosen on this computer.
  bool get isSet => _record != null;

  /// Whether this computer knows it right now, so nothing has to ask.
  bool get isKnown => _password != null;

  /// Set, but not known here: the keyring lost it, or cannot keep it.
  bool get needsTyping => isSet && !isKnown;

  /// Whether this computer keeps it between sessions. Where it cannot, it is
  /// asked for once a session.
  bool get canRemember => _secrets.canPersist;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final storage = _kv;
    if (storage == null) {
      // Nothing to read yet; whatever asks later reads again.
      _loading = null;
      return;
    }
    try {
      _record = AppPasswordRecord.tryParse(await storage.get(storageKey));
      final record = _record;
      if (record != null) {
        final kept = await _readKept();
        // Kept beside the record it was proved against, it needs no slow
        // check; kept beside another one, it has to pass one.
        if (kept != null &&
            (kept.stamp == record.changedAt.millisecondsSinceEpoch ||
                await record.accepts(kept.password))) {
          _password = kept.password;
        }
      }
      notifyListeners();
    } on Object catch (error) {
      _loading = null;
      Log.warn('The AppFlowy password could not be read: $error');
    }
  }

  @override
  Future<String?> current() async {
    await ensureLoaded();
    return _password;
  }

  /// Whether [password] is the AppFlowy password of this computer.
  Future<bool> check(String password) async {
    await ensureLoaded();
    final known = _password;
    if (known != null) {
      return known == password;
    }
    final record = _record;
    return record != null && await record.accepts(password);
  }

  /// Chooses the password on a computer that has none.
  Future<void> choose(String password) async {
    await ensureLoaded();
    if (isSet) {
      throw StateError('An AppFlowy password is set already.');
    }
    await _write(password);
  }

  /// Types the password on this computer, where it is set but not known.
  /// False when it is not the password.
  Future<bool> unlock(String password) async {
    await ensureLoaded();
    final record = _record;
    if (record == null || !await record.accepts(password)) {
      return false;
    }
    _password = password;
    await _keep(password, record);
    notifyListeners();
    return true;
  }

  @override
  Future<void> adopt(String password) async {
    await ensureLoaded();
    if (_password == password) {
      return;
    }
    final record = _record;
    if (record != null && _password == null && await record.accepts(password)) {
      // Typed again on a computer that had forgotten it: nothing changed.
      _password = password;
      await _keep(password, record);
      notifyListeners();
      return;
    }
    await _write(password);
  }

  /// Writes [next] down as the password, once everything that follows it has
  /// been moved over to it.
  Future<void> commitChange(String next) async {
    await ensureLoaded();
    await _write(next);
  }

  /// Forgets the password and its check value on this computer, for a full
  /// local reset.
  Future<void> clear() async {
    _record = null;
    _password = null;
    _loading = null;
    try {
      await _secrets.forget(secretId);
    } on Object catch (error) {
      Log.warn('The AppFlowy password could not be cleared from keyring: $error');
    }
    try {
      await _kv?.remove(storageKey);
    } on Object catch (error) {
      Log.warn('The AppFlowy password record could not be removed: $error');
    }
    notifyListeners();
  }

  Future<void> _write(String password) async {
    final storage = _kv;
    if (storage == null) {
      throw StateError('Settings are not ready yet.');
    }
    final record = await AppPasswordRecord.make(
      password,
      now: _clock(),
      iterations: iterations,
    );
    await storage.set(storageKey, record.encode());
    _record = record;
    _password = password;
    await _keep(password, record);
    notifyListeners();
  }

  Future<void> _keep(String password, AppPasswordRecord record) async {
    try {
      await _secrets.write(
        secretId,
        jsonEncode({
          'password': password,
          'stamp': record.changedAt.millisecondsSinceEpoch,
        }),
      );
    } on Object catch (error) {
      // Held for the session; it is asked for again next time.
      Log.warn('The AppFlowy password could not be kept: $error');
    }
  }

  Future<({String password, int stamp})?> _readKept() async {
    try {
      final kept = await _secrets.read(secretId);
      if (kept == null || kept.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(kept);
      if (decoded is! Map) {
        return null;
      }
      final password = decoded['password'];
      final stamp = decoded['stamp'];
      return password is String && password.isNotEmpty && stamp is int
          ? (password: password, stamp: stamp)
          : null;
    } on Object {
      return null;
    }
  }

  /// Reads everything again, as a restarted application would.
  @visibleForTesting
  Future<void> reload() {
    _record = null;
    _password = null;
    _loading = null;
    return ensureLoaded();
  }
}
