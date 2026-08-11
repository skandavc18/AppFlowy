import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_view_picker.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Picks a button's action AND whatever that action needs.
///
/// Choosing "open a page" asks which page there and then, so a button is
/// never left pointing at nothing. Returns the settings to write, or null
/// when the question was dismissed.
Future<Map<String, Object?>?> chooseButtonAction({
  required BuildContext context,
  required PropertyStyle style,
  required PropertyButtonAction action,
}) async {
  switch (action) {
    case PropertyButtonAction.openRow:
    case PropertyButtonAction.copyValue:
      return {'action': action.name, 'target': null, 'target_name': null};
    case PropertyButtonAction.openView:
      final view = await showInteractiveViewPicker(context);
      if (view == null) {
        return null;
      }
      return {
        'action': action.name,
        'target': view.id,
        'target_name': view.name,
      };
    case PropertyButtonAction.openUrl:
    case PropertyButtonAction.setValue:
      if (!context.mounted) {
        return null;
      }
      final answer = await showAFTextFieldDialog(
        context: context,
        title: propertyButtonTargetLabel(action),
        initialValue: style.buttonTarget,
        hintText: action == PropertyButtonAction.openUrl ? 'https://' : null,
      );
      if (answer == null || answer.trim().isEmpty) {
        return null;
      }
      return {
        'action': action.name,
        'target': answer.trim(),
        'target_name': null,
      };
  }
}

/// Whether the action needs somewhere to point.
bool propertyButtonNeedsTarget(PropertyButtonAction action) =>
    action != PropertyButtonAction.openRow &&
    action != PropertyButtonAction.copyValue;

String propertyButtonTargetLabel(PropertyButtonAction action) =>
    switch (action) {
      PropertyButtonAction.openView =>
        LocaleKeys.interactive_button_chooseView.tr(),
      PropertyButtonAction.openUrl =>
        LocaleKeys.interactive_button_actionOpenUrl.tr(),
      PropertyButtonAction.setValue =>
        LocaleKeys.interactive_property_setValue.tr(),
      _ => LocaleKeys.interactive_button_chooseTarget.tr(),
    };

/// What a button points at, named if it has a name.
String? propertyButtonTargetName(PropertyStyle style) {
  final name = style.buttonTargetName;
  if (name.isNotEmpty) {
    return name;
  }
  return style.buttonTarget.isEmpty ? null : style.buttonTarget;
}

IconData propertyButtonActionIcon(PropertyButtonAction action) =>
    switch (action) {
      PropertyButtonAction.openRow => Icons.do_not_disturb_alt_rounded,
      PropertyButtonAction.openView => Icons.description_rounded,
      PropertyButtonAction.openUrl => Icons.open_in_new_rounded,
      PropertyButtonAction.setValue => Icons.edit_rounded,
      PropertyButtonAction.copyValue => Icons.copy_rounded,
    };
