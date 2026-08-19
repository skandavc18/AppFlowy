// Taking a copy, and putting one back.
//
// This is the one place that knows the whole order of events: gather, squeeze,
// seal, send, keep a copy here, sweep what is too old. Everything it uses is
// separately testable, so what is left here is the sequence itself and the
// progress reporting that makes a long job bearable to watch.

import 'dart:async';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup_archive.dart';
import 'package:appflowy/workspace/application/backup/backup_crypto.dart';
import 'package:appflowy/workspace/application/backup/backup_manifest.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/backup/backup_settings.dart';
import 'package:appflowy/workspace/application/backup/backup_target.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Which part of a copy is happening.
enum BackupStage {
  idle,
  gathering,
  sealing,
  sending,
  keeping,
  tidying,
  finished,
  failed,
}

/// Where a restore has got to.
enum RestoreStage { idle, fetching, opening, unpacking, finished, failed }

@immutable
class BackupProgress {
  const BackupProgress({
    this.stage = BackupStage.idle,
    this.done = 0,
    this.total = 0,
    this.detail = '',
  });

  final BackupStage stage;
  final int done;
  final int total;
  final String detail;

  bool get isRunning =>
      stage != BackupStage.idle &&
      stage != BackupStage.finished &&
      stage != BackupStage.failed;

  /// How far along, or null when the length is not known yet.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0, 1);
}

@immutable
class RestoreProgress {
  const RestoreProgress({
    this.stage = RestoreStage.idle,
    this.done = 0,
    this.total = 0,
    this.detail = '',
  });

  final RestoreStage stage;
  final int done;
  final int total;
  final String detail;

  bool get isRunning =>
      stage != RestoreStage.idle &&
      stage != RestoreStage.finished &&
      stage != RestoreStage.failed;

  double? get fraction => total <= 0 ? null : (done / total).clamp(0, 1);
}

/// What a restore produced.
@immutable
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.folder,
    required this.dataFolder,
    required this.fileCount,
  });

  /// The folder that was chosen.
  final Directory folder;

  /// The workspace inside it, ready to be pointed at.
  final Directory dataFolder;

  final int fileCount;
}

/// Raised when a copy or a restore cannot go ahead.
class BackupError implements Exception {
  const BackupError(this.detail, {this.needsPassphrase = false});

  final String detail;

  /// Whether the only thing missing is the passphrase, which the interface
  /// answers by asking for it rather than by showing a failure.
  final bool needsPassphrase;

  @override
  String toString() => 'BackupError: $detail';
}

class BackupService extends ChangeNotifier {
  BackupService._();

  static final BackupService instance = BackupService._();

  /// The folder a copy is built in before it goes anywhere.
  static const String stagingFolderName = 'appflowy_backup_staging';

  /// Where copies kept on this computer go when no folder was chosen.
  static const String defaultLocalFolderName = 'AppFlowyBackups';

  BackupProgress _progress = const BackupProgress();
  RestoreProgress _restore = const RestoreProgress();

  /// The signed-in person, needed only for AppFlowy Cloud.
  UserProfilePB? userProfile;

  BackupProgress get progress => _progress;

  RestoreProgress get restoreProgress => _restore;

  bool get isRunning => _progress.isRunning || _restore.isRunning;

  BackupSettings get _settings => BackupSettings.instance;

  // --- Taking a copy ------------------------------------------------------

  /// Runs one copy now.
  ///
  /// Throws [BackupError] rather than recording a failure when it could not
  /// even start, so the interface can tell "nothing is set up yet" from "it
  /// tried and something went wrong".
  Future<BackupOutcome> runNow({bool automatic = false}) async {
    if (isRunning) {
      throw const BackupError('A copy is already being made.');
    }
    await _settings.ensureLoaded();
    final policy = _settings.policy;
    if (!policy.destination.isReady) {
      throw const BackupError('There is nowhere to put a copy yet.');
    }
    if (policy.parts.isEmpty) {
      throw const BackupError('Nothing has been chosen to copy.');
    }

    Uint8List? key;
    if (policy.encrypt) {
      key = await _resolveKey(policy);
      if (key == null) {
        throw const BackupError(
          'The backup passphrase has not been entered on this computer yet.',
          needsPassphrase: true,
        );
      }
    }

    final started = DateTime.now();
    final id = newBackupId(started);
    final staging = Directory(
      p.join((await getTemporaryDirectory()).path, stagingFolderName, id),
    );
    await staging.create(recursive: true);

    BackupTarget? target;
    try {
      _report(const BackupProgress(stage: BackupStage.gathering));

      final dataPath = await getIt<ApplicationDataStorage>().getPath();
      final preferencesPath = await _preferencesPath();

      // The copy that is sent away and the copy kept here can be squeezed
      // differently, and when they are they really are two different files —
      // pretending otherwise would silently ignore one of the two settings.
      final destinationArchive = File(
        p.join(staging.path, '$id.remote.zip'),
      );
      final destinationResult = await writeBackupArchive(
        dataPath: dataPath,
        destination: destinationArchive,
        parts: policy.parts,
        compression: policy.compressionForDestination,
        preferencesPath: preferencesPath,
        maximumFileBytes: policy.maximumFileBytes,
        onProgress: (done, total) => _report(
          BackupProgress(
            stage: BackupStage.gathering,
            done: done,
            total: total,
          ),
        ),
      );

      var manifest = BackupManifest(
        id: id,
        createdAt: started.toUtc(),
        parts: policy.parts,
        compression: policy.compressionForDestination,
        fileCount: destinationResult.fileCount,
        rawBytes: destinationResult.rawBytes,
        archiveBytes: destinationResult.archiveBytes,
        omissions: destinationResult.omissions,
        appVersion: await _appVersion(),
        workspaceName: userProfile?.name ?? '',
        hint: policy.hint,
      );

      var toSend = destinationArchive;
      if (key != null) {
        _report(const BackupProgress(stage: BackupStage.sealing));
        final sealed = File(p.join(staging.path, '$id.remote.sealed'));
        final sealedBytes = await sealBackupFile(
          source: destinationArchive,
          destination: sealed,
          key: key,
          onProgress: (done, total) => _report(
            BackupProgress(
              stage: BackupStage.sealing,
              done: done,
              total: total,
            ),
          ),
        );
        toSend = sealed;
        manifest = manifest.copyWith(
          encrypted: true,
          salt: policy.salt,
          iterations: policy.iterations,
          verifier: policy.verifier,
          chunkBytes: backupChunkBytes,
          sealedBytes: sealedBytes,
        );
        // A manifest sits in the clear beside a sealed archive, so it must not
        // describe what is inside one.
        manifest = manifest.redacted();
      }

      _report(BackupProgress(stage: BackupStage.sending, detail: id));
      target = await openTarget();
      await target.ensureReady();
      final stored = await target.put(
        archive: toSend,
        manifest: manifest,
        onProgress: (done, total) => _report(
          BackupProgress(
            stage: BackupStage.sending,
            done: done,
            total: total,
          ),
        ),
      );
      await _settings.rememberCopy(stored);

      if (policy.keepLocalCopy && policy.destination.kind.isRemote) {
        _report(const BackupProgress(stage: BackupStage.keeping));
        await _keepLocalCopy(
          policy: policy,
          id: id,
          manifest: manifest,
          key: key,
          staging: staging,
          dataPath: dataPath,
          preferencesPath: preferencesPath,
          sealedForDestination: toSend,
        );
      }

      _report(const BackupProgress(stage: BackupStage.tidying));
      await _sweep(target, policy);

      final outcome = BackupOutcome(
        at: DateTime.now(),
        succeeded: true,
        backupId: id,
        bytes: manifest.storedBytes,
      );
      await _settings.recordRun(outcome);
      _report(
        BackupProgress(
          stage: BackupStage.finished,
          done: manifest.storedBytes,
          total: manifest.storedBytes,
          detail: id,
        ),
      );
      return outcome;
    } on Object catch (error) {
      final detail = _describe(error);
      Log.warn('A backup did not finish: $detail');
      final outcome = BackupOutcome(
        at: DateTime.now(),
        succeeded: false,
        backupId: id,
        detail: detail,
      );
      await _settings.recordRun(outcome);
      _report(BackupProgress(stage: BackupStage.failed, detail: detail));
      if (!automatic) {
        rethrow;
      }
      return outcome;
    } finally {
      target?.dispose();
      await _discard(staging);
    }
  }

  /// Builds the copy that stays on this computer.
  ///
  /// It reuses the one that was just sent whenever the two settings agree,
  /// which is the common case; only a genuine disagreement costs a second
  /// gather.
  Future<void> _keepLocalCopy({
    required BackupPolicy policy,
    required String id,
    required BackupManifest manifest,
    required Uint8List? key,
    required Directory staging,
    required String dataPath,
    required String preferencesPath,
    required File sealedForDestination,
  }) async {
    final folder = Directory(await resolveLocalCopyFolder(policy));
    final local = LocalFolderBackupTarget(folder);

    File toKeep = sealedForDestination;
    var localManifest = manifest;

    if (policy.needsTwoArchives) {
      final archive = File(p.join(staging.path, '$id.local.zip'));
      final result = await writeBackupArchive(
        dataPath: dataPath,
        destination: archive,
        parts: policy.parts,
        compression: policy.localCompression,
        preferencesPath: preferencesPath,
        maximumFileBytes: policy.maximumFileBytes,
        onProgress: (done, total) => _report(
          BackupProgress(
            stage: BackupStage.keeping,
            done: done,
            total: total,
          ),
        ),
      );
      localManifest = manifest.copyWith(
        compression: policy.localCompression,
        archiveBytes: result.archiveBytes,
        omissions: key == null ? result.omissions : null,
      );
      toKeep = archive;

      if (key != null) {
        final sealed = File(p.join(staging.path, '$id.local.sealed'));
        final sealedBytes = await sealBackupFile(
          source: archive,
          destination: sealed,
          key: key,
          onProgress: (done, total) => _report(
            BackupProgress(
              stage: BackupStage.keeping,
              done: done,
              total: total,
            ),
          ),
        );
        localManifest = localManifest.copyWith(sealedBytes: sealedBytes);
        toKeep = sealed;
      }
    }

    await local.put(archive: toKeep, manifest: localManifest);
    await _sweepFolder(local, policy.localCopies);
  }

  Future<void> _sweep(BackupTarget target, BackupPolicy policy) async {
    if (target.kind == BackupDestinationKind.folder) {
      await _sweepFolder(target, policy.localCopies);
      return;
    }
    final keep =
        target.kind.isRemote ? policy.remoteCopies : policy.localCopies;
    if (keep == BackupPolicy.keepEveryCopy) {
      return;
    }
    try {
      final copies = await target.list();
      for (final copy in expiredBackupCopies(copies, keep)) {
        await target.remove(copy);
        await _settings.forgetCopy(copy.id);
      }
    } on Object catch (error) {
      // Failing to sweep is not failing to back up. The copy that matters is
      // already there.
      Log.warn('Old backups could not be swept: $error');
    }
  }

  Future<void> _sweepFolder(BackupTarget target, int keep) async {
    if (keep == BackupPolicy.keepEveryCopy) {
      return;
    }
    try {
      final copies = await target.list();
      for (final copy in expiredBackupCopies(copies, keep)) {
        await target.remove(copy);
      }
    } on Object catch (error) {
      Log.warn('Old backups could not be swept: $error');
    }
  }

  // --- Reading what is there ----------------------------------------------

  /// The destination the policy names, ready to be asked.
  Future<BackupTarget> openTarget([BackupPolicy? override]) async {
    await _settings.ensureLoaded();
    final policy = override ?? _settings.policy;
    final destination = policy.destination;

    switch (destination.kind) {
      case BackupDestinationKind.none:
        throw const BackupError('There is nowhere to put a copy yet.');
      case BackupDestinationKind.folder:
        return LocalFolderBackupTarget(Directory(destination.localPath));
      case BackupDestinationKind.appflowyCloud:
        return AppFlowyCloudBackupTarget(
          userProfile: userProfile,
          knownCopies: _settings.ledger,
        );
      case BackupDestinationKind.googleDrive:
      case BackupDestinationKind.oneDrive:
      case BackupDestinationKind.box:
        await ProviderConnections.instance.ensureLoaded();
        final connection =
            ProviderConnections.instance.byId(destination.connectionId);
        if (connection == null) {
          throw const BackupError(
            'The account this backup uses is no longer signed in.',
          );
        }
        return ProviderBackupTarget(
          kind: destination.kind,
          connection: connection,
          folderId: destination.folderId,
          folderName: destination.folderName,
        );
    }
  }

  /// Every copy at the destination, newest first.
  Future<List<BackupCopy>> listCopies() async {
    final target = await openTarget();
    try {
      await target.ensureReady();
      final copies = await target.list();
      if (target.kind == BackupDestinationKind.appflowyCloud) {
        // The index stored beside the copies is the only listing there is, so
        // whatever it turned up is worth remembering here too.
        await _settings.rememberCopies(copies);
      }
      return copies;
    } finally {
      target.dispose();
    }
  }

  /// The copies kept on this computer beside a remote destination.
  Future<List<BackupCopy>> listLocalCopies() async {
    await _settings.ensureLoaded();
    final policy = _settings.policy;
    if (!policy.keepLocalCopy || !policy.destination.kind.isRemote) {
      return const [];
    }
    final folder = Directory(await resolveLocalCopyFolder(policy));
    if (!folder.existsSync()) {
      return const [];
    }
    return LocalFolderBackupTarget(folder).list();
  }

  Future<void> removeCopy(BackupCopy copy) async {
    final target = await openTarget();
    try {
      await target.ensureReady();
      await target.remove(copy);
      await _settings.forgetCopy(copy.id);
    } finally {
      target.dispose();
    }
  }

  // --- Putting one back ----------------------------------------------------

  /// Brings [copy] back into [into].
  ///
  /// Nothing is written over: the workspace is unpacked into the chosen folder
  /// and the person decides whether to point AppFlowy at it. Overwriting a
  /// workspace that is open would fail anyway — its files are held — and
  /// failing halfway through replacing somebody's notes is the one outcome a
  /// backup feature must never produce.
  Future<BackupRestoreResult> restore({
    required BackupCopy copy,
    required Directory into,
    Uint8List? key,
    BackupTarget? from,
  }) async {
    if (isRunning) {
      throw const BackupError('Something is already being copied.');
    }
    final target = from ?? await openTarget();
    final staging = Directory(
      p.join(
        (await getTemporaryDirectory()).path,
        stagingFolderName,
        'restore-${copy.id}',
      ),
    );
    await staging.create(recursive: true);

    try {
      _reportRestore(const RestoreProgress(stage: RestoreStage.fetching));
      final fetched = File(p.join(staging.path, '${copy.id}.fetched'));
      await target.ensureReady();
      await target.fetch(
        copy,
        fetched,
        onProgress: (done, total) => _reportRestore(
          RestoreProgress(
            stage: RestoreStage.fetching,
            done: done,
            total: total,
          ),
        ),
      );

      var archive = fetched;
      if (await looksLikeSealedBackup(fetched)) {
        if (key == null) {
          throw const BackupError(
            'This copy is sealed and needs its passphrase.',
            needsPassphrase: true,
          );
        }
        _reportRestore(const RestoreProgress(stage: RestoreStage.opening));
        final opened = File(p.join(staging.path, '${copy.id}.zip'));
        await openBackupFile(
          source: fetched,
          destination: opened,
          key: key,
          onProgress: (done, total) => _reportRestore(
            RestoreProgress(
              stage: RestoreStage.opening,
              done: done,
              total: total,
            ),
          ),
        );
        archive = opened;
      }

      _reportRestore(const RestoreProgress(stage: RestoreStage.unpacking));
      final files = await extractBackupArchive(
        source: archive,
        target: into,
        onProgress: (done, total) => _reportRestore(
          RestoreProgress(
            stage: RestoreStage.unpacking,
            done: done,
            total: total,
          ),
        ),
      );

      // A restored workspace is named the way AppFlowy names one, so pointing
      // the application at the folder is all that is left to do.
      final unpacked = Directory(p.join(into.path, backupWorkspaceFolder));
      final dataFolder = Directory(p.join(into.path, appFlowyDataFolder));
      if (unpacked.existsSync() && !dataFolder.existsSync()) {
        await unpacked.rename(dataFolder.path);
      }

      _reportRestore(
        RestoreProgress(
          stage: RestoreStage.finished,
          done: files,
          total: files,
        ),
      );
      return BackupRestoreResult(
        folder: into,
        dataFolder: dataFolder.existsSync() ? dataFolder : into,
        fileCount: files,
      );
    } on Object catch (error) {
      _reportRestore(
        RestoreProgress(stage: RestoreStage.failed, detail: _describe(error)),
      );
      rethrow;
    } finally {
      if (from == null) {
        target.dispose();
      }
      await _discard(staging);
    }
  }

  // --- Odds and ends --------------------------------------------------------

  /// Where copies kept on this computer go.
  Future<String> resolveLocalCopyFolder(BackupPolicy policy) async {
    if (policy.localCopyPath.isNotEmpty) {
      return policy.localCopyPath;
    }
    final data = await getIt<ApplicationDataStorage>().getPath();
    return p.join(p.dirname(data), defaultLocalFolderName);
  }

  Future<Uint8List?> _resolveKey(BackupPolicy policy) async {
    final held = _settings.key;
    if (held != null) {
      return held;
    }
    final remembered = await _settings.rememberedPassphrase();
    if (remembered == null || remembered.isEmpty) {
      return null;
    }
    final key = unlockBackupKey(
      passphrase: remembered,
      salt: policy.salt,
      verifier: policy.verifier,
      verifierPhrase: BackupPolicy.verifierPhrase,
      iterations: policy.iterations,
    );
    if (key != null) {
      _settings.unlockWith(key);
    }
    return key;
  }

  /// The settings file this computer keeps, when there is one to copy.
  Future<String> _preferencesPath() async {
    try {
      final support = await getApplicationSupportDirectory();
      final file = File(p.join(support.path, 'shared_preferences.json'));
      return file.existsSync() ? file.path : '';
    } on Object {
      return '';
    }
  }

  Future<String> _appVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } on Object {
      // The version is only ever shown, so failing to read it costs nothing.
      return '';
    }
  }

  void _report(BackupProgress progress) {
    _progress = progress;
    notifyListeners();
  }

  void _reportRestore(RestoreProgress progress) {
    _restore = progress;
    notifyListeners();
  }

  static String _describe(Object error) => switch (error) {
        BackupError(:final detail) => detail,
        BackupTargetError(:final detail) => detail,
        BackupArchiveError(:final detail) => detail,
        BackupCipherError(reason: BackupCipherFailure.wrongKeyOrAltered) =>
          'The passphrase did not open this copy.',
        BackupCipherError(reason: BackupCipherFailure.truncated) =>
          'That copy is incomplete.',
        BackupCipherError(reason: BackupCipherFailure.notABackup) =>
          'That file is not an AppFlowy backup.',
        BackupCipherError(reason: BackupCipherFailure.unsupportedVersion) =>
          'That copy was written by a newer version of AppFlowy.',
        _ => error.toString(),
      };

  static Future<void> _discard(Directory directory) async {
    try {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    } on Object {
      // A staging folder left behind is swept next time.
    }
  }
}
