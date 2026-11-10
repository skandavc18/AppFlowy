// What a sync folder holds, and what to do about it.
//
// A sync folder is a plain folder — on a disk, in Google Drive, OneDrive or
// Box — that every computer reads and writes. Nothing in it is ever rewritten:
// a computer only adds files under its own name and, when tidying, removes
// files whose contents something newer already carries. That is what lets the
// folder live on a service that has no way to lock a file or to change one only
// if nobody else has.
//
//   afsync1_<epoch>_base.pack                   the workspace an epoch starts from
//   afsync1_<epoch>_base.json                   who started it, readable on its own
//   afsync1_<epoch>_chg_<device>_<seq>.pack     one computer's changes, in order
//   afsync1_<epoch>_ckpt_<device>_<seq>.pack    everything merged, for tidying
//   afsync1_<epoch>_ckpt_<device>_<seq>.json    which changes that holds
//   afsync1_<epoch>_dev_<device>.json           what a computer calls itself
//   afsync1_blob_<sha256>                       one attached file, by contents
//
// An epoch begins when sync is started on an empty folder, and again whenever
// the workspace is restored to an earlier state: the newest epoch is the
// workspace, and a computer still on an older one takes the newer one up.
//
// Everything here is pure, so every decision can be tested without a folder.

import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

const String syncFilePrefix = 'afsync1_';
const String syncPackExtension = '.pack';
const String syncInfoExtension = '.json';
const String syncBlobPrefix = '${syncFilePrefix}blob_';

/// The shape of the files in a sync folder. A computer refuses a folder written
/// by a newer version rather than guessing at it.
const int syncFormat = 1;

/// A file in the sync folder, as the folder lists it.
@immutable
class RemoteSyncFile {
  const RemoteSyncFile({
    required this.name,
    required this.id,
    this.bytes = 0,
    this.modifiedAt,
  });

  final String name;

  /// How the folder finds the file again: a path, or a service's own id.
  final String id;
  final int bytes;
  final DateTime? modifiedAt;

  @override
  bool operator ==(Object other) =>
      other is RemoteSyncFile && other.name == name && other.id == id;

  @override
  int get hashCode => Object.hash(name, id);

  @override
  String toString() => 'RemoteSyncFile($name)';
}

enum SyncFileKind {
  base,
  baseInfo,
  changes,
  checkpoint,
  checkpointInfo,
  deviceInfo,
  blob,

  /// The clear record of the password an epoch is sealed with.
  vault,
}

/// What a file name says about the file.
@immutable
class SyncFileName {
  const SyncFileName._({
    required this.kind,
    this.epoch = '',
    this.device = '',
    this.seq = 0,
    this.hash = '',
  });

  final SyncFileKind kind;
  final String epoch;
  final String device;
  final int seq;
  final String hash;

  static String base(String epoch) =>
      '$syncFilePrefix${epoch}_base$syncPackExtension';

  static String baseInfo(String epoch) =>
      '$syncFilePrefix${epoch}_base$syncInfoExtension';

  static String changes(String epoch, String device, int seq) =>
      '$syncFilePrefix${epoch}_chg_${device}_${_seq(seq)}$syncPackExtension';

  static String checkpoint(String epoch, String device, int seq) =>
      '$syncFilePrefix${epoch}_ckpt_${device}_${_seq(seq)}$syncPackExtension';

  static String checkpointInfo(String epoch, String device, int seq) =>
      '$syncFilePrefix${epoch}_ckpt_${device}_${_seq(seq)}$syncInfoExtension';

  static String deviceInfo(String epoch, String device) =>
      '$syncFilePrefix${epoch}_dev_$device$syncInfoExtension';

  static String blob(String hash) => '$syncBlobPrefix$hash';

  /// The record of the password [epoch] is sealed with. Each epoch has its
  /// own, so an epoch is sealed exactly when its record is there, and sealing
  /// again with another password never leaves two records competing.
  static String vault(String epoch) =>
      '$syncFilePrefix${epoch}_vault$syncInfoExtension';

  /// Where a version from before epochs had their own records kept the one
  /// record of a folder. Nothing reads it; it is removed when found.
  static const String legacyVault = '${syncFilePrefix}vault$syncInfoExtension';

  static String _seq(int seq) => seq.toString().padLeft(8, '0');

  static final RegExp _epochPattern =
      RegExp(r'^[0-9]{8}T[0-9]{6}-[a-z0-9]{6}$');
  static final RegExp _devicePattern = RegExp(r'^[a-z0-9]{6,32}$');
  static final RegExp _hashPattern = RegExp(r'^[0-9a-f]{64}$');

  static bool isDeviceId(String value) => _devicePattern.hasMatch(value);

  /// Reads a name, or returns null for anything this version did not write.
  static SyncFileName? parse(String name) {
    if (!name.startsWith(syncFilePrefix)) {
      return null;
    }
    if (name.startsWith(syncBlobPrefix)) {
      final hash = name.substring(syncBlobPrefix.length);
      return _hashPattern.hasMatch(hash)
          ? SyncFileName._(kind: SyncFileKind.blob, hash: hash)
          : null;
    }

    final String stem;
    final bool isInfo;
    if (name.endsWith(syncPackExtension)) {
      stem = name.substring(0, name.length - syncPackExtension.length);
      isInfo = false;
    } else if (name.endsWith(syncInfoExtension)) {
      stem = name.substring(0, name.length - syncInfoExtension.length);
      isInfo = true;
    } else {
      return null;
    }

    final parts = stem.substring(syncFilePrefix.length).split('_');
    if (parts.length < 2 || !_epochPattern.hasMatch(parts[0])) {
      return null;
    }
    final epoch = parts[0];
    switch (parts[1]) {
      case 'base':
        if (parts.length != 2) {
          return null;
        }
        return SyncFileName._(
          kind: isInfo ? SyncFileKind.baseInfo : SyncFileKind.base,
          epoch: epoch,
        );
      case 'vault':
        return parts.length == 2 && isInfo
            ? SyncFileName._(kind: SyncFileKind.vault, epoch: epoch)
            : null;
      case 'dev':
        if (parts.length != 3 ||
            !isInfo ||
            !_devicePattern.hasMatch(parts[2])) {
          return null;
        }
        return SyncFileName._(
          kind: SyncFileKind.deviceInfo,
          epoch: epoch,
          device: parts[2],
        );
      case 'chg':
      case 'ckpt':
        if (parts.length != 4 || !_devicePattern.hasMatch(parts[2])) {
          return null;
        }
        final seq = int.tryParse(parts[3]);
        if (seq == null || seq < 1 || parts[3].length != 8) {
          return null;
        }
        if (parts[1] == 'chg') {
          return isInfo
              ? null
              : SyncFileName._(
                  kind: SyncFileKind.changes,
                  epoch: epoch,
                  device: parts[2],
                  seq: seq,
                );
        }
        return SyncFileName._(
          kind: isInfo ? SyncFileKind.checkpointInfo : SyncFileKind.checkpoint,
          epoch: epoch,
          device: parts[2],
          seq: seq,
        );
      default:
        return null;
    }
  }
}

/// A new epoch id. It starts with the moment, so ids sort the way time does.
String newSyncEpoch(DateTime at, {Random? random}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final utc = at.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
      '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}'
      '-${randomSyncToken(6, random: random)}';
}

/// A name for an epoch that replaces [previous]. It sorts after it even when
/// both start within the same second, or this computer's clock is behind the
/// one that started [previous].
String nextSyncEpoch(String previous, DateTime at, {Random? random}) {
  final match =
      RegExp(r'^(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d)-').firstMatch(previous);
  var time = at.toUtc();
  if (match != null) {
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    final after = DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5] + 1,
    );
    if (time.isBefore(after)) {
      time = after;
    }
  }
  return newSyncEpoch(time, random: random);
}

/// A new name for this computer in sync folders.
String newSyncDeviceId({Random? random}) => randomSyncToken(12, random: random);

String randomSyncToken(int length, {Random? random}) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final source = random ?? Random.secure();
  return String.fromCharCodes(
    List.generate(
      length,
      (_) => alphabet.codeUnitAt(source.nextInt(alphabet.length)),
    ),
  );
}

/// One checkpoint, and the record written beside it.
@immutable
class SyncCheckpoint {
  const SyncCheckpoint({
    required this.device,
    required this.seq,
    required this.pack,
    this.info,
  });

  final String device;
  final int seq;
  final RemoteSyncFile pack;
  final RemoteSyncFile? info;
}

/// Everything of one epoch that is in the folder.
class SyncEpochListing {
  SyncEpochListing(this.id);

  final String id;
  RemoteSyncFile? base;
  RemoteSyncFile? baseInfo;

  /// The record of the password this epoch is sealed with; none for an epoch
  /// written before folders were sealed.
  RemoteSyncFile? vault;

  /// Each computer's changes, by sequence number.
  final Map<String, SplayTreeMap<int, RemoteSyncFile>> changes = {};

  /// Checkpoints, oldest first.
  final List<SyncCheckpoint> checkpoints = [];

  /// What each computer calls itself.
  final Map<String, RemoteSyncFile> deviceInfos = {};

  Set<String> get devices => {
        ...changes.keys,
        ...deviceInfos.keys,
        for (final checkpoint in checkpoints) checkpoint.device,
      };

  int get changeCount =>
      changes.values.fold(0, (sum, files) => sum + files.length);

  /// The highest sequence number [device] has used in this epoch.
  int lastSeqOf(String device) {
    final mine = changes[device];
    final fromChanges = mine == null || mine.isEmpty ? 0 : mine.lastKey()!;
    final fromCheckpoints = checkpoints
        .where((checkpoint) => checkpoint.device == device)
        .fold<int>(0, (highest, checkpoint) => max(highest, checkpoint.seq));
    return max(fromChanges, fromCheckpoints);
  }

  /// When [device] last added anything here.
  DateTime? lastSeenOf(String device) {
    DateTime? latest;
    void consider(RemoteSyncFile file) {
      final at = file.modifiedAt;
      if (at != null && (latest == null || at.isAfter(latest!))) {
        latest = at;
      }
    }

    changes[device]?.values.forEach(consider);
    final info = deviceInfos[device];
    if (info != null) {
      consider(info);
    }
    for (final checkpoint in checkpoints) {
      if (checkpoint.device == device) {
        consider(checkpoint.pack);
      }
    }
    return latest;
  }
}

/// A sync folder, read.
class SyncListing {
  SyncListing._(this.epochs, this.blobs, this.others, this.legacyVaults);

  factory SyncListing.of(Iterable<RemoteSyncFile> files) {
    final epochs = SplayTreeMap<String, SyncEpochListing>();
    final blobs = <String, RemoteSyncFile>{};
    final others = <RemoteSyncFile>[];
    final legacyVaults = <RemoteSyncFile>[];
    final checkpointInfos = <String, RemoteSyncFile>{};

    for (final file in files) {
      final parsed = SyncFileName.parse(file.name);
      if (parsed == null) {
        if (file.name == SyncFileName.legacyVault) {
          legacyVaults.add(file);
        } else {
          others.add(file);
        }
        continue;
      }
      if (parsed.kind == SyncFileKind.blob) {
        blobs[parsed.hash] = file;
        continue;
      }
      final epoch = epochs.putIfAbsent(
        parsed.epoch,
        () => SyncEpochListing(parsed.epoch),
      );
      switch (parsed.kind) {
        case SyncFileKind.base:
          epoch.base = _older(epoch.base, file);
        case SyncFileKind.baseInfo:
          epoch.baseInfo = _older(epoch.baseInfo, file);
        case SyncFileKind.vault:
          epoch.vault = _older(epoch.vault, file);
        case SyncFileKind.changes:
          epoch.changes
              .putIfAbsent(parsed.device, SplayTreeMap.new)
              .putIfAbsent(parsed.seq, () => file);
        case SyncFileKind.checkpoint:
          epoch.checkpoints.add(
            SyncCheckpoint(device: parsed.device, seq: parsed.seq, pack: file),
          );
        case SyncFileKind.checkpointInfo:
          checkpointInfos[_checkpointKey(
            parsed.epoch,
            parsed.device,
            parsed.seq,
          )] = file;
        case SyncFileKind.deviceInfo:
          epoch.deviceInfos[parsed.device] =
              _older(epoch.deviceInfos[parsed.device], file);
        case SyncFileKind.blob:
          break;
      }
    }

    for (final epoch in epochs.values) {
      for (var i = 0; i < epoch.checkpoints.length; i++) {
        final checkpoint = epoch.checkpoints[i];
        epoch.checkpoints[i] = SyncCheckpoint(
          device: checkpoint.device,
          seq: checkpoint.seq,
          pack: checkpoint.pack,
          info: checkpointInfos[
              _checkpointKey(epoch.id, checkpoint.device, checkpoint.seq)],
        );
      }
      epoch.checkpoints.sort(
        (a, b) => _checkpointOrder(a).compareTo(_checkpointOrder(b)),
      );
    }
    return SyncListing._(epochs, blobs, others, legacyVaults);
  }

  /// Every epoch in the folder, oldest first.
  final SplayTreeMap<String, SyncEpochListing> epochs;

  /// Attached files, by the hash of their contents.
  final Map<String, RemoteSyncFile> blobs;

  /// Anything else in the folder, which sync leaves alone.
  final List<RemoteSyncFile> others;

  /// Records a version from before epochs had their own left in the folder,
  /// one of them by a seal that never finished. They seal nothing.
  final List<RemoteSyncFile> legacyVaults;

  /// The newest epoch that has actually been started: its base is there.
  SyncEpochListing? get current {
    for (final id in epochs.keys.toList().reversed) {
      final epoch = epochs[id]!;
      if (epoch.base != null && epoch.baseInfo != null) {
        return epoch;
      }
    }
    return null;
  }

  bool get isEmpty => current == null;

  static String _checkpointKey(String epoch, String device, int seq) =>
      '$epoch/$device/$seq';

  static String _checkpointOrder(SyncCheckpoint checkpoint) {
    final at = checkpoint.pack.modifiedAt?.millisecondsSinceEpoch ?? 0;
    return '${at.toString().padLeft(16, '0')}/${checkpoint.pack.name}';
  }

  /// Two computers that upload the same name both succeed on a service that
  /// allows duplicates; the older upload is the one everybody reads.
  static RemoteSyncFile _older(RemoteSyncFile? existing, RemoteSyncFile file) {
    if (existing == null) {
      return file;
    }
    final a = existing.modifiedAt;
    final b = file.modifiedAt;
    if (a == null || b == null) {
      return existing;
    }
    return b.isBefore(a) ? file : existing;
  }
}

/// Why an epoch began.
enum SyncEpochReason {
  started,

  /// A backup was restored: the workspace is replaced everywhere.
  restored,

  /// The same workspace carries on, sealed anew or with something taken out
  /// of the folder: every computer merges into it and carries on.
  continued;

  static SyncEpochReason fromValue(Object? value) => SyncEpochReason.values
      .firstWhere((reason) => reason.name == value, orElse: () => started);
}

/// Who started an epoch, and what it holds — written beside its base so a
/// computer can say what a folder is before downloading any of it.
@immutable
class SyncEpochInfo {
  const SyncEpochInfo({
    required this.epoch,
    required this.workspaceId,
    required this.workspaceName,
    required this.uid,
    required this.createdAt,
    required this.device,
    required this.deviceName,
    this.reason = SyncEpochReason.started,
    this.objectCount = 0,
    this.fileCount = 0,
    this.bytes = 0,
    this.roster = const [],
  });

  factory SyncEpochInfo.fromJson(Map<String, Object?> json) => SyncEpochInfo(
        epoch: _string(json['epoch']),
        workspaceId: _string(json['workspace_id']),
        workspaceName: _string(json['workspace_name']),
        uid: _int(json['uid']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          _int(json['created_at']),
          isUtc: true,
        ),
        device: _string(json['device']),
        deviceName: _string(json['device_name']),
        reason: SyncEpochReason.fromValue(json['reason']),
        objectCount: _int(json['object_count']),
        fileCount: _int(json['file_count']),
        bytes: _int(json['bytes']),
        roster: [
          if (json['roster'] case final List<Object?> entries)
            for (final entry in entries)
              if (entry is Map)
                if (SyncDeviceInfo.fromJson(Map<String, Object?>.from(entry))
                    case final device?)
                  device,
        ],
      );

  /// Reads an epoch record, or returns null for anything else — including a
  /// record written by a newer version, which this one must not act on.
  static SyncEpochInfo? tryParse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map || decoded['format'] != syncFormat) {
        return null;
      }
      final info = SyncEpochInfo.fromJson(Map<String, Object?>.from(decoded));
      return info.workspaceId.isEmpty ? null : info;
    } on Object {
      return null;
    }
  }

  final String epoch;
  final String workspaceId;
  final String workspaceName;
  final int uid;
  final DateTime createdAt;
  final String device;
  final String deviceName;
  final SyncEpochReason reason;
  final int objectCount;
  final int fileCount;
  final int bytes;

  /// The computers that synced the epoch this one carries on from, with when
  /// each was last seen there — so one still catching up is not forgotten.
  final List<SyncDeviceInfo> roster;

  Map<String, Object?> toJson() => {
        'format': syncFormat,
        'epoch': epoch,
        'workspace_id': workspaceId,
        'workspace_name': workspaceName,
        'uid': uid,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'device': device,
        'device_name': deviceName,
        'reason': reason.name,
        'object_count': objectCount,
        'file_count': fileCount,
        'bytes': bytes,
        if (roster.isNotEmpty)
          'roster': [for (final device in roster) device.toJson()],
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// What a computer calls itself in a sync folder.
@immutable
class SyncDeviceInfo {
  const SyncDeviceInfo({
    required this.device,
    required this.name,
    required this.platform,
    required this.joinedAt,
    this.lastSeen,
  });

  /// Reads one, or returns null when it names no computer.
  static SyncDeviceInfo? fromJson(Map<String, Object?> json) {
    final device = _string(json['device']);
    if (device.isEmpty) {
      return null;
    }
    final seen = json['last_seen'];
    return SyncDeviceInfo(
      device: device,
      name: _string(json['name']),
      platform: _string(json['platform']),
      joinedAt: DateTime.fromMillisecondsSinceEpoch(
        _int(json['joined_at']),
        isUtc: true,
      ),
      lastSeen: seen is int && seen > 0
          ? DateTime.fromMillisecondsSinceEpoch(seen, isUtc: true)
          : null,
    );
  }

  static SyncDeviceInfo? tryParse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map || decoded['format'] != syncFormat) {
        return null;
      }
      return fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return null;
    }
  }

  final String device;
  final String name;
  final String platform;
  final DateTime joinedAt;

  /// When it last added anything to the folder, as far as the computer that
  /// wrote this down knew. Only a roster says.
  final DateTime? lastSeen;

  Map<String, Object?> toJson() => {
        'device': device,
        'name': name,
        'platform': platform,
        'joined_at': joinedAt.toUtc().millisecondsSinceEpoch,
        if (lastSeen != null)
          'last_seen': lastSeen!.toUtc().millisecondsSinceEpoch,
      };

  String encode() => jsonEncode({'format': syncFormat, ...toJson()});
}

/// Which changes a checkpoint already holds, written beside it.
@immutable
class SyncCheckpointInfo {
  const SyncCheckpointInfo({
    required this.covers,
    required this.createdAt,
    required this.device,
  });

  factory SyncCheckpointInfo.fromJson(Map<String, Object?> json) {
    final covers = json['covers'];
    return SyncCheckpointInfo(
      covers: covers is Map
          ? {
              for (final entry in covers.entries)
                if (entry.key is String && entry.value is int)
                  entry.key as String: entry.value as int,
            }
          : const {},
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _int(json['created_at']),
        isUtc: true,
      ),
      device: _string(json['device']),
    );
  }

  static SyncCheckpointInfo? tryParse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map || decoded['format'] != syncFormat) {
        return null;
      }
      return SyncCheckpointInfo.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return null;
    }
  }

  /// For every computer, the last of its changes this checkpoint holds.
  final Map<String, int> covers;
  final DateTime createdAt;
  final String device;

  Map<String, Object?> toJson() => {
        'format': syncFormat,
        'covers': covers,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'device': device,
      };

  String encode() => jsonEncode(toJson());
}

/// What one round of pulling fetches, in order.
@immutable
class SyncPullPlan {
  const SyncPullPlan({
    this.checkpoints = const [],
    this.changes = const [],
    this.unreachable = const {},
  });

  /// Checkpoints to merge first, because changes this computer still needs
  /// are no longer in the folder on their own.
  final List<SyncPlannedCheckpoint> checkpoints;

  /// Other computers' changes, each computer's in its own order.
  final List<SyncPendingChange> changes;

  /// Computers some of whose changes are in no change or checkpoint in the
  /// folder, so this computer cannot catch up with them.
  final Set<String> unreachable;

  bool get isEmpty => checkpoints.isEmpty && changes.isEmpty;
}

@immutable
class SyncPlannedCheckpoint {
  const SyncPlannedCheckpoint({required this.checkpoint, required this.covers});

  final SyncCheckpoint checkpoint;

  /// The last change of each computer it holds.
  final Map<String, int> covers;
}

@immutable
class SyncPendingChange {
  const SyncPendingChange({
    required this.device,
    required this.seq,
    required this.file,
  });

  final String device;
  final int seq;
  final RemoteSyncFile file;
}

/// Decides what to fetch from [epoch], given what has been applied here.
///
/// [checkpointInfos] is keyed by the checkpoint pack's name.
///
/// One computer's changes are applied without gaps, or a merge could miss
/// something that only the gap held. A gap appears when tidying removed changes
/// this computer had not seen yet; it is filled by merging a checkpoint, which
/// holds everything up to the point it names. Computers that checkpointed at
/// about the same time each tidied away what their own checkpoint holds, so
/// filling every gap can take more than one.
///
/// This computer's own changes are no exception: [applied] names the ones its
/// workspace holds, and any others, sent before it last joined, are merged
/// back like anybody else's.
SyncPullPlan planSyncPull({
  required SyncEpochListing epoch,
  required Map<String, int> applied,
  required Map<String, SyncCheckpointInfo> checkpointInfos,
}) {
  final devices = {
    ...epoch.devices,
    for (final info in checkpointInfos.values) ...info.covers.keys,
  };

  // The first change of [device] that is needed but not in the folder on its
  // own, or null when nothing is missing.
  int? firstMissing(String device, Map<String, int> after) {
    final mine = epoch.changes[device];
    var expected = (after[device] ?? 0) + 1;
    while (mine != null && mine.containsKey(expected)) {
      expected++;
    }
    final later = mine != null && mine.isNotEmpty && mine.lastKey()! > expected;
    final held = checkpointInfos.values.any(
      (info) => (info.covers[device] ?? 0) >= expected,
    );
    return later || held ? expected : null;
  }

  Map<String, int> gaps(Map<String, int> after) => {
        for (final device in devices)
          if (firstMissing(device, after) case final seq?) device: seq,
      };

  final after = Map<String, int>.from(applied);
  final candidates = [
    for (final checkpoint in epoch.checkpoints.reversed)
      if (checkpointInfos.containsKey(checkpoint.pack.name)) checkpoint,
  ];
  final checkpoints = <SyncPlannedCheckpoint>[];
  var missing = gaps(after);
  while (missing.isNotEmpty) {
    // The newest checkpoint that fills one of the gaps.
    SyncCheckpoint? pick;
    for (final candidate in candidates) {
      final covers = checkpointInfos[candidate.pack.name]!.covers;
      if (missing.entries.any((gap) => (covers[gap.key] ?? 0) >= gap.value)) {
        pick = candidate;
        break;
      }
    }
    if (pick == null) {
      break;
    }
    candidates.remove(pick);
    final covers = checkpointInfos[pick.pack.name]!.covers;
    checkpoints.add(SyncPlannedCheckpoint(checkpoint: pick, covers: covers));
    covers.forEach((device, seq) {
      if ((after[device] ?? 0) < seq) {
        after[device] = seq;
      }
    });
    missing = gaps(after);
  }

  final changes = <SyncPendingChange>[];
  for (final entry in epoch.changes.entries) {
    var expected = (after[entry.key] ?? 0) + 1;
    for (final seq in entry.value.keys.where((seq) => seq >= expected)) {
      if (seq != expected) {
        break;
      }
      changes.add(
        SyncPendingChange(
          device: entry.key,
          seq: seq,
          file: entry.value[seq]!,
        ),
      );
      expected++;
    }
  }

  return SyncPullPlan(
    checkpoints: checkpoints,
    changes: changes,
    unreachable: missing.keys.toSet(),
  );
}

/// What tidying may remove once [newest] is in the folder: every change it
/// covers, every older checkpoint a newer one holds all of, and every epoch
/// that was replaced long enough ago that no computer can still be reading it.
///
/// [checkpointInfos] is keyed by the checkpoint pack's name.
List<RemoteSyncFile> syncFilesToTidy({
  required SyncListing listing,
  required SyncEpochListing epoch,
  required SyncCheckpointInfo newest,
  required Map<String, SyncCheckpointInfo> checkpointInfos,
  required DateTime now,
  Duration keepReplacedEpochs = const Duration(days: 7),
}) {
  final doomed = <RemoteSyncFile>[];
  for (final entry in epoch.changes.entries) {
    final covered = newest.covers[entry.key] ?? 0;
    for (final seq in entry.value.keys) {
      if (seq <= covered) {
        doomed.add(entry.value[seq]!);
      }
    }
  }
  // The newest two checkpoints stay: the newest, and the one before it in case
  // the newest turns out to be unreadable somewhere. An older one goes once a
  // newer one holds everything it does; until then it may be the only place
  // left for some changes, tidied away by the computer that wrote it. One
  // whose record never arrived is of no use to anybody.
  bool holds(Map<String, int> outer, Map<String, int> inner) =>
      inner.entries.every((entry) => (outer[entry.key] ?? 0) >= entry.value);
  final checkpoints = epoch.checkpoints;
  for (var i = 0; i < checkpoints.length - 2; i++) {
    final checkpoint = checkpoints[i];
    final covers = checkpointInfos[checkpoint.pack.name]?.covers;
    final redundant = checkpoint.info == null ||
        (covers != null &&
            checkpoints.skip(i + 1).any((later) {
              final laterCovers = checkpointInfos[later.pack.name]?.covers;
              return laterCovers != null && holds(laterCovers, covers);
            }));
    if (redundant) {
      doomed.add(checkpoint.pack);
      if (checkpoint.info != null) {
        doomed.add(checkpoint.info!);
      }
    }
  }
  final startedAt = epoch.baseInfo?.modifiedAt ?? epoch.base?.modifiedAt;
  if (startedAt != null && now.difference(startedAt) >= keepReplacedEpochs) {
    for (final other in listing.epochs.values) {
      if (other.id.compareTo(epoch.id) >= 0) {
        continue;
      }
      doomed
        ..addAll([
          if (other.base != null) other.base!,
          if (other.baseInfo != null) other.baseInfo!,
          if (other.vault != null) other.vault!,
        ])
        ..addAll(other.changes.values.expand((files) => files.values))
        ..addAll(other.deviceInfos.values)
        ..addAll(
          other.checkpoints.expand(
            (checkpoint) => [
              checkpoint.pack,
              if (checkpoint.info != null) checkpoint.info!,
            ],
          ),
        );
    }
  }
  return doomed;
}

String _string(Object? value) => value is String ? value : '';

int _int(Object? value) => value is int ? value : 0;
