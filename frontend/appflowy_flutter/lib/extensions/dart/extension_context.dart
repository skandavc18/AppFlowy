import 'dart:async';

import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What a Dart extension is handed when it is switched on.
///
/// Everything registered through here is remembered by the scope and undone
/// when the extension is switched off, so an extension never has to write its
/// own teardown.
class DartExtensionContext implements ExtensionContext {
  DartExtensionContext({required this.info}) : scope = ExtensionScope(info.id);

  @override
  final DartExtensionInfo info;

  @override
  final ExtensionScope scope;

  late final ExtensionBlocks blocks = ExtensionBlocks._(this);
  late final ExtensionCommands commands = ExtensionCommands._(this);
  late final ExtensionThemes themes = ExtensionThemes._(this);
  late final ExtensionTableViews tableViews = ExtensionTableViews._(this);
  late final ExtensionDashboardWidgets dashboardWidgets =
      ExtensionDashboardWidgets._(this);
  late final ExtensionData data = ExtensionData._(this);
  late final ExtensionJobs jobs = ExtensionJobs._(this);
}

/// Block types this extension adds to the editor.
class ExtensionBlocks {
  ExtensionBlocks._(this._context);

  final DartExtensionContext _context;

  /// Adds a block type, its markdown parser and its `/` entry in one go.
  void define({
    required String type,
    required BlockComponentBuilder Function(
      BlockComponentConfiguration configuration,
    ) builder,
    NodeParser? parser,
    String? slashName,
    List<String> slashKeywords = const [],
    IconData slashIcon = Icons.extension_rounded,
    String slashDescription = '',
    Node Function()? newNode,
    bool alignable = false,
  }) {
    ExtensionBlockRegistry.register(
      ExtensionBlockDefinition(
        extensionId: _context.info.id,
        type: type,
        builder: builder,
        parser: parser,
        slashName: slashName,
        slashKeywords: slashKeywords,
        slashIcon: slashIcon,
        slashDescription: slashDescription,
        newNode: newNode,
        alignable: alignable,
      ),
    );
    _context.scope.onDispose(() => ExtensionBlockRegistry.unregister(type));
  }
}

/// New ways of reading a table this extension supplies.
///
/// ⚠️ A table view, not a page type. `ViewLayoutPB` is a protobuf enum owned by
/// the backend, so a genuinely new page kind cannot be added from Dart — the
/// server would reject it. A table view rides on a Grid and lives in the view's
/// `extra` JSON, which the backend never reads.
class ExtensionTableViews {
  ExtensionTableViews._(this._context);

  final DartExtensionContext _context;

  var _registeredTeardown = false;

  void add({
    required String id,
    required String name,
    required DatabaseTabBarItemBuilder Function() buildTabBar,
    IconData icon = Icons.table_chart_rounded,
  }) {
    ExtensionTableViewRegistry.register(
      ExtensionTableView(
        extensionId: _context.info.id,
        id: id,
        name: name,
        icon: icon,
        buildTabBar: buildTabBar,
      ),
    );
    if (!_registeredTeardown) {
      _registeredTeardown = true;
      _context.scope.onDispose(
        () => ExtensionTableViewRegistry.unregisterAll(_context.info.id),
      );
    }
  }
}

/// Cards this extension adds to the dashboard's "Add" menu.
class ExtensionDashboardWidgets {
  ExtensionDashboardWidgets._(this._context);

  final DartExtensionContext _context;

  var _registeredTeardown = false;

  /// [definition] must carry `extensionId`, or nothing can take it away again.
  void add(DashboardWidgetDefinition definition) {
    assert(
      definition.extensionId == _context.info.id,
      'A dashboard widget must name the extension that supplied it.',
    );
    DashboardWidgetRegistry.register(definition);
    if (!_registeredTeardown) {
      _registeredTeardown = true;
      _context.scope.onDispose(
        () => DashboardWidgetRegistry.unregisterAll(_context.info.id),
      );
    }
  }
}

/// Things this extension can be asked to do.
class ExtensionCommands {
  ExtensionCommands._(this._context);

  final DartExtensionContext _context;

  var _registeredTeardown = false;

  void add({
    required String id,
    required String name,
    required Future<void> Function(BuildContext context) run,
    String description = '',
    List<String> keywords = const [],
    IconData icon = Icons.bolt_rounded,
  }) {
    ExtensionCommandRegistry.register(
      ExtensionCommand(
        extensionId: _context.info.id,
        id: id,
        name: name,
        description: description,
        keywords: keywords,
        icon: icon,
        run: run,
      ),
    );
    // One teardown covers every command, however many are added.
    if (!_registeredTeardown) {
      _registeredTeardown = true;
      _context.scope.onDispose(
        () => ExtensionCommandRegistry.unregisterAll(_context.info.id),
      );
    }
  }
}

/// Appearances this extension supplies.
class ExtensionThemes {
  ExtensionThemes._(this._context);

  final DartExtensionContext _context;

  var _registeredTeardown = false;

  void add({
    required String id,
    required String name,
    required Brightness brightness,
    required ThemeData Function(ThemeData base) build,
  }) {
    ExtensionThemeRegistry.register(
      ExtensionTheme(
        extensionId: _context.info.id,
        id: id,
        name: name,
        brightness: brightness,
        build: build,
      ),
    );
    if (!_registeredTeardown) {
      _registeredTeardown = true;
      _context.scope.onDispose(
        () => ExtensionThemeRegistry.unregisterAll(_context.info.id),
      );
    }
  }
}

/// The same reactive store actions write to, scoped to this extension.
///
/// A Dart extension and a JSON action therefore share one place to put values,
/// which is what lets a native block draw what a background action worked out.
class ExtensionData {
  ExtensionData._(this._context);

  final DartExtensionContext _context;

  String _qualify(String key) =>
      ExtensionDataStore.qualify(_context.info.id, key);

  Object? read(String key) => ExtensionDataStore.instance.read(_qualify(key));

  ExtensionDataEntry? entryFor(String key) =>
      ExtensionDataStore.instance.entryFor(_qualify(key));

  Future<void> write(String key, Object? value, {Duration? staleAfter}) =>
      ExtensionDataStore.instance
          .write(_qualify(key), value, staleAfter: staleAfter);

  Future<void> remove(String key) =>
      ExtensionDataStore.instance.remove(_qualify(key));

  /// Rebuilds whatever listens when this key changes.
  ValueListenable<Object?> listenable(String key) =>
      ExtensionDataStore.instance.listenable(_qualify(key));

  /// Raised whenever anything in the store changes.
  ValueListenable<int> get revision => ExtensionDataStore.instance.revision;
}

/// Work on a clock, sharing the one scheduler every action already uses.
class ExtensionJobs {
  ExtensionJobs._(this._context);

  final DartExtensionContext _context;

  /// ⚠️ Runs only while the app is open. There is no background worker, and
  /// saying so is better than promising work that never happens.
  void every(Duration interval, FutureOr<void> Function() work) {
    final timer = Timer.periodic(interval, (_) async {
      try {
        await work();
      } on Object catch (_) {
        // A failing job must not take the timer down with it.
      }
    });
    _context.scope.addTimer(timer);
  }

  /// Runs one of this extension's own JSON actions, if it has any.
  Future<ActionRun> runAction(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) =>
      ActionScheduler.instance.runNow(
        extensionId: _context.info.id,
        actionId: actionId,
        arguments: arguments,
      );

  /// Tells listening actions that something happened.
  void raise(ActionEvent event, {String viewId = '', String tag = ''}) =>
      ActionScheduler.instance.raise(event, viewId: viewId, tag: tag);
}
