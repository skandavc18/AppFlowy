import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter/foundation.dart';

/// Device-local presentation only. These IDs are not written into workspace
/// objects, IconPBs, user profiles, or synced appearance settings.
enum DefaultIconStyle {
  monochrome,
  vivid;

  static DefaultIconStyle fromId(String? id) => switch (id) {
        'monochrome' => DefaultIconStyle.monochrome,
        _ => DefaultIconStyle.vivid,
      };
}

/// Symbolic failures only: storage exceptions can contain private paths/data.
enum DefaultIconStyleFailure { unavailable, load, save }

/// One device preference, with acknowledged (not optimistic) publication.
///
/// Reading [styles] is side-effect-free, including before dependency injection
/// is initialized. Startup explicitly awaits [ensureLoaded]; every mutation
/// also waits for that same read. Failed/early reads remain retryable. Writes
/// run in invocation order, and a failure never poisons the queue or announces
/// an unsaved selection to the UI.
class DefaultIconStyleStore extends ChangeNotifier {
  DefaultIconStyleStore({KeyValueStorage? Function()? resolveStorage})
      : _resolveStorage = resolveStorage ?? _registeredStorage;

  static final instance = DefaultIconStyleStore();
  static const storageKey = 'appflowy_default_icon_style';

  final KeyValueStorage? Function() _resolveStorage;
  final _styles = ValueNotifier(DefaultIconStyle.vivid);
  KeyValueStorage? _storage;
  Future<bool>? _loading;
  Future<void> _writeTail = Future<void>.value();
  bool _loaded = false;
  bool _disposed = false;
  bool _writeUncertain = false;
  int _pendingWrites = 0;
  DefaultIconStyleFailure? _failure;

  /// Only glyph leaves listen here; loading/saving feedback does not rebuild
  /// them, let alone the editor, router or workspace tree.
  ValueListenable<DefaultIconStyle> get styles => _styles;
  DefaultIconStyle get value => _styles.value;
  bool get isLoaded => _loaded;
  bool get isSaving => _pendingWrites != 0;
  DefaultIconStyleFailure? get failure => _failure;

  static KeyValueStorage? _registeredStorage() =>
      getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null;

  Future<bool> ensureLoaded() {
    if (_disposed) return Future.value(false);
    if (_loaded) return Future.value(true);
    final loading = _loading;
    if (loading != null) return loading;

    final future = _load();
    _loading = future;
    // _load always crosses an async boundary and handles its own failures.
    // In particular, an unavailable store must not latch a completed read.
    return future.whenComplete(() => _loading = null);
  }

  Future<bool> _load() async {
    // Resolve on a later microtask so even an unavailable/throwing resolver
    // cannot complete before ensureLoaded has recorded the pending read.
    await Future<void>.value();
    if (_disposed) return false;
    try {
      final storage = _resolveStorage();
      if (storage == null) {
        _failure = DefaultIconStyleFailure.unavailable;
        _notify();
        return false;
      }
      final raw = await storage.get(storageKey);
      if (_disposed) return false;
      _storage = storage;
      _loaded = true;
      _failure = null;
      _styles.value = DefaultIconStyle.fromId(raw);
      _notify();
      return true;
    } catch (_) {
      _failure = DefaultIconStyleFailure.load;
      _notify();
      return false;
    }
  }

  Future<bool> setStyle(DefaultIconStyle style) {
    if (_disposed) return Future.value(false);
    _pendingWrites++;
    final operation = _writeTail.then((_) => _write(style));
    // _write returns a result for every storage failure, so subsequent writes
    // still run. No view metadata is ever read or changed by this queue.
    _writeTail = operation.then<void>((_) {});
    _notify();
    return operation;
  }

  Future<bool> _write(DefaultIconStyle style) async {
    try {
      if (_disposed || !await ensureLoaded()) return false;
      _failure = null;
      if (style == value && !_writeUncertain) return true;

      _writeUncertain = true;
      final storage = _storage!;
      if (storage is DartKeyValue) {
        // DartKeyValue.set discards SharedPreferences' boolean acknowledgement.
        // Keep this stricter contract local to this preference: false is NOT
        // a successful save. The initial get has initialized this instance.
        final saved = await storage.sharedPreferences.setString(
          storageKey,
          style.name,
        );
        if (!saved) throw StateError('Default icon style was not saved');
      } else {
        await storage.set(storageKey, style.name);
      }
      _writeUncertain = false;
      if (!_disposed) _styles.value = style;
      return true;
    } catch (_) {
      // SharedPreferences mutates its cache before awaiting the platform.
      // Reload after a refusal/exception, without writing a compensating value
      // that could race a newer selection. Keep the last acknowledged style.
      final storage = _storage;
      if (storage is DartKeyValue) {
        try {
          await storage.sharedPreferences.reload();
        } catch (_) {
          // The next explicit selection still performs a real write, even if
          // it equals the last good value; a failed write is never deduped.
        }
      }
      _failure = DefaultIconStyleFailure.save;
      return false;
    } finally {
      _pendingWrites--;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _styles.dispose();
    super.dispose();
  }
}
