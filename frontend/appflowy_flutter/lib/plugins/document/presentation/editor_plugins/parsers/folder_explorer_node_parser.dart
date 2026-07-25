import 'package:appflowy/plugins/document/presentation/editor_plugins/folder_explorer/folder_explorer_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

class FolderExplorerNodeParser extends NodeParser {
  const FolderExplorerNodeParser();

  @override
  String get id => FolderExplorerBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final folderId =
        node.attributes[FolderExplorerBlockKeys.folderId] as String?;
    if (folderId == null || folderId.isEmpty) {
      return '';
    }
    return '[AppFlowy folder](appflowy://view/$folderId)\n';
  }
}
