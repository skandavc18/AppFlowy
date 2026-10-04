import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

/// Bounds decoding and retained Dart data, not native bulk-response transfer.
/// No index, document bytes, file paths or snippets survive the modal.
@immutable
class WorkspaceContentSearchLimits {
  const WorkspaceContentSearchLimits({
    this.maxCachedViews = 4096,
    this.maxSnapshotBytes = 4 * 1024 * 1024,
    this.maxPages = 240,
    this.maxResults = 50,
    this.maxBytes = 2 * 1024 * 1024,
    this.page = const DocumentFindLimits(
      maxDepth: 0,
      maxViews: 1,
      maxEntries: 512,
      maxBytes: 64 * 1024,
    ),
  })  : assert(maxCachedViews > 0),
        assert(maxSnapshotBytes > 0),
        assert(maxPages > 0),
        assert(maxResults > 0),
        assert(maxBytes > 0);

  static const maxQueryLength = 256;
  static const maxSnippetLength = 320;
  static const maxAncestorDepth = 64;
  static const maxViewTextBytes = 256 * 1024;

  final int maxCachedViews;
  final int maxSnapshotBytes;
  final int maxPages;
  final int maxResults;
  final int maxBytes;
  final DocumentFindLimits page;
}

enum WorkspaceContentSearchStatus {
  idle,
  waitingForSource,
  debouncing,
  scanning,
  complete,
  partial,
  queryTooLong,
}

@immutable
class WorkspaceContentSearchResult {
  const WorkspaceContentSearchResult._({
    required this.view,
    required this.query,
    required this.snippet,
    required this.location,
  });

  /// A frozen, child-free PB, never the mutable cache's view.
  final ViewPB view;
  final String query;
  final String snippet;
  final String location;
}

@immutable
class WorkspaceContentSearchState {
  const WorkspaceContentSearchState._({
    this.query = '',
    this.status = WorkspaceContentSearchStatus.idle,
    this.results = const [],
    this.scannedPages = 0,
    this.candidatePages = 0,
    this.scannedBytes = 0,
    this.unavailablePages = 0,
    this.truncated = false,
    this.coverageUnknown = false,
    this.timedOut = false,
  });

  final String query;
  final WorkspaceContentSearchStatus status;
  final List<WorkspaceContentSearchResult> results;
  final int scannedPages;
  final int candidatePages;
  final int scannedBytes;
  final int unavailablePages;
  final bool truncated;
  final bool coverageUnknown;
  final bool timedOut;

  bool get isSearching =>
      status == WorkspaceContentSearchStatus.debouncing ||
      status == WorkspaceContentSearchStatus.scanning;
}

/// Searches ALL eligible supplied cached views, not the metadata search hits.
/// The host supplies workspace identity and refreshes its existing view cache;
/// this controller never discovers pages, mounts plugins or materializes files.
class WorkspaceContentSearchController extends ChangeNotifier {
  WorkspaceContentSearchController({
    required this.provider,
    this.limits = const WorkspaceContentSearchLimits(),
    this.debounce = const Duration(milliseconds: 300),
    this.isWorkspaceCurrent,
    this.onSourceInvalidated,
    Stream<String>? scopeChanges,
  }) {
    provider.accessChanges?.addListener(invalidate);
    _contentSubscription = provider.contentChanges?.listen(
      (_) => _sourceChanged(),
      onError: (Object _) => invalidate(),
    );
    _scopeSubscription = scopeChanges?.listen(
      (_) => _sourceChanged(),
      onError: (Object _) => invalidate(),
    );
  }

  factory WorkspaceContentSearchController.native({
    bool Function(String workspaceId)? isWorkspaceCurrent,
    VoidCallback? onSourceInvalidated,
  }) =>
      WorkspaceContentSearchController(
        provider: DocumentFindReadProvider.native(),
        isWorkspaceCurrent: isWorkspaceCurrent,
        onSourceInvalidated: onSourceInvalidated,
        // Includes shared-user/section/workspace membership changes, not only
        // the per-page updates observed by DocumentFindReadProvider.
        scopeChanges: RustStreamReceiver.shared.observable.stream
            .where((event) => event.source == 'Folder')
            .map((_) => ''),
      );

  final DocumentFindReadProvider provider;
  final WorkspaceContentSearchLimits limits;
  final Duration debounce;
  final bool Function(String workspaceId)? isWorkspaceCurrent;
  final VoidCallback? onSourceInvalidated;
  StreamSubscription<String>? _contentSubscription;
  StreamSubscription<String>? _scopeSubscription;
  Timer? _debounceTimer;
  Timer? _deadline;
  Timer? _betweenPages;
  Map<String, ViewPB> _views = const {};
  Set<String> _excluded = const {};
  String _workspaceId = '';
  String _query = '';
  Int64? _currentUserId;
  CommandPaletteFilter _filter = const CommandPaletteFilter();
  bool _sourceReady = false;
  bool _sourceTruncated = false;
  bool _rootWasSupplied = false;
  int _invalidViews = 0;
  bool _enabled = false;
  bool _disposed = false;
  int _generation = 0;
  _ContentSearchRun? _activeRun;
  WorkspaceContentSearchState _state = const WorkspaceContentSearchState._();

  WorkspaceContentSearchState get state => _state;

  /// Snapshot only identity/metadata fields. Never recurse through childViews
  /// (they can be huge or cyclic), mutate, or freeze a caller's protobuf.
  void updateSource({
    required String workspaceId,
    required Map<String, ViewPB> cachedViews,
    Iterable<String> excludedViewIds = const [],
    Int64? currentUserId,
    bool ready = true,
  }) {
    if (_disposed) return;
    final views = <String, ViewPB>{};
    final rejected = <String>{};
    var bytes = 0;
    var invalid = 0;
    var truncated = cachedViews.length > limits.maxCachedViews;
    for (final entry in cachedViews.entries.take(limits.maxCachedViews)) {
      final view = _snapshot(entry.value);
      if (entry.key != entry.value.id || view == null) {
        invalid++;
        rejected.add(entry.key);
        rejected.add(entry.value.id);
        continue;
      }
      bytes += view.writeToBuffer().length;
      if (bytes > limits.maxSnapshotBytes) {
        truncated = true;
        break;
      }
      views[entry.key] = view;
    }
    final exclusions = excludedViewIds.take(limits.maxCachedViews + 1).toList();
    final excluded = exclusions.toSet()..addAll(rejected);
    // Never drop an exclusion to fit a budget and then read that page.
    final exclusionsFit = exclusions.length <= limits.maxCachedViews;
    final sourceReady = ready && exclusionsFit;
    final rootWasSupplied = cachedViews.containsKey(workspaceId);
    if (_workspaceId == workspaceId &&
        _currentUserId == currentUserId &&
        _sourceReady == sourceReady &&
        _sourceTruncated == truncated &&
        _rootWasSupplied == rootWasSupplied &&
        _invalidViews == invalid &&
        mapEquals(views, _views) &&
        setEquals(excluded, _excluded)) {
      return;
    }
    _workspaceId = workspaceId;
    _currentUserId = currentUserId;
    _views = Map.unmodifiable(views);
    _excluded = Set.unmodifiable(excluded);
    _sourceReady = sourceReady;
    _sourceTruncated = truncated;
    _rootWasSupplied = rootWasSupplied;
    _invalidViews = invalid;
    _restart();
  }

  void search(
    String query, {
    required bool enabled,
    CommandPaletteFilter filter = const CommandPaletteFilter(),
  }) {
    if (_disposed) return;
    final active = enabled && !filter.titleOnly;
    if (_query == query && _enabled == active && _sameFilter(filter, _filter)) {
      return;
    }
    _query = query;
    _enabled = active;
    _filter = filter;
    _restart();
  }

  /// Permission changes clear ALL snippets synchronously, including completed
  /// results. Every rescan must authorize again; no text cache is retained.
  void invalidate() {
    if (!_disposed) _restart();
  }

  void _sourceChanged() {
    if (_disposed) return;
    invalidate();
    if (_enabled) onSourceInvalidated?.call();
  }

  void stop() {
    if (_disposed) return;
    _enabled = false;
    _restart();
  }

  /// A deferred click/open must not use an item removed by a newer query,
  /// permission notification or workspace switch before the next frame.
  bool canUseResult(String id, String query) =>
      !_disposed &&
      _enabled &&
      _query == query &&
      _workspaceIsCurrent &&
      _state.results.any((result) => result.view.id == id);

  bool get _workspaceIsCurrent =>
      _workspaceId.isNotEmpty &&
      (isWorkspaceCurrent?.call(_workspaceId) ?? true);

  void _cancelPending() {
    _generation++;
    _debounceTimer?.cancel();
    _deadline?.cancel();
    _betweenPages?.cancel();
    provider.readScheduler.cancel(this);
    _activeRun?.results.clear();
    _activeRun = null;
  }

  void _restart() {
    _cancelPending();
    final query = _query.trim();
    final status = !_enabled || query.isEmpty || query.startsWith('>')
        ? WorkspaceContentSearchStatus.idle
        : query.length > WorkspaceContentSearchLimits.maxQueryLength
            ? WorkspaceContentSearchStatus.queryTooLong
            : !_sourceReady || !_workspaceIsCurrent
                ? WorkspaceContentSearchStatus.waitingForSource
                : WorkspaceContentSearchStatus.debouncing;
    _state = WorkspaceContentSearchState._(query: _query, status: status);
    final generation = _generation;
    if (status == WorkspaceContentSearchStatus.debouncing) {
      _debounceTimer = Timer(debounce, () => _start(generation));
    }
    notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed &&
      _enabled &&
      generation == _generation &&
      _workspaceIsCurrent;

  void _start(int generation) {
    if (!_current(generation)) return;
    final candidates = <ViewPB>[];
    var unavailable = _invalidViews;
    for (final view in _views.values) {
      if (view.id == _workspaceId ||
          !_filter.matchesRecentView(
            view: view,
            cachedViews: _views,
            currentUserId: _currentUserId,
          )) {
        continue;
      }
      if (!_inWorkspace(view)) {
        unavailable++;
        continue;
      }
      final extra = decodeViewExtra(view.extra);
      if (view.isWorkspaceFolder || extra['is_space'] == true) continue;
      if (!_supported(view, extra)) {
        unavailable++;
        continue;
      }
      candidates.add(view);
    }
    final run = _ContentSearchRun(
      generation: generation,
      query: _query,
      pattern: buildFindPattern(_query.trim(), const FindOptions())!,
      candidates: List.unmodifiable(candidates.take(limits.maxPages)),
      candidateCount: candidates.length,
      unavailable: unavailable,
      truncated: _sourceTruncated || candidates.length > limits.maxPages,
    );
    _activeRun = run;
    _publish(run, scanning: true);
    _queueNext(run);
  }

  bool _inWorkspace(ViewPB view) {
    var cursor = view;
    final visited = <String>{};
    while (visited.length < WorkspaceContentSearchLimits.maxAncestorDepth &&
        visited.add(cursor.id)) {
      // Every cursor is already a validated, frozen snapshot. Re-decoding a
      // large ancestor's extra for each descendant would multiply scan work.
      if (_excluded.contains(cursor.id)) return false;
      if (cursor.id == _workspaceId) return true;
      final parent = cursor.parentViewId;
      if (_excluded.contains(parent)) return false;
      // getAllViews need not include the synthetic workspace root.
      if (parent == _workspaceId && !_rootWasSupplied) return true;
      final next = _views[parent];
      if (next == null) return false;
      cursor = next;
    }
    return false;
  }

  void _queueNext(_ContentSearchRun run) {
    if (!_current(run.generation)) return;
    if (run.next >= run.candidates.length ||
        run.results.length >= limits.maxResults ||
        run.bytes >= limits.maxBytes) {
      run.truncated = run.truncated || run.next < run.candidates.length;
      _publish(run, scanning: false);
      return;
    }
    final expected = run.candidates[run.next++];
    // Includes time waiting for the shared slot. Expiration drops this owner's
    // queued work, but NEVER races/completes the scheduler's native future.
    _deadline = Timer(provider.deadline, () {
      if (!_current(run.generation)) return;
      _publish(run, scanning: false, timedOut: true);
      // A listener may have started a newer query during publication.
      if (_current(run.generation)) _cancelPending();
    });
    provider.readScheduler.schedule(
      this,
      () => _current(run.generation),
      () async {
        try {
          await _readPage(run, expected);
        } on Object {
          // Native errors can contain page text/paths; never log or display them.
          if (_current(run.generation)) run.unavailable++;
        } finally {
          if (_current(run.generation)) {
            _deadline?.cancel();
            run.scanned++;
            _publish(run, scanning: true);
            // Yield between pages: another owner, close or a newly typed query
            // gets an event-loop turn before this scan requests another slot.
            if (_current(run.generation)) {
              _betweenPages = Timer(Duration.zero, () => _queueNext(run));
            }
          }
        }
      },
    );
  }

  Future<ViewPB?> _authorized(ViewPB expected, int generation) async {
    if (!_current(generation)) return null;
    final value = await provider.readView(expected.id);
    if (!_current(generation) || value == null || value.id != expected.id) {
      return null;
    }
    final view = _snapshot(value);
    if (view == null || view != expected || !_inWorkspace(view)) return null;
    final allowed = await provider.preflight(view);
    return _current(generation) && allowed ? view : null;
  }

  Future<void> _readPage(_ContentSearchRun run, ViewPB expected) async {
    final view = await _authorized(expected, run.generation);
    if (!_current(run.generation)) return;
    if (view == null) {
      run.unavailable++;
      return;
    }
    final page = limits.page;
    final content = await provider.read(
      view,
      DocumentFindReference(view.id),
      DocumentFindLimits(
        maxDepth: 0,
        maxViews: 1,
        maxEntries: page.maxEntries,
        maxBytes: math.min(page.maxBytes, limits.maxBytes - run.bytes),
        maxSourceBytes: page.maxSourceBytes,
      ),
      () => _current(run.generation),
    );
    if (!_current(run.generation)) return;
    final fresh = await _authorized(view, run.generation);
    if (!_current(run.generation)) return;
    if (fresh == null) {
      run.unavailable++;
      return;
    }
    if (content.unavailable) run.unavailable++;
    run.truncated = run.truncated || content.truncated;
    // References are not followed: targets must be supplied independently by
    // the workspace cache. In particular, an embed URL never authorizes a read.
    run.coverageUnknown = run.coverageUnknown ||
        content.coverageUnknown ||
        content.references.isNotEmpty;
    WorkspaceContentSearchResult? hit;
    var pageBytes = 0;
    for (final part in content.texts.take(page.maxEntries)) {
      if (part.text.length > page.maxBytes) {
        run.truncated = true;
        break;
      }
      final bytes = utf8.encode(part.text).length;
      if (pageBytes + bytes > page.maxBytes ||
          run.bytes + bytes > limits.maxBytes) {
        run.truncated = true;
        break;
      }
      pageBytes += bytes;
      run.bytes += bytes;
      if (looksSealed(part.text.trimLeft())) {
        run.coverageUnknown = true;
        continue;
      }
      if (hit != null) continue;
      final match = run.pattern.firstMatch(part.text);
      if (match == null) continue;
      hit = WorkspaceContentSearchResult._(
        view: fresh,
        query: run.query,
        snippet: _excerpt(part.text, match),
        location: part.location.length > 120
            ? '${part.location.substring(0, 120)}…'
            : part.location,
      );
    }
    run.truncated = run.truncated || content.texts.length > page.maxEntries;
    if (hit != null) run.results.add(hit);
  }

  void _publish(
    _ContentSearchRun run, {
    required bool scanning,
    bool timedOut = false,
  }) {
    if (!_current(run.generation)) return;
    final partial =
        timedOut || run.truncated || run.coverageUnknown || run.unavailable > 0;
    _state = WorkspaceContentSearchState._(
      query: run.query,
      status: scanning
          ? WorkspaceContentSearchStatus.scanning
          : partial
              ? WorkspaceContentSearchStatus.partial
              : WorkspaceContentSearchStatus.complete,
      results: List.unmodifiable(run.results),
      scannedPages: run.scanned,
      candidatePages: run.candidateCount,
      scannedBytes: run.bytes,
      unavailablePages: run.unavailable,
      truncated: run.truncated,
      coverageUnknown: run.coverageUnknown,
      timedOut: timedOut,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelPending();
    _views = const {};
    _excluded = const {};
    _query = '';
    _state = const WorkspaceContentSearchState._();
    provider.accessChanges?.removeListener(invalidate);
    unawaited(_contentSubscription?.cancel());
    unawaited(_scopeSubscription?.cancel());
    super.dispose();
  }
}

class _ContentSearchRun {
  _ContentSearchRun({
    required this.generation,
    required this.query,
    required this.pattern,
    required this.candidates,
    required this.candidateCount,
    required this.unavailable,
    required this.truncated,
  });

  final int generation;
  final String query;
  final RegExp pattern;
  final List<ViewPB> candidates;
  final int candidateCount;
  final results = <WorkspaceContentSearchResult>[];
  int next = 0;
  int scanned = 0;
  int bytes = 0;
  int unavailable;
  bool truncated;
  bool coverageUnknown = false;
}

bool _sameFilter(CommandPaletteFilter a, CommandPaletteFilter b) =>
    a.titleOnly == b.titleOnly &&
    a.createdByMe == b.createdByMe &&
    a.spaceId == b.spaceId &&
    a.pageType == b.pageType;

bool _safeMetadata(ViewPB view) {
  try {
    final extra =
        view.extra.isEmpty ? <String, dynamic>{} : jsonDecode(view.extra);
    if (extra is! Map ||
        extra.containsKey('appflowy_encryption') ||
        extra.containsKey('appflowy_encrypted_columns')) {
      return false;
    }
    if (extra.containsKey(WorkspaceItemMetadata.envelopeKey) &&
        view.workspaceItem == null) {
      return false;
    }
    return !looksSealed(view.name.trimLeft());
  } on Object {
    return false;
  }
}

bool _supported(ViewPB view, Map<String, dynamic> extra) =>
    !extra.containsKey('appflowy_dashboard') &&
    !extra.containsKey('appflowy_canvas') &&
    !extra.containsKey('appflowy_collection_source') &&
    const [
      ViewLayoutPB.Document,
      ViewLayoutPB.Grid,
      ViewLayoutPB.Board,
      ViewLayoutPB.Calendar,
    ].contains(view.layout);

final _invalidViewIdCharacter = RegExp('[^a-zA-Z0-9_-]');

bool _safeViewId(String id) =>
    id.isNotEmpty && id.length <= 128 && !_invalidViewIdCharacter.hasMatch(id);

ViewPB? _snapshot(ViewPB view) {
  final edited = view.lastEdited.toInt();
  if (!_safeViewId(view.id) ||
      (view.parentViewId.isNotEmpty && !_safeViewId(view.parentViewId)) ||
      edited < -8640000000000 ||
      edited > 8640000000000 ||
      view.extra.length > WorkspaceContentSearchLimits.maxViewTextBytes ||
      view.name.length > 16 * 1024 ||
      view.icon.value.length > 16 * 1024 ||
      utf8.encode(view.extra).length >
          WorkspaceContentSearchLimits.maxViewTextBytes ||
      !_safeMetadata(view)) {
    return null;
  }
  return ViewPB(
    id: view.id,
    parentViewId: view.parentViewId,
    name: view.name,
    createTime: view.createTime,
    layout: view.layout,
    icon: view.hasIcon()
        ? ViewIconPB(ty: view.icon.ty, value: view.icon.value)
        : null,
    isFavorite: view.isFavorite,
    extra: view.extra,
    createdBy: view.hasCreatedBy() ? view.createdBy : null,
    lastEdited: view.lastEdited,
    lastEditedBy: view.hasLastEditedBy() ? view.lastEditedBy : null,
    isLocked: view.hasIsLocked() ? view.isLocked : null,
  )..freeze();
}

/// Literal, case-insensitive context, preserving the original text and case.
/// Regex-looking queries are words, not executable regular expressions.
String? workspaceContentSearchExcerpt(String text, String query) {
  final needle = query.trim();
  if (needle.isEmpty ||
      needle.length > WorkspaceContentSearchLimits.maxQueryLength) {
    return null;
  }
  final match = buildFindPattern(needle, const FindOptions())!.firstMatch(text);
  return match == null ? null : _excerpt(text, match);
}

String _excerpt(String text, RegExpMatch match) {
  const width = WorkspaceContentSearchLimits.maxSnippetLength;
  final before = math.min(80, (width - (match.end - match.start)) ~/ 2);
  var start = math.max(0, match.start - before);
  var end = math.min(text.length, start + width);
  // Don't split UTF-16 surrogate pairs at either clipping edge.
  if (start > 0 && _lowSurrogate(text.codeUnitAt(start))) start--;
  if (end < text.length && _lowSurrogate(text.codeUnitAt(end))) end++;
  return '${start > 0 ? '…' : ''}${text.substring(start, end)}'
      '${end < text.length ? '…' : ''}';
}

bool _lowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

/// Modal-local title index. Unlike body scanning, this considers every cached
/// workspace view. Only the published result count is capped, AFTER ranking,
/// path filters and authorization. No document, file or database reads occur.
class WorkspaceTitleSearchController extends ChangeNotifier {
  WorkspaceTitleSearchController({
    required this.provider,
    required this.isWorkspaceCurrent,
    this.onSourceInvalidated,
    Stream<String>? scopeChanges,
  }) {
    provider.accessChanges?.addListener(invalidate);
    _changes = provider.contentChanges?.listen(
      (_) => invalidate(),
      onError: (Object _) => invalidate(),
    );
    _scopeChanges = scopeChanges?.listen(
      (_) => invalidate(),
      onError: (Object _) => invalidate(),
    );
  }

  factory WorkspaceTitleSearchController.native({
    required bool Function(String) isWorkspaceCurrent,
    VoidCallback? onSourceInvalidated,
  }) =>
      WorkspaceTitleSearchController(
        provider: DocumentFindReadProvider.native(),
        isWorkspaceCurrent: isWorkspaceCurrent,
        onSourceInvalidated: onSourceInvalidated,
        scopeChanges: RustStreamReceiver.shared.observable.stream
            .where((event) => event.source == 'Folder')
            .map((_) => ''),
      );

  final DocumentFindReadProvider provider;
  final bool Function(String) isWorkspaceCurrent;
  final VoidCallback? onSourceInvalidated;
  StreamSubscription<String>? _changes;
  StreamSubscription<String>? _scopeChanges;
  Timer? _deadline;
  Map<String, ViewPB> _views = const {};
  Set<String> _excluded = const {};
  final _readable = <String>{};
  Map<String, SearchResultItem> _backend = const {};
  String _workspace = '';
  String _query = '';
  Int64? _user;
  CommandPaletteFilter _filter = const CommandPaletteFilter();
  bool _ready = false;
  bool _enabled = false;
  bool _disposed = false;
  int _generation = 0;
  List<SearchResultItem> _results = const [];
  Map<String, ViewPB> _publishedViews = const {};

  List<SearchResultItem> get results => _results;
  Map<String, ViewPB> get views => _publishedViews;
  bool searching = false;
  bool timedOut = false;

  void updateSource({
    required String workspaceId,
    required Map<String, ViewPB> cachedViews,
    required Iterable<String> excludedViewIds,
    Int64? currentUserId,
    required bool ready,
  }) {
    if (_disposed) return;
    final views = <String, ViewPB>{};
    final excluded = excludedViewIds.toSet();
    for (final entry in cachedViews.entries) {
      final view = _snapshot(entry.value);
      if (view == null || entry.key != view.id) {
        excluded.addAll([entry.key, entry.value.id]);
      } else {
        views[entry.key] = view;
      }
    }
    if (_workspace == workspaceId &&
        _user == currentUserId &&
        _ready == ready &&
        mapEquals(views, _views) &&
        setEquals(excluded, _excluded)) {
      return;
    }
    _workspace = workspaceId;
    _user = currentUserId;
    _ready = ready;
    _views = views;
    _excluded = excluded;
    _readable.clear();
    _restart();
  }

  void search(
    String query,
    CommandPaletteFilter filter,
    Iterable<SearchResultItem> backend,
  ) {
    if (_disposed) return;
    final items = {for (final item in backend) item.id: item};
    if (_enabled &&
        _query == query &&
        _sameFilter(_filter, filter) &&
        _filter.pageContents == filter.pageContents &&
        mapEquals(_backend, items)) {
      return;
    }
    _query = query;
    _enabled = true;
    _filter = filter;
    _backend = items;
    _restart();
  }

  void invalidate() {
    if (_disposed) return;
    _readable.clear();
    // Membership notifications require a new trusted workspace snapshot.
    // In particular, do not re-authorize against a stale parent path.
    _ready = false;
    _restart();
    if (_enabled) onSourceInvalidated?.call();
  }

  bool canUseResult(String id, String query) =>
      !_disposed &&
      _ready &&
      _query == query &&
      isWorkspaceCurrent(_workspace) &&
      _results.any((item) => item.id == id);

  List<ViewPB>? _path(ViewPB view) {
    final path = <ViewPB>[];
    final visited = <String>{};
    var cursor = view;
    while (visited.length < WorkspaceContentSearchLimits.maxAncestorDepth &&
        visited.add(cursor.id)) {
      if (_excluded.contains(cursor.id)) return null;
      path.add(cursor);
      if (cursor.id == _workspace) return path;
      if (_excluded.contains(cursor.parentViewId)) return null;
      if (cursor.parentViewId == _workspace &&
          !_views.containsKey(_workspace)) {
        return path;
      }
      final parent = _views[cursor.parentViewId];
      if (parent == null) return null;
      cursor = parent;
    }
    return null;
  }

  void stop() {
    _enabled = false;
    _readable.clear();
    _cancelRun();
  }

  void _cancelRun() {
    _generation++;
    _deadline?.cancel();
    provider.readScheduler.cancel(this);
    _results = const [];
    _publishedViews = const {};
    searching = false;
  }

  void _restart({bool retry = false}) {
    _cancelRun();
    timedOut = false;
    final generation = _generation;
    final query = normalizePaletteQuery(_query);
    final candidates = <(ViewPB, int)>[];
    if (_enabled &&
        _ready &&
        isWorkspaceCurrent(_workspace) &&
        !_filter.pageContents &&
        query.isNotEmpty &&
        query.length <= WorkspaceContentSearchLimits.maxQueryLength &&
        !query.startsWith('>')) {
      for (final view in _views.values) {
        final backend = _backendFor(view.id);
        final rank = paletteTitleRank(view.name, query);
        if (rank == null && (backend == null || _filter.titleOnly)) continue;
        if (_path(view) == null ||
            !_filter.matchesRecentView(
              view: view,
              cachedViews: _views,
              currentUserId: _user,
            )) {
          continue;
        }
        candidates.add((view, rank ?? 5));
      }
      candidates.sort((a, b) {
        final rank = a.$2.compareTo(b.$2);
        if (rank != 0) return rank;
        final name = normalizePaletteQuery(a.$1.name)
            .compareTo(normalizePaletteQuery(b.$1.name));
        return name != 0 ? name : a.$1.id.compareTo(b.$1.id);
      });
    }
    searching = candidates.isNotEmpty;
    notifyListeners();
    if (candidates.isNotEmpty) {
      var started = false;
      _deadline = Timer(provider.deadline, () {
        if (!_current(generation)) return;
        _generation++;
        provider.readScheduler.cancel(this);
        searching = false;
        timedOut = true;
        final retryGeneration = _generation;
        if (!started && !retry) {
          provider.readScheduler.whenAvailable(
            this,
            () => _current(retryGeneration),
            () => _restart(retry: true),
          );
        }
        notifyListeners();
      });
      provider.readScheduler.schedule(
        this,
        () => _current(generation),
        () {
          started = true;
          return _resolve(candidates, generation);
        },
      );
    }
  }

  bool _current(int generation) =>
      !_disposed &&
      _enabled &&
      generation == _generation &&
      _ready &&
      isWorkspaceCurrent(_workspace);

  SearchResultItem? _backendFor(String id) {
    final item = _backend[id];
    return item?.workspaceId?.isNotEmpty == true &&
            item!.workspaceId != _workspace
        ? null
        : item;
  }

  Future<void> _resolve(List<(ViewPB, int)> candidates, int generation) async {
    final hits = <SearchResultItem>[];
    final published = <String, ViewPB>{};
    for (final (expected, _) in candidates) {
      if (!_current(generation)) return;
      if (!_readable.contains(expected.id)) {
        try {
          final native = await provider.readView(expected.id);
          if (!_current(generation)) return;
          final fresh = native == null ? null : _snapshot(native);
          if (fresh != expected || fresh == null) continue;
          final allowed = await provider.preflight(fresh);
          if (!_current(generation)) return;
          if (!allowed) continue;
          _readable.add(expected.id);
        } on Object {
          if (!_current(generation)) return;
          continue;
        }
      }
      final path = _path(expected);
      if (path == null) continue;
      for (final view in path) {
        published[view.id] = view;
      }
      final backend = _backendFor(expected.id);
      hits.add(
        SearchResultItem(
          id: expected.id,
          icon: backend?.icon ?? ResultIconPB(),
          displayName: expected.name,
          content: backend?.content ?? '',
          workspaceId: _workspace,
        ),
      );
      _results = List.unmodifiable(hits);
      _publishedViews = Map.unmodifiable(published);
      notifyListeners();
      if (!_current(generation)) return;
      if (hits.length == 50) break;
    }
    if (!_current(generation)) return;
    _deadline?.cancel();
    searching = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _readable.clear();
    _views = const {};
    _backend = const {};
    provider.accessChanges?.removeListener(invalidate);
    unawaited(_changes?.cancel());
    unawaited(_scopeChanges?.cancel());
    super.dispose();
  }
}
