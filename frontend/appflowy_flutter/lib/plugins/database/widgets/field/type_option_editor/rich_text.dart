import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:flutter/material.dart';
import 'builder.dart';
import 'location.dart';
import 'property_style_editor.dart';
import 'rollup.dart';

class RichTextTypeOptionEditorFactory implements TypeOptionEditorFactory {
  const RichTextTypeOptionEditorFactory();

  @override
  Widget? build({
    required BuildContext context,
    required String viewId,
    required FieldPB field,
    required PopoverMutex popoverMutex,
    required TypeOptionDataCallback onTypeOptionUpdated,
  }) =>
      ValueListenableBuilder<Set<String>>(
        valueListenable: LocationFieldRegistry.instance.listenable(viewId),
        builder: (context, locationFields, _) {
          if (locationFields.contains(field.id)) {
            return LocationEditor(
              viewId: viewId,
              fieldId: field.id,
              popoverMutex: popoverMutex,
            );
          }
          return ValueListenableBuilder<PropertyStyles>(
            valueListenable: PropertyStyleRegistry.instance.listenable(viewId),
            builder: (context, styles, _) {
              final style = styles[field.id];
              if (style != null && style.kind != PropertyStyleKind.plain) {
                return PropertyStyleEditor(
                  viewId: viewId,
                  fieldId: field.id,
                  style: style,
                );
              }
              return RollupEditor(
                viewId: viewId,
                fieldId: field.id,
                popoverMutex: popoverMutex,
              );
            },
          );
        },
      );
}
