// What the application has been told about copying this workspace somewhere
// safe.
//
// Everything here is pure: no storage, no widgets, no network. A backup is a
// long chain of decisions — what to include, how hard to squeeze it, whether to
// seal it, where to put it, how many to keep — and each one has to be
// answerable in a test without a Google account or a data folder.

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:flutter/foundation.dart';

/// Where a copy is put.
///
/// A local folder is deliberately first among equals: a copy on an external
/// disk is a real backup, and it is the only one that keeps working when
/// nothing can be reached.
enum BackupDestinationKind {
  none,
  folder,
  googleDrive,
  oneDrive,
  box,
  appflowyCloud;

  /// The connected service this destination speaks to, when it is one.
  ProviderService? get providerService => switch (this) {
        BackupDestinationKind.googleDrive => ProviderService.googleDrive,
        BackupDestinationKind.oneDrive => ProviderService.oneDrive,
        BackupDestinationKind.box => ProviderService.box,
        BackupDestinationKind.none ||
        BackupDestinationKind.folder ||
        BackupDestinationKind.appflowyCloud =>
          null,
      };

  bool get isRemote => this != BackupDestinationKind.none &&
      this != BackupDestinationKind.folder;

  /// Whether a copy in this place needs an account to have been signed in.
  bool get needsConnection => providerService != null;

  /// Whether the service can be asked what is already there.
  ///
  /// AppFlowy Cloud stores a file behind a link and offers no listing, so the
  /// record of what has been sent has to be kept on this computer. Saying so
  /// here is what stops the interface promising a list it cannot produce.
  bool get canListRemotely => this != BackupDestinationKind.appflowyCloud;

  static BackupDestinationKind fromValue(Object? value) {
    for (final kind in BackupDestinationKind.values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return BackupDestinationKind.none;
  }
}

/// How hard the bytes are squeezed.
///
/// Named for what it costs rather than for a number, because the number means
/// nothing to the person choosing: `maximum` on a folder of photographs buys
/// almost nothing and takes several times as long.
enum BackupCompression {
  none,
  fast,
  balanced,
  maximum;

  /// The deflate level the archive writer takes. 0 stores, 9 squeezes.
  int get deflateLevel => switch (this) {
        BackupCompression.none => 0,
        BackupCompression.fast => 1,
        BackupCompression.balanced => 6,
        BackupCompression.maximum => 9,
      };

  bool get compresses => this != BackupCompression.none;

  static BackupCompression fromValue(Object? value) {
    for (final level in BackupCompression.values) {
      if (level.name == value) {
        return level;
      }
    }
    return BackupCompression.balanced;
  }
}

/// When a copy is taken.
enum BackupSchedule {
  manual,
  onClose,
  hourly,
  daily,
  weekly;

  /// How long between automatic copies, or null when there is no clock.
  Duration? get interval => switch (this) {
        BackupSchedule.manual || BackupSchedule.onClose => null,
        BackupSchedule.hourly => const Duration(hours: 1),
        BackupSchedule.daily => const Duration(days: 1),
        BackupSchedule.weekly => const Duration(days: 7),
      };

  bool get runsOnAClock => interval != null;

  static BackupSchedule fromValue(Object? value) {
    for (final schedule in BackupSchedule.values) {
      if (schedule.name == value) {
        return schedule;
      }
    }
    return BackupSchedule.manual;
  }
}

/// The parts of a workspace a copy may carry.
///
/// Caches are not on this list and never will be: `cache_files` and
/// `provider_cache` are copies of things that live somewhere else, and putting
/// them in a backup is paying to store what can simply be fetched again.
enum BackupPart {
  /// The workspace itself — pages, tables, folders, everything typed.
  workspace,

  /// Files and pictures that were brought in, plus saved web pages.
  attachments,

  /// Earlier states of pages, if version history is being kept.
  pageVersions,

  /// This computer's own settings, so a restored workspace can be recognised.
  preferences;

  static BackupPart? fromValue(Object? value) {
    for (final part in BackupPart.values) {
      if (part.name == value) {
        return part;
      }
    }
    return null;
  }
}

/// The folders inside the data directory each part is made of.
///
/// Anything not named here belongs to [BackupPart.workspace], which is what
/// makes the split safe: a folder added by a later version of AppFlowy is
/// carried by default rather than silently left out of every backup.
const Map<BackupPart, Set<String>> backupPartFolders = {
  BackupPart.attachments: {'files', 'images', 'bookmark_snapshots'},
  BackupPart.pageVersions: {'page_versions'},
};

/// Folders that are never copied, whatever is chosen.
const Set<String> backupExcludedFolders = {
  'cache_files',
  'provider_cache',
  'log',
  'logs',
};

/// Which part a top-level folder of the data directory belongs to.
BackupPart backupPartOfFolder(String folderName) {
  for (final entry in backupPartFolders.entries) {
    if (entry.value.contains(folderName)) {
      return entry.key;
    }
  }
  return BackupPart.workspace;
}

/// Where one destination points.
///
/// The service is only half the answer — a Drive account with no folder chosen
/// would drop copies in the root of somebody's whole drive, so the folder is
/// part of the binding and a destination without one is not ready.
@immutable
class BackupDestination {
  const BackupDestination({
    this.kind = BackupDestinationKind.none,
    this.connectionId = '',
    this.accountLabel = '',
    this.folderId = '',
    this.folderName = '',
    this.localPath = '',
  });

  factory BackupDestination.fromJson(Map<String, Object?> json) {
    String read(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    return BackupDestination(
      kind: BackupDestinationKind.fromValue(json['kind']),
      connectionId: read('connection'),
      accountLabel: read('account'),
      folderId: read('folder_id'),
      folderName: read('folder_name'),
      localPath: read('local_path'),
    );
  }

  final BackupDestinationKind kind;

  /// Which signed-in account answers, for a destination that needs one.
  final String connectionId;

  /// What that account is called, so the settings can say so without going to
  /// the network.
  final String accountLabel;

  /// The service's own id of the folder copies are put in.
  final String folderId;
  final String folderName;

  /// The folder on this computer, for [BackupDestinationKind.folder].
  final String localPath;

  bool get isSet => kind != BackupDestinationKind.none;

  /// Whether a copy could actually be sent right now, as far as this side can
  /// tell without asking the service.
  bool get isReady => switch (kind) {
        BackupDestinationKind.none => false,
        BackupDestinationKind.folder => localPath.isNotEmpty,
        BackupDestinationKind.appflowyCloud => true,
        BackupDestinationKind.googleDrive ||
        BackupDestinationKind.oneDrive ||
        BackupDestinationKind.box =>
          connectionId.isNotEmpty && folderId.isNotEmpty,
      };

  BackupDestination copyWith({
    BackupDestinationKind? kind,
    String? connectionId,
    String? accountLabel,
    String? folderId,
    String? folderName,
    String? localPath,
  }) =>
      BackupDestination(
        kind: kind ?? this.kind,
        connectionId: connectionId ?? this.connectionId,
        accountLabel: accountLabel ?? this.accountLabel,
        folderId: folderId ?? this.folderId,
        folderName: folderName ?? this.folderName,
        localPath: localPath ?? this.localPath,
      );

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        if (connectionId.isNotEmpty) 'connection': connectionId,
        if (accountLabel.isNotEmpty) 'account': accountLabel,
        if (folderId.isNotEmpty) 'folder_id': folderId,
        if (folderName.isNotEmpty) 'folder_name': folderName,
        if (localPath.isNotEmpty) 'local_path': localPath,
      };

  @override
  bool operator ==(Object other) =>
      other is BackupDestination &&
      other.kind == kind &&
      other.connectionId == connectionId &&
      other.accountLabel == accountLabel &&
      other.folderId == folderId &&
      other.folderName == folderName &&
      other.localPath == localPath;

  @override
  int get hashCode => Object.hash(
        kind,
        connectionId,
        accountLabel,
        folderId,
        folderName,
        localPath,
      );
}

/// Every rule that governs a copy.
@immutable
class BackupPolicy {
  const BackupPolicy({
    this.enabled = false,
    this.schedule = BackupSchedule.manual,
    this.destination = const BackupDestination(),
    this.parts = const {
      BackupPart.workspace,
      BackupPart.attachments,
      BackupPart.preferences,
    },
    this.localCompression = BackupCompression.balanced,
    this.remoteCompression = BackupCompression.maximum,
    this.keepLocalCopy = true,
    this.localCopyPath = '',
    this.localCopies = 5,
    this.remoteCopies = 10,
    this.encrypt = false,
    this.salt = '',
    this.verifier = '',
    this.hint = '',
    this.iterations = defaultKeyIterations,
    this.maximumFileBytes = 512 * megabyte,
    this.warnAboveBytes = 2048 * megabyte,
  });

  factory BackupPolicy.fromJson(Map<String, Object?> json) {
    bool readBool(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    int readInt(String key, int fallback) {
      final value = json[key];
      return value is int ? value : fallback;
    }

    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    final storedParts = json['parts'];
    final parts = <BackupPart>{};
    if (storedParts is List) {
      for (final name in storedParts) {
        final part = BackupPart.fromValue(name);
        if (part != null) {
          parts.add(part);
        }
      }
    }

    final destination = json['destination'];

    return BackupPolicy(
      enabled: readBool('enabled', false),
      schedule: BackupSchedule.fromValue(json['schedule']),
      destination: destination is Map
          ? BackupDestination.fromJson(Map<String, Object?>.from(destination))
          : const BackupDestination(),
      // An empty set would mean a backup of nothing, which is worse than the
      // default: a policy written by a version that did not know about a part
      // falls back rather than quietly copying less than it says.
      parts: parts.isEmpty ? const BackupPolicy().parts : parts,
      localCompression: BackupCompression.fromValue(json['local_compression']),
      remoteCompression:
          BackupCompression.fromValue(json['remote_compression']),
      keepLocalCopy: readBool('keep_local_copy', true),
      localCopyPath: readString('local_copy_path'),
      localCopies: readInt('local_copies', 5),
      remoteCopies: readInt('remote_copies', 10),
      encrypt: readBool('encrypt', false),
      salt: readString('salt'),
      verifier: readString('verifier'),
      hint: readString('hint'),
      iterations: readInt('iterations', defaultKeyIterations),
      maximumFileBytes: readInt('maximum_file_bytes', 512 * megabyte),
      warnAboveBytes: readInt('warn_above_bytes', 2048 * megabyte),
    );
  }

  static const int megabyte = 1024 * 1024;

  /// The words the backup verifier holds. Not secret; what matters is that
  /// only the right passphrase can produce them again.
  static const verifierPhrase = 'appflowy-backup-key-v1';

  static const copyChoices = <int>[1, 3, 5, 10, 20, 50, keepEveryCopy];

  /// Never sweep an old copy. A real choice for a folder on a large disk.
  static const int keepEveryCopy = -1;

  static const fileSizeChoices = <int>[
    16 * megabyte,
    64 * megabyte,
    256 * megabyte,
    512 * megabyte,
    2048 * megabyte,
    anySize,
  ];

  /// No ceiling at all.
  static const int anySize = -1;

  final bool enabled;
  final BackupSchedule schedule;
  final BackupDestination destination;
  final Set<BackupPart> parts;

  /// How hard the copy kept on this computer is squeezed.
  final BackupCompression localCompression;

  /// How hard the copy that is sent away is squeezed.
  ///
  /// Deliberately a separate answer. Local disk is cheap and time is not, so a
  /// copy on this machine is usually worth squeezing lightly; a copy that has
  /// to cross a connection and take up somebody's cloud quota is usually worth
  /// squeezing hard. One setting could not say both.
  final BackupCompression remoteCompression;

  final bool keepLocalCopy;

  /// The folder that copy is kept in. Empty means "beside the workspace",
  /// which is resolved when a copy actually runs — a pure model must not go
  /// looking for the application's own directories.
  final String localCopyPath;

  final int localCopies;
  final int remoteCopies;

  /// Whether the archive is sealed before it leaves this machine.
  final bool encrypt;

  final String salt;
  final String verifier;
  final String hint;
  final int iterations;

  /// A single file larger than this is left out and named in the manifest,
  /// rather than making every backup enormous because one video was dropped in.
  final int maximumFileBytes;

  /// The size at which the interface says something before starting.
  final int warnAboveBytes;

  bool get hasPassphrase =>
      encrypt && salt.isNotEmpty && verifier.isNotEmpty;

  /// Whether a copy can be taken at all right now.
  bool get isReady =>
      destination.isReady && parts.isNotEmpty && (!encrypt || hasPassphrase);

  bool get keepsEveryLocalCopy => localCopies == keepEveryCopy;

  bool get keepsEveryRemoteCopy => remoteCopies == keepEveryCopy;

  bool get sendsToAService => destination.kind.isRemote;

  /// Whether one archive can serve both copies.
  ///
  /// Two different compression levels mean two different files, and pretending
  /// otherwise would silently ignore one of the two settings.
  bool get needsTwoArchives =>
      keepLocalCopy &&
      destination.kind.isRemote &&
      localCompression != remoteCompression;

  /// The compression the archive that is sent away is written at.
  BackupCompression get compressionForDestination =>
      destination.kind.isRemote ? remoteCompression : localCompression;

  BackupPolicy copyWith({
    bool? enabled,
    BackupSchedule? schedule,
    BackupDestination? destination,
    Set<BackupPart>? parts,
    BackupCompression? localCompression,
    BackupCompression? remoteCompression,
    bool? keepLocalCopy,
    String? localCopyPath,
    int? localCopies,
    int? remoteCopies,
    bool? encrypt,
    String? salt,
    String? verifier,
    String? hint,
    int? iterations,
    int? maximumFileBytes,
    int? warnAboveBytes,
  }) =>
      BackupPolicy(
        enabled: enabled ?? this.enabled,
        schedule: schedule ?? this.schedule,
        destination: destination ?? this.destination,
        parts: parts ?? this.parts,
        localCompression: localCompression ?? this.localCompression,
        remoteCompression: remoteCompression ?? this.remoteCompression,
        keepLocalCopy: keepLocalCopy ?? this.keepLocalCopy,
        localCopyPath: localCopyPath ?? this.localCopyPath,
        localCopies: localCopies ?? this.localCopies,
        remoteCopies: remoteCopies ?? this.remoteCopies,
        encrypt: encrypt ?? this.encrypt,
        salt: salt ?? this.salt,
        verifier: verifier ?? this.verifier,
        hint: hint ?? this.hint,
        iterations: iterations ?? this.iterations,
        maximumFileBytes: maximumFileBytes ?? this.maximumFileBytes,
        warnAboveBytes: warnAboveBytes ?? this.warnAboveBytes,
      );

  /// Forgets the passphrase entirely. Used when encryption is turned off, so a
  /// salt and verifier are never left behind to be picked up again later.
  BackupPolicy withoutPassphrase() => BackupPolicy(
        enabled: enabled,
        schedule: schedule,
        destination: destination,
        parts: parts,
        localCompression: localCompression,
        remoteCompression: remoteCompression,
        keepLocalCopy: keepLocalCopy,
        localCopyPath: localCopyPath,
        localCopies: localCopies,
        remoteCopies: remoteCopies,
        maximumFileBytes: maximumFileBytes,
        warnAboveBytes: warnAboveBytes,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'schedule': schedule.name,
        'destination': destination.toJson(),
        'parts': [for (final part in parts) part.name],
        'local_compression': localCompression.name,
        'remote_compression': remoteCompression.name,
        'keep_local_copy': keepLocalCopy,
        'local_copy_path': localCopyPath,
        'local_copies': localCopies,
        'remote_copies': remoteCopies,
        'encrypt': encrypt,
        'salt': salt,
        'verifier': verifier,
        'hint': hint,
        'iterations': iterations,
        'maximum_file_bytes': maximumFileBytes,
        'warn_above_bytes': warnAboveBytes,
      };

  @override
  bool operator ==(Object other) =>
      other is BackupPolicy &&
      other.enabled == enabled &&
      other.schedule == schedule &&
      other.destination == destination &&
      setEquals(other.parts, parts) &&
      other.localCompression == localCompression &&
      other.remoteCompression == remoteCompression &&
      other.keepLocalCopy == keepLocalCopy &&
      other.localCopyPath == localCopyPath &&
      other.localCopies == localCopies &&
      other.remoteCopies == remoteCopies &&
      other.encrypt == encrypt &&
      other.salt == salt &&
      other.verifier == verifier &&
      other.hint == hint &&
      other.iterations == iterations &&
      other.maximumFileBytes == maximumFileBytes &&
      other.warnAboveBytes == warnAboveBytes;

  @override
  int get hashCode => Object.hash(
        enabled,
        schedule,
        destination,
        Object.hashAllUnordered(parts),
        localCompression,
        remoteCompression,
        keepLocalCopy,
        localCopyPath,
        localCopies,
        remoteCopies,
        encrypt,
        salt,
        verifier,
        hint,
        iterations,
        maximumFileBytes,
        warnAboveBytes,
      );
}

/// Whether the clock says another copy is due.
///
/// Pure, so "would this run?" can be asked of any moment in a test rather than
/// by waiting an hour.
bool backupIsDue({
  required BackupPolicy policy,
  required DateTime now,
  DateTime? lastRunAt,
}) {
  if (!policy.enabled || !policy.isReady) {
    return false;
  }
  final interval = policy.schedule.interval;
  if (interval == null) {
    return false;
  }
  if (lastRunAt == null) {
    return true;
  }
  return !now.isBefore(lastRunAt.add(interval));
}

/// Which copies are swept, oldest first.
///
/// [identifiers] arrives newest first, which is how every listing here is
/// sorted. The newest is never swept, whatever the count says: a rule that can
/// leave nothing behind is not a retention rule.
List<T> expiredBackupCopies<T>(List<T> identifiers, int keep) {
  if (keep == BackupPolicy.keepEveryCopy || identifiers.length <= 1) {
    return const [];
  }
  final ceiling = keep < 1 ? 1 : keep;
  if (identifiers.length <= ceiling) {
    return const [];
  }
  return identifiers.sublist(ceiling);
}
