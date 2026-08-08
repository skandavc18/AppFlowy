import 'package:flutter/foundation.dart';

/// What one line of a diff is.
enum GitDiffLineKind {
  context,
  addition,
  deletion,

  /// The `@@ -1,7 +1,9 @@` line that opens a hunk.
  hunkHeader,

  /// `\ No newline at end of file` and friends.
  note,
}

@immutable
class GitDiffLine {
  const GitDiffLine({
    required this.kind,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final GitDiffLineKind kind;

  /// The line without its leading `+`, `-` or space.
  final String text;

  final int? oldLineNumber;
  final int? newLineNumber;

  bool get isChange =>
      kind == GitDiffLineKind.addition || kind == GitDiffLineKind.deletion;
}

@immutable
class GitDiffHunk {
  const GitDiffHunk({
    required this.header,
    required this.lines,
    this.oldStart = 0,
    this.oldCount = 0,
    this.newStart = 0,
    this.newCount = 0,
  });

  final String header;
  final List<GitDiffLine> lines;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;

  /// The bit of context git puts after the `@@`, usually the enclosing
  /// function. It is what makes a long diff readable.
  String get context {
    final marker = header.lastIndexOf('@@');
    if (marker < 0 || marker + 2 >= header.length) {
      return '';
    }
    return header.substring(marker + 2).trim();
  }
}

/// One file's worth of diff.
@immutable
class GitFileDiff {
  const GitFileDiff({
    required this.path,
    required this.hunks,
    this.oldPath,
    this.isBinary = false,
    this.isNew = false,
    this.isDeleted = false,
    this.isRenamed = false,
    this.mode = '',
  });

  final String path;
  final List<GitDiffHunk> hunks;
  final String? oldPath;
  final bool isBinary;
  final bool isNew;
  final bool isDeleted;
  final bool isRenamed;
  final String mode;

  String get name => path.split('/').last;

  String get directory {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  int get additions => _count(GitDiffLineKind.addition);
  int get deletions => _count(GitDiffLineKind.deletion);

  bool get isEmpty => hunks.isEmpty && !isBinary;

  int _count(GitDiffLineKind kind) {
    var total = 0;
    for (final hunk in hunks) {
      for (final line in hunk.lines) {
        if (line.kind == kind) {
          total++;
        }
      }
    }
    return total;
  }
}

/// Reads a unified diff.
///
/// Written as a plain state machine over the lines rather than with regular
/// expressions over the whole text: a diff's own content contains lines that
/// look exactly like diff syntax — a patch inside a patch, a test fixture, a
/// commit message quoted in a file — and only the position in the stream tells
/// them apart.
List<GitFileDiff> parseUnifiedDiff(String diff) {
  if (diff.trim().isEmpty) {
    return const <GitFileDiff>[];
  }

  final files = <GitFileDiff>[];
  final lines = diff.split('\n');

  String? path;
  String? oldPath;
  var isBinary = false;
  var isNew = false;
  var isDeleted = false;
  var isRenamed = false;
  var mode = '';
  var hunks = <GitDiffHunk>[];
  var hunkLines = <GitDiffLine>[];
  var hunkHeader = '';
  var oldStart = 0;
  var oldCount = 0;
  var newStart = 0;
  var newCount = 0;
  var oldLine = 0;
  var newLine = 0;

  void closeHunk() {
    if (hunkHeader.isEmpty) {
      return;
    }
    hunks.add(
      GitDiffHunk(
        header: hunkHeader,
        lines: List<GitDiffLine>.unmodifiable(hunkLines),
        oldStart: oldStart,
        oldCount: oldCount,
        newStart: newStart,
        newCount: newCount,
      ),
    );
    hunkLines = <GitDiffLine>[];
    hunkHeader = '';
  }

  void closeFile() {
    closeHunk();
    if (path == null) {
      return;
    }
    files.add(
      GitFileDiff(
        path: path!,
        oldPath: oldPath,
        hunks: List<GitDiffHunk>.unmodifiable(hunks),
        isBinary: isBinary,
        isNew: isNew,
        isDeleted: isDeleted,
        isRenamed: isRenamed,
        mode: mode,
      ),
    );
    hunks = <GitDiffHunk>[];
    path = null;
    oldPath = null;
    isBinary = false;
    isNew = false;
    isDeleted = false;
    isRenamed = false;
    mode = '';
  }

  for (final line in lines) {
    if (line.startsWith('diff --git ')) {
      closeFile();
      path = _pathFromDiffHeader(line);
      continue;
    }

    // Only trust a header line while no hunk is open; inside a hunk every line
    // is content, whatever it starts with.
    if (hunkHeader.isEmpty) {
      if (line.startsWith('new file mode')) {
        isNew = true;
        mode = line.substring('new file mode'.length).trim();
        continue;
      }
      if (line.startsWith('deleted file mode')) {
        isDeleted = true;
        mode = line.substring('deleted file mode'.length).trim();
        continue;
      }
      if (line.startsWith('rename from ')) {
        isRenamed = true;
        oldPath = line.substring('rename from '.length).trim();
        continue;
      }
      if (line.startsWith('rename to ')) {
        isRenamed = true;
        path = line.substring('rename to '.length).trim();
        continue;
      }
      if (line.startsWith('Binary files ') ||
          line.startsWith('GIT binary patch')) {
        isBinary = true;
        continue;
      }
      if (line.startsWith('--- ')) {
        final from = line.substring(4).trim();
        if (from != '/dev/null') {
          oldPath ??= _stripPrefix(from);
        }
        continue;
      }
      if (line.startsWith('+++ ')) {
        final to = line.substring(4).trim();
        if (to == '/dev/null') {
          isDeleted = true;
        } else {
          path ??= _stripPrefix(to);
        }
        continue;
      }
      if (line.startsWith('index ') || line.startsWith('similarity index ')) {
        continue;
      }
    }

    if (line.startsWith('@@')) {
      closeHunk();
      final range = _parseHunkRange(line);
      hunkHeader = line;
      oldStart = range.oldStart;
      oldCount = range.oldCount;
      newStart = range.newStart;
      newCount = range.newCount;
      oldLine = oldStart;
      newLine = newStart;
      hunkLines.add(GitDiffLine(kind: GitDiffLineKind.hunkHeader, text: line));
      continue;
    }

    if (hunkHeader.isEmpty) {
      continue;
    }

    if (line.startsWith(r'\')) {
      hunkLines.add(
        GitDiffLine(kind: GitDiffLineKind.note, text: line.substring(1).trim()),
      );
      continue;
    }

    if (line.startsWith('+')) {
      hunkLines.add(
        GitDiffLine(
          kind: GitDiffLineKind.addition,
          text: line.substring(1),
          newLineNumber: newLine++,
        ),
      );
      continue;
    }
    if (line.startsWith('-')) {
      hunkLines.add(
        GitDiffLine(
          kind: GitDiffLineKind.deletion,
          text: line.substring(1),
          oldLineNumber: oldLine++,
        ),
      );
      continue;
    }
    if (line.startsWith(' ') || line.isEmpty) {
      hunkLines.add(
        GitDiffLine(
          kind: GitDiffLineKind.context,
          text: line.isEmpty ? '' : line.substring(1),
          oldLineNumber: oldLine++,
          newLineNumber: newLine++,
        ),
      );
      continue;
    }
  }

  closeFile();
  return files;
}

/// A conflicted file, split into the two sides so the interface can show them
/// beside each other rather than making somebody read the markers.
@immutable
class GitConflictBlock {
  const GitConflictBlock({
    required this.ours,
    required this.theirs,
    this.base = const <String>[],
    this.oursLabel = '',
    this.theirsLabel = '',
    this.startLine = 0,
  });

  final List<String> ours;
  final List<String> theirs;

  /// The common ancestor, present only in a diff3-style conflict.
  final List<String> base;

  final String oursLabel;
  final String theirsLabel;
  final int startLine;
}

@immutable
class GitConflictedFile {
  const GitConflictedFile({
    required this.lines,
    required this.blocks,
  });

  /// Every line of the file, markers included, so a resolution can be written
  /// back exactly.
  final List<String> lines;

  final List<GitConflictBlock> blocks;

  bool get hasConflicts => blocks.isNotEmpty;
}

/// Splits a file that git left conflict markers in.
///
/// `<<<<<<<` … `|||||||` … `=======` … `>>>>>>>` — the middle section only
/// appears with diff3 style, and both forms have to parse or a resolution
/// screen shows nothing for half of everybody's repositories.
GitConflictedFile parseConflicts(String content) {
  final lines = content.split('\n');
  final blocks = <GitConflictBlock>[];

  var index = 0;
  while (index < lines.length) {
    if (!lines[index].startsWith('<<<<<<<')) {
      index++;
      continue;
    }

    final startLine = index;
    final oursLabel = lines[index].substring(7).trim();
    final ours = <String>[];
    final base = <String>[];
    final theirs = <String>[];
    var theirsLabel = '';
    var section = 0;
    index++;

    while (index < lines.length) {
      final line = lines[index];
      if (line.startsWith('|||||||')) {
        section = 1;
        index++;
        continue;
      }
      if (line.startsWith('=======') && line.trim() == '=======') {
        section = 2;
        index++;
        continue;
      }
      if (line.startsWith('>>>>>>>')) {
        theirsLabel = line.substring(7).trim();
        index++;
        break;
      }
      switch (section) {
        case 0:
          ours.add(line);
        case 1:
          base.add(line);
        default:
          theirs.add(line);
      }
      index++;
    }

    blocks.add(
      GitConflictBlock(
        ours: List<String>.unmodifiable(ours),
        theirs: List<String>.unmodifiable(theirs),
        base: List<String>.unmodifiable(base),
        oursLabel: oursLabel,
        theirsLabel: theirsLabel,
        startLine: startLine,
      ),
    );
  }

  return GitConflictedFile(
    lines: List<String>.unmodifiable(lines),
    blocks: List<GitConflictBlock>.unmodifiable(blocks),
  );
}

/// Rewrites a conflicted file taking one side of every block.
String resolveConflictsWith(GitConflictedFile file, {required bool ours}) {
  if (!file.hasConflicts) {
    return file.lines.join('\n');
  }

  final output = <String>[];
  var index = 0;
  var block = 0;

  while (index < file.lines.length) {
    if (block < file.blocks.length && index == file.blocks[block].startLine) {
      final chosen = ours ? file.blocks[block].ours : file.blocks[block].theirs;
      output.addAll(chosen);
      // Skip to just past the closing marker of this block.
      index = _endOfBlock(file.lines, index);
      block++;
      continue;
    }
    output.add(file.lines[index]);
    index++;
  }
  return output.join('\n');
}

int _endOfBlock(List<String> lines, int start) {
  var index = start;
  while (index < lines.length) {
    if (lines[index].startsWith('>>>>>>>')) {
      return index + 1;
    }
    index++;
  }
  return lines.length;
}

({int oldStart, int oldCount, int newStart, int newCount}) _parseHunkRange(
  String header,
) {
  final match =
      RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@').firstMatch(header);
  if (match == null) {
    return (oldStart: 0, oldCount: 0, newStart: 0, newCount: 0);
  }
  return (
    oldStart: int.tryParse(match.group(1) ?? '') ?? 0,
    oldCount: int.tryParse(match.group(2) ?? '1') ?? 1,
    newStart: int.tryParse(match.group(3) ?? '') ?? 0,
    newCount: int.tryParse(match.group(4) ?? '1') ?? 1,
  );
}

/// `diff --git a/lib/main.dart b/lib/main.dart` — and the awkward case where
/// the path itself contains ` b/`, which is why the second half is preferred
/// and the prefix is stripped rather than the line being split naively.
String? _pathFromDiffHeader(String line) {
  final rest = line.substring('diff --git '.length).trim();
  final marker = rest.lastIndexOf(' b/');
  if (marker < 0) {
    return null;
  }
  return _stripPrefix(rest.substring(marker + 1));
}

String _stripPrefix(String path) {
  var value = path.trim();
  // `git diff` quotes a path containing anything unusual.
  if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
    value = value.substring(1, value.length - 1);
  }
  if (value.startsWith('a/') || value.startsWith('b/')) {
    return value.substring(2);
  }
  return value;
}
