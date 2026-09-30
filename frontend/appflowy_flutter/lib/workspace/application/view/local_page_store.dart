import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// The places AppFlowy draws itself — Home, Recents, Favorites, Library — have
/// no folder view to keep a cover on. This keeps one per place on this device:
/// the same `extra` a real page stores (its cover and cover height) under a
/// plain id, so the ordinary cover actions and resize grip work unchanged.
class LocalPageStore {
  LocalPageStore({KeyValueStorage? storage, this.persist = true})
      : _storage = storage;

  /// Shared by every surface, so a cover changed in one tab shows in all.
  static final instance = LocalPageStore();

  static const _prefix = 'appflowy_local_page_';

  final KeyValueStorage? _storage;

  /// False keeps everything in memory, for isolated hosts and tests.
  final bool persist;
  final _extras = <String, String>{};
  final _reads = <String, Future<String>>{};
  final _listeners = <String, List<ValueChanged<String>>>{};

  KeyValueStorage? get _kv => !persist
      ? null
      : _storage ??
          (getIt.isRegistered<KeyValueStorage>()
              ? getIt<KeyValueStorage>()
              : null);

  /// What is known without waiting; null until the first read has finished.
  String? peek(String id) => _extras[id];

  Future<String> read(String id) {
    final known = _extras[id];
    if (known != null) return Future.value(known);
    return _reads[id] ??= _load(id);
  }

  Future<String> _load(String id) async {
    String? stored;
    try {
      stored = await _kv?.get('$_prefix$id');
    } catch (error) {
      Log.warn('A page cover could not be read: $error');
    }
    unawaited(_reads.remove(id));
    // A write made while this read was in flight is the newer one.
    final written = _extras[id];
    if (written != null) return written;
    final extra = stored ?? '';
    _extras[id] = extra;
    _notify(id, extra);
    return extra;
  }

  Future<void> write(String id, String extra) async {
    _extras[id] = extra;
    _notify(id, extra);
    await _kv?.set('$_prefix$id', extra);
  }

  VoidCallback listen(String id, ValueChanged<String> onChanged) {
    final listeners = _listeners.putIfAbsent(id, () => []);
    listeners.add(onChanged);
    return () {
      listeners.remove(onChanged);
      if (listeners.isEmpty && identical(_listeners[id], listeners)) {
        _listeners.remove(id);
      }
    };
  }

  void _notify(String id, String extra) {
    for (final listener in [...?_listeners[id]]) {
      listener(extra);
    }
  }

  /// The stand-in view the cover machinery reads and writes.
  static ViewPB viewFor(String id, [String extra = '']) =>
      ViewPB(id: id, layout: ViewLayoutPB.Document, extra: extra);
}

/// A stable id per place and workspace. A cloud workspace also files an
/// uploaded cover under it, so it stays plain: letters, digits and dashes.
String localPageId(String place, String? workspaceId) {
  final workspace = (workspaceId ?? '').trim();
  return workspace.isEmpty
      ? 'appflowy-page-$place'
      : 'appflowy-page-$place-$workspace';
}
