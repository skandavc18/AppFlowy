import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_binding.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_charts.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_common.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_entry_dialog.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_kit.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/finance/balance_sheet.dart';
import 'package:appflowy/workspace/application/finance/capital_series.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

void registerWealthWidgets() {
  DashboardWidgetRegistry.register(_netWorth);
  DashboardWidgetRegistry.register(_balanceSheet);
  DashboardWidgetRegistry.register(_loans);
}

const _keyHistory = 'history_view';
const _keyHistoryName = 'history_name';
const _keyShow = 'show';

Widget _pickSheet(DashboardWidgetContext data, FinanceGhostShape shape) =>
    FinanceGhost(
      palette: data.palette,
      shape: shape,
      icon: Icons.savings_rounded,
      message: LocaleKeys.dashboard_money_pickBalanceSheet.tr(),
      action:
          data.isTypable ? LocaleKeys.dashboard_money_chooseTable.tr() : null,
      onAction: () => unawaited(financePickTable(data)),
      color: data.tone.strong,
    );

Widget _loading(DashboardWidgetContext data, BuildContext context) => Center(
      child: FinanceShimmer(
        palette: data.palette,
        width: 180,
        height: 14,
        still: financeStill(data, context),
      ),
    );

List<DashboardConfigField> _sheetConfig(DashboardWidgetContext data) => [
      financeTableField(data),
      financeCurrencyField(data),
      financeColumnsField(data, [
        (BalanceRoles.name, LocaleKeys.dashboard_money_name.tr()),
        (BalanceRoles.side, LocaleKeys.dashboard_money_kind.tr()),
        (BalanceRoles.category, LocaleKeys.dashboard_money_category.tr()),
        (BalanceRoles.value, LocaleKeys.dashboard_money_value.tr()),
        (BalanceRoles.invested, LocaleKeys.dashboard_money_invested.tr()),
        (BalanceRoles.borrowed, LocaleKeys.dashboard_money_borrowed.tr()),
        (BalanceRoles.rate, LocaleKeys.dashboard_money_rate.tr()),
        (BalanceRoles.emi, LocaleKeys.dashboard_money_emi.tr()),
      ]),
    ];

BalanceSummary _summaryOf(DashboardWidgetContext data, ChartTable table) =>
    BalanceSummary.of(readBalanceItems(table, settings: data.spec.settings));

String _itemCount(int count) => count == 1
    ? LocaleKeys.dashboard_money_itemsOne.tr()
    : LocaleKeys.dashboard_money_itemsMany.tr(args: ['$count']);

/// [value] written the way [other] beside it is: both short once the larger
/// is, so a pair never mixes ₹1.64 Cr with ₹53,08,000.
String _pairFit(MoneyStyle money, double value, double other) =>
    math.max(value.abs(), other.abs()) >= 1e7
        ? money.compact(value)
        : money.format(value);

// ----------------------------------------------------------------- net worth

final _netWorth = DashboardWidgetDefinition(
  type: 'net_worth',
  label: () => LocaleKeys.dashboard_money_netWorth.tr(),
  description: () => LocaleKeys.dashboard_money_netWorthHint.tr(),
  icon: Icons.savings_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 8,
  defaultRowSpan: 5,
  minimumColumnSpan: 3,
  minimumRowSpan: 3,
  surface: DashboardSurface.gradient,
  identity: DashboardAccent.teal,
  showsTitleByDefault: false,
  padding: EdgeInsets.zero,
  keywords: const [
    'net worth',
    'wealth',
    'assets',
    'liabilities',
    'balance sheet',
    'gold',
    'nps',
    'pf',
  ],
  builder: (data) => _NetWorth(data: data),
  configure: (data) => [
    ..._sheetConfig(data),
    DashboardConfigView(
      label: LocaleKeys.dashboard_money_historyTable.tr(),
      hint: LocaleKeys.dashboard_money_historyHint.tr(),
      viewId: data.spec.setting(_keyHistory),
      name: data.spec.setting(_keyHistoryName),
      filter: financeIsDatabase,
      onChanged: (viewId, name) => data.setSettings({
        _keyHistory: viewId,
        _keyHistoryName: name,
      }),
    ),
  ],
);

class _NetWorth extends StatelessWidget {
  const _NetWorth({required this.data});

  final DashboardWidgetContext data;

  @override
  Widget build(BuildContext context) {
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    return FinanceView(
      data: data,
      secondaryViewId: data.spec.setting(_keyHistory),
      builder: (context, feed) {
        if (!feed.bound) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _pickSheet(data, FinanceGhostShape.line),
          );
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final summary = _summaryOf(data, feed.table);
        final money = financeMoney(data);
        final history = readSeries(feed.secondary);
        final change = history.change;
        final ink = data.tone.label;
        final debtColor = colors.loss;
        final worthColor = data.tone.strong;
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight - 34;
            final roomy = height >= 120;
            final tall = height >= 175;
            final wide = constraints.maxWidth >= 600 && tall;
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FinanceEyebrow(
                  LocaleKeys.dashboard_money_netWorth.tr(),
                  color: ink,
                  trailing: change == null || wide
                      ? null
                      : ChangePill(
                          colors: colors,
                          value: change,
                          dense: true,
                          text: formatPercent(
                            history.changePercent,
                            decimals: 1,
                            signed: false,
                          ),
                        ),
                ),
                SizedBox(height: roomy ? 10 : 6),
                AnimatedFigure(
                  value: summary.netWorth,
                  format: (value) => money.fit(value, from: 1e9),
                  countUp: true,
                  still: still,
                  style: DashboardType.display(
                    palette,
                    size: roomy && constraints.maxWidth >= 360 ? 40 : 30,
                    weight: FontWeight.w600,
                    color: data.tone.figure,
                  ),
                ),
                SizedBox(height: roomy ? 12 : 8),
                // One style for both figures: ₹1.64 Cr beside ₹53,08,000
                // reads as two different kinds of number.
                FinanceRun(
                  height: 20,
                  spacing: 18,
                  children: [
                    _Dot(
                      color: worthColor,
                      label: LocaleKeys.dashboard_money_assets.tr(),
                      value:
                          _pairFit(money, summary.assets, summary.liabilities),
                      palette: palette,
                    ),
                    _Dot(
                      color: debtColor,
                      label: LocaleKeys.dashboard_money_liabilities.tr(),
                      value:
                          _pairFit(money, summary.liabilities, summary.assets),
                      palette: palette,
                    ),
                  ],
                ),
                if (roomy) ...[
                  const Spacer(),
                  if (summary.assets > 0)
                    FinanceStackedBar(
                      palette: palette,
                      still: still,
                      height: 12,
                      segments: [
                        StackSegment(
                          label: LocaleKeys.dashboard_money_netWorth.tr(),
                          value: math.max(0, summary.netWorth),
                          color: worthColor,
                        ),
                        StackSegment(
                          label: LocaleKeys.dashboard_money_liabilities.tr(),
                          value: math.min(summary.liabilities, summary.assets),
                          color: debtColor,
                        ),
                      ],
                      describe: (segment, share) =>
                          '${segment.label} · ${money.fit(segment.value)} · '
                          '${formatPercent(share * 100, decimals: 1, signed: false)}',
                    ),
                ],
                if (tall) ...[
                  const SizedBox(height: 12),
                  FinanceRun(
                    height: 26,
                    children: [
                      _Pill(
                        label: LocaleKeys.dashboard_money_liquid.tr(),
                        value: formatPercent(
                          summary.liquidShare,
                          decimals: 0,
                          signed: false,
                        ),
                        palette: palette,
                      ),
                      _Pill(
                        label: LocaleKeys.dashboard_money_lockedIn.tr(),
                        value: money.fit(summary.locked),
                        palette: palette,
                      ),
                      _Pill(
                        label: LocaleKeys.dashboard_money_debtRatio.tr(),
                        value: formatPercent(
                          summary.debtRatio,
                          decimals: 1,
                          signed: false,
                        ),
                        palette: palette,
                        color:
                            (summary.debtRatio ?? 0) > 40 ? colors.loss : null,
                      ),
                      if (summary.monthlyEmi > 0)
                        _Pill(
                          label: LocaleKeys.dashboard_money_monthlyEmi.tr(),
                          value: money.fit(summary.monthlyEmi),
                          palette: palette,
                        ),
                    ],
                  ),
                ],
              ],
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: FinanceOrbs(
                    colors: colors,
                    first: worthColor,
                    second: colors.hue(1),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 20, 16),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: main),
                            const SizedBox(width: 18),
                            SizedBox(
                              width: math.min(260, constraints.maxWidth * 0.36),
                              child: _WorthPanel(
                                summary: summary,
                                history: history,
                                money: money,
                                colors: colors,
                                tone: data.tone,
                                still: still,
                              ),
                            ),
                          ],
                        )
                      : main,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.label,
    required this.value,
    required this.palette,
  });

  final Color color;
  final String label;
  final String value;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label  ',
            style: financeLabel(palette.textSecondary, size: 12),
          ),
          Text(value, style: financeNumber(palette.textPrimary)),
        ],
      );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.value,
    required this.palette,
    this.color,
  });

  final String label;
  final String value;
  final DashboardPalette palette;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: palette.isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: palette.isPaper ? 0.45 : 0.62),
          borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label  ',
                style: financeLabel(palette.textSecondary, size: 11),
              ),
              TextSpan(
                text: value,
                style: financeNumber(color ?? palette.textPrimary, size: 11.5),
              ),
            ],
          ),
          maxLines: 1,
        ),
      );
}

class _WorthPanel extends StatelessWidget {
  const _WorthPanel({
    required this.summary,
    required this.history,
    required this.money,
    required this.colors,
    required this.tone,
    required this.still,
  });

  final BalanceSummary summary;
  final TimeSeries history;
  final MoneyStyle money;
  final FinanceColors colors;
  final DashboardTone tone;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final change = history.change;
    final decoration = BoxDecoration(
      color: palette.isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.white.withValues(alpha: palette.isPaper ? 0.38 : 0.55),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Colors.white.withValues(alpha: palette.isDark ? 0.06 : 0.75),
      ),
    );
    if (history.length >= 2) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleKeys.dashboard_money_sinceDate.tr(
                      args: [DateFormat.yMMM().format(history.first!.time)],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: financeLabel(palette.textMuted, size: 11),
                  ),
                ),
                if (change != null)
                  ChangePill(
                    colors: colors,
                    value: change,
                    dense: true,
                    text: formatPercent(
                      history.changePercent,
                      decimals: 1,
                      signed: false,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (change != null)
              Text(
                money.fit(change, signed: true),
                style: financeNumber(colors.change(change), size: 15),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: FinanceSparkline(
                values: [for (final point in history.points) point.value],
                color: tone.strong,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      );
    }
    // No history yet: how quickly the assets could become cash.
    final parts = [
      (BalanceLiquidity.liquid, summary.liquid, colors.gain),
      (BalanceLiquidity.moderate, summary.moderate, colors.hue(3)),
      (BalanceLiquidity.locked, summary.locked, colors.hue(0)),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: decoration,
      child: Row(
        children: [
          Expanded(
            child: FinanceDonut(
              palette: palette,
              still: still,
              thickness: 0.3,
              slices: [
                for (final (liquidity, value, color) in parts)
                  DonutSlice(
                    label: balanceLiquidityLabel(liquidity),
                    value: value,
                    color: color,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (liquidity, value, color) in parts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        balanceLiquidityLabel(liquidity),
                        style: financeLabel(palette.textSecondary, size: 11),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatPercent(
                          percentOf(value, summary.assets),
                          decimals: 0,
                          signed: false,
                        ),
                        style: financeNumber(palette.textPrimary, size: 11),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ balance sheet

enum _Show { assets, liabilities, both }

_Show _showOf(DashboardWidgetContext data) => _Show.values.firstWhere(
      (show) => show.name == data.spec.setting(_keyShow, fallback: 'assets'),
      orElse: () => _Show.assets,
    );

final _balanceSheet = DashboardWidgetDefinition(
  type: 'balance_sheet',
  label: () => LocaleKeys.dashboard_money_balanceSheet.tr(),
  description: () => LocaleKeys.dashboard_money_balanceSheetHint.tr(),
  icon: Icons.account_balance_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 12,
  defaultRowSpan: 7,
  minimumColumnSpan: 3,
  minimumRowSpan: 4,
  identity: DashboardAccent.teal,
  defaultTitle: () => LocaleKeys.dashboard_money_balanceSheet.tr(),
  keywords: const [
    'balance sheet',
    'assets',
    'gold',
    'real estate',
    'provident fund',
    'nps',
    'mutual funds',
    'fixed deposits',
  ],
  headerTrailing: (data) => FinanceSegmented<_Show>(
    palette: data.palette,
    values: _Show.values,
    selected: _showOf(data),
    labelOf: (show) => switch (show) {
      _Show.assets => LocaleKeys.dashboard_money_showAssets.tr(),
      _Show.liabilities => LocaleKeys.dashboard_money_showLiabilities.tr(),
      _Show.both => LocaleKeys.dashboard_money_showBoth.tr(),
    },
    onSelected: data.isTypable
        ? (show) => data.setSettings({_keyShow: show.name})
        : null,
  ),
  builder: (data) => _BalanceSheet(data: data),
  configure: _sheetConfig,
);

class _BalanceSheet extends StatelessWidget {
  const _BalanceSheet({required this.data});

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
          return _pickSheet(data, FinanceGhostShape.tiles);
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final summary = _summaryOf(data, feed.table);
        final money = financeMoney(data);
        final show = _showOf(data);
        final totals = [
          if (show != _Show.liabilities) ...summary.assetCategories,
          if (show != _Show.assets) ...summary.liabilityCategories,
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = financeColumnsFor(constraints.maxWidth, 215);
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Column(
              children: [
                Expanded(
                  child: totals.isEmpty
                      ? Center(
                          child: Text(
                            LocaleKeys.dashboard_money_pickBalanceSheet.tr(),
                            style: DashboardType.caption(palette),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (var index = 0;
                                  index < totals.length;
                                  index++)
                                SizedBox(
                                  width: width,
                                  child: FinanceEntrance(
                                    index: index,
                                    still: still,
                                    child: _CategoryTile(
                                      total: totals[index],
                                      share: totals[index].category.isAsset
                                          ? percentOf(
                                              totals[index].value,
                                              summary.assets,
                                            )
                                          : percentOf(
                                              totals[index].value,
                                              summary.liabilities,
                                            ),
                                      money: money,
                                      colors: colors,
                                      still: still,
                                      onTap: () => _showCategory(
                                        context,
                                        data,
                                        totals[index],
                                        money,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                if (data.isTypable) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: DashboardButton(
                      label: LocaleKeys.dashboard_money_addEntry.tr(),
                      palette: palette,
                      icon: Icons.add_rounded,
                      onPressed: () => _addEntry(context, data, feed.table),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.total,
    required this.share,
    required this.money,
    required this.colors,
    required this.still,
    required this.onTap,
  });

  final CategoryTotal total;
  final double? share;
  final MoneyStyle money;
  final FinanceColors colors;
  final bool still;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final category = total.category;
    final hue = balanceCategoryColor(category, colors);
    final gain = total.gainPercent;
    return FinanceHover(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: DashboardMetrics.settle,
        curve: DashboardMetrics.curve,
        transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: colors.panel(hovered: hovered, hue: hue, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FinanceIconTile(
                  icon: balanceCategoryIcon(category),
                  color: hue,
                  colors: colors,
                  size: 38,
                ),
                const Spacer(),
                if (share != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.wash(hue, 0.12),
                      borderRadius:
                          BorderRadius.circular(DashboardMetrics.pillRadius),
                    ),
                    child: Text(
                      formatPercent(share, decimals: 0, signed: false),
                      style: financeNumber(hue, size: 11.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              balanceCategoryLabel(category),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: financeLabel(
                palette.textPrimary,
                size: 13.5,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_itemCount(total.items.length)} · '
              '${balanceLiquidityLabel(category.liquidity)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: financeLabel(palette.textMuted, size: 11),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AnimatedFigure(
                    value: total.value,
                    format: (value) => money.fit(value),
                    still: still,
                    style: financeNumber(
                      palette.textPrimary,
                      size: 19,
                      weight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (gain != null)
                  ChangePill(
                    colors: colors,
                    value: gain,
                    dense: true,
                    text: formatPercent(gain, decimals: 1, signed: false),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 4,
                child: Stack(
                  children: [
                    Container(
                      color: palette.isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : palette.sunken,
                    ),
                    FractionallySizedBox(
                      widthFactor: ((share ?? 0) / 100).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [hue.withValues(alpha: 0.6), hue],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showCategory(
  BuildContext context,
  DashboardWidgetContext data,
  CategoryTotal total,
  MoneyStyle money,
) {
  final palette = data.palette;
  final colors = FinanceColors.of(palette);
  final hue = balanceCategoryColor(total.category, colors);
  unawaited(
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: palette.isDark ? 0.5 : 0.28),
      builder: (dialogContext) => Dialog(
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.border.withValues(alpha: 0.5)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    FinanceIconTile(
                      icon: balanceCategoryIcon(total.category),
                      color: hue,
                      colors: colors,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            balanceCategoryLabel(total.category),
                            style: DashboardType.title(palette, size: 19),
                          ),
                          Text(
                            '${_itemCount(total.items.length)} · '
                            '${balanceLiquidityLabel(total.category.liquidity)}',
                            style: DashboardType.caption(palette),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money.fit(total.value),
                      style: financeNumber(
                        palette.textPrimary,
                        size: 22,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    DashboardIconButton(
                      icon: Icons.close_rounded,
                      palette: palette,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: total.items.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: palette.border.withValues(alpha: 0.35),
                    ),
                    itemBuilder: (context, index) => _ItemLine(
                      item: total.items[index],
                      money: money,
                      colors: colors,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({
    required this.item,
    required this.money,
    required this.colors,
  });

  final BalanceItem item;
  final MoneyStyle money;
  final FinanceColors colors;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final gain = item.gainPercent;
    final details = [
      if (item.categoryLabel.isNotEmpty) item.categoryLabel,
      if (item.invested != null)
        '${LocaleKeys.dashboard_money_invested.tr()} ${money.fit(item.invested!)}',
      if (item.rate != null)
        '${LocaleKeys.dashboard_money_rate.tr()} ${formatPercent(item.rate, signed: false)}',
      if (item.emi != null)
        '${LocaleKeys.dashboard_money_emi.tr()} ${money.fit(item.emi!)}',
      if (item.updated != null)
        '${LocaleKeys.dashboard_money_updatedOn.tr()} ${DateFormat.yMMMd().format(item.updated!)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: financeLabel(
                    palette.textPrimary,
                    size: 13.5,
                    weight: FontWeight.w600,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: financeLabel(palette.textMuted),
                  ),
                if (item.notes.isNotEmpty)
                  Text(
                    item.notes,
                    style: financeLabel(palette.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money.fit(item.value),
                style: financeNumber(palette.textPrimary, size: 14),
              ),
              if (gain != null)
                Text(
                  formatPercent(gain, decimals: 1),
                  style: financeNumber(colors.change(gain), size: 11.5),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

void _addEntry(
  BuildContext context,
  DashboardWidgetContext data,
  ChartTable table,
) {
  final items = readBalanceItems(table, settings: data.spec.settings);
  final categories = {
    for (final item in items)
      if (item.categoryLabel.isNotEmpty) item.categoryLabel,
  }.toList()
    ..sort();
  final sideColumn = FinanceColumns.resolve(
    table,
    BalanceRoles.all,
    settings: data.spec.settings,
  )[BalanceRoles.side];
  final sheet = FinanceSheet(table);
  final sides = {
    for (var row = 0; row < sheet.length; row++) sheet.text(row, sideColumn),
  }.where((value) => value.isNotEmpty).toList();
  unawaited(
    showFinanceEntryDialog(
      context: context,
      palette: data.palette,
      title: LocaleKeys.dashboard_money_addEntry.tr(),
      icon: Icons.savings_rounded,
      color: data.tone.strong,
      fields: [
        FinanceEntryField(
          key: BalanceRoles.name.key,
          label: LocaleKeys.dashboard_money_name.tr(),
          required: true,
          wide: true,
        ),
        FinanceEntryField(
          key: BalanceRoles.side.key,
          label: LocaleKeys.dashboard_money_kind.tr(),
          kind: FinanceFieldKind.choice,
          options: sides,
          initial: sides.isEmpty ? '' : sides.first,
        ),
        FinanceEntryField(
          key: BalanceRoles.category.key,
          label: LocaleKeys.dashboard_money_category.tr(),
          kind: FinanceFieldKind.choice,
          options: categories,
        ),
        FinanceEntryField(
          key: BalanceRoles.value.key,
          label: LocaleKeys.dashboard_money_value.tr(),
          kind: FinanceFieldKind.number,
          required: true,
        ),
        FinanceEntryField(
          key: BalanceRoles.invested.key,
          label: LocaleKeys.dashboard_money_invested.tr(),
          kind: FinanceFieldKind.number,
        ),
        FinanceEntryField(
          key: BalanceRoles.rate.key,
          label: LocaleKeys.dashboard_money_rate.tr(),
          kind: FinanceFieldKind.number,
        ),
        FinanceEntryField(
          key: BalanceRoles.emi.key,
          label: LocaleKeys.dashboard_money_emi.tr(),
          kind: FinanceFieldKind.number,
        ),
        FinanceEntryField(
          key: BalanceRoles.updated.key,
          label: LocaleKeys.dashboard_money_updatedOn.tr(),
          kind: FinanceFieldKind.date,
          initial: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        ),
      ],
      onSave: (values) => financeAddRow(data, table, BalanceRoles.all, values),
    ),
  );
}

// --------------------------------------------------------------------- loans

final _loans = DashboardWidgetDefinition(
  type: 'loans',
  label: () => LocaleKeys.dashboard_money_loans.tr(),
  description: () => LocaleKeys.dashboard_money_loansHint.tr(),
  icon: Icons.hourglass_bottom_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 12,
  defaultRowSpan: 6,
  minimumColumnSpan: 4,
  minimumRowSpan: 4,
  identity: DashboardAccent.red,
  defaultTitle: () => LocaleKeys.dashboard_money_loans.tr(),
  keywords: const [
    'loans',
    'emi',
    'home loan',
    'car loan',
    'debt',
    'credit card',
    'payoff',
  ],
  builder: (data) => _Loans(data: data),
  configure: _sheetConfig,
);

class _Loans extends StatelessWidget {
  const _Loans({required this.data});

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
          return _pickSheet(data, FinanceGhostShape.tiles);
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final summary = _summaryOf(data, feed.table);
        final loans = summary.loans.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final money = financeMoney(data);
        if (loans.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FinanceIconTile(
                  icon: Icons.verified_rounded,
                  color: colors.gain,
                  colors: colors,
                  size: 44,
                ),
                const SizedBox(height: 10),
                Text(
                  LocaleKeys.dashboard_money_noLoans.tr(),
                  style: DashboardType.body(palette),
                ),
              ],
            ),
          );
        }
        final weighted = loans.where((loan) => loan.rate != null).toList();
        final weightedValue =
            weighted.fold<double>(0, (sum, loan) => sum + loan.value);
        final averageRate = weightedValue <= 0
            ? null
            : weighted.fold<double>(
                  0,
                  (sum, loan) => sum + loan.rate! * loan.value,
                ) /
                weightedValue;
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = financeColumnsFor(
              constraints.maxWidth,
              280,
              maximum: 4,
            );
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FinanceRun(
                  height: 44,
                  spacing: 26,
                  children: [
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_outstanding.tr(),
                      value: money.fit(summary.liabilities),
                      valueColor: colors.loss,
                      palette: palette,
                      size: 16,
                    ),
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_monthlyEmi.tr(),
                      value: money.fit(summary.monthlyEmi),
                      palette: palette,
                      size: 16,
                    ),
                    if (averageRate != null)
                      FinanceStat(
                        label: LocaleKeys.dashboard_money_weightedRate.tr(),
                        value: formatPercent(
                          averageRate,
                          signed: false,
                        ),
                        palette: palette,
                        size: 16,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (var index = 0; index < loans.length; index++)
                          SizedBox(
                            width: width,
                            child: FinanceEntrance(
                              index: index,
                              still: still,
                              child: _LoanCard(
                                loan: loans[index],
                                money: money,
                                colors: colors,
                                still: still,
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan,
    required this.money,
    required this.colors,
    required this.still,
  });

  final BalanceItem loan;
  final MoneyStyle money;
  final FinanceColors colors;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final hue = balanceCategoryColor(loan.category, colors);
    final outlook = loan.outlook!;
    final repaid = outlook.repaidShare;
    final months = outlook.monthsLeft;
    final String left;
    if (outlook.neverRepaid) {
      left = LocaleKeys.dashboard_money_neverRepaid.tr();
    } else if (months == null) {
      left = '';
    } else if (months >= 12) {
      left = LocaleKeys.dashboard_money_yearsMonthsLeft.tr(
        args: ['${months ~/ 12}', '${months % 12}'],
      );
    } else {
      left = LocaleKeys.dashboard_money_monthsLeft.tr(args: ['$months']);
    }
    return FinanceHover(
      builder: (context, hovered) => AnimatedContainer(
        duration: DashboardMetrics.settle,
        curve: DashboardMetrics.curve,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: colors.panel(hovered: hovered, hue: hue, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FinanceIconTile(
                  icon: balanceCategoryIcon(loan.category),
                  color: hue,
                  colors: colors,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeLabel(
                          palette.textPrimary,
                          size: 13.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                      // "Home loan" under "Home loan" says nothing.
                      if (balanceCategoryLabel(loan.category).toLowerCase() !=
                          loan.name.trim().toLowerCase())
                        Text(
                          balanceCategoryLabel(loan.category),
                          maxLines: 1,
                          style: financeLabel(palette.textMuted, size: 11),
                        ),
                    ],
                  ),
                ),
                Text(
                  money.fit(loan.value),
                  style: financeNumber(
                    palette.textPrimary,
                    size: 16,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox.square(
                  dimension: 66,
                  child: FinanceRing(
                    value: repaid ?? 0,
                    still: still,
                    thickness: 7,
                    track: palette.isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : palette.sunken,
                    colors: [colors.gain.withValues(alpha: 0.7), colors.gain],
                    child: Text(
                      repaid == null
                          ? '—'
                          : formatPercent(repaid * 100,
                              decimals: 0, signed: false),
                      style: financeNumber(palette.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            if (loan.emi != null)
                              TextSpan(
                                text: '${money.fit(loan.emi!)} ',
                                style: financeNumber(palette.textPrimary),
                              ),
                            if (loan.emi != null)
                              TextSpan(
                                text: LocaleKeys.dashboard_money_emi.tr(),
                                style:
                                    financeLabel(palette.textMuted, size: 11),
                              ),
                            if (loan.rate != null)
                              TextSpan(
                                text: '${loan.emi != null ? '  ·  ' : ''}'
                                    '${formatPercent(loan.rate, signed: false)}',
                                style: financeNumber(
                                  palette.textSecondary,
                                  size: 12,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (left.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          left,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: financeLabel(
                            outlook.neverRepaid
                                ? colors.loss
                                : palette.textSecondary,
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (outlook.payoffDate != null)
                        Text(
                          LocaleKeys.dashboard_money_paidOffBy.tr(
                            args: [
                              DateFormat.yMMM().format(outlook.payoffDate!)
                            ],
                          ),
                          maxLines: 1,
                          style: financeLabel(palette.textMuted, size: 11),
                        ),
                      if (outlook.interestLeft != null &&
                          outlook.interestLeft! > 0)
                        Text(
                          '${LocaleKeys.dashboard_money_interestLeft.tr()} '
                          '${money.fit(outlook.interestLeft!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: financeLabel(colors.loss, size: 11),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
