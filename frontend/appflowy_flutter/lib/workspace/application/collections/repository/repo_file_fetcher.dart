import 'dart:io';

import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy_backend/log.dart';

/// Fetches one repository file at a time, for a repository too large to take
/// whole.
///
/// A file lands exactly where unpacking the archive would have put it, so
/// nothing above this knows the difference: the browser, the editor and the
/// source reader all open an ordinary local file. What changes is *when* the
/// bytes arrive — the moment somebody asks for that one file, and never for
/// the thousands they did not ask for.
class RepoFileFetcher {
  RepoFileFetcher({
    required this.provider,
    required this.root,
    this.maxFileBytes = 24 << 20,
  });

  final RepositoryProvider provider;

  /// Where the repository's files live once they have been fetched.
  final Directory root;

  /// A single file bigger than this is not something a panel reads.
  final int maxFileBytes;

  final Map<String, ProviderNode> _nodes = <String, ProviderNode>{};
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  final Set<String> _local = <String>{};
  final Set<String> _failed = <String>{};
  bool _scanned = false;
  bool _disposed = false;

  /// Remembers what the listing said about each file, which is where the
  /// download address and the expected size come from.
  void remember(Iterable<ProviderNode> nodes) {
    for (final node in nodes) {
      if (node.isFolder) {
        continue;
      }
      final path = node.path.isEmpty ? node.id : node.path;
      if (path.isNotEmpty) {
        _nodes[path] = node;
      }
    }
  }

  /// Whether [entry]'s bytes are already on disk.
  ///
  /// Answered from a set rather than the filesystem: a repository view asks
  /// this for every file it draws, many times over, and a listing of ten
  /// thousand names must not become ten thousand stat calls a frame.
  bool hasLocal(RepoEntry entry) {
    if (!_scanned) {
      _scan();
    }
    return _local.contains(entry.path);
  }

  /// Whether fetching [entry] has already been tried and refused.
  bool hasFailed(RepoEntry entry) => _failed.contains(entry.path);

  /// Whether [entry] is worth fetching at all: a file the listing knows about,
  /// small enough to read here.
  bool canFetch(RepoEntry entry) {
    if (entry.isFolder || !entry.isLocalFile) {
      return false;
    }
    final size = entry.byteSize;
    if (size != null && size > maxFileBytes) {
      return false;
    }
    return _nodes.containsKey(entry.path);
  }

  /// The local path of [entry]'s bytes, downloading them once if they are not
  /// there yet. Null when the file cannot be fetched.
  Future<String?> ensureLocal(RepoEntry entry) {
    if (hasLocal(entry)) {
      return Future<String?>.value(entry.storageUrl);
    }
    if (_disposed || _failed.contains(entry.path) || !canFetch(entry)) {
      return Future<String?>.value();
    }
    return _inFlight.putIfAbsent(entry.path, () async {
      try {
        return await _fetch(entry);
      } finally {
        _inFlight.removeWhere((key, _) => key == entry.path);
      }
    });
  }

  Future<String?> _fetch(RepoEntry entry) async {
    final node = _nodes[entry.path];
    if (node == null) {
      return null;
    }

    // The staging name keeps a cancelled or refused download from leaving a
    // truncated file that would then read as the real one for ever.
    final destination = File(entry.storageUrl);
    final staging = File('${destination.path}.fetching');
    try {
      await destination.parent.create(recursive: true);
      await provider.downloadFile(node, staging);
      if (_disposed) {
        return null;
      }
      await staging.rename(destination.path);
      _local.add(entry.path);
      return destination.path;
    } on ProviderFailure catch (failure) {
      _failed.add(entry.path);
      Log.warn(
        'Unable to fetch ${entry.path} from a repository: '
        '${failure.status.name}',
      );
      return null;
    } catch (error) {
      _failed.add(entry.path);
      Log.warn('Unable to fetch ${entry.path} from a repository: $error');
      return null;
    } finally {
      try {
        if (staging.existsSync()) {
          await staging.delete();
        }
      } catch (_) {
        // A leftover staging file is not worth reporting.
      }
    }
  }

  /// Forgets a refusal, so retrying is allowed to work.
  void retry(RepoEntry entry) => _failed.remove(entry.path);

  /// What an earlier session already fetched, read once.
  void _scan() {
    _scanned = true;
    if (!root.existsSync()) {
      return;
    }
    final prefix = root.path.length + 1;
    try {
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || entity.path.endsWith('.fetching')) {
          continue;
        }
        _local.add(entity.path.substring(prefix).replaceAll(r'\', '/'));
      }
    } catch (error) {
      Log.warn('Unable to read what a repository has already fetched: $error');
    }
  }

  void dispose() {
    _disposed = true;
    _inFlight.clear();
  }
}
