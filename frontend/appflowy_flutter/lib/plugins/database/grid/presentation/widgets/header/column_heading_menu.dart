import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/field_settings_service.dart';
import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy/plugins/database/domain/sort_service.dart';
import 'package:appflowy/plugins/database/widgets/field/property_button_action.dart';
import 'package:appflowy/plugins/database/widgets/field/property_type_picker.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Everything a column can be told to do, from a right click on its heading.
///
/// It is the same menu the page blocks use — one surface, one set of rows —
/// rather than a second design that happens to live in a table.
Future<void> showColumnHeadingMenu({
  required BuildContext context,
  required Offset globalPosition,
  required String viewId,
  required FieldInfo fieldInfo,
  required VoidCallback onEditProperty,
}) =>
    showAppMenu<Object?>(
      context: context,
      globalPosition: globalPosition,
      entries: columnHeadingMenuEntries(
        context: context,
        viewId: viewId,
        fieldInfo: fieldInfo,
        style: PropertyStyleRegistry.instance.styleFor(viewId, fieldInfo.id),
        isLocation:
            LocationFieldRegistry.instance.isLocation(viewId, fieldInfo.id),
        onEditProperty: onEditProperty,
      ),
    );

/// The rows the heading menu is made of.
List<AppMenuEntry> columnHeadingMenuEntries({
  required BuildContext context,
  required String viewId,
  required FieldInfo fieldInfo,
  required PropertyStyle? style,
  required bool isLocation,
  required VoidCallback onEditProperty,
}) {
  final fieldId = fieldInfo.id;
  final isPrimary = fieldInfo.isPrimary;
  final current = propertyTypeEntryFor(
    fieldType: fieldInfo.fieldType,
    style: style,
    isLocation: isLocation,
  );
  final settings = FieldSettingsBackendService(viewId: viewId);
  final service = FieldBackendService(viewId: viewId, fieldId: fieldId);
  final hidden = fieldInfo.visibility == FieldVisibility.AlwaysHidden;

  return normalizeAppMenuEntries([
      AppMenuItem(
        label: LocaleKeys.disclosureAction_rename.tr(),
        icon: Icons.text_fields_rounded,
        onSelected: () => unawaited(_rename(context, service, fieldInfo.name)),
      ),
      AppMenuItem(
        label: LocaleKeys.grid_field_editProperty.tr(),
        icon: Icons.tune_rounded,
        onSelected: onEditProperty,
      ),
      AppMenuItem(
        label: LocaleKeys.interactive_property_type.tr(),
        icon: current?.icon ?? Icons.category_rounded,
        shortcut: current?.label,
        enabled: !isPrimary,
        submenu: _typeEntries(
          viewId: viewId,
          fieldInfo: fieldInfo,
          current: current,
          wasLocation: isLocation,
        ),
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.interactive_property_align.tr(),
        icon: _alignIcon(style?.align),
        submenu: [
          for (final align in PropertyAlign.values)
            AppMenuItem(
              label: _alignLabel(align),
              icon: _alignIcon(align),
              selected: style?.align == align,
              onSelected: () => unawaited(
                PropertyStyleRegistry.instance.setSetting(
                  viewId: viewId,
                  fieldId: fieldId,
                  key: 'align',
                  value: style?.align == align ? null : align.name,
                ),
              ),
            ),
        ],
      ),
      AppMenuItem(
        label: LocaleKeys.grid_field_wrapCellContent.tr(),
        icon: (fieldInfo.wrapCellContent ?? false)
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded,
        onSelected: () => unawaited(
          settings.updateFieldSettings(
            fieldId: fieldId,
            wrapCellContent: !(fieldInfo.wrapCellContent ?? false),
          ),
        ),
      ),
      if (fieldInfo.fieldType == FieldType.Media)
        AppMenuItem(
          label: LocaleKeys.interactive_property_thumbnailSize.tr(),
          icon: Icons.photo_size_select_large_rounded,
          submenu: [
            for (final size in PropertyThumbnailSize.values)
              AppMenuItem(
                label: _thumbnailLabel(size),
                selected:
                    (style?.thumbnailSize ?? PropertyThumbnailSize.medium) ==
                        size,
                onSelected: () => unawaited(
                  PropertyStyleRegistry.instance.setSetting(
                    viewId: viewId,
                    fieldId: fieldId,
                    key: 'thumbnail_size',
                    value: size.name,
                  ),
                ),
              ),
          ],
        ),
      ..._styleEntries(
        context: context,
        viewId: viewId,
        fieldId: fieldId,
        style: style,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.grid_settings_sort.tr(),
        icon: Icons.swap_vert_rounded,
        submenu: [
          AppMenuItem(
            label: LocaleKeys.grid_sort_ascending.tr(),
            icon: Icons.arrow_upward_rounded,
            onSelected: () => unawaited(
              SortBackendService(viewId: viewId).insertSort(
                fieldId: fieldId,
                condition: SortConditionPB.Ascending,
              ),
            ),
          ),
          AppMenuItem(
            label: LocaleKeys.grid_sort_descending.tr(),
            icon: Icons.arrow_downward_rounded,
            onSelected: () => unawaited(
              SortBackendService(viewId: viewId).insertSort(
                fieldId: fieldId,
                condition: SortConditionPB.Descending,
              ),
            ),
          ),
        ],
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.grid_field_insertLeft.tr(),
        icon: Icons.arrow_back_rounded,
        onSelected: () => unawaited(service.createBefore()),
      ),
      AppMenuItem(
        label: LocaleKeys.grid_field_insertRight.tr(),
        icon: Icons.arrow_forward_rounded,
        onSelected: () => unawaited(service.createAfter()),
      ),
      AppMenuItem(
        label: LocaleKeys.grid_field_duplicate.tr(),
        icon: Icons.control_point_duplicate_rounded,
        enabled: !isPrimary,
        onSelected: () => unawaited(
          FieldBackendService.duplicateField(viewId: viewId, fieldId: fieldId),
        ),
      ),
      AppMenuItem(
        label: hidden
            ? LocaleKeys.grid_field_show.tr()
            : LocaleKeys.grid_field_hide.tr(),
        icon: hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        enabled: !isPrimary,
        onSelected: () => unawaited(
          settings.updateFieldSettings(
            fieldId: fieldId,
            fieldVisibility: hidden
                ? FieldVisibility.AlwaysShown
                : FieldVisibility.AlwaysHidden,
          ),
        ),
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.grid_field_clear.tr(),
        icon: Icons.cleaning_services_rounded,
        onSelected: () => showCancelAndConfirmDialog(
          context: context,
          title: LocaleKeys.grid_field_clear.tr(),
          description: LocaleKeys.grid_field_clearFieldPromptMessage.tr(),
          confirmLabel: LocaleKeys.button_confirm.tr(),
          onConfirm: (_) => unawaited(
            FieldBackendService.clearField(viewId: viewId, fieldId: fieldId),
          ),
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.grid_field_delete.tr(),
        icon: Icons.delete_outline_rounded,
        destructive: true,
        enabled: !isPrimary,
        onSelected: () => showConfirmDeletionDialog(
          context: context,
          name: fieldInfo.name,
          description: LocaleKeys.grid_field_deleteFieldPromptMessage.tr(),
          onConfirm: () => unawaited(
            FieldBackendService.deleteField(
              viewId: viewId,
              fieldId: fieldId,
            ),
          ),
        ),
      ),
    ],
  );
}

/// The property types, grouped the way the picker groups them.
List<AppMenuEntry> _typeEntries({
  required String viewId,
  required FieldInfo fieldInfo,
  required PropertyTypeEntry? current,
  required bool wasLocation,
}) {
  final entries = <AppMenuEntry>[];
  PropertyTypeGroup? previous;
  for (final entry in propertyTypeEntries()) {
    if (entry.group != previous) {
      previous = entry.group;
      entries.add(AppMenuHeader(entry.group.label));
    }
    entries.add(
      AppMenuItem(
        label: entry.label,
        icon: entry.icon,
        selected: entry.id == current?.id,
        onSelected: () => unawaited(
          applyPropertyType(
            viewId: viewId,
            fieldInfo: fieldInfo,
            chosen: entry,
            previous: current,
            wasLocation: wasLocation,
          ),
        ),
      ),
    );
  }
  return entries;
}

/// The settings that belong to how the column is drawn.
List<AppMenuEntry> _styleEntries({
  required BuildContext context,
  required String viewId,
  required String fieldId,
  required PropertyStyle? style,
}) {
  if (style == null) {
    return const [];
  }

  Future<void> write(String key, Object? value) =>
      PropertyStyleRegistry.instance.setSetting(
        viewId: viewId,
        fieldId: fieldId,
        key: key,
        value: value,
      );

  Future<void> writeAll(Map<String, Object?> values) =>
      PropertyStyleRegistry.instance.setSettings(
        viewId: viewId,
        fieldId: fieldId,
        values: values,
      );

  Future<void> askNumber(String key, String title, double? current) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: current == null ? '' : _trim(current),
    );
    if (answer == null) {
      return;
    }
    final parsed = double.tryParse(answer.trim());
    await write(key, answer.trim().isEmpty ? null : parsed);
  }

  Future<void> askText(String key, String title) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: style.stringSetting(key),
    );
    if (answer != null) {
      await write(key, answer.trim().isEmpty ? null : answer.trim());
    }
  }

  return switch (style.kind) {
    PropertyStyleKind.progress => [
        AppMenuItem(
          label: LocaleKeys.interactive_property_maximum.tr(),
          icon: Icons.straighten_rounded,
          shortcut: _trim(style.maximum),
          onSelected: () => unawaited(
            askNumber(
              'maximum',
              LocaleKeys.interactive_property_maximum.tr(),
              style.maximum,
            ),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.interactive_progress_showPercent.tr(),
          icon: style.showPercent
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          onSelected: () => unawaited(
            write('show_percent', !style.showPercent),
          ),
        ),
      ],
    PropertyStyleKind.counter => [
        AppMenuItem(
          label: LocaleKeys.interactive_property_step.tr(),
          icon: Icons.linear_scale_rounded,
          shortcut: _trim(style.step),
          onSelected: () => unawaited(
            askNumber(
              'step',
              LocaleKeys.interactive_property_step.tr(),
              style.step,
            ),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.interactive_counter_setMinimum.tr(),
          icon: Icons.south_rounded,
          shortcut: style.minimum == null ? null : _trim(style.minimum!),
          onSelected: () => unawaited(
            askNumber(
              'minimum',
              LocaleKeys.interactive_counter_setMinimum.tr(),
              style.minimum,
            ),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.interactive_counter_setMaximum.tr(),
          icon: Icons.north_rounded,
          shortcut: style.counterMaximum == null
              ? null
              : _trim(style.counterMaximum!),
          onSelected: () => unawaited(
            askNumber(
              'maximum',
              LocaleKeys.interactive_counter_setMaximum.tr(),
              style.counterMaximum,
            ),
          ),
        ),
      ],
    PropertyStyleKind.button => [
        AppMenuItem(
          label: LocaleKeys.interactive_property_buttonLabel.tr(),
          icon: Icons.text_fields_rounded,
          onSelected: () => unawaited(
            askText(
              'label',
              LocaleKeys.interactive_property_buttonLabel.tr(),
            ),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.interactive_button_action.tr(),
          icon: Icons.bolt_rounded,
          shortcut: propertyButtonActionLabel(style.buttonAction),
          submenu: [
            for (final action in PropertyButtonAction.values)
              AppMenuItem(
                label: propertyButtonActionLabel(action),
                icon: propertyButtonActionIcon(action),
                selected: action == style.buttonAction,
                onSelected: () => unawaited(
                  _chooseAction(context, style, action, writeAll),
                ),
              ),
          ],
        ),
        if (propertyButtonNeedsTarget(style.buttonAction))
          AppMenuItem(
            label: propertyButtonTargetLabel(style.buttonAction),
            icon: Icons.my_location_rounded,
            shortcut: propertyButtonTargetName(style),
            onSelected: () => unawaited(
              _chooseAction(context, style, style.buttonAction, writeAll),
            ),
          ),
      ],
    PropertyStyleKind.link => [
        AppMenuItem(
          label: LocaleKeys.interactive_property_showThumbnail.tr(),
          icon: style.showThumbnail
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          onSelected: () => unawaited(
            write('thumbnail', !style.showThumbnail),
          ),
        ),
      ],
    _ => const [],
  };
}

Future<void> _chooseAction(
  BuildContext context,
  PropertyStyle style,
  PropertyButtonAction action,
  Future<void> Function(Map<String, Object?> values) write,
) async {
  final values = await chooseButtonAction(
    context: context,
    style: style,
    action: action,
  );
  if (values != null) {
    await write(values);
  }
}

Future<void> _rename(
  BuildContext context,
  FieldBackendService service,
  String name,
) async {
  final answer = await showAFTextFieldDialog(
    context: context,
    title: LocaleKeys.disclosureAction_rename.tr(),
    initialValue: name,
  );
  if (answer == null || answer.trim().isEmpty) {
    return;
  }
  await service.updateField(name: answer.trim());
}

String _trim(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(2);

String _alignLabel(PropertyAlign align) => switch (align) {
      PropertyAlign.left => LocaleKeys.interactive_property_alignLeft.tr(),
      PropertyAlign.center => LocaleKeys.interactive_property_alignCenter.tr(),
      PropertyAlign.right => LocaleKeys.interactive_property_alignRight.tr(),
    };

IconData _alignIcon(PropertyAlign? align) => switch (align) {
      PropertyAlign.center => Icons.format_align_center_rounded,
      PropertyAlign.right => Icons.format_align_right_rounded,
      _ => Icons.format_align_left_rounded,
    };

String _thumbnailLabel(PropertyThumbnailSize size) => switch (size) {
      PropertyThumbnailSize.small => LocaleKeys.interactive_size_small.tr(),
      PropertyThumbnailSize.medium => LocaleKeys.interactive_size_medium.tr(),
      PropertyThumbnailSize.large => LocaleKeys.interactive_size_large.tr(),
    };
