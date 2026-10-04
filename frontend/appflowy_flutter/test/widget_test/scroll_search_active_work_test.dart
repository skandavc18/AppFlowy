import 'package:appflowy/plugins/ai_chat/presentation/message/ai_markdown_text.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_embed_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database_find_test_support.dart';
import 'surface_find_test_support.dart';

void main() {
  surfaceFindTestEnvironment();
  for (final count in [100, 1000]) {
    testWidgets('real native embedded page range work is linear M=$count',
        (tester) async {
      final reads = DatabaseFindReads(layout: ViewLayoutPB.Document);
      const spec = DashboardWidgetSpec(
        id: 'page',
        type: 'page',
        source: DashboardDataSource(
          kind: DashboardSourceKind.page,
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
      final work = <String, int>{};
      SurfaceFindWork.onOperation =
          (key) => work.update(key, (n) => n + 1, ifAbsent: () => 1);
      try {
        await tester.pumpWidget(
          surfaceFindTestApp(
            SurfaceFindHost(
              controller: controller,
              child: DashboardFindEmbed(
                dashboard: dashboard,
                spec: spec,
                child: AIMarkdownText(
                  markdown: List.filled(count, 'needle').join(' '),
                ),
              ),
            ),
          ),
        );
        await pumpSurfaceFind(tester);
        controller.open();
        controller.setQuery('needle');
        await pumpSurfaceFind(tester);
        await pumpSurfaceFind(tester);
        expect(controller.matches, hasLength(count));
        final paint = tester.renderObject<RenderSurfaceFindHighlight>(
          find.descendant(
            of: find.byType(DashboardFindEmbed),
            matching: find.byType(SurfaceFindHighlight),
          ),
        );
        work.clear();
        expect(paint.matchRects, hasLength(count));
        debugPrint('SCROLL_SEARCH ranges M=$count work=$work');
        expect(work['documentMatchCheck'] ?? 0, lessThanOrEqualTo(count * 2));
        expect(work['snapshotScan'] ?? 0, lessThanOrEqualTo(8));
        work.clear();
        final readCount = reads.calls.length;
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        debugPrint('SCROLL_SEARCH active-stable M=$count work=$work');
        expect(work, isEmpty);
        expect(reads.calls.length, readCount);
        final editor = tester
            .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
            .editorState;
        final node = editor.document.root.children.single;
        // EditorState.apply rejects even remote transactions while readonly.
        // These are the same model operations its remote adapter applies.
        editor.document.updateText([0], Delta()..insert('needle '));
        expect(
          RegExp('needle').allMatches(node.delta!.toPlainText()),
          hasLength(count + 1),
        );
        await pumpSurfaceFind(tester);
        await pumpSurfaceFind(tester);
        expect(controller.matches, hasLength(count + 1));
        editor.document.insert([1], [paragraphNode(text: 'needle new node')]);
        await pumpSurfaceFind(tester);
        await pumpSurfaceFind(tester);
        expect(controller.matches, hasLength(count + 2));
        expect(paint.matchRects, hasLength(count + 2));
        reads.allowed = false;
        reads.access.value++;
        expect(controller.matches, isEmpty);
        expect(paint.matchRects, isEmpty);
      } finally {
        SurfaceFindWork.onOperation = null;
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        dashboard.dispose();
        reads.dispose();
      }
    });
  }
}
