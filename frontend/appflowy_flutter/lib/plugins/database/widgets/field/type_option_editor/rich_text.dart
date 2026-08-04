import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:flutter/material.dart';
import 'builder.dart';
import 'location.dart';
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
        builder: (context, locationFields, _) => locationFields.contains(
          field.id,
        )
            ? LocationEditor(
                viewId: viewId,
                fieldId: field.id,
                popoverMutex: popoverMutex,
              )
            : RollupEditor(
                viewId: viewId,
                fieldId: field.id,
                popoverMutex: popoverMutex,
              ),
      );
}
