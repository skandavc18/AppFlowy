import 'dart:io';

import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_hover_suppression.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    testWidgets('$appearance renders every sidebar icon at a visible size',
        (tester) async {
      await tester.pumpWidget(
        _app(
          appearance,
          Wrap(
            children: [
              for (final icon in SidebarIcon.values)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: SidebarGlyph(icon, key: ValueKey(icon)),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FlowySvg), findsNWidgets(SidebarIcon.values.length));
      for (final icon in SidebarIcon.values) {
        final finder = find.descendant(
          of: find.byKey(ValueKey(icon)),
          matching: find.byType(FlowySvg),
        );
        final svg = tester.widget<FlowySvg>(finder);
        expect(svg.svgString, startsWith('<svg'));
        expect(svg.color, SidebarPalette.of(tester.element(finder)).icon);
        expect(svg.color!.a, greaterThan(0.4));
        expect(
          tester.getSize(finder),
          const Size.square(SidebarMetrics.iconSize),
        );
      }
      expect(tester.takeException(), isNull);
    });

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
