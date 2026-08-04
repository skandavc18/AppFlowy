import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/charts/chart_color_menu.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

String chartTypeLabel(ChartType type) => switch (type) {
      ChartType.bar => LocaleKeys.charts_bar.tr(),
      ChartType.horizontalBar => LocaleKeys.charts_horizontalBar.tr(),
      ChartType.stackedBar => LocaleKeys.charts_stackedBar.tr(),
      ChartType.line => LocaleKeys.charts_line.tr(),
      ChartType.area => LocaleKeys.charts_area.tr(),
      ChartType.stackedArea => LocaleKeys.charts_stackedArea.tr(),
      ChartType.pie => LocaleKeys.charts_pie.tr(),
      ChartType.donut => LocaleKeys.charts_donut.tr(),
      ChartType.scatter => LocaleKeys.charts_scatter.tr(),
      ChartType.bubble => LocaleKeys.charts_bubble.tr(),
    };

IconData chartTypeIcon(ChartType type) => switch (type) {
      ChartType.bar => Icons.bar_chart_rounded,
      ChartType.horizontalBar => Icons.align_horizontal_left_rounded,
      ChartType.stackedBar => Icons.stacked_bar_chart_rounded,
      ChartType.line => Icons.show_chart_rounded,
      ChartType.area => Icons.area_chart_rounded,
      ChartType.stackedArea => Icons.layers_rounded,
      ChartType.pie => Icons.pie_chart_rounded,
      ChartType.donut => Icons.donut_large_rounded,
      ChartType.scatter => Icons.scatter_plot_rounded,
      ChartType.bubble => Icons.bubble_chart_rounded,
    };

String chartAggregateLabel(ChartAggregate aggregate) => switch (aggregate) {
      ChartAggregate.sum => LocaleKeys.charts_sum.tr(),
      ChartAggregate.average => LocaleKeys.charts_average.tr(),
      ChartAggregate.count => LocaleKeys.charts_count.tr(),
      ChartAggregate.min => LocaleKeys.charts_min.tr(),
      ChartAggregate.max => LocaleKeys.charts_max.tr(),
      ChartAggregate.median => LocaleKeys.charts_median.tr(),
    };

String chartSortLabel(ChartSort sort) => switch (sort) {
      ChartSort.natural => LocaleKeys.charts_sortNatural.tr(),
      ChartSort.labelAscending => LocaleKeys.charts_sortLabel.tr(),
      ChartSort.valueDescending => LocaleKeys.charts_sortValueDown.tr(),
      ChartSort.valueAscending => LocaleKeys.charts_sortValueUp.tr(),
    };

/// The controls that say what a chart shows.
///
/// Shared by the collection view, the standalone chart page, the database tab
/// and the block, so a chart is configured the same way wherever it is drawn.
class ChartToolbar extends StatelessWidget {
  const ChartToolbar({
    super.key,
    required this.table,
    required this.spec,
    required this.palette,
    required this.onChanged,
    this.data,
    this.compact = false,
  });

  final ChartTable table;
  final ChartSpec spec;
  final ChartPalette palette;
  final ValueChanged<ChartSpec> onChanged;

  /// What is actually drawn, so the colour menu can name each series.
  final ChartData? data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final numeric = table.numericColumns;
    final measured = spec.plotsAgainstValues;

    return Wrap(
      spacing: 6,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _typeChip(),
        _horizontalChip(numeric, measured),
        _verticalChip(numeric),
        if (!measured && spec.valueColumns.isNotEmpty) _aggregateChip(),
        if (spec.type.sizesPoints) _sizeChip(numeric),
        if (measured && spec.categoryColumn != null) _labelChip(),
        _colorChip(),
        if (!compact) _optionsChip(measured),
      ],
    );
  }

  Widget _colorChip() => ChartChip(
        icon: Icons.palette_outlined,
        label: chartPaletteLabel(spec.palette),
        caption: LocaleKeys.charts_colors.tr(),
        palette: palette,
        swatch: ChartColors.of(palette, spec).at(
          0,
          data?.series.isNotEmpty ?? false ? data!.series.first.name : '',
        ),
        entries: chartColorEntries(
          spec: spec,
          data: data ?? ChartData.empty,
          palette: palette,
          onChanged: onChanged,
        ),
      );

  Widget _typeChip() => ChartChip(
        icon: chartTypeIcon(spec.type),
        label: chartTypeLabel(spec.type),
        caption: LocaleKeys.charts_chartType.tr(),
        palette: palette,
        entries: [
          for (final group in _typeGroups) ...[
            if (group != _typeGroups.first) const AppMenuSeparator(),
            for (final type in group)
              AppMenuItem(
                label: chartTypeLabel(type),
                icon: chartTypeIcon(type),
                selected: type == spec.type,
                onSelected: () => onChanged(_switchType(type)),
              ),
          ],
        ],
      );

  static const _typeGroups = [
    [ChartType.bar, ChartType.horizontalBar, ChartType.stackedBar],
    [ChartType.line, ChartType.area, ChartType.stackedArea],
    [ChartType.scatter, ChartType.bubble],
    [ChartType.pie, ChartType.donut],
  ];

  /// Changing type keeps whatever still makes sense and drops what does not.
  ChartSpec _switchType(ChartType type) {
    var next = spec.copyWith(type: type);
    if (!type.supportsValueAxis) {
      next = next.copyWith(clearX: true);
    }
    if (!type.sizesPoints) {
      next = next.copyWith(clearSize: true);
    }
    if (type.drawsPoints && next.xColumn == null) {
      // A scatter with no measured axis has nothing to plot against.
      final numeric = table.numericColumns
          .where((column) => !next.valueColumns.contains(column))
          .toList();
      if (numeric.isNotEmpty) {
        next = next.copyWith(xColumn: numeric.first);
      }
    }
    return next;
  }

  /// The axis that runs across the plot: names, or numbers.
  Widget _horizontalChip(List<String> numeric, bool measured) {
    final canMeasure = spec.type.supportsValueAxis;
    return ChartChip(
      icon: spec.type.isHorizontal
          ? Icons.swap_vert_rounded
          : Icons.swap_horiz_rounded,
      label: measured
          ? spec.xColumn!
          : spec.categoryColumn ?? LocaleKeys.charts_everyRow.tr(),
      caption: spec.type.isCircular
          ? LocaleKeys.charts_groupBy.tr()
          : LocaleKeys.charts_xAxis.tr(),
      palette: palette,
      entries: [
        if (canMeasure && numeric.isNotEmpty) ...[
          AppMenuHeader(LocaleKeys.charts_xAxis.tr()),
          for (final column in numeric)
            AppMenuItem(
              label: column,
              icon: Icons.trending_up_rounded,
              selected: measured && column == spec.xColumn,
              onSelected: () => onChanged(spec.copyWith(xColumn: column)),
            ),
          const AppMenuSeparator(),
        ],
        AppMenuHeader(LocaleKeys.charts_groupBy.tr()),
        AppMenuItem(
          label: LocaleKeys.charts_everyRow.tr(),
          icon: Icons.table_rows_rounded,
          selected: !measured && spec.categoryColumn == null,
          onSelected: () =>
              onChanged(spec.copyWith(clearCategory: true, clearX: true)),
        ),
        for (final column in table.columns)
          AppMenuItem(
            label: column,
            icon: Icons.label_outline_rounded,
            selected: !measured && column == spec.categoryColumn,
            onSelected: () => onChanged(
              spec.copyWith(categoryColumn: column, clearX: true),
            ),
          ),
      ],
    );
  }

  /// The numbers themselves. Several columns can be plotted at once.
  Widget _verticalChip(List<String> numeric) => ChartChip(
        icon: Icons.stacked_line_chart_rounded,
        label: spec.valueColumns.isEmpty
            ? LocaleKeys.charts_countRows.tr()
            : spec.valueColumns.join(', '),
        caption: LocaleKeys.charts_yAxis.tr(),
        palette: palette,
        entries: [
          if (!spec.plotsAgainstValues)
            AppMenuItem(
              label: LocaleKeys.charts_countRows.tr(),
              icon: Icons.tag_rounded,
              selected: spec.valueColumns.isEmpty,
              onSelected: () =>
                  onChanged(spec.copyWith(valueColumns: const [])),
            ),
          if (numeric.isNotEmpty) const AppMenuSeparator(),
          for (final column in numeric)
            AppMenuItem(
              label: column,
              icon: Icons.numbers_rounded,
              selected: spec.valueColumns.contains(column),
              onSelected: () => onChanged(
                spec.copyWith(
                  valueColumns: spec.valueColumns.contains(column)
                      ? spec.valueColumns
                          .where((value) => value != column)
                          .toList()
                      : [...spec.valueColumns, column],
                ),
              ),
            ),
          if (numeric.isEmpty)
            AppMenuItem(
              label: LocaleKeys.charts_noNumericColumns.tr(),
              enabled: false,
            ),
        ],
      );

  Widget _aggregateChip() => ChartChip(
        icon: Icons.functions_rounded,
        label: chartAggregateLabel(spec.aggregate),
        caption: LocaleKeys.charts_count.tr(),
        palette: palette,
        entries: [
          for (final aggregate in ChartAggregate.values)
            AppMenuItem(
              label: chartAggregateLabel(aggregate),
              selected: aggregate == spec.aggregate,
              onSelected: () => onChanged(spec.copyWith(aggregate: aggregate)),
            ),
        ],
      );

  Widget _sizeChip(List<String> numeric) => ChartChip(
        icon: Icons.blur_circular_rounded,
        label: spec.sizeColumn ?? LocaleKeys.charts_noSize.tr(),
        caption: LocaleKeys.charts_bubbleSize.tr(),
        palette: palette,
        entries: [
          AppMenuItem(
            label: LocaleKeys.charts_noSize.tr(),
            icon: Icons.circle_outlined,
            selected: spec.sizeColumn == null,
            onSelected: () => onChanged(spec.copyWith(clearSize: true)),
          ),
          if (numeric.isNotEmpty) const AppMenuSeparator(),
          for (final column in numeric)
            AppMenuItem(
              label: column,
              icon: Icons.numbers_rounded,
              selected: column == spec.sizeColumn,
              onSelected: () => onChanged(spec.copyWith(sizeColumn: column)),
            ),
        ],
      );

  /// What names a point when the axes both carry numbers.
  Widget _labelChip() => ChartChip(
        icon: Icons.label_outline_rounded,
        label: spec.categoryColumn!,
        caption: LocaleKeys.charts_pickColumn.tr(),
        palette: palette,
        entries: [
          AppMenuItem(
            label: LocaleKeys.charts_everyRow.tr(),
            icon: Icons.table_rows_rounded,
            selected: spec.categoryColumn == null,
            onSelected: () => onChanged(spec.copyWith(clearCategory: true)),
          ),
          const AppMenuSeparator(),
          for (final column in table.columns)
            AppMenuItem(
              label: column,
              icon: Icons.label_outline_rounded,
              selected: column == spec.categoryColumn,
              onSelected: () =>
                  onChanged(spec.copyWith(categoryColumn: column)),
            ),
        ],
      );

  Widget _optionsChip(bool measured) => ChartChip(
        icon: Icons.tune_rounded,
        label: LocaleKeys.charts_display.tr(),
        palette: palette,
        showChevron: false,
        entries: [
          if (!measured) ...[
            AppMenuHeader(LocaleKeys.charts_sortBy.tr()),
            for (final sort in ChartSort.values)
              AppMenuItem(
                label: chartSortLabel(sort),
                selected: sort == spec.sort,
                onSelected: () => onChanged(spec.copyWith(sort: sort)),
              ),
            const AppMenuSeparator(),
          ],
          AppMenuHeader(LocaleKeys.charts_display.tr()),
          _toggle(
            LocaleKeys.charts_showLegend.tr(),
            spec.showLegend,
            () => onChanged(spec.copyWith(showLegend: !spec.showLegend)),
          ),
          _toggle(
            LocaleKeys.charts_showValues.tr(),
            spec.showValues,
            () => onChanged(spec.copyWith(showValues: !spec.showValues)),
          ),
          _toggle(
            LocaleKeys.charts_showGrid.tr(),
            spec.showGrid,
            () => onChanged(spec.copyWith(showGrid: !spec.showGrid)),
          ),
        ],
      );

  AppMenuItem _toggle(String label, bool on, VoidCallback onSelected) =>
      AppMenuItem(
        label: label,
        icon: on
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded,
        onSelected: onSelected,
      );
}

/// One control in a chart's header.
class ChartChip extends StatefulWidget {
  const ChartChip({
    super.key,
    required this.icon,
    required this.label,
    required this.palette,
    required this.entries,
    this.caption,
    this.showChevron = true,
    this.swatch,
  });

  final IconData icon;
  final String label;

  /// What the control sets, shown before its value.
  final String? caption;
  final ChartPalette palette;
  final List<AppMenuEntry> entries;
  final bool showChevron;

  /// Shown in place of the icon, for a control that sets a colour.
  final Color? swatch;

  @override
  State<ChartChip> createState() => _ChartChipState();
}

class _ChartChipState extends State<ChartChip> {
  final GlobalKey _anchor = GlobalKey();
  bool _hovered = false;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final lit = _hovered || _open;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: _anchor,
        onTap: _openMenu,
        child: AnimatedContainer(
          duration: ChartMetrics.hoverDuration,
          curve: ChartMetrics.hoverCurve,
          height: ChartMetrics.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: lit ? palette.chipHover : palette.chip,
            borderRadius: BorderRadius.circular(ChartMetrics.chipRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.swatch != null)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: widget.swatch,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )
              else
                Icon(
                  widget.icon,
                  size: 13.5,
                  color: lit ? palette.strongLabel : palette.label,
                ),
              const SizedBox(width: 6),
              if (widget.caption != null) ...[
                Text(
                  widget.caption!,
                  style: palette.text(size: 11, color: palette.label),
                ),
                const SizedBox(width: 5),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.text(
                    size: 11.5,
                    color: palette.strongLabel,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.showChevron) ...[
                const SizedBox(width: 3),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: palette.label,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu() async {
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    setState(() => _open = true);
    await showAppMenu<void>(
      context: context,
      globalPosition: box.localToGlobal(
        box.size.bottomLeft(const Offset(0, 5)),
      ),
      entries: widget.entries,
    );
    if (mounted) {
      setState(() => _open = false);
    }
  }
}
