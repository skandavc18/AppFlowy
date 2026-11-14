// The files a workspace keeps beside its pages: pictures, attachments, saved
// web pages, version history.
//
// They are synced as files, by path, the way any folder sync would: the
// newest version of a path wins, wherever and in whatever order the versions
// arrive, so every computer ends up with the same one. Contents travel
// separately, named by their hash, so a picture used in ten pages, or brought
// back after a restore, is stored once. Removals are versions too: a file
// removed elsewhere goes here unless it changed here, and an older version
// arriving late does not bring it back.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy_backend/log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The folders of the data directory that are synced. Caches are not here, and
/// neither are keyboard shortcuts: they belong to the keyboard in front of you.
const List<String> syncedDataFolders = [
  'files',
  'images',
  'covers',
  'page_versions',
  'workflows',
  'extension_data',
  'extensions',
  'bookmark_snapshots',
];

/// One synced file: where it is, what it holds and when it last changed.
@immutable
class SyncFileRecord {
  const SyncFileRecord({
    required this.path,
    this.hash = '',
    this.bytes = 0,
    this.modified = 0,
  });

  factory SyncFileRecord.fromJson(Map<String, Object?> json) => SyncFileRecord(
        path: json['p'] is String ? json['p']! as String : '',
        hash: json['h'] is String ? json['h']! as String : '',
        bytes: json['s'] is int ? json['s']! as int : 0,
        modified: json['m'] is int ? json['m']! as int : 0,
      );

  /// Relative to the data folder, always with `/`.
  final String path;

  /// SHA-256 of the contents, in hex.
  final String hash;
  final int bytes;

  /// Milliseconds since the epoch.
  final int modified;

  Map<String, Object?> toJson() => {
        'p': path,
        if (hash.isNotEmpty) 'h': hash,
        if (bytes > 0) 's': bytes,
        'm': modified,
      };

  @override
  bool operator ==(Object other) =>
      other is SyncFileRecord &&
      other.path == path &&
      other.hash == hash &&
      other.bytes == bytes &&
      other.modified == modified;

  @override
  int get hashCode => Object.hash(path, hash, bytes, modified);
}

/// Whether [path], as another computer wrote it, may be written here.
///
/// A sync folder is somebody else's data as far as this computer can tell, and
/// a path inside it can say anything. Only plain relative paths inside one of
/// the synced folders are accepted.
bool isSafeSyncPath(String path) {
  if (path.isEmpty || path.contains('\\') || path.startsWith('/')) {
    return false;
  }
  final segments = p.posix.split(path);
  if (segments.length < 2 || !syncedDataFolders.contains(segments.first)) {
    return false;
  }
  for (final segment in segments) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains(':')) {
      return false;
    }
  }
  return true;
}

/// Whether a version of a path made at [time] with contents [hash] is later
/// than one made at [otherTime] with [otherHash]. The later modification wins;
/// two made at the same moment are told apart by their contents, so every
/// computer picks the same one. A removal has no contents and loses such a tie.
bool isLaterSyncVersion(
  int time,
  String hash,
  int otherTime,
  String otherHash,
) =>
    time > otherTime || (time == otherTime && hash.compareTo(otherHash) > 0);

/// What each synced file was when this computer last sent or took it.
class SyncFileIndex {
  SyncFileIndex([Map<String, SyncFileRecord>? entries])
      : entries = entries ?? <String, SyncFileRecord>{};

  /// How long a removal is remembered.
  static const Duration keepRemovals = Duration(days: 180);

  final Map<String, SyncFileRecord> entries;

  /// Files whose contents were not in the folder yet when they were named,
  /// to be fetched again later.
  final Map<String, SyncFileRecord> waiting = {};

  /// When synced files were removed, here or elsewhere, by path.
  final Map<String, int> removed = {};

  /// Remembers that [path] was removed at [time].
  void noteRemoved(String path, int time) {
    removed[path] = max(removed[path] ?? 0, time);
  }

  /// Every removal, as records that can travel in a pack.
  List<SyncFileRecord> get removals => [
        for (final entry in removed.entries)
          SyncFileRecord(path: entry.key, modified: entry.value),
      ];

  static Future<SyncFileIndex> load(File file) async {
    try {
      if (!file.existsSync()) {
        return SyncFileIndex();
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return SyncFileIndex();
      }
      List<SyncFileRecord> read(Object? value) => value is List
          ? [
              for (final entry in value)
                if (entry is Map)
                  SyncFileRecord.fromJson(Map<String, Object?>.from(entry)),
            ]
          : const [];
      final index = SyncFileIndex({
        for (final record in read(decoded['files'])) record.path: record,
      });
      for (final record in read(decoded['waiting'])) {
        index.waiting[record.path] = record;
      }
      for (final record in read(decoded['removed'])) {
        index.noteRemoved(record.path, record.modified);
      }
      return index;
    } on Object catch (error) {
      Log.warn('The synced files record could not be read: $error');
      return SyncFileIndex();
    }
  }

  Future<void> save(File file) async {
    final forgetBefore =
        DateTime.now().subtract(keepRemovals).millisecondsSinceEpoch;
    removed.removeWhere(
      (path, time) => entries.containsKey(path) || time < forgetBefore,
    );
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.tmp');
    await staging.writeAsString(
      jsonEncode({
        'files': [for (final record in entries.values) record.toJson()],
        'waiting': [for (final record in waiting.values) record.toJson()],
        'removed': [for (final record in removals) record.toJson()],
      }),
    );
    await staging.rename(file.path);
  }
}

/// What changed in the synced folders since the index was last brought up to
/// date.
@immutable
class SyncFileScan {
  const SyncFileScan({
    required this.current,
    required this.changed,
    required this.deleted,
    this.skipped = 0,
  });

  /// Every synced file as it is now.
  final Map<String, SyncFileRecord> current;
  final List<SyncFileRecord> changed;
  final List<SyncFileRecord> deleted;

  /// Files left out because they are larger than sync carries.
  final int skipped;

  bool get isEmpty => changed.isEmpty && deleted.isEmpty;
}

/// Walks the synced folders under [dataPath].
///
/// A file whose size and modification time match its record keeps the hash it
/// had, so a scan reads only what actually changed.
Future<SyncFileScan> scanSyncedFiles({
  required String dataPath,
  required SyncFileIndex index,
  int maximumBytes = -1,
  List<String> folders = syncedDataFolders,
  bool strict = false,
}) async {
  final current = <String, SyncFileRecord>{};
  final changed = <SyncFileRecord>[];
  var skipped = 0;

  for (final folder in folders) {
    final directory = Directory(p.join(dataPath, folder));
    if (strict &&
        await FileSystemEntity.type(directory.path, followLinks: false) ==
            FileSystemEntityType.link) {
      throw FileSystemException(
        'A synced folder is a symbolic link.',
        directory.path,
      );
    }
    if (!directory.existsSync()) {
      continue;
    }
    final entities = directory.listSync(recursive: true, followLinks: false);
    for (final entity in entities) {
      if (strict && entity is Link) {
        throw FileSystemException(
          'A synced file is a symbolic link.',
          entity.path,
        );
      }
      if (entity is! File || _isScratch(p.basename(entity.path))) {
        continue;
      }
      final path = p.posix.joinAll(
        p.split(p.relative(entity.path, from: dataPath)),
      );
      final FileStat stat;
      try {
        stat = entity.statSync();
      } on FileSystemException {
        if (strict) rethrow;
        continue;
      }
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }
      final known = index.entries[path];
      if (maximumBytes >= 0 && stat.size > maximumBytes) {
        skipped++;
        // Grown too large to carry: what was sent before stays, rather than
        // the file counting as removed.
        if (known != null) {
          current[path] = known;
        }
        continue;
      }
      final modified = stat.modified.millisecondsSinceEpoch;
      if (known != null &&
          known.bytes == stat.size &&
          known.modified == modified &&
          known.hash.isNotEmpty) {
        current[path] = known;
        continue;
      }
      final String hash;
      try {
        hash = await hashFile(entity);
      } on FileSystemException {
        if (strict) rethrow;
        continue;
      }
      final record = SyncFileRecord(
        path: path,
        hash: hash,
        bytes: stat.size,
        modified: modified,
      );
      current[path] = record;
      if (known == null || known.hash != hash) {
        changed.add(record);
      }
    }
  }

  final deleted = [
    for (final record in index.entries.values)
      if (!current.containsKey(record.path))
        SyncFileRecord(
          path: record.path,
          modified: DateTime.now().millisecondsSinceEpoch,
        ),
  ];
  return SyncFileScan(
    current: current,
    changed: changed,
    deleted: deleted,
    skipped: skipped,
  );
}

bool _isScratch(String name) =>
    name.startsWith('.') || name.endsWith('.part') || name.endsWith('.tmp');

Future<String> hashFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// What applying another computer's files did.
@immutable
class SyncFileApplyResult {
  const SyncFileApplyResult({
    this.written = 0,
    this.removed = 0,
    this.kept = 0,
    this.waiting = 0,
    this.changedPaths = const {},
  });

  final int written;
  final int removed;

  /// Changed here since it was last synced, or newer here, so this
  /// computer's version stays.
  final int kept;

  /// Named, but their contents are not in the folder yet.
  final int waiting;
  final Set<String> changedPaths;
}

/// Fetches the contents with [hash] into [destination]; false when they are
/// not in the folder.
typedef SyncBlobFetcher = Future<bool> Function(String hash, File destination);

/// Brings another computer's file changes into [dataPath].
///
/// Each path ends up with its latest version, whatever order versions arrive
/// in: one older than what is here changes nothing. A removal never takes away
/// a file changed here since it was last synced. Fetches run up to
/// [concurrency] at a time, and duplicate hashes in the same batch are fetched
/// once and copied locally.
Future<SyncFileApplyResult> applyRemoteFiles({
  required String dataPath,
  required SyncFileIndex index,
  required List<SyncFileRecord> files,
  required List<SyncFileRecord> deleted,
  required SyncBlobFetcher fetch,
  int concurrency = 4,
}) async {
  var written = 0;
  var removed = 0;
  var kept = 0;
  final changedPaths = <String>{};

  // A version still waiting for its contents is dropped once a version at
  // least as late is here.
  void settle(String path, int time, String hash) {
    final waiting = index.waiting[path];
    if (waiting != null &&
        !isLaterSyncVersion(waiting.modified, waiting.hash, time, hash)) {
      index.waiting.remove(path);
    }
  }

  for (final record in deleted) {
    if (!isSafeSyncPath(record.path)) {
      continue;
    }
    final waiting = index.waiting[record.path];
    if (waiting != null &&
        isLaterSyncVersion(
          waiting.modified,
          waiting.hash,
          record.modified,
          '',
        )) {
      continue;
    }
    index.waiting.remove(record.path);
    final local = File(p.joinAll([dataPath, ...p.posix.split(record.path)]));
    final known = index.entries[record.path];
    if (!local.existsSync()) {
      index.entries.remove(record.path);
      index.noteRemoved(record.path, record.modified);
      continue;
    }
    final stat = local.statSync();
    final unchangedHere = known != null &&
        ((known.bytes == stat.size &&
                known.modified == stat.modified.millisecondsSinceEpoch) ||
            await hashFile(local) == known.hash);
    if (!unchangedHere ||
        !isLaterSyncVersion(record.modified, '', known.modified, known.hash)) {
      kept++;
      continue;
    }
    try {
      await local.delete();
      removed++;
      changedPaths.add(record.path);
      index.entries.remove(record.path);
      index.noteRemoved(record.path, record.modified);
    } on FileSystemException catch (error) {
      // Still here and still known, so it is not sent back as a new file.
      Log.warn('A synced file could not be removed: $error');
    }
  }

  // Latest winning record per path, filtered against what is already on disk.
  final neededByHash = <String, List<SyncFileRecord>>{};
  final orderedTargets = <String, SyncFileRecord>{};
  for (final record in files) {
    if (!isSafeSyncPath(record.path) || record.hash.isEmpty) {
      continue;
    }
    final prior = orderedTargets[record.path];
    if (prior != null &&
        !isLaterSyncVersion(
          record.modified,
          record.hash,
          prior.modified,
          prior.hash,
        )) {
      continue;
    }
    orderedTargets[record.path] = record;
  }

  for (final record in orderedTargets.values) {
    final waiting = index.waiting[record.path];
    if (waiting != null &&
        isLaterSyncVersion(
          waiting.modified,
          waiting.hash,
          record.modified,
          record.hash,
        )) {
      continue;
    }
    final local = File(p.joinAll([dataPath, ...p.posix.split(record.path)]));
    final known = index.entries[record.path];
    if (local.existsSync()) {
      final stat = local.statSync();
      final modified = stat.modified.millisecondsSinceEpoch;
      final unchangedByStat = known != null &&
          known.bytes == stat.size &&
          known.modified == modified;
      final localHash = unchangedByStat ? known.hash : await hashFile(local);
      if (localHash == record.hash) {
        index.entries[record.path] = SyncFileRecord(
          path: record.path,
          hash: localHash,
          bytes: stat.size,
          modified: modified,
        );
        index.removed.remove(record.path);
        index.waiting.remove(record.path);
        continue;
      }
      // The version here: the one last synced, or a change made here since.
      final changedHere = known == null || known.hash != localHash;
      final hereTime = changedHere ? modified : known.modified;
      if (!isLaterSyncVersion(
        record.modified,
        record.hash,
        hereTime,
        localHash,
      )) {
        if (changedHere) {
          kept++;
        }
        settle(record.path, hereTime, localHash);
        continue;
      }
    } else if (known != null) {
      // Removed here and not sent yet: only a later version brings it back.
      if (!isLaterSyncVersion(
        record.modified,
        record.hash,
        known.modified,
        known.hash,
      )) {
        settle(record.path, known.modified, known.hash);
        continue;
      }
    } else {
      final removedAt = index.removed[record.path];
      if (removedAt != null &&
          !isLaterSyncVersion(record.modified, record.hash, removedAt, '')) {
        settle(record.path, removedAt, '');
        continue;
      }
    }
    neededByHash.putIfAbsent(record.hash, () => <SyncFileRecord>[]).add(record);
  }

  if (neededByHash.isNotEmpty) {
    final queue = neededByHash.entries.toList(growable: false);
    var cursor = 0;
    final workers = min(max(1, concurrency), queue.length);

    Future<void> runWorker() async {
      while (true) {
        final next = cursor++;
        if (next >= queue.length) {
          return;
        }
        final hash = queue[next].key;
        final targets = queue[next].value;
        final primary = targets.first;
        final primaryLocal =
            File(p.joinAll([dataPath, ...p.posix.split(primary.path)]));
        final staging = File(
          p.join(
            primaryLocal.parent.path,
            '.${p.basename(primaryLocal.path)}.$hash.sync.part',
          ),
        );
        try {
          await primaryLocal.parent.create(recursive: true);
          if (!await fetch(hash, staging)) {
            for (final record in targets) {
              index.waiting[record.path] = record;
            }
            continue;
          }
          if (await hashFile(staging) != hash) {
            Log.warn('A synced file did not match its record and was skipped.');
            await staging.delete();
            continue;
          }
          for (var i = 0; i < targets.length; i++) {
            final record = targets[i];
            final local =
                File(p.joinAll([dataPath, ...p.posix.split(record.path)]));
            await local.parent.create(recursive: true);
            if (i < targets.length - 1) {
              final copyPart = File(
                p.join(
                  local.parent.path,
                  '.${p.basename(local.path)}.$i.sync.part',
                ),
              );
              await staging.copy(copyPart.path);
              await copyPart.rename(local.path);
            } else {
              await staging.rename(local.path);
            }
            final when = DateTime.fromMillisecondsSinceEpoch(record.modified);
            try {
              await local.setLastModified(when);
            } on FileSystemException {
              // Keeping the remote time only saves a hash on the next scan.
            }
            final stat = local.statSync();
            index.entries[record.path] = SyncFileRecord(
              path: record.path,
              hash: record.hash,
              bytes: stat.size,
              modified: stat.modified.millisecondsSinceEpoch,
            );
            index.removed.remove(record.path);
            index.waiting.remove(record.path);
            written++;
            changedPaths.add(record.path);
          }
        } on Object catch (error) {
          Log.warn('A synced file could not be written: $error');
          if (staging.existsSync()) {
            try {
              await staging.delete();
            } on Object {
              // Swept on a later run.
            }
          }
        }
      }
    }

    await Future.wait([for (var i = 0; i < workers; i++) runWorker()]);
  }

  return SyncFileApplyResult(
    written: written,
    removed: removed,
    kept: kept,
    waiting: index.waiting.length,
    changedPaths: changedPaths,
  );
}
