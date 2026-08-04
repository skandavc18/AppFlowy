import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/relation_cell_bloc.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/relation_cell_editor.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/database/widgets/row/relation_row_detail.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../editable_cell_skeleton/relation.dart';

class DesktopGridRelationCellSkin extends IEditableRelationCellSkin {
  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    RelationCellBloc bloc,
    RelationCellState state,
    PopoverController popoverController,
  ) {
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    return AppFlowyPopover(
      controller: popoverController,
      direction: PopoverDirection.bottomWithLeftAligned,
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
      margin: EdgeInsets.zero,
      onClose: () => cellContainerNotifier.isFocus = false,
      popupBuilder: (context) {
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: userWorkspaceBloc),
            BlocProvider.value(value: bloc),
          ],
          child: const RelationCellEditor(),
        );
      },
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ValueListenableBuilder(
          valueListenable: compactModeNotifier,
          builder: (context, compactMode, _) {
            final databaseId = state.relatedDatabaseMeta?.databaseId;
            return state.wrap
                ? _buildWrapRows(databaseId, state.rows, compactMode)
                : _buildNoWrapRows(databaseId, state.rows, compactMode);
          },
        ),
      ),
    );
  }

  Widget _buildWrapRows(
    String? databaseId,
    List<RelatedRowDataPB> rows,
    bool compactMode,
  ) {
    return Padding(
      padding: compactMode
          ? GridSize.compactCellContentInsets
          : GridSize.cellContentInsets,
      child: Wrap(
        runSpacing: 4,
        spacing: 4.0,
        children: rows
            .map((row) => RelatedRowLink(databaseId: databaseId, row: row))
            .toList(),
      ),
    );
  }

  Widget _buildNoWrapRows(
    String? databaseId,
    List<RelatedRowDataPB> rows,
    bool compactMode,
  ) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: GridSize.cellContentInsets,
        child: SeparatedRow(
          separatorBuilder: () => const HSpace(4.0),
          mainAxisSize: MainAxisSize.min,
          children: rows
              .map((row) => RelatedRowLink(databaseId: databaseId, row: row))
              .toList(),
        ),
      ),
    );
  }
}
