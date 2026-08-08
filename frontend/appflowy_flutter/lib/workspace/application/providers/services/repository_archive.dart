import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// How far a repository has got towards being readable.
@immutable
class RepositoryArchiveProgress {
  const RepositoryArchiveProgress({
    required this.stage,
    this.received = 0,
    this.total,
  });

  final RepositoryArchiveStage stage;
  final int received;
  final int? total;

  double? get fraction {
    final size = total;
    if (size == null || size <= 0) {
      return null;
    }
    return (received / size).clamp(0.0, 1.0);
  }
}

enum RepositoryArchiveStage { downloading, extracting, ready, failed }

/// How a repository was made readable.
@immutable
class RepositoryFetch {
  const RepositoryFetch({required this.root, required this.isLazy});

  /// Where the repository's files are, or will be once they are fetched.
  final Directory root;

  /// Whether only the listing was taken, so a file arrives when it is opened
  /// rather than up front.
  final bool isLazy;
}

/// Puts a hosted repository on disk, once.
///
/// Reading a project needs its file contents, not just its names: the symbol
/// outline, the dependency graph and the documentation pane all parse source.
/// Fetching that a file at a time would be thousands of requests against a
/// rate limit, so the whole tree is taken in ONE request — the archive endpoint
/// both GitHub and GitLab offer — and unpacked into the provider cache.
///
/// After this, every repository view works on ordinary local files, which is
/// why the hosted repository and the local one share one implementation.
///
/// A repository too big for that — or hosted somewhere that offers no archive —
/// falls back to a lazy fetch: the listing alone is read, and each file is
/// downloaded into the same place the archive would have put it the moment
/// somebody opens it. Browsing a large repository therefore costs one request,
/// not a download of the entire project.
class RepositoryArchive {
  RepositoryArchive({ProviderCache? cache})
      : _cache = cache ?? ProviderCache.instance;

  /// A source tarball this large is not a project somebody reads in a panel.
  static const maxCompressedBytes = 96 << 20;

  /// Guards against a crafted archive that expands without bound.
  static const maxExtractedBytes = 320 << 20;

  static const maxEntries = 40000;

  /// Above the size the host reports, the archive is not even attempted: a
  /// download that is going to be refused halfway is worse than not starting
  /// it, and the lazy listing is ready in one request.
  static const maxUnpackedKb = 100 * 1024;

  final ProviderCache _cache;

  /// The tree for [source], fetching it when the branch has changed or nothing
  /// has been fetched yet.
  ///
  /// Never throws for size: a repository that will not fit comes back lazy.
  Future<RepositoryFetch> ensure({
    required RepositoryProvider provider,
    required CollectionSource source,
    required String branch,
    ValueChanged<RepositoryArchiveProgress>? onProgress,
  }) async {
    final root = await _treeDirectory(source);
    final stamp = File(p.join(root.parent.path, 'tree.ref'));
    final marker = _marker(stamp);

    if (root.existsSync() && marker == branch) {
      return RepositoryFetch(root: root, isLazy: false);
    }
    if (root.existsSync() && marker == _lazyMarker(branch)) {
      return RepositoryFetch(root: root, isLazy: true);
    }

    final url = await provider.archiveUrl(branch);
    if (url == null || url.isEmpty) {
      return _beginLazy(root, stamp, branch);
    }

    final sizeKb = (await provider.summary())?.sizeKb ?? 0;
    if (sizeKb > maxUnpackedKb) {
      Log.info(
        'Browsing a repository of ${sizeKb ~/ 1024} MB rather than unpacking it.',
      );
      return _beginLazy(root, stamp, branch);
    }

    final download = File(p.join(root.parent.path, 'repo.tar.gz'));
    try {
      onProgress?.call(
        const RepositoryArchiveProgress(
          stage: RepositoryArchiveStage.downloading,
        ),
      );
      await provider.downloadArchive(
        url,
        download,
        onProgress: (received, total) => onProgress?.call(
          RepositoryArchiveProgress(
            stage: RepositoryArchiveStage.downloading,
            received: received,
            total: total,
          ),
        ),
      );

      onProgress?.call(
        const RepositoryArchiveProgress(
          stage: RepositoryArchiveStage.extracting,
        ),
      );
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
      await root.create(recursive: true);
      await _extract(download, root);
      await stamp.writeAsString(branch, flush: true);

      onProgress?.call(
        const RepositoryArchiveProgress(stage: RepositoryArchiveStage.ready),
      );
      return RepositoryFetch(root: root, isLazy: false);
    } on ProviderFailure catch (failure) {
      // Only a refusal to fetch this much is a reason to browse instead;
      // being signed out or offline is not, and must still be reported.
      if (failure.status != ProviderStatus.error) {
        onProgress?.call(
          const RepositoryArchiveProgress(stage: RepositoryArchiveStage.failed),
        );
        rethrow;
      }
      Log.info('Browsing a repository that was too large to unpack.');
      return _beginLazy(root, stamp, branch);
    } catch (error, stackTrace) {
      Log.warn('Unable to unpack a repository: $error\n$stackTrace');
      return _beginLazy(root, stamp, branch);
    } finally {
      try {
        if (download.existsSync()) {
          await download.delete();
        }
      } catch (_) {
        // A leftover download is not worth reporting.
      }
    }
  }

  /// Starts a lazy tree, discarding whatever an earlier branch left behind so
  /// a stale file is never mistaken for one that has been fetched.
  Future<RepositoryFetch> _beginLazy(
    Directory root,
    File stamp,
    String branch,
  ) async {
    try {
      if (root.existsSync() && _marker(stamp) != _lazyMarker(branch)) {
        await root.delete(recursive: true);
      }
      await root.create(recursive: true);
      await stamp.writeAsString(_lazyMarker(branch), flush: true);
    } catch (error) {
      Log.warn('Unable to prepare a repository for browsing: $error');
    }
    return RepositoryFetch(root: root, isLazy: true);
  }

  static String _lazyMarker(String branch) => 'lazy:$branch';

  static String _marker(File stamp) {
    try {
      return stamp.existsSync() ? stamp.readAsStringSync().trim() : '';
    } catch (_) {
      return '';
    }
  }

  Future<Directory> _treeDirectory(CollectionSource source) async {
    final directory = await _cache.directoryFor(source.cacheKey);
    return Directory(p.join(directory.path, 'tree'));
  }

  /// Unpacks the tarball, dropping the single wrapper folder both hosts add.
  Future<void> _extract(File download, Directory root) async {
    final gz = await download.readAsBytes();
    final tar = GZipDecoder().decodeBytes(gz);
    if (tar.length > maxExtractedBytes) {
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'The repository is larger than AppFlowy will unpack.',
      );
    }

    final archive = TarDecoder().decodeBytes(tar);
    var written = 0;
    var count = 0;

    for (final entry in archive) {
      if (!entry.isFile || count++ > maxEntries) {
        continue;
      }
      final relative = stripWrapper(entry.name);
      if (relative == null) {
        continue;
      }
      final destination = safeJoin(root, relative);
      if (destination == null) {
        Log.warn('Refused an archive entry that escaped the tree.');
        continue;
      }

      written += entry.size;
      if (written > maxExtractedBytes) {
        throw const ProviderFailure(
          ProviderStatus.error,
          detail: 'The repository is larger than AppFlowy will unpack.',
        );
      }

      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(entry.content as List<int>);
    }
  }

  /// `owner-repo-<sha>/lib/main.dart` → `lib/main.dart`.
  @visibleForTesting
  static String? stripWrapper(String name) {
    final normalized = name.replaceAll(r'\', '/');
    final slash = normalized.indexOf('/');
    if (slash < 0 || slash == normalized.length - 1) {
      return null;
    }
    return normalized.substring(slash + 1);
  }

  /// Resolves [relative] under [root], or null when it would escape it.
  ///
  /// An archive is a stranger's data and a name in one can say `../`; this is
  /// the only thing standing between that and somebody's home directory.
  @visibleForTesting
  static File? safeJoin(Directory root, String relative) {
    if (relative.isEmpty || relative.contains('\u0000')) {
      return null;
    }
    final rootPath = p.normalize(root.absolute.path);
    final candidate = p.normalize(p.join(rootPath, relative));
    if (!p.isWithin(rootPath, candidate)) {
      return null;
    }
    return File(candidate);
  }
}

/// The unpacked repository, dressed as workspace items.
///
/// [buildRepoTree] walks views, so giving the extracted files the same shape
/// means the repository views need no idea where the project came from.
class RepositoryTreeViews {
  RepositoryTreeViews({required this.rootId, required this.root});

  final String rootId;
  final Directory root;

  final Map<String, List<ViewPB>> _children = <String, List<ViewPB>>{};
  bool _loaded = false;

  /// Folders a project keeps but nobody reads.
  static const _skipped = <String>{
    '.git',
    'node_modules',
    '.dart_tool',
    'build',
    '.gradle',
    '.idea',
    '__pycache__',
  };

  List<ViewPB> childrenOf(String id) {
    if (!_loaded) {
      _load();
    }
    return _children[id] ?? const <ViewPB>[];
  }

  String idFor(String relative) =>
      relative.isEmpty ? rootId : '$rootId::$relative';

  void _load() {
    _loaded = true;
    if (!root.existsSync()) {
      return;
    }
    _walk(root, '');
  }

  void _walk(Directory directory, String relative) {
    final views = <ViewPB>[];
    late final List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } catch (error) {
      Log.warn('Unable to read an unpacked folder: $error');
      return;
    }

    for (final entity in entries) {
      final name = p.basename(entity.path);
      if (name.startsWith('.git') || _skipped.contains(name)) {
        continue;
      }
      final childRelative = relative.isEmpty ? name : '$relative/$name';

      if (entity is Directory) {
        views.add(
          _view(
            id: idFor(childRelative),
            parentId: idFor(relative),
            name: name,
            metadata: const WorkspaceItemMetadata.folder(),
          ),
        );
        _walk(entity, childRelative);
      } else if (entity is File) {
        int? size;
        DateTime? modified;
        try {
          final stat = entity.statSync();
          size = stat.size;
          modified = stat.modified;
        } catch (_) {
          // A file that cannot be stat'd is still worth listing.
        }
        views.add(
          _view(
            id: idFor(childRelative),
            parentId: idFor(relative),
            name: name,
            metadata: WorkspaceItemMetadata.file(
              contentKind: WorkspaceFileContentKind.binary,
              storageUrl: entity.path,
              size: size,
              modifiedAt: modified,
            ),
          ),
        );
      }
    }

    views.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _children[idFor(relative)] = views;
  }

  static ViewPB _view({
    required String id,
    required String parentId,
    required String name,
    required WorkspaceItemMetadata metadata,
  }) =>
      ViewPB(
        id: id,
        parentViewId: parentId,
        name: name,
        layout: ViewLayoutPB.Document,
        extra: metadata.mergeIntoExtra(''),
      );
}

/// A repository that was listed rather than unpacked, dressed as workspace
/// items.
///
/// The same shape [RepositoryTreeViews] produces, built from listing metadata
/// instead of files on disk, so every repository view works unchanged. Each
/// file's storage path is where the archive would have put it; the fetcher
/// puts it there when it is opened, and until then only its name and size are
/// known — which is all a listing draws anyway.
class RepositoryLazyTreeViews {
  RepositoryLazyTreeViews({
    required this.rootId,
    required this.root,
    required List<ProviderNode> nodes,
  }) : _nodes = nodes;

  final String rootId;
  final Directory root;
  final List<ProviderNode> _nodes;

  final Map<String, List<ViewPB>> _children = <String, List<ViewPB>>{};
  bool _loaded = false;

  List<ViewPB> childrenOf(String id) {
    if (!_loaded) {
      _load();
    }
    return _children[id] ?? const <ViewPB>[];
  }

  String idFor(String relative) =>
      relative.isEmpty ? rootId : '$rootId::$relative';

  void _load() {
    _loaded = true;
    final folders = <String>{''};
    final pending = <ProviderNode>[];

    for (final node in _nodes) {
      final path = node.path.isEmpty ? node.id : node.path;
      if (path.isEmpty || _isSkipped(path)) {
        continue;
      }
      if (node.isFolder) {
        folders.add(path);
      }
      pending.add(node);
    }

    for (final node in pending) {
      final path = node.path.isEmpty ? node.id : node.path;
      // A listing truncated part way can leave a file whose folder never
      // arrived; inventing the folder keeps the file reachable.
      var parent = _parentOf(path);
      while (parent.isNotEmpty && folders.add(parent)) {
        parent = _parentOf(parent);
      }
    }

    for (final folder in folders) {
      _children.putIfAbsent(idFor(folder), () => <ViewPB>[]);
    }

    final seen = <String>{};
    for (final folder in folders) {
      if (folder.isEmpty || !seen.add(folder)) {
        continue;
      }
      _children[idFor(_parentOf(folder))]!.add(
        RepositoryTreeViews._view(
          id: idFor(folder),
          parentId: idFor(_parentOf(folder)),
          name: folder.split('/').last,
          metadata: const WorkspaceItemMetadata.folder(),
        ),
      );
    }

    for (final node in pending) {
      final path = node.path.isEmpty ? node.id : node.path;
      if (node.isFolder || !seen.add(path)) {
        continue;
      }
      _children[idFor(_parentOf(path))]!.add(
        RepositoryTreeViews._view(
          id: idFor(path),
          parentId: idFor(_parentOf(path)),
          name: path.split('/').last,
          metadata: WorkspaceItemMetadata.file(
            contentKind: WorkspaceFileContentKind.binary,
            storageUrl: p.join(root.path, p.joinAll(path.split('/'))),
            size: node.byteSize,
            modifiedAt: node.modifiedAt,
          ),
        ),
      );
    }

    for (final views in _children.values) {
      views
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  static bool _isSkipped(String path) {
    for (final segment in path.split('/')) {
      if (segment.startsWith('.git') ||
          RepositoryTreeViews._skipped.contains(segment)) {
        return true;
      }
    }
    return false;
  }

  static String _parentOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }
}

/// Reads a file out of the unpacked tree, for anything that wants text rather
/// than a path.
Future<String?> readRepositoryFile(
  File file, {
  int maxBytes = 512 * 1024,
}) async {
  try {
    if (!file.existsSync()) {
      return null;
    }
    final handle = await file.open();
    try {
      final length = await handle.length();
      final bytes = await handle.read(length < maxBytes ? length : maxBytes);
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } finally {
      await handle.close();
    }
  } catch (error) {
    Log.warn('Unable to read an unpacked file: $error');
    return null;
  }
}
