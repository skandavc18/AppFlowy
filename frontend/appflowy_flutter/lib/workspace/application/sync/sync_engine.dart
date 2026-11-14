// Keeping this workspace the same on every computer that uses one folder.
//
// A round, every few seconds while AppFlowy is open:
//   1. read the folder;
//   2. if the workspace was restored on another computer, stop and say so —
//      merging across a restore would quietly undo it;
//   3. merge every other computer's changes not merged yet, in order;
//   4. send this computer's own changes, if it has any;
//   5. now and then, write a checkpoint and tidy what it makes redundant.
//
// The workspace itself is merged by the backend, page by page, so two computers
// editing at once both keep their work. Attached files are synced by path,
// newest version winning.
//
// Everything in the folder is sealed with a key derived from the AppFlowy
// password. A folder written before folders were sealed keeps syncing pages
// and files until somebody seals it; settings, accounts and keys only ever
// travel sealed.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy/shared/encryption/encryption.dart'
    show defaultKeyIterations;
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/backup/backup_target.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/sync/sync_files.dart';
import 'package:appflowy/workspace/application/sync/sync_pack.dart';
import 'package:appflowy/workspace/application/sync/sync_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:appflowy/workspace/application/sync/sync_remote.dart';
import 'package:appflowy/workspace/application/sync/sync_sealed_remote.dart';
import 'package:appflowy/workspace/application/sync/sync_settings.dart';
import 'package:appflowy/workspace/application/sync/sync_vault.dart';
import 'package:appflowy/workspace/application/sync/workspace_bundle_bridge.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where sync stands.
enum SyncPhase {
  /// Not set up, or set up for a workspace other than the one that is open.
  off,

  /// Up to date, waiting for the next look.
  idle,

  /// A round is running.
  working,

  paused,

  /// The workspace was restored on another computer. Loading the restored
  /// workspace replaces this one; until then nothing is merged.
  restoredElsewhere,

  /// The folder is sealed with an AppFlowy password this computer does not
  /// know: never typed here, or changed on another computer since.
  locked,

  /// The last round did not finish. The next one tries again.
  failed,
}

/// Runtime status of a single sync provider destination.
@immutable
class SyncDestinationStatus {
  const SyncDestinationStatus({
    this.phase = SyncPhase.idle,
    this.activity = '',
    this.needsSignIn = false,
    this.lockedBy,
    this.passwordChangedElsewhere = false,
  });

  final SyncPhase phase;
  final String activity;
  final bool needsSignIn;
  final SyncVault? lockedBy;
  final bool passwordChangedElsewhere;
}

/// One computer or phone syncing through the folder.
@immutable
class SyncDeviceSummary {
  const SyncDeviceSummary({
    required this.id,
    required this.name,
    required this.isThisComputer,
    this.platform = '',
    this.lastSeen,
    this.joinedAt,
    this.waiting = false,
  });

  static SyncDeviceSummary? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) {
      return null;
    }
    DateTime? time(Object? value) => value is int && value > 0
        ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
        : null;
    return SyncDeviceSummary(
      id: id,
      name: name,
      isThisComputer: json['this'] == true,
      platform: json['platform'] is String ? json['platform']! as String : '',
      lastSeen: time(json['last_seen']),
      joinedAt: time(json['joined_at']),
      waiting: json['waiting'] == true,
    );
  }

  final String id;
  final String name;
  final String platform;

  /// When it last sent anything to the folder.
  final DateTime? lastSeen;

  /// When it first took part.
  final DateTime? joinedAt;
  final bool isThisComputer;

  /// It synced before the folder was sealed again, and has not caught up
  /// since: it needs the AppFlowy password, or has not been opened.
  final bool waiting;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (isThisComputer) 'this': true,
        if (platform.isNotEmpty) 'platform': platform,
        if (lastSeen != null) 'last_seen': lastSeen!.millisecondsSinceEpoch,
        if (joinedAt != null) 'joined_at': joinedAt!.millisecondsSinceEpoch,
        if (waiting) 'waiting': true,
      };
}

enum SyncFolderState {
  /// Nothing synced there yet.
  empty,

  /// The workspace that is open here.
  thisWorkspace,

  /// Another workspace. Joining replaces the one here.
  otherWorkspace,

  /// Written by a newer version of AppFlowy, or not readable.
  unreadable,

  /// Holds a workspace sealed with an AppFlowy password this computer does
  /// not know.
  locked,
}

/// What a folder holds, read before anything is changed.
@immutable
class SyncFolderInspection {
  const SyncFolderInspection({
    required this.state,
    this.epoch,
    this.devices = const [],
    this.vault,
    this.key,
    this.password,
  });

  final SyncFolderState state;
  final SyncEpochInfo? epoch;
  final List<SyncDeviceSummary> devices;

  /// The password record of a sealed folder; null for one never sealed.
  final SyncVault? vault;

  /// The folder's key, once its password is known here.
  final SyncKey? key;

  /// The password that was typed to open the folder, which becomes this
  /// computer's AppFlowy password once the folder is joined.
  final String? password;

  /// Whether the folder is sealed and its password still has to be typed.
  bool get needsPassword => vault != null && key == null;
}

/// Raised when sync cannot do what was asked.
class SyncError implements Exception {
  const SyncError(this.detail);

  final String detail;

  @override
  String toString() => detail;
}

/// Says what went wrong in words somebody can act on.
String describeSyncError(Object error) => switch (error) {
      SyncError(:final detail) => detail,
      BackupTargetError(:final detail) => detail,
      WorkspaceBundleError(:final detail) => detail,
      SyncPackError(:final detail) => detail,
      SyncSealError() =>
        'Something in the sync folder could not be opened with the AppFlowy '
            'password. It may have been changed by something other than '
            'AppFlowy.',
      ProviderFailure(:final status) => switch (status) {
          ProviderStatus.offline => 'The sync folder cannot be reached.',
          ProviderStatus.authExpired =>
            'The account that holds the sync folder needs signing in again.',
          ProviderStatus.permissionDenied =>
            'The account can no longer write to the sync folder.',
          ProviderStatus.rateLimited =>
            'The service asked AppFlowy to slow down. Sync will try again.',
          ProviderStatus.notFound => 'The sync folder is gone.',
          _ => 'The sync folder could not be used.',
        },
      FileSystemException(:final message, :final path) =>
        path == null ? message : '$message ($path)',
      _ => error.toString(),
    };

class WorkspaceSyncEngine extends ChangeNotifier {
  WorkspaceSyncEngine({
    WorkspaceBundleBridge? bridge,
    SyncSettings? settings,
    Future<SyncRemote> Function(BackupDestination destination)? openRemote,
    Future<String> Function()? dataPath,
    Future<Directory> Function()? scratch,
    Future<void> Function()? restart,
    Future<void> Function(String reason)? safetyCopy,
    String Function()? deviceName,
    DateTime Function()? clock,
    SyncedPreferencesSource? preferences,
    SyncKeyKeeper? keys,
    AppPasswordSource? passwords,
    this.checkpointAfter = 64,
    this.checkpointQuietPeriod = const Duration(minutes: 10),
    this.vaultIterations = defaultKeyIterations,
  })  : _bridge = bridge ?? const RustWorkspaceBundleBridge(),
        _keys = keys ?? SecretStoreKeyKeeper(),
        _passwords = passwords ?? AppPassword.instance,
        _settingsOverride = settings,
        _openRemote = openRemote ?? openSyncRemote,
        _dataPath = dataPath,
        _scratch = scratch ?? _defaultScratch,
        _restart = restart,
        _safetyCopy = safetyCopy,
        _deviceName = deviceName ?? _defaultDeviceName,
        _clock = clock ?? DateTime.now,
        _preferences = preferences;

  static final WorkspaceSyncEngine instance = WorkspaceSyncEngine();

  /// Changes are folded into a checkpoint once there are this many in the
  /// folder.
  final int checkpointAfter;

  /// Nobody writes a checkpoint within this long of the last one.
  final Duration checkpointQuietPeriod;

  /// How hard a new password record is made to guess.
  final int vaultIterations;

  /// An attached file no checkpoint names is removed after this long.
  static const Duration blobGracePeriod = Duration(days: 7);

  /// A single file larger than this is not synced.
  static const int maximumFileBytes = 512 * 1024 * 1024;

  final WorkspaceBundleBridge _bridge;
  final SyncSettings? _settingsOverride;
  final Future<SyncRemote> Function(BackupDestination destination) _openRemote;
  Future<String> Function()? _dataPath;
  final Future<Directory> Function() _scratch;
  Future<void> Function()? _restart;
  Future<void> Function(String reason)? _safetyCopy;
  final String Function() _deviceName;
  final DateTime Function() _clock;
  SyncedPreferencesSource? _preferences;
  final SyncKeyKeeper _keys;
  final AppPasswordSource _passwords;

  // Keys and vaults unlocked in memory, indexed by vaultId.
  final Map<String, SyncKey> _keysInMemory = {};
  final Map<String, SyncVault> _vaultsById = {};

  // Per-binding runtime status and locked vault records.
  final Map<String, SyncDestinationStatus> _destinationStatuses = {};
  final Map<String, SyncVault> _lockedByBinding = {};

  // The most recent key/locked record for single-provider compatibility.
  SyncKey? _key;
  SyncVault? _lockedBy;

  final Map<String, SyncVault> _vaults = {};

  // The AppFlowy password each record was last tried with, so a password that
  // does not open it is not tried again every round.
  final Map<String, String> _triedPasswords = {};

  final Map<String, SyncEpochInfo> _epochInfos = {};

  // What the folder last said about accounts, passwords and keys.
  bool _credentialsOn = true;

  // Switches turned here, sent with the next changes.
  final List<SyncPreferenceRecord> _outbox = [];

  // This computer's settings as last read in this round.
  Map<String, String>? _preferencesNow;

  /// Tells somebody about something that happened while nobody was looking.
  void Function(String message, {bool isError})? notify;

  /// Asked when another computer restored the workspace, so the person here
  /// can be offered the restored workspace straight away.
  void Function(SyncEpochInfo restored)? onRestoredElsewhere;
  Future<void> Function(Set<String> paths)? _onFilesApplied;

  SyncPhase _phase = SyncPhase.off;
  String _activity = '';
  bool _needsSignIn = false;
  bool _inBackground = false;
  List<SyncDeviceSummary> _devices = const [];
  final Map<String, List<SyncDeviceSummary>> _devicesByBinding = {};
  SyncEpochInfo? _restoredElsewhere;
  String? _restoredBindingId;
  WorkspaceRestoreOutcome? _lastRestore;

  String? _workspaceId;
  int? _uid;
  String _workspaceName = '';
  bool _isLocalWorkspace = false;

  Timer? _timer;
  bool _running = false;
  bool _again = false;
  bool _suspended = false;
  final Set<Future<void>> _attachments = {};

  // Completes when the rounds running now, and any asked for meanwhile, are
  // done.
  Completer<void>? _rounds;
  bool _busyWithSetup = false;
  BackupDestination? _settingUpDestination;

  final Map<String, SyncCheckpointInfo> _checkpointInfos = {};
  final Map<String, SyncDeviceInfo> _deviceInfos = {};
  final Expando<Map<String, RemoteSyncFile>> _remoteBlobs = Expando();

  // Since when changes of [_unreachable] have been missing from a folder, per
  // binding id.
  final Map<String, DateTime> _unreachableSinceByBinding = {};
  final Map<String, Set<String>> _unreachableByBinding = {};

  SyncSettings get settings => _settingsOverride ?? SyncSettings.instance;

  /// All destinations bound to the currently open workspace.
  List<SyncBinding> get boundBindings =>
      settings.bindingsFor(workspaceId: _workspaceId, uid: _uid);

  /// Primary binding: the first destination bound to the open workspace, or the
  /// first configured destination overall when another workspace is open.
  SyncBinding? get binding {
    final bound = boundBindings;
    if (bound.isNotEmpty) {
      return bound.first;
    }
    return settings.binding;
  }

  /// Destination currently being initialized in the background (before its
  /// first epoch is published).
  BackupDestination? get settingUpDestination => _settingUpDestination;

  /// Per-destination runtime status.
  SyncDestinationStatus statusOf(String bindingId) {
    final b = settings.byId(bindingId);
    if (b != null && b.paused) {
      return const SyncDestinationStatus(phase: SyncPhase.paused);
    }
    return _destinationStatuses[bindingId] ??
        SyncDestinationStatus(
          phase: b == null
              ? SyncPhase.off
              : (b.lastError.isEmpty ? SyncPhase.idle : SyncPhase.failed),
          activity: b?.lastError ?? '',
        );
  }

  SyncPhase get phase => _phase;

  /// What a running round is doing, for the interface.
  String get activity => _activity;

  /// Whether any bound destination needs re-authentication.
  bool get needsSignIn =>
      (_phase == SyncPhase.failed && _needsSignIn) ||
      boundBindings.any((b) => statusOf(b.id).needsSignIn);

  /// Whether every bound destination for this workspace is currently paused.
  bool get isAllPaused {
    final bound = boundBindings;
    return bound.isNotEmpty && bound.every((b) => b.paused);
  }

  List<SyncDeviceSummary> get devices => _devices;

  /// The restore waiting on another computer, while [phase] says so.
  SyncEpochInfo? get restoredElsewhere => _restoredElsewhere;

  /// Whether any bound folder is sealed with the AppFlowy password.
  bool get isSealed => boundBindings.isNotEmpty
      ? boundBindings.any((b) => b.vaultId.isNotEmpty)
      : (binding?.vaultId.isNotEmpty ?? false);

  /// The record whose password has to be typed before sync can go on.
  SyncVault? get lockedBy =>
      _lockedBy ??
      (_lockedByBinding.values.isEmpty ? null : _lockedByBinding.values.first);

  /// Whether a folder is locked because the AppFlowy password was changed on
  /// another computer, rather than never typed here.
  bool get passwordChangedElsewhere {
    for (final b in boundBindings) {
      final locked = _lockedByBinding[b.id];
      if (locked != null && b.vaultId.isNotEmpty && locked.id != b.vaultId) {
        return true;
      }
    }
    final locked = _lockedBy;
    final vaultId = binding?.vaultId ?? '';
    return locked != null && vaultId.isNotEmpty && locked.id != vaultId;
  }

  /// Whether any bound folder is still sealed with an old AppFlowy password
  /// waiting to be sealed again.
  bool get needsResealing => boundBindings.isNotEmpty
      ? boundBindings.any((b) => b.vaultId.isNotEmpty && b.resealPending)
      : (isSealed && (binding?.resealPending ?? false));

  /// Whether accounts, passwords and keys travel through the folder.
  bool get credentialsSynced => isSealed && _credentialsOn;

  /// How the last restore at start-up went, if there was one.
  WorkspaceRestoreOutcome? get lastRestore => _lastRestore;

  bool get isBusy => _running || _busyWithSetup;
  bool get isSuspended => _suspended;
  bool get inBackground => _inBackground;

  /// Whether the workspace that is open is a local one. A workspace on
  /// AppFlowy Cloud is already kept in step by the cloud.
  bool get canSyncThisWorkspace => _isLocalWorkspace && _workspaceId != null;

  /// Whether sync is set up for the workspace that is open.
  bool get isBoundHere => boundBindings.isNotEmpty;

  String get workspaceName => _workspaceName;

  /// What this computer calls itself in sync folders.
  String get thisDeviceName => _deviceName();

  /// Wires in what only the running application can provide.
  void configure({
    Future<String> Function()? dataPath,
    Future<void> Function()? restart,
    Future<void> Function(String reason)? safetyCopy,
    SyncedPreferencesSource? preferences,
    Future<void> Function(Set<String> paths)? onFilesApplied,
  }) {
    _dataPath = dataPath ?? _dataPath;
    _restart = restart ?? _restart;
    _safetyCopy = safetyCopy ?? _safetyCopy;
    _preferences = preferences ?? _preferences;
    _onFilesApplied = onFilesApplied ?? _onFilesApplied;
  }

  /// Where settings are read and put, or nowhere while this computer does
  /// not sync them: what the others send is then carried, not applied.
  ///
  /// Nothing travels through a folder that is not sealed, and accounts,
  /// passwords and keys only while the folder says they do.
  SyncedPreferencesSource _preferencesFor(
    SyncBinding? binding, {
    required bool sealed,
    required bool credentials,
  }) =>
      _preferencesWhen(
        on: binding?.syncPreferences ?? true,
        sealed: sealed,
        credentials: credentials,
      );

  SyncedPreferencesSource _preferencesWhen({
    required bool on,
    required bool sealed,
    required bool credentials,
  }) {
    final source = _preferences;
    if (source == null || !on || !sealed) {
      return const InertPreferencesSource();
    }
    return GatedPreferences(source, credentials: credentials);
  }

  Future<File> _preferencesIndexFile(
    String epoch, {
    String bindingId = '',
  }) async =>
      File(
        p.join(
          (await settings.epochFolder(epoch, bindingId: bindingId)).path,
          'prefs.json',
        ),
      );

  /// The settings changed here since they were last synced. None when they
  /// cannot be read this time: nothing is noted, so they go out next round.
  Future<List<SyncPreferenceRecord>> _scanPreferences(
    SyncPreferencesIndex index, {
    required bool on,
    required bool sealed,
  }) async {
    final source = _preferencesWhen(
      on: on,
      sealed: sealed,
      credentials: index.credentialsOn,
    );
    try {
      final current = _preferencesNow = await source.read();
      await adoptCarriedPreferences(
        source: source,
        index: index,
        current: current,
      );
      return [
        ...scanSyncedPreferences(
          current: current,
          index: index,
          handles: source.handles,
          now: _clock().millisecondsSinceEpoch,
          unreadable: source.unreadable,
        ),
        // Switches turned here go out with the changes.
        if (sealed)
          for (final record in _outbox)
            if (record.isLaterThan(index.entries[record.key])) record,
      ];
    } on Object catch (error) {
      _preferencesNow = null;
      Log.warn('Settings could not be read, so none go out this time: $error');
      return const [];
    }
  }

  /// Merges [records] that arrived from the folder into the settings here.
  ///
  /// When the settings here cannot be read, this fails, and with it the
  /// round: what arrived is merged again next time rather than taken for
  /// something this computer already had.
  Future<void> _takePreferences(
    List<SyncPreferenceRecord> records,
    SyncPreferencesIndex index,
    SyncBinding? binding, {
    required bool sealed,
  }) async {
    if (records.isEmpty) {
      return;
    }
    // Sync's own switches first: they decide what else is taken.
    for (final record in records) {
      if (isSyncSwitchKey(record.key)) {
        index.note(record);
      }
    }
    final credentialsOn = index.credentialsOn;
    if (!credentialsOn) {
      // Taken out of the folder: each computer keeps what it has, and every
      // one of them counts as new should they travel again.
      index.dropCredentials();
    }
    _credentialsOn = credentialsOn;
    final rest = [
      for (final record in records)
        if (!isSyncSwitchKey(record.key) &&
            (credentialsOn || !isCredentialKey(record.key)))
          record,
    ];
    if (rest.isEmpty) {
      return;
    }
    final source = _preferencesFor(
      binding,
      sealed: sealed,
      credentials: credentialsOn,
    );
    final current = _preferencesNow ??= await source.read();
    final changed = await applyRemotePreferences(
      source: source,
      index: index,
      records: rest,
      current: current,
    );
    if (changed > 0) {
      Log.info('Synced $changed settings from another computer.');
    }
  }

  // --- Following the open workspace -----------------------------------------

  /// Starts syncing the workspace that was just opened, if sync is set up for
  /// it.
  Future<void> attach({
    required String workspaceId,
    required int uid,
    required String workspaceName,
    required bool isLocalWorkspace,
  }) async {
    if (_suspended && _uid != null) return;
    _suspended = false;
    final next = _attach(
      workspaceId: workspaceId,
      uid: uid,
      workspaceName: workspaceName,
      isLocalWorkspace: isLocalWorkspace,
    );
    _attachments.add(next);
    try {
      await next;
    } finally {
      _attachments.remove(next);
    }
  }

  Future<void> _attach({
    required String workspaceId,
    required int uid,
    required String workspaceName,
    required bool isLocalWorkspace,
  }) async {
    _workspaceId = workspaceId;
    _uid = uid;
    _workspaceName = workspaceName;
    _isLocalWorkspace = isLocalWorkspace;
    _restoredElsewhere = null;
    _restoredBindingId = null;
    _unreachableSinceByBinding.clear();
    _unreachableByBinding.clear();
    await settings.ensureLoaded();
    for (final b in boundBindings) {
      final vaultId = b.vaultId;
      if (vaultId.isNotEmpty && !_keysInMemory.containsKey(vaultId)) {
        final stored = await _keys.read(vaultId);
        if (stored != null) {
          _keysInMemory[vaultId] = stored;
          _key ??= stored;
        }
      }
    }
    if (isBoundHere) {
      await _loadDevices();
    }
    final pending = settings.pendingStart;
    if (pending != null &&
        settings.byDestination(pending) == null &&
        canSyncThisWorkspace) {
      unawaited(
        _startPending(pending, encrypt: settings.pendingEncrypt),
      );
    }

    final outcome = await _bridge.takeRestoreOutcome();
    if (outcome != null) {
      _lastRestore = outcome;
      notify?.call(
        outcome.succeeded
            ? 'Restored "${outcome.workspaceName}".'
            : 'The workspace could not be restored: ${outcome.detail}',
        isError: !outcome.succeeded,
      );
    }
    _schedule();
  }

  /// Stops looking, for instance while the application restarts.
  void detach() {
    _timer?.cancel();
    _timer = null;
  }

  /// Adjusts the background polling cadence when the desktop window hides to or
  /// returns from the notification area.
  void setBackgroundMode(bool inBackground) {
    if (_inBackground == inBackground) {
      return;
    }
    _inBackground = inBackground;
    _schedule(runImmediately: !inBackground);
  }

  Future<void> suspendForSignOut() async {
    _suspended = true;
    detach();
    _again = false;
    await Future.wait(_attachments.toList());
    await _rounds?.future;
    await _round();
  }

  void resumeAfterSignOutFailure() {
    _suspended = false;
    _schedule();
  }

  Future<void> forgetAccount() async {
    final matching = [
      for (final b in settings.bindings)
        if (b.uid == _uid) b,
    ];
    for (final current in matching) {
      final folder = await settings.epochFolder(
        current.epoch,
        bindingId: current.id,
      );
      for (final name in ['files.json', 'prefs.json', 'collab_state.json']) {
        final file = File(p.join(folder.path, name));
        if (await file.exists()) await file.delete();
      }
      await settings.upsertBinding(
        current.copyWith(applied: const {}, baseApplied: false),
      );
    }
    _uid = null;
    _workspaceId = null;
    _workspaceName = '';
    _key = null;
    _keysInMemory.clear();
    _vaultsById.clear();
    _lockedBy = null;
    _lockedByBinding.clear();
    _destinationStatuses.clear();
    _devicesByBinding.clear();
    _preferencesNow = null;
    _preferences = null;
    _onFilesApplied = null;
    _set(SyncPhase.off);
  }

  void _schedule({bool runImmediately = true}) {
    _timer?.cancel();
    _timer = null;
    if (_suspended) return;
    final bound = boundBindings;
    if (bound.isEmpty) {
      if (_busyWithSetup) {
        _set(SyncPhase.working, activity: _activity);
      } else {
        _set(SyncPhase.off);
      }
      return;
    }
    final active = [for (final b in bound) if (!b.paused) b];
    if (active.isEmpty) {
      _set(SyncPhase.paused);
      return;
    }
    final anyError = active.any((b) => b.lastError.isNotEmpty);
    final allError = active.every((b) => b.lastError.isNotEmpty);
    if (!_running && !_busyWithSetup) {
      _set(allError && anyError ? SyncPhase.failed : SyncPhase.idle);
    }
    final shortest = active
        .map((b) => b.intervalSeconds)
        .reduce(min);
    final seconds = _inBackground ? max(60, shortest) : max(5, shortest);
    _timer = Timer.periodic(
      Duration(seconds: seconds),
      (_) => unawaited(syncNow()),
    );
    if (runImmediately) {
      unawaited(syncNow());
    }
  }

  void _set(SyncPhase phase, {String activity = ''}) {
    _phase = phase;
    _activity = activity;
    notifyListeners();
  }

  void _report(String activity) {
    _activity = activity;
    notifyListeners();
  }

  // --- A round --------------------------------------------------------------

  /// Runs a round now, or right after the one that is running, and returns
  /// once a round that started after this was asked for has finished.
  Future<void> syncNow() {
    if (_suspended || _busyWithSetup) {
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
        } while (_again && !_suspended);
      } finally {
        _running = false;
        rounds.complete();
      }
    }());
    return rounds.future;
  }

  Future<void> _round() async {
    final bound = boundBindings;
    final active = [
      for (final b in bound)
        if (!b.paused) b,
    ];
    if (active.isEmpty || _restoredElsewhere != null) {
      return;
    }
    _set(SyncPhase.working, activity: 'Looking for changes…');
    _preferencesNow = null;

    final sessions = <_ProviderSession>[];
    var anyLocked = false;
    var anyFailed = false;
    var anySignInNeeded = false;
    var lastErrorDetail = '';

    try {
      // Phase 1: Pull from every active provider so incoming edits from any
      // provider merge into the workspace before Phase 2 pushes out to all.
      for (final candidate in active) {
        _destinationStatuses[candidate.id] = const SyncDestinationStatus(
          phase: SyncPhase.working,
          activity: 'Looking for changes…',
        );
        notifyListeners();
        SyncRemote? plain;
        var handedOff = false;
        try {
          plain = await _openRemote(candidate.destination);
          await plain.ensureReady();
          final listing = SyncListing.of(await plain.list());
          final current = listing.current;
          if (current == null) {
            throw const SyncError(
              'The sync folder no longer holds this workspace.',
            );
          }
          final key =
              await _keyFor(plain, current, bindingId: candidate.id);
          final lockedVault = _lockedByBinding[candidate.id];
          if (lockedVault != null) {
            anyLocked = true;
            _destinationStatuses[candidate.id] = SyncDestinationStatus(
              phase: SyncPhase.locked,
              lockedBy: lockedVault,
              passwordChangedElsewhere: candidate.vaultId.isNotEmpty &&
                  lockedVault.id != candidate.vaultId,
            );
            continue;
          }
          if (key == null && candidate.vaultId.isNotEmpty) {
            throw const SyncError(
              'The sync folder is no longer sealed with the AppFlowy password. '
              'Set sync up again.',
            );
          }
          final remote = SealedSyncRemote(plain, key, scratch: _scratchFolder);
          var next = candidate;
          if (current.id != candidate.epoch) {
            if (current.id.compareTo(candidate.epoch) < 0) {
              throw const SyncError(
                'The sync folder lost the start of this workspace. Set sync up '
                'again.',
              );
            }
            final info = await _readEpochInfo(remote, current);
            if (info.reason != SyncEpochReason.continued) {
              await _restoredOnAnotherComputer(
                plain,
                listing,
                candidate,
                info,
              );
              return;
            }
            next = await _follow(current, info, candidate, key);
          }

          await _announceDevice(remote, current);
          await _refreshDevices(remote, current, bindingId: next.id);
          next = await _pull(remote, listing, current, next);
          sessions.add(
            _ProviderSession(
              original: candidate,
              currentBinding: next,
              plain: plain,
              remote: remote,
              epoch: current,
            ),
          );
          handedOff = true;
        } on Object catch (error, stackTrace) {
          final detail = describeSyncError(error);
          final signIn =
              error is ProviderFailure && error.status.needsReconnect;
          anyFailed = true;
          if (signIn) anySignInNeeded = true;
          lastErrorDetail = detail;
          Log.warn(
            'A sync pull from ${candidate.destination.kind.name} did not finish: '
            '$detail\n$stackTrace',
          );
          final latest = settings.byId(candidate.id);
          if (latest != null && latest.epoch == candidate.epoch) {
            await settings.upsertBinding(latest.copyWith(lastError: detail));
          }
          _destinationStatuses[candidate.id] = SyncDestinationStatus(
            phase: SyncPhase.failed,
            activity: detail,
            needsSignIn: signIn,
          );
        } finally {
          if (!handedOff) {
            plain?.dispose();
          }
        }
      }

      // Phase 2: Push local changes (plus anything merged from other providers
      // in Phase 1) out to every connected provider.
      _preferencesNow = null;
      for (final session in sessions) {
        try {
          var next = await _push(
            session.remote,
            session.epoch,
            session.currentBinding,
          );
          next = await _maybeCheckpoint(session.remote, session.epoch, next);
          final missingSince =
              _unreachableSinceByBinding[session.original.id];
          final unreachable =
              _unreachableByBinding[session.original.id] ?? const {};
          if (missingSince != null &&
              _clock().difference(missingSince) >= checkpointQuietPeriod) {
            throw SyncError(
              'Changes from ${unreachable.map(_nameOf).join(', ')} are missing '
              'from the sync folder, so this computer cannot catch up with them. '
              'On a computer that has them, stop syncing and set sync up again '
              'in an empty folder, then join it here.',
            );
          }
          await settings.upsertBinding(
            next.copyWith(lastSyncedAt: _clock(), lastError: ''),
          );
          _destinationStatuses[session.original.id] =
              const SyncDestinationStatus();
        } on Object catch (error, stackTrace) {
          final detail = describeSyncError(error);
          final signIn =
              error is ProviderFailure && error.status.needsReconnect;
          anyFailed = true;
          if (signIn) anySignInNeeded = true;
          lastErrorDetail = detail;
          Log.warn(
            'A sync push to ${session.original.destination.kind.name} did not '
            'finish: $detail\n$stackTrace',
          );
          final latest = settings.byId(session.original.id);
          if (latest != null && latest.epoch == session.currentBinding.epoch) {
            await settings.upsertBinding(latest.copyWith(lastError: detail));
          }
          _destinationStatuses[session.original.id] = SyncDestinationStatus(
            phase: SyncPhase.failed,
            activity: detail,
            needsSignIn: signIn,
          );
        }
      }

      // Prune outbox switches only once every sealed bound provider has noted
      // them, so a second provider still receives a switch turned here.
      if (_outbox.isNotEmpty) {
        await _pruneOutboxAcrossSealedBindings();
      }
    } finally {
      for (final session in sessions) {
        session.plain.dispose();
      }
    }

    if (_restoredElsewhere != null) {
      return;
    }
    _needsSignIn = anySignInNeeded;
    if (anyLocked && sessions.isEmpty) {
      _set(SyncPhase.locked);
    } else if (anyFailed && (sessions.isEmpty || active.length == 1)) {
      _set(SyncPhase.failed, activity: lastErrorDetail);
    } else if (anyLocked) {
      _set(SyncPhase.locked);
    } else if (anyFailed) {
      _set(SyncPhase.failed, activity: lastErrorDetail);
    } else {
      _set(SyncPhase.idle);
    }
  }

  Future<void> _pruneOutboxAcrossSealedBindings() async {
    final sealedBindings = [
      for (final b in boundBindings)
        if (b.vaultId.isNotEmpty) b,
    ];
    if (sealedBindings.isEmpty) {
      _outbox.clear();
      return;
    }
    final indices = <SyncPreferencesIndex>[];
    for (final b in sealedBindings) {
      final key = await _keyOf(b);
      if (key == null) {
        return;
      }
      indices.add(
        await SyncPreferencesIndex.load(
          await _preferencesIndexFile(b.epoch, bindingId: b.id),
          key: key,
        ),
      );
    }
    _outbox.removeWhere(
      (record) => indices.every(
        (prefs) => !record.isLaterThan(prefs.entries[record.key]),
      ),
    );
  }

  /// The key [epoch] is sealed with, as this computer keeps it or as the
  /// AppFlowy password makes it; null for an epoch never sealed. Leaves
  /// [_lockedBy] set when this computer has no password that opens it.
  Future<SyncKey?> _keyFor(
    SyncRemote remote,
    SyncEpochListing epoch, {
    String? bindingId,
  }) async {
    final file = epoch.vault;
    if (file == null) {
      if (bindingId != null) {
        _lockedByBinding.remove(bindingId);
      }
      _lockedBy = _lockedByBinding.values.isEmpty
          ? null
          : _lockedByBinding.values.first;
      return null;
    }
    final vault = await _readVault(remote, file);
    final key = await _openVault(vault);
    if (bindingId != null) {
      if (key == null) {
        _lockedByBinding[bindingId] = vault;
      } else {
        _lockedByBinding.remove(bindingId);
      }
    }
    _lockedBy = key == null
        ? vault
        : (_lockedByBinding.values.isEmpty
            ? null
            : _lockedByBinding.values.first);
    if (key != null) {
      _keysInMemory[vault.id] = key;
      _vaultsById[vault.id] = vault;
      _key = key;
    }
    return key;
  }

  /// The key for [vault]: the one in memory, the one kept in the keyring, or
  /// the one the AppFlowy password makes.
  Future<SyncKey?> _openVault(SyncVault vault) async {
    final inMemory = _keysInMemory[vault.id] ?? _key;
    if (inMemory != null && vault.accepts(inMemory)) {
      _keysInMemory[vault.id] = inMemory;
      return inMemory;
    }
    final kept = await _keys.read(vault.id);
    if (kept != null && vault.accepts(kept)) {
      _keysInMemory[vault.id] = kept;
      return kept;
    }
    final password = await _passwords.current();
    if (password == null || _triedPasswords[vault.id] == password) {
      return null;
    }
    _triedPasswords[vault.id] = password;
    final key = await vault.unlock(password);
    if (key != null) {
      _keysInMemory[vault.id] = key;
      await _keys.write(key);
    }
    return key;
  }

  Future<SyncVault> _readVault(SyncRemote remote, RemoteSyncFile file) async {
    final cacheKey = '${file.id}@${file.modifiedAt?.millisecondsSinceEpoch}';
    final known = _vaults[cacheKey];
    if (known != null) {
      return known;
    }
    final vault = SyncVault.tryParse(await remote.readText(file));
    if (vault == null) {
      throw const SyncError(
        'The sync folder was sealed by a newer version of AppFlowy.',
      );
    }
    return _vaults[cacheKey] = vault;
  }

  /// The key [binding]'s own epoch is sealed with, when this computer has it.
  Future<SyncKey?> _keyOf(SyncBinding binding) async {
    final vaultId = binding.vaultId;
    if (vaultId.isEmpty) {
      return null;
    }
    final held = _keysInMemory[vaultId] ?? _key;
    if (held != null && held.vaultId == vaultId) {
      return held;
    }
    final kept = await _keys.read(vaultId);
    if (kept != null) {
      _keysInMemory[vaultId] = kept;
    }
    return kept;
  }

  /// Carries on in [current], an epoch another computer started for the same
  /// workspace — to seal the folder, or to take something out of it.
  ///
  /// Nothing is replaced: the epoch's whole state is merged into the workspace
  /// here, and everything this computer has goes out again, so what it had not
  /// sent yet reaches the others too.
  Future<SyncBinding> _follow(
    SyncEpochListing current,
    SyncEpochInfo info,
    SyncBinding binding,
    SyncKey? key,
  ) async {
    if (info.workspaceId != binding.workspaceId) {
      throw const SyncError('The sync folder now holds another workspace.');
    }
    _report('Catching up…');
    // What the settings were when last synced, so a change made here and not
    // sent yet still counts as one.
    final carried = await SyncPreferencesIndex.load(
      await _preferencesIndexFile(binding.epoch, bindingId: binding.id),
      key: await _keyOf(binding),
    );
    final next = SyncBinding(
      id: binding.id,
      destination: binding.destination,
      epoch: current.id,
      workspaceId: binding.workspaceId,
      workspaceName: info.workspaceName.isEmpty
          ? binding.workspaceName
          : info.workspaceName,
      uid: binding.uid,
      nextSeq: current.lastSeqOf(settings.deviceId) + 1,
      paused: binding.paused,
      intervalSeconds: binding.intervalSeconds,
      syncPreferences: binding.syncPreferences,
      vaultId: key?.vaultId ?? '',
    );
    await carried.save(
      await _preferencesIndexFile(current.id, bindingId: next.id),
      key: key,
    );
    await settings.upsertBinding(next);
    await settings.sweepEpochFolders(keep: current.id);
    _checkpointInfos.clear();
    return next;
  }

  /// Another computer restored the workspace. What was typed here and not yet
  /// sent goes into the old epoch first, so it is at least in the folder, and
  /// then nothing more is merged until the restored workspace is loaded.
  Future<void> _restoredOnAnotherComputer(
    SyncRemote plain,
    SyncListing listing,
    SyncBinding binding,
    SyncEpochInfo info,
  ) async {
    final mine = listing.epochs[binding.epoch];
    final mineKey = await _keyOf(binding);
    // A sealed epoch whose key is not here gets nothing rather than something
    // in the clear.
    if (mine != null && (binding.vaultId.isEmpty || mineKey != null)) {
      try {
        await _push(
          SealedSyncRemote(plain, mineKey, scratch: _scratchFolder),
          mine,
          binding,
        );
      } on Object catch (error) {
        Log.warn(
          'Changes made before a restore elsewhere were not sent: $error',
        );
      }
    }
    _restoredElsewhere = info;
    _restoredBindingId = binding.id;
    _set(SyncPhase.restoredElsewhere);
    final ask = onRestoredElsewhere;
    if (ask != null) {
      ask(info);
    } else {
      notify?.call(
        '"${info.workspaceName}" was restored on ${info.deviceName}. '
        'Open Settings › Backup & sync to load it.',
      );
    }
  }

  // --- Taking changes in ----------------------------------------------------

  Future<SyncBinding> _pull(
    SealedSyncRemote remote,
    SyncListing listing,
    SyncEpochListing epoch,
    SyncBinding binding,
  ) async {
    final folder = await settings.epochFolder(
      epoch.id,
      bindingId: binding.id,
    );
    final state = File(p.join(folder.path, 'collab_state.json'));
    final indexFile = File(p.join(folder.path, 'files.json'));
    final index = await SyncFileIndex.load(indexFile);
    final prefsFile =
        await _preferencesIndexFile(epoch.id, bindingId: binding.id);
    final prefs = await SyncPreferencesIndex.load(prefsFile, key: remote.key);
    _credentialsOn = prefs.credentialsOn;
    var next = binding;

    if (!next.baseApplied) {
      next = await _catchUp(remote, epoch, next, state, index, prefs);
      await index.save(indexFile);
      await prefs.save(prefsFile, key: remote.key);
    }

    final infos = await _checkpointInfosOf(remote, epoch);
    final plan = planSyncPull(
      epoch: epoch,
      applied: next.applied,
      checkpointInfos: infos,
    );

    if (plan.unreachable.isEmpty) {
      _unreachableSinceByBinding.remove(binding.id);
      _unreachableByBinding.remove(binding.id);
    } else {
      if (!_unreachableSinceByBinding.containsKey(binding.id)) {
        _unreachableSinceByBinding[binding.id] = _clock();
        Log.warn(
          'Changes from ${plan.unreachable.map(_nameOf).join(', ')} are not '
          'in the sync folder any more.',
        );
      }
      _unreachableByBinding[binding.id] = plan.unreachable;
    }

    for (final planned in plan.checkpoints) {
      _report('Catching up…');
      await _applyPack(
        remote,
        planned.checkpoint.pack,
        state,
        index,
        prefs,
        next,
      );
      final applied = Map<String, int>.from(next.applied);
      planned.covers.forEach((device, seq) {
        if ((applied[device] ?? 0) < seq) {
          applied[device] = seq;
        }
      });
      next = next.copyWith(applied: applied);
      await settings.upsertBinding(next);
      await index.save(indexFile);
      await prefs.save(prefsFile, key: remote.key);
    }

    for (final change in plan.changes) {
      _report('Merging changes from ${_nameOf(change.device)}…');
      await _applyPack(remote, change.file, state, index, prefs, next);
      next = next.copyWith(
        applied: {...next.applied, change.device: change.seq},
      );
      await settings.upsertBinding(next);
      await index.save(indexFile);
      await prefs.save(prefsFile, key: remote.key);
    }

    if (index.waiting.isNotEmpty) {
      await _applyFiles(remote, index, index.waiting.values.toList(), const []);
      await index.save(indexFile);
    }
    return next;
  }

  /// Merges the newest whole state of the epoch into a workspace that already
  /// had it, for a computer reconnecting to a folder it once used.
  Future<SyncBinding> _catchUp(
    SealedSyncRemote remote,
    SyncEpochListing epoch,
    SyncBinding binding,
    File state,
    SyncFileIndex index,
    SyncPreferencesIndex prefs,
  ) async {
    _report('Catching up…');
    final infos = await _checkpointInfosOf(remote, epoch);
    final newest = _newestCheckpoint(epoch, infos);
    var applied = binding.applied;
    if (newest != null) {
      await _applyPack(remote, newest.pack, state, index, prefs, binding);
      applied = {...applied};
      infos[newest.pack.name]!.covers.forEach((device, seq) {
        if ((applied[device] ?? 0) < seq) {
          applied[device] = seq;
        }
      });
    } else {
      await _applyPack(remote, epoch.base!, state, index, prefs, binding);
    }
    final next = binding.copyWith(applied: applied, baseApplied: true);
    await settings.upsertBinding(next);
    return next;
  }

  Future<void> _applyPack(
    SealedSyncRemote remote,
    RemoteSyncFile file,
    File state,
    SyncFileIndex index,
    SyncPreferencesIndex prefs,
    SyncBinding binding,
  ) async {
    final scratch = await _scratchFolder();
    final pack = File(p.join(scratch.path, 'in-${randomSyncToken(8)}.pack'));
    final bundle =
        File(p.join(scratch.path, 'in-${randomSyncToken(8)}.bundle'));
    try {
      await remote.download(file, pack);
      final record = await readSyncPack(source: pack, bundle: bundle);
      _checkPack(record, file);
      if (record.workspaceId != _workspaceId) {
        throw const SyncError(
          'The sync folder holds changes for another workspace.',
        );
      }
      if (record.hasBundle) {
        await _bridge.importChanges(
          path: bundle.path,
          syncStatePath: state.path,
        );
      }
      if (record.files.isNotEmpty || record.deleted.isNotEmpty) {
        await _applyFiles(remote, index, record.files, record.deleted);
      }
      await _takePreferences(
        record.preferences,
        prefs,
        binding,
        sealed: remote.isSealed,
      );
    } finally {
      await _discard(pack);
      await _discard(bundle);
    }
  }

  Future<SyncFileApplyResult> _applyFiles(
    SealedSyncRemote remote,
    SyncFileIndex index,
    List<SyncFileRecord> files,
    List<SyncFileRecord> deleted,
  ) async {
    final dataPath = await _resolveDataPath();
    final result = await applyRemoteFiles(
      dataPath: dataPath,
      index: index,
      files: files,
      deleted: deleted,
      fetch: (hash, destination) async {
        final blob = (await _blobsOf(remote))[remote.blobName(hash)];
        if (blob == null) {
          return false;
        }
        await remote.download(blob, destination);
        return true;
      },
    );
    if (result.changedPaths.isNotEmpty) {
      await _onFilesApplied?.call(result.changedPaths);
    }
    return result;
  }

  // --- Sending changes out --------------------------------------------------

  Future<SyncBinding> _push(
    SealedSyncRemote remote,
    SyncEpochListing epoch,
    SyncBinding binding,
  ) async {
    final folder = await settings.epochFolder(
      epoch.id,
      bindingId: binding.id,
    );
    final state = File(p.join(folder.path, 'collab_state.json'));
    final indexFile = File(p.join(folder.path, 'files.json'));
    final index = await SyncFileIndex.load(indexFile);
    final prefsFile =
        await _preferencesIndexFile(epoch.id, bindingId: binding.id);
    final prefs = await SyncPreferencesIndex.load(prefsFile, key: remote.key);
    final scratch = await _scratchFolder();
    final bundle =
        File(p.join(scratch.path, 'out-${randomSyncToken(8)}.bundle'));
    final pack = File(p.join(scratch.path, 'out-${randomSyncToken(8)}.pack'));

    try {
      final exported = await _bridge.exportChanges(
        path: bundle.path,
        syncStatePath: state.path,
      );
      final dataPath = await _resolveDataPath();
      final scan = await scanSyncedFiles(
        dataPath: dataPath,
        index: index,
        maximumBytes: maximumFileBytes,
      );
      final preferences = await _scanPreferences(
        prefs,
        on: binding.syncPreferences,
        sealed: remote.isSealed,
      );
      if (!exported.wrote && scan.isEmpty && preferences.isEmpty) {
        index.entries
          ..clear()
          ..addAll(scan.current);
        await index.save(indexFile);
        return binding;
      }

      _report('Sending changes…');
      final sent = await _uploadFiles(remote, dataPath, scan.changed);
      await _announceDevice(remote, epoch);

      final seq = max(binding.nextSeq, epoch.lastSeqOf(settings.deviceId) + 1);
      await writeSyncPack(
        destination: pack,
        record: SyncPackRecord(
          kind: SyncPackKind.changes,
          epoch: epoch.id,
          device: settings.deviceId,
          deviceName: _deviceName(),
          workspaceId: binding.workspaceId,
          seq: seq,
          createdAt: _clock(),
          hasBundle: exported.wrote,
          files: sent,
          deleted: scan.deleted,
          preferences: preferences,
        ),
        bundle: exported.wrote ? bundle : null,
      );
      final uploaded = await remote.upload(
        SyncFileName.changes(epoch.id, settings.deviceId, seq),
        pack,
      );
      epoch.changes
          .putIfAbsent(settings.deviceId, SplayTreeMap.new)
          .putIfAbsent(seq, () => uploaded);

      // Only now that the changes are in the folder does this computer
      // consider them sent.
      final pending = File('${state.path}.next');
      if (exported.wrote && pending.existsSync()) {
        await pending.rename(state.path);
      }
      final before = Map<String, SyncFileRecord>.of(index.entries);
      index.entries
        ..clear()
        ..addAll(scan.current);
      // A file that could not be sent this time keeps its old record, so the
      // next scan still sees it as changed.
      final sentPaths = {for (final record in sent) record.path};
      for (final record in scan.changed) {
        if (!sentPaths.contains(record.path)) {
          final previous = before[record.path];
          if (previous == null) {
            index.entries.remove(record.path);
          } else {
            index.entries[record.path] = previous;
          }
        }
      }
      for (final record in sent) {
        index.entries[record.path] = record;
      }
      for (final record in scan.deleted) {
        index.noteRemoved(record.path, record.modified);
      }
      await index.save(indexFile);
      preferences.forEach(prefs.note);
      _credentialsOn = prefs.credentialsOn;
      await prefs.save(prefsFile, key: remote.key);

      // What was just sent is in this workspace, which therefore holds this
      // computer's changes up to it, as long as it held all the ones before.
      final me = settings.deviceId;
      final next = binding.copyWith(
        nextSeq: seq + 1,
        applied: (binding.applied[me] ?? 0) >= seq - 1
            ? {...binding.applied, me: seq}
            : null,
      );
      await settings.upsertBinding(next);
      return next;
    } finally {
      await _discard(bundle);
      await _discard(pack);
    }
  }

  /// Puts the contents of [changed] in the folder, each under its hash, using
  /// up to [concurrency] parallel uploads and deduplicating identical hashes.
  Future<List<SyncFileRecord>> _uploadFiles(
    SealedSyncRemote remote,
    String dataPath,
    List<SyncFileRecord> changed, {
    int concurrency = 4,
  }) async {
    if (changed.isEmpty) {
      return const [];
    }
    final blobs = await _blobsOf(remote);
    final scratch = await _scratchFolder();
    final sentByIndex = List<SyncFileRecord?>.filled(changed.length, null);
    final inFlight = <String, Future<RemoteSyncFile>>{};
    var cursor = 0;
    final workers = min(max(1, concurrency), changed.length);

    Future<void> runWorker() async {
      while (true) {
        final index = cursor++;
        if (index >= changed.length) {
          return;
        }
        final record = changed[index];
        final source =
            File(p.joinAll([dataPath, ...p.posix.split(record.path)]));
        final copy = File(p.join(scratch.path, 'file-${randomSyncToken(8)}'));
        try {
          await source.copy(copy.path);
          final hash = await hashFile(copy);
          final name = remote.blobName(hash);
          if (!blobs.containsKey(name)) {
            final pending = inFlight[name];
            if (pending != null) {
              blobs[name] = await pending;
            } else {
              final upload = remote.upload(
                SyncFileName.blob(name),
                copy,
                blob: true,
              );
              inFlight[name] = upload;
              try {
                blobs[name] = await upload;
              } finally {
                unawaited(inFlight.remove(name));
              }
            }
          }
          sentByIndex[index] = SyncFileRecord(
            path: record.path,
            hash: hash,
            bytes: copy.lengthSync(),
            modified: record.modified,
          );
        } on FileSystemException catch (error) {
          // Removed or locked since the scan; the next round sees it as it is.
          Log.info('A file was not synced this time: $error');
        } finally {
          await _discard(copy);
        }
      }
    }

    await Future.wait([for (var i = 0; i < workers; i++) runWorker()]);
    return [
      for (final item in sentByIndex)
        if (item != null) item,
    ];
  }

  /// Writes this computer's name into the epoch, once.
  Future<void> _announceDevice(
    SealedSyncRemote remote,
    SyncEpochListing epoch,
  ) async {
    final device = settings.deviceId;
    if (epoch.deviceInfos.containsKey(device)) {
      return;
    }
    final scratch = await _scratchFolder();
    final file =
        File(p.join(scratch.path, 'device-${randomSyncToken(8)}.json'));
    try {
      await file.writeAsString(
        SyncDeviceInfo(
          device: device,
          name: _deviceName(),
          platform: Platform.operatingSystem,
          joinedAt: _clock(),
        ).encode(),
      );
      epoch.deviceInfos[device] = await remote.upload(
        SyncFileName.deviceInfo(epoch.id, device),
        file,
      );
    } finally {
      await _discard(file);
    }
  }

  // --- Checkpoints and tidying ----------------------------------------------

  Future<SyncBinding> _maybeCheckpoint(
    SealedSyncRemote remote,
    SyncEpochListing epoch,
    SyncBinding binding,
  ) async {
    if (epoch.changeCount < checkpointAfter) {
      return binding;
    }
    // A checkpoint is named after this computer's last change, so there is
    // one only with a change since its last: two of the same name could be
    // told apart by nobody.
    final lastSent = binding.nextSeq - 1;
    if (lastSent < 1 ||
        epoch.checkpoints.any(
          (checkpoint) =>
              checkpoint.device == settings.deviceId &&
              checkpoint.seq >= lastSent,
        )) {
      return binding;
    }
    final last = epoch.checkpoints.isEmpty
        ? null
        : epoch.checkpoints.last.pack.modifiedAt;
    if (last != null && _clock().difference(last) < checkpointQuietPeriod) {
      return binding;
    }
    try {
      _report('Tidying the sync folder…');
      await _writeCheckpoint(remote, epoch, binding);
    } on Object catch (error) {
      // A missed checkpoint only means the folder stays larger for a while.
      Log.warn('A sync checkpoint was not written: $error');
    }
    return binding;
  }

  Future<void> _writeCheckpoint(
    SealedSyncRemote remote,
    SyncEpochListing epoch,
    SyncBinding binding,
  ) async {
    final folder =
        await settings.epochFolder(epoch.id, bindingId: binding.id);
    final index =
        await SyncFileIndex.load(File(p.join(folder.path, 'files.json')));
    final prefs = await SyncPreferencesIndex.load(
      await _preferencesIndexFile(epoch.id, bindingId: binding.id),
      key: remote.key,
    );
    final scratch = await _scratchFolder();
    final bundle =
        File(p.join(scratch.path, 'ckpt-${randomSyncToken(8)}.bundle'));
    final pack = File(p.join(scratch.path, 'ckpt-${randomSyncToken(8)}.pack'));
    final infoFile =
        File(p.join(scratch.path, 'ckpt-${randomSyncToken(8)}.json'));
    final seq = binding.nextSeq - 1;
    final device = settings.deviceId;
    try {
      await _bridge.exportSnapshot(path: bundle.path);
      // Everything merged here, this computer's own changes included.
      final covers = Map<String, int>.of(binding.applied);
      await writeSyncPack(
        destination: pack,
        record: SyncPackRecord(
          kind: SyncPackKind.checkpoint,
          epoch: epoch.id,
          device: device,
          deviceName: _deviceName(),
          workspaceId: binding.workspaceId,
          seq: seq,
          createdAt: _clock(),
          hasBundle: true,
          files: index.entries.values.toList(),
          deleted: index.removals,
          filesComplete: true,
          preferences: prefs.records,
        ),
        bundle: bundle,
      );
      final packName = SyncFileName.checkpoint(epoch.id, device, seq);
      await remote.upload(packName, pack);
      final info = SyncCheckpointInfo(
        covers: covers,
        createdAt: _clock(),
        device: device,
      );
      await infoFile.writeAsString(info.encode());
      await remote.upload(
        SyncFileName.checkpointInfo(epoch.id, device, seq),
        infoFile,
      );
      _checkpointInfos[packName] = info;

      // Read again: the checkpoint has to be in the listing it tidies, or
      // what it covers would be nowhere.
      final listing = SyncListing.of(await remote.list());
      final fresh = listing.epochs[epoch.id];
      if (fresh == null ||
          !fresh.checkpoints.any(
            (checkpoint) =>
                checkpoint.pack.name == packName && checkpoint.info != null,
          )) {
        return;
      }
      for (final file in syncFilesToTidy(
        listing: listing,
        epoch: fresh,
        newest: info,
        checkpointInfos: await _checkpointInfosOf(remote, fresh),
        now: _clock(),
      )) {
        try {
          await remote.delete(file);
        } on Object catch (error) {
          Log.info('A tidied sync file could not be removed: $error');
        }
      }
      await _tidyBlobs(remote, index);
    } finally {
      await _discard(bundle);
      await _discard(pack);
      await _discard(infoFile);
    }
  }

  /// Removes attached-file contents nothing names any more, once they have
  /// been unnamed for long enough that no computer can still be on its way to
  /// fetching them.
  Future<void> _tidyBlobs(SealedSyncRemote remote, SyncFileIndex index) async {
    final named = {
      for (final record in index.entries.values) remote.blobName(record.hash),
      for (final record in index.waiting.values) remote.blobName(record.hash),
    };
    final now = _clock();
    for (final entry in (await _blobsOf(remote)).entries) {
      final modified = entry.value.modifiedAt;
      if (named.contains(entry.key) ||
          modified == null ||
          now.difference(modified) < blobGracePeriod) {
        continue;
      }
      try {
        await remote.delete(entry.value);
      } on Object catch (error) {
        Log.info('An unused synced file could not be removed: $error');
      }
    }
  }

  // --- Setting up -----------------------------------------------------------

  /// Reads what [destination] holds, without changing anything.
  ///
  /// A sealed folder says what it holds only once its AppFlowy password is
  /// known: [key] when it has just been typed, the key this computer kept, or
  /// the one this computer's AppFlowy password makes.
  Future<SyncFolderInspection> inspect(
    BackupDestination destination, {
    SyncKey? key,
    String? password,
  }) async {
    await settings.ensureLoaded();
    final plain = await _openRemote(destination);
    try {
      await plain.ensureReady();
      final listing = SyncListing.of(await plain.list());
      final epoch = listing.current;
      if (epoch == null) {
        return SyncFolderInspection(
          state: listing.epochs.isNotEmpty
              ? SyncFolderState.unreadable
              : SyncFolderState.empty,
        );
      }
      SyncVault? vault;
      SyncKey? unlocked;
      final file = epoch.vault;
      if (file != null) {
        vault = await _readVault(plain, file);
        unlocked =
            key != null && vault.accepts(key) ? key : await _openVault(vault);
      }
      if (vault != null && unlocked == null) {
        return SyncFolderInspection(
          state: SyncFolderState.locked,
          vault: vault,
        );
      }
      final remote = SealedSyncRemote(plain, unlocked, scratch: _scratchFolder);
      final SyncEpochInfo info;
      try {
        info = await _readEpochInfo(remote, epoch);
      } on Object catch (error) {
        Log.warn('A sync folder could not be read: $error');
        return SyncFolderInspection(
          state: SyncFolderState.unreadable,
          vault: vault,
          key: unlocked,
        );
      }
      await _refreshDevices(remote, epoch);
      return SyncFolderInspection(
        state: info.workspaceId == _workspaceId && info.uid == _uid
            ? SyncFolderState.thisWorkspace
            : SyncFolderState.otherWorkspace,
        epoch: info,
        devices: _devices,
        vault: vault,
        key: unlocked,
        password: unlocked == null ? null : password,
      );
    } finally {
      plain.dispose();
    }
  }

  /// Opens a sealed folder with [password], and says what it holds. Joining
  /// it, or syncing with it again, makes [password] this computer's AppFlowy
  /// password too.
  Future<SyncFolderInspection> unlockFolder(
    BackupDestination destination,
    SyncFolderInspection inspection,
    String password,
  ) async {
    final vault = inspection.vault;
    if (vault == null) {
      return inspection;
    }
    final key = await vault.unlock(password);
    if (key == null) {
      throw const SyncError(
        'That is not the AppFlowy password this folder is sealed with.',
      );
    }
    return inspect(destination, key: key, password: password);
  }

  /// Records an already-inspected empty folder for the first workspace to start
  /// syncing into asynchronously as soon as it opens — without a second
  /// blocking network round-trip.
  Future<void> queueStartWhenReady(
    BackupDestination destination, {
    bool encrypt = true,
  }) async {
    await settings.ensureLoaded();
    if (encrypt) {
      await _requirePassword();
    }
    await settings.setPendingStart(destination, encrypt: encrypt);
  }

  /// Keeps an empty folder, chosen before any workspace exists here, for the
  /// first workspace to start syncing into once it opens — sealed with the
  /// AppFlowy password by default, or unsealed when [encrypt] is false.
  Future<void> startWhenReady(
    BackupDestination destination, {
    bool encrypt = true,
  }) async {
    await settings.ensureLoaded();
    if (encrypt) {
      await _requirePassword();
    }
    final plain = await _openRemote(destination);
    try {
      await plain.ensureReady();
      if (!SyncListing.of(await plain.list()).isEmpty) {
        throw const SyncError('That folder already holds a workspace.');
      }
    } finally {
      plain.dispose();
    }
    await settings.setPendingStart(destination, encrypt: encrypt);
  }

  /// Starts syncing into [destination] asynchronously in the background without
  /// blocking the caller or showing a modal spinner.
  void startNewInBackground(
    BackupDestination destination, {
    bool encrypt = true,
    void Function()? onSucceeded,
    void Function(Object error)? onFailed,
  }) {
    _settingUpDestination = destination;
    _set(SyncPhase.working, activity: 'Preparing initial sync…');
    unawaited(() async {
      try {
        await startNew(destination, encrypt: encrypt);
        onSucceeded?.call();
      } on Object catch (error) {
        Log.warn('Background initial sync setup failed: $error');
        if (onFailed != null) {
          onFailed(error);
        } else {
          notify?.call(
            'Sync could not start: ${describeSyncError(error)}',
            isError: true,
          );
        }
      } finally {
        if (_settingUpDestination == destination) {
          _settingUpDestination = null;
          notifyListeners();
        }
      }
    }());
  }

  /// Starts syncing this workspace into an empty folder, sealed with the
  /// AppFlowy password when [encrypt] is true (the default). If other providers
  /// are already syncing this workspace, [destination] is added alongside them.
  Future<void> startNew(
    BackupDestination destination, {
    bool encrypt = true,
  }) =>
      encrypt ? _startSealed(destination) : startUnsealed(destination);

  Future<void> _startSealed(BackupDestination destination) => _setup(() async {
        _requireLocalWorkspace();
        final password = await _requirePassword();
        _settingUpDestination = destination;
        final plain = await _openRemote(destination);
        try {
          await plain.ensureReady();
          final listing = SyncListing.of(await plain.list());
          if (!listing.isEmpty) {
            throw const SyncError('That folder already holds a workspace.');
          }
          _set(SyncPhase.working, activity: 'Sealing the folder…');
          final (vault, key) = await _newVault(password);
          final epoch = newSyncEpoch(_clock());
          final created = await _publishEpoch(
            remote: SealedSyncRemote(plain, key, scratch: _scratchFolder),
            vault: vault,
            destination: destination,
            epoch: epoch,
            reason: SyncEpochReason.started,
            filesRoot: await _resolveDataPath(),
            snapshot: null,
          );
          await _keep(key, vault);
          await settings.upsertBinding(created);
          await settings.sweepEpochFolders(keep: epoch);
          await _removeFiles(plain, listing.legacyVaults);
        } finally {
          _settingUpDestination = null;
          plain.dispose();
        }
        _schedule();
      });

  /// Starts syncing into an empty folder without sealing it.
  Future<void> startUnsealed(BackupDestination destination) => _setup(() async {
        _requireLocalWorkspace();
        _settingUpDestination = destination;
        final plain = await _openRemote(destination);
        try {
          await plain.ensureReady();
          final listing = SyncListing.of(await plain.list());
          if (!listing.isEmpty) {
            throw const SyncError('That folder already holds a workspace.');
          }
          _set(SyncPhase.working, activity: 'Preparing sync folder…');
          final epoch = newSyncEpoch(_clock());
          final created = await _publishEpoch(
            remote: SealedSyncRemote(plain, null, scratch: _scratchFolder),
            vault: null,
            destination: destination,
            epoch: epoch,
            reason: SyncEpochReason.started,
            filesRoot: await _resolveDataPath(),
            snapshot: null,
          );
          await settings.upsertBinding(created);
          await settings.sweepEpochFolders(keep: epoch);
          await _removeFiles(plain, listing.legacyVaults);
        } finally {
          _settingUpDestination = null;
          plain.dispose();
        }
        _schedule();
      });

  Future<void> _startPending(
    BackupDestination destination, {
    bool encrypt = true,
  }) async {
    try {
      await settings.setPendingStart(null);
      await startNew(destination, encrypt: encrypt);
      notify?.call('"$_workspaceName" is syncing.');
    } on Object catch (error) {
      Log.warn('Sync could not start in the folder chosen at first: $error');
      notify?.call(
        'Sync could not start: ${describeSyncError(error)}',
        isError: true,
      );
    }
  }

  /// Syncs this workspace with a folder that already holds it (adding it
  /// alongside any other providers already bound to this workspace).
  Future<void> reconnect(
    BackupDestination destination,
    SyncFolderInspection inspection,
  ) =>
      _setup(() async {
        _requireLocalWorkspace();
        final info = inspection.epoch;
        if (inspection.state != SyncFolderState.thisWorkspace || info == null) {
          throw const SyncError('That folder holds another workspace.');
        }
        final key = inspection.key;
        if (inspection.needsPassword) {
          throw const SyncError('Type your AppFlowy password first.');
        }
        if (key != null) {
          await _keep(key, inspection.vault);
        }
        await _adoptPasswordOf(inspection);
        final existing = settings.byDestination(destination) ?? binding;
        await settings.upsertBinding(
          SyncBinding(
            destination: destination,
            epoch: info.epoch,
            workspaceId: info.workspaceId,
            workspaceName: _workspaceName,
            uid: info.uid,
            intervalSeconds:
                existing?.intervalSeconds ?? defaultSyncIntervalSeconds,
            syncPreferences: existing?.syncPreferences ?? true,
            vaultId: key?.vaultId ?? '',
          ),
        );
        await settings.sweepEpochFolders(keep: info.epoch);
        _schedule();
      });

  /// Replaces the workspace on this computer with the one in [destination].
  ///
  /// When [deferFiles] is true (used by UI flows), only the compact workspace
  /// structure pack is fetched before restarting so the workspace opens in a
  /// second or two; attached files and media stream asynchronously in the
  /// background once the workspace opens.
  Future<void> join(
    BackupDestination destination,
    SyncFolderInspection inspection, {
    bool deferFiles = false,
    bool skipSafetyCopy = false,
  }) =>
      _setup(() async {
        final info = inspection.epoch;
        if (info == null) {
          throw const SyncError('That folder does not hold a workspace.');
        }
        if (inspection.needsPassword) {
          throw const SyncError('Type your AppFlowy password first.');
        }
        final key = inspection.key;
        final plain = await _openRemote(destination);
        try {
          await plain.ensureReady();
          await _replaceFrom(
            SealedSyncRemote(plain, key, scratch: _scratchFolder),
            destination,
            info,
            reason: 'join',
            deferFiles: deferFiles,
            skipSafetyCopy: skipSafetyCopy,
          );
        } finally {
          plain.dispose();
        }
        if (key != null) {
          await _keep(key, inspection.vault);
        }
        await _adoptPasswordOf(inspection);
        await _restartApplication();
      });

  /// Loads the workspace another computer restored, replacing this one.
  Future<void> loadRestoredWorkspace({bool deferFiles = false}) =>
      _setup(() async {
        final info = _restoredElsewhere;
        final target = (_restoredBindingId == null
                ? null
                : settings.byId(_restoredBindingId!)) ??
            binding;
        if (info == null || target == null) {
          return;
        }
        final plain = await _openRemote(target.destination);
        try {
          await plain.ensureReady();
          final current = SyncListing.of(await plain.list()).current;
          if (current == null) {
            throw const SyncError(
              'The sync folder no longer holds this workspace.',
            );
          }
          final key =
              await _keyFor(plain, current, bindingId: target.id);
          if (_lockedByBinding[target.id] != null ||
              (current.vault != null && key == null)) {
            throw const SyncError('Type your AppFlowy password first.');
          }
          await _replaceFrom(
            SealedSyncRemote(plain, key, scratch: _scratchFolder),
            target.destination,
            info,
            reason: 'restore-elsewhere',
            deferFiles: deferFiles,
          );
        } finally {
          plain.dispose();
        }
        await _restartApplication();
      });

  /// Forgets the key held in memory, as a computer that never had it.
  @visibleForTesting
  void forgetKeyInMemory() {
    _key = null;
    _keysInMemory.clear();
  }

  /// Types the AppFlowy password on this computer, for the folder(s) that asked
  /// for it, and carries on syncing. It becomes this computer's AppFlowy
  /// password too.
  Future<void> unlock(String password, {String? bindingId}) async {
    final vaultsToTry = <String, SyncVault>{
      if (bindingId != null && _lockedByBinding[bindingId] != null)
        bindingId: _lockedByBinding[bindingId]!
      else
        ..._lockedByBinding,
    };
    if (vaultsToTry.isEmpty && _lockedBy != null) {
      vaultsToTry[''] = _lockedBy!;
    }
    if (vaultsToTry.isEmpty) {
      return;
    }
    var unlockedAny = false;
    for (final entry in vaultsToTry.entries) {
      final key = await entry.value.unlock(password);
      if (key != null) {
        unlockedAny = true;
        await _keep(key, entry.value);
        if (entry.key.isNotEmpty) {
          _lockedByBinding.remove(entry.key);
          _destinationStatuses[entry.key] = const SyncDestinationStatus();
        }
      }
    }
    if (!unlockedAny) {
      throw const SyncError(
        'That is not the AppFlowy password this folder is sealed with.',
      );
    }
    _lockedBy = _lockedByBinding.values.isEmpty
        ? null
        : _lockedByBinding.values.first;
    await _passwords.adopt(password);
    _schedule();
  }

  /// Seals bound sync folder(s) with the AppFlowy password: [bindingId] when
  /// specified, or every bound folder that is unsealed or awaiting resealing.
  Future<void> sealWithAppPassword({String? bindingId}) => _setup(() async {
        final targets = bindingId != null
            ? [
                if (settings.byId(bindingId) case final found?) found,
              ]
            : boundBindings;
        if (targets.isEmpty || !isBoundHere) {
          throw const SyncError('Sync is not set up for this workspace.');
        }
        final password = await _requirePassword();
        for (final target in targets) {
          await _sealSingleBinding(target, password);
        }
        _schedule();
      });

  Future<void> _sealSingleBinding(
    SyncBinding binding,
    String password,
  ) async {
    final plain = await _openRemote(binding.destination);
    try {
      await plain.ensureReady();
      var listing = SyncListing.of(await plain.list());
      final current = listing.current;
      if (current == null || current.id != binding.epoch) {
        throw const SyncError(
          'The sync folder changed. Sync once, then try again.',
        );
      }
      SyncKey? key;
      if (binding.vaultId.isNotEmpty) {
        final file = current.vault;
        if (file == null) {
          throw const SyncError(
            'The sync folder is no longer sealed with the AppFlowy '
            'password. Set sync up again.',
          );
        }
        final vault = await _readVault(plain, file);
        if (await vault.unlock(password) != null) {
          if (binding.resealPending) {
            await settings
                .upsertBinding(binding.copyWith(resealPending: false));
          }
          return;
        }
        key = await _keyOf(binding);
        if (key == null || !vault.accepts(key)) {
          throw const SyncError('Type your AppFlowy password first.');
        }
      }
      _report('Taking in what the others sent…');
      final previous = SealedSyncRemote(plain, key, scratch: _scratchFolder);
      await _refreshDevices(previous, current, bindingId: binding.id);
      final pulled = await _pull(previous, listing, current, binding);

      _report('Sealing the folder…');
      final (vault, sealed) = await _newVault(password);
      final epoch = nextSyncEpoch(binding.epoch, _clock());
      final next = await _publishEpoch(
        remote: SealedSyncRemote(plain, sealed, scratch: _scratchFolder),
        vault: vault,
        destination: binding.destination,
        epoch: epoch,
        reason: SyncEpochReason.continued,
        filesRoot: await _resolveDataPath(),
        snapshot: null,
        intervalSeconds: pulled.intervalSeconds,
        syncPreferences: pulled.syncPreferences,
      );
      await _keep(sealed, vault);
      await settings.upsertBinding(next);
      await settings.sweepEpochFolders(keep: epoch);

      listing = SyncListing.of(await plain.list());
      await _removeAllBut(
        plain,
        listing,
        epoch,
        bindingId: next.id,
        key: sealed,
        keepBlobs: false,
      );
    } finally {
      plain.dispose();
    }
  }

  /// Turns encryption off for [bindingId] (or the primary bound folder),
  /// carrying the workspace on in an unsealed epoch and removing sealed files.
  Future<void> unsealSyncFolder({String? bindingId}) => _setup(() async {
        final target =
            (bindingId == null ? null : settings.byId(bindingId)) ?? binding;
        if (target == null || !isBoundHere) {
          throw const SyncError('Sync is not set up for this workspace.');
        }
        if (target.vaultId.isEmpty) {
          return;
        }
        final plain = await _openRemote(target.destination);
        try {
          await plain.ensureReady();
          var listing = SyncListing.of(await plain.list());
          final current = listing.current;
          if (current == null || current.id != target.epoch) {
            throw const SyncError(
              'The sync folder changed. Sync once, then try again.',
            );
          }
          final key =
              await _keyFor(plain, current, bindingId: target.id);
          if (_lockedByBinding[target.id] != null || key == null) {
            throw const SyncError('Type your AppFlowy password first.');
          }
          _report('Taking in what the others sent…');
          final previous =
              SealedSyncRemote(plain, key, scratch: _scratchFolder);
          await _refreshDevices(previous, current, bindingId: target.id);
          final pulled = await _pull(previous, listing, current, target);

          _report('Updating the sync folder…');
          final epoch = nextSyncEpoch(target.epoch, _clock());
          final next = await _publishEpoch(
            remote: SealedSyncRemote(plain, null, scratch: _scratchFolder),
            vault: null,
            destination: target.destination,
            epoch: epoch,
            reason: SyncEpochReason.continued,
            filesRoot: await _resolveDataPath(),
            snapshot: null,
            intervalSeconds: pulled.intervalSeconds,
            syncPreferences: pulled.syncPreferences,
          );
          final oldVaultId = target.vaultId;
          _keysInMemory.remove(oldVaultId);
          _vaultsById.remove(oldVaultId);
          _lockedByBinding.remove(target.id);
          if (_key?.vaultId == oldVaultId) {
            _key = _keysInMemory.values.isEmpty
                ? null
                : _keysInMemory.values.first;
          }
          if (!boundBindings.any(
            (b) => b.id != target.id && b.vaultId.isNotEmpty,
          )) {
            _credentialsOn = false;
          }
          if (oldVaultId.isNotEmpty) {
            await _keys.forget(oldVaultId);
          }
          await settings.upsertBinding(next);
          await settings.sweepEpochFolders(keep: epoch);

          listing = SyncListing.of(await plain.list());
          await _removeAllBut(
            plain,
            listing,
            epoch,
            bindingId: next.id,
            key: null,
            keepBlobs: false,
          );
        } finally {
          plain.dispose();
        }
        _schedule();
      });

  /// Notes that the AppFlowy password was changed here while sealed folders
  /// could not be sealed again yet, so they are sealed as soon as reachable.
  Future<void> markResealPending() async {
    var changed = false;
    for (final b in boundBindings) {
      if (b.vaultId.isNotEmpty && !b.resealPending) {
        await settings.upsertBinding(b.copyWith(resealPending: true));
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Whether accounts, passwords and keys travel through sealed sync folders.
  Future<void> setSyncCredentials(bool on) async {
    final sealedTargets = [
      for (final b in boundBindings)
        if (b.vaultId.isNotEmpty) b,
    ];
    if (sealedTargets.isEmpty || !isBoundHere) {
      throw const SyncError(
        'Accounts, passwords and keys only travel through a sealed folder.',
      );
    }
    if (on == _credentialsOn) {
      return;
    }
    final record = SyncPreferenceRecord(
      key: credentialsSwitchKey,
      value: on ? syncSwitchOn : syncSwitchOff,
      modified: _clock().millisecondsSinceEpoch,
    );
    if (on) {
      _credentialsOn = true;
      _outbox.add(record);
      notifyListeners();
      await syncNow();
      return;
    }
    await _setup(() async {
      for (final binding in sealedTargets) {
        final plain = await _openRemote(binding.destination);
        try {
          await plain.ensureReady();
          var listing = SyncListing.of(await plain.list());
          final current = listing.current;
          if (current == null || current.id != binding.epoch) {
            throw const SyncError(
              'The sync folder changed. Sync once, then try again.',
            );
          }
          final key =
              await _keyFor(plain, current, bindingId: binding.id);
          final vault = key == null ? null : _vaultsById[key.vaultId];
          if (_lockedByBinding[binding.id] != null ||
              key == null ||
              vault == null) {
            throw const SyncError('Type your AppFlowy password first.');
          }
          final remote = SealedSyncRemote(plain, key, scratch: _scratchFolder);
          _report('Taking in what the others sent…');
          await _refreshDevices(remote, current, bindingId: binding.id);
          final pulled = await _pull(remote, listing, current, binding);

          _report('Taking accounts, passwords and keys out of the folder…');
          final epoch = nextSyncEpoch(binding.epoch, _clock());
          final next = await _publishEpoch(
            remote: remote,
            vault: vault,
            destination: binding.destination,
            epoch: epoch,
            reason: SyncEpochReason.continued,
            filesRoot: await _resolveDataPath(),
            snapshot: null,
            intervalSeconds: pulled.intervalSeconds,
            syncPreferences: pulled.syncPreferences,
            switches: [record],
          );
          _credentialsOn = false;
          await settings.upsertBinding(next);
          await settings.sweepEpochFolders(keep: epoch);
          listing = SyncListing.of(await plain.list());
          await _removeAllBut(
            plain,
            listing,
            epoch,
            bindingId: next.id,
            key: key,
            keepBlobs: true,
          );
        } finally {
          plain.dispose();
        }
      }
    });
    _schedule();
  }

  /// The epoch a restore made here will be synced in, or null when sync is
  /// not set up for this workspace.
  String? newRestoreEpoch() {
    final binding = this.binding;
    return binding != null && isBoundHere
        ? nextSyncEpoch(binding.epoch, _clock())
        : null;
  }

  /// Publishes a restore made on this computer across every bound sync folder.
  Future<void> publishRestore({
    required String epoch,
    required File snapshot,
    required String filesRoot,
  }) async {
    final targets = boundBindings;
    if (targets.isEmpty) {
      return;
    }
    _busyWithSetup = true;
    detach();
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    try {
      for (var i = 0; i < targets.length; i++) {
        final binding = targets[i];
        final targetEpoch =
            i == 0 ? epoch : nextSyncEpoch(binding.epoch, _clock());
        final plain = await _openRemote(binding.destination);
        try {
          await plain.ensureReady();
          SyncKey? key;
          SyncVault? vault;
          final mine =
              SyncListing.of(await plain.list()).epochs[binding.epoch];
          if (binding.vaultId.isNotEmpty) {
            key = mine == null
                ? null
                : await _keyFor(plain, mine, bindingId: binding.id);
            vault = key == null ? null : _vaultsById[key.vaultId];
            if (key == null || vault == null || vault.id != key.vaultId) {
              throw const SyncError('Type your AppFlowy password first.');
            }
          }
          if (mine != null) {
            try {
              await _refreshDevices(
                SealedSyncRemote(plain, key, scratch: _scratchFolder),
                mine,
                bindingId: binding.id,
              );
            } on Object catch (error) {
              Log.info('Who else syncs could not be read: $error');
            }
          }
          final next = await _publishEpoch(
            remote: SealedSyncRemote(plain, key, scratch: _scratchFolder),
            vault: vault,
            destination: binding.destination,
            epoch: targetEpoch,
            reason: SyncEpochReason.restored,
            filesRoot: filesRoot,
            snapshot: snapshot,
            intervalSeconds: binding.intervalSeconds,
            syncPreferences: binding.syncPreferences,
          );
          await settings.upsertBinding(next);
          await settings.sweepEpochFolders(keep: targetEpoch);
        } finally {
          plain.dispose();
        }
      }
    } on Object catch (error) {
      Log.warn('A restore could not be published to the sync folder: $error');
      await settings.update(null);
      throw SyncError(
        'The sync folder could not be updated, so sync was turned off here: '
        '${describeSyncError(error)}',
      );
    } finally {
      _busyWithSetup = false;
    }
  }

  Future<String> _requirePassword() async {
    final password = await _passwords.current();
    if (password == null) {
      throw const SyncError('Set your AppFlowy password first.');
    }
    return password;
  }

  Future<(SyncVault, SyncKey)> _newVault(String password) => SyncVault.create(
        passphrase: password,
        now: _clock(),
        device: settings.deviceId,
        iterations: vaultIterations,
      );

  /// The password that opened [inspection]'s folder is the AppFlowy password.
  Future<void> _adoptPasswordOf(SyncFolderInspection inspection) async {
    final password = inspection.password;
    if (password != null) {
      await _passwords.adopt(password);
    }
  }

  Future<void> _keep(SyncKey key, [SyncVault? vault]) async {
    await _keys.write(key);
    _keysInMemory[key.vaultId] = key;
    _key = key;
    if (vault != null) {
      _vaultsById[vault.id] = vault;
    }
    _lockedBy = _lockedByBinding.values.isEmpty
        ? null
        : _lockedByBinding.values.first;
  }

  /// Removes every file of every epoch but [epoch], and, unless [keepBlobs],
  /// every attached file the new epoch does not name.
  Future<void> _removeAllBut(
    SyncRemote plain,
    SyncListing listing,
    String epoch, {
    required String bindingId,
    required SyncKey? key,
    required bool keepBlobs,
  }) async {
    final doomed = <RemoteSyncFile>[
      for (final other in listing.epochs.values)
        if (other.id != epoch) ...[
          if (other.base != null) other.base!,
          if (other.baseInfo != null) other.baseInfo!,
          if (other.vault != null) other.vault!,
          ...other.changes.values.expand((files) => files.values),
          ...other.deviceInfos.values,
          for (final checkpoint in other.checkpoints) ...[
            checkpoint.pack,
            if (checkpoint.info != null) checkpoint.info!,
          ],
        ],
      ...listing.legacyVaults,
    ];
    if (!keepBlobs) {
      final index = await SyncFileIndex.load(
        File(
          p.join(
            (await settings.epochFolder(epoch, bindingId: bindingId)).path,
            'files.json',
          ),
        ),
      );
      final named = {
        for (final record in index.entries.values)
          key?.blobName(record.hash) ?? record.hash,
      };
      for (final file in await plain.list(blobs: true)) {
        final parsed = SyncFileName.parse(file.name);
        if (parsed?.kind == SyncFileKind.blob &&
            !named.contains(parsed!.hash)) {
          doomed.add(file);
        }
      }
    }
    await _removeFiles(plain, doomed);
  }

  Future<void> _removeFiles(
    SyncRemote plain,
    Iterable<RemoteSyncFile> files,
  ) async {
    for (final file in files) {
      try {
        await plain.delete(file);
      } on Object catch (error) {
        Log.info('A replaced sync file could not be removed: $error');
      }
    }
  }

  /// Where the sync bookkeeping for [epoch] lives — what a restore that is
  /// about to start a new epoch should write its state to.
  Future<String> collabStatePath(String epoch) async => p.join(
        (await settings.epochFolder(
          epoch,
          bindingId: binding?.id ?? '',
        ))
            .path,
        'collab_state.json',
      );

  /// Pauses or resumes every bound sync provider for this workspace.
  Future<void> setPaused(bool paused) async {
    final targets = boundBindings.isNotEmpty
        ? boundBindings
        : [if (binding case final b?) b];
    if (targets.isEmpty) {
      return;
    }
    for (final target in targets) {
      await settings.upsertBinding(target.copyWith(paused: paused));
    }
    _schedule();
  }

  /// Pauses or resumes a single sync provider identified by [bindingId].
  Future<void> setDestinationPaused(String bindingId, bool paused) async {
    final target = settings.byId(bindingId);
    if (target == null || target.paused == paused) {
      return;
    }
    await settings.upsertBinding(target.copyWith(paused: paused));
    _schedule();
  }

  /// Whether this computer's settings follow the workspace.
  Future<void> setSyncPreferences(bool on) async {
    final targets = boundBindings;
    if (targets.isEmpty || targets.every((b) => b.syncPreferences == on)) {
      return;
    }
    for (final target in targets) {
      final next = target.copyWith(syncPreferences: on);
      if (on) {
        try {
          await adoptIndexedPreferences(
            source: _preferencesFor(
              next,
              sealed: target.vaultId.isNotEmpty,
              credentials: _credentialsOn,
            ),
            index: await SyncPreferencesIndex.load(
              await _preferencesIndexFile(target.epoch, bindingId: target.id),
              key: await _keyOf(target),
            ),
          );
        } on Object catch (error) {
          Log.warn('The synced settings could not be taken: $error');
        }
      }
      await settings.upsertBinding(next);
    }
    notifyListeners();
    if (on) {
      unawaited(syncNow());
    }
  }

  Future<void> setInterval(int seconds) async {
    final targets = boundBindings.isNotEmpty
        ? boundBindings
        : [if (binding case final b?) b];
    if (targets.isEmpty) {
      return;
    }
    for (final target in targets) {
      await settings.upsertBinding(target.copyWith(intervalSeconds: seconds));
    }
    _schedule();
  }

  /// Disconnects a single sync provider [bindingId], leaving any other
  /// providers active.
  Future<void> disconnectDestination(String bindingId) async {
    _destinationStatuses.remove(bindingId);
    _lockedByBinding.remove(bindingId);
    _devicesByBinding.remove(bindingId);
    _unreachableSinceByBinding.remove(bindingId);
    _unreachableByBinding.remove(bindingId);
    _lockedBy = _lockedByBinding.values.isEmpty
        ? null
        : _lockedByBinding.values.first;
    await settings.removeBinding(bindingId);
    _rebuildMergedDevices();
    if (boundBindings.isEmpty) {
      detach();
      _restoredElsewhere = null;
      _restoredBindingId = null;
      _devices = const [];
      _set(SyncPhase.off);
    } else {
      _schedule();
    }
  }

  /// Stops syncing across all destinations on this computer. The remote folders
  /// and everything in them stay as they are.
  Future<void> disconnect() async {
    detach();
    _restoredElsewhere = null;
    _restoredBindingId = null;
    _destinationStatuses.clear();
    _lockedByBinding.clear();
    _lockedBy = null;
    _devicesByBinding.clear();
    _devices = const [];
    await settings.update(null);
    await settings.sweepEpochFolders();
    _set(SyncPhase.off);
  }

  /// Removes all AppFlowy sync files and synced blobs from [override] (or
  /// every currently bound destination when omitted), leaving any unrelated
  /// personal files untouched.
  Future<void> clearRemoteSyncFolder([BackupDestination? override]) async {
    final targets = override != null
        ? [override]
        : [for (final b in settings.bindings) b.destination];
    for (final target in targets) {
      if (!target.isReady) {
        continue;
      }
      final plain = await _openRemote(target);
      try {
        await plain.ensureReady();
        final files = [
          ...await plain.list(),
          ...await plain.list(blobs: true),
        ];
        for (final file in files) {
          if (SyncFileName.parse(file.name) != null) {
            await plain.delete(file);
          }
        }
      } finally {
        plain.dispose();
      }
    }
  }

  /// Clears all local sync state (and, when [clearRemote] is true, removes
  /// synced data from all cloud sync folders first) for a fresh start.
  Future<void> resetForFreshStart({bool clearRemote = false}) async {
    _suspended = true;
    detach();
    _again = false;
    await Future.wait(_attachments.toList());
    await _rounds?.future;
    final existing = List<SyncBinding>.of(settings.bindings);
    if (clearRemote && existing.isNotEmpty) {
      await clearRemoteSyncFolder();
    }
    for (final current in existing) {
      if (current.vaultId.isNotEmpty) {
        try {
          await _keys.forget(current.vaultId);
        } on Object catch (error) {
          Log.warn('Sync vault key could not be cleared: $error');
        }
      }
    }
    _uid = null;
    _workspaceId = null;
    _workspaceName = '';
    _key = null;
    _keysInMemory.clear();
    _vaultsById.clear();
    _lockedBy = null;
    _lockedByBinding.clear();
    _destinationStatuses.clear();
    _restoredElsewhere = null;
    _restoredBindingId = null;
    _devicesByBinding.clear();
    _devices = const [];
    _preferencesNow = null;
    _preferences = null;
    _onFilesApplied = null;
    _suspended = false;
    await settings.resetForFreshStart();
    _set(SyncPhase.off);
  }

  Future<void> _setup(Future<void> Function() work) async {
    if (_busyWithSetup) {
      throw const SyncError('Sync is already being set up.');
    }
    await settings.ensureLoaded();
    _busyWithSetup = true;
    detach();
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    try {
      await work();
    } on Object {
      // What failed leaves sync as it was, and sync carries on.
      _busyWithSetup = false;
      _schedule();
      rethrow;
    } finally {
      _busyWithSetup = false;
      notifyListeners();
    }
  }

  void _requireLocalWorkspace() {
    if (!canSyncThisWorkspace) {
      throw const SyncError(
        'Only a workspace kept on this computer can be synced through a '
        'folder. A workspace on AppFlowy Cloud is already kept in step.',
      );
    }
  }

  /// Uploads a new epoch: every attached file, the workspace, this computer's
  /// name, and last the record that makes the epoch real.
  Future<SyncBinding> _publishEpoch({
    required SealedSyncRemote remote,
    required SyncVault? vault,
    required BackupDestination destination,
    required String epoch,
    required SyncEpochReason reason,
    required String filesRoot,
    required File? snapshot,
    int intervalSeconds = defaultSyncIntervalSeconds,
    bool syncPreferences = true,
    List<SyncPreferenceRecord> switches = const [],
  }) async {
    final bindingId = SyncBinding.idFor(destination);
    final folder = await settings.epochFolder(epoch, bindingId: bindingId);
    final state = File(p.join(folder.path, 'collab_state.json'));
    final scratch = await _scratchFolder();
    final bundle = snapshot ??
        File(p.join(scratch.path, 'base-${randomSyncToken(8)}.bundle'));
    final pack = File(p.join(scratch.path, 'base-${randomSyncToken(8)}.pack'));
    final infoFile =
        File(p.join(scratch.path, 'base-${randomSyncToken(8)}.json'));
    if ((vault == null) != (remote.key == null) ||
        (vault != null && !vault.accepts(remote.key!))) {
      throw const SyncError('The sync folder could not be sealed.');
    }
    final previous = settings.byDestination(destination) ?? binding;
    final previousDevices =
        _devicesByBinding[bindingId] ?? const <SyncDeviceSummary>[];
    final roster = [
      for (final device in previousDevices)
        if (!device.isThisComputer)
          SyncDeviceInfo(
            device: device.id,
            name: device.name,
            platform: device.platform,
            joinedAt: device.joinedAt ?? _clock(),
            lastSeen: device.lastSeen,
          ),
    ];
    try {
      if (vault != null) {
        final vaultFile =
            File(p.join(scratch.path, 'vault-${randomSyncToken(8)}.json'));
        try {
          await vaultFile.writeAsString(vault.encode());
          await remote.upload(SyncFileName.vault(epoch), vaultFile);
        } finally {
          await _discard(vaultFile);
        }
      }

      _report('Gathering the workspace…');
      var objects = 0;
      var uid = _uid ?? 0;
      var workspaceId = _workspaceId ?? '';
      var workspaceName = _workspaceName;
      if (snapshot != null) {
        final header = await readWorkspaceBundleHeader(snapshot);
        if (header == null) {
          throw const SyncError('The workspace being restored is damaged.');
        }
        uid = header.uid;
        workspaceId = header.workspaceId;
        workspaceName = header.workspaceName;
      } else {
        final exported = await _bridge.exportSnapshot(
          path: bundle.path,
          syncStatePath: state.path,
        );
        objects = exported.objectCount;
        uid = exported.uid;
        workspaceId = exported.workspaceId;
        workspaceName = exported.workspaceName;
      }

      _report('Sending attached files…');
      final scan = await scanSyncedFiles(
        dataPath: filesRoot,
        index: SyncFileIndex(),
        maximumBytes: maximumFileBytes,
      );
      final files = await _uploadFiles(remote, filesRoot, scan.changed);

      final prefs = previous != null && previous.epoch != epoch
          ? await SyncPreferencesIndex.load(
              await _preferencesIndexFile(
                previous.epoch,
                bindingId: previous.id,
              ),
              key: await _keyOf(previous),
            )
          : SyncPreferencesIndex();
      for (final record in switches) {
        prefs.note(record);
      }
      if (!prefs.credentialsOn) {
        prefs.dropCredentials();
      }
      (await _scanPreferences(
        prefs,
        on: syncPreferences,
        sealed: remote.isSealed,
      ))
          .forEach(prefs.note);

      _report('Sending the workspace…');
      await writeSyncPack(
        destination: pack,
        record: SyncPackRecord(
          kind: SyncPackKind.base,
          epoch: epoch,
          device: settings.deviceId,
          deviceName: _deviceName(),
          workspaceId: workspaceId,
          createdAt: _clock(),
          hasBundle: true,
          files: files,
          filesComplete: true,
          preferences: prefs.records,
        ),
        bundle: bundle,
      );
      final listing = SyncEpochListing(epoch);
      await remote.upload(SyncFileName.base(epoch), pack);
      await _announceDevice(remote, listing);
      final info = SyncEpochInfo(
        epoch: epoch,
        workspaceId: workspaceId,
        workspaceName: workspaceName,
        uid: uid,
        createdAt: _clock(),
        device: settings.deviceId,
        deviceName: _deviceName(),
        reason: reason,
        objectCount: objects,
        fileCount: files.length,
        bytes: pack.lengthSync(),
        roster: reason == SyncEpochReason.started ? const [] : roster,
      );
      await infoFile.writeAsString(info.encode());
      await remote.upload(SyncFileName.baseInfo(epoch), infoFile);

      final index = SyncFileIndex({
        for (final record in files) record.path: record,
      });
      await index.save(File(p.join(folder.path, 'files.json')));
      await prefs.save(
        await _preferencesIndexFile(epoch, bindingId: bindingId),
        key: remote.key,
      );

      return SyncBinding(
        id: bindingId,
        destination: destination,
        epoch: epoch,
        workspaceId: workspaceId,
        workspaceName: workspaceName,
        uid: uid,
        baseApplied: true,
        intervalSeconds: intervalSeconds,
        syncPreferences: syncPreferences,
        vaultId: remote.key?.vaultId ?? '',
      );
    } finally {
      if (snapshot == null) {
        await _discard(bundle);
      }
      await _discard(pack);
      await _discard(infoFile);
    }
  }

  /// Fetches the newest whole state of [info]'s epoch and schedules it to
  /// replace the workspace here at the next start.
  ///
  /// When [deferFiles] is true, attached files are recorded in `index.waiting`
  /// instead of blocking the join, and stream in parallel in the background as
  /// soon as the workspace opens.
  Future<void> _replaceFrom(
    SealedSyncRemote remote,
    BackupDestination destination,
    SyncEpochInfo info, {
    required String reason,
    bool deferFiles = false,
    bool skipSafetyCopy = false,
  }) async {
    final listing = SyncListing.of(await remote.list());
    final epoch = listing.epochs[info.epoch];
    if (epoch == null || epoch.base == null) {
      throw const SyncError('The sync folder changed while it was being read.');
    }

    if (!skipSafetyCopy) {
      _report('Keeping a copy of this workspace…');
      await _safetyCopy?.call(reason);
    }

    final infos = await _checkpointInfosOf(remote, epoch);
    final newest = _newestCheckpoint(epoch, infos);
    final source = newest?.pack ?? epoch.base!;
    final applied = newest == null
        ? <String, int>{}
        : Map<String, int>.from(infos[newest.pack.name]!.covers);

    final bindingId = SyncBinding.idFor(destination);
    final folder =
        await settings.epochFolder(epoch.id, bindingId: bindingId);
    final state = File(p.join(folder.path, 'collab_state.json'));
    final indexFile = File(p.join(folder.path, 'files.json'));
    final scratch = await _scratchFolder();
    final pack = File(p.join(scratch.path, 'join-${randomSyncToken(8)}.pack'));
    final bundle = File(p.join(scratch.path, 'join.bundle'));

    try {
      _report('Fetching the workspace…');
      await remote.download(source, pack);
      final record = await readSyncPack(source: pack, bundle: bundle);
      _checkPack(record, source);
      if (!record.hasBundle || record.workspaceId != info.workspaceId) {
        throw const SyncError('The workspace in the sync folder is damaged.');
      }

      final index = SyncFileIndex();
      if (deferFiles) {
        // Apply deletions immediately and queue attachments for async
        // background download right after the workspace opens.
        if (record.deleted.isNotEmpty) {
          await _applyFiles(remote, index, const [], record.deleted);
        }
        for (final fileRecord in record.files) {
          if (isSafeSyncPath(fileRecord.path) && fileRecord.hash.isNotEmpty) {
            index.waiting[fileRecord.path] = fileRecord;
          }
        }
      } else {
        _report('Fetching attached files…');
        await _applyFiles(remote, index, record.files, record.deleted);
      }
      await index.save(indexFile);

      // Settings never synced here take the folder's values. Joining does not
      // fail over them: the first rounds sort them out.
      _preferencesNow = null;
      final prefs = SyncPreferencesIndex();
      try {
        await _takePreferences(
          record.preferences,
          prefs,
          binding,
          sealed: remote.isSealed,
        );
      } on Object catch (error) {
        Log.warn('The synced settings were not taken while joining: $error');
      }
      await prefs.save(
        await _preferencesIndexFile(epoch.id, bindingId: bindingId),
        key: remote.key,
      );

      await _bridge.scheduleRestore(
        path: bundle.path,
        syncStatePath: state.path,
      );
      final joined = SyncBinding(
        id: bindingId,
        destination: destination,
        epoch: epoch.id,
        workspaceId: info.workspaceId,
        workspaceName: info.workspaceName,
        uid: info.uid,
        nextSeq: epoch.lastSeqOf(settings.deviceId) + 1,
        applied: applied,
        baseApplied: true,
        intervalSeconds:
            binding?.intervalSeconds ?? defaultSyncIntervalSeconds,
        syncPreferences: binding?.syncPreferences ?? true,
        vaultId: remote.key?.vaultId ?? '',
      );
      if (reason == 'restore-elsewhere') {
        await settings.upsertBinding(joined);
      } else {
        await settings.replaceAllBindings([joined]);
      }
      await settings.sweepEpochFolders(keep: epoch.id);
    } finally {
      await _discard(pack);
      await _discard(bundle);
    }
  }

  Future<void> _restartApplication() async {
    final restart = _restart;
    if (restart != null) {
      await restart();
    }
  }

  // --- Reading the folder ---------------------------------------------------

  Future<SyncEpochInfo> _readEpochInfo(
    SealedSyncRemote remote,
    SyncEpochListing epoch,
  ) async {
    final file = epoch.baseInfo;
    // Read once: an epoch's record never changes, and a sealed one is only
    // ever read with the key that opened it.
    final cacheKey = '${file?.id}@${remote.key?.vaultId ?? ''}';
    final known = _epochInfos[cacheKey];
    if (known != null) {
      return known;
    }
    final info = file == null
        ? null
        : SyncEpochInfo.tryParse(await remote.readText(file));
    if (info == null || info.epoch != epoch.id) {
      throw const SyncError(
        'The sync folder was written by a newer version of AppFlowy.',
      );
    }
    return _epochInfos[cacheKey] = info;
  }

  Future<Map<String, SyncCheckpointInfo>> _checkpointInfosOf(
    SealedSyncRemote remote,
    SyncEpochListing epoch,
  ) async {
    final infos = <String, SyncCheckpointInfo>{};
    for (final checkpoint in epoch.checkpoints) {
      final file = checkpoint.info;
      if (file == null) {
        continue;
      }
      var info = _checkpointInfos[checkpoint.pack.name];
      if (info == null) {
        try {
          info = SyncCheckpointInfo.tryParse(await remote.readText(file));
        } on Object catch (error) {
          Log.info('A sync checkpoint record could not be read: $error');
        }
        if (info != null) {
          _checkpointInfos[checkpoint.pack.name] = info;
        }
      }
      if (info != null) {
        infos[checkpoint.pack.name] = info;
      }
    }
    return infos;
  }

  SyncCheckpoint? _newestCheckpoint(
    SyncEpochListing epoch,
    Map<String, SyncCheckpointInfo> infos,
  ) {
    for (final checkpoint in epoch.checkpoints.reversed) {
      if (infos.containsKey(checkpoint.pack.name)) {
        return checkpoint;
      }
    }
    return null;
  }

  Future<Map<String, RemoteSyncFile>> _blobsOf(
    SealedSyncRemote remote,
  ) async {
    final known = _remoteBlobs[remote];
    if (known != null) {
      return known;
    }
    final blobs = <String, RemoteSyncFile>{};
    for (final file in await remote.list(blobs: true)) {
      final parsed = SyncFileName.parse(file.name);
      if (parsed?.kind == SyncFileKind.blob) {
        blobs[parsed!.hash] = file;
      }
    }
    return _remoteBlobs[remote] = blobs;
  }

  /// Every computer and phone syncing through [epoch]: those that have sent
  /// anything to it, and those from the epoch it carries on from that have
  /// not caught up yet.
  Future<void> _refreshDevices(
    SealedSyncRemote remote,
    SyncEpochListing epoch, {
    String bindingId = '',
  }) async {
    List<SyncDeviceInfo> roster = const [];
    try {
      roster = (await _readEpochInfo(remote, epoch)).roster;
    } on Object catch (error) {
      Log.info('Who else syncs could not be read: $error');
    }
    final active = epoch.devices;
    final summaries = <SyncDeviceSummary>[];
    for (final device in active) {
      var info = _deviceInfos[device];
      final file = epoch.deviceInfos[device];
      if (info == null && file != null) {
        try {
          info = SyncDeviceInfo.tryParse(await remote.readText(file));
        } on Object {
          info = null;
        }
        if (info != null) {
          _deviceInfos[device] = info;
        }
      }
      final isThisComputer = device == settings.deviceId;
      final listed = roster.where((entry) => entry.device == device);
      final before = listed.isEmpty ? null : listed.first;
      final name = info?.name.isNotEmpty == true
          ? info!.name
          : before?.name.isNotEmpty == true
              ? before!.name
              : (isThisComputer ? _deviceName() : 'Another computer');
      summaries.add(
        SyncDeviceSummary(
          id: device,
          name: name,
          platform: info?.platform ?? before?.platform ?? '',
          lastSeen: epoch.lastSeenOf(device),
          joinedAt: before?.joinedAt ?? info?.joinedAt,
          isThisComputer: isThisComputer,
        ),
      );
    }
    for (final entry in roster) {
      if (active.contains(entry.device)) {
        continue;
      }
      final isThisComputer = entry.device == settings.deviceId;
      summaries.add(
        SyncDeviceSummary(
          id: entry.device,
          name: entry.name.isNotEmpty
              ? entry.name
              : (isThisComputer ? _deviceName() : 'Another computer'),
          platform: entry.platform,
          lastSeen: entry.lastSeen,
          joinedAt: entry.joinedAt,
          isThisComputer: isThisComputer,
          waiting: !isThisComputer,
        ),
      );
    }
    if (bindingId.isNotEmpty) {
      _devicesByBinding[bindingId] = summaries;
      _rebuildMergedDevices();
      await _saveDevices(epoch.id, bindingId: bindingId, list: summaries);
    } else {
      _sortDeviceSummaries(summaries);
      _devices = summaries;
    }
  }

  void _rebuildMergedDevices() {
    final merged = <String, SyncDeviceSummary>{};
    for (final list in _devicesByBinding.values) {
      for (final item in list) {
        final prior = merged[item.id];
        if (prior == null) {
          merged[item.id] = item;
        } else {
          final lastSeen = switch ((prior.lastSeen, item.lastSeen)) {
            (final a?, final b?) => a.isAfter(b) ? a : b,
            (final a?, null) => a,
            (null, final b?) => b,
            _ => null,
          };
          merged[item.id] = SyncDeviceSummary(
            id: item.id,
            name: prior.name.isNotEmpty ? prior.name : item.name,
            isThisComputer: prior.isThisComputer || item.isThisComputer,
            platform:
                prior.platform.isNotEmpty ? prior.platform : item.platform,
            lastSeen: lastSeen,
            joinedAt: prior.joinedAt ?? item.joinedAt,
            waiting: prior.waiting || item.waiting,
          );
        }
      }
    }
    final list = merged.values.toList();
    _sortDeviceSummaries(list);
    _devices = list;
  }

  static void _sortDeviceSummaries(List<SyncDeviceSummary> summaries) {
    summaries.sort((a, b) {
      if (a.isThisComputer != b.isThisComputer) {
        return a.isThisComputer ? -1 : 1;
      }
      if (a.waiting != b.waiting) {
        return a.waiting ? 1 : -1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  /// Keeps the list where the next start finds it, so it is there before the
  /// first round has read the folder.
  Future<void> _saveDevices(
    String epoch, {
    required String bindingId,
    required List<SyncDeviceSummary> list,
  }) async {
    try {
      final file = File(
        p.join(
          (await settings.epochFolder(epoch, bindingId: bindingId)).path,
          'devices.json',
        ),
      );
      await file.writeAsString(
        jsonEncode([for (final device in list) device.toJson()]),
      );
    } on Object catch (error) {
      Log.info('The list of synced devices could not be kept: $error');
    }
  }

  Future<void> _loadDevices() async {
    final bound = boundBindings;
    if (bound.isEmpty || _devices.isNotEmpty) {
      return;
    }
    try {
      for (final b in bound) {
        final file = File(
          p.join(
            (await settings.epochFolder(b.epoch, bindingId: b.id)).path,
            'devices.json',
          ),
        );
        if (!file.existsSync()) {
          continue;
        }
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          _devicesByBinding[b.id] = [
            for (final entry in decoded)
              if (SyncDeviceSummary.fromJson(entry) case final device?) device,
          ];
        }
      }
      if (_devicesByBinding.isNotEmpty) {
        _rebuildMergedDevices();
        notifyListeners();
      }
    } on Object catch (error) {
      Log.info('The list of synced devices could not be read: $error');
    }
  }

  String _nameOf(String device) {
    final name = _deviceInfos[device]?.name ?? '';
    return name.isEmpty ? 'another computer' : name;
  }

  Future<String> _resolveDataPath() async {
    final resolve = _dataPath;
    if (resolve == null) {
      throw const SyncError('The workspace folder is not known yet.');
    }
    return resolve();
  }

  Future<Directory> _scratchFolder() async {
    final folder = await _scratch();
    await folder.create(recursive: true);
    return folder;
  }

  static Future<Directory> _defaultScratch() async =>
      Directory(p.join((await getTemporaryDirectory()).path, 'appflowy_sync'));

  static String _defaultDeviceName() {
    try {
      final name = Platform.localHostname;
      return name.isEmpty ? 'This computer' : name;
    } on Object {
      return 'This computer';
    }
  }

  static Future<void> _discard(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } on Object {
      // Scratch files are swept with the scratch folder.
    }
  }

  /// Refuses a pack that is not what its name says: one copied over another,
  /// or moved.
  static void _checkPack(SyncPackRecord record, RemoteSyncFile file) {
    final name = SyncFileName.parse(file.name);
    final matches = name != null &&
        record.epoch == name.epoch &&
        switch (name.kind) {
          SyncFileKind.base => record.kind == SyncPackKind.base,
          SyncFileKind.changes => record.kind == SyncPackKind.changes &&
              record.device == name.device &&
              record.seq == name.seq,
          SyncFileKind.checkpoint => record.kind == SyncPackKind.checkpoint &&
              record.device == name.device &&
              record.seq == name.seq,
          _ => false,
        };
    if (!matches) {
      throw const SyncError(
        'A file in the sync folder is not what its name says.',
      );
    }
  }
}

class _ProviderSession {
  const _ProviderSession({
    required this.original,
    required this.currentBinding,
    required this.plain,
    required this.remote,
    required this.epoch,
  });

  final SyncBinding original;
  final SyncBinding currentBinding;
  final SyncRemote plain;
  final SealedSyncRemote remote;
  final SyncEpochListing epoch;
}

