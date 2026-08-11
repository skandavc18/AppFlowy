import 'package:appflowy/plugins/database/application/cell/bloc/number_cell_bloc.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../editable_cell_skeleton/number.dart';

class DesktopGridNumberCellSkin extends IEditableNumberCellSkin {
  @override
  Widget build(
    BuildContext context,
    CellContainerNotifier cellContainerNotifier,
    ValueNotifier<bool> compactModeNotifier,
    NumberCellBloc bloc,
    FocusNode focusNode,
    TextEditingController textEditingController,
  ) {
    return ValueListenableBuilder(
      valueListenable: compactModeNotifier,
      builder: (context, compactMode, _) {
        final padding = compactMode
            ? GridSize.compactCellContentInsets
            : GridSize.cellContentInsets;

        return PropertyAlignedText(
          viewId: bloc.cellController.viewId,
          fieldId: bloc.cellController.fieldId,
          builder: (context, align) => TextField(
            controller: textEditingController,
            focusNode: focusNode,
            onEditingComplete: () => focusNode.unfocus(),
            onSubmitted: (_) => focusNode.unfocus(),
            maxLines: context.watch<NumberCellBloc>().state.wrap ? null : 1,
            textAlign: align,
            style: Theme.of(context).textTheme.bodyMedium,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              contentPadding: padding,
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              isDense: true,
            ),
          ),
        );
      },
    );
  }
}
