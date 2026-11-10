// What this computer remembers about syncing its workspace.
//
// One binding at a time: the folder, the workspace it syncs, the epoch this
// computer is on, and how far it has read every other computer's changes. The
// binding names the workspace it belongs to, so switching to another workspace
// pauses sync rather than pouring one workspace into another.

import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How often a running AppFlowy looks for changes, in seconds.
const List<int> syncIntervalChoices = [10, 15, 30, 60, 300];

/// Often enough that an edit shows up on the other computer while it is still
/// fresh, rarely enough to stay well inside every service's request limits.
const int defaultSyncIntervalSeconds = 15;

@immutable
class SyncBinding {
  const SyncBinding({
    required this.destination,
    required this.epoch,
    required this.workspaceId,
    required this.workspaceName,
    required this.uid,
    this.nextSeq = 1,
    this.applied = const {},
    this.baseApplied = false,
    this.paused = false,
    this.intervalSeconds = defaultSyncIntervalSeconds,
    this.syncPreferences = true,
    this.vaultId = '',
    this.resealPending = false,
    this.lastSyncedAt,
    this.lastError = '',
  });

  factory SyncBinding.fromJson(Map<String, Object?> json) {
    final destination = json['destination'];
    final applied = json['applied'];
    final last = json['last_synced_at'];
    return SyncBinding(
      destination: destination is Map
          ? BackupDestination.fromJson(Map<String, Object?>.from(destination))
          : const BackupDestination(),
      epoch: json['epoch'] is String ? json['epoch']! as String : '',
      workspaceId:
          json['workspace_id'] is String ? json['workspace_id']! as String : '',
      workspaceName: json['workspace_name'] is String
          ? json['workspace_name']! as String
          : '',
      uid: json['uid'] is int ? json['uid']! as int : 0,
      nextSeq: json['next_seq'] is int ? json['next_seq']! as int : 1,
      applied: applied is Map
          ? {
              for (final entry in applied.entries)
                if (entry.key is String && entry.value is int)
                  entry.key as String: entry.value as int,
            }
          : const {},
      baseApplied: json['base_applied'] == true,
      paused: json['paused'] == true,
      intervalSeconds: json['interval'] is int
          ? json['interval']! as int
          : defaultSyncIntervalSeconds,
      syncPreferences: json['sync_settings'] != false,
      vaultId: json['vault'] is String ? json['vault']! as String : '',
      resealPending: json['reseal'] == true,
      lastSyncedAt:
          last is int ? DateTime.fromMillisecondsSinceEpoch(last) : null,
      lastError:
          json['last_error'] is String ? json['last_error']! as String : '',
    );
  }

  final BackupDestination destination;
  final String epoch;
  final String workspaceId;
  final String workspaceName;
  final int uid;

  /// The sequence number this computer's next changes go out under.
  final int nextSeq;

  /// For every other computer, the last of its changes merged here.
  final Map<String, int> applied;

  /// Whether the epoch's base has been merged here. A computer that started
  /// the epoch, or joined from its base, has it already.
  final bool baseApplied;

  final bool paused;
  final int intervalSeconds;

  /// Whether this computer's settings follow the workspace. Off, the settings
  /// the others send are carried along but not applied here.
  final bool syncPreferences;

  /// The password record the folder is sealed with; empty for a folder
  /// written before folders were sealed.
  final String vaultId;

  /// The AppFlowy password was changed here, and the folder is still sealed
  /// with the one before: it is sealed again as soon as it can be.
  final bool resealPending;

  final DateTime? lastSyncedAt;

  /// Why the last round did not finish; empty when it did.
  final String lastError;

  bool get isReady => destination.isReady && epoch.isNotEmpty;

  SyncBinding copyWith({
    BackupDestination? destination,
    String? epoch,
    String? workspaceId,
    String? workspaceName,
    int? uid,
    int? nextSeq,
    Map<String, int>? applied,
    bool? baseApplied,
    bool? paused,
    int? intervalSeconds,
    bool? syncPreferences,
    String? vaultId,
    bool? resealPending,
    DateTime? lastSyncedAt,
    String? lastError,
  }) =>
      SyncBinding(
        destination: destination ?? this.destination,
        epoch: epoch ?? this.epoch,
        workspaceId: workspaceId ?? this.workspaceId,
        workspaceName: workspaceName ?? this.workspaceName,
        uid: uid ?? this.uid,
        nextSeq: nextSeq ?? this.nextSeq,
        applied: applied ?? this.applied,
        baseApplied: baseApplied ?? this.baseApplied,
        paused: paused ?? this.paused,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
        syncPreferences: syncPreferences ?? this.syncPreferences,
        vaultId: vaultId ?? this.vaultId,
        resealPending: resealPending ?? this.resealPending,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: lastError ?? this.lastError,
      );

  Map<String, Object?> toJson() => {
        'destination': destination.toJson(),
        'epoch': epoch,
        'workspace_id': workspaceId,
        'workspace_name': workspaceName,
        'uid': uid,
        'next_seq': nextSeq,
        'applied': applied,
        'base_applied': baseApplied,
        'paused': paused,
        'interval': intervalSeconds,
        if (!syncPreferences) 'sync_settings': false,
        if (vaultId.isNotEmpty) 'vault': vaultId,
        if (resealPending) 'reseal': true,
        if (lastSyncedAt != null)
          'last_synced_at': lastSyncedAt!.millisecondsSinceEpoch,
        if (lastError.isNotEmpty) 'last_error': lastError,
      };
}

/// The binding, this computer's name in sync folders, and where the
/// bookkeeping for an epoch is kept.
///
/// ⚠️ Every mutation waits on [ensureLoaded] before it writes, for the same
/// reason backup settings do: a lazily loaded singleton whose writes do not
/// wait will happily persist a view of the world it never read.
class SyncSettings extends ChangeNotifier {
  SyncSettings({KeyValueStorage? storage, Future<Directory> Function()? home})
      : _storageOverride = storage,
        _home = home ?? getApplicationSupportDirectory;

  static final SyncSettings instance = SyncSettings();

  static const bindingKey = 'appflowy_sync_binding';
  static const deviceKey = 'appflowy_sync_device';
  static const pendingStartKey = 'appflowy_sync_pending_start';

  final KeyValueStorage? _storageOverride;
  final Future<Directory> Function() _home;

  SyncBinding? _binding;
  BackupDestination? _pendingStart;
  String _deviceId = '';
  Future<void>? _loading;

  SyncBinding? get binding => _binding;

  /// A folder chosen before any workspace existed here, sealed and waiting
  /// for the first workspace to start syncing into it.
  BackupDestination? get pendingStart => _pendingStart;

  /// This computer's name in every sync folder. Kept for good, so a computer
  /// that reconnects carries on its own numbering rather than starting a new
  /// one beside it.
  String get deviceId => _deviceId;

  KeyValueStorage? get _kv =>
      _storageOverride ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final storage = _kv;
    if (storage == null) {
      _loading = null;
      return;
    }
    try {
      final device = await storage.get(deviceKey);
      if (device != null && SyncFileName.isDeviceId(device)) {
        _deviceId = device;
      } else {
        _deviceId = newSyncDeviceId();
        await storage.set(deviceKey, _deviceId);
      }
      final stored = await storage.get(bindingKey);
      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          final binding =
              SyncBinding.fromJson(Map<String, Object?>.from(decoded));
          _binding = binding.isReady ? binding : null;
        }
      }
      final pending = await storage.get(pendingStartKey);
      if (pending != null && pending.isNotEmpty) {
        final decoded = jsonDecode(pending);
        if (decoded is Map) {
          final destination =
              BackupDestination.fromJson(Map<String, Object?>.from(decoded));
          _pendingStart = destination.isReady ? destination : null;
        }
      }
      notifyListeners();
    } on Object catch (error) {
      _loading = null;
      Log.warn('The sync settings could not be read: $error');
    }
  }

  Future<void> update(SyncBinding? binding) async {
    await ensureLoaded();
    _binding = binding;
    notifyListeners();
    final storage = _kv;
    if (storage == null) {
      return;
    }
    try {
      if (binding == null) {
        await storage.remove(bindingKey);
      } else {
        await storage.set(bindingKey, jsonEncode(binding.toJson()));
      }
    } on Object catch (error) {
      Log.warn('The sync settings could not be stored: $error');
    }
  }

  Future<void> setPendingStart(BackupDestination? destination) async {
    await ensureLoaded();
    _pendingStart = destination;
    final storage = _kv;
    if (storage == null) {
      return;
    }
    try {
      if (destination == null) {
        await storage.remove(pendingStartKey);
      } else {
        await storage.set(pendingStartKey, jsonEncode(destination.toJson()));
      }
    } on Object catch (error) {
      Log.warn('The folder to sync into could not be kept: $error');
    }
  }

  /// Where this computer keeps its bookkeeping for [epoch].
  Future<Directory> epochFolder(String epoch) async {
    final folder = Directory(p.join((await _home()).path, 'sync', epoch));
    await folder.create(recursive: true);
    return folder;
  }

  /// Forgets the bookkeeping of every epoch but [keep].
  Future<void> sweepEpochFolders({String? keep}) async {
    try {
      final root = Directory(p.join((await _home()).path, 'sync'));
      if (!root.existsSync()) {
        return;
      }
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is Directory && p.basename(entity.path) != keep) {
          await entity.delete(recursive: true);
        }
      }
    } on Object catch (error) {
      Log.info('Old sync bookkeeping could not be removed: $error');
    }
  }
}
