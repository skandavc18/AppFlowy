import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/widgets/field/property_button_action.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What ONE cell can be told to do, from a right click on it.
///
/// A column says what its cells are; a cell says where its own button goes,
/// how far its own bar runs, what colour it wears. Anything it does not
/// answer for falls back to the column.
Future<void> showCellStyleMenu({
  required BuildContext context,
  required Offset globalPosition,
  required String viewId,
  required String fieldId,
  required String rowId,
}) {
  final registry = PropertyStyleRegistry.instance;
  final entries = cellStyleMenuEntries(
    context: context,
    viewId: viewId,
    fieldId: fieldId,
    rowId: rowId,
    style: registry.cellStyleFor(viewId, fieldId, rowId),
    override: registry.cellOverrideFor(viewId, fieldId, rowId),
  );
  if (entries.isEmpty) {
    return Future<void>.value();
  }
  return showAppMenu<Object?>(
    context: context,
    globalPosition: globalPosition,
    entries: entries,
  );
}

/// The rows the cell menu is made of. Empty when the column is drawn the way
/// its own type is drawn — a plain cell has nothing of its own to say.
List<AppMenuEntry> cellStyleMenuEntries({
  required BuildContext context,
  required String viewId,
  required String fieldId,
  required String rowId,
  required PropertyStyle? style,
  required Map<String, Object?> override,
}) {
  if (style == null || style.kind == PropertyStyleKind.plain) {
    return const [];
  }

  Future<void> write(Map<String, Object?> values) =>
      PropertyStyleRegistry.instance.setCellSettings(
        viewId: viewId,
        fieldId: fieldId,
        rowId: rowId,
        values: values,
      );

  Future<void> ask(String key, String title, String current) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: current,
    );
    if (answer != null) {
      await write({key: answer.trim().isEmpty ? null : answer.trim()});
    }
  }

  Future<void> askNumber(String key, String title, double? current) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: current == null ? '' : _trim(current),
    );
    if (answer == null) {
      return;
    }
    await write({key: double.tryParse(answer.trim())});
  }

  return normalizeAppMenuEntries([
    AppMenuHeader(LocaleKeys.interactive_property_thisCell.tr()),
    ..._settingEntries(
      context: context,
      style: style,
      write: write,
      ask: ask,
      askNumber: askNumber,
    ),
    AppMenuItem(
      label: LocaleKeys.interactive_menu_colour.tr(),
      icon: Icons.palette_rounded,
      submenu: [
        for (final accent in InteractiveAccent.values)
          AppMenuItem(
            label: interactiveAccentLabel(accent),
            iconWidget: InteractiveAccentDot(accent: accent),
            selected: accent.name == style.accent,
            onSelected: () => unawaited(write({'accent': accent.name})),
          ),
      ],
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.interactive_property_useColumn.tr(),
      icon: Icons.settings_backup_restore_rounded,
      enabled: override.isNotEmpty,
      onSelected: () => unawaited(
        PropertyStyleRegistry.instance.clearCell(
          viewId: viewId,
          fieldId: fieldId,
          rowId: rowId,
        ),
      ),
    ),
  ]);
}

List<AppMenuEntry> _settingEntries({
  required BuildContext context,
  required PropertyStyle style,
  required Future<void> Function(Map<String, Object?> values) write,
  required Future<void> Function(String key, String title, String current) ask,
  required Future<void> Function(String key, String title, double? current)
      askNumber,
}) {
  return switch (style.kind) {
    PropertyStyleKind.button => [
        AppMenuItem(
          label: LocaleKeys.interactive_property_buttonLabel.tr(),
          icon: Icons.text_fields_rounded,
          shortcut: style.buttonLabel.isEmpty ? null : style.buttonLabel,
          onSelected: () => unawaited(
            ask(
              'label',
              LocaleKeys.interactive_property_buttonLabel.tr(),
              style.buttonLabel,
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
                  _configure(context, style, action, write),
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
              _configure(context, style, style.buttonAction, write),
            ),
          ),
      ],
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
          onSelected: () => unawaited(write({'show_percent': !style.showPercent})),
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
          shortcut:
              style.counterMaximum == null ? null : _trim(style.counterMaximum!),
          onSelected: () => unawaited(
            askNumber(
              'maximum',
              LocaleKeys.interactive_counter_setMaximum.tr(),
              style.counterMaximum,
            ),
          ),
        ),
      ],
    PropertyStyleKind.link => [
        AppMenuItem(
          label: LocaleKeys.interactive_property_showThumbnail.tr(),
          icon: style.showThumbnail
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          onSelected: () => unawaited(write({'thumbnail': !style.showThumbnail})),
        ),
      ],
    PropertyStyleKind.media => [
        AppMenuItem(
          label: LocaleKeys.interactive_property_thumbnailSize.tr(),
          icon: Icons.photo_size_select_large_rounded,
          submenu: [
            for (final size in PropertyThumbnailSize.values)
              AppMenuItem(
                label: _thumbnailLabel(size),
                selected: style.thumbnailSize == size,
                onSelected: () =>
                    unawaited(write({'thumbnail_size': size.name})),
              ),
          ],
        ),
      ],
    _ => const [],
  };
}

/// Picks the action AND what it needs, so choosing "open a page" asks which
/// page there and then rather than leaving a button that does nothing.
Future<void> _configure(
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

String _thumbnailLabel(PropertyThumbnailSize size) => switch (size) {
      PropertyThumbnailSize.small => LocaleKeys.interactive_size_small.tr(),
      PropertyThumbnailSize.medium => LocaleKeys.interactive_size_medium.tr(),
      PropertyThumbnailSize.large => LocaleKeys.interactive_size_large.tr(),
    };

String _trim(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(2);
