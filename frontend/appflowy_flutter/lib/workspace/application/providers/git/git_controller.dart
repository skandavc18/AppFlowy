import 'dart:async';
import 'dart:io';

import 'package:appflowy/workspace/application/providers/git/git_diff.dart';
import 'package:appflowy/workspace/application/providers/git/git_repository.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The state of one working tree, and every operation on it.
///
/// The interface talks to this and never to [GitRepository] directly, so
/// "refresh afterwards", "do not run two things at once" and "a destructive
/// operation was confirmed" are decided once rather than at every button.
class GitController extends ChangeNotifier {
  GitController(this.workingDirectory)
      : repository = GitRepository(workingDirectory);

  final String workingDirectory;
  final GitRepository repository;

  GitStatus status = GitStatus.empty;
  List<GitBranch> branches = const <GitBranch>[];
  List<GitLogEntry> log = const <GitLogEntry>[];
  List<GitStash> stashes = const <GitStash>[];
  List<GitRemote> remotes = const <GitRemote>[];

  String? selectedPath;
  List<GitFileDiff> diff = const <GitFileDiff>[];

  bool busy = false;
  bool loading = true;

  /// The last thing an operation said, for the strip above the panel. Cleared
  /// as soon as anything else happens.
  String notice = '';
  bool noticeIsFailure = false;

  bool get isAvailable => GitRepository.isAvailable;

  List<GitBranch> get localBranches => [
        for (final branch in branches)
          if (!branch.isRemote) branch,
      ];

  GitBranch? get currentBranch {
    for (final branch in branches) {
      if (branch.isCurrent) {
        return branch;
      }
    }
    return null;
  }

  Future<void> refresh() async {
    if (!isAvailable) {
      loading = false;
      notifyListeners();
      return;
    }

    final results = await Future.wait([
      repository.status(),
      repository.branches(),
      repository.log(),
      repository.stashes(),
      repository.remotes(),
    ]);

    status = results[0] as GitStatus;
    branches = results[1] as List<GitBranch>;
    log = results[2] as List<GitLogEntry>;
    stashes = results[3] as List<GitStash>;
    remotes = results[4] as List<GitRemote>;
    loading = false;

    // Keep the selection only while the file is still changed; otherwise the
    // diff pane would show a file nobody is looking at any more.
    if (selectedPath != null &&
        !status.changes.any((change) => change.path == selectedPath)) {
      selectedPath = null;
      diff = const <GitFileDiff>[];
    }
    notifyListeners();

    if (selectedPath != null) {
      await select(selectedPath!);
    }
  }

  /// Reads the diff of one file. Untracked files need their own command, and a
  /// staged file is read from the index rather than the working tree.
  Future<void> select(String path) async {
    selectedPath = path;
    notifyListeners();

    final change = _changeFor(path);
    try {
      final text = change != null && change.isUntracked
          ? await repository.diffUntracked(p.join(workingDirectory, path))
          : await repository.diff(
              path: path,
              staged: change?.isStaged ?? false,
            );
      // A file that is both staged and edited has two diffs; showing the
      // working tree one as well is what somebody actually wants to see.
      final extra = change != null && change.isStaged && change.isUnstaged
          ? await repository.diff(path: path)
          : '';
      diff = parseUnifiedDiff('$text\n$extra');
    } catch (error) {
      Log.warn('Unable to read a diff: $error');
      diff = const <GitFileDiff>[];
    }
    notifyListeners();
  }

  GitChange? _changeFor(String path) {
    for (final change in status.changes) {
      if (change.path == path) {
        return change;
      }
    }
    return null;
  }

  // --- Operations ------------------------------------------------------------

  Future<bool> stage(List<String> paths) => _run(() => repository.stage(paths));

  Future<bool> stageAll() => _run(repository.stageAll);

  Future<bool> unstage(List<String> paths) =>
      _run(() => repository.unstage(paths));

  Future<bool> commit(String message, {bool amend = false}) =>
      _run(() => repository.commit(message, amend: amend));

  Future<bool> fetch() => _run(repository.fetch);

  Future<bool> pull() => _run(repository.pull);

  Future<bool> push({bool setUpstream = false}) => _run(
        () => repository.push(
          branch: status.branch,
          setUpstream: setUpstream || status.upstream.isEmpty,
        ),
      );

  Future<bool> createStash([String message = '']) =>
      _run(() => repository.createStash(message: message));

  Future<bool> applyStash(GitStash stash, {bool drop = false}) =>
      _run(() => repository.applyStash(stash, drop: drop));

  Future<bool> dropStash(GitStash stash) =>
      _run(() => repository.dropStash(stash));

  Future<bool> createBranch(String name, {String? from}) =>
      _run(() => repository.createBranch(name, from: from));

  Future<bool> checkout(String name) =>
      _run(() => repository.checkoutBranch(name));

  Future<bool> renameBranch(String from, String to) =>
      _run(() => repository.renameBranch(from, to));

  Future<bool> deleteBranch(String name, {bool force = false}) =>
      _run(() => repository.deleteBranch(name, force: force));

  Future<bool> merge(String branch) => _run(() => repository.merge(branch));

  Future<bool> rebase(String onto) => _run(() => repository.rebase(onto));

  Future<bool> abort() => _run(
        () => repository.abort(
          status.operation.isEmpty ? 'merge' : status.operation,
        ),
      );

  Future<bool> continueOperation() => _run(
        () => repository.continueOperation(
          status.operation.isEmpty ? 'merge' : status.operation,
        ),
      );

  Future<bool> discard(List<String> paths) =>
      _run(() => repository.discard(paths));

  Future<bool> resolveWith(String path, GitConflictSide side) =>
      _run(() => repository.resolveWith(path, side));

  Future<bool> markResolved(List<String> paths) =>
      _run(() => repository.markResolved(paths));

  /// Reads a conflicted file so both sides can be shown.
  Future<GitConflictedFile?> readConflict(String path) async {
    try {
      final file = File(p.join(workingDirectory, path));
      if (!file.existsSync()) {
        return null;
      }
      return parseConflicts(await file.readAsString());
    } catch (error) {
      Log.warn('Unable to read a conflicted file: $error');
      return null;
    }
  }

  /// Writes a resolution back and marks the file resolved.
  Future<bool> writeResolution(String path, String content) async {
    if (!await writeResolutionOnly(path, content)) {
      return false;
    }
    return markResolved([path]);
  }

  /// Writes a resolution back without marking anything.
  ///
  /// Resolving one block of a file that has several is not the same as
  /// finishing the file, and staging it early would hide the rest.
  Future<bool> writeResolutionOnly(String path, String content) async {
    try {
      await File(p.join(workingDirectory, path)).writeAsString(content);
      notifyListeners();
      return true;
    } catch (error) {
      Log.warn('Unable to write a resolution: $error');
      return false;
    }
  }

  Future<bool> _run(Future<GitOutcome> Function() action) async {
    if (busy) {
      return false;
    }
    busy = true;
    notice = '';
    notifyListeners();

    GitOutcome outcome;
    try {
      outcome = await action();
    } catch (error) {
      Log.warn('A git operation failed: $error');
      outcome = GitOutcome(ok: false, stderr: '$error', exitCode: 1);
    }

    busy = false;
    // A merge or rebase that stops on a conflict is not a failure; the panel
    // switches to the resolution view rather than reporting an error.
    noticeIsFailure = !outcome.ok && !outcome.hasConflicts;
    notice = outcome.message;
    notifyListeners();

    await refresh();
    return outcome.ok;
  }
}
