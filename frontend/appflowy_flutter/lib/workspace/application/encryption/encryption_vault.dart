import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/encryption/encryption_policy.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// Raised when something asks for words that are still sealed.
class WorkspaceLockedError implements Exception {
  const WorkspaceLockedError();

  @override
  String toString() =>
      'WorkspaceLockedError: the workspace key has not been entered';
}

/// The one place the workspace key lives while the application is running.
///
/// The key is derived from a passphrase nobody stores and is held in memory
/// only. Closing the application, choosing Lock, or leaving the machine alone
/// for the chosen time all drop it, and everything sealed becomes unreadable
/// again until it is entered.
///
/// ⚠️ Every mutation waits on [ensureLoaded] before it writes. A lazily loaded
/// singleton whose writes do not wait will happily persist a view of the world
/// it never read — which is how a policy gets erased on a cold start.
class EncryptionVault extends ChangeNotifier {
  EncryptionVault._();

  static final EncryptionVault instance = EncryptionVault._();

  static const storageKey = 'appflowy_workspace_encryption';

  EncryptionPolicy _policy = const EncryptionPolicy();
  Uint8List? _key;
  Future<void>? _loading;
  bool _loaded = false;
  Timer? _idle;

  /// What has been opened since the application started.
  ///
  /// Being encrypted is what a thing *is*; being revealed is what has happened
  /// since AppFlowy opened. This starts empty and is never written down, so
  /// everything protected is shut on a cold start however long the key later
  /// stays in memory.
  final Set<String> _revealed = {};

  EncryptionPolicy get policy => _policy;

  /// Whether a passphrase has been chosen for this workspace at all.
  bool get isConfigured => _policy.isConfigured;

  /// Whether the key is in memory right now.
  bool get isUnlocked => _key != null;

  /// Whether anything is currently hidden. A workspace with no passphrase is
  /// never locked, which is what makes the whole feature optional.
  bool get isLocked => isConfigured && !isUnlocked;

  bool get isLoaded => _loaded;

  /// The words shown beside the passphrase field, if one was left.
  String get hint => _policy.hint;

  /// Whether [id] is open right now. Needs the key as well as the intent.
  bool isRevealed(String id) => isUnlocked && _revealed.contains(id);

  void reveal(String id) {
    if (_revealed.add(id)) {
      notifyListeners();
    }
  }

  void conceal(String id) {
    // Always speaks, even when nothing was open: this is also how a page that
    // has just been protected is told to shut while somebody is looking at it.
    _revealed.remove(id);
    notifyListeners();
  }

  KeyValueStorage? get _kv =>
      getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final storage = _kv;
    if (storage == null) {
      // Reading nothing must not latch: settings opened later has to try again.
      _loading = null;
      return;
    }
    try {
      final stored = await storage.get(storageKey);
      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          _policy = EncryptionPolicy.fromJson(
            Map<String, Object?>.from(decoded),
          );
        }
      }
      _loaded = true;
      notifyListeners();
    } on Object catch (error) {
      _loading = null;
      Log.warn('The workspace encryption settings could not be read: $error');
    }
  }

  /// Chooses a passphrase for a workspace that had none.
  ///
  /// [gateWholeWorkspace] is the caller's intent, not a default: setting a key
  /// from Settings means "ask before opening this workspace", while setting one
  /// from a collection's menu means "ask for that collection". Deciding it here
  /// is what stops protecting a single item closing the way in to everything.
  Future<bool> enable({
    required String passphrase,
    String hint = '',
    bool gateWholeWorkspace = false,
  }) async {
    await ensureLoaded();
    if (passphrase.length < minimumPassphraseLength) {
      return false;
    }

    final next = newEncryptionPolicy(
      passphrase: passphrase,
      hint: hint,
      previous: _policy,
    ).copyWith(gateWholeWorkspace: gateWholeWorkspace);
    final key = unlockEncryptionKey(policy: next, passphrase: passphrase);
    if (key == null) {
      // Cannot happen unless the policy and the derivation disagree, and if
      // they ever do, enabling must fail loudly rather than lock somebody out.
      Log.error('A new workspace key did not verify against its own policy.');
      return false;
    }

    _policy = next;
    _key = key;
    await _persist();
    _restartIdleTimer();
    notifyListeners();
    return true;
  }

  /// Puts the key in memory. False means the passphrase was wrong.
  Future<bool> unlock(String passphrase) async {
    await ensureLoaded();
    final key = unlockEncryptionKey(policy: _policy, passphrase: passphrase);
    if (key == null) {
      return false;
    }
    _key = key;
    _restartIdleTimer();
    notifyListeners();
    return true;
  }

  /// Drops the key. Everything sealed goes back to being unreadable.
  void lock() {
    if (_key == null) {
      return;
    }
    _wipe();
    _revealed.clear();
    _idle?.cancel();
    _idle = null;
    notifyListeners();
  }

  /// Changes the passphrase without changing the key that content was sealed
  /// with... which is impossible, so it changes both.
  ///
  /// Anything already sealed was sealed with the OLD key, so callers must
  /// re-seal it. [reseal] is handed the two keys in order and runs before the
  /// new policy is written down, so a failure leaves the old passphrase working.
  Future<bool> changePassphrase({
    required String current,
    required String next,
    String? hint,
    Future<bool> Function(Uint8List from, Uint8List to)? reseal,
  }) async {
    await ensureLoaded();
    if (next.length < minimumPassphraseLength) {
      return false;
    }
    final oldKey = unlockEncryptionKey(policy: _policy, passphrase: current);
    if (oldKey == null) {
      return false;
    }

    final nextPolicy = newEncryptionPolicy(
      passphrase: next,
      hint: hint ?? _policy.hint,
      previous: _policy,
    );
    final newKey = unlockEncryptionKey(policy: nextPolicy, passphrase: next);
    if (newKey == null) {
      return false;
    }

    if (reseal != null && !await reseal(oldKey, newKey)) {
      return false;
    }

    _policy = nextPolicy;
    _key = newKey;
    await _persist();
    _restartIdleTimer();
    notifyListeners();
    return true;
  }

  /// Removes the passphrase entirely.
  ///
  /// [beforeRemoval] runs while the passphrase is still known to be right and
  /// before anything is written, so whatever the key was guarding can be let
  /// go of. Returning false abandons the removal.
  Future<bool> disable({
    required String passphrase,
    Future<bool> Function(Uint8List key)? beforeRemoval,
  }) async {
    await ensureLoaded();
    final key = unlockEncryptionKey(policy: _policy, passphrase: passphrase);
    if (key == null) {
      return false;
    }
    if (beforeRemoval != null && !await beforeRemoval(key)) {
      return false;
    }

    _policy = const EncryptionPolicy();
    _wipe();
    _revealed.clear();
    _idle?.cancel();
    _idle = null;
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> update(EncryptionPolicy policy) async {
    await ensureLoaded();
    if (policy == _policy) {
      return;
    }
    _policy = policy;
    await _persist();
    _restartIdleTimer();
    notifyListeners();
  }

  /// Somebody is using the application, so the idle clock starts again.
  void touch() {
    if (_key != null && _policy.locksOnIdle) {
      _restartIdleTimer();
    }
  }

  /// Seals [plaintext], binding it to [context] so it cannot be moved.
  String seal(String plaintext, {String context = ''}) {
    final key = _key;
    if (key == null) {
      throw const WorkspaceLockedError();
    }
    return sealText(key: key, plaintext: plaintext, context: context);
  }

  /// Opens a sealed value, or throws when the workspace is locked.
  String open(String value, {String context = ''}) {
    final key = _key;
    if (key == null) {
      throw const WorkspaceLockedError();
    }
    return openText(key: key, value: value, context: context);
  }

  /// Opens a value that may or may not be sealed, and may or may not be
  /// openable.
  ///
  /// Returns the value untouched when it was never sealed, and null when it is
  /// sealed but cannot be read. Reading is done from widgets that must not
  /// throw, which is why this exists beside [open].
  String? tryOpen(String? value, {String context = ''}) {
    if (value == null) {
      return null;
    }
    if (!looksSealed(value)) {
      return value;
    }
    final key = _key;
    if (key == null) {
      return null;
    }
    try {
      return openText(key: key, value: value, context: context);
    } on Object {
      return null;
    }
  }

  /// The key itself, for the services that seal many values at once.
  ///
  /// Kept deliberately awkward to reach: everything that only needs one value
  /// should use [seal] and [open].
  Uint8List? get keyForBulkWork => _key;

  Future<void> _persist() async {
    final storage = _kv;
    if (storage == null) {
      return;
    }
    try {
      await storage.set(storageKey, jsonEncode(_policy.toJson()));
      _loaded = true;
    } on Object catch (error) {
      Log.warn('The workspace encryption settings could not be stored: $error');
    }
  }

  void _restartIdleTimer() {
    _idle?.cancel();
    if (!_policy.locksOnIdle || _key == null) {
      _idle = null;
      return;
    }
    _idle = Timer(Duration(minutes: _policy.lockAfterMinutes), lock);
  }

  /// Overwrites the key before dropping it, so it does not linger in a buffer
  /// the collector has not got round to.
  void _wipe() {
    final key = _key;
    if (key != null) {
      key.fillRange(0, key.length, 0);
    }
    _key = null;
  }

  @visibleForTesting
  void seedForTest({
    EncryptionPolicy policy = const EncryptionPolicy(),
    Uint8List? key,
    Set<String> revealed = const {},
  }) {
    _policy = policy;
    _key = key;
    _revealed
      ..clear()
      ..addAll(revealed);
    _loaded = true;
    _loading = Future<void>.value();
  }

  @visibleForTesting
  void resetForTest() {
    _idle?.cancel();
    _idle = null;
    _policy = const EncryptionPolicy();
    _key = null;
    _revealed.clear();
    _loaded = false;
    _loading = null;
  }
}
