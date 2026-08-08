import 'dart:async';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/provider_view_factory.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// The one object every external collection view listens to.
///
/// It owns the whole life of a remote listing: read the cache so the first
/// paint is instant, refresh behind it, classify anything that goes wrong into
/// a state the interface can draw, and hand out synthetic workspace items so
/// the views themselves never learn what a provider is.
class ProviderController extends ChangeNotifier {
  ProviderController({
    required this.collectionId,
    required CollectionSource source,
    CollectionProvider? provider,
    ProviderCache? cache,
    this.autoRefresh = const Duration(minutes: 10),
  })  : _source = source,
        _cache = cache ?? ProviderCache.instance,
        _factory = ProviderViewFactory(
          collectionId: collectionId,
          source: source,
        ) {
    _provider = provider;
  }

  final String collectionId;
  final ProviderCache _cache;
  final ProviderViewFactory _factory;

  /// How often a collection left open refreshes itself. External content that
  /// silently goes stale is worse than content that visibly reloads.
  final Duration autoRefresh;

  final CollectionSource _source;
  CollectionProvider? _provider;
  Future<CollectionProvider>? _resolving;
  bool _disposed = false;
  Timer? _refreshTimer;

  ProviderStatus _status = ProviderStatus.idle;
  ProviderFailure? _failure;
  DateTime? _lastSyncedAt;
  String _query = '';

  /// Everything read so far, keyed by the container it was read from. The root
  /// listing lives under the empty string.
  final Map<String, List<ProviderNode>> _children =
      <String, List<ProviderNode>>{};
  final Map<String, ProviderNode> _byId = <String, ProviderNode>{};
  final Map<String, String> _thumbnails = <String, String>{};
  final Set<String> _refusedThumbnails = <String>{};
  final Set<String> _loadingContainers = <String>{};

  List<ProviderNode> _searchResults = const <ProviderNode>[];

  CollectionSource get source => _source;
  ProviderViewFactory get factory => _factory;
  ProviderStatus get status => _status;
  ProviderFailure? get failure => _failure;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String get query => _query;
  bool get isSearching => _query.isNotEmpty;

  bool get isReady => _status == ProviderStatus.ready;
  bool get isBusy => _status.isBusy;
  bool get hasFailed => _status.isFailure;

  /// What the interface may offer. A collection with no provider is local and
  /// can do everything; a provider narrows this from what the account can do,
  /// and a binding marked read only narrows it again — a mount must not be
  /// able to write to somebody's Drive until they have said it may.
  ProviderCapabilities get capabilities {
    final allowed = _provider?.capabilities ?? ProviderCapabilities.full;
    return _source.readOnly ? allowed.readOnlyCopy() : allowed;
  }

  String get originLabel => _provider?.originLabel ?? _source.remoteName;

  /// The nodes the current view should show: the search results while a query
  /// is running, the root listing otherwise.
  List<ProviderNode> get nodes =>
      isSearching ? _searchResults : childrenOf(null);

  List<ProviderNode> childrenOf(String? containerId) =>
      _children[containerId ?? ''] ?? const <ProviderNode>[];

  bool hasLoaded(String? containerId) =>
      _children.containsKey(containerId ?? '');

  bool isLoadingContainer(String? containerId) =>
      _loadingContainers.contains(containerId ?? '');

  ProviderNode? nodeById(String id) => _byId[id];

  /// The node behind a synthetic workspace view, so a view handed back by a
  /// card can be turned into something the provider understands.
  ProviderNode? nodeForView(String viewId) {
    final remoteId = _factory.remoteIdOf(viewId);
    return remoteId == null ? null : _byId[remoteId];
  }

  String? thumbnailFor(String nodeId) => _thumbnails[nodeId];

  /// Whether a picture was asked for and could not be had.
  ///
  /// Told apart from "not asked yet" so a tile can stop waiting rather than
  /// spinning for ever over something that is never going to arrive.
  bool thumbnailRefused(String nodeId) => _refusedThumbnails.contains(nodeId);

  /// The current listing dressed as workspace items.
  List<ProviderItemView> itemsFor(String? containerId) => _factory.viewsFor(
        childrenOf(containerId),
        thumbnails: _thumbnails,
      );

  List<ViewPB> viewsFor(String? containerId) =>
      [for (final item in itemsFor(containerId)) item.view];

  // --- Reading ---------------------------------------------------------------

  /// Opens the collection: cache first so something is on screen immediately,
  /// then a real read behind it.
  Future<void> load() async {
    if (_source.isLocal) {
      _set(ProviderStatus.ready);
      return;
    }

    await _restoreFromCache();
    await refresh(silent: _children.isNotEmpty);
    _startAutoRefresh();
  }

  /// Reads the collection again.
  ///
  /// [silent] keeps whatever is already on screen and shows a syncing state
  /// instead of a spinner, which is what a background refresh should look like.
  Future<void> refresh({bool silent = false}) async {
    if (_source.isLocal || _disposed) {
      return;
    }

    _set(silent ? ProviderStatus.syncing : ProviderStatus.loading);
    try {
      final provider = await _resolveProvider();
      await provider.ensureReady();

      final nodes = await provider.listAll();
      _adopt(null, nodes);
      _lastSyncedAt = DateTime.now();
      _failure = null;
      _set(ProviderStatus.ready);
      await _cache.writeJson(
        _source.cacheKey,
        'root',
        [for (final node in nodes) node.toJson()],
      );
      unawaited(_warmThumbnails(nodes));
    } on ProviderFailure catch (failure) {
      _fail(failure);
    } catch (error, stackTrace) {
      Log.warn('A provider read failed: $error\n$stackTrace');
      _fail(ProviderFailure(ProviderStatus.error, detail: '$error'));
    }
  }

  /// Reads one container's children, for a tree or a folder that was opened.
  Future<void> ensureLoaded(String containerId) async {
    if (_source.isLocal ||
        _children.containsKey(containerId) ||
        _loadingContainers.contains(containerId)) {
      return;
    }

    _loadingContainers.add(containerId);
    notifyListeners();
    try {
      final cached = await _cache.readJson(
        _source.cacheKey,
        'dir-${ProviderCache.digest(containerId)}',
      );
      if (cached != null) {
        _adopt(
          containerId,
          cached.list.map(ProviderNode.fromJson).whereType<ProviderNode>(),
        );
      }

      final provider = await _resolveProvider();
      final nodes = await provider.listAll(parentId: containerId);
      _adopt(containerId, nodes);
      await _cache.writeJson(
        _source.cacheKey,
        'dir-${ProviderCache.digest(containerId)}',
        [for (final node in nodes) node.toJson()],
      );
      unawaited(_warmThumbnails(nodes));
    } on ProviderFailure catch (failure) {
      // A single folder failing must not take the whole collection down: the
      // rest of the listing is still good.
      _failure = failure;
      Log.warn('Unable to read a remote folder: ${failure.status.name}');
    } catch (error) {
      Log.warn('Unable to read a remote folder: $error');
    } finally {
      _loadingContainers.remove(containerId);
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query == _query) {
      return;
    }
    _query = query;

    if (query.isEmpty) {
      _searchResults = const <ProviderNode>[];
      notifyListeners();
      return;
    }

    notifyListeners();
    try {
      final provider = await _resolveProvider();
      if (provider.capabilities.canSearch) {
        final page = await provider.search(query);
        _searchResults = page.nodes;
        for (final node in page.nodes) {
          _byId[node.id] = node;
        }
      } else {
        // No server-side search: filter what has already been read rather than
        // pretending the feature is missing.
        final needle = query.toLowerCase();
        _searchResults = [
          for (final node in _byId.values)
            if (node.name.toLowerCase().contains(needle)) node,
        ];
      }
      unawaited(_warmThumbnails(_searchResults));
    } on ProviderFailure catch (failure) {
      _failure = failure;
      _searchResults = const <ProviderNode>[];
    } catch (error) {
      Log.warn('A provider search failed: $error');
      _searchResults = const <ProviderNode>[];
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Forgets the cached listings and reads everything again. This is what the
  /// explicit "Sync" action does; a plain refresh trusts the cache.
  Future<void> resync() async {
    await _cache.invalidateListings(_source.cacheKey);
    _children.clear();
    await refresh();
  }

  /// The bytes of [node] on disk, so an existing viewer can open it by path.
  Future<String?> materialize(ProviderNode node) async {
    try {
      return await (await _resolveProvider()).materialize(node);
    } on ProviderFailure catch (failure) {
      _failure = failure;
      notifyListeners();
      return null;
    } catch (error) {
      Log.warn('Unable to fetch remote content: $error');
      return null;
    }
  }

  // --- Writes ----------------------------------------------------------------

  Future<bool> createFolder(String name, {String? parentId}) =>
      _write(() async {
        final node = await (await _resolveProvider())
            .createFolder(name, parentId: parentId);
        _insert(parentId, node);
      });

  Future<bool> rename(ProviderNode node, String name) => _write(() async {
        final renamed = await (await _resolveProvider()).rename(node, name);
        _replace(renamed);
      });

  Future<bool> delete(ProviderNode node) => _write(() async {
        await (await _resolveProvider()).delete(node);
        _remove(node);
      });

  Future<bool> move(ProviderNode node, {required String parentId}) =>
      _write(() async {
        final moved =
            await (await _resolveProvider()).move(node, parentId: parentId);
        _remove(node);
        _insert(parentId, moved);
      });

  Future<bool> setFavourite(ProviderNode node, bool favourite) =>
      _write(() async {
        final updated =
            await (await _resolveProvider()).setFavourite(node, favourite);
        _replace(updated);
      });

  Future<bool> upload(
    String name,
    Uint8List bytes, {
    String? parentId,
    String? mimeType,
  }) =>
      _write(() async {
        final node = await (await _resolveProvider()).upload(
          name,
          bytes,
          parentId: parentId,
          mimeType: mimeType,
        );
        _insert(parentId, node);
      });

  Future<bool> _write(Future<void> Function() action) async {
    try {
      await action();
      _failure = null;
      notifyListeners();
      return true;
    } on ProviderFailure catch (failure) {
      _failure = failure;
      notifyListeners();
      return false;
    } catch (error) {
      Log.warn('A provider write failed: $error');
      _failure = const ProviderFailure(ProviderStatus.error);
      notifyListeners();
      return false;
    }
  }

  // --- Internals -------------------------------------------------------------

  /// The provider for this collection, built on first use.
  ///
  /// ⚠️ The connection list is read lazily, and a provider cannot be built
  /// without it: [ProviderRegistry.create] reports a missing connection as an
  /// expired sign in. Awaiting it here is what stops a page opened before the
  /// list has loaded — an embed, or a folder bound to a service — from
  /// claiming the account is gone and asking somebody to sign in again.
  Future<CollectionProvider> _resolveProvider() {
    final live = _provider;
    if (live != null) {
      return Future<CollectionProvider>.value(live);
    }
    // One build at a time: a view firing a listing, a search and six
    // thumbnails at once must not end up with seven providers.
    return _resolving ??= () async {
      try {
        await ProviderConnections.instance.ensureLoaded();
        final created = ProviderRegistry.create(_source);
        if (created == null) {
          throw const ProviderFailure(
            ProviderStatus.error,
            detail: 'This collection has no external source.',
          );
        }
        _provider = created;
        return created;
      } finally {
        _resolving = null;
      }
    }();
  }

  Future<void> _restoreFromCache() async {
    final cached = await _cache.readJson(_source.cacheKey, 'root');
    if (cached == null) {
      return;
    }
    final nodes =
        cached.list.map(ProviderNode.fromJson).whereType<ProviderNode>();
    if (nodes.isEmpty) {
      return;
    }
    _adopt(null, nodes);
    _lastSyncedAt = cached.writtenAt;
    _set(ProviderStatus.ready);
    unawaited(_readCachedThumbnails(nodes));
  }

  void _adopt(String? containerId, Iterable<ProviderNode> nodes) {
    final list = nodes.toList(growable: false);
    _children[containerId ?? ''] = list;
    for (final node in list) {
      _byId[node.id] = node;
    }
  }

  void _insert(String? containerId, ProviderNode node) {
    final key = containerId ?? '';
    final list = List<ProviderNode>.from(_children[key] ?? const []);
    list.insert(0, node);
    _children[key] = list;
    _byId[node.id] = node;
  }

  void _replace(ProviderNode node) {
    _byId[node.id] = node;
    for (final entry in _children.entries) {
      final index =
          entry.value.indexWhere((existing) => existing.id == node.id);
      if (index >= 0) {
        final list = List<ProviderNode>.from(entry.value);
        list[index] = node;
        _children[entry.key] = list;
      }
    }
  }

  void _remove(ProviderNode node) {
    _byId.remove(node.id);
    for (final entry in _children.entries.toList()) {
      _children[entry.key] =
          entry.value.where((existing) => existing.id != node.id).toList();
    }
    _searchResults =
        _searchResults.where((existing) => existing.id != node.id).toList();
  }

  /// Pulls thumbnails a few at a time, so a wall of a thousand pictures does
  /// not open a thousand sockets. The list is already on screen while this
  /// runs; every arrival is one repaint.
  Future<void> _warmThumbnails(List<ProviderNode> nodes) async {
    const batch = 6;
    final wanted = [
      for (final node in nodes)
        if (!node.isFolder &&
            node.thumbnailUrl != null &&
            !_thumbnails.containsKey(node.id))
          node,
    ];

    for (var index = 0; index < wanted.length; index += batch) {
      if (_disposed) {
        return;
      }
      final slice = wanted.skip(index).take(batch);
      final paths = await Future.wait([
        for (final node in slice) _thumbnailFor(node),
      ]);
      var changed = false;
      var position = 0;
      for (final node in slice) {
        final path = paths[position++];
        if (path != null) {
          _thumbnails[node.id] = path;
          _refusedThumbnails.remove(node.id);
        } else {
          _refusedThumbnails.add(node.id);
        }
        changed = true;
      }
      if (changed && !_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _readCachedThumbnails(Iterable<ProviderNode> nodes) async {
    var changed = false;
    for (final node in nodes) {
      final path = await _cache.thumbnailPath(_source.cacheKey, node.id);
      if (path != null) {
        _thumbnails[node.id] = path;
        changed = true;
      }
    }
    if (changed && !_disposed) {
      notifyListeners();
    }
  }

  Future<String?> _thumbnailFor(ProviderNode node) async {
    try {
      return await (await _resolveProvider()).thumbnailPath(node);
    } catch (_) {
      return null;
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    if (autoRefresh <= Duration.zero) {
      return;
    }
    _refreshTimer = Timer.periodic(autoRefresh, (_) {
      if (!_disposed && !isBusy) {
        unawaited(refresh(silent: true));
      }
    });
  }

  void _set(ProviderStatus status) {
    if (_disposed) {
      return;
    }
    _status = status;
    notifyListeners();
  }

  void _fail(ProviderFailure failure) {
    if (_disposed) {
      return;
    }
    _failure = failure;
    // Anything already read stays on screen. A refresh that fails should not
    // empty a collection somebody was reading.
    _status = failure.status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _provider?.dispose();
    super.dispose();
  }
}
