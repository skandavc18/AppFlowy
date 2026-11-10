// Settings, accounts and keys that follow a person through their AppFlowy
// server.
//
// A workspace on an AppFlowy server is already the same on every computer
// signed in to it. What the server does not keep is this application's
// settings, and the accounts, passwords and keys connected here. They are kept
// with the account on the server as one document, sealed with the AppFlowy
// password like a sync folder, so the server holds nothing it can read. Each
// setting still travels on its own: the later change wins, a change made here
// and not sent yet stays, and accounts, passwords and keys can be taken out on
// their own.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/encryption/encryption.dart'
    show defaultKeyIterations;
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart'
    show SyncError, describeSyncError;
import 'package:appflowy/workspace/application/sync/sync_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart'
    show syncFormat;
import 'package:appflowy/workspace/application/sync/sync_vault.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Values kept with the signed-in account on the server.
abstract class CloudUserValues {
  /// Null when the server holds nothing under [key].
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// The account's values as the backend reaches them.
class BackendCloudUserValues implements CloudUserValues {
  const BackendCloudUserValues();

  @override
  Future<String?> read(String key) async {
    final result =
        await UserEventGetCloudUserValue(CloudUserKeyPB(key: key)).send();
    return result.fold(
      (value) => value.found ? value.value : null,
      (error) => throw SyncError(
        error.msg.isEmpty ? 'The server could not be asked.' : error.msg,
      ),
    );
  }

  @override
  Future<void> write(String key, String value) async {
    final result = await UserEventSetCloudUserValue(
      CloudUserValuePB(key: key, value: value),
    ).send();
    result.fold(
      (_) {},
      (error) => throw SyncError(
        error.msg.isEmpty ? 'The server would not keep it.' : error.msg,
      ),
    );
  }
}

enum ServerSettingsPhase {
  /// Not a workspace on an AppFlowy server.
  off,

  /// Not set up for this account yet, and this computer has no AppFlowy
  /// password to set it up with.
  notSetUp,

  /// Set up with an AppFlowy password this computer does not know: never
  /// typed here, or changed on another computer since.
  locked,
  idle,
  working,
  failed,
}

class ServerSettingsSync extends ChangeNotifier {
  ServerSettingsSync({
    CloudUserValues? values,
    SyncKeyKeeper? keys,
    KeyValueStorage? storage,
    Future<Directory> Function()? home,
    DateTime Function()? clock,
    AppPasswordSource? passwords,
    this.vaultIterations = defaultKeyIterations,
    this.interval = const Duration(minutes: 1),
  })  : _values = values ?? const BackendCloudUserValues(),
        _keys = keys ?? SecretStoreKeyKeeper(),
        _passwords = passwords ?? AppPassword.instance,
        _storage = storage,
        _home = home ?? getApplicationSupportDirectory,
        _clock = clock ?? DateTime.now;

  static final ServerSettingsSync instance = ServerSettingsSync();

  /// Where the password record and the sealed settings are kept with the
  /// account.
  static const String vaultValueKey = 'appflowy_sync_vault';
  static const String settingsValueKey = 'appflowy_sync_settings';

  /// What each computer chose for itself, by account.
  static const String optionsKey = 'appflowy_sync_server_options';

  /// Which record each account's settings were last sealed under here, so
  /// what this computer kept of them follows a new password.
  static const String vaultsKey = 'appflowy_sync_server_vaults';

  final int vaultIterations;
  final Duration interval;

  final CloudUserValues _values;
  final SyncKeyKeeper _keys;
  final AppPasswordSource _passwords;
  final KeyValueStorage? _storage;
  final Future<Directory> Function() _home;
  final DateTime Function() _clock;

  SyncedPreferencesSource? _preferences;
  int? _uid;
  SyncVault? _vault;
  SyncKey? _key;
  Timer? _timer;
  bool _running = false;
  bool _again = false;
  Completer<void>? _rounds;
  bool _syncHere = true;
  bool _credentialsOn = true;
  final List<SyncPreferenceRecord> _outbox = [];

  ServerSettingsPhase _phase = ServerSettingsPhase.off;
  String _lastError = '';
  DateTime? _lastSyncedAt;

  ServerSettingsPhase get phase => _phase;
  String get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Whether this computer's settings follow the account.
  bool get syncsHere => _syncHere;

  /// Whether accounts, passwords and keys travel through the server.
  bool get credentialsSynced => _credentialsOn;

  bool get isBusy => _running;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  /// Wires in where this computer's settings are read and put.
  void configure({SyncedPreferencesSource? preferences}) {
    _preferences = preferences ?? _preferences;
  }

  /// Starts following the settings of the account [uid] signed in to an
  /// AppFlowy server.
  Future<void> attach({required int uid}) async {
    _uid = uid;
    _syncHere = (await _options())['$uid'] != false;
    try {
      _vault = await _readVault();
      final vault = _vault;
      if (vault == null) {
        _key = null;
        if (await _passwords.current() == null) {
          _set(ServerSettingsPhase.notSetUp);
          return;
        }
        // Nothing to ask: the AppFlowy password seals it.
        await setUp();
        return;
      }
      final key = await _openVault(vault);
      if (key == null) {
        _key = null;
        _set(ServerSettingsPhase.locked);
        return;
      }
      await _keep(key);
      unawaited(_schedule());
    } on Object catch (error) {
      _fail(error);
    }
  }

  /// Whether the account is set up with an AppFlowy password that is not the
  /// one this computer knows, rather than one never typed here.
  bool get passwordChangedElsewhere =>
      _phase == ServerSettingsPhase.locked && _wasOpenHere;
  bool _wasOpenHere = false;

  /// The key for [vault]: the one in memory, the one kept in the keyring, or
  /// the one the AppFlowy password makes.
  Future<SyncKey?> _openVault(SyncVault vault) async {
    final held = _key;
    if (held != null && vault.accepts(held)) {
      return held;
    }
    _wasOpenHere = held != null;
    final kept = await _keys.read(vault.id);
    if (kept != null && vault.accepts(kept)) {
      return kept;
    }
    final password = await _passwords.current();
    if (password == null) {
      return null;
    }
    final key = await vault.unlock(password);
    if (key != null) {
      await _keys.write(key);
    }
    return key;
  }

  /// Stops looking, for instance while the application restarts.
  void detach() {
    _timer?.cancel();
    _timer = null;
  }

  /// Seals the account's settings with the AppFlowy password and starts — or
  /// opens them with it, when another computer set them up already.
  Future<void> setUp() async {
    final password = await _passwords.current();
    if (password == null) {
      throw const SyncError('Set your AppFlowy password first.');
    }
    final vault = await _readVault();
    if (vault != null) {
      return unlock(password);
    }
    final (created, key) = await SyncVault.create(
      passphrase: password,
      now: _clock(),
      iterations: vaultIterations,
    );
    await _values.write(vaultValueKey, created.encode());
    // Read again: when two computers set it up at once, the last one written
    // is the account's.
    final winner = await _readVault();
    if (winner == null || winner.id != created.id) {
      if (winner != null) {
        return unlock(password);
      }
      throw const SyncError('The server would not keep the settings.');
    }
    _vault = winner;
    await _keep(key);
    await _schedule();
  }

  /// Types the AppFlowy password the account's settings are sealed with. It
  /// becomes this computer's AppFlowy password too.
  Future<void> unlock(String password) async {
    final vault = await _readVault();
    if (vault == null) {
      throw const SyncError('Nothing is set up for this account yet.');
    }
    final key = await vault.unlock(password);
    if (key == null) {
      throw const SyncError(
        'That is not the AppFlowy password these settings are sealed with.',
      );
    }
    _vault = vault;
    await _keep(key);
    await _passwords.adopt(password);
    await _schedule();
  }

  /// Seals the account's settings again, with the AppFlowy password this
  /// computer has just changed to. The others are asked for it next time.
  Future<void> resealWithAppPassword() async {
    final password = await _passwords.current();
    final previous = _key;
    if (password == null || _uid == null) {
      return;
    }
    final vault = await _readVault();
    if (vault == null) {
      return;
    }
    if (await vault.unlock(password) != null) {
      return;
    }
    if (previous == null || !vault.accepts(previous)) {
      throw const SyncError('Type your AppFlowy password first.');
    }
    detach();
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final records = await _readSettings(previous);
    final (created, key) = await SyncVault.create(
      passphrase: password,
      now: _clock(),
      iterations: vaultIterations,
    );
    // The record first: a computer still holding the old key sees it change
    // and stops, rather than write over what is sealed with the new one.
    await _values.write(vaultValueKey, created.encode());
    await _writeSettings(key, records);
    _vault = created;
    await _keep(key);
    await _schedule();
  }

  /// Whether this computer's settings follow the account. Turned back on,
  /// the account's settings are taken here first.
  Future<void> setSyncHere(bool on) async {
    final uid = _uid;
    if (uid == null || on == _syncHere) {
      return;
    }
    final options = await _options();
    options['$uid'] = on;
    await _kv?.set(optionsKey, jsonEncode(options));
    _syncHere = on;
    if (on) {
      final key = _key;
      final source = _preferences;
      if (key != null && source != null) {
        try {
          await adoptIndexedPreferences(
            source: GatedPreferences(source, credentials: _credentialsOn),
            index: await SyncPreferencesIndex.load(
              await _indexFile(),
              key: key,
            ),
          );
        } on Object catch (error) {
          Log.warn('The account\'s settings could not be taken: $error');
        }
      }
    }
    notifyListeners();
    unawaited(syncNow());
  }

  /// Whether accounts, passwords and keys travel through the server. Turned
  /// off, they are taken off it; every computer keeps the ones it has.
  Future<void> setSyncCredentials(bool on) async {
    if (on == _credentialsOn) {
      return;
    }
    _outbox.add(
      SyncPreferenceRecord(
        key: credentialsSwitchKey,
        value: on ? syncSwitchOn : syncSwitchOff,
        modified: _clock().millisecondsSinceEpoch,
      ),
    );
    _credentialsOn = on;
    notifyListeners();
    await syncNow();
  }

  /// Runs a round now, or right after the one that is running, and returns
  /// once a round that started after this was asked for has finished.
  Future<void> syncNow() {
    if (_key == null) {
      return Future<void>.value();
    }
    final running = _rounds;
    if (_running && running != null) {
      _again = true;
      return running.future;
    }
    _running = true;
    final rounds = _rounds = Completer<void>();
    unawaited(() async {
      try {
        do {
          _again = false;
          await _round();
        } while (_again);
      } finally {
        _running = false;
        rounds.complete();
        notifyListeners();
      }
    }());
    return rounds.future;
  }

  /// Starts looking every [interval], and returns once the first round is
  /// done.
  Future<void> _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(syncNow()));
    _set(ServerSettingsPhase.idle);
    return syncNow();
  }

  Future<void> _round() async {
    final held = _key;
    final preferences = _preferences;
    if (held == null || preferences == null) {
      return;
    }
    _set(ServerSettingsPhase.working);
    try {
      // Sealed again elsewhere, with a password this computer may not know:
      // nothing is written with the old key over what the new one sealed.
      final vault = await _readVault();
      if (vault == null || !vault.accepts(held)) {
        final opened = vault == null ? null : await _openVault(vault);
        _vault = vault;
        if (opened == null) {
          _key = null;
          _wasOpenHere = true;
          detach();
          _set(
            vault == null
                ? ServerSettingsPhase.notSetUp
                : ServerSettingsPhase.locked,
          );
          return;
        }
        await _keep(opened);
      }
      final key = _key!;
      final indexFile = await _indexFile();
      final index = await SyncPreferencesIndex.load(indexFile, key: key);
      var remote = await _readSettings(key);

      // The account's switches first: they decide what else is taken.
      for (final record in remote.values) {
        if (isSyncSwitchKey(record.key)) {
          index.note(record);
        }
      }
      for (final record in _outbox) {
        index.note(record);
      }
      _credentialsOn = index.credentialsOn;
      if (!_credentialsOn) {
        index.dropCredentials();
      }
      final source = _syncHere
          ? GatedPreferences(preferences, credentials: _credentialsOn)
          : const InertPreferencesSource();
      final current = await source.read();
      final changed = await applyRemotePreferences(
        source: source,
        index: index,
        records: [
          for (final record in remote.values)
            if (!isSyncSwitchKey(record.key) &&
                (_credentialsOn || !isCredentialKey(record.key)))
              record,
        ],
        current: current,
      );
      if (changed > 0) {
        Log.info('Synced $changed settings from the account.');
      }

      final outgoing = [
        ...scanSyncedPreferences(
          current: current,
          index: index,
          handles: source.handles,
          now: _clock().millisecondsSinceEpoch,
          unreadable: source.unreadable,
        ),
        ..._outbox,
      ];
      // The server keeps one document, and a computer writing it at the same
      // moment as another can overwrite what the other just wrote. Whoever
      // knows a later version of a setting than the server holds sends it
      // again, so nothing written is lost for good.
      final sending = {for (final record in outgoing) record.key};
      for (final record in index.entries.values) {
        if (!sending.contains(record.key) &&
            record.isLaterThan(remote[record.key])) {
          outgoing.add(record);
        }
      }
      final strayCredentials =
          !_credentialsOn && remote.keys.any(isCredentialKey);
      if (outgoing.isNotEmpty || strayCredentials) {
        // Another computer may write between the read and the write: what
        // it wrote is read again and merged, and only what is then really on
        // the server counts as sent.
        for (var attempt = 0; attempt < 3; attempt++) {
          final merged = Map<String, SyncPreferenceRecord>.of(remote);
          for (final record in outgoing) {
            if (record.isLaterThan(merged[record.key])) {
              merged[record.key] = record;
            }
          }
          final switches = {
            for (final record in merged.values)
              if (isSyncSwitchKey(record.key)) record.key: record,
          };
          if (switches[credentialsSwitchKey]?.value == syncSwitchOff) {
            merged.removeWhere((key, _) => isCredentialKey(key));
          }
          await _writeSettings(key, merged);
          remote = await _readSettings(key);
          if (outgoing.every(
            (record) => !record.isLaterThan(remote[record.key]),
          )) {
            break;
          }
        }
        for (final record in outgoing) {
          if (!record.isLaterThan(remote[record.key])) {
            index.note(record);
          }
        }
        _outbox.removeWhere(
          (record) => !record.isLaterThan(remote[record.key]),
        );
      }
      await index.save(indexFile, key: key);
      _lastSyncedAt = _clock();
      _lastError = '';
      _set(ServerSettingsPhase.idle);
    } on Object catch (error, stackTrace) {
      Log.warn('Settings did not sync with the account: $error\n$stackTrace');
      _fail(error);
    }
  }

  Future<SyncVault?> _readVault() async {
    final text = await _values.read(vaultValueKey);
    if (text == null || text.isEmpty) {
      return null;
    }
    final vault = SyncVault.tryParse(text);
    if (vault == null) {
      throw const SyncError(
        'The account was set up by a newer version of AppFlowy.',
      );
    }
    return vault;
  }

  Future<Map<String, SyncPreferenceRecord>> _readSettings(SyncKey key) async {
    final sealed = await _values.read(settingsValueKey);
    if (sealed == null || sealed.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(key.openText(sealed, context: _context));
    if (decoded is! Map || decoded['format'] != syncFormat) {
      throw const SyncError(
        'The account\'s settings were written by a newer version of '
        'AppFlowy.',
      );
    }
    final records = decoded['records'];
    return {
      if (records is List)
        for (final entry in records)
          if (entry is Map)
            if (SyncPreferenceRecord.fromJson(Map<String, Object?>.from(entry))
                case final record when record.key.isNotEmpty)
              record.key: record,
    };
  }

  Future<void> _writeSettings(
    SyncKey key,
    Map<String, SyncPreferenceRecord> records,
  ) =>
      _values.write(
        settingsValueKey,
        key.sealText(
          jsonEncode({
            'format': syncFormat,
            'records': [for (final record in records.values) record.toJson()],
          }),
          context: _context,
        ),
      );

  static const String _context = 'server-settings';

  Future<File> _indexFile() async => File(
        p.join(
          (await _home()).path,
          'sync',
          'server-${_uid ?? 0}',
          'prefs.json',
        ),
      );

  Future<Map<String, Object?>> _options() => _map(optionsKey);

  Future<Map<String, Object?>> _map(String key) async {
    try {
      final raw = await _kv?.get(key);
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } on Object {
      return {};
    }
  }

  Future<void> _keep(SyncKey key) async {
    await _keys.write(key);
    await _rekeyIndex(key);
    _key = key;
  }

  /// What this computer kept of the account's settings, sealed under [key]
  /// now if it was sealed under another. Unread, a setting changed here and
  /// not sent yet would look never synced, and the server's would win.
  Future<void> _rekeyIndex(SyncKey key) async {
    final uid = _uid;
    if (uid == null) {
      return;
    }
    final vaults = await _map(vaultsKey);
    final before = vaults['$uid'];
    if (before is String && before.isNotEmpty && before != key.vaultId) {
      final held = _key;
      final old =
          held != null && held.vaultId == before ? held : await _keys.read(before);
      if (old != null) {
        final file = await _indexFile();
        final index = await SyncPreferencesIndex.load(file, key: old);
        await index.save(file, key: key);
      }
    }
    if (before != key.vaultId) {
      vaults['$uid'] = key.vaultId;
      await _kv?.set(vaultsKey, jsonEncode(vaults));
    }
  }

  void _set(ServerSettingsPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  void _fail(Object error) {
    _lastError = describeSyncError(error);
    _set(ServerSettingsPhase.failed);
  }

  @visibleForTesting
  void forgetKeyInMemory() => _key = null;
}
