import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One value an action produced.
@immutable
class ExtensionDataEntry {
  const ExtensionDataEntry({
    required this.value,
    required this.writtenAt,
    this.staleAfter,
  });

  final Object? value;
  final DateTime writtenAt;

  /// How long the value is worth showing without a warning. Null means for
  /// ever — a watchlist does not go off, a share price does.
  final Duration? staleAfter;

  bool isStale(DateTime now) {
    final window = staleAfter;
    return window != null && now.difference(writtenAt) > window;
  }

  Map<String, Object?> toJson() => {
        'value': value,
        'at': writtenAt.toIso8601String(),
        if (staleAfter != null) 'staleAfter': staleAfter!.inSeconds,
      };

  static ExtensionDataEntry? fromJson(Map<String, Object?> values) {
    final writtenAt = DateTime.tryParse((values['at'] as String?) ?? '');
    if (writtenAt == null) {
      return null;
    }
    final seconds = values['staleAfter'];
    return ExtensionDataEntry(
      value: values['value'],
      writtenAt: writtenAt,
      staleAfter:
          seconds is int && seconds > 0 ? Duration(seconds: seconds) : null,
    );
  }
}

/// The reactive store an action writes and a block reads.
///
/// ⚠️⚠️ This is the default write target, NOT the document. An action that put
/// a share price into a block's attributes would add an undo entry, a collab
/// sync round and a page-version snapshot every time it ran, for ever. The
/// document holds WHICH ticker; this holds WHAT the price is.
///
/// Keys are qualified with the extension's id (`finance.quote.AAPL`), so two
/// extensions cannot tread on each other and a key names its owner.
class ExtensionDataStore extends ChangeNotifier {
  ExtensionDataStore({this.rootOverride});

  static final ExtensionDataStore instance = ExtensionDataStore();

  static const folderName = 'extension_data';
  static const fileName = 'values.json';

  /// Set in tests, where the application directories do not exist.
  @visibleForTesting
  final String? rootOverride;

  final Map<String, ExtensionDataEntry> _entries = {};
  final Map<String, ValueNotifier<Object?>> _listeners = {};
  final Set<String> _dirty = {};

  Timer? _persist;
  bool _loaded = false;
  Future<void>? _loading;
  String? _root;

  /// Bumped whenever anything changes, for a view that watches the lot.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool get isLoaded => _loaded;

  /// How long writes are gathered before they reach the disk. A poller writing
  /// every few seconds must not cost a file write every few seconds.
  static const persistDebounce = Duration(seconds: 3);

  static String qualify(String extensionId, String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return extensionId;
    }
    return trimmed.startsWith('$extensionId.')
        ? trimmed
        : '$extensionId.$trimmed';
  }

  Future<String> resolveRoot() async {
    final override = rootOverride;
    if (override != null) {
      return override;
    }
    final cached = _root;
    if (cached != null) {
      return cached;
    }
    String base;
    try {
      base = await getIt<ApplicationDataStorage>().getPath();
    } on Object catch (_) {
      base = (await getApplicationSupportDirectory()).path;
    }
    final root = p.join(base, folderName);
    await Directory(root).create(recursive: true);
    return _root = root;
  }

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final root = Directory(await resolveRoot());
      if (!root.existsSync()) {
        _loaded = true;
        return;
      }
      await for (final entity in root.list()) {
        if (entity is! Directory) {
          continue;
        }
        final file = File(p.join(entity.path, fileName));
        if (!file.existsSync()) {
          continue;
        }
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          continue;
        }
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is! Map) {
            continue;
          }
          final parsed =
              ExtensionDataEntry.fromJson(Map<String, Object?>.from(value));
          if (parsed != null) {
            _entries['${entry.key}'] = parsed;
          }
        }
      }
      _loaded = true;
    } on Object catch (error) {
      // A store that could not be read is read again next time, never latched
      // as empty — that mistake has cost this codebase a whole session before.
      Log.warn('Extension data could not be read: $error');
    } finally {
      _loading = null;
    }
    if (_loaded) {
      _raise();
    }
  }

  Object? read(String key) => _entries[key]?.value;

  ExtensionDataEntry? entryFor(String key) => _entries[key];

  /// Every key under `<prefix>.`, plus the prefix itself when it holds a value.
  List<String> keysUnder(String prefix) => [
        for (final key in _entries.keys)
          if (key == prefix || key.startsWith('$prefix.')) key,
      ]..sort();

  List<String> allKeys() => _entries.keys.toList()..sort();

  /// A notifier for one key, so a card rebuilds without watching the store.
  ValueListenable<Object?> listenable(String key) =>
      _listeners.putIfAbsent(key, () => ValueNotifier<Object?>(read(key)));

  Future<void> write(
    String key,
    Object? value, {
    Duration? staleAfter,
  }) async {
    await ensureLoaded();
    _entries[key] = ExtensionDataEntry(
      value: value,
      writtenAt: DateTime.now(),
      staleAfter: staleAfter,
    );
    _listeners[key]?.value = value;
    _dirty.add(_ownerOf(key));
    _schedulePersist();
    _raise();
  }

  Future<void> remove(String key) async {
    await ensureLoaded();
    if (_entries.remove(key) == null) {
      return;
    }
    _listeners[key]?.value = null;
    _dirty.add(_ownerOf(key));
    _schedulePersist();
    _raise();
  }

  /// Throws away everything one extension wrote.
  Future<void> clearExtension(String extensionId) async {
    await ensureLoaded();
    final doomed = keysUnder(extensionId);
    if (doomed.isEmpty) {
      return;
    }
    for (final key in doomed) {
      _entries.remove(key);
      _listeners[key]?.value = null;
    }
    _dirty.add(extensionId);
    _schedulePersist();
    _raise();
  }

  Future<void> flush() async {
    _persist?.cancel();
    _persist = null;
    if (_dirty.isEmpty) {
      return;
    }
    final owners = _dirty.toList();
    _dirty.clear();
    for (final owner in owners) {
      await _writeOwner(owner);
    }
  }

  void _schedulePersist() {
    _persist?.cancel();
    _persist = Timer(persistDebounce, () {
      _persist = null;
      unawaited(flush());
    });
  }

  Future<void> _writeOwner(String owner) async {
    try {
      final folder = Directory(p.join(await resolveRoot(), owner));
      await folder.create(recursive: true);
      final payload = <String, Object?>{
        for (final entry in _entries.entries)
          if (_ownerOf(entry.key) == owner) entry.key: entry.value.toJson(),
      };
      final file = File(p.join(folder.path, fileName));
      if (payload.isEmpty) {
        if (file.existsSync()) {
          await file.delete();
        }
        return;
      }
      await file.writeAsString(jsonEncode(payload));
    } on Object catch (error) {
      Log.warn('Extension data for $owner could not be written: $error');
    }
  }

  static String _ownerOf(String key) {
    final dot = key.indexOf('.');
    return dot <= 0 ? key : key.substring(0, dot);
  }

  void _raise() {
    revision.value = revision.value + 1;
    notifyListeners();
  }

  @override
  void dispose() {
    _persist?.cancel();
    for (final listener in _listeners.values) {
      listener.dispose();
    }
    _listeners.clear();
    revision.dispose();
    super.dispose();
  }
}
