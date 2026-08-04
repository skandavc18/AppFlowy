import 'package:flutter/material.dart';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/util/field_type_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/field_entities.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';

typedef SelectFieldCallback = void Function(FieldType);

const List<FieldType> _supportedFieldTypes = [
  FieldType.RichText,
  FieldType.Number,
  FieldType.SingleSelect,
  FieldType.MultiSelect,
  FieldType.DateTime,
  FieldType.Media,
  FieldType.URL,
  FieldType.Checkbox,
  FieldType.Checklist,
  FieldType.LastEditedTime,
  FieldType.CreatedTime,
  FieldType.Relation,
  FieldType.Summary,
  FieldType.Translate,
  // FieldType.Time,
];

class FieldTypeList extends StatelessWidget with FlowyOverlayDelegate {
  const FieldTypeList({
    required this.onSelectField,
    this.onSelectLocation,
    this.isLocation = false,
    super.key,
  });

  final SelectFieldCallback onSelectField;

  /// Turns the column into one that holds a place. A location column is a text
  /// column underneath, so it is offered here rather than as a field type the
  /// backend would have to learn.
  final VoidCallback? onSelectLocation;

  final bool isLocation;

  @override
  Widget build(BuildContext context) {
    final cells = _supportedFieldTypes.map((fieldType) {
      return FieldTypeCell(
        fieldType: fieldType,
        onSelectField: (fieldType) {
          onSelectField(fieldType);
          PopoverContainer.of(context).closeAll();
        },
      );
    }).toList();

    return SizedBox(
      width: 140,
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: cells.length + (onSelectLocation == null ? 0 : 1),
        separatorBuilder: (context, index) {
          return VSpace(GridSize.typeOptionSeparatorHeight);
        },
        physics: StyledScrollPhysics(),
        itemBuilder: (BuildContext context, int index) {
          if (index < cells.length) {
            return cells[index];
          }
          return SizedBox(
            height: GridSize.popoverItemHeight,
            child: FlowyButton(
              text: FlowyText(
                LocaleKeys.map_locationField.tr(),
                lineHeight: 1.0,
              ),
              leftIcon: const Icon(Icons.place_rounded, size: 16),
              rightIcon: isLocation ? const FlowySvg(FlowySvgs.check_s) : null,
              onTap: () {
                onSelectLocation!();
                PopoverContainer.of(context).closeAll();
              },
            ),
          );
        },
      ),
    );
  }
}

class FieldTypeCell extends StatelessWidget {
  const FieldTypeCell({
    super.key,
    required this.fieldType,
    required this.onSelectField,
  });

  final FieldType fieldType;
  final SelectFieldCallback onSelectField;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: GridSize.popoverItemHeight,
      child: FlowyButton(
        text: FlowyText(fieldType.i18n, lineHeight: 1.0),
        onTap: () => onSelectField(fieldType),
        leftIcon: FlowySvg(
          fieldType.svgData,
        ),
      ),
    );
  }
}
