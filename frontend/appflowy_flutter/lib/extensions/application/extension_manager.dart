import 'dart:async';

import 'package:appflowy/ai/tools/tool_registry.dart';
import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/application/extension_run_log.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/application/extension_tool_server.dart';
import 'package:appflowy/extensions/application/island_server.dart';
import 'package:appflowy/extensions/application/script_host.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// Starts the extension layer and keeps the agent's tool list in step with it.
///
/// One place owns the lifetime, so a reload of the folder cannot leave a tool
/// server pointing at an extension that no longer exists.
class ExtensionManager {
  ExtensionManager({
    ExtensionStore? store,
    ActionScheduler? scheduler,
  })  : _store = store ?? ExtensionStore.instance,
        _scheduler = scheduler ?? ActionScheduler.instance;

  static final ExtensionManager instance = ExtensionManager();

  final ExtensionStore _store;
  final ActionScheduler _scheduler;
  final Map<String, ExtensionToolServer> _servers = {};

  bool _started = false;

  bool get isStarted => _started;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      await ExtensionDataStore.instance.ensureLoaded();
      await ExtensionRunLog.instance.ensureLoaded();
      await _store.ensureLoaded();
      _store.addListener(_syncServers);
      _syncServers();
      await _scheduler.start();
      // Compiled-in extensions register blocks, commands and themes; they are
      // independent of the folder, so a failure in one cannot stop the other.
      await DartExtensionHost.instance.start();
    } on Object catch (error) {
      // An extension layer that cannot start must not stop the app from
      // starting; it reports and stays out of the way.
      Log.warn('Extensions could not be started: $error');
    }
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;
    _store.removeListener(_syncServers);
    for (final id in _servers.keys) {
      AIToolRegistry.instance.removeServer(id);
    }
    _servers.clear();
    await _scheduler.stop();
    await DartExtensionHost.instance.stop();
    await ScriptHost.instance.dispose();
    await IslandServer.disposeAll();
  }

  void _syncServers() {
    final wanted = <String>{
      for (final extension in _store.active)
        if (extension.actions.any((action) => action.exposeToAgent))
          extension.id,
    };

    var changed = false;
    for (final id in _servers.keys.toList()) {
      if (!wanted.contains(id)) {
        _servers.remove(id);
        AIToolRegistry.instance.removeServer(id);
        changed = true;
      }
    }
    for (final id in wanted) {
      if (_servers.containsKey(id)) {
        continue;
      }
      final server = ExtensionToolServer(extensionId: id, store: _store);
      _servers[id] = server;
      AIToolRegistry.instance.addServer(server);
      changed = true;
    }

    if (changed) {
      // The agent's list is read lazily, so refreshing is only worth it when
      // somebody has already asked for it.
      unawaited(_refreshTools());
    }
  }

  Future<void> _refreshTools() async {
    if (AIToolRegistry.instance.tools.isEmpty) {
      return;
    }
    await AIToolRegistry.instance.refresh();
  }

  /// Tells every listening action that something happened.
  void raise(ActionEvent event, {String viewId = '', String tag = ''}) {
    if (!_started) {
      return;
    }
    _scheduler.raise(event, viewId: viewId, tag: tag);
  }

  @visibleForTesting
  Map<String, ExtensionToolServer> get servers => Map.unmodifiable(_servers);
}

/// Called once, from the application's startup.
Future<void> startExtensions() => ExtensionManager.instance.start();
