import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/launch_configuration.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/sidebar_expansion_task.dart';
import 'package:appflowy/util/expand_views.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Storage storage;
  late LaunchContext context;
  setUp(() {
    getIt.pushNewScope();
    storage = _Storage();
    getIt.registerSingleton<KeyValueStorage>(storage);
    context = LaunchContext(
      getIt,
      IntegrationMode.unitTest,
      const LaunchConfiguration(version: 'sidebar-test', rustEnvs: {}),
    );
  });
  tearDown(getIt.popScope);

  test('startup resets only the saved tree expansion preference', () async {
    storage.values.addAll({
      KVKeys.expandedViews: '{"parent":true,"sub-folder":true}',
      KVKeys.lastOpenedSpaceId: 'my-space',
      KVKeys.featureFlag: '{"sharedSection":true}',
      'other-preferences': 'unchanged',
    });
    final expected = Map.of(storage.values)..remove(KVKeys.expandedViews);
    await const SidebarExpansionTask().initialize(context);
    expect(storage.values, expected);
    expect(storage.removedKeys, [KVKeys.expandedViews]);
  });

  for (final saved in [null, '', '{invalid old expansion json']) {
    test('startup tolerates absent or obsolete expansion data: $saved',
        () async {
      if (saved != null) storage.values[KVKeys.expandedViews] = saved;
      await const SidebarExpansionTask().initialize(context);
      expect(storage.values.containsKey(KVKeys.expandedViews), isFalse);
    });
  }

  test('sidebar mounting waits for the expansion reset to finish', () async {
    storage.values[KVKeys.expandedViews] = '{"parent":true}';
    storage.removeGate = Completer<void>();
    var mounted = false;
    final launcher = AppLauncher(context: context);
    launcher.addTasks([
      const SidebarExpansionTask(),
      _ProbeTask(() {
        expect(storage.values.containsKey(KVKeys.expandedViews), isFalse);
        mounted = true;
      }),
    ]);
    final started = launcher.launch();
    await storage.removalStarted.future;
    expect(mounted, isFalse);
    storage.removeGate!.complete();
    await started;
    expect(mounted, isTrue);
    await launcher.dispose();
  });

  for (final kind in ['page', 'folder', 'file']) {
    test('$kind with saved children starts collapsed without dropping them',
        () async {
      final child = ViewPB(id: 'child', name: 'Child');
      final view = ViewPB(
        id: 'parent',
        name: 'Parent',
        childViews: [child],
        extra: switch (kind) {
          'folder' => const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
          'file' => const WorkspaceItemMetadata.file(
              contentKind: WorkspaceFileContentKind.collaborativeText,
            ).mergeIntoExtra(''),
          _ => '',
        },
      );
      storage.values[KVKeys.expandedViews] =
          jsonEncode({'parent': true, 'child': true});
      await const SidebarExpansionTask().initialize(context);
      final bloc = await _loadView(view);
      expect(bloc.state.isExpanded, isFalse);
      expect(bloc.state.view.childViews.map((v) => v.id), ['child']);
      await bloc.close();
    });
  }

  test('explicit session expansion survives remount but not a new startup',
      () async {
    final view = ViewPB(id: 'parent', name: 'Parent');
    await const SidebarExpansionTask().initialize(context);
    // This is the same preference written by the disclosure action. A parent
    // collapse/remount may reuse it; an application restart must not.
    await storage.set(KVKeys.expandedViews, '{"parent":true}');
    final expanded = await _loadView(view);
    expect(expanded.state.isExpanded, isTrue);
    await expanded.close();
    final remounted = await _loadView(view);
    expect(remounted.state.isExpanded, isTrue);
    final collapsed = remounted.stream.firstWhere((s) => !s.isExpanded);
    remounted.add(const ViewEvent.setIsExpanded(false));
    await collapsed;
    await remounted.close();
    final afterCollapse = await _loadView(view);
    expect(afterCollapse.state.isExpanded, isFalse);
    await afterCollapse.close();
    await storage.set(KVKeys.expandedViews, '{"parent":true}');
    await const SidebarExpansionTask().initialize(context);
    final restarted = await _loadView(view);
    expect(restarted.state.isExpanded, isFalse);
    await restarted.close();
  });

  test('top-level sections remain visible after startup', () async {
    await const SidebarExpansionTask().initialize(context);
    for (final type in [
      FolderSpaceType.public,
      FolderSpaceType.private,
      FolderSpaceType.favorite,
    ]) {
      final folder = FolderBloc(type: type);
      final loaded = folder.stream.first;
      folder.add(const FolderEvent.initial());
      await loaded;
      expect(folder.state.isExpanded, isTrue);
      await folder.close();
    }
  });

  test('opening a nested page does not automatically unfold sidebar ancestors',
      () async {
    final menu = MenuSharedState();
    getIt.registerSingleton<MenuSharedState>(menu);
    getIt.registerSingleton<PluginSandbox>(PluginSandbox());
    final expanders = _TrackedExpanders();
    getIt.registerSingleton<ViewExpanderRegistry>(expanders);
    final tabs = TabsBloc();
    try {
      final view = ViewPB(id: 'nested-page', parentViewId: 'collapsed-folder');
      final opened = tabs.stream.first;
      tabs.add(TabsEvent.openPlugin(plugin: _Plugin(view.id), view: view));
      await opened;
      expect(menu.latestOpenView?.id, view.id);
      expect(tabs.state.currentPageManager.plugin.id, view.id);
      expect(expanders.queries, isEmpty);
      expect(storage.values.containsKey(KVKeys.expandedViews), isFalse);
    } finally {
      await tabs.close();
      menu.notifier.dispose();
    }
  });
}

Future<ViewBloc> _loadView(ViewPB view) async {
  // Real restoration/listener lifecycle, without any Rust child-view request.
  final bloc = ViewBloc(view: view, shouldLoadChildViews: false);
  final initialized = bloc.stream.first;
  bloc.add(const ViewEvent.initial());
  await initialized;
  return bloc;
}

class _Storage implements KeyValueStorage {
  final values = <String, String>{};
  final removedKeys = <String>[];
  final removalStarted = Completer<void>();
  Completer<void>? removeGate;

  @override
  Future<void> remove(String key) async {
    removedKeys.add(key);
    if (!removalStarted.isCompleted) removalStarted.complete();
    await removeGate?.future;
    values.remove(key);
  }

  @override
  Future<String?> get(String key) async => values[key];
  @override
  Future<void> set(String key, String value) async => values[key] = value;
  @override
  Future<void> clear() async => values.clear();
  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }
}

class _ProbeTask extends LaunchTask {
  const _ProbeTask(this.onInitialize);
  final void Function() onInitialize;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    onInitialize();
  }
}

class _TrackedExpanders extends ViewExpanderRegistry {
  final queries = <String>[];
  @override
  bool isViewExpanded(String id) {
    queries.add(id);
    // The old navigation hook would ask to reveal ancestors here. Returning
    // true keeps this regression backend-free on that old implementation too.
    return true;
  }
}

class _Plugin extends Plugin {
  _Plugin(this.id);
  @override
  final String id;
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => throw UnimplementedError();
}
