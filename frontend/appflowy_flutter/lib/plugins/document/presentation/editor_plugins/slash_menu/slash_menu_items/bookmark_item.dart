import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/bookmark/bookmark_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'slash_menu_items.dart';

/// Saves a web page into the document, shown as the card a bookmark library
/// uses for the same link.
final bookmarkSlashMenuItem = SelectionMenuItem(
  getName: () => 'Bookmark',
  keywords: const [
    'bookmark',
    'link',
    'url',
    'web',
    'website',
    'article',
    'preview',
  ],
  handler: (editorState, _, __) => editorState.insertBookmarkBlock(),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableIconWidget(
    icon: Icons.link_rounded,
    isSelected: isSelected,
    style: style,
  ),
);

extension InsertBookmarkBlock on EditorState {
  Future<void> insertBookmarkBlock() async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final path = selection.end.path;
    final currentNode = getNodeAtPath(path);
    final delta = currentNode?.delta;
    if (currentNode == null || delta == null) {
      return;
    }

    final transaction = this.transaction;
    if (delta.isEmpty && currentNode.type == ParagraphBlockKeys.type) {
      transaction
        ..insertNode(path, bookmarkBlockNode())
        ..deleteNode(currentNode);
    } else {
      transaction.insertNode(path.next, bookmarkBlockNode());
    }
    await apply(transaction);
  }
}
