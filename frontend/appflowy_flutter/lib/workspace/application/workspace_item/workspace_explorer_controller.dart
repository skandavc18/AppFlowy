import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/trash/application/trash_listener.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_selection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/trash.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

class WorkspaceExplorerController extends ChangeNotifier {
  WorkspaceExplorerController({
    required ViewPB root,
    WorkspaceItemRepository? repository,
    WorkspaceItemClipboard? clipboard,
    this.listenForUpdates = true,
  })  : _rootId = root.id,
        _repository = repository ?? const WorkspaceItemService(),
        clipboard = clipboard ?? WorkspaceItemClipboard.instance {
    _cacheView(root);
    _breadcrumbs.add(root.id);
    selection.addListener(notifyListeners);
    this.clipboard.addListener(notifyListeners);
    if (listenForUpdates) {
      _trashListener = TrashListener()..start(trashUpdated: _handleTrashUpdate);
    }
  }

  final String _rootId;
  final WorkspaceItemRepository _repository;
  final WorkspaceItemClipboard clipboard;
  final bool listenForUpdates;
  final WorkspaceExplorerSelection selection = WorkspaceExplorerSelection();
  final Map<String, ViewPB> _views = {};
  final Map<String, List<String>> _children = {};
  final Set<String> _loadedFolders = {};
  final Set<String> _loadingFolders = {};
  final Map<String, int> _loadGenerations = {};
  final Set<String> _expandedFolders = {};
  final Map<String, ViewListener> _listeners = {};
  final List<String> _breadcrumbs = [];
  TrashListener? _trashListener;
  Set<String> _trashIds = {};

  List<WorkspaceExplorerRow> _rows = const [];
  List<WorkspaceExplorerRow>? _searchRows;
  List<ViewPB>? _searchIndex;
  WorkspaceExplorerDraft? _draft;
  String? _editingId;
  String _query = '';
  String? _errorMessage;
  bool _isSearching = false;
  bool _isDisposed = false;
  int _searchGeneration = 0;

  WorkspaceExplorerItem get root =>
      WorkspaceExplorerItem.fromView(_views[_rootId]!);
  WorkspaceExplorerItem get currentFolder =>
      WorkspaceExplorerItem.fromView(_views[_breadcrumbs.last]!);
  List<WorkspaceExplorerItem> get breadcrumbs => List.unmodifiable(
        _breadcrumbs.map((id) => WorkspaceExplorerItem.fromView(_views[id]!)),
      );
  List<WorkspaceExplorerRow> get rows => _searchRows ?? _rows;
  WorkspaceExplorerDraft? get draft => _draft;
  String? get editingId => _editingId;
  String get query => _query;
  String? get errorMessage => _errorMessage;
  bool get isSearching => _isSearching;
  bool get isLoading => _loadingFolders.contains(currentFolder.id);
  bool get canPaste => clipboard.hasData;
  String get selectedOrCurrentFolderId => _selectedFolderId ?? currentFolder.id;

  int get visibleFolderCount => rows.where((row) => row.item.isFolder).length;
  int get visibleFileCount => rows.where((row) => !row.item.isFolder).length;

  Future<void> initialize() async {
    await _loadChildren(_rootId);
  }

  Future<void> refresh() async {
    _errorMessage = null;
    _searchIndex = null;
    final folders = {
      currentFolder.id,
      ..._expandedFolders.where(_loadedFolders.contains),
    };
    for (final id in folders) {
      await _loadChildren(id, force: true);
    }
    if (_query.isNotEmpty) {
      await search(_query);
    }
  }

  Future<void> toggleFolder(String id) async {
    final item = _item(id);
    if (item == null || !item.isFolder) {
      return;
    }
    if (!_expandedFolders.remove(id)) {
      _expandedFolders.add(id);
      _refreshRows();
      await _loadChildren(id);
    } else {
      _refreshRows();
    }
  }

  Future<void> navigateTo(String id) async {
    final item = _item(id);
    if (item == null || !item.isFolder) {
      return;
    }
    _cancelSearch();
    _setBreadcrumbPath(id);
    selection.clear();
    _draft = null;
    _editingId = null;
    _refreshRows();
    await _loadChildren(id);
  }

  void selectRow(
    String id, {
    required bool toggle,
    required bool range,
  }) {
    if (!_isSelectableSearchResult(id)) {
      return;
    }
    final visibleIds = rows
        .map((row) => row.item.id)
        .where(_isSelectableSearchResult)
        .toList(growable: false);
    if (range) {
      selection.selectRange(id: id, visibleIds: visibleIds);
    } else if (toggle) {
      selection.toggle(id);
    } else {
      selection.selectOnly(id);
    }
  }

  void selectAll() {
    selection.selectAll(
      rows.map((row) => row.item.id).where(_isSelectableSearchResult),
    );
  }

  void moveSelection(int delta) {
    final selectableRows =
        rows.where((row) => _isSelectableSearchResult(row.item.id)).toList();
    if (selectableRows.isEmpty) {
      return;
    }
    final selected = selection.anchorId;
    final currentIndex = selected == null
        ? -1
        : selectableRows.indexWhere((row) => row.item.id == selected);
    final nextIndex =
        (currentIndex + delta).clamp(0, selectableRows.length - 1);
    selection.selectOnly(selectableRows[nextIndex].item.id);
  }

  Future<void> expandSelection() async {
    final selected = selection.anchorId;
    if (selected == null) {
      return;
    }
    final item = _item(selected);
    if (item?.isFolder ?? false) {
      if (!_expandedFolders.contains(selected)) {
        await toggleFolder(selected);
      } else {
        final childIds = _children[selected];
        if (childIds?.isNotEmpty ?? false) {
          selection.selectOnly(childIds!.first);
        }
      }
    }
  }

  void collapseSelection() {
    final selected = selection.anchorId;
    if (selected == null) {
      return;
    }
    if (_expandedFolders.remove(selected)) {
      _refreshRows();
      return;
    }
    final parentId = _views[selected]?.parentViewId;
    if (parentId != null && rows.any((row) => row.item.id == parentId)) {
      selection.selectOnly(parentId);
    }
  }

  void beginCreate(
    WorkspaceExplorerDraftKind kind, {
    String? parentId,
    String? suggestedName,
  }) {
    final resolvedParent = parentId ?? _selectedFolderId ?? currentFolder.id;
    if (resolvedParent != currentFolder.id) {
      _expandedFolders.add(resolvedParent);
      unawaited(_loadChildren(resolvedParent));
    }
    _draft = WorkspaceExplorerDraft(
      kind: kind,
      parentId: resolvedParent,
      suggestedName: suggestedName ??
          (kind == WorkspaceExplorerDraftKind.folder
              ? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr()
              : LocaleKeys.workspaceFolderExplorer_untitledFile.tr()),
    );
    _editingId = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Runs one entry of the "New file" menu inside [parentId].
  ///
  /// Blank documents open an inline name field, uploads go straight through
  /// the picker. Returns the created view, if any.
  Future<ViewPB?> createFileOfKind(
    WorkspaceFileMenuAction action, {
    String? parentId,
  }) async {
    if (action.source == WorkspaceFileSource.create) {
      beginCreate(
        WorkspaceExplorerDraftKind.file,
        parentId: parentId,
        suggestedName: action.kind.defaultFileName,
      );
      return null;
    }

    final resolvedParent = parentId ?? _selectedFolderId ?? currentFolder.id;
    final result = await createWorkspaceFile(
      parentViewId: resolvedParent,
      action: action,
    );
    if (result == null) {
      return null;
    }
    return result.fold(
      (view) async {
        _cacheView(view);
        _insertChild(resolvedParent, view.id);
        selection.selectOnly(view.id);
        _refreshRows();
        await _refreshActiveSearch();
        return view;
      },
      (error) {
        _setError(error.msg);
        return null;
      },
    );
  }

  void cancelEditing() {
    if (_draft == null && _editingId == null) {
      return;
    }
    _draft = null;
    _editingId = null;
    notifyListeners();
  }

  /// Creates a file immediately instead of opening an inline name field.
  ///
  /// Hosts that do not draw the explorer's draft row — the collection page —
  /// must use this, or a blank document is asked for and never appears.
  Future<ViewPB?> createFileImmediately(
    WorkspaceFileMenuAction action, {
    String? parentId,
    String? name,
  }) async {
    final resolvedParent = parentId ?? _selectedFolderId ?? currentFolder.id;
    final result = await createWorkspaceFile(
      parentViewId: resolvedParent,
      action: action,
      name: name ?? action.kind.defaultFileName,
    );
    if (result == null) {
      return null;
    }
    return _adopt(resolvedParent, result);
  }

  Future<ViewPB?> createFolderImmediately({
    String? parentId,
    String? name,
  }) async {
    final resolvedParent = parentId ?? _selectedFolderId ?? currentFolder.id;
    final result = await _repository.createFolder(
      parentViewId: resolvedParent,
      name: name ?? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
    );
    return _adopt(resolvedParent, result);
  }

  Future<ViewPB?> _adopt(
    String parentId,
    FlowyResult<ViewPB, FlowyError> result,
  ) async {
    return result.fold(
      (view) async {
        _cacheView(view);
        _insertChild(parentId, view.id);
        selection.selectOnly(view.id);
        _refreshRows();
        await _refreshActiveSearch();
        return view;
      },
      (error) {
        _setError(error.msg);
        return null;
      },
    );
  }

  void beginRename(String id) {
    if (!_views.containsKey(id)) {
      return;
    }
    _draft = null;
    _editingId = id;
    notifyListeners();
  }

  Future<bool> commitDraft(String rawName) async {
    final draft = _draft;
    final name = rawName.trim();
    if (draft == null || name.isEmpty) {
      _setError(LocaleKeys.workspaceFolderExplorer_nameRequired.tr());
      return false;
    }

    final result = switch (draft.kind) {
      WorkspaceExplorerDraftKind.folder => _repository.createFolder(
          parentViewId: draft.parentId,
          name: name,
        ),
      WorkspaceExplorerDraftKind.file => _repository.createTextFile(
          parentViewId: draft.parentId,
          name: name,
          content: '',
        ),
    };
    final created = await result;
    return created.fold(
      (view) async {
        _draft = null;
        _cacheView(view);
        _insertChild(draft.parentId, view.id);
        selection.selectOnly(view.id);
        _refreshRows();
        await _refreshActiveSearch();
        return true;
      },
      (error) async {
        _setError(error.msg);
        return false;
      },
    );
  }

  void _setBreadcrumbPath(String folderId) {
    final path = <String>[];
    var current = _views[folderId];
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      path.add(current.id);
      if (current.id == _rootId) {
        break;
      }
      current = _views[current.parentViewId];
    }
    if (path.isEmpty || path.last != _rootId) {
      path.add(_rootId);
    }
    _breadcrumbs
      ..clear()
      ..addAll(path.reversed);
  }

  Future<bool> commitRename(String rawName) async {
    final id = _editingId;
    final name = rawName.trim();
    if (id == null || name.isEmpty) {
      _setError(LocaleKeys.workspaceFolderExplorer_renameNameRequired.tr());
      return false;
    }
    final result = await _repository.rename(viewId: id, name: name);
    return result.fold(
      (view) async {
        _editingId = null;
        _cacheView(view);
        _refreshRows();
        await _refreshActiveSearch();
        return true;
      },
      (error) async {
        _setError(error.msg);
        return false;
      },
    );
  }

  void copySelection() {
    final views = _selectedViews;
    if (views.isNotEmpty) {
      clipboard.copy(views);
    }
  }

  void cutSelection() {
    final views = _selectedViews;
    if (views.isNotEmpty) {
      clipboard.cut(views);
    }
  }

  Future<void> duplicateSelection() async {
    final targetIds = <String>{};
    for (final view in _selectedViews) {
      final targetId = view.parentViewId;
      final result = await _repository.duplicate(
        view: view,
        parentViewId: targetId,
      );
      final shouldContinue = result.fold(
        (duplicate) {
          _cacheView(duplicate);
          _insertChild(targetId, duplicate.id);
          targetIds.add(targetId);
          return true;
        },
        (error) {
          _setError(error.msg);
          return false;
        },
      );
      if (!shouldContinue) {
        return;
      }
    }
    for (final targetId in targetIds) {
      await _loadChildren(targetId, force: true);
    }
    await _refreshActiveSearch();
  }

  Future<void> paste({String? parentId}) async {
    final data = clipboard.data;
    if (data == null || data.views.isEmpty) {
      _setError(LocaleKeys.workspaceFolderExplorer_nothingToPaste.tr());
      return;
    }
    final targetId = parentId ?? _selectedFolderId ?? currentFolder.id;
    final currentFolderId = currentFolder.id;
    final affectedParentIds = <String>{targetId, currentFolderId};

    for (final view in data.views) {
      if (data.operation == WorkspaceItemClipboardOperation.copy &&
          view.isWorkspaceFile) {
        continue;
      }
      final canPaste = await _canMove(view.id, targetId);
      if (canPaste == null) {
        return;
      }
      if (!canPaste) {
        _setError(
          data.operation == WorkspaceItemClipboardOperation.copy
              ? LocaleKeys.workspaceFolderExplorer_invalidFolderCopy.tr()
              : LocaleKeys.workspaceFolderExplorer_invalidFolderMove.tr(),
        );
        return;
      }
    }

    if (data.operation == WorkspaceItemClipboardOperation.copy) {
      for (final view in data.views) {
        final result = await _repository.duplicate(
          view: view,
          parentViewId: targetId,
        );
        if (result.isFailure) {
          result.onFailure((error) => _setError(error.msg));
          return;
        }
      }
    } else {
      String? previousViewId;
      for (final view in data.views) {
        if (_loadedFolders.contains(view.parentViewId)) {
          affectedParentIds.add(view.parentViewId);
        }
        final result = await _repository.move(
          viewId: view.id,
          parentViewId: targetId,
          previousViewId: previousViewId,
        );
        if (result.isFailure) {
          result.onFailure((error) => _setError(error.msg));
          return;
        }
        previousViewId = view.id;
      }
      clipboard.clear();
    }
    for (final folderId in affectedParentIds) {
      await _loadChildren(folderId, force: true);
    }
    _rebuildCurrentBreadcrumbs();
    await _refreshActiveSearch();
  }

  Future<void> deleteSelection() async {
    final ids = _selectedViews.map((view) => view.id).toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final result = await _repository.delete(ids);
    await result.fold(
      (_) async {
        if (_query.isNotEmpty) {
          _searchRows = const [];
        }
        for (final id in ids) {
          _removeCachedBranch(id);
        }
        _repairBreadcrumbs();
        selection.clear();
        _refreshRows();
        await _refreshActiveSearch();
      },
      (error) async => _setError(error.msg),
    );
  }

  Future<void> moveItem({
    required String itemId,
    required String parentId,
    String? previousViewId,
  }) async {
    final canMove = await _canMove(itemId, parentId);
    if (canMove == null) {
      return;
    }
    if (!canMove) {
      _setError(LocaleKeys.workspaceFolderExplorer_invalidFolderMove.tr());
      return;
    }
    final previousParentId = _views[itemId]?.parentViewId;
    final result = await _repository.move(
      viewId: itemId,
      parentViewId: parentId,
      previousViewId: previousViewId,
    );
    await result.fold(
      (_) async {
        if (previousParentId != null) {
          await _loadChildren(previousParentId, force: true);
        }
        await _loadChildren(parentId, force: true);
        _rebuildCurrentBreadcrumbs();
        await _refreshActiveSearch();
      },
      (error) async => _setError(error.msg),
    );
  }

  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    _query = query;
    final generation = ++_searchGeneration;
    if (query.isEmpty) {
      _isSearching = false;
      _searchRows = null;
      notifyListeners();
      return;
    }

    final cachedIndex = _searchIndex;
    if (cachedIndex != null) {
      _buildSearchRows(cachedIndex, query.toLowerCase());
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _errorMessage = null;
    notifyListeners();
    final result = await _repository.getAllViews();
    if (_isDisposed || generation != _searchGeneration) {
      return;
    }
    result.fold(
      (views) {
        _searchIndex = List.unmodifiable(
          views.map((view) => ViewPB.fromBuffer(view.writeToBuffer())),
        );
        _buildSearchRows(_searchIndex!, query.toLowerCase());
        _isSearching = false;
        notifyListeners();
      },
      (error) {
        _searchRows = const [];
        _isSearching = false;
        _setError(error.msg);
      },
    );
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  ViewPB? viewForId(String id) => _views[id];

  WorkspaceExplorerItem? itemForId(String id) => _item(id);

  /// The cached children of [id] in backend order, regardless of where the
  /// explorer has navigated to.
  List<ViewPB> childrenOf(String id) => [
        for (final childId in _children[id] ?? const <String>[])
          if (_views[childId] case final view?) view,
      ];

  bool hasLoaded(String id) => _loadedFolders.contains(id);

  Future<void> ensureLoaded(String id) => _loadChildren(id);

  void updateView(ViewPB view) => _handleViewUpdated(view);

  void updateRoot(ViewPB root) {
    if (root.id != _rootId) {
      return;
    }
    _searchIndex = null;
    _cacheView(root);
    _refreshRows();
  }

  String? previousSiblingId(String id, {String? excludingId}) {
    final view = _views[id];
    if (view == null) {
      return null;
    }
    final siblings = (_children[view.parentViewId] ?? const <String>[])
        .where((siblingId) => siblingId != excludingId)
        .toList(growable: false);
    final index = siblings.indexOf(id);
    return index <= 0 ? null : siblings[index - 1];
  }

  String relativePathFor(String id) {
    final names = <String>[];
    var current = _views[id];
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      if (current.name.isNotEmpty) {
        names.add(current.name);
      }
      if (current.id == _rootId) {
        break;
      }
      current = _views[current.parentViewId];
    }
    return names.reversed.join('/');
  }

  void showError(String message) => _setError(message);

  Future<void> revealItem(String id) async {
    final view = _views[id];
    if (view == null) {
      _setError(LocaleKeys.workspaceFolderExplorer_itemUnavailable.tr());
      return;
    }
    _cancelSearch();
    final result = await _repository.getAncestors(id);
    await result.fold(
      (ancestors) async {
        for (final ancestor in ancestors) {
          _cacheView(ancestor);
        }
        _setBreadcrumbPath(view.parentViewId);
        await _loadChildren(_breadcrumbs.last);
        selection.selectOnly(id);
        _refreshRows();
      },
      (error) async => _setError(error.msg),
    );
  }

  Future<void> _loadChildren(String folderId, {bool force = false}) async {
    if (!force &&
        (_loadingFolders.contains(folderId) ||
            _loadedFolders.contains(folderId))) {
      return;
    }
    final generation = (_loadGenerations[folderId] ?? 0) + 1;
    _loadGenerations[folderId] = generation;
    _loadingFolders.add(folderId);
    _refreshRows();
    final result = await _repository.getChildren(folderId);
    if (_isDisposed || _loadGenerations[folderId] != generation) {
      return;
    }
    result.fold(
      (views) {
        _searchIndex = null;
        final ids = <String>[];
        for (final view in views) {
          _cacheView(view);
          ids.add(view.id);
        }
        _children[folderId] = List.unmodifiable(ids);
        _loadedFolders.add(folderId);
        _listenToFolder(folderId);
      },
      (error) => _errorMessage = error.msg,
    );
    _loadingFolders.remove(folderId);
    _refreshRows();
  }

  void _listenToFolder(String id) {
    if (!listenForUpdates || _listeners.containsKey(id)) {
      return;
    }
    _listeners[id] = ViewListener(viewId: id)
      ..start(
        onViewUpdated: (view) {
          if (!_isDisposed) {
            _handleViewUpdated(view);
            unawaited(_refreshActiveSearch());
          }
        },
        onViewChildViewsUpdated: (_) {
          if (!_isDisposed) {
            unawaited(_reloadFolderAfterUpdate(id));
          }
        },
        onViewDeleted: (result) {
          if (!_isDisposed) {
            result.fold(
              (view) => _handleExternalRemoval(view.id),
              (error) => _setError(error.msg),
            );
          }
        },
        onViewMoveToTrash: (result) {
          if (!_isDisposed) {
            result.fold(
              (deleted) => _handleExternalRemoval(deleted.viewId),
              (error) => _setError(error.msg),
            );
          }
        },
      );
  }

  void _handleViewUpdated(ViewPB view) {
    _searchIndex = null;
    final previousParentId = _views[view.id]?.parentViewId;
    _cacheView(view);
    if (previousParentId != null && previousParentId != view.parentViewId) {
      _children[previousParentId] =
          List.unmodifiable([...?_children[previousParentId]]..remove(view.id));
      if (_loadedFolders.contains(view.parentViewId)) {
        _insertChild(view.parentViewId, view.id);
      }
      _rebuildCurrentBreadcrumbs();
    }
    _refreshRows();
  }

  void _handleExternalRemoval(String id) {
    if (id == _rootId) {
      _setError(LocaleKeys.workspaceFolderExplorer_itemUnavailable.tr());
      return;
    }
    _cancelSearch();
    _removeCachedBranch(id);
    _repairBreadcrumbs();
    selection.clear();
    _refreshRows();
  }

  void _handleTrashUpdate(
    FlowyResult<List<TrashPB>, FlowyError> trashOrFailure,
  ) {
    if (_isDisposed) {
      return;
    }
    trashOrFailure.fold(
      (List<TrashPB> trash) {
        final nextTrashIds = trash.map((item) => item.id).toSet();
        var removedCachedView = false;
        for (final id in nextTrashIds.difference(_trashIds)) {
          if (id == _rootId) {
            _setError(LocaleKeys.workspaceFolderExplorer_itemUnavailable.tr());
          } else if (_views.containsKey(id)) {
            _removeCachedBranch(id);
            removedCachedView = true;
          }
        }
        final restoredOrDeleted = _trashIds.difference(nextTrashIds).isNotEmpty;
        _trashIds = nextTrashIds;
        if (removedCachedView) {
          _repairBreadcrumbs();
          selection.retain(_views.keys);
          _refreshRows();
        }
        if (removedCachedView || restoredOrDeleted) {
          unawaited(refresh());
        }
      },
      (error) => _setError(error.msg),
    );
  }

  void _cacheView(ViewPB view) {
    _views[view.id] = ViewPB.fromBuffer(view.writeToBuffer());
  }

  void _insertChild(String parentId, String id) {
    final children = [...?_children[parentId]];
    if (!children.contains(id)) {
      children.add(id);
    }
    _children[parentId] = List.unmodifiable(children);
  }

  void _removeCachedBranch(String id) {
    final view = _views.remove(id);
    if (view == null) {
      return;
    }
    _children[view.parentViewId] =
        List.unmodifiable([...?_children[view.parentViewId]]..remove(id));
    for (final childId in _children.remove(id) ?? const <String>[]) {
      _removeCachedBranch(childId);
    }
    _expandedFolders.remove(id);
    _loadedFolders.remove(id);
    _loadingFolders.remove(id);
    _loadGenerations.remove(id);
    _listeners.remove(id)?.stop();
  }

  void _repairBreadcrumbs() {
    final surviving = <String>[];
    for (final id in _breadcrumbs) {
      if (!_views.containsKey(id)) {
        break;
      }
      surviving.add(id);
    }
    _breadcrumbs
      ..clear()
      ..addAll(surviving.isEmpty ? [_rootId] : surviving);
  }

  void _rebuildCurrentBreadcrumbs() {
    if (_breadcrumbs.isEmpty) {
      _breadcrumbs.add(_rootId);
      return;
    }
    final currentId = _breadcrumbs.last;
    if (_views.containsKey(currentId)) {
      _setBreadcrumbPath(currentId);
    } else {
      _repairBreadcrumbs();
    }
  }

  void _refreshRows() {
    final result = <WorkspaceExplorerRow>[];
    _appendRows(
      parentId: currentFolder.id,
      depth: 0,
      output: result,
    );
    _rows = List.unmodifiable(result);
    selection.retain(rows.map((row) => row.item.id));
    notifyListeners();
  }

  void _appendRows({
    required String parentId,
    required int depth,
    required List<WorkspaceExplorerRow> output,
  }) {
    for (final id in _children[parentId] ?? const <String>[]) {
      final item = _item(id);
      if (item == null) {
        continue;
      }
      final expanded = _expandedFolders.contains(id);
      output.add(
        WorkspaceExplorerRow(
          item: item,
          depth: depth,
          isExpanded: expanded,
          isLoading: _loadingFolders.contains(id),
        ),
      );
      if (item.isFolder && expanded) {
        _appendRows(parentId: id, depth: depth + 1, output: output);
      }
    }
  }

  void _buildSearchRows(List<ViewPB> views, String query) {
    final scopeId = currentFolder.id;
    final byId = <String, ViewPB>{
      ..._views,
      for (final view in views) view.id: view,
    };
    final children = <String, List<String>>{};
    for (final view in views) {
      children.putIfAbsent(view.parentViewId, () => []).add(view.id);
    }

    final included = <String>{};
    for (final view in views) {
      if (!view.name.toLowerCase().contains(query) ||
          !_isDescendantOf(view, scopeId, byId)) {
        continue;
      }
      var current = view;
      while (current.id != scopeId) {
        included.add(current.id);
        final parent = byId[current.parentViewId];
        if (parent == null) {
          break;
        }
        current = parent;
      }
    }

    final result = <WorkspaceExplorerRow>[];
    void append(String parentId, int depth) {
      for (final id in children[parentId] ?? const <String>[]) {
        if (!included.contains(id)) {
          continue;
        }
        final view = byId[id]!;
        _cacheView(view);
        final item = WorkspaceExplorerItem.fromView(view);
        result.add(
          WorkspaceExplorerRow(
            item: item,
            depth: depth,
            isExpanded: item.isFolder,
            isLoading: false,
          ),
        );
        append(id, depth + 1);
      }
    }

    append(scopeId, 0);
    _searchRows = List.unmodifiable(result);
    selection.retain(result.map((row) => row.item.id));
  }

  bool _isDescendantOf(
    ViewPB view,
    String ancestorId,
    Map<String, ViewPB> byId,
  ) {
    var current = view;
    final visited = <String>{};
    while (current.parentViewId.isNotEmpty && visited.add(current.id)) {
      if (current.parentViewId == ancestorId) {
        return true;
      }
      final parent = byId[current.parentViewId];
      if (parent == null) {
        return false;
      }
      current = parent;
    }
    return false;
  }

  bool _isSelectableSearchResult(String id) {
    if (_query.isEmpty) {
      return true;
    }
    return _views[id]?.name.toLowerCase().contains(_query.toLowerCase()) ??
        false;
  }

  Future<bool?> _canMove(String itemId, String parentId) async {
    if (itemId == parentId) {
      return false;
    }
    final result = await _repository.getAncestors(parentId);
    return result.fold(
      (ancestors) => ancestors.every((view) => view.id != itemId),
      (error) {
        _setError(error.msg);
        return null;
      },
    );
  }

  Future<void> _reloadFolderAfterUpdate(String id) async {
    await _loadChildren(id, force: true);
    await _refreshActiveSearch();
  }

  Future<void> _refreshActiveSearch() async {
    _searchIndex = null;
    final activeQuery = _query;
    if (activeQuery.isNotEmpty) {
      await search(activeQuery);
    }
  }

  void _cancelSearch() {
    _searchGeneration++;
    _query = '';
    _searchRows = null;
    _isSearching = false;
  }

  WorkspaceExplorerItem? _item(String id) {
    final view = _views[id];
    return view == null ? null : WorkspaceExplorerItem.fromView(view);
  }

  String? get _selectedFolderId {
    if (selection.length != 1) {
      return null;
    }
    final id = selection.ids.first;
    return _item(id)?.isFolder ?? false ? id : null;
  }

  List<ViewPB> get _selectedViews {
    final selectedIds = selection.ids.where((id) => id != _rootId).toSet();
    final result = <ViewPB>[];
    for (final row in rows) {
      final view = _views[row.item.id];
      if (view == null ||
          !selectedIds.contains(view.id) ||
          _hasSelectedAncestor(view, selectedIds)) {
        continue;
      }
      result.add(view);
    }
    return List.unmodifiable(result);
  }

  bool _hasSelectedAncestor(ViewPB view, Set<String> selectedIds) {
    var parent = _views[view.parentViewId];
    final visited = <String>{};
    while (parent != null && visited.add(parent.id)) {
      if (selectedIds.contains(parent.id)) {
        return true;
      }
      if (parent.id == _rootId) {
        break;
      }
      parent = _views[parent.parentViewId];
    }
    return false;
  }

  void _setError(String message) {
    _errorMessage = message.isEmpty
        ? LocaleKeys.workspaceFolderExplorer_operationFailed.tr()
        : message;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchGeneration++;
    for (final listener in _listeners.values) {
      listener.stop();
    }
    _listeners.clear();
    unawaited(_trashListener?.close());
    selection
      ..removeListener(notifyListeners)
      ..dispose();
    clipboard.removeListener(notifyListeners);
    super.dispose();
  }
}
