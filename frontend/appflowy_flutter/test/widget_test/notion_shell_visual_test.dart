import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_layout.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/menu/menu_user_bloc.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_layout.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_top_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_user.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:appflowy/workspace/presentation/home/workspace_navigation_controls.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart'
    show WorkspaceLatestPB;
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart' as user;
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAnimatedOpacity;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart';

// SOURCE-ONLY: the owner generates and visually approves the six new baselines
// with --update-goldens. This is a labelled, offline fixture, not a screenshot
// of a user's workspace or evidence that the running application was inspected.
// HomeStack owns HomeTopBar, TabsManager, FlowyTab and the page-host lifetimes.
// Only startup/data/plugin boundaries and sidebar listing data are fixtures.
const _capture = ValueKey('notion-shell-fixture');
const _sidebar = ValueKey('notion-shell-fixture-sidebar');
const _title = ValueKey('notion-shell-fixture-title');
const _metadata = ValueKey('notion-shell-fixture-metadata');
const _body = ValueKey('notion-shell-fixture-body');
const _pageAction = ValueKey('notion-shell-fixture-inspect');
const _iconPicker = ValueKey('notion-shell-fixture-icon-picker');
const _caption = ValueKey('workspace-title-bar');
const _contextRow = ValueKey('workspace-context-header');
const _rail = ValueKey('workspace-tab-rail');
const _identityHeader = ValueKey('sidebar-identity-header');
const _workspaceId = 'notion-shell-fixture-workspace';
const _fixtureName = 'Fixture Studio';
const _longTitle = 'Research notes with an intentionally long page title';
const _height = 960.0;
const _away = Offset(-20, -20);
const _locale = Locale('en', 'US');
const _windowChannel = MethodChannel('window_manager');
const _cover = PageStyleCover(
  type: PageStyleCoverImageType.gradientColor,
  value: 'appflowy_them_color_gradient7',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = _FixtureEnvironment();
  setUpAll(environment.prepare);
  tearDownAll(environment.restore);

  for (final appearance in vividIconTestAppearances) {
    for (final width in [1280.0, 640.0]) {
      testWidgets(
        'notion shell $appearance ${width.toInt()}px golden',
        (tester) async {
          await _withFixture(
            tester,
            environment,
            appearance: appearance,
            width: width,
            // Desktop shows adjacent faces; compact shows the lone-tab close.
            count: width == 1280 ? 3 : 1,
            body: (fixture) async {
              _expectShell(tester, fixture);
              _expectPageHeader(tester);
              _expectActions(tester, icon: false, cover: false, page: false);
              await expectLater(
                find.byKey(_capture),
                matchesGoldenFile(
                  'goldens/notion_shell/${appearance}_${width.toInt()}.png',
                ),
              );
            },
          );
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      'notion shell $appearance: hover, close targets and 2x long-title resize',
      (tester) async {
        await _withFixture(
          tester,
          environment,
          appearance: appearance,
          width: 1280,
          count: 3,
          longTitle: true,
          body: (fixture) async {
            final first = fixture.tabs.state.pageManagers.first;
            final shellState = tester.state(find.byType(HomeStack));
            final tabsState = tester.state(find.byType(TabsManager));
            final pageFinder = find.byKey(
              const ValueKey('notion-shell-page-0'),
              skipOffstage: false,
            );
            final pageElement = tester.element(pageFinder);
            final pageState = tester.state<_FixturePageState>(pageFinder);
            final pageDepth = pageElement.depth;
            final coverElement = tester.element(find.byType(ViewCoverImage));
            final actionsState =
                tester.state(find.byType(ViewDecorationActions));
            final iconState = tester.state(find.byKey(_iconPicker));
            final sidebarState = tester.state(find.byType(SidebarUser));
            final mouse =
                await tester.createGesture(kind: PointerDeviceKind.mouse);
            await mouse.addPointer(location: _away);
            try {
              _expectShell(tester, fixture);
              _expectPageHeader(tester);
              await _expectHoverWithoutReflow(tester, mouse);

              // Real tab events, not a replacement strip/state. Closing an
              // inactive tab must leave the selected page mounted and selected.
              for (final remaining in [2, 1]) {
                final closing = fixture.tabs.state.pageManagers.last;
                final plugin = closing.plugin as _FixturePlugin;
                await tester.tap(
                  _closeButton(closing),
                  kind: PointerDeviceKind.mouse,
                );
                await tester.pumpAndSettle();
                expect(fixture.tabs.state.pages, remaining);
                expect(fixture.tabs.state.currentPageManager, same(first));
                expect(plugin.disposals, 1);
                expect(tester.element(pageFinder), same(pageElement));
              }
              _expectShell(tester, fixture);
              expect(_closeButton(first).hitTestable(), findsOneWidget);
              expect(
                tester.widget<IconButton>(_closeButton(first)).onPressed,
                isNotNull,
              );

              // Resizing changes constraints, never the HomeStack/sidebar slots.
              for (final width in [640.0, 1280.0]) {
                await mouse.moveTo(_away);
                tester.view.physicalSize = Size(width, _height);
                fixture.resize(width, scale: 2);
                await settleVividIconPictures(tester);
                _expectShell(tester, fixture);
                _expectPageHeader(tester);
                expect(
                  MediaQuery.textScalerOf(tester.element(find.byKey(_title)))
                      .scale(14),
                  28,
                );
                expect(
                  tester.widget<Text>(find.byKey(_title)).data,
                  _longTitle,
                );
                final label = find.descendant(
                  of: _tab(first),
                  matching: find.text(_longTitle),
                );
                expect(label, findsOneWidget);
                expect(
                  tester.widget<Text>(label).overflow,
                  TextOverflow.ellipsis,
                );
                expect(
                  tester.getRect(label).right,
                  lessThanOrEqualTo(tester.getRect(_closeButton(first)).left),
                );
                await _expectHoverWithoutReflow(tester, mouse);

                if (width == 640) {
                  await mouse.moveTo(_away);
                  await tester.tap(
                    find.byKey(const ValueKey('workspace-navigation-sidebar')),
                    kind: PointerDeviceKind.mouse,
                  );
                  await tester.pumpAndSettle();
                  expect(fixture.layout.menuIsDrawer, isTrue);
                  expect(fixture.layout.homePageLOffset, 0);
                  expect(
                    tester.getSize(find.byKey(_identityHeader)).height,
                    40,
                  );
                  _inside(
                    tester.getRect(find.byKey(_identityHeader)),
                    tester.getRect(find.byKey(_sidebar)),
                  );
                  await mouse
                      .moveTo(tester.getCenter(find.byKey(_identityHeader)));
                  await tester.pumpAndSettle();
                  final dismiss = find.descendant(
                    of: find.byKey(_identityHeader),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is SidebarIconButton &&
                          widget.icon == SidebarIcon.collapse,
                    ),
                  );
                  expect(dismiss.hitTestable(), findsOneWidget);
                  await tester.tap(dismiss, kind: PointerDeviceKind.mouse);
                  await tester.pumpAndSettle();
                  expect(find.byKey(_identityHeader), findsNothing);
                }

                expect(tester.state(find.byType(HomeStack)), same(shellState));
                expect(tester.state(find.byType(TabsManager)), same(tabsState));
                expect(tester.element(pageFinder), same(pageElement));
                expect(pageElement.depth, pageDepth);
                expect(tester.state(pageFinder), same(pageState));
                expect(pageState.scroll.offset, 0);
                expect(
                  tester.element(find.byType(ViewCoverImage)),
                  same(coverElement),
                );
                expect(
                  tester.state(find.byType(ViewDecorationActions)),
                  same(actionsState),
                );
                expect(tester.state(find.byKey(_iconPicker)), same(iconState));
                expect(
                  tester.state(find.byType(SidebarUser, skipOffstage: false)),
                  same(sidebarState),
                );
                expect((first.plugin as _FixturePlugin).disposals, 0);
                expect(tester.takeException(), isNull);
              }

              // Calls are intercepted: the test never minimizes/closes a real
              // window. Check the production callbacks as well as their paint.
              await mouse.moveTo(_away);
              fixture.windowCalls.clear();
              for (var index = 0; index < 3; index++) {
                await tester.tap(
                  find.byType(WindowCaptionButton).at(index),
                  kind: PointerDeviceKind.mouse,
                );
                await tester.pump();
              }
              expect(fixture.windowCalls, ['minimize', 'maximize', 'close']);
            } finally {
              await mouse.removePointer();
            }
          },
        );
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}

Future<void> _withFixture(
  WidgetTester tester,
  _FixtureEnvironment environment, {
  required String appearance,
  required double width,
  required int count,
  required Future<void> Function(_Fixture) body,
  bool longTitle = false,
}) =>
    environment.offline(() async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, _height);
      addTearDown(tester.view.reset);
      // Construct blocs INSIDE testWidgets so subscriptions use its clock.
      final fixture = _Fixture(appearance, width, count, longTitle);
      try {
        await tester.pumpWidget(_FixtureApp(fixture, environment.translations));
        await settleVividIconPictures(tester);
        expect(fixture.windowCalls, ['isMaximized']);
        environment.expectFonts(tester);
        await body(fixture);
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // A cancelled broadcast subscription can have a real-zone completion.
        // Observe shutdown in fake time; never await fake close inside runAsync.
        await _finishClosing(tester, fixture.close());
        expect(fixture.boundaries.calls, isEmpty);
        expect(environment.network.attempts, 0);
      }
    });

Future<void> _finishClosing(WidgetTester tester, Future<void> closing) async {
  var complete = false;
  Object? failure;
  StackTrace? trace;
  final observed = closing.then<void>(
    (_) => complete = true,
    onError: (Object error, StackTrace stack) {
      failure = error;
      trace = stack;
      complete = true;
    },
  );
  for (var turn = 0; turn < 40 && !complete; turn++) {
    await tester.pump();
    await tester.runAsync(() async {});
  }
  expect(
    complete,
    isTrue,
    reason: 'Fixture subscriptions must finish closing.',
  );
  await observed;
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

Finder _tab(PageManager manager) => find.byWidgetPredicate(
      (widget) => widget is FlowyTab && identical(widget.pageManager, manager),
    );

Finder _closeButton(PageManager manager) => find.descendant(
      of: _tab(manager),
      matching: find.byType(IconButton),
    );

void _expectShell(WidgetTester tester, _Fixture fixture) {
  expect(tester.takeException(), isNull);
  expect(find.byType(HomeStack), findsOneWidget);
  expect(find.byType(HomeTopBar), findsOneWidget);
  expect(find.byType(TabsManager), findsOneWidget);
  expect(find.byType(WorkspaceNavigationControls), findsOneWidget);
  final frame = tester.getRect(find.byKey(_capture));
  final caption = tester.getRect(find.byKey(_caption));
  final rail = tester.getRect(find.byKey(_rail));
  final contextRow = tester.getRect(find.byKey(_contextRow));
  final palette = WorkspacePalette.of(tester.element(find.byKey(_caption)));
  final background =
      SidebarPalette.of(tester.element(find.byKey(_caption))).background;
  expect(frame.size, Size(fixture.width, _height));
  expect(caption.height, 40);
  expect(rail.height, 40);
  expect(contextRow.height, 36);
  expect(caption.top, frame.top);
  expect(caption.bottom, contextRow.top);
  expect(rail.top, caption.top);
  expect(rail.bottom, contextRow.top);
  expect(
    tester.widget<WindowTitleBar>(find.byKey(_caption)).backgroundColor,
    background,
  );
  expect(tester.widget<ColoredBox>(find.byKey(_rail)).color, background);
  _inside(rail, caption);
  expect(
    tester.getTopLeft(find.byKey(const ValueKey('workspace-page-canvas'))).dy,
    contextRow.bottom,
  );
  final path = find.byType(WorkspaceBreadcrumbs);
  expect(path, findsOneWidget);
  _inside(tester.getRect(path), contextRow);
  expect(tester.getRect(path).overlaps(caption), isFalse);
  final tooltip = tester.widget<Tooltip>(
    find.byKey(const ValueKey('workspace-current-path')),
  );
  expect(
    tooltip.message,
    '$_fixtureName / Research / ${fixture.plugins.first.view.name}',
  );
  expect(
    find.byKey(const ValueKey('breadcrumb-workspace-root')).hitTestable(),
    findsOneWidget,
  );

  final controls = find.byKey(const ValueKey('workspace-navigation-controls'));
  expect(tester.getSize(controls), const Size(112, 28));
  _inside(tester.getRect(controls), caption);
  for (final name in ['sidebar', 'back', 'forward', 'home']) {
    final button = find.byKey(ValueKey('workspace-navigation-$name'));
    expect(tester.getSize(button), const Size.square(28));
    _outsideNativeDrag(button);
  }
  final captions = find.byType(WindowCaptionButton);
  expect(captions, findsNWidgets(3));
  final painters = <Type>{};
  for (final (index, name) in ['minimize', 'maximize', 'close'].indexed) {
    final button = captions.at(index);
    expect(button.hitTestable(), findsOneWidget);
    expect(
      tester.widget<WindowCaptionButton>(button).iconName,
      'icon_chrome_$name',
    );
    expect(tester.getSize(button), const Size(46, 40));
    _inside(tester.getRect(button), caption);
    _outsideNativeDrag(button);
    final paint = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter != null,
      ),
    );
    expect(
      paint,
      findsOneWidget,
      reason: 'A blank caption hit target is not enough.',
    );
    expect(tester.getSize(paint), const Size.square(16));
    expect(tester.renderObject(paint).attached, isTrue);
    final captionIcon = tester.widget<WindowCaptionButtonIcon>(
      find.descendant(
        of: button,
        matching: find.byType(WindowCaptionButtonIcon),
      ),
    );
    expect(captionIcon.color, isNotNull);
    expect(captionIcon.color!.a, greaterThan(.4));
    painters.add(tester.widget<CustomPaint>(paint).painter.runtimeType);
    final surface =
        tester.element(button).findAncestorWidgetOfExactType<ColoredBox>();
    expect(surface?.color, background);
    final decoration = tester
        .widget<Container>(
          find.descendant(of: button, matching: find.byType(Container)),
        )
        .decoration as BoxDecoration;
    expect(Color.alphaBlend(decoration.color!, background), background);
  }
  expect(painters, hasLength(3));
  expect(tester.getRect(captions.last).right, frame.right);
  expect(tester.getRect(captions.first).left, rail.right + 24);

  if (fixture.layout.showMenu) {
    expect(fixture.layout.menuIsDrawer, isFalse);
    final sidebar = tester.getRect(find.byKey(_sidebar));
    final identity = tester.getRect(find.byKey(_identityHeader));
    expect(identity.height, 40);
    expect(identity.top, caption.top);
    expect(identity.bottom, caption.bottom);
    expect(sidebar.right, caption.left);
    expect(tester.widget<ColoredBox>(find.byKey(_sidebar)).color, background);
    _inside(identity, sidebar);
    expect(find.byType(SidebarUser), findsOneWidget);
  } else {
    expect(fixture.layout.menuIsDrawer, isTrue);
    expect(find.byKey(_identityHeader), findsNothing);
    expect(caption.left, frame.left);
  }

  final selected = fixture.tabs.state.currentPageManager;
  final viewport = tester.getRect(find.byType(ReorderableListView));
  _inside(tester.getRect(_tab(selected)), viewport);
  var previousRight = viewport.left;
  for (final manager in fixture.tabs.state.pageManagers) {
    final tab = _tab(manager);
    expect(tab, findsOneWidget);
    final face = find.descendant(
      of: tab,
      matching: find.byKey(const ValueKey('workspace-tab-face')),
    );
    final bounds = tester.getRect(face);
    expect(bounds, tester.getRect(tab));
    expect(bounds.left, closeTo(previousRight, .01));
    expect(bounds.top, caption.top);
    expect(bounds.bottom, contextRow.top);
    final decoration =
        tester.widget<DecoratedBox>(face).decoration as BoxDecoration;
    expect(decoration.boxShadow, isNull);
    expect(decoration.border, isNull);
    expect(
      decoration.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(4)),
    );
    expect(
      Color.alphaBlend(decoration.color!, background),
      identical(manager, selected) ? palette.background : background,
    );
    final close = _closeButton(manager);
    expect(tester.getSize(close), const Size.square(24));
    expect(tester.widget<IconButton>(close).onPressed, isNotNull);
    _inside(tester.getRect(close), bounds);
    expect(close.hitTestable(), findsOneWidget);
    _outsideNativeDrag(close);
    previousRight = bounds.right;
  }
  expect(
    tester.getTopLeft(find.byType(TabsNewTabButton)).dx,
    closeTo(previousRight, .01),
  );
  expect(
    find.byKey(const ValueKey('new-workspace-tab')).hitTestable(),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('open-tabs-menu')).hitTestable(),
    findsOneWidget,
  );
  expect(
    PaperTheme.isEnabled(tester.element(find.byKey(_capture))),
    fixture.appearance == 'paper',
  );

  // The shared family is compiled SVG artwork, not a missing icon font. Check
  // its actual loader, including navigation arrows, tab x and sidebar glyphs.
  for (final element in find.byType(WorkspaceGlyph).evaluate()) {
    final glyph = element.widget as WorkspaceGlyph;
    // Several tabs share the SAME const x widget. Match its mounted element,
    // not widget identity, so this checks exactly one rendered leaf.
    final glyphFinder = find.byElementPredicate(
      (candidate) => identical(candidate, element),
    );
    expect(glyph.name, isNot('unknown'));
    final picture = tester.widget<SvgPicture>(
      find.descendant(
        of: glyphFinder,
        matching: find.byType(SvgPicture),
      ),
    );
    final loader = picture.bytesLoader as SvgStringLoader;
    expect(
      loader,
      SvgStringLoader(
        defaultIconSvg(glyph.name)!,
        theme: loader.theme,
        colorMapper: loader.colorMapper,
      ),
    );
    expect(tester.getSize(glyphFinder), Size.square(glyph.size));
  }
}

void _expectPageHeader(WidgetTester tester) {
  expect(find.byType(WorkspacePageHeader), findsOneWidget);
  expect(find.byType(WorkspacePageIdentity), findsOneWidget);
  final header = tester.getRect(find.byType(WorkspacePageHeader));
  final cover = tester.getRect(find.byType(WorkspacePageCover));
  final icon =
      tester.getRect(find.byKey(const ValueKey('workspace-page-icon')));
  final title = tester.getRect(find.byKey(_title));
  final metadata = tester.getRect(find.byKey(_metadata));
  final actions = tester.getRect(find.byType(WorkspaceActionRow));
  expect(header.top, tester.getRect(find.byKey(_contextRow)).bottom);
  expect(cover.left - header.left, 8);
  expect(header.right - cover.right, 8);
  expect(cover.top - header.top, 8);
  expect(cover.height, header.width < 600 ? 160 : 176);
  expect(icon.size, const Size.square(56));
  expect(cover.bottom - icon.top, closeTo(22, .01));
  expect(title.top, greaterThanOrEqualTo(icon.bottom + 6));
  expect(
    tester
        .getTopLeft(find.byKey(const ValueKey('view-decoration-icon-actions')))
        .dy,
    greaterThanOrEqualTo(cover.bottom + 8),
  );
  expect(actions.top, closeTo(metadata.bottom + 8, .01));
  expect(tester.getRect(find.byKey(_body)).top, closeTo(header.bottom, .01));
  for (final rect in [icon, title, metadata, actions]) {
    _inside(rect, header);
  }
  _inside(header, tester.getRect(find.byKey(_capture)));
  expect(
    tester.widget<ViewCoverImage>(find.byType(ViewCoverImage)).cover,
    _cover,
  );
  final image = find.descendant(
    of: find.byType(ViewCoverImage),
    matching: find.byType(Container),
  );
  expect(
    (tester.widget<Container>(image).decoration as BoxDecoration).gradient,
    isA<LinearGradient>(),
  );
  expect(tester.takeException(), isNull);
}

void _expectActions(
  WidgetTester tester, {
  required bool icon,
  required bool cover,
  required bool page,
}) {
  for (final (finder, visible) in [
    (find.byKey(const ValueKey('view-decoration-icon')), icon),
    (find.byKey(const ValueKey('view-decoration-cover')), cover),
    (find.byKey(_pageAction), page),
  ]) {
    final toolbar =
        find.ancestor(of: finder, matching: find.byType(PreviewToolbar)).first;
    final widget = tester.widget<PreviewToolbar>(toolbar);
    final fade = find.descendant(
      of: toolbar,
      matching: find.byWidgetPredicate(
        (candidate) =>
            candidate is AnimatedOpacity &&
            identical(candidate.child, widget.child),
      ),
    );
    expect(fade, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(fade).opacity, visible ? 1 : 0);
    expect(
      tester.renderObject<RenderAnimatedOpacity>(fade).opacity.value,
      visible ? 1 : 0,
    );
    expect(finder.hitTestable(), visible ? findsOneWidget : findsNothing);
  }
}

Future<void> _expectHoverWithoutReflow(
  WidgetTester tester,
  TestGesture mouse,
) async {
  await mouse.moveTo(_away);
  await tester.pumpAndSettle();
  final targets = [
    find.byType(WorkspacePageHeader),
    find.byType(WorkspacePageCover),
    find.byKey(_title),
    find.byKey(_body),
    find.byKey(const ValueKey('workspace-page-icon')),
  ];
  final bounds = targets.map(tester.getRect).toList();
  _expectActions(tester, icon: false, cover: false, page: false);
  await mouse.moveTo(tester.getCenter(find.byKey(_title)));
  await tester.pumpAndSettle();
  _expectActions(tester, icon: true, cover: false, page: true);
  await mouse.moveTo(tester.getCenter(find.byType(WorkspacePageCover)));
  await tester.pumpAndSettle();
  _expectActions(tester, icon: true, cover: true, page: true);
  for (var index = 0; index < targets.length; index++) {
    expect(tester.getRect(targets[index]), bounds[index]);
  }
  await mouse.moveTo(_away);
  await tester.pumpAndSettle();
  _expectActions(tester, icon: false, cover: false, page: false);
  expect(tester.takeException(), isNull);
}

void _inside(Rect child, Rect parent) {
  expect(child.isFinite, isTrue);
  expect(child.width, greaterThan(0));
  expect(child.height, greaterThan(0));
  expect(child.left, greaterThanOrEqualTo(parent.left - .01));
  expect(child.right, lessThanOrEqualTo(parent.right + .01));
  expect(child.top, greaterThanOrEqualTo(parent.top - .01));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + .01));
}

void _outsideNativeDrag(Finder target) {
  for (final type in [DragToMoveArea, MoveWindowDetector]) {
    expect(
      find.ancestor(of: target, matching: find.byType(type)),
      findsNothing,
    );
  }
}

class _FixtureApp extends StatelessWidget {
  const _FixtureApp(this.fixture, this.translations);
  final _Fixture fixture;
  final AssetLoader translations;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: fixture,
        builder: (_, __) => EasyLocalization(
          supportedLocales: const [_locale],
          startLocale: _locale,
          fallbackLocale: _locale,
          path: 'assets/translations',
          saveLocale: false,
          assetLoader: translations,
          child: Builder(
            builder: (context) {
              final theme = vividIconTestTheme(fixture.appearance);
              final defaults = AppFlowyDefaultTheme();
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                theme: theme,
                themeAnimationDuration: Duration.zero,
                builder: (context, child) => AppFlowyTheme(
                  data: PremiumTheme.appFlowyTheme(
                    base: theme.brightness == Brightness.dark
                        ? defaults.dark()
                        : defaults.light(),
                    palette: theme.extension<PremiumThemeExtension>()!,
                    brightness: theme.brightness,
                  ),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(fixture.scale),
                      disableAnimations: true,
                      // Do not force hidden production actions visible.
                      accessibleNavigation: false,
                    ),
                    child: DefaultIconStyleScope(
                      styles: fixture.iconStyle,
                      child: TooltipVisibility(visible: false, child: child!),
                    ),
                  ),
                ),
                home: MultiBlocProvider(
                  providers: [
                    BlocProvider<HomeSettingBloc>.value(
                      value: fixture.settings,
                    ),
                    BlocProvider<UserWorkspaceBloc>.value(
                      value: fixture.workspace,
                    ),
                  ],
                  child: Scaffold(
                    body: BlocBuilder<HomeSettingBloc, HomeSettingState>(
                      builder: (context, _) {
                        final layout = fixture.layout;
                        return RepaintBoundary(
                          key: _capture,
                          child: ClipRect(
                            // Same permanent slots and HomeLayout offsets as the
                            // desktop host, without its auth/startup/data fetches.
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned(
                                  left: layout.homePageLOffset,
                                  right: layout.homePageROffset,
                                  top: 0,
                                  bottom: 0,
                                  child: HomeStack(
                                    delegate: fixture.delegate,
                                    layout: layout,
                                    userProfile: fixture.profile,
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: layout.menuWidth,
                                  child: Offstage(
                                    offstage: !layout.showMenu,
                                    child: _FixtureSidebar(fixture),
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
              );
            },
          ),
        ),
      );
}

class _FixtureSidebar extends StatelessWidget {
  const _FixtureSidebar(this.fixture);
  final _Fixture fixture;

  @override
  Widget build(BuildContext context) => Theme(
        data: SidebarStyle.themeData(context),
        child: Builder(
          builder: (context) {
            const inset = EdgeInsets.symmetric(
              horizontal: HomeSizes.sidebarHorizontalInset,
            );
            return MouseRegion(
              onEnter: (_) => fixture.sidebarHover.value = true,
              onExit: (_) => fixture.sidebarHover.value = false,
              child: ColoredBox(
                key: _sidebar,
                color: SidebarPalette.of(context).background,
                child: Column(
                  children: [
                    Padding(
                      padding: inset,
                      child: SidebarTopMenu(
                        isSidebarOnHover: fixture.sidebarHover,
                        identity: SizedBox(
                          height: HomeSizes.workspaceSectionHeight,
                          child: SidebarUser(
                            userProfile: fixture.profile,
                            showUtilities: false,
                            createUserBloc: fixture.createUserBloc,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: SidebarMetrics.space3),
                    Expanded(
                      child: Padding(
                        padding: inset,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SidebarSectionLabel('Fixture pages'),
                            const SizedBox(height: SidebarMetrics.space2),
                            for (final (index, plugin)
                                in fixture.plugins.indexed)
                              SidebarRow(
                                reserveLeadingSpace: true,
                                selected: index == 0,
                                icon: const SidebarGlyph(SidebarIcon.document),
                                label: SidebarText.page(
                                  plugin.view.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            const Spacer(),
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child:
                                  SidebarText.section('OFFLINE VISUAL FIXTURE'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class _FixturePage extends StatefulWidget {
  const _FixturePage({super.key, required this.plugin});
  final _FixturePlugin plugin;
  @override
  State<_FixturePage> createState() => _FixturePageState();
}

class _FixturePageState extends State<_FixturePage> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final plugin = widget.plugin;
          return SingleChildScrollView(
            controller: scroll,
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ViewDecorationActions(
                  view: plugin.view,
                  userProfile: plugin.fixture.profile,
                  visible: false,
                  coverBackend: plugin.fixture.coverBackend,
                  onViewChanged: (_) =>
                      plugin.fixture.boundaries.fail('view write'),
                  children: [
                    TextButton(
                      key: _pageAction,
                      onPressed: () =>
                          plugin.fixture.boundaries.fail('page command'),
                      child: const Text('Inspect fixture'),
                    ),
                  ],
                  layoutBuilder: (iconActions, coverActions, pageActions) =>
                      WorkspacePageHeader(
                    cover: const ViewCoverImage(
                      cover: _cover,
                      width: double.infinity,
                    ),
                    coverActions: coverActions,
                    identity: WorkspacePageIdentity(
                      icon: ViewIconPicker(
                        key: _iconPicker,
                        view: plugin.view,
                        updateIcon: plugin.fixture.rejectIconWrite,
                        child: const WorkspaceGlyph.named(
                          'file-text',
                          size: WorkspaceTokens.pageIconSize,
                        ),
                      ),
                      iconActions: iconActions,
                      title: Text(
                        plugin.view.name,
                        key: _title,
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.pageTitle,
                          compact: constraints.maxWidth < 800,
                        ),
                      ),
                      metadata: const Text(
                        'Visual fixture · in-memory data only',
                        key: _metadata,
                      ),
                      actions: pageActions,
                    ),
                  ),
                ),
                Padding(
                  key: _body,
                  padding: EdgeInsets.symmetric(
                    horizontal: WorkspaceTokens.pageInset(constraints.maxWidth),
                  ),
                  child: Text(
                    'Production shell and shared page header.\n'
                    'No user workspace or network is connected.',
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.body,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _Fixture extends ChangeNotifier {
  _Fixture(this.appearance, this.width, int count, bool longTitle) {
    getIt.pushNewScope();
    getIt.registerSingleton<MenuSharedState>(menu);
    getIt.registerSingleton<FToast>(FToast());
    getIt.registerSingleton<PluginSandbox>(
      PluginSandbox()..registerPlugin(PluginType.document, _FixtureFactory()),
    );
    previousNotifications = RustStreamReceiver.shared;
    RustStreamReceiver.shared = notifications;
    EncryptionVault.instance.seedForTest();
    settings = _FixtureSettings(width, boundaries);
    workspace = _FixtureWorkspace(
      UserWorkspaceState(
        userProfile: profile,
        currentWorkspace: user.UserWorkspacePB(
          workspaceId: _workspaceId,
          name: _fixtureName,
          workspaceType: user.WorkspaceTypePB.LocalW,
        ),
      ),
      boundaries,
    );
    plugins = [
      for (var index = 0; index < count; index++)
        _FixturePlugin(
          this,
          index,
          index == 0
              ? (longTitle ? _longTitle : 'Fixture notebook')
              : index == 1
                  ? 'Reference notes'
                  : 'Project plan',
        ),
    ];
    tabs = _FixtureTabs(
      TabsState(
        pageManagers: [
          for (final plugin in plugins) PageManager(plugin: plugin),
        ],
      ),
      boundaries,
    );
    getIt.registerSingleton<TabsBloc>(tabs);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
      windowCalls.add(call.method);
      switch (call.method) {
        case 'isMaximized':
          return false;
        case 'minimize':
        case 'maximize':
        case 'close':
          return null;
        default:
          return boundaries.fail('window_manager.${call.method}');
      }
    });
  }

  final String appearance;
  double width;
  double scale = 1;
  final profile = user.UserProfilePB(
    name: _fixtureName,
    workspaceType: user.WorkspaceTypePB.LocalW,
  );
  final boundaries = _UnexpectedBoundary();
  final menu = MenuSharedState();
  final notifications = _FixtureNotifications();
  final sidebarHover = ValueNotifier(false);
  final iconStyle = ValueNotifier(DefaultIconStyle.monochrome);
  final windowCalls = <String>[];
  final users = <_FixtureUser>[];
  late final RustStreamReceiver previousNotifications;
  late final _FixtureSettings settings;
  late final _FixtureWorkspace workspace;
  late final _FixtureTabs tabs;
  late final List<_FixturePlugin> plugins;
  late final coverBackend = _FixtureCoverBackend(boundaries);
  late final repository = _FixtureRepository(boundaries);
  late final delegate = _FixtureDelegate(boundaries);

  HomeLayout get layout => HomeLayout.fromState(
        settings.state,
        availableWidth: width,
        disableAnimations: true,
      );

  void resize(double value, {required double scale}) {
    width = value;
    this.scale = scale;
    settings.resize(value);
    notifyListeners();
  }

  MenuUserBloc createUserBloc(user.UserProfilePB profile, String workspaceId) {
    if (workspaceId != _workspaceId) boundaries.fail('unexpected workspace');
    final bloc = _FixtureUser(profile, boundaries);
    users.add(bloc);
    return bloc;
  }

  Future<FlowyResult<void, FlowyError>> rejectIconWrite({
    required ViewPB view,
    required EmojiIconData viewIcon,
  }) async =>
      boundaries.fail('icon write');

  Future<void> close() async {
    try {
      await Future.wait([
        tabs.close(),
        settings.close(),
        workspace.close(),
        for (final user in users) user.close(),
        notifications.dispose(),
      ]);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowChannel, null);
      RustStreamReceiver.shared = previousNotifications;
      EncryptionVault.instance.resetForTest();
      sidebarHover.dispose();
      iconStyle.dispose();
      menu.notifier.dispose();
      dispose();
      await getIt.popScope();
    }
  }
}

/// Seed real TabsBloc once; all selection, close and layout behavior is real.
class _FixtureTabs extends TabsBloc {
  _FixtureTabs(TabsState initial, _UnexpectedBoundary boundary)
      : super(
          loadHistoryView: (_) async => boundary.fail('history lookup'),
          buildHistoryPlugin: (_) => boundary.fail('history plugin'),
          loadHomeView: (_) async => boundary.fail('Home lookup'),
        ) {
    state.dispose();
    emit(initial);
  }
}

class _FixturePlugin extends Plugin {
  _FixturePlugin(this.fixture, this.index, String name)
      : view = ViewPB(
          id: 'notion-shell-fixture-page-$index',
          parentViewId: 'notion-shell-fixture-folder',
          name: name,
          layout: ViewLayoutPB.Document,
          extra: ViewCoverCodec.mergeCover('', _cover),
        );
  final _Fixture fixture;
  final int index;
  final ViewPB view;
  int disposals = 0;
  // Empty HOST IDs deliberately bypass version/protection service lookups.
  // ViewPB IDs remain distinct for real tab labels and breadcrumb rendering;
  // production close commands address the distinct PageManager.tabId values.
  @override
  String get id => '';
  @override
  PluginType get pluginType => PluginType.document;
  @override
  late final PluginWidgetBuilder widgetBuilder = _FixtureWidgets(this);
  @override
  void dispose() => disposals++;
}

class _FixtureWidgets extends PluginWidgetBuilder {
  _FixtureWidgets(this.plugin);
  final _FixturePlugin plugin;
  @override
  late final List<NavigationItem> navigationItems = List.unmodifiable([this]);
  @override
  String get viewName => plugin.view.name;
  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;
  @override
  Widget get leftBarItem => WorkspaceBreadcrumbs(
        view: plugin.view,
        ancestors: [
          ViewPB(id: _workspaceId, name: _fixtureName),
          ViewPB(
            id: plugin.view.parentViewId,
            parentViewId: _workspaceId,
            name: 'Research',
          ),
          plugin.view,
        ],
        repository: plugin.fixture.repository,
        onNavigate: (_) =>
            plugin.fixture.boundaries.fail('breadcrumb navigation'),
      );
  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: plugin.view, shortForm: shortForm);
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      _FixturePage(
        key: ValueKey('notion-shell-page-${plugin.index}'),
        plugin: plugin,
      );
}

class _FixtureFactory extends PluginBuilder {
  @override
  Plugin build(dynamic data) => data as _FixturePlugin;
  @override
  String get menuName => 'Offline shell fixture';
  @override
  FlowySvgData get icon => const FlowySvgData('');
  @override
  PluginType get pluginType => PluginType.document;
  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class _FixtureDelegate extends HomeStackDelegate {
  _FixtureDelegate(this.boundary);
  final _UnexpectedBoundary boundary;
  @override
  void didDeleteStackWidget(ViewPB view, int? index) =>
      boundary.fail('delete page');
}

/// In-memory state/service boundaries only. No auth, native backend, workspace
/// repository, preference file, account listener or app startup is invoked.
class _FixtureSettings extends Cubit<HomeSettingState>
    implements HomeSettingBloc {
  _FixtureSettings(double width, this.boundary) : super(_state(width));
  final _UnexpectedBoundary boundary;
  static HomeSettingState _state(double width) => HomeSettingState(
        panelContext: null,
        workspaceSetting: WorkspaceLatestPB(workspaceId: _workspaceId),
        unauthorized: false,
        menuStatus: WorkspaceLayout.sidebarIsDrawer(width)
            ? MenuStatus.hidden
            : MenuStatus.expanded,
        isNotificationPanelCollapsed: true,
        isScreenSmall: WorkspaceLayout.sidebarIsDrawer(width),
        hasColappsedMenuManually: false,
        resizeOffset: 0,
        resizeStart: 0,
        resizeType: MenuResizeType.slide,
      );
  void resize(double width) => emit(_state(width));
  @override
  void collapseMenu() => emit(
        state.copyWith(
          menuStatus: state.menuStatus == MenuStatus.expanded
              ? MenuStatus.hidden
              : MenuStatus.expanded,
        ),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      boundary.fail('settings ${invocation.memberName}');
}

class _FixtureWorkspace extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _FixtureWorkspace(super.state, this.boundary);
  final _UnexpectedBoundary boundary;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      boundary.fail('workspace ${invocation.memberName}');
}

class _FixtureUser extends Cubit<MenuUserState> implements MenuUserBloc {
  _FixtureUser(user.UserProfilePB profile, this.boundary)
      : super(MenuUserState.initial(profile));
  final _UnexpectedBoundary boundary;
  Future<void>? _closing;
  @override
  void add(MenuUserEvent event) {
    if (event != const MenuUserEvent.initial()) boundary.fail('profile event');
  }

  @override
  Future<FlowyResult<void, FlowyError>> saveUserIcon(String iconUrl) async =>
      boundary.fail('profile write');
  @override
  Future<void> close() => _closing ??= super.close();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      boundary.fail('profile ${invocation.memberName}');
}

class _FixtureNotifications implements RustStreamReceiver {
  @override
  final observable = StreamController<SubscribeObject>.broadcast();
  @override
  Future<void> dispose() => observable.close();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No native notification port in the shell fixture.');
}

class _UnexpectedBoundary {
  final calls = <String>[];
  Never fail(String operation) {
    calls.add(operation);
    throw StateError('Offline shell fixture cannot perform $operation.');
  }
}

class _FixtureRepository implements WorkspaceItemRepository {
  _FixtureRepository(this.boundary);
  final _UnexpectedBoundary boundary;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      boundary.fail('repository ${invocation.memberName}');
}

class _FixtureCoverBackend implements ViewCoverActionsBackend {
  _FixtureCoverBackend(this.boundary);
  final _UnexpectedBoundary boundary;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      boundary.fail('cover ${invocation.memberName}');
}

class _FixtureEnvironment {
  final _previousFetching = GoogleFonts.config.allowRuntimeFetching;
  final _previousRecents = RecentIcons.enable;
  final network = _NoNetwork();
  final loadedFamilies = <String>{};
  late final AssetLoader translations;

  Future<T> offline<T>(Future<T> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, network);

  Future<void> prepare() => offline(() async {
        if (!Platform.isWindows) {
          throw StateError('These caption/font goldens are pinned to Windows.');
        }
        SharedPreferences.setMockInitialValues({});
        GoogleFonts.config.allowRuntimeFetching = false;
        RecentIcons.enable = false;
        EasyLocalization.logger.enableLevels = [];
        await EasyLocalization.ensureInitialized();
        translations = _Translations(
          await const TestBundleAssetLoader()
              .load('assets/translations', _locale),
        );

        // Reuse vivid_icon_test_support's themes and SVG settling, but do NOT
        // alias DM Sans bytes to Segoe UI as its geometry-only setup does.
        // Load the actual Windows face, plus every resolved theme family.
        final families = <String>{
          SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
          for (final appearance in vividIconTestAppearances)
            vividIconTestTheme(appearance).textTheme.bodyMedium!.fontFamily!,
        };
        for (final family in families) {
          final normalized = family.split('_').first.replaceAll(' ', '');
          final loader = FontLoader(family);
          if (normalized == 'SegoeUI') {
            final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
            for (final file in [
              'segoeui.ttf',
              'seguisb.ttf',
              'segoeuib.ttf',
              'segoeuii.ttf',
            ]) {
              final bytes = await File('$windows/Fonts/$file').readAsBytes();
              expect(bytes.length, greaterThan(1000));
              loader.addFont(Future.value(ByteData.sublistView(bytes)));
            }
          } else if (normalized == 'DMSans') {
            loader.addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            );
            loader.addFont(
              rootBundle.load(
                'assets/google_fonts/DM_Sans/DMSans-VariableItalic.ttf',
              ),
            );
          } else {
            throw StateError('No offline font mapping for $family.');
          }
          await loader.load();
          loadedFamilies.add(family);
        }
        // AppFlowyTheme text and any Material icon fallback must not use Ahem.
        for (final (family, asset) in [
          ('Inter', 'assets/google_fonts/Inter/Inter-Variable.ttf'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
          loadedFamilies.add(family);
        }
        expect(network.attempts, 0);
      });

  void expectFonts(WidgetTester tester) {
    final theme = Theme.of(tester.element(find.byKey(_capture)));
    expect(theme.platform, TargetPlatform.windows);
    expect(loadedFamilies, contains(theme.textTheme.bodyMedium!.fontFamily));
    expect(loadedFamilies, contains('MaterialIcons'));
    for (final family
        in loadedFamilies.where((family) => family != 'MaterialIcons')) {
      double measure(String text) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontFamily: family, fontSize: 16),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      expect(
        measure('iiii'),
        lessThan(measure('WWWW')),
        reason: '$family must render real proportional glyphs, not Ahem.',
      );
    }
  }

  void restore() {
    RecentIcons.enable = _previousRecents;
    GoogleFonts.config.allowRuntimeFetching = _previousFetching;
  }
}

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(values); // Future.wait must not receive SynchronousFuture.
}

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Network is forbidden in the shell visual fixture.');
  }
}
