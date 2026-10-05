import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_geometry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewId = 'canvas-persistence';

void main() {
  group('a canvas reading itself back', () {
    final mine = CanvasDocument(
      nodes: [_card('a', text: 'first'), _card('b', x: 300, text: 'second')],
      settings: const CanvasSettings(
        viewport: CanvasViewport(offset: Offset(40, 20), zoom: 1.25),
      ),
    );
    late CanvasController controller;
    late int notified;

    setUp(() {
      // Nothing here edits, so nothing is ever written to a backend.
      controller = CanvasController(viewId: _viewId, document: mine);
      notified = 0;
      controller.addListener(() => notified++);
    });
    tearDown(() => controller.dispose());

    test('an equal copy is not adopted', () {
      controller.adoptFromView(_view(mine));
      expect(controller.document, same(mine));
      expect(notified, 0);
    });

    test('a copy that only looks somewhere else is not adopted', () {
      final elsewhere = mine.copyWith(
        settings: mine.settings.copyWith(
          viewport: const CanvasViewport(offset: Offset(-500, 90), zoom: 0.5),
        ),
      );
      controller.adoptFromView(_view(elsewhere));
      expect(controller.document, same(mine));
      expect(notified, 0);
    });

    test("a changed canvas is adopted, keeping this window's camera", () {
      final changed = mine.copyWith(
        nodes: [...mine.nodes, _card('c', y: 300, text: 'third')],
        settings: mine.settings.copyWith(
          viewport: const CanvasViewport(zoom: 2),
        ),
      );
      controller.adoptFromView(_view(changed));
      expect(notified, 1);
      expect(controller.document.nodeById('c')?.text, 'third');
      expect(controller.document.settings.viewport, mine.settings.viewport);
    });
  });

  testWidgets('where the camera rests is kept aside, then folded in silently',
      (tester) async {
    final start = CanvasDocument(nodes: [_card('a')]);
    // No view id: the fold schedules a write that has nowhere to go.
    final controller = CanvasController(viewId: '', document: start);
    var notified = 0;
    controller.addListener(() => notified++);
    const rested = CanvasViewport(offset: Offset(120, -40), zoom: 1.5);

    controller.rememberViewport(
      const CanvasCamera(offset: Offset(120, -40), zoom: 1.5),
    );
    expect(controller.viewport, rested);
    // Nothing on the canvas changed: the same document, and nobody told.
    expect(controller.document, same(start));
    expect(notified, 0);

    await tester.pump(CanvasController.viewportDebounce);
    expect(controller.document.settings.viewport, rested);
    expect(controller.document.nodes, same(start.nodes));
    expect(notified, 0);

    await tester.pump(controller.persistDebounce);
    controller.dispose();
  });
}

CanvasNode _card(String id, {double x = 0, double y = 0, String text = ''}) =>
    CanvasNode(
      id: id,
      kind: CanvasNodeKind.text,
      position: Offset(x, y),
      size: const Size(200, 100),
      text: text,
    );

ViewPB _view(CanvasDocument document) => ViewPB(
      id: _viewId,
      extra: CanvasMetadata(document: document).mergeIntoExtra(''),
    );
