import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/extension_manifest.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One extension folder, read.
@immutable
class LoadedExtension {
  const LoadedExtension({
    required this.manifest,
    required this.folder,
    this.actions = const [],
    this.problems = const [],
  });

  final ExtensionManifest manifest;
  final String folder;
  final List<ActionDefinition> actions;

  /// What could not be read. ⚠️ Reported rather than swallowed: a recipe with
  /// a typo that silently does not exist is indistinguishable from one that
  /// runs and does nothing.
  final List<String> problems;

  String get id => manifest.id;

  ActionDefinition? actionFor(String actionId) {
    for (final action in actions) {
      if (action.id == actionId) {
        return action;
      }
    }
    return null;
  }

  List<ActionDefinition> get scheduledActions => [
        for (final action in actions)
          if (action.enabled && action.trigger.isScheduled) action,
      ];
}

/// Reads the extensions folder, and watches it so a recipe can be edited
/// without restarting the app.
class ExtensionStore extends ChangeNotifier {
  ExtensionStore({this.rootOverride});

  static final ExtensionStore instance = ExtensionStore();

  static const folderName = 'extensions';
  static const manifestFileName = 'manifest.json';
  static const actionsFolderName = 'actions';

  static const enabledKey = 'appflowy_extensions_disabled';

  /// A change is followed by more changes — an editor writes a file in
  /// several goes — so the folder settles before it is read.
  static const watchDebounce = Duration(milliseconds: 500);

  @visibleForTesting
  final String? rootOverride;

  final List<LoadedExtension> _extensions = [];
  final Set<String> _disabled = {};

  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _settle;
  String? _root;
  bool _loading = false;
  bool _loaded = false;

  List<LoadedExtension> get extensions => List.unmodifiable(_extensions);

  bool get isLoaded => _loaded;

  bool get isLoading => _loading;

  /// The ones actually in force.
  List<LoadedExtension> get active => [
        for (final extension in _extensions)
          if (isEnabled(extension.id) && extension.manifest.isSupported)
            extension,
      ];

  LoadedExtension? byId(String id) {
    for (final extension in _extensions) {
      if (extension.id == id) {
        return extension;
      }
    }
    return null;
  }

  bool isEnabled(String id) => !_disabled.contains(id);

  Future<String> resolveRoot() async {
    final override = rootOverride;
    if (override != null) {
      return override;
    }
    final cached = _root;
    if (cached != null) {
      return cached;
    }
    String base;
    try {
      base = await getIt<ApplicationDataStorage>().getPath();
    } on Object catch (_) {
      base = (await getApplicationSupportDirectory()).path;
    }
    final root = p.join(base, folderName);
    await Directory(root).create(recursive: true);
    return _root = root;
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) {
      return;
    }
    await reload();
  }

  Future<void> reload() async {
    if (_loading) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      await _readDisabled();
      final root = Directory(await resolveRoot());
      final found = <LoadedExtension>[];
      if (root.existsSync()) {
        final folders = <Directory>[
          await for (final entity in root.list())
            if (entity is Directory) entity,
        ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
        for (final folder in folders) {
          final loaded = await _readFolder(folder);
          if (loaded != null) {
            found.add(loaded);
          }
        }
      }
      _extensions
        ..clear()
        ..addAll(found);
      _loaded = true;
    } on Object catch (error) {
      Log.warn('The extensions folder could not be read: $error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<LoadedExtension?> _readFolder(Directory folder) async {
    final manifestFile = File(p.join(folder.path, manifestFileName));
    if (!manifestFile.existsSync()) {
      return null;
    }

    final problems = <String>[];
    ExtensionManifest? manifest;
    try {
      manifest = ExtensionManifest.fromJson(
        decodeExtensionJson(await manifestFile.readAsString()),
      );
    } on Object catch (error) {
      problems.add('manifest.json could not be read: $error');
    }

    if (manifest == null) {
      final name = p.basename(folder.path);
      Log.warn('Extension $name has no usable manifest.');
      return LoadedExtension(
        manifest: ExtensionManifest(id: _safeId(name), name: name),
        folder: folder.path,
        problems: problems.isEmpty
            ? const ['manifest.json is missing an id.']
            : problems,
      );
    }

    if (!manifest.isSupported) {
      problems.add(
        'Written for extension API ${manifest.apiVersion}; this AppFlowy '
        'understands ${ExtensionManifest.currentApiVersion}.',
      );
    }

    final actions = <ActionDefinition>[];
    final actionsFolder = Directory(p.join(folder.path, actionsFolderName));
    if (actionsFolder.existsSync()) {
      final files = <File>[
        await for (final entity in actionsFolder.list())
          if (entity is File && p.extension(entity.path) == '.json') entity,
      ]..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final name = p.basename(file.path);
        try {
          final parsed = ActionDefinition.fromJson(
            decodeExtensionJson(await file.readAsString()),
          );
          if (parsed == null) {
            problems.add('$name has no usable id.');
            continue;
          }
          if (actions.any((action) => action.id == parsed.id)) {
            problems.add('$name declares "${parsed.id}" a second time.');
            continue;
          }
          if (parsed.steps.isEmpty) {
            problems.add('$name has no steps that could be read.');
          }
          actions.add(parsed);
        } on Object catch (error) {
          problems.add('$name could not be read: $error');
        }
      }
    }

    return LoadedExtension(
      manifest: manifest,
      folder: folder.path,
      actions: actions,
      problems: problems,
    );
  }

  Future<void> setEnabled(String id, bool enabled) async {
    if (enabled) {
      _disabled.remove(id);
    } else {
      _disabled.add(id);
    }
    await _writeDisabled();
    notifyListeners();
  }

  /// Watches the folder so an edited recipe is picked up at once. That is the
  /// whole development loop for an action, and it is why they are not Dart.
  Future<void> startWatching() async {
    if (_watcher != null) {
      return;
    }
    try {
      final root = Directory(await resolveRoot());
      if (!root.existsSync()) {
        return;
      }
      _watcher = root.watch(recursive: true).listen(
        (_) {
          _settle?.cancel();
          _settle = Timer(watchDebounce, () {
            _settle = null;
            unawaited(reload());
          });
        },
        onError: (Object error) =>
            Log.warn('The extensions folder cannot be watched: $error'),
      );
    } on Object catch (error) {
      // Watching is a convenience; failing to watch must not stop extensions
      // from working at all.
      Log.warn('The extensions folder cannot be watched: $error');
    }
  }

  Future<void> stopWatching() async {
    _settle?.cancel();
    _settle = null;
    await _watcher?.cancel();
    _watcher = null;
  }

  Future<void> _readDisabled() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      final stored = await getIt<KeyValueStorage>().get(enabledKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = jsonDecode(stored);
      if (decoded is! List) {
        return;
      }
      _disabled
        ..clear()
        ..addAll([
          for (final entry in decoded)
            if (entry is String) entry,
        ]);
    } on Object catch (error) {
      Log.warn('Which extensions are turned off could not be read: $error');
    }
  }

  Future<void> _writeDisabled() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      await getIt<KeyValueStorage>()
          .set(enabledKey, jsonEncode(_disabled.toList()));
    } on Object catch (error) {
      Log.warn('Which extensions are turned off could not be saved: $error');
    }
  }

  static String _safeId(String name) {
    final cleaned = name.toLowerCase().replaceAll(RegExp('[^a-z0-9_-]'), '-');
    return cleaned.isEmpty ? 'extension' : cleaned;
  }

  @override
  void dispose() {
    unawaited(stopWatching());
    super.dispose();
  }
}
