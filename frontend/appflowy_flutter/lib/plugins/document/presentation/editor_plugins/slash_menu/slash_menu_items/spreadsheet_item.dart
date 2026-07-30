import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';

import 'slash_menu_item_builder.dart';

const _keywords = [
  'spreadsheet',
  'sheet',
  'excel',
  'formula',
  'sum',
  'calculate',
  'budget',
  'numbers',
  'grid',
];

SelectionMenuItem spreadsheetSlashMenuItem = SelectionMenuItem(
  getName: () => LocaleKeys.document_slashMenu_name_spreadsheet.tr(),
  keywords: _keywords,
  handler: (editorState, _, __) async => editorState.insertSpreadsheet(),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableSvgWidget(
    data: FlowySvgs.slash_menu_icon_grid_s,
    isSelected: isSelected,
    style: style,
  ),
);

extension InsertSpreadsheet on EditorState {
  Future<void> insertSpreadsheet() async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final path = selection.end.path;
    final currentNode = getNodeAtPath(path);
    if (currentNode == null) {
      return;
    }

    final sheet = spreadsheetNode(
      data: SpreadsheetData.empty(rows: 8, columns: 5),
    );
    final transaction = this.transaction;
    final delta = currentNode.delta;
    if (delta != null &&
        delta.isEmpty &&
        currentNode.type == ParagraphBlockKeys.type) {
      transaction
        ..insertNode(path, sheet)
        ..deleteNode(currentNode);
    } else {
      transaction.insertNode(path.next, sheet);
    }
    await apply(transaction);
  }
}
