import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/tabs/page_navigation_history.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_layout.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
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

    test('closing an unknown tab is a no-op', () {
      final before = state(count: 1, current: 0);
      addTearDown(before.dispose);
      expect(before.closeView('missing'), same(before));
      expect((before.currentPageManager.plugin as _Plugin).disposals, 0);
    });

    for (final pinned in [false, true]) {
      test('closing the last tab creates fresh blank Home (pinned: $pinned)',
          () {
        final before = state(count: 1, current: 0, pinned: pinned ? 1 : 0);
        addTearDown(before.dispose);
        final closed = before.currentPageManager;
        final plugin = closed.plugin as _Plugin;
        final secondary = _Plugin(10);
        closed.setSecondaryPlugin(secondary);
        closed.showSecondaryPlugin();

        final after = before.closeView(closed.tabId);
        addTearDown(after.dispose);
        expect(after, isNot(same(before)));
        expect(after.pages, 1);
        expect(after.currentIndex, 0);
        expect(after.currentPageManager, isNot(same(closed)));
        expect(after.currentPageManager.tabId, isNot(closed.tabId));
        expect(after.currentPageManager.plugin, isA<BlankPagePlugin>());
        expect(
          after.currentPageManager.plugin.widgetBuilder.viewName,
          LocaleKeys.dashboard_home.tr(),
        );
        expect(after.currentPageManager.isPinned, isFalse);
        expect(
          after.currentPageManager.showSecondaryPluginNotifier.value,
          isFalse,
        );
        expect(plugin.disposals, 1);
        expect(secondary.disposals, 1);
        before.dispose();
        expect(plugin.disposals, 1);
        expect(secondary.disposals, 1);

        final nextHome = after.closeView(after.currentPageManager.tabId);
        addTearDown(nextHome.dispose);
        expect(nextHome.pages, 1);
        expect(nextHome.currentPageManager.plugin, isA<BlankPagePlugin>());
        expect(
          nextHome.currentPageManager,
          isNot(same(after.currentPageManager)),
        );
        expect(
          nextHome.currentPageManager.tabId,
          isNot(after.currentPageManager.tabId),
        );
      });
    }

    test('tab IDs disambiguate shared Home IDs without changing legacy lookup',
        () {
      final managers = [
        for (var i = 0; i < 3; i++)
          PageManager(plugin: _Plugin(i, viewId: 'home')),
      ];
      final before = TabsState(currentIndex: 2, pageManagers: managers);
      addTearDown(before.dispose);
      expect(managers.map((manager) => manager.tabId).toSet(), hasLength(3));
      expect(before.managerForTab('home'), same(managers.first));
      for (final manager in managers) {
        expect(before.managerForTab(manager.tabId), same(manager));
      }
      final after = before.closeView(managers[1].tabId);
      expect(after.pageManagers, orderedEquals([managers[0], managers[2]]));
      expect(after.currentPageManager, same(managers[2]));
      expect(after.currentIndex, 1);
      expect(
        managers.map((manager) => (manager.plugin as _Plugin).disposals),
        [0, 1, 0],
      );
      expect(before.pageManagers, orderedEquals(managers));
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
      try {
        expect(tester.takeException(), isNull);
        final active = find.byKey(const ValueKey('tab-page-8'));
        _expectReachableTab(tester, 8);
        expect(
          tester.getSize(active).width,
          greaterThanOrEqualTo(HomeSizes.tabBarMinWidth),
        );
        expect(
          tester.getSize(find.byType(TabsManager)).height,
          HomeSizes.tabBarHeight,
        );

        final managers = [...bloc.state.pageManagers];
        for (final index in [0, 8]) {
          await tester.tap(find.byKey(const ValueKey('open-tabs-menu')));
          await tester.pumpAndSettle();
          expect(find.byType(AppMenuRow), findsNWidgets(9));
          await tester.tap(find.widgetWithText(AppMenuRow, 'Page $index'));
          await tester.pumpAndSettle();
          expect(bloc.state.currentIndex, index);
          expect(bloc.state.currentPageManager, same(managers[index]));
          _expectReachableTab(tester, index);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(bloc.close);
      }
    });

    testWidgets(
        '$appearance: cold overflow selection and horizontal scrolling reach '
        'both ends of mixed-width tabs', (tester) async {
      final bloc = await pumpTabs(
        tester,
        initial: state(count: 9, current: 0, pinned: 2),
        appearance: appearance,
        width: 320,
      );
      try {
        final last = find.byKey(const ValueKey('tab-page-8'));
        expect(last, findsNothing, reason: 'the distant tab is not built yet');
        _expectReachableTab(tester, 0);

        await tester.tap(find.byKey(const ValueKey('open-tabs-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AppMenuRow, 'Page 8'));
        await tester.pumpAndSettle();
        expect(bloc.state.currentIndex, 8);
        _expectReachableTab(tester, 8);

        // Browse the real horizontal viewport without selecting another tab.
        // A metrics/reveal loop must not pull it back to the active tab.
        final scrollable = Scrollable.of(
          tester.element(last),
          axis: Axis.horizontal,
        );
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(ReorderableListView)),
            scrollDelta: Offset(-scrollable.position.maxScrollExtent, 0),
          ),
        );
        await tester.pumpAndSettle();
        expect(bloc.state.currentIndex, 8);
        _expectReachableTab(tester, 0);
        await tester.tap(find.byKey(const ValueKey('tab-page-0')));
        await tester.pumpAndSettle();
        expect(bloc.state.currentIndex, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(bloc.close);
      }
    });

    testWidgets(
        '$appearance: 24px close is visible at rest on every tab, including the last',
        (tester) async {
      final bloc = await pumpTabs(
        tester,
        initial: state(count: 3, pinned: 1),
        appearance: appearance,
        width: 640,
      );
      try {
        final managers = [...bloc.state.pageManagers];
        final selected = bloc.state.currentPageManager;
        for (var i = 0; i < managers.length; i++) {
          final manager = managers[i];
          final tab = _tab(manager);
          expect(
            tester.widget<FlowyTab>(tab).key,
            ValueKey('tab-${manager.plugin.id}'),
          );
          expect(tester.getSize(tab).height, 40);
          if (manager.isPinned) expect(tester.getSize(tab).width, 72);
          final close = _expectCloseTarget(tester, tab);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(bloc.state.pageManagers, isNot(contains(manager)));
          expect((manager.plugin as _Plugin).disposals, 1);
          if (i < managers.length - 1) {
            expect(
              bloc.state.pageManagers,
              orderedEquals(managers.skip(i + 1)),
            );
            expect(bloc.state.currentPageManager, same(selected));
            expect((selected.plugin as _Plugin).disposals, 0);
          }
        }
        final home = bloc.state.currentPageManager;
        expect(bloc.state.pages, 1);
        expect(home.plugin, isA<BlankPagePlugin>());
        expect(home.isPinned, isFalse);
        expect(
          managers.map((manager) => manager.tabId),
          isNot(contains(home.tabId)),
        );
        expect(tester.widget<FlowyTab>(_tab(home)).key, const ValueKey('tab-'));
        await tester.tap(_expectCloseTarget(tester, _tab(home)));
        await tester.pumpAndSettle();
        expect(bloc.state.pages, 1);
        expect(bloc.state.currentPageManager, isNot(same(home)));
        expect(bloc.state.currentPageManager.plugin, isA<BlankPagePlugin>());
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(bloc.close);
      }
    });

    testWidgets(
        '$appearance: a lone 72px pinned tab explicitly closes to unpinned Home',
        (tester) async {
      final bloc = await pumpTabs(
        tester,
        initial: state(count: 1, current: 0, pinned: 1),
        appearance: appearance,
      );
      try {
        final manager = bloc.state.currentPageManager;
        expect(tester.getSize(_tab(manager)), const Size(72, 40));
        await tester.tap(_expectCloseTarget(tester, _tab(manager)));
        await tester.pumpAndSettle();
        expect(bloc.state.pages, 1);
        expect(bloc.state.currentPageManager, isNot(same(manager)));
        expect(bloc.state.currentPageManager.plugin, isA<BlankPagePlugin>());
        expect(bloc.state.currentPageManager.isPinned, isFalse);
        expect((manager.plugin as _Plugin).disposals, 1);
        _expectCloseTarget(tester, _tab(bloc.state.currentPageManager));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(bloc.close);
      }
    });
  }

  testWidgets(
      'hover does not move a tab label; background close keeps selection',
      (tester) async {
    final bloc = await pumpTabs(tester, initial: state(count: 3));
    final tab = find.byKey(const ValueKey('tab-page-0'));
    final label = find.descendant(of: tab, matching: find.text('Page 0'));
    final before = tester.getRect(label);
    final close = _expectCloseTarget(tester, tab);
    final closeBounds = tester.getRect(close);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tab));
    await tester.pumpAndSettle();
    expect(tester.getRect(label), before);
    expect(tester.getRect(close), closeBounds);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(close.hitTestable(), findsOneWidget);
    expect(tester.getRect(label), before);
    expect(tester.getRect(close), closeBounds);

    final selected = bloc.state.currentPageManager;
    final emissions = <TabsState>[];
    final subscription = bloc.stream.listen(emissions.add);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(bloc.state.currentPageManager, same(selected));
    expect(emissions, hasLength(1));
    expect(bloc.state.pages, 2);
    await mouse.removePointer();
    await tester.runAsync(subscription.cancel);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets(
      'middle click closes pinned and ordinary tabs without selecting them',
      (tester) async {
    final bloc = await pumpTabs(tester, initial: state(count: 3, pinned: 1));
    final selected = bloc.state.currentPageManager;
    await tester.tap(
      find.byKey(const ValueKey('tab-page-0')),
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(bloc.state.pages, 2);
    expect(bloc.state.currentPageManager, same(selected));
    await tester.tap(
      find.byKey(const ValueKey('tab-page-1')),
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(bloc.state.pages, 1);
    expect(bloc.state.currentPageManager, same(selected));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(bloc.close);
  });

  testWidgets(
      'shared Home IDs keep tab keys and close only the addressed manager',
      (tester) async {
    final managers = [
      for (var i = 0; i < 3; i++)
        PageManager(plugin: _Plugin(i, viewId: 'home')),
    ];
    final bloc = await pumpTabs(
      tester,
      initial: TabsState(pageManagers: managers),
      width: 700,
    );
    try {
      expect(find.byKey(const ValueKey('tab-home')), findsNWidgets(3));
      final firstElement = tester.element(_tab(managers.first));
      final lastElement = tester.element(_tab(managers.last));
      await tester.tap(_expectCloseTarget(tester, _tab(managers[1])));
      await tester.pumpAndSettle();
      expect(
        bloc.state.pageManagers,
        orderedEquals([managers.first, managers.last]),
      );
      expect(bloc.state.currentPageManager, same(managers.first));
      expect(tester.element(_tab(managers.first)), same(firstElement));
      expect(tester.element(_tab(managers.last)), same(lastElement));
      expect(
        managers.map((manager) => (manager.plugin as _Plugin).disposals),
        [0, 1, 0],
      );
      bloc.add(const TabsEvent.selectTab(1));
      await tester.pumpAndSettle();
      bloc.add(const TabsEvent.closeCurrentTab());
      await tester.pumpAndSettle();
      expect(bloc.state.pageManagers.single, same(managers.first));
      expect(
        managers.map((manager) => (manager.plugin as _Plugin).disposals),
        [0, 1, 1],
      );
      expect(tester.element(_tab(managers.first)), same(firstElement));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(bloc.close);
    }
  });

  testWidgets(
      'overflow pin and tab-menu close-others address shared Home tabs independently',
      (tester) async {
    final managers = [
      for (var i = 0; i < 3; i++)
        PageManager(plugin: _Plugin(i, viewId: 'home')),
    ];
    final target = managers[1];
    final bloc = await pumpTabs(
      tester,
      initial: TabsState(currentIndex: 1, pageManagers: managers),
      width: 200,
    );
    try {
      await tester.tap(find.byKey(const ValueKey('open-tabs-menu')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(AppMenuRow, LocaleKeys.tabMenu_pinTab.tr()));
      await tester.pumpAndSettle();
      expect(bloc.state.pageManagers.first, same(target));
      expect(bloc.state.currentPageManager, same(target));
      expect(target.isPinned, isTrue);
      expect(
        managers
            .where((manager) => !identical(manager, target))
            .every((manager) => !manager.isPinned),
        isTrue,
      );
      expect(tester.getSize(_tab(target)).width, 72);

      await tester.tap(
        _tab(target),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TabMenu>(find.byType(TabMenu)).pageId, target.tabId);
      await tester.tap(find.text(LocaleKeys.tabMenu_closeOthers.tr()));
      await tester.pumpAndSettle();
      expect(bloc.state.pageManagers.single, same(target));
      expect((target.plugin as _Plugin).disposals, 0);
      expect(
        managers
            .where((manager) => !identical(manager, target))
            .map((manager) => (manager.plugin as _Plugin).disposals),
        everyElement(1),
      );

      final overflow = find.byType(TabsOverflowButton);
      final close = tester
          .widget<TabsOverflowButton>(overflow)
          .entries(tester.element(overflow))
          .whereType<AppMenuItem>()
          .singleWhere((entry) => entry.label == LocaleKeys.tabMenu_close.tr());
      expect(close.enabled, isTrue);
      expect(close.onSelected, isNotNull);
      await tester.tap(find.byKey(const ValueKey('open-tabs-menu')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(AppMenuRow, LocaleKeys.tabMenu_close.tr()));
      await tester.pumpAndSettle();
      expect(bloc.state.currentPageManager.plugin, isA<BlankPagePlugin>());
      expect(bloc.state.currentPageManager, isNot(same(target)));
      expect((target.plugin as _Plugin).disposals, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(bloc.close);
    }
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

  testWidgets(
      'Windows caption and tabs share 40px above a separate 36px context row',
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
    final settings = HomeSettingState(
      panelContext: null,
      workspaceSetting: WorkspaceLatestPB(workspaceId: 'chrome-test'),
      unauthorized: false,
      menuStatus: MenuStatus.expanded,
      isNotificationPanelCollapsed: true,
      isScreenSmall: false,
      hasColappsedMenuManually: false,
      resizeOffset: 0,
      resizeStart: 0,
      resizeType: MenuResizeType.slide,
    );
    final home = _MockHomeSettingBloc();
    when(() => home.state).thenReturn(settings);
    when(() => home.isClosed).thenReturn(false);
    when(() => home.stream)
        .thenAnswer((_) => const Stream<HomeSettingState>.empty());
    final layout = HomeLayout.fromState(settings, availableWidth: 1280);
    try {
      await tester.pumpWidget(
        _app(
          'paper',
          MultiBlocProvider(
            providers: [
              BlocProvider<TabsBloc>.value(value: bloc),
              BlocProvider<HomeSettingBloc>.value(value: home),
            ],
            child: Center(
              child: SizedBox(
                // Leave room for grouped navigation and native captions
                // beside the tab viewport; the path has its own row below.
                width: 800,
                child: BlocBuilder<TabsBloc, TabsState>(
                  builder: (context, state) =>
                      ChangeNotifierProvider<PageNotifier>.value(
                    value: state.currentPageManager.notifier,
                    child: HomeTopBar(
                      layout: layout,
                      tabs: TabsManager(
                        onIndexChanged: (index) =>
                            bloc.add(TabsEvent.selectTab(index)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final caption = find.byKey(const ValueKey('workspace-title-bar'));
      final contextRow = find.byKey(const ValueKey('workspace-context-header'));
      final rail = find.byKey(const ValueKey('workspace-tab-rail'));
      final path = find.byKey(const ValueKey('workspace-context-path'));
      final tabsState = tester.state(find.byType(TabsManager));
      expect(find.byType(HomeTopBar), findsOneWidget);
      expect(HomeSizes.topBarHeight, 76);
      expect(tester.getSize(find.byType(HomeTopBar)).height, 76);
      expect(caption, findsOneWidget);
      expect(tester.widget(caption), isA<WindowTitleBar>());
      expect(tester.getSize(caption).height, 40);
      expect(tester.getSize(contextRow).height, 36);
      expect(
        tester.getSize(find.byType(TabsManager)).height,
        HomeSizes.tabBarHeight,
      );
      expect(rail, findsOneWidget);
      expect(tester.getCenter(rail).dy, tester.getCenter(caption).dy);
      expect(
        tester.getTopLeft(contextRow).dy,
        tester.getBottomLeft(caption).dy,
      );
      expect(tester.getRect(path).overlaps(tester.getRect(rail)), isFalse);
      expect(find.ancestor(of: rail, matching: caption), findsOneWidget);
      expect(find.ancestor(of: rail, matching: contextRow), findsNothing);
      final navigation =
          find.byKey(const ValueKey('workspace-navigation-controls'));
      expect(tester.getSize(navigation), const Size(112, 28));
      expect(find.ancestor(of: navigation, matching: caption), findsOneWidget);
      for (final name in ['sidebar', 'back', 'forward', 'home']) {
        final button = find.byKey(ValueKey('workspace-navigation-$name'));
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getSize(button), const Size.square(28));
      }
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('workspace-navigation-back')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('workspace-navigation-forward')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(FlowyTab), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('open-tabs-menu')),
          matching: caption,
        ),
        findsOneWidget,
      );

      bloc.replace(
        TabsState(
          pageManagers: [
            ...initial.pageManagers,
            PageManager(plugin: _Plugin(1)),
            PageManager(plugin: _Plugin(2)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(caption, findsOneWidget);
      expect(tester.getSize(caption).height, 40);
      expect(tester.getSize(find.byType(HomeTopBar)).height, 76);
      expect(tester.getSize(contextRow).height, 36);
      expect(tester.getSize(rail).height, HomeSizes.tabBarHeight);
      expect(tester.getCenter(rail).dy, tester.getCenter(caption).dy);
      expect(tester.state(find.byType(TabsManager)), same(tabsState));
      expect(find.byType(WindowCaptionButton), findsNWidgets(3));
      expect(find.byType(FlowyTab), findsNWidgets(3));
      // Ancestor finders return the same caption once for each matching leaf.
      // Check each keyed tab, not a multi-tab finder with duplicate ancestors.
      for (final id in ['page-0', 'page-1', 'page-2']) {
        final tab = find.byKey(ValueKey('tab-$id'));
        expect(tab, findsOneWidget);
        expect(find.ancestor(of: tab, matching: caption), findsOneWidget);
      }
      for (final interactive in [
        find.byType(FlowyTab),
        find.byType(WindowCaptionButton),
        navigation,
        path,
        find.descendant(
          of: find.byType(FlowyTab),
          matching: find.byType(IconButton),
        ),
        find.byKey(const ValueKey('open-tabs-menu')),
        find.byKey(const ValueKey('new-workspace-tab')),
      ]) {
        for (final dragType in [DragToMoveArea, MoveWindowDetector]) {
          expect(
            find.ancestor(of: interactive, matching: find.byType(dragType)),
            findsNothing,
          );
        }
      }
      calls.clear();
      await tester
          .tap(find.byKey(const ValueKey('workspace-navigation-sidebar')));
      await tester.pump();
      verify(() => home.collapseMenu()).called(1);
      expect(bloc.state.currentPageManager, same(initial.currentPageManager));
      _expectReachableTab(tester, 1);
      await tester.tap(find.byKey(const ValueKey('tab-page-1')));
      await tester.pumpAndSettle();
      expect(bloc.state.currentIndex, 1);
      bloc.navigationHistory
        ..record(
          const PageHistoryEntry(
            pluginType: PluginType.document,
            viewId: 'page-0',
          ),
        )
        ..record(
          const PageHistoryEntry(
            pluginType: PluginType.document,
            viewId: 'page-1',
          ),
        );
      bloc.replace(bloc.state.copyWith());
      await tester.pumpAndSettle();
      final selected = bloc.state.currentPageManager;
      await tester.tap(find.byKey(const ValueKey('workspace-navigation-back')));
      await tester.pumpAndSettle();
      expect(bloc.state.currentPageManager, same(initial.currentPageManager));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('workspace-navigation-forward')),
            )
            .onPressed,
        isNotNull,
      );
      await tester
          .tap(find.byKey(const ValueKey('workspace-navigation-forward')));
      await tester.pumpAndSettle();
      expect(bloc.state.currentPageManager, same(selected));
      await tester.tap(find.byType(WindowCaptionButton).first);
      await tester.pump();
      expect(calls, contains('minimize'));
      expect(calls, isNot(contains('startDragging')));

      calls.clear();
      _expectReachableTab(tester, 0);
      await tester.drag(
        find.byKey(const ValueKey('tab-page-0')),
        const Offset(30, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(calls, isNot(contains('startDragging')));
      for (final region in [caption, rail]) {
        calls.clear();
        await tester.drag(
          find
              .descendant(
                of: region,
                matching: find.byType(DragToMoveArea),
              )
              .last,
          const Offset(30, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(calls, contains('startDragging'));
      }

      for (final id in ['page-1', 'page-2']) {
        bloc.add(TabsEvent.closeTab(id));
        await tester.pumpAndSettle();
      }
      expect(bloc.state.currentPageManager, same(initial.currentPageManager));
      expect(tester.getSize(caption).height, 40);
      expect(tester.getSize(find.byType(HomeTopBar)).height, 76);
      expect(tester.getSize(contextRow).height, 36);
      expect(
        tester.getSize(find.byType(TabsManager)).height,
        HomeSizes.tabBarHeight,
      );
      expect(rail, findsOneWidget);
      expect(tester.getCenter(rail).dy, tester.getCenter(caption).dy);
      expect(tester.state(find.byType(TabsManager)), same(tabsState));
      expect(find.byType(FlowyTab), findsOneWidget);
      calls.clear();
      await tester.tap(find.byKey(const ValueKey('workspace-navigation-home')));
      await tester.pumpAndSettle();
      expect(bloc.state.currentPageManager.plugin, isA<BlankPagePlugin>());
      expect(bloc.state.pageManagers, contains(initial.currentPageManager));
      expect((initial.currentPageManager.plugin as _Plugin).disposals, 0);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('workspace-navigation-home')),
            )
            .isSelected,
        isTrue,
      );
      expect(tester.state(find.byType(TabsManager)), same(tabsState));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('workspace-shell-header')))
            .height,
        76,
      );
      expect(calls, isNot(contains('startDragging')));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(bloc.close);
    }
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

Finder _tab(PageManager manager) => find.byWidgetPredicate(
      (widget) => widget is FlowyTab && identical(widget.pageManager, manager),
    );

Finder _expectCloseTarget(WidgetTester tester, Finder tab) {
  final close = find.descendant(of: tab, matching: find.byType(IconButton));
  expect(close.hitTestable(), findsOneWidget);
  expect(tester.getSize(close), const Size.square(24));
  expect(tester.widget<IconButton>(close).onPressed, isNotNull);
  final bounds = tester.getRect(close);
  final face = tester.getRect(tab);
  expect(bounds.left, greaterThanOrEqualTo(face.left));
  expect(bounds.right, lessThanOrEqualTo(face.right));
  expect(bounds.top, greaterThanOrEqualTo(face.top));
  expect(bounds.bottom, lessThanOrEqualTo(face.bottom));
  return close;
}

void _expectReachableTab(WidgetTester tester, int index) {
  final tab = find.byKey(ValueKey('tab-page-$index'));
  expect(tab.hitTestable(), findsOneWidget);
  final bounds = tester.getRect(tab);
  final viewport = tester.getRect(find.byType(ReorderableListView));
  // Require the entire tab, including its trailing close target, not merely
  // a sliver or its center. Never scroll it into view from the test itself.
  expect(bounds.left, greaterThanOrEqualTo(viewport.left - 0.001));
  expect(bounds.right, lessThanOrEqualTo(viewport.right + 0.001));
  expect(bounds.top, greaterThanOrEqualTo(viewport.top - 0.001));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + 0.001));
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
  _TabsBloc(TabsState initial) : super(loadHomeView: (_) async => null) {
    state.dispose();
    emit(initial);
  }

  void replace(TabsState next) => emit(next);
}

class _MockHomeSettingBloc extends Mock implements HomeSettingBloc {}

class _Plugin extends Plugin {
  _Plugin(this.index, {this.viewId});
  final int index;
  final String? viewId;
  int initializations = 0;
  int disposals = 0;
  @override
  String get id => viewId ?? 'page-$index';
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => _Builder(index);
  @override
  void init() => initializations++;
  @override
  void dispose() => disposals++;
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
