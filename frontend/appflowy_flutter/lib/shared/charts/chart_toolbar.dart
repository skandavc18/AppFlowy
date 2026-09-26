import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/charts/chart_color_menu.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
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
class ChartToolbar extends StatefulWidget {
  const ChartToolbar({
    super.key,
    required this.table,
    required this.spec,
    required this.palette,
    required this.onChanged,
    this.data,
    this.compact = false,
    this.showControls = true,
    this.keepVisible = false,
    this.trailing = const [],
    this.additionalEntries = const [],
  });

  final ChartTable table;
  final ChartSpec spec;
  final ChartPalette palette;
  final ValueChanged<ChartSpec> onChanged;

  /// What is actually drawn, so the colour menu can name each series.
  final ChartData? data;
  final bool compact;
  final bool showControls;
  final bool keepVisible;

  /// Host actions share the controls' wrap, never a clipped fixed-width slot.
  final List<Widget> trailing;
  final List<AppMenuEntry> additionalEntries;

  @override
  State<ChartToolbar> createState() => _ChartToolbarState();
}

class _ChartToolbarState extends State<ChartToolbar> {
  final Set<Key> _active = {};

  ChartTable get table => widget.table;
  ChartSpec get spec => widget.spec;
  ChartPalette get palette => widget.palette;
  ChartData? get data => widget.data;
  ValueChanged<ChartSpec> get onChanged => widget.onChanged;

  void _retain(String name, bool active) {
    final key = ValueKey(name);
    if (_active.contains(key) == active) return;
    setState(() => active ? _active.add(key) : _active.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final numeric = table.numericColumns.map(table.keyOf).toList();
    final measured = spec.plotsAgainstValues;
    final controls = <ChartChip>[
      _typeChip(),
      _horizontalChip(numeric, measured),
      _verticalChip(numeric),
      if (!measured && !spec.type.drawsPoints && spec.valueColumns.isNotEmpty)
        _aggregateChip(),
      if (spec.type.sizesPoints) _sizeChip(numeric),
      if (measured || spec.type.drawsPoints) _labelChip(),
      _colorChip(),
      _optionsChip(measured),
    ];

    return PreviewToolbar(
      keepVisible:
          widget.keepVisible || table.isEmpty || (data?.isEmpty ?? false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final measure = width / MediaQuery.textScalerOf(context).scale(1);
          final count = measure >= 960 && !widget.compact
              ? controls.length - 1
              : measure >= 600
                  ? 3
                  : measure < 200 || (widget.compact && measure < 260)
                      ? 0
                      : 1;
          return Wrap(
            runSpacing: 6,
            alignment:
                widget.showControls ? WrapAlignment.start : WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var index = 0; index < controls.length; index++)
                // Key the WRAPPER too. Resize must not dispose a menu anchor
                // or transfer a focused button's state to its neighbour.
                _controlSlot(
                  controls[index],
                  width,
                  widget.showControls &&
                      (index < count || _active.contains(controls[index].key)),
                ),
              for (var index = 0; index < widget.trailing.length; index++)
                ConstrainedBox(
                  key: ValueKey(
                    ('chart-action-slot', widget.trailing[index].key ?? index),
                  ),
                  constraints: BoxConstraints(maxWidth: width),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: widget.trailing[index],
                  ),
                ),
              // Always retain this anchor, even when a resize can expose all
              // the controls. Its submenus also make compact charts complete.
              ConstrainedBox(
                key: const ValueKey('chart-more-slot'),
                constraints: BoxConstraints(maxWidth: width),
                child: ChartChip(
                  key: const ValueKey('chart-more-controls'),
                  icon: Icons.more_horiz_rounded,
                  label: LocaleKeys.document_plugins_optionAction_more.tr(),
                  palette: palette,
                  showChevron: false,
                  entries: [
                    for (final control in controls)
                      AppMenuItem(
                        label: control.caption ?? control.label,
                        subtitle:
                            control.caption == null ? null : control.label,
                        icon: control.icon,
                        iconWidget: control.swatch == null
                            ? null
                            : Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: control.swatch,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                        submenu: control.entries,
                      ),
                    if (widget.additionalEntries.isNotEmpty) ...[
                      const AppMenuSeparator(),
                      ...widget.additionalEntries,
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _controlSlot(ChartChip control, double width, bool visible) =>
      Visibility(
        key: ValueKey(('chart-control-slot', control.key)),
        visible: visible,
        maintainState: true,
        child: ExcludeFocus(
          excluding: !visible,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: control,
            ),
          ),
        ),
      );

  ChartChip _colorChip() => ChartChip(
        key: const ValueKey('chart-colors'),
        onActiveChanged: (value) => _retain('chart-colors', value),
        icon: Icons.palette_outlined,
        label: chartPaletteLabel(spec.palette),
        caption: LocaleKeys.charts_colors.tr(),
        palette: palette,
        swatch: ChartColors.of(palette, spec).at(
          0,
          _firstColorName,
        ),
        entries: chartColorEntries(
          spec: spec,
          data: data ?? ChartData.empty,
          palette: palette,
          onChanged: onChanged,
        ),
      );

  String get _firstColorName {
    final series = data?.series;
    if (series == null || series.isEmpty) return '';
    final first = series.first;
    return spec.type.isCircular
        ? first.points.isEmpty
            ? ''
            : first.points.first.label
        : first.name;
  }

  ChartChip _typeChip() => ChartChip(
        key: const ValueKey('chart-type'),
        onActiveChanged: (value) => _retain('chart-type', value),
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
          .map(table.keyOf)
          .where((column) => !next.valueColumns.contains(column))
          .toList();
      if (numeric.isNotEmpty) {
        next = next.copyWith(xColumn: numeric.first);
      }
    }
    return next;
  }

  /// The axis that runs across the plot: names, or numbers.
  ChartChip _horizontalChip(List<String> numeric, bool measured) {
    final canMeasure = spec.type.supportsValueAxis;
    return ChartChip(
      key: const ValueKey('chart-horizontal-column'),
      onActiveChanged: (value) => _retain('chart-horizontal-column', value),
      icon: spec.type.isHorizontal
          ? Icons.swap_vert_rounded
          : Icons.swap_horiz_rounded,
      label: measured
          ? table.nameOf(spec.xColumn!)
          : spec.type.drawsPoints
              ? LocaleKeys.charts_pickColumn.tr()
              : spec.categoryColumn == null
                  ? LocaleKeys.charts_everyRow.tr()
                  : table.nameOf(spec.categoryColumn!),
      caption: spec.type.isCircular
          ? LocaleKeys.charts_groupBy.tr()
          : LocaleKeys.charts_xAxis.tr(),
      palette: palette,
      entries: [
        if (canMeasure && numeric.isNotEmpty) ...[
          AppMenuHeader(LocaleKeys.charts_xAxis.tr()),
          for (final column in numeric)
            AppMenuItem(
              label: table.nameOf(column),
              icon: Icons.trending_up_rounded,
              selected: measured && column == spec.xColumn,
              onSelected: () => onChanged(spec.copyWith(xColumn: column)),
            ),
          const AppMenuSeparator(),
        ],
        if (spec.type.drawsPoints && numeric.isEmpty)
          AppMenuItem(
            label: LocaleKeys.charts_noNumericColumns.tr(),
            enabled: false,
          ),
        // A point chart requires numeric X/Y. Its separate label control can
        // name points; offering categorical grouping here used to do nothing.
        if (!spec.type.drawsPoints) ...[
          AppMenuHeader(LocaleKeys.charts_groupBy.tr()),
          AppMenuItem(
            label: LocaleKeys.charts_everyRow.tr(),
            icon: Icons.table_rows_rounded,
            selected: !measured && spec.categoryColumn == null,
            onSelected: () =>
                onChanged(spec.copyWith(clearCategory: true, clearX: true)),
          ),
          for (final column in table.columnKeys)
            AppMenuItem(
              label: table.nameOf(column),
              icon: Icons.label_outline_rounded,
              selected: !measured && column == spec.categoryColumn,
              onSelected: () => onChanged(
                spec.copyWith(categoryColumn: column, clearX: true),
              ),
            ),
        ],
      ],
    );
  }

  /// The numbers themselves. Several columns can be plotted at once.
  ChartChip _verticalChip(List<String> numeric) => ChartChip(
        key: const ValueKey('chart-value-columns'),
        onActiveChanged: (value) => _retain('chart-value-columns', value),
        icon: Icons.stacked_line_chart_rounded,
        label: spec.valueColumns.isEmpty
            ? (spec.plotsAgainstValues || spec.type.drawsPoints
                ? LocaleKeys.charts_pickColumn.tr()
                : LocaleKeys.charts_countRows.tr())
            : spec.valueColumns.map(table.nameOf).join(', '),
        caption: LocaleKeys.charts_yAxis.tr(),
        palette: palette,
        entries: [
          if (!spec.plotsAgainstValues && !spec.type.drawsPoints)
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
              label: table.nameOf(column),
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

  ChartChip _aggregateChip() => ChartChip(
        key: const ValueKey('chart-aggregate'),
        onActiveChanged: (value) => _retain('chart-aggregate', value),
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

  ChartChip _sizeChip(List<String> numeric) => ChartChip(
        key: const ValueKey('chart-size-column'),
        onActiveChanged: (value) => _retain('chart-size-column', value),
        icon: Icons.blur_circular_rounded,
        label: spec.sizeColumn == null
            ? LocaleKeys.charts_noSize.tr()
            : table.nameOf(spec.sizeColumn!),
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
              label: table.nameOf(column),
              icon: Icons.numbers_rounded,
              selected: column == spec.sizeColumn,
              onSelected: () => onChanged(spec.copyWith(sizeColumn: column)),
            ),
        ],
      );

  /// What names a point when the axes both carry numbers.
  ChartChip _labelChip() => ChartChip(
        key: const ValueKey('chart-label-column'),
        onActiveChanged: (value) => _retain('chart-label-column', value),
        icon: Icons.label_outline_rounded,
        label: spec.categoryColumn == null
            ? LocaleKeys.charts_everyRow.tr()
            : table.nameOf(spec.categoryColumn!),
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
          for (final column in table.columnKeys)
            AppMenuItem(
              label: table.nameOf(column),
              icon: Icons.label_outline_rounded,
              selected: column == spec.categoryColumn,
              onSelected: () =>
                  onChanged(spec.copyWith(categoryColumn: column)),
            ),
        ],
      );

  ChartChip _optionsChip(bool measured) => ChartChip(
        key: const ValueKey('chart-display'),
        onActiveChanged: (value) => _retain('chart-display', value),
        icon: Icons.tune_rounded,
        label: LocaleKeys.charts_display.tr(),
        palette: palette,
        showChevron: false,
        entries: [
          if (!measured && !spec.type.drawsPoints) ...[
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
    this.onActiveChanged,
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
  final ValueChanged<bool>? onActiveChanged;

  @override
  State<ChartChip> createState() => _ChartChipState();
}

class _ChartChipState extends State<ChartChip> {
  final GlobalKey _anchor = GlobalKey();
  bool _hovered = false;
  bool _open = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final lit = _hovered || _open || _focused;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TextButton(
        key: _anchor,
        onPressed: _openMenu,
        onFocusChange: (value) {
          setState(() => _focused = value);
          widget.onActiveChanged?.call(_focused || _open);
        },
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: palette.strongLabel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChartMetrics.chipRadius),
          ),
        ).copyWith(
          animationDuration:
              WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
        ),
        child: Tooltip(
          message:
              [widget.caption, widget.label].whereType<String>().join(': '),
          excludeFromSemantics: true,
          child: AnimatedContainer(
            duration:
                WorkspaceTokens.motion(context, ChartMetrics.hoverDuration),
            curve: ChartMetrics.hoverCurve,
            constraints:
                const BoxConstraints(minHeight: ChartMetrics.chipHeight),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: palette.chipHover
                  .withValues(alpha: lit ? palette.chipHover.a : 0),
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
                  WorkspaceGlyph(
                    widget.icon,
                    size: 16,
                    color: palette.label,
                  ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (widget.caption != null)
                          TextSpan(
                            text: '${widget.caption!}  ',
                            style: palette.text(size: 11, color: palette.label),
                          ),
                        TextSpan(text: widget.label),
                      ],
                    ),
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
                  WorkspaceGlyph(
                    Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: palette.label,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu() async {
    if (_open) return;
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    setState(() => _open = true);
    widget.onActiveChanged?.call(true);
    try {
      await showAppMenu<void>(
        context: context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        placement: AppMenuPlacement.below,
        entries: widget.entries,
      );
    } finally {
      if (mounted) {
        setState(() => _open = false);
        widget.onActiveChanged?.call(_focused);
      }
    }
  }
}
