import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';

class WorkspaceItemTransferService {
  WorkspaceItemTransferService({
    WorkspaceItemRepository? repository,
    WorkspaceItemClipboard? clipboard,
  })  : _repository = repository ?? const WorkspaceItemService(),
        _clipboard = clipboard ?? WorkspaceItemClipboard.instance;

  final WorkspaceItemRepository _repository;
  final WorkspaceItemClipboard _clipboard;

  Future<FlowyResult<void, FlowyError>> moveTo({
    required Iterable<ViewPB> views,
    required String destinationId,
  }) async {
    final sources = views.toList(growable: false);
    final validation = await _validate(
      sources: sources,
      destinationId: destinationId,
      errorMessage: LocaleKeys.workspaceFolderExplorer_invalidFolderMove.tr(),
    );
    if (validation != null) {
      return FlowyResult.failure(validation);
    }

    String? previousViewId;
    for (final view in sources) {
      if (view.parentViewId == destinationId) {
        previousViewId = view.id;
        continue;
      }
      final result = await _repository.move(
        viewId: view.id,
        parentViewId: destinationId,
        previousViewId: previousViewId,
      );
      if (result.isFailure) {
        return result;
      }
      previousViewId = view.id;
    }
    return FlowyResult.success(null);
  }

  Future<FlowyResult<void, FlowyError>> copyTo({
    required Iterable<ViewPB> views,
    required String destinationId,
  }) async {
    final sources = views.toList(growable: false);
    final validation = await _validate(
      sources: sources,
      destinationId: destinationId,
      errorMessage: LocaleKeys.workspaceFolderExplorer_invalidFolderCopy.tr(),
    );
    if (validation != null) {
      return FlowyResult.failure(validation);
    }

    for (final view in sources) {
      final result = await _repository.duplicate(
        view: view,
        parentViewId: destinationId,
      );
      if (result.isFailure) {
        return result.fold(
          (_) => FlowyResult.success(null),
          FlowyResult.failure,
        );
      }
    }
    return FlowyResult.success(null);
  }

  Future<FlowyResult<void, FlowyError>> pasteTo({
    required String destinationId,
  }) async {
    final data = _clipboard.data;
    if (data == null || data.views.isEmpty) {
      return FlowyResult.failure(
        FlowyError(
          msg: LocaleKeys.workspaceFolderExplorer_nothingToPaste.tr(),
        ),
      );
    }

    final result = switch (data.operation) {
      WorkspaceItemClipboardOperation.copy => copyTo(
          views: data.views,
          destinationId: destinationId,
        ),
      WorkspaceItemClipboardOperation.cut => moveTo(
          views: data.views,
          destinationId: destinationId,
        ),
    };
    final transferred = await result;
    if (transferred.isSuccess &&
        data.operation == WorkspaceItemClipboardOperation.cut) {
      _clipboard.clear();
    }
    return transferred;
  }

  Future<FlowyError?> _validate({
    required List<ViewPB> sources,
    required String destinationId,
    required String errorMessage,
  }) async {
    if (sources.isEmpty || destinationId.isEmpty) {
      return FlowyError(msg: errorMessage);
    }

    final allViewsResult = await _repository.getAllViews();
    return allViewsResult.fold(
      (allViews) {
        final invalidIds = workspaceInvalidDestinationIds(
          sources: sources,
          allViews: allViews,
        );
        final sourceScopes = sources
            .map(
              (view) => workspaceTransferScopeId(
                view: view,
                allViews: allViews,
              ),
            )
            .toSet();
        final destination = {
          for (final view in allViews) view.id: view,
        }[destinationId];
        final destinationScope = destination == null
            ? null
            : workspaceTransferScopeId(
                view: destination,
                allViews: allViews,
              );
        return invalidIds.contains(destinationId) ||
                sourceScopes.length != 1 ||
                sourceScopes.single != destinationScope
            ? FlowyError(msg: errorMessage)
            : null;
      },
      (error) => error,
    );
  }
}

Set<String> workspaceInvalidDestinationIds({
  required Iterable<ViewPB> sources,
  required Iterable<ViewPB> allViews,
}) {
  final sourceIds = sources.map((view) => view.id).toSet();
  final viewsById = {
    for (final view in allViews) view.id: view,
  };
  final invalidIds = <String>{...sourceIds};

  for (final candidate in viewsById.values) {
    var current = candidate;
    final visited = <String>{};
    while (visited.add(current.id)) {
      if (sourceIds.contains(current.id)) {
        invalidIds.add(candidate.id);
        break;
      }
      final parent = viewsById[current.parentViewId];
      if (parent == null) {
        break;
      }
      current = parent;
    }
  }
  return invalidIds;
}

String? workspaceTransferScopeId({
  required ViewPB view,
  required Iterable<ViewPB> allViews,
}) {
  final viewsById = {
    for (final candidate in allViews) candidate.id: candidate,
  };
  var current = view;
  final visited = <String>{};
  while (visited.add(current.id)) {
    if (current.isSpace) {
      return current.id;
    }
    final parent = viewsById[current.parentViewId];
    if (parent == null) {
      return null;
    }
    current = parent;
  }
  return null;
}
