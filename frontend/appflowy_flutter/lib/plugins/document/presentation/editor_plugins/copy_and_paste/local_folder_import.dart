import 'dart:io';

import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

/// How much of a folder is copied into AppFlowy in one go. A pasted path can
/// name a whole drive; these keep that from becoming an afternoon's copy.
@immutable
class LocalFolderLimits {
  const LocalFolderLimits({
    this.maximumFiles = 2000,
    this.maximumBytes = 2 * 1024 * 1024 * 1024,
    this.maximumDepth = 16,
  });

  final int maximumFiles;
  final int maximumBytes;

  /// Folders within folders, counting the copied folder's own children as 1.
  final int maximumDepth;
}

/// The limit a folder goes past.
enum LocalFolderLimit { files, bytes, depth }

/// What copying a folder would take, counted before anything is written.
@immutable
class LocalFolderSurvey {
  const LocalFolderSurvey({
    required this.files,
    required this.folders,
    required this.bytes,
    this.exceeded,
  });

  final int files;
  final int folders;
  final int bytes;

  /// The limit the folder went past; counting stops there.
  final LocalFolderLimit? exceeded;

  bool get fits => exceeded == null;
}

/// Names never worth copying: version-control internals, package caches and
/// the litter operating systems leave in folders.
const localFolderSkippedNames = {
  '.git',
  '.hg',
  '.svn',
  'node_modules',
  '__pycache__',
  '.dart_tool',
  '.ds_store',
  'thumbs.db',
  'desktop.ini',
  '__macosx',
  r'$recycle.bin',
  'system volume information',
};

bool skipsLocalFolderEntry(String name) =>
    localFolderSkippedNames.contains(name.toLowerCase());

/// Counts what copying [root] would take, stopping at the first limit it
/// goes past. Unreadable folders are passed over; the copy reports them.
Future<LocalFolderSurvey> surveyLocalFolder(
  Directory root, {
  LocalFolderLimits limits = const LocalFolderLimits(),
}) async {
  var files = 0, folders = 0, bytes = 0;
  LocalFolderSurvey survey([LocalFolderLimit? exceeded]) => LocalFolderSurvey(
        files: files,
        folders: folders,
        bytes: bytes,
        exceeded: exceeded,
      );

  final pending = <(Directory, int)>[(root, 0)];
  while (pending.isNotEmpty) {
    final (directory, depth) = pending.removeLast();
    final (List<Directory>, List<File>) entries;
    try {
      entries = await _listCopyable(directory);
    } on FileSystemException {
      continue;
    }
    for (final folder in entries.$1) {
      if (depth + 1 > limits.maximumDepth) {
        return survey(LocalFolderLimit.depth);
      }
      folders++;
      pending.add((folder, depth + 1));
    }
    for (final file in entries.$2) {
      files++;
      if (files > limits.maximumFiles) {
        return survey(LocalFolderLimit.files);
      }
      try {
        bytes += await file.length();
      } on FileSystemException {
        // Still counted: the copy will say it could not be read.
      }
      if (bytes > limits.maximumBytes) {
        return survey(LocalFolderLimit.bytes);
      }
    }
  }
  return survey();
}

/// Where a copied folder is written: the workspace, or a fake in tests.
abstract interface class LocalFolderDestination {
  /// The new folder's id, or null when it could not be made.
  Future<String?> createFolder({
    required String parentId,
    required String name,
  });

  /// Whether [file] was stored in the folder [parentId].
  Future<bool> importFile({required String parentId, required File file});

  /// Takes back a folder made for a copy that was then abandoned.
  Future<void> remove(String id);
}

/// Copies into workspace folders and workspace files: the same items the
/// sidebar's own "Add file" makes, with each file kept in AppFlowy storage.
class WorkspaceLocalFolderDestination implements LocalFolderDestination {
  const WorkspaceLocalFolderDestination({
    this.userProfile,
    this.service = const WorkspaceItemService(),
  });

  /// Saves asking the backend who is signed in once per file.
  final UserProfilePB? userProfile;
  final WorkspaceItemService service;

  @override
  Future<String?> createFolder({
    required String parentId,
    required String name,
  }) async {
    final result = await service.createFolder(
      parentViewId: parentId,
      name: name,
    );
    return result.fold((view) => view.id, (_) => null);
  }

  @override
  Future<bool> importFile({
    required String parentId,
    required File file,
  }) async {
    final name = p.basename(file.path);
    final result = await service.importBinaryFile(
      parentViewId: parentId,
      file: XFile(file.path, name: name, mimeType: lookupMimeType(name)),
      userProfile: userProfile,
    );
    return result.isSuccess;
  }

  @override
  Future<void> remove(String id) => service.delete([id]);
}

/// What a folder copy managed.
@immutable
class LocalFolderCopyReport {
  const LocalFolderCopyReport({required this.copied, required this.failed});

  /// Files stored.
  final int copied;

  /// Files and folders that could not be read or stored.
  final int failed;
}

/// Copies what [source] holds into the workspace folder [folderId], folders
/// before files and each in name order, so the copy reads the way the folder
/// did. One file that cannot be read does not stop the rest.
Future<LocalFolderCopyReport> copyLocalFolderContents({
  required Directory source,
  required String folderId,
  required LocalFolderDestination destination,
  LocalFolderLimits limits = const LocalFolderLimits(),
}) async {
  var copied = 0, failed = 0;

  Future<void> copy(Directory directory, String parentId, int depth) async {
    final (List<Directory>, List<File>) entries;
    try {
      entries = await _listCopyable(directory);
    } on FileSystemException {
      failed++;
      return;
    }
    for (final folder in entries.$1) {
      if (depth + 1 > limits.maximumDepth) {
        failed++;
        continue;
      }
      String? id;
      try {
        id = await destination.createFolder(
          parentId: parentId,
          name: p.basename(folder.path),
        );
      } catch (_) {
        id = null;
      }
      if (id == null) {
        failed++;
        continue;
      }
      await copy(folder, id, depth + 1);
    }
    for (final file in entries.$2) {
      // The folder may have grown since it was measured.
      if (copied >= limits.maximumFiles) {
        failed++;
        continue;
      }
      var stored = false;
      try {
        stored = await destination.importFile(parentId: parentId, file: file);
      } catch (_) {
        stored = false;
      }
      if (stored) {
        copied++;
      } else {
        failed++;
      }
    }
  }

  await copy(source, folderId, 0);
  return LocalFolderCopyReport(copied: copied, failed: failed);
}

/// The entries of [directory] worth copying: folders and files, each in name
/// order, the way a file manager lists them. Links are left out — following
/// one can lead out of the folder, or round in a circle.
Future<(List<Directory>, List<File>)> _listCopyable(
  Directory directory,
) async {
  final folders = <Directory>[];
  final files = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (skipsLocalFolderEntry(p.basename(entity.path))) {
      continue;
    }
    if (entity is Directory) {
      folders.add(entity);
    } else if (entity is File) {
      files.add(entity);
    }
  }
  int byName(FileSystemEntity a, FileSystemEntity b) => p
      .basename(a.path)
      .toLowerCase()
      .compareTo(p.basename(b.path).toLowerCase());
  folders.sort(byName);
  files.sort(byName);
  return (folders, files);
}
