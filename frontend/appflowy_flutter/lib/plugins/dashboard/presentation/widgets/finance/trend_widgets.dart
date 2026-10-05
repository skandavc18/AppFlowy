import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_binding.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_charts.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_common.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_kit.dart';
import 'package:appflowy/shared/market/market_data.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/finance/balance_sheet.dart';
import 'package:appflowy/workspace/application/finance/capital_series.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:appflowy/workspace/application/finance/portfolio_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

void registerTrendWidgets() {
  DashboardWidgetRegistry.register(_trend);
  DashboardWidgetRegistry.register(_allocation);
  DashboardWidgetRegistry.register(_pnlCalendar);
  DashboardWidgetRegistry.register(_pnlStats);
}

const _keyRange = 'range';
const _keyStyle = 'style';

Widget _pickTable(
  DashboardWidgetContext data,
  FinanceGhostShape shape,
  IconData icon,
) =>
    FinanceGhost(
      palette: data.palette,
      shape: shape,
      icon: icon,
      message: LocaleKeys.dashboard_money_needsDates.tr(),
      action:
          data.isTypable ? LocaleKeys.dashboard_money_chooseTable.tr() : null,
      onAction: () => unawaited(financePickTable(data)),
      color: data.tone.strong,
    );

Widget _loading(DashboardWidgetContext data, BuildContext context) => Center(
      child: FinanceShimmer(
        palette: data.palette,
        width: 160,
        height: 14,
        still: financeStill(data, context),
      ),
    );

/// The name of the column [role] resolves to, for a legend.
String _columnName(
  ChartTable table,
  List<FinanceRole> roles,
  FinanceRole role,
  Map<String, Object?> settings,
) {
  final index = FinanceColumns.resolve(table, roles, settings: settings)[role];
  return index >= 0 ? table.columns[index] : '';
}

String _timeLabel(DateTime time, Duration span) => span.inDays > 400
    ? DateFormat.yMMM().format(time)
    : DateFormat.MMMd().format(time);

/// Whether a comparison column is an index to beat rather than money put in.
bool _isBenchmark(String column) {
  final name = column.toLowerCase();
  return name.contains('benchmark') || name.contains('index');
}

/// The yearly rate, once there is a year of history to rate.
double? _annualized(TimeSeries series) {
  final first = series.first;
  final last = series.last;
  if (first == null ||
      last == null ||
      last.time.difference(first.time).inDays < 365) {
    return null;
  }
  return series.cagr;
}

// --------------------------------------------------------------------- trend

enum _Range { quarter, half, year, all }

Duration? _rangeSpan(_Range range) => switch (range) {
      _Range.quarter => const Duration(days: 92),
      _Range.half => const Duration(days: 183),
      _Range.year => const Duration(days: 366),
      _Range.all => null,
    };

_Range _rangeOf(DashboardWidgetContext data) => _Range.values.firstWhere(
      (range) => range.name == data.spec.setting(_keyRange, fallback: 'all'),
      orElse: () => _Range.all,
    );

final _trend = DashboardWidgetDefinition(
  type: 'trend',
  label: () => LocaleKeys.dashboard_money_trend.tr(),
  description: () => LocaleKeys.dashboard_money_trendHint.tr(),
  icon: Icons.show_chart_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 8,
  defaultRowSpan: 7,
  minimumColumnSpan: 3,
  minimumRowSpan: 4,
  identity: DashboardAccent.blue,
  defaultTitle: () => LocaleKeys.dashboard_money_trend.tr(),
  keywords: const [
    'trend',
    'equity curve',
    'capital',
    'growth',
    'history',
    'net worth',
    'line',
  ],
  headerTrailing: (data) => FinanceSegmented<_Range>(
    palette: data.palette,
    values: _Range.values,
    selected: _rangeOf(data),
    labelOf: (range) => switch (range) {
      _Range.quarter => LocaleKeys.dashboard_money_rangeQuarter.tr(),
      _Range.half => LocaleKeys.dashboard_money_rangeHalf.tr(),
      _Range.year => LocaleKeys.dashboard_money_rangeYear.tr(),
      _Range.all => LocaleKeys.dashboard_money_rangeAll.tr(),
    },
    onSelected: data.isTypable
        ? (range) => data.setSettings({_keyRange: range.name})
        : null,
  ),
  builder: (data) => _Trend(data: data),
  configure: (data) => [
    financeTableField(data),
    financeCurrencyField(data),
    financeColumnsField(data, [
      (SeriesRoles.date, LocaleKeys.dashboard_money_date.tr()),
      (SeriesRoles.value, LocaleKeys.dashboard_money_valueColumn.tr()),
      (SeriesRoles.baseline, LocaleKeys.dashboard_money_compareColumn.tr()),
    ]),
  ],
);

class _Trend extends StatelessWidget {
  const _Trend({required this.data});

  final DashboardWidgetContext data;

  @override
  Widget build(BuildContext context) {
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    return FinanceView(
      data: data,
      builder: (context, feed) {
        if (!feed.bound) {
          return _pickTable(
            data,
            FinanceGhostShape.line,
            Icons.show_chart_rounded,
          );
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final settings = data.spec.settings;
        var series = readSeries(feed.table, settings: settings);
        var baseline = readCompanionSeries(
          feed.table,
          SeriesRoles.baseline,
          settings: settings,
        );
        if (series.length < 2) {
          return _pickTable(
            data,
            FinanceGhostShape.line,
            Icons.show_chart_rounded,
          );
        }
        final span = _rangeSpan(_rangeOf(data));
        // A history shown whole is counted from its start; a range only
        // from where the range begins.
        var whole = true;
        if (span != null) {
          final start = series.last!.time.subtract(span);
          final trimmed = series.since(start);
          if (trimmed.length >= 2) {
            whole = trimmed.length == series.length;
            series = trimmed;
            baseline = baseline.since(start);
          }
        }
        final money = financeMoney(data);
        final roles = [
          SeriesRoles.date,
          SeriesRoles.value,
          SeriesRoles.baseline,
        ];
        final valueName =
            _columnName(feed.table, roles, SeriesRoles.value, settings);
        final baseName =
            _columnName(feed.table, roles, SeriesRoles.baseline, settings);
        final last = series.last!;
        // A comparison with what went in turns a rise into growth: money
        // paid in is taken out of the gain, and the return is time-weighted.
        // A benchmark is something else entirely and is only drawn.
        final paidIn = _isBenchmark(baseName)
            ? null
            : ContributedReturn.of(series, baseline, fromInception: whole);
        final change = paidIn?.gain ?? series.change ?? 0;
        final changePercent = paidIn?.percent ?? series.changePercent;
        final drawdown = paidIn?.drawdown ?? series.maxDrawdown;
        final cagr = paidIn == null ? _annualized(series) : paidIn.annualized;
        final timeSpan = last.time.difference(series.first!.time);
        final lines = [
          TrendLine(
            label: valueName.isEmpty
                ? LocaleKeys.dashboard_money_value.tr()
                : valueName,
            times: [for (final point in series.points) point.time],
            values: [for (final point in series.points) point.value],
            color: data.tone.strong,
            fill: true,
          ),
          if (baseline.length >= 2)
            TrendLine(
              label: baseName,
              times: [for (final point in baseline.points) point.time],
              values: [for (final point in baseline.points) point.value],
              color: palette.textMuted,
              dashed: true,
            ),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final roomy = constraints.maxHeight >= 220;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FinanceRun(
                  height: roomy ? 40 : 30,
                  spacing: 12,
                  children: [
                    AnimatedFigure(
                      value: last.value,
                      format: (value) => money.fit(value),
                      still: still,
                      style: DashboardType.display(
                        palette,
                        size: roomy ? 30 : 22,
                        weight: FontWeight.w600,
                      ),
                    ),
                    ChangePill(
                      colors: colors,
                      value: change,
                      text: '${money.fit(change, signed: true)} · '
                          '${formatPercent(changePercent, decimals: 1, signed: false)}',
                    ),
                    if (cagr != null)
                      _Chip(
                        label: LocaleKeys.dashboard_money_cagr.tr(),
                        value: formatPercent(cagr, decimals: 1),
                        color: colors.change(cagr),
                        palette: palette,
                      ),
                    if (drawdown.percent > 0)
                      _Chip(
                        label: LocaleKeys.dashboard_money_maxDrawdown.tr(),
                        value: formatPercent(
                          -drawdown.percent,
                          decimals: 1,
                        ),
                        color: colors.loss,
                        palette: palette,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FinanceTrendChart(
                    lines: lines,
                    palette: palette,
                    colors: colors,
                    compare: lines.length > 1,
                    still: still,
                    axes: constraints.maxWidth >= 260,
                    formatValue: (value) => money.compact(value),
                    formatTime: (time) => _timeLabel(time, timeSpan),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.value,
    required this.color,
    required this.palette,
  });

  final String label;
  final String value;
  final Color color;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: palette.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : palette.sunken,
          borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label  ',
                style: financeLabel(palette.textMuted, size: 11),
              ),
              TextSpan(
                text: value,
                style: financeNumber(color, size: 11.5),
              ),
            ],
          ),
          maxLines: 1,
        ),
      );
}

// ---------------------------------------------------------------- allocation

/// One slice of an allocation, with what it should be drawn as.
class _Part {
  const _Part(this.label, this.value, this.color, {this.icon});

  final String label;
  final double value;
  final Color color;
  final IconData? icon;
}

final _allocation = DashboardWidgetDefinition(
  type: 'allocation',
  label: () => LocaleKeys.dashboard_money_allocation.tr(),
  description: () => LocaleKeys.dashboard_money_allocationHint.tr(),
  icon: Icons.donut_large_rounded,
  group: DashboardWidgetGroup.money,
  defaultRowSpan: 7,
  minimumColumnSpan: 3,
  minimumRowSpan: 4,
  identity: DashboardAccent.purple,
  defaultTitle: () => LocaleKeys.dashboard_money_allocation.tr(),
  keywords: const [
    'allocation',
    'donut',
    'pie',
    'split',
    'diversification',
    'asset mix',
  ],
  builder: (data) => _Allocation(data: data),
  configure: (data) => [
    financeTableField(data),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_money_style.tr(),
      value: data.spec.setting(_keyStyle, fallback: 'donut'),
      choices: [
        DashboardChoice(
          value: 'donut',
          label: LocaleKeys.dashboard_money_styleDonut.tr(),
        ),
        DashboardChoice(
          value: 'bars',
          label: LocaleKeys.dashboard_money_styleBars.tr(),
        ),
        DashboardChoice(
          value: 'map',
          label: LocaleKeys.dashboard_money_styleMap.tr(),
        ),
      ],
      onChanged: (value) => data.setSettings({_keyStyle: value}),
    ),
    financeCurrencyField(data),
    financeColumnsField(data, [
      (FinanceRole.sector, LocaleKeys.dashboard_money_groupColumn.tr()),
      (FinanceRole.value, LocaleKeys.dashboard_money_valueColumn.tr()),
    ]),
  ],
);

/// Reads a table as parts of a whole, whatever kind of table it is: a
/// balance sheet splits by category, holdings by sector at live prices, and
/// anything else by its group column.
List<_Part> _partsOf(
  ChartTable table,
  Map<String, Object?> settings,
  MarketWatch market,
  FinanceColors colors,
) {
  final other = LocaleKeys.dashboard_money_otherSlice.tr();
  final explicit =
      (settings[FinanceRole.sector.key] as String? ?? '').isNotEmpty;
  final balance = FinanceColumns.resolve(
    table,
    BalanceRoles.all,
    settings: settings,
  );
  if (!explicit &&
      balance.has(BalanceRoles.value) &&
      (balance.has(BalanceRoles.side) || balance.has(BalanceRoles.category))) {
    final summary = BalanceSummary.of(
      readBalanceItems(table, settings: settings),
    );
    return [
      for (final total in summary.assetCategories)
        _Part(
          balanceCategoryLabel(total.category),
          total.value,
          balanceCategoryColor(total.category, colors),
          icon: balanceCategoryIcon(total.category),
        ),
    ];
  }

  final holdingColumns = FinanceColumns.resolve(
    table,
    Holding.roles,
    settings: settings,
  );
  final List<AllocationSlice> slices;
  if (holdingColumns.has(FinanceRole.quantity) &&
      (holdingColumns.has(FinanceRole.lastPrice) ||
          holdingColumns.has(FinanceRole.averagePrice) ||
          holdingColumns.has(FinanceRole.symbol))) {
    final holdings = priceHoldings(
      Holding.read(table, settings: settings),
      market,
    );
    slices = allocate(
      [
        for (final holding in holdings)
          (
            holding.holding.sector.isNotEmpty
                ? holding.holding.sector
                : holding.holding.name,
            holding.value,
          ),
      ],
      otherLabel: other,
    );
  } else {
    final columns = FinanceColumns.resolve(
      table,
      [FinanceRole.value, FinanceRole.sector, FinanceRole.name],
      settings: settings,
    );
    var group = columns[FinanceRole.sector];
    if (group < 0) {
      group = columns.has(FinanceRole.name) ? columns[FinanceRole.name] : 0;
    }
    var value = columns[FinanceRole.value];
    final sheet = FinanceSheet(table);
    if (value < 0) {
      for (var column = 0; column < table.columns.length; column++) {
        if (column != group &&
            List.generate(sheet.length, (row) => sheet.number(row, column))
                .any((number) => number != null)) {
          value = column;
          break;
        }
      }
    }
    if (value < 0) {
      return const [];
    }
    slices = allocate(
      [
        for (var row = 0; row < sheet.length; row++)
          (sheet.text(row, group), sheet.number(row, value) ?? 0),
      ],
      otherLabel: other,
    );
  }
  return [
    for (var index = 0; index < slices.length; index++)
      _Part(
        slices[index].label,
        slices[index].value,
        sliceColor(colors, index, other: slices[index].isOther),
      ),
  ];
}

class _Allocation extends StatefulWidget {
  const _Allocation({required this.data});

  final DashboardWidgetContext data;

  @override
  State<_Allocation> createState() => _AllocationState();
}

class _AllocationState extends State<_Allocation> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    return FinanceView(
      data: data,
      builder: (context, feed) {
        if (!feed.bound) {
          return FinanceGhost(
            palette: palette,
            shape: FinanceGhostShape.donut,
            icon: Icons.donut_large_rounded,
            message: LocaleKeys.dashboard_money_allocationHint.tr(),
            action: data.isTypable
                ? LocaleKeys.dashboard_money_chooseTable.tr()
                : null,
            onAction: () => unawaited(financePickTable(data)),
            color: data.tone.strong,
          );
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final parts = _partsOf(
          feed.table,
          data.spec.settings,
          feed.market,
          colors,
        );
        if (parts.isEmpty) {
          return Center(
            child: Text(
              LocaleKeys.dashboard_money_allocationHint.tr(),
              textAlign: TextAlign.center,
              style: DashboardType.caption(palette),
            ),
          );
        }
        final money = financeMoney(data);
        final total = parts.fold<double>(0, (sum, part) => sum + part.value);
        final style = data.spec.setting(_keyStyle, fallback: 'donut');
        if (style == 'map') {
          return FinanceTreemap(
            palette: palette,
            still: still,
            items: [
              for (final part in parts)
                TreemapItem(
                  label: part.label,
                  value: part.value,
                  color: part.color,
                  caption: formatPercent(
                    part.value / total * 100,
                    decimals: 1,
                    signed: false,
                  ),
                  detail: '${part.label}\n${money.fit(part.value)}',
                ),
            ],
          );
        }
        if (style == 'bars') {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              for (var index = 0; index < parts.length; index++)
                FinanceEntrance(
                  index: index,
                  still: still,
                  child: _BarRow(
                    part: parts[index],
                    share: parts[index].value / total,
                    largest: parts.first.value / total,
                    money: money,
                    colors: colors,
                    still: still,
                  ),
                ),
            ],
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth >= constraints.maxHeight * 1.35 &&
                constraints.maxWidth >= 360;
            final hovered = _hovered;
            final focus = hovered == null || hovered >= parts.length
                ? null
                : parts[hovered];
            final donut = FinanceDonut(
              palette: palette,
              still: still,
              hovered: _hovered,
              onHover: (index) => setState(() => _hovered = index),
              slices: [
                for (final part in parts)
                  DonutSlice(
                    label: part.label,
                    value: part.value,
                    color: part.color,
                  ),
              ],
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    focus?.label ?? LocaleKeys.dashboard_money_total.tr(),
                    maxLines: 1,
                    style: financeLabel(palette.textMuted, size: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    money.fit(focus?.value ?? total),
                    maxLines: 1,
                    style: financeNumber(palette.textPrimary, size: 17),
                  ),
                  if (focus != null)
                    Text(
                      formatPercent(
                        focus.value / total * 100,
                        decimals: 1,
                        signed: false,
                      ),
                      style: financeNumber(focus.color, size: 12),
                    ),
                ],
              ),
            );
            final legend = ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: !side,
              children: [
                for (var index = 0; index < parts.length; index++)
                  MouseRegion(
                    onEnter: (_) => setState(() => _hovered = index),
                    onExit: (_) => setState(() => _hovered = null),
                    child: _LegendRow(
                      part: parts[index],
                      share: parts[index].value / total,
                      money: money,
                      colors: colors,
                      highlighted: _hovered == index,
                    ),
                  ),
              ],
            );
            if (side) {
              return Row(
                children: [
                  Expanded(flex: 5, child: donut),
                  const SizedBox(width: 14),
                  Expanded(flex: 6, child: legend),
                ],
              );
            }
            return Column(
              children: [
                Expanded(flex: 6, child: donut),
                const SizedBox(height: 10),
                Expanded(flex: 5, child: legend),
              ],
            );
          },
        );
      },
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.part,
    required this.share,
    required this.money,
    required this.colors,
    required this.highlighted,
  });

  final _Part part;
  final double share;
  final MoneyStyle money;
  final FinanceColors colors;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final icon = part.icon;
    return AnimatedContainer(
      duration: DashboardMetrics.hover,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.wash(part.color, 0.1)
            : part.color.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          if (icon != null)
            FinanceIconTile(
              icon: icon,
              color: part.color,
              colors: colors,
              size: 24,
              soft: true,
            )
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: part.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              part.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: financeLabel(
                palette.textPrimary,
                size: 12.5,
                weight: highlighted ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatPercent(share * 100, decimals: 1, signed: false),
            style: financeNumber(palette.textSecondary, size: 12),
          ),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.part,
    required this.share,
    required this.largest,
    required this.money,
    required this.colors,
    required this.still,
  });

  final _Part part;
  final double share;
  final double largest;
  final MoneyStyle money;
  final FinanceColors colors;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  part.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: financeLabel(
                    palette.textPrimary,
                    size: 12.5,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                money.fit(part.value),
                style: financeNumber(palette.textSecondary, size: 12),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                child: Text(
                  formatPercent(share * 100, decimals: 1, signed: false),
                  textAlign: TextAlign.end,
                  style: financeNumber(palette.textPrimary, size: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (context, constraints) => TweenAnimationBuilder<double>(
              tween: Tween(begin: still ? 1 : 0, end: 1),
              duration:
                  still ? Duration.zero : const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, grow, _) => Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette.isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : palette.sunken,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Container(
                    height: 8,
                    width: constraints.maxWidth *
                        (largest <= 0 ? 0 : share / largest) *
                        grow,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        colors: colors.gradientOf(part.color).reversed.toList(),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: part.color.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- P&L calendar

/// A daily P&L read from a table: the date column against the P&L column,
/// summed per day.
TimeSeries _dailyPnl(ChartTable table, Map<String, Object?> settings) =>
    readSeries(
      table,
      valueRole: SeriesRoles.pnl,
      settings: settings,
      fallbackToNumeric: false,
    ).perDay();

final _pnlCalendar = DashboardWidgetDefinition(
  type: 'pnl_calendar',
  label: () => LocaleKeys.dashboard_money_pnlCalendar.tr(),
  description: () => LocaleKeys.dashboard_money_pnlCalendarHint.tr(),
  icon: Icons.calendar_month_rounded,
  group: DashboardWidgetGroup.money,
  defaultRowSpan: 8,
  minimumColumnSpan: 3,
  minimumRowSpan: 5,
  identity: DashboardAccent.green,
  defaultTitle: () => LocaleKeys.dashboard_money_pnlCalendar.tr(),
  keywords: const ['pnl', 'p&l', 'calendar', 'trading days', 'journal'],
  builder: (data) => _PnlCalendar(data: data),
  configure: (data) => [
    financeTableField(data),
    financeCurrencyField(data),
    financeColumnsField(data, [
      (SeriesRoles.date, LocaleKeys.dashboard_money_date.tr()),
      (SeriesRoles.pnl, LocaleKeys.dashboard_money_pnlColumn.tr()),
    ]),
  ],
);

class _PnlCalendar extends StatefulWidget {
  const _PnlCalendar({required this.data});

  final DashboardWidgetContext data;

  @override
  State<_PnlCalendar> createState() => _PnlCalendarState();
}

class _PnlCalendarState extends State<_PnlCalendar> {
  DateTime? _month;
  bool _forward = true;

  void _move(int months, DateTime from) {
    setState(() {
      _forward = months > 0;
      _month = DateTime(from.year, from.month + months);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    return FinanceView(
      data: data,
      builder: (context, feed) {
        if (!feed.bound) {
          return _pickTable(
            data,
            FinanceGhostShape.grid,
            Icons.calendar_month_rounded,
          );
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final daily = _dailyPnl(feed.table, data.spec.settings);
        if (daily.isEmpty) {
          return _pickTable(
            data,
            FinanceGhostShape.grid,
            Icons.calendar_month_rounded,
          );
        }
        final money = financeMoney(data);
        final latest = daily.last!.time;
        final month = _month ?? DateTime(latest.year, latest.month);
        final values = <DateTime, double>{
          for (final point in daily.points) point.time: point.value,
        };
        var total = 0.0;
        var green = 0;
        var red = 0;
        for (final point in daily.points) {
          if (point.time.year == month.year &&
              point.time.month == month.month) {
            total += point.value;
            if (point.value > 0) {
              green++;
            } else if (point.value < 0) {
              red++;
            }
          }
        }
        final weekdays = [
          for (var day = 0; day < 7; day++)
            DateFormat.E().format(DateTime(2024, 1, 1 + day)).substring(0, 1),
        ];
        return Column(
          children: [
            Row(
              children: [
                DashboardIconButton(
                  icon: Icons.chevron_left_rounded,
                  palette: palette,
                  size: 24,
                  tooltip: LocaleKeys.dashboard_money_previousMonth.tr(),
                  onPressed: () => _move(-1, month),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        DateFormat.yMMMM().format(month),
                        maxLines: 1,
                        style: financeLabel(
                          palette.textPrimary,
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        money.fit(total, signed: true),
                        style: financeNumber(colors.change(total), size: 12),
                      ),
                    ],
                  ),
                ),
                DashboardIconButton(
                  icon: Icons.chevron_right_rounded,
                  palette: palette,
                  size: 24,
                  tooltip: LocaleKeys.dashboard_money_nextMonth.tr(),
                  onPressed: () => _move(1, month),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : DashboardMetrics.settle,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(_forward ? 0.08 : -0.08, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: FinanceCalendar(
                  key: ValueKey(month),
                  month: month,
                  values: values,
                  colors: colors,
                  palette: palette,
                  weekdays: weekdays,
                  today: DateTime.now(),
                  formatValue: (value) => money.compact(value, signed: true),
                  formatDay: (day) => DateFormat.yMMMEd().format(day),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DayCount(
                  color: colors.gain,
                  text: LocaleKeys.dashboard_money_greenDays.tr(
                    args: ['$green'],
                  ),
                  palette: palette,
                ),
                const SizedBox(width: 16),
                _DayCount(
                  color: colors.loss,
                  text: LocaleKeys.dashboard_money_redDays.tr(args: ['$red']),
                  palette: palette,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DayCount extends StatelessWidget {
  const _DayCount({
    required this.color,
    required this.text,
    required this.palette,
  });

  final Color color;
  final String text;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(text, style: financeLabel(palette.textSecondary)),
        ],
      );
}

// ---------------------------------------------------------------- P&L stats

final _pnlStats = DashboardWidgetDefinition(
  type: 'pnl_stats',
  label: () => LocaleKeys.dashboard_money_pnlStats.tr(),
  description: () => LocaleKeys.dashboard_money_pnlStatsHint.tr(),
  icon: Icons.insights_rounded,
  group: DashboardWidgetGroup.money,
  defaultRowSpan: 5,
  minimumColumnSpan: 3,
  minimumRowSpan: 4,
  identity: DashboardAccent.teal,
  defaultTitle: () => LocaleKeys.dashboard_money_pnlStats.tr(),
  keywords: const [
    'win rate',
    'profit factor',
    'drawdown',
    'streak',
    'trading',
    'stats',
  ],
  builder: (data) => _PnlStats(data: data),
  configure: (data) => [
    financeTableField(data),
    financeCurrencyField(data),
    financeColumnsField(data, [
      (SeriesRoles.date, LocaleKeys.dashboard_money_date.tr()),
      (SeriesRoles.pnl, LocaleKeys.dashboard_money_pnlColumn.tr()),
    ]),
  ],
);

class _PnlStats extends StatelessWidget {
  const _PnlStats({required this.data});

  final DashboardWidgetContext data;

  @override
  Widget build(BuildContext context) {
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    return FinanceView(
      data: data,
      builder: (context, feed) {
        if (!feed.bound) {
          return _pickTable(
            data,
            FinanceGhostShape.bars,
            Icons.insights_rounded,
          );
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final stats = PnlStats.of(_dailyPnl(feed.table, data.spec.settings));
        if (stats.isEmpty) {
          return _pickTable(
            data,
            FinanceGhostShape.bars,
            Icons.insights_rounded,
          );
        }
        final money = financeMoney(data);
        final winRate = stats.winRate ?? 0;
        final streak = stats.streak;
        final tiles = [
          (
            LocaleKeys.dashboard_money_netPnl.tr(),
            money.fit(stats.total, signed: true),
            colors.change(stats.total),
          ),
          (
            LocaleKeys.dashboard_money_profitFactor.tr(),
            stats.profitFactor == null
                ? '∞'
                : stats.profitFactor!.toStringAsFixed(2),
            (stats.profitFactor ?? 2) >= 1 ? colors.gain : colors.loss,
          ),
          (
            LocaleKeys.dashboard_money_averageWin.tr(),
            money.fit(stats.averageWin),
            colors.gain,
          ),
          (
            LocaleKeys.dashboard_money_averageLoss.tr(),
            money.fit(-stats.averageLoss),
            colors.loss,
          ),
          (
            LocaleKeys.dashboard_money_maxDrawdown.tr(),
            money.fit(-stats.drawdown.amount),
            colors.loss,
          ),
          (
            LocaleKeys.dashboard_money_streak.tr(),
            streak >= 0
                ? LocaleKeys.dashboard_money_winStreak.tr(args: ['$streak'])
                : LocaleKeys.dashboard_money_lossStreak
                    .tr(args: ['${-streak}']),
            streak >= 0 ? colors.gain : colors.loss,
          ),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final ringSize = math.min(
              constraints.maxHeight,
              math.min(132.0, constraints.maxWidth * 0.36),
            );
            final columns = constraints.maxWidth - ringSize - 18 >= 300 ? 3 : 2;
            final rows = (tiles.length / columns).ceil();
            final shown = math.min(
              tiles.length,
              columns * math.max(1, (constraints.maxHeight / 44).floor()),
            );
            return Row(
              children: [
                SizedBox.square(
                  dimension: ringSize,
                  child: FinanceRing(
                    value: winRate / 100,
                    still: still,
                    thickness: math.max(6, ringSize * 0.085),
                    track: palette.isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : palette.sunken,
                    colors: [
                      Color.lerp(colors.gain, Colors.white, 0.25)!,
                      colors.gain,
                    ],
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatPercent(
                                winRate,
                                decimals: 0,
                                signed: false,
                              ),
                              style: financeNumber(
                                palette.textPrimary,
                                size: 22,
                                weight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              LocaleKeys.dashboard_money_winRate.tr(),
                              style:
                                  financeLabel(palette.textMuted, size: 10.5),
                            ),
                            Text(
                              LocaleKeys.dashboard_money_tradingDays.tr(
                                args: ['${stats.days}'],
                              ),
                              style: financeLabel(palette.textMuted, size: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var row = 0; row < rows; row++)
                        if (row * columns < shown)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                for (var column = 0; column < columns; column++)
                                  Expanded(
                                    child: row * columns + column < shown
                                        ? FinanceStat(
                                            label: tiles[row * columns + column]
                                                .$1,
                                            value: tiles[row * columns + column]
                                                .$2,
                                            valueColor:
                                                tiles[row * columns + column]
                                                    .$3,
                                            palette: palette,
                                            size: 14,
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
