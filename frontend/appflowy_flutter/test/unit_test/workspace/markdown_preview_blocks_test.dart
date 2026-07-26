import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMarkdownPreviewBlocks', () {
    test('keeps the structure of ordinary markdown', () {
      final blocks = parseMarkdownPreviewBlocks('''
# Title

Some **bold** and `code` text.

- first
- second

1. one
2. two

> a quote

```dart
void main() {}
```
''');

      expect(blocks[0].kind, FolderGalleryPreviewBlockKind.heading);
      expect(blocks[0].plainText, 'Title');

      final paragraph = blocks[1];
      expect(paragraph.kind, FolderGalleryPreviewBlockKind.paragraph);
      expect(paragraph.plainText, 'Some bold and code text.');
      expect(paragraph.runs.any((run) => run.bold && run.text == 'bold'), true);
      expect(
        paragraph.runs.any((run) => run.inlineCode && run.text == 'code'),
        true,
      );

      final kinds = blocks.map((block) => block.kind).toList();
      expect(kinds, contains(FolderGalleryPreviewBlockKind.bulletedList));
      expect(kinds, contains(FolderGalleryPreviewBlockKind.numberedList));
      expect(kinds, contains(FolderGalleryPreviewBlockKind.quote));

      final code = blocks.firstWhere(
        (block) => block.kind == FolderGalleryPreviewBlockKind.code,
      );
      expect(code.language, 'dart');
      expect(code.plainText.trim(), 'void main() {}');
    });

    test('reads raw HTML instead of showing the tags', () {
      final blocks = parseMarkdownPreviewBlocks('''
<h1 align="center">
  <b>
    <a href="https://www.appflowy.com">AppFlowy</a><br>
  </b>
  The Open Source Alternative<br>
</h1>

<p align="center">
AppFlowy is the AI workspace
</p>
''');

      expect(blocks, isNotEmpty);
      for (final block in blocks) {
        expect(block.plainText, isNot(contains('<')));
        expect(block.plainText, isNot(contains('href=')));
      }
      expect(blocks.first.kind, FolderGalleryPreviewBlockKind.heading);
      expect(blocks.first.plainText, contains('AppFlowy'));
      expect(
        blocks.any((block) => block.plainText.contains('AI workspace')),
        true,
      );
    });

    test('drops badge strips that carry no words', () {
      final blocks = parseMarkdownPreviewBlocks(
        '<p><img src="https://img.shields.io/badge/a-b" /></p>\n\nReal text.\n',
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.plainText, 'Real text.');
    });

    test('renders task lists as todos', () {
      final blocks = parseMarkdownPreviewBlocks('- [x] done\n- [ ] pending\n');

      expect(blocks, hasLength(2));
      expect(blocks[0].kind, FolderGalleryPreviewBlockKind.todo);
      expect(blocks[0].checked, isTrue);
      expect(blocks[0].plainText.trim(), 'done');
      expect(blocks[1].checked, isFalse);
    });

    test('stops at the requested block count', () {
      final source = List.generate(40, (index) => 'line $index').join('\n\n');
      expect(
        parseMarkdownPreviewBlocks(source, maximumBlocks: 5),
        hasLength(5),
      );
    });

    test('falls back to plain paragraphs when nothing renders', () {
      expect(parseMarkdownPreviewBlocks('   '), isEmpty);
      expect(
        parseMarkdownPreviewBlocks('<img src="only-an-image.png">'),
        isEmpty,
      );
    });
  });

  group('parsePlainTextPreviewBlocks', () {
    test('turns non-empty lines into paragraphs', () {
      final blocks = parsePlainTextPreviewBlocks('first\n\nsecond\n');
      expect(blocks.map((block) => block.plainText), ['first', 'second']);
      expect(
        blocks.every(
          (block) => block.kind == FolderGalleryPreviewBlockKind.paragraph,
        ),
        isTrue,
      );
    });
  });

  group('isMarkdownFileName', () {
    test('matches only markdown extensions', () {
      expect(isMarkdownFileName('README.md'), isTrue);
      expect(isMarkdownFileName('notes.MARKDOWN'), isTrue);
      expect(isMarkdownFileName('main.py'), isFalse);
    });
  });
}
