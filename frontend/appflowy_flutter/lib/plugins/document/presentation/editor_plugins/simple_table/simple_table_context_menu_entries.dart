import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/option/color_option_action.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/context_menu/custom_context_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';

/// The table half of the editor's context menu.
///
/// A right click inside a cell is where people reach for "insert a row here",
/// so the structural operations live next to cut and paste rather than only
/// behind the hover handles.
List<List<EditorContextMenuEntry>> simpleTableContextMenuGroups(
  EditorState editorState,
) {
  final cell = _selectedCell(editorState);
  if (cell == null) {
    return const [];
  }
  final table = cell.parentTableNode;
  if (table == null) {
    return const [];
  }

  final rowIndex = cell.rowIndex;
  final columnIndex = cell.columnIndex;
  if (rowIndex < 0 || columnIndex < 0) {
    return const [];
  }

  EditorContextMenuEntry entry(
    String name,
    IconData icon,
    Future<void> Function(EditorState editorState) run, {
    bool destructive = false,
  }) =>
      EditorContextMenuEntry(
        action: EditorContextMenuAction.table,
        getName: () => name,
        icon: icon,
        destructive: destructive,
        onPressed: (editorState) => unawaited(run(editorState)),
      );

  EditorContextMenuEntry alignEntry(TableAlign align) => entry(
        align.name,
        switch (align) {
          TableAlign.left => Icons.format_align_left_rounded,
          TableAlign.center => Icons.format_align_center_rounded,
          TableAlign.right => Icons.format_align_right_rounded,
        },
        (editorState) =>
            editorState.updateColumnAlign(tableCellNode: cell, align: align),
      );

  return [
    [
      entry(
        LocaleKeys.document_plugins_simpleTable_moreActions_insertAbove.tr(),
        Icons.arrow_upward_rounded,
        (editorState) => editorState.insertRowInTable(table, rowIndex),
      ),
      entry(
        LocaleKeys.document_plugins_simpleTable_moreActions_insertBelow.tr(),
        Icons.arrow_downward_rounded,
        (editorState) => editorState.insertRowInTable(table, rowIndex + 1),
      ),
      entry(
        LocaleKeys.document_plugins_simpleTable_moreActions_insertLeft.tr(),
        Icons.arrow_back_rounded,
        (editorState) => editorState.insertColumnInTable(table, columnIndex),
      ),
      entry(
        LocaleKeys.document_plugins_simpleTable_moreActions_insertRight.tr(),
        Icons.arrow_forward_rounded,
        (editorState) =>
            editorState.insertColumnInTable(table, columnIndex + 1),
      ),
    ],
    [
      alignEntry(TableAlign.left),
      alignEntry(TableAlign.center),
      alignEntry(TableAlign.right),
    ],
    [
      entry(
        LocaleKeys.document_plugins_simpleTable_moreActions_clearContents.tr(),
        Icons.backspace_rounded,
        (editorState) => editorState.clearContentAtRowIndex(
          tableNode: table,
          rowIndex: rowIndex,
        ),
      ),
      if (table.rowLength > 1)
        entry(
          LocaleKeys.document_plugins_simpleTable_moreActions_deleteRow.tr(),
          Icons.remove_circle_outline_rounded,
          (editorState) => editorState.deleteRowInTable(table, rowIndex),
          destructive: true,
        ),
      if (table.columnLength > 1)
        entry(
          LocaleKeys.document_plugins_simpleTable_moreActions_deleteColumn.tr(),
          Icons.remove_circle_outline_rounded,
          (editorState) => editorState.deleteColumnInTable(table, columnIndex),
          destructive: true,
        ),
    ],
  ];
}

/// Whether the pointer is inside a table cell, and so whether the row and
/// column swatches belong in the menu at all.
bool simpleTableContextMenuHasColors(EditorState editorState) =>
    _selectedCell(editorState) != null;

Node? _selectedCell(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return null;
  }
  return editorState.getNodeAtPath(selection.start.path)?.parentTableCellNode;
}

/// Swatch strips for the row and column under the pointer.
///
/// A simple table tints whole rows and columns rather than single cells, so
/// the menu offers both instead of one "cell colour".
List<Widget> simpleTableContextMenuColors(
  BuildContext context,
  EditorState editorState, {
  required VoidCallback onDismiss,
}) {
  final cell = _selectedCell(editorState);
  if (cell == null) {
    return const [];
  }
  return [
    _ColorStrip(
      label: LocaleKeys.document_plugins_simpleTable_moreActions_rowColor.tr(),
      selected: cell.rowColors[cell.rowIndex.toString()],
      onPick: (id) {
        onDismiss();
        unawaited(
          editorState.updateRowBackgroundColor(tableCellNode: cell, color: id),
        );
      },
    ),
    _ColorStrip(
      label:
          LocaleKeys.document_plugins_simpleTable_moreActions_columnColor.tr(),
      selected: cell.columnColors[cell.columnIndex.toString()],
      onPick: (id) {
        onDismiss();
        unawaited(
          editorState.updateColumnBackgroundColor(
            tableCellNode: cell,
            color: id,
          ),
        );
      },
    ),
  ];
}

class _ColorStrip extends StatelessWidget {
  const _ColorStrip({
    required this.label,
    required this.selected,
    required this.onPick,
  });

  final String label;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final tints = AFThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textStyle.caption.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Swatch(
                color: null,
                selected: selected == null ||
                    selected == optionActionColorDefaultColor,
                onTap: () => onPick(optionActionColorDefaultColor),
              ),
              for (final tint in FlowyTint.values)
                _Swatch(
                  color: tint.color(context, theme: tints),
                  selected: selected == tint.id,
                  onTap: () => onPick(tint.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? theme.borderColorScheme.themeThick
                  : theme.borderColorScheme.primary,
              width: selected ? 2 : 1,
            ),
          ),
          child: color == null
              ? Icon(
                  Icons.format_color_reset_rounded,
                  size: 11,
                  color: theme.iconColorScheme.tertiary,
                )
              : null,
        ),
      ),
    );
  }
}
