import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_language.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// What a repository entry is for, which decides where it shows up.
enum RepoEntryKind {
  folder,
  source,
  documentation,
  data,
  asset,
  page,
  other;

  bool get isFolder => this == RepoEntryKind.folder;

  /// Whether the entry has text a reader can analyse.
  bool get isReadable => switch (this) {
        RepoEntryKind.source ||
        RepoEntryKind.documentation ||
        RepoEntryKind.data =>
          true,
        _ => false,
      };
}

/// One file or folder inside a repository, at its place in the tree.
@immutable
class RepoEntry {
  const RepoEntry({
    required this.view,
    required this.kind,
    required this.path,
    required this.depth,
    required this.parentPath,
    this.language,
    this.byteSize,
    this.modifiedAt,
    this.storageUrl = '',
  });

  final ViewPB view;
  final RepoEntryKind kind;

  /// Repository-relative path with `/` separators, e.g. `lib/main.dart`.
  final String path;
  final int depth;

  /// The folder holding this entry; empty for the repository root.
  final String parentPath;
  final RepoLanguage? language;
  final int? byteSize;
  final DateTime? modifiedAt;

  /// Where the bytes live. Empty for folders, pages and unsaved files.
  final String storageUrl;

  String get id => view.id;
  String get name => view.name;
  bool get isFolder => kind.isFolder;
  bool get isLocalFile =>
      storageUrl.isNotEmpty && !storageUrl.startsWith('http');

  /// The extension without its dot, lowercased; empty when there is none.
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// The documentation file names that belong on a repository's front page.
const Set<String> repoReadmeNames = {
  'readme',
  'readme.md',
  'readme.markdown',
  'readme.txt',
  'readme.rst',
  'index.md',
};

const Set<String> _repoDocExtensions = {
  'md',
  'markdown',
  'mdx',
  'rst',
  'adoc',
  'txt',
};

const Set<String> _repoDataExtensions = {
  'json',
  'jsonc',
  'yaml',
  'yml',
  'toml',
  'ini',
  'cfg',
  'conf',
  'properties',
  'env',
  'csv',
  'tsv',
  'sql',
  'lock',
  'xml',
};

/// Folders that are build output or vendored code rather than the project.
const Set<String> repoIgnoredFolderNames = {
  '.git',
  'node_modules',
  'build',
  'dist',
  'out',
  'target',
  '.dart_tool',
  '__pycache__',
  '.venv',
  'venv',
  '.gradle',
  '.idea',
  'vendor',
  'pods',
};

RepoEntryKind repoEntryKindOf(ViewPB view) {
  if (view.isCollection || view.isWorkspaceFolder) {
    return RepoEntryKind.folder;
  }
  if (!view.isWorkspaceFile) {
    return RepoEntryKind.page;
  }
  final name = view.name;
  final lower = name.toLowerCase();
  if (imgExtensionRegex.hasMatch(lower) ||
      videoExtensionRegex.hasMatch(lower) ||
      audioExtensionRegex.hasMatch(lower)) {
    return RepoEntryKind.asset;
  }
  final dot = lower.lastIndexOf('.');
  final extension = dot <= 0 ? '' : lower.substring(dot + 1);
  if (repoReadmeNames.contains(lower) || _repoDocExtensions.contains(extension)) {
    return RepoEntryKind.documentation;
  }
  if (_repoDataExtensions.contains(extension)) {
    return RepoEntryKind.data;
  }
  if (repoLanguageForName(name) != null ||
      filePreviewKindFromName(name) == FilePreviewKind.code) {
    return RepoEntryKind.source;
  }
  return RepoEntryKind.other;
}

/// Builds one entry for [view] under [parentPath].
RepoEntry repoEntryFor(
  ViewPB view, {
  required String parentPath,
  required int depth,
}) {
  final metadata = view.workspaceItem;
  final edited = view.lastEdited.toInt();
  return RepoEntry(
    view: view,
    kind: repoEntryKindOf(view),
    path: parentPath.isEmpty ? view.name : '$parentPath/${view.name}',
    depth: depth,
    parentPath: parentPath,
    language: repoLanguageForName(view.name),
    byteSize: metadata?.size,
    modifiedAt: edited > 0
        ? DateTime.fromMillisecondsSinceEpoch(edited * 1000)
        : metadata?.modifiedAt,
    storageUrl: metadata?.storageUrl ?? '',
  );
}

/// Folders first, then files, each group by name — the order every file
/// browser uses, so a repository reads the way a developer expects.
int compareRepoEntries(RepoEntry a, RepoEntry b) {
  if (a.isFolder != b.isFolder) {
    return a.isFolder ? -1 : 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// The folder part of [path], or empty when it sits at the root.
String repoParentPath(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

typedef RepoChildrenResolver = List<ViewPB> Function(String id);

/// Flattens the repository under [rootId] into one depth-first listing.
///
/// The limits are guards, not preferences: a workspace folder can be pointed
/// at anything, and an explorer must not walk a cycle or a hundred thousand
/// files into a stall.
List<RepoEntry> buildRepoTree({
  required String rootId,
  required RepoChildrenResolver childrenOf,
  int maxDepth = 12,
  int maxEntries = 5000,
}) {
  final entries = <RepoEntry>[];
  final visited = <String>{rootId};

  void walk(String parentId, String parentPath, int depth) {
    if (depth > maxDepth || entries.length >= maxEntries) {
      return;
    }
    final children = [
      for (final view in childrenOf(parentId))
        repoEntryFor(view, parentPath: parentPath, depth: depth),
    ]..sort(compareRepoEntries);
    for (final entry in children) {
      if (entries.length >= maxEntries) {
        return;
      }
      entries.add(entry);
      if (entry.isFolder && visited.add(entry.id)) {
        walk(entry.id, entry.path, depth + 1);
      }
    }
  }

  walk(rootId, '', 0);
  return entries;
}

/// Whether [name] is hidden or is build output rather than project source.
bool isHiddenRepoName(String name) => name.startsWith('.');

bool isIgnoredRepoFolder(String name) =>
    repoIgnoredFolderNames.contains(name.toLowerCase());

/// Resolves `./x`, `../x` and bare `x` against the folder [from].
///
/// Returns null when the path climbs above the repository root.
String? resolveRepoPath(String from, String relative) {
  final segments = <String>[
    if (from.isNotEmpty) ...from.split('/'),
  ];
  for (final segment in relative.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isEmpty) {
        return null;
      }
      segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}
