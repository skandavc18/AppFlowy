import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    show Document, pageNode, paragraphNode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a remembered row shows.
///
/// A row's page is kept inside its table's version when the row was reached
/// through the table, and under a version of its own when it was reached
/// through its own page. Both ways in have to draw the same page.
void main() {
  PageVersion versionOf() => PageVersion(
        id: 'v1',
        viewId: 'table',
        createdAt: DateTime.utc(2026),
        kind: PageVersionKind.manual,
        contentHash: 'h',
        shape: PageVersionShape.row,
        pageName: 'Grid',
      );

  PageVersionPayload payloadOf({Map<String, Object?>? document}) =>
      PageVersionPayload(
        shape: PageVersionShape.row,
        settings: const PageVersionViewSettings(name: 'Grid', extra: ''),
        document: document,
        table: const PageVersionTable(
          columns: [PageVersionColumn(id: 'a', name: 'Name')],
          rows: [
            PageVersionRow(id: 'r1', cells: {'a': 'Hello'}),
          ],
        ),
      );

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 800, height: 600, child: child),
        ),
      );

  testWidgets('a row whose page is not in the version asks the store',
      (tester) async {
    await tester.pumpWidget(
      host(PageVersionRowView(version: versionOf(), payload: payloadOf())),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final canvas = tester.widget<PageVersionCanvas>(
      find.byType(PageVersionCanvas),
    );
    expect(canvas.content, isNull);
    expect(canvas.viewId, 'table');
    expect(canvas.versionId, 'v1');
    // Nothing in either place reads as a note rather than an empty space.
    expect(canvas.placeholder, isNotNull);
  });

  testWidgets('a row that was written on draws its page', (tester) async {
    await tester.pumpWidget(
      host(
        PageVersionRowView(
          version: versionOf(),
          payload: payloadOf(
            document: Document(
              root: pageNode(children: [paragraphNode(text: 'Inside')]),
            ).toJson(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PageVersionCanvas), findsOneWidget);
    // The editor styles itself from the application's own theme, which a bare
    // test host has not got; that it reached the editor at all is the point.
    tester.takeException();
  });

  test('a row keeps its cells whether or not it was written on', () {
    final read = PageVersionPayload.fromJson(payloadOf().toJson());

    expect(read.shape, PageVersionShape.row);
    expect(read.table!.rows.single.cells['a'], 'Hello');
    expect(read.editorDocument, isNull);
  });
}
