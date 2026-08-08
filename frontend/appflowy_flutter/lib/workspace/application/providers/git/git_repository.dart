import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// Everything a repository can be asked to do, named once.
///
/// The interface offers these; it never composes a command line. That is the
/// whole point of the separation: nobody using AppFlowy has to know that a
/// rebase is `git rebase --autostash <upstream>`, and nothing they type is
/// ever read as part of a command.
enum GitAction {
  fetch,
  pull,
  push,
  commit,
  stash,
  applyStash,
  dropStash,
  createBranch,
  deleteBranch,
  checkoutBranch,
  renameBranch,
  merge,
  rebase,
  reset,
  discard;

  /// Whether doing this can lose work that has not been recorded anywhere.
  ///
  /// The interface explains and asks before any of these, and never runs one
  /// as a side effect of something else.
  bool get isDestructive => switch (this) {
        GitAction.reset ||
        GitAction.discard ||
        GitAction.dropStash ||
        GitAction.deleteBranch ||
        GitAction.rebase =>
          true,
        _ => false,
      };

  /// Whether it changes the remote, i.e. needs write access to be offered.
  bool get writesRemote => this == GitAction.push;
}

/// What one command did.
@immutable
class GitOutcome {
  const GitOutcome({
    required this.ok,
    this.stdout = '',
    this.stderr = '',
    this.exitCode = 0,
    this.conflicts = const <String>[],
  });

  final bool ok;
  final String stdout;
  final String stderr;
  final int exitCode;

  /// The files git says are in conflict, if any. A merge or a rebase that
  /// stops here is not a failure — it is a question.
  final List<String> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;

  /// The line worth showing. Git puts its real message on stderr even when
  /// nothing went wrong, so both are considered.
  String get message {
    final source = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
    if (source.isEmpty) {
      return '';
    }
    return source.split('\n').first.trim();
  }
}

/// One changed file in the working tree.
@immutable
class GitChange {
  const GitChange({
    required this.path,
    required this.indexStatus,
    required this.workTreeStatus,
    this.originalPath,
  });

  final String path;

  /// The letter git puts in the first column: what is staged.
  final String indexStatus;

  /// The second column: what is changed but not staged.
  final String workTreeStatus;

  /// Where a renamed file came from.
  final String? originalPath;

  bool get isStaged => indexStatus.trim().isNotEmpty && indexStatus != '?';
  bool get isUnstaged => workTreeStatus.trim().isNotEmpty;
  bool get isUntracked => indexStatus == '?' && workTreeStatus == '?';
  bool get isConflicted =>
      indexStatus == 'U' ||
      workTreeStatus == 'U' ||
      (indexStatus == 'A' && workTreeStatus == 'A') ||
      (indexStatus == 'D' && workTreeStatus == 'D');

  bool get isDeleted => indexStatus == 'D' || workTreeStatus == 'D';
  bool get isAdded => isUntracked || indexStatus == 'A';
  bool get isRenamed => indexStatus == 'R' || workTreeStatus == 'R';

  String get name => path.split('/').last;
}

/// The state of a working tree, as one answer.
@immutable
class GitStatus {
  const GitStatus({
    this.branch = '',
    this.upstream = '',
    this.ahead = 0,
    this.behind = 0,
    this.changes = const <GitChange>[],
    this.isDetached = false,
    this.operation = '',
  });

  static const empty = GitStatus();

  final String branch;
  final String upstream;
  final int ahead;
  final int behind;
  final List<GitChange> changes;
  final bool isDetached;

  /// A merge or rebase that is part way through, so the interface can offer to
  /// finish or abort it rather than pretending the tree is idle.
  final String operation;

  bool get isClean => changes.isEmpty;
  bool get hasConflicts => changes.any((change) => change.isConflicted);
  bool get hasStaged => changes.any((change) => change.isStaged);
  bool get canPush => ahead > 0;
  bool get canPull => behind > 0;
  bool get isMidOperation => operation.isNotEmpty;

  List<GitChange> get staged => [
        for (final change in changes)
          if (change.isStaged) change,
      ];

  List<GitChange> get unstaged => [
        for (final change in changes)
          if (change.isUnstaged || change.isUntracked) change,
      ];

  List<GitChange> get conflicted => [
        for (final change in changes)
          if (change.isConflicted) change,
      ];
}

@immutable
class GitStash {
  const GitStash({
    required this.index,
    required this.message,
    required this.branch,
  });

  final int index;
  final String message;
  final String branch;

  String get ref => 'stash@{$index}';
}

/// A git working tree on this machine, driven through the `git` executable.
///
/// Two rules hold everywhere in this class.
///
/// Every command is run with an explicit argument list and **no shell**, so a
/// branch name, a commit message or a path can never be read as a command
/// however it is spelled. Anything that could be mistaken for an option is
/// separated with `--`.
///
/// Nothing destructive happens by accident: this class exposes the operations,
/// and the interface above it explains and confirms the ones that can lose
/// work.
class GitRepository {
  GitRepository(this.workingDirectory);

  /// Long enough for a real fetch over a slow line, short enough that a
  /// credential prompt nobody can answer does not hang for ever.
  static const commandTimeout = Duration(minutes: 3);

  final String workingDirectory;

  static File? _git;
  static bool _searched = false;

  /// Where git is, or null when it is not installed.
  ///
  /// A repository with no git available shows its files and says plainly that
  /// the operations need git, rather than offering buttons that do nothing.
  static File? get executable {
    if (!_searched) {
      _searched = true;
      _git = resolveExecutable(const ['git']);
    }
    return _git;
  }

  static bool get isAvailable => executable != null;

  /// Forgets the search, so git installed while AppFlowy is running is found.
  static void rescan() {
    _searched = false;
    _git = null;
    clearExecutableCache();
  }

  /// Whether [directory] is inside a git working tree.
  static Future<String?> discover(String directory) async {
    if (!isAvailable || !Directory(directory).existsSync()) {
      return null;
    }
    final outcome = await GitRepository(directory)._run(
      const ['rev-parse', '--show-toplevel'],
    );
    if (!outcome.ok) {
      return null;
    }
    final root = outcome.stdout.trim();
    return root.isEmpty ? null : root;
  }

  // --- Reading ---------------------------------------------------------------

  Future<GitStatus> status() async {
    final outcome = await _run(const [
      'status',
      '--porcelain=v1',
      '--branch',
      '--untracked-files=all',
      '-z',
    ]);
    if (!outcome.ok) {
      return GitStatus.empty;
    }
    return parseStatus(outcome.stdout, operation: await _operationInProgress());
  }

  Future<List<GitBranch>> branches() async {
    final outcome = await _run(const [
      'for-each-ref',
      '--format=%(refname:short)%09%(objectname)%09%(upstream:short)%09%(HEAD)%09%(committerdate:iso8601)',
      'refs/heads',
      'refs/remotes',
    ]);
    if (!outcome.ok) {
      return const <GitBranch>[];
    }

    final branches = <GitBranch>[];
    for (final line in const LineSplitter().convert(outcome.stdout)) {
      final parts = line.split('\t');
      if (parts.isEmpty || parts.first.isEmpty) {
        continue;
      }
      final name = parts[0];
      if (name.endsWith('/HEAD')) {
        continue;
      }
      branches.add(
        GitBranch(
          name: name,
          sha: parts.length > 1 ? parts[1] : '',
          upstream: parts.length > 2 ? parts[2] : '',
          isCurrent: parts.length > 3 && parts[3].trim() == '*',
          isRemote: name.contains('/') && !_localNames(branches).contains(name),
          committedAt:
              parts.length > 4 ? DateTime.tryParse(parts[4].trim()) : null,
        ),
      );
    }
    return branches;
  }

  static Set<String> _localNames(List<GitBranch> branches) => {
        for (final branch in branches)
          if (!branch.isRemote) branch.name,
      };

  Future<List<GitLogEntry>> log({
    int limit = 60,
    String? path,
    String? branch,
  }) async {
    // A record separator git will never emit inside a field, so a commit
    // message containing anything at all still parses.
    const separator = '\u001e';
    const field = '\u001f';

    final outcome = await _run([
      'log',
      '--max-count=$limit',
      '--format=%H$field%an$field%ae$field%aI$field%P$field%s$field%b$separator',
      if (branch != null && branch.isNotEmpty) branch,
      if (path != null && path.isNotEmpty) ...['--', path],
    ]);
    if (!outcome.ok) {
      return const <GitLogEntry>[];
    }

    final entries = <GitLogEntry>[];
    for (final record in outcome.stdout.split(separator)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parts = trimmed.split(field);
      if (parts.length < 6) {
        continue;
      }
      entries.add(
        GitLogEntry(
          sha: parts[0],
          authorName: parts[1],
          authorEmail: parts[2],
          authoredAt: DateTime.tryParse(parts[3]),
          parents: parts[4].split(' ').where((p) => p.isNotEmpty).toList(),
          subject: parts[5],
          body: parts.length > 6 ? parts[6].trim() : '',
        ),
      );
    }
    return entries;
  }

  /// The diff of one file, or of everything when [path] is null.
  ///
  /// [staged] reads the index rather than the working tree, which is what a
  /// commit view has to show.
  Future<String> diff({String? path, bool staged = false}) async {
    final outcome = await _run([
      'diff',
      if (staged) '--cached',
      '--no-color',
      '--unified=3',
      if (path != null && path.isNotEmpty) ...['--', path],
    ]);
    return outcome.ok ? outcome.stdout : '';
  }

  /// The diff of a file git has never seen, which `git diff` will not produce.
  Future<String> diffUntracked(String path) async {
    final outcome = await _run([
      'diff',
      '--no-index',
      '--no-color',
      '--unified=3',
      '--',
      Platform.isWindows ? 'NUL' : '/dev/null',
      path,
    ]);
    // `--no-index` exits 1 when the files differ, which is the normal case.
    return outcome.stdout;
  }

  Future<List<GitStash>> stashes() async {
    final outcome = await _run(const [
      'stash',
      'list',
      '--format=%gd\u001f%gs',
    ]);
    if (!outcome.ok) {
      return const <GitStash>[];
    }

    final stashes = <GitStash>[];
    for (final line in const LineSplitter().convert(outcome.stdout)) {
      final parts = line.split('\u001f');
      if (parts.length < 2) {
        continue;
      }
      final index = RegExp(r'stash@\{(\d+)\}').firstMatch(parts[0]);
      final description = parts[1];
      final onBranch =
          RegExp('^(?:WIP on|On) ([^:]+):').firstMatch(description);
      stashes.add(
        GitStash(
          index: int.tryParse(index?.group(1) ?? '') ?? stashes.length,
          message: description,
          branch: onBranch?.group(1) ?? '',
        ),
      );
    }
    return stashes;
  }

  Future<List<GitRemote>> remotes() async {
    final outcome = await _run(const ['remote', '-v']);
    if (!outcome.ok) {
      return const <GitRemote>[];
    }
    final seen = <String, GitRemote>{};
    for (final line in const LineSplitter().convert(outcome.stdout)) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      seen.putIfAbsent(
        parts[0],
        () => GitRemote(name: parts[0], url: parts[1]),
      );
    }
    return seen.values.toList(growable: false);
  }

  // --- Writing ---------------------------------------------------------------

  Future<GitOutcome> fetch({String remote = 'origin'}) =>
      _run(['fetch', '--prune', '--', remote]);

  /// Pulls with a rebase and an autostash, which is the behaviour that leaves
  /// the fewest surprise merge commits and never refuses because of a local
  /// edit somebody forgot about.
  Future<GitOutcome> pull({String remote = 'origin'}) =>
      _run(['pull', '--rebase', '--autostash', '--', remote]);

  Future<GitOutcome> push({
    String remote = 'origin',
    String? branch,
    bool setUpstream = false,
  }) =>
      _run([
        'push',
        if (setUpstream) '--set-upstream',
        '--',
        remote,
        if (branch != null && branch.isNotEmpty) branch,
      ]);

  Future<GitOutcome> stage(List<String> paths) =>
      paths.isEmpty ? _ok() : _run(['add', '--', ...paths]);

  Future<GitOutcome> stageAll() => _run(const ['add', '--all']);

  Future<GitOutcome> unstage(List<String> paths) =>
      paths.isEmpty ? _ok() : _run(['restore', '--staged', '--', ...paths]);

  /// Commits what is staged.
  ///
  /// The message goes in through a file rather than an argument: it can be any
  /// length, contain any character, and never touches a command line.
  Future<GitOutcome> commit(String message, {bool amend = false}) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return const GitOutcome(
        ok: false,
        stderr: 'A commit needs a message.',
        exitCode: 1,
      );
    }

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'appflowy-commit-${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    try {
      await file.writeAsString(trimmed, flush: true);
      return await _run([
        'commit',
        if (amend) '--amend',
        '--file',
        file.path,
        '--cleanup=strip',
      ]);
    } finally {
      try {
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {
        // A leftover message file is harmless.
      }
    }
  }

  Future<GitOutcome> createStash({
    String message = '',
    bool keepIndex = false,
  }) =>
      _run([
        'stash',
        'push',
        if (keepIndex) '--keep-index',
        '--include-untracked',
        if (message.trim().isNotEmpty) ...['--message', message.trim()],
      ]);

  Future<GitOutcome> applyStash(GitStash stash, {bool drop = false}) =>
      _run(['stash', drop ? 'pop' : 'apply', stash.ref]);

  Future<GitOutcome> dropStash(GitStash stash) =>
      _run(['stash', 'drop', stash.ref]);

  Future<GitOutcome> createBranch(
    String name, {
    String? from,
    bool checkout = true,
  }) =>
      _run([
        if (checkout) ...['checkout', '-b'] else ...['branch'],
        '--',
        name,
        if (from != null && from.isNotEmpty) from,
      ]);

  Future<GitOutcome> checkoutBranch(String name) =>
      _run(['checkout', '--', name]);

  Future<GitOutcome> renameBranch(String from, String to) =>
      _run(['branch', '--move', '--', from, to]);

  /// Deletes a branch. [force] is only ever passed after the interface has said
  /// what would be lost and been told to go ahead.
  Future<GitOutcome> deleteBranch(String name, {bool force = false}) =>
      _run(['branch', force ? '-D' : '--delete', '--', name]);

  Future<GitOutcome> merge(String branch, {bool noFastForward = false}) =>
      _run([
        'merge',
        if (noFastForward) '--no-ff',
        '--no-edit',
        '--',
        branch,
      ]);

  Future<GitOutcome> rebase(String onto) =>
      _run(['rebase', '--autostash', '--', onto]);

  Future<GitOutcome> abort(String operation) => _run([operation, '--abort']);

  Future<GitOutcome> continueOperation(String operation) =>
      _run([operation, '--continue']);

  /// Moves the branch pointer. `--hard` throws away the working tree, so it is
  /// never the default and never reached without an explicit confirmation.
  Future<GitOutcome> reset(
    String ref, {
    GitResetMode mode = GitResetMode.mixed,
  }) =>
      _run(['reset', '--${mode.name}', '--', ref]);

  Future<GitOutcome> discard(List<String> paths) => paths.isEmpty
      ? _ok()
      : _run(['restore', '--staged', '--worktree', '--', ...paths]);

  /// Marks a conflict resolved by taking one side wholesale.
  Future<GitOutcome> resolveWith(String path, GitConflictSide side) async {
    final checkout = await _run([
      'checkout',
      side == GitConflictSide.ours ? '--ours' : '--theirs',
      '--',
      path,
    ]);
    if (!checkout.ok) {
      return checkout;
    }
    return _run(['add', '--', path]);
  }

  Future<GitOutcome> markResolved(List<String> paths) =>
      paths.isEmpty ? _ok() : _run(['add', '--', ...paths]);

  // --- Internals -------------------------------------------------------------

  Future<String> _operationInProgress() async {
    final gitDir = Directory('$workingDirectory${Platform.pathSeparator}.git');
    if (!gitDir.existsSync()) {
      return '';
    }
    final separator = Platform.pathSeparator;
    if (Directory('${gitDir.path}${separator}rebase-merge').existsSync() ||
        Directory('${gitDir.path}${separator}rebase-apply').existsSync()) {
      return 'rebase';
    }
    if (File('${gitDir.path}${separator}MERGE_HEAD').existsSync()) {
      return 'merge';
    }
    if (File('${gitDir.path}${separator}CHERRY_PICK_HEAD').existsSync()) {
      return 'cherry-pick';
    }
    return '';
  }

  Future<GitOutcome> _ok() async => const GitOutcome(ok: true);

  Future<GitOutcome> _run(List<String> arguments) async {
    final git = executable;
    if (git == null) {
      return const GitOutcome(
        ok: false,
        stderr: 'git is not installed on this computer.',
        exitCode: 127,
      );
    }

    try {
      final result = await Process.run(
        git.path,
        arguments,
        workingDirectory: workingDirectory,
        // `runInShell` is left at its default of false on purpose: nothing
        // here goes near a command interpreter, so an argument is an argument
        // whatever is in it.
        stdoutEncoding: null,
        stderrEncoding: null,
        environment: const {
          // A credential prompt has nobody to answer it here, so git must fail
          // rather than block for ever waiting on a terminal.
          'GIT_TERMINAL_PROMPT': '0',
          'GIT_ASKPASS': '',
          'GCM_INTERACTIVE': 'never',
          // Git's own output is what is parsed, so it must not be localised.
          'LC_ALL': 'C',
        },
      ).timeout(commandTimeout);

      // Git writes paths and messages in whatever encoding the tree uses, so
      // malformed bytes are tolerated rather than throwing.
      const decoder = Utf8Decoder(allowMalformed: true);
      final stdout = decoder.convert(result.stdout as List<int>);
      final stderr = decoder.convert(result.stderr as List<int>);

      return GitOutcome(
        ok: result.exitCode == 0,
        stdout: stdout,
        stderr: stderr,
        exitCode: result.exitCode,
        conflicts: _conflictsIn('$stdout\n$stderr'),
      );
    } on TimeoutException {
      return const GitOutcome(
        ok: false,
        stderr: 'The operation took too long and was stopped.',
        exitCode: 124,
      );
    } catch (error) {
      Log.warn('A git command failed: $error');
      return GitOutcome(ok: false, stderr: '$error', exitCode: 1);
    }
  }

  static List<String> _conflictsIn(String output) {
    final conflicts = <String>{};
    final pattern = RegExp(
      r'^(?:CONFLICT \([^)]*\): Merge conflict in |Auto-merging )(.+)$',
      multiLine: true,
    );
    for (final match in pattern.allMatches(output)) {
      final path = match.group(1)?.trim();
      if (path != null && path.isNotEmpty && output.contains('CONFLICT')) {
        conflicts.add(path);
      }
    }
    return conflicts.toList(growable: false);
  }

  /// Reads `git status --porcelain=v1 --branch -z`.
  ///
  /// The `-z` form is the only one that survives a file name containing a
  /// space, a quote or a newline, which is exactly the case a naive parser
  /// gets wrong. Public because it is the part most worth pinning in a test.
  static GitStatus parseStatus(String output, {String operation = ''}) {
    final records = output.split('\u0000');
    var branch = '';
    var upstream = '';
    var ahead = 0;
    var behind = 0;
    var detached = false;
    final changes = <GitChange>[];

    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      if (record.isEmpty) {
        continue;
      }

      if (record.startsWith('##')) {
        final header = record.substring(2).trim();
        if (header.startsWith('HEAD (no branch)')) {
          detached = true;
          continue;
        }
        final tracking = header.split(RegExp(r'\s+\['));
        final names = tracking.first.split('...');
        branch = names.first.trim();
        upstream = names.length > 1 ? names[1].trim() : '';
        if (tracking.length > 1) {
          final aheadMatch = RegExp(r'ahead (\d+)').firstMatch(tracking[1]);
          final behindMatch = RegExp(r'behind (\d+)').firstMatch(tracking[1]);
          ahead = int.tryParse(aheadMatch?.group(1) ?? '') ?? 0;
          behind = int.tryParse(behindMatch?.group(1) ?? '') ?? 0;
        }
        continue;
      }

      if (record.length < 3) {
        continue;
      }
      final indexStatus = record[0];
      final workTreeStatus = record[1];
      final path = record.substring(3);

      // A rename is two records: the new name, then the old one.
      String? originalPath;
      if (indexStatus == 'R' || workTreeStatus == 'R') {
        if (index + 1 < records.length) {
          originalPath = records[index + 1];
          index++;
        }
      }

      changes.add(
        GitChange(
          path: path,
          indexStatus: indexStatus,
          workTreeStatus: workTreeStatus,
          originalPath: originalPath,
        ),
      );
    }

    return GitStatus(
      branch: branch,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      changes: changes,
      isDetached: detached,
      operation: operation,
    );
  }
}

enum GitResetMode { soft, mixed, hard }

enum GitConflictSide { ours, theirs }

@immutable
class GitBranch {
  const GitBranch({
    required this.name,
    this.sha = '',
    this.upstream = '',
    this.isCurrent = false,
    this.isRemote = false,
    this.committedAt,
  });

  final String name;
  final String sha;
  final String upstream;
  final bool isCurrent;
  final bool isRemote;
  final DateTime? committedAt;

  String get shortName =>
      isRemote && name.contains('/') ? name.split('/').skip(1).join('/') : name;

  bool get isTracking => upstream.isNotEmpty;
}

@immutable
class GitLogEntry {
  const GitLogEntry({
    required this.sha,
    required this.subject,
    required this.authorName,
    this.authorEmail = '',
    this.authoredAt,
    this.body = '',
    this.parents = const <String>[],
  });

  final String sha;
  final String subject;
  final String authorName;
  final String authorEmail;
  final DateTime? authoredAt;
  final String body;
  final List<String> parents;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  bool get isMerge => parents.length > 1;
}

@immutable
class GitRemote {
  const GitRemote({required this.name, required this.url});

  final String name;
  final String url;
}
