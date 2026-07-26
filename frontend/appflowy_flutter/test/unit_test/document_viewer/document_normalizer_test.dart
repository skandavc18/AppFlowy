import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('markdown normalization', () {
    test('lowers headings, prose, lists and inline styling', () {
      final blocks = DocumentNormalizer.fromMarkdown(
        '# Title\n\n'
        'A **bold** and *italic* and `code` run.\n\n'
        '- First\n'
        '- Second\n\n'
        '1. One\n'
        '2. Two\n',
      );

      final heading = blocks.first as DocumentHeadingBlock;
      expect(heading.level, 1);
      expect(heading.text.plainText, 'Title');

      final paragraph = blocks[1] as DocumentParagraphBlock;
      expect(paragraph.text.spans.any((span) => span.bold), isTrue);
      expect(paragraph.text.spans.any((span) => span.italic), isTrue);
      expect(paragraph.text.spans.any((span) => span.code), isTrue);

      final unordered = blocks[2] as DocumentListBlock;
      expect(unordered.ordered, isFalse);
      expect(unordered.items, hasLength(2));

      final ordered = blocks[3] as DocumentListBlock;
      expect(ordered.ordered, isTrue);
      expect(ordered.start, 1);
    });

    test('produces native checklists from task list syntax', () {
      final blocks = DocumentNormalizer.fromMarkdown(
        '- [x] Done\n'
        '- [ ] Pending\n',
      );

      final list = blocks.single as DocumentListBlock;
      expect(list.items.map((item) => item.checked), [true, false]);
      expect(
        (list.items.first.children.single as DocumentParagraphBlock)
            .text
            .plainText
            .trim(),
        'Done',
      );
    });

    test('keeps fenced code verbatim with its language', () {
      final blocks = DocumentNormalizer.fromMarkdown(
        '```dart\nvoid main() {\n  print("hi");\n}\n```\n',
      );

      final code = blocks.single as DocumentCodeBlock;
      expect(code.language, 'dart');
      expect(code.code, 'void main() {\n  print("hi");\n}');
    });

    test('renders GitHub alerts as modern callouts', () {
      final blocks = DocumentNormalizer.fromMarkdown(
        '> [!WARNING]\n'
        '> Mind the gap.\n',
      );

      final callout = blocks.single as DocumentCalloutBlock;
      expect(callout.tone, DocumentCalloutTone.warning);
      expect(
        (callout.children.single as DocumentParagraphBlock).text.plainText,
        'Mind the gap.',
      );
    });

    test('plain block quotes stay quotes', () {
      final blocks = DocumentNormalizer.fromMarkdown('> Just a quote.\n');
      expect(blocks.single, isA<DocumentQuoteBlock>());
    });

    test('lowers tables with their column alignment', () {
      final blocks = DocumentNormalizer.fromMarkdown(
        '| Name | Size |\n'
        '| :--- | ---: |\n'
        '| Report | 12 |\n',
      );

      final table = blocks.single as DocumentTableBlock;
      expect(table.hasHeader, isTrue);
      expect(table.columnCount, 2);
      expect(table.rows, hasLength(2));
      expect(table.alignments, [TextAlign.left, TextAlign.right]);
      expect(table.rows[1][0].plainText, 'Report');
    });

    test('captures thematic breaks', () {
      final blocks = DocumentNormalizer.fromMarkdown('a\n\n---\n\nb');
      expect(blocks.any((block) => block is DocumentDividerBlock), isTrue);
    });
  });

  group('html normalization', () {
    test('produces the same blocks as the equivalent markdown', () {
      final fromHtml = DocumentNormalizer.fromHtml(
        '<h2>Heading</h2><p>Body <strong>text</strong>.</p>',
      );
      final fromMarkdown = DocumentNormalizer.fromMarkdown(
        '## Heading\n\nBody **text**.\n',
      );

      expect(fromHtml, hasLength(fromMarkdown.length));
      expect(
        (fromHtml.first as DocumentHeadingBlock).level,
        (fromMarkdown.first as DocumentHeadingBlock).level,
      );
      expect(
        (fromHtml[1] as DocumentParagraphBlock).text.plainText,
        (fromMarkdown[1] as DocumentParagraphBlock).text.plainText,
      );
    });

    test('discards presentation, scripts and embedded frames', () {
      final blocks = DocumentNormalizer.fromHtml('''
        <style>body { color: red }</style>
        <script>window.compromised = true</script>
        <iframe src="https://example.com"></iframe>
        <div style="font-size: 48px; color: hotpink">Readable text</div>
      ''');

      expect(blocks, hasLength(1));
      final paragraph = blocks.single as DocumentParagraphBlock;
      expect(paragraph.text.plainText, 'Readable text');
      expect(paragraph.text.spans.single.link, isNull);
    });

    test('rejects active image sources and keeps safe ones', () {
      final unsafe = DocumentNormalizer.fromHtml(
        '<p><img src="javascript:alert(1)"></p>',
      );
      expect(unsafe, isEmpty);

      final safe = DocumentNormalizer.fromHtml(
        '<p><img src="https://images.example.com/a.png" '
        'width="320" height="200" alt="A photo"></p>',
      );
      final image = safe.single as DocumentImageBlock;
      expect(image.source, 'https://images.example.com/a.png');
      expect(image.width, 320);
      expect(image.height, 200);
      expect(image.alt, 'A photo');
    });

    test('resolves relative images against the document directory', () {
      final blocks = DocumentNormalizer.fromHtml(
        '<p><img src="assets/a.png"></p>',
        baseDirectory: '/documents/report',
      );
      final image = blocks.single as DocumentImageBlock;
      expect(image.source, endsWith('/documents/report/assets/a.png'));
      expect(image.source, startsWith('file:'));
    });

    test('drops relative images when no base directory is known', () {
      expect(
        DocumentNormalizer.fromHtml('<p><img src="assets/a.png"></p>'),
        isEmpty,
      );
    });

    test('preserves links for the reader', () {
      final blocks = DocumentNormalizer.fromHtml(
        '<p>See <a href="https://appflowy.io">AppFlowy</a>.</p>',
      );
      final paragraph = blocks.single as DocumentParagraphBlock;
      final link = paragraph.text.spans.firstWhere(
        (span) => span.link != null,
      );
      expect(link.link, 'https://appflowy.io');
      expect(link.text, 'AppFlowy');
    });

    test('collapses source whitespace the way a renderer would', () {
      final blocks = DocumentNormalizer.fromHtml(
        '<p>\n   Wrapped\n   across lines   </p>',
      );
      expect(
        (blocks.single as DocumentParagraphBlock).text.plainText,
        'Wrapped\nacross lines',
      );
    });
  });
}
