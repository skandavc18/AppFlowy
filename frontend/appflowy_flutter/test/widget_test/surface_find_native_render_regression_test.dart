import 'dart:async';

import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surface_find_test_support.dart';

List<Rect> _native(
  RenderParagraph paragraph,
  RenderBox target,
  int start,
  int end,
) =>
    paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .map(
          (box) => MatrixUtils.transformRect(
            paragraph.getTransformTo(target),
            box.toRect(),
          ),
        )
        .toList();

void main() {
  surfaceFindTestEnvironment();

  testWidgets('late query uses glyph offsets and inline widget words in order',
      (tester) async {
    final findController = SurfaceFindController(
      search: (query, options) => searchSurfaceEntries(
        const [SurfaceFindEntry('body', 'needle needle needle')],
        query,
        options,
      ),
    );
    const inlineKey = ValueKey('native-inline-word');
    const richKey = ValueKey('native-styled-words');
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          SurfaceFindHost(
            controller: findController,
            child: const Center(
              child: SurfaceFindTarget(
                id: 'body',
                child: Text.rich(
                  key: richKey,
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'nee',
                        semanticsLabel: 'not glyph offsets',
                      ),
                      TextSpan(
                        text: 'dle ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      WidgetSpan(child: Text('needle', key: inlineKey)),
                      TextSpan(
                        text: ' needle',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSurfaceFind(tester);
      final element = tester.element(find.byKey(richKey));
      await openSurfaceFind(tester);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      await pumpSurfaceFind(tester);
      final paint = surfaceFindPaint(tester, 'body');
      final outer = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byKey(richKey),
              matching: find.byType(RichText),
            )
            .first,
      );
      final inner = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(inlineKey),
          matching: find.byType(RichText),
        ),
      );
      final groups = [
        _native(outer, paint, 0, 6),
        _native(inner, paint, 0, 6),
        _native(outer, paint, 9, 15),
      ];
      // TextSpan offsets: "needle " + U+FFFC + " needle".
      expect(paint.matchRects, groups.expand((group) => group).toList());
      for (final group in groups) {
        expect(paint.currentRect, group.reduce((a, b) => a.expandToInclude(b)));
        findController.step(1);
        await pumpSurfaceFind(tester);
      }
      expect(tester.element(find.byKey(richKey)), same(element));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      findController.dispose();
    }
  });

  testWidgets(
      'async descendant behind a repaint boundary is revealed once ready',
      (tester) async {
    final loaded = Completer<String>();
    final controller = SurfaceFindController(
      search: (query, options) => searchSurfaceEntries(
        const [SurfaceFindEntry('late', 'needle')],
        query,
        options,
      ),
    );
    final scroll = ScrollController();
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          SurfaceFindHost(
            controller: controller,
            child: SingleChildScrollView(
              controller: scroll,
              child: SurfaceFindTarget(
                id: 'late',
                child: RepaintBoundary(
                  child: FutureBuilder<String>(
                    future: loaded.future,
                    builder: (_, snapshot) => Column(
                      children: [
                        const SizedBox(height: 1200),
                        if (snapshot.hasData) Text(snapshot.data!),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await openSurfaceFind(tester);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      await pumpSurfaceFind(tester);
      loaded.complete('needle');
      await pumpSurfaceFind(tester);
      final paint = surfaceFindPaint(tester, 'late');
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('needle'),
          matching: find.byType(RichText),
        ),
      );
      expect(paint.matchRects, _native(paragraph, paint, 0, 6));
      final viewport = tester.getRect(find.byType(SurfaceFindHost));
      expect(viewport.contains(controller.currentTargetRect!.center), isTrue);
      expect(scroll.offset, greaterThan(0));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      scroll.dispose();
    }
  });

  testWidgets('retained hidden faces do not contribute native word boxes',
      (tester) async {
    await tester.pumpWidget(
      surfaceFindTestApp(
        const Center(
          child: SurfaceFindHighlight(
            query: 'needle',
            options: FindOptions(),
            currentOccurrence: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Offstage(child: Text('needle offstage')),
                Visibility(
                  visible: false,
                  maintainState: true,
                  child: Text('needle hidden'),
                ),
                Opacity(opacity: 0, child: Text('needle transparent')),
                IndexedStack(
                  index: 1,
                  children: [Text('needle inactive'), Text('needle active')],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await pumpSurfaceFind(tester);
    final paint = tester.renderObject<RenderSurfaceFindHighlight>(
      find.byType(SurfaceFindHighlight),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('needle active'),
        matching: find.byType(RichText),
      ),
    );
    expect(paint.matchRects, _native(paragraph, paint, 0, 6));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('read-only live draft keeps composition and updates native paint',
      (tester) async {
    final draft = TextEditingController(text: 'needle');
    final controller = SurfaceFindController(
      search: (query, options) => searchSurfaceEntries(
        [SurfaceFindEntry('draft', draft.text)],
        query,
        options,
      ),
    );
    draft.addListener(controller.refresh);
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          SurfaceFindHost(
            controller: controller,
            child: Center(
              child: SurfaceFindTarget(
                id: 'draft',
                includeEditable: true,
                child: TextField(controller: draft, readOnly: true),
              ),
            ),
          ),
        ),
      );
      await openSurfaceFind(tester);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      await pumpSurfaceFind(tester);
      final field = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller == draft,
      );
      final state = tester.state(field);
      const value = TextEditingValue(
        text: 'prefix needle needle',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
        composing: TextRange(start: 0, end: 6),
      );
      draft.value = value;
      await pumpSurfaceFind(tester);
      controller.step(1);
      await pumpSurfaceFind(tester);
      final paint = surfaceFindPaint(tester, 'draft');
      final editable = tester
          .state<EditableTextState>(
            find.descendant(
              of: field,
              matching: find.byType(EditableText),
            ),
          )
          .renderEditable;
      final boxes = editable
          .getBoxesForSelection(
            const TextSelection(baseOffset: 14, extentOffset: 20),
          )
          .map(
            (box) => MatrixUtils.transformRect(
              editable.getTransformTo(paint),
              box.toRect(),
            ),
          );
      expect(paint.currentRect, boxes.reduce((a, b) => a.expandToInclude(b)));
      expect(draft.value, value);
      expect(tester.state(field), same(state));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      draft.removeListener(controller.refresh);
      controller.dispose();
      draft.dispose();
    }
  });
}
