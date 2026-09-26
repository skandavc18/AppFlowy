import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_home.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_home_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/startup_home.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/home_profile_test_support.dart';
import 'vivid_icon_test_support.dart';

void main() {
  setUpAll(prepareVividIconTestAssets);

  group('Home preference resolution (memory only)', () {
    test('concurrent reads wait for the same stored choice without writes',
        () async {
      final storage = _MemoryStorage()..pending = Completer<String?>();
      final loaded = <String>[];
      final home = DashboardHome(
        storage: storage,
        loadView: (id) async {
          loaded.add(id);
          return _dashboard(id);
        },
        loadAncestors: (_) => throw StateError('Direct child needs no lookup'),
      );
      final first = home.ensureLoaded();
      final second = home.resolveForWorkspace('workspace');
      await Future<void>.delayed(Duration.zero);
      expect(loaded, isEmpty);
      expect(storage.reads, ['appflowy_home_dashboard']);
      storage.pending!.complete('chosen-home');
      await first;
      expect((await second)?.id, 'chosen-home');
      expect(home.viewId, 'chosen-home');
      expect(storage.writes, isEmpty);
      home.dispose();
    });

    for (final target in [
      'missing',
      'plain page',
      'other workspace',
      'nested',
    ]) {
      test('$target uses only an appropriate existing dashboard', () async {
        final storage = _MemoryStorage();
        final before = Map.of(storage.values);
        final home = DashboardHome(
          storage: storage,
          loadView: (id) async => switch (target) {
            'missing' => null,
            'plain page' => ViewPB(id: id, parentViewId: 'workspace'),
            _ => _dashboard(id, parent: 'space'),
          },
          loadAncestors: (_) async => [
            ViewPB(id: 'space'),
            ViewPB(id: target == 'nested' ? 'workspace' : 'another-workspace'),
          ],
        );
        final result = await home.resolveForWorkspace('workspace');
        expect(result?.id, target == 'nested' ? 'chosen-home' : null);
        expect(home.viewId, 'chosen-home');
        expect(storage.values, before);
        expect(storage.writes, isEmpty);
        home.dispose();
      });
    }

    test('converted dashboard choices never mount or vanish from the tree',
        () async {
      final storage = _MemoryStorage();
      getIt.registerSingleton<KeyValueStorage>(storage);
      try {
        await DashboardHome.instance.ensureLoaded();
        final dashboard = _dashboard('chosen-home');
        expect(withoutHomeDashboard([dashboard]), isEmpty);
        final converted = [
          _dashboard('chosen-home')
            ..extra = const CollectionMetadata(kind: CollectionKind.album)
                .mergeIntoExtra(dashboard.extra),
          _dashboard('chosen-home')
            ..extra = const WorkspaceItemMetadata.folder()
                .mergeIntoExtra(dashboard.extra),
          _dashboard('chosen-home')
            ..extra = const WorkspaceItemMetadata.file(
              contentKind: WorkspaceFileContentKind.binary,
            ).mergeIntoExtra(dashboard.extra),
          _dashboard('chosen-home', parent: ''),
          _dashboard('chosen-home')
            ..extra = jsonEncode({
              ...decodeViewExtra(dashboard.extra),
              'is_space': true,
            }),
        ];
        for (final view in converted) {
          final home = DashboardHome(
            storage: storage,
            loadView: (_) async => view,
            loadAncestors: (_) =>
                throw StateError('Do not resolve a converted Home'),
          );
          expect(await home.resolveForWorkspace('workspace'), isNull);
          expect(withoutHomeDashboard([view]), [view]);
          home.dispose();
        }
        expect(storage.writes, isEmpty);
      } finally {
        await getIt.unregister<KeyValueStorage>();
      }
    });

    test('preference read failure is a fallback, not a reset or page creation',
        () async {
      final storage = _MemoryStorage()..failReads = true;
      final home = DashboardHome(
        storage: storage,
        loadView: (_) => throw StateError('No view should be loaded'),
        loadAncestors: (_) => throw StateError('No ancestor should be loaded'),
      );
      expect(await home.resolveForWorkspace('workspace'), isNull);
      expect(storage.writes, isEmpty);
      storage.failReads = false;
      expect(await home.resolveForWorkspace(''), isNull);
      home.dispose();
    });
  });

  group('desktop Home and sidebar', () {
    late MenuSharedState menu;
    late _MemoryStorage storage;
    late TabsBloc tabs;
    late _WorkspaceBloc workspace;
    late Future<ViewPB?> Function(String) loadHome;
    final built = <_Plugin>[];
    final requests = <String>[];

    setUp(() {
      menu = MenuSharedState();
      storage = _MemoryStorage();
      getIt.registerSingleton<MenuSharedState>(menu);
      getIt.registerSingleton<KeyValueStorage>(storage);
      getIt.registerSingleton<PluginSandbox>(PluginSandbox());
      built.clear();
      requests.clear();
      loadHome = (_) async => _dashboard('chosen-home');
      tabs = TabsBloc(
        loadHomeView: (id) {
          requests.add(id);
          return loadHome(id);
        },
        buildHistoryPlugin: (view) {
          final plugin = _Plugin(view.id);
          built.add(plugin);
          return plugin;
        },
      );
      workspace = _WorkspaceBloc();
    });

    tearDown(() async {
      menu.notifier.dispose();
      await getIt.unregister<MenuSharedState>();
      await getIt.unregister<KeyValueStorage>();
      await getIt.unregister<PluginSandbox>();
    });

    Widget shell(String appearance, {bool startup = true}) {
      final button = SizedBox(width: 260, child: const SidebarHomeButton());
      return vividIconTestApp(
        appearance,
        MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<UserWorkspaceBloc>.value(value: workspace),
          ],
          child: startup
              ? BlocSelector<UserWorkspaceBloc, UserWorkspaceState, String>(
                  selector: (state) =>
                      state.currentWorkspace?.workspaceId ?? 'workspace',
                  builder: (context, workspaceId) => StartupHome(
                    workspaceId: workspaceId,
                    child: button,
                  ),
                )
              : button,
        ),
      );
    }

    Future<void> disposeShell(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      if (!tabs.isClosed) {
        await pumpHomeProfileClose(
          tester,
          tabs.close(),
          description: 'Home tabs fixture close',
        );
      }
      await pumpHomeProfileClose(
        tester,
        workspace.close(),
        description: 'Home workspace fixture close',
      );
    }

    void manual(String id) => tabs.add(
          TabsEvent.openPlugin(
            plugin: _Plugin(id),
            view: ViewPB(id: id),
            setLatest: false, // No native latest-view write in these tests.
          ),
        );

    for (final appearance in vividIconTestAppearances) {
      testWidgets(
        '$appearance starts Home, not stored opened/pinned/crash tabs',
        (tester) async {
          try {
            final before = Map.of(storage.values);
            await tester.pumpWidget(shell(appearance));
            await tester.pumpAndSettle();
            expect(tabs.state.currentPageManager.plugin.id, 'chosen-home');
            expect(built.map((plugin) => plugin.id), ['chosen-home']);
            expect(built.single.initializations, 1);
            expect(tabs.state.pages, 1);
            expect(storage.values, before);
            expect(storage.reads, isEmpty);
            expect(storage.writes, isEmpty);
            expect(find.text('Home'), findsOneWidget);
            expect(find.byKey(const ValueKey('sidebar-home')), findsOneWidget);
            expect(
              tester
                  .widget<SidebarNavItem>(find.byType(SidebarNavItem))
                  .selected,
              isTrue,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await disposeShell(tester);
          }
        },
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'no chosen Home uses the existing blank/Home fallback',
      (tester) async {
        try {
          loadHome = (_) async => null;
          await tester.pumpWidget(shell('paper'));
          await tester.pumpAndSettle();
          expect(tabs.state.currentPageManager.plugin, isA<BlankPagePlugin>());
          expect(
            tabs.state.currentPageManager.plugin.widgetBuilder.viewName,
            'Home',
          );
          expect(built, isEmpty);
          expect(storage.writes, isEmpty);
        } finally {
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    for (final navigation in ['deep link', 'manual page', 'blank tab']) {
      testWidgets(
        'a slow startup cannot override a newer $navigation',
        (tester) async {
          final pending = Completer<ViewPB?>();
          try {
            loadHome = (_) => pending.future;
            await tester.pumpWidget(shell('light'));
            await tester.pumpAndSettle();
            expect(requests, ['workspace']);
            final plugin = navigation == 'blank tab'
                ? tabs.state.currentPageManager.plugin
                : _Plugin(navigation);
            tabs.add(TabsEvent.openPlugin(plugin: plugin, setLatest: false));
            // Resolve before pumping: the navigation event is only queued, but
            // must already invalidate the startup request.
            pending.complete(_dashboard('chosen-home'));
            await tester.pumpAndSettle();
            expect(tabs.state.currentPageManager.plugin, same(plugin));
            expect(built, isEmpty);
            await tester.pumpWidget(shell('dark'));
            await tester.pumpAndSettle();
            expect(requests, ['workspace']);
            expect(tabs.state.currentPageManager.plugin, same(plugin));
          } finally {
            if (!pending.isCompleted) pending.complete(null);
            await disposeShell(tester);
          }
        },
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'a deep link queued before shell construction wins too',
      (tester) async {
        try {
          manual('deep-link');
          await tester.pumpWidget(shell('light'));
          await tester.pumpAndSettle();
          expect(tabs.state.currentPageManager.plugin.id, 'deep-link');
          expect(requests, isEmpty);
          expect(built, isEmpty);
        } finally {
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'an explicit Home remains selected when the startup shell mounts',
      (tester) async {
        try {
          unawaited(tabs.openHome(workspaceId: 'workspace'));
          await tester.pump();
          await tester.pumpAndSettle();
          final opened = tabs.state.currentPageManager;
          expect(tabs.homeViewId, 'chosen-home');
          await tester.pumpWidget(shell('paper'));
          await tester.pumpAndSettle();
          expect(requests, ['workspace']);
          expect(tabs.state.currentPageManager, same(opened));
          expect(tabs.homeViewId, 'chosen-home');
          expect(
            tester.widget<SidebarNavItem>(find.byType(SidebarNavItem)).selected,
            isTrue,
          );
          expect(storage.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'Home click/Enter/Space keep manual pinned tabs and select Home',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          manual('manual-pinned');
          await tester.pump();
          final pinned = tabs.state.currentPageManager;
          tabs.add(const TabsEvent.togglePin('manual-pinned'));
          await tester.pump();
          expect(pinned.isPinned, isTrue);
          await tester.pumpWidget(shell('paper', startup: false));
          await tester.pumpAndSettle();
          final home = find.byKey(const ValueKey('sidebar-home'));
          final node = tester.getSemantics(find.byType(SidebarRow));
          expect(
            node.getSemanticsData().hasFlag(SemanticsFlag.isButton),
            isTrue,
          );
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(node.label, 'Home');
          await tester.tap(home);
          await tester.pumpAndSettle();
          expect(tabs.state.pages, 2);
          expect(tabs.state.pageManagers.first, same(pinned));
          expect(pinned.plugin.id, 'manual-pinned');
          expect(pinned.isPinned, isTrue);
          final homeManager = tabs.state.currentPageManager;
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.space,
          ]) {
            tabs.add(const TabsEvent.selectTab(0));
            await tester.pumpAndSettle();
            // Even a rapid Home re-selection must not be deduplicated while a
            // different tab is active. Focus the production row's own node.
            tester
                .widget<Focus>(
                  find
                      .descendant(
                        of: home,
                        matching: find.byType(Focus),
                      )
                      .first,
                )
                .focusNode!
                .requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(key);
            await tester.pumpAndSettle();
            expect(tabs.state.currentPageManager, same(homeManager));
            expect(tabs.state.pages, 2);
          }
          expect(storage.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'Home retains an unpinned manual page too',
      (tester) async {
        try {
          manual('manual-unpinned');
          await tester.pump();
          final manualManager = tabs.state.currentPageManager;
          await tester.pumpWidget(shell('light', startup: false));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sidebar-home')));
          await tester.pumpAndSettle();
          expect(tabs.state.pages, 2);
          expect(tabs.state.pageManagers.first, same(manualManager));
          expect(manualManager.plugin.id, 'manual-unpinned');
          expect(manualManager.isPinned, isFalse);
          expect(tabs.state.currentPageManager.plugin.id, 'chosen-home');
          expect(menu.latestOpenView?.id, 'chosen-home');
          expect(storage.writes, isEmpty);
        } finally {
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    for (final hasHome in [false, true]) {
      testWidgets(
        'confirmed workspace change resolves its own Home (configured=$hasHome) and can return',
        (tester) async {
          try {
            loadHome = (id) async => id == 'another-workspace' && !hasHome
                ? null
                : _dashboard('home-$id', parent: id);
            final before = Map.of(storage.values);
            await tester.pumpWidget(shell('paper'));
            await tester.pumpAndSettle();
            final original = tabs.state.currentPageManager;
            tabs.add(const TabsEvent.togglePin('home-workspace'));
            await tester.pump();
            final startup = tester.state(find.byType(StartupHome));

            tabs.add(const TabsEvent.switchWorkspace('another-workspace'));
            await tester.pump();
            // Intent alone is not a confirmed backend workspace change.
            expect(requests, ['workspace']);
            expect(tabs.state.currentPageManager, same(original));
            workspace.changeWorkspace('another-workspace');
            await tester.pumpAndSettle();
            expect(tester.state(find.byType(StartupHome)), same(startup));
            expect(requests, ['workspace', 'another-workspace']);
            expect(tabs.state.pageManagers, contains(same(original)));
            expect(original.isPinned, isTrue);
            expect(tabs.state.currentPageManager, isNot(same(original)));
            if (hasHome) {
              expect(
                tabs.state.currentPageManager.plugin.id,
                'home-another-workspace',
              );
              expect(tabs.homeViewId, 'home-another-workspace');
              expect(menu.latestOpenView?.id, 'home-another-workspace');
            } else {
              expect(
                tabs.state.currentPageManager.plugin,
                isA<BlankPagePlugin>(),
              );
              expect(tabs.homeViewId, isNull);
              expect(menu.latestOpenView, isNull);
            }

            tabs.add(const TabsEvent.switchWorkspace('workspace'));
            workspace.changeWorkspace('workspace');
            await tester.pumpAndSettle();
            expect(requests, ['workspace', 'another-workspace', 'workspace']);
            expect(tabs.state.currentPageManager, same(original));
            expect(tabs.homeViewId, 'home-workspace');
            expect(storage.values, before);
            expect(storage.writes, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await disposeShell(tester);
          }
        },
        timeout: homeProfileTestTimeout,
      );
    }

    for (final remount in [false, true]) {
      testWidgets(
        'workspace rebind (remount=$remount) ignores the previous pending Home',
        (tester) async {
          final previous = Completer<ViewPB?>();
          try {
            loadHome = (id) => id == 'workspace'
                ? previous.future
                : Future.value(_dashboard('new-home', parent: id));
            await tester.pumpWidget(shell('light'));
            await tester.pumpAndSettle();
            expect(requests, ['workspace']);
            tabs.add(const TabsEvent.switchWorkspace('another-workspace'));
            if (remount) await tester.pumpWidget(const SizedBox());
            workspace.changeWorkspace('another-workspace');
            if (remount) await tester.pumpWidget(shell('light'));
            await tester.pumpAndSettle();
            expect(requests, ['workspace', 'another-workspace']);
            expect(tabs.state.currentPageManager.plugin.id, 'new-home');
            expect(built.map((plugin) => plugin.id), ['new-home']);
            previous.complete(_dashboard('previous-home'));
            await tester.pumpAndSettle();
            expect(tabs.state.currentPageManager.plugin.id, 'new-home');
            expect(tabs.homeViewId, 'new-home');
            expect(menu.latestOpenView?.id, 'new-home');
            expect(built.map((plugin) => plugin.id), ['new-home']);
            expect(storage.writes, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            if (!previous.isCompleted) previous.complete(null);
            await disposeShell(tester);
          }
        },
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'a confirmed workspace change rejects Home before its next frame',
      (tester) async {
        final previous = Completer<ViewPB?>();
        try {
          loadHome = (id) => id == 'workspace'
              ? previous.future
              : Future.value(_dashboard('next-home', parent: id));
          await tester.pumpWidget(shell('light'));
          await tester.pumpAndSettle();
          expect(requests, ['workspace']);
          // No TabsEvent intent: a confirmed invitation/creation update arrives
          // before StartupHome.didUpdateWidget can invalidate its old request.
          workspace.changeWorkspace('another-workspace');
          previous.complete(_dashboard('previous-home'));
          await tester.idle();
          expect(built, isEmpty);
          expect(tabs.state.currentPageManager.plugin, isA<BlankPagePlugin>());
          await tester.pumpAndSettle();
          expect(requests, ['workspace', 'another-workspace']);
          expect(built.map((plugin) => plugin.id), ['next-home']);
          expect(tabs.state.currentPageManager.plugin.id, 'next-home');
          expect(tester.takeException(), isNull);
        } finally {
          if (!previous.isCompleted) previous.complete(null);
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'blank Home fallback does not latch the next workspace blank',
      (tester) async {
        try {
          loadHome = (id) async =>
              id == 'workspace' ? null : _dashboard('next-home', parent: id);
          await tester.pumpWidget(shell('light'));
          await tester.pumpAndSettle();
          expect(tabs.state.currentPageManager.plugin, isA<BlankPagePlugin>());
          // Invitation/creation flows also publish a confirmed workspace without
          // the switcher's TabsEvent.switchWorkspace intent.
          workspace.changeWorkspace('another-workspace');
          await tester.pumpAndSettle();
          expect(requests, ['workspace', 'another-workspace']);
          expect(tabs.state.currentPageManager.plugin.id, 'next-home');
          expect(built.map((plugin) => plugin.id), ['next-home']);
          expect(tester.takeException(), isNull);
        } finally {
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'navigation queued during a workspace change beats its Home',
      (tester) async {
        try {
          await tester.pumpWidget(shell('light'));
          await tester.pumpAndSettle();
          tabs.add(const TabsEvent.switchWorkspace('another-workspace'));
          manual('new-workspace-deep-link');
          workspace.changeWorkspace('another-workspace');
          await tester.pumpAndSettle();
          expect(requests, ['workspace']);
          expect(
            tabs.state.currentPageManager.plugin.id,
            'new-workspace-deep-link',
          );
          expect(tabs.homeViewId, isNull);
          await tester.pumpWidget(shell('dark'));
          await tester.pumpAndSettle();
          expect(requests, ['workspace']);
          expect(
            tabs.state.currentPageManager.plugin.id,
            'new-workspace-deep-link',
          );
          expect(storage.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'a queued workspace deep link wins before shell construction',
      (tester) async {
        try {
          tabs.add(const TabsEvent.switchWorkspace('another-workspace'));
          manual('queued-workspace-deep-link');
          await tester.pumpWidget(shell('light'));
          await tester.pumpAndSettle();
          expect(requests, isEmpty);
          workspace.changeWorkspace('another-workspace');
          await tester.pumpAndSettle();
          expect(requests, isEmpty);
          expect(built, isEmpty);
          expect(
            tabs.state.currentPageManager.plugin.id,
            'queued-workspace-deep-link',
          );
          expect(storage.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'workspace rebind, disposal and close cancel pending Home',
      (tester) async {
        try {
          for (final invalidation in ['workspace', 'disposal', 'close']) {
            final pending = Completer<ViewPB?>();
            loadHome = (_) => pending.future;
            await tester.pumpWidget(shell('light', startup: false));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('sidebar-home')));
            await tester.pump();
            if (invalidation == 'workspace') {
              workspace.changeWorkspace('another-workspace');
            } else if (invalidation == 'disposal') {
              await tester.pumpWidget(const SizedBox());
            } else {
              await pumpHomeProfileClose(tester, tabs.close());
            }
            pending.complete(_dashboard('chosen-home'));
            await tester.pumpAndSettle();
            expect(built, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            workspace.changeWorkspace('workspace');
          }
        } finally {
          await disposeShell(tester);
        }
      },
      timeout: homeProfileTestTimeout,
    );
  });

  test('desktop shell uses startup Home and sidebar exposes Home separately',
      () {
    final shell =
        File('lib/workspace/presentation/home/desktop_home_screen.dart')
            .readAsStringSync();
    final sidebar =
        File('lib/workspace/presentation/home/menu/sidebar/sidebar.dart')
            .readAsStringSync();
    expect(shell, contains('StartupHome('));
    expect(shell, contains('state.currentWorkspace?.workspaceId ??'));
    expect(shell, contains('workspaceId: workspaceId,'));
    expect(shell, isNot(contains('_switchToSpace')));
    expect(shell, isNot(contains('p.latestView != c.latestView')));
    expect(sidebar, contains('child: const SidebarHomeButton()'));
    expect(
      sidebar.indexOf('child: const SidebarHomeButton()'),
      lessThan(sidebar.indexOf('_renderFolderOrSpace(),')),
    );
  });
}

ViewPB _dashboard(String id, {String parent = 'workspace'}) => ViewPB(
      id: id,
      parentViewId: parent,
      layout: ViewLayoutPB.Document,
      extra: DashboardMetadata.newExtra(),
    );

class _Plugin extends Plugin {
  _Plugin(this.id);
  @override
  final String id;
  int initializations = 0;
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => throw UnimplementedError();
  @override
  void init() => initializations++;
}

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc()
      : super(
          UserWorkspaceState.initial(UserProfilePB(id: Int64(7))).copyWith(
            currentWorkspace:
                UserWorkspacePB(workspaceId: 'workspace', role: AFRolePB.Owner),
          ),
        );
  void changeWorkspace(String id) =>
      emit(state.copyWith(currentWorkspace: UserWorkspacePB(workspaceId: id)));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryStorage implements KeyValueStorage {
  final values = <String, String>{
    'appflowy_home_dashboard': 'chosen-home',
    'openedTabs':
        '{"workspace":[{"id":"last-crash-collection","isPinned":true},{"id":"saved-page"}]}',
    'pinnedTabs': '["last-crash-collection"]',
    'expandedViews': '{"saved-page":true}',
  };
  final reads = <String>[];
  final writes = <String>[];
  Completer<String?>? pending;
  bool failReads = false;
  @override
  Future<String?> get(String key) async {
    reads.add(key);
    if (failReads) throw StateError('unavailable preferences');
    return pending != null ? await pending!.future : values[key];
  }

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = await get(key);
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> set(String key, String value) async {
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    writes.add(key);
    values.remove(key);
  }

  @override
  Future<void> clear() async {
    writes.add('*');
    values.clear();
  }
}
