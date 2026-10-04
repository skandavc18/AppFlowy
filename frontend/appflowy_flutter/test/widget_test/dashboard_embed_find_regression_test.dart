import 'package:appflowy/plugins/ai_chat/presentation/message/ai_markdown_text.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_embed_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_search_highlight.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show AppFlowyEditor;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database_find_test_support.dart';
import 'surface_find_test_support.dart';

void main() {
  surfaceFindTestEnvironment();

  for (final document in [true, false]) {
    testWidgets(
        'dashboard searches authorized native ${document ? 'document' : 'database draft'} without nested query mutation',
        (tester) async {
      final reads = DatabaseFindReads(
        layout: document ? ViewLayoutPB.Document : ViewLayoutPB.Grid,
      );
      final spec = DashboardWidgetSpec(
        id: 'embed',
        type: document ? 'page' : 'database',
        source: DashboardDataSource(
          kind: document
              ? DashboardSourceKind.page
              : DashboardSourceKind.database,
          viewId: databaseFindViewId,
        ),
      );
      final dashboard = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(id: 'section', widgets: [spec]),
          ],
        ),
      );
      final controller = DashboardFindController(
        dashboard,
        title: () => '',
        readProvider: reads.provider(),
      );
      final draft = TextEditingController(text: 'prefix needle needle');
      final nested = SurfaceFindController(search: (_, __) => const []);
      nested.setQuery('independent nested query');
      final scroll = ScrollController();
      DocumentFindSession? childFind;
      Object? childSelection;
      List<TextRange>? childMarks;
      var nestedFinds = 0;
      try {
        await tester.pumpWidget(
          surfaceFindTestApp(
            SurfaceFindHost(
              controller: controller,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 850),
                    SizedBox(
                      height: 200,
                      child: DashboardFindEmbed(
                        dashboard: dashboard,
                        spec: spec,
                        child: SurfaceFindScope(
                          controller: nested,
                          child: ContextualFindRegion(
                            onFind: () => nestedFinds++,
                            child: document
                                ? const AIMarkdownText(
                                    markdown: '**needle** and *needle*',
                                  )
                                : DatabaseFindAnchor(
                                    target: const DatabaseFindTarget.cell(
                                      databaseFindViewId,
                                      databaseFindRowId,
                                      databaseFindFieldId,
                                    ),
                                    child: TextField(
                                      controller: draft,
                                      readOnly: true,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await pumpSurfaceFind(tester);
        if (document) {
          final editor = tester
              .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
              .editorState;
          childFind = DocumentFindSession(editor);
          childFind.search('and', const FindOptions());
          await pumpSurfaceFind(tester);
          childSelection = editor.selection;
          childMarks = List.of(
            DocumentSearchHighlight.instance
                .rangesOf(editor.document.root.children.single),
          );
          expect(childMarks, hasLength(1));
        }
        // Query is entered AFTER the real renderer has laid out its words.
        controller.open();
        controller.setQuery('needle');
        await pumpSurfaceFind(tester);
        await pumpSurfaceFind(tester);
        expect(controller.matches, hasLength(2));
        expect(
          controller.matches.every((match) => !match.entry.replaceable),
          isTrue,
        );
        final highlight = tester.renderObject<RenderSurfaceFindHighlight>(
          find.descendant(
            of: find.byType(DashboardFindEmbed),
            matching: find.byType(SurfaceFindHighlight),
          ),
        );
        final native = <Rect>[];
        for (final run in highlight.textRuns) {
          for (final match in RegExp('needle').allMatches(run.text)) {
            native.addAll(
              run.boxes(match.start, match.end).map(
                    (box) => MatrixUtils.transformRect(
                      run.render.getTransformTo(highlight),
                      box.toRect(),
                    ),
                  ),
            );
          }
        }
        expect(native, isNotEmpty);
        expect(highlight.matchRects, native);
        controller.step(1);
        await pumpSurfaceFind(tester);
        expect(highlight.currentRect, native.last);
        final viewport = tester.getRect(find.byType(SurfaceFindHost));
        expect(
          viewport.contains(controller.currentTargetRect!.topLeft),
          isTrue,
        );
        expect(
          viewport.contains(controller.currentTargetRect!.bottomRight),
          isTrue,
        );
        expect(scroll.offset, greaterThan(0));
        expect(nested.query, 'independent nested query');
        expect(nested.isOpen, isFalse);
        expect(nestedFinds, 0);
        expect(reads.forbiddenReads, isEmpty);
        expect(
          reads.calls.where((call) => call.startsWith('preflight:')),
          hasLength(2),
        );
        expect(dashboard.canUndo, isFalse);

        if (document) {
          final editor = childFind!.editorState;
          expect(childFind.query, 'and');
          expect(editor.selection, childSelection);
          expect(
            DocumentSearchHighlight.instance
                .rangesOf(editor.document.root.children.single),
            childMarks,
          );
          expect(editor.undoManager.undoStack.isEmpty, isTrue);
          controller.replacementController.text = 'changed';
          controller.replaceCurrent();
          controller.replaceAll();
          await pumpSurfaceFind(tester);
          expect(controller.matches, hasLength(2));
          expect(editor.selection, childSelection);
          expect(editor.undoManager.undoStack.isEmpty, isTrue);
        }

        if (!document) {
          final field = find.byWidgetPredicate(
            (widget) => widget is TextField && widget.controller == draft,
          );
          final nativeState = tester.state(field);
          const value = TextEditingValue(
            text: 'draft needle needle needle',
            selection: TextSelection(baseOffset: 1, extentOffset: 3),
            composing: TextRange(start: 0, end: 5),
          );
          draft.value = value;
          await pumpSurfaceFind(tester);
          await pumpSurfaceFind(tester);
          expect(controller.matches, hasLength(3));
          expect(highlight.matchRects, hasLength(3));
          expect(tester.state(field), same(nativeState));
          expect(draft.value, value);
          expect(dashboard.canUndo, isFalse);
        }

        reads.allowed = false;
        reads.access.value++;
        expect(
          controller.matches.where((match) => match.id is DashboardEmbedFindId),
          isEmpty,
          reason: 'Revoke cached embed text synchronously, not after debounce.',
        );
        await pumpSurfaceFind(tester);
        expect(highlight.matchRects, isEmpty);
        if (document) {
          expect(childFind!.query, 'and');
          expect(childFind.editorState.selection, childSelection);
          expect(
            DocumentSearchHighlight.instance.rangesOf(
              childFind.editorState.document.root.children.single,
            ),
            childMarks,
          );
        }
      } finally {
        childFind?.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        dashboard.dispose();
        nested.dispose();
        draft.dispose();
        scroll.dispose();
        reads.dispose();
      }
    });
  }

  testWidgets(
      'cancelled embed authorization retains the scheduler slot until native completion',
      (tester) async {
    final reads = DatabaseFindReads();
    final gate = reads.hold('view:$databaseFindViewId');
    const spec = DashboardWidgetSpec(
      id: 'embed',
      type: 'database',
      source: DashboardDataSource(
        kind: DashboardSourceKind.database,
        viewId: databaseFindViewId,
      ),
    );
    final dashboard = DashboardController(
      viewId: '',
      document: const DashboardDocument(
        sections: [
          DashboardSection(id: 's', widgets: [spec]),
        ],
      ),
    );
    final controller = DashboardFindController(
      dashboard,
      title: () => '',
      readProvider: reads.provider(),
    );
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          SurfaceFindHost(
            controller: controller,
            child: DashboardFindEmbed(
              dashboard: dashboard,
              spec: spec,
              child: const DatabaseFindAnchor(
                target: DatabaseFindTarget.cell(
                  databaseFindViewId,
                  databaseFindRowId,
                  databaseFindFieldId,
                ),
                child: Text('needle'),
              ),
            ),
          ),
        ),
      );
      await pumpSurfaceFind(tester);
      controller.open();
      controller.setQuery('needle');
      await pumpSurfaceFind(tester);
      expect(reads.inFlight, 1);
      controller.close();
      await pumpSurfaceFind(tester);
      var nextStarted = false;
      reads.scheduler.schedule(Object(), () => true, () async {
        nextStarted = true;
      });
      await tester.pump();
      expect(nextStarted, isFalse);
      expect(controller.matches, isEmpty);
      gate.complete();
      await pumpSurfaceFind(tester);
      expect(nextStarted, isTrue);
      expect(reads.maxInFlight, 1);
      expect(controller.matches, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      dashboard.dispose();
      reads.dispose();
    }
  });
}
