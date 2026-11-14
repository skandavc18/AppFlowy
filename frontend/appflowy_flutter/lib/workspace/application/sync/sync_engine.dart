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

  // The key of the folder this computer syncs with, and the record it opens;
  // null while the folder is not sealed, or is sealed with a password not
  // typed here yet.
  SyncKey? _key;
  SyncVault? _vault;

  // The record waiting for its password.
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
  List<SyncDeviceSummary> _devices = const [];
  SyncEpochInfo? _restoredElsewhere;
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

  final Map<String, SyncCheckpointInfo> _checkpointInfos = {};
  final Map<String, SyncDeviceInfo> _deviceInfos = {};
  Map<String, RemoteSyncFile>? _blobs;

  // Since when changes of [_unreachable] have been missing from the folder.
  // A moment's gap, say a record that could not be read, is not worth a word.
  DateTime? _unreachableSince;
  Set<String> _unreachable = const {};

  SyncSettings get settings => _settingsOverride ?? SyncSettings.instance;

  SyncBinding? get binding => settings.binding;

  SyncPhase get phase => _phase;

  /// What a running round is doing, for the interface.
  String get activity => _activity;

  /// Whether the last round failed because the account holding the sync
  /// folder has to be signed in to again.
  bool get needsSignIn => _phase == SyncPhase.failed && _needsSignIn;

  List<SyncDeviceSummary> get devices => _devices;

  /// The restore waiting on another computer, while [phase] says so.
  SyncEpochInfo? get restoredElsewhere => _restoredElsewhere;

  /// Whether the folder this computer syncs with is sealed.
  bool get isSealed => binding?.vaultId.isNotEmpty ?? false;

  /// The record whose password has to be typed before sync can go on.
  SyncVault? get lockedBy => _lockedBy;

  /// Whether the folder is locked because the AppFlowy password was changed
  /// on another computer, rather than never typed here.
  bool get passwordChangedElsewhere {
    final locked = _lockedBy;
    final vaultId = binding?.vaultId ?? '';
    return locked != null && vaultId.isNotEmpty && locked.id != vaultId;
  }

  /// Whether the folder is still sealed with an AppFlowy password this
  /// computer has since changed, waiting to be sealed again.
  bool get needsResealing => isSealed && (binding?.resealPending ?? false);

  /// Whether accounts, passwords and keys travel through the folder.
  bool get credentialsSynced => isSealed && _credentialsOn;

  /// How the last restore at start-up went, if there was one.
  WorkspaceRestoreOutcome? get lastRestore => _lastRestore;

  bool get isBusy => _running || _busyWithSetup;
  bool get isSuspended => _suspended;

  /// Whether the workspace that is open is a local one. A workspace on
  /// AppFlowy Cloud is already kept in step by the cloud.
  bool get canSyncThisWorkspace => _isLocalWorkspace && _workspaceId != null;

  /// Whether sync is set up for the workspace that is open.
  bool get isBoundHere {
    final binding = this.binding;
    return binding != null &&
        binding.workspaceId == _workspaceId &&
        binding.uid == _uid;
  }

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

  Future<File> _preferencesIndexFile(String epoch) async =>
      File(p.join((await settings.epochFolder(epoch)).path, 'prefs.json'));

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
    _unreachableSince = null;
    await settings.ensureLoaded();
    final vaultId = binding?.vaultId ?? '';
    if (vaultId.isNotEmpty && _key?.vaultId != vaultId) {
      _key = await _keys.read(vaultId);
    }
    if (isBoundHere) {
      await _loadDevices();
    }
    final pending = settings.pendingStart;
    if (pending != null && binding == null && canSyncThisWorkspace) {
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
    final current = binding;
    if (current != null && current.uid == _uid) {
      final folder = await settings.epochFolder(current.epoch);
      for (final name in ['files.json', 'prefs.json', 'collab_state.json']) {
        final file = File(p.join(folder.path, name));
        if (await file.exists()) await file.delete();
      }
      await settings
          .update(current.copyWith(applied: const {}, baseApplied: false));
    }
    _uid = null;
    _workspaceId = null;
    _workspaceName = '';
    _key = null;
    _preferencesNow = null;
    _preferences = null;
    _onFilesApplied = null;
    _set(SyncPhase.off);
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_suspended) return;
    final binding = this.binding;
    if (binding == null || !isBoundHere) {
      _set(SyncPhase.off);
      return;
    }
    if (binding.paused) {
      _set(SyncPhase.paused);
      return;
    }
    _set(binding.lastError.isEmpty ? SyncPhase.idle : SyncPhase.failed);
    _timer = Timer.periodic(
      Duration(seconds: max(5, binding.intervalSeconds)),
      (_) => unawaited(syncNow()),
    );
    unawaited(syncNow());
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
    final binding = this.binding;
    if (binding == null ||
        !isBoundHere ||
        binding.paused ||
        _restoredElsewhere != null) {
      return;
    }
    _set(SyncPhase.working, activity: 'Looking for changes…');
    _blobs = null;
    _preferencesNow = null;
    SyncRemote? plain;
    try {
      plain = await _openRemote(binding.destination);
      await plain.ensureReady();
      final listing = SyncListing.of(await plain.list());
      final current = listing.current;
      if (current == null) {
        throw const SyncError(
          'The sync folder no longer holds this workspace.',
        );
      }
      final key = await _keyFor(plain, current);
      if (_lockedBy != null) {
        _set(SyncPhase.locked);
        return;
      }
      if (key == null && binding.vaultId.isNotEmpty) {
        // Never followed into an epoch that is not sealed: everything here
        // would go out in the clear.
        throw const SyncError(
          'The sync folder is no longer sealed with the AppFlowy password. '
          'Set sync up again.',
        );
      }
      final remote = SealedSyncRemote(plain, key, scratch: _scratchFolder);
      var next = binding;
      if (current.id != binding.epoch) {
        if (current.id.compareTo(binding.epoch) < 0) {
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
            binding,
            info,
          );
          return;
        }
        next = await _follow(current, info, binding, key);
      }

      await _announceDevice(remote, current);
      await _refreshDevices(remote, current);
      next = await _pull(remote, listing, current, next);
      next = await _push(remote, current, next);
      next = await _maybeCheckpoint(remote, current, next);
      final missingSince = _unreachableSince;
      if (missingSince != null &&
          _clock().difference(missingSince) >= checkpointQuietPeriod) {
        throw SyncError(
          'Changes from ${_unreachable.map(_nameOf).join(', ')} are missing '
          'from the sync folder, so this computer cannot catch up with them. '
          'On a computer that has them, stop syncing and set sync up again '
          'in an empty folder, then join it here.',
        );
      }
      await settings.update(
        next.copyWith(lastSyncedAt: _clock(), lastError: ''),
      );
      _needsSignIn = false;
      _set(SyncPhase.idle);
    } on Object catch (error, stackTrace) {
      final detail = describeSyncError(error);
      _needsSignIn = error is ProviderFailure && error.status.needsReconnect;
      Log.warn('A sync round did not finish: $detail\n$stackTrace');
      final latest = this.binding;
      if (latest != null && latest.epoch == binding.epoch) {
        await settings.update(latest.copyWith(lastError: detail));
      }
      _set(SyncPhase.failed, activity: detail);
    } finally {
      plain?.dispose();
    }
  }

  /// The key [epoch] is sealed with, as this computer keeps it or as the
  /// AppFlowy password makes it; null for an epoch never sealed. Leaves
  /// [_lockedBy] set when this computer has no password that opens it.
  Future<SyncKey?> _keyFor(SyncRemote remote, SyncEpochListing epoch) async {
    final file = epoch.vault;
    if (file == null) {
      _lockedBy = null;
      return null;
    }
    final vault = await _readVault(remote, file);
    final key = await _openVault(vault);
    _lockedBy = key == null ? vault : null;
    if (key != null) {
      _key = key;
      _vault = vault;
    }
    return key;
  }

  /// The key for [vault]: the one in memory, the one kept in the keyring, or
  /// the one the AppFlowy password makes.
  Future<SyncKey?> _openVault(SyncVault vault) async {
    final held = _key;
    if (held != null && vault.accepts(held)) {
      return held;
    }
    final kept = await _keys.read(vault.id);
    if (kept != null && vault.accepts(kept)) {
      return kept;
    }
    final password = await _passwords.current();
    if (password == null || _triedPasswords[vault.id] == password) {
      return null;
    }
    _triedPasswords[vault.id] = password;
    final key = await vault.unlock(password);
    if (key != null) {
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
    final held = _key;
    if (held != null && held.vaultId == vaultId) {
      return held;
    }
    return _keys.read(vaultId);
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
      await _preferencesIndexFile(binding.epoch),
      key: await _keyOf(binding),
    );
    final next = SyncBinding(
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
    await carried.save(await _preferencesIndexFile(current.id), key: key);
    await settings.update(next);
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
    final folder = await settings.epochFolder(epoch.id);
    final state = File(p.join(folder.path, 'collab_state.json'));
    final indexFile = File(p.join(folder.path, 'files.json'));
    final index = await SyncFileIndex.load(indexFile);
    final prefsFile = await _preferencesIndexFile(epoch.id);
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
      _unreachableSince = null;
    } else {
      if (_unreachableSince == null) {
        _unreachableSince = _clock();
        Log.warn(
          'Changes from ${plan.unreachable.map(_nameOf).join(', ')} are not '
          'in the sync folder any more.',
        );
      }
      _unreachable = plan.unreachable;
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
      await settings.update(next);
      await index.save(indexFile);
      await prefs.save(prefsFile, key: remote.key);
    }

    for (final change in plan.changes) {
      _report('Merging changes from ${_nameOf(change.device)}…');
      await _applyPack(remote, change.file, state, index, prefs, next);
      next = next.copyWith(
        applied: {...next.applied, change.device: change.seq},
      );
      await settings.update(next);
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
    await settings.update(next);
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
    final folder = await settings.epochFolder(epoch.id);
    final state = File(p.join(folder.path, 'collab_state.json'));
    final indexFile = File(p.join(folder.path, 'files.json'));
    final index = await SyncFileIndex.load(indexFile);
    final prefsFile = await _preferencesIndexFile(epoch.id);
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
      _outbox.removeWhere(
        (record) => !record.isLaterThan(prefs.entries[record.key]),
      );
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
      await settings.update(next);
      return next;
    } finally {
      await _discard(bundle);
      await _discard(pack);
    }
  }

  /// Puts the contents of [changed] in the folder, each under its hash.
  ///
  /// Each file is copied aside and hashed again before it goes: a file changed
  /// while it was being sent must never be stored under the hash of what it
  /// was.
  Future<List<SyncFileRecord>> _uploadFiles(
    SealedSyncRemote remote,
    String dataPath,
    List<SyncFileRecord> changed,
  ) async {
    if (changed.isEmpty) {
      return const [];
    }
    final blobs = await _blobsOf(remote);
    final scratch = await _scratchFolder();
    final sent = <SyncFileRecord>[];
    for (final record in changed) {
      final source = File(p.joinAll([dataPath, ...p.posix.split(record.path)]));
      final copy = File(p.join(scratch.path, 'file-${randomSyncToken(8)}'));
      try {
        await source.copy(copy.path);
        final hash = await hashFile(copy);
        final name = remote.blobName(hash);
        if (!blobs.containsKey(name)) {
          blobs[name] = await remote.upload(
            SyncFileName.blob(name),
            copy,
            blob: true,
          );
        }
        sent.add(
          SyncFileRecord(
            path: record.path,
            hash: hash,
            bytes: copy.lengthSync(),
            modified: record.modified,
          ),
        );
      } on FileSystemException catch (error) {
        // Removed or locked since the scan; the next round sees it as it is.
        Log.info('A file was not synced this time: $error');
      } finally {
        await _discard(copy);
      }
    }
    return sent;
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
    final folder = await settings.epochFolder(epoch.id);
    final index =
        await SyncFileIndex.load(File(p.join(folder.path, 'files.json')));
    final prefs = await SyncPreferencesIndex.load(
      await _preferencesIndexFile(epoch.id),
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

  /// Starts syncing this workspace into an empty folder, sealed with the
  /// AppFlowy password when [encrypt] is true (the default).
  Future<void> startNew(
    BackupDestination destination, {
    bool encrypt = true,
  }) =>
      encrypt ? _startSealed(destination) : startUnsealed(destination);

  Future<void> _startSealed(BackupDestination destination) => _setup(() async {
        _requireLocalWorkspace();
        final password = await _requirePassword();
        final plain = await _openRemote(destination);
        try {
          await plain.ensureReady();
          final listing = SyncListing.of(await plain.list());
          if (!listing.isEmpty) {
            throw const SyncError('That folder already holds a workspace.');
          }
          _report('Sealing the folder…');
          final (vault, key) = await _newVault(password);
          final epoch = newSyncEpoch(_clock());
          final binding = await _publishEpoch(
            remote: SealedSyncRemote(plain, key, scratch: _scratchFolder),
            vault: vault,
            destination: destination,
            epoch: epoch,
            reason: SyncEpochReason.started,
            filesRoot: await _resolveDataPath(),
            snapshot: null,
          );
          await _keep(key, vault);
          await settings.update(binding);
          await settings.sweepEpochFolders(keep: epoch);
          await _removeFiles(plain, listing.legacyVaults);
        } finally {
          plain.dispose();
        }
        _schedule();
      });

  /// Starts syncing into an empty folder without sealing it.
  Future<void> startUnsealed(BackupDestination destination) => _setup(() async {
        _requireLocalWorkspace();
        final plain = await _openRemote(destination);
        try {
          await plain.ensureReady();
          final listing = SyncListing.of(await plain.list());
          if (!listing.isEmpty) {
            throw const SyncError('That folder already holds a workspace.');
          }
          final epoch = newSyncEpoch(_clock());
          final binding = await _publishEpoch(
            remote: SealedSyncRemote(plain, null, scratch: _scratchFolder),
            vault: null,
            destination: destination,
            epoch: epoch,
            reason: SyncEpochReason.started,
            filesRoot: await _resolveDataPath(),
            snapshot: null,
          );
          await settings.update(binding);
          await settings.sweepEpochFolders(keep: epoch);
          await _removeFiles(plain, listing.legacyVaults);
        } finally {
          plain.dispose();
        }
        _schedule();
      });

  Future<void> _startPending(
    BackupDestination destination, {
    bool encrypt = true,
  }) async {
    try {
      await startNew(destination, encrypt: encrypt);
      await settings.setPendingStart(null);
      notify?.call('"$_workspaceName" is syncing.');
    } on Object catch (error) {
      Log.warn('Sync could not start in the folder chosen at first: $error');
      notify?.call(
        'Sync could not start: ${describeSyncError(error)}',
        isError: true,
      );
    }
  }

  /// Syncs this workspace with a folder that already holds it.
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
        await settings.sweepEpochFolders(keep: info.epoch);
        if (key != null) {
          await _keep(key, inspection.vault);
        }
        await _adoptPasswordOf(inspection);
        await settings.update(
          SyncBinding(
            destination: destination,
            epoch: info.epoch,
            workspaceId: info.workspaceId,
            workspaceName: _workspaceName,
            uid: info.uid,
            intervalSeconds:
                binding?.intervalSeconds ?? defaultSyncIntervalSeconds,
            syncPreferences: binding?.syncPreferences ?? true,
            vaultId: key?.vaultId ?? '',
          ),
        );
        _schedule();
      });

  /// Replaces the workspace on this computer with the one in [destination].
  ///
  /// The workspace here is copied aside first. AppFlowy restarts to finish.
  Future<void> join(
    BackupDestination destination,
    SyncFolderInspection inspection,
  ) =>
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
  Future<void> loadRestoredWorkspace() => _setup(() async {
        final info = _restoredElsewhere;
        final binding = this.binding;
        if (info == null || binding == null) {
          return;
        }
        final plain = await _openRemote(binding.destination);
        try {
          await plain.ensureReady();
          final current = SyncListing.of(await plain.list()).current;
          if (current == null) {
            throw const SyncError(
              'The sync folder no longer holds this workspace.',
            );
          }
          final key = await _keyFor(plain, current);
          if (_lockedBy != null) {
            throw const SyncError('Type your AppFlowy password first.');
          }
          await _replaceFrom(
            SealedSyncRemote(plain, key, scratch: _scratchFolder),
            binding.destination,
            info,
            reason: 'restore-elsewhere',
          );
        } finally {
          plain.dispose();
        }
        await _restartApplication();
      });

  /// Forgets the key held in memory, as a computer that never had it.
  @visibleForTesting
  void forgetKeyInMemory() => _key = null;

  /// Types the AppFlowy password on this computer, for the folder that asked
  /// for it, and carries on syncing. It becomes this computer's AppFlowy
  /// password too: the folder is sealed with nothing else.
  Future<void> unlock(String password) async {
    final vault = _lockedBy;
    if (vault == null) {
      return;
    }
    final key = await vault.unlock(password);
    if (key == null) {
      throw const SyncError(
        'That is not the AppFlowy password this folder is sealed with.',
      );
    }
    await _keep(key, vault);
    await _passwords.adopt(password);
    _schedule();
  }

  /// Seals the folder with the AppFlowy password: a folder written before
  /// folders were sealed, or one still sealed with the password this computer
  /// had before it was changed.
  ///
  /// Everything is merged first, then the workspace carries on in an epoch
  /// sealed with the password, which the others merge into once they have
  /// it. What the folder held before is removed.
  Future<void> sealWithAppPassword() => _setup(() async {
        final binding = this.binding;
        if (binding == null || !isBoundHere) {
          throw const SyncError('Sync is not set up for this workspace.');
        }
        final password = await _requirePassword();
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
              // Sealed with it already: another computer got there first, or
              // the password went back to what it was.
              if (binding.resealPending) {
                await settings.update(binding.copyWith(resealPending: false));
              }
              return;
            }
            key = await _keyOf(binding);
            if (key == null || !vault.accepts(key)) {
              throw const SyncError('Type your AppFlowy password first.');
            }
          }
          _report('Taking in what the others sent…');
          final previous =
              SealedSyncRemote(plain, key, scratch: _scratchFolder);
          await _refreshDevices(previous, current);
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
          await settings.update(next);
          await settings.sweepEpochFolders(keep: epoch);

          // Nothing sealed the old way, or not at all, stays behind.
          listing = SyncListing.of(await plain.list());
          await _removeAllBut(plain, listing, epoch, keepBlobs: false);
        } finally {
          plain.dispose();
        }
        _schedule();
      });

  /// Turns encryption off for the sync folder, carrying the workspace on in an
  /// unsealed epoch and removing sealed files from the folder.
  ///
  /// Requires the current key to be known first so nothing sent by other
  /// computers is left behind and nobody without the AppFlowy password can
  /// unseal the folder. Settings and credentials do not travel unsealed.
  Future<void> unsealSyncFolder() => _setup(() async {
        final binding = this.binding;
        if (binding == null || !isBoundHere) {
          throw const SyncError('Sync is not set up for this workspace.');
        }
        if (binding.vaultId.isEmpty) {
          return;
        }
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
          final key = await _keyFor(plain, current);
          if (_lockedBy != null || key == null) {
            throw const SyncError('Type your AppFlowy password first.');
          }
          _report('Taking in what the others sent…');
          final previous =
              SealedSyncRemote(plain, key, scratch: _scratchFolder);
          await _refreshDevices(previous, current);
          final pulled = await _pull(previous, listing, current, binding);

          _report('Updating the sync folder…');
          final epoch = nextSyncEpoch(binding.epoch, _clock());
          final next = await _publishEpoch(
            remote: SealedSyncRemote(plain, null, scratch: _scratchFolder),
            vault: null,
            destination: binding.destination,
            epoch: epoch,
            reason: SyncEpochReason.continued,
            filesRoot: await _resolveDataPath(),
            snapshot: null,
            intervalSeconds: pulled.intervalSeconds,
            syncPreferences: pulled.syncPreferences,
          );
          final oldVaultId = binding.vaultId;
          _key = null;
          _vault = null;
          _lockedBy = null;
          _credentialsOn = false;
          if (oldVaultId.isNotEmpty) {
            await _keys.forget(oldVaultId);
          }
          await settings.update(next);
          await settings.sweepEpochFolders(keep: epoch);

          listing = SyncListing.of(await plain.list());
          await _removeAllBut(plain, listing, epoch, keepBlobs: false);
        } finally {
          plain.dispose();
        }
        _schedule();
      });

  /// Notes that the AppFlowy password was changed here while the folder could
  /// not be sealed again, so it is sealed as soon as it can be.
  Future<void> markResealPending() async {
    final binding = this.binding;
    if (binding == null || binding.vaultId.isEmpty || binding.resealPending) {
      return;
    }
    await settings.update(binding.copyWith(resealPending: true));
    notifyListeners();
  }

  /// Whether accounts, passwords and keys travel through the folder.
  ///
  /// Turned off, they are taken out of the folder: the workspace carries on
  /// in an epoch without them, and the files that held them are removed.
  /// Every computer keeps the ones it has.
  Future<void> setSyncCredentials(bool on) async {
    final binding = this.binding;
    if (binding == null || !isBoundHere || binding.vaultId.isEmpty) {
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
        final key = await _keyFor(plain, current);
        final vault = _vault;
        if (_lockedBy != null || key == null || vault == null) {
          throw const SyncError('Type your AppFlowy password first.');
        }
        final remote = SealedSyncRemote(plain, key, scratch: _scratchFolder);
        _report('Taking in what the others sent…');
        await _refreshDevices(remote, current);
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
        await settings.update(next);
        await settings.sweepEpochFolders(keep: epoch);
        listing = SyncListing.of(await plain.list());
        await _removeAllBut(plain, listing, epoch, keepBlobs: true);
      } finally {
        plain.dispose();
      }
    });
    _schedule();
  }

  /// The epoch a restore made here will be synced in, or null when sync is
  /// not set up for this workspace.
  ///
  /// Chosen before the restore is scheduled, because the restore writes the
  /// sync bookkeeping for exactly that epoch.
  String? newRestoreEpoch() {
    final binding = this.binding;
    return binding != null && isBoundHere
        ? nextSyncEpoch(binding.epoch, _clock())
        : null;
  }

  /// Publishes a restore made on this computer as [epoch], so every other
  /// computer takes it up too.
  ///
  /// [snapshot] is the workspace being restored and [filesRoot] the folder that
  /// holds the attached files it comes with. When the folder cannot be updated,
  /// sync is turned off here rather than left to send the workspace as it was
  /// before the restore.
  Future<void> publishRestore({
    required String epoch,
    required File snapshot,
    required String filesRoot,
  }) async {
    final binding = this.binding;
    if (binding == null || !isBoundHere) {
      return;
    }
    _busyWithSetup = true;
    detach();
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    try {
      final plain = await _openRemote(binding.destination);
      try {
        await plain.ensureReady();
        SyncKey? key;
        SyncVault? vault;
        final mine = SyncListing.of(await plain.list()).epochs[binding.epoch];
        if (binding.vaultId.isNotEmpty) {
          key = mine == null ? null : await _keyFor(plain, mine);
          vault = _vault;
          if (key == null || vault == null || vault.id != key.vaultId) {
            throw const SyncError('Type your AppFlowy password first.');
          }
        }
        if (mine != null) {
          try {
            await _refreshDevices(
              SealedSyncRemote(plain, key, scratch: _scratchFolder),
              mine,
            );
          } on Object catch (error) {
            Log.info('Who else syncs could not be read: $error');
          }
        }
        final next = await _publishEpoch(
          remote: SealedSyncRemote(plain, key, scratch: _scratchFolder),
          vault: vault,
          destination: binding.destination,
          epoch: epoch,
          reason: SyncEpochReason.restored,
          filesRoot: filesRoot,
          snapshot: snapshot,
          intervalSeconds: binding.intervalSeconds,
          syncPreferences: binding.syncPreferences,
        );
        await settings.update(next);
        await settings.sweepEpochFolders(keep: epoch);
      } finally {
        plain.dispose();
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
    _key = key;
    if (vault != null) {
      _vault = vault;
    }
    _lockedBy = null;
  }

  /// Removes every file of every epoch but [epoch], and, unless [keepBlobs],
  /// every attached file the new epoch does not name.
  Future<void> _removeAllBut(
    SyncRemote plain,
    SyncListing listing,
    String epoch, {
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
        File(p.join((await settings.epochFolder(epoch)).path, 'files.json')),
      );
      final named = {
        for (final record in index.entries.values)
          _key?.blobName(record.hash) ?? record.hash,
      };
      for (final file in await plain.list(blobs: true)) {
        final parsed = SyncFileName.parse(file.name);
        if (parsed?.kind == SyncFileKind.blob &&
            !named.contains(parsed!.hash)) {
          doomed.add(file);
        }
      }
      _blobs = null;
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
  Future<String> collabStatePath(String epoch) async =>
      p.join((await settings.epochFolder(epoch)).path, 'collab_state.json');

  Future<void> setPaused(bool paused) async {
    final binding = this.binding;
    if (binding == null) {
      return;
    }
    await settings.update(binding.copyWith(paused: paused));
    _schedule();
  }

  /// Whether this computer's settings follow the workspace. Turned on, the
  /// settings the folder holds are taken here first: what this computer had
  /// while it was off is not sent over everybody else's.
  Future<void> setSyncPreferences(bool on) async {
    final binding = this.binding;
    if (binding == null || binding.syncPreferences == on) {
      return;
    }
    final next = binding.copyWith(syncPreferences: on);
    if (on) {
      try {
        await adoptIndexedPreferences(
          source: _preferencesFor(
            next,
            sealed: isSealed,
            credentials: _credentialsOn,
          ),
          index: await SyncPreferencesIndex.load(
            await _preferencesIndexFile(binding.epoch),
            key: await _keyOf(binding),
          ),
        );
      } on Object catch (error) {
        Log.warn('The synced settings could not be taken: $error');
      }
    }
    await settings.update(next);
    notifyListeners();
    if (on) {
      unawaited(syncNow());
    }
  }

  Future<void> setInterval(int seconds) async {
    final binding = this.binding;
    if (binding == null) {
      return;
    }
    await settings.update(binding.copyWith(intervalSeconds: seconds));
    _schedule();
  }

  /// Stops syncing here. The folder and everything in it stay as they are.
  Future<void> disconnect() async {
    detach();
    _restoredElsewhere = null;
    _devices = const [];
    await settings.update(null);
    await settings.sweepEpochFolders();
    _set(SyncPhase.off);
  }

  /// Removes all AppFlowy sync files and synced blobs from [destination] (or
  /// the currently bound destination), leaving any unrelated files untouched.
  Future<void> clearRemoteSyncFolder([BackupDestination? override]) async {
    final target = override ?? binding?.destination;
    if (target == null || !target.isReady) {
      return;
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

  /// Clears all local sync state (and, when [clearRemote] is true, removes
  /// synced data from the cloud sync folder first) for a fresh start.
  Future<void> resetForFreshStart({bool clearRemote = false}) async {
    _suspended = true;
    detach();
    _again = false;
    await Future.wait(_attachments.toList());
    await _rounds?.future;
    final current = binding;
    if (clearRemote && current != null) {
      await clearRemoteSyncFolder(current.destination);
    }
    if (current != null && current.vaultId.isNotEmpty) {
      try {
        await _keys.forget(current.vaultId);
      } on Object catch (error) {
        Log.warn('Sync vault key could not be cleared: $error');
      }
    }
    _uid = null;
    _workspaceId = null;
    _workspaceName = '';
    _key = null;
    _vault = null;
    _lockedBy = null;
    _restoredElsewhere = null;
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
    final folder = await settings.epochFolder(epoch);
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
    // Who synced the epoch this one carries on from, so the ones still
    // catching up are listed until they have.
    final roster = [
      for (final device in _devices)
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
        // First, so that nothing of the epoch is ever there without the
        // record of the password it is sealed with.
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

      // Everything known of the settings so far — including those kept for
      // other kinds of computer — with what changed here since.
      final previous = binding;
      final prefs = previous != null && previous.epoch != epoch
          ? await SyncPreferencesIndex.load(
              await _preferencesIndexFile(previous.epoch),
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
      await prefs.save(await _preferencesIndexFile(epoch), key: remote.key);

      return SyncBinding(
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

  /// Fetches the newest whole state of [info]'s epoch, with its attached files,
  /// and schedules it to replace the workspace here at the next start.
  Future<void> _replaceFrom(
    SealedSyncRemote remote,
    BackupDestination destination,
    SyncEpochInfo info, {
    required String reason,
  }) async {
    final listing = SyncListing.of(await remote.list());
    final epoch = listing.epochs[info.epoch];
    if (epoch == null || epoch.base == null) {
      throw const SyncError('The sync folder changed while it was being read.');
    }

    _report('Keeping a copy of this workspace…');
    await _safetyCopy?.call(reason);

    final infos = await _checkpointInfosOf(remote, epoch);
    final newest = _newestCheckpoint(epoch, infos);
    final source = newest?.pack ?? epoch.base!;
    final applied = newest == null
        ? <String, int>{}
        : Map<String, int>.from(infos[newest.pack.name]!.covers);

    final folder = await settings.epochFolder(epoch.id);
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

      _report('Fetching attached files…');
      final index = SyncFileIndex();
      await _applyFiles(remote, index, record.files, record.deleted);
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
      await prefs.save(await _preferencesIndexFile(epoch.id), key: remote.key);

      await _bridge.scheduleRestore(
        path: bundle.path,
        syncStatePath: state.path,
      );
      await settings.update(
        SyncBinding(
          destination: destination,
          epoch: epoch.id,
          workspaceId: info.workspaceId,
          workspaceName: info.workspaceName,
          uid: info.uid,
          nextSeq: epoch.lastSeqOf(settings.deviceId) + 1,
          // Changes this computer sent before, and the checkpoint does not
          // hold, are merged back by the first round.
          applied: applied,
          baseApplied: true,
          intervalSeconds:
              binding?.intervalSeconds ?? defaultSyncIntervalSeconds,
          syncPreferences: binding?.syncPreferences ?? true,
          vaultId: remote.key?.vaultId ?? '',
        ),
      );
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
    final known = _blobs;
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
    return _blobs = blobs;
  }

  /// Every computer and phone syncing through [epoch]: those that have sent
  /// anything to it, and those from the epoch it carries on from that have
  /// not caught up yet.
  Future<void> _refreshDevices(
    SealedSyncRemote remote,
    SyncEpochListing epoch,
  ) async {
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
          // This computer is about to announce itself in the epoch.
          waiting: !isThisComputer,
        ),
      );
    }
    summaries.sort((a, b) {
      if (a.isThisComputer != b.isThisComputer) {
        return a.isThisComputer ? -1 : 1;
      }
      if (a.waiting != b.waiting) {
        return a.waiting ? 1 : -1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _devices = summaries;
    await _saveDevices(epoch.id);
  }

  /// Keeps the list where the next start finds it, so it is there before the
  /// first round has read the folder.
  Future<void> _saveDevices(String epoch) async {
    if (binding?.epoch != epoch) {
      return;
    }
    try {
      final file = File(
        p.join((await settings.epochFolder(epoch)).path, 'devices.json'),
      );
      await file.writeAsString(
        jsonEncode([for (final device in _devices) device.toJson()]),
      );
    } on Object catch (error) {
      Log.info('The list of synced devices could not be kept: $error');
    }
  }

  Future<void> _loadDevices() async {
    final binding = this.binding;
    if (binding == null || _devices.isNotEmpty) {
      return;
    }
    try {
      final file = File(
        p.join(
          (await settings.epochFolder(binding.epoch)).path,
          'devices.json',
        ),
      );
      if (!file.existsSync()) {
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        _devices = [
          for (final entry in decoded)
            if (SyncDeviceSummary.fromJson(entry) case final device?) device,
        ];
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
