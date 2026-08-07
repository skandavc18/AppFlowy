import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

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
    this.listenForUpdates = true,
  })  : _collection = collection,
        _repository = repository {
    _load();
    if (listenForUpdates) {
      _listen(collection.id);
    }
  }

  final WorkspaceItemRepository _repository;
  final bool listenForUpdates;

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

  ViewPB get collection => _collection;
  List<ViewPB> get children => _children;
  bool get isLoading => _loading;
  Object? get error => _error;
  bool get isEmpty => !_loading && _children.isEmpty;

  /// The collection's children in the order a widget should offer them.
  List<ViewPB> ordered(CollectionEmbedSort sort) {
    if (sort == CollectionEmbedSort.manual) {
      return _children;
    }
    final sorted = [..._children];
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

  int _editedAt(ViewPB view) =>
      view.lastEdited.toInt() != 0 ? view.lastEdited.toInt() : view.createTime.toInt();

  /// Children of a nested folder. Returns what is already known and starts a
  /// read when it is not — so a preview can call this straight from `build`.
  List<ViewPB> childrenOf(String viewId) {
    final known = _nested[viewId];
    if (known != null) {
      return known;
    }
    unawaited(ensureLoaded(viewId));
    return const [];
  }

  bool hasLoaded(String viewId) => _nested.containsKey(viewId);

  Future<void> ensureLoaded(String viewId) async {
    if (_nested.containsKey(viewId) || _loadingNested.contains(viewId)) {
      return;
    }
    _loadingNested.add(viewId);
    final result = await _repository.getChildren(viewId);
    _loadingNested.remove(viewId);
    if (_disposed) {
      return;
    }
    result.fold(
      (views) {
        _nested[viewId] = views;
        notifyListeners();
      },
      (_) => _nested[viewId] = const [],
    );
  }

  Future<void> refresh() async {
    _nested.clear();
    await _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _loading = true;
    _error = null;
    final result = await _repository.getChildren(_collection.id);
    if (_disposed || generation != _generation) {
      return;
    }
    result.fold(
      (views) {
        _children = views;
        _error = null;
      },
      (error) => _error = error,
    );
    _loading = false;
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
    super.dispose();
  }
}
