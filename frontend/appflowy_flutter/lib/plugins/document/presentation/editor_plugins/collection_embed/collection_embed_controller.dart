import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_selection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;

/// Reads exactly as much of a collection as a widget needs, and no more.
///
/// A widget on a page must never instantiate the collection's application:
/// this loads the collection's own children once, keeps them fresh through a
/// [ViewListener], and hands out an ordered, capped slice. Anything deeper —
/// a repository tree, a book's chapters — is walked by the preview that
/// actually needs it, on demand.
class CollectionEmbedController extends ChangeNotifier {
  CollectionEmbedController({
    required ViewPB collection,
    WorkspaceItemRepository repository = const WorkspaceItemService(),
    FolderGalleryPreviewLoader? previewLoader,
    this.listenForUpdates = true,
  })  : _collection = collection,
        _previewLoader = previewLoader,
        _repository = repository {
    _load();
    if (listenForUpdates) {
      _listen(collection.id);
    }
  }

  final WorkspaceItemRepository _repository;
  final FolderGalleryPreviewLoader? _previewLoader;
  final bool listenForUpdates;

  /// Matches the largest saved embed item limit. List-only and other collection
  /// previews never allocate this cache or start document/media reads.
  static const maximumPreviewEntries = 60;
  FolderGalleryPreviewCache? _folderPreviews;

  ViewPB _collection;
  List<ViewPB> _children = const [];
  bool _loading = true;
  Object? _error;
  bool _disposed = false;
  ViewListener? _listener;
  int _generation = 0;

  /// Children of nested folders, read only when a preview asks for them.
  final Map<String, List<ViewPB>> _nested = <String, List<ViewPB>>{};
  final Set<String> _loadingNested = <String>{};
  final Map<String, Object> _nestedErrors = {};

  /// Session navigation and selection are shared with the expanded embed.
  /// Neither is a write to the collection or its backing provider.
  final folderSelection = WorkspaceExplorerSelection();
  final expandedFolders = <String>{};
  TextEditingController? _folderFilter;
  bool get folderFilterActive => _folderFilter != null;
  String get folderQuery => _folderFilter?.text.trim().toLowerCase() ?? '';
  TextEditingController get folderFilter =>
      _folderFilter ??= (TextEditingController()..addListener(_filterChanged));
  void _filterChanged() {
    if (!_disposed) notifyListeners();
  }

  late List<ViewPB> _folderPath = [_collection];
  List<ViewPB> get folderPath => List.unmodifiable(_folderPath);

  void navigateFolder(ViewPB view) {
    if (_disposed) return;
    final existing = _folderPath.indexWhere((entry) => entry.id == view.id);
    if (existing >= 0) {
      _folderPath = _folderPath.take(existing + 1).toList();
    } else {
      if (!WorkspaceExplorerItem.fromView(view).isBrowsable) return;
      final parent =
          _folderPath.indexWhere((entry) => entry.id == view.parentViewId);
      if (parent < 0) return;
      _folderPath = [..._folderPath.take(parent + 1), view];
    }
    folderSelection.clear();
    _folderFilter?.clear();
    unawaited(ensureLoaded(view.id));
    notifyListeners();
  }

  List<ViewPB> orderedChildren(String id, CollectionEmbedSort sort) {
    final views = id == _collection.id ? _children : childrenOf(id);
    return _ordered(views, sort);
  }

  bool loadingChildren(String id) =>
      id == _collection.id ? _loading : _loadingNested.contains(id);
  Object? childrenError(String id) =>
      id == _collection.id ? _error : _nestedErrors[id];

  Future<void> retryChildren(String id) async {
    if (id == _collection.id) return refresh();
    _nested.remove(id);
    _nestedErrors.remove(id);
    await ensureLoaded(id);
  }

  ViewPB get collection => _collection;
  List<ViewPB> get children => _children;
  bool get isLoading => _loading;
  Object? get error => _error;
  bool get isEmpty => !_loading && _children.isEmpty;

  /// The same bounded, stamped preview contract as the workspace gallery.
  /// Ownership follows the controller, not a layout, hover or theme rebuild.
  Future<FolderGalleryPreview> folderPreviewFor(ViewPB view) =>
      (_folderPreviews ??= FolderGalleryPreviewCache(
        loader: _previewLoader,
        maximumEntries: maximumPreviewEntries,
      ))
          .previewFor(view: view, item: WorkspaceExplorerItem.fromView(view));

  void retryFolderPreview(String viewId) {
    if (_disposed) return;
    _folderPreviews?.invalidate(viewId);
    notifyListeners();
  }

  /// The collection's children in the order a widget should offer them.
  List<ViewPB> ordered(CollectionEmbedSort sort) {
    return _ordered(_children, sort);
  }

  List<ViewPB> _ordered(List<ViewPB> views, CollectionEmbedSort sort) {
    if (sort == CollectionEmbedSort.manual) {
      return views;
    }
    final sorted = [...views];
    switch (sort) {
      case CollectionEmbedSort.name:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case CollectionEmbedSort.newest:
        sorted.sort((a, b) => _editedAt(b).compareTo(_editedAt(a)));
      case CollectionEmbedSort.oldest:
        sorted.sort((a, b) => _editedAt(a).compareTo(_editedAt(b)));
      case CollectionEmbedSort.manual:
        break;
    }
    return sorted;
  }

  /// The slice a widget paints, honouring both order and the item cap.
  List<ViewPB> slice(CollectionEmbedSettings settings, int fallbackLimit) {
    final limit = settings.itemLimit ?? fallbackLimit;
    final views = ordered(settings.sort);
    return views.length <= limit ? views : views.take(limit).toList();
  }

  int _editedAt(ViewPB view) => view.lastEdited.toInt() != 0
      ? view.lastEdited.toInt()
      : view.createTime.toInt();

  /// Children of a nested folder. Returns what is already known and starts a
  /// read when it is not — so a preview can call this straight from `build`.
  List<ViewPB> childrenOf(String viewId) {
    if (viewId == _collection.id) return _children;
    final known = _nested[viewId];
    if (known != null) {
      return known;
    }
    unawaited(ensureLoaded(viewId));
    return const [];
  }

  bool hasLoaded(String viewId) => viewId == _collection.id
      ? !_loading && _error == null
      : _nested.containsKey(viewId);

  Future<void> ensureLoaded(String viewId) async {
    if (_disposed ||
        viewId == _collection.id ||
        _nestedErrors.containsKey(viewId) ||
        _nested.containsKey(viewId) ||
        _loadingNested.contains(viewId)) {
      return;
    }
    final generation = _generation;
    _loadingNested.add(viewId);
    try {
      final result = await _repository.getChildren(viewId);
      if (_disposed || generation != _generation) return;
      result.fold(
        (views) => _nested[viewId] = views,
        (error) => _nestedErrors[viewId] = error,
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _nestedErrors[viewId] = error;
    } finally {
      if (!_disposed && generation == _generation) {
        _loadingNested.remove(viewId);
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    _nested.clear();
    _nestedErrors.clear();
    _loadingNested.clear();
    await _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _loadingNested.clear();
    _loading = true;
    _error = null;
    try {
      final result = await _repository.getChildren(_collection.id);
      if (_disposed || generation != _generation) return;
      result.fold(
        (views) {
          _children = views;
          _error = null;
        },
        (error) => _error = error,
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _error = error;
    }
    _loading = false;
    // An adopted refresh can contain new document/file contents with identical
    // view stamps. Replace those futures together with the listing, never on a
    // presentation rebuild or a nested-folder count notification. Late results
    // belong only to the old futures and cannot repopulate the cleared cache.
    _folderPreviews?.clear();
    notifyListeners();
  }

  void _listen(String viewId) {
    _listener = ViewListener(viewId: viewId)
      ..start(
        onViewUpdated: (view) {
          if (_disposed) {
            return;
          }
          _collection = view;
          notifyListeners();
        },
        onViewChildViewsUpdated: (_) => unawaited(_load()),
      );
  }

  @override
  void dispose() {
    _disposed = true;
    _listener?.stop();
    _folderPreviews?.clear();
    folderSelection.dispose();
    _folderFilter?.dispose();
    super.dispose();
  }
}
