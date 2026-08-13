import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The strip of controls that drives the whole dashboard.
///
/// Changing one of these writes a dashboard variable, and every widget bound
/// to it redraws — a project selector really does re-point the task list, the
/// counters and the charts, because none of them reads the selector: they all
/// read the state it writes.
class DashboardVariablesBar extends StatelessWidget {
  const DashboardVariablesBar({
    super.key,
    required this.controller,
    required this.palette,
  });

  final DashboardController controller;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) {
    final variables = controller.document.variables;
    final editable = controller.isEditable;
    if (variables.isEmpty && !editable) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final variable in variables)
            _VariableControl(
              controller: controller,
              palette: palette,
              variable: variable,
            ),
          if (editable)
            DashboardButton(
              label: LocaleKeys.dashboard_variable_add.tr(),
              icon: Icons.add_rounded,
              palette: palette,
              tooltip: LocaleKeys.dashboard_variable_addHint.tr(),
              onPressed: () => _addVariable(context),
            ),
          if (variables.isNotEmpty && !editable)
            DashboardIconButton(
              icon: Icons.restart_alt_rounded,
              palette: palette,
              size: 30,
              tooltip: LocaleKeys.dashboard_variable_reset.tr(),
              onPressed: controller.resetState,
            ),
        ],
      ),
    );
  }

  Future<void> _addVariable(BuildContext context) async {
    final kind = await showAppMenuForWidget<DashboardVariableKind>(
      context: context,
      entries: [
        for (final kind in DashboardVariableKind.values)
          AppMenuItem(
            label: dashboardVariableKindLabel(kind),
            icon: dashboardVariableKindIcon(kind),
            value: kind,
          ),
      ],
    );
    if (kind == null) {
      return;
    }
    final key = 'var${controller.document.variables.length + 1}';
    controller.edit(
      (document) => document.withVariable(
        DashboardVariable(
          key: key,
          label: dashboardVariableKindLabel(kind),
          kind: kind,
          options: kind == DashboardVariableKind.option ||
                  kind == DashboardVariableKind.multiOption
              ? [
                  DashboardOption(
                    id: newDashboardId('o'),
                    label: LocaleKeys.dashboard_config_newOption.tr(),
                  ),
                ]
              : const [],
        ),
      ),
    );
  }
}

String dashboardVariableKindLabel(DashboardVariableKind kind) => switch (kind) {
      DashboardVariableKind.option => LocaleKeys.dashboard_variable_option.tr(),
      DashboardVariableKind.multiOption =>
        LocaleKeys.dashboard_variable_multiOption.tr(),
      DashboardVariableKind.text => LocaleKeys.dashboard_variable_text.tr(),
      DashboardVariableKind.number => LocaleKeys.dashboard_variable_number.tr(),
      DashboardVariableKind.period => LocaleKeys.dashboard_variable_period.tr(),
      DashboardVariableKind.date => LocaleKeys.dashboard_variable_date.tr(),
      DashboardVariableKind.toggle => LocaleKeys.dashboard_variable_toggle.tr(),
      DashboardVariableKind.page => LocaleKeys.dashboard_variable_page.tr(),
    };

IconData dashboardVariableKindIcon(DashboardVariableKind kind) =>
    switch (kind) {
      DashboardVariableKind.option => Icons.arrow_drop_down_circle_rounded,
      DashboardVariableKind.multiOption => Icons.checklist_rounded,
      DashboardVariableKind.text => Icons.text_fields_rounded,
      DashboardVariableKind.number => Icons.numbers_rounded,
      DashboardVariableKind.period => Icons.date_range_rounded,
      DashboardVariableKind.date => Icons.event_rounded,
      DashboardVariableKind.toggle => Icons.toggle_on_rounded,
      DashboardVariableKind.page => Icons.description_rounded,
    };

String dashboardPeriodLabel(DashboardPeriod period) => switch (period) {
      DashboardPeriod.today => LocaleKeys.dashboard_period_today.tr(),
      DashboardPeriod.yesterday => LocaleKeys.dashboard_period_yesterday.tr(),
      DashboardPeriod.thisWeek => LocaleKeys.dashboard_period_thisWeek.tr(),
      DashboardPeriod.lastWeek => LocaleKeys.dashboard_period_lastWeek.tr(),
      DashboardPeriod.thisMonth => LocaleKeys.dashboard_period_thisMonth.tr(),
      DashboardPeriod.lastMonth => LocaleKeys.dashboard_period_lastMonth.tr(),
      DashboardPeriod.thisQuarter =>
        LocaleKeys.dashboard_period_thisQuarter.tr(),
      DashboardPeriod.thisYear => LocaleKeys.dashboard_period_thisYear.tr(),
      DashboardPeriod.allTime => LocaleKeys.dashboard_period_allTime.tr(),
    };

class _VariableControl extends StatelessWidget {
  const _VariableControl({
    required this.controller,
    required this.palette,
    required this.variable,
  });

  final DashboardController controller;
  final DashboardPalette palette;
  final DashboardVariable variable;

  @override
  Widget build(BuildContext context) {
    final value = controller.state[variable.key];
    return GestureDetector(
      onSecondaryTapDown: controller.isEditable
          ? (details) => _showMenu(context, details.globalPosition)
          : null,
      child: switch (variable.kind) {
        DashboardVariableKind.toggle => _ToggleChip(
            palette: palette,
            label: variable.label,
            value: value == true,
            onChanged: (next) => controller.setValue(variable.key, next),
          ),
        DashboardVariableKind.text => _TextChip(
            palette: palette,
            label: variable.label,
            value: '${value ?? ''}',
            onChanged: (next) => controller.setValue(variable.key, next),
          ),
        _ => _PickerChip(
            palette: palette,
            label: variable.label,
            value: _describe(value),
            onTap: (buttonContext) => _pick(buttonContext),
          ),
      },
    );
  }

  String _describe(Object? value) {
    switch (variable.kind) {
      case DashboardVariableKind.period:
        return dashboardPeriodLabel(DashboardPeriod.fromValue(value));
      case DashboardVariableKind.multiOption:
        final selected = value is List ? value.length : 0;
        if (selected == 0) {
          return _allLabel;
        }
        return LocaleKeys.dashboard_variable_selected.tr(args: ['$selected']);
      case DashboardVariableKind.option:
      case DashboardVariableKind.page:
        final id = '${value ?? ''}';
        if (id.isEmpty) {
          return _allLabel;
        }
        return variable.options
                .where((option) => option.id == id)
                .firstOrNull
                ?.label ??
            id;
      case DashboardVariableKind.number:
      case DashboardVariableKind.date:
      case DashboardVariableKind.text:
      case DashboardVariableKind.toggle:
        return '${value ?? ''}';
    }
  }

  String get _allLabel => variable.allLabel.isNotEmpty
      ? variable.allLabel
      : LocaleKeys.dashboard_control_all.tr();

  Future<void> _pick(BuildContext context) async {
    if (variable.kind == DashboardVariableKind.period) {
      final chosen = await showAppMenuForWidget<DashboardPeriod>(
        context: context,
        entries: [
          for (final period in DashboardPeriod.values)
            AppMenuItem(
              label: dashboardPeriodLabel(period),
              value: period,
              selected: DashboardPeriod.fromValue(
                    controller.state[variable.key],
                  ) ==
                  period,
            ),
        ],
      );
      if (chosen != null) {
        controller.setValue(variable.key, chosen.name);
      }
      return;
    }

    if (variable.kind == DashboardVariableKind.multiOption) {
      final selected = controller.state.selection(variable.key).toSet();
      final chosen = await showAppMenuForWidget<String>(
        context: context,
        entries: [
          for (final option in variable.options)
            AppMenuItem(
              label: option.label,
              value: option.id,
              selected: selected.contains(option.id),
            ),
        ],
      );
      if (chosen != null) {
        final next = {...selected};
        if (!next.remove(chosen)) {
          next.add(chosen);
        }
        controller.setValue(variable.key, next.toList());
      }
      return;
    }

    final chosen = await showAppMenuForWidget<String>(
      context: context,
      entries: [
        if (variable.includeAll)
          AppMenuItem(
            label: _allLabel,
            value: '',
            selected: controller.state[variable.key] == null,
          ),
        for (final option in variable.options)
          AppMenuItem(
            label: option.label,
            value: option.id,
            selected: controller.state[variable.key] == option.id,
          ),
      ],
    );
    if (chosen != null) {
      controller.setValue(variable.key, chosen.isEmpty ? null : chosen);
    }
  }

  void _showMenu(BuildContext context, Offset position) {
    showAppMenu<void>(
      context: context,
      globalPosition: position,
      entries: [
        AppMenuItem(
          label: LocaleKeys.dashboard_variable_rename.tr(),
          icon: Icons.edit_rounded,
          onSelected: () => _rename(context),
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_config_addOption.tr(),
          icon: Icons.add_rounded,
          enabled: variable.kind == DashboardVariableKind.option ||
              variable.kind == DashboardVariableKind.multiOption,
          onSelected: () => controller.edit(
            (document) => document.withVariable(
              variable.copyWith(
                options: [
                  ...variable.options,
                  DashboardOption(
                    id: newDashboardId('o'),
                    label: LocaleKeys.dashboard_config_newOption.tr(),
                  ),
                ],
              ),
            ),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.button_delete.tr(),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () => controller
              .edit((document) => document.withoutVariable(variable.key)),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final text = TextEditingController(text: variable.label);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: palette.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          LocaleKeys.dashboard_variable_rename.tr(),
          style: DashboardType.title(palette, size: 17),
        ),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: text,
            autofocus: true,
            style: DashboardType.body(palette),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          DashboardButton(
            label: LocaleKeys.button_save.tr(),
            palette: palette,
            primary: true,
            onPressed: () => Navigator.of(context).pop(text.text),
          ),
        ],
      ),
    );
    text.dispose();
    if (name != null) {
      controller.edit(
        (document) =>
            document.withVariable(variable.copyWith(label: name.trim())),
      );
    }
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.palette,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final DashboardPalette palette;
  final String label;
  final String value;
  final void Function(BuildContext context) onTap;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (buttonContext) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onTap(buttonContext),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius:
                    BorderRadius.circular(DashboardMetrics.controlRadius),
                boxShadow: palette.cardShadow(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$label:',
                    style: DashboardType.caption(palette),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.cardTitle(
                        palette,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final DashboardPalette palette;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: DashboardMetrics.hover,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: value
                  ? palette.accent.withValues(alpha: 0.13)
                  : palette.surface,
              borderRadius:
                  BorderRadius.circular(DashboardMetrics.controlRadius),
              boxShadow: value ? null : palette.cardShadow(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  value
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 15,
                  color: value ? palette.accent : palette.textMuted,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: DashboardType.cardTitle(
                    palette,
                    color: value ? palette.accent : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _TextChip extends StatefulWidget {
  const _TextChip({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final DashboardPalette palette;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TextChip> createState() => _TextChipState();
}

class _TextChipState extends State<_TextChip> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_TextChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Container(
      height: 32,
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(DashboardMetrics.controlRadius),
        boxShadow: palette.cardShadow(),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 15, color: palette.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: _controller,
              style: DashboardType.body(palette).copyWith(fontSize: 13),
              cursorColor: palette.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.label,
                hintStyle: DashboardType.caption(palette),
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
