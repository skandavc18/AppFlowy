import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

class PagePreviewNodeParser extends NodeParser {
  const PagePreviewNodeParser();

  @override
  String get id => PagePreviewBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final viewId = node.attributes[PagePreviewBlockKeys.viewId] as String?;
    if (viewId == null || viewId.isEmpty) {
      return '';
    }
    final name = pageMemorizer[viewId]?.name;
    final label = name == null || name.isEmpty ? 'AppFlowy page' : name;
    return '[$label](appflowy://view/$viewId)\n';
  }
}
