import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/chart/chart_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'slash_menu_items.dart';

/// Draws a table's numbers in the page, live.
final chartSlashMenuItem = SelectionMenuItem(
  getName: () => 'Chart',
  keywords: const [
    'chart',
    'graph',
    'plot',
    'bar',
    'line',
    'pie',
    'donut',
    'scatter',
    'visualize',
  ],
  handler: (editorState, _, __) => editorState.insertChartBlock(),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableIconWidget(
    icon: Icons.bar_chart_rounded,
    isSelected: isSelected,
    style: style,
  ),
);

extension InsertChartBlock on EditorState {
  Future<void> insertChartBlock() async {
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
        ..insertNode(path, chartBlockNode())
        ..deleteNode(currentNode);
    } else {
      transaction.insertNode(path.next, chartBlockNode());
    }
    await apply(transaction);
  }
}
