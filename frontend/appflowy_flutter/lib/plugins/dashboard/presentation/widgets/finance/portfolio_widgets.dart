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
import 'package:appflowy/shared/market/market_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:appflowy/workspace/application/finance/portfolio_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

void registerPortfolioWidgets() {
  DashboardWidgetRegistry.register(_portfolio);
  DashboardWidgetRegistry.register(_holdings);
  DashboardWidgetRegistry.register(_heatmap);
  DashboardWidgetRegistry.register(_watchlist);
}

const _keyGroupBy = 'group_by';
const _keySort = 'sort';
const _keyColourBy = 'colour_by';
const _keySymbols = 'symbols';

List<DashboardConfigField> _holdingsConfig(DashboardWidgetContext data) => [
      financeTableField(data),
      financeCurrencyField(data),
      financeColumnsField(data, [
        (FinanceRole.name, LocaleKeys.dashboard_money_name.tr()),
        (FinanceRole.symbol, LocaleKeys.dashboard_money_symbol.tr()),
        (FinanceRole.quantity, LocaleKeys.dashboard_money_quantity.tr()),
        (
          FinanceRole.averagePrice,
          LocaleKeys.dashboard_money_averagePrice.tr()
        ),
        (FinanceRole.lastPrice, LocaleKeys.dashboard_money_lastPrice.tr()),
        (FinanceRole.sector, LocaleKeys.dashboard_money_sector.tr()),
        (FinanceRole.date, LocaleKeys.dashboard_money_boughtOn.tr()),
      ]),
    ];

Widget _pickHoldings(DashboardWidgetContext data, FinanceGhostShape shape) =>
    FinanceGhost(
      palette: data.palette,
      shape: shape,
      icon: Icons.show_chart_rounded,
      message: LocaleKeys.dashboard_money_pickHoldings.tr(),
      action:
          data.isTypable ? LocaleKeys.dashboard_money_chooseTable.tr() : null,
      onAction: () => unawaited(financePickTable(data)),
      color: data.tone.strong,
    );

Widget _reading(DashboardPalette palette, bool still) => Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceShimmer(palette: palette, width: 120, still: still),
          const SizedBox(height: 14),
          FinanceShimmer(
            palette: palette,
            width: 220,
            height: 30,
            still: still,
          ),
          const SizedBox(height: 14),
          FinanceShimmer(palette: palette, height: 10, still: still),
          const SizedBox(height: 8),
          FinanceShimmer(
            palette: palette,
            width: 180,
            height: 10,
            still: still,
          ),
        ],
      ),
    );

/// What the portfolio was worth on each of the past month's trading days,
/// from each holding's daily closes. Holdings with no history count at
/// today's value throughout.
List<double> portfolioHistory(List<PricedHolding> holdings) {
  final tracked = [
    for (final holding in holdings)
      if (holding.intraday.length >= 2 && holding.holding.quantity > 0) holding,
  ];
  if (tracked.isEmpty) {
    return const [];
  }
  final length =
      tracked.map((holding) => holding.intraday.length).reduce(math.min);
  final fixed = holdings
      .where((holding) => !tracked.contains(holding))
      .fold<double>(0, (sum, holding) => sum + holding.value);
  return [
    for (var index = 0; index < length; index++)
      fixed +
          tracked.fold<double>(0, (sum, holding) {
            final closes = holding.intraday;
            return sum +
                closes[closes.length - length + index] *
                    holding.holding.quantity;
          }),
  ];
}

// ----------------------------------------------------------------- portfolio

final _portfolio = DashboardWidgetDefinition(
  type: 'portfolio',
  label: () => LocaleKeys.dashboard_money_portfolio.tr(),
  description: () => LocaleKeys.dashboard_money_portfolioHint.tr(),
  icon: Icons.payments_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 8,
  defaultRowSpan: 5,
  minimumColumnSpan: 3,
  minimumRowSpan: 3,
  surface: DashboardSurface.gradient,
  identity: DashboardAccent.blue,
  showsTitleByDefault: false,
  padding: EdgeInsets.zero,
  keywords: const [
    'portfolio',
    'stocks',
    'investments',
    'holdings',
    'returns',
    'xirr',
    'wealth',
  ],
  builder: (data) => _PortfolioHero(data: data),
  configure: (data) => [
    ..._holdingsConfig(data),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_money_allocation.tr(),
      value: data.spec.setting(_keyGroupBy, fallback: 'sector'),
      choices: [
        DashboardChoice(
          value: 'sector',
          label: LocaleKeys.dashboard_money_sector.tr(),
        ),
        DashboardChoice(
          value: 'holding',
          label: LocaleKeys.dashboard_money_holdings.tr(),
        ),
      ],
      onChanged: (value) => data.setSettings({_keyGroupBy: value}),
    ),
  ],
);

class _PortfolioHero extends StatelessWidget {
  const _PortfolioHero({required this.data});

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
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _pickHoldings(data, FinanceGhostShape.line),
          );
        }
        if (feed.loading) {
          return Padding(
            padding: const EdgeInsets.all(22),
            child: _reading(palette, still),
          );
        }
        final holdings = priceHoldings(
          Holding.read(feed.table, settings: data.spec.settings),
          feed.market,
        );
        final snapshot = PortfolioSnapshot.of(holdings);
        final money = financeMoney(data);
        final updated = latestUpdate(
          feed.market,
          holdings.map((holding) => holding.holding.symbol),
        );
        final bySector =
            data.spec.setting(_keyGroupBy, fallback: 'sector') == 'sector';
        final slices = snapshot.allocation(
          (holding) => bySector && holding.holding.sector.isNotEmpty
              ? holding.holding.sector
              : (holding.holding.symbol.isEmpty
                  ? holding.holding.name
                  : marketDisplayName(holding.holding.symbol)),
          maxSlices: 6,
          otherLabel: LocaleKeys.dashboard_money_otherSlice.tr(),
        );
        final history = portfolioHistory(holdings);
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight - 34;
            final tall = height >= 180;
            final roomy = height >= 120;
            final wide = constraints.maxWidth >= 600 && tall;
            final figureSize =
                constraints.maxWidth < 360 || !roomy ? 30.0 : 40.0;
            final ink = data.tone.label;
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FinanceEyebrow(
                  LocaleKeys.dashboard_money_portfolioValue.tr(),
                  color: ink,
                  trailing: wide
                      ? null
                      : Flexible(
                          child: FinanceFreshness(
                            palette: palette,
                            colors: colors,
                            market: feed.market,
                            updated: updated,
                            still: still,
                            ink: ink,
                          ),
                        ),
                ),
                SizedBox(height: roomy ? 10 : 6),
                AnimatedFigure(
                  value: snapshot.value,
                  format: (value) => money.format(value),
                  countUp: true,
                  still: still,
                  style: DashboardType.display(
                    palette,
                    size: figureSize,
                    weight: FontWeight.w600,
                    color: data.tone.figure,
                  ),
                ),
                SizedBox(height: roomy ? 12 : 8),
                FinanceRun(
                  height: 32,
                  children: [
                    if (snapshot.liveCount > 0)
                      _HeroChange(
                        label: LocaleKeys.dashboard_money_today.tr(),
                        amount: snapshot.dayChange,
                        percent: snapshot.dayPercent,
                        money: money,
                        colors: colors,
                      ),
                    _HeroChange(
                      label: LocaleKeys.dashboard_money_overall.tr(),
                      amount: snapshot.pnl,
                      percent: snapshot.pnlPercent,
                      money: money,
                      colors: colors,
                    ),
                  ],
                ),
                if (roomy) const Spacer(),
                if (tall) ...[
                  FinanceRun(
                    height: 17,
                    spacing: 18,
                    children: [
                      _InlineStat(
                        label: LocaleKeys.dashboard_money_invested.tr(),
                        value: money.fit(snapshot.invested),
                        palette: palette,
                      ),
                      if (snapshot.xirr != null)
                        _InlineStat(
                          label: LocaleKeys.dashboard_money_xirr.tr(),
                          value: formatPercent(snapshot.xirr, decimals: 1),
                          palette: palette,
                          color: colors.change(snapshot.xirr),
                        ),
                      _InlineStat(
                        label: '',
                        value: LocaleKeys.dashboard_money_holdingsCount.tr(
                          args: ['${holdings.length}'],
                        ),
                        palette: palette,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (roomy && slices.isNotEmpty) ...[
                  FinanceStackedBar(
                    palette: palette,
                    still: still,
                    segments: [
                      for (var index = 0; index < slices.length; index++)
                        StackSegment(
                          label: slices[index].label,
                          value: slices[index].value,
                          color: sliceColor(
                            colors,
                            index,
                            other: slices[index].isOther,
                          ),
                        ),
                    ],
                    describe: (segment, share) =>
                        '${segment.label} · ${formatPercent(share * 100, decimals: 1, signed: false)}'
                        ' · ${money.fit(segment.value)}',
                  ),
                  if (tall) ...[
                    const SizedBox(height: 9),
                    _Legend(
                      slices: slices,
                      colors: colors,
                      palette: palette,
                    ),
                  ],
                ],
              ],
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: FinanceOrbs(
                    colors: colors,
                    first: data.tone.strong,
                    second: colors.hue(5),
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
                              child: _MoversPanel(
                                snapshot: snapshot,
                                history: history,
                                palette: palette,
                                colors: colors,
                                money: money,
                                market: feed.market,
                                updated: updated,
                                still: still,
                                tone: data.tone,
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

class _HeroChange extends StatelessWidget {
  const _HeroChange({
    required this.label,
    required this.amount,
    required this.percent,
    required this.money,
    required this.colors,
  });

  final String label;
  final double amount;
  final double? percent;
  final MoneyStyle money;
  final FinanceColors colors;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final color = colors.change(amount);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        color: palette.isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: palette.isPaper ? 0.45 : 0.62),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: palette.isDark ? 0.06 : 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: financeLabel(palette.textSecondary),
          ),
          const SizedBox(width: 8),
          Text(
            money.fit(amount, signed: true),
            style: financeNumber(color),
          ),
          const SizedBox(width: 6),
          ChangePill(
            colors: colors,
            value: amount,
            dense: true,
            text: formatPercent(percent, signed: false),
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
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
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          children: [
            if (label.isNotEmpty)
              TextSpan(
                text: '$label  ',
                style: financeLabel(palette.textMuted),
              ),
            TextSpan(
              text: value,
              style: financeNumber(color ?? palette.textPrimary, size: 12.5),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.slices,
    required this.colors,
    required this.palette,
  });

  final List<AllocationSlice> slices;
  final FinanceColors colors;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => FinanceRun(
        height: 16,
        spacing: 12,
        children: [
          for (var index = 0; index < math.min(slices.length, 6); index++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: sliceColor(
                      colors,
                      index,
                      other: slices[index].isOther,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  slices[index].label,
                  style: financeLabel(palette.textSecondary, size: 11),
                ),
                const SizedBox(width: 4),
                Text(
                  formatPercent(
                    slices[index].share * 100,
                    decimals: 0,
                    signed: false,
                  ),
                  style: financeNumber(palette.textMuted, size: 11),
                ),
              ],
            ),
        ],
      );
}

class _MoversPanel extends StatelessWidget {
  const _MoversPanel({
    required this.snapshot,
    required this.history,
    required this.palette,
    required this.colors,
    required this.money,
    required this.market,
    required this.updated,
    required this.still,
    required this.tone,
  });

  final PortfolioSnapshot snapshot;
  final List<double> history;
  final DashboardPalette palette;
  final FinanceColors colors;
  final MoneyStyle money;
  final MarketWatch market;
  final DateTime? updated;
  final bool still;
  final DashboardTone tone;

  @override
  Widget build(BuildContext context) {
    final best = snapshot.bestToday;
    final worst = snapshot.worstToday;
    final movers = [
      if (best != null && (best.dayPercent ?? 0) > 0) best,
      if (worst != null &&
          !identical(worst, best) &&
          (worst.dayPercent ?? 0) < 0)
        worst,
    ];
    final monthChange =
        history.length >= 2 ? history.last - history.first : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: palette.isPaper ? 0.38 : 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: palette.isDark ? 0.06 : 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceFreshness(
            palette: palette,
            colors: colors,
            market: market,
            updated: updated,
            still: still,
          ),
          if (history.length >= 2) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleKeys.dashboard_money_pastMonth.tr(),
                    style: financeLabel(palette.textMuted, size: 11),
                  ),
                ),
                if (monthChange != null)
                  Text(
                    formatPercent(
                      history.first == 0
                          ? null
                          : monthChange / history.first * 100,
                    ),
                    style:
                        financeNumber(colors.change(monthChange), size: 11.5),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              flex: 3,
              child: FinanceSparkline(
                values: history,
                color: tone.strong,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            LocaleKeys.dashboard_money_topMovers.tr(),
            style: financeLabel(palette.textMuted, size: 11),
          ),
          const SizedBox(height: 6),
          if (movers.isEmpty)
            Text(
              LocaleKeys.dashboard_money_noMovers.tr(),
              maxLines: 2,
              style: financeLabel(palette.textSecondary),
            )
          else
            for (final mover in movers)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    FinanceAvatar(
                      label: mover.holding.symbol.isEmpty
                          ? mover.holding.name
                          : mover.holding.symbol,
                      colors: colors,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mover.holding.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeLabel(
                          palette.textPrimary,
                          size: 12,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ChangePill(
                      colors: colors,
                      value: mover.dayPercent,
                      dense: true,
                      text: formatPercent(mover.dayPercent, signed: false),
                    ),
                  ],
                ),
              ),
          if (history.length < 2) const Spacer(),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ holdings

enum _Sort { value, returns, today, name }

final _holdings = DashboardWidgetDefinition(
  type: 'holdings',
  label: () => LocaleKeys.dashboard_money_holdings.tr(),
  description: () => LocaleKeys.dashboard_money_holdingsHint.tr(),
  icon: Icons.format_list_bulleted_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 8,
  defaultRowSpan: 9,
  minimumColumnSpan: 4,
  minimumRowSpan: 4,
  identity: DashboardAccent.blue,
  defaultTitle: () => LocaleKeys.dashboard_money_holdings.tr(),
  keywords: const ['holdings', 'positions', 'stocks', 'shares', 'portfolio'],
  headerTrailing: (data) => FinanceSegmented<_Sort>(
    palette: data.palette,
    values: _Sort.values,
    selected: _sortOf(data),
    labelOf: (sort) => switch (sort) {
      _Sort.value => LocaleKeys.dashboard_money_sortValue.tr(),
      _Sort.returns => LocaleKeys.dashboard_money_sortReturn.tr(),
      _Sort.today => LocaleKeys.dashboard_money_sortToday.tr(),
      _Sort.name => LocaleKeys.dashboard_money_sortName.tr(),
    },
    onSelected: data.isTypable
        ? (sort) => data.setSettings({_keySort: sort.name})
        : null,
  ),
  builder: (data) => _HoldingsList(data: data),
  configure: _holdingsConfig,
);

_Sort _sortOf(DashboardWidgetContext data) => _Sort.values.firstWhere(
      (sort) => sort.name == data.spec.setting(_keySort, fallback: 'value'),
      orElse: () => _Sort.value,
    );

class _HoldingsList extends StatefulWidget {
  const _HoldingsList({required this.data});

  final DashboardWidgetContext data;

  @override
  State<_HoldingsList> createState() => _HoldingsListState();
}

class _HoldingsListState extends State<_HoldingsList> {
  String? _expanded;

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
          return _pickHoldings(data, FinanceGhostShape.rows);
        }
        if (feed.loading) {
          return _reading(palette, still);
        }
        final holdings = priceHoldings(
          Holding.read(feed.table, settings: data.spec.settings),
          feed.market,
        );
        final snapshot = PortfolioSnapshot.of(holdings);
        final money = financeMoney(data);
        final sorted = [...holdings];
        switch (_sortOf(data)) {
          case _Sort.value:
            sorted.sort((a, b) => b.value.compareTo(a.value));
          case _Sort.returns:
            sorted.sort(
              (a, b) => (b.pnlPercent ?? -1e9).compareTo(a.pnlPercent ?? -1e9),
            );
          case _Sort.today:
            sorted.sort(
              (a, b) => (b.dayPercent ?? -1e9).compareTo(a.dayPercent ?? -1e9),
            );
          case _Sort.name:
            sorted.sort(
              (a, b) => a.holding.name
                  .toLowerCase()
                  .compareTo(b.holding.name.toLowerCase()),
            );
        }
        final largest = sorted.isEmpty
            ? 1.0
            : sorted.map((holding) => holding.value).reduce(math.max);
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 560;
            final narrow = constraints.maxWidth < 380;
            return Column(
              children: [
                Expanded(
                  child: sorted.isEmpty
                      ? Center(
                          child: Text(
                            LocaleKeys.dashboard_money_emptyHoldings.tr(),
                            style: DashboardType.caption(palette),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: sorted.length,
                          itemBuilder: (context, index) {
                            final holding = sorted[index];
                            final key = holding.holding.rowId ??
                                '${holding.holding.symbol}|${holding.holding.name}';
                            return FinanceEntrance(
                              key: ValueKey(key),
                              index: index,
                              still: still,
                              child: _HoldingRow(
                                holding: holding,
                                share: snapshot.value > 0
                                    ? holding.value / snapshot.value
                                    : 0,
                                bar: largest > 0 ? holding.value / largest : 0,
                                money: money,
                                colors: colors,
                                wide: wide,
                                narrow: narrow,
                                expanded: _expanded == key,
                                onTap: () => setState(
                                  () =>
                                      _expanded = _expanded == key ? null : key,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 6),
                _HoldingsFooter(
                  snapshot: snapshot,
                  money: money,
                  colors: colors,
                  onAdd: data.isTypable
                      ? () => _addHolding(context, data, feed, colors)
                      : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addHolding(
    BuildContext context,
    DashboardWidgetContext data,
    FinanceFeed feed,
    FinanceColors colors,
  ) {
    final sectors = <String>{
      for (final holding
          in Holding.read(feed.table, settings: data.spec.settings))
        if (holding.sector.isNotEmpty) holding.sector,
    }.toList()
      ..sort();
    unawaited(
      showFinanceEntryDialog(
        context: context,
        palette: data.palette,
        title: LocaleKeys.dashboard_money_addHolding.tr(),
        icon: Icons.add_chart_rounded,
        color: data.tone.strong,
        fields: [
          FinanceEntryField(
            key: FinanceRole.symbol.key,
            label: LocaleKeys.dashboard_money_symbol.tr(),
            hint: LocaleKeys.dashboard_money_symbolHint.tr(),
            kind: FinanceFieldKind.symbol,
            fills: FinanceRole.name.key,
            required: true,
          ),
          FinanceEntryField(
            key: FinanceRole.name.key,
            label: LocaleKeys.dashboard_money_name.tr(),
          ),
          FinanceEntryField(
            key: FinanceRole.sector.key,
            label: LocaleKeys.dashboard_money_sector.tr(),
            kind: FinanceFieldKind.choice,
            options: sectors,
          ),
          FinanceEntryField(
            key: FinanceRole.quantity.key,
            label: LocaleKeys.dashboard_money_quantity.tr(),
            kind: FinanceFieldKind.number,
            required: true,
          ),
          FinanceEntryField(
            key: FinanceRole.averagePrice.key,
            label: LocaleKeys.dashboard_money_averagePrice.tr(),
            kind: FinanceFieldKind.number,
            required: true,
          ),
          FinanceEntryField(
            key: FinanceRole.date.key,
            label: LocaleKeys.dashboard_money_boughtOn.tr(),
            kind: FinanceFieldKind.date,
            initial: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          ),
        ],
        onSave: (values) => financeAddRow(
          data,
          feed.table,
          Holding.roles,
          {
            ...values,
            FinanceRole.symbol.key:
                (values[FinanceRole.symbol.key] ?? '').toUpperCase(),
          },
        ),
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    required this.holding,
    required this.share,
    required this.bar,
    required this.money,
    required this.colors,
    required this.wide,
    required this.narrow,
    required this.expanded,
    required this.onTap,
  });

  final PricedHolding holding;
  final double share;
  final double bar;
  final MoneyStyle money;
  final FinanceColors colors;
  final bool wide;

  /// Too narrow for a price column: only the value and return are shown.
  final bool narrow;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final item = holding.holding;
    final hue = colors.hueFor(item.symbol.isEmpty ? item.name : item.symbol);
    final closes = holding.intraday;
    final monthUp = closes.length >= 2 ? closes.last >= closes.first : null;
    final price = holding.price;
    return FinanceHover(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: DashboardMetrics.hover,
        curve: DashboardMetrics.curve,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
        decoration: BoxDecoration(
          color: hovered || expanded
              ? palette.hover.withValues(alpha: palette.isDark ? 0.6 : 0.55)
              : palette.hoverBase,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              children: [
                FinanceAvatar(
                  label: item.symbol.isEmpty ? item.name : item.symbol,
                  colors: colors,
                  color: hue,
                ),
                const SizedBox(width: 11),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
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
                        [
                          if (item.symbol.isNotEmpty)
                            marketDisplayName(item.symbol),
                          if (item.quantity > 0 && item.averagePrice != null)
                            '${formatQuantity(item.quantity)} × '
                                '${money.price(item.averagePrice!)}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeLabel(palette.textMuted),
                      ),
                    ],
                  ),
                ),
                if (wide && closes.length >= 2) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 76,
                    height: 28,
                    child: FinanceSparkline(
                      values: closes,
                      color: monthUp == false ? colors.loss : colors.gain,
                      dot: false,
                    ),
                  ),
                ],
                const SizedBox(width: 14),
                if (!narrow) ...[
                  SizedBox(
                    width: wide ? 104 : 86,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          price == null ? '—' : money.price(price),
                          maxLines: 1,
                          style: financeNumber(palette.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        if (holding.dayPercent != null)
                          ChangePill(
                            colors: colors,
                            value: holding.dayPercent,
                            dense: true,
                            text: formatPercent(
                              holding.dayPercent,
                              signed: false,
                            ),
                          )
                        else
                          Text(
                            LocaleKeys.dashboard_money_lastPrice.tr(),
                            style: financeLabel(
                              palette.textMuted,
                              size: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                SizedBox(
                  width: wide ? 118 : 96,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money.fit(holding.value),
                        maxLines: 1,
                        style: financeNumber(
                          palette.textPrimary,
                          size: 13.5,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${money.fit(holding.pnl, signed: true)} '
                        '(${formatPercent(holding.pnlPercent, decimals: 1, signed: false)})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeNumber(
                          colors.change(holding.pnl),
                          size: 11.5,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                const SizedBox(width: 45),
                Expanded(
                  child: _WeightBar(
                    fraction: bar,
                    color: hue,
                    palette: palette,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    formatPercent(share * 100, decimals: 1, signed: false),
                    textAlign: TextAlign.end,
                    style: financeNumber(palette.textMuted, size: 10.5),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: DashboardMetrics.settle,
              curve: DashboardMetrics.curve,
              alignment: Alignment.topCenter,
              child: expanded
                  ? _HoldingDetail(
                      holding: holding,
                      share: share,
                      money: money,
                      colors: colors,
                      hue: hue,
                      chart: !narrow,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightBar extends StatelessWidget {
  const _WeightBar({
    required this.fraction,
    required this.color,
    required this.palette,
  });

  final double fraction;
  final Color color;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        height: 4,
        decoration: BoxDecoration(
          color: palette.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : palette.sunken,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0).toDouble(),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.55), color],
              ),
            ),
          ),
        ),
      );
}

class _HoldingDetail extends StatelessWidget {
  const _HoldingDetail({
    required this.holding,
    required this.share,
    required this.money,
    required this.colors,
    required this.hue,
    required this.chart,
  });

  final PricedHolding holding;
  final double share;
  final MoneyStyle money;
  final FinanceColors colors;
  final Color hue;
  final bool chart;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final item = holding.holding;
    final closes = holding.intraday;
    return Padding(
      padding: const EdgeInsets.fromLTRB(45, 12, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                FinanceStat(
                  label: LocaleKeys.dashboard_money_invested.tr(),
                  value: money.fit(holding.invested),
                  palette: palette,
                  size: 13,
                ),
                if (item.averagePrice != null)
                  FinanceStat(
                    label: LocaleKeys.dashboard_money_averagePrice.tr(),
                    value: money.price(item.averagePrice!),
                    palette: palette,
                    size: 13,
                  ),
                FinanceStat(
                  label: LocaleKeys.dashboard_money_weight.tr(),
                  value: formatPercent(share * 100, decimals: 1, signed: false),
                  palette: palette,
                  size: 13,
                ),
                if (item.boughtOn != null)
                  FinanceStat(
                    label: LocaleKeys.dashboard_money_boughtOn.tr(),
                    value: DateFormat.yMMMd().format(item.boughtOn!),
                    palette: palette,
                    size: 13,
                  ),
                if (item.sector.isNotEmpty)
                  FinanceStat(
                    label: LocaleKeys.dashboard_money_sector.tr(),
                    value: item.sector,
                    palette: palette,
                    size: 13,
                  ),
              ],
            ),
          ),
          if (chart && closes.length >= 2) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              height: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleKeys.dashboard_money_pastMonth.tr(),
                    style: financeLabel(palette.textMuted, size: 10.5),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: FinanceSparkline(
                      values: closes,
                      color: hue,
                      baseline: holding.holding.averagePrice,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HoldingsFooter extends StatelessWidget {
  const _HoldingsFooter({
    required this.snapshot,
    required this.money,
    required this.colors,
    required this.onAdd,
  });

  final PortfolioSnapshot snapshot;
  final MoneyStyle money;
  final FinanceColors colors;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final add = onAdd;
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          decoration: BoxDecoration(
            color: palette.isDark
                ? Colors.white.withValues(alpha: 0.04)
                : palette.sunken.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      LocaleKeys.dashboard_money_total.tr(),
                      style: financeLabel(palette.textSecondary, size: 12),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        money.fit(snapshot.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeNumber(palette.textPrimary, size: 13.5),
                      ),
                    ),
                    if (width >= 420) ...[
                      const SizedBox(width: 8),
                      ChangePill(
                        colors: colors,
                        value: snapshot.pnl,
                        dense: true,
                        text: '${money.fit(snapshot.pnl, signed: true)} · '
                            '${formatPercent(snapshot.pnlPercent, decimals: 1, signed: false)}',
                      ),
                    ],
                  ],
                ),
              ),
              if (add != null)
                width >= 320
                    ? DashboardButton(
                        label: LocaleKeys.dashboard_money_addHolding.tr(),
                        palette: palette,
                        icon: Icons.add_rounded,
                        onPressed: add,
                      )
                    : DashboardIconButton(
                        icon: Icons.add_rounded,
                        palette: palette,
                        tooltip: LocaleKeys.dashboard_money_addHolding.tr(),
                        onPressed: add,
                      ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------- heatmap

final _heatmap = DashboardWidgetDefinition(
  type: 'heatmap',
  label: () => LocaleKeys.dashboard_money_heatmap.tr(),
  description: () => LocaleKeys.dashboard_money_heatmapHint.tr(),
  icon: Icons.grid_view_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 12,
  defaultRowSpan: 6,
  minimumColumnSpan: 3,
  minimumRowSpan: 3,
  identity: DashboardAccent.green,
  defaultTitle: () => LocaleKeys.dashboard_money_heatmap.tr(),
  keywords: const ['heatmap', 'treemap', 'market map', 'movers', 'stocks'],
  headerTrailing: (data) => _HeatLegend(palette: data.palette),
  builder: (data) => _Heatmap(data: data),
  configure: (data) => [
    ..._holdingsConfig(data),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_money_style.tr(),
      value: data.spec.setting(_keyColourBy, fallback: 'today'),
      choices: [
        DashboardChoice(
          value: 'today',
          label: LocaleKeys.dashboard_money_today.tr(),
        ),
        DashboardChoice(
          value: 'return',
          label: LocaleKeys.dashboard_money_overall.tr(),
        ),
      ],
      onChanged: (value) => data.setSettings({_keyColourBy: value}),
    ),
  ],
);

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({required this.palette});

  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(palette);
    // The header of a small card is narrower than the scale: it shrinks.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerEnd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('−3%', style: financeNumber(palette.textMuted, size: 10.5)),
          const SizedBox(width: 6),
          Container(
            width: 84,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                colors: [
                  heatColor(-3, colors),
                  heatColor(-1, colors),
                  heatColor(0, colors),
                  heatColor(1, colors),
                  heatColor(3, colors),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('+3%', style: financeNumber(palette.textMuted, size: 10.5)),
        ],
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.data});

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
          return _pickHoldings(data, FinanceGhostShape.tiles);
        }
        if (feed.loading) {
          return _reading(palette, still);
        }
        final holdings = priceHoldings(
          Holding.read(feed.table, settings: data.spec.settings),
          feed.market,
        )..removeWhere((holding) => holding.value <= 0);
        if (holdings.isEmpty) {
          return Center(
            child: Text(
              LocaleKeys.dashboard_money_emptyHoldings.tr(),
              style: DashboardType.caption(palette),
            ),
          );
        }
        final money = financeMoney(data);
        final total = holdings.fold<double>(0, (sum, h) => sum + h.value);
        final anyLive = holdings.any((holding) => holding.dayPercent != null);
        final byReturn =
            data.spec.setting(_keyColourBy, fallback: 'today') == 'return' ||
                !anyLive;
        return Column(
          children: [
            Expanded(
              child: FinanceTreemap(
                palette: palette,
                still: still,
                items: [
                  for (final holding in holdings)
                    TreemapItem(
                      label: holding.holding.symbol.isEmpty
                          ? holding.holding.name
                          : marketDisplayName(holding.holding.symbol),
                      value: holding.value,
                      color: heatColor(
                        byReturn
                            ? (holding.pnlPercent == null
                                ? null
                                : holding.pnlPercent! / 8)
                            : holding.dayPercent,
                        colors,
                      ),
                      caption: byReturn
                          ? formatPercent(holding.pnlPercent, decimals: 1)
                          : formatPercent(holding.dayPercent),
                      detail: [
                        holding.holding.name,
                        '${LocaleKeys.dashboard_money_currentValue.tr()}: '
                            '${money.fit(holding.value)} '
                            '(${formatPercent(holding.value / total * 100, decimals: 1, signed: false)})',
                        if (holding.dayChange != null)
                          '${LocaleKeys.dashboard_money_today.tr()}: '
                              '${money.fit(holding.dayChange!, signed: true)} '
                              '(${formatPercent(holding.dayPercent)})',
                        '${LocaleKeys.dashboard_money_returns.tr()}: '
                            '${money.fit(holding.pnl, signed: true)} '
                            '(${formatPercent(holding.pnlPercent, decimals: 1)})',
                      ].join('\n'),
                    ),
                ],
              ),
            ),
            if (!anyLive) ...[
              const SizedBox(height: 6),
              Text(
                LocaleKeys.dashboard_money_heatmapNoLive.tr(),
                style: DashboardType.caption(palette),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------- watchlist

const _defaultWatchlist = ['^NSEI', '^NSEBANK', '^BSESN', 'GC=F', 'INR=X'];

final _watchlist = DashboardWidgetDefinition(
  type: 'watchlist',
  label: () => LocaleKeys.dashboard_money_watchlist.tr(),
  description: () => LocaleKeys.dashboard_money_watchlistHint.tr(),
  icon: Icons.visibility_rounded,
  group: DashboardWidgetGroup.money,
  defaultRowSpan: 7,
  minimumColumnSpan: 3,
  minimumRowSpan: 3,
  identity: DashboardAccent.purple,
  defaultTitle: () => LocaleKeys.dashboard_money_watchlist.tr(),
  defaultSettings: const {_keySymbols: _defaultWatchlist},
  keywords: const [
    'watchlist',
    'quotes',
    'tickers',
    'indices',
    'nifty',
    'sensex',
    'live prices',
  ],
  headerTrailing: (data) => data.isTypable
      ? DashboardIconButton(
          icon: Icons.add_rounded,
          palette: data.palette,
          tooltip: LocaleKeys.dashboard_money_addSymbol.tr(),
          onPressed: () => _addSymbol(data),
        )
      : const SizedBox.shrink(),
  builder: (data) => _Watchlist(data: data),
  configure: (data) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_money_symbols.tr(),
      hint: LocaleKeys.dashboard_money_symbolsHint.tr(),
      value: financeStringList(data.spec.settings[_keySymbols]).join(', '),
      onChanged: (value) => data.setSettings({
        _keySymbols: [
          for (final part in value.split(','))
            if (part.trim().isNotEmpty) part.trim().toUpperCase(),
        ],
      }),
    ),
  ],
);

List<String> _watchedSymbols(DashboardWidgetContext data) {
  final stored = data.spec.settings[_keySymbols];
  return stored == null ? _defaultWatchlist : financeStringList(stored);
}

void _addSymbol(DashboardWidgetContext data) {
  unawaited(
    showFinanceEntryDialog(
      context: data.context,
      palette: data.palette,
      title: LocaleKeys.dashboard_money_addSymbol.tr(),
      icon: Icons.visibility_rounded,
      color: data.tone.strong,
      fields: [
        FinanceEntryField(
          key: 'symbol',
          label: LocaleKeys.dashboard_money_symbol.tr(),
          hint: LocaleKeys.dashboard_money_symbolHint.tr(),
          kind: FinanceFieldKind.symbol,
          required: true,
        ),
      ],
      onSave: (values) async {
        final symbol = (values['symbol'] ?? '').trim().toUpperCase();
        if (symbol.isEmpty) {
          return false;
        }
        final current = _watchedSymbols(data);
        if (!current.contains(symbol)) {
          data.setSettings({
            _keySymbols: [...current, symbol],
          });
        }
        return true;
      },
    ),
  );
}

class _Watchlist extends StatefulWidget {
  const _Watchlist({required this.data});

  final DashboardWidgetContext data;

  @override
  State<_Watchlist> createState() => _WatchlistState();
}

class _WatchlistState extends State<_Watchlist> {
  late final MarketWatch _market = MarketWatch()..addListener(_changed);

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _market
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    final symbols = _watchedSymbols(data);
    _market.want(symbols: symbols.toSet());
    if (symbols.isEmpty) {
      return FinanceGhost(
        palette: palette,
        shape: FinanceGhostShape.rows,
        icon: Icons.show_chart_rounded,
        message: LocaleKeys.dashboard_money_emptyWatchlist.tr(),
        action:
            data.isTypable ? LocaleKeys.dashboard_money_addSymbol.tr() : null,
        onAction: () => _addSymbol(data),
        color: data.tone.strong,
      );
    }
    final updated = latestUpdate(_market, symbols);
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: symbols.length,
            itemBuilder: (context, index) => FinanceEntrance(
              key: ValueKey(symbols[index]),
              index: index,
              still: still,
              child: _WatchRow(
                symbol: symbols[index],
                quote: _market.quote(symbols[index]),
                colors: colors,
                onRemove: data.isTypable
                    ? () => data.setSettings({
                          _keySymbols: [
                            for (final symbol in symbols)
                              if (symbol != symbols[index]) symbol,
                          ],
                        })
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: FinanceFreshness(
            palette: palette,
            colors: colors,
            market: _market,
            updated: updated,
            still: still,
          ),
        ),
      ],
    );
  }
}

/// A price written the way its market writes it.
String marketPrice(String symbol, double value) {
  final currency = marketCurrencySymbol(symbol);
  if (currency.isEmpty) {
    return formatLevel(value, decimals: value.abs() < 1000 ? 2 : 1);
  }
  return MoneyStyle(
    symbol: currency,
    grouping:
        currency == '₹' ? MoneyGrouping.indian : MoneyGrouping.international,
  ).price(value);
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({
    required this.symbol,
    required this.quote,
    required this.colors,
    required this.onRemove,
  });

  final String symbol;
  final MarketQuote? quote;
  final FinanceColors colors;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final quote = this.quote;
    final price = quote?.price;
    final change = quote?.changePercent;
    final closes = quote?.closes ?? const <double>[];
    final name = marketDisplayName(symbol);
    return FinanceHover(
      builder: (context, hovered) => AnimatedContainer(
        duration: DashboardMetrics.hover,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: hovered
              ? palette.hover.withValues(alpha: 0.6)
              : palette.hoverBase,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy = constraints.maxWidth >= 300;
            return Row(
              children: [
                FinanceAvatar(label: name, colors: colors, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeLabel(
                          palette.textPrimary,
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        quote?.error != null && price == null
                            ? LocaleKeys.dashboard_money_notFound.tr()
                            : symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeLabel(palette.textMuted, size: 11),
                      ),
                    ],
                  ),
                ),
                if (roomy && closes.length >= 2) ...[
                  SizedBox(
                    width: 64,
                    height: 26,
                    child: FinanceSparkline(
                      values: closes,
                      color: closes.last >= closes.first
                          ? colors.gain
                          : colors.loss,
                      dot: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price == null ? '—' : marketPrice(symbol, price),
                      style: financeNumber(palette.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    if (change != null)
                      ChangePill(
                        colors: colors,
                        value: change,
                        dense: true,
                        text: formatPercent(change, signed: false),
                      ),
                  ],
                ),
                if (onRemove != null)
                  AnimatedOpacity(
                    opacity: hovered ? 1 : 0,
                    duration: DashboardMetrics.hover,
                    child: IgnorePointer(
                      ignoring: !hovered,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: DashboardIconButton(
                          icon: Icons.close_rounded,
                          palette: palette,
                          size: 22,
                          iconSize: 13,
                          tooltip: LocaleKeys.dashboard_money_removeSymbol.tr(),
                          onPressed: onRemove,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
