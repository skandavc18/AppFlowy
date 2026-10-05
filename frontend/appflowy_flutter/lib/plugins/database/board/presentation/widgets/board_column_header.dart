import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/board/application/board_bloc.dart';
import 'package:appflowy/plugins/database/board/application/board_group_colors.dart';
import 'package:appflowy/plugins/database/board/group_ext.dart';
import 'package:appflowy/plugins/database/board/presentation/board_style.dart';
import 'package:appflowy/plugins/database/board/presentation/widgets/board_group_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/util/field_type_extension.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_board/appflowy_board.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'board_checkbox_column_header.dart';
import 'board_editable_column_header.dart';

class BoardColumnHeader extends StatefulWidget {
  const BoardColumnHeader({
    super.key,
    required this.databaseController,
    required this.groupData,
    required this.margin,
  });

  final DatabaseController databaseController;
  final AppFlowyGroupData groupData;
  final EdgeInsets margin;

  @override
  State<BoardColumnHeader> createState() => _BoardColumnHeaderState();
}

class _BoardColumnHeaderState extends State<BoardColumnHeader> {
  final ValueNotifier<bool> isEditing = ValueNotifier(false);

  GroupData get customData => widget.groupData.customData;

  @override
  void dispose() {
    isEditing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (customData.fieldType) {
      FieldType.MultiSelect ||
      FieldType.SingleSelect when !customData.group.isDefault =>
        EditableColumnHeader(
          databaseController: widget.databaseController,
          groupData: widget.groupData,
          isEditing: isEditing,
          onSubmitted: (columnName) {
            context
                .read<BoardBloc>()
                .add(BoardEvent.renameGroup(widget.groupData.id, columnName));
          },
        ),
      FieldType.Checkbox => CheckboxColumnHeader(
          databaseController: widget.databaseController,
          groupData: widget.groupData,
        ),
      _ => _DefaultColumnHeaderContent(
          databaseController: widget.databaseController,
          groupData: widget.groupData,
        ),
    };

    return Container(
      padding: widget.margin,
      height: 46,
      child: child,
    );
  }
}

/// How many cards a column holds, set the way Notion and Linear set it.
class BoardColumnCount extends StatelessWidget {
  const BoardColumnCount({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = boardPaletteOf(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

class GroupOptionsButton extends StatelessWidget {
  const GroupOptionsButton({
    super.key,
    required this.groupData,
    this.isEditing,
  });

  final AppFlowyGroupData groupData;
  final ValueNotifier<bool>? isEditing;

  @override
  Widget build(BuildContext context) {
    // The menu hangs off the button itself, not off the whole header.
    return Builder(
      builder: (buttonContext) => FlowyIconButton(
        width: 20,
        icon: const FlowySvg(FlowySvgs.details_horizontal_s),
        iconColorOnHover: Theme.of(context).colorScheme.onSurface,
        onPressed: () => _showMenu(buttonContext),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final customGroupData = groupData.customData as GroupData;
    final group = customGroupData.group;
    final isDefault = group.isDefault;
    final databaseController = context.read<BoardBloc>().databaseController;
    final view = databaseController.view;
    final colors = BoardGroupColorRegistry.instance;
    unawaited(
      showAppMenuForWidget<void>(
        context: context,
        placement: AppMenuPlacement.below,
        entries: boardGroupMenuEntries(
          context,
          canRename: customGroupData.fieldType.canEditHeader && !isDefault,
          canDelete: customGroupData.fieldType.canDeleteGroup && !isDefault,
          color: colors.colorsFor(view)[group.groupId],
          optionColor: group.groupOptionColor(databaseController),
          onRename: () => run(context, GroupOption.rename, group),
          onHide: () => run(context, GroupOption.hide, group),
          onDelete: () => run(context, GroupOption.delete, group),
          onColorChanged: (color) =>
              unawaited(colors.set(view, group.groupId, color)),
        ),
      ),
    );
  }

  void run(BuildContext context, GroupOption option, GroupPB group) {
    switch (option) {
      case GroupOption.rename:
        isEditing?.value = true;
        break;
      case GroupOption.hide:
        context
            .read<BoardBloc>()
            .add(BoardEvent.setGroupVisibility(group, false));
        break;
      case GroupOption.delete:
        showConfirmDeletionDialog(
          context: context,
          name: LocaleKeys.board_column_label.tr(),
          description: LocaleKeys.board_column_deleteColumnConfirmation.tr(),
          onConfirm: () {
            context
                .read<BoardBloc>()
                .add(BoardEvent.deleteGroup(group.groupId));
          },
        );
        break;
    }
  }
}

class CreateCardFromTopButton extends StatelessWidget {
  const CreateCardFromTopButton({
    super.key,
    required this.groupId,
  });

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return FlowyTooltip(
      message: LocaleKeys.board_column_addToColumnTopTooltip.tr(),
      preferBelow: false,
      child: FlowyIconButton(
        width: 20,
        icon: const FlowySvg(FlowySvgs.add_s),
        iconColorOnHover: Theme.of(context).colorScheme.onSurface,
        onPressed: () => context.read<BoardBloc>().add(
              BoardEvent.createRow(
                groupId,
                OrderObjectPositionTypePB.Start,
                null,
                null,
              ),
            ),
      ),
    );
  }
}

class _DefaultColumnHeaderContent extends StatelessWidget {
  const _DefaultColumnHeaderContent({
    required this.databaseController,
    required this.groupData,
  });

  final DatabaseController databaseController;
  final AppFlowyGroupData groupData;

  @override
  Widget build(BuildContext context) {
    final palette = boardPaletteOf(context);
    final customData = groupData.customData as GroupData;
    final groupName = customData.group.generateGroupName(databaseController);
    return Row(
      children: [
        Flexible(
          child: FlowyTooltip(
            message: groupName,
            child: Text(
              groupName,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                height: 1.2,
                letterSpacing: -0.1,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ),
        const HSpace(8),
        BoardColumnCount(count: groupData.items.length),
        const Spacer(),
        GroupOptionsButton(
          groupData: groupData,
        ),
        const HSpace(4),
        CreateCardFromTopButton(
          groupId: groupData.id,
        ),
      ],
    );
  }
}

enum GroupOption {
  rename,
  hide,
  delete,
}
