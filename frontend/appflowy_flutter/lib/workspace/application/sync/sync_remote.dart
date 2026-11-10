// The folder a workspace is synced through, whatever holds it.
//
// Sync needs very little of a folder: say what is in it, take a file, give a
// file back, forget a file. Attached files live in a subfolder of their own,
// so the listing that is read every few seconds stays the size of the changes
// rather than the size of everything ever attached.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/backup/backup_target.dart';
import 'package:appflowy/workspace/application/backup/provider_file_transfer.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

/// The subfolder attached files are kept in.
const String syncBlobFolderName = 'afsync1_files';

abstract class SyncRemote {
  /// What the folder is called, for the interface.
  String get label;

  /// Proves the folder can be reached and written to.
  Future<void> ensureReady();

  /// The sync files in the folder, or in its attached-files subfolder.
  Future<List<RemoteSyncFile>> list({bool blobs = false});

  /// Puts [file] in the folder under [name].
  Future<RemoteSyncFile> upload(
    String name,
    File file, {
    bool blob = false,
    FileTransferProgress? onProgress,
  });

  /// Brings [file] back to [destination].
  Future<void> download(
    RemoteSyncFile file,
    File destination, {
    FileTransferProgress? onProgress,
  });

  /// A small file's text.
  Future<String> readText(RemoteSyncFile file);

  Future<void> delete(RemoteSyncFile file);

  void dispose() {}
}

/// Opens the folder [destination] names.
Future<SyncRemote> openSyncRemote(BackupDestination destination) async {
  switch (destination.kind) {
    case BackupDestinationKind.folder:
      return FolderSyncRemote(Directory(destination.localPath));
    case BackupDestinationKind.googleDrive:
    case BackupDestinationKind.oneDrive:
    case BackupDestinationKind.box:
      await ProviderConnections.instance.ensureLoaded();
      final connection =
          ProviderConnections.instance.byId(destination.connectionId);
      if (connection == null) {
        throw const BackupTargetError(
          'The account sync uses is no longer signed in.',
        );
      }
      return ProviderSyncRemote(
        kind: destination.kind,
        connection: connection,
        folderId: destination.folderId,
        folderName: destination.folderName,
      );
    case BackupDestinationKind.none:
    case BackupDestinationKind.appflowyCloud:
      throw const BackupTargetError('That place cannot hold a sync folder.');
  }
}

/// A folder on this computer — or one another program keeps in step, such as
/// a Dropbox or Syncthing folder.
class FolderSyncRemote extends SyncRemote {
  FolderSyncRemote(this.folder);

  final Directory folder;

  Directory get _blobs => Directory(p.join(folder.path, syncBlobFolderName));

  @override
  String get label => folder.path;

  @override
  Future<void> ensureReady() async {
    if (folder.path.isEmpty) {
      throw const BackupTargetError('No folder has been chosen.');
    }
    await folder.create(recursive: true);
  }

  @override
  Future<List<RemoteSyncFile>> list({bool blobs = false}) async {
    final directory = blobs ? _blobs : folder;
    if (!directory.existsSync()) {
      return const [];
    }
    final files = <RemoteSyncFile>[];
    await for (final entity in directory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! File || !name.startsWith(syncFilePrefix)) {
        continue;
      }
      try {
        final stat = entity.statSync();
        files.add(
          RemoteSyncFile(
            name: name,
            id: entity.path,
            bytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      } on FileSystemException {
        // Removed while the folder was being read.
      }
    }
    return files;
  }

  @override
  Future<RemoteSyncFile> upload(
    String name,
    File file, {
    bool blob = false,
    FileTransferProgress? onProgress,
  }) async {
    final directory = blob ? _blobs : folder;
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, name));
    // Staged under a name nothing reads, then renamed: a program syncing this
    // folder elsewhere must never pick up half a file.
    final staging = File(p.join(directory.path, '.$name.part'));
    await file.copy(staging.path);
    await staging.rename(target.path);
    final length = target.lengthSync();
    onProgress?.call(length, length);
    return RemoteSyncFile(
      name: name,
      id: target.path,
      bytes: length,
      modifiedAt: target.lastModifiedSync(),
    );
  }

  @override
  Future<void> download(
    RemoteSyncFile file,
    File destination, {
    FileTransferProgress? onProgress,
  }) async {
    final source = File(file.id);
    if (!source.existsSync()) {
      throw const BackupTargetError('A sync file is no longer in the folder.');
    }
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    final length = destination.lengthSync();
    onProgress?.call(length, length);
  }

  @override
  Future<String> readText(RemoteSyncFile file) => File(file.id).readAsString();

  @override
  Future<void> delete(RemoteSyncFile file) async {
    try {
      final target = File(file.id);
      if (target.existsSync()) {
        await target.delete();
      }
    } on FileSystemException {
      // Already gone is what was wanted.
    }
  }
}

/// A folder in Google Drive, OneDrive or Box.
class ProviderSyncRemote extends SyncRemote {
  ProviderSyncRemote({
    required this.kind,
    required this.connection,
    required this.folderId,
    required this.folderName,
    @visibleForTesting CollectionProvider? provider,
  }) : _provider = provider;

  final BackupDestinationKind kind;
  final ProviderConnection connection;
  final String folderId;
  final String folderName;

  CollectionProvider? _provider;
  ProviderFileTransfer? _transfer;
  String? _blobFolderId;

  /// A sync folder can hold far more files than a page of a listing.
  static const int listingLimit = 20000;

  @override
  String get label => folderName.isEmpty
      ? connection.accountLabel
      : '$folderName · ${connection.accountLabel}';

  ProviderFileTransfer get _files => _transfer ??= ProviderFileTransfer(
        service: kind.providerService!,
        connection: connection,
      );

  Future<CollectionProvider> _resolve() async {
    final existing = _provider;
    if (existing != null) {
      return existing;
    }
    final provider = ProviderRegistry.create(
      CollectionSource(
        service: kind.providerService!,
        connectionId: connection.id,
        remoteId: folderId,
        remoteName: folderName,
      ),
    );
    if (provider == null) {
      throw const BackupTargetError('That service is not available.');
    }
    await provider.ensureReady();
    _provider = provider;
    return provider;
  }

  @override
  Future<void> ensureReady() async {
    if (folderId.isEmpty) {
      throw const BackupTargetError('No folder has been chosen.');
    }
    final provider = await _resolve();
    if (!provider.capabilities.canUpload) {
      throw const BackupTargetError(
        'This account was signed in without permission to write.',
      );
    }
  }

  /// The attached-files subfolder, made the first time it is needed.
  Future<String?> _blobFolder({required bool create}) async {
    final known = _blobFolderId;
    if (known != null) {
      return known;
    }
    final provider = await _resolve();
    final nodes =
        await provider.listAll(parentId: folderId, limit: listingLimit);
    for (final node in nodes) {
      if (node.isFolder && node.name == syncBlobFolderName) {
        return _blobFolderId = node.id;
      }
    }
    if (!create) {
      return null;
    }
    final created =
        await provider.createFolder(syncBlobFolderName, parentId: folderId);
    return _blobFolderId = created.id;
  }

  @override
  Future<List<RemoteSyncFile>> list({bool blobs = false}) async {
    final provider = await _resolve();
    final parent = blobs ? await _blobFolder(create: false) : folderId;
    if (parent == null) {
      return const [];
    }
    final nodes = await provider.listAll(parentId: parent, limit: listingLimit);
    return [
      for (final node in nodes)
        if (!node.isFolder && node.name.startsWith(syncFilePrefix))
          RemoteSyncFile(
            name: node.name,
            id: node.id,
            bytes: node.byteSize ?? 0,
            modifiedAt: node.modifiedAt ?? node.createdAt,
          ),
    ];
  }

  @override
  Future<RemoteSyncFile> upload(
    String name,
    File file, {
    bool blob = false,
    FileTransferProgress? onProgress,
  }) async {
    final provider = await _resolve();
    final parent = blob ? (await _blobFolder(create: true))! : folderId;
    final node = await _files.upload(
      provider: provider,
      file: file,
      name: name,
      folderId: parent,
      mimeType: name.endsWith(syncInfoExtension)
          ? 'application/json'
          : 'application/octet-stream',
      onProgress: onProgress,
    );
    return RemoteSyncFile(
      name: name,
      id: node.id,
      bytes: file.lengthSync(),
      modifiedAt: DateTime.now(),
    );
  }

  @override
  Future<void> download(
    RemoteSyncFile file,
    File destination, {
    FileTransferProgress? onProgress,
  }) async {
    final provider = await _resolve();
    await _files.download(
      provider: provider,
      id: file.id,
      destination: destination,
      expectedBytes: file.bytes,
      onProgress: onProgress,
    );
  }

  @override
  Future<String> readText(RemoteSyncFile file) async {
    final bytes = await _files.readBytes(
      provider: await _resolve(),
      id: file.id,
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> delete(RemoteSyncFile file) async {
    final provider = await _resolve();
    await provider.delete(
      ProviderNode(id: file.id, name: file.name, kind: ProviderNodeKind.other),
    );
  }

  @override
  void dispose() {
    _provider?.dispose();
    _provider = null;
    _transfer?.close();
    _transfer = null;
  }
}
