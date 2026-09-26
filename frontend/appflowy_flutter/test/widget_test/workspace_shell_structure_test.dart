import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_host.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/encryption/protected_view_gate.dart';
import 'package:appflowy/workspace/presentation/home/home_layout.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/navigation.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mocktail/mocktail.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  final windowCalls = <String>[];

  setUp(() {
    getIt.pushNewScope();
    getIt.registerSingleton<MenuSharedState>(MenuSharedState());
    getIt.registerSingleton<FToast>(FToast());
    getIt.registerSingleton<PluginSandbox>(
      PluginSandbox()..registerPlugin(PluginType.document, _FixtureFactory()),
    );
    EncryptionVault.instance.seedForTest();
    windowCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
      windowCalls.add(call.method);
      return call.method.startsWith('is') ? false : null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
    EncryptionVault.instance.resetForTest();
    getIt<MenuSharedState>().notifier.dispose();
    await getIt.popScope();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance has one 76px shell with 40px tabs above the 36px context row',
        (tester) async {
      final fixture = await _pumpShell(tester, appearance);
      try {
        final header = find.byKey(const ValueKey('workspace-shell-header'));
        final caption = find.byKey(const ValueKey('workspace-title-bar'));
        final contextRow =
            find.byKey(const ValueKey('workspace-context-header'));
        expect(find.byType(HomeTopBar), findsOneWidget);
        expect(find.byType(WindowTitleBar), findsOneWidget);
        expect(tester.widget(caption), isA<WindowTitleBar>());
        expect(HomeSizes.topBarHeight, 76);
        expect(tester.getSize(header).height, 76);
        expect(tester.getSize(caption).height, 40);
        expect(tester.getSize(contextRow).height, 36);
        expect(tester.getTopLeft(caption), tester.getTopLeft(header));
        expect(tester.getBottomLeft(caption), tester.getTopLeft(contextRow));
        expect(
          tester.getBottomRight(contextRow),
          tester.getBottomRight(header),
        );
        final rail = find.byKey(const ValueKey('workspace-tab-rail'));
        expect(rail, findsOneWidget);
        expect(find.byType(FlowyTab), findsOneWidget);
        expect(tester.getSize(rail).height, 40);
        expect(tester.getCenter(rail).dy, tester.getCenter(caption).dy);
        expect(
          tester.getTopLeft(rail).dy,
          tester.getTopLeft(caption).dy,
        );
        expect(
          tester.getBottomLeft(rail).dy,
          tester.getTopLeft(contextRow).dy,
        );
        expect(
          find.ancestor(of: rail, matching: caption),
          findsOneWidget,
        );
        expect(find.ancestor(of: rail, matching: contextRow), findsNothing);
        final path = find.byKey(const ValueKey('workspace-context-path'));
        final actions = find.byType(HomeContextActions);
        _inside(tester.getRect(path), tester.getRect(contextRow));
        _inside(tester.getRect(actions), tester.getRect(contextRow));
        expect(
          find.ancestor(of: actions, matching: contextRow),
          findsOneWidget,
        );
        expect(find.ancestor(of: actions, matching: caption), findsNothing);
        expect(tester.getRect(path).overlaps(tester.getRect(rail)), isFalse);
        expect(tester.getRect(actions).overlaps(tester.getRect(rail)), isFalse);
        expect(
          tester.getTopRight(path).dx + WorkspaceTokens.space1,
          tester.getTopLeft(actions).dx,
        );
        final navigation =
            find.byKey(const ValueKey('workspace-navigation-controls'));
        expect(
          find.ancestor(of: navigation, matching: caption),
          findsOneWidget,
        );
        _inside(tester.getRect(navigation), tester.getRect(caption));
        expect(tester.getSize(navigation), const Size(112, 28));
        expect(
          find.descendant(
            of: find.byType(FlowyNavigation),
            matching: find.byType(SidebarIconButton),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: contextRow,
            matching: find.byType(WindowDragTarget),
          ),
          findsNothing,
        );
        final tabs = find.byType(TabsManager);
        expect(
          tester.widget<HomeTopBar>(find.byType(HomeTopBar)).tabs,
          same(tester.widget<TabsManager>(tabs)),
        );
        expect(
          tester.element(tabs).findAncestorWidgetOfExactType<Expanded>()?.child,
          same(tester.widget<TabsManager>(tabs)),
        );
        expect(
          tester.getTopLeft(find.byType(PageStack)).dy,
          tester.getBottomLeft(header).dy,
        );
        final canvas = tester.widget<Container>(
          find.byKey(const ValueKey('workspace-page-canvas')),
        );
        expect(
          canvas.color,
          WorkspacePalette.of(tester.element(contextRow)).background,
        );
        expect(
          tester
              .element(contextRow)
              .findAncestorWidgetOfExactType<ColoredBox>()!
              .color,
          canvas.color,
        );
        expect(
          tester.widget<WindowTitleBar>(caption).backgroundColor,
          SidebarPalette.of(tester.element(caption)).background,
        );
        expect(
          tester.widget<ColoredBox>(rail).color,
          tester.widget<WindowTitleBar>(caption).backgroundColor,
        );

        // Even the last tab can explicitly close; the manager supplies fresh
        // Home state rather than leaving an empty shell or disabling the UI.
        final overflow = find.byType(TabsOverflowButton);
        final menu = tester.widget<TabsOverflowButton>(overflow);
        final entries = menu
            .entries(tester.element(overflow))
            .whereType<AppMenuItem>()
            .toList();
        expect(
          entries.any(
            (entry) =>
                entry.label == LocaleKeys.disclosureAction_openNewTab.tr() &&
                entry.enabled &&
                entry.onSelected != null,
          ),
          isTrue,
        );
        expect(
          entries
              .singleWhere(
                (entry) => entry.label == LocaleKeys.tabMenu_close.tr(),
              )
              .enabled,
          isTrue,
        );
        expect(
          entries
              .singleWhere(
                (entry) => entry.label == LocaleKeys.tabMenu_close.tr(),
              )
              .onSelected,
          isNotNull,
        );
        expect(
          entries
              .singleWhere(
                (entry) => entry.label == LocaleKeys.tabMenu_closeOthers.tr(),
              )
              .enabled,
          isFalse,
        );
        final close = find.descendant(
          of: find.byType(FlowyTab),
          matching: find.byType(IconButton),
        );
        expect(close.hitTestable(), findsOneWidget);
        expect(tester.getSize(close), const Size.square(24));
        expect(
          entries.any((entry) => entry.label == LocaleKeys.tabMenu_pinTab.tr()),
          isTrue,
        );
        expect(find.byType(ProtectedViewGate), findsOneWidget);
        expect(find.byType(PageVersionHost), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.tabs.close);
      }
    });

    testWidgets('$appearance retains the real page host across shell changes',
        (tester) async {
      final fixture = await _pumpShell(tester, appearance);
      try {
        final draftFinder = find.byKey(
          const ValueKey('draft-a'),
          skipOffstage: false,
        );
        final draft = tester.state<_DraftState>(draftFinder);
        final draftElement = tester.element(draftFinder);
        final depth = draftElement.depth;
        final page = tester.state(find.byType(PageStack));
        final host = tester.element(_managerHost(fixture.first));
        draft.text.text = 'Unsaved shell resize draft';
        draft.focus.requestFocus();
        draft.scroll.jumpTo(180);
        await tester.pumpAndSettle();
        draft.text.selection =
            const TextSelection(baseOffset: 2, extentOffset: 8);
        await tester.pump();
        final draftValue = draft.text.value;
        final scrollPosition = draft.scroll.position;

        void expectRetainedDraft({required bool focused}) {
          expect(draft.mounted, isTrue);
          expect(tester.state<_DraftState>(draftFinder), same(draft));
          expect(tester.element(draftFinder), same(draftElement));
          expect(tester.element(draftFinder).depth, depth);
          expect(tester.element(_managerHost(fixture.first)), same(host));
          expect(
            tester.state(
              find.descendant(
                of: _managerHost(fixture.first),
                matching: find.byType(PageStack, skipOffstage: false),
                skipOffstage: false,
              ),
            ),
            same(page),
          );
          expect(draft.text.value, draftValue);
          expect(draft.scroll.position, same(scrollPosition));
          expect(draft.scroll.offset, 180);
          expect(draft.focus.hasFocus, focused);
          expect(fixture.firstPlugin.disposals, 0);
        }

        for (final width in [1280.0, 1040.0, 800.0, 640.0, 320.0, 1280.0]) {
          for (final status in [MenuStatus.hidden, MenuStatus.expanded]) {
            fixture.update(() {
              fixture.width = width;
              fixture.settings = _settings(status: status, offset: 137);
            });
            await tester.pumpAndSettle();
            expect(tester.element(draftFinder), same(draftElement));
            expect(tester.element(draftFinder).depth, depth);
            expect(tester.element(_managerHost(fixture.first)), same(host));
            expect(tester.state(find.byType(PageStack)), same(page));
            expect(draft.focus.hasFocus, isTrue);
            expect(draft.text.text, 'Unsaved shell resize draft');
            expect(
              draft.text.selection,
              const TextSelection(baseOffset: 2, extentOffset: 8),
            );
            expect(draft.scroll.offset, 180);
            expectRetainedDraft(focused: true);
            expect(fixture.settings.resizeOffset, 137);
            expect(tester.takeException(), isNull);
          }
        }

        final secondPlugin = _FixturePlugin('b');
        final second = PageManager(plugin: secondPlugin);
        fixture.tabs.replace(
          TabsState(pageManagers: [fixture.first, second]),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(find.byKey(const ValueKey('workspace-tab-rail')))
              .height,
          HomeSizes.tabBarHeight,
        );
        expect(find.byType(HomeTopBar), findsOneWidget);
        expect(find.byKey(const ValueKey('new-workspace-tab')), findsOneWidget);
        expect(tester.element(draftFinder), same(draftElement));
        expect(draft.focus.hasFocus, isTrue);
        expectRetainedDraft(focused: true);

        final secondFinder = find.byKey(
          const ValueKey('draft-b'),
          skipOffstage: false,
        );
        final secondDraft = tester.state<_DraftState>(secondFinder);
        final secondElement = tester.element(secondFinder);
        final secondHost = tester.element(_managerHost(second));

        // Inserting/removing before the selected page must retain real hosts,
        // not just the PageManager objects shared by immutable tab snapshots.
        final thirdPlugin = _FixturePlugin('c');
        final third = PageManager(plugin: thirdPlugin);
        fixture.tabs.replace(
          TabsState(
            currentIndex: 1,
            pageManagers: [third, fixture.first, second],
          ),
        );
        await tester.pumpAndSettle();
        expectRetainedDraft(focused: true);
        fixture.tabs.reorderTab(1, 3);
        await tester.pumpAndSettle();
        expect(fixture.tabs.state.currentPageManager, same(fixture.first));
        expectRetainedDraft(focused: true);
        fixture.tabs.replace(
          TabsState(currentIndex: 1, pageManagers: [second, fixture.first]),
        );
        await tester.pumpAndSettle();
        expect(thirdPlugin.disposals, 1);
        expectRetainedDraft(focused: true);
        fixture.tabs.reorderTab(1, 0);
        await tester.pumpAndSettle();
        expectRetainedDraft(focused: true);
        expect(tester.element(secondFinder), same(secondElement));
        expect(tester.element(_managerHost(second)), same(secondHost));

        fixture.tabs.add(const TabsEvent.selectTab(1));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('breadcrumb-b')), findsOneWidget);
        expect(find.byKey(const ValueKey('breadcrumb-a')), findsNothing);
        expect(tester.element(draftFinder), same(draftElement));
        expect(tester.element(draftFinder).depth, depth);
        expectRetainedDraft(focused: false);
        secondDraft.text.text = 'Second unsaved draft';
        secondDraft.focus.requestFocus();
        secondDraft.scroll.jumpTo(260);
        await tester.pumpAndSettle();
        secondDraft.text.selection =
            const TextSelection(baseOffset: 1, extentOffset: 7);
        await tester.pump();
        final secondValue = secondDraft.text.value;
        final secondScrollPosition = secondDraft.scroll.position;
        fixture.tabs.reorderTab(1, 0);
        await tester.pumpAndSettle();
        expect(fixture.tabs.state.currentPageManager, same(second));
        expect(tester.element(_managerHost(fixture.first)), same(host));
        expectRetainedDraft(focused: false);
        expect(tester.element(_managerHost(second)), same(secondHost));
        expect(tester.element(secondFinder), same(secondElement));
        expect(tester.state<_DraftState>(secondFinder), same(secondDraft));
        expect(secondDraft.text.value, secondValue);
        expect(secondDraft.scroll.position, same(secondScrollPosition));
        expect(secondDraft.scroll.offset, 260);
        expect(secondDraft.focus.hasFocus, isTrue);
        expect(fixture.firstPlugin.disposals, 0);
        expect(secondPlugin.initializations, 0);

        // Both plugins use the same empty view ID to avoid backend I/O. The
        // command must close this manager alone and retain the other draft.
        expect(second.plugin.id, fixture.first.plugin.id);
        expect(second.tabId, isNot(fixture.first.tabId));
        fixture.tabs.add(TabsEvent.closeTab(second.tabId));
        await tester.pumpAndSettle();
        expect(fixture.tabs.state.pageManagers.single, same(fixture.first));
        expect(secondPlugin.disposals, 1);
        expect(secondDraft.mounted, isFalse);
        expect(
          find.byKey(const ValueKey('workspace-tab-rail')),
          findsOneWidget,
        );
        expect(find.byType(FlowyTab), findsOneWidget);
        expect(tester.element(draftFinder), same(draftElement));
        expect(tester.element(draftFinder).depth, depth);
        expect(draft.text.text, 'Unsaved shell resize draft');
        expect(draft.scroll.offset, 180);
        expectRetainedDraft(focused: false);

        fixture.firstPlugin.name = 'Renamed in the existing notifier';
        fixture.first.notifier.setPlugin(fixture.firstPlugin, setLatest: false);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('workspace-context-path')),
            matching: find.text(fixture.firstPlugin.name),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(FlowyTab),
            matching: find.text(fixture.firstPlugin.name),
          ),
          findsOneWidget,
        );
        expect(tester.element(draftFinder), same(draftElement));
        expectRetainedDraft(focused: false);
        expect(fixture.firstPlugin.initializations, 0);
        expect(fixture.firstPlugin.disposals, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.tabs.close);
      }
      expect(fixture.firstPlugin.disposals, 1);
    });

    for (final windowWidth in [320.0, 1600.0]) {
      testWidgets(
          '$appearance narrow context actions remain reachable '
          'in a ${windowWidth.toInt()}px window', (tester) async {
        final fixture = await _pumpShell(tester, appearance);
        try {
          // Exercise both a genuinely narrow root overlay and a narrow pane
          // inside a wide window; changing only the shell width tests the latter.
          tester.view.physicalSize = Size(windowWidth, 900);
          fixture.update(() {
            fixture.width = 320;
            fixture.settings = _settings(status: MenuStatus.hidden);
          });
          await tester.pumpAndSettle();
          final draft = tester.state(find.byKey(const ValueKey('draft-a')));
          final actions =
              find.byKey(const ValueKey('workspace-context-actions'));
          expect(actions.hitTestable(), findsOneWidget);
          await tester.tap(actions);
          await tester.pumpAndSettle();
          final last = find.byKey(const ValueKey('context-action-5'));
          final scrollView = find
              .ancestor(of: last, matching: find.byType(SingleChildScrollView))
              .first;
          final scrollable =
              Scrollable.of(tester.element(last), axis: Axis.horizontal);
          expect(scrollable.position.maxScrollExtent, greaterThan(0));
          final viewport = tester.getRect(scrollView);
          expect(viewport.left, greaterThanOrEqualTo(0));
          expect(viewport.right, lessThanOrEqualTo(windowWidth));

          // A translated action can be wider than the popup (especially with
          // the test font). Its trailing edge being visible does not mean its
          // center is hit-testable. Scroll through the actual viewport first,
          // then require every native button to receive a real tap.
          for (var i = 5; i >= 0; i--) {
            final action = find.byKey(ValueKey('context-action-$i'));
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: viewport.center,
                scrollDelta: Offset(
                  tester.getCenter(action).dx - viewport.center.dx,
                  0,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            await tester.tap(action);
            await tester.pump();
            expect(fixture.firstPlugin.actionTaps, 6 - i);
          }
          expect(
            tester.state(find.byKey(const ValueKey('draft-a'))),
            same(draft),
          );
          tester.view.physicalSize = const Size(1600, 900);
          fixture.update(() => fixture.width = 1280);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-context-actions')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('context-action-5')),
            findsOneWidget,
          );
          expect(
            tester.state(find.byKey(const ValueKey('draft-a'))),
            same(draft),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(fixture.tabs.close);
        }
      });
    }
  }

  testWidgets('native dragging is separate from breadcrumbs, tabs and captions',
      (tester) async {
    final fixture = await _pumpShell(tester, 'paper');
    try {
      final breadcrumb = find.byKey(const ValueKey('breadcrumb-a'));
      for (final dragType in [DragToMoveArea, MoveWindowDetector]) {
        for (final target in [
          breadcrumb,
          find.byType(HomeContextActions),
          find.byKey(const ValueKey('workspace-navigation-controls')),
          find.byType(WindowCaptionButton),
        ]) {
          expect(
            find.ancestor(of: target, matching: find.byType(dragType)),
            findsNothing,
          );
        }
      }
      windowCalls.clear();
      await tester.tap(breadcrumb);
      await tester.pump();
      expect(fixture.firstPlugin.breadcrumbTaps, 1);
      expect(windowCalls, isNot(contains('startDragging')));

      if (UniversalPlatform.isWindows || UniversalPlatform.isLinux) {
        expect(find.byType(WindowCaptionButton), findsNWidgets(3));
        await tester.tap(find.byType(WindowCaptionButton).first);
        await tester.pump();
        expect(windowCalls, contains('minimize'));
        expect(windowCalls, isNot(contains('startDragging')));
        await tester.drag(
          find.byType(WindowDragTarget).first,
          const Offset(30, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(windowCalls, contains('startDragging'));
      }

      fixture.tabs.replace(
        TabsState(
          pageManagers: [
            fixture.first,
            PageManager(plugin: _FixturePlugin('b')),
          ],
        ),
      );
      await tester.pumpAndSettle();
      for (final dragType in [DragToMoveArea, MoveWindowDetector]) {
        expect(
          find.ancestor(
            of: find.byType(FlowyTab),
            matching: find.byType(dragType),
          ),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.tabs.close);
    }
  });

  test('the baseline changes without overwriting relative width or mac spacing',
      () {
    final settings = _settings(offset: 137);
    expect(
      HomeLayout.fromState(settings, availableWidth: 1920).menuWidth,
      WorkspaceTokens.navigationWidth + 137,
    );
    expect(HomeLayout.fromState(settings, availableWidth: 320).menuWidth, 288);
    expect(
      HomeLayout.fromState(settings, availableWidth: 1920).menuWidth,
      WorkspaceTokens.navigationWidth + 137,
    );
    expect(settings.resizeOffset, 137);
    final hidden = _settings(status: MenuStatus.hidden);
    expect(
      HomeLayout.fromState(hidden, availableWidth: 1280, isMacOS: true)
          .menuSpacing,
      80,
    );
    expect(
      HomeLayout.fromState(
        settings,
        availableWidth: 1280,
        disableAnimations: true,
      ).animDuration,
      Duration.zero,
    );
  });
}

Finder _managerHost(PageManager manager) => find.byWidgetPredicate(
      (widget) => widget is LayoutBuilder && widget.key == ObjectKey(manager),
      skipOffstage: false,
    );

void _inside(Rect child, Rect parent) {
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.01));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.01));
  expect(child.top, greaterThanOrEqualTo(parent.top - 0.01));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.01));
}

Future<_ShellFixture> _pumpShell(WidgetTester tester, String appearance) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 900);
  addTearDown(tester.view.reset);
  final fixture = _ShellFixture();
  getIt.registerSingleton<TabsBloc>(fixture.tabs);
  final home = _MockHomeSettingBloc();
  when(() => home.state).thenAnswer((_) => fixture.settings);
  when(() => home.isClosed).thenReturn(false);
  when(() => home.stream)
      .thenAnswer((_) => const Stream<HomeSettingState>.empty());
  final theme = DesktopAppearance()
      .getThemeData(
        appearance == 'paper'
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        appearance == 'dark' ? Brightness.dark : Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      )
      .copyWith(platform: TargetPlatform.windows);
  await tester.pumpWidget(
    BlocProvider<HomeSettingBloc>.value(
      value: home,
      child: MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) {
              fixture.update = update;
              final layout = HomeLayout.fromState(
                fixture.settings,
                availableWidth: fixture.width,
                disableAnimations: true,
              );
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: fixture.width,
                  height: 600,
                  child: Stack(
                    children: [
                      Positioned(
                        left: layout.homePageLOffset,
                        right: layout.homePageROffset,
                        top: 0,
                        bottom: 0,
                        child: HomeStack(
                          layout: layout,
                          delegate: _Delegate(),
                          userProfile: UserProfilePB(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

HomeSettingState _settings({
  MenuStatus status = MenuStatus.expanded,
  double offset = 0,
}) =>
    HomeSettingState(
      panelContext: null,
      workspaceSetting: WorkspaceLatestPB(workspaceId: 'shell-fixture'),
      unauthorized: false,
      menuStatus: status,
      isNotificationPanelCollapsed: true,
      isScreenSmall: false,
      hasColappsedMenuManually: false,
      resizeOffset: offset,
      resizeStart: 0,
      resizeType: MenuResizeType.slide,
    );

class _ShellFixture {
  final firstPlugin = _FixturePlugin('a');
  late final first = PageManager(plugin: firstPlugin);
  late final tabs = _FixtureTabs(TabsState(pageManagers: [first]));
  double width = 1280;
  HomeSettingState settings = _settings();
  late StateSetter update;
}

class _FixtureTabs extends TabsBloc {
  _FixtureTabs(TabsState initial) {
    state.dispose();
    emit(initial);
  }

  void replace(TabsState next) {
    final removed = state.pageManagers
        .where((pm) => !next.pageManagers.contains(pm))
        .toList();
    emit(next);
    for (final pm in removed) {
      pm.dispose();
    }
  }
}

class _FixturePlugin extends Plugin {
  _FixturePlugin(this.tag) : name = 'Page $tag';
  final String tag;
  String name;
  int initializations = 0;
  int disposals = 0;
  int breadcrumbTaps = 0;
  int actionTaps = 0;

  // Exercise the real wrappers without reading or recording a backend view.
  @override
  String get id => '';
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => _FixtureWidgets(this);
  @override
  void init() => initializations++;
  @override
  void dispose() => disposals++;
}

class _FixtureFactory extends PluginBuilder {
  @override
  Plugin build(dynamic data) => data as Plugin;
  @override
  String get menuName => 'Fixture';
  @override
  FlowySvgData get icon => const FlowySvgData('');
  @override
  PluginType get pluginType => PluginType.document;
  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class _FixtureWidgets extends PluginWidgetBuilder {
  _FixtureWidgets(this.plugin);
  final _FixturePlugin plugin;

  @override
  String get viewName => plugin.name;
  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;
  @override
  List<NavigationItem> get navigationItems => [this];
  @override
  Widget get leftBarItem => TextButton(
        key: ValueKey('breadcrumb-${plugin.tag}'),
        onPressed: () => plugin.breadcrumbTaps++,
        child: Text(plugin.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
  @override
  Widget get rightBarItem => Builder(
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 6; i++)
              TextButton(
                key: ValueKey('context-action-$i'),
                onPressed: () {
                  // A compact action still belongs to the current page and tabs,
                  // even though its popup is rendered in the root overlay.
                  if (identical(context.read<PageNotifier>().plugin, plugin) &&
                      identical(
                        context
                            .read<TabsBloc>()
                            .state
                            .currentPageManager
                            .plugin,
                        plugin,
                      )) {
                    plugin.actionTaps++;
                  }
                },
                child: Text('Action $i with a long translated name'),
              ),
          ],
        ),
      );
  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      Text(plugin.name, maxLines: 1, overflow: TextOverflow.ellipsis);
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      _Draft(key: ValueKey('draft-${plugin.tag}'));
}

class _Draft extends StatefulWidget {
  const _Draft({super.key});
  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  final text = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(controller: text, focusNode: focus),
          Expanded(
            child: ListView(
              controller: scroll,
              children: const [SizedBox(height: 2400)],
            ),
          ),
        ],
      );
}

class _MockHomeSettingBloc extends Mock implements HomeSettingBloc {}

class _Delegate extends HomeStackDelegate {
  @override
  void didDeleteStackWidget(ViewPB view, int? index) {}
}
