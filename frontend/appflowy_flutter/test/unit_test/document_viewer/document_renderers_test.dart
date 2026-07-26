import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'document_viewer_fixtures.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: DesktopAppearance().getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      home: Scaffold(body: SizedBox(height: 600, child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  DocumentTypography.debugMonoFamilyOverride = builtInCodeFontFamily;

  group('DocumentContentView', () {
    testWidgets('renders markdown through the shared reading viewport',
        (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        DocumentContentView(
          controller: controller,
          blocks: DocumentNormalizer.fromMarkdown(
            '# Release notes\n\n'
            'Everything ships **today**.\n\n'
            '- [x] Ship it\n'
            '- [ ] Celebrate\n\n'
            '> [!TIP]\n'
            '> Read the changelog.\n\n'
            '| Area | Status |\n'
            '| --- | --- |\n'
            '| Editor | Done |\n',
          ),
        ),
      );

      expect(find.byType(DocumentViewport), findsOneWidget);
      expect(find.textContaining('Release notes'), findsOneWidget);
      expect(find.textContaining('Everything ships'), findsOneWidget);
      // Native checklists, not Material checkboxes.
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // Modern callout with its tone label.
      expect(find.text('Tip'), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb_outline_rounded), findsOneWidget);
      // Elegant table.
      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('Editor'), findsOneWidget);
      // Everything is selectable as one document.
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('code blocks read as premium code surfaces', (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        DocumentContentView(
          controller: controller,
          blocks: DocumentNormalizer.fromMarkdown(
            '```dart\nvoid main() {}\n```\n',
          ),
        ),
      );

      expect(find.byType(DocumentCodeSurface), findsOneWidget);
      expect(find.text('DART'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      // Line numbers ride along with the code.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('an empty document says so calmly', (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        DocumentContentView(controller: controller, blocks: const []),
      );
      expect(find.text('This document is empty.'), findsOneWidget);
    });

    test('vertical rhythm gives headings room and keeps lists tight', () {
      final typography = DocumentTypography.resolve(
        sampleDocumentViewerTheme,
        monoFamily: builtInCodeFontFamily,
      );
      const paragraph = DocumentParagraphBlock(DocumentInline.empty());
      const heading = DocumentHeadingBlock(
        level: 2,
        text: DocumentInline.empty(),
      );
      const list = DocumentListBlock(items: []);

      expect(documentBlockSpacing(paragraph, null, typography), 0);
      expect(
        documentBlockSpacing(heading, paragraph, typography),
        typography.spaceAboveHeading(2),
      );
      expect(
        documentBlockSpacing(paragraph, heading, typography),
        typography.spaceBelowHeading(2),
      );
      // Sibling lists sit closer together than unrelated blocks.
      expect(
        documentBlockSpacing(list, list, typography),
        lessThan(documentBlockSpacing(list, paragraph, typography)),
      );
    });

    test('language labels stay human', () {
      expect(documentCodeLanguageLabel(null), 'CODE');
      expect(documentCodeLanguageLabel('c++'), 'C++');
      expect(documentCodeLanguageLabel('c#'), 'C#');
      expect(documentCodeLanguageLabel('ts'), 'TYPESCRIPT');
      expect(documentCodeLanguageLabel('dart'), 'DART');
    });

    test('data images decode without touching the network', () async {
      DocumentImageLoader.clearCache();
      addTearDown(DocumentImageLoader.clearCache);

      // A 1x1 transparent GIF.
      final raster = await DocumentImageLoader.load(
        'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///'
        'yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
      );
      expect(raster, isA<DocumentRasterImage>());

      await expectLater(
        DocumentImageLoader.load('mailto:a@b.c'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('data renderers', () {
    testWidgets('plain text virtualizes into chunks', (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        DocumentPlainTextView(
          controller: controller,
          text: List.generate(500, (index) => 'line $index').join('\n'),
        ),
      );

      expect(find.byType(DocumentViewport), findsOneWidget);
      // Only the visible chunks are built.
      expect(find.textContaining('line 0'), findsOneWidget);
    });

    testWidgets('delimited data reads as an elegant table', (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        DocumentDataTableView(
          controller: controller,
          rows: const [
            ['Name', 'Owner'],
            ['Roadmap', 'Ada'],
          ],
        ),
      );

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Roadmap'), findsOneWidget);
    });

    testWidgets('archives list their entries', (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        DocumentArchiveView(
          controller: controller,
          entries: const [
            DocumentArchiveEntry(
              name: 'assets/',
              size: 0,
              isDirectory: true,
            ),
            DocumentArchiveEntry(
              name: 'assets/logo.png',
              size: 2048,
              isDirectory: false,
            ),
          ],
        ),
      );

      expect(find.text('assets/'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    });

    test('chunking preserves the document exactly', () {
      final text = List.generate(250, (index) => 'row $index').join('\n');
      final chunks = chunkDocumentText(text, 120);
      expect(chunks, hasLength(3));
      expect(chunks.join('\n'), text);
      expect(chunkDocumentText('', 120), isEmpty);
    });

    test('delimited parsing honours quoted fields', () {
      expect(parseDelimitedLine('a,b,c', ','), ['a', 'b', 'c']);
      expect(
        parseDelimitedLine('"Doe, Jane",42,"He said ""hi"""', ','),
        ['Doe, Jane', '42', 'He said "hi"'],
      );
      expect(parseDelimitedLine('a\tb', '\t'), ['a', 'b']);
    });

    test('delimited documents skip blank lines and honour the cap', () {
      final rows = parseDelimitedDocument('a,b\n\nc,d\n', ',');
      expect(rows, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect(
        parseDelimitedDocument('1\n2\n3\n', ',', maxRows: 2),
        hasLength(2),
      );
    });

    test('column widths stay within readable bounds', () {
      final widths = DocumentDataTableView.resolveColumnWidths([
        ['id', 'x' * 400],
      ]);
      expect(widths, hasLength(2));
      for (final width in widths) {
        expect(
          width,
          greaterThanOrEqualTo(DocumentDataTableView.minColumnWidth),
        );
        expect(
          width,
          lessThanOrEqualTo(DocumentDataTableView.maxColumnWidth),
        );
      }
    });

    test('notebook cells carry prose, code and output', () {
      final cells = parseNotebookCells({
        'cells': [
          {
            'cell_type': 'markdown',
            'source': ['# Title\n', 'Body'],
          },
          {
            'cell_type': 'code',
            'execution_count': 3,
            'source': 'print("hi")',
            'outputs': [
              {
                'text': ['hi\n'],
              },
              {
                'data': {'text/plain': 'done'},
              },
            ],
          },
        ],
      });

      expect(cells, hasLength(2));
      expect(cells.first.markdown, isTrue);
      expect(cells.first.source, '# Title\nBody');
      expect(cells[1].markdown, isFalse);
      expect(cells[1].executionCount, 3);
      expect(cells[1].output, 'hi\ndone');
      expect(parseNotebookCells(const {}), isEmpty);
    });
  });

  group('media presentation', () {
    test('times read the way people say them', () {
      expect(formatMediaTime(Duration.zero), '0:00');
      expect(formatMediaTime(const Duration(seconds: 64)), '1:04');
      expect(
        formatMediaTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatMediaTime(const Duration(seconds: -5)), '0:00');
    });

    test('image zoom advances through deliberate stops', () {
      expect(DocumentImageStage.nextZoomStop(1, increase: true), 1.5);
      expect(DocumentImageStage.nextZoomStop(1, increase: false), 0.75);
      expect(
        DocumentImageStage.nextZoomStop(8, increase: true),
        DocumentImageStage.maxZoom,
      );
      expect(
        DocumentImageStage.nextZoomStop(0.25, increase: false),
        DocumentImageStage.minZoom,
      );
    });
  });
}
