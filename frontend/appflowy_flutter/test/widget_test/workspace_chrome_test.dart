import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  setUp(() {
    getIt.registerSingleton<MenuSharedState>(MenuSharedState());
    getIt.registerSingleton<PluginSandbox>(PluginSandbox());
  });

  tearDown(() async {
    getIt<MenuSharedState>().notifier.dispose();
    await getIt.unregister<MenuSharedState>();
    await getIt.unregister<PluginSandbox>();
  });

  TabsState state({int count = 4, int current = 2, int pinned = 0}) =>
      TabsState(
        currentIndex: current,
        pageManagers: [
          for (var i = 0; i < count; i++)
            PageManager(plugin: _Plugin(i))..isPinned = i < pinned,
        ],
      );

  group('tab identity', () {
    test('closing a tab before the active one keeps the same page', () {
      final before = state();
      addTearDown(before.dispose);
      final after = before.closeView('page-0');
      expect(after.currentPageManager, same(before.currentPageManager));
      expect(after.currentIndex, 1);
      expect(before.pageManagers, hasLength(4));
    });

    test('closing a tab after the active one keeps the same page', () {
      final before = state();
      addTearDown(before.dispose);
      final after = before.closeView('page-3');
      expect(after.currentPageManager, same(before.currentPageManager));
      expect(after.currentIndex, 2);
    });

    test('closing the active tab selects its neighbour', () {
      final before = state();
      addTearDown(before.dispose);
      expect(before.closeView('page-2').currentPageManager.plugin.id, 'page-3');
      final last = before.copyWith(currentIndex: 3);
      expect(last.closeView('page-3').currentPageManager.plugin.id, 'page-2');
    });

    test('closing the only or an unknown tab is a no-op', () {
      final before = state(count: 1, current: 0);
      addTearDown(before.dispose);
      expect(before.closeView('page-0'), same(before));
      expect(before.closeView('missing'), same(before));
    });

    test('reordering preserves managers, selection and the original list', () {
      final before = state();
      addTearDown(before.dispose);
      final after = before.reorderTab(0, 4);
      expect(
        after.pageManagers.map((pm) => pm.plugin.id),
        ['page-1', 'page-2', 'page-3', 'page-0'],
      );
      expect(after.currentPageManager, same(before.currentPageManager));
      expect(before.pageManagers.first.plugin.id, 'page-0');
      expect(after.pageManagers.toSet(), before.pageManagers.toSet());
      expect(
        after.pageManagers.map((pm) => (pm.plugin as _Plugin).initializations),
        everyElement(0),
      );
    });

    test('moving the active tab keeps it selected', () {
      final before = state();
      addTearDown(before.dispose);
      final after = before.reorderTab(2, 0);
      expect(after.currentIndex, 0);
      expect(after.currentPageManager, same(before.currentPageManager));
    });

    test('dragging respects the pinned boundary in both directions', () {
      final before = state(pinned: 2);
      addTearDown(before.dispose);
      final pinnedMove = before.reorderTab(0, 4);
      expect(
        pinnedMove.pageManagers.map((pm) => pm.plugin.id),
        ['page-1', 'page-0', 'page-2', 'page-3'],
      );
      final regularMove = before.reorderTab(3, 0);
      expect(
        regularMove.pageManagers.map((pm) => pm.plugin.id),
        ['page-0', 'page-1', 'page-3', 'page-2'],
      );
      expect(
        regularMove.pageManagers.take(2).every((pm) => pm.isPinned),
        isTrue,
      );
    });

    test('invalid and unchanged reorder requests are no-ops', () {
      final before = state();
      addTearDown(before.dispose);
      for (final indices in [
        (-1, 0),
        (4, 0),
        (0, 5),
        (0, -1),
        (1, 1),
        (1, 2),
      ]) {
        expect(before.reorderTab(indices.$1, indices.$2), same(before));
      }
    });
  });

  Future<_TabsBloc> pumpTabs(
    WidgetTester tester, {
    required TabsState initial,
    String appearance = 'light',
    double width = 500,
  }) async {
    final bloc = _TabsBloc(initial);
    await tester.pumpWidget(
      _app(
        appearance,
        BlocProvider<TabsBloc>.value(
          value: bloc,
          child: Center(
            child: SizedBox(
              width: width,
              height: 40,
              child: TabsManager(
                onIndexChanged: (index) => bloc.add(TabsEvent.selectTab(index)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance: crowded tabs stay readable and overflow is usable',
        (tester) async {
      final bloc = await pumpTabs(
        tester,
        initial: state(count: 9, current: 8, pinned: 2),
        appearance: appearance,
      );
      expect(tester.takeException(), isNull);
      final active = find.byKey(const ValueKey('tab-page-8'));
      expect(active.hitTestable(), findsOneWidget);
      expect(tester.getSize(active).width, greaterThanOrEqualTo(140));

      await tester.tap(find.byKey(const ValueKey('open-tabs-menu')));
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuRow), findsNWidgets(9));
      await tester.tap(find.widgetWithText(AppMenuRow, 'Page 0'));
      await tester.pumpAndSettle();
      expect(bloc.state.currentIndex, 0);
      expect(
        find.byKey(const ValueKey('tab-page-0')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(bloc.close);
    });
  }

  testWidgets(
      'hover does not move a tab label; background close keeps selection',
      (tester) async {
    final bloc = await pumpTabs(tester, initial: state(count: 3));
    final tab = find.byKey(const ValueKey('tab-page-0'));
    final label = find.descendant(of: tab, matching: find.text('Page 0'));
    final before = tester.getRect(label);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tab));
    await tester.pumpAndSettle();
    expect(tester.getRect(label), before);

    final selected = bloc.state.currentPageManager;
    final emissions = <TabsState>[];
    final subscription = bloc.stream.listen(emissions.add);
    await tester
        .tap(find.descendant(of: tab, matching: find.byType(FlowyIconButton)));
    await tester.pumpAndSettle();
    expect(bloc.state.currentPageManager, same(selected));
    expect(emissions, hasLength(1));
    expect(bloc.state.pages, 2);
    await mouse.removePointer();
    await tester.runAsync(subscription.cancel);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets('middle click closes ordinary tabs but not pinned tabs',
      (tester) async {
    final bloc = await pumpTabs(tester, initial: state(count: 3, pinned: 1));
    await tester.tap(
      find.byKey(const ValueKey('tab-page-0')),
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(bloc.state.pages, 3);
    await tester.tap(
      find.byKey(const ValueKey('tab-page-1')),
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(bloc.state.pages, 2);
    expect(bloc.state.currentPageManager.plugin.id, 'page-2');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets('a drag survives intermediate frames and moves the existing tab',
      (tester) async {
    final bloc = await pumpTabs(tester, initial: state(count: 3));
    final original = [...bloc.state.pageManagers];
    final tab = find.byKey(const ValueKey('tab-page-0'));
    final drag = await tester.startGesture(
      tester.getTopLeft(tab) + const Offset(40, 16),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(20, 0));
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await drag.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(bloc.state.pageManagers.indexOf(original.first), greaterThan(0));
    expect(bloc.state.currentPageManager, same(original.first));
    expect(bloc.state.pageManagers.toSet(), original.toSet());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets(
      'closing a tab during reveal still brings the active tab into view',
      (tester) async {
    final bloc = await pumpTabs(tester, initial: state(count: 9, current: 0));
    final last = bloc.state.pageManagers.last;
    bloc.add(const TabsEvent.selectTab(8));
    await tester.pump();
    bloc.add(const TabsEvent.closeTab('page-0'));
    await tester.pumpAndSettle();
    expect(bloc.state.currentPageManager, same(last));
    expect(
      find.byKey(const ValueKey('tab-page-8')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets('Windows tabs share the title bar without capturing window drags',
      (tester) async {
    const channel = MethodChannel('window_manager');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'isMaximized' || call.method == 'isFullScreen'
          ? false
          : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final initial = state(count: 1, current: 0);
    final bloc = _TabsBloc(initial);
    await tester.pumpWidget(
      _app(
        'paper',
        BlocProvider<TabsBloc>.value(
          value: bloc,
          child: Center(
            child: SizedBox(
              width: 500,
              child: WindowTitleBar(
                title: TabsManager(
                  onIndexChanged: (index) =>
                      bloc.add(TabsEvent.selectTab(index)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byType(WindowTitleBar)).height;
    expect(height, 40);
    expect(find.byType(FlowyTab), findsNothing);
    bloc.replace(state(count: 3, current: 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(WindowTitleBar)).height, height);
    expect(find.byType(WindowCaptionButton), findsNWidgets(3));
    expect(
      find.ancestor(
        of: find.byType(FlowyTab).first,
        matching: find.byType(DragToMoveArea),
      ),
      findsNothing,
    );
    await tester.drag(find.byType(DragToMoveArea).last, const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(calls, contains('startDragging'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
    initial.dispose();
  });

  testWidgets('collapsed ancestors open by keyboard and retain the full labels',
      (tester) async {
    ViewPB? chosen;
    final parent = ViewPB()
      ..id = 'parent'
      ..name = 'Research';
    await tester.pumpWidget(
      _app(
        'paper',
        Center(
          child: ViewAncestorMenu(
            views: [parent],
            onSelected: (view) => chosen = view,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppMenuRow, 'Research'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen, same(parent));
    expect(find.byType(AppMenuSurface), findsNothing);
    expect(
      find.byTooltip(LocaleKeys.workspaceChrome_ancestors),
      findsOneWidget,
    );
  });

  testWidgets('a disabled menu trigger cannot open from the keyboard',
      (tester) async {
    await tester.pumpWidget(
      _app(
        'light',
        Center(
          child: AppMenuIconButton(
            icon: Icons.more_horiz_rounded,
            enabled: false,
            entries: () => [const AppMenuItem(label: 'Unavailable')],
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AppMenuSurface), findsNothing);
  });
}

Widget _app(String appearance, Widget child) {
  final theme = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  return MaterialApp(
    theme: theme,
    themeAnimationDuration: Duration.zero,
    home: Scaffold(body: child),
  );
}

class _TabsBloc extends TabsBloc {
  _TabsBloc(TabsState initial) {
    state.dispose();
    emit(initial);
  }

  void replace(TabsState next) => emit(next);
}

class _Plugin extends Plugin {
  _Plugin(this.index);
  final int index;
  int initializations = 0;
  @override
  String get id => 'page-$index';
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => _Builder(index);
  @override
  void init() => initializations++;
}

class _Builder extends PluginWidgetBuilder {
  _Builder(this.index);
  final int index;
  @override
  String get viewName => 'Page $index';
  @override
  Widget get leftBarItem => Text(viewName);
  @override
  List<NavigationItem> get navigationItems => [this];
  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => shortForm
      ? const Icon(Icons.description_rounded, size: 16)
      : Text(viewName, maxLines: 1, overflow: TextOverflow.ellipsis);
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      Text(viewName);
}
