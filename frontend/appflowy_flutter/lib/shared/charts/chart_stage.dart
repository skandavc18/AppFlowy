import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/charts/chart_toolbar.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'package:appflowy/shared/charts/chart_style.dart' show chartPaletteOf;

/// A chart over one table: the controls, the plot, and the numbers behind it.
///
/// The data is always the table's own — the chart holds no copy of it, so it
/// is never out of step with the rows someone is editing.
class ChartStage extends StatefulWidget {
  const ChartStage({
    super.key,
    required this.viewId,
    required this.spec,
    required this.onSpecChanged,
    this.title,
    this.background,
    this.showToolbar = true,
    this.compactToolbar = false,
    this.framed = true,
    this.trailing = const [],
    this.padding = const EdgeInsets.all(16),
  });

  final String viewId;
  final ChartSpec spec;
  final ValueChanged<ChartSpec> onSpecChanged;

  /// What the chart is called, shown at the head of the card.
  final String? title;
  final Color? background;
  final bool showToolbar;
  final bool compactToolbar;

  /// Whether the chart draws its own card. A host that already supplies one
  /// turns this off.
  final bool framed;
  final List<Widget> trailing;
  final EdgeInsets padding;

  @override
  State<ChartStage> createState() => ChartStageState();
}

class ChartStageState extends State<ChartStage> {
  late ChartSource _source = ChartSource(viewId: widget.viewId);

  @override
  void initState() {
    super.initState();
    _source.addListener(_onChanged);
    unawaited(_source.load());
  }

  @override
  void didUpdateWidget(covariant ChartStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId) {
      _source
        ..removeListener(_onChanged)
        ..dispose();
      _source = ChartSource(viewId: widget.viewId)..addListener(_onChanged);
      unawaited(_source.load());
    }
  }

  @override
  void dispose() {
    _source
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Reads the table again, for a host that knows it has changed.
  Future<void> reload() => _source.load();

  @override
  Widget build(BuildContext context) {
    final palette = chartPaletteOf(context, background: widget.background);
    final table = _source.table;
    final spec = _resolve(widget.spec, table);
    final data = buildChartData(table, spec);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToolbar) ...[
          _Header(
            title: widget.title,
            palette: palette,
            table: table,
            spec: spec,
            data: data,
            compact: widget.compactToolbar,
            onChanged: widget.onSpecChanged,
            onRefresh: reload,
            onExport: () => _copyNumbers(context, table, data, spec),
            busy: _source.isLoading,
            trailing: widget.trailing,
          ),
          SizedBox(
            height: spec.showControls
                ? ChartMetrics.plotGap
                : ChartMetrics.headerGap,
          ),
        ],
        Expanded(child: _body(palette, table, spec, data)),
      ],
    );

    if (!widget.framed) {
      return Padding(padding: widget.padding, child: body);
    }
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(ChartMetrics.cardRadius),
        border: Border.all(color: palette.border),
        boxShadow: chartCardShadow(palette),
      ),
      padding: widget.padding,
      child: body,
    );
  }

  Widget _body(
    ChartPalette palette,
    ChartTable table,
    ChartSpec spec,
    ChartData data,
  ) {
    if (_source.isLoading && table.isEmpty) {
      return _ChartSkeleton(palette: palette);
    }
    final error = _source.error;
    if (error != null) {
      return ChartEmptyState(
        palette: palette,
        icon: Icons.error_outline_rounded,
        title: LocaleKeys.charts_empty.tr(),
        message: error,
      );
    }
    if (table.isEmpty || data.isEmpty) {
      return ChartEmptyState(
        palette: palette,
        icon: Icons.insert_chart_outlined_rounded,
        title: LocaleKeys.charts_empty.tr(),
        message: LocaleKeys.charts_emptyDescription.tr(),
      );
    }

    return AnimatedSwitcher(
      duration: ChartMetrics.morphDuration,
      switchInCurve: ChartMetrics.revealCurve,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: AppChart(
        // A new type is a new drawing, so it arrives rather than mutating.
        key: ValueKey(spec.type),
        data: data,
        spec: spec,
        palette: palette,
      ),
    );
  }

  Future<void> _copyNumbers(
    BuildContext context,
    ChartTable table,
    ChartData data,
    ChartSpec spec,
  ) async {
    final rows = <String>[
      [spec.xAxisLabel ?? '', ...data.series.map((one) => one.name)].join(','),
      for (var index = 0; index < data.categories.length; index++)
        [
          data.categories[index],
          for (final series in data.series)
            index < series.points.length
                ? series.points[index].value.toString()
                : '',
        ].join(','),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
  }

  /// Fills in a chart that has never been configured, so opening one shows
  /// something rather than an empty frame.
  ChartSpec _resolve(ChartSpec spec, ChartTable table) {
    if (table.isEmpty) {
      return spec;
    }
    var resolved = spec;
    final numeric = table.numericColumns;

    if (resolved.plotsAgainstValues &&
        !table.columns.contains(resolved.xColumn)) {
      resolved = resolved.copyWith(clearX: true);
    }
    if (!resolved.plotsAgainstValues &&
        (resolved.categoryColumn == null ||
            !table.columns.contains(resolved.categoryColumn))) {
      final names = numeric.toSet();
      resolved = resolved.copyWith(
        categoryColumn: table.columns.firstWhere(
          (column) => !names.contains(column),
          orElse: () => table.columns.first,
        ),
      );
    }
    if (resolved.valueColumns.isEmpty) {
      final free = numeric
          .where(
            (column) =>
                column != resolved.categoryColumn && column != resolved.xColumn,
          )
          .toList();
      if (free.isNotEmpty) {
        resolved = resolved.copyWith(valueColumns: [free.first]);
      }
    }
    // A scatter has nothing to say without a measured axis.
    if (resolved.type.drawsPoints && resolved.xColumn == null) {
      final free = numeric
          .where((column) => !resolved.valueColumns.contains(column))
          .toList();
      if (free.isNotEmpty) {
        resolved = resolved.copyWith(xColumn: free.first);
      }
    }
    return resolved;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.palette,
    required this.table,
    required this.spec,
    required this.data,
    required this.compact,
    required this.onChanged,
    required this.onRefresh,
    required this.onExport,
    required this.busy,
    required this.trailing,
  });

  final String? title;
  final ChartPalette palette;
  final ChartTable table;
  final ChartSpec spec;
  final ChartData data;
  final bool compact;
  final ValueChanged<ChartSpec> onChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback onExport;
  final bool busy;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title != null && title!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasTitle)
          Row(
            children: [
              Expanded(
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.text(
                    size: 15,
                    color: palette.strongLabel,
                    weight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              _actions(context),
            ],
          )
        else if (!spec.showControls)
          // Without a title there is nothing to sit beside, so the actions
          // hold the row on their own.
          Align(alignment: Alignment.centerRight, child: _actions(context)),
        if (spec.showControls) ...[
          if (hasTitle) const SizedBox(height: ChartMetrics.headerGap + 2),
          _controls(context, withActions: !hasTitle),
        ],
      ],
    );
  }

  Widget _controls(BuildContext context, {required bool withActions}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ChartToolbar(
              table: table,
              spec: spec,
              data: data,
              palette: palette,
              compact: compact,
              onChanged: onChanged,
            ),
          ),
          if (withActions) ...[
            const SizedBox(width: 12),
            _actions(context),
          ],
        ],
      );

  Widget _actions(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...trailing,
          if (trailing.isNotEmpty) const SizedBox(width: 4),
          ChartIconAction(
            icon: Icons.refresh_rounded,
            tooltip: LocaleKeys.charts_refresh.tr(),
            palette: palette,
            busy: busy,
            onTap: onRefresh,
          ),
          const SizedBox(width: 2),
          ChartIconAction(
            icon: Icons.more_horiz_rounded,
            tooltip: LocaleKeys.charts_options.tr(),
            palette: palette,
            onTap: () => showAppMenuForWidget<void>(
              context: context,
              width: 232,
              offset: const Offset(0, 4),
              entries: [
                AppMenuItem(
                  label: LocaleKeys.charts_showOptions.tr(),
                  icon: Icons.tune_rounded,
                  selected: spec.showControls,
                  onSelected: () => onChanged(
                    spec.copyWith(showControls: !spec.showControls),
                  ),
                ),
                const AppMenuSeparator(),
                AppMenuHeader(LocaleKeys.charts_display.tr()),
                // With the controls put away these are the only way to reach
                // what the chart shows.
                AppMenuItem(
                  label: LocaleKeys.charts_showLegend.tr(),
                  icon: Icons.legend_toggle_rounded,
                  selected: spec.showLegend,
                  onSelected: () =>
                      onChanged(spec.copyWith(showLegend: !spec.showLegend)),
                ),
                AppMenuItem(
                  label: LocaleKeys.charts_showValues.tr(),
                  icon: Icons.numbers_rounded,
                  selected: spec.showValues,
                  onSelected: () =>
                      onChanged(spec.copyWith(showValues: !spec.showValues)),
                ),
                AppMenuItem(
                  label: LocaleKeys.charts_showGrid.tr(),
                  icon: Icons.grid_on_rounded,
                  selected: spec.showGrid,
                  onSelected: () =>
                      onChanged(spec.copyWith(showGrid: !spec.showGrid)),
                ),
                const AppMenuSeparator(),
                AppMenuItem(
                  label: LocaleKeys.charts_refresh.tr(),
                  icon: Icons.refresh_rounded,
                  onSelected: () => unawaited(onRefresh()),
                ),
                AppMenuItem(
                  label: LocaleKeys.charts_export.tr(),
                  icon: Icons.download_rounded,
                  onSelected: onExport,
                ),
              ],
            ),
          ),
        ],
      );
}

/// A quiet square button in a chart's header.
class ChartIconAction extends StatefulWidget {
  const ChartIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final ChartPalette palette;
  final FutureOr<void> Function() onTap;
  final bool busy;

  @override
  State<ChartIconAction> createState() => _ChartIconActionState();
}

class _ChartIconActionState extends State<ChartIconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => widget.onTap(),
          child: AnimatedContainer(
            duration: ChartMetrics.hoverDuration,
            curve: ChartMetrics.hoverCurve,
            width: ChartMetrics.chipHeight,
            height: ChartMetrics.chipHeight,
            decoration: BoxDecoration(
              color: _hovered ? palette.chipHover : Colors.transparent,
              borderRadius: BorderRadius.circular(ChartMetrics.chipRadius),
            ),
            child: widget.busy
                ? Center(
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: palette.label,
                      ),
                    ),
                  )
                : Icon(
                    widget.icon,
                    size: 15,
                    color: _hovered ? palette.strongLabel : palette.label,
                  ),
          ),
        ),
      ),
    );
  }
}

/// What a chart shows when it has nothing to show.
class ChartEmptyState extends StatelessWidget {
  const ChartEmptyState({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.message,
  });

  final ChartPalette palette;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Illustration(palette: palette, icon: icon),
              const SizedBox(height: 16),
              Text(
                title,
                style: palette.text(
                  size: 13.5,
                  color: palette.strongLabel,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: palette.text(size: 12, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Three quiet bars, so an empty chart still looks like a chart.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.palette, required this.icon});

  final ChartPalette palette;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 76,
        height: 54,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final height in const [22.0, 38.0, 29.0])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      width: 12,
                      height: height,
                      decoration: BoxDecoration(
                        color: palette.grid,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Positioned(
              right: 2,
              top: 0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: palette.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: palette.label.withValues(alpha: palette.label.a * 0.8),
                ),
              ),
            ),
          ],
        ),
      );
}

/// The shape of a chart while its numbers are still being read.
class _ChartSkeleton extends StatefulWidget {
  const _ChartSkeleton({required this.palette});

  final ChartPalette palette;

  @override
  State<_ChartSkeleton> createState() => _ChartSkeletonState();
}

class _ChartSkeletonState extends State<_ChartSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => Opacity(
          opacity: 0.45 + _pulse.value * 0.35,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 8, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final fraction in const [0.55, 0.85, 0.4, 0.68, 0.32])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: FractionallySizedBox(
                        heightFactor: fraction,
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: ChartMetrics.maximumBarWidth,
                          ),
                          decoration: BoxDecoration(
                            color: widget.palette.grid,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(ChartMetrics.barRadius),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
