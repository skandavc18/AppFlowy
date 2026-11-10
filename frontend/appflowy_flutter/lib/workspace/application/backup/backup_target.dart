// Where a copy is put, and how it gets there.
//
// Every destination answers the same four questions — what is already there,
// put this, fetch that, forget that one — so nothing above this line knows
// whether a backup went to a folder on a desk, to Google Drive or to AppFlowy
// Cloud. Adding another service is one more implementation and one more entry
// in [BackupDestinationKind].

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/shared/appflowy_cloud_auth.dart';
import 'package:appflowy/workspace/application/backup/backup_manifest.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/backup/provider_file_transfer.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// One copy that exists somewhere.
@immutable
class BackupCopy {
  const BackupCopy({
    required this.id,
    required this.locator,
    this.manifestLocator = '',
    this.bytes = 0,
    this.storedAt,
    this.manifest,
  });

  /// The backup's own name, shared by the archive and its manifest.
  final String id;

  /// How the destination finds the archive again: a path, a service id, a url.
  final String locator;

  final String manifestLocator;
  final int bytes;
  final DateTime? storedAt;

  /// What was written beside it, once it has been read.
  final BackupManifest? manifest;

  bool get isSealed => manifest?.encrypted ?? false;

  DateTime get takenAt => manifest?.createdAt ?? storedAt ?? DateTime.now();

  BackupCopy withManifest(BackupManifest? manifest) => BackupCopy(
        id: id,
        locator: locator,
        manifestLocator: manifestLocator,
        bytes: bytes,
        storedAt: storedAt,
        manifest: manifest ?? this.manifest,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'locator': locator,
        if (manifestLocator.isNotEmpty) 'manifest_locator': manifestLocator,
        'bytes': bytes,
        if (storedAt != null) 'stored_at': storedAt!.millisecondsSinceEpoch,
        if (manifest != null) 'manifest': manifest!.toJson(),
      };

  static BackupCopy? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final values = Map<String, Object?>.from(value);
    final id = values['id'];
    final locator = values['locator'];
    if (id is! String || id.isEmpty || locator is! String) {
      return null;
    }
    final storedAt = values['stored_at'];
    final manifest = values['manifest'];
    return BackupCopy(
      id: id,
      locator: locator,
      manifestLocator: values['manifest_locator'] is String
          ? values['manifest_locator']! as String
          : '',
      bytes: values['bytes'] is int ? values['bytes']! as int : 0,
      storedAt: storedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(storedAt)
          : null,
      manifest: manifest is Map
          ? BackupManifest.fromJson(Map<String, Object?>.from(manifest))
          : null,
    );
  }
}

/// How far along a transfer is.
typedef BackupTransferProgress = void Function(int done, int total);

/// Somewhere copies are kept.
abstract class BackupTarget {
  BackupDestinationKind get kind;

  /// What the destination is called, for the interface to name it.
  String get label;

  /// Proves the destination can be reached and written to.
  Future<void> ensureReady();

  /// The copies already there, newest first.
  Future<List<BackupCopy>> list();

  /// Puts [archive] there, with [manifest] beside it.
  Future<BackupCopy> put({
    required File archive,
    required BackupManifest manifest,
    BackupTransferProgress? onProgress,
  });

  /// Brings one copy back to [destination].
  Future<void> fetch(
    BackupCopy copy,
    File destination, {
    BackupTransferProgress? onProgress,
  });

  Future<void> remove(BackupCopy copy);

  void dispose() {}
}

/// A folder on this computer, or on a disk plugged into it.
///
/// The simplest destination and the only one that keeps working with nothing
/// switched on, which is why it is offered first.
class LocalFolderBackupTarget extends BackupTarget {
  LocalFolderBackupTarget(this.folder);

  final Directory folder;

  @override
  BackupDestinationKind get kind => BackupDestinationKind.folder;

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
  Future<List<BackupCopy>> list() async {
    if (!folder.existsSync()) {
      return const [];
    }
    final copies = <BackupCopy>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith(backupArchiveExtension)) {
        continue;
      }
      final id = p.basename(entity.path).replaceAll(backupArchiveExtension, '');
      final manifestFile =
          File(p.join(folder.path, '$id$backupManifestExtension'));
      copies.add(
        BackupCopy(
          id: id,
          locator: entity.path,
          manifestLocator: manifestFile.existsSync() ? manifestFile.path : '',
          bytes: entity.lengthSync(),
          storedAt: entity.lastModifiedSync(),
          manifest: manifestFile.existsSync()
              ? BackupManifest.tryParse(await manifestFile.readAsString())
              : null,
        ),
      );
    }
    copies.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return copies;
  }

  @override
  Future<BackupCopy> put({
    required File archive,
    required BackupManifest manifest,
    BackupTransferProgress? onProgress,
  }) async {
    await ensureReady();
    final target = File(p.join(folder.path, manifest.archiveFileName));
    final manifestFile = File(p.join(folder.path, manifest.manifestFileName));

    // Staged then renamed, so an interrupted copy never leaves a half file
    // that later reads as a corrupt backup.
    final staging = File('${target.path}.part');
    await archive.copy(staging.path);
    if (target.existsSync()) {
      await target.delete();
    }
    await staging.rename(target.path);
    await manifestFile.writeAsString(manifest.encode());
    onProgress?.call(manifest.storedBytes, manifest.storedBytes);

    return BackupCopy(
      id: manifest.id,
      locator: target.path,
      manifestLocator: manifestFile.path,
      bytes: target.lengthSync(),
      storedAt: DateTime.now(),
      manifest: manifest,
    );
  }

  @override
  Future<void> fetch(
    BackupCopy copy,
    File destination, {
    BackupTransferProgress? onProgress,
  }) async {
    final source = File(copy.locator);
    if (!source.existsSync()) {
      throw const BackupTargetError('That copy is no longer in the folder.');
    }
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    final length = destination.lengthSync();
    onProgress?.call(length, length);
  }

  @override
  Future<void> remove(BackupCopy copy) async {
    await _deleteQuietly(File(copy.locator));
    if (copy.manifestLocator.isNotEmpty) {
      await _deleteQuietly(File(copy.manifestLocator));
    }
  }
}

/// Google Drive, OneDrive or Box, through the account already signed in.
///
/// Listing, deleting and downloading go through the provider the rest of the
/// application uses. Uploading goes through [ProviderFileTransfer], because a
/// backup is far larger than the one-request upload a file embed needs and
/// every one of these services has its own way of taking a big file in pieces.
class ProviderBackupTarget extends BackupTarget {
  ProviderBackupTarget({
    required this.kind,
    required this.connection,
    required this.folderId,
    required this.folderName,
  });

  @override
  final BackupDestinationKind kind;

  final ProviderConnection connection;
  final String folderId;
  final String folderName;

  CollectionProvider? _provider;
  ProviderFileTransfer? _transfer;

  @override
  String get label => folderName.isEmpty
      ? connection.accountLabel
      : '$folderName · ${connection.accountLabel}';

  CollectionSource get _source => CollectionSource(
        service: kind.providerService!,
        connectionId: connection.id,
        remoteId: folderId,
        remoteName: folderName,
      );

  ProviderFileTransfer get _files => _transfer ??= ProviderFileTransfer(
        service: kind.providerService!,
        connection: connection,
      );

  Future<CollectionProvider> _resolve() async {
    final existing = _provider;
    if (existing != null) {
      return existing;
    }
    await ProviderConnections.instance.ensureLoaded();
    final provider = ProviderRegistry.create(_source);
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

  @override
  Future<List<BackupCopy>> list() async {
    final provider = await _resolve();
    final nodes = await provider.listAll(parentId: folderId, limit: 500);

    final archives = <String, ProviderNode>{};
    final manifests = <String, ProviderNode>{};
    for (final node in nodes) {
      if (node.name.endsWith(backupManifestExtension)) {
        manifests[node.name.replaceAll(backupManifestExtension, '')] = node;
      } else if (node.name.endsWith(backupArchiveExtension)) {
        archives[node.name.replaceAll(backupArchiveExtension, '')] = node;
      }
    }

    final copies = <BackupCopy>[];
    for (final entry in archives.entries) {
      final manifestNode = manifests[entry.key];
      BackupManifest? manifest;
      if (manifestNode != null) {
        try {
          final bytes = await provider.readBytes(
            manifestNode,
            maxBytes: 1 << 20,
          );
          manifest = BackupManifest.tryParse(
            utf8.decode(bytes, allowMalformed: true),
          );
        } on Object catch (error) {
          Log.warn('A backup manifest could not be read: $error');
        }
      }
      copies.add(
        BackupCopy(
          id: entry.key,
          locator: entry.value.id,
          manifestLocator: manifestNode?.id ?? '',
          bytes: entry.value.byteSize ?? 0,
          storedAt: entry.value.modifiedAt ?? entry.value.createdAt,
          manifest: manifest,
        ),
      );
    }
    copies.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return copies;
  }

  @override
  Future<BackupCopy> put({
    required File archive,
    required BackupManifest manifest,
    BackupTransferProgress? onProgress,
  }) async {
    final provider = await _resolve();
    final total = archive.lengthSync();

    final uploaded = await _files.upload(
      provider: provider,
      file: archive,
      name: manifest.archiveFileName,
      folderId: folderId,
      onProgress: onProgress,
    );

    final manifestNode = await provider.upload(
      manifest.manifestFileName,
      Uint8List.fromList(utf8.encode(manifest.encode())),
      parentId: folderId,
      mimeType: 'application/json',
    );

    return BackupCopy(
      id: manifest.id,
      locator: uploaded.id,
      manifestLocator: manifestNode.id,
      bytes: total,
      storedAt: DateTime.now(),
      manifest: manifest,
    );
  }

  @override
  Future<void> fetch(
    BackupCopy copy,
    File destination, {
    BackupTransferProgress? onProgress,
  }) async {
    final provider = await _resolve();
    await _files.download(
      provider: provider,
      id: copy.locator,
      destination: destination,
      expectedBytes: copy.bytes,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> remove(BackupCopy copy) async {
    final provider = await _resolve();
    for (final id in [copy.locator, copy.manifestLocator]) {
      if (id.isEmpty) {
        continue;
      }
      try {
        await provider.delete(
          ProviderNode(id: id, name: '', kind: ProviderNodeKind.other),
        );
      } on Object catch (error) {
        Log.warn('An old backup could not be removed: $error');
      }
    }
  }

  @override
  void dispose() {
    _provider?.dispose();
    _provider = null;
    _transfer?.close();
    _transfer = null;
  }
}

/// AppFlowy Cloud's own storage.
///
/// ⚠️ It has no way to ask what is in a folder, so the list of copies cannot
/// come from a listing. Instead the list is kept as an object of its own at a
/// FIXED address — `…/blob/appflowy-backup-index` — which any machine signed in
/// to the same workspace can read with nothing remembered locally. The copies
/// this computer knows about are merged in on top, so a copy taken while the
/// index could not be written is never lost from view.
class AppFlowyCloudBackupTarget extends BackupTarget {
  AppFlowyCloudBackupTarget({
    required this.userProfile,
    required this.knownCopies,
  });

  final UserProfilePB? userProfile;

  /// What this computer remembers sending.
  final List<BackupCopy> knownCopies;

  /// The parent the storage service files backups under.
  static const String parentDirectory = 'appflowy-backups';

  /// The name the index is stored under.
  ///
  /// ⚠️ This uses the older `/blob/{file_id}` route on purpose. The newer
  /// `/v1/blob/{parent_dir}` route names an object by the hash of its contents,
  /// which is right for an archive and useless for an index — a list that
  /// changes would move every time it was written, and nothing could find it.
  /// The older route stores under the name the caller chooses, which is exactly
  /// what a fixed address needs.
  static const String indexObjectName = 'appflowy-backup-index';

  static const int indexVersion = 1;

  /// A cap, so a workspace backed up hourly for a year still has an index that
  /// is read in one go.
  static const int maximumIndexEntries = 200;

  @override
  BackupDestinationKind get kind => BackupDestinationKind.appflowyCloud;

  @override
  String get label => 'AppFlowy Cloud';

  @override
  Future<void> ensureReady() async {
    if (userProfile?.workspaceType != WorkspaceTypePB.ServerW) {
      throw const BackupTargetError(
        'This workspace is not signed in to AppFlowy Cloud.',
      );
    }
  }

  @override
  Future<List<BackupCopy>> list() async =>
      mergeBackupCopies(await readPublishedIndex(), knownCopies);

  /// The list of copies stored beside them, or empty when there is not one yet.
  ///
  /// Never throws: a workspace that has never been backed up, an older server
  /// that no longer serves this route, and a genuine network failure all mean
  /// the same thing here — fall back to what this computer remembers.
  Future<List<BackupCopy>> readPublishedIndex() async {
    final client = http.Client();
    try {
      final uri = await _indexUri();
      if (uri == null) {
        return const [];
      }
      final response = await client.get(
        uri,
        headers: appFlowyCloudAuthHeaders(userProfile),
      );
      if (response.statusCode != 200) {
        return const [];
      }
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) {
        return const [];
      }
      final version = decoded['version'];
      if (version is! int || version < 1 || version > indexVersion) {
        return const [];
      }
      final copies = decoded['copies'];
      if (copies is! List) {
        return const [];
      }
      return [
        for (final entry in copies)
          if (BackupCopy.fromJson(entry) != null) BackupCopy.fromJson(entry)!,
      ];
    } on Object catch (error) {
      Log.info('The backup index could not be read: $error');
      return const [];
    } finally {
      client.close();
    }
  }

  /// Writes the list of copies back beside them.
  ///
  /// Best effort by design: failing to publish the index is not failing to back
  /// up, and the copy that matters is already stored.
  Future<bool> publishIndex(List<BackupCopy> copies) async {
    final client = http.Client();
    try {
      final uri = await _indexUri();
      if (uri == null) {
        return false;
      }
      final body = utf8.encode(
        jsonEncode({
          'version': indexVersion,
          'copies': [
            for (final copy in copies.take(maximumIndexEntries)) copy.toJson(),
          ],
        }),
      );
      final response = await client.put(
        uri,
        headers: {
          ...appFlowyCloudAuthHeaders(userProfile),
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode >= 400) {
        Log.info(
          'The backup index was refused (${response.statusCode}); the list of '
          'copies is kept on this computer only.',
        );
        return false;
      }
      return true;
    } on Object catch (error) {
      Log.info('The backup index could not be written: $error');
      return false;
    } finally {
      client.close();
    }
  }

  Future<Uri?> _indexUri() async {
    final base = await getAppFlowyCloudUrl();
    if (base.isEmpty) {
      return null;
    }
    final workspaceId = await _workspaceId();
    if (workspaceId == null || workspaceId.isEmpty) {
      return null;
    }
    return Uri.parse(
      '${base.replaceAll(RegExp(r'/+$'), '')}'
      '/api/file_storage/$workspaceId/blob/$indexObjectName',
    );
  }

  Future<String?> _workspaceId() async {
    final workspace = await FolderEventReadCurrentWorkspace().send();
    return workspace.fold((value) => value.id, (_) => null);
  }

  @override
  Future<BackupCopy> put({
    required File archive,
    required BackupManifest manifest,
    BackupTransferProgress? onProgress,
  }) async {
    await ensureReady();
    final service = DocumentService();
    final total = archive.lengthSync();

    // The backend takes the file whole and does its own chunking, so there is
    // no progress to report until it comes back.
    final uploaded = await service.uploadFile(
      localFilePath: archive.path,
      documentId: parentDirectory,
    );

    final url = uploaded.fold<String?>(
      (file) => file.url,
      (error) => throw BackupTargetError(error.msg),
    );
    if (url == null || url.isEmpty) {
      throw const BackupTargetError('The copy was not accepted.');
    }
    onProgress?.call(total, total);

    // The manifest goes up beside it so a restore on another computer can be
    // pointed at the pair with nothing but the two links.
    final manifestFile = File(
      p.join(archive.parent.path, manifest.manifestFileName),
    );
    await manifestFile.writeAsString(manifest.encode());
    final manifestUpload = await service.uploadFile(
      localFilePath: manifestFile.path,
      documentId: parentDirectory,
    );
    final manifestUrl = manifestUpload.fold<String>(
      (file) => file.url,
      (_) => '',
    );

    final stored = BackupCopy(
      id: manifest.id,
      locator: url,
      manifestLocator: manifestUrl,
      bytes: total,
      storedAt: DateTime.now(),
      manifest: manifest,
    );

    try {
      await publishIndex(mergeBackupCopies([stored], await list()));
    } on Object catch (error) {
      // Failing to publish the list is not failing to back up; the copy that
      // matters is already stored and this computer still remembers it.
      Log.info('The backup index was not updated: $error');
    }
    return stored;
  }

  @override
  Future<void> fetch(
    BackupCopy copy,
    File destination, {
    BackupTransferProgress? onProgress,
  }) async {
    await destination.parent.create(recursive: true);
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(copy.locator))
        ..headers.addAll(appFlowyCloudAuthHeaders(userProfile));
      final response = await client.send(request);
      if (response.statusCode >= 400) {
        await response.stream.drain<void>();
        throw BackupTargetError(
          'AppFlowy Cloud refused the download (${response.statusCode}).',
        );
      }
      final sink = destination.openWrite();
      var received = 0;
      try {
        await for (final piece in response.stream) {
          sink.add(piece);
          received += piece.length;
          onProgress?.call(received, response.contentLength ?? copy.bytes);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<void> remove(BackupCopy copy) async {
    for (final url in [copy.locator, copy.manifestLocator]) {
      if (url.isEmpty) {
        continue;
      }
      final result =
          await DocumentEventDeleteFile(DeleteFilePB(url: url)).send();
      result.onFailure(
        (error) => Log.warn('An old backup could not be removed: ${error.msg}'),
      );
    }

    try {
      final remaining = [
        for (final existing in await list())
          if (existing.id != copy.id) existing,
      ];
      await publishIndex(remaining);
    } on Object catch (error) {
      Log.info('The backup index was not updated: $error');
    }
  }
}

/// Joins two lists of copies into one, newest first.
///
/// The same copy can be known from both the index stored beside the backups and
/// from what this computer remembers; the first mention of an id wins, so the
/// published index leads and anything only this computer saw is added after.
List<BackupCopy> mergeBackupCopies(
  List<BackupCopy> leading,
  List<BackupCopy> trailing,
) {
  final byId = <String, BackupCopy>{};
  for (final copy in [...leading, ...trailing]) {
    byId.putIfAbsent(copy.id, () => copy);
  }
  return byId.values.toList()..sort((a, b) => b.takenAt.compareTo(a.takenAt));
}

/// Raised when a destination cannot do what was asked of it.
class BackupTargetError implements Exception {
  const BackupTargetError(this.detail);

  final String detail;

  @override
  String toString() => 'BackupTargetError: $detail';
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (file.existsSync()) {
      await file.delete();
    }
  } on Object {
    // A copy that is already gone needs no reporting.
  }
}
