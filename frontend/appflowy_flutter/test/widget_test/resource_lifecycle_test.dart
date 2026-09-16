import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    getIt.registerSingleton<PluginSandbox>(PluginSandbox());
    getIt.registerSingleton<MenuSharedState>(MenuSharedState());
  });

  tearDown(() async {
    getIt<MenuSharedState>().notifier.dispose();
    await getIt.unregister<MenuSharedState>();
    await getIt.unregister<PluginSandbox>();
  });

  test('a page notifier disposes the plugin it owns', () {
    final plugin = _Plugin('main');
    PageNotifier(plugin: plugin).dispose();
    expect(plugin.disposals, 1);
    expect(plugin.notifier.disposals, 1);
  });

  test('a tab releases primary and secondary plugins exactly once', () {
    final primary = _Plugin('main');
    final secondary = _Plugin('secondary');
    final manager = PageManager(plugin: primary)..setSecondaryPlugin(secondary);
    manager.dispose();
    manager.dispose();
    expect(primary.disposals, 1);
    expect(secondary.disposals, 1);
  });

  test('expanding a secondary page transfers ownership without disposing it',
      () {
    final primary = _Plugin('main');
    final secondary = _Plugin('secondary');
    final manager = PageManager(plugin: primary)..setSecondaryPlugin(secondary);
    manager.expandSecondaryPlugin();
    expect(primary.disposals, 1);
    expect(manager.plugin, same(secondary));
    expect(secondary.initializations, 1);
    expect(secondary.disposals, 0);
    manager.dispose();
    expect(primary.disposals, 1);
    expect(secondary.disposals, 1);
  });

  test('repeated tab open and close never accumulates owned plugins', () {
    final retained = _Plugin('retained');
    var state = TabsState(pageManagers: [PageManager(plugin: retained)]);
    final closed = <_Plugin>[];
    for (var i = 0; i < 100; i++) {
      final plugin = _Plugin('temporary-$i');
      closed.add(plugin);
      state = state.openView(plugin).closeView(plugin.id);
      expect(state.pages, 1);
      expect(state.currentPageManager.plugin, same(retained));
    }
    expect(closed.map((plugin) => plugin.disposals), everyElement(1));
    expect(retained.disposals, 0);
    state.dispose();
    expect(retained.disposals, 1);
  });

  test('closing a tab releases its resources but keeps the selected page', () {
    final plugins = [for (var i = 0; i < 3; i++) _Plugin('page-$i')];
    final before = TabsState(
      currentIndex: 2,
      pageManagers: [for (final plugin in plugins) PageManager(plugin: plugin)],
    );
    addTearDown(before.dispose);
    final after = before.closeView('page-0');
    expect(after.currentPageManager, same(before.currentPageManager));
    expect(plugins[0].disposals, 1);
    expect(plugins[1].disposals, 0);
    expect(plugins[2].disposals, 0);
    expect(before.pageManagers, hasLength(3));
  });

  for (final openTab in [false, true]) {
    test(
        'selecting an existing ${openTab ? 'tab' : 'page'} releases the unused notifier',
        () {
      final existing = _Plugin('same-page');
      final incoming = _Plugin('same-page');
      final state = TabsState(pageManagers: [PageManager(plugin: existing)]);
      addTearDown(state.dispose);
      final next = openTab
          ? state.openView(incoming)
          : state.openPlugin(plugin: incoming, setLatest: false);
      expect(next.currentPageManager.plugin, same(existing));
      expect(existing.notifier.disposals, 0);
      expect(incoming.initializations, 0);
      // Real plugins create their ViewListener in the constructor, but their
      // late-final blocs only in init(). Do not dispose uninitialized blocs.
      expect(incoming.notifier.disposals, 1);
      expect(incoming.disposals, 0);
    });
  }

  test('reusing the owned plugin does not reinitialize or dispose it', () {
    final plugin = _Plugin('same-instance');
    final manager = PageManager()..setPlugin(plugin, false);
    addTearDown(manager.dispose);
    manager.setPlugin(plugin, false);
    expect(plugin.initializations, 1);
    expect(plugin.disposals, 0);
  });

  test('closing other tabs releases them and preserves pinned ownership',
      () async {
    final plugins = [for (var i = 0; i < 4; i++) _Plugin('page-$i')];
    final initial = TabsState(
      currentIndex: 3,
      pageManagers: [
        for (var i = 0; i < plugins.length; i++)
          PageManager(plugin: plugins[i])..isPinned = i == 0,
      ],
    );
    final tabs = _TabsBloc(initial);
    addTearDown(tabs.close);
    final changed = tabs.stream.first;
    tabs.add(const TabsEvent.closeOtherTabs('page-2'));
    await changed;
    expect(
      tabs.state.pageManagers.map((p) => p.plugin.id),
      ['page-0', 'page-2'],
    );
    expect(tabs.state.currentPageManager.plugin, same(plugins[2]));
    expect(plugins.map((p) => p.disposals), [0, 1, 0, 1]);
  });

  test('duplicate open events release constructor-owned listeners', () async {
    final tabs = TabsBloc();
    addTearDown(tabs.close);
    final first = _Plugin('same-page');
    final view = ViewPB(id: first.id, parentViewId: 'workspace');
    final opened = tabs.stream.first;
    tabs.add(TabsEvent.openPlugin(plugin: first, view: view, setLatest: false));
    await opened;
    final duplicate = _Plugin(first.id);
    tabs.add(
      TabsEvent.openPlugin(plugin: duplicate, view: view, setLatest: false),
    );
    await Future<void>.delayed(Duration.zero);
    expect(tabs.state.currentPageManager.plugin, same(first));
    expect(duplicate.initializations, 0);
    expect(duplicate.notifier.disposals, 1);
    expect(first.notifier.disposals, 0);
  });

  runResourceLifecycleWidgetTests();
}

/// Shared with the native fixture; these cases never dispatch to the backend.
void runResourceLifecycleWidgetTests() {
  testWidgets('removing a secondary pane mid-animation stops its ticker',
      (tester) async {
    final manager = PageManager(plugin: _Plugin('main'))
      ..setSecondaryPlugin(_Plugin('secondary'));
    await tester.pumpWidget(
      _app(
        SecondaryView(pageManager: manager, adaptedPercentageWidth: 450),
      ),
    );
    manager.showSecondaryPlugin();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
    manager.dispose();
  });

  testWidgets('interrupted closing never collapses a reopened secondary pane',
      (tester) async {
    final manager = PageManager(plugin: _Plugin('main'))
      ..setSecondaryPlugin(_Plugin('secondary'));
    await tester.pumpWidget(
      _app(SecondaryView(pageManager: manager, adaptedPercentageWidth: 450)),
    );
    manager.showSecondaryPlugin();
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      manager.hideSecondaryPlugin();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      manager.showSecondaryPlugin();
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SecondaryViewResizer)).width, 450);
    }
    manager.hideSecondaryPlugin();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    // The tab can be released before its widget is unmounted in the frame.
    manager.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('removing the resize grip cancels its pending hover timer',
      (tester) async {
    final manager = PageManager(plugin: _Plugin('main'));
    final width = ValueNotifier(450.0);
    await tester.pumpWidget(
      _app(
        SecondaryViewResizer(
          pageManager: manager,
          notifier: width,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final grip =
        tester.widgetList<MouseRegion>(find.byType(MouseRegion)).firstWhere(
              (region) => region.cursor == SystemMouseCursors.resizeLeftRight,
            );
    grip.onEnter!(const PointerEnterEvent());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    width.dispose();
    manager.dispose();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance: history snapshots never retain a live loading page',
        (tester) async {
      final history = HistorySwipeController();
      final page = ValueNotifier(0);
      final states = <_AnimatedPageState>[];
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<int>(
            valueListenable: page,
            builder: (_, value, __) => HistorySwipeSurface(
              controller: history,
              pageKey: value,
              child: value.isEven
                  ? _AnimatedPage(onMounted: states.add)
                  : const SizedBox.expand(),
            ),
          ),
          appearance: appearance,
        ),
      );
      for (var visit = 0; visit < 10; visit++) {
        await tester.pump(const Duration(milliseconds: 20));
        page.value++;
        await tester.pump();
        if (page.value.isOdd) {
          expect(states.every((state) => !state.mounted), isTrue);
          expect(tester.binding.transientCallbackCount, 0);
        }
      }
      await tester.pumpWidget(const SizedBox());
      history.dispose();
      page.dispose();
      expect(states.every((state) => !state.mounted), isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _app(Widget child, {String appearance = 'paper'}) => MaterialApp(
      theme: DesktopAppearance().getThemeData(
        appearance == 'paper'
            ? AppTheme.builtins
                .firstWhere((t) => t.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        appearance == 'dark' ? Brightness.dark : Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(body: child),
    );

class _TabsBloc extends TabsBloc {
  _TabsBloc(TabsState initial) {
    state.dispose();
    emit(initial);
  }
}

class _Plugin extends Plugin {
  _Plugin(this.id);
  @override
  final String id;
  int initializations = 0;
  int disposals = 0;
  @override
  final _Notifier notifier = _Notifier();
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => _Builder();
  @override
  void init() => initializations++;
  @override
  void dispose() {
    disposals++;
    notifier.dispose();
  }
}

class _Notifier extends PluginNotifier<DeletedViewPB?> {
  int disposals = 0;
  @override
  final isDeleted = ValueNotifier<DeletedViewPB?>(null);
  @override
  void dispose() {
    disposals++;
    isDeleted.dispose();
  }
}

class _Builder extends PluginWidgetBuilder {
  @override
  String get viewName => 'Lifecycle fixture';
  @override
  Widget get leftBarItem => const SizedBox();
  @override
  List<NavigationItem> get navigationItems => [this];
  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      const SizedBox();
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      const SizedBox.expand();
}

class _AnimatedPage extends StatefulWidget {
  const _AnimatedPage({required this.onMounted});
  final ValueChanged<_AnimatedPageState> onMounted;
  @override
  State<_AnimatedPage> createState() => _AnimatedPageState();
}

class _AnimatedPageState extends State<_AnimatedPage> {
  @override
  void initState() {
    super.initState();
    widget.onMounted(this);
  }

  @override
  Widget build(BuildContext context) => const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            CircularProgressIndicator(),
            CircularProgressIndicator(),
            CircularProgressIndicator(),
          ],
        ),
      );
}
