import 'package:appflowy/plugins/document/presentation/editor_plugins/folder_explorer/folder_explorer_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/parsers/folder_explorer_node_parser.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_collection_preview.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('folder explorer block', () {
    test('serializes the selected folder and display mode', () {
      final node = folderExplorerNode(
        folderId: 'folder-id',
        displayMode: FolderExplorerBlockDisplayMode.icon,
        previewMode: ViewPreviewMode.content,
      );

      expect(node.type, FolderExplorerBlockKeys.type);
      expect(
        node.attributes[FolderExplorerBlockKeys.folderId],
        'folder-id',
      );
      expect(
        node.attributes[FolderExplorerBlockKeys.displayMode],
        FolderExplorerBlockDisplayMode.icon.name,
      );
      expect(node.attributes[FolderExplorerBlockKeys.width], 720.0);
      expect(node.attributes[FolderExplorerBlockKeys.height], 390.0);
      expect(
        node.attributes[FolderExplorerBlockKeys.previewMode],
        ViewPreviewMode.content.name,
      );
    });

    test('uses explorer mode for missing or future serialized values', () {
      expect(
        FolderExplorerBlockDisplayMode.fromValue(null),
        FolderExplorerBlockDisplayMode.explorer,
      );
      expect(
        FolderExplorerBlockDisplayMode.fromValue('future-mode'),
        FolderExplorerBlockDisplayMode.explorer,
      );
    });

    test('exports a stable AppFlowy view link to Markdown', () {
      final parser = const FolderExplorerNodeParser();

      expect(
        parser.transform(folderExplorerNode(folderId: 'folder-id'), null),
        '[AppFlowy folder](appflowy://view/folder-id)\n',
      );
      expect(parser.transform(folderExplorerNode(), null), isEmpty);
    });

    test('bounds embedded collection previews to six cards', () {
      expect(kFolderCollectionPreviewItemLimit, 6);
    });
  });
}
