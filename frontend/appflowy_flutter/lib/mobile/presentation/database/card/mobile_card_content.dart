import 'package:flutter/material.dart';

import 'package:appflowy/plugins/database/widgets/card/card.dart';
import 'package:appflowy/plugins/database/widgets/card/card_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_builder.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_style_maps/mobile_board_card_cell_style.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:collection/collection.dart';

class MobileCardContent extends StatelessWidget {
  const MobileCardContent({
    super.key,
    required this.rowMeta,
    required this.cellBuilder,
    required this.cells,
    required this.styleConfiguration,
    required this.userProfile,
  });

  final RowMetaPB rowMeta;
  final CardCellBuilder cellBuilder;
  final List<CellMeta> cells;
  final RowCardStyleConfiguration styleConfiguration;
  final UserProfilePB? userProfile;

  @override
  Widget build(BuildContext context) {
    final fields = cellBuilder.databaseController.fieldController;
    final title = cells.firstWhereOrNull(
      (cell) => fields.getField(cell.fieldId)?.isPrimary ?? false,
    );
    final styles = mobileBoardCardCellStyleMap(context);
    final showProperties = styleConfiguration.showProperties ||
        styleConfiguration.preview.showsRowData;
    return RowCardPreviewLayout(
      rowMeta: rowMeta,
      mode: styleConfiguration.preview,
      padding: styleConfiguration.cardPadding,
      radius: styleConfiguration.coverRadius,
      tint: styleConfiguration.previewTint,
      userProfile: userProfile,
      showProperties: showProperties,
      titleBuilder: (context, foreground) => title == null
          ? const SizedBox.shrink()
          : cellBuilder.build(
              cellContext: title.cellContext(),
              styleMap: cardPreviewTitleStyleMap(styles, foreground),
              hasNotes: !rowMeta.isDocumentEmpty,
            ),
      properties: [
        if (showProperties)
          for (final cell in cells)
            if (cell != title)
              cellBuilder.build(
                cellContext: cell.cellContext(),
                styleMap: styles,
                hasNotes: !rowMeta.isDocumentEmpty,
              ),
      ],
    );
  }
}
