import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What external content is remembered between reads.
///
/// A remote collection has to feel like a local one on a slow connection, and
/// the only way to do that is to keep the cheap parts — the listing, the
/// metadata, the thumbnails — and fetch the expensive part only when somebody
/// actually opens something. Nothing here is authoritative: every entry knows
/// when it was written and is refreshed behind whatever is already on screen.
class ProviderCache {
  ProviderCache._();

  static final ProviderCache instance = ProviderCache._();

  /// How long a listing is trusted before it is refreshed in the background.
  /// It is still shown immediately while that happens.
  static const listingFreshness = Duration(minutes: 5);

  /// Thumbnails change far less often than listings, so they are kept much
  /// longer and only dropped when the collection is unbound or swept.
  static const thumbnailLifetime = Duration(days: 30);

  static const maxThumbnailBytes = 8 << 20;

  Directory? _root;
  Future<Directory>? _opening;

  final Map<String, _MemoryEntry> _memory = <String, _MemoryEntry>{};

  Future<Directory> _rootDirectory() {
    final open = _root;
    if (open != null) {
      return Future<Directory>.value(open);
    }
    return _opening ??= () async {
      String base;
      try {
        base = await getIt<ApplicationDataStorage>().getPath();
      } catch (_) {
        base = (await getTemporaryDirectory()).path;
      }
      final directory = Directory(p.join(base, 'provider_cache'));
      await directory.create(recursive: true);
      _root = directory;
      _opening = null;
      return directory;
    }();
  }

  /// A stable, short, filesystem-safe name for any key.
  static String digest(String value) =>
      sha1.convert(utf8.encode(value)).toString().substring(0, 24);

  Future<Directory> directoryFor(String cacheKey) async {
    final root = await _rootDirectory();
    final directory = Directory(p.join(root.path, digest(cacheKey)));
    await directory.create(recursive: true);
    return directory;
  }

  // --- Listings and metadata -------------------------------------------------

  /// Reads a stored listing, however old. The caller decides whether to use it
  /// while a refresh runs or to wait.
  Future<CachedValue?> readJson(String cacheKey, String name) async {
    final live = _memory['$cacheKey/$name'];
    if (live != null) {
      return CachedValue(live.value, live.writtenAt);
    }

    try {
      final file =
          File(p.join((await directoryFor(cacheKey)).path, '$name.json'));
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final writtenAt = decoded['written_at'];
      final value = CachedValue(
        decoded['value'],
        writtenAt is int
            ? DateTime.fromMillisecondsSinceEpoch(writtenAt)
            : DateTime.fromMillisecondsSinceEpoch(0),
      );
      _memory['$cacheKey/$name'] = _MemoryEntry(value.value, value.writtenAt);
      return value;
    } catch (error) {
      Log.warn('Unable to read a cached listing: $error');
      return null;
    }
  }

  Future<void> writeJson(String cacheKey, String name, Object? value) async {
    final now = DateTime.now();
    _memory['$cacheKey/$name'] = _MemoryEntry(value, now);
    try {
      final file =
          File(p.join((await directoryFor(cacheKey)).path, '$name.json'));
      await file.writeAsString(
        jsonEncode({'written_at': now.millisecondsSinceEpoch, 'value': value}),
        flush: true,
      );
    } catch (error) {
      Log.warn('Unable to cache a listing: $error');
    }
  }

  // --- Thumbnails ------------------------------------------------------------

  /// Where a thumbnail for [remoteId] would live, whether or not it is there.
  Future<File> thumbnailFile(
    String cacheKey,
    String remoteId, {
    String extension = 'jpg',
  }) async {
    final directory =
        Directory(p.join((await directoryFor(cacheKey)).path, 'thumbnails'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, '${digest(remoteId)}.$extension'));
  }

  /// The cached thumbnail's path, or null when it has not been fetched or has
  /// gone stale.
  Future<String?> thumbnailPath(
    String cacheKey,
    String remoteId, {
    String extension = 'jpg',
  }) async {
    try {
      final file =
          await thumbnailFile(cacheKey, remoteId, extension: extension);
      if (!file.existsSync()) {
        return null;
      }
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age > thumbnailLifetime) {
        await file.delete();
        return null;
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> writeThumbnail(
    String cacheKey,
    String remoteId,
    Uint8List bytes, {
    String extension = 'jpg',
  }) async {
    if (bytes.isEmpty || bytes.length > maxThumbnailBytes) {
      return null;
    }
    try {
      final file =
          await thumbnailFile(cacheKey, remoteId, extension: extension);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (error) {
      Log.warn('Unable to cache a thumbnail: $error');
      return null;
    }
  }

  // --- Whole files -----------------------------------------------------------

  /// Where an object's real bytes are kept once somebody has opened it, so the
  /// second open is instant and the viewer can work from a path.
  Future<File> contentFile(
    String cacheKey,
    String remoteId,
    String name,
  ) async {
    final directory =
        Directory(p.join((await directoryFor(cacheKey)).path, 'files'));
    await directory.create(recursive: true);
    final safe = _safeName(name);
    return File(p.join(directory.path, '${digest(remoteId)}-$safe'));
  }

  /// Everything a service could name a file, reduced to something a filesystem
  /// will accept and to a leaf: nothing here may escape the cache directory.
  static String _safeName(String name) {
    final leaf = name.split(RegExp('[\\\\/]')).last;
    final cleaned =
        leaf.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_').replaceAll('..', '_');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '_') {
      return 'file';
    }
    return cleaned.length > 96
        ? cleaned.substring(cleaned.length - 96)
        : cleaned;
  }

  // --- Invalidation ----------------------------------------------------------

  /// Forgets one collection's listings but keeps its pictures: a manual sync
  /// means "the contents may have changed", not "throw the thumbnails away".
  Future<void> invalidateListings(String cacheKey) async {
    _memory.removeWhere((key, _) => key.startsWith('$cacheKey/'));
    try {
      final directory = await directoryFor(cacheKey);
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          await entity.delete();
        }
      }
    } catch (error) {
      Log.warn('Unable to clear cached listings: $error');
    }
  }

  /// Drops everything for one collection. This is what unbinding means.
  Future<void> evict(String cacheKey) async {
    _memory.removeWhere((key, _) => key.startsWith('$cacheKey/'));
    try {
      final directory = await directoryFor(cacheKey);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    } catch (error) {
      Log.warn('Unable to clear a provider cache: $error');
    }
  }

  Future<int> sizeInBytes() async {
    try {
      final root = await _rootDirectory();
      var total = 0;
      await for (final entity in root.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearAll() async {
    _memory.clear();
    try {
      final root = await _rootDirectory();
      if (root.existsSync()) {
        await root.delete(recursive: true);
        await root.create(recursive: true);
      }
    } catch (error) {
      Log.warn('Unable to clear the provider cache: $error');
    }
  }
}

/// A cached value and when it was written, so the caller can decide whether it
/// is fresh enough to trust without asking again.
@immutable
class CachedValue {
  const CachedValue(this.value, this.writtenAt);

  final Object? value;
  final DateTime writtenAt;

  Duration get age => DateTime.now().difference(writtenAt);

  bool isFresh(Duration within) => age <= within;

  List<Map<String, dynamic>> get list => value is List
      ? [
          for (final entry in value! as List)
            if (entry is Map) Map<String, dynamic>.from(entry),
        ]
      : const <Map<String, dynamic>>[];
}

class _MemoryEntry {
  _MemoryEntry(this.value, this.writtenAt);

  final Object? value;
  final DateTime writtenAt;
}
