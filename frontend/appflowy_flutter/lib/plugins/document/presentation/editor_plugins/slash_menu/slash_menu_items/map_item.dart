import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/map/map_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'slash_menu_items.dart';

/// Puts a live map in the page.
final mapSlashMenuItem = SelectionMenuItem(
  getName: () => 'Map',
  keywords: const [
    'map',
    'place',
    'location',
    'address',
    'google maps',
    'pin',
    'geo',
    'where',
  ],
  handler: (editorState, _, __) => editorState.insertMapBlock(),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableIconWidget(
    icon: Icons.map_rounded,
    isSelected: isSelected,
    style: style,
  ),
);

extension InsertMapBlock on EditorState {
  Future<void> insertMapBlock() async {
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
        ..insertNode(path, mapBlockNode())
        ..deleteNode(currentNode);
    } else {
      transaction.insertNode(path.next, mapBlockNode());
    }
    await apply(transaction);
  }
}
