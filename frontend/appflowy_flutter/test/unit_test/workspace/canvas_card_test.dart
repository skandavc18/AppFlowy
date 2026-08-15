import 'package:appflowy/plugins/canvas/presentation/canvas_card.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_view_resolver.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a click on a card actually reaches.
///
/// The card's gesture layer covers its whole body, so every affordance a card
/// offers has to arrive through here. These are the tests that catch "clicking
/// it does nothing".
void main() {
  late CanvasViewResolver resolver;

  setUp(() => resolver = CanvasViewResolver());
  tearDown(() => resolver.dispose());

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 400, height: 300, child: child),
          ),
        ),
      );

  ({
    Widget widget,
    List<String> events,
  }) build(
    CanvasNode node, {
    bool editable = true,
    bool selected = false,
  }) {
    final events = <String>[];
    return (
      events: events,
      widget: Builder(
        builder: (context) => CanvasCard(
          node: node,
          palette: canvasPaletteOf(context),
          resolver: resolver,
          zoom: 1,
          selected: selected,
          editing: false,
          editable: editable,
          onTap: (_) => events.add('tap'),
          onDoubleTap: () => events.add('doubleTap'),
          onContextMenu: (_) => events.add('menu'),
          onDragStart: () => events.add('dragStart'),
          onDragUpdate: (_, __) => events.add('dragUpdate'),
          onDragEnd: () => events.add('dragEnd'),
          onResizeStart: (_) => events.add('resizeStart'),
          onResizeUpdate: (_, __) => events.add('resizeUpdate'),
          onResizeEnd: () => events.add('resizeEnd'),
          onConnectStart: (_) => events.add('connectStart'),
          onConnectUpdate: (_) => events.add('connectUpdate'),
          onConnectEnd: (_) => events.add('connectEnd'),
          onTextChanged: (_) => events.add('text'),
          onEditingFinished: () => events.add('editingFinished'),
          onOpen: () => events.add('open'),
          onSetUp: () => events.add('setUp'),
          onEdit: () => events.add('edit'),
        ),
      ),
    );
  }

  CanvasNode cardOf(CanvasNodeKind kind) => CanvasNode.create(
        kind: kind,
        position: Offset.zero,
        size: const Size(400, 300),
      );

  group('a click that never moves', () {
    testWidgets('reaches the card', (tester) async {
      final built = build(cardOf(CanvasNodeKind.text));
      await tester.pumpWidget(host(built.widget));

      // `tester.tap` puts the pointer down and up at the SAME point. A drag
      // recogniser that only reports through `onEnd` never hears about it,
      // which is exactly how a card comes to do nothing when it is clicked.
      await tester.tap(find.byType(CanvasCard));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

      expect(built.events, contains('tap'));
    });

    testWidgets('asks an empty diagram card what it holds', (tester) async {
      final built = build(cardOf(CanvasNodeKind.diagram));
      await tester.pumpWidget(host(built.widget));

      await tester.tap(find.byType(CanvasCard));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

      expect(built.events, contains('setUp'));
    });

    testWidgets('asks an empty picture card too', (tester) async {
      final built = build(cardOf(CanvasNodeKind.image));
      await tester.pumpWidget(host(built.widget));

      await tester.tap(find.byType(CanvasCard));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

      expect(built.events, contains('setUp'));
    });

    testWidgets('does not ask a card that already holds something',
        (tester) async {
      final built = build(
        cardOf(CanvasNodeKind.diagram)
            .withData(canvasDiagramKindKey, CanvasDiagramKind.mermaid.id),
      );
      await tester.pumpWidget(host(built.widget));

      await tester.tap(find.byType(CanvasCard));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

      expect(built.events, contains('tap'));
      expect(built.events, isNot(contains('setUp')));
    });
  });

  group('a click that wobbles', () {
    testWidgets('is still a click, not a drag', (tester) async {
      final built = build(cardOf(CanvasNodeKind.diagram));
      await tester.pumpWidget(host(built.widget));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CanvasCard)),
        kind: PointerDeviceKind.mouse,
      );
      // Under the drag threshold: a hand that is not perfectly still must not
      // turn a click into a drag.
      await gesture.moveBy(const Offset(1.5, 1));
      await tester.pump();
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

      expect(built.events, contains('setUp'));
      expect(built.events, isNot(contains('dragStart')));
    });
  });

  group('a real drag', () {
    testWidgets('moves the card and never reads as a click', (tester) async {
      final built = build(cardOf(CanvasNodeKind.text));
      await tester.pumpWidget(host(built.widget));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CanvasCard)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 24));
      await tester.pump();
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

      expect(built.events, contains('dragStart'));
      expect(built.events, contains('dragEnd'));
      expect(built.events, isNot(contains('tap')));
    });
  });

  group('a double click', () {
    testWidgets('opens the card rather than reporting two clicks',
        (tester) async {
      final built = build(cardOf(CanvasNodeKind.text));
      await tester.pumpWidget(host(built.widget));

      final where = tester.getCenter(find.byType(CanvasCard));
      await tester.tapAt(where);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(where);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

      expect(built.events, contains('doubleTap'));
    });
  });

  group('the button on the card', () {
    // The gesture layer covers the whole card, so an affordance only works if
    // it is drawn above it. These are the buttons a reader can actually press.
    testWidgets('offers to fill an empty card without being hovered',
        (tester) async {
      final built = build(cardOf(CanvasNodeKind.diagram));
      await tester.pumpWidget(host(built.widget));

      await tester.tap(find.byTooltip('canvas.diagram.choose'));
      await tester.pump();

      expect(built.events, contains('setUp'));
    });

    testWidgets('offers to rewrite a diagram that has one', (tester) async {
      final built = build(
        cardOf(CanvasNodeKind.diagram)
            .withData(canvasDiagramKindKey, CanvasDiagramKind.mermaid.id)
            .copyWith(text: 'flowchart LR\n  A --> B'),
        selected: true,
      );
      await tester.pumpWidget(host(built.widget));

      await tester.tap(find.byTooltip('canvas.diagram.editSource'));
      await tester.pump();

      expect(built.events, contains('edit'));
      expect(built.events, isNot(contains('setUp')));
    });

    testWidgets('lets a saved link be changed as well as opened',
        (tester) async {
      final built = build(
        cardOf(CanvasNodeKind.bookmark).copyWith(url: 'https://example.com'),
        selected: true,
      );
      await tester.pumpWidget(host(built.widget));

      await tester.tap(find.byTooltip('canvas.card.addUrl'));
      await tester.pump();
      await tester.tap(find.byTooltip('canvas.menu.open'));
      await tester.pump();

      expect(built.events, containsAll(<String>['edit', 'open']));
    });

    testWidgets('says nothing on a canvas that cannot be changed',
        (tester) async {
      final built = build(
        cardOf(CanvasNodeKind.diagram),
        editable: false,
        selected: true,
      );
      await tester.pumpWidget(host(built.widget));

      expect(find.byType(CanvasButton), findsNothing);
    });
  });

  group('a canvas that cannot be changed', () {
    // Read only must not mean dead. Selecting a card, opening it and reading
    // its menu are not edits, and a card that answers nothing at all reads as
    // the whole canvas being broken.
    testWidgets('still answers a click', (tester) async {
      final built = build(cardOf(CanvasNodeKind.text), editable: false);
      await tester.pumpWidget(host(built.widget));

      await tester.tapAt(tester.getCenter(find.byType(CanvasCard)));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

      expect(built.events, contains('tap'));
    });

    testWidgets('still answers a right click', (tester) async {
      final built = build(cardOf(CanvasNodeKind.text), editable: false);
      await tester.pumpWidget(host(built.widget));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CanvasCard)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();

      expect(built.events, contains('menu'));
    });

    testWidgets('never picks a card up', (tester) async {
      final built = build(cardOf(CanvasNodeKind.text), editable: false);
      await tester.pumpWidget(host(built.widget));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CanvasCard)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(built.events, isNot(contains('dragStart')));
      expect(built.events, isNot(contains('tap')));
    });
  });
}
