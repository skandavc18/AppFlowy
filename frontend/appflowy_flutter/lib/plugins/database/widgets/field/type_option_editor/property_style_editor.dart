import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// What a styled column offers in the field editor.
///
/// The column's own type panel is still shown above this; these are only the
/// settings the presentation needs — a maximum, a step, a button's action.
class PropertyStyleEditor extends StatelessWidget {
  const PropertyStyleEditor({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.style,
  });

  final String viewId;
  final String fieldId;
  final PropertyStyle style;

  Future<void> _write(String key, Object? value) =>
      PropertyStyleRegistry.instance.setStyle(
        viewId: viewId,
        fieldId: fieldId,
        style: style.withSetting(key, value),
      );

  Future<void> _askForNumber(
    BuildContext context, {
    required String key,
    required String title,
    required double? current,
    bool clearable = false,
  }) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: current == null ? '' : _trim(current),
    );
    if (answer == null) {
      return;
    }
    final trimmed = answer.trim();
    if (trimmed.isEmpty && clearable) {
      await _write(key, null);
      return;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed != null) {
      await _write(key, parsed);
    }
  }

  Future<void> _askForText(
    BuildContext context, {
    required String key,
    required String title,
  }) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: style.stringSetting(key),
    );
    if (answer != null) {
      await _write(key, answer.trim().isEmpty ? null : answer.trim());
    }
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    switch (style.kind) {
      case PropertyStyleKind.progress:
        rows
          ..add(
            _Row(
              icon: Icons.straighten_rounded,
              label: LocaleKeys.interactive_property_maximum.tr(),
              value: _trim(style.maximum),
              onTap: () => unawaited(
                _askForNumber(
                  context,
                  key: 'maximum',
                  title: LocaleKeys.interactive_property_maximum.tr(),
                  current: style.maximum,
                ),
              ),
            ),
          )
          ..add(
            _Row(
              icon: style.showPercent
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              label: LocaleKeys.interactive_progress_showPercent.tr(),
              onTap: () =>
                  unawaited(_write('show_percent', !style.showPercent)),
            ),
          );
      case PropertyStyleKind.counter:
        rows
          ..add(
            _Row(
              icon: Icons.linear_scale_rounded,
              label: LocaleKeys.interactive_property_step.tr(),
              value: _trim(style.step),
              onTap: () => unawaited(
                _askForNumber(
                  context,
                  key: 'step',
                  title: LocaleKeys.interactive_property_step.tr(),
                  current: style.step,
                ),
              ),
            ),
          )
          ..add(
            _Row(
              icon: Icons.south_rounded,
              label: LocaleKeys.interactive_counter_setMinimum.tr(),
              value: style.minimum == null ? null : _trim(style.minimum!),
              onTap: () => unawaited(
                _askForNumber(
                  context,
                  key: 'minimum',
                  title: LocaleKeys.interactive_counter_setMinimum.tr(),
                  current: style.minimum,
                  clearable: true,
                ),
              ),
            ),
          )
          ..add(
            _Row(
              icon: Icons.north_rounded,
              label: LocaleKeys.interactive_counter_setMaximum.tr(),
              value: style.counterMaximum == null
                  ? null
                  : _trim(style.counterMaximum!),
              onTap: () => unawaited(
                _askForNumber(
                  context,
                  key: 'maximum',
                  title: LocaleKeys.interactive_counter_setMaximum.tr(),
                  current: style.counterMaximum,
                  clearable: true,
                ),
              ),
            ),
          );
      case PropertyStyleKind.button:
        rows
          ..add(
            _Row(
              icon: Icons.text_fields_rounded,
              label: LocaleKeys.interactive_property_buttonLabel.tr(),
              value: style.buttonLabel.isEmpty ? null : style.buttonLabel,
              onTap: () => unawaited(
                _askForText(
                  context,
                  key: 'label',
                  title: LocaleKeys.interactive_property_buttonLabel.tr(),
                ),
              ),
            ),
          )
          ..add(
            _Row(
              icon: Icons.bolt_rounded,
              label: LocaleKeys.interactive_button_action.tr(),
              value: propertyButtonActionLabel(style.buttonAction),
              onTap: () => unawaited(
                _write(
                  'action',
                  _nextAction(style.buttonAction).name,
                ),
              ),
            ),
          )
          ..add(
            _Row(
              icon: Icons.my_location_rounded,
              label: LocaleKeys.interactive_button_chooseTarget.tr(),
              value: style.buttonTarget.isEmpty ? null : style.buttonTarget,
              onTap: () => unawaited(
                _askForText(
                  context,
                  key: 'target',
                  title: LocaleKeys.interactive_button_chooseTarget.tr(),
                ),
              ),
            ),
          );
      case PropertyStyleKind.link:
        rows.add(
          _Row(
            icon: style.showThumbnail
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            label: LocaleKeys.interactive_property_showThumbnail.tr(),
            onTap: () => unawaited(_write('thumbnail', !style.showThumbnail)),
          ),
        );
      case PropertyStyleKind.plain:
      case PropertyStyleKind.reminder:
      case PropertyStyleKind.media:
        break;
    }

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
          child: FlowyText.regular(
            LocaleKeys.interactive_property_styleSettings.tr(),
            color: Theme.of(context).hintColor,
            fontSize: 11,
          ),
        ),
        ...rows,
      ],
    );
  }

  /// The panel is a list of rows, so the action cycles rather than opening a
  /// second popover inside the field editor's own.
  static PropertyButtonAction _nextAction(PropertyButtonAction action) =>
      PropertyButtonAction.values[
          (action.index + 1) % PropertyButtonAction.values.length];
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: GridSize.popoverItemHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FlowyButton(
          text: FlowyText(label, lineHeight: 1.0),
          leftIcon: Icon(icon, size: 16),
          rightIcon: value == null
              ? null
              : FlowyText.regular(
                  value!,
                  color: Theme.of(context).hintColor,
                  fontSize: 12,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: onTap,
        ),
      ),
    );
  }
}
