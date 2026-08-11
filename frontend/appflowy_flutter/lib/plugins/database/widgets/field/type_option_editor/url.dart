import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:flutter/material.dart';
import 'builder.dart';
import 'property_style_editor.dart';

class URLTypeOptionEditorFactory implements TypeOptionEditorFactory {
  const URLTypeOptionEditorFactory();

  @override
  Widget? build({
    required BuildContext context,
    required String viewId,
    required FieldPB field,
    required PopoverMutex popoverMutex,
    required TypeOptionDataCallback onTypeOptionUpdated,
  }) =>
      ValueListenableBuilder<PropertyStyles>(
        valueListenable: PropertyStyleRegistry.instance.listenable(viewId),
        builder: (context, styles, _) {
          final style = styles[field.id];
          if (style == null || style.kind != PropertyStyleKind.link) {
            return const SizedBox.shrink();
          }
          return PropertyStyleEditor(
            viewId: viewId,
            fieldId: field.id,
            style: style,
          );
        },
      );
}
