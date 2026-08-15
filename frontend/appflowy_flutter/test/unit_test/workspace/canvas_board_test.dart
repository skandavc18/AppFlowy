import 'package:appflowy/plugins/canvas/presentation/canvas_board.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_card.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether a card that has been put down can actually be told what it holds.
///
/// The board asks through a menu, and a menu opened from inside another menu
/// is exactly where these flows go quiet, so this drives the real widgets.
void main() {
  late CanvasController controller;
  var closed = false;

  setUp(() {
    closed = false;
    // An empty view id means nothing is ever written to the backend.
    controller = CanvasController(viewId: '', document: CanvasDocument.blank());
  });

  tearDown(() {
    if (!closed) {
      controller.dispose();
    }
  });

  Widget host() => MaterialApp(
        home: Scaffold(
          body: CanvasBoard(controller: controller),
        ),
      );

  /// The board reads its viewport from a `LayoutBuilder` and settles its
  /// camera one frame later.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
  }

  /// Take the tree down and stop the controller's persist timer, which would
  /// otherwise outlive the test and fail the pending-timer check.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    closed = true;
    await tester.pump();
  }

  Future<void> clickCentreOf(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(
      tester.getCenter(finder),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // easy_localization is not started in a plain widget test, so `.tr()` hands
  // back the key path. Asserting on those is also what keeps these tests from
  // breaking every time a word is reworded.
  const mermaidRow = 'canvas.diagram.mermaid';
  const drawingRow = 'canvas.diagram.drawing';
  const diagramCard = 'canvas.node.diagram';

  testWidgets('clicking an empty diagram card offers both sorts of diagram',
      (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
    board.addCard(CanvasNodeKind.diagram, configure: false);
    await settle(tester);

    await clickCentreOf(tester, find.byType(CanvasBoard));

    expect(find.text(mermaidRow), findsOneWidget);
    expect(find.text(drawingRow), findsOneWidget);
    await close(tester);
  });

  testWidgets('choosing a written diagram opens it for typing', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
    final id = board.addCard(CanvasNodeKind.diagram, configure: false);
    await settle(tester);

    await clickCentreOf(tester, find.byType(CanvasBoard));
    await tester.tap(find.text(mermaidRow));
    await tester.pump(const Duration(milliseconds: 300));

    final node = controller.document.nodeById(id);
    expect(node?.diagramKind, CanvasDiagramKind.mermaid);
    expect(node?.text.trim(), isNotEmpty);
    await close(tester);
  });

  testWidgets('adding a diagram from the toolbar asks which sort it is',
      (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    // The `+` on the toolbar, then the Diagram row: a menu opened from inside
    // a menu, which is where the second one used to be popped with the first.
    await tester.tap(find.byTooltip('canvas.toolbar.add'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(diagramCard), findsOneWidget);

    await tester.tap(find.text(diagramCard));
    // The menu hands its callback to a post-frame callback, so the card is
    // made at the end of one frame and the next menu is built in another.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.document.nodes.length, 1);
    expect(find.text(mermaidRow), findsOneWidget);
    expect(find.text(drawingRow), findsOneWidget);
    await close(tester);
  });

  testWidgets('a diagram that is already written can be rewritten',
      (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
    final id = board.addCard(CanvasNodeKind.diagram, configure: false);
    controller
      ..updateNode(
        id,
        (node) => node
            .withData(canvasDiagramKindKey, CanvasDiagramKind.mermaid.id)
            .copyWith(text: 'flowchart LR\n  A --> B'),
      )
      ..select([id]);
    await settle(tester);

    await tester.tap(find.byTooltip('canvas.diagram.editSource'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.editing, id);
    await close(tester);
  });

  testWidgets('a saved bookmark can have its address changed', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
    final id = board.addCard(CanvasNodeKind.bookmark, configure: false);
    controller
      ..updateNode(id, (node) => node.copyWith(url: 'https://example.com'))
      ..select([id]);
    await settle(tester);

    await tester.tap(find.byTooltip('canvas.card.addUrl'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The dialog starts from the address the card already points at, so an
    // edit is an edit rather than typing the whole thing again.
    expect(
      find.widgetWithText(AlertDialog, 'https://example.com'),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('a card far from the origin still answers a click',
      (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    // Hit testing gives up outside a box, so a card laid out past the layer's
    // own size used to be painted perfectly and be completely dead.
    final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
    final id = board.addCard(
      CanvasNodeKind.text,
      at: const Offset(4200, 3100),
    );
    board.revealObject(id);
    await settle(tester);

    controller.select(const []);
    expect(find.byType(CanvasCard), findsOneWidget);

    await clickCentreOf(tester, find.byType(CanvasCard));

    expect(controller.selection, contains(id));
    await close(tester);
  });

  testWidgets('a card at negative coordinates still answers a click',
      (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
    final id = board.addCard(
      CanvasNodeKind.text,
      at: const Offset(-3600, -2400),
    );
    board.revealObject(id);
    await settle(tester);

    controller.select(const []);
    await clickCentreOf(tester, find.byType(CanvasCard));

    expect(controller.selection, contains(id));
    await close(tester);
  });
}
