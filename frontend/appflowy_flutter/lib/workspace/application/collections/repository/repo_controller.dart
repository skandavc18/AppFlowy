import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_file_fetcher.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_language.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_source_cache.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_state.dart';
import 'package:appflowy/workspace/application/collections/repository/source_imports.dart';
import 'package:appflowy/workspace/application/collections/repository/source_outline.dart';
import 'package:flutter/foundation.dart';

/// One file in the dependency graph, with everything it points at.
@immutable
class RepoDependencyNode {
  const RepoDependencyNode({
    required this.entry,
    required this.dependsOn,
    required this.dependedOnBy,
    required this.packages,
  });

  final RepoEntry entry;

  /// Repository paths this file imports.
  final Set<String> dependsOn;

  /// Repository paths that import this file.
  final Set<String> dependedOnBy;

  /// Third-party packages this file imports.
  final Set<String> packages;

  int get degree => dependsOn.length + dependedOnBy.length;
}

/// The repository's import structure, as far as it could be followed.
@immutable
class RepoDependencyGraph {
  const RepoDependencyGraph({
    required this.nodes,
    required this.edges,
    required this.packages,
  });

  static const empty = RepoDependencyGraph(nodes: {}, edges: [], packages: {});

  /// By repository path.
  final Map<String, RepoDependencyNode> nodes;

  /// From-path to to-path pairs.
  final List<(String, String)> edges;

  /// External package name to the number of files importing it.
  final Map<String, int> packages;

  bool get isEmpty => nodes.isEmpty;
}

/// Owns a repository's tree, what has been read out of it and what it
/// remembers.
class RepositoryController extends ChangeNotifier {
  RepositoryController({
    required Map<String, dynamic> initialState,
    required this.onPersist,
    RepoSourceCache? source,
    this.persistDebounce = const Duration(milliseconds: 900),
  })  : _state = RepoState.fromJson(initialState),
        source = source ?? RepoSourceCache();

  final ValueChanged<Map<String, dynamic>> onPersist;
  final RepoSourceCache source;
  final Duration persistDebounce;

  RepoState _state;
  List<RepoEntry> _all = const [];
  List<RepoEntry> _visible = const [];
  Map<String, RepoEntry> _byPath = const {};
  Map<String, RepoEntry> _byId = const {};
  RepoPathIndex _index = RepoPathIndex(const []);
  RepoStats _stats = const RepoStats();
  RepoDependencyGraph _graph = RepoDependencyGraph.empty;
  RepoFileFetcher? _fetcher;
  Timer? _persistTimer;
  bool _disposed = false;
  bool _analysing = false;
  int _analysed = 0;

  RepoState get state => _state;
  RepoSettings get settings => _state.settings;

  /// Set when the repository was listed rather than taken whole, in which case
  /// a file's bytes only arrive once it is opened.
  RepoFileFetcher? get fetcher => _fetcher;

  set fetcher(RepoFileFetcher? value) {
    _fetcher = value;
    source.fetch = value?.ensureLocal;
  }

  /// Everything found in the repository, in tree order.
  List<RepoEntry> get allEntries => _all;

  /// The entries the current settings show, in tree order.
  List<RepoEntry> get entries => _visible;

  RepoStats get stats => _stats;
  RepoDependencyGraph get graph => _graph;
  bool get isEmpty => _visible.isEmpty;
  bool get isAnalysing => _analysing;

  /// How far the reader has got, 0..1.
  double get analysisProgress {
    final total = readableEntries.length;
    return total == 0 ? 1 : (_analysed / total).clamp(0.0, 1.0);
  }

  /// The files a whole-tree read may touch.
  ///
  /// A lazily fetched repository only offers what is already on disk: reading
  /// all of it would be the download the lazy listing exists to avoid.
  List<RepoEntry> get readableEntries {
    final fetcher = _fetcher;
    return [
      for (final entry in _visible)
        if (!entry.isFolder && entry.kind.isReadable && entry.isLocalFile)
          if (fetcher == null || fetcher.hasLocal(entry)) entry,
    ];
  }

  List<RepoEntry> get sourceEntries => [
        for (final entry in _visible)
          if (entry.kind == RepoEntryKind.source) entry,
      ];

  List<RepoEntry> get documentationEntries => [
        for (final entry in _visible)
          if (entry.kind == RepoEntryKind.documentation) entry,
      ];

  RepoEntry? entryForPath(String path) => _byPath[path];
  RepoEntry? entryForId(String id) => _byId[id];

  /// The entries directly inside [path], already ordered.
  List<RepoEntry> childrenOfPath(String path) => [
        for (final entry in _visible)
          if (entry.parentPath == path) entry,
      ];

  /// The file a repository opens on: its README, if it has one.
  RepoEntry? get readme {
    RepoEntry? best;
    for (final entry in _visible) {
      if (entry.kind != RepoEntryKind.documentation) {
        continue;
      }
      if (!repoReadmeNames.contains(entry.name.toLowerCase())) {
        continue;
      }
      // A README at the root wins over one buried in a folder.
      if (best == null || entry.depth < best.depth) {
        best = entry;
      }
    }
    return best;
  }

  void setEntries(List<RepoEntry> entries) {
    final sameTree = _all.length == entries.length &&
        !_all.indexed.any((entry) => entry.$2.path != entries[entry.$1].path);
    _all = entries;
    _rebuild();
    final pruned = _state.prunedTo(
      paths: {for (final entry in _visible) entry.path},
      ids: {for (final entry in _visible) entry.id},
    );
    final changed = !identical(pruned, _state);
    _state = pruned;
    if (changed) {
      _schedulePersist();
    }
    if (!sameTree || changed) {
      _notify();
    }
  }

  RepoFileAnalysis analysisFor(RepoEntry entry) =>
      source.peek(entry.id) ?? RepoFileAnalysis.pending;

  String? textFor(RepoEntry entry) => source.textFor(entry.id);

  /// Reads [entry] if it has not been read yet.
  Future<void> ensureAnalysis(RepoEntry entry) async {
    if (source.peek(entry.id) != null) {
      return;
    }
    await source.load(entry);
    if (_disposed) {
      return;
    }
    _rebuildStats();
    _notify();
  }

  /// Reads every file the repository holds, so symbols and the graph settle.
  ///
  /// Batched: a whole tree opened at once exhausts the file handles and
  /// stalls everything else the application is doing.
  Future<void> analyseAll({int batchSize = 8}) async {
    final targets = readableEntries;
    if (targets.isEmpty || _analysing) {
      return;
    }
    _analysing = true;
    _analysed = 0;
    _notify();
    try {
      for (var start = 0; start < targets.length; start += batchSize) {
        if (_disposed) {
          return;
        }
        final end = math.min(start + batchSize, targets.length);
        await Future.wait(targets.sublist(start, end).map(source.load));
        if (_disposed) {
          return;
        }
        _analysed = end;
        _rebuildStats();
        _notify();
      }
    } finally {
      _analysing = false;
      if (!_disposed) {
        _rebuildStats();
        _rebuildGraph();
        _notify();
      }
    }
  }

  /// Every symbol read so far, with the file it came from.
  List<(RepoEntry, SourceSymbol)> symbols({
    String query = '',
    Set<SymbolKind>? kinds,
  }) {
    final needle = query.trim().toLowerCase();
    final results = <(RepoEntry, SourceSymbol)>[];
    for (final entry in _visible) {
      if (entry.isFolder) {
        continue;
      }
      final analysis = source.peek(entry.id);
      if (analysis == null) {
        continue;
      }
      for (final symbol in analysis.symbols) {
        if (kinds != null && !kinds.contains(symbol.kind)) {
          continue;
        }
        if (needle.isNotEmpty &&
            !symbol.name.toLowerCase().contains(needle) &&
            !entry.name.toLowerCase().contains(needle)) {
          continue;
        }
        results.add((entry, symbol));
      }
    }
    return results;
  }

  void updateSettings(RepoSettings settings) {
    _state = _state.copyWith(settings: settings);
    _rebuild();
    _schedulePersist();
    _notify();
  }

  void toggleExpanded(String path) {
    _state = _state.toggleExpanded(path);
    _schedulePersist();
    _notify();
  }

  void expandTo(String path) {
    final expanded = Set<String>.from(_state.expandedPaths);
    final segments = path.split('/');
    for (var index = 1; index < segments.length; index++) {
      expanded.add(segments.take(index).join('/'));
    }
    if (expanded.length == _state.expandedPaths.length) {
      return;
    }
    _state = _state.copyWith(expandedPaths: expanded);
    _schedulePersist();
    _notify();
  }

  void openFile(String? id) {
    if (_state.activeFileId == id) {
      return;
    }
    _state = RepoState(
      settings: _state.settings,
      expandedPaths: _state.expandedPaths,
      activeFileId: id,
      activeDocId: _state.activeDocId,
      browserPath: _state.browserPath,
    );
    _schedulePersist();
    _notify();
  }

  void openDoc(String? id) {
    if (_state.activeDocId == id) {
      return;
    }
    _state = RepoState(
      settings: _state.settings,
      expandedPaths: _state.expandedPaths,
      activeFileId: _state.activeFileId,
      activeDocId: id,
      browserPath: _state.browserPath,
    );
    _schedulePersist();
    _notify();
  }

  void browseTo(String path) {
    if (_state.browserPath == path) {
      return;
    }
    _state = _state.copyWith(browserPath: path);
    _schedulePersist();
    _notify();
  }

  void _rebuild() {
    _visible = _filtered(_all);
    _byPath = {for (final entry in _visible) entry.path: entry};
    _byId = {for (final entry in _visible) entry.id: entry};
    _index = RepoPathIndex(_visible);
    _rebuildStats();
    _rebuildGraph();
  }

  List<RepoEntry> _filtered(List<RepoEntry> entries) {
    final hiddenRoots = <String>{};
    final kept = <RepoEntry>[];
    for (final entry in entries) {
      final underHidden = hiddenRoots.any(
        (root) => entry.path == root || entry.path.startsWith('$root/'),
      );
      if (underHidden) {
        continue;
      }
      final hidden = !settings.showHidden && isHiddenRepoName(entry.name);
      final ignored = !settings.showIgnored &&
          entry.isFolder &&
          isIgnoredRepoFolder(entry.name);
      if (hidden || ignored) {
        hiddenRoots.add(entry.path);
        continue;
      }
      kept.add(entry);
    }
    return _sorted(kept);
  }

  /// Sorts each folder's own children, keeping the tree order intact.
  List<RepoEntry> _sorted(List<RepoEntry> entries) {
    if (settings.sort == RepoSort.name) {
      return List.unmodifiable(entries);
    }
    final byParent = <String, List<RepoEntry>>{};
    for (final entry in entries) {
      byParent.putIfAbsent(entry.parentPath, () => []).add(entry);
    }
    for (final group in byParent.values) {
      group.sort((a, b) {
        if (a.isFolder != b.isFolder) {
          return a.isFolder ? -1 : 1;
        }
        return switch (settings.sort) {
          RepoSort.name => 0,
          RepoSort.size => (b.byteSize ?? 0).compareTo(a.byteSize ?? 0),
          RepoSort.modified => (b.modifiedAt ?? DateTime(0))
              .compareTo(a.modifiedAt ?? DateTime(0)),
          RepoSort.type => (a.language?.label ?? a.extension)
              .compareTo(b.language?.label ?? b.extension),
        };
      });
    }
    final ordered = <RepoEntry>[];
    void emit(String parentPath) {
      for (final entry in byParent[parentPath] ?? const <RepoEntry>[]) {
        ordered.add(entry);
        if (entry.isFolder) {
          emit(entry.path);
        }
      }
    }

    emit('');
    return List.unmodifiable(ordered);
  }

  void _rebuildStats() {
    var files = 0;
    var folders = 0;
    var sources = 0;
    var docs = 0;
    var assets = 0;
    var bytes = 0;
    var lines = 0;
    final byLanguage = <String, (int files, int bytes)>{};

    for (final entry in _visible) {
      if (entry.isFolder) {
        folders += 1;
        continue;
      }
      files += 1;
      final analysis = source.peek(entry.id);
      final size = analysis?.byteSize ?? entry.byteSize ?? 0;
      bytes += size;
      lines += analysis?.lineCount ?? 0;
      switch (entry.kind) {
        case RepoEntryKind.source:
          sources += 1;
        case RepoEntryKind.documentation:
          docs += 1;
        case RepoEntryKind.asset:
          assets += 1;
        case RepoEntryKind.folder:
        case RepoEntryKind.data:
        case RepoEntryKind.page:
        case RepoEntryKind.other:
          break;
      }
      final language = entry.language;
      if (language == null || !language.isCode) {
        continue;
      }
      final current = byLanguage[language.id] ?? (0, 0);
      byLanguage[language.id] =
          (current.$1 + 1, current.$2 + math.max(size, 1));
    }

    final total = byLanguage.values.fold<int>(0, (sum, it) => sum + it.$2);
    final shares = <RepoLanguageShare>[
      for (final entry in byLanguage.entries)
        if (repoLanguageById(entry.key) case final language?)
          RepoLanguageShare(
            languageId: language.id,
            label: language.label,
            color: language.color,
            files: entry.value.$1,
            bytes: entry.value.$2,
            fraction: total == 0 ? 0 : entry.value.$2 / total,
          ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));

    _stats = RepoStats(
      fileCount: files,
      folderCount: folders,
      sourceCount: sources,
      docCount: docs,
      assetCount: assets,
      byteSize: bytes,
      lineCount: lines,
      languages: shares,
    );
  }

  void _rebuildGraph() {
    final dependsOn = <String, Set<String>>{};
    final dependedOnBy = <String, Set<String>>{};
    final packagesFor = <String, Set<String>>{};
    final packageCounts = <String, int>{};
    final edges = <(String, String)>[];

    for (final entry in _visible) {
      if (entry.isFolder) {
        continue;
      }
      final analysis = source.peek(entry.id);
      if (analysis == null || analysis.imports.isEmpty) {
        continue;
      }
      final resolution = resolveRepoImports(
        from: entry,
        imports: analysis.imports,
        index: _index,
      );
      dependsOn[entry.path] = resolution.internal;
      packagesFor[entry.path] = resolution.external;
      for (final package in resolution.external) {
        packageCounts[package] = (packageCounts[package] ?? 0) + 1;
      }
      for (final target in resolution.internal) {
        edges.add((entry.path, target));
        dependedOnBy.putIfAbsent(target, () => {}).add(entry.path);
      }
    }

    final nodes = <String, RepoDependencyNode>{};
    for (final path in {...dependsOn.keys, ...dependedOnBy.keys}) {
      final entry = _byPath[path];
      if (entry == null) {
        continue;
      }
      nodes[path] = RepoDependencyNode(
        entry: entry,
        dependsOn: dependsOn[path] ?? const {},
        dependedOnBy: dependedOnBy[path] ?? const {},
        packages: packagesFor[path] ?? const {},
      );
    }

    final sortedPackages = packageCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _graph = RepoDependencyGraph(
      nodes: nodes,
      edges: edges,
      packages: {for (final entry in sortedPackages) entry.key: entry.value},
    );
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, flush);
  }

  /// Writes the state now rather than waiting for the debounce.
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
    if (_persistTimer?.isActive ?? false) {
      flush();
    }
    _persistTimer?.cancel();
    _fetcher?.dispose();
    _disposed = true;
    super.dispose();
  }
}
