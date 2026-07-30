import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/blank_file_content.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceFileKind', () {
    test('splits blank documents from imported ones', () {
      expect(WorkspaceFileKind.markdown.isBlankCreatable, isTrue);
      expect(WorkspaceFileKind.word.isBlankCreatable, isTrue);
      expect(WorkspaceFileKind.pdf.isBlankCreatable, isFalse);
      expect(WorkspaceFileKind.image.creation, WorkspaceFileCreation.imported);
    });

    test('derives the kind from a file name', () {
      expect(
        WorkspaceFileKind.fromName('notes.md'),
        WorkspaceFileKind.markdown,
      );
      expect(WorkspaceFileKind.fromName('Report.DOCX'), WorkspaceFileKind.word);
      expect(
        WorkspaceFileKind.fromName('budget.xlsx'),
        WorkspaceFileKind.excel,
      );
      expect(
        WorkspaceFileKind.fromName('deck.pptx'),
        WorkspaceFileKind.powerpoint,
      );
      expect(WorkspaceFileKind.fromName('main.py'), isNull);
      expect(WorkspaceFileKind.fromName(''), isNull);
    });

    test('offers every type somewhere in the menu', () {
      final offered =
          workspaceFileMenuActions.map((action) => action.kind).toSet();
      expect(offered, containsAll(WorkspaceFileKind.values));
    });

    test('wears the same glyph as the file it creates', () {
      for (final kind in WorkspaceFileKind.values) {
        if (kind == WorkspaceFileKind.file) {
          continue;
        }
        expect(
          kind.icon,
          fileIconForName(kind.defaultFileName),
          reason: '$kind',
        );
      }
      expect(
        WorkspaceFileKind.file.icon,
        fileIconForName('attachment.bin'),
      );
    });
  });

  group('workspaceFileMenuActions', () {
    test('groups creation before upload without repeating a row', () {
      expect(
        workspaceFileMenuActions.toSet().length,
        workspaceFileMenuActions.length,
      );
      final sources =
          workspaceFileMenuActions.map((action) => action.source).toList();
      expect(
        sources.indexOf(WorkspaceFileSource.upload),
        greaterThan(sources.lastIndexOf(WorkspaceFileSource.create)),
      );
    });

    test('only authors kinds that can be produced blank', () {
      for (final action in workspaceFileMenuActions) {
        if (action.source == WorkspaceFileSource.create) {
          expect(
            action.kind.isBlankCreatable,
            isTrue,
            reason: '${action.kind}',
          );
        }
      }
    });

    test('lets every type be uploaded from disk', () {
      final uploadable = workspaceFileMenuActions
          .where((action) => action.source == WorkspaceFileSource.upload)
          .map((action) => action.kind)
          .toSet();
      expect(
        uploadable,
        containsAll([
          WorkspaceFileKind.file,
          WorkspaceFileKind.pdf,
          WorkspaceFileKind.image,
          WorkspaceFileKind.video,
          WorkspaceFileKind.audio,
          WorkspaceFileKind.word,
          WorkspaceFileKind.excel,
          WorkspaceFileKind.powerpoint,
        ]),
      );
    });

    test('names the blank text entry unambiguously', () {
      const create = WorkspaceFileMenuAction(
        WorkspaceFileKind.text,
        WorkspaceFileSource.create,
      );
      const upload = WorkspaceFileMenuAction(
        WorkspaceFileKind.text,
        WorkspaceFileSource.upload,
      );
      expect(create.label, 'Blank text file');
      expect(upload.label, WorkspaceFileKind.text.label);
      expect(create, isNot(upload));
    });
  });

  group('blankFileContent', () {
    test('writes plain text kinds as utf8 source', () {
      expect(blankFileContent(WorkspaceFileKind.text), isEmpty);
      expect(
        String.fromCharCodes(blankFileContent(WorkspaceFileKind.markdown)),
        startsWith('# Untitled'),
      );
      expect(
        String.fromCharCodes(blankFileContent(WorkspaceFileKind.html)),
        contains('<!DOCTYPE html>'),
      );
    });

    test('builds an openable docx package', () {
      final archive =
          ZipDecoder().decodeBytes(blankFileContent(WorkspaceFileKind.word));
      final names = archive.files.map((file) => file.name).toSet();
      expect(names, contains('[Content_Types].xml'));
      expect(names, contains('_rels/.rels'));
      expect(names, contains('word/document.xml'));
    });

    test('builds an openable xlsx package', () {
      final archive =
          ZipDecoder().decodeBytes(blankFileContent(WorkspaceFileKind.excel));
      final names = archive.files.map((file) => file.name).toSet();
      expect(names, contains('xl/workbook.xml'));
      expect(names, contains('xl/_rels/workbook.xml.rels'));
      expect(names, contains('xl/worksheets/sheet1.xml'));
    });

    test('builds a pptx package with a master, layout and slide', () {
      final archive = ZipDecoder()
          .decodeBytes(blankFileContent(WorkspaceFileKind.powerpoint));
      final names = archive.files.map((file) => file.name).toSet();
      expect(names, contains('ppt/presentation.xml'));
      expect(names, contains('ppt/slideMasters/slideMaster1.xml'));
      expect(names, contains('ppt/slideLayouts/slideLayout1.xml'));
      expect(names, contains('ppt/slides/slide1.xml'));
      expect(names, contains('ppt/theme/theme1.xml'));
    });
  });

  group('WorkspaceFilePreviewCodec', () {
    test('round trips the viewer state without dropping other keys', () {
      const original = '{"is_pinned":true}';
      final merged =
          WorkspaceFilePreviewCodec.merge(original, {'edit_mode': true});
      expect(WorkspaceFilePreviewCodec.decode(merged)['edit_mode'], isTrue);
      expect(decodeViewExtra(merged)['is_pinned'], isTrue);
    });

    test('returns an empty map for missing or broken extras', () {
      expect(WorkspaceFilePreviewCodec.decode(''), isEmpty);
      expect(WorkspaceFilePreviewCodec.decode('not json'), isEmpty);
      expect(WorkspaceFilePreviewCodec.decode('{"a":1}'), isEmpty);
    });
  });
}
