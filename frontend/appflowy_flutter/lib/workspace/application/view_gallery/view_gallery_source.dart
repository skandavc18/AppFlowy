import 'dart:async';

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/favorite/favorite_listener.dart';
import 'package:appflowy/workspace/application/favorite/favorite_service.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart'
    show UserWorkspacePB;
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

/// A page as a library remembers it: when it was last viewed or favorited,
/// and whether it is pinned. The page itself is never copied or changed.
@immutable
class ViewGalleryEntry {
  const ViewGalleryEntry({required this.view, this.at, this.pinned = false});

  final ViewPB view;

  /// When the page was last viewed (Recents) or favorited (Favorites).
  final DateTime? at;
  final bool pinned;

  String get id => view.id;
}

/// Section timestamps are seconds; older records may hold milliseconds.
DateTime? viewGalleryTime(Int64 stamp) {
  final value = stamp.toInt();
  if (value <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    value > 100000000000 ? value : value * 1000,
  );
}

/// [entries] with the workspace itself shown as the folder it is everywhere
/// else — its name, icon and cover — rather than as a page with no document.
List<ViewGalleryEntry> viewGalleryEntriesWithRoot(
  List<ViewGalleryEntry> entries,
  UserWorkspacePB? workspace,
) {
  final id = workspace?.workspaceId ?? '';
  if (workspace == null ||
      id.isEmpty ||
      !entries.any((entry) => entry.view.isWorkspaceRootFor(id))) {
    return entries;
  }
  var cover = WorkspaceCoverCodec.decode(workspace.cover);
  if (cover == null && workspace.cover.trim().isEmpty) {
    cover = AutomaticViewCover.forWorkspace(name: workspace.name);
  }
  return [
    for (final entry in entries)
      entry.view.isWorkspaceRootFor(id)
          ? ViewGalleryEntry(
              view: entry.view.asWorkspaceRootFolder(
                workspaceId: id,
                name: workspace.name,
                icon: workspace.icon,
                cover: cover,
              ),
              at: entry.at,
              pinned: entry.pinned,
            )
          : entry,
  ];
}

/// A live list of pages. Reading one never creates, reorders or opens a page;
/// the only writes are the explicit library actions a person asks for.
abstract class ViewGallerySource extends ChangeNotifier {
  List<ViewGalleryEntry> get entries;
  bool get isLoading;
  bool get failed;

  Future<void> load();

  /// Forget [entry] from this library. The page itself is untouched.
  Future<void> forget(ViewGalleryEntry entry);
}

abstract class _ViewGallerySourceBase extends ViewGallerySource {
  List<ViewGalleryEntry> _entries = const [];
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;
  int _generation = 0;

  @override
  List<ViewGalleryEntry> get entries => _entries;
  @override
  bool get isLoading => _loading;
  @override
  bool get failed => _failed;

  bool get disposed => _disposed;

  void _publish(List<ViewGalleryEntry> entries, {bool failed = false}) {
    if (_disposed) return;
    _entries = List.unmodifiable(entries);
    _loading = false;
    _failed = failed;
    notifyListeners();
  }

  void _drop(String id) {
    if (_disposed) return;
    final remaining = _entries.where((entry) => entry.id != id).toList();
    if (remaining.length == _entries.length) return;
    _generation++;
    _publish(remaining, failed: _failed);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

List<ViewGalleryEntry> _recentEntries(Iterable<SectionViewPB> sections) {
  final seen = <String>{};
  return [
    for (final section in sections)
      // Spaces and orphans are containers, not somewhere a person works.
      if (!section.item.isSpace &&
          section.item.id != section.item.parentViewId &&
          seen.add(section.item.id))
        ViewGalleryEntry(
          view: section.item,
          at: viewGalleryTime(section.timestamp),
        ),
  ];
}

/// The pages opened most recently, newest first.
class RecentViewGallerySource extends _ViewGallerySourceBase {
  RecentViewGallerySource({
    Future<List<SectionViewPB>> Function()? read,
    Future<void> Function(List<String> viewIds)? remove,
    ValueListenable<List<SectionViewPB>>? live,
    CachedRecentService? recents,
  })  : _read = read ?? _readRecents,
        _remove = remove ?? _removeRecents,
        _live = live,
        _service = recents,
        _useSharedLive = read == null && live == null && recents == null;

  final Future<List<SectionViewPB>> Function() _read;
  final Future<void> Function(List<String> viewIds) _remove;
  final bool _useSharedLive;
  ValueListenable<List<SectionViewPB>>? _live;
  CachedRecentService? _service;
  bool _bound = false;

  void _bind() {
    if (_bound) return;
    _bound = true;
    if (_useSharedLive && getIt.isRegistered<CachedRecentService>()) {
      _service = getIt<CachedRecentService>();
    }
    final service = _service;
    if (service != null && !service.isDisposed) {
      // The shared cache owns the one backend listener for recent views.
      unawaited(service.recentViews());
      _live ??= service.notifier;
    }
    _live?.addListener(_onLiveChanged);
  }

  void _onLiveChanged() {
    final live = _live;
    if (live == null || disposed) return;
    final generation = ++_generation;
    final service = _service;
    if (live.value.isEmpty && service != null && !service.isDisposed) {
      // A workspace switch (the one at launch included) empties the shared
      // history and stops it listening until it is asked again. Ask, rather
      // than showing that gap as "nothing opened lately".
      unawaited(
        service.recentViews().then((sections) {
          if (!disposed && generation == _generation) {
            _publish(_recentEntries(sections));
          }
        }),
      );
      return;
    }
    _publish(_recentEntries(live.value));
  }

  @override
  Future<void> load() async {
    _bind();
    final generation = ++_generation;
    try {
      final sections = await _read();
      if (disposed || generation != _generation) return;
      _publish(_recentEntries(sections));
    } catch (error, stackTrace) {
      if (disposed || generation != _generation) return;
      Log.error('Recent pages could not be read: $error', error, stackTrace);
      _publish(_entries, failed: true);
    }
  }

  @override
  Future<void> forget(ViewGalleryEntry entry) async {
    await _remove([entry.id]);
    _drop(entry.id);
  }

  /// Forget the whole history at once; the pages themselves are untouched.
  Future<void> clear() async {
    final ids = [for (final entry in entries) entry.id];
    if (ids.isEmpty) return;
    await _remove(ids);
    if (disposed) return;
    _generation++;
    _publish(const []);
  }

  static Future<List<SectionViewPB>> _readRecents() async {
    final result = await FolderEventReadRecentViews(
      ReadRecentViewsPB(start: Int64(), limit: Int64(100)),
    ).send();
    return result.fold(
      (views) => views.items.toList(),
      (error) => throw StateError(error.msg),
    );
  }

  static Future<void> _removeRecents(List<String> ids) async {
    final result = await FolderEventUpdateRecentViews(
      UpdateRecentViewPayloadPB(viewIds: ids, addInRecent: false),
    ).send();
    result.fold((_) {}, (error) => throw StateError(error.msg));
  }

  @override
  void dispose() {
    _live?.removeListener(_onLiveChanged);
    super.dispose();
  }
}

/// Favorited pages: pinned ones first, then the rest in the stored order.
class FavoriteViewGallerySource extends _ViewGallerySourceBase {
  FavoriteViewGallerySource({
    FavoriteService? service,
    bool listen = true,
  })  : _service = service ?? FavoriteService(),
        _listener = listen ? FavoriteListener() : null;

  final FavoriteService _service;
  final FavoriteListener? _listener;
  bool _listening = false;

  @override
  Future<void> load() async {
    if (!_listening) {
      _listening = true;
      _listener?.start(favoritesUpdated: (_, __) => unawaited(_fetch()));
    }
    await _fetch();
  }

  Future<void> _fetch() async {
    final generation = ++_generation;
    try {
      final result = await _service.readFavorites();
      if (disposed || generation != _generation) return;
      result.fold(
        (favorites) {
          final seen = <String>{};
          final entries = [
            for (final section in favorites.items)
              if (seen.add(section.item.id))
                ViewGalleryEntry(
                  view: section.item,
                  at: viewGalleryTime(section.timestamp),
                  pinned: section.item.isPinned,
                ),
          ];
          _publish([
            ...entries.where((entry) => entry.pinned),
            ...entries.where((entry) => !entry.pinned),
          ]);
        },
        (error) {
          Log.error('Favorites could not be read: ${error.msg}');
          _publish(_entries, failed: true);
        },
      );
    } catch (error, stackTrace) {
      if (disposed || generation != _generation) return;
      Log.error('Favorites could not be read: $error', error, stackTrace);
      _publish(_entries, failed: true);
    }
  }

  /// Pinned favorites are the ones the sidebar keeps in view.
  Future<void> setPinned(ViewGalleryEntry entry, bool pinned) async {
    await (pinned
        ? _service.pinFavorite(entry.view)
        : _service.unpinFavorite(entry.view));
    if (!disposed) await _fetch();
  }

  @override
  Future<void> forget(ViewGalleryEntry entry) async {
    if (entry.pinned) await _service.unpinFavorite(entry.view);
    await _service.toggleFavorite(entry.id);
    _drop(entry.id);
  }

  @override
  void dispose() {
    unawaited(_listener?.stop());
    super.dispose();
  }
}

const _databaseLayouts = {
  ViewLayoutPB.Grid,
  ViewLayoutPB.Board,
  ViewLayoutPB.Calendar,
};

/// Every page a person works in, most recently edited first. The workspace
/// itself, spaces, orphans (row pages) and a database's other tabs are
/// containers or parts of another page, so they are left out.
@visibleForTesting
List<ViewGalleryEntry> allPagesEntries(Iterable<ViewPB> views) {
  final byId = {for (final view in views) view.id: view};
  bool isDatabaseTab(ViewPB view) =>
      _databaseLayouts.contains(view.layout) &&
      _databaseLayouts.contains(byId[view.parentViewId]?.layout);
  final seen = <String>{};
  final indexed = <(int, ViewGalleryEntry)>[];
  for (final view in views) {
    if (view.parentViewId.isEmpty ||
        view.id == view.parentViewId ||
        view.isSpace ||
        isDatabaseTab(view) ||
        !seen.add(view.id)) {
      continue;
    }
    final entry = ViewGalleryEntry(
      view: view,
      at: viewGalleryTime(view.lastEdited) ?? viewGalleryTime(view.createTime),
    );
    indexed.add((indexed.length, entry));
  }
  indexed.sort((a, b) {
    final left = a.$2.at, right = b.$2.at;
    if (left != null && right != null && left != right) {
      return right.compareTo(left);
    }
    if ((left == null) != (right == null)) return left == null ? 1 : -1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, entry) in indexed) entry];
}

/// Every page in the workspace: the Library.
class AllPagesGallerySource extends _ViewGallerySourceBase {
  AllPagesGallerySource({
    Future<List<ViewPB>> Function()? read,
    Listenable? changes,
  })  : _read = read ?? _readAll,
        _changes = changes,
        _useSharedChanges = read == null && changes == null;

  final Future<List<ViewPB>> Function() _read;
  final bool _useSharedChanges;
  Listenable? _changes;
  CachedRecentService? _service;
  bool _bound = false;
  Timer? _reload;

  void _bind() {
    if (_bound) return;
    _bound = true;
    if (_useSharedChanges && getIt.isRegistered<CachedRecentService>()) {
      final service = getIt<CachedRecentService>();
      if (!service.isDisposed) {
        // Creating, opening, renaming or trashing a page touches the recent
        // pages; that one shared listener is enough to keep this list fresh.
        _service = service;
        unawaited(service.recentViews());
        _changes = service.notifier;
      }
    }
    _changes?.addListener(_onChanged);
  }

  void _onChanged() {
    if (disposed) return;
    final service = _service;
    // A workspace switch stops the shared listener until it is asked again.
    if (service != null && !service.isDisposed) {
      unawaited(service.recentViews());
    }
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 400), () {
      if (!disposed) unawaited(load());
    });
  }

  @override
  Future<void> load() async {
    _bind();
    final generation = ++_generation;
    try {
      final views = await _read();
      if (disposed || generation != _generation) return;
      _publish(allPagesEntries(views));
    } catch (error, stackTrace) {
      if (disposed || generation != _generation) return;
      Log.error('The pages could not be read: $error', error, stackTrace);
      _publish(_entries, failed: true);
    }
  }

  /// Every page belongs here, so there is nothing to forget.
  @override
  Future<void> forget(ViewGalleryEntry entry) async {}

  static Future<List<ViewPB>> _readAll() async {
    final result = await ViewBackendService.getAllViews();
    return result.fold(
      (views) => views.items.toList(),
      (error) => throw StateError(error.msg),
    );
  }

  @override
  void dispose() {
    _reload?.cancel();
    _changes?.removeListener(_onChanged);
    super.dispose();
  }
}

/// The name of the place each page lives in, looked up once per parent.
class ViewGalleryLocations extends ChangeNotifier {
  ViewGalleryLocations({Future<String?> Function(String id)? readName})
      : _readName = readName ?? _readViewName;

  final Future<String?> Function(String id) _readName;
  final Map<String, String> _names = {};
  final Set<String> _pending = {};
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// An empty string until the parent has been read, or when it cannot be.
  String nameOf(ViewPB view) => _names[view.parentViewId] ?? '';

  void request(Iterable<ViewGalleryEntry> entries) {
    for (final entry in entries) {
      final id = entry.view.parentViewId;
      if (id.isEmpty || _names.containsKey(id) || !_pending.add(id)) continue;
      unawaited(_resolve(id));
    }
  }

  Future<void> _resolve(String id) async {
    String? name;
    try {
      name = await _readName(id);
    } catch (error) {
      Log.warn('A page location could not be read: $error');
    }
    _pending.remove(id);
    if (_disposed) return;
    _names[id] = name?.trim() ?? '';
    if (_notifyScheduled) return;
    // Parents usually resolve together; repaint the wall once for all of them.
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  static Future<String?> _readViewName(String id) async =>
      (await ViewBackendService.getView(id))
          .fold((view) => view.nameOrDefault, (_) => null);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
