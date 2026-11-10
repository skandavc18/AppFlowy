// A sync folder seen through its key: what goes in is sealed on the way, what
// comes out is opened, and anything in a sealed folder that is not sealed is
// refused rather than read.

import 'dart:io';

import 'package:appflowy/workspace/application/backup/provider_file_transfer.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:appflowy/workspace/application/sync/sync_remote.dart';
import 'package:appflowy/workspace/application/sync/sync_vault.dart';
import 'package:path/path.dart' as p;

class SealedSyncRemote implements SyncRemote {
  SealedSyncRemote(
    this.inner,
    this.key, {
    required Future<Directory> Function() scratch,
  }) : _scratch = scratch;

  final SyncRemote inner;

  /// The folder's key; null for a folder written before folders were sealed,
  /// whose files pass through as they are.
  final SyncKey? key;

  final Future<Directory> Function() _scratch;

  bool get isSealed => key != null;

  /// The name of the attached file with [hash]. In a sealed folder it is a
  /// keyed hash, which says nothing to anybody without the key.
  String blobName(String hash) => key?.blobName(hash) ?? hash;

  @override
  String get label => inner.label;

  @override
  Future<void> ensureReady() => inner.ensureReady();

  @override
  Future<List<RemoteSyncFile>> list({bool blobs = false}) =>
      inner.list(blobs: blobs);

  @override
  Future<void> delete(RemoteSyncFile file) => inner.delete(file);

  @override
  void dispose() => inner.dispose();

  @override
  Future<RemoteSyncFile> upload(
    String name,
    File file, {
    bool blob = false,
    FileTransferProgress? onProgress,
  }) async {
    final key = this.key;
    final kind = SyncFileName.parse(name)?.kind;
    if (key == null || kind == null || kind == SyncFileKind.vault) {
      return inner.upload(name, file, blob: blob, onProgress: onProgress);
    }
    final sealed = await _scratchFile('out');
    try {
      if (_isText(kind)) {
        await sealed.writeAsString(
          key.sealText(await file.readAsString(), context: _context(name)),
        );
      } else {
        await key.sealFile(file, sealed);
      }
      return await inner.upload(
        name,
        sealed,
        blob: blob,
        onProgress: onProgress,
      );
    } finally {
      await _discard(sealed);
    }
  }

  @override
  Future<void> download(
    RemoteSyncFile file,
    File destination, {
    FileTransferProgress? onProgress,
  }) async {
    final key = this.key;
    final kind = SyncFileName.parse(file.name)?.kind;
    if (key == null || kind == null || kind == SyncFileKind.vault) {
      return inner.download(file, destination, onProgress: onProgress);
    }
    if (_isText(kind)) {
      await destination.writeAsString(await readText(file));
      return;
    }
    final raw = await _scratchFile('in');
    try {
      await inner.download(file, raw, onProgress: onProgress);
      if (!await isSealedSyncFile(raw)) {
        throw const SyncSealError('A file in the sync folder is not sealed.');
      }
      await key.openFile(raw, destination);
    } finally {
      await _discard(raw);
    }
  }

  @override
  Future<String> readText(RemoteSyncFile file) async {
    final text = await inner.readText(file);
    final key = this.key;
    final kind = SyncFileName.parse(file.name)?.kind;
    if (key == null || kind == null || kind == SyncFileKind.vault) {
      return text;
    }
    return key.openText(text, context: _context(file.name));
  }

  // Bound to the name, so a record cannot be passed off as another one.
  static String _context(String name) => 'file:$name';

  static bool _isText(SyncFileKind kind) => switch (kind) {
        SyncFileKind.baseInfo ||
        SyncFileKind.checkpointInfo ||
        SyncFileKind.deviceInfo =>
          true,
        _ => false,
      };

  Future<File> _scratchFile(String purpose) async {
    final folder = await _scratch();
    await folder.create(recursive: true);
    return File(
      p.join(folder.path, 'sealed-$purpose-${randomSyncToken(10)}.tmp'),
    );
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
}
