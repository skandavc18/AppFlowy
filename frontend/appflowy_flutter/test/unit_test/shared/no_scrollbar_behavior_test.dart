import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart'
    show DatabasePluginWidgetBuilderSize;
import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets(
    'retains parent behavior and removes only scrollbar decoration after copies',
    (tester) async {
      final tracker = VelocityTracker.withKind(PointerDeviceKind.stylus);
      final GestureVelocityTrackerBuilder trackerBuilder = (_) => tracker;
      final parent = _ParentScrollBehavior(trackerBuilder);
      final behavior = NoScrollbarBehavior(parent);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      late BuildContext context;

      await tester.pumpWidget(
        _testApp(
          Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      for (final candidate in [
        behavior,
        behavior.copyWith(scrollbars: true),
        behavior.copyWith(scrollbars: false).copyWith(scrollbars: true),
      ]) {
        expect(candidate.getPlatform(context), TargetPlatform.macOS);
        expect(candidate.dragDevices, same(parent.dragDevices));
        expect(
          candidate.getMultitouchDragStrategy(context),
          MultitouchDragStrategy.sumAllPointers,
        );
        expect(
          candidate.getScrollPhysics(context),
          same(_ParentScrollBehavior.physics),
        );
        expect(candidate.velocityTrackerBuilder(context), same(trackerBuilder));
        expect(
          candidate.velocityTrackerBuilder(context)(
            const PointerDownEvent(kind: PointerDeviceKind.stylus),
          ),
          same(tracker),
        );
        expect(
            candidate.pointerAxisModifiers, same(parent.pointerAxisModifiers));

        for (final direction in [AxisDirection.down, AxisDirection.right]) {
          const child = SizedBox(width: 20, height: 20);
          final details = ScrollableDetails(
            direction: direction,
            controller: controller,
          );
          expect(
            parent.buildScrollbar(context, child, details),
            isA<RawScrollbar>(),
          );
          expect(
              candidate.buildScrollbar(context, child, details), same(child));

          final overscroll =
              candidate.buildOverscrollIndicator(context, child, details);
          expect(overscroll, isA<GlowingOverscrollIndicator>());
          final indicator = overscroll as GlowingOverscrollIndicator;
          expect(indicator.child, same(child));
          expect(indicator.axisDirection, direction);
          expect(indicator.color, _ParentScrollBehavior.overscrollColor);
        }
      }
      expect(tester.takeException(), isNull);
    },
    variant: windows,
  );

  testWidgets(
    'new local multiline SelectableText has no bar while outer and sibling do',
    (tester) async {
      final outerController = ScrollController();
      final siblingController = ScrollController();
      addTearDown(outerController.dispose);
      addTearDown(siblingController.dispose);
      const guardKey = ValueKey('local-scrollbar-guard');
      const addedTextKey = ValueKey('added-multiline-text');
      const outerKey = ValueKey('outer-scroll');
      const siblingKey = ValueKey('normal-sibling');
      var showNewText = false;
      late StateSetter update;

      await tester.pumpWidget(
        _testApp(
          SizedBox(
            width: 600,
            height: 260,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    key: outerKey,
                    controller: outerController,
                    primary: false,
                    child: Column(
                      children: [
                        Builder(
                          builder: (context) => ScrollConfiguration(
                            key: guardKey,
                            behavior: NoScrollbarBehavior(
                              ScrollConfiguration.of(context),
                            ),
                            child: StatefulBuilder(
                              builder: (context, setState) {
                                update = setState;
                                return Column(
                                  children: [
                                    const SelectableText(
                                      'Existing\nlocal reading',
                                      maxLines: 2,
                                    ),
                                    if (showNewText)
                                      SelectableText(
                                        List.generate(
                                          20,
                                          (index) => 'New reading line $index',
                                        ).join('\n'),
                                        key: addedTextKey,
                                        maxLines: 3,
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 800),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ListView.builder(
                    key: siblingKey,
                    controller: siblingController,
                    primary: false,
                    itemCount: 30,
                    itemExtent: 40,
                    itemBuilder: (_, index) => Text('Normal row $index'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(addedTextKey), findsNothing);
      expect(_scrollbarsWithin(find.byKey(guardKey)), findsNothing);
      expect(find.byType(Scrollbar), findsNWidgets(2));

      update(() => showNewText = true);
      await tester.pump();

      final addedText = find.byKey(addedTextKey);
      expect(addedText, findsOneWidget);
      final editable = tester.widget<EditableText>(
        find.descendant(of: addedText, matching: find.byType(EditableText)),
      );
      expect(editable.maxLines, 3);
      final textScroll = tester.state<ScrollableState>(
        find.descendant(of: addedText, matching: find.byType(Scrollable)),
      );
      expect(textScroll.position.maxScrollExtent, greaterThan(0));
      expect(_scrollbarsWithin(find.byKey(guardKey)), findsNothing);

      // Positive controls: these are actual Material Scrollbar widgets, not
      // just an assertion that the local behavior has a particular type.
      for (final entry in [
        (key: outerKey, controller: outerController),
        (key: siblingKey, controller: siblingController),
      ]) {
        expect(entry.controller.hasClients, isTrue);
        expect(entry.controller.position.maxScrollExtent, greaterThan(0));
        final bar = find.descendant(
          of: find.byKey(entry.key),
          matching: find.byType(Scrollbar),
        );
        expect(bar, findsOneWidget);
        expect(
            tester.widget<Scrollbar>(bar).controller, same(entry.controller));
      }
      expect(find.byType(Scrollbar), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: windows,
  );

  for (final axis in [Axis.vertical, Axis.horizontal]) {
    testWidgets(
      '${axis.name} wheel and drag input still scrolls the hit-tested viewport',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        const viewportKey = ValueKey('guarded-viewport');
        const contentKey = ValueKey('scrolling-content');
        var wheelEvents = 0;
        var downEvents = 0;

        await tester.pumpWidget(
          _testApp(
            Builder(
              builder: (context) => ScrollConfiguration(
                behavior: NoScrollbarBehavior(ScrollConfiguration.of(context)),
                child: SizedBox(
                  width: 280,
                  height: 180,
                  child: SingleChildScrollView(
                    key: viewportKey,
                    controller: controller,
                    primary: false,
                    scrollDirection: axis,
                    child: Listener(
                      key: contentKey,
                      behavior: HitTestBehavior.opaque,
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) wheelEvents++;
                      },
                      onPointerDown: (_) => downEvents++,
                      child: SizedBox(
                        width: axis == Axis.horizontal ? 1400 : 280,
                        height: axis == Axis.vertical ? 1400 : 180,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final viewport = find.byKey(viewportKey);
        final content = find.byKey(contentKey);
        expect(viewport.hitTestable(), findsOneWidget);
        expect(controller.hasClients, isTrue);
        expect(controller.positions, hasLength(1));
        expect(controller.position.axis, axis);
        expect(controller.position.maxScrollExtent, greaterThan(80));
        expect(controller.offset, 0);
        expect(_scrollbarsWithin(viewport), findsNothing);
        final initialContentPosition = tester.getTopLeft(content);
        final wheelDelta =
            axis == Axis.vertical ? const Offset(0, 80) : const Offset(80, 0);

        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(viewport),
            scrollDelta: wheelDelta,
          ),
        );
        await tester.pump();

        expect(wheelEvents, 1);
        expect(controller.offset, closeTo(80, 0.01));
        expect(
          tester.getTopLeft(content),
          initialContentPosition - wheelDelta,
        );
        final offsetAfterWheel = controller.offset;

        await tester.drag(viewport, -wheelDelta, kind: PointerDeviceKind.touch);
        await tester.pumpAndSettle();

        expect(downEvents, 1);
        expect(controller.offset, greaterThan(offsetAfterWheel));
        final displacement =
            initialContentPosition - tester.getTopLeft(content);
        expect(
          displacement.dx,
          closeTo(axis == Axis.horizontal ? controller.offset : 0, 0.01),
        );
        expect(
          displacement.dy,
          closeTo(axis == Axis.vertical ? controller.offset : 0, 0.01),
        );
        expect(_scrollbarsWithin(viewport), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: windows,
    );
  }

  testWidgets(
    'read-only text remains selectable and guarded and normal fields stay editable',
    (tester) async {
      const source = 'alpha beta\ngamma delta';
      const guardKey = ValueKey('text-scrollbar-guard');
      const selectableKey = ValueKey('read-only-text');
      const insideKey = ValueKey('guarded-field');
      const outsideKey = ValueKey('normal-field');
      final insideController = TextEditingController(text: 'before\ninside');
      final outsideController = TextEditingController(text: 'before\noutside');
      final insideChanges = <String>[];
      final outsideChanges = <String>[];
      addTearDown(insideController.dispose);
      addTearDown(outsideController.dispose);

      await tester.pumpWidget(
        _testApp(
          SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (context) => ScrollConfiguration(
                    key: guardKey,
                    behavior:
                        NoScrollbarBehavior(ScrollConfiguration.of(context)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SelectableText(
                          source,
                          key: selectableKey,
                          maxLines: 2,
                          style: TextStyle(fontSize: 16),
                        ),
                        TextField(
                          key: insideKey,
                          controller: insideController,
                          maxLines: 2,
                          onChanged: insideChanges.add,
                        ),
                      ],
                    ),
                  ),
                ),
                TextField(
                  key: outsideKey,
                  controller: outsideController,
                  maxLines: 2,
                  onChanged: outsideChanges.add,
                ),
              ],
            ),
          ),
        ),
      );

      final readOnlyFinder = find.descendant(
        of: find.byKey(selectableKey),
        matching: find.byType(EditableText),
      );
      final readOnly = tester.widget<EditableText>(readOnlyFinder);
      expect(readOnly.readOnly, isTrue);
      expect(readOnly.enableInteractiveSelection, isTrue);
      expect(readOnly.selectionEnabled, isTrue);

      // Select through the real desktop gesture detector, not by assigning a
      // selection to SelectableText's internally owned controller.
      final render =
          tester.state<EditableTextState>(readOnlyFinder).renderEditable;
      final start = render.localToGlobal(
        render.getLocalRectForCaret(const TextPosition(offset: 0)).center,
      );
      final end = render.localToGlobal(
        render.getLocalRectForCaret(const TextPosition(offset: 5)).center,
      );
      await tester.dragFrom(start, end - start, kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(readOnly.focusNode.hasFocus, isTrue);
      expect(readOnly.controller.selection.textInside(source), 'alpha');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace,
          platform: 'windows');
      await tester.pump();
      expect(readOnly.controller.text, source);

      for (final key in [insideKey, outsideKey]) {
        final editable = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(EditableText),
          ),
        );
        expect(editable.readOnly, isFalse);
        expect(editable.enableInteractiveSelection, isTrue);
        expect(editable.selectionEnabled, isTrue);
      }

      await tester.enterText(find.byKey(insideKey), 'edited\ninside');
      await tester.pump();
      expect(insideController.text, 'edited\ninside');
      expect(insideChanges, ['edited\ninside']);
      expect(outsideController.text, 'before\noutside');

      await tester.enterText(find.byKey(outsideKey), 'edited\noutside');
      await tester.pump();
      expect(outsideController.text, 'edited\noutside');
      expect(outsideChanges, ['edited\noutside']);
      expect(insideController.text, 'edited\ninside');
      expect(readOnly.controller.text, source);
      expect(_scrollbarsWithin(find.byKey(guardKey)), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(outsideKey),
          matching: find.byType(Scrollbar),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: windows,
  );

  test('database scrollbar visibility defaults on and accepts an opt-out', () {
    // Constructor contract only; this does not simulate tab/provider propagation.
    const normal = DatabasePluginWidgetBuilderSize(horizontalPadding: 24);
    const custom = DatabasePluginWidgetBuilderSize(
      horizontalPadding: 24,
      showScrollbars: false,
    );

    expect(normal.showScrollbars, isTrue);
    expect(custom.showScrollbars, isFalse);
  });
}

Widget _testApp(Widget child) => MaterialApp(
      home: Material(
        child: ScrollNotificationObserver(child: Center(child: child)),
      ),
    );

Finder _scrollbarsWithin(Finder ancestor) => find.descendant(
      of: ancestor,
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollbar || widget is RawScrollbar,
      ),
    );

class _ParentScrollBehavior extends ScrollBehavior {
  const _ParentScrollBehavior(this.trackerBuilder);

  final GestureVelocityTrackerBuilder trackerBuilder;

  static const physics = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );
  static const overscrollColor = Color(0xFF123456);
  static final _axisModifiers = {LogicalKeyboardKey.altLeft};

  @override
  TargetPlatform getPlatform(BuildContext context) => TargetPlatform.macOS;

  @override
  Set<PointerDeviceKind> get dragDevices => const {PointerDeviceKind.stylus};

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers => _axisModifiers;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      MultitouchDragStrategy.sumAllPointers;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => physics;

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      trackerBuilder;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      GlowingOverscrollIndicator(
        axisDirection: details.direction,
        color: overscrollColor,
        child: child,
      );
}
