import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/page_versions/page_version.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where a page's remembered states live.
///
/// One folder per page holding an `index.json` of descriptions and one file
/// per version, so drawing the list never reads a document and opening one
/// version never reads the rest.
class PageVersionStore {
  PageVersionStore({this.rootOverride});

  static final PageVersionStore instance = PageVersionStore();

  static const folderName = 'page_versions';
  static const indexFileName = 'index.json';

  /// Set in tests, where the application directories do not exist.
  @visibleForTesting
  final String? rootOverride;

  /// Raised whenever a page's list changes, so an open rail redraws without
  /// polling. [lastChanged] names the page the change belongs to.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String lastChanged = '';

  String? _root;
  final Map<String, List<PageVersion>> _cache = {};
  final Map<String, Future<List<PageVersion>>> _reading = {};

  /// The last few documents that were read back, so a rail of thumbnails does
  /// not open the same file again every time it is scrolled past.
  final Map<String, Map<String, Object?>> _documents = {};
  static const _maximumCachedDocuments = 24;

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

  /// What has already been read, without waiting. Null means "not read yet",
  /// which a rail draws as loading rather than as an empty history.
  List<PageVersion>? peek(String viewId) => _cache[viewId];

  Future<List<PageVersion>> read(String viewId) {
    if (viewId.isEmpty) {
      return Future.value(const []);
    }
    final cached = _cache[viewId];
    if (cached != null) {
      return Future.value(cached);
    }
    return _reading[viewId] ??= _load(viewId);
  }

  Future<List<PageVersion>> _load(String viewId) async {
    try {
      final file = File(p.join(await _folderFor(viewId), indexFileName));
      if (!file.existsSync()) {
        return _cache[viewId] = const [];
      }
      final decoded = jsonDecode(await file.readAsString());
      final items = decoded is Map ? decoded['versions'] : null;
      final versions = <PageVersion>[];
      if (items is List) {
        for (final item in items) {
          if (item is Map) {
            versions.add(PageVersion.fromJson(Map<String, Object?>.from(item)));
          }
        }
      }
      return _cache[viewId] = sortPageVersions(versions);
    } on Object catch (error) {
      Log.warn('The versions of $viewId could not be read: $error');
      return _cache[viewId] = const [];
    } finally {
      _reading.removeWhere((key, _) => key == viewId);
    }
  }

  /// Writes one version and returns the page's list, newest first.
  ///
  /// [fileBytes] is a workspace file's own content, kept as a sibling file
  /// under its original extension so the application's own viewers can open it
  /// with no unpacking.
  Future<List<PageVersion>> write(
    PageVersion version,
    Map<String, Object?> document, {
    Uint8List? fileBytes,
    String fileExtension = '',
  }) async {
    final existing = await read(version.viewId);
    try {
      final folder = await _folderFor(version.viewId);
      final file = File(p.join(folder, '${version.id}.json'));
      await file.writeAsString(jsonEncode(document), flush: true);

      var total = file.lengthSync();
      if (fileBytes != null) {
        final copy = File(
          p.join(folder, _contentFileName(version.id, fileExtension)),
        );
        await copy.writeAsBytes(fileBytes, flush: true);
        total += fileBytes.length;
      }

      final stored = version.bytes > 0
          ? version
          : PageVersion(
              id: version.id,
              viewId: version.viewId,
              createdAt: version.createdAt,
              kind: version.kind,
              contentHash: version.contentHash,
              shape: version.shape,
              name: version.name,
              pageName: version.pageName,
              blockCount: version.blockCount,
              wordCount: version.wordCount,
              characterCount: version.characterCount,
              bytes: total,
              excerpt: version.excerpt,
            );
      final next = sortPageVersions([...existing, stored]);
      await _writeIndex(version.viewId, next);
      return next;
    } on Object catch (error) {
      Log.warn('A version of ${version.viewId} could not be stored: $error');
      return existing;
    }
  }

  /// The copy of a workspace file one version holds, or null when it kept none.
  Future<File?> contentFile(
    String viewId,
    String versionId,
    String extension,
  ) async {
    try {
      final file = File(
        p.join(
          await _folderFor(viewId),
          _contentFileName(versionId, extension),
        ),
      );
      return file.existsSync() ? file : null;
    } on Object catch (error) {
      Log.warn('The file of $versionId could not be found: $error');
      return null;
    }
  }

  static String _contentFileName(String versionId, String extension) =>
      extension.isEmpty
          ? '$versionId.content'
          : '$versionId.content.$extension';

  /// The stored document of one version, or null when the file has gone.
  Future<Map<String, Object?>?> readDocument(
    String viewId,
    String versionId,
  ) async {
    final key = '$viewId|$versionId';
    final remembered = _documents[key];
    if (remembered != null) {
      return remembered;
    }
    try {
      final file = File(p.join(await _folderFor(viewId), '$versionId.json'));
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final document = Map<String, Object?>.from(decoded);
      if (_documents.length >= _maximumCachedDocuments) {
        _documents.remove(_documents.keys.first);
      }
      return _documents[key] = document;
    } on Object catch (error) {
      Log.warn('Version $versionId of $viewId could not be read: $error');
      return null;
    }
  }

  Future<List<PageVersion>> rename(
    String viewId,
    String versionId,
    String name,
  ) async {
    final existing = await read(viewId);
    final next = existing
        .map(
          (version) => version.id == versionId
              ? version.copyWith(
                  name: name,
                  // Naming a copy is asking for it to be kept.
                  kind: name.trim().isEmpty
                      ? version.kind
                      : version.kind == PageVersionKind.automatic
                          ? PageVersionKind.manual
                          : version.kind,
                )
              : version,
        )
        .toList();
    await _writeIndex(viewId, next);
    return next;
  }

  Future<List<PageVersion>> remove(String viewId, Iterable<String> ids) async {
    final doomed = ids.toSet();
    if (doomed.isEmpty) {
      return read(viewId);
    }
    final existing = await read(viewId);
    final next =
        existing.where((version) => !doomed.contains(version.id)).toList();
    try {
      final folder = await _folderFor(viewId);
      for (final id in doomed) {
        _documents.remove('$viewId|$id');
        await for (final entity in Directory(folder).list()) {
          if (entity is File && p.basename(entity.path).startsWith('$id.')) {
            await entity.delete();
          }
        }
      }
    } on Object catch (error) {
      Log.warn('Versions of $viewId could not be discarded: $error');
    }
    await _writeIndex(viewId, next);
    return next;
  }

  /// Forgets everything about a page — used when the page itself is gone.
  Future<void> forget(String viewId) async {
    try {
      final folder = Directory(await _folderFor(viewId));
      if (folder.existsSync()) {
        await folder.delete(recursive: true);
      }
    } on Object catch (error) {
      Log.warn('The versions of $viewId could not be discarded: $error');
    }
    _cache.remove(viewId);
    _documents.removeWhere((key, _) => key.startsWith('$viewId|'));
    _announce(viewId);
  }

  /// Applies a retention policy and returns what is left.
  Future<List<PageVersion>> prune(
    String viewId,
    PageVersionPolicy policy, {
    DateTime? now,
  }) async {
    final existing = await read(viewId);
    final expired = expiredPageVersions(
      existing,
      policy,
      now: now ?? DateTime.now().toUtc(),
    );
    if (expired.isEmpty) {
      return existing;
    }
    return remove(viewId, expired.map((version) => version.id));
  }

  /// What every page is holding on disk, for the settings screen.
  Future<PageVersionUsage> measureUsage() async {
    var pages = 0;
    var versions = 0;
    var bytes = 0;
    try {
      final root = Directory(await resolveRoot());
      if (!root.existsSync()) {
        return const PageVersionUsage(pages: 0, versions: 0, bytes: 0);
      }
      await for (final entity in root.list()) {
        if (entity is! Directory) {
          continue;
        }
        pages++;
        await for (final file in entity.list()) {
          if (file is! File || p.basename(file.path) == indexFileName) {
            continue;
          }
          versions++;
          bytes += file.lengthSync();
        }
      }
    } on Object catch (error) {
      Log.warn('The stored versions could not be measured: $error');
    }
    return PageVersionUsage(pages: pages, versions: versions, bytes: bytes);
  }

  /// Sweeps every page against the policy. Run when the rules change, so a
  /// tightened setting takes effect on pages nobody has opened since.
  Future<void> pruneEverything(PageVersionPolicy policy) async {
    if (!policy.discardsAnything) {
      return;
    }
    for (final page in await _pageIds()) {
      await prune(page, policy);
    }
    await sweepToBudget(policy);
  }

  /// Brings the whole history back under the room it is allowed.
  ///
  /// The oldest automatic copies go first, wherever they are — a budget for
  /// the workspace cannot be honoured one page at a time, because no single
  /// page knows what the others are holding.
  Future<void> sweepToBudget(PageVersionPolicy policy) async {
    if (!policy.discardsAnything || policy.maximumTotalBytes <= 0) {
      return;
    }

    final everything = <PageVersion>[];
    for (final page in await _pageIds()) {
      everything.addAll(await read(page));
    }

    var total = everything.fold<int>(0, (sum, version) => sum + version.bytes);
    if (total <= policy.maximumTotalBytes) {
      return;
    }

    // Oldest first, and only the copies the application took by itself. The
    // newest copy of each page is left alone, or a sweep would leave a page
    // with no history at all.
    final newest = <String, String>{};
    for (final version in sortPageVersions(everything)) {
      newest.putIfAbsent(version.viewId, () => version.id);
    }

    final doomed = <String, List<String>>{};
    for (final version in sortPageVersions(everything).reversed) {
      if (total <= policy.maximumTotalBytes) {
        break;
      }
      if (version.isKeptForever || newest[version.viewId] == version.id) {
        continue;
      }
      doomed.putIfAbsent(version.viewId, () => []).add(version.id);
      total -= version.bytes;
    }

    for (final entry in doomed.entries) {
      await remove(entry.key, entry.value);
    }
  }

  Future<List<String>> _pageIds() async {
    final pages = <String>[];
    try {
      final root = Directory(await resolveRoot());
      if (!root.existsSync()) {
        return pages;
      }
      await for (final entity in root.list()) {
        if (entity is Directory) {
          pages.add(p.basename(entity.path));
        }
      }
    } on Object catch (error) {
      Log.warn('The stored versions could not be listed: $error');
    }
    return pages;
  }

  /// Throws away every stored version of every page.
  Future<void> discardEverything() async {
    try {
      final root = Directory(await resolveRoot());
      if (root.existsSync()) {
        await root.delete(recursive: true);
        await root.create(recursive: true);
      }
    } on Object catch (error) {
      Log.warn('The stored versions could not be discarded: $error');
    }
    _cache.clear();
    _documents.clear();
    _announce('');
  }

  Future<void> _writeIndex(String viewId, List<PageVersion> versions) async {
    final ordered = sortPageVersions(versions);
    _cache[viewId] = ordered;
    try {
      final file = File(p.join(await _folderFor(viewId), indexFileName));
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'versions': ordered.map((entry) => entry.toJson()).toList(),
        }),
        flush: true,
      );
    } on Object catch (error) {
      Log.warn('The version list of $viewId could not be stored: $error');
    }
    _announce(viewId);
  }

  void _announce(String viewId) {
    lastChanged = viewId;
    revision.value = revision.value + 1;
  }

  Future<String> _folderFor(String viewId) async {
    final folder = p.join(await resolveRoot(), _safeName(viewId));
    await Directory(folder).create(recursive: true);
    return folder;
  }

  static String _safeName(String viewId) =>
      viewId.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  @visibleForTesting
  void forgetEverythingRead() {
    _cache.clear();
    _reading.clear();
    _documents.clear();
  }
}

/// What the stored versions cost, all together.
@immutable
class PageVersionUsage {
  const PageVersionUsage({
    required this.pages,
    required this.versions,
    required this.bytes,
  });

  final int pages;
  final int versions;
  final int bytes;

  bool get isEmpty => versions == 0;
}
