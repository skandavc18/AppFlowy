import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/parsers/page_preview_node_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/page_preview_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('page preview block', () {
    test('serializes the selected page and width', () {
      final node = pagePreviewNode(
        viewId: 'page-id',
        width: 640,
        previewMode: ViewPreviewMode.content,
      );

      expect(node.type, PagePreviewBlockKeys.type);
      expect(node.attributes[PagePreviewBlockKeys.viewId], 'page-id');
      expect(node.attributes[PagePreviewBlockKeys.width], 640);
      expect(
        node.attributes[PagePreviewBlockKeys.previewMode],
        ViewPreviewMode.content.name,
      );
    });

    test('exports a stable AppFlowy view link to Markdown', () {
      final parser = const PagePreviewNodeParser();

      expect(
        parser.transform(pagePreviewNode(viewId: 'page-id'), null),
        '[AppFlowy page](appflowy://view/page-id)\n',
      );
      expect(parser.transform(pagePreviewNode(), null), isEmpty);
    });

    test('inserts a selected page preview into an empty paragraph', () async {
      final document = Document.blank()..insert([0], [paragraphNode(text: '')]);
      final editorState = EditorState(document: document)
        ..selection = Selection.collapsed(Position(path: [0]));
      final view = ViewPB()
        ..id = 'page-id'
        ..name = 'Project notes';

      await editorState.insertPagePreviewBlock(view);

      expect(document.root.children, hasLength(1));
      expect(document.root.children.single.type, PagePreviewBlockKeys.type);
      expect(
        document.root.children.single.attributes[PagePreviewBlockKeys.viewId],
        'page-id',
      );
    });

    test('inserts an empty preview block before opening its picker', () async {
      final document = Document.blank()..insert([0], [paragraphNode(text: '')]);
      final editorState = EditorState(document: document)
        ..selection = Selection.collapsed(Position(path: [0]));

      await editorState.insertPagePreviewBlock();

      expect(document.root.children, hasLength(1));
      expect(document.root.children.single.type, PagePreviewBlockKeys.type);
      expect(
        document.root.children.single.attributes[PagePreviewBlockKeys.viewId],
        isNull,
      );
      expect(
        document
            .root.children.single.extraInfos?[PagePreviewBlockKeys.globalKey],
        isA<GlobalKey<PagePreviewBlockComponentState>>(),
      );
    });

    test('accepts other previewable page layouts', () {
      final page = ViewPB(
        id: 'page',
        parentViewId: 'space',
        layout: ViewLayoutPB.Document,
      );
      final currentPage = ViewPB(
        id: 'current',
        parentViewId: 'space',
        layout: ViewLayoutPB.Document,
      );
      final workspaceRoot = ViewPB(
        id: 'root',
        layout: ViewLayoutPB.Document,
      );
      final space = ViewPB(
        id: 'space',
        parentViewId: 'root',
        layout: ViewLayoutPB.Document,
        extra: jsonEncode({'is_space': true}),
      );
      final folder = ViewPB(
        id: 'folder',
        parentViewId: 'space',
        layout: ViewLayoutPB.Document,
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final file = ViewPB(
        id: 'file',
        parentViewId: 'space',
        layout: ViewLayoutPB.Document,
        extra: const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.collaborativeText,
        ).mergeIntoExtra(''),
      );
      final table = ViewPB(
        id: 'table',
        parentViewId: 'space',
        layout: ViewLayoutPB.Grid,
      );

      expect(
        isPagePreviewCandidate(page, currentViewId: currentPage.id),
        isTrue,
      );
      expect(
        isPagePreviewCandidate(table, currentViewId: currentPage.id),
        isTrue,
      );
      for (final view in [
        currentPage,
        workspaceRoot,
        space,
        folder,
        file,
      ]) {
        expect(
          isPagePreviewCandidate(view, currentViewId: currentPage.id),
          isFalse,
          reason: '${view.id} must not be offered as a page preview',
        );
      }
    });
  });
}
