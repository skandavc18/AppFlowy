import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/board/application/board_group_colors.dart';
import 'package:appflowy/plugins/database/board/presentation/board_style.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/extension.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The rows of a board column's ⋯ menu.
List<AppMenuEntry> boardGroupMenuEntries(
  BuildContext context, {
  required bool canRename,
  required bool canDelete,
  required BoardColumnColor? color,
  required SelectOptionColorPB? optionColor,
  required VoidCallback onRename,
  required VoidCallback onHide,
  required VoidCallback onDelete,
  required ValueChanged<BoardColumnColor?> onColorChanged,
}) =>
    [
      if (canRename)
        AppMenuItem(
          label: LocaleKeys.board_column_renameColumn.tr(),
          icon: Icons.edit_rounded,
          onSelected: onRename,
        ),
      AppMenuItem(
        label: LocaleKeys.board_column_color.tr(),
        icon: Icons.palette_rounded,
        submenu: boardColumnColorEntries(
          context,
          color: color,
          optionColor: optionColor,
          onChanged: onColorChanged,
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.board_column_hideColumn.tr(),
        icon: Icons.visibility_off_rounded,
        onSelected: onHide,
      ),
      if (canDelete) ...[
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.board_column_deleteColumn.tr(),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: onDelete,
        ),
      ],
    ];

/// The colours a column can be given, each beside a swatch of itself.
///
/// "Default" follows the group, which for a select option is the option's own
/// colour; "No color" is offered only when there is a colour to turn off.
List<AppMenuEntry> boardColumnColorEntries(
  BuildContext context, {
  required BoardColumnColor? color,
  required SelectOptionColorPB? optionColor,
  required ValueChanged<BoardColumnColor?> onChanged,
}) {
  final well = boardColumnWellColor(boardPaletteOf(context));
  return [
    AppMenuItem(
      label: LocaleKeys.board_column_defaultColor.tr(),
      iconWidget: _ColumnSwatch(color: optionColor?.toColor(context) ?? well),
      // A column turned plain whose group has since lost its colour looks
      // exactly like the default, so it reads as the default too.
      selected: color == null || (optionColor == null && color.isPlain),
      onSelected: () => onChanged(null),
    ),
    if (optionColor != null)
      AppMenuItem(
        label: LocaleKeys.board_column_noColor.tr(),
        iconWidget: _ColumnSwatch(color: well),
        selected: color?.isPlain ?? false,
        onSelected: () => onChanged(BoardColumnColor.plain),
      ),
    const AppMenuSeparator(),
    for (final tint in SelectOptionColorPB.values)
      AppMenuItem(
        label: tint.colorName(),
        iconWidget: _ColumnSwatch(color: tint.toColor(context)),
        selected: color?.tint == tint,
        onSelected: () => onChanged(BoardColumnColor.tint(tint)),
      ),
  ];
}

class _ColumnSwatch extends StatelessWidget {
  const _ColumnSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = AppMenuStyle.of(context);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: style.border, width: 0.8),
      ),
    );
  }
}
