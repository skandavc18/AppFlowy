import 'dart:ui' as ui;

import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeAppMenuEntries', () {
    test('drops leading, trailing and repeated separators', () {
      final entries = normalizeAppMenuEntries([
        const AppMenuSeparator(),
        const AppMenuItem(label: 'One'),
        const AppMenuSeparator(),
        const AppMenuSeparator(),
        const AppMenuItem(label: 'Two'),
        const AppMenuSeparator(),
      ]);

      expect(entries.length, 3);
      expect((entries[0] as AppMenuItem).label, 'One');
      expect(entries[1], isA<AppMenuSeparator>());
      expect((entries[2] as AppMenuItem).label, 'Two');
    });

    test('keeps an empty list empty', () {
      expect(normalizeAppMenuEntries(const [AppMenuSeparator()]), isEmpty);
    });
  });

  group('AppContextMenu', () {
    Future<void> openMenu(
      WidgetTester tester, {
      required List<AppMenuEntry> entries,
      ValueChanged<Object?>? onResult,
      bool disableAnimations = false,
      bool accessibleNavigation = false,
      double textScale = 1,
      bool settle = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: disableAnimations,
              accessibleNavigation: accessibleNavigation,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    final result = await showAppMenu<Object?>(
                      context: context,
                      entries: entries,
                      globalPosition: const Offset(120, 120),
                    );
                    onResult?.call(result);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump();
      }
    }

    Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(finder));
      await tester.pump();
      return gesture;
    }

    testWidgets('renders every kind of entry', (tester) async {
      await openMenu(
        tester,
        entries: const [
          AppMenuHeader('Create'),
          AppMenuItem(label: 'New folder', icon: Icons.folder_rounded),
          AppMenuSeparator(),
          AppMenuItem(label: 'Delete', destructive: true, shortcut: 'Del'),
        ],
      );

      expect(find.text('CREATE'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Del'), findsOneWidget);
      expect(find.byType(AppMenuSeparatorLine), findsOneWidget);
      expect(find.byType(AppMenuSurface), findsOneWidget);
    });

    testWidgets('tapping a row returns its value and closes the menu',
        (tester) async {
      Object? result;
      var ran = false;
      await openMenu(
        tester,
        onResult: (value) => result = value,
        entries: [
          AppMenuItem(
            label: 'Rename',
            value: 'rename',
            onSelected: () => ran = true,
          ),
        ],
      );

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(result, 'rename');
      expect(ran, isTrue);
      expect(find.byType(AppMenuSurface), findsNothing);
    });

    testWidgets('a disabled row cannot be chosen', (tester) async {
      var ran = false;
      await openMenu(
        tester,
        entries: [
          AppMenuItem(
            label: 'Paste',
            enabled: false,
            onSelected: () => ran = true,
          ),
        ],
      );

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(ran, isFalse);
      expect(find.byType(AppMenuSurface), findsOneWidget);
    });

    testWidgets('hovering a row opens its submenu without a click',
        (tester) async {
      await openMenu(
        tester,
        entries: const [
          AppMenuItem(label: 'First'),
          AppMenuItem(
            label: 'Add file',
            submenu: [
              AppMenuItem(label: 'Document'),
              AppMenuItem(label: 'Spreadsheet'),
            ],
          ),
        ],
      );

      expect(find.text('Document'), findsNothing);

      await hover(tester, find.text('Add file'));
      await tester.pump(AppMenuMetrics.submenuOpenDelay);
      await tester.pumpAndSettle();

      expect(find.text('Document'), findsOneWidget);
      expect(find.byType(AppMenuSurface), findsNWidgets(2));
    });

    testWidgets('moving to a sibling row closes the open submenu',
        (tester) async {
      await openMenu(
        tester,
        entries: const [
          AppMenuItem(
            label: 'Add file',
            submenu: [AppMenuItem(label: 'Document')],
          ),
          AppMenuItem(label: 'Rename'),
        ],
      );

      final gesture = await hover(tester, find.text('Add file'));
      await tester.pump(AppMenuMetrics.submenuOpenDelay);
      await tester.pumpAndSettle();
      expect(find.text('Document'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(find.text('Rename')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Document'), findsNothing);
      expect(find.byType(AppMenuSurface), findsOneWidget);
    });

    testWidgets('arrow keys move the highlight and enter runs the row',
        (tester) async {
      Object? result;
      await openMenu(
        tester,
        onResult: (value) => result = value,
        entries: const [
          AppMenuItem(label: 'One', value: 1),
          AppMenuSeparator(),
          AppMenuItem(label: 'Two', value: 2),
          AppMenuItem(label: 'Skipped', value: 3, enabled: false),
        ],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(result, 2);
    });

    testWidgets('right arrow opens a submenu and left arrow closes it',
        (tester) async {
      await openMenu(
        tester,
        entries: const [
          AppMenuItem(
            label: 'Turn into',
            submenu: [AppMenuItem(label: 'Heading')],
          ),
        ],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Heading'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Heading'), findsNothing);
      expect(find.byType(AppMenuSurface), findsOneWidget);
    });

    testWidgets('escape closes the submenu first and the menu second',
        (tester) async {
      await openMenu(
        tester,
        entries: const [
          AppMenuItem(
            label: 'Turn into',
            submenu: [AppMenuItem(label: 'Heading')],
          ),
        ],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Heading'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Heading'), findsNothing);
      expect(find.byType(AppMenuSurface), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuSurface), findsNothing);
    });

    testWidgets('nesting is not limited to one level', (tester) async {
      await openMenu(
        tester,
        entries: const [
          AppMenuItem(
            label: 'Level one',
            submenu: [
              AppMenuItem(
                label: 'Level two',
                submenu: [AppMenuItem(label: 'Level three')],
              ),
            ],
          ),
        ],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(find.text('Level three'), findsOneWidget);
      expect(find.byType(AppMenuSurface), findsNWidgets(3));
    });

    testWidgets('a row that keeps the menu open does not dismiss it',
        (tester) async {
      var count = 0;
      await openMenu(
        tester,
        entries: [
          AppMenuItem(
            label: 'Toggle',
            closeOnSelect: false,
            onSelected: () => count++,
          ),
        ],
      );

      await tester.tap(find.text('Toggle'));
      await tester.pump();
      await tester.tap(find.text('Toggle'));
      await tester.pump();

      expect(count, 2);
      expect(find.byType(AppMenuSurface), findsOneWidget);
    });

    TextStyle labelStyleOf(WidgetTester tester, String label) => tester
        .widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        )
        .style;

    testWidgets('destructive rows are tinted without shouting', (tester) async {
      await openMenu(
        tester,
        entries: const [
          AppMenuItem(label: 'Keep'),
          AppMenuItem(label: 'Delete', destructive: true),
        ],
      );

      final normal = labelStyleOf(tester, 'Keep').color!;
      final danger = labelStyleOf(tester, 'Delete').color!;

      expect(danger, isNot(normal));
      expect(danger.r, greaterThan(danger.g));
      expect(danger.r, greaterThan(danger.b));
    });

    testWidgets('labels are set in the application face at medium weight',
        (tester) async {
      await openMenu(tester, entries: const [AppMenuItem(label: 'Rename')]);

      final style = labelStyleOf(tester, 'Rename');

      expect(style.fontWeight, FontWeight.w500);
      // A variable face renders at its default instance without an explicit
      // axis, which is what made menu text look thinner than the app.
      expect(
        style.fontVariations,
        const [FontVariation.weight(500)],
      );
      // Variable and fallback faces share the same explicit medium weight.
      expect(AppMenuMetrics.labelWeightAxis, 500);
      expect(style.fontSize, AppMenuMetrics.labelSize);
      expect(style.leadingDistribution, TextLeadingDistribution.even);
    });

    testWidgets('a resting row keeps the hover colour channels',
        (tester) async {
      await openMenu(tester, entries: const [AppMenuItem(label: 'Rename')]);

      final container = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('Rename'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      final resting = decoration.color!;
      final style = AppMenuStyle.of(
        tester.element(find.text('Rename')),
      );

      // Fading from Colors.transparent would pass through transparent black
      // and flash dark before settling.
      expect(resting.a, 0);
      expect(resting.r, style.hover.r);
      expect(resting.g, style.hover.g);
      expect(resting.b, style.hover.b);
      expect(container.duration.inMilliseconds, inInclusiveRange(120, 160));
      expect(container.curve, Curves.easeOutCubic);
    });

    testWidgets('every row is the same height', (tester) async {
      await openMenu(
        tester,
        entries: const [
          AppMenuItem(label: 'Plain'),
          AppMenuItem(label: 'With icon', icon: Icons.copy_rounded),
          AppMenuItem(label: 'With shortcut', shortcut: 'Ctrl+C'),
          AppMenuItem(
            label: 'With submenu',
            submenu: [AppMenuItem(label: 'Nested')],
          ),
        ],
      );

      final heights = tester
          .widgetList<AppMenuRow>(find.byType(AppMenuRow))
          .map((row) => tester.getSize(find.byWidget(row)).height)
          .toSet();

      expect(heights, {AppMenuMetrics.rowHeight});
    });

    testWidgets('a custom row can close the menu it lives in', (tester) async {
      await openMenu(
        tester,
        entries: [
          AppMenuCustom(
            builder: (context) => TextButton(
              onPressed: () => AppMenuScope.maybeOf(context)?.close(),
              child: const Text('custom'),
            ),
          ),
        ],
      );

      expect(find.text('custom'), findsOneWidget);
      await tester.tap(find.text('custom'));
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuSurface), findsNothing);
    });

    testWidgets('the menu is pushed back on screen instead of overflowing',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppMenu<void>(
                  context: context,
                  entries: const [
                    AppMenuItem(label: 'One'),
                    AppMenuItem(label: 'Two'),
                  ],
                  globalPosition: const Offset(790, 590),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byType(AppMenuSurface));
      expect(rect.right, lessThanOrEqualTo(800));
      expect(rect.bottom, lessThanOrEqualTo(600));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
    });

    for (final accessible in [false, true]) {
      testWidgets(
          'reduced-motion menus skip root, row and submenu motion ($accessible)',
          (tester) async {
        await openMenu(
          tester,
          disableAnimations: !accessible,
          accessibleNavigation: accessible,
          settle: false,
          entries: const [
            AppMenuItem(
              label: 'Parent',
              submenu: [AppMenuItem(label: 'Child')],
            ),
          ],
        );
        final surface = find.byType(AppMenuSurface);
        final route = ModalRoute.of(tester.element(surface))!;
        expect(route.transitionDuration, Duration.zero);
        expect(route.reverseTransitionDuration, Duration.zero);
        final scale = tester.widget<ScaleTransition>(
          find
              .ancestor(of: surface, matching: find.byType(ScaleTransition))
              .first,
        );
        expect(scale.scale.value, 1);
        expect(
          tester
              .widget<AnimatedContainer>(
                find.descendant(
                  of: find.byType(AppMenuRow),
                  matching: find.byType(AnimatedContainer),
                ),
              )
              .duration,
          Duration.zero,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.pump();
        expect(find.text('Child'), findsOneWidget);
        expect(
          tester
              .widget<TweenAnimationBuilder<double>>(
                find.byType(TweenAnimationBuilder<double>),
              )
              .duration,
          Duration.zero,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(find.byType(AppMenuSurface), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('scaled menu rows keep labels, metadata and disabled semantics',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await openMenu(
          tester,
          textScale: 2,
          entries: const [
            AppMenuItem(label: 'Restore', subtitle: 'Recover this page'),
            AppMenuItem(label: 'Unavailable', enabled: false),
          ],
        );
        final row = find.widgetWithText(AppMenuRow, 'Restore');
        expect(
          tester.getSize(row).height,
          greaterThan(AppMenuMetrics.rowHeightWithSubtitle),
        );
        final metadata = tester.getRect(find.text('Recover this page'));
        final bounds = tester.getRect(row);
        expect(metadata.bottom, lessThanOrEqualTo(bounds.bottom));
        final disabled =
            tester.getSemantics(find.widgetWithText(AppMenuRow, 'Unavailable'));
        expect(disabled.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(disabled.hasFlag(ui.SemanticsFlag.isEnabled), isFalse);
        expect(
          disabled.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  });
}
