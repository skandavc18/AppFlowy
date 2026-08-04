import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/type_option/rollup_cubit.dart';
import 'package:appflowy/plugins/database/application/field/type_option/rollup_entities.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Lets a text column be filled in from the rows a relation points at.
///
/// The column stays a text column throughout — this only records which
/// relation to follow, what to read on the far side, and how to boil the
/// values down to one line.
class RollupEditor extends StatelessWidget {
  const RollupEditor({
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
    return BlocProvider(
      create: (_) => RollupCubit(viewId: viewId, fieldId: fieldId),
      child: BlocBuilder<RollupCubit, RollupState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const SizedBox.shrink();
          }

          final cubit = context.read<RollupCubit>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Label(LocaleKeys.grid_rollup_label.tr()),
              _Picker(
                popoverMutex: popoverMutex,
                value: state.relation?.name,
                placeholder: state.relations.isEmpty
                    ? LocaleKeys.grid_rollup_noRelations.tr()
                    : LocaleKeys.grid_rollup_relationPlaceholder.tr(),
                enabled: state.relations.isNotEmpty,
                popupBuilder: (_) => _FieldList(
                  fields: state.relations,
                  selectedId: state.relationFieldId,
                  onSelected: (field) {
                    cubit.selectRelation(field.id);
                    PopoverContainer.of(context).close();
                  },
                ),
              ),
              if (state.relationFieldId.isNotEmpty) ...[
                _Label(LocaleKeys.grid_rollup_propertyLabel.tr()),
                _Picker(
                  popoverMutex: popoverMutex,
                  value: state.target?.name,
                  placeholder: state.targets.isEmpty
                      ? LocaleKeys.grid_rollup_noProperties.tr()
                      : LocaleKeys.grid_rollup_propertyPlaceholder.tr(),
                  enabled: state.targets.isNotEmpty,
                  popupBuilder: (_) => _FieldList(
                    fields: state.targets,
                    selectedId: state.targetFieldId,
                    onSelected: (field) {
                      cubit.selectTarget(field.id);
                      PopoverContainer.of(context).close();
                    },
                  ),
                ),
              ],
              if (state.isConfigured) ...[
                _Label(LocaleKeys.grid_rollup_calculateLabel.tr()),
                _Picker(
                  popoverMutex: popoverMutex,
                  value: state.aggregation.label,
                  placeholder: state.aggregation.label,
                  popupBuilder: (_) => _AggregationList(
                    selected: state.aggregation,
                    onSelected: (aggregation) {
                      cubit.selectAggregation(aggregation);
                      PopoverContainer.of(context).close();
                    },
                  ),
                ),
                _Action(
                  icon: FlowySvgs.restore_s,
                  label: LocaleKeys.grid_rollup_recalculate.tr(),
                  onTap: cubit.recalculate,
                ),
                _Action(
                  icon: FlowySvgs.delete_s,
                  label: LocaleKeys.grid_rollup_clear.tr(),
                  onTap: cubit.clear,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 8),
      height: GridSize.popoverItemHeight,
      alignment: Alignment.centerLeft,
      child: FlowyText.regular(
        text,
        color: Theme.of(context).hintColor,
        fontSize: 11,
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.popoverMutex,
    required this.value,
    required this.placeholder,
    required this.popupBuilder,
    this.enabled = true,
  });

  final PopoverMutex popoverMutex;
  final String? value;
  final String placeholder;
  final Widget Function(BuildContext) popupBuilder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: GridSize.popoverItemHeight,
      child: FlowyButton(
        text: FlowyText(
          lineHeight: 1.0,
          value ?? placeholder,
          color: value == null ? Theme.of(context).hintColor : null,
          overflow: TextOverflow.ellipsis,
        ),
        rightIcon: enabled ? const FlowySvg(FlowySvgs.more_s) : null,
      ),
    );

    if (!enabled) {
      return button;
    }

    return AppFlowyPopover(
      mutex: popoverMutex,
      triggerActions: PopoverTriggerFlags.hover | PopoverTriggerFlags.click,
      offset: const Offset(6, 0),
      constraints: const BoxConstraints(maxWidth: 260, maxHeight: 360),
      popupBuilder: popupBuilder,
      child: button,
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final FlowySvgData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: GridSize.popoverItemHeight,
      child: FlowyButton(
        leftIcon: FlowySvg(icon),
        text: FlowyText(lineHeight: 1.0, label),
        onTap: onTap,
      ),
    );
  }
}

class _FieldList extends StatelessWidget {
  const _FieldList({
    required this.fields,
    required this.selectedId,
    required this.onSelected,
  });

  final List<FieldPB> fields;
  final String selectedId;
  final void Function(FieldPB field) onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      separatorBuilder: (_, __) => VSpace(GridSize.typeOptionSeparatorHeight),
      itemCount: fields.length,
      itemBuilder: (context, index) {
        final field = fields[index];
        return SizedBox(
          height: GridSize.popoverItemHeight,
          child: FlowyButton(
            onTap: () => onSelected(field),
            text: FlowyText(
              lineHeight: 1.0,
              field.name,
              overflow: TextOverflow.ellipsis,
            ),
            rightIcon: field.id == selectedId
                ? const FlowySvg(FlowySvgs.check_s)
                : null,
          ),
        );
      },
    );
  }
}

class _AggregationList extends StatelessWidget {
  const _AggregationList({
    required this.selected,
    required this.onSelected,
  });

  final RollupAggregation selected;
  final void Function(RollupAggregation aggregation) onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      separatorBuilder: (_, __) => VSpace(GridSize.typeOptionSeparatorHeight),
      itemCount: RollupAggregation.values.length,
      itemBuilder: (context, index) {
        final aggregation = RollupAggregation.values[index];
        return SizedBox(
          height: GridSize.popoverItemHeight,
          child: FlowyButton(
            onTap: () => onSelected(aggregation),
            text: FlowyText(
              lineHeight: 1.0,
              aggregation.label,
              overflow: TextOverflow.ellipsis,
            ),
            rightIcon: aggregation == selected
                ? const FlowySvg(FlowySvgs.check_s)
                : null,
          ),
        );
      },
    );
  }
}
