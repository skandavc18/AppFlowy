import 'package:appflowy/plugins/document/presentation/editor_plugins/canvas/canvas_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// A canvas exports as a link to itself.
///
/// A canvas has no linear reading, so there is nothing honest to write down as
/// markdown; naming it and pointing at it is better than flattening a spatial
/// arrangement into a list that means something else.
class CanvasNodeParser extends NodeParser {
  const CanvasNodeParser();

  @override
  String get id => CanvasBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final viewId = node.attributes[CanvasBlockKeys.viewId] as String?;
    if (viewId == null || viewId.isEmpty) {
      return '';
    }
    final name = pageMemorizer[viewId]?.name;
    final label = name == null || name.isEmpty ? 'Canvas' : name;
    return '[$label](appflowy://view/$viewId)\n';
  }
}
