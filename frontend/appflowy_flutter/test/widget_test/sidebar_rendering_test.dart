import 'dart:io';

import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_hover_suppression.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_icons.dart'
    show DSWorkspaceGlyph, DefaultIconStyleScope, WorkspaceGlyphs;
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_top_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:window_manager/window_manager.dart';

import 'vivid_icon_test_support.dart' show settleVividIconPictures;

const _frame = Duration(microseconds: 8333);
const _pointer = Offset(120, 160);

void main() {
  setUpAll(() async {
    final groups = await loadIconPack(sidebarIconPack);
    expect(groups, isNotEmpty);
  });

  test('sidebar has no per-pixel rebuild listener', () {
    final source = File(
      'lib/workspace/presentation/home/menu/sidebar/sidebar.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('_scrollController.addListener(')));
    expect(source, isNot(contains('_scrollDebounce')));
    expect(source, isNot(contains('_isScrolling')));
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final drawer in [false, true]) {
      testWidgets(
          '$appearance: 40px sidebar identity keeps a local dismiss only in a drawer ($drawer)',
          (tester) async {
        final settings = _HeaderSettingsBloc();
        when(() => settings.state).thenReturn(_headerSettings(drawer));
        when(() => settings.isClosed).thenReturn(false);
        when(() => settings.stream)
            .thenAnswer((_) => const Stream<HomeSettingState>.empty());
        final hover = ValueNotifier(false);
        var identityTaps = 0;
        try {
          await tester.pumpWidget(
            _app(
              appearance,
              BlocProvider<HomeSettingBloc>.value(
                value: settings,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SidebarTopMenu(
                    isSidebarOnHover: hover,
                    identity: TextButton(
                      key: const ValueKey('sidebar-test-identity'),
                      onPressed: () => identityTaps++,
                      child: const Text('Workspace'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final header = find.byKey(const ValueKey('sidebar-identity-header'));
          final identity = find.byKey(const ValueKey('sidebar-test-identity'));
          final dismiss = find.descendant(
            of: header,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SidebarIconButton &&
                  widget.icon == SidebarIcon.collapse,
            ),
          );
          expect(tester.getSize(header), const Size(260, 40));
          expect(identity.hitTestable(), findsOneWidget);
          expect(dismiss, drawer ? findsOneWidget : findsNothing);
          expect(
            find.descendant(
              of: header,
              matching: find.byType(WindowDragTarget),
            ),
            findsOneWidget,
          );
          for (final dragType in [DragToMoveArea, MoveWindowDetector]) {
            expect(
              find.ancestor(of: identity, matching: find.byType(dragType)),
              findsNothing,
            );
            expect(
              find.ancestor(of: dismiss, matching: find.byType(dragType)),
              findsNothing,
            );
          }
          await tester.tap(identity);
          await tester.pumpAndSettle();
          expect(identityTaps, 1);
          verifyNever(() => settings.collapseMenu());
          hover.value = true;
          await tester.pumpAndSettle();
          expect(tester.getSize(header).height, 40);
          if (drawer) {
            expect(dismiss.hitTestable(), findsOneWidget);
            expect(tester.getSize(dismiss), const Size.square(24));
            expect(
              tester.getRect(dismiss).overlaps(tester.getRect(identity)),
              isFalse,
            );
            await tester.tap(dismiss);
            await tester.pumpAndSettle();
            verify(() => settings.collapseMenu()).called(1);
          } else {
            expect(dismiss, findsNothing);
            verifyNever(() => settings.collapseMenu());
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          hover.dispose();
        }
      });
    }

    for (final style in DefaultIconStyle.values) {
      final vivid = style == DefaultIconStyle.vivid;
      final preference = vivid ? 'unset Vivid' : 'saved Monochrome';
      testWidgets(
          '$appearance/$preference renders every sidebar icon at a visible size',
          (tester) async {
        final styles = ValueNotifier(DefaultIconStyle.fromId(style.name));
        addTearDown(styles.dispose);
        final icons = Wrap(
          children: [
            for (final icon in SidebarIcon.values)
              Padding(
                padding: const EdgeInsets.all(4),
                child: SidebarGlyph(icon, key: ValueKey(icon)),
              ),
          ],
        );
        await tester.pumpWidget(
          _app(
            appearance,
            // Keep the default branch unscoped; only Monochrome is selected.
            vivid ? icons : DefaultIconStyleScope(styles: styles, child: icons),
          ),
        );
        await settleVividIconPictures(tester);
        expect(
          find.byType(DSWorkspaceGlyph),
          findsNWidgets(SidebarIcon.values.length),
        );
        expect(
          find.byType(SvgPicture),
          findsNWidgets(SidebarIcon.values.length),
        );
        for (final icon in SidebarIcon.values) {
          final glyphFinder = find.descendant(
            of: find.byKey(ValueKey(icon)),
            matching: find.byType(DSWorkspaceGlyph),
          );
          expect(glyphFinder, findsOneWidget);
          final glyph = tester.widget<DSWorkspaceGlyph>(glyphFinder);
          expect(glyph.name, icon.name);
          expect(glyph.style, isNull);
          expect(
            DefaultIconStyleScope.of(tester.element(glyphFinder)).value,
            style,
          );
          final finder = find.descendant(
            of: glyphFinder,
            matching: find.byType(SvgPicture),
          );
          expect(finder, findsOneWidget);
          final svg = tester.widget<SvgPicture>(finder);
          final artwork = vivid
              ? vividIconSvg(WorkspaceGlyphs.vividNameFor(icon.name)!)
              : defaultIconSvg(icon.name);
          expect(artwork, startsWith('<svg'));
          final loader = svg.bytesLoader as SvgStringLoader;
          expect(
            loader,
            SvgStringLoader(
              artwork!,
              theme: loader.theme,
              colorMapper: loader.colorMapper,
            ),
          );
          final ink = SidebarPalette.of(tester.element(finder)).icon;
          expect(glyph.color, ink);
          expect(glyph.color!.a, greaterThan(0.4));
          expect(
            svg.colorFilter,
            vivid ? isNull : ColorFilter.mode(ink, BlendMode.srcIn),
          );
          expect(svg.width, SidebarMetrics.iconSize);
          expect(svg.height, SidebarMetrics.iconSize);
          expect(
            tester.getSize(finder),
            const Size.square(SidebarMetrics.iconSize),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('$appearance scroll frames do not rebuild the sidebar tree',
        (tester) async {
      final scroll = ScrollController();
      var builds = 0;
      var enters = 0;
      var exits = 0;
      var actionsBuilt = 0;
      var clicks = 0;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final pan = await tester.createGesture(
        pointer: 87,
        kind: PointerDeviceKind.trackpad,
      );
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            SidebarScrollbar(
              controller: scroll,
              child: Builder(
                builder: (context) {
                  builds++;
                  return SingleChildScrollView(
                    controller: scroll,
                    child: Column(
                      children: [
                        for (var i = 0; i < 200; i++)
                          SidebarRow(
                            key: ValueKey('sidebar-page-$i'),
                            icon: const SidebarGlyph(SidebarIcon.document),
                            label: Text('Page $i'),
                            onTap: () => clicks++,
                            onHoverChanged: (value) =>
                                value ? enters++ : exits++,
                            trailingSlots: 1,
                            trailingBuilder: (_) {
                              actionsBuilt++;
                              return [
                                SidebarIconButton(
                                  icon: SidebarIcon.more,
                                  onPressed: () {},
                                ),
                              ];
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ScrollHoverSuppression), findsOneWidget);
        final initialBuilds = builds;
        final childState =
            tester.state(find.byKey(const ValueKey('sidebar-page-30')));
        await mouse.addPointer(location: const Offset(600, 500));
        await mouse.moveTo(_pointer);
        await tester.pumpAndSettle();
        expect(enters, 1);

        await pan.panZoomStart(_pointer);
        await pan.panZoomUpdate(
          _pointer,
          pan: const Offset(0, -32),
          timeStamp: const Duration(milliseconds: 16),
        );
        await tester.pump(_frame);
        expect(scroll.position.isScrollingNotifier.value, isTrue);
        expect(exits, 1);
        final hoverActionsAtStart = actionsBuilt;
        for (var step = 2; step <= 25; step++) {
          await pan.panZoomUpdate(
            _pointer,
            pan: Offset(0, -32.0 * step),
            timeStamp: Duration(milliseconds: step * 16),
          );
          await tester.pump(_frame);
          await tester.pump(_frame);
          expect(builds, initialBuilds);
          expect(enters, 1);
          expect(actionsBuilt, hoverActionsAtStart);
        }
        final beforeRelease = scroll.offset;
        expect(beforeRelease, greaterThan(400));
        await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 401));
        await tester.pump();
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(_frame);
          expect(builds, initialBuilds);
          expect(enters, 1);
        }
        expect(scroll.offset, greaterThan(beforeRelease));

        // The hover gate must not swallow clicks delivered during coasting.
        await tester.tapAt(_pointer, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(clicks, 1);
        expect(enters, 2);
        expect(exits, 1);
        expect(builds, initialBuilds);
        expect(
          tester.state(find.byKey(const ValueKey('sidebar-page-30'))),
          same(childState),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      }
    });
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
        'sidebar wheel keeps existing physics (reduced motion: $reducedMotion)',
        (tester) async {
      final scroll = ScrollController();
      try {
        await tester.pumpWidget(
          _app(
            'paper',
            SidebarScrollbar(
              controller: scroll,
              child: SingleChildScrollView(
                controller: scroll,
                child: const SizedBox(height: 4000),
              ),
            ),
            reducedMotion: reducedMotion,
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            position: _pointer,
            scrollDelta: Offset(0, 120),
          ),
        );
        expect(scroll.offset, reducedMotion ? 120 : 0);
        await tester.pump(_frame);
        final first = scroll.offset;
        await tester.pump(_frame);
        expect(scroll.offset, reducedMotion ? first : greaterThan(first));
        await tester.pumpAndSettle(_frame);
        expect(scroll.offset, closeTo(120, 0.11));
        expect(
          scroll.position.physics is PremiumKineticScrollPhysics,
          !reducedMotion,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      }
    });
  }
}

class _HeaderSettingsBloc extends Mock implements HomeSettingBloc {}

HomeSettingState _headerSettings(bool drawer) => HomeSettingState(
      panelContext: null,
      workspaceSetting: WorkspaceLatestPB(workspaceId: 'sidebar-header-test'),
      unauthorized: false,
      menuStatus: MenuStatus.expanded,
      isNotificationPanelCollapsed: true,
      isScreenSmall: drawer,
      hasColappsedMenuManually: false,
      resizeOffset: 0,
      resizeStart: 0,
      resizeType: MenuResizeType.slide,
    );

Widget _app(String appearance, Widget child, {bool reducedMotion = false}) {
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
  return MaterialApp(
    theme: theme,
    themeAnimationDuration: Duration.zero,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: PremiumScrollScope(
        enabled: true,
        child: Builder(
          builder: (context) => Theme(
            data: SidebarStyle.themeData(context),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 260, height: 320, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}
