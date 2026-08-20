import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// What each action did, the last few times it ran.
///
/// ⚠️ Not a nicety. An action that quietly stops working is indistinguishable
/// from one that was never written, and this codebase has repeatedly lost days
/// to failures that reported nothing. The log is also where the scheduler gets
/// "when did this last run", which is what makes catch-up on launch possible.
class ExtensionRunLog extends ChangeNotifier {
  ExtensionRunLog({this.rootOverride});

  static final ExtensionRunLog instance = ExtensionRunLog();

  static const fileName = 'runs.json';

  /// How many runs are kept per extension. Enough to see a pattern, few enough
  /// that the file stays small.
  static const maximumRuns = 80;

  @visibleForTesting
  final String? rootOverride;

  final Map<String, List<ActionRun>> _runs = {};
  final Set<String> _dirty = {};

  Timer? _persist;
  bool _loaded = false;
  Future<void>? _loading;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const persistDebounce = Duration(seconds: 2);

  Future<String> _resolveRoot() async =>
      rootOverride ?? await ExtensionDataStore.instance.resolveRoot();

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final root = Directory(await _resolveRoot());
      if (root.existsSync()) {
        await for (final entity in root.list()) {
          if (entity is! Directory) {
            continue;
          }
          final file = File(p.join(entity.path, fileName));
          if (!file.existsSync()) {
            continue;
          }
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is! List) {
            continue;
          }
          final parsed = <ActionRun>[
            for (final entry in decoded)
              if (entry is Map)
                if (ActionRun.fromJson(Map<String, Object?>.from(entry))
                    case final run?)
                  run,
          ];
          if (parsed.isNotEmpty) {
            _runs[p.basename(entity.path)] = parsed;
          }
        }
      }
      _loaded = true;
    } on Object catch (error) {
      Log.warn('Extension run log could not be read: $error');
    } finally {
      _loading = null;
    }
    if (_loaded) {
      _raise();
    }
  }

  /// Newest first.
  List<ActionRun> runsFor(String extensionId, {String? actionId}) {
    final all = _runs[extensionId] ?? const <ActionRun>[];
    if (actionId == null) {
      return List.unmodifiable(all);
    }
    return List.unmodifiable(
      all.where((run) => run.actionId == actionId),
    );
  }

  ActionRun? lastRunOf(String extensionId, String actionId) {
    for (final run in _runs[extensionId] ?? const <ActionRun>[]) {
      if (run.actionId == actionId) {
        return run;
      }
    }
    return null;
  }

  /// When this action last STARTED, whatever came of it.
  ///
  /// A failed run still counts: a service that is refusing must not be
  /// hammered once a frame because the failure never updated the clock.
  DateTime? lastAttemptOf(String extensionId, String actionId) =>
      lastRunOf(extensionId, actionId)?.startedAt;

  void record(ActionRun run) {
    final list = _runs.putIfAbsent(run.extensionId, () => <ActionRun>[])
      ..insert(0, run);
    if (list.length > maximumRuns) {
      list.removeRange(maximumRuns, list.length);
    }
    _dirty.add(run.extensionId);
    _schedulePersist();
    _raise();
  }

  /// Replaces the newest record for an action that was left `running`.
  void complete(ActionRun run) {
    final list = _runs[run.extensionId];
    if (list == null) {
      record(run);
      return;
    }
    final at = list.indexWhere(
      (existing) =>
          existing.actionId == run.actionId &&
          existing.startedAt == run.startedAt,
    );
    if (at < 0) {
      record(run);
      return;
    }
    list[at] = run;
    _dirty.add(run.extensionId);
    _schedulePersist();
    _raise();
  }

  Future<void> clear(String extensionId) async {
    if (_runs.remove(extensionId) == null) {
      return;
    }
    _dirty.add(extensionId);
    _schedulePersist();
    _raise();
  }

  Future<void> flush() async {
    _persist?.cancel();
    _persist = null;
    if (_dirty.isEmpty) {
      return;
    }
    final owners = _dirty.toList();
    _dirty.clear();
    for (final owner in owners) {
      await _write(owner);
    }
  }

  void _schedulePersist() {
    _persist?.cancel();
    _persist = Timer(persistDebounce, () {
      _persist = null;
      unawaited(flush());
    });
  }

  Future<void> _write(String extensionId) async {
    try {
      final folder = Directory(p.join(await _resolveRoot(), extensionId));
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, fileName));
      final runs = _runs[extensionId] ?? const <ActionRun>[];
      if (runs.isEmpty) {
        if (file.existsSync()) {
          await file.delete();
        }
        return;
      }
      await file.writeAsString(
        jsonEncode([for (final run in runs) run.toJson()]),
      );
    } on Object catch (error) {
      Log.warn('Run log for $extensionId could not be written: $error');
    }
  }

  void _raise() {
    revision.value = revision.value + 1;
    notifyListeners();
  }

  @override
  void dispose() {
    _persist?.cancel();
    revision.dispose();
    super.dispose();
  }
}
