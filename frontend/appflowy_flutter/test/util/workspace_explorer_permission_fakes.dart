import 'dart:async';

import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

ViewPB permissionFolder(String id, String parent, String name) => ViewPB(
      id: id,
      parentViewId: parent,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

ViewPB permissionFile(String id, String parent, String name) => ViewPB(
      id: id,
      parentViewId: parent,
      name: name,
      layout: ViewLayoutPB.Document,
      // No document, local file, network image, or native preview is loaded.
      extra: const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
      ).mergeIntoExtra(''),
    );

/// Deliberately in-memory: writes record dispatches, never touch a workspace,
/// preferences file, native backend, service account, or test-data directory.
class ExplorerPermissionRepository implements WorkspaceItemRepository {
  ExplorerPermissionRepository() {
    for (final view in [root, folder, first, second, nested]) {
      views[view.id] = ViewPB.fromBuffer(view.writeToBuffer());
    }
  }

  final root = permissionFolder('root', '', 'Permission folder');
  final folder = permissionFolder('folder', 'root', 'Child folder');
  final first = permissionFile('first', 'root', 'First.bin');
  final second = permissionFile('second', 'root', 'Second.bin');
  final nested = permissionFile('nested', 'folder', 'Nested.bin');
  final views = <String, ViewPB>{};
  final writes = <String>[];
  final ancestorRequests = <String>[];
  int serial = 0;
  FlowyError? failure;
  Completer<List<ViewPB>>? nextAncestors;
  Future<void> Function(String operation)? beforeWriteReply;

  Future<void> _record(String operation) async {
    writes.add(operation);
    await beforeWriteReply?.call(operation);
  }

  Future<FlowyResult<ViewPB, FlowyError>> _save(
    String operation,
    ViewPB next,
  ) async {
    await _record(operation);
    final error = failure;
    if (error != null) return FlowyResult.failure(error);
    views[next.id] = ViewPB.fromBuffer(next.writeToBuffer());
    return FlowyResult.success(next);
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) async =>
      FlowyResult.success([
        for (final view in views.values)
          if (view.parentViewId == id) ViewPB.fromBuffer(view.writeToBuffer()),
      ]);

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async =>
      FlowyResult.success(views.values.toList(growable: false));

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String id) async =>
      FlowyResult.success(ViewPB.fromBuffer(views[id]!.writeToBuffer()));

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAncestors(String id) async {
    ancestorRequests.add(id);
    final pending = nextAncestors;
    nextAncestors = null;
    if (pending != null) return FlowyResult.success(await pending.future);
    final ancestors = <ViewPB>[];
    var current = views[id];
    while (current != null) {
      ancestors.insert(0, current);
      current = views[current.parentViewId];
    }
    return FlowyResult.success(ancestors);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> createFolder({
    required String parentViewId,
    required String name,
    ViewSectionPB? section,
  }) =>
      _save(
        'createFolder:$parentViewId',
        permissionFolder('created-${++serial}', parentViewId, name),
      );

  @override
  Future<FlowyResult<ViewPB, FlowyError>> createTextFile({
    required String parentViewId,
    required String name,
    String content = '',
    ViewSectionPB? section,
  }) =>
      _save(
        'createTextFile:$parentViewId',
        permissionFile('created-${++serial}', parentViewId, name),
      );

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) =>
      _save(
        'rename:$viewId',
        ViewPB.fromBuffer(views[viewId]!.writeToBuffer())..name = name,
      );

  @override
  Future<FlowyResult<ViewPB, FlowyError>> duplicate({
    required ViewPB view,
    required String parentViewId,
  }) =>
      _save(
        'duplicate:${view.id}:$parentViewId',
        ViewPB.fromBuffer(view.writeToBuffer())
          ..id = 'duplicate-${++serial}'
          ..parentViewId = parentViewId,
      );

  @override
  Future<FlowyResult<void, FlowyError>> move({
    required String viewId,
    required String parentViewId,
    String? previousViewId,
  }) async {
    await _record('move:$viewId:$parentViewId');
    final error = failure;
    if (error != null) return FlowyResult.failure(error);
    views[viewId] = ViewPB.fromBuffer(views[viewId]!.writeToBuffer())
      ..parentViewId = parentViewId;
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<void, FlowyError>> delete(List<String> ids) async {
    await _record('delete:${ids.join(',')}');
    final error = failure;
    if (error != null) return FlowyResult.failure(error);
    for (final id in ids) {
      views.remove(id);
    }
    return FlowyResult.success(null);
  }
}
