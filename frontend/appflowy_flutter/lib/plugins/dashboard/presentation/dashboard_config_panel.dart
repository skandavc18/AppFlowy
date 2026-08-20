import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_actions.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_place_picker.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_view_picker.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The panel that slides in beside the dashboard when a widget is selected.
///
/// It renders whatever the widget SAYS it can be configured with, so the rows
/// look the same for every widget and a new widget needs no form of its own.
class DashboardConfigPanel extends StatelessWidget {
  const DashboardConfigPanel({
    super.key,
    required this.controller,
    required this.palette,
    required this.spec,
  });

  final DashboardController controller;
  final DashboardPalette palette;
  final DashboardWidgetSpec spec;

  @override
  Widget build(BuildContext context) {
    final definition = DashboardWidgetRegistry.definitionFor(spec.type);
    final widgetContext = DashboardWidgetContext(
      context: context,
      controller: controller,
      spec: spec,
      palette: palette,
    );

    return Container(
      width: DashboardMetrics.panelWidth,
      decoration: BoxDecoration(
        color: palette.raised,
        border: Border(
          left: BorderSide(color: palette.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, definition),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              children: [
                _Group(
                  label: LocaleKeys.dashboard_config_general.tr(),
                  palette: palette,
                  children: [
                    _TextRow(
                      palette: palette,
                      label: LocaleKeys.dashboard_config_title.tr(),
                      value: spec.title,
                      onChanged: (value) => controller.edit(
                        (document) =>
                            document.withWidget(spec.copyWith(title: value)),
                      ),
                    ),
                    _ToggleRow(
                      palette: palette,
                      label: LocaleKeys.dashboard_card_showTitle.tr(),
                      value: spec.showTitle,
                      onChanged: (value) => controller.edit(
                        (document) => document
                            .withWidget(spec.copyWith(showTitle: value)),
                      ),
                    ),
                    _AccentRow(
                      palette: palette,
                      label: LocaleKeys.dashboard_config_colour.tr(),
                      value: spec.accent,
                      onChanged: (accent) => controller.edit(
                        (document) =>
                            document.withWidget(spec.copyWith(accent: accent)),
                      ),
                    ),
                  ],
                ),
                _Group(
                  label: LocaleKeys.dashboard_config_size.tr(),
                  palette: palette,
                  children: [
                    _NumberRow(
                      palette: palette,
                      label: LocaleKeys.dashboard_config_widthUnits.tr(),
                      value: spec.placement.columnSpan.toDouble(),
                      minimum: 1,
                      maximum: 12,
                      onChanged: (value) => controller.edit(
                        (document) => document.withWidget(
                          spec.copyWith(
                            placement: spec.placement
                                .copyWith(columnSpan: value.round()),
                          ),
                        ),
                      ),
                    ),
                    _NumberRow(
                      palette: palette,
                      label: LocaleKeys.dashboard_config_heightUnits.tr(),
                      value: spec.placement.rowSpan.toDouble(),
                      minimum: 1,
                      maximum: 40,
                      onChanged: (value) => controller.edit(
                        (document) => document.withWidget(
                          spec.copyWith(
                            placement:
                                spec.placement.copyWith(rowSpan: value.round()),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (definition?.configure != null)
                  _Group(
                    label: LocaleKeys.dashboard_config_widget.tr(),
                    palette: palette,
                    children: [
                      for (final field in definition!.configure!(widgetContext))
                        _buildField(context, field),
                    ],
                  ),
                _Group(
                  label: LocaleKeys.dashboard_config_visibility.tr(),
                  palette: palette,
                  children: [
                    _BindingRow(
                      palette: palette,
                      label: LocaleKeys.dashboard_config_visibleWhen.tr(),
                      hint: LocaleKeys.dashboard_config_visibleWhenHint.tr(),
                      value: spec.visibleWhen,
                      variables: controller.document.variables,
                      onChanged: (value) => controller.edit(
                        (document) => document
                            .withWidget(spec.copyWith(visibleWhen: value)),
                      ),
                    ),
                    _ToggleRow(
                      palette: palette,
                      label: LocaleKeys.dashboard_card_hide.tr(),
                      value: spec.hidden,
                      onChanged: (value) => controller.edit(
                        (document) =>
                            document.withWidget(spec.copyWith(hidden: value)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ButtonRow(
                  palette: palette,
                  label: LocaleKeys.button_delete.tr(),
                  icon: Icons.delete_outline_rounded,
                  destructive: true,
                  onPressed: () {
                    controller.select(null);
                    controller
                        .edit((document) => document.withoutWidget(spec.id));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    DashboardWidgetDefinition? definition,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
        child: Row(
          children: [
            Icon(
              definition?.icon ?? Icons.widgets_rounded,
              size: 17,
              color: palette.accent,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                definition?.label() ?? spec.type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.title(palette, size: 15),
              ),
            ),
            DashboardIconButton(
              icon: Icons.close_rounded,
              palette: palette,
              size: 26,
              tooltip: LocaleKeys.button_close.tr(),
              onPressed: controller.closeSettings,
            ),
          ],
        ),
      );

  Widget _buildField(BuildContext context, DashboardConfigField field) =>
      switch (field) {
        DashboardConfigText() => _TextRow(
            palette: palette,
            label: field.label,
            hint: field.hint,
            value: field.value,
            placeholder: field.placeholder,
            multiline: field.multiline,
            onChanged: field.onChanged,
          ),
        DashboardConfigNumber() => _NumberRow(
            palette: palette,
            label: field.label,
            hint: field.hint,
            value: field.value,
            minimum: field.minimum,
            maximum: field.maximum,
            step: field.step,
            onChanged: field.onChanged,
          ),
        DashboardConfigToggle() => _ToggleRow(
            palette: palette,
            label: field.label,
            hint: field.hint,
            value: field.value,
            onChanged: field.onChanged,
          ),
        DashboardConfigChoice() => _ChoiceRow(
            palette: palette,
            field: field,
          ),
        DashboardConfigAccent() => _AccentRow(
            palette: palette,
            label: field.label,
            value: field.value,
            onChanged: field.onChanged,
          ),
        DashboardConfigView() => _ViewRow(palette: palette, field: field),
        DashboardConfigPlace() => _PlaceRow(palette: palette, field: field),
        DashboardConfigOptions() => _OptionsRow(palette: palette, field: field),
        DashboardConfigAction() => _ActionRow(
            palette: palette,
            field: field,
            controller: controller,
          ),
        DashboardConfigBinding() => _BindingRow(
            palette: palette,
            label: field.label,
            hint: field.hint,
            value: field.variableKey,
            variables: [
              for (final variable in controller.document.variables)
                if (field.kinds.isEmpty || field.kinds.contains(variable.kind))
                  variable,
            ],
            plain: true,
            onChanged: field.onChanged,
          ),
        DashboardConfigButton() => _ButtonRow(
            palette: palette,
            label: field.label,
            icon: field.icon,
            destructive: field.destructive,
            onPressed: field.onPressed,
          ),
        DashboardConfigNote() => _NoteRow(palette: palette, field: field),
        DashboardConfigGroup() => _Group(
            label: field.label,
            palette: palette,
            children: [
              for (final child in field.fields) _buildField(context, child),
            ],
          ),
        DashboardConfigSource() => const SizedBox.shrink(),
        // SettingsField is open so an extension can add a row type; one this
        // panel has never seen is skipped rather than crashing the sidebar.
        _ => const SizedBox.shrink(),
      };
}

// ----------------------------------------------------------------------- rows

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.palette,
    required this.children,
  });

  final String label;
  final DashboardPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 2),
              child: Text(label, style: DashboardType.sectionLabel(palette)),
            ),
            ...children,
          ],
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    required this.palette,
    this.hint = '',
    this.trailing,
  });

  final String label;
  final DashboardPalette palette;
  final String hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: DashboardType.cardTitle(
                      palette,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (hint.isNotEmpty)
                    Text(hint, style: DashboardType.caption(palette)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.placeholder = '',
    this.multiline = false,
  });

  final DashboardPalette palette;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  final String placeholder;
  final bool multiline;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(label: label, palette: palette, hint: hint),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: palette.sunken,
                borderRadius: BorderRadius.circular(10),
              ),
              child: DashboardEditableText(
                key: ValueKey('$label|$placeholder'),
                value: value,
                hint: placeholder,
                palette: palette,
                multiline: multiline,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.minimum,
    this.maximum,
    this.step = 1,
  });

  final DashboardPalette palette;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String hint;
  final double? minimum;
  final double? maximum;
  final double step;

  void _nudge(double delta) {
    var next = value + delta;
    if (minimum != null && next < minimum!) {
      next = minimum!;
    }
    if (maximum != null && next > maximum!) {
      next = maximum!;
    }
    if (next != value) {
      onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _Label(
          label: label,
          palette: palette,
          hint: hint,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashboardIconButton(
                icon: Icons.remove_rounded,
                palette: palette,
                size: 24,
                iconSize: 15,
                onPressed: () => _nudge(-step),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  formatDashboardNumber(value),
                  textAlign: TextAlign.center,
                  style: DashboardType.body(palette),
                ),
              ),
              DashboardIconButton(
                icon: Icons.add_rounded,
                palette: palette,
                size: 24,
                iconSize: 15,
                onPressed: () => _nudge(step),
              ),
            ],
          ),
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = '',
  });

  final DashboardPalette palette;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _Label(
          label: label,
          palette: palette,
          hint: hint,
          trailing: Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              activeColor: palette.accent,
              onChanged: onChanged,
            ),
          ),
        ),
      );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.palette, required this.field});

  final DashboardPalette palette;
  final DashboardConfigChoice field;

  @override
  Widget build(BuildContext context) {
    if (field.choices.length <= 3) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(label: field.label, palette: palette, hint: field.hint),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: palette.sunken,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  for (final choice in field.choices)
                    Expanded(
                      child: _Segment(
                        palette: palette,
                        label: field.iconsOnly ? '' : choice.label,
                        icon: choice.icon,
                        selected: choice.value == field.value,
                        onTap: () => field.onChanged(choice.value),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final current = field.choices
        .where((choice) => choice.value == field.value)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Builder(
        builder: (menuContext) => _Label(
          label: field.label,
          palette: palette,
          hint: field.hint,
          trailing: DashboardButton(
            label: current?.label ?? field.value,
            palette: palette,
            icon: current?.icon ?? Icons.expand_more_rounded,
            onPressed: () async {
              final value = await showAppMenuForWidget<String>(
                context: menuContext,
                entries: [
                  for (final choice in field.choices)
                    AppMenuItem(
                      label: choice.label,
                      icon: choice.icon,
                      value: choice.value,
                      selected: choice.value == field.value,
                    ),
                ],
              );
              if (value != null) {
                field.onChanged(value);
              }
            },
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final DashboardPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: DashboardMetrics.hover,
            height: 28,
            decoration: BoxDecoration(
              color: selected ? palette.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected ? palette.cardShadow() : null,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null)
                    Icon(
                      icon,
                      size: 15,
                      color: selected ? palette.accent : palette.textSecondary,
                    ),
                  if (icon != null && label.isNotEmpty)
                    const SizedBox(width: 6),
                  if (label.isNotEmpty)
                    Text(
                      label,
                      style: DashboardType.cardTitle(
                        palette,
                        color:
                            selected ? palette.textPrimary : palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _AccentRow extends StatelessWidget {
  const _AccentRow({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final DashboardPalette palette;
  final String label;
  final DashboardAccent value;
  final ValueChanged<DashboardAccent> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(label: label, palette: palette),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final accent in DashboardAccent.values)
                  Tooltip(
                    message: dashboardAccentLabel(accent),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => onChanged(accent),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: palette.strongFor(accent),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accent == value
                                  ? palette.textPrimary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}

class _ViewRow extends StatelessWidget {
  const _ViewRow({required this.palette, required this.field});

  final DashboardPalette palette;
  final DashboardConfigView field;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _Label(
          label: field.label,
          palette: palette,
          hint: field.hint,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashboardButton(
                label: field.name.isEmpty
                    ? LocaleKeys.dashboard_config_choose.tr()
                    : field.name,
                palette: palette,
                icon: Icons.description_rounded,
                onPressed: () async {
                  final view = await showInteractiveViewPicker(
                    context,
                    selectedViewId: field.viewId.isEmpty ? null : field.viewId,
                    filter: field.filter,
                  );
                  if (view != null) {
                    field.onChanged(view.id, view.name);
                  }
                },
              ),
              if (field.viewId.isNotEmpty)
                DashboardIconButton(
                  icon: Icons.close_rounded,
                  palette: palette,
                  size: 24,
                  iconSize: 14,
                  onPressed: () => field.onChanged('', ''),
                ),
            ],
          ),
        ),
      );
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.palette, required this.field});

  final DashboardPalette palette;
  final DashboardConfigPlace field;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _Label(
          label: field.label,
          palette: palette,
          hint: field.hint,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashboardButton(
                label: field.place.isEmpty
                    ? LocaleKeys.dashboard_config_choose.tr()
                    : field.place,
                palette: palette,
                icon: Icons.place_rounded,
                onPressed: () async {
                  final place = await showDashboardPlacePicker(
                    context: context,
                    palette: palette,
                    initialQuery: field.place,
                  );
                  if (place != null) {
                    field.onChanged(
                      place.name,
                      place.latitude,
                      place.longitude,
                    );
                  }
                },
              ),
              if (field.place.isNotEmpty)
                DashboardIconButton(
                  icon: Icons.close_rounded,
                  palette: palette,
                  size: 24,
                  iconSize: 14,
                  onPressed: () => field.onChanged('', null, null),
                ),
            ],
          ),
        ),
      );
}

class _OptionsRow extends StatelessWidget {
  const _OptionsRow({required this.palette, required this.field});

  final DashboardPalette palette;
  final DashboardConfigOptions field;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(label: field.label, palette: palette, hint: field.hint),
            for (var index = 0; index < field.options.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: palette.sunken,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: DashboardEditableText(
                          key: ValueKey(field.options[index].id),
                          value: field.options[index].label,
                          palette: palette,
                          onChanged: (value) {
                            final next = [...field.options];
                            next[index] = next[index].copyWith(label: value);
                            field.onChanged(next);
                          },
                        ),
                      ),
                    ),
                    DashboardIconButton(
                      icon: Icons.close_rounded,
                      palette: palette,
                      size: 24,
                      iconSize: 14,
                      onPressed: () => field.onChanged([
                        for (var i = 0; i < field.options.length; i++)
                          if (i != index) field.options[i],
                      ]),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: DashboardButton(
                label: LocaleKeys.dashboard_config_addOption.tr(),
                icon: Icons.add_rounded,
                palette: palette,
                onPressed: () => field.onChanged([
                  ...field.options,
                  DashboardOption(
                    id: newDashboardId('o'),
                    label: LocaleKeys.dashboard_config_newOption.tr(),
                  ),
                ]),
              ),
            ),
          ],
        ),
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.palette,
    required this.field,
    required this.controller,
  });

  final DashboardPalette palette;
  final DashboardConfigAction field;
  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final action = field.action;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Builder(
            builder: (menuContext) => _Label(
              label: field.label,
              palette: palette,
              hint: field.hint,
              trailing: DashboardButton(
                label: dashboardActionLabel(action.kind),
                palette: palette,
                icon: dashboardActionIcon(action.kind),
                onPressed: () async {
                  final kind = await showAppMenuForWidget<DashboardActionKind>(
                    context: menuContext,
                    entries: [
                      for (final kind in DashboardActionKind.values)
                        AppMenuItem(
                          label: dashboardActionLabel(kind),
                          icon: dashboardActionIcon(kind),
                          value: kind,
                          selected: kind == action.kind,
                        ),
                    ],
                  );
                  if (kind != null) {
                    field.onChanged(
                      DashboardAction(kind: kind, label: action.label),
                    );
                  }
                },
              ),
            ),
          ),
          ..._buildTarget(context, action),
        ],
      ),
    );
  }

  List<Widget> _buildTarget(BuildContext context, DashboardAction action) {
    if (action.kind.needsView) {
      return [
        _ViewRow(
          palette: palette,
          field: DashboardConfigView(
            label: LocaleKeys.dashboard_config_target.tr(),
            viewId: action.target,
            name: action.targetName,
            onChanged: (viewId, name) => field.onChanged(
              action.copyWith(target: viewId, targetName: name),
            ),
          ),
        ),
      ];
    }
    if (action.kind == DashboardActionKind.openUrl ||
        action.kind == DashboardActionKind.copyText) {
      return [
        _TextRow(
          palette: palette,
          label: LocaleKeys.dashboard_config_target.tr(),
          value: action.target,
          placeholder:
              action.kind == DashboardActionKind.openUrl ? 'https://' : '',
          onChanged: (value) => field.onChanged(action.copyWith(target: value)),
        ),
      ];
    }
    if (action.kind == DashboardActionKind.setVariable ||
        action.kind == DashboardActionKind.toggleVariable) {
      return [
        _BindingRow(
          palette: palette,
          label: LocaleKeys.dashboard_config_variable.tr(),
          value: action.variableKey,
          variables: controller.document.variables,
          plain: true,
          onChanged: (key) =>
              field.onChanged(action.copyWith(variableKey: key)),
        ),
        if (action.kind == DashboardActionKind.setVariable)
          _TextRow(
            palette: palette,
            label: LocaleKeys.dashboard_config_value.tr(),
            value: '${action.value ?? ''}',
            onChanged: (value) =>
                field.onChanged(action.copyWith(value: value)),
          ),
      ];
    }
    if (action.kind == DashboardActionKind.toggleSection) {
      return [
        Builder(
          builder: (menuContext) => _Label(
            label: LocaleKeys.dashboard_config_section.tr(),
            palette: palette,
            trailing: DashboardButton(
              label: controller.document
                      .sectionById(action.target)
                      ?.title
                      .replaceAll('', '') ??
                  LocaleKeys.dashboard_config_choose.tr(),
              palette: palette,
              onPressed: () async {
                final id = await showAppMenuForWidget<String>(
                  context: menuContext,
                  entries: [
                    for (final section in controller.document.sections)
                      AppMenuItem(
                        label: section.title.isEmpty
                            ? LocaleKeys.dashboard_section_untitled.tr()
                            : section.title,
                        value: section.id,
                        selected: section.id == action.target,
                      ),
                  ],
                );
                if (id != null) {
                  field.onChanged(action.copyWith(target: id));
                }
              },
            ),
          ),
        ),
      ];
    }
    return const [];
  }
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({
    required this.palette,
    required this.label,
    required this.value,
    required this.variables,
    required this.onChanged,
    this.hint = '',
    this.plain = false,
  });

  final DashboardPalette palette;
  final String label;

  /// Either a bare variable key (when [plain]) or a `key=value` rule.
  final String value;
  final List<DashboardVariable> variables;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final key = plain ? value : value.split('=').first.replaceFirst('!', '');
    final variable = variables.where((v) => v.key == key).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Builder(
        builder: (menuContext) => _Label(
          label: label,
          palette: palette,
          hint: hint,
          trailing: DashboardButton(
            label: variable?.label ??
                (value.isEmpty ? LocaleKeys.dashboard_config_none.tr() : value),
            palette: palette,
            icon: Icons.tune_rounded,
            onPressed: variables.isEmpty
                ? null
                : () async {
                    final chosen = await showAppMenuForWidget<String>(
                      context: menuContext,
                      entries: [
                        AppMenuItem(
                          label: LocaleKeys.dashboard_config_none.tr(),
                          value: '',
                          selected: value.isEmpty,
                        ),
                        for (final variable in variables)
                          AppMenuItem(
                            label: variable.label,
                            value: variable.key,
                            selected: variable.key == key,
                          ),
                      ],
                    );
                    if (chosen != null) {
                      onChanged(chosen);
                    }
                  },
          ),
        ),
      ),
    );
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.palette,
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
  });

  final DashboardPalette palette;
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: DashboardButton(
            label: label,
            icon: icon,
            palette: palette,
            onPressed: onPressed,
          ),
        ),
      );
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.palette, required this.field});

  final DashboardPalette palette;
  final DashboardConfigNote field;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              field.icon ?? Icons.info_outline_rounded,
              size: 14,
              color: palette.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                field.label,
                style: DashboardType.caption(palette),
              ),
            ),
          ],
        ),
      );
}

/// Ask for one line of text — used by the variables bar and the templates.
Future<String?> askForDashboardText(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String hintText = '',
}) =>
    showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: initialValue,
      hintText: hintText,
    );
