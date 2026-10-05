import 'dart:math' as math;

import 'package:appflowy/plugins/canvas/presentation/canvas_board.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_card.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_node_body.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/drawing/drawing_block_component.dart';
import 'package:appflowy/shared/drawing/excalidraw_scene.dart';
import 'package:appflowy/shared/mermaid/mermaid_view.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// How much work the canvas does while somebody pans, zooms and drags.
///
/// A canvas is panned on every frame of a gesture, so anything rebuilt or
/// repainted per frame is multiplied by sixty a second. These tests count the
/// rebuilds of the expensive pieces — the cards, their bodies, the drawing and
/// diagram previews — rather than wall-clock time, which depends on the machine.
void main() {
  late CanvasController controller;
  var closed = false;

  setUp(() {
    closed = false;
    controller = CanvasController(viewId: '', document: _busyCanvas());
  });

  tearDown(() {
    debugOnRebuildDirtyWidget = null;
    if (!closed) {
      controller.dispose();
    }
  });

  Widget host() => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 900,
            child: CanvasBoard(controller: controller),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    closed = true;
    await tester.pump();
  }

  /// Rebuilds of the interesting widgets while [frames] runs.
  Future<_Work> measure(
    WidgetTester tester,
    Future<void> Function() frames,
  ) async {
    final work = _Work();
    debugOnRebuildDirtyWidget = (element, _) {
      work.total++;
      final widget = element.widget;
      if (widget is CanvasCard) work.cards++;
      if (widget is CanvasNodeBody) work.bodies++;
      if (widget is DrawScenePreview) work.drawings++;
      if (widget is MermaidView) work.diagrams++;
    };
    final clock = Stopwatch()..start();
    await frames();
    clock.stop();
    debugOnRebuildDirtyWidget = null;
    work.elapsed = clock.elapsed;
    return work;
  }

  testWidgets('panning, zooming and dragging a busy canvas', (tester) async {
    await open(tester);
    final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
    board.revealSceneRect(const Rect.fromLTWH(900, 500, 10, 10), atZoom: 1);
    await tester.pump();

    final visibleCards = find.byType(CanvasCard).evaluate().length;
    expect(visibleCards, greaterThan(8));

    const frameCount = 60;
    final pan = await measure(tester, () async {
      for (var frame = 0; frame < frameCount; frame++) {
        board.revealSceneRect(
          Rect.fromLTWH(900 + frame * 6.0, 500 + frame * 3.0, 10, 10),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    });

    final zoom = await measure(tester, () async {
      for (var frame = 0; frame < frameCount; frame++) {
        board.revealSceneRect(
          const Rect.fromLTWH(1200, 650, 10, 10),
          atZoom: 1 - frame * 0.004,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    });

    final dragged = controller.document.nodes[11].id;
    final start = controller.document.nodes[11].position;
    final drag = await measure(tester, () async {
      for (var frame = 0; frame < frameCount; frame++) {
        controller.updateNode(
          dragged,
          (node) => node.copyWith(position: start + Offset(frame * 4.0, 0)),
          transient: true,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    });

    debugPrint('[canvas-responsiveness] visible cards: $visibleCards');
    debugPrint('[canvas-responsiveness] pan:  $pan');
    debugPrint('[canvas-responsiveness] zoom: $zoom');
    debugPrint('[canvas-responsiveness] drag: $drag');

    // Before the board kept its cards, a 60-frame pan rebuilt every visible
    // card, body and preview on every frame (46,052 rebuilds; 1,152 cards).
    // Panning moves the camera, not the cards.
    expect(pan.cards, lessThan(visibleCards));
    expect(pan.bodies, lessThan(visibleCards));
    expect(pan.drawings + pan.diagrams, lessThan(visibleCards));
    expect(pan.total, lessThan(frameCount * 120));
    // Zooming re-lays the cards out, but their contents stay painted.
    expect(zoom.bodies, lessThan(visibleCards * 2));
    expect(zoom.drawings + zoom.diagrams, lessThan(visibleCards));
    // Dragging one card rebuilds that card, not the board (was 58,056).
    expect(drag.bodies, 0);
    expect(drag.cards, lessThanOrEqualTo(frameCount * 2));
    expect(drag.total, lessThan(frameCount * 150));

    await close(tester);
  });
}

class _Work {
  int total = 0;
  int cards = 0;
  int bodies = 0;
  int drawings = 0;
  int diagrams = 0;
  Duration elapsed = Duration.zero;

  @override
  String toString() => 'total=$total cards=$cards bodies=$bodies '
      'drawings=$drawings diagrams=$diagrams '
      'elapsed=${elapsed.inMilliseconds}ms';
}

/// Sixty cards of every expensive kind, connected, with a layer of ink.
CanvasDocument _busyCanvas() {
  final random = math.Random(7);
  final scene = _drawing(random);
  final nodes = <CanvasNode>[];
  for (var index = 0; index < 60; index++) {
    final position = Offset((index % 10) * 480.0, (index ~/ 10) * 380.0);
    nodes.add(
      switch (index % 4) {
        0 => CanvasNode.create(
            id: 'n$index',
            kind: CanvasNodeKind.text,
            position: position,
            title: 'Card $index',
            text: 'Notes for card $index. ' * 6,
          ),
        1 => CanvasNode.create(
            id: 'n$index',
            kind: CanvasNodeKind.code,
            position: position,
            text: 'void main() {\n  for (var i = 0; i < $index; i++) {\n'
                '    print(i);\n  }\n}\n',
            data: const {canvasCodeLanguageKey: 'dart'},
          ),
        2 => CanvasNode.create(
            id: 'n$index',
            kind: CanvasNodeKind.diagram,
            position: position,
            text: 'flowchart LR\n  A[Idea $index] --> B[Plan]\n'
                '  B --> C[Build]\n  C --> D[Ship]\n  D --> A',
            data: {canvasDiagramKindKey: CanvasDiagramKind.mermaid.id},
          ),
        _ => CanvasNode.create(
            id: 'n$index',
            kind: CanvasNodeKind.diagram,
            position: position,
            text: scene,
            data: {canvasDiagramKindKey: CanvasDiagramKind.drawing.id},
          ),
      },
    );
  }
  final edges = <CanvasEdge>[
    for (var index = 0; index + 1 < nodes.length; index++)
      CanvasEdge.create(
        id: 'e$index',
        from: nodes[index].id,
        to: nodes[index + 1].id,
        label: index % 3 == 0 ? 'step $index' : '',
        style: index % 4 == 0 ? CanvasEdgeStyle.dashed : CanvasEdgeStyle.solid,
      ),
  ];
  final strokes = <CanvasStroke>[
    for (var index = 0; index < 30; index++)
      CanvasStroke.create(
        id: 's$index',
        points: [
          for (var step = 0; step < 300; step++)
            Offset(
              index * 150.0 + step * 2.0,
              200 + math.sin(step / 9 + index) * 80 + index * 60,
            ),
        ],
      ),
  ];
  return CanvasDocument(nodes: nodes, edges: edges, strokes: strokes);
}

/// A hand drawing of a realistic size: boxes, arrows and freehand lines.
String _drawing(math.Random random) {
  final elements = <DrawElement>[];
  for (var index = 0; index < 40; index++) {
    final x = random.nextDouble() * 600;
    final y = random.nextDouble() * 400;
    switch (index % 4) {
      case 0:
        elements.add(
          DrawElement.create(
            type: DrawElementType.rectangle,
            x: x,
            y: y,
            width: 80,
            height: 50,
          ),
        );
      case 1:
        elements.add(
          DrawElement.create(
            type: DrawElementType.ellipse,
            x: x,
            y: y,
            width: 60,
            height: 60,
          ),
        );
      case 2:
        elements.add(
          DrawElement.create(
            type: DrawElementType.arrow,
            x: x,
            y: y,
            width: 120,
            height: 40,
            points: const [Offset.zero, Offset(120, 40)],
          ),
        );
      default:
        elements.add(
          DrawElement.create(
            type: DrawElementType.freedraw,
            x: x,
            y: y,
            width: 100,
            height: 60,
            points: [
              for (var step = 0; step < 50; step++)
                Offset(step * 2.0, math.sin(step / 4) * 30 + 30),
            ],
          ),
        );
    }
  }
  return DrawScene(elements: elements, appState: DrawAppState.initial())
      .encode();
}
