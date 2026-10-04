import 'package:appflowy/plugins/canvas/presentation/canvas_board.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_card.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_find.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_painters.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surface_find_test_support.dart';

const _document = CanvasDocument(
  settings: CanvasSettings(viewport: CanvasViewport(offset: Offset(80, 100))),
  nodes: [
    CanvasNode(
      id: 'near',
      kind: CanvasNodeKind.text,
      position: Offset.zero,
      size: Size(280, 160),
      text: 'An editable local note',
    ),
    CanvasNode(
      id: 'far',
      kind: CanvasNodeKind.text,
      position: Offset(6000, 4000),
      size: Size(280, 160),
      text: 'farword and another farword',
      frameId: 'frame',
    ),
  ],
  frames: [
    CanvasFrame(
      id: 'frame',
      position: Offset(5940, 3930),
      size: Size(460, 360),
      title: 'frameword',
      description: 'frame descriptionword',
      collapsed: true,
    ),
  ],
  edges: [
    CanvasEdge(
      id: 'edge',
      from: 'near',
      to: 'far',
      label: 'edgeword connection',
      relation: 'relationshipword',
    ),
  ],
);

void main() {
  surfaceFindTestEnvironment();

  for (final appearance in WorkspaceDesignAppearance.values) {
    testWidgets(
        '${appearance.name}: readonly chrome-less canvas finds model words and pans',
        (tester) async {
      final controller = CanvasController(viewId: '', document: _document);
      final baseline = ContextualFindRegion.debugRegisteredRegionCount;
      try {
        await tester.pumpWidget(
          surfaceFindTestApp(
            CanvasBoard(
              controller: controller,
              editable: false,
              embedded: true,
              showChrome: false,
            ),
            appearance: appearance,
          ),
        );
        await pumpSurfaceFind(tester);
        final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
        expect(
          board.visibleScene.contains(_document.nodes.last.center),
          isFalse,
        );
        expect(find.byType(FindReplaceBar), findsNothing);
        await openSurfaceFind(tester);
        expect(find.byType(FindReplaceBar), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'farword',
        );
        await pumpSurfaceFind(tester);
        final session = tester
            .widget<SurfaceFindHost>(find.byType(SurfaceFindHost))
            .controller;
        expect(session.matches, hasLength(2));
        expect(
          board.visibleScene.contains(_document.nodes.last.center),
          isTrue,
        );
        final paint = surfaceFindPaint(
          tester,
          canvasFindNode('far', CanvasSearchField.text),
        );
        expect(paint.matchRects, hasLength(2));
        expect(paint.currentRect, isNotNull);
        expect(
          tester
              .widget<FindReplaceBar>(find.byType(FindReplaceBar))
              .replaceController,
          isNull,
        );
        expect(controller.document, same(_document));
        expect(controller.document.frames.single.collapsed, isTrue);
        expect(
          tester
              .widget<CanvasFrameBox>(find.byType(CanvasFrameBox))
              .frame
              .collapsed,
          isFalse,
        );
        await tester.sendKeyEvent(
          LogicalKeyboardKey.f3,
          physicalKey: PhysicalKeyboardKey.f3,
        );
        await pumpSurfaceFind(tester);
        expect(session.currentIndex, 1);
        for (final query in ['frameword', 'descriptionword']) {
          await tester.enterText(
            find.byKey(const ValueKey('findTextField')),
            query,
          );
          await pumpSurfaceFind(tester);
          expect(session.matches, hasLength(1));
          expect(session.currentTargetRect, isNotNull);
        }
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'edgeword',
        );
        await pumpSurfaceFind(tester);
        final edgePainter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<CanvasEdgePainter>()
            .single;
        expect(edgePainter.findHighlightRects, isNotEmpty);
        final boardRect = tester.getRect(find.byType(CanvasBoard));
        expect(
          edgePainter.findHighlightRects
              .any((rect) => (Offset.zero & boardRect.size).overlaps(rect)),
          isTrue,
        );
        session.setOptions(const FindOptions(useRegex: true));
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          r'^relationshipword$',
        );
        await pumpSurfaceFind(tester);
        expect(session.matches, hasLength(1));
        final relationPainter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<CanvasEdgePainter>()
            .single;
        expect(relationPainter.currentFindRect, isNotNull);
        expect(
          (Offset.zero & boardRect.size)
              .overlaps(relationPainter.currentFindRect!),
          isTrue,
        );
        await tester.sendKeyEvent(
          LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await pumpSurfaceFind(tester);
        expect(find.byType(FindReplaceBar), findsNothing);
        expect(controller.document, same(_document));
        expect(controller.canUndo, isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
      expect(ContextualFindRegion.debugRegisteredRegionCount, baseline);
    });
  }

  testWidgets(
      'canvas find keeps the actual editing field alive while panning away',
      (tester) async {
    final controller = CanvasController(viewId: '', document: _document);
    controller.beginEditing('near');
    try {
      await tester
          .pumpWidget(surfaceFindTestApp(CanvasBoard(controller: controller)));
      await pumpSurfaceFind(tester);
      final field = find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is CanvasCard && widget.node.id == 'near',
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'Unsaved near draft');
      final native = tester.widget<TextField>(field);
      native.controller!.selection =
          const TextSelection(baseOffset: 2, extentOffset: 7);
      final value = native.controller!.value;
      final state = tester.state(field);
      await openSurfaceFind(tester);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'farword',
      );
      await pumpSurfaceFind(tester);
      expect(controller.editing, 'near');
      expect(tester.state(field), same(state));
      expect(native.controller!.value, value);
      expect(controller.document.nodeById('near')!.text, value.text);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await pumpSurfaceFind(tester);
      expect(tester.state(field), same(state));
      expect(native.controller!.value, value);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets(
      'canvas updates remove stale hits and disposal leaves the borrowed model usable',
      (tester) async {
    final controller = CanvasController(viewId: '', document: _document);
    await tester
        .pumpWidget(surfaceFindTestApp(CanvasBoard(controller: controller)));
    await openSurfaceFind(tester);
    await tester.enterText(
      find.byKey(const ValueKey('findTextField')),
      'farword',
    );
    await pumpSurfaceFind(tester);
    final session =
        tester.widget<SurfaceFindHost>(find.byType(SurfaceFindHost)).controller;
    controller.updateNode(
      'far',
      (node) => node.copyWith(text: 'changed elsewhere'),
    );
    await pumpSurfaceFind(tester);
    expect(session.matches, isEmpty);
    session.setQuery('near');
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSurfaceFind(tester);
    expect(
      () => controller.updateNode(
        'near',
        (node) => node.copyWith(text: 'Still live'),
      ),
      returnsNormally,
    );
    controller.dispose();
  });
}
