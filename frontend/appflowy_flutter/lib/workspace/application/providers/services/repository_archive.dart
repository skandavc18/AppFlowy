import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
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
class RepositoryArchive {
  RepositoryArchive({ProviderCache? cache})
      : _cache = cache ?? ProviderCache.instance;

  /// A source tarball this large is not a project somebody reads in a panel.
  static const maxCompressedBytes = 96 << 20;

  /// Guards against a crafted archive that expands without bound.
  static const maxExtractedBytes = 320 << 20;

  static const maxEntries = 40000;

  final ProviderCache _cache;

  /// The unpacked tree for [source], fetching it when the branch has changed
  /// or nothing has been fetched yet.
  Future<Directory?> ensure({
    required RepositoryProvider provider,
    required CollectionSource source,
    required String branch,
    ValueChanged<RepositoryArchiveProgress>? onProgress,
  }) async {
    final root = await _treeDirectory(source);
    final stamp = File(p.join(root.parent.path, 'tree.ref'));

    if (root.existsSync() &&
        stamp.existsSync() &&
        stamp.readAsStringSync().trim() == branch) {
      return root;
    }

    final url = await provider.archiveUrl(branch);
    if (url == null || url.isEmpty) {
      return null;
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
      return root;
    } on ProviderFailure {
      onProgress?.call(
        const RepositoryArchiveProgress(stage: RepositoryArchiveStage.failed),
      );
      rethrow;
    } catch (error, stackTrace) {
      Log.warn('Unable to unpack a repository: $error\n$stackTrace');
      onProgress?.call(
        const RepositoryArchiveProgress(stage: RepositoryArchiveStage.failed),
      );
      return null;
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
