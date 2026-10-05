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
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:appflowy/workspace/application/finance/finance_row_writer.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:appflowy/workspace/application/finance/options_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

void registerOptionsWidgets() {
  DashboardWidgetRegistry.register(_summary);
  DashboardWidgetRegistry.register(_book);
  DashboardWidgetRegistry.register(_payoff);
  DashboardWidgetRegistry.register(_chain);
}

const _keyCapital = 'capital';
const _keyUnderlying = 'underlying';
const _keyAround = 'strikes';
const _defaultCapital = 1000000.0;
const _chainUnderlyings = ['NIFTY', 'BANKNIFTY', 'FINNIFTY', 'MIDCPNIFTY'];

/// An options journal read against the live market.
class _Book {
  _Book(this.book, this.market);

  factory _Book.read(
    ChartTable table,
    Map<String, Object?> settings,
    MarketWatch market,
  ) {
    final book = OptionsBook.of(readOptionLegs(table, settings: settings));
    final open = book.openExpiries;
    market.want(
      symbols: {
        for (final underlying in open.keys)
          marketSymbolForUnderlying(underlying),
      },
      chains: {
        for (final entry in open.entries)
          for (final expiry in entry.value) ChainRequest(entry.key, expiry),
      },
    );
    return _Book(book, market);
  }

  final OptionsBook book;
  final MarketWatch market;

  OptionChain? _chainFor(OptionLeg leg) => leg.expiry == null
      ? null
      : market.chain(ChainRequest(leg.underlying, leg.expiry));

  /// The underlying's level: the chain's own spot first, then its quote.
  double? spotOf(String underlying) {
    for (final leg in book.legs) {
      if (leg.underlying == underlying && leg.isOpen) {
        final spot = _chainFor(leg)?.spot;
        if (spot != null) {
          return spot;
        }
      }
    }
    return market.quote(marketSymbolForUnderlying(underlying))?.price;
  }

  double? priceOf(OptionLeg leg) {
    if (!leg.isOption) {
      return null;
    }
    return _chainFor(leg)
        ?.quoteAt(leg.strike!, call: leg.kind == LegKind.call)
        ?.lastPrice;
  }

  double? volatilityOf(OptionLeg leg) {
    if (!leg.isOption) {
      return null;
    }
    final iv = _chainFor(leg)
        ?.quoteAt(leg.strike!, call: leg.kind == LegKind.call)
        ?.impliedVolatility;
    return iv == null ? null : iv / 100;
  }

  bool get isLive => book.legs.any(
        (leg) => leg.isOpen && leg.isOption && priceOf(leg) != null,
      );

  DateTime? get updated {
    DateTime? latest;
    for (final leg in book.legs) {
      final time = _chainFor(leg)?.fetchedAt;
      if (time != null && (latest == null || time.isAfter(latest))) {
        latest = time;
      }
    }
    return latest;
  }

  StrategyAnalysis analyse(OptionStrategy strategy) => StrategyAnalysis(
        strategy,
        spot: spotOf(strategy.underlying),
        priceOf: priceOf,
        volatilityOf: volatilityOf,
      );
}

Widget _pickJournal(DashboardWidgetContext data, FinanceGhostShape shape) =>
    FinanceGhost(
      palette: data.palette,
      shape: shape,
      icon: Icons.stacked_line_chart_rounded,
      message: LocaleKeys.dashboard_money_pickJournal.tr(),
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

List<DashboardConfigField> _journalConfig(DashboardWidgetContext data) => [
      financeTableField(data),
      financeCurrencyField(data),
      financeColumnsField(data, [
        (OptionRoles.strategy, LocaleKeys.dashboard_money_strategy.tr()),
        (OptionRoles.underlying, LocaleKeys.dashboard_money_underlying.tr()),
        (OptionRoles.kind, LocaleKeys.dashboard_money_optionType.tr()),
        (OptionRoles.side, LocaleKeys.dashboard_money_side.tr()),
        (OptionRoles.strike, LocaleKeys.dashboard_money_strike.tr()),
        (OptionRoles.entry, LocaleKeys.dashboard_money_entry.tr()),
        (OptionRoles.exit, LocaleKeys.dashboard_money_exit.tr()),
        (OptionRoles.expiry, LocaleKeys.dashboard_money_expiry.tr()),
      ]),
    ];

String _daysLeft(DateTime? expiry) {
  if (expiry == null) {
    return '';
  }
  final now = DateTime.now();
  final days = DateTime(expiry.year, expiry.month, expiry.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days < 0) {
    return LocaleKeys.dashboard_money_expired.tr();
  }
  if (days == 0) {
    return LocaleKeys.dashboard_money_expiresToday.tr();
  }
  if (days == 1) {
    return LocaleKeys.dashboard_money_dayLeft.tr();
  }
  return LocaleKeys.dashboard_money_daysLeft.tr(args: ['$days']);
}

String _legLabel(OptionLeg leg) {
  final side = leg.side == OptionSide.buy ? 'B' : 'S';
  final kind = switch (leg.kind) {
    LegKind.call => 'CE',
    LegKind.put => 'PE',
    LegKind.future => 'FUT',
  };
  final strike = leg.strike == null ? '' : '${formatLevel(leg.strike!)} ';
  return '$side $strike$kind ×${formatQuantity(leg.quantity)}';
}

PayoffLabels _payoffLabels() => PayoffLabels(
      expiry: LocaleKeys.dashboard_money_atExpiry.tr(),
      today: LocaleKeys.dashboard_money_todayCurve.tr(),
      spot: LocaleKeys.dashboard_money_spot.tr(),
      price: LocaleKeys.dashboard_money_atPrice.tr(),
    );

String _boundText(double value, bool unlimited, MoneyStyle money) => unlimited
    ? LocaleKeys.dashboard_money_unlimited.tr()
    : money.fit(value, signed: true);

// ------------------------------------------------------------------ summary

final _summary = DashboardWidgetDefinition(
  type: 'options_summary',
  label: () => LocaleKeys.dashboard_money_optionsSummary.tr(),
  description: () => LocaleKeys.dashboard_money_optionsSummaryHint.tr(),
  icon: Icons.speed_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 8,
  defaultRowSpan: 5,
  minimumColumnSpan: 4,
  minimumRowSpan: 3,
  surface: DashboardSurface.gradient,
  identity: DashboardAccent.purple,
  showsTitleByDefault: false,
  padding: EdgeInsets.zero,
  defaultSettings: const {_keyCapital: _defaultCapital},
  keywords: const [
    'options',
    'capital',
    'margin',
    'pnl',
    'returns',
    'fno',
    'derivatives',
  ],
  builder: (data) => _Summary(data: data),
  configure: (data) => [
    ..._journalConfig(data),
    DashboardConfigNumber(
      label: LocaleKeys.dashboard_money_capital.tr(),
      value: data.spec.number(_keyCapital, fallback: _defaultCapital),
      minimum: 0,
      step: 10000,
      onChanged: (value) => data.setSettings({_keyCapital: value}),
    ),
  ],
);

class _Summary extends StatelessWidget {
  const _Summary({required this.data});

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
            child: _pickJournal(data, FinanceGhostShape.payoff),
          );
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final reading = _Book.read(feed.table, data.spec.settings, feed.market);
        final book = reading.book;
        final money = financeMoney(data);
        final capital =
            data.spec.number(_keyCapital, fallback: _defaultCapital);
        final open = book.openMarkToMarket(reading.priceOf);
        final booked = book.realized;
        final total = open + booked;
        final roi = percentOf(total, capital);
        final margin = book.marginUsed;
        final marginShare =
            capital > 0 ? (margin / capital).clamp(0.0, 1.0) : 0.0;
        final openCount = book.open.length;
        final nextExpiry = book.nextExpiry;
        final ink = data.tone.label;
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight - 34;
            final roomy = height >= 150;
            final gauge = constraints.maxWidth >= 520 && height >= 120;
            final figure = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FinanceEyebrow(
                  LocaleKeys.dashboard_money_totalPnl.tr(),
                  color: ink,
                  trailing: Flexible(
                    child: FinanceFreshness(
                      palette: palette,
                      colors: colors,
                      market: feed.market,
                      updated: reading.updated,
                      still: still,
                      ink: ink,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FinanceRun(
                  height: roomy ? 46 : 34,
                  spacing: 10,
                  children: [
                    AnimatedFigure(
                      value: total,
                      format: (value) => money.format(value, signed: true),
                      countUp: true,
                      still: still,
                      style: DashboardType.display(
                        palette,
                        size: roomy ? 38 : 28,
                        weight: FontWeight.w600,
                        color: colors.change(total),
                      ),
                    ),
                    ChangePill(
                      colors: colors,
                      value: roi,
                      text: formatPercent(roi, signed: false),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${LocaleKeys.dashboard_money_capital.tr()}  '
                  '${money.fit(capital)}  →  ${money.fit(capital + total)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: financeLabel(palette.textSecondary, size: 12),
                ),
                if (roomy) const Spacer() else const SizedBox(height: 10),
                FinanceRun(
                  // Tall enough for a caption under each figure.
                  height: roomy ? 54 : 44,
                  spacing: 22,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_openPnl.tr(),
                      value: money.fit(open, signed: true),
                      valueColor: colors.change(open),
                      palette: palette,
                      caption: LocaleKeys.dashboard_money_openStrategies.tr(
                        args: ['$openCount'],
                      ),
                    ),
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_booked.tr(),
                      value: money.fit(booked, signed: true),
                      valueColor: colors.change(booked),
                      palette: palette,
                    ),
                    if (nextExpiry != null)
                      FinanceStat(
                        label: LocaleKeys.dashboard_money_nextExpiry.tr(),
                        value: DateFormat.MMMd().format(nextExpiry),
                        palette: palette,
                        caption: _daysLeft(nextExpiry),
                      ),
                    if (!gauge)
                      FinanceStat(
                        label: LocaleKeys.dashboard_money_marginUsed.tr(),
                        value: formatPercent(
                          marginShare * 100,
                          decimals: 0,
                          signed: false,
                        ),
                        palette: palette,
                      ),
                  ],
                ),
              ],
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: FinanceOrbs(
                    colors: colors,
                    first: data.tone.strong,
                    second: colors.hue(1),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                  child: gauge
                      ? Row(
                          children: [
                            Expanded(child: figure),
                            const SizedBox(width: 20),
                            SizedBox.square(
                              dimension: math.min(150, height),
                              child: _MarginGauge(
                                share: marginShare,
                                margin: margin,
                                capital: capital,
                                money: money,
                                colors: colors,
                                still: still,
                              ),
                            ),
                          ],
                        )
                      : figure,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MarginGauge extends StatelessWidget {
  const _MarginGauge({
    required this.share,
    required this.margin,
    required this.capital,
    required this.money,
    required this.colors,
    required this.still,
  });

  final double share;
  final double margin;
  final double capital;
  final MoneyStyle money;
  final FinanceColors colors;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final warm =
        palette.isPaper ? const Color(0xFFC08A2E) : const Color(0xFFF59E0B);
    return FinanceRing(
      value: share,
      still: still,
      arc: math.pi * 1.5,
      thickness: 11,
      track: palette.isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: palette.isPaper ? 0.5 : 0.7),
      colors: [colors.gain, warm, colors.loss],
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatPercent(share * 100, decimals: 0, signed: false),
                style: financeNumber(
                  palette.textPrimary,
                  size: 22,
                  weight: FontWeight.w700,
                ),
              ),
              Text(
                LocaleKeys.dashboard_money_marginUsed.tr(),
                style: financeLabel(palette.textMuted, size: 10.5),
              ),
              const SizedBox(height: 2),
              Text(
                LocaleKeys.dashboard_money_marginFree.tr(
                  args: [money.compact(math.max(0, capital - margin))],
                ),
                style: financeLabel(palette.textSecondary, size: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- book

final _book = DashboardWidgetDefinition(
  type: 'options_book',
  label: () => LocaleKeys.dashboard_money_optionsBook.tr(),
  description: () => LocaleKeys.dashboard_money_optionsBookHint.tr(),
  icon: Icons.stacked_line_chart_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 12,
  defaultRowSpan: 8,
  minimumColumnSpan: 4,
  minimumRowSpan: 5,
  identity: DashboardAccent.purple,
  defaultTitle: () => LocaleKeys.dashboard_money_optionsBook.tr(),
  keywords: const [
    'strategies',
    'iron condor',
    'straddle',
    'spread',
    'positions',
    'options',
    'payoff',
  ],
  builder: (data) => _BookView(data: data),
  configure: _journalConfig,
);

void _addTrade(DashboardWidgetContext data, ChartTable table) {
  final strategies = {
    for (final leg in readOptionLegs(table, settings: data.spec.settings))
      if (leg.strategy.isNotEmpty) leg.strategy,
  }.toList();
  unawaited(
    showFinanceEntryDialog(
      context: data.context,
      palette: data.palette,
      title: LocaleKeys.dashboard_money_addTrade.tr(),
      icon: Icons.candlestick_chart_rounded,
      color: data.tone.strong,
      fields: [
        FinanceEntryField(
          key: OptionRoles.strategy.key,
          label: LocaleKeys.dashboard_money_strategy.tr(),
          kind: FinanceFieldKind.choice,
          options: strategies,
          required: true,
          wide: true,
        ),
        FinanceEntryField(
          key: OptionRoles.underlying.key,
          label: LocaleKeys.dashboard_money_underlying.tr(),
          kind: FinanceFieldKind.choice,
          options: _chainUnderlyings,
          initial: 'NIFTY',
          required: true,
        ),
        FinanceEntryField(
          key: OptionRoles.expiry.key,
          label: LocaleKeys.dashboard_money_expiry.tr(),
          kind: FinanceFieldKind.date,
          required: true,
        ),
        FinanceEntryField(
          key: OptionRoles.kind.key,
          label: LocaleKeys.dashboard_money_optionType.tr(),
          kind: FinanceFieldKind.choice,
          options: const ['CE', 'PE', 'FUT'],
          required: true,
        ),
        FinanceEntryField(
          key: OptionRoles.side.key,
          label: LocaleKeys.dashboard_money_side.tr(),
          kind: FinanceFieldKind.choice,
          options: [
            LocaleKeys.dashboard_money_buy.tr(),
            LocaleKeys.dashboard_money_sell.tr(),
          ],
          required: true,
        ),
        FinanceEntryField(
          key: OptionRoles.strike.key,
          label: LocaleKeys.dashboard_money_strike.tr(),
          kind: FinanceFieldKind.number,
        ),
        FinanceEntryField(
          key: OptionRoles.quantity.key,
          label: LocaleKeys.dashboard_money_quantity.tr(),
          kind: FinanceFieldKind.number,
          required: true,
        ),
        FinanceEntryField(
          key: OptionRoles.entry.key,
          label: LocaleKeys.dashboard_money_entry.tr(),
          kind: FinanceFieldKind.number,
          required: true,
        ),
        FinanceEntryField(
          key: OptionRoles.opened.key,
          label: LocaleKeys.dashboard_money_date.tr(),
          kind: FinanceFieldKind.date,
          initial: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        ),
      ],
      onSave: (values) => financeAddRow(
        data,
        table,
        OptionRoles.all,
        {
          ...values,
          OptionRoles.status.key: 'Open',
        },
      ),
    ),
  );
}

class _BookView extends StatelessWidget {
  const _BookView({required this.data});

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
          return _pickJournal(data, FinanceGhostShape.tiles);
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final reading = _Book.read(feed.table, data.spec.settings, feed.market);
        final money = financeMoney(data);
        final open = reading.book.open.toList();
        final closed = reading.book.closed.toList();
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = financeColumnsFor(
              constraints.maxWidth,
              300,
              maximum: 4,
            );
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (open.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              LocaleKeys.dashboard_money_noOpenStrategies.tr(),
                              style: DashboardType.caption(palette),
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (var index = 0; index < open.length; index++)
                              SizedBox(
                                width: width,
                                child: FinanceEntrance(
                                  index: index,
                                  still: still,
                                  child: _StrategyCard(
                                    analysis: reading.analyse(open[index]),
                                    reading: reading,
                                    data: data,
                                    table: feed.table,
                                    money: money,
                                    colors: colors,
                                    still: still,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (closed.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _ClosedStrategies(
                          strategies: closed,
                          money: money,
                          colors: colors,
                        ),
                      ],
                    ],
                  ),
                ),
                if (data.isTypable) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: DashboardButton(
                      label: LocaleKeys.dashboard_money_addTrade.tr(),
                      palette: palette,
                      icon: Icons.add_rounded,
                      onPressed: () => _addTrade(data, feed.table),
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

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({
    required this.analysis,
    required this.reading,
    required this.data,
    required this.table,
    required this.money,
    required this.colors,
    required this.still,
  });

  final StrategyAnalysis analysis;
  final _Book reading;
  final DashboardWidgetContext data;
  final ChartTable table;
  final MoneyStyle money;
  final FinanceColors colors;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final strategy = analysis.strategy;
    final bounds = analysis.bounds;
    final mtm = analysis.markToMarket;
    final hue = colors.hueFor(strategy.name);
    final (low, high) = analysis.range;
    final pop = analysis.probabilityOfProfit;
    final premium = strategy.netPremium;
    return FinanceHover(
      onTap: () => _showAnalysis(context, analysis, data, table, money, still),
      builder: (context, hovered) => AnimatedContainer(
        duration: DashboardMetrics.settle,
        curve: DashboardMetrics.curve,
        transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: colors.panel(hovered: hovered, hue: hue),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FinanceAvatar(
                  label: strategy.underlying.isEmpty
                      ? strategy.name
                      : strategy.underlying,
                  colors: colors,
                  color: hue,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strategy.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeLabel(
                          palette.textPrimary,
                          size: 13.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          if (strategy.underlying.isNotEmpty)
                            strategy.underlying,
                          if (strategy.expiry != null)
                            DateFormat.MMMd().format(strategy.expiry!),
                          _daysLeft(strategy.expiry),
                        ].where((part) => part.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: financeLabel(palette.textMuted, size: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      mtm == null ? '—' : money.fit(mtm, signed: true),
                      style: financeNumber(
                        colors.change(mtm),
                        size: 16,
                        weight: FontWeight.w700,
                      ),
                    ),
                    if (premium != 0)
                      Text(
                        '${premium > 0 ? LocaleKeys.dashboard_money_credit.tr() : LocaleKeys.dashboard_money_debit.tr()} '
                        '${money.fit(premium.abs())}',
                        style: financeLabel(palette.textMuted, size: 10.5),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 78,
              child: FinancePayoffChart(
                low: low,
                high: high,
                expiry: strategy.payoffAt,
                today: analysis.hasTimeValue ? analysis.todayAt : null,
                spot: analysis.spot,
                breakevens: bounds.breakevens,
                colors: colors,
                palette: palette,
                formatMoney: (value) => money.compact(value, signed: true),
                formatPrice: (value) => formatLevel(value),
                labels: _payoffLabels(),
                compact: true,
                still: still,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FinanceStat(
                    label: LocaleKeys.dashboard_money_maxProfit.tr(),
                    value: _boundText(
                      bounds.maxProfit,
                      bounds.unlimitedProfit,
                      money,
                    ),
                    valueColor: colors.gain,
                    palette: palette,
                    size: 12.5,
                  ),
                ),
                Expanded(
                  child: FinanceStat(
                    label: LocaleKeys.dashboard_money_maxLoss.tr(),
                    value: _boundText(
                      bounds.maxLoss,
                      bounds.unlimitedLoss,
                      money,
                    ),
                    valueColor: colors.loss,
                    palette: palette,
                    size: 12.5,
                  ),
                ),
                Expanded(
                  child: FinanceStat(
                    label: LocaleKeys.dashboard_money_chanceOfProfit.tr(),
                    value: pop == null
                        ? '—'
                        : formatPercent(pop, decimals: 0, signed: false),
                    palette: palette,
                    size: 12.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final leg in strategy.openLegs)
                  _LegChip(leg: leg, colors: colors),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegChip extends StatelessWidget {
  const _LegChip({required this.leg, required this.colors});

  final OptionLeg leg;
  final FinanceColors colors;

  @override
  Widget build(BuildContext context) {
    final color = leg.side == OptionSide.buy ? colors.gain : colors.loss;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.wash(color, 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        _legLabel(leg),
        style: financeNumber(color, size: 10.5),
      ),
    );
  }
}

class _ClosedStrategies extends StatelessWidget {
  const _ClosedStrategies({
    required this.strategies,
    required this.money,
    required this.colors,
  });

  final List<OptionStrategy> strategies;
  final MoneyStyle money;
  final FinanceColors colors;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final booked = strategies.fold<double>(0, (sum, s) => sum + s.realized);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FinanceEyebrow(
          LocaleKeys.dashboard_money_closedSummary.tr(
            args: ['${strategies.length}', money.fit(booked, signed: true)],
          ),
          color: palette.textMuted,
        ),
        const SizedBox(height: 6),
        for (final strategy in strategies)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.change(strategy.realized),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      strategy.name,
                      if (strategy.underlying.isNotEmpty) strategy.underlying,
                      if (strategy.expiry != null)
                        DateFormat.MMMd().format(strategy.expiry!),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: financeLabel(palette.textSecondary, size: 12),
                  ),
                ),
                Text(
                  money.fit(strategy.realized, signed: true),
                  style:
                      financeNumber(colors.change(strategy.realized), size: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------- the analysis

void _showAnalysis(
  BuildContext context,
  StrategyAnalysis analysis,
  DashboardWidgetContext data,
  ChartTable table,
  MoneyStyle money,
  bool still,
) {
  unawaited(
    showDialog<void>(
      context: context,
      barrierColor:
          Colors.black.withValues(alpha: data.palette.isDark ? 0.55 : 0.3),
      builder: (_) => _AnalysisDialog(
        analysis: analysis,
        data: data,
        table: table,
        money: money,
        still: still,
      ),
    ),
  );
}

class _AnalysisDialog extends StatelessWidget {
  const _AnalysisDialog({
    required this.analysis,
    required this.data,
    required this.table,
    required this.money,
    required this.still,
  });

  final StrategyAnalysis analysis;
  final DashboardWidgetContext data;
  final ChartTable table;
  final MoneyStyle money;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final strategy = analysis.strategy;
    final bounds = analysis.bounds;
    final greeks = analysis.greeks;
    final pop = analysis.probabilityOfProfit;
    final mtm = analysis.markToMarket;
    final (low, high) = analysis.range;
    final reward = bounds.rewardToRisk;
    return Dialog(
      backgroundColor: palette.raised,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: palette.border.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FinanceIconTile(
                    icon: Icons.candlestick_chart_rounded,
                    color: colors.hueFor(strategy.name),
                    colors: colors,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strategy.name,
                          style: DashboardType.title(palette, size: 19),
                        ),
                        Text(
                          [
                            if (strategy.underlying.isNotEmpty)
                              strategy.underlying,
                            if (strategy.expiry != null)
                              DateFormat.yMMMd().format(strategy.expiry!),
                            _daysLeft(strategy.expiry),
                            if (analysis.spot != null)
                              '${LocaleKeys.dashboard_money_spot.tr()} ${formatLevel(analysis.spot!, decimals: 2)}',
                          ].where((part) => part.isNotEmpty).join(' · '),
                          style: DashboardType.caption(palette),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        mtm == null ? '—' : money.format(mtm, signed: true),
                        style: financeNumber(
                          colors.change(mtm),
                          size: 24,
                          weight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        LocaleKeys.dashboard_money_openPnl.tr(),
                        style: DashboardType.caption(palette),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  DashboardIconButton(
                    icon: Icons.close_rounded,
                    palette: palette,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: palette.border.withValues(alpha: 0.4),
                    ),
                  ),
                  child: FinancePayoffChart(
                    low: low,
                    high: high,
                    expiry: strategy.payoffAt,
                    today: analysis.hasTimeValue ? analysis.todayAt : null,
                    spot: analysis.spot,
                    breakevens: bounds.breakevens,
                    strikes: [
                      for (final leg in strategy.openLegs)
                        if (leg.strike != null)
                          PayoffMark(
                            leg.strike!,
                            _legLabel(leg),
                            buy: leg.side == OptionSide.buy,
                          ),
                    ],
                    colors: colors,
                    palette: palette,
                    formatMoney: (value) => money.compact(value, signed: true),
                    formatPrice: (value) => formatLevel(value),
                    labels: _payoffLabels(),
                    still: still,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 26,
                runSpacing: 12,
                children: [
                  FinanceStat(
                    label: LocaleKeys.dashboard_money_maxProfit.tr(),
                    value: _boundText(
                      bounds.maxProfit,
                      bounds.unlimitedProfit,
                      money,
                    ),
                    valueColor: colors.gain,
                    palette: palette,
                  ),
                  FinanceStat(
                    label: LocaleKeys.dashboard_money_maxLoss.tr(),
                    value: _boundText(
                      bounds.maxLoss,
                      bounds.unlimitedLoss,
                      money,
                    ),
                    valueColor: colors.loss,
                    palette: palette,
                  ),
                  FinanceStat(
                    label: LocaleKeys.dashboard_money_breakevens.tr(),
                    value: bounds.breakevens.isEmpty
                        ? '—'
                        : bounds.breakevens
                            .map((value) => formatLevel(value))
                            .join(' · '),
                    palette: palette,
                  ),
                  if (reward != null)
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_rewardRisk.tr(),
                      value: '${reward.toStringAsFixed(2)} : 1',
                      palette: palette,
                    ),
                  FinanceStat(
                    label: LocaleKeys.dashboard_money_chanceOfProfit.tr(),
                    value: pop == null
                        ? '—'
                        : formatPercent(pop, decimals: 0, signed: false),
                    palette: palette,
                  ),
                  if (strategy.netPremium != 0)
                    FinanceStat(
                      label: strategy.netPremium > 0
                          ? LocaleKeys.dashboard_money_credit.tr()
                          : LocaleKeys.dashboard_money_debit.tr(),
                      value: money.fit(strategy.netPremium.abs()),
                      palette: palette,
                    ),
                  if (strategy.margin > 0)
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_marginUsed.tr(),
                      value: money.fit(strategy.margin),
                      palette: palette,
                    ),
                ],
              ),
              if (greeks != null) ...[
                const SizedBox(height: 14),
                FinanceEyebrow(
                  LocaleKeys.dashboard_money_netGreeks.tr(),
                  color: palette.textMuted,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 26,
                  runSpacing: 10,
                  children: [
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_delta.tr(),
                      value: greeks.delta.toStringAsFixed(1),
                      palette: palette,
                      size: 13,
                    ),
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_gamma.tr(),
                      value: greeks.gamma.toStringAsFixed(3),
                      palette: palette,
                      size: 13,
                    ),
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_theta.tr(),
                      value: money.fit(greeks.theta, signed: true),
                      valueColor: colors.change(greeks.theta),
                      palette: palette,
                      size: 13,
                    ),
                    FinanceStat(
                      label: LocaleKeys.dashboard_money_vega.tr(),
                      value: money.fit(greeks.vega, signed: true),
                      valueColor: colors.change(greeks.vega),
                      palette: palette,
                      size: 13,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              FinanceEyebrow(
                LocaleKeys.dashboard_money_legs.tr(),
                color: palette.textMuted,
              ),
              const SizedBox(height: 6),
              for (final leg in strategy.legs)
                _LegLine(
                  leg: leg,
                  price: analysis.priceOf(leg),
                  money: money,
                  colors: colors,
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (data.isTypable && strategy.isOpen)
                    DashboardButton(
                      label: LocaleKeys.dashboard_money_markClosed.tr(),
                      palette: palette,
                      icon: Icons.check_circle_rounded,
                      onPressed: () async {
                        final done = await _markClosed(
                          context,
                          analysis,
                          data,
                          table,
                        );
                        if (done && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegLine extends StatelessWidget {
  const _LegLine({
    required this.leg,
    required this.price,
    required this.money,
    required this.colors,
  });

  final OptionLeg leg;
  final double? price;
  final MoneyStyle money;
  final FinanceColors colors;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final mtm = leg.markToMarket(leg.isOpen ? price : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          _LegChip(leg: leg, colors: colors),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              [
                '${LocaleKeys.dashboard_money_entry.tr()} ${money.price(leg.entry)}',
                if (leg.isOpen && (price ?? leg.lastPrice) != null)
                  '${LocaleKeys.dashboard_money_ltp.tr()} ${money.price((price ?? leg.lastPrice)!)}',
                if (!leg.isOpen && leg.exit != null)
                  '${LocaleKeys.dashboard_money_exit.tr()} ${money.price(leg.exit!)}',
              ].join('   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: financeNumber(
                palette.textSecondary,
                size: 12,
                weight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            mtm == null ? '—' : money.fit(mtm, signed: true),
            style: financeNumber(colors.change(mtm), size: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Writes today's prices as the exit of every open leg and marks them
/// closed, after asking.
Future<bool> _markClosed(
  BuildContext context,
  StrategyAnalysis analysis,
  DashboardWidgetContext data,
  ChartTable table,
) async {
  final strategy = analysis.strategy;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: data.palette.raised,
      content: Text(
        LocaleKeys.dashboard_money_markClosedBody.tr(args: [strategy.name]),
        style: DashboardType.body(data.palette),
      ),
      actions: [
        DashboardButton(
          label: LocaleKeys.dashboard_money_cancel.tr(),
          palette: data.palette,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        DashboardButton(
          label: LocaleKeys.dashboard_money_markClosed.tr(),
          palette: data.palette,
          primary: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return false;
  }
  final columns = FinanceColumns.resolve(
    table,
    OptionRoles.all,
    settings: data.spec.settings,
  );
  final sheet = FinanceSheet(table);
  final exitColumn = sheet.fieldId(columns[OptionRoles.exit]);
  final statusColumn = sheet.fieldId(columns[OptionRoles.status]);
  if (exitColumn == null && statusColumn == null) {
    return false;
  }
  final writer = FinanceRowWriter(data.spec.source.viewId);
  var wrote = false;
  for (final leg in strategy.openLegs) {
    final rowId = leg.rowId;
    if (rowId == null) {
      continue;
    }
    final price = analysis.priceOf(leg);
    if (exitColumn != null && price != null) {
      wrote = await writer.write(rowId, exitColumn, '$price') || wrote;
    }
    if (statusColumn != null) {
      wrote = await writer.write(rowId, statusColumn, 'Closed') || wrote;
    }
  }
  return wrote;
}

// ------------------------------------------------------------------- payoff

final _payoff = DashboardWidgetDefinition(
  type: 'options_payoff',
  label: () => LocaleKeys.dashboard_money_payoff.tr(),
  description: () => LocaleKeys.dashboard_money_payoffHint.tr(),
  icon: Icons.area_chart_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 8,
  defaultRowSpan: 9,
  minimumColumnSpan: 4,
  minimumRowSpan: 5,
  identity: DashboardAccent.purple,
  defaultTitle: () => LocaleKeys.dashboard_money_payoff.tr(),
  keywords: const ['payoff', 'risk graph', 'breakeven', 'options', 'greeks'],
  builder: (data) => _PayoffView(data: data),
  configure: _journalConfig,
);

class _PayoffView extends StatefulWidget {
  const _PayoffView({required this.data});

  final DashboardWidgetContext data;

  @override
  State<_PayoffView> createState() => _PayoffViewState();
}

class _PayoffViewState extends State<_PayoffView> {
  String? _selected;

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
          return _pickJournal(data, FinanceGhostShape.payoff);
        }
        if (feed.loading) {
          return _loading(data, context);
        }
        final reading = _Book.read(feed.table, data.spec.settings, feed.market);
        final open = reading.book.open.toList();
        if (open.isEmpty) {
          return Center(
            child: Text(
              LocaleKeys.dashboard_money_noOpenStrategies.tr(),
              style: DashboardType.caption(palette),
            ),
          );
        }
        final strategy = open.firstWhere(
          (candidate) => candidate.name == _selected,
          orElse: () => open.first,
        );
        final analysis = reading.analyse(strategy);
        final bounds = analysis.bounds;
        final money = financeMoney(data);
        final (low, high) = analysis.range;
        final pop = analysis.probabilityOfProfit;
        final mtm = analysis.markToMarket;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final candidate in open)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _StrategyChip(
                        label: candidate.name,
                        selected: identical(candidate, strategy),
                        color: colors.hueFor(candidate.name),
                        palette: palette,
                        onTap: () => setState(() => _selected = candidate.name),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FinanceRun(
              height: 44,
              spacing: 24,
              children: [
                FinanceStat(
                  label: LocaleKeys.dashboard_money_openPnl.tr(),
                  value: mtm == null ? '—' : money.fit(mtm, signed: true),
                  valueColor: colors.change(mtm),
                  palette: palette,
                ),
                FinanceStat(
                  label: LocaleKeys.dashboard_money_maxProfit.tr(),
                  value: _boundText(
                    bounds.maxProfit,
                    bounds.unlimitedProfit,
                    money,
                  ),
                  valueColor: colors.gain,
                  palette: palette,
                ),
                FinanceStat(
                  label: LocaleKeys.dashboard_money_maxLoss.tr(),
                  value:
                      _boundText(bounds.maxLoss, bounds.unlimitedLoss, money),
                  valueColor: colors.loss,
                  palette: palette,
                ),
                FinanceStat(
                  label: LocaleKeys.dashboard_money_breakevens.tr(),
                  value: bounds.breakevens.isEmpty
                      ? '—'
                      : bounds.breakevens
                          .map((value) => formatLevel(value))
                          .join(' · '),
                  palette: palette,
                ),
                FinanceStat(
                  label: LocaleKeys.dashboard_money_chanceOfProfit.tr(),
                  value: pop == null
                      ? '—'
                      : formatPercent(pop, decimals: 0, signed: false),
                  palette: palette,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FinancePayoffChart(
                key: ValueKey(strategy.name),
                low: low,
                high: high,
                expiry: strategy.payoffAt,
                today: analysis.hasTimeValue ? analysis.todayAt : null,
                spot: analysis.spot,
                breakevens: bounds.breakevens,
                strikes: [
                  for (final leg in strategy.openLegs)
                    if (leg.strike != null)
                      PayoffMark(
                        leg.strike!,
                        _legLabel(leg),
                        buy: leg.side == OptionSide.buy,
                      ),
                ],
                colors: colors,
                palette: palette,
                formatMoney: (value) => money.compact(value, signed: true),
                formatPrice: (value) => formatLevel(value),
                labels: _payoffLabels(),
                still: still,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StrategyChip extends StatelessWidget {
  const _StrategyChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final DashboardPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FinanceHover(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: DashboardMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: palette.isDark ? 0.24 : 0.14)
                : (hovered ? palette.hover : palette.sunken),
            borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
            border: Border.all(
              color: color.withValues(alpha: selected ? 0.5 : 0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: financeLabel(
                  selected ? palette.textPrimary : palette.textSecondary,
                  size: 12,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
}

// -------------------------------------------------------------------- chain

final _chain = DashboardWidgetDefinition(
  type: 'option_chain',
  label: () => LocaleKeys.dashboard_money_optionChain.tr(),
  description: () => LocaleKeys.dashboard_money_optionChainHint.tr(),
  icon: Icons.table_rows_rounded,
  group: DashboardWidgetGroup.money,
  defaultColumnSpan: 12,
  defaultRowSpan: 10,
  minimumColumnSpan: 6,
  minimumRowSpan: 5,
  identity: DashboardAccent.purple,
  defaultTitle: () => LocaleKeys.dashboard_money_optionChain.tr(),
  defaultSettings: const {_keyUnderlying: 'NIFTY', _keyAround: 12},
  keywords: const [
    'option chain',
    'open interest',
    'oi',
    'pcr',
    'max pain',
    'nifty',
    'banknifty',
    'nse',
  ],
  builder: (data) => _ChainView(data: data),
  configure: (data) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_money_underlying.tr(),
      hint: LocaleKeys.dashboard_money_underlyingHint.tr(),
      value: data.spec.setting(_keyUnderlying, fallback: 'NIFTY'),
      onChanged: (value) =>
          data.setSettings({_keyUnderlying: value.trim().toUpperCase()}),
    ),
    DashboardConfigNumber(
      label: LocaleKeys.dashboard_money_strikesAround.tr(),
      value: data.spec.number(_keyAround, fallback: 12),
      minimum: 4,
      maximum: 30,
      onChanged: (value) => data.setSettings({_keyAround: value.round()}),
    ),
    financeTableField(data,
        label: LocaleKeys.dashboard_money_yourPosition.tr()),
  ],
);

class _ChainView extends StatefulWidget {
  const _ChainView({required this.data});

  final DashboardWidgetContext data;

  @override
  State<_ChainView> createState() => _ChainViewState();
}

class _ChainViewState extends State<_ChainView> {
  static const _rowHeight = 30.0;
  static const _markerHeight = 20.0;

  String? _underlying;
  DateTime? _expiry;
  final ScrollController _scroll = ScrollController();
  String? _centredOn;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _centre(OptionChain chain, int atm, bool markerAbove) {
    final key = '${chain.underlying}|${chain.expiry}';
    if (_centredOn == key) {
      return;
    }
    _centredOn = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      final viewport = _scroll.position.viewportDimension;
      final offset = atm * _rowHeight + (markerAbove ? _markerHeight : 0);
      final target = (offset - viewport / 2 + _rowHeight / 2)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    final underlying =
        (_underlying ?? data.spec.setting(_keyUnderlying, fallback: 'NIFTY'))
            .trim()
            .toUpperCase();
    return FinanceView(
      data: data,
      builder: (context, feed) {
        final market = feed.market;
        final positions = feed.bound
            ? readOptionLegs(feed.table, settings: data.spec.settings)
                .where((leg) => leg.isOpen && leg.underlying == underlying)
                .toList()
            : const <OptionLeg>[];
        final request = ChainRequest(underlying, _expiry);
        market.want(
          symbols: {marketSymbolForUnderlying(underlying)},
          chains: {request},
        );
        final provider = market.provider;
        final header = _ChainHeader(
          underlying: underlying,
          expiry: _expiry,
          expiries: provider?.expiries(underlying) ?? const [],
          chain: market.chain(request),
          quote: market.quote(marketSymbolForUnderlying(underlying)),
          palette: palette,
          colors: colors,
          market: market,
          still: still,
          onUnderlying: (value) => setState(() {
            _underlying = value;
            _expiry = null;
          }),
          onExpiry: (value) => setState(() => _expiry = value),
        );
        if (provider == null) {
          return Column(
            children: [
              header,
              Expanded(
                child: FinanceGhost(
                  palette: palette,
                  shape: FinanceGhostShape.rows,
                  icon: Icons.table_rows_rounded,
                  message: LocaleKeys.dashboard_money_chainNeedsExtension.tr(),
                  color: data.tone.strong,
                ),
              ),
            ],
          );
        }
        if (!provider.supportsChain(underlying)) {
          return Column(
            children: [
              header,
              Expanded(
                child: Center(
                  child: Text(
                    LocaleKeys.dashboard_money_chainUnsupported.tr(
                      args: [underlying],
                    ),
                    style: DashboardType.caption(palette),
                  ),
                ),
              ),
            ],
          );
        }
        final chain = market.chain(request);
        if (chain == null) {
          final error = provider.chainError(request);
          return Column(
            children: [
              header,
              Expanded(
                child: error == null
                    ? ListView(
                        padding: const EdgeInsets.only(top: 12),
                        children: [
                          for (var row = 0; row < 8; row++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: FinanceShimmer(
                                palette: palette,
                                height: 14,
                                still: still,
                              ),
                            ),
                        ],
                      )
                    : DashboardPlaceholder(
                        palette: palette,
                        icon: Icons.refresh_rounded,
                        message: LocaleKeys.dashboard_money_chainFailed.tr(),
                        action: LocaleKeys.dashboard_money_refresh.tr(),
                        onAction: () =>
                            unawaited(provider.refresh(force: true)),
                        color: data.tone.strong,
                      ),
              ),
            ],
          );
        }
        final around = data.spec.integer(_keyAround, fallback: 12);
        final atm = chain.atmIndex;
        final first = math.max(0, atm - around);
        final last = math.min(chain.rows.length, atm + around + 1);
        final rows = chain.rows.sublist(first, last);
        final localAtm = atm - first;
        var maxInterest = 1.0;
        for (final row in rows) {
          maxInterest = math.max(
            maxInterest,
            math.max(row.call?.openInterest ?? 0, row.put?.openInterest ?? 0),
          );
        }
        final spot = chain.spot;
        var spotIndex = -1;
        if (spot != null) {
          for (var index = 0; index < rows.length - 1; index++) {
            if (rows[index].strike <= spot && rows[index + 1].strike > spot) {
              spotIndex = index;
              break;
            }
          }
        }
        _centre(chain, localAtm, spotIndex >= 0 && spotIndex < localAtm);
        return Column(
          children: [
            header,
            const SizedBox(height: 8),
            _ChainColumns(palette: palette, colors: colors),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.zero,
                children: [
                  for (var index = 0; index < rows.length; index++) ...[
                    SizedBox(
                      height: _rowHeight,
                      child: _ChainRow(
                        row: rows[index],
                        spot: spot,
                        maxInterest: maxInterest,
                        palette: palette,
                        colors: colors,
                        positions: [
                          for (final leg in positions)
                            if (leg.strike == rows[index].strike &&
                                leg.expiry != null &&
                                DateTime(
                                      leg.expiry!.year,
                                      leg.expiry!.month,
                                      leg.expiry!.day,
                                    ) ==
                                    chain.expiry)
                              leg,
                        ],
                      ),
                    ),
                    if (index == spotIndex && spot != null)
                      SizedBox(
                        height: _markerHeight,
                        child: _SpotMarker(spot: spot, palette: palette),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChainHeader extends StatelessWidget {
  const _ChainHeader({
    required this.underlying,
    required this.expiry,
    required this.expiries,
    required this.chain,
    required this.quote,
    required this.palette,
    required this.colors,
    required this.market,
    required this.still,
    required this.onUnderlying,
    required this.onExpiry,
  });

  final String underlying;
  final DateTime? expiry;
  final List<DateTime> expiries;
  final OptionChain? chain;
  final MarketQuote? quote;
  final DashboardPalette palette;
  final FinanceColors colors;
  final MarketWatch market;
  final bool still;
  final ValueChanged<String> onUnderlying;
  final ValueChanged<DateTime?> onExpiry;

  @override
  Widget build(BuildContext context) {
    final chain = this.chain;
    final spot = chain?.spot ?? quote?.price;
    final change = quote?.changePercent;
    final pcr = chain?.putCallRatio;
    final selected = expiry ?? chain?.expiry;
    final names = {..._chainUnderlyings, underlying}.toList();
    final today = DateTime.now();
    final upcoming = [
      for (final date in expiries)
        if (!date.isBefore(DateTime(today.year, today.month, today.day))) date,
    ].take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 30,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final name in names)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _StrategyChip(
                          label: name,
                          selected: name == underlying,
                          color: palette.accent,
                          palette: palette,
                          onTap: () => onUnderlying(name),
                        ),
                      ),
                  ],
                ),
              ),
              if (spot != null) ...[
                const SizedBox(width: 10),
                Text(
                  formatLevel(spot, decimals: 2),
                  style: financeNumber(
                    palette.textPrimary,
                    size: 15,
                    weight: FontWeight.w700,
                  ),
                ),
                if (change != null) ...[
                  const SizedBox(width: 6),
                  ChangePill(
                    colors: colors,
                    value: change,
                    dense: true,
                    text: formatPercent(change, signed: false),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 26,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final date in upcoming)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _ExpiryChip(
                          label: DateFormat.MMMd().format(date),
                          selected: selected == date,
                          palette: palette,
                          onTap: () => onExpiry(date),
                        ),
                      ),
                  ],
                ),
              ),
              if (pcr != null)
                _Badge(
                  label: LocaleKeys.dashboard_money_putCallRatio.tr(),
                  value: pcr.toStringAsFixed(2),
                  color: pcr >= 1 ? colors.gain : colors.loss,
                  palette: palette,
                ),
              if (chain?.maxPain != null) ...[
                const SizedBox(width: 6),
                _Badge(
                  label: LocaleKeys.dashboard_money_maxPain.tr(),
                  value: formatLevel(chain!.maxPain!),
                  color: palette.textPrimary,
                  palette: palette,
                ),
              ],
              const SizedBox(width: 8),
              Flexible(
                child: FinanceFreshness(
                  palette: palette,
                  colors: colors,
                  market: market,
                  updated: chain?.fetchedAt,
                  still: still,
                ),
              ),
              if (market.provider != null)
                DashboardIconButton(
                  icon: Icons.refresh_rounded,
                  palette: palette,
                  size: 24,
                  iconSize: 14,
                  tooltip: LocaleKeys.dashboard_money_refresh.tr(),
                  onPressed: () =>
                      unawaited(market.provider!.refresh(force: true)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpiryChip extends StatelessWidget {
  const _ExpiryChip({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final DashboardPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FinanceHover(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: DashboardMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? palette.accentSoft
                : (hovered ? palette.hover : palette.hoverBase),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.45)
                  : palette.border.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            label,
            style: financeLabel(
              selected ? palette.accent : palette.textSecondary,
              weight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: palette.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : palette.sunken,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: financeLabel(palette.textMuted, size: 10.5),
              ),
              TextSpan(
                text: value,
                style: financeNumber(color, size: 11.5),
              ),
            ],
          ),
        ),
      );
}

/// The proportions every chain row shares, so the header lines up.
const _chainFlex = [5, 4, 3, 5, 5, 5, 3, 4, 5];

class _ChainColumns extends StatelessWidget {
  const _ChainColumns({required this.palette, required this.colors});

  final DashboardPalette palette;
  final FinanceColors colors;

  @override
  Widget build(BuildContext context) {
    final labels = [
      LocaleKeys.dashboard_money_openInterest.tr(),
      LocaleKeys.dashboard_money_openInterestChange.tr(),
      LocaleKeys.dashboard_money_impliedVolatility.tr(),
      LocaleKeys.dashboard_money_ltp.tr(),
      LocaleKeys.dashboard_money_strike.tr(),
      LocaleKeys.dashboard_money_ltp.tr(),
      LocaleKeys.dashboard_money_impliedVolatility.tr(),
      LocaleKeys.dashboard_money_openInterestChange.tr(),
      LocaleKeys.dashboard_money_openInterest.tr(),
    ];
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 17,
              child: Text(
                LocaleKeys.dashboard_money_calls.tr(),
                textAlign: TextAlign.center,
                style: financeLabel(
                  colors.loss,
                  size: 11,
                  weight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const Spacer(flex: 5),
            Expanded(
              flex: 17,
              child: Text(
                LocaleKeys.dashboard_money_puts.tr(),
                textAlign: TextAlign.center,
                style: financeLabel(
                  colors.gain,
                  size: 11,
                  weight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var index = 0; index < labels.length; index++)
              Expanded(
                flex: _chainFlex[index],
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: financeLabel(palette.textMuted, size: 10.5),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChainRow extends StatelessWidget {
  const _ChainRow({
    required this.row,
    required this.spot,
    required this.maxInterest,
    required this.palette,
    required this.colors,
    required this.positions,
  });

  final OptionChainRow row;
  final double? spot;
  final double maxInterest;
  final DashboardPalette palette;
  final FinanceColors colors;
  final List<OptionLeg> positions;

  @override
  Widget build(BuildContext context) {
    final spot = this.spot;
    final callInMoney = spot != null && row.strike < spot;
    final putInMoney = spot != null && row.strike > spot;
    final itm = palette.isDark
        ? Colors.white.withValues(alpha: 0.04)
        : (palette.isPaper ? const Color(0x14B08A55) : const Color(0xFFFFF8E6));
    final call = row.call;
    final put = row.put;
    final callPositions =
        positions.where((leg) => leg.kind == LegKind.call).toList();
    final putPositions =
        positions.where((leg) => leg.kind == LegKind.put).toList();
    Widget number(String text, {Color? color, bool bold = false}) => Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: financeNumber(
            color ?? palette.textSecondary,
            size: 11.5,
            weight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        );
    String interest(double? value) => value == null ? '—' : formatCount(value);
    String percent(double? value) =>
        value == null ? '—' : value.toStringAsFixed(1);
    Widget price(OptionQuote? quote) {
      final last = quote?.lastPrice;
      final change = quote?.change;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          number(
            last == null ? '—' : last.toStringAsFixed(2),
            color: palette.textPrimary,
            bold: true,
          ),
          if (change != null)
            Text(
              change > 0
                  ? '+${change.toStringAsFixed(1)}'
                  : change.toStringAsFixed(1),
              style: financeNumber(colors.change(change), size: 9.5),
            ),
        ],
      );
    }

    Widget bar(double? value, {required bool left, required Color color}) {
      final fraction =
          value == null ? 0.0 : (value / maxInterest).clamp(0.0, 1.0);
      return Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: left ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              heightFactor: 0.62,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    begin: left ? Alignment.centerRight : Alignment.centerLeft,
                    end: left ? Alignment.centerLeft : Alignment.centerRight,
                    colors: [
                      color.withValues(alpha: 0.35),
                      color.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              ),
            ),
          ),
          number(interest(value)),
        ],
      );
    }

    final cells = [
      bar(call?.openInterest, left: true, color: colors.loss),
      number(
        interest(call?.openInterestChange),
        color: colors.change(call?.openInterestChange),
      ),
      number(percent(call?.impliedVolatility)),
      price(call),
      _StrikeCell(
        strike: row.strike,
        palette: palette,
        colors: colors,
        callPositions: callPositions,
        putPositions: putPositions,
      ),
      price(put),
      number(percent(put?.impliedVolatility)),
      number(
        interest(put?.openInterestChange),
        color: colors.change(put?.openInterestChange),
      ),
      bar(put?.openInterest, left: false, color: colors.gain),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                flex: 17,
                child:
                    ColoredBox(color: callInMoney ? itm : Colors.transparent),
              ),
              const Spacer(flex: 5),
              Expanded(
                flex: 17,
                child: ColoredBox(color: putInMoney ? itm : Colors.transparent),
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: palette.border.withValues(alpha: 0.25),
                ),
              ),
            ),
            child: Row(
              children: [
                for (var index = 0; index < cells.length; index++)
                  Expanded(flex: _chainFlex[index], child: cells[index]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Where the underlying is trading, drawn between the strikes it sits between.
class _SpotMarker extends StatelessWidget {
  const _SpotMarker({required this.spot, required this.palette});

  final double spot;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.accent.withValues(alpha: 0),
                  palette.accent,
                  palette.accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '${LocaleKeys.dashboard_money_spot.tr()} ${formatLevel(spot, decimals: 2)}',
              style: financeLabel(
                palette.onAccent,
                size: 10,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
}

class _StrikeCell extends StatelessWidget {
  const _StrikeCell({
    required this.strike,
    required this.palette,
    required this.colors,
    required this.callPositions,
    required this.putPositions,
  });

  final double strike;
  final DashboardPalette palette;
  final FinanceColors colors;
  final List<OptionLeg> callPositions;
  final List<OptionLeg> putPositions;

  @override
  Widget build(BuildContext context) {
    Widget mark(List<OptionLeg> legs) {
      if (legs.isEmpty) {
        return const SizedBox(width: 6);
      }
      final net =
          legs.fold<double>(0, (sum, leg) => sum + leg.sign * leg.quantity);
      final color = net >= 0 ? colors.gain : colors.loss;
      return Tooltip(
        message: legs.map(_legLabel).join('\n'),
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: palette.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : palette.sunken,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          mark(callPositions),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              formatLevel(strike, decimals: strike % 1 == 0 ? 0 : 1),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: financeNumber(
                palette.textPrimary,
                size: 12,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          mark(putPositions),
        ],
      ),
    );
  }
}
