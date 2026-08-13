import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_canvas.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/collection_widgets.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DashboardController _controllerWith(
  String type, {
  DashboardMode? mode,
}) =>
    DashboardController(
      viewId: '',
      document: DashboardDocument(
        sections: [
          DashboardSection(
            id: 's',
            widgets: [DashboardWidgetRegistry.definitionFor(type)!.create()],
          ),
        ],
      ),
      mode: mode,
      persistDebounce: const Duration(days: 1),
    );

Widget _cardHost({
  required DashboardController controller,
  VoidCallback? onDragStart,
  void Function(Offset delta, Offset globalPosition)? onDragUpdate,
  VoidCallback? onDragEnd,
  void Function(DashboardResizeEdge edge)? onResizeStart,
  void Function(DashboardResizeEdge edge, Offset delta)? onResizeUpdate,
  VoidCallback? onResizeEnd,
}) =>
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 220,
              child: DashboardCard(
                controller: controller,
                spec: controller.document.allWidgets.first,
                palette: DashboardPalette.of(context),
                selected: false,
                dragging: false,
                onDragStart: onDragStart,
                onDragUpdate: onDragUpdate,
                onDragEnd: onDragEnd,
                onResizeStart: onResizeStart,
                onResizeUpdate: onResizeUpdate,
                onResizeEnd: onResizeEnd,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  group('the registry every dashboard widget is added through', () {
    test('the built-in widgets are registered exactly once', () {
      final all = DashboardWidgetRegistry.all();
      expect(all, isNotEmpty);
      final types = all.map((definition) => definition.type).toList();
      expect(types.toSet().length, types.length, reason: 'no duplicates');
      // A second read must not register a second copy.
      expect(DashboardWidgetRegistry.all().length, all.length);
    });

    test('every group offers something', () {
      for (final group in DashboardWidgetGroup.values) {
        expect(
          DashboardWidgetRegistry.inGroup(group),
          isNotEmpty,
          reason: '$group has no widgets',
        );
      }
    });

    test('a fresh widget carries its definition\'s defaults', () {
      final definition = DashboardWidgetRegistry.definitionFor('metric')!;
      final spec = definition.create();
      expect(spec.type, 'metric');
      expect(spec.id, isNotEmpty);
      expect(spec.placement.columnSpan, definition.defaultColumnSpan);
      expect(spec.placement.rowSpan, definition.defaultRowSpan);
    });

    test('two widgets never share an id', () {
      final definition = DashboardWidgetRegistry.definitionFor('text')!;
      expect(definition.create().id, isNot(definition.create().id));
    });

    test('searching finds a widget by name and by keyword', () {
      expect(
        DashboardWidgetRegistry.search('chart').first.type,
        'chart',
      );
      expect(
        DashboardWidgetRegistry.search('kanban')
            .map((definition) => definition.type),
        contains('database'),
      );
      expect(DashboardWidgetRegistry.search('zzzz'), isEmpty);
    });

    test('an unknown type simply has no definition', () {
      expect(DashboardWidgetRegistry.definitionFor('not_a_widget'), isNull);
    });
  });

  group('what a collection widget accepts', () {
    test('a folder widget takes a plain workspace folder', () {
      final folder = ViewPB(
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );

      expect(
        acceptsDashboardCollection(folder, CollectionKind.folder),
        isTrue,
        reason: 'most people never make a folder collection, and a picker '
            'offering an empty list offers nothing',
      );
      expect(
        acceptsDashboardCollection(folder, CollectionKind.book),
        isFalse,
        reason: 'a book shelf cannot draw a folder',
      );
    });

    test('every other kind still has to match exactly', () {
      final album = ViewPB(
        extra: CollectionMetadata.newExtra(CollectionKind.album),
      );

      expect(acceptsDashboardCollection(album, CollectionKind.album), isTrue);
      expect(acceptsDashboardCollection(album, CollectionKind.folder), isFalse);
    });
  });

  group('what the canvas draws', () {
    testWidgets('a widget with no source says what it needs', (tester) async {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(
              id: 's',
              widgets: [
                DashboardWidgetRegistry.definitionFor('clock')!.create(),
              ],
            ),
          ],
        ),
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) {
              final palette = DashboardPalette.of(context);
              final definition =
                  DashboardWidgetRegistry.definitionFor('clock')!;
              return Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 200,
                  child: definition.builder(
                    DashboardWidgetContext(
                      context: context,
                      controller: controller,
                      spec: controller.document.allWidgets.first,
                      palette: palette,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('clicking a card picks it up without opening its settings', (
      tester,
    ) async {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(
              id: 's',
              widgets: [
                DashboardWidgetRegistry.definitionFor('clock')!.create(),
              ],
            ),
          ],
        ),
        mode: DashboardMode.edit,
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);
      final spec = controller.document.allWidgets.first;

      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: 260,
                  height: 180,
                  child: DashboardCard(
                    controller: controller,
                    spec: spec,
                    palette: DashboardPalette.of(context),
                    selected: false,
                    dragging: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(controller.selectedWidgetId, isNull);
      await tester.tap(find.byType(DashboardCard));
      await tester.pump();
      expect(controller.selectedWidgetId, spec.id);
      // The panel takes width off the canvas, so a click must not open it.
      expect(controller.configuringWidgetId, isNull);
    });

    testWidgets('a card is a shadowed surface, never an outlined box', (
      tester,
    ) async {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(
              id: 's',
              widgets: [
                DashboardWidgetRegistry.definitionFor('clock')!.create(),
              ],
            ),
          ],
        ),
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: 260,
                  height: 180,
                  child: DashboardCard(
                    controller: controller,
                    spec: controller.document.allWidgets.first,
                    palette: DashboardPalette.of(context),
                    selected: false,
                    dragging: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surface = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(DashboardCard),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.border, isNull);
      expect(decoration.boxShadow, isNotEmpty);
    });

    testWidgets('the whole card can be dragged, not just its handle', (
      tester,
    ) async {
      final controller = _controllerWith('clock', mode: DashboardMode.edit);
      addTearDown(controller.dispose);

      var started = 0;
      var moved = Offset.zero;
      var ended = 0;

      await tester.pumpWidget(
        _cardHost(
          controller: controller,
          onDragStart: () => started++,
          onDragUpdate: (delta, _) => moved += delta,
          onDragEnd: () => ended++,
        ),
      );
      await tester.pump();

      // The middle of the card, well away from the handle and the grips.
      await tester.drag(find.byType(DashboardCard), const Offset(90, 60));
      await tester.pump();

      expect(started, 1);
      expect(ended, 1);
      expect(moved.dx, greaterThan(0));
      expect(moved.dy, greaterThan(0));
    });

    testWidgets('a card can be resized by its corner', (tester) async {
      final controller = _controllerWith('text');
      addTearDown(controller.dispose);

      DashboardResizeEdge? edge;
      var moved = Offset.zero;
      var ended = 0;

      await tester.pumpWidget(
        _cardHost(
          controller: controller,
          onResizeStart: (value) => edge = value,
          onResizeUpdate: (_, delta) => moved += delta,
          onResizeEnd: () => ended++,
        ),
      );
      await tester.pump();

      final card = tester.getRect(find.byType(DashboardCard));
      await tester.dragFrom(
        card.bottomRight - const Offset(6, 6),
        const Offset(60, 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      expect(edge, DashboardResizeEdge.corner);
      expect(ended, 1);
      expect(moved.dx, greaterThan(0));
      expect(moved.dy, greaterThan(0));
    });

    testWidgets('a card dropped on another section belongs to it', (
      tester,
    ) async {
      // Two bands of a real board need more than the default test window.
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(
              id: 'first',
              widgets: [
                DashboardWidgetRegistry.definitionFor('text')!.create(),
              ],
            ),
            DashboardSection(
              id: 'second',
              widgets: [
                DashboardWidgetRegistry.definitionFor('metric')!.create(),
              ],
            ),
          ],
        ),
        mode: DashboardMode.edit,
        persistDebounce: const Duration(days: 1),
      );
      final spec = controller.document.sections.first.widgets.first;

      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) => Scaffold(
              body: DashboardBoard(
                registry: DashboardSectionRegistry(),
                child: SizedBox(
                  width: 1200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final section in controller.document.sections)
                        DashboardCanvas(
                          key: ValueKey(section.id),
                          controller: controller,
                          section: section,
                          palette: DashboardPalette.of(context),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final card = find.byType(DashboardCard).first;
      final target = tester.getCenter(find.byType(DashboardCard).last);
      final gesture = await tester.startGesture(
        tester.getCenter(card),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.document.sectionOf(spec.id)?.id, 'second');

      controller.dispose();
    });

    testWidgets('a metric that holds its own number is typed into', (
      tester,
    ) async {
      final controller = _controllerWith('metric', mode: DashboardMode.edit);

      await tester.pumpWidget(_cardHost(controller: controller));
      await tester.pump();

      final field = find.descendant(
        of: find.byType(DashboardCard),
        matching: find.byType(TextField),
      );
      expect(
        field,
        findsOneWidget,
        reason: 'a figure nobody can type into has to be hunted for',
      );

      await tester.enterText(field, '42');
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        controller.document.allWidgets.first.number('value', fallback: 0),
        42,
      );

      controller.dispose();
    });

    testWidgets('a progress bar that owns its number is typed into', (
      tester,
    ) async {
      final controller = _controllerWith('progress', mode: DashboardMode.edit);

      await tester.pumpWidget(_cardHost(controller: controller));
      await tester.pump();

      // The current value and the target, both typed where they are read.
      final fields = find.descendant(
        of: find.byType(DashboardCard),
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(2));

      await tester.enterText(fields.first, '30');
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        controller.document.allWidgets.first.number('value', fallback: 0),
        30,
      );

      controller.dispose();
    });

    testWidgets('a progress bar is dragged to where it should be', (
      tester,
    ) async {
      final controller = _controllerWith('progress', mode: DashboardMode.edit);

      await tester.pumpWidget(_cardHost(controller: controller));
      await tester.pump();

      final bar = find.byType(LinearProgressIndicator);
      expect(bar, findsOneWidget);
      final box = tester.getRect(bar);

      // Pumping between the moves matters: the tree is rebuilt mid-gesture,
      // and a recogniser that is discarded there loses the drag.
      final gesture = await tester.startGesture(
        Offset(box.left + 2, box.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(box.center.dx, box.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        controller.document.allWidgets.first.number('value', fallback: 0),
        closeTo(50, 8),
        reason: 'the bar was dragged to its middle, and the target is 100',
      );

      controller.dispose();
    });

    testWidgets('a double click opens a widget for setting up', (
      tester,
    ) async {
      final controller = _controllerWith('database');
      addTearDown(controller.dispose);
      expect(controller.mode, DashboardMode.edit);

      await tester.pumpWidget(_cardHost(controller: controller));
      await tester.pump();

      final spec = controller.document.allWidgets.first;
      await tester.tap(find.byType(DashboardCard));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.byType(DashboardCard));
      await tester.pump();

      expect(controller.mode, DashboardMode.edit);
      expect(controller.selectedWidgetId, spec.id);
      expect(controller.configuringWidgetId, spec.id);
    });

    testWidgets('a card moves down even though the page under it scrolls', (
      tester,
    ) async {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(
              id: 's',
              // Widgets with no clock of their own, so pumpAndSettle settles.
              widgets: [
                DashboardWidgetRegistry.definitionFor('text')!.create(),
                DashboardWidgetRegistry.definitionFor('metric')!.create(),
              ],
            ),
          ],
        ),
        mode: DashboardMode.edit,
        persistDebounce: const Duration(days: 1),
      );
      final spec = controller.document.allWidgets.first;
      expect(spec.placement.row, 0);

      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) => Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 1200,
                  child: Column(
                    children: [
                      DashboardCanvas(
                        controller: controller,
                        section: controller.document.sections.first,
                        palette: DashboardPalette.of(context),
                      ),
                      // Enough to make the page really scrollable, so its
                      // drag recogniser is in the arena and competing.
                      const SizedBox(height: 1400),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Straight down, which is the direction the scroll view wants. A mouse,
      // because that is where the two thresholds differ.
      final card = find.byType(DashboardCard).first;
      await tester.drag(
        card,
        const Offset(0, 300),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(
        controller.document.widgetById(spec.id)!.placement.row,
        greaterThan(0),
        reason: 'the scroll view must not take the drag',
      );

      // Disposed here rather than in a tear down: the edit schedules a write,
      // and a timer must not outlive the widget tree.
      controller.dispose();
    });

    testWidgets('the board shows where a dragged card will land', (
      tester,
    ) async {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(
              id: 's',
              widgets: [
                DashboardWidgetRegistry.definitionFor('text')!.create(),
                DashboardWidgetRegistry.definitionFor('metric')!.create(),
              ],
            ),
          ],
        ),
        mode: DashboardMode.edit,
        persistDebounce: const Duration(days: 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) => Scaffold(
              body: SizedBox(
                width: 1200,
                child: DashboardCanvas(
                  controller: controller,
                  section: controller.document.sections.first,
                  palette: DashboardPalette.of(context),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      const landing = ValueKey('dashboard-landing');
      expect(find.byKey(landing), findsNothing);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DashboardCard).first),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 110));
      await tester.pump();

      expect(
        find.byKey(landing),
        findsOneWidget,
        reason: 'a card in the air must say where it is going',
      );

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        controller.document.allWidgets.first.placement.row,
        greaterThan(0),
        reason: 'letting go must land the card',
      );
      expect(find.byKey(landing), findsNothing);

      controller.dispose();
    });
  });

  group('the controller a dashboard is edited through', () {
    test('a dashboard with nothing on it opens ready to be built in', () {
      final empty = DashboardController(
        viewId: '',
        document: DashboardDocument.blank(),
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(empty.dispose);
      expect(empty.mode, DashboardMode.edit);

      final built = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(
              id: 's',
              widgets: [
                DashboardWidgetRegistry.definitionFor('clock')!.create(),
              ],
            ),
          ],
        ),
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(built.dispose);
      expect(built.mode, DashboardMode.edit);
    });

    test('an edit can be undone and redone', () {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument.blank(),
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      final widget = DashboardWidgetRegistry.definitionFor('text')!.create();
      controller.edit((document) => document.addWidget(widget));
      expect(controller.document.widgetCount, 1);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.document.widgetCount, 0);
      controller.redo();
      expect(controller.document.widgetCount, 1);
    });

    test('a change still in flight does not fill the history', () {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument.blank(),
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      final widget = DashboardWidgetRegistry.definitionFor('text')!.create();
      controller.edit((document) => document.addWidget(widget));
      for (var row = 1; row < 10; row++) {
        controller.edit(
          (document) => document.withWidget(
            controller.document.widgetById(widget.id)!.copyWith(
                  placement: widget.placement.copyWith(row: row),
                ),
          ),
          transient: true,
        );
      }
      controller.undo();
      expect(
        controller.document.widgetCount,
        0,
        reason: 'one drag must undo in one step',
      );
    });

    test('a variable gets its starting value the moment it is added', () {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument.blank(),
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      controller.edit(
        (document) => document.withVariable(
          const DashboardVariable(
            key: 'live',
            label: 'Live',
            kind: DashboardVariableKind.toggle,
          ),
        ),
      );
      expect(controller.state['live'], false);

      controller.toggleValue('live');
      expect(controller.state.flag('live'), isTrue);

      controller.resetState();
      expect(controller.state.flag('live'), isFalse);
    });

    test('presenting a dashboard closes the configuration panel', () {
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument.blank(),
        mode: DashboardMode.edit,
        persistDebounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      controller.select('anything');
      expect(controller.selectedWidgetId, 'anything');
      controller.setMode(DashboardMode.presentation);
      expect(controller.selectedWidgetId, isNull);
    });
  });
}
