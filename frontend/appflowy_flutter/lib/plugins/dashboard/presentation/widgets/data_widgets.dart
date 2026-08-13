import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_number.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The widgets that read something.
///
/// A database is ONE possible source among many here — a metric can be typed
/// in by hand, a progress bar can measure a number nobody else owns, and a
/// dashboard holding none of these is still a dashboard.
void registerDashboardDataWidgets() {
  DashboardWidgetRegistry.register(_database);
  DashboardWidgetRegistry.register(_chart);
  DashboardWidgetRegistry.register(_metric);
  DashboardWidgetRegistry.register(_progress);
  DashboardWidgetRegistry.register(_list);
}

const _keyValue = 'value';
const _keyTarget = 'target';
const _keyUnit = 'unit';
const _keyPrefix = 'prefix';
const _keyAggregate = 'aggregate';
const _keyChartType = 'chart_type';
const _keyLimit = 'limit';
const _keyStyle = 'style';

DashboardConfigField _sourceField(
  DashboardWidgetContext context, {
  required String label,
  required DashboardSourceKind kind,
  bool Function(ViewPB view)? filter,
}) =>
    DashboardConfigView(
      label: label,
      viewId: context.spec.source.viewId,
      name: context.spec.source.name,
      filter: filter,
      onChanged: (viewId, name) => context.setSource(
        context.spec.source.copyWith(
          kind: viewId.isEmpty ? DashboardSourceKind.none : kind,
          viewId: viewId,
          name: name,
        ),
      ),
    );

bool _isDatabase(ViewPB view) => const [
      ViewLayoutPB.Grid,
      ViewLayoutPB.Board,
      ViewLayoutPB.Calendar,
    ].contains(view.layout);

Future<void> _pickDatabase(DashboardWidgetContext context) =>
    context.pickSource(
      kind: DashboardSourceKind.database,
      filter: _isDatabase,
    );

// ------------------------------------------------------------------- database

final _database = DashboardWidgetDefinition(
  type: 'database',
  label: () => LocaleKeys.dashboard_widget_database.tr(),
  description: () => LocaleKeys.dashboard_widget_databaseHint.tr(),
  icon: Icons.table_rows_rounded,
  group: DashboardWidgetGroup.data,
  defaultColumnSpan: 8,
  defaultRowSpan: 8,
  keywords: const [
    'database',
    'table',
    'grid',
    'board',
    'kanban',
    'calendar',
    'collection view',
  ],
  builder: (context) {
    final viewId = context.spec.source.viewId;
    if (viewId.isEmpty) {
      return DashboardPlaceholder(
        palette: context.palette,
        icon: Icons.table_chart_outlined,
        message: LocaleKeys.dashboard_widget_pickDatabase.tr(),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(_pickDatabase(context)),
      );
    }
    return DashboardViewBuilder(
      viewId: viewId,
      revision: context.refreshToken,
      builder: (_, view) => Provider<DatabasePluginWidgetBuilderSize>.value(
        value: const DatabasePluginWidgetBuilderSize(horizontalPadding: 0),
        // Keyed on the view: switching table reuses the previous database's
        // controllers otherwise, and the grid draws the wrong rows.
        child: DatabaseTabBarView(
          key: ValueKey('dashboard-database-${view.id}'),
          view: view,
          shrinkWrap: false,
          showActions: false,
        ),
      ),
    );
  },
  configure: (context) => [
    _sourceField(
      context,
      label: LocaleKeys.dashboard_config_database.tr(),
      kind: DashboardSourceKind.database,
      filter: _isDatabase,
    ),
  ],
);

// ---------------------------------------------------------------------- chart

final _chart = DashboardWidgetDefinition(
  type: 'chart',
  label: () => LocaleKeys.dashboard_widget_chart.tr(),
  description: () => LocaleKeys.dashboard_widget_chartHint.tr(),
  icon: Icons.bar_chart_rounded,
  group: DashboardWidgetGroup.data,
  defaultColumnSpan: 6,
  defaultRowSpan: 6,
  slashName: 'chart',
  keywords: const ['chart', 'graph', 'bar', 'line', 'pie', 'plot', 'analytics'],
  builder: (context) => _ChartBody(context: context),
  configure: (context) => [
    _sourceField(
      context,
      label: LocaleKeys.dashboard_config_database.tr(),
      kind: DashboardSourceKind.database,
      filter: _isDatabase,
    ),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_chartType.tr(),
      value: context.spec.setting(_keyChartType, fallback: 'bar'),
      choices: [
        for (final type in ChartType.values)
          DashboardChoice(value: type.name, label: type.name),
      ],
      onChanged: (value) => context.setSettings({_keyChartType: value}),
    ),
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_categoryColumn.tr(),
      hint: LocaleKeys.dashboard_config_columnHint.tr(),
      value: context.spec.source.groupField,
      onChanged: (value) =>
          context.setSource(context.spec.source.copyWith(groupField: value)),
    ),
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_valueColumn.tr(),
      hint: LocaleKeys.dashboard_config_columnHint.tr(),
      value: context.spec.source.field,
      onChanged: (value) =>
          context.setSource(context.spec.source.copyWith(field: value)),
    ),
  ],
);

class _ChartBody extends StatefulWidget {
  const _ChartBody({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_ChartBody> createState() => _ChartBodyState();
}

class _ChartBodyState extends State<_ChartBody> {
  ChartSource? _source;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(_ChartBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final viewId = widget.context.spec.source.viewId;
    if (_source?.viewId != viewId ||
        oldWidget.context.refreshToken != widget.context.refreshToken) {
      _bind();
    }
  }

  void _bind() {
    _source?.removeListener(_onChanged);
    _source?.dispose();
    final viewId = widget.context.spec.source.viewId;
    if (viewId.isEmpty) {
      _source = null;
      return;
    }
    final source = ChartSource(viewId: viewId)..addListener(_onChanged);
    _source = source;
    unawaited(source.load());
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _source?.removeListener(_onChanged);
    _source?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.context.palette;
    final source = _source;
    if (source == null) {
      return DashboardPlaceholder(
        palette: palette,
        icon: Icons.insert_chart_outlined_rounded,
        message: LocaleKeys.dashboard_widget_pickDatabase.tr(),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(_pickDatabase(widget.context)),
      );
    }
    if (source.table.rows.isEmpty) {
      return DashboardPlaceholder(
        palette: palette,
        icon: Icons.insert_chart_outlined_rounded,
        message: source.isLoading
            ? LocaleKeys.dashboard_widget_reading.tr()
            : LocaleKeys.dashboard_widget_nothingToChart.tr(),
      );
    }

    final spec = _spec(source.table);
    return AppChart(
      data: buildChartData(source.table, spec),
      spec: spec,
      palette: chartPaletteOf(context, background: widget.context.tone.surface),
      allowZoom: false,
    );
  }

  ChartSpec _spec(ChartTable table) {
    final settings = widget.context.spec;
    final source = settings.source;
    final category = source.groupField.isNotEmpty
        ? source.groupField
        : (table.columns.isNotEmpty ? table.columns.first : null);
    final value = source.field.isNotEmpty
        ? [source.field]
        : (table.numericColumns.isEmpty
            ? const <String>[]
            : [table.numericColumns.first]);
    return ChartSpec(
      type: ChartType.values.firstWhere(
        (type) => type.name == settings.setting(_keyChartType, fallback: 'bar'),
        orElse: () => ChartType.bar,
      ),
      categoryColumn: category,
      valueColumns: value,
      showLegend: value.length > 1,
    );
  }
}

// --------------------------------------------------------------------- metric

final _metric = DashboardWidgetDefinition(
  type: 'metric',
  label: () => LocaleKeys.dashboard_widget_metric.tr(),
  description: () => LocaleKeys.dashboard_widget_metricHint.tr(),
  icon: Icons.speed_rounded,
  group: DashboardWidgetGroup.data,
  defaultColumnSpan: 3,
  defaultRowSpan: 3,
  slashName: 'metric',
  keywords: const ['metric', 'number', 'kpi', 'stat', 'total', 'count'],
  builder: (context) => _AggregateBody(
    context: context,
    builder: (value, loading) {
      // A metric that reads a table shows what it read; one that holds its own
      // number is typed into where it is read.
      final own = !context.spec.source.isBound;
      return Center(
        child: own
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (context.spec.setting(_keyPrefix).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Text(
                        context.spec.setting(_keyPrefix),
                        style: DashboardType.caption(context.palette)
                            .copyWith(fontSize: 14),
                      ),
                    ),
                  Flexible(
                    child: DashboardEditableNumber(
                      value: context.spec.number(_keyValue, fallback: 0),
                      palette: context.palette,
                      enabled: context.isTypable,
                      textAlign: TextAlign.center,
                      style: DashboardType.figure(context.palette)
                          .copyWith(color: context.strong),
                      onChanged: (next) =>
                          context.setSettings({_keyValue: next}),
                    ),
                  ),
                  if (context.spec.setting(_keyUnit).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Text(
                        context.spec.setting(_keyUnit),
                        style: DashboardType.caption(context.palette)
                            .copyWith(fontSize: 14),
                      ),
                    ),
                ],
              )
            : DashboardFigure(
                value: value == null ? '—' : formatChartNumber(value),
                prefix: context.spec.setting(_keyPrefix),
                suffix: context.spec.setting(_keyUnit),
                palette: context.palette,
                color: context.strong,
                caption: context.spec.source.name,
              ),
      );
    },
  ),
  configure: _aggregateFields,
);

// ------------------------------------------------------------------- progress

final _progress = DashboardWidgetDefinition(
  type: 'progress',
  label: () => LocaleKeys.dashboard_widget_progress.tr(),
  description: () => LocaleKeys.dashboard_widget_progressHint.tr(),
  icon: Icons.donut_large_rounded,
  group: DashboardWidgetGroup.data,
  defaultRowSpan: 3,
  slashName: 'progress',
  keywords: const ['progress', 'bar', 'percent', 'completion', 'goal', 'ring'],
  builder: (context) => _AggregateBody(
    context: context,
    builder: (value, loading) {
      final target = context.spec.number(_keyTarget, fallback: 100);
      // A bar reading a table shows what it read; one that holds its own
      // number is typed into where it is read.
      final own = !context.spec.source.isBound;
      final current =
          own ? context.spec.number(_keyValue, fallback: 0) : (value ?? 0);
      final fraction = target <= 0 ? 0.0 : (current / target).clamp(0.0, 1.0);
      final ring = context.spec.setting(_keyStyle, fallback: 'bar') == 'ring';

      // A field asks for its natural width; in a narrow card the two of them
      // plus the percentage do not fit, so they are allowed to give way.
      Widget numbers({required bool flexible}) {
        Widget give(Widget child) => flexible ? Flexible(child: child) : child;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            give(
              own
                  ? DashboardEditableNumber(
                      value: current,
                      palette: context.palette,
                      enabled: context.isTypable,
                      style: DashboardType.figure(
                        context.palette,
                        size: ring ? 15 : 22,
                      ),
                      onChanged: (next) =>
                          context.setSettings({_keyValue: next}),
                    )
                  : Text(
                      formatChartNumber(current),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.figure(
                        context.palette,
                        size: ring ? 15 : 22,
                      ),
                    ),
            ),
            Text(
              ' / ',
              style:
                  DashboardType.caption(context.palette).copyWith(fontSize: 13),
            ),
            give(
              DashboardEditableNumber(
                value: target,
                palette: context.palette,
                enabled: context.isTypable,
                style: DashboardType.caption(context.palette)
                    .copyWith(fontSize: 13),
                onChanged: (next) => context.setSettings({_keyTarget: next}),
              ),
            ),
          ],
        );
      }

      if (ring) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: fraction,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: context.strong.withValues(alpha: 0.16),
                        valueColor: AlwaysStoppedAnimation(context.strong),
                      ),
                    ),
                    Text(
                      '${(fraction * 100).round()}%',
                      style: DashboardType.figure(context.palette, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: numbers(flexible: false),
            ),
          ],
        );
      }

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Expanded, never Flexible beside a Spacer: the two would share
              // the free space and the percentage would drift off the edge.
              Expanded(child: numbers(flexible: true)),
              const SizedBox(width: 8),
              Text(
                '${(fraction * 100).round()}%',
                style: DashboardType.cardTitle(
                  context.palette,
                  color: context.strong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProgressTrack(
            fraction: fraction,
            palette: context.palette,
            strong: context.strong,
            // Only a bar that owns its number can be dragged; one reading a
            // table would be arguing with what it read.
            interactive: own && context.isTypable,
            onChanged: (next, {required settled}) => context.update(
              (spec) => spec.withSettings({_keyValue: next * target}),
              transient: !settled,
            ),
          ),
        ],
      );
    },
  ),
  configure: (context) => [
    ..._aggregateFields(context),
    DashboardConfigNumber(
      label: LocaleKeys.dashboard_config_target.tr(),
      value: context.spec.number(_keyTarget, fallback: 100),
      minimum: 1,
      onChanged: (value) => context.setSettings({_keyTarget: value}),
    ),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_style.tr(),
      value: context.spec.setting(_keyStyle, fallback: 'bar'),
      choices: [
        DashboardChoice(
          value: 'bar',
          label: LocaleKeys.dashboard_progress_bar.tr(),
        ),
        DashboardChoice(
          value: 'ring',
          label: LocaleKeys.dashboard_progress_ring.tr(),
        ),
      ],
      onChanged: (value) => context.setSettings({_keyStyle: value}),
    ),
  ],
);

/// The bar itself, which can be dragged to set what it shows.
///
/// A figure that can only be changed in a settings panel is a figure that has
/// to be hunted for; a progress bar is the one control where pointing at the
/// place you mean IS the way to say it.
class _ProgressTrack extends StatefulWidget {
  const _ProgressTrack({
    required this.fraction,
    required this.palette,
    required this.strong,
    required this.interactive,
    required this.onChanged,
  });

  final double fraction;
  final DashboardPalette palette;
  final Color strong;
  final bool interactive;
  final void Function(double fraction, {required bool settled}) onChanged;

  @override
  State<_ProgressTrack> createState() => _ProgressTrackState();
}

class _ProgressTrackState extends State<_ProgressTrack> {
  /// What the pointer is saying, until it is let go.
  double? _live;

  void _report(Offset globalPosition, {required bool settled}) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    if (box == null || width <= 0) {
      return;
    }
    final dx = box.globalToLocal(globalPosition).dx;
    final fraction = (dx / width).clamp(0.0, 1.0);
    setState(() => _live = settled ? null : fraction);
    widget.onChanged(fraction, settled: settled);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _live ?? widget.fraction;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: TweenAnimationBuilder<double>(
        duration: _live == null ? DashboardMetrics.settle : Duration.zero,
        curve: DashboardMetrics.curve,
        tween: Tween(begin: 0, end: shown),
        builder: (_, animated, __) => LinearProgressIndicator(
          value: animated,
          minHeight: 9,
          backgroundColor: widget.strong.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation(widget.strong),
        ),
      ),
    );

    if (!widget.interactive) {
      return bar;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          // Eager: the card's own pan claims a drag at a pixel of travel, and
          // a bar that loses the arena cannot be dragged at all.
          _EagerHorizontalDrag:
              GestureRecognizerFactoryWithHandlers<_EagerHorizontalDrag>(
            _EagerHorizontalDrag.new,
            (recognizer) {
              recognizer.onStart = (details) {
                _report(details.globalPosition, settled: false);
              };
              recognizer.onUpdate = (details) {
                _report(details.globalPosition, settled: false);
              };
              recognizer.onEnd = (_) {
                final fraction = _live;
                if (fraction != null) {
                  setState(() => _live = null);
                  widget.onChanged(fraction, settled: true);
                }
              };
            },
          ),
        },
        child: SizedBox(height: 20, child: Center(child: bar)),
      ),
    );
  }
}

/// Accepts as soon as it is offered, so a scroll view or the card's own pan
/// cannot take the drag away.
class _EagerHorizontalDrag extends HorizontalDragGestureRecognizer {
  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}

List<DashboardConfigField> _aggregateFields(DashboardWidgetContext context) => [
      _sourceField(
        context,
        label: LocaleKeys.dashboard_config_database.tr(),
        kind: DashboardSourceKind.database,
        filter: _isDatabase,
      ),
      if (context.spec.source.viewId.isEmpty)
        DashboardConfigNumber(
          label: LocaleKeys.dashboard_config_value.tr(),
          value: context.spec.number(_keyValue, fallback: 0),
          onChanged: (value) => context.setSettings({_keyValue: value}),
        )
      else ...[
        DashboardConfigChoice(
          label: LocaleKeys.dashboard_config_aggregate.tr(),
          value: context.spec.setting(_keyAggregate, fallback: 'count'),
          choices: [
            for (final aggregate in ChartAggregate.values)
              DashboardChoice(value: aggregate.name, label: aggregate.name),
          ],
          onChanged: (value) => context.setSettings({_keyAggregate: value}),
        ),
        DashboardConfigText(
          label: LocaleKeys.dashboard_config_valueColumn.tr(),
          hint: LocaleKeys.dashboard_config_columnHint.tr(),
          value: context.spec.source.field,
          onChanged: (value) =>
              context.setSource(context.spec.source.copyWith(field: value)),
        ),
      ],
      DashboardConfigText(
        label: LocaleKeys.dashboard_config_prefix.tr(),
        value: context.spec.setting(_keyPrefix),
        onChanged: (value) => context.setSettings({_keyPrefix: value}),
      ),
      DashboardConfigText(
        label: LocaleKeys.dashboard_config_unit.tr(),
        value: context.spec.setting(_keyUnit),
        onChanged: (value) => context.setSettings({_keyUnit: value}),
      ),
    ];

/// Reads one number: either the widget's own, or an aggregate over a column.
class _AggregateBody extends StatefulWidget {
  const _AggregateBody({required this.context, required this.builder});

  final DashboardWidgetContext context;
  final Widget Function(double? value, bool loading) builder;

  @override
  State<_AggregateBody> createState() => _AggregateBodyState();
}

class _AggregateBodyState extends State<_AggregateBody> {
  ChartSource? _source;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(_AggregateBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_source?.viewId != widget.context.spec.source.viewId ||
        oldWidget.context.refreshToken != widget.context.refreshToken) {
      _bind();
    }
  }

  void _bind() {
    _source?.removeListener(_onChanged);
    _source?.dispose();
    final viewId = widget.context.spec.source.viewId;
    if (viewId.isEmpty) {
      _source = null;
      return;
    }
    final source = ChartSource(viewId: viewId)..addListener(_onChanged);
    _source = source;
    unawaited(source.load());
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _source?.removeListener(_onChanged);
    _source?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.context.spec;
    final source = _source;
    if (source == null) {
      return widget.builder(spec.number(_keyValue, fallback: 0), false);
    }
    final table = source.table;
    final aggregate = ChartAggregate.fromValue(
      spec.setting(_keyAggregate, fallback: 'count'),
    );
    if (aggregate == ChartAggregate.count) {
      return widget.builder(table.rows.length.toDouble(), source.isLoading);
    }
    final index = table.indexOf(spec.source.field);
    if (index < 0) {
      return widget.builder(null, source.isLoading);
    }
    final values = <double>[
      for (final row in table.rows)
        if (index < row.length)
          if (parseChartNumber(row[index]) case final number?) number,
    ];
    return widget.builder(aggregate.apply(values), source.isLoading);
  }
}

// ----------------------------------------------------------------------- list

final _list = DashboardWidgetDefinition(
  type: 'list',
  label: () => LocaleKeys.dashboard_widget_list.tr(),
  description: () => LocaleKeys.dashboard_widget_listHint.tr(),
  icon: Icons.format_list_bulleted_rounded,
  group: DashboardWidgetGroup.data,
  defaultRowSpan: 6,
  keywords: const ['list', 'pages', 'feed', 'recent', 'folder', 'collection'],
  builder: (context) => _ChildListBody(context: context),
  configure: (context) => [
    _sourceField(
      context,
      label: LocaleKeys.dashboard_config_folder.tr(),
      kind: DashboardSourceKind.folder,
    ),
    DashboardConfigNumber(
      label: LocaleKeys.dashboard_config_limit.tr(),
      value: context.spec.number(_keyLimit, fallback: 10),
      minimum: 1,
      maximum: 60,
      onChanged: (value) => context.setSettings({_keyLimit: value.round()}),
    ),
  ],
);

class _ChildListBody extends StatefulWidget {
  const _ChildListBody({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_ChildListBody> createState() => _ChildListBodyState();
}

class _ChildListBodyState extends State<_ChildListBody> {
  List<ViewPB> _children = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_ChildListBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context.spec.source.viewId !=
            widget.context.spec.source.viewId ||
        oldWidget.context.refreshToken != widget.context.refreshToken) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final viewId = widget.context.spec.source.viewId;
    if (viewId.isEmpty) {
      setState(() => _children = const []);
      return;
    }
    setState(() => _loading = true);
    final result = await const WorkspaceItemService().getChildren(viewId);
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _children = result.fold((views) => views, (_) => const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.context.palette;
    if (widget.context.spec.source.viewId.isEmpty) {
      return DashboardPlaceholder(
        palette: palette,
        icon: Icons.folder_open_rounded,
        message: LocaleKeys.dashboard_widget_pickFolder.tr(),
        action: LocaleKeys.dashboard_config_choose.tr(),
        onAction: () => unawaited(
          widget.context.pickSource(kind: DashboardSourceKind.folder),
        ),
      );
    }
    if (_children.isEmpty) {
      return DashboardPlaceholder(
        palette: palette,
        icon: Icons.inbox_rounded,
        message: _loading
            ? LocaleKeys.dashboard_widget_reading.tr()
            : LocaleKeys.dashboard_widget_nothingHere.tr(),
      );
    }
    final limit = widget.context.spec.integer(_keyLimit, fallback: 10);
    final shown = _children.take(limit).toList();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: shown.length,
      itemBuilder: (_, index) {
        final view = shown[index];
        return _ListRow(
          label: view.name.isEmpty
              ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
              : view.name,
          palette: palette,
          onTap: () => unawaited(
            widget.context.run(
              DashboardAction(
                kind: DashboardActionKind.openPage,
                target: view.id,
                targetName: view.name,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ListRow extends StatefulWidget {
  const _ListRow({
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final DashboardPalette palette;
  final VoidCallback onTap;

  @override
  State<_ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<_ListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: DashboardMetrics.hover,
            height: 30,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hovered ? widget.palette.hover : widget.palette.hoverBase,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 15,
                  color: widget.palette.textMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardType.body(widget.palette)
                        .copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
