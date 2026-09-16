import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/external/external_embed_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/extensions/presentation/island_block_component.dart';
import 'package:appflowy/shared/scrolling/deferred_page_embed.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    show Node, ImageBlockKeys, TableBlockKeys;
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flutter/widgets.dart';

/// These blocks can contain their own scrollable or custom pan/zoom surface.
/// Prose is deliberately excluded: reading a paragraph must never add another
/// focus/activation destination to the editor.
final _scrollableEmbedTypes = {
  CodeBlockKeys.type,
  ImageBlockKeys.type,
  MultiImageBlockKeys.type,
  FileBlockKeys.type,
  VideoBlockKeys.type,
  LinkPreviewBlockKeys.type,
  DatabaseBlockKeys.gridType,
  DatabaseBlockKeys.boardType,
  DatabaseBlockKeys.calendarType,
  FolderExplorerBlockKeys.type,
  ExternalEmbedKeys.type,
  PagePreviewBlockKeys.type,
  SimpleTableBlockKeys.type,
  TableBlockKeys.type,
  SpreadsheetBlockKeys.type,
  ChartBlockKeys.type,
  MapBlockKeys.type,
  CanvasBlockKeys.type,
  MindMapBlockKeys.type,
  MermaidBlockKeys.type,
  DrawingBlockKeys.type,
  ExtensionIslandBlockKeys.type,
};

Widget editorEmbedScrollRegion(Node node, Widget child) =>
    _scrollableEmbedTypes.contains(node.type) ||
            ExtensionBlockRegistry.definitionFor(node.type) != null
        ? ScrollActivationRegion(
            key: ValueKey('embed-scroll-${node.id}'),
            gateScrollGestures: true,
            child: PageEmbedPreviewScope(
              // The code editor has its own idle highlighting and must remain
              // available for selection/editing immediately. Other previews
              // opt in only when their ResizableMedia frame has fixed bounds.
              enabled: node.type != CodeBlockKeys.type,
              // The inactive gesture gate removes this marker too. Once the
              // viewer is engaged, its horizontal pan must not leave the page.
              child: HistorySwipeExclusion(child: child),
            ),
          )
        : child;
