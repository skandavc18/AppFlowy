// The Rust side of sync and restore, seen from Dart.
//
// Everything that touches the workspace's collabs — exporting what changed,
// merging what arrived, replacing a workspace at the next start — happens in
// the backend. This is the narrow door to it, kept behind an interface so the
// engine that drives it can be tested without a backend at all.

import 'dart:convert';
import 'dart:io';

import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/foundation.dart';

/// What an export wrote.
@immutable
class WorkspaceBundleExport {
  const WorkspaceBundleExport({
    required this.wrote,
    required this.objectCount,
    required this.uid,
    required this.workspaceId,
    required this.workspaceName,
    required this.isLocalWorkspace,
  });

  /// False when there was nothing to write.
  final bool wrote;
  final int objectCount;
  final int uid;
  final String workspaceId;
  final String workspaceName;
  final bool isLocalWorkspace;
}

/// What an import merged.
@immutable
class WorkspaceBundleImport {
  const WorkspaceBundleImport({
    this.objects = 0,
    this.live = 0,
    this.created = 0,
    this.merged = 0,
    this.unchanged = 0,
  });

  final int objects;

  /// Merged into a page or table that was open.
  final int live;
  final int created;
  final int merged;
  final int unchanged;
}

/// How the last restore went.
@immutable
class WorkspaceRestoreOutcome {
  const WorkspaceRestoreOutcome({
    required this.succeeded,
    required this.workspaceId,
    required this.workspaceName,
    required this.objectCount,
    this.detail = '',
  });

  final bool succeeded;
  final String workspaceId;
  final String workspaceName;
  final int objectCount;
  final String detail;
}

/// Raised when the backend refused.
class WorkspaceBundleError implements Exception {
  const WorkspaceBundleError(this.detail);

  final String detail;

  @override
  String toString() => detail;
}

abstract class WorkspaceBundleBridge {
  /// Writes every collab of the workspace to [path]. With [syncStatePath], the
  /// sync state there is reset to say all of it has been shared.
  Future<WorkspaceBundleExport> exportSnapshot({
    required String path,
    String syncStatePath = '',
  });

  /// Writes the collabs that changed since the last export to [path]. The state
  /// reflecting it waits beside [syncStatePath] as `.next` until committed.
  Future<WorkspaceBundleExport> exportChanges({
    required String path,
    required String syncStatePath,
  });

  /// Merges the bundle at [path] into the open workspace.
  Future<WorkspaceBundleImport> importChanges({
    required String path,
    String syncStatePath = '',
  });

  /// Sets the snapshot at [path] aside to replace its workspace at the next
  /// start.
  Future<void> scheduleRestore({
    required String path,
    String syncStatePath = '',
  });

  /// How the last restore went, once; null when nothing was restored.
  Future<WorkspaceRestoreOutcome?> takeRestoreOutcome();
}

class RustWorkspaceBundleBridge implements WorkspaceBundleBridge {
  const RustWorkspaceBundleBridge();

  @override
  Future<WorkspaceBundleExport> exportSnapshot({
    required String path,
    String syncStatePath = '',
  }) async {
    final result = await UserEventExportWorkspaceSnapshot(
      ExportWorkspaceSnapshotPB(path: path, syncStatePath: syncStatePath),
    ).send();
    return _export(
      result.fold((value) => value, (error) => throw _fail(error)),
    );
  }

  @override
  Future<WorkspaceBundleExport> exportChanges({
    required String path,
    required String syncStatePath,
  }) async {
    final result = await UserEventExportWorkspaceChanges(
      ExportWorkspaceChangesPB(path: path, syncStatePath: syncStatePath),
    ).send();
    return _export(
      result.fold((value) => value, (error) => throw _fail(error)),
    );
  }

  @override
  Future<WorkspaceBundleImport> importChanges({
    required String path,
    String syncStatePath = '',
  }) async {
    final result = await UserEventImportWorkspaceChanges(
      ImportWorkspaceChangesPB(path: path, syncStatePath: syncStatePath),
    ).send();
    final value = result.fold((value) => value, (error) => throw _fail(error));
    return WorkspaceBundleImport(
      objects: value.objects.toInt(),
      live: value.live.toInt(),
      created: value.created.toInt(),
      merged: value.merged.toInt(),
      unchanged: value.unchanged.toInt(),
    );
  }

  @override
  Future<void> scheduleRestore({
    required String path,
    String syncStatePath = '',
  }) async {
    final result = await UserEventScheduleWorkspaceRestore(
      ScheduleWorkspaceRestorePB(
        snapshotPath: path,
        syncStatePath: syncStatePath,
      ),
    ).send();
    result.fold((_) {}, (error) => throw _fail(error));
  }

  @override
  Future<WorkspaceRestoreOutcome?> takeRestoreOutcome() async {
    final result = await UserEventTakeWorkspaceRestoreOutcome().send();
    final value = result.fold((value) => value, (_) => null);
    if (value == null || !value.happened) {
      return null;
    }
    return WorkspaceRestoreOutcome(
      succeeded: value.succeeded,
      workspaceId: value.workspaceId,
      workspaceName: value.workspaceName,
      objectCount: value.objectCount.toInt(),
      detail: value.detail,
    );
  }

  static WorkspaceBundleExport _export(WorkspaceBundlePB value) =>
      WorkspaceBundleExport(
        wrote: value.wrote,
        objectCount: value.objectCount.toInt(),
        uid: value.uid.toInt(),
        workspaceId: value.workspaceId,
        workspaceName: value.workspaceName,
        isLocalWorkspace: value.isLocalWorkspace,
      );

  static WorkspaceBundleError _fail(FlowyError error) => WorkspaceBundleError(
        error.msg.isNotEmpty ? error.msg : error.code.toString(),
      );
}

/// Who a workspace bundle belongs to, read from its header.
@immutable
class WorkspaceBundleHeader {
  const WorkspaceBundleHeader({
    required this.isSnapshot,
    required this.uid,
    required this.workspaceId,
    required this.workspaceName,
    required this.createdAt,
  });

  final bool isSnapshot;
  final int uid;
  final String workspaceId;
  final String workspaceName;
  final DateTime createdAt;
}

/// The bytes every workspace bundle starts with, as the backend writes them.
const String workspaceBundleMagic = 'AFWSYNC1';

/// Reads the header of the workspace bundle at [file], or returns null when
/// the file is not one.
Future<WorkspaceBundleHeader?> readWorkspaceBundleHeader(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open();
    final start = await handle.read(12);
    if (start.length < 12 ||
        ascii.decode(start.sublist(0, 8), allowInvalid: true) !=
            workspaceBundleMagic) {
      return null;
    }
    final length =
        ByteData.sublistView(start, 8, 12).getUint32(0, Endian.little);
    if (length > 1 << 20) {
      return null;
    }
    final decoded = jsonDecode(utf8.decode(await handle.read(length)));
    if (decoded is! Map) {
      return null;
    }
    final workspaceId = decoded['workspace_id'];
    if (workspaceId is! String || workspaceId.isEmpty) {
      return null;
    }
    return WorkspaceBundleHeader(
      isSnapshot: decoded['kind'] == 'snapshot',
      uid: decoded['uid'] is int ? decoded['uid']! as int : 0,
      workspaceId: workspaceId,
      workspaceName: decoded['workspace_name'] is String
          ? decoded['workspace_name']! as String
          : '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        decoded['created_at'] is int ? decoded['created_at']! as int : 0,
        isUtc: true,
      ),
    );
  } on Object {
    return null;
  } finally {
    await handle?.close();
  }
}
