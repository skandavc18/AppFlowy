// What the application has been told about backups, and what it remembers
// having done.
//
// Two things live here and they are deliberately separate. The POLICY is the
// set of rules somebody chose. The LEDGER is the record of copies that were
// actually made — which matters because AppFlowy Cloud will not tell us what is
// there, so without this the list would be empty every time the application
// starts.

import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/backup/backup_target.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// How a run ended, kept so the settings can say what happened last.
@immutable
class BackupOutcome {
  const BackupOutcome({
    required this.at,
    required this.succeeded,
    this.backupId = '',
    this.bytes = 0,
    this.detail = '',
  });

  factory BackupOutcome.fromJson(Map<String, Object?> json) => BackupOutcome(
        at: DateTime.fromMillisecondsSinceEpoch(
          json['at'] is int ? json['at']! as int : 0,
        ),
        succeeded: json['succeeded'] == true,
        backupId: json['id'] is String ? json['id']! as String : '',
        bytes: json['bytes'] is int ? json['bytes']! as int : 0,
        detail: json['detail'] is String ? json['detail']! as String : '',
      );

  final DateTime at;
  final bool succeeded;
  final String backupId;
  final int bytes;

  /// What went wrong, in words somebody can act on. Empty when it worked.
  final String detail;

  Map<String, Object?> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'succeeded': succeeded,
        if (backupId.isNotEmpty) 'id': backupId,
        if (bytes > 0) 'bytes': bytes,
        if (detail.isNotEmpty) 'detail': detail,
      };
}

/// The rules, the record, and the passphrase while the application is running.
///
/// ⚠️ Every mutation waits on [ensureLoaded] before it writes. A lazily loaded
/// singleton whose writes do not wait will happily persist a view of the world
/// it never read.
class BackupSettings extends ChangeNotifier {
  BackupSettings._();

  static final BackupSettings instance = BackupSettings._();

  static const policyKey = 'appflowy_backup_policy';
  static const ledgerKey = 'appflowy_backup_ledger';

  /// The name the passphrase is sealed under, when somebody asks this computer
  /// to remember it. Reuses the store the connections already use, which on
  /// Windows means DPAPI and elsewhere means the session only.
  static const passphraseSecretId = 'appflowy-backup-passphrase';

  final ProviderSecretStore _secrets = ProviderSecretStore();

  BackupPolicy _policy = const BackupPolicy();
  List<BackupCopy> _ledger = const <BackupCopy>[];
  BackupOutcome? _lastOutcome;
  DateTime? _lastRunAt;
  Future<void>? _loading;
  bool _loaded = false;

  /// The derived key, in memory only.
  ///
  /// A backup taken on a clock cannot stop and ask for a passphrase, so the key
  /// is kept for the session once it has been entered. Nothing writes it down
  /// unless [rememberPassphrase] was asked for.
  Uint8List? _key;

  BackupPolicy get policy => _policy;

  List<BackupCopy> get ledger => _ledger;

  BackupOutcome? get lastOutcome => _lastOutcome;

  DateTime? get lastRunAt => _lastRunAt;

  bool get isLoaded => _loaded;

  /// Whether a sealed backup could run right now without asking anybody.
  bool get isUnlocked => !_policy.encrypt || _key != null;

  Uint8List? get key => _key;

  /// Whether this computer can keep the passphrase between sessions.
  bool get canRememberPassphrase => _secrets.canPersist;

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
      final stored = await storage.get(policyKey);
      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          final values = Map<String, Object?>.from(decoded);
          _policy = BackupPolicy.fromJson(values);
          final outcome = values['last_outcome'];
          if (outcome is Map) {
            _lastOutcome = BackupOutcome.fromJson(
              Map<String, Object?>.from(outcome),
            );
          }
          final last = values['last_run_at'];
          if (last is int) {
            _lastRunAt = DateTime.fromMillisecondsSinceEpoch(last);
          }
        }
      }

      final ledger = await storage.get(ledgerKey);
      if (ledger != null && ledger.isNotEmpty) {
        final decoded = jsonDecode(ledger);
        if (decoded is List) {
          _ledger = [
            for (final entry in decoded)
              if (BackupCopy.fromJson(entry) != null)
                BackupCopy.fromJson(entry)!,
          ];
        }
      }

      _loaded = true;
      notifyListeners();
    } on Object catch (error) {
      _loading = null;
      Log.warn('The backup settings could not be read: $error');
    }
  }

  Future<void> update(BackupPolicy policy) async {
    await ensureLoaded();
    if (policy == _policy) {
      return;
    }
    _policy = policy;
    _loaded = true;
    if (!policy.encrypt) {
      // Turning sealing off must not leave a key in memory that a later run
      // would quietly start using again.
      _wipeKey();
      await forgetRememberedPassphrase();
    }
    notifyListeners();
    await _persistPolicy();
  }

  Future<void> recordRun(BackupOutcome outcome) async {
    await ensureLoaded();
    _lastOutcome = outcome;
    _lastRunAt = outcome.at;
    notifyListeners();
    await _persistPolicy();
  }

  /// Remembers what is at a destination that cannot be asked.
  Future<void> rememberCopy(BackupCopy copy) => rememberCopies([copy]);

  /// The same for several at once, so adopting a whole published index costs
  /// one write rather than one per copy.
  Future<void> rememberCopies(List<BackupCopy> copies) async {
    await ensureLoaded();
    if (copies.isEmpty) {
      return;
    }
    final merged = mergeBackupCopies(copies, _ledger);
    if (_sameLedger(merged, _ledger)) {
      return;
    }
    _ledger = merged;
    notifyListeners();
    await _persistLedger();
  }

  static bool _sameLedger(List<BackupCopy> a, List<BackupCopy> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].locator != b[i].locator) {
        return false;
      }
    }
    return true;
  }

  Future<void> forgetCopy(String id) async {
    await ensureLoaded();
    final next = [
      for (final copy in _ledger)
        if (copy.id != id) copy,
    ];
    if (next.length == _ledger.length) {
      return;
    }
    _ledger = next;
    notifyListeners();
    await _persistLedger();
  }

  Future<void> clearLedger() async {
    await ensureLoaded();
    if (_ledger.isEmpty) {
      return;
    }
    _ledger = const <BackupCopy>[];
    notifyListeners();
    await _persistLedger();
  }

  // --- The passphrase ---------------------------------------------------------

  /// Holds the derived key for this session.
  void unlockWith(Uint8List key) {
    _key = key;
    notifyListeners();
  }

  void lock() {
    _wipeKey();
    notifyListeners();
  }

  /// Seals the passphrase where this computer can find it again.
  ///
  /// Opt in, and only where the platform can really seal it — everywhere else
  /// it lasts for the session and the interface says so.
  Future<void> rememberPassphrase(String passphrase) =>
      _secrets.write(passphraseSecretId, passphrase);

  Future<String?> rememberedPassphrase() => _secrets.read(passphraseSecretId);

  Future<void> forgetRememberedPassphrase() =>
      _secrets.write(passphraseSecretId, '');

  void _wipeKey() {
    final key = _key;
    if (key != null) {
      // Overwritten rather than dropped: a released buffer keeps its bytes.
      for (var i = 0; i < key.length; i++) {
        key[i] = 0;
      }
    }
    _key = null;
  }

  Future<void> _persistPolicy() async {
    final storage = _kv;
    if (storage == null) {
      return;
    }
    try {
      await storage.set(
        policyKey,
        jsonEncode({
          ..._policy.toJson(),
          if (_lastOutcome != null) 'last_outcome': _lastOutcome!.toJson(),
          if (_lastRunAt != null)
            'last_run_at': _lastRunAt!.millisecondsSinceEpoch,
        }),
      );
    } on Object catch (error) {
      Log.warn('The backup settings could not be stored: $error');
    }
  }

  Future<void> _persistLedger() async {
    final storage = _kv;
    if (storage == null) {
      return;
    }
    try {
      await storage.set(
        ledgerKey,
        jsonEncode([for (final copy in _ledger) copy.toJson()]),
      );
    } on Object catch (error) {
      Log.warn('The record of backups could not be stored: $error');
    }
  }

  @visibleForTesting
  void seedForTest(BackupPolicy policy, {List<BackupCopy> ledger = const []}) {
    _policy = policy;
    _ledger = ledger;
    _loaded = true;
    _loading = Future<void>.value();
  }
}
