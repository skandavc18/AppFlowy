import 'dart:async';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_browser_reader.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_fetcher.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_service.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// How many pages are read at once when a library catches up on metadata.
const _fetchBatchSize = 4;

/// Holds a bookmark library: what is in it, how it is ordered, and the work
/// still running against it.
class BookmarkController extends ChangeNotifier {
  BookmarkController({
    Map<String, dynamic>? initialState,
    this.onPersist,
    BookmarkService service = const BookmarkService(),
    BookmarkFetcher? fetcher,
    BookmarkSnapshotStore? snapshots,
    Duration persistDebounce = const Duration(milliseconds: 900),
  })  : _state = BookmarkState.fromJson(initialState ?? const {}),
        _service = service,
        _fetcher =
            fetcher ?? BookmarkFetcher(browserFallback: readPageInBrowser),
        _snapshots = snapshots ?? BookmarkSnapshotStore.instance,
        _persistDebounce = persistDebounce;

  final ValueChanged<Map<String, dynamic>>? onPersist;
  final BookmarkService _service;
  final BookmarkFetcher _fetcher;
  final BookmarkSnapshotStore _snapshots;
  final Duration _persistDebounce;

  BookmarkState _state;
  List<BookmarkEntry> _all = const [];
  List<BookmarkEntry> _visible = const [];
  BookmarkStats _stats = BookmarkStats.empty;
  String _query = '';
  Timer? _persistTimer;
  bool _disposed = false;

  /// Bookmarks whose page is being read right now.
  final Set<String> _working = <String>{};

  /// Bookmarks whose last read failed, so the interface can offer a retry.
  final Set<String> _failed = <String>{};

  BookmarkState get state => _state;
  BookmarkSettings get settings => _state.settings;
  List<BookmarkEntry> get all => _all;
  List<BookmarkEntry> get entries => _visible;
  BookmarkStats get stats => _stats;
  String get query => _query;
  bool get isWorking => _working.isNotEmpty;
  int get workingCount => _working.length;

  bool isWorkingOn(String id) => _working.contains(id);
  bool hasFailed(String id) => _failed.contains(id);

  BookmarkEntry? entryFor(String? id) {
    if (id == null) {
      return null;
    }
    for (final entry in _all) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  BookmarkEntry? get activeEntry => entryFor(_state.activeId);

  /// Adopts the collection's children.
  void setViews(List<ViewPB> views) {
    final next = bookmarkEntriesFrom(views);
    final unchanged = next.length == _all.length &&
        List.generate(next.length, (i) => i).every(
          (i) =>
              next[i].id == _all[i].id &&
              next[i].view.extra == _all[i].view.extra &&
              next[i].view.name == _all[i].view.name,
        );
    if (unchanged) {
      return;
    }
    _all = next;
    _rebuild();
    notifyListeners();
  }

  void setQuery(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed == _query) {
      return;
    }
    _query = trimmed;
    _rebuild();
    notifyListeners();
  }

  void updateSettings(BookmarkSettings settings) {
    _state = _state.copyWith(settings: settings);
    _rebuild();
    _schedulePersist();
    notifyListeners();
  }

  void toggleTagFilter(String tag) {
    _state = _state.toggleTag(tag);
    _rebuild();
    _schedulePersist();
    notifyListeners();
  }

  void clearFilters() {
    _state = _state.copyWith(
      activeTags: const <String>{},
      clearSite: true,
      settings: settings.copyWith(filter: BookmarkFilter.all),
    );
    _rebuild();
    _schedulePersist();
    notifyListeners();
  }

  void setSiteFilter(String? site) {
    _state = _state.copyWith(activeSite: site, clearSite: site == null);
    _rebuild();
    _schedulePersist();
    notifyListeners();
  }

  void openBookmark(String? id) {
    if (_state.activeId == id) {
      return;
    }
    _state = _state.copyWith(activeId: id, clearActive: id == null);
    _schedulePersist();
    notifyListeners();
  }

  /// Groups the visible bookmarks the way the settings ask for.
  ///
  /// A view whose whole shape is rows — the shelf — passes [grouping] so it
  /// never has to show one undivided run.
  List<BookmarkGroup> groups({BookmarkGrouping? grouping}) {
    final by = grouping ?? settings.grouping;
    if (by == BookmarkGrouping.none) {
      return [BookmarkGroup(label: '', entries: _visible)];
    }
    final buckets = <String, List<BookmarkEntry>>{};
    for (final entry in _visible) {
      buckets.putIfAbsent(_groupLabel(entry, by), () => []).add(entry);
    }
    final labels = buckets.keys.toList()
      ..sort((a, b) {
        if (by == BookmarkGrouping.month) {
          return b.compareTo(a);
        }
        final bySize = buckets[b]!.length.compareTo(buckets[a]!.length);
        return bySize != 0 ? bySize : a.compareTo(b);
      });
    return [
      for (final label in labels)
        BookmarkGroup(label: label, entries: buckets[label]!),
    ];
  }

  String _groupLabel(BookmarkEntry entry, BookmarkGrouping grouping) =>
      switch (grouping) {
        BookmarkGrouping.site => entry.host ?? 'Other',
        BookmarkGrouping.tag =>
          entry.metadata.tags.isEmpty ? 'Untagged' : entry.metadata.tags.first,
        BookmarkGrouping.month => _monthKey(entry.timelineDate),
        BookmarkGrouping.readState => switch (entry.metadata.readState) {
            BookmarkReadState.unread => 'Unread',
            BookmarkReadState.reading => 'Reading',
            BookmarkReadState.read => 'Read',
          },
        BookmarkGrouping.none => '',
      };

  static String _monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------- writes

  /// Reads a page and writes what it says about itself back onto the view.
  Future<void> refresh(
    BookmarkEntry entry, {
    bool snapshot = false,
    bool force = true,
  }) async {
    if (_working.contains(entry.id)) {
      return;
    }
    if (!force && entry.metadata.hasMetadata && !snapshot) {
      return;
    }
    _working.add(entry.id);
    _failed.remove(entry.id);
    notifyListeners();

    try {
      // The article is always read: it supplies the excerpt, the reading time
      // and the picture for pages that only declare a logo. Only the offline
      // copy needs the page kept as well.
      final result = await _fetcher.fetch(entry.url, keepHtml: snapshot);
      if (_disposed) {
        return;
      }
      if (!result.succeeded) {
        _failed.add(entry.id);
        await _write(entry, entry.metadata.copyWith(fetchFailed: true));
        return;
      }

      final found = result.metadata!;
      final article = result.article;
      var metadata = entry.metadata.copyWith(
        title: found.title,
        description: found.description,
        siteName: found.siteName,
        author: found.author,
        // A social post often declares only the site's logo, so the picture
        // inside the post itself is the better illustration.
        imageUrl: found.imageUrl ?? article?.leadImageUrl,
        faviconUrl: found.faviconUrl,
        canonicalUrl: found.canonicalUrl,
        publishedAt: found.publishedAt,
        fetchedAt: DateTime.now(),
        fetchFailed: false,
      );

      if (article != null && !article.isEmpty) {
        metadata = metadata.copyWith(
          wordCount: article.wordCount,
          excerpt: article.excerpt(),
        );
      }

      if (snapshot) {
        final hero = found.imageUrl == null
            ? null
            : await _fetcher.fetchImage(found.imageUrl!);
        final saved = await _snapshots.save(
          url: entry.url,
          article: article,
          html: result.html,
          heroBytes: hero,
        );
        if (saved != null) {
          metadata = metadata.copyWith(
            snapshotPath: saved.directory,
            snapshotAt: saved.savedAt,
            snapshotBytes: saved.bytes,
          );
        }
      }

      await _write(entry, metadata);
    } finally {
      _working.remove(entry.id);
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// Reads every bookmark that has never been read, a few at a time.
  Future<void> refreshMissing({bool snapshot = false}) async {
    final pending = [
      for (final entry in _all)
        if (!entry.metadata.hasMetadata &&
            !entry.metadata.fetchFailed &&
            !_working.contains(entry.id))
          entry,
    ];
    await _runBatched(pending, snapshot: snapshot);
  }

  Future<void> refreshAll({bool snapshot = false}) =>
      _runBatched(_visible.toList(), snapshot: snapshot);

  Future<void> _runBatched(
    List<BookmarkEntry> pending, {
    required bool snapshot,
  }) async {
    for (var i = 0; i < pending.length; i += _fetchBatchSize) {
      if (_disposed) {
        return;
      }
      final batch = pending.skip(i).take(_fetchBatchSize);
      await Future.wait([
        for (final entry in batch) refresh(entry, snapshot: snapshot),
      ]);
    }
  }

  Future<void> setStarred(BookmarkEntry entry, bool starred) =>
      _write(entry, entry.metadata.copyWith(starred: starred));

  Future<void> setReadState(BookmarkEntry entry, BookmarkReadState state) =>
      _write(
        entry,
        entry.metadata.copyWith(
          readState: state,
          readProgress: state == BookmarkReadState.read ? 1 : null,
        ),
      );

  Future<void> setNotes(BookmarkEntry entry, String notes) =>
      _write(entry, entry.metadata.copyWith(notes: notes));

  Future<void> setTags(BookmarkEntry entry, List<String> tags) {
    final normalized = <String>[];
    for (final tag in tags) {
      final value = normalizeBookmarkTag(tag);
      if (value != null && !normalized.contains(value)) {
        normalized.add(value);
      }
    }
    return _write(entry, entry.metadata.copyWith(tags: normalized));
  }

  Future<void> addTag(BookmarkEntry entry, String tag) {
    final value = normalizeBookmarkTag(tag);
    if (value == null || entry.metadata.tags.contains(value)) {
      return Future.value();
    }
    return setTags(entry, [...entry.metadata.tags, value]);
  }

  Future<void> removeTag(BookmarkEntry entry, String tag) => setTags(
        entry,
        entry.metadata.tags.where((value) => value != tag).toList(),
      );

  Future<void> recordProgress(BookmarkEntry entry, double progress) {
    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= entry.metadata.readProgress + 0.02) {
      return Future.value();
    }
    return _write(
      entry,
      entry.metadata.copyWith(
        readProgress: clamped,
        readState: clamped >= 0.96
            ? BookmarkReadState.read
            : BookmarkReadState.reading,
      ),
    );
  }

  Future<void> removeSnapshot(BookmarkEntry entry) async {
    await _snapshots.delete(entry.metadata.snapshotPath);
    await _write(entry, entry.metadata.copyWith(clearSnapshot: true));
  }

  /// Applies [metadata] locally at once, then persists it.
  Future<void> _write(BookmarkEntry entry, BookmarkMetadata metadata) async {
    _applyLocally(entry.id, metadata);
    await _service.updateMetadata(view: entry.view, metadata: metadata);
  }

  void _applyLocally(String id, BookmarkMetadata metadata) {
    final next = <BookmarkEntry>[];
    for (final entry in _all) {
      if (entry.id != id) {
        next.add(entry);
        continue;
      }
      final view = ViewPB()
        ..mergeFromMessage(entry.view)
        ..extra = metadata.mergeIntoExtra(entry.view.extra);
      next.add(BookmarkEntry(view: view, metadata: metadata));
    }
    _all = next;
    _rebuild();
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- rebuilding

  void _rebuild() {
    _visible = _sorted(_filtered(_all));
    _stats = _buildStats();
  }

  List<BookmarkEntry> _filtered(List<BookmarkEntry> source) {
    final tags = _state.activeTags;
    final site = _state.activeSite;
    return [
      for (final entry in source)
        if (_matchesFilter(entry) &&
            (site == null || entry.host == site) &&
            (tags.isEmpty || tags.every(entry.metadata.tags.contains)) &&
            (_query.isEmpty || entry.searchText.contains(_query)))
          entry,
    ];
  }

  bool _matchesFilter(BookmarkEntry entry) => switch (settings.filter) {
        BookmarkFilter.all => true,
        BookmarkFilter.unread =>
          entry.metadata.readState != BookmarkReadState.read,
        BookmarkFilter.starred => entry.metadata.starred,
        BookmarkFilter.offline => entry.metadata.hasSnapshot,
        BookmarkFilter.untagged => entry.metadata.tags.isEmpty,
      };

  List<BookmarkEntry> _sorted(List<BookmarkEntry> source) {
    final entries = source.toList();
    switch (settings.sort) {
      case BookmarkSort.recentlyAdded:
        entries.sort((a, b) => b.savedDate.compareTo(a.savedDate));
      case BookmarkSort.oldestFirst:
        entries.sort((a, b) => a.savedDate.compareTo(b.savedDate));
      case BookmarkSort.published:
        entries.sort((a, b) => b.timelineDate.compareTo(a.timelineDate));
      case BookmarkSort.title:
        entries.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case BookmarkSort.site:
        entries.sort((a, b) {
          final byHost = (a.host ?? '').compareTo(b.host ?? '');
          return byHost != 0 ? byHost : b.savedDate.compareTo(a.savedDate);
        });
      case BookmarkSort.unreadFirst:
        entries.sort((a, b) {
          final rank = _readRank(a).compareTo(_readRank(b));
          return rank != 0 ? rank : b.savedDate.compareTo(a.savedDate);
        });
    }
    return entries;
  }

  static int _readRank(BookmarkEntry entry) =>
      switch (entry.metadata.readState) {
        BookmarkReadState.unread => 0,
        BookmarkReadState.reading => 1,
        BookmarkReadState.read => 2,
      };

  BookmarkStats _buildStats() {
    final sites = <String, int>{};
    final tags = <String, int>{};
    var unread = 0;
    var starred = 0;
    var offline = 0;
    for (final entry in _all) {
      final host = entry.host;
      if (host != null) {
        sites[host] = (sites[host] ?? 0) + 1;
      }
      for (final tag in entry.metadata.tags) {
        tags[tag] = (tags[tag] ?? 0) + 1;
      }
      if (entry.metadata.readState != BookmarkReadState.read) {
        unread++;
      }
      if (entry.metadata.starred) {
        starred++;
      }
      if (entry.metadata.hasSnapshot) {
        offline++;
      }
    }
    return BookmarkStats(
      total: _all.length,
      unread: unread,
      starred: starred,
      offline: offline,
      sites: _facets(sites),
      tags: _facets(tags),
    );
  }

  static List<BookmarkFacet> _facets(Map<String, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [
      for (final entry in entries)
        BookmarkFacet(label: entry.key, count: entry.value),
    ];
  }

  // ------------------------------------------------------------ persistence

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, _persist);
  }

  /// Writes the state now rather than on the debounce, for a handover where
  /// another view is about to read it.
  void flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persist();
  }

  void _persist() => onPersist?.call(_state.toJson());

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    _persist();
    _fetcher.close();
    super.dispose();
  }
}
