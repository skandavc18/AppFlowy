import 'dart:ui' as ui;

import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_layout.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/navigation.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:appflowy/workspace/presentation/home/workspace_navigation_controls.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' as editor;
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mocktail/mocktail.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

import 'vivid_icon_test_support.dart';

const _captionKey = ValueKey('workspace-title-bar');
const _contextKey = ValueKey('workspace-context-header');
const _shellKey = ValueKey('workspace-shell-header');
const _railKey = ValueKey('workspace-tab-rail');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final windowCalls = <String>[];
  setUpAll(prepareVividIconTestAssets);
  setUp(() {
    getIt.pushNewScope();
    getIt.registerSingleton<MenuSharedState>(MenuSharedState());
    getIt.registerSingleton<FToast>(FToast());
    getIt.registerSingleton<PluginSandbox>(
      PluginSandbox()..registerPlugin(PluginType.document, _Factory()),
    );
    EncryptionVault.instance.seedForTest();
    windowCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      windowCalls.add(call.method);
      return call.method.startsWith('is') ? false : null;
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    EncryptionVault.instance.resetForTest();
    getIt<MenuSharedState>().notifier.dispose();
    await getIt.popScope();
  });

  for (final appearance in vividIconTestAppearances) {
    for (final width in [320.0, 640.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            '$appearance $width/${scale}x: path sits below ten open tabs',
            (tester) async {
          final fixture = await _pumpShell(
            tester,
            appearance: appearance,
            width: width,
            scale: scale,
            contextActions: true,
          );
          final semantics = tester.ensureSemantics();
          try {
            final caption = find.byKey(_captionKey);
            final contextRow = find.byKey(_contextKey);
            final shell = find.byKey(_shellKey);
            final rail = find.byKey(_railKey);
            final path = find.byKey(const ValueKey('workspace-context-path'));
            final tabsState = tester.state(find.byType(TabsManager));
            expect(tester.widget(caption), isA<WindowTitleBar>());
            expect(HomeSizes.topBarHeight, 76);
            expect(tester.getSize(shell), Size(width, 76));
            expect(tester.getSize(caption), Size(width, 40));
            expect(tester.getSize(contextRow), Size(width, 36));
            expect(tester.getSize(rail).height, 40);
            expect(tester.getTopLeft(rail).dy, tester.getTopLeft(caption).dy);
            expect(
              tester.getBottomLeft(rail).dy,
              tester.getTopLeft(contextRow).dy,
            );
            expect(
              tester.getBottomLeft(caption).dy,
              tester.getTopLeft(contextRow).dy,
            );
            expect(find.ancestor(of: rail, matching: caption), findsOneWidget);
            expect(find.ancestor(of: rail, matching: contextRow), findsNothing);
            _inside(tester.getRect(rail), tester.getRect(caption));
            _inside(tester.getRect(path), tester.getRect(contextRow));
            _inside(
              tester.getRect(find.byType(WorkspaceBreadcrumbs)),
              tester.getRect(contextRow),
            );
            // No old, unkeyed sidebar toggle may consume the path's width.
            expect(
              tester.getTopLeft(find.byType(WorkspaceBreadcrumbs)).dx,
              tester.getTopLeft(path).dx,
            );
            expect(
              tester.getTopRight(find.byType(WorkspaceBreadcrumbs)).dx,
              tester.getTopRight(path).dx,
            );
            expect(
              tester.getRect(path).overlaps(tester.getRect(rail)),
              isFalse,
            );
            expect(
              tester.getRect(path).overlaps(tester.getRect(caption)),
              isFalse,
            );
            expect(
              tester.getTopLeft(path).dx,
              tester.getTopLeft(contextRow).dx + WorkspaceTokens.space3,
            );
            expect(
              tester
                  .getTopLeft(
                    find.byKey(const ValueKey('workspace-page-canvas')),
                  )
                  .dy,
              tester.getBottomLeft(contextRow).dy,
            );
            expect(find.byType(HomeTopBar), findsOneWidget);
            _expectNavigationTargets(tester, caption, contextRow);
            _expectCaptionSurface(tester, caption, rail);
            for (final index in [0, 9, 4, 9]) {
              fixture.tabs.add(TabsEvent.selectTab(index));
              await tester.pumpAndSettle();
              expect(tester.state(find.byType(TabsManager)), same(tabsState));
              final pathTooltip = tester.widget<Tooltip>(
                find.byKey(const ValueKey('workspace-current-path')),
              );
              expect(
                pathTooltip.message,
                contains(fixture.plugins[index].view.name),
              );
              final overflow = tester.widget<TabsOverflowButton>(
                find.byType(TabsOverflowButton),
              );
              final entries = overflow
                  .entries(tester.element(find.byType(TabsOverflowButton)))
                  .whereType<AppMenuItem>()
                  .toList();
              expect(
                entries.where((entry) => entry.selected).single.label,
                fixture.plugins[index].view.name,
              );
              if (find.byType(ReorderableListView).evaluate().isEmpty) {
                expect(overflow.includeTabActions, isTrue);
                expect(
                  entries.map((entry) => entry.label),
                  containsAll([
                    LocaleKeys.disclosureAction_openNewTab.tr(),
                    LocaleKeys.tabMenu_pinTab.tr(),
                    LocaleKeys.tabMenu_close.tr(),
                    LocaleKeys.tabMenu_closeOthers.tr(),
                  ]),
                );
                continue;
              }
              final manager = fixture.managers[index];
              final tab = _tab(manager);
              expect(
                tester.widget<FlowyTab>(tab).key,
                ValueKey('tab-${manager.plugin.id}'),
              );
              final viewport = tester.getRect(find.byType(ReorderableListView));
              if (viewport.width >= tester.getSize(tab).width) {
                _inside(tester.getRect(tab), viewport);
                expect(tab.hitTestable(), findsOneWidget);
              } else {
                expect(
                  tester.getRect(tab).intersect(viewport).width,
                  greaterThan(0),
                );
              }
              final face = find.descendant(
                of: tab,
                matching: find.byKey(const ValueKey('workspace-tab-face')),
              );
              expect(tester.getRect(face), tester.getRect(tab));
              expect(tester.getSize(face).height, 40);
              expect(
                tester.getBottomLeft(face).dy,
                tester.getTopLeft(contextRow).dy,
              );
              final decoration =
                  tester.widget<DecoratedBox>(face).decoration as BoxDecoration;
              final palette = WorkspacePalette.of(tester.element(face));
              expect(decoration.color, palette.background);
              expect(decoration.boxShadow, isNull);
              expect(decoration.border, isNull);
              expect(
                decoration.borderRadius,
                const BorderRadius.vertical(top: Radius.circular(4)),
              );
              final close =
                  find.descendant(of: tab, matching: find.byType(IconButton));
              expect(close.hitTestable(), findsOneWidget);
              expect(tester.getSize(close), const Size.square(24));
              expect(tester.widget<IconButton>(close).onPressed, isNotNull);
              _inside(tester.getRect(close), tester.getRect(face));
              _outsideNativeDrag(close);
              expect(
                tester.getSize(tab).width,
                inInclusiveRange(
                  HomeSizes.tabBarMinWidth,
                  HomeSizes.tabBarWidth,
                ),
              );
              final selected = find.descendant(
                of: tab,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Semantics && widget.properties.selected == true,
                ),
              );
              expect(selected, findsOneWidget);
              expect(
                tester
                    .getSemantics(selected)
                    .getSemanticsData()
                    .hasFlag(ui.SemanticsFlag.isSelected),
                isTrue,
              );
            }
            for (final control in ['new-workspace-tab', 'open-tabs-menu']) {
              final button = find.byKey(ValueKey(control));
              if (control == 'new-workspace-tab' && button.evaluate().isEmpty) {
                expect(
                  tester
                      .widget<TabsOverflowButton>(
                        find.byType(TabsOverflowButton),
                      )
                      .includeTabActions,
                  isTrue,
                );
                continue;
              }
              expect(button.hitTestable(), findsOneWidget);
              _inside(tester.getRect(button), tester.getRect(rail));
            }
            final actions = find.byType(HomeContextActions);
            _inside(tester.getRect(actions), tester.getRect(contextRow));
            expect(
              find.ancestor(of: actions, matching: contextRow),
              findsOneWidget,
            );
            expect(find.ancestor(of: actions, matching: caption), findsNothing);
            expect(
              tester.getRect(actions).overlaps(tester.getRect(rail)),
              isFalse,
            );
            expect(
              tester.getTopLeft(actions).dx,
              tester.getTopRight(path).dx + WorkspaceTokens.space1,
            );
            _outsideNativeDrag(actions);
            final compactActions =
                find.byKey(const ValueKey('workspace-context-actions'));
            if (compactActions.evaluate().isNotEmpty) {
              expect(compactActions.hitTestable(), findsOneWidget);
              await tester.tap(compactActions);
              await tester.pumpAndSettle();
              await tester.tap(
                find.byKey(const ValueKey('composition-context-command')),
              );
              expect(fixture.plugins[9].actionCalls, 1);
            }
            expect(
              fixture.widgets.every((item) => item.navigationItems.length == 1),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
            await _dispose(tester, fixture);
          }
        });
      }
    }

    testWidgets(
        '$appearance: a lone tab keeps its close target and adjacent + at rest',
        (tester) async {
      final fixture =
          await _pumpShell(tester, appearance: appearance, count: 1);
      try {
        final tab = _tab(fixture.managers.single);
        final add = find.byKey(const ValueKey('new-workspace-tab'));
        final close =
            find.descendant(of: tab, matching: find.byType(IconButton));
        expect(tab.hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(add).dx, tester.getTopRight(tab).dx);
        expect(close.hitTestable(), findsOneWidget);
        expect(tester.getSize(close), const Size.square(24));
        expect(tester.widget<IconButton>(close).onPressed, isNotNull);
        _inside(tester.getRect(close), tester.getRect(tab));
        final railColor = tester.widget<ColoredBox>(find.byKey(_railKey)).color;
        expect(railColor, SidebarPalette.of(tester.element(tab)).background);
        _expectCaptionSurface(
          tester,
          find.byKey(_captionKey),
          find.byKey(_railKey),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    });

    testWidgets(
        '$appearance: pinned and ordinary tabs adjoin without gaps or shadows',
        (tester) async {
      final fixture =
          await _pumpShell(tester, appearance: appearance, count: 3, pinned: 1);
      try {
        final rail = tester.getRect(find.byKey(_railKey));
        final contextRow = tester.getRect(find.byKey(_contextKey));
        final palette =
            WorkspacePalette.of(tester.element(find.byKey(_railKey)));
        final sidebar = SidebarPalette.of(tester.element(find.byKey(_railKey)));
        var right = rail.left;
        for (final manager in fixture.managers) {
          final tab = _tab(manager);
          final face = find.descendant(
            of: tab,
            matching: find.byKey(const ValueKey('workspace-tab-face')),
          );
          final bounds = tester.getRect(face);
          expect(bounds, tester.getRect(tab));
          expect(bounds.left, right);
          expect(bounds.top, rail.top);
          expect(bounds.bottom, rail.bottom);
          expect(bounds.bottom, contextRow.top);
          expect(bounds.height, 40);
          expect(bounds.width, manager.isPinned ? 72 : HomeSizes.tabBarWidth);
          final decoration =
              tester.widget<DecoratedBox>(face).decoration as BoxDecoration;
          expect(decoration.boxShadow, isNull);
          expect(decoration.border, isNull);
          expect(
            decoration.borderRadius,
            const BorderRadius.vertical(top: Radius.circular(4)),
          );
          expect(
            Color.alphaBlend(decoration.color!, sidebar.background),
            identical(manager, fixture.tabs.state.currentPageManager)
                ? palette.background
                : sidebar.background,
          );
          final close =
              find.descendant(of: tab, matching: find.byType(IconButton));
          expect(close.hitTestable(), findsOneWidget);
          expect(tester.getSize(close), const Size.square(24));
          _inside(tester.getRect(close), bounds);
          right = bounds.right;
        }
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('new-workspace-tab'))).dx,
          right,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    });

    testWidgets(
        '$appearance: resize, selection and reorder retain the real editor',
        (tester) async {
      final fixture =
          await _pumpShell(tester, appearance: appearance, realEditor: true);
      try {
        final first = fixture.managers.first;
        final probe =
            find.byKey(const ValueKey('retained-editor'), skipOffstage: false);
        final state = tester.state<_EditorProbeState>(probe);
        final element = tester.element(probe);
        final depth = element.depth;
        final editorFinder =
            find.byType(editor.AppFlowyEditor, skipOffstage: false);
        final editorElement = tester.element(editorFinder);
        final editorWidget = tester.widget<editor.AppFlowyEditor>(editorFinder);
        final node = state.editorState.document.root.children.first;
        final transaction = state.editorState.transaction
          ..insertText(node, 0, 'Unsaved ');
        await state.editorState.apply(transaction);
        final document = state.editorState.document.toJson();
        state.focus.requestFocus();
        await tester.pump();
        final selection =
            editor.Selection.collapsed(editor.Position(path: [0], offset: 4));
        state.editorState.selection = selection;
        await tester.pump();

        for (final width in [320.0, 640.0, 1280.0]) {
          fixture.update(() {
            fixture.width = width;
            fixture.scale = 2;
          });
          await tester.pumpAndSettle();
          expect(tester.element(probe), same(element));
          expect(element.depth, depth);
          expect(tester.element(editorFinder), same(editorElement));
          expect(
            tester.widget<editor.AppFlowyEditor>(editorFinder).editorState,
            same(editorWidget.editorState),
          );
          expect(state.editorState.document.toJson(), document);
          expect(state.editorState.selection, selection);
          expect(state.focus.hasFocus, isTrue);
          expect(tester.takeException(), isNull);
        }
        fixture.tabs.reorderTab(0, 10);
        await tester.pumpAndSettle();
        expect(fixture.tabs.state.currentPageManager, same(first));
        expect(tester.element(probe), same(element));
        expect(tester.element(editorFinder), same(editorElement));
        expect(state.editorState.document.toJson(), document);
        expect(state.focus.hasFocus, isTrue);
        fixture.tabs.add(const TabsEvent.selectTab(0));
        await tester.pumpAndSettle();
        expect(state.mounted, isTrue);
        fixture.tabs.add(const TabsEvent.selectTab(9));
        await tester.pumpAndSettle();
        expect(tester.element(probe), same(element));
        expect(tester.element(editorFinder), same(editorElement));
        expect(state.editorState.document.toJson(), document);
        expect(fixture.plugins.first.disposals, 0);
        fixture.tabs.add(TabsEvent.closeTab(fixture.managers[4].tabId));
        await tester.pumpAndSettle();
        expect(fixture.tabs.state.pages, 9);
        expect(fixture.tabs.state.currentPageManager, same(first));
        expect(tester.element(probe), same(element));
        expect(element.depth, depth);
        expect(tester.element(editorFinder), same(editorElement));
        expect(state.editorState.document.toJson(), document);
        expect(fixture.plugins[4].disposals, 1);
        expect(fixture.plugins.first.disposals, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    });
  }

  testWidgets('tab drag feedback can build outside the TabsBloc provider',
      (tester) async {
    final manager = PageManager(plugin: _Plugin(0, false));
    try {
      await tester.pumpWidget(
        vividIconTestApp(
          'paper',
          SizedBox(
            width: 180,
            height: HomeSizes.tabBarHeight,
            child: FlowyTab(
              pageManager: manager,
              isCurrent: true,
              isAllPinned: false,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FlowyTab).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      manager.dispose();
    }
  });

  testWidgets('inactive labels stay quiet with an always-visible close target',
      (tester) async {
    final fixture = await _pumpShell(tester, count: 3);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      final tab = _tab(fixture.managers[1]);
      final label = find.descendant(
        of: tab,
        matching: find.text(fixture.plugins[1].view.name),
      );
      final before = tester.getRect(label);
      final palette = WorkspacePalette.of(tester.element(label));
      expect(tester.widget<Text>(label).style!.color, palette.secondaryText);
      final face = tester
          .widget<DecoratedBox>(
            find.descendant(
              of: tab,
              matching: find.byKey(const ValueKey('workspace-tab-face')),
            ),
          )
          .decoration as BoxDecoration;
      expect(face.boxShadow, isNull);
      final close = find.descendant(of: tab, matching: find.byType(IconButton));
      final closeBounds = tester.getRect(close);
      expect(close.hitTestable(), findsOneWidget);
      expect(closeBounds.size, const Size.square(24));
      expect(before.right, lessThanOrEqualTo(closeBounds.left));
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(tab));
      await tester.pumpAndSettle();
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getRect(close), closeBounds);
      expect(tester.getRect(label), before);
      expect(tester.widget<Text>(label).style!.color, palette.secondaryText);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getRect(close), closeBounds);
      expect(tester.getRect(label), before);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _dispose(tester, fixture);
    }
  });

  testWidgets(
      'caption controls, tab hits and reorder never enter native drag areas',
      (tester) async {
    final fixture = await _pumpShell(tester, count: 3);
    try {
      for (final target in [
        find.byType(WorkspaceBreadcrumbs),
        find.byType(FlowyTab),
        find.byType(WorkspaceNavigationControls),
        find.byType(WindowCaptionButton),
        find.descendant(
          of: find.byType(FlowyTab),
          matching: find.byType(IconButton),
        ),
        find.byKey(const ValueKey('new-workspace-tab')),
        find.byKey(const ValueKey('open-tabs-menu')),
      ]) {
        _outsideNativeDrag(target);
      }
      windowCalls.clear();
      await tester.tap(_tab(fixture.managers[1]));
      await tester.pumpAndSettle();
      expect(fixture.tabs.state.currentIndex, 1);
      await tester.drag(
        _tab(fixture.managers.first),
        const Offset(40, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(windowCalls, isNot(contains('startDragging')));
      if (UniversalPlatform.isWindows || UniversalPlatform.isLinux) {
        expect(find.byType(WindowCaptionButton), findsNWidgets(3));
        expect(
          tester.getRect(find.byType(WindowCaptionButton).last).right -
              tester.getRect(find.byType(WindowCaptionButton).first).left,
          138,
        );
        for (final region in [find.byKey(_captionKey), find.byKey(_railKey)]) {
          final drag = find
              .descendant(of: region, matching: find.byType(WindowDragTarget))
              .last;
          expect(tester.getSize(drag).width, greaterThanOrEqualTo(24));
          windowCalls.clear();
          await tester.drag(
            drag,
            const Offset(30, 0),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(windowCalls, contains('startDragging'));
        }
      }
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  test(
      'breadcrumb normalization keeps the current file once and filters only ancestors',
      () {
    final root = ViewPB(id: 'root', name: 'Workspace');
    final folder =
        ViewPB(id: 'folder', parentViewId: root.id, name: 'Research');
    final file =
        ViewPB(id: 'file', parentViewId: folder.id, name: 'Report.pdf');
    final saved = file.writeToBuffer();
    for (final ancestors in <List<ViewPB>>[
      [],
      [root],
      [root, folder],
      [root, folder, file, file],
    ]) {
      final path = workspaceBreadcrumbViews(view: file, ancestors: ancestors);
      expect(path.last.id, file.id);
      expect(path.where((view) => view.id == file.id), hasLength(1));
      expect(path.where((view) => view.id == root.id), isEmpty);
    }
    expect(
      workspaceBreadcrumbViews(view: root, ancestors: [root]).single,
      same(root),
    );
    expect(
      workspaceBreadcrumbViews(
        view: file,
        ancestors: [root, folder, file],
        showCurrentView: false,
      ).map((view) => view.id),
      ['folder'],
    );
    final space = ViewPB(
      id: 'space',
      parentViewId: root.id,
      name: 'Private space',
      extra: '{"is_space":true}',
    );
    expect(
      workspaceBreadcrumbViews(
        view: file,
        ancestors: [root, space, folder, file],
        isGuest: true,
      ).map((view) => view.id),
      ['folder', 'file'],
    );
    expect(file.writeToBuffer(), saved);
    expect(const DSWorkspaceGlyph.named('plus'), isA<WorkspaceGlyph>());
  });
}

Finder _tab(PageManager manager) => find.byWidgetPredicate(
      (widget) => widget is FlowyTab && identical(widget.pageManager, manager),
    );

void _outsideNativeDrag(Finder target) {
  for (final dragType in [DragToMoveArea, MoveWindowDetector]) {
    expect(
      find.ancestor(of: target, matching: find.byType(dragType)),
      findsNothing,
    );
  }
}

void _expectNavigationTargets(
  WidgetTester tester,
  Finder caption,
  Finder contextRow,
) {
  final group = find.byKey(const ValueKey('workspace-navigation-controls'));
  expect(find.byType(WorkspaceNavigationControls), findsOneWidget);
  expect(find.ancestor(of: group, matching: caption), findsOneWidget);
  expect(tester.getSize(group), const Size(112, 28));
  _inside(tester.getRect(group), tester.getRect(caption));
  var right = tester.getTopLeft(group).dx;
  for (final name in ['sidebar', 'back', 'forward', 'home']) {
    final button = find.byKey(ValueKey('workspace-navigation-$name'));
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.getSize(button), const Size.square(28));
    expect(tester.getTopLeft(button).dx, right);
    _inside(tester.getRect(button), tester.getRect(group));
    _outsideNativeDrag(button);
    right = tester.getTopRight(button).dx;
  }
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
      matching: find.byType(WorkspaceNavigationControls),
    ),
    findsNothing,
  );
  expect(
    find.descendant(of: contextRow, matching: find.byType(WindowDragTarget)),
    findsNothing,
  );
}

void _expectCaptionSurface(WidgetTester tester, Finder caption, Finder rail) {
  final background = SidebarPalette.of(tester.element(caption)).background;
  expect(tester.widget<WindowTitleBar>(caption).backgroundColor, background);
  expect(tester.widget<ColoredBox>(rail).color, background);
  if (UniversalPlatform.isWindows || UniversalPlatform.isLinux) {
    final captions = find.byType(WindowCaptionButton);
    expect(captions, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      final button = captions.at(i);
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.getSize(button), const Size(46, 40));
      _inside(tester.getRect(button), tester.getRect(caption));
      _outsideNativeDrag(button);
      final surface =
          tester.element(button).findAncestorWidgetOfExactType<ColoredBox>();
      expect(surface, isNotNull);
      expect(surface!.color, background);
      final decoration = tester
          .widget<Container>(
            find.descendant(of: button, matching: find.byType(Container)),
          )
          .decoration as BoxDecoration;
      expect(decoration.color!.a, 0);
      expect(Color.alphaBlend(decoration.color!, surface.color), background);
      expect(decoration.boxShadow, isNull);
    }
  }
}

void _inside(Rect child, Rect parent) {
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.01));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.01));
  expect(child.top, greaterThanOrEqualTo(parent.top - 0.01));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.01));
}

Future<_Fixture> _pumpShell(
  WidgetTester tester, {
  String appearance = 'paper',
  double width = 1280,
  double scale = 1,
  int count = 10,
  int pinned = 0,
  bool realEditor = false,
  bool contextActions = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(tester.view.reset);
  final fixture = _Fixture(count, realEditor, contextActions, pinned)
    ..width = width
    ..scale = scale;
  getIt.registerSingleton<TabsBloc>(fixture.tabs);
  final settings = _Settings();
  when(() => settings.state).thenReturn(_settings);
  when(() => settings.isClosed).thenReturn(false);
  when(() => settings.stream)
      .thenAnswer((_) => const Stream<HomeSettingState>.empty());
  final theme = vividIconTestTheme(appearance);
  final defaults = AppFlowyDefaultTheme();
  await tester.pumpWidget(
    vividIconTestApp(
      appearance,
      AppFlowyTheme(
        data: PremiumTheme.appFlowyTheme(
          base: appearance == 'dark' ? defaults.dark() : defaults.light(),
          palette: theme.extension<PremiumThemeExtension>()!,
          brightness: theme.brightness,
        ),
        child: BlocProvider<HomeSettingBloc>.value(
          value: settings,
          child: StatefulBuilder(
            builder: (context, update) {
              fixture.update = update;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(fixture.scale)),
                child: SizedBox(
                  width: fixture.width,
                  height: 640,
                  child: HomeStack(
                    delegate: _Delegate(),
                    userProfile: UserProfilePB(),
                    layout: HomeLayout.fromState(
                      _settings,
                      availableWidth: fixture.width,
                    ),
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

Future<void> _dispose(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(fixture.tabs.close);
}

final _settings = HomeSettingState(
  panelContext: null,
  workspaceSetting: WorkspaceLatestPB(workspaceId: 'composition-test'),
  unauthorized: false,
  menuStatus: MenuStatus.hidden,
  isNotificationPanelCollapsed: true,
  isScreenSmall: false,
  hasColappsedMenuManually: false,
  resizeOffset: 0,
  resizeStart: 0,
  resizeType: MenuResizeType.slide,
);

class _Fixture {
  _Fixture(int count, bool realEditor, bool contextActions, int pinned) {
    plugins = [
      for (var i = 0; i < count; i++)
        _Plugin(i, realEditor && i == 0, contextActions: contextActions),
    ];
    managers = [
      for (var i = 0; i < plugins.length; i++)
        PageManager(plugin: plugins[i])..isPinned = i < pinned,
    ];
    tabs = _Tabs(TabsState(pageManagers: managers));
  }
  late final List<_Plugin> plugins;
  late final List<PageManager> managers;
  late final _Tabs tabs;
  List<_Widgets> get widgets =>
      plugins.map((plugin) => plugin.widgets).toList();
  double width = 1280;
  double scale = 1;
  late StateSetter update;
}

class _Tabs extends TabsBloc {
  _Tabs(TabsState initial) {
    state.dispose();
    emit(initial);
  }
}

class _Settings extends Mock implements HomeSettingBloc {}

class _Delegate extends HomeStackDelegate {
  @override
  void didDeleteStackWidget(ViewPB view, int? index) {}
}

class _Factory extends PluginBuilder {
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

class _Plugin extends Plugin {
  _Plugin(int index, this.realEditor, {this.contextActions = false})
      : view = ViewPB(
          id: 'page-$index',
          parentViewId: 'folder',
          name: 'Report $index.pdf',
          layout: ViewLayoutPB.Document,
        );
  final ViewPB view;
  final bool realEditor;
  final bool contextActions;
  late final widgets = _Widgets(this);
  int disposals = 0;
  int actionCalls = 0;
  // Empty host IDs avoid protection/version backend I/O; view labels are real PBs.
  @override
  String get id => '';
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => widgets;
  @override
  void dispose() => disposals++;
}

class _Widgets extends PluginWidgetBuilder {
  _Widgets(this.plugin);
  final _Plugin plugin;
  // The old removeLast() path throws on this, and also corrupted mutable lists.
  late final _navigation = List<NavigationItem>.unmodifiable([this]);
  @override
  List<NavigationItem> get navigationItems => _navigation;
  @override
  String get viewName => plugin.view.name;
  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;
  @override
  Widget get leftBarItem => WorkspaceBreadcrumbs(
        view: plugin.view,
        showCurrentView: false,
        ancestors: [
          ViewPB(id: 'root', name: 'Workspace'),
          ViewPB(id: 'folder', parentViewId: 'root', name: 'Research'),
          plugin.view,
          plugin.view,
        ],
      );
  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: plugin.view, shortForm: shortForm);
  @override
  Widget? get rightBarItem => plugin.contextActions
      ? TextButton(
          key: const ValueKey('composition-context-command'),
          onPressed: () => plugin.actionCalls++,
          child: const Text('Inspect'),
        )
      : null;
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      plugin.realEditor
          ? const _EditorProbe(key: ValueKey('retained-editor'))
          : const SizedBox.expand();
}

class _EditorProbe extends StatefulWidget {
  const _EditorProbe({super.key});
  @override
  State<_EditorProbe> createState() => _EditorProbeState();
}

class _EditorProbeState extends State<_EditorProbe> {
  final editorState = editor.EditorState(
    document: editor.Document(
      root: editor.pageNode(
        children: [editor.paragraphNode(text: 'Retained page draft')],
      ),
    ),
  )..disableSealTimer = true;
  final focus = FocusNode();
  final editorKey = GlobalKey();
  @override
  Widget build(BuildContext context) => editor.AppFlowyEditor(
        key: editorKey,
        editorState: editorState,
        focusNode: focus,
        disableAutoScroll: true,
        editorStyle:
            const editor.EditorStyle.desktop(padding: EdgeInsets.all(16)),
        contextMenuItems: const [],
      );
  @override
  void dispose() {
    editorState.dispose();
    focus.dispose();
    super.dispose();
  }
}
