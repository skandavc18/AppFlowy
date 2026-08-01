import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_language.dart';
import 'package:flutter/foundation.dart';

/// One `import`, `use`, `require` or `#include` found in a source file.
@immutable
class SourceImport {
  const SourceImport({
    required this.target,
    required this.line,
    required this.isRelative,
  });

  /// The module exactly as it was written.
  final String target;

  /// 1-based.
  final int line;

  /// Whether the target names a path next to the importing file.
  final bool isRelative;

  /// The third-party package this import belongs to, or null when it points
  /// inside the project.
  String? get packageName {
    if (isRelative) {
      return null;
    }
    var value = target;
    if (value.startsWith('package:')) {
      value = value.substring('package:'.length);
      final slash = value.indexOf('/');
      return slash < 0 ? value : value.substring(0, slash);
    }
    if (value.startsWith('@')) {
      final parts = value.split('/');
      return parts.length > 1 ? '${parts[0]}/${parts[1]}' : value;
    }
    if (value.contains('::')) {
      final head = value.split('::').first;
      return const {'crate', 'self', 'super'}.contains(head) ? null : head;
    }
    if (value.contains('/')) {
      return value.split('/').first;
    }
    if (value.contains('.')) {
      return value.split('.').first;
    }
    return value.isEmpty ? null : value;
  }

  @override
  bool operator ==(Object other) =>
      other is SourceImport &&
      other.target == target &&
      other.line == line &&
      other.isRelative == isRelative;

  @override
  int get hashCode => Object.hash(target, line, isRelative);

  @override
  String toString() => 'import $target:$line';
}

final _quoted = RegExp('''['"]([^'"]+)['"]''');

final _importPatterns = <String, List<RegExp>>{
  'dart': [
    RegExp('''^\\s*(?:import|export|part)\\s+['"]([^'"]+)['"]'''),
  ],
  'typescript': [
    RegExp('''^\\s*import\\s+[^;]*?from\\s+['"]([^'"]+)['"]'''),
    RegExp('''^\\s*import\\s+['"]([^'"]+)['"]'''),
    RegExp('''^\\s*export\\s+[^;]*?from\\s+['"]([^'"]+)['"]'''),
    RegExp('''require\\s*\\(\\s*['"]([^'"]+)['"]'''),
    RegExp('''import\\s*\\(\\s*['"]([^'"]+)['"]'''),
  ],
  'python': [
    RegExp(r'^\s*from\s+([.\w]+)\s+import\b'),
    RegExp(r'^\s*import\s+([.\w]+)'),
  ],
  'rust': [
    RegExp(r'^\s*(?:pub\s+)?use\s+([\w:]+)'),
    RegExp(r'^\s*(?:pub\s+)?mod\s+(\w+)\s*;'),
    RegExp(r'^\s*extern\s+crate\s+(\w+)'),
  ],
  'go': [
    RegExp('''^\\s*import\\s+(?:\\w+\\s+)?["`]([^"`]+)["`]'''),
    RegExp('''^\\s*(?:\\w+\\s+)?["`]([^"`/][^"`]*)["`]\\s*\$'''),
  ],
  'java': [
    RegExp(r'^\s*import\s+(?:static\s+)?([\w.]+)\s*;'),
  ],
  'kotlin': [
    RegExp(r'^\s*import\s+([\w.]+)'),
  ],
  'swift': [
    RegExp(r'^\s*(?:@testable\s+)?import\s+([\w.]+)'),
  ],
  'csharp': [
    RegExp(r'^\s*(?:global\s+)?using\s+(?:static\s+)?([\w.]+)\s*;'),
  ],
  'cpp': [
    RegExp('''^\\s*#\\s*include\\s*[<"]([^>"]+)[>"]'''),
  ],
  'c': [
    RegExp('''^\\s*#\\s*include\\s*[<"]([^>"]+)[>"]'''),
  ],
  'ruby': [
    RegExp('''^\\s*require(?:_relative)?\\s+['"]([^'"]+)['"]'''),
  ],
  'php': [
    RegExp(r'^\s*use\s+([\w\\]+)'),
    RegExp(
        '''^\\s*(?:require|include)(?:_once)?\\s*\\(?\\s*['"]([^'"]+)['"]'''),
  ],
  'css': [
    RegExp('''^\\s*@import\\s+(?:url\\()?\\s*['"]([^'"]+)['"]'''),
  ],
  'bash': [
    RegExp('''^\\s*(?:source|\\.)\\s+['"]?([\\w./\\-]+)['"]?'''),
  ],
};

/// The languages whose imports are a path, so anything not starting with a
/// dot is still a project path rather than a package name.
const Set<String> _pathImportLanguages = {'cpp', 'c', 'css', 'bash', 'ruby'};

/// Reads the imports out of [source].
List<SourceImport> parseSourceImports(RepoLanguage? language, String source) {
  if (language == null || source.isEmpty) {
    return const [];
  }
  final patterns = _importPatterns[language.id];
  if (patterns == null) {
    return const [];
  }
  final lines = source.split('\n');
  final imports = <SourceImport>[];
  final seen = <String>{};
  final lineComment = language.lineComment;
  var inGoImportBlock = false;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (lineComment.isNotEmpty && trimmed.startsWith(lineComment)) {
      continue;
    }
    if (language.id == 'go') {
      if (trimmed.startsWith('import (')) {
        inGoImportBlock = true;
        continue;
      }
      if (inGoImportBlock) {
        if (trimmed == ')') {
          inGoImportBlock = false;
          continue;
        }
        final quoted = _quoted.firstMatch(trimmed.replaceAll('`', '"'));
        final target = quoted?.group(1);
        if (target != null && seen.add(target)) {
          imports.add(
            SourceImport(
              target: target,
              line: index + 1,
              isRelative: _isRelative(language, target),
            ),
          );
        }
        continue;
      }
    }

    for (final pattern in patterns) {
      final target = pattern.firstMatch(line)?.group(1);
      if (target == null || target.isEmpty) {
        continue;
      }
      if (seen.add(target)) {
        imports.add(
          SourceImport(
            target: target,
            line: index + 1,
            isRelative: _isRelative(language, target),
          ),
        );
      }
      break;
    }
  }
  return imports;
}

bool _isRelative(RepoLanguage language, String target) {
  if (target.startsWith('./') || target.startsWith('../')) {
    return true;
  }
  if (language.id == 'python' || language.id == 'rust') {
    return target.startsWith('.') ||
        target.startsWith('crate::') ||
        target.startsWith('self::') ||
        target.startsWith('super::');
  }
  if (_pathImportLanguages.contains(language.id)) {
    return true;
  }
  // A bare `foo.dart` or `styles.css` next to the importer is a path too.
  return target.contains('.') &&
      !target.contains(':') &&
      repoLanguageForName(target) != null;
}

/// Where a file's imports point.
@immutable
class RepoImportResolution {
  const RepoImportResolution({
    required this.internal,
    required this.external,
    required this.unresolved,
  });

  /// Repository paths this file depends on.
  final Set<String> internal;

  /// Third-party package names.
  final Set<String> external;

  /// Imports that named neither, kept so the graph can be honest about what
  /// it could not follow.
  final Set<String> unresolved;

  static const empty = RepoImportResolution(
    internal: {},
    external: {},
    unresolved: {},
  );
}

/// An index of a repository's files, used to follow imports.
class RepoPathIndex {
  RepoPathIndex(Iterable<RepoEntry> entries) {
    for (final entry in entries) {
      if (entry.isFolder) {
        folders.add(entry.path);
        continue;
      }
      byPath[entry.path] = entry.path;
      byLowerPath[entry.path.toLowerCase()] = entry.path;
      byName.putIfAbsent(entry.name.toLowerCase(), () => []).add(entry.path);
      final dot = entry.name.lastIndexOf('.');
      if (dot > 0) {
        byStem
            .putIfAbsent(entry.name.substring(0, dot).toLowerCase(), () => [])
            .add(entry.path);
      }
    }
  }

  final Map<String, String> byPath = {};
  final Map<String, String> byLowerPath = {};
  final Map<String, List<String>> byName = {};
  final Map<String, List<String>> byStem = {};
  final Set<String> folders = {};

  String? lookup(String path) =>
      byPath[path] ?? byLowerPath[path.toLowerCase()];

  /// The single file called [name], or null when there is none or many.
  String? unique(Map<String, List<String>> index, String name) {
    final matches = index[name.toLowerCase()];
    return matches != null && matches.length == 1 ? matches.first : null;
  }
}

/// Follows [imports] from [from] into the repository.
///
/// Module systems differ enough that this cannot be exact for every language
/// at once, so an import that cannot be followed is reported as unresolved
/// rather than guessed at.
RepoImportResolution resolveRepoImports({
  required RepoEntry from,
  required List<SourceImport> imports,
  required RepoPathIndex index,
}) {
  final internal = <String>{};
  final external = <String>{};
  final unresolved = <String>{};
  final directory = repoParentPath(from.path);
  final languageId = from.language?.id ?? '';

  for (final import in imports) {
    final resolved = _resolve(
      target: import.target,
      directory: directory,
      languageId: languageId,
      index: index,
    );
    if (resolved != null && resolved != from.path) {
      internal.add(resolved);
      continue;
    }
    final package = import.packageName;
    if (!import.isRelative && package != null && package.isNotEmpty) {
      external.add(package);
    } else {
      unresolved.add(import.target);
    }
  }
  return RepoImportResolution(
    internal: internal,
    external: external,
    unresolved: unresolved,
  );
}

String? _resolve({
  required String target,
  required String directory,
  required String languageId,
  required RepoPathIndex index,
}) {
  final candidates = <String>[];

  void addPath(String? path) {
    if (path != null && path.isNotEmpty) {
      candidates.add(path);
    }
  }

  if (target.startsWith('package:')) {
    // `package:app/x/y.dart` is `lib/x/y.dart` in the package that owns it.
    final rest = target.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash > 0) {
      final inside = rest.substring(slash + 1);
      addPath(inside);
      addPath('lib/$inside');
    }
  } else if (languageId == 'python') {
    final leadingDots =
        target.length - target.replaceFirst(RegExp(r'^\.+'), '').length;
    final module = target.substring(leadingDots).replaceAll('.', '/');
    final base = leadingDots > 0
        ? resolveRepoPath(
            directory, List.filled(leadingDots - 1, '..').join('/'))
        : '';
    final head =
        base == null ? null : (base.isEmpty ? module : '$base/$module');
    addPath(head == null ? null : '$head.py');
    addPath(head == null ? null : '$head/__init__.py');
    if (leadingDots == 0) {
      addPath('$module.py');
      addPath('$module/__init__.py');
    }
  } else if (languageId == 'rust') {
    final segments = target
        .split('::')
        .where((segment) => segment.isNotEmpty && segment != 'crate')
        .toList();
    if (segments.isNotEmpty) {
      final joined = segments.join('/');
      for (final root in ['', 'src/', '$directory/']) {
        addPath('$root$joined.rs');
        addPath('$root$joined/mod.rs');
      }
      addPath('${segments.first}.rs');
      addPath('${segments.first}/mod.rs');
    }
  } else if (languageId == 'java' ||
      languageId == 'kotlin' ||
      languageId == 'csharp') {
    final segments = target.split('.');
    if (segments.isNotEmpty) {
      final last = segments.last;
      final byName = index.unique(index.byStem, last);
      addPath(byName);
    }
  } else {
    final relative = resolveRepoPath(directory, target);
    addPath(relative);
    if (relative != null) {
      for (final extension in const [
        'dart',
        'ts',
        'tsx',
        'js',
        'jsx',
        'rb',
        'php',
        'css',
        'scss',
        'h',
        'hpp',
        'go',
      ]) {
        addPath('$relative.$extension');
        addPath('$relative/index.$extension');
      }
    }
    addPath(target);
  }

  for (final candidate in candidates) {
    final hit = index.lookup(candidate);
    if (hit != null) {
      return hit;
    }
  }
  // A header or module named uniquely in the project still points at it.
  final name = target.split('/').last.split('::').last;
  if (name.contains('.')) {
    return index.unique(index.byName, name);
  }
  return null;
}
