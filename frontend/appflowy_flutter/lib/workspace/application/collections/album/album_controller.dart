import 'dart:async';

import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_metadata.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:flutter/foundation.dart';

/// Owns an album's media, its order and everything it remembers.
class AlbumController extends ChangeNotifier {
  AlbumController({
    required Map<String, dynamic> initialState,
    required this.onPersist,
    AlbumMetadataCache? metadata,
    this.persistDebounce = const Duration(milliseconds: 900),
  })  : _state = AlbumState.fromJson(initialState),
        metadata = metadata ?? AlbumMetadataCache();

  final ValueChanged<Map<String, dynamic>> onPersist;
  final AlbumMetadataCache metadata;
  final Duration persistDebounce;

  AlbumState _state;
  List<AlbumMediaItem> _items = const [];
  List<AlbumMediaItem> _ordered = const [];
  Timer? _persistTimer;
  bool _disposed = false;
  bool _loadingAll = false;

  AlbumState get state => _state;
  AlbumSettings get settings => _state.settings;

  /// Every piece of media, in the album's own order.
  List<AlbumMediaItem> get items => _items;

  /// The media as the current sort arranges it.
  List<AlbumMediaItem> get ordered => _ordered;

  List<AlbumMediaItem> get visual =>
      [for (final item in _ordered) if (item.kind.isVisual) item];

  List<AlbumMediaItem> get playable =>
      [for (final item in _ordered) if (item.kind.plays) item];

  bool get isEmpty => _items.isEmpty;

  int get imageCount =>
      _items.where((item) => item.kind == AlbumMediaKind.image).length;
  int get videoCount =>
      _items.where((item) => item.kind == AlbumMediaKind.video).length;
  int get audioCount =>
      _items.where((item) => item.kind == AlbumMediaKind.audio).length;

  void setItems(List<AlbumMediaItem> items) {
    final sameOrder = _items.length == items.length &&
        !_items.indexed.any((entry) => entry.$2.id != items[entry.$1].id);
    _items = items;
    final pruned = _state.prunedTo([for (final item in items) item.id]);
    final changed = !identical(pruned, _state);
    _state = pruned;
    _reorder();
    if (changed) {
      _schedulePersist();
    }
    if (!sameOrder || changed) {
      _notify();
    }
  }

  /// The moment a picture was taken, falling back to when the file changed.
  DateTime? capturedAt(AlbumMediaItem item) =>
      metadata.peek(item.id)?.capturedAt ?? item.modifiedAt;

  AlbumMediaMetadata metadataFor(AlbumMediaItem item) =>
      metadata.peek(item.id) ?? AlbumMediaMetadata.pending;

  /// Reads the header of [item] if it has not been read yet, and rebuilds the
  /// order once a real capture date is known.
  Future<void> ensureMetadata(AlbumMediaItem item) async {
    if (metadata.peek(item.id) != null) {
      return;
    }
    await metadata.load(item);
    if (_disposed) {
      return;
    }
    _reorder();
    _notify();
  }

  /// Reads every header, so a date sort settles rather than shuffling as the
  /// wall scrolls.
  ///
  /// Batched: a thousand photographs read at once exhausts the file handles
  /// and stalls everything else the application is doing.
  Future<void> ensureAllMetadata({int batchSize = 8}) async {
    if (_items.isEmpty || _loadingAll) {
      return;
    }
    _loadingAll = true;
    _notify();
    try {
      for (var start = 0; start < _items.length; start += batchSize) {
        if (_disposed) {
          return;
        }
        final end = (start + batchSize).clamp(0, _items.length);
        await Future.wait(_items.sublist(start, end).map(metadata.load));
        if (_disposed) {
          return;
        }
        _reorder();
        _notify();
      }
    } finally {
      _loadingAll = false;
      if (!_disposed) {
        _reorder();
        _notify();
      }
    }
  }

  bool get isReadingMetadata => _loadingAll;

  List<AlbumGroup> groups() => groupAlbumMedia(
        _ordered,
        settings.grouping,
        capturedAt,
      );

  void _reorder() {
    final next = [..._items];
    switch (settings.sort) {
      case AlbumSort.albumOrder:
        break;
      case AlbumSort.name:
        next.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case AlbumSort.newestFirst:
      case AlbumSort.oldestFirst:
        final newest = settings.sort == AlbumSort.newestFirst;
        next.sort((a, b) {
          final left = capturedAt(a);
          final right = capturedAt(b);
          if (left == null && right == null) {
            return a.index.compareTo(b.index);
          }
          // Undated media sinks to the bottom whichever way time runs.
          if (left == null) {
            return 1;
          }
          if (right == null) {
            return -1;
          }
          final comparison = left.compareTo(right);
          return newest ? -comparison : comparison;
        });
    }
    _ordered = List.unmodifiable(next);
  }

  void updateSettings(AlbumSettings settings) {
    _state = _state.copyWith(settings: settings);
    _reorder();
    _schedulePersist();
    _notify();
  }

  void toggleFavourite(String id) {
    _state = _state.toggleFavourite(id);
    _schedulePersist();
    _notify();
  }

  void select(String? id) {
    if (_state.selectedId == id) {
      return;
    }
    _state = AlbumState(
      settings: _state.settings,
      favourites: _state.favourites,
      selectedId: id,
    );
    _schedulePersist();
    _notify();
  }

  /// The position of [id] among [ordered], or 0 when it is no longer there.
  int indexOf(String? id) {
    if (id == null) {
      return 0;
    }
    final index = _ordered.indexWhere((item) => item.id == id);
    return index < 0 ? 0 : index;
  }

  void _schedulePersist() {
    if (_disposed) {
      return;
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, flush);
  }

  void flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    onPersist(_state.toJson());
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _persistTimer = null;
    onPersist(_state.toJson());
    _disposed = true;
    super.dispose();
  }
}
