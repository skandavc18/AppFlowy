import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a version preview actually draws.
///
/// A preview that throws during layout leaves an unsized card, which paints
/// nothing and swallows the click that should open the version. These are the
/// tests that catch "the preview is blank and clicking it does nothing".
void main() {
  Widget host(Widget child, {double width = 244, double height = 112}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      );

  const settings = PageVersionViewSettings(name: 'Tasks', extra: '');

  const children = [
    PageVersionChild(id: 'a', name: 'Notes', layout: 0),
    PageVersionChild(id: 'b', name: 'Photos', layout: 0, isFolder: true),
    PageVersionChild(id: 'c', name: 'Budget', layout: 1),
  ];

  const table = PageVersionTable(
    columns: [
      PageVersionColumn(id: 'a', name: 'Name', isPrimary: true),
      PageVersionColumn(id: 'b', name: 'Where'),
    ],
    rows: [
      PageVersionRow(id: 'r1', cells: {'a': 'Alpha', 'b': 'London'}),
      PageVersionRow(id: 'r2', cells: {'a': 'Beta', 'b': 'Leeds'}),
    ],
  );

  group('the thumbnail the rail shows', () {
    testWidgets('a remembered table is drawn by the gallery preview',
        (tester) async {
      await tester.pumpWidget(
        host(
          const PageVersionCardPreview(
            payload: PageVersionPayload(
              shape: PageVersionShape.database,
              settings: settings,
              table: table,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('folder-gallery-database-grid')),
        findsOneWidget,
      );
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('a remembered folder is drawn by the gallery preview',
        (tester) async {
      await tester.pumpWidget(
        host(
          const PageVersionCardPreview(
            payload: PageVersionPayload(
              shape: PageVersionShape.container,
              settings: settings,
              children: children,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });

    testWidgets('a remembered file is drawn by the gallery preview',
        (tester) async {
      await tester.pumpWidget(
        host(
          const PageVersionCardPreview(
            payload: PageVersionPayload(
              shape: PageVersionShape.file,
              settings: settings,
              file: PageVersionFile(
                name: 'notes.txt',
                extension: 'txt',
                bytes: 2048,
              ),
            ),
            filePath: r'C:\nowhere\notes.txt',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });

    testWidgets('the thumbnail lets a click through to the card underneath',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          GestureDetector(
            onTap: () => taps++,
            child: const ColoredBox(
              color: Colors.white,
              child: PageVersionCardPreview(
                payload: PageVersionPayload(
                  shape: PageVersionShape.database,
                  settings: settings,
                  table: table,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tapAt(tester.getCenter(find.byType(PageVersionCardPreview)));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('the view the popup shows', () {
    testWidgets('a remembered folder draws a card for every child',
        (tester) async {
      await tester.pumpWidget(
        host(
          const PageVersionGalleryView(children: children),
          width: 900,
          height: 640,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Photos'), findsOneWidget);
    });
  });

  test('a stored table is cut down to what a preview card shows', () {
    final snapshot = pageVersionDatabaseSnapshot(table)!;

    expect(snapshot.columns, ['Name', 'Where']);
    expect(snapshot.rows.first, ['Alpha', 'London']);
    expect(snapshot.totalRowCount, 2);
  });
}
