import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_codec.dart'
    show encodeDelimitedText;
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/charts/chart_toolbar.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'package:appflowy/shared/charts/chart_style.dart' show chartPaletteOf;

/// A chart over one table: the controls, the plot, and the numbers behind it.
///
/// The data is always the table's own. Empty results hide the last valid plot
/// without discarding its interactions or drawing stale rows.
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
    this.framed = false,
    this.trailing = const [],
    this.padding = const EdgeInsets.all(16),
    this.source,
  });

  final String viewId;
  final ChartSpec spec;
  final ValueChanged<ChartSpec> onSpecChanged;

  /// What the chart is called, shown above the plot.
  final String? title;

  /// An explicit surface choice, independent of [framed]. When absent, an
  /// unframed chart paints no background, including on custom page canvases.
  final Color? background;
  final bool showToolbar;
  final bool compactToolbar;

  /// Opts into a card with a fill, border and shadow. Charts normally draw
  /// directly on the page; readouts are transparent and menus own their surfaces.
  final bool framed;
  final List<Widget> trailing;
  final EdgeInsets padding;

  /// An optional borrowed source; the host remains responsible for disposal.
  final ChartSource? source;

  @override
  State<ChartStage> createState() => ChartStageState();
}

class ChartStageState extends State<ChartStage> {
  late ChartSource _source =
      widget.source ?? ChartSource(viewId: widget.viewId);
  AppChart? _lastChart;

  @override
  void initState() {
    super.initState();
    _source.addListener(_onChanged);
    unawaited(_source.load());
  }

  @override
  void didUpdateWidget(covariant ChartStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId ||
        oldWidget.source != widget.source) {
      _source.removeListener(_onChanged);
      if (oldWidget.source == null) {
        _source.dispose();
      }
      _lastChart = null;
      _source = widget.source ?? ChartSource(viewId: widget.viewId);
      _source.addListener(_onChanged);
      unawaited(_source.load());
    }
  }

  @override
  void dispose() {
    _source.removeListener(_onChanged);
    if (widget.source == null) {
      _source.dispose();
    }
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
    final palette = chartPaletteOf(
      context,
      background: widget.background,
      framed: widget.framed,
    );
    final table = _source.table;
    // Resolving a name to an id is not permission to replace a choice. Null
    // category and empty values mean "Every row" and "Count rows".
    final spec = table.resolveSpec(widget.spec);
    final data = buildChartData(table, spec);
    final content = _body(palette, table, spec, data);

    final body = CustomScrollView(
      primary: false,
      slivers: [
        if (widget.showToolbar)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  title: widget.title,
                  palette: palette,
                  table: table,
                  spec: spec,
                  data: data,
                  compact: widget.compactToolbar,
                  onChanged: widget.onSpecChanged,
                  onRefresh: reload,
                  onExport: _copyNumbers,
                  busy: _source.isLoading,
                  error: _source.error,
                  trailing: widget.trailing,
                ),
                SizedBox(
                  height: spec.showControls
                      ? ChartMetrics.plotGap
                      : ChartMetrics.headerGap,
                ),
              ],
            ),
          ),
        SliverLayoutBuilder(
          key: const ValueKey('chart-stage-body'),
          builder: (context, constraints) {
            // A wrapped header must not squeeze the drawing below its usable
            // size. Reserve headroom and three scaled control rows for the
            // plot/legend; short hosts scroll, rather than hiding any data.
            final minimumHeight = ChartMetrics.plotHeadroom +
                MediaQuery.textScalerOf(context)
                    .scale(ChartMetrics.chipHeight * 3);
            return SliverToBoxAdapter(
              child: SizedBox(
                height: math.max(
                  minimumHeight,
                  // Use total preceding extent, not remaining paint extent:
                  // scrolling the header away must not resize the live plot.
                  constraints.viewportMainAxisExtent -
                      constraints.precedingScrollExtent,
                ),
                child: content,
              ),
            );
          },
        ),
      ],
    );

    // Keep the same subtree when a host changes its surface choice: a frame
    // must never own the lifetime of the plot, viewport or focused controls.
    return Container(
      decoration: BoxDecoration(
        color: widget.background ?? (widget.framed ? palette.background : null),
        borderRadius: BorderRadius.circular(ChartMetrics.cardRadius),
        border: widget.framed ? Border.all(color: palette.border) : null,
        boxShadow: widget.framed ? chartCardShadow(palette) : null,
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
    final empty = table.isEmpty || data.isEmpty;
    if (!empty) {
      _lastChart = AppChart(
        // A different source or type owns a new drawing and interactions;
        // reloading the same source must not discard the reader's viewport.
        key: ValueKey((_source, spec.type)),
        data: data,
        spec: table.displaySpec(spec),
        interactionSpec: spec.copyWith(
          valueColumns: spec.valueColumns
              .where((column) => table.indexOf(column) >= 0)
              .toList(),
        ),
        palette: palette,
      );
    }
    final error = _source.error;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Never feed an empty projection into the retained chart: its missing
        // series/axes would reset interactions before the next valid reading.
        Offstage(
          key: const ValueKey('chart-stage-plot'),
          offstage: empty,
          child: TickerMode(
            enabled: !empty,
            child: ExcludeFocus(
              excluding: empty,
              child: _ChartTransitionScope(
                currentKey: _lastChart?.key,
                // No extra entrance fade before the first valid reading.
                child: _lastChart == null
                    ? const SizedBox.expand()
                    : AnimatedSwitcher(
                        duration: WorkspaceTokens.motion(
                          context,
                          ChartMetrics.morphDuration,
                        ),
                        switchInCurve: ChartMetrics.revealCurve,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: _chartTransition,
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [...previous, if (current != null) current],
                        ),
                        child: _lastChart,
                      ),
              ),
            ),
          ),
        ),
        if (empty)
          if (_source.isLoading && table.isEmpty)
            _ChartSkeleton(palette: palette)
          else
            ChartEmptyState(
              palette: palette,
              icon: error != null && table.isEmpty
                  ? Icons.error_outline_rounded
                  : Icons.insert_chart_outlined_rounded,
              title: LocaleKeys.charts_empty.tr(),
              message: error != null && table.isEmpty
                  ? error
                  : LocaleKeys.charts_emptyDescription.tr(),
            ),
      ],
    );
  }

  Future<void> _copyNumbers() async {
    // An open menu may outlive a row refresh or field rename. Export the
    // current reading, never its captured snapshot or the offstage plot.
    final table = _source.table;
    final spec = table.resolveSpec(widget.spec);
    final display = table.displaySpec(spec);
    final data = buildChartData(table, spec);
    final measured = spec.plotsAgainstValues;
    final label = measured ? display.categoryColumn : null;
    final size = measured && spec.type.sizesPoints ? display.sizeColumn : null;
    final rows = <List<String>>[
      [
        display.xAxisLabel ?? '',
        if (label != null) label,
        ...data.series.map((one) => one.name),
        if (size != null) size,
      ],
      if (measured)
        // Series can omit different rows and repeat X/label pairs. One row per
        // point preserves all values without inventing cross-series matches.
        for (var series = 0; series < data.series.length; series++)
          for (final point in data.series[series].points)
            [
              point.x?.toString() ?? '',
              if (label != null) point.label,
              for (var column = 0; column < data.series.length; column++)
                column == series ? point.value.toString() : '',
              if (size != null) point.size?.toString() ?? '',
            ]
      else
        for (var index = 0; index < data.categories.length; index++)
          [
            data.categories[index],
            for (final series in data.series)
              index < series.points.length
                  ? series.points[index].value.toString()
                  : '',
          ],
    ];
    await Clipboard.setData(ClipboardData(text: encodeDelimitedText(rows)));
  }
}

// Updating the marker rebuilds cached outgoing transitions before their first
// reverse tick. Keep this scope and the transition structure stable throughout.
class _ChartTransitionScope extends InheritedWidget {
  const _ChartTransitionScope({required this.currentKey, required super.child});

  final Key? currentKey;

  @override
  bool updateShouldNotify(_ChartTransitionScope oldWidget) =>
      currentKey != oldWidget.currentKey;
}

Widget _chartTransition(Widget child, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final currentKey = context
            .dependOnInheritedWidgetOfExactType<_ChartTransitionScope>()!
            .currentKey;
        // A rapid A -> B -> A can leave an older A with the same key outgoing.
        final outgoing = child!.key != currentKey ||
            animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;
        final reduced =
            WorkspaceTokens.motion(context, ChartMetrics.morphDuration) ==
                Duration.zero;
        return ExcludeFocus(
          excluding: outgoing,
          child: IgnorePointer(
            ignoring: outgoing,
            child: ExcludeSemantics(
              excluding: outgoing,
              child: FadeTransition(
                // Switcher controllers capture their original duration. A
                // motion change must snap paint, not replace the live chart.
                opacity: reduced
                    ? outgoing
                        ? kAlwaysDismissedAnimation
                        : kAlwaysCompleteAnimation
                    : animation,
                child: child,
              ),
            ),
          ),
        );
      },
    );

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
    required this.error,
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
  final String? error;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title != null && title!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasTitle) ...[
          Text(
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
          const SizedBox(height: ChartMetrics.headerGap),
        ],
        // One stable wrap owns configuration AND host actions. No 4:1 Row,
        // horizontal scroll viewport or width-dependent reparenting.
        ChartToolbar(
          key: const ValueKey('chart-header-toolbar'),
          table: table,
          spec: spec,
          data: data,
          palette: palette,
          compact: compact,
          showControls: spec.showControls,
          keepVisible: error != null || busy,
          onChanged: onChanged,
          trailing: [
            ...trailing,
            ChartIconAction(
              key: const ValueKey('chart-refresh'),
              icon: error == null
                  ? Icons.refresh_rounded
                  : Icons.error_outline_rounded,
              tooltip: error == null
                  ? LocaleKeys.charts_refresh.tr()
                  : '${LocaleKeys.charts_refresh.tr()}\n$error',
              palette: palette,
              busy: busy,
              onTap: onRefresh,
            ),
          ],
          additionalEntries: _entries(),
        ),
      ],
    );
  }

  List<AppMenuEntry> _entries() => [
        AppMenuItem(
          label: LocaleKeys.charts_showOptions.tr(),
          icon: Icons.tune_rounded,
          selected: spec.showControls,
          onSelected: () => onChanged(
            spec.copyWith(showControls: !spec.showControls),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.charts_showLegend.tr(),
          icon: Icons.legend_toggle_rounded,
          selected: spec.showLegend,
          onSelected: () => onChanged(
            spec.copyWith(showLegend: !spec.showLegend),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.charts_showValues.tr(),
          icon: Icons.numbers_rounded,
          selected: spec.showValues,
          onSelected: () => onChanged(
            spec.copyWith(showValues: !spec.showValues),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.charts_showGrid.tr(),
          icon: Icons.grid_on_rounded,
          selected: spec.showGrid,
          onSelected: () => onChanged(spec.copyWith(showGrid: !spec.showGrid)),
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
      ];
}

/// A quiet square button in a chart's header.
class ChartIconAction extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: ChartMetrics.chipHeight,
      child: IconButton(
        tooltip: tooltip,
        onPressed: () => onTap(),
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(ChartMetrics.chipHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: palette.label,
          hoverColor: palette.chipHover,
          focusColor: palette.chipHover,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChartMetrics.chipRadius),
          ),
        ).copyWith(
          animationDuration:
              WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
        ),
        icon: busy &&
                WorkspaceTokens.motion(context, ChartMetrics.hoverDuration) !=
                    Duration.zero
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
            : WorkspaceGlyph(
                icon,
                size: 15,
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
        child: SingleChildScrollView(
          primary: false,
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
                child: WorkspaceGlyph(
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
  AnimationController? _pulse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced =
        WorkspaceTokens.motion(context, ChartMetrics.hoverDuration) ==
            Duration.zero;
    if (reduced) {
      _pulse?.stop();
      _pulse?.value = 1;
    } else {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      );
      if (!_pulse!.isAnimating) _pulse!.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _pulse ?? kAlwaysCompleteAnimation,
        builder: (context, child) => Opacity(
          opacity: 0.45 + (_pulse?.value ?? 1) * 0.35,
          child: child,
        ),
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
      );
}
