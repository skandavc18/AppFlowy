import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';

import 'document_find_content.dart';

class DocumentFindAnchoredReference {
  DocumentFindAnchoredReference(this.node, this.reference)
      : path = List<int>.unmodifiable(node.path),
        sourceIdentity = documentFindSourceIdentity(node);

  final Node node;
  final Path path;
  final DocumentFindReference reference;
  final Object sourceIdentity;

  bool get isCurrent =>
      node.parent != null &&
      listEquals(path, node.path) &&
      sourceIdentity == documentFindSourceIdentity(node) &&
      documentFindReferences(node).contains(reference);

  @override
  bool operator ==(Object other) =>
      other is DocumentFindAnchoredReference &&
      identical(node, other.node) &&
      listEquals(path, other.path) &&
      sourceIdentity == other.sourceIdentity &&
      reference == other.reference;

  @override
  int get hashCode =>
      Object.hash(node, Object.hashAll(path), sourceIdentity, reference);
}

/// Only identity-bearing native source attributes, not arbitrary JSON or
/// presentation settings. Rebinding an existing node invalidates its old read.
Object documentFindSourceIdentity(Node node) =>
    node.type == 'file' || node.type == 'image'
        ? (
            node.type,
            node.attributes['url'],
            node.attributes['url_type'],
            node.attributes['image_type'],
            node.attributes['name'],
            node.attributes['workspace_file_id']
          )
        : node.type;

class DocumentFindExternalText {
  const DocumentFindExternalText(this.node, this.viewId, this.part);

  /// Always a real node in the owning document, never a reference's delta.
  final Node node;
  final String viewId;
  final DocumentFindText part;
}

/// A session-local index with a shared native scheduler. Superseded queries,
/// timeouts and disposal drop answers, never a still-occupied native slot.
/// There is no background workspace indexing and no cache survives disposal.
class DocumentFindReferenceIndex extends ChangeNotifier {
  DocumentFindReferenceIndex({
    required this.pageId,
    required this.provider,
    required this.isOwnerActive,
    this.limits = const DocumentFindLimits(),
  }) {
    provider.accessChanges?.addListener(invalidate);
    _subscription = provider.contentChanges?.listen((id) {
      if (id == pageId || _observedIds.contains(id)) invalidate();
    });
  }

  final String pageId;
  final DocumentFindReadProvider provider;
  final bool Function() isOwnerActive;
  final DocumentFindLimits limits;
  StreamSubscription<String>? _subscription;
  final _cache = <DocumentFindReference, _CachedReference>{};
  final _observedIds = <String>{};
  List<DocumentFindAnchoredReference> _roots = const [];
  List<DocumentFindExternalText> _texts = const [];
  int _generation = 0;
  Timer? _deadline;
  bool _disposed = false;
  bool _enabled = false;
  bool _loading = false;
  bool _truncated = false;
  bool _timedOut = false;
  int _unavailable = 0;
  int _coverageUnknown = 0;
  bool _started = false;
  bool _retried = false;
  bool _refinable = false;
  int _queryRevision = 0;
  int _readQueryRevision = 0;

  /// Prefix typing can refine this session's bounded, authorized source data.
  /// Unversioned files are never reused after completion.
  bool get canRefineQuery => _loading || (_refinable && !_timedOut);

  List<DocumentFindExternalText> get texts => _texts;
  bool get loading => _loading;
  bool get truncated => _truncated;
  bool get timedOut => _timedOut;
  int get unavailable => _unavailable;
  int get coverageUnknown => _coverageUnknown;

  void update(
    List<DocumentFindAnchoredReference> roots, {
    required bool enabled,
    bool force = false,
    int queryRevision = 0,
  }) {
    _queryRevision = queryRevision;
    if (_disposed ||
        (!force && enabled == _enabled && listEquals(roots, _roots))) {
      return;
    }
    _roots = List.unmodifiable(roots);
    _enabled = enabled;
    _retried = false;
    _restart();
  }

  /// Discard readable text immediately on a permission/content notification.
  /// The next scan must preflight again; cached text is never authorization.
  void invalidate() {
    if (_disposed) return;
    _cache.clear();
    _retried = false;
    _restart();
  }

  void _restart() {
    final generation = ++_generation;
    _readQueryRevision = _queryRevision;
    _refinable = false;
    _deadline?.cancel();
    provider.readScheduler.cancel(this);
    _texts = const [];
    _observedIds.clear();
    _unavailable = 0;
    _coverageUnknown = 0;
    _truncated = false;
    _timedOut = false;
    _started = false;
    _loading = _enabled && _roots.isNotEmpty && isOwnerActive();
    if (_loading) {
      _deadline = Timer(provider.deadline, () => _expire(generation));
      provider.readScheduler.schedule(
        this,
        () => _current(generation),
        () {
          _started = true;
          return _scan(generation);
        },
      );
    }
    notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed &&
      generation == _generation &&
      _enabled &&
      isOwnerActive() &&
      _roots.every((root) => root.isCurrent);

  void _expire(int generation) {
    if (_disposed || generation != _generation || !_loading) return;
    _generation++;
    provider.readScheduler.cancel(this);
    // Only local body/title results remain. Partially collected external text
    // has not passed the final owner gate and cannot be published on timeout.
    _texts = const [];
    _cache.clear();
    _loading = false;
    _timedOut = true;
    final retryGeneration = _generation;
    if ((!_started || _readQueryRevision != _queryRevision) && !_retried) {
      _retried = true;
      provider.readScheduler
          .whenAvailable(this, () => _current(retryGeneration), _restart);
    }
    notifyListeners();
  }

  Future<ViewPB?> _authorized(String id, int generation) async {
    if (!_current(generation)) return null;
    final value = await provider.readView(id);
    if (!_current(generation) || value == null || value.id != id) return null;
    final view = ViewPB.fromBuffer(value.writeToBuffer());
    final allowed = await provider.preflight(view);
    return _current(generation) && allowed ? view : null;
  }

  Future<void> _scan(int generation) async {
    var refinable = true;
    final texts = <DocumentFindExternalText>[];
    final visited = <(String, DocumentFindReference)>{
      (pageId, DocumentFindReference(pageId)),
    };
    final queue = Queue<(Node, DocumentFindReference, int, String, String)>();
    var unavailable = 0;
    var coverageUnknown = 0;
    var truncated = _roots.length > limits.maxViews;
    var bytes = 0;
    var full = false;
    bool add(Node node, String viewId, DocumentFindText part) {
      if (part.text.isEmpty) return true;
      if (looksSealed(part.text.trimLeft())) {
        unavailable++;
        return true;
      }
      final size = utf8.encode(part.text).length;
      if (texts.length >= limits.maxEntries || bytes + size > limits.maxBytes) {
        full = truncated = true;
        return false;
      }
      bytes += size;
      texts.add(DocumentFindExternalText(node, viewId, part));
      return true;
    }

    bool seen(DocumentFindReference reference, String viewId) =>
        visited.contains((viewId, reference)) ||
        (!reference.isLocalFile &&
            (viewId == pageId ||
                visited.contains((viewId, DocumentFindReference(viewId)))));

    try {
      if (await _authorized(pageId, generation) == null) {
        if (_current(generation)) unavailable++;
        return;
      }
      for (final root in _roots.take(limits.maxViews)) {
        queue.add((root.node, root.reference, 1, '', pageId));
      }
      var readViews = 0;
      while (queue.isNotEmpty && _current(generation)) {
        final (node, reference, depth, trail, sourceOwner) =
            queue.removeFirst();
        final viewId = reference.isLocalFile ? sourceOwner : reference.viewId;
        if (seen(reference, viewId)) {
          continue;
        }
        if (depth > limits.maxDepth || readViews >= limits.maxViews) {
          truncated = true;
          continue;
        }
        visited.add((viewId, reference));
        _observedIds.add(viewId);
        readViews++;
        try {
          final view = await _authorized(viewId, generation);
          if (!_current(generation)) return;
          if (view == null) {
            _cache.remove(reference);
            unavailable++;
            continue;
          }
          final cached = _cache[reference];
          final content = cached != null && cached.matches(view)
              ? cached.content
              : await provider.read(
                  view,
                  reference,
                  limits,
                  () => _current(generation),
                );
          if (!_current(generation)) return;
          // Access may have changed while native I/O was pending. No name or
          // snippet is published until both checks pass for the same view.
          final fresh = await _authorized(viewId, generation);
          if (!_current(generation)) return;
          if (fresh == null ||
              fresh.layout != view.layout ||
              fresh.name != view.name ||
              fresh.extra != view.extra ||
              fresh.lastEdited != view.lastEdited) {
            _cache.remove(reference);
            unavailable++;
            continue;
          }
          if (content.cacheable &&
              !content.unavailable &&
              !content.coverageUnknown &&
              !content.truncated) {
            _remember(reference, fresh, content);
          }
          if (content.unavailable) unavailable++;
          refinable = refinable && content.cacheable;
          if (content.coverageUnknown) coverageUnknown++;
          truncated = truncated || content.truncated;
          final rawName =
              reference.isLocalFile ? reference.fileName! : fresh.name;
          final name = looksSealed(rawName.trimLeft())
              ? 'Protected title'
              : rawName.isEmpty
                  ? 'Untitled page'
                  : rawName;
          final location = trail.isEmpty ? name : '$trail › $name';
          if (!reference.isLocalFile &&
              !add(
                node,
                fresh.id,
                DocumentFindText('title', fresh.name, '$location · Title'),
              )) {
            break;
          }
          for (final part in content.texts) {
            if (!add(
              node,
              fresh.id,
              DocumentFindText(
                part.id,
                part.text,
                '$location · ${part.location}',
              ),
            )) {
              break;
            }
          }
          if (full ||
              bytes >= limits.maxBytes ||
              texts.length >= limits.maxEntries) {
            truncated =
                truncated || queue.isNotEmpty || content.references.isNotEmpty;
            break;
          }
          for (final child in content.references) {
            if (seen(child, child.isLocalFile ? viewId : child.viewId)) {
              continue;
            }
            if (queue.length + readViews >= limits.maxViews) {
              truncated = true;
              break;
            }
            queue.add((node, child, depth + 1, location, viewId));
          }
        } on Object {
          if (!_current(generation)) return;
          _cache.remove(reference);
          unavailable++;
        }
      }
      // Revalidate the owner after all I/O as well (deleted/locked/switching).
      if (_current(generation) &&
          await _authorized(pageId, generation) == null) {
        texts.clear();
        _cache.clear();
        unavailable++;
      }
    } on Object {
      texts.clear();
      _cache.clear();
      unavailable++;
    } finally {
      if (_current(generation)) {
        _deadline?.cancel();
        _refinable = refinable;
        _texts = List.unmodifiable(texts);
        _unavailable = unavailable;
        _coverageUnknown = coverageUnknown;
        _truncated = truncated;
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _remember(
    DocumentFindReference reference,
    ViewPB view,
    DocumentFindContent content,
  ) {
    _cache.remove(reference);
    var bytes = content.byteCount;
    var entries = content.texts.length;
    for (final cached in _cache.values) {
      bytes += cached.content.byteCount;
      entries += cached.content.texts.length;
    }
    while (_cache.isNotEmpty &&
        (bytes > limits.maxBytes ||
            entries > limits.maxEntries ||
            _cache.length >= limits.maxViews)) {
      final oldest = _cache.remove(_cache.keys.first)!;
      bytes -= oldest.content.byteCount;
      entries -= oldest.content.texts.length;
    }
    if (bytes <= limits.maxBytes && entries <= limits.maxEntries) {
      _cache[reference] = _CachedReference(
        view.layout,
        view.extra,
        view.lastEdited.toString(),
        content,
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _deadline?.cancel();
    provider.readScheduler.cancel(this);
    _loading = false;
    _texts = const [];
    _cache.clear();
    _observedIds.clear();
    provider.accessChanges?.removeListener(invalidate);
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}

class _CachedReference {
  const _CachedReference(
    this.layout,
    this.extra,
    this.lastEdited,
    this.content,
  );
  final ViewLayoutPB layout;
  final String extra;
  final String lastEdited;
  final DocumentFindContent content;
  bool matches(ViewPB view) =>
      view.layout == layout &&
      view.extra == extra &&
      view.lastEdited.toString() == lastEdited;
}
