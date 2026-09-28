import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:flutter/foundation.dart';

import 'database_find_target.dart';

enum DatabaseFindStatus {
  idle,
  loading,
  ready,
  denied,
  failed,
  timedOut,
  changed,
}

class DatabaseFindMatch {
  const DatabaseFindMatch(this.part, this.range);

  final DocumentFindText part;
  final RegExpMatch range;

  DatabaseFindTarget? targetIn(String viewId) =>
      DatabaseFindTarget.parse(viewId, part.id);
}

/// A disposable, read-only search of ONE live database view. It neither owns a
/// DatabaseController nor changes filters, opens rows or follows references.
/// The injected boundary still uses the production typed-cell decoder/matcher.
class DatabaseFindSession extends ChangeNotifier {
  DatabaseFindSession({
    required this.viewId,
    required this.isOwnerActive,
    DocumentFindReadProvider? provider,
    this.limits = const DocumentFindLimits(maxDepth: 0, maxViews: 1),
    this.viewSnapshot,
  }) : provider = provider ?? DocumentFindReadProvider.native() {
    this.provider.accessChanges?.addListener(invalidate);
    // IDs here can identify views, fields, rows or workspace membership. Do
    // not mistake a notification ID for permission to read another database.
    _contentChanges = this.provider.contentChanges?.listen((_) => invalidate());
    if (provider == null) {
      _nativeChanges = databaseFindNativeChanges().listen((_) => invalidate());
    }
  }

  static const debounce = Duration(milliseconds: 180);

  final String viewId;
  final bool Function() isOwnerActive;
  final DocumentFindReadProvider provider;
  final DocumentFindLimits limits;
  final DatabaseFindViewSnapshot? Function()? viewSnapshot;
  StreamSubscription<String>? _contentChanges;
  StreamSubscription<String>? _nativeChanges;
  Timer? _debounce;
  Timer? _deadline;
  int _generation = 0;
  bool _disposed = false;
  String _query = '';
  FindOptions _options = const FindOptions();
  List<DatabaseFindMatch> _matches = const [];
  int _index = -1;
  DatabaseFindStatus _status = DatabaseFindStatus.idle;
  bool _truncated = false;
  bool _unavailable = false;
  bool _coverageUnknown = false;
  DocumentFindContent? _sourceContent;
  ViewPB? _sourceView;
  DatabaseFindViewSnapshot? _sourceSnapshot;
  bool _started = false;
  bool _retried = false;

  String get query => _query;
  FindOptions get options => _options;
  List<DatabaseFindMatch> get matches => _matches;
  int get currentMatch => _index + 1;
  DatabaseFindMatch? get current => _index < 0 ? null : _matches[_index];
  DatabaseFindStatus get status => _status;
  bool get loading => _status == DatabaseFindStatus.loading;
  bool get queryInvalid => !isFindQueryValid(_query, _options);
  bool get truncated => _truncated;
  bool get unavailable => _unavailable;
  bool get coverageUnknown => _coverageUnknown;

  void search(String query, FindOptions options) {
    if (_disposed || (query == _query && options == _options)) return;
    _query = query;
    _options = options;
    if (_query.isNotEmpty && !queryInvalid && isOwnerActive()) {
      if (_sourceContent != null && _sourceSnapshot == viewSnapshot?.call()) {
        _clear();
        _match(_sourceContent!, _sourceView!, _generation);
        return;
      }
    }
    invalidate();
  }

  /// Revoke old snippets synchronously, including during the debounce window.
  /// No source snapshot survives access/content invalidation, close or rebind.
  void invalidate() {
    if (_disposed) return;
    _sourceContent = null;
    _sourceView = null;
    _sourceSnapshot = null;
    _retried = false;
    _restart();
  }

  void _restart() {
    final generation = ++_generation;
    _started = false;
    _debounce?.cancel();
    _deadline?.cancel();
    provider.readScheduler.cancel(this);
    _clear();
    _status = _query.isNotEmpty && !queryInvalid && isOwnerActive()
        ? DatabaseFindStatus.loading
        : DatabaseFindStatus.idle;
    if (loading) {
      _debounce = Timer(debounce, () {
        if (!_current(generation)) return;
        _deadline = Timer(provider.deadline, () => _expire(generation));
        provider.readScheduler.schedule(
          this,
          () => _current(generation),
          () {
            _started = true;
            return _scan(generation);
          },
        );
      });
    }
    notifyListeners();
  }

  void navigate({bool forward = true}) {
    if (_disposed || _matches.isEmpty || !isOwnerActive()) return;
    _index = (_index + (forward ? 1 : -1)) % _matches.length;
    notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && isOwnerActive();

  Future<ViewPB?> _authorized(int generation) async {
    if (!_current(generation)) return null;
    final value = await provider.readView(viewId);
    if (!_current(generation) || value == null || value.id != viewId) {
      return null;
    }
    // Do not retain a mutable PB supplied by a listener or an injected reader.
    final view = ViewPB.fromBuffer(value.writeToBuffer());
    final allowed = await provider.preflight(view);
    return _current(generation) && allowed ? view : null;
  }

  Future<void> _scan(int generation) async {
    try {
      final snapshot = viewSnapshot?.call();
      if (snapshot != null && snapshot.viewId != viewId) {
        _finish(generation, DatabaseFindStatus.changed);
        return;
      }
      final before = await _authorized(generation);
      if (!_current(generation)) return;
      if (before == null || !_isDatabase(before)) {
        _finish(generation, DatabaseFindStatus.denied);
        return;
      }
      final content = await _scopedProvider(snapshot).read(
        before,
        DocumentFindReference(viewId),
        limits,
        () => _current(generation),
      );
      if (!_current(generation)) return;
      // read() intentionally does not authorize. Both checks are required,
      // including when the first one passed before an outstanding cell read.
      final after = await _authorized(generation);
      if (!_current(generation)) return;
      if (after == null || !_isDatabase(after)) {
        _finish(generation, DatabaseFindStatus.denied);
        return;
      }
      if (before.name != after.name ||
          before.layout != after.layout ||
          before.extra != after.extra ||
          before.lastEdited != after.lastEdited ||
          snapshot != viewSnapshot?.call()) {
        _finish(generation, DatabaseFindStatus.changed);
        return;
      }

      _sourceContent = content;
      _sourceView = after;
      _sourceSnapshot = snapshot;
      _match(content, after, generation);
    } on Object {
      // Native details can contain protected values; never echo them in UI.
      if (_current(generation)) {
        _clear();
        _finish(generation, DatabaseFindStatus.failed);
      }
    }
  }

  void _match(DocumentFindContent content, ViewPB after, int generation) {
    _truncated = content.truncated;
    _unavailable = content.unavailable || content.references.isNotEmpty;
    _coverageUnknown = content.coverageUnknown;
    final pattern = buildFindPattern(_query, _options);
    final matches = <DatabaseFindMatch>[];
    var bytes = 0;
    var entries = 0;
    for (final part in [
      DocumentFindText('title', after.name, 'Database title'),
      ...content.texts,
    ]) {
      if (part.text.isEmpty) continue;
      if (looksSealed(part.text.trimLeft())) {
        _unavailable = true;
        continue;
      }
      // Include the title in the SAME aggregate budget as the typed cells.
      if (part.text.length > limits.maxBytes ||
          ++entries > limits.maxEntries ||
          (bytes += utf8.encode(part.text).length) > limits.maxBytes) {
        _truncated = true;
        break;
      }
      if (pattern == null) continue;
      // Use the shared pattern semantics, but bound retained occurrences as
      // well as text entries (one long cell can contain thousands of hits).
      for (final range in pattern.allMatches(part.text)) {
        if (range.end == range.start) continue;
        if (matches.length == limits.maxEntries) {
          _truncated = true;
          break;
        }
        matches.add(DatabaseFindMatch(part, range));
      }
      if (matches.length == limits.maxEntries && _truncated) break;
    }
    if (!_current(generation)) return;
    _matches = List.unmodifiable(matches);
    _index = matches.isEmpty ? -1 : 0;
    _finish(generation, DatabaseFindStatus.ready);
  }

  /// Restrict the existing typed decoder BEFORE it reads any cell. Do not
  /// unhide a field, export a relation, or substitute another database's rows.
  DocumentFindReadProvider _scopedProvider(DatabaseFindViewSnapshot? snapshot) {
    if (snapshot == null) return provider;
    return DocumentFindReadProvider(
      readView: provider.readView,
      preflight: provider.preflight,
      readDocument: provider.readDocument,
      readCell: provider.readCell,
      readFields: (id, _) async {
        if (id != snapshot.viewId) return null;
        final fields = await provider.readFields(id, const []);
        if (fields == null) return null;
        final byId = {for (final field in fields) field.id: field};
        return [
          for (final id in snapshot.fieldIds)
            if (byId.containsKey(id)) byId[id]!,
        ];
      },
      readViewRows: (id) async {
        if (id != snapshot.viewId) return null;
        final rows = await provider.readViewRows(id);
        if (rows == null) return null;
        final byId = {for (final row in rows) row.id: row};
        return [
          for (final id in snapshot.rowIds)
            if (byId.containsKey(id)) byId[id]!,
        ];
      },
    );
  }

  static bool _isDatabase(ViewPB view) =>
      const [ViewLayoutPB.Grid, ViewLayoutPB.Board, ViewLayoutPB.Calendar]
          .contains(view.layout) &&
      view.workspaceItem == null &&
      !decodeViewExtra(view.extra)
          .containsKey(WorkspaceItemMetadata.envelopeKey);

  void _finish(int generation, DatabaseFindStatus status) {
    if (!_current(generation)) return;
    _deadline?.cancel();
    _status = status;
    notifyListeners();
  }

  void _expire(int generation) {
    if (_disposed || generation != _generation || !loading) return;
    ++_generation;
    provider.readScheduler.cancel(this);
    _clear();
    _status = DatabaseFindStatus.timedOut;
    final retryGeneration = _generation;
    if (!_retried && !_started) {
      _retried = true;
      provider.readScheduler
          .whenAvailable(this, () => _current(retryGeneration), _restart);
    }
    notifyListeners();
    // NEVER Future.timeout/race the read: the shared slot belongs to the
    // unfinished native operation even after the UI deadline/close/reopen.
  }

  void _clear() {
    _matches = const [];
    _index = -1;
    _truncated = false;
    _unavailable = false;
    _coverageUnknown = false;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _debounce?.cancel();
    _deadline?.cancel();
    provider.readScheduler.cancel(this);
    provider.accessChanges?.removeListener(invalidate);
    unawaited(_contentChanges?.cancel());
    unawaited(_nativeChanges?.cancel());
    _sourceContent = null;
    _sourceView = null;
    _sourceSnapshot = null;
    _clear();
    super.dispose();
  }
}

/// Supplement the document provider's notifications without changing that
/// shared provider. Cell events use row:field IDs, and membership/access events
/// can be workspace-scoped. Invalidate conservatively, but read only viewId.
Stream<String> databaseFindNativeChanges() =>
    RustStreamReceiver.shared.observable.stream.where((event) {
      if (event.source == 'Database') {
        return {
          DatabaseNotification.DidUpdateCell.value,
          DatabaseNotification.DidUpdateField.value,
          DatabaseNotification.DidUpdateFieldSettings.value,
          DatabaseNotification.DidUpdateRowMeta.value,
          DatabaseNotification.DidUpdateGroupRow.value,
          DatabaseNotification.DidUpdateSettings.value,
          DatabaseNotification.DidUpdateLayoutSettings.value,
          DatabaseNotification.DidUpdateDatabaseLayout.value,
          DatabaseNotification.DidDeleteDatabaseView.value,
          DatabaseNotification.DidMoveDatabaseViewToTrash.value,
          DatabaseNotification.DidUpdateDatabaseSyncUpdate.value,
        }.contains(event.ty);
      }
      return event.source == 'Folder' &&
          {
            FolderNotification.DidUpdateSharedUsers.value,
            FolderNotification.DidUpdateSharedViews.value,
            FolderNotification.DidUpdateSectionViews.value,
          }.contains(event.ty);
    }).map((event) => event.id);
