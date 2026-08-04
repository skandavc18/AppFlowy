import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// The panel a location column shows in the field editor.
///
/// A location column is a text column that has been told it holds a place, so
/// there is little to configure: how the place is written, and a way out.
class LocationEditor extends StatelessWidget {
  const LocationEditor({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.popoverMutex,
  });

  final String viewId;
  final String fieldId;
  final PopoverMutex popoverMutex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: FlowyText.regular(
            LocaleKeys.map_locationFieldHint.tr(),
            color: Theme.of(context).hintColor,
            fontSize: 11,
            maxLines: 3,
          ),
        ),
        SizedBox(
          height: GridSize.popoverItemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FlowyButton(
              text: FlowyText(
                LocaleKeys.map_locationFieldTurnOff.tr(),
                lineHeight: 1.0,
              ),
              leftIcon: const FlowySvg(FlowySvgs.delete_s),
              onTap: () => LocationFieldRegistry.instance.setLocation(
                viewId: viewId,
                fieldId: fieldId,
                enabled: false,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
