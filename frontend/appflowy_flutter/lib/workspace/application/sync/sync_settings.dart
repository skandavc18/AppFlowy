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
import 'package:crypto/crypto.dart';
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
    String id = '',
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
  }) : _id = id;

  factory SyncBinding.fromJson(Map<String, Object?> json) {
    final destination = json['destination'];
    final applied = json['applied'];
    final last = json['last_synced_at'];
    final parsedDestination = destination is Map
        ? BackupDestination.fromJson(Map<String, Object?>.from(destination))
        : const BackupDestination();
    return SyncBinding(
      id: json['id'] is String && (json['id']! as String).isNotEmpty
          ? json['id']! as String
          : idFor(parsedDestination),
      destination: parsedDestination,
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

  /// Stable identifier for [destination], safe to use in folder names.
  static String idFor(BackupDestination destination) {
    final raw = [
      destination.kind.name,
      destination.connectionId,
      destination.folderId,
      destination.localPath,
      destination.server,
    ].join('|');
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
  }

  final String _id;
  String get id => _id.isEmpty ? idFor(destination) : _id;

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

  bool matchesDestination(BackupDestination other) =>
      idFor(destination) == idFor(other);

  SyncBinding copyWith({
    String? id,
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
        id: id ?? _id,
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
        'id': id,
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

/// The bindings, this computer's name in sync folders, background sync
/// preferences, and where the bookkeeping for each epoch is kept.
///
/// Multiple providers (for example Google Drive and Box simultaneously) may be
/// bound to the same workspace at once; each keeps its own epoch and sync state
/// so edits merge across every provider.
class SyncSettings extends ChangeNotifier {
  SyncSettings({KeyValueStorage? storage, Future<Directory> Function()? home})
      : _storageOverride = storage,
        _home = home ?? getApplicationSupportDirectory;

  static final SyncSettings instance = SyncSettings();

  static const bindingKey = 'appflowy_sync_binding';
  static const deviceKey = 'appflowy_sync_device';
  static const pendingStartKey = 'appflowy_sync_pending_start';
  static const backgroundKey = 'appflowy_sync_background';

  final KeyValueStorage? _storageOverride;
  final Future<Directory> Function() _home;

  List<SyncBinding> _bindings = const [];
  BackupDestination? _pendingStart;
  bool _pendingEncrypt = true;
  bool _keepRunningInBackground = true;
  String _deviceId = '';
  Future<void>? _loading;

  /// Primary binding (first configured destination), kept for callers that ask
  /// whether sync is configured at all.
  SyncBinding? get binding => _bindings.isEmpty ? null : _bindings.first;

  /// Every configured sync destination on this computer.
  List<SyncBinding> get bindings => List<SyncBinding>.unmodifiable(_bindings);

  SyncBinding? byId(String id) {
    for (final entry in _bindings) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  SyncBinding? byDestination(BackupDestination destination) {
    for (final entry in _bindings) {
      if (entry.matchesDestination(destination)) {
        return entry;
      }
    }
    return null;
  }

  List<SyncBinding> bindingsFor({
    required String? workspaceId,
    required int? uid,
  }) =>
      workspaceId == null || uid == null
          ? const []
          : [
              for (final entry in _bindings)
                if (entry.workspaceId == workspaceId && entry.uid == uid) entry,
            ];

  /// Whether AppFlowy keeps syncing in the background when the window is closed
  /// on desktop or scheduled via the OS on Android.
  bool get keepRunningInBackground => _keepRunningInBackground;

  /// A folder chosen before any workspace existed here, waiting for the first
  /// workspace to start syncing into it.
  BackupDestination? get pendingStart => _pendingStart;

  /// Whether [pendingStart] should be sealed with the AppFlowy password.
  bool get pendingEncrypt => _pendingEncrypt;

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
        final parsed = <SyncBinding>[];
        if (decoded is Map) {
          final list = decoded['bindings'];
          if (list is List) {
            for (final item in list) {
              if (item is Map) {
                final candidate =
                    SyncBinding.fromJson(Map<String, Object?>.from(item));
                if (candidate.isReady) {
                  parsed.add(candidate);
                }
              }
            }
          } else {
            final single =
                SyncBinding.fromJson(Map<String, Object?>.from(decoded));
            if (single.isReady) {
              parsed.add(single);
            }
          }
        } else if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final candidate =
                  SyncBinding.fromJson(Map<String, Object?>.from(item));
              if (candidate.isReady) {
                parsed.add(candidate);
              }
            }
          }
        }
        _bindings = parsed;
      }
      final bg = await storage.get(backgroundKey);
      if (bg != null && bg.isNotEmpty) {
        _keepRunningInBackground = bg != 'false';
      }
      final pending = await storage.get(pendingStartKey);
      if (pending != null && pending.isNotEmpty) {
        final decoded = jsonDecode(pending);
        if (decoded is Map) {
          final map = Map<String, Object?>.from(decoded);
          final destination = BackupDestination.fromJson(map);
          _pendingStart = destination.isReady ? destination : null;
          _pendingEncrypt = map['encrypt'] != false;
        }
      }
      notifyListeners();
    } on Object catch (error) {
      _loading = null;
      Log.warn('The sync settings could not be read: $error');
    }
  }

  Future<void> _persistBindings() async {
    final storage = _kv;
    if (storage == null) {
      return;
    }
    try {
      if (_bindings.isEmpty) {
        await storage.remove(bindingKey);
      } else if (_bindings.length == 1) {
        await storage.set(bindingKey, jsonEncode(_bindings.single.toJson()));
      } else {
        await storage.set(
          bindingKey,
          jsonEncode({
            'bindings': [for (final item in _bindings) item.toJson()],
          }),
        );
      }
    } on Object catch (error) {
      Log.warn('The sync settings could not be stored: $error');
    }
  }

  /// Adds [next] or updates the existing binding for the same destination.
  Future<void> upsertBinding(SyncBinding next) async {
    await ensureLoaded();
    final updated = List<SyncBinding>.of(_bindings);
    final index = updated.indexWhere(
      (b) => b.id == next.id || b.matchesDestination(next.destination),
    );
    if (index >= 0) {
      updated[index] = next;
    } else {
      updated.add(next);
    }
    _bindings = updated;
    notifyListeners();
    await _persistBindings();
  }

  /// Replaces every binding with [only] (used when joining another workspace).
  Future<void> replaceAllBindings(List<SyncBinding> next) async {
    await ensureLoaded();
    _bindings = List<SyncBinding>.of(next);
    notifyListeners();
    await _persistBindings();
  }

  /// Removes the binding with [id], keeping any other providers intact.
  Future<void> removeBinding(String id) async {
    await ensureLoaded();
    final updated = [
      for (final item in _bindings)
        if (item.id != id) item,
    ];
    if (updated.length == _bindings.length) {
      return;
    }
    _bindings = updated;
    notifyListeners();
    await _persistBindings();
    await sweepEpochFolders();
  }

  Future<void> update(SyncBinding? binding) async {
    if (binding == null) {
      await replaceAllBindings(const []);
      return;
    }
    await upsertBinding(binding);
  }

  Future<void> setKeepRunningInBackground(bool enabled) async {
    await ensureLoaded();
    if (_keepRunningInBackground == enabled) {
      return;
    }
    _keepRunningInBackground = enabled;
    notifyListeners();
    final storage = _kv;
    if (storage != null) {
      try {
        await storage.set(backgroundKey, enabled ? 'true' : 'false');
      } on Object catch (error) {
        Log.warn('Background sync preference could not be stored: $error');
      }
    }
  }

  Future<void> setPendingStart(
    BackupDestination? destination, {
    bool encrypt = true,
  }) async {
    await ensureLoaded();
    _pendingStart = destination;
    _pendingEncrypt = destination == null || encrypt;
    final storage = _kv;
    if (storage == null) {
      return;
    }
    try {
      if (destination == null) {
        await storage.remove(pendingStartKey);
      } else {
        await storage.set(
          pendingStartKey,
          jsonEncode({
            ...destination.toJson(),
            if (!encrypt) 'encrypt': false,
          }),
        );
      }
    } on Object catch (error) {
      Log.warn('The folder to sync into could not be kept: $error');
    }
  }

  /// Clears all local sync bindings and epoch bookkeeping for a fresh start.
  Future<void> resetForFreshStart() async {
    _bindings = const [];
    _pendingStart = null;
    _pendingEncrypt = true;
    _keepRunningInBackground = true;
    _deviceId = '';
    _loading = null;
    final storage = _kv;
    if (storage != null) {
      try {
        await storage.remove(bindingKey);
        await storage.remove(pendingStartKey);
        await storage.remove(deviceKey);
        await storage.remove(backgroundKey);
      } on Object catch (error) {
        Log.warn('Sync settings could not be cleared: $error');
      }
    }
    await sweepEpochFolders();
    notifyListeners();
  }

  String _folderNameFor(String epoch, String bindingId) {
    if (bindingId.isEmpty) {
      return epoch;
    }
    return '${bindingId}_$epoch';
  }

  /// Where this computer keeps its bookkeeping for [epoch] (scoped to
  /// [bindingId] when multiple providers are configured, while seamlessly
  /// reading an existing legacy `<epoch>` folder when unique).
  Future<Directory> epochFolder(String epoch, {String bindingId = ''}) async {
    final syncRoot = p.join((await _home()).path, 'sync');
    final legacy = Directory(p.join(syncRoot, epoch));
    if (bindingId.isEmpty) {
      await legacy.create(recursive: true);
      return legacy;
    }
    final sharedEpoch = _bindings
            .where((b) => b.epoch == epoch && b.id != bindingId)
            .isNotEmpty;
    if (!sharedEpoch && legacy.existsSync()) {
      return legacy;
    }
    final scoped = Directory(p.join(syncRoot, _folderNameFor(epoch, bindingId)));
    await scoped.create(recursive: true);
    return scoped;
  }

  /// Forgets the bookkeeping of every epoch except active bindings and [keep].
  Future<void> sweepEpochFolders({
    String? keep,
    Set<String> keepFolders = const {},
  }) async {
    try {
      final root = Directory(p.join((await _home()).path, 'sync'));
      if (!root.existsSync()) {
        return;
      }
      final retained = <String>{
        if (keep != null && keep.isNotEmpty) keep,
        ...keepFolders,
        for (final b in _bindings) ...[
          b.epoch,
          _folderNameFor(b.epoch, b.id),
        ],
      };
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is Directory &&
            !retained.contains(p.basename(entity.path))) {
          await entity.delete(recursive: true);
        }
      }
    } on Object catch (error) {
      Log.info('Old sync bookkeeping could not be removed: $error');
    }
  }
}
