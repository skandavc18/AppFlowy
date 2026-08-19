// Gathering a workspace into one file, and putting it back.
//
// A copy is an ordinary zip. That is a deliberate choice: somebody whose
// computer has died should be able to open their backup with the tools their
// new computer already has, and should not need AppFlowy to run in order to get
// at a photograph they put in a page. Sealing (see backup_crypto.dart) is a
// layer on top of that, not instead of it.
//
// Both directions run in an isolate — deflate at level 9 over a folder of
// photographs is seconds to minutes of solid work, and the interface has to
// keep drawing while it happens.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:appflowy/workspace/application/backup/backup_manifest.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Where the workspace's own files sit inside the archive.
const String backupWorkspaceFolder = 'workspace';

/// Where this computer's settings sit inside the archive.
const String backupPreferencesFolder = 'preferences';

/// What one archive turned out to be.
@immutable
class BackupArchiveResult {
  const BackupArchiveResult({
    required this.fileCount,
    required this.rawBytes,
    required this.archiveBytes,
    this.omissions = const <BackupOmission>[],
  });

  final int fileCount;
  final int rawBytes;
  final int archiveBytes;
  final List<BackupOmission> omissions;

  /// What was saved, as a fraction. Zero when nothing was compressed.
  double get savedFraction =>
      rawBytes <= 0 ? 0 : (1 - archiveBytes / rawBytes).clamp(0, 1).toDouble();
}

/// How far along a gather or an extraction is.
typedef BackupArchiveProgress = void Function(int done, int total);

/// Writes every chosen part of [dataPath] into [destination].
Future<BackupArchiveResult> writeBackupArchive({
  required String dataPath,
  required File destination,
  required Set<BackupPart> parts,
  required BackupCompression compression,
  String preferencesPath = '',
  int maximumFileBytes = BackupPolicy.anySize,
  BackupArchiveProgress? onProgress,
}) async {
  await destination.parent.create(recursive: true);
  final answer = await _run(
    _writeEntryPoint,
    <String, Object?>{
      'data_path': dataPath,
      'destination': destination.path,
      'parts': [for (final part in parts) part.name],
      'level': compression.deflateLevel,
      'store': !compression.compresses,
      'preferences': preferencesPath,
      'maximum_file_bytes': maximumFileBytes,
    },
    onProgress,
  );

  return BackupArchiveResult(
    fileCount: answer['file_count']! as int,
    rawBytes: answer['raw_bytes']! as int,
    archiveBytes: answer['archive_bytes']! as int,
    omissions: [
      for (final omission in answer['omissions']! as List)
        BackupOmission.fromJson(Map<String, Object?>.from(omission as Map)),
    ],
  );
}

/// Unpacks [source] into [target], which is created if it is not there.
///
/// Returns how many files were written. Never writes outside [target], however
/// the names inside the archive are spelled.
Future<int> extractBackupArchive({
  required File source,
  required Directory target,
  BackupArchiveProgress? onProgress,
}) async {
  await target.create(recursive: true);
  final answer = await _run(
    _extractEntryPoint,
    <String, Object?>{
      'source': source.path,
      'target': target.path,
    },
    onProgress,
  );
  return answer['file_count']! as int;
}

/// The parts an archive actually holds, read from its listing.
///
/// Used before a restore, so the interface can say what is about to be written
/// even for an archive whose manifest has been lost.
Future<Set<BackupPart>> readBackupArchiveParts(File source) async {
  final parts = <BackupPart>{};
  InputFileStream? input;
  try {
    input = InputFileStream(source.path);
    final archive = ZipDecoder().decodeBuffer(input);
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final segments = p.posix.split(file.name);
      if (segments.isEmpty) {
        continue;
      }
      if (segments.first == backupPreferencesFolder) {
        parts.add(BackupPart.preferences);
      } else if (segments.first == backupWorkspaceFolder &&
          segments.length > 1) {
        parts.add(backupPartOfFolder(segments[1]));
      }
    }
  } on Object {
    // A listing that cannot be read is reported as "nothing known", which the
    // restore screen already handles.
    return const <BackupPart>{};
  } finally {
    await input?.close();
  }
  return parts;
}

// --- The work itself ----------------------------------------------------------

Map<String, Object?> _writeArchive(
  Map<String, Object?> request,
  BackupArchiveProgress? onProgress,
) {
  final dataPath = request['data_path']! as String;
  final destination = request['destination']! as String;
  final level = request['level']! as int;
  final store = request['store']! as bool;
  final preferencesPath = request['preferences']! as String;
  final maximumFileBytes = request['maximum_file_bytes']! as int;
  final parts = <BackupPart>{
    for (final name in request['parts']! as List)
      if (BackupPart.fromValue(name) != null) BackupPart.fromValue(name)!,
  };

  final chosen = <_Candidate>[];
  final tooLarge = <String>[];
  var tooLargeBytes = 0;
  final unreadable = <String>[];

  final root = Directory(dataPath);
  if (root.existsSync()) {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: dataPath);
      final segments = p.split(relative);
      if (segments.isEmpty) {
        continue;
      }
      // Names are recorded the way they are written inside the archive, so a
      // record made on Windows reads the same as one made anywhere else.
      final inside = p.posix.joinAll(segments);
      final top = segments.first;
      if (backupExcludedFolders.contains(top)) {
        continue;
      }
      // A file sitting loose at the root belongs to the workspace itself.
      final part = segments.length == 1
          ? BackupPart.workspace
          : backupPartOfFolder(top);
      if (!parts.contains(part)) {
        continue;
      }

      final int length;
      try {
        length = entity.lengthSync();
      } on FileSystemException {
        unreadable.add(inside);
        continue;
      }
      if (maximumFileBytes != BackupPolicy.anySize &&
          length > maximumFileBytes) {
        tooLarge.add(inside);
        tooLargeBytes += length;
        continue;
      }

      chosen.add(
        _Candidate(
          file: entity,
          name: p.posix.join(backupWorkspaceFolder, inside),
          length: length,
        ),
      );
    }
  }

  if (parts.contains(BackupPart.preferences) && preferencesPath.isNotEmpty) {
    final preferences = File(preferencesPath);
    if (preferences.existsSync()) {
      chosen.add(
        _Candidate(
          file: preferences,
          name: p.posix.join(
            backupPreferencesFolder,
            p.basename(preferencesPath),
          ),
          length: preferences.lengthSync(),
        ),
      );
    }
  }

  final total = chosen.fold<int>(0, (sum, candidate) => sum + candidate.length);

  final encoder = ZipFileEncoder()..create(destination, level: level);
  var done = 0;
  var written = 0;
  try {
    for (final candidate in chosen) {
      InputFileStream? content;
      try {
        // The public `addFile` is asynchronous and there is no synchronous
        // form, so the archive entry is built the same way it builds one:
        // a stream over the file, so nothing is ever held in memory whole.
        content = InputFileStream(candidate.file.path);
        final entry = ArchiveFile.stream(
          candidate.name,
          candidate.length,
          content,
        )
          ..lastModTime =
              candidate.file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000
          ..compress = !store;
        encoder.addArchiveFile(entry);
        written++;
      } on FileSystemException {
        // A file that vanished or is locked while the copy runs is named and
        // skipped; one unreadable attachment must not lose the whole backup.
        unreadable.add(candidate.name);
      } finally {
        content?.closeSync();
      }
      done += candidate.length;
      onProgress?.call(done, total);
    }
  } finally {
    encoder.closeSync();
  }

  final omissions = <BackupOmission>[
    if (tooLarge.isNotEmpty)
      BackupOmission(
        reason: BackupOmissionReason.tooLarge,
        count: tooLarge.length,
        bytes: tooLargeBytes,
        names: tooLarge,
      ),
    if (unreadable.isNotEmpty)
      BackupOmission(
        reason: BackupOmissionReason.unreadable,
        count: unreadable.length,
        bytes: 0,
        names: unreadable,
      ),
  ];

  return <String, Object?>{
    'file_count': written,
    'raw_bytes': total,
    'archive_bytes': File(destination).lengthSync(),
    'omissions': [for (final omission in omissions) omission.toJson()],
  };
}

Map<String, Object?> _extractArchive(
  Map<String, Object?> request,
  BackupArchiveProgress? onProgress,
) {
  final sourcePath = request['source']! as String;
  final targetPath = request['target']! as String;
  final target = Directory(targetPath)..createSync(recursive: true);
  final root = p.normalize(target.absolute.path);

  final input = InputFileStream(sourcePath);
  var written = 0;
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    final files = [for (final file in archive.files) if (file.isFile) file];
    final total = files.fold<int>(0, (sum, file) => sum + file.size);
    var done = 0;

    for (final file in files) {
      final destination = p.normalize(
        p.join(root, p.joinAll(p.posix.split(file.name))),
      );
      // An archive is somebody else's data and a name inside one can say `..`.
      if (!p.isWithin(root, destination)) {
        continue;
      }
      Directory(p.dirname(destination)).createSync(recursive: true);
      final handle = OutputFileStream(destination);
      try {
        file.writeContent(handle);
        written++;
      } finally {
        handle.closeSync();
      }
      done += file.size;
      onProgress?.call(done, total);
    }
  } finally {
    input.closeSync();
  }

  return <String, Object?>{'file_count': written};
}

@immutable
class _Candidate {
  const _Candidate({
    required this.file,
    required this.name,
    required this.length,
  });

  final File file;
  final String name;
  final int length;
}

// --- Running it on another thread ---------------------------------------------

class _ArchiveMessage {
  const _ArchiveMessage(this.request, this.replyTo);

  final Map<String, Object?> request;
  final SendPort replyTo;
}

Future<Map<String, Object?>> _run(
  void Function(_ArchiveMessage) entryPoint,
  Map<String, Object?> request,
  BackupArchiveProgress? onProgress,
) async {
  final port = ReceivePort();
  final completer = Completer<Map<String, Object?>>();

  final subscription = port.listen((Object? message) {
    if (message is List && message.length == 3 && message.first == 'progress') {
      onProgress?.call(message[1] as int, message[2] as int);
      return;
    }
    if (message is List && message.length == 2 && message.first == 'done') {
      if (!completer.isCompleted) {
        completer.complete(
          Map<String, Object?>.from(message[1]! as Map),
        );
      }
      return;
    }
    if (message is List && message.length == 2 && message.first == 'error') {
      if (!completer.isCompleted) {
        completer.completeError(BackupArchiveError(message[1] as String));
      }
    }
  });

  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(
      entryPoint,
      _ArchiveMessage(request, port.sendPort),
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    return await completer.future;
  } finally {
    await subscription.cancel();
    port.close();
    isolate?.kill(priority: Isolate.immediate);
  }
}

void _writeEntryPoint(_ArchiveMessage message) =>
    _report(message, _writeArchive);

void _extractEntryPoint(_ArchiveMessage message) =>
    _report(message, _extractArchive);

void _report(
  _ArchiveMessage message,
  Map<String, Object?> Function(
    Map<String, Object?>,
    BackupArchiveProgress?,
  ) work,
) {
  try {
    var lastReported = 0;
    final answer = work(message.request, (done, total) {
      // One message every few megabytes: a send per file would cost more than
      // the deflate on a folder of thumbnails.
      if (done - lastReported >= 2 * 1024 * 1024 || done >= total) {
        lastReported = done;
        message.replyTo.send(['progress', done, total]);
      }
    });
    message.replyTo.send(['done', answer]);
  } on Object catch (error) {
    message.replyTo.send(['error', error.toString()]);
  }
}

/// Raised when an archive could not be written or read.
class BackupArchiveError implements Exception {
  const BackupArchiveError(this.detail);

  final String detail;

  @override
  String toString() => 'BackupArchiveError: $detail';
}
