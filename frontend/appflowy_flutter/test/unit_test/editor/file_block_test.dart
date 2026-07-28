import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileBlock:', () {
    test('workspace embed preserves the existing storage reference', () {
      const reference = WorkspaceFileReference(
        viewId: 'workspace-file-id',
        name: 'report.pdf',
        url: 'C:\\AppFlowy\\files\\report.pdf',
        mimeType: 'application/pdf',
      );

      final attributes = workspaceFileBlockAttributes(
        reference: reference,
        showPreview: true,
        embeddedAt: 123,
      );

      expect(attributes[FileBlockKeys.url], reference.url);
      expect(
        attributes[FileBlockKeys.workspaceFileId],
        reference.viewId,
      );
      expect(attributes[FileBlockKeys.displayMode], 'preview');
      expect(attributes[FileBlockKeys.uploadedAt], 123);
    });

    test('workspace embed derives cloud storage from the reference URL', () {
      const reference = WorkspaceFileReference(
        viewId: 'workspace-file-id',
        name: 'report.pdf',
        url: 'https://cloud.appflowy.test/report.pdf',
        mimeType: 'application/pdf',
      );

      final attributes = workspaceFileBlockAttributes(
        reference: reference,
        showPreview: true,
      );

      expect(
        attributes[FileBlockKeys.urlType],
        FileUrlType.cloud.toIntValue(),
      );
    });

    test('insert file block in non-empty paragraph', () async {
      final document = Document.blank()
        ..insert(
          [0],
          [paragraphNode(text: 'Hello World')],
        );
      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(Position(path: [0]));

      // insert file block after the first line
      await editorState.insertEmptyFileBlock(GlobalKey());

      final afterDocument = editorState.document;
      expect(afterDocument.root.children.length, 2);
      expect(afterDocument.root.children[1].type, FileBlockKeys.type);
      expect(afterDocument.root.children[0].type, ParagraphBlockKeys.type);
      expect(
        afterDocument.root.children[0].delta!.toPlainText(),
        'Hello World',
      );
    });

    test('insert file block in empty paragraph', () async {
      final document = Document.blank()
        ..insert(
          [0],
          [paragraphNode(text: '')],
        );
      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await editorState.insertEmptyFileBlock(GlobalKey());

      final afterDocument = editorState.document;
      expect(afterDocument.root.children.length, 1);
      expect(afterDocument.root.children[0].type, FileBlockKeys.type);
    });

    test('preview block preserves its file picker filter', () async {
      final document = Document.blank()
        ..insert(
          [0],
          [paragraphNode(text: '')],
        );
      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await editorState.insertEmptyFileBlock(
        GlobalKey(),
        showPreview: true,
        allowedExtensions: const ['doc', 'docx'],
      );

      final file = editorState.document.root.children.single;
      expect(file.attributes[FileBlockKeys.displayMode], 'preview');
      expect(
        file.extraInfos?[FileBlockKeys.pickerAllowedExtensions],
        ['doc', 'docx'],
      );
    });

    test('file filters match extensions case-insensitively', () {
      expect(
        fileNameMatchesExtensions('REPORT.DOCX', const ['doc', 'docx']),
        isTrue,
      );
      expect(
        fileNameMatchesExtensions('report.xlsx', const ['doc', 'docx']),
        isFalse,
      );
      expect(fileNameMatchesExtensions('report', const ['docx']), isFalse);
      expect(fileNameMatchesExtensions('report.bin', null), isTrue);
    });
  });
}
