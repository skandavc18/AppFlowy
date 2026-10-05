import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_binding.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_kit.dart';
import 'package:appflowy/shared/market/market_data.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/finance/balance_sheet.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:appflowy/workspace/application/finance/finance_row_writer.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:appflowy/workspace/application/finance/portfolio_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Holdings at the best price known: live where the market has one, the
/// table's own price otherwise. Asks the market to keep those symbols fresh.
List<PricedHolding> priceHoldings(List<Holding> holdings, MarketWatch market) {
  market.want(
    symbols: {
      for (final holding in holdings)
        if (holding.symbol.isNotEmpty) holding.symbol,
    },
  );
  return [
    for (final holding in holdings)
      () {
        final quote = market.quote(holding.symbol);
        return PricedHolding(
          holding,
          livePrice: quote?.price,
          previousClose: quote?.previousClose,
          intraday: quote?.closes ?? const [],
        );
      }(),
  ];
}

/// The newest moment any of [symbols] was priced.
DateTime? latestUpdate(MarketWatch market, Iterable<String> symbols) {
  DateTime? latest;
  for (final symbol in symbols) {
    final time = market.quote(symbol)?.updatedAt;
    if (time != null && (latest == null || time.isAfter(latest))) {
      latest = time;
    }
  }
  return latest;
}

/// "just now", "4 min ago", "2 h ago" or a date.
String financeAgo(DateTime time, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(time);
  if (age.inSeconds < 60) {
    return LocaleKeys.dashboard_money_justNow.tr();
  }
  if (age.inMinutes < 60) {
    return LocaleKeys.dashboard_money_minutesAgo.tr(args: ['${age.inMinutes}']);
  }
  if (age.inHours < 24) {
    return LocaleKeys.dashboard_money_hoursAgo.tr(args: ['${age.inHours}']);
  }
  return DateFormat.MMMd().format(time);
}

/// Whether [time] is recent enough to call the price live.
bool financeIsFresh(DateTime? time) =>
    time != null &&
    DateTime.now().difference(time) < const Duration(minutes: 5);

/// A dot and a few words saying how current the prices are.
class FinanceFreshness extends StatelessWidget {
  const FinanceFreshness({
    super.key,
    required this.palette,
    required this.colors,
    required this.market,
    required this.updated,
    required this.still,
    this.ink,
  });

  final DashboardPalette palette;
  final FinanceColors colors;
  final MarketWatch market;
  final DateTime? updated;
  final bool still;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final time = updated;
    final live = market.isLive && financeIsFresh(time);
    final String text;
    if (!market.isLive) {
      text = LocaleKeys.dashboard_money_tablePrices.tr();
    } else if (time == null) {
      text = LocaleKeys.dashboard_money_reading.tr();
    } else if (live) {
      text = '${LocaleKeys.dashboard_money_live.tr()} · ${financeAgo(time)}';
    } else {
      text =
          '${LocaleKeys.dashboard_money_lastKnown.tr()} · ${financeAgo(time)}';
    }
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiveDot(
          color: live ? colors.gain : (ink ?? palette.textMuted),
          live: live,
          still: still,
          size: 6,
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: financeLabel(ink ?? palette.textMuted, size: 11),
          ),
        ),
      ],
    );
    return market.isLive
        ? label
        : Tooltip(
            message: LocaleKeys.dashboard_money_liveHint.tr(),
            child: label,
          );
  }
}

// -------------------------------------------------------------- categories

String balanceCategoryLabel(BalanceCategory category) => switch (category) {
      BalanceCategory.realEstate =>
        LocaleKeys.dashboard_money_categoryRealEstate.tr(),
      BalanceCategory.gold => LocaleKeys.dashboard_money_categoryGold.tr(),
      BalanceCategory.providentFund =>
        LocaleKeys.dashboard_money_categoryProvidentFund.tr(),
      BalanceCategory.pension =>
        LocaleKeys.dashboard_money_categoryPension.tr(),
      BalanceCategory.mutualFunds =>
        LocaleKeys.dashboard_money_categoryMutualFunds.tr(),
      BalanceCategory.stocks => LocaleKeys.dashboard_money_categoryStocks.tr(),
      BalanceCategory.deposits =>
        LocaleKeys.dashboard_money_categoryDeposits.tr(),
      BalanceCategory.cash => LocaleKeys.dashboard_money_categoryCash.tr(),
      BalanceCategory.bonds => LocaleKeys.dashboard_money_categoryBonds.tr(),
      BalanceCategory.crypto => LocaleKeys.dashboard_money_categoryCrypto.tr(),
      BalanceCategory.insurance =>
        LocaleKeys.dashboard_money_categoryInsurance.tr(),
      BalanceCategory.vehicle =>
        LocaleKeys.dashboard_money_categoryVehicle.tr(),
      BalanceCategory.otherAsset =>
        LocaleKeys.dashboard_money_categoryOtherAsset.tr(),
      BalanceCategory.homeLoan =>
        LocaleKeys.dashboard_money_categoryHomeLoan.tr(),
      BalanceCategory.vehicleLoan =>
        LocaleKeys.dashboard_money_categoryVehicleLoan.tr(),
      BalanceCategory.educationLoan =>
        LocaleKeys.dashboard_money_categoryEducationLoan.tr(),
      BalanceCategory.personalLoan =>
        LocaleKeys.dashboard_money_categoryPersonalLoan.tr(),
      BalanceCategory.creditCard =>
        LocaleKeys.dashboard_money_categoryCreditCard.tr(),
      BalanceCategory.otherLiability =>
        LocaleKeys.dashboard_money_categoryOtherLiability.tr(),
    };

IconData balanceCategoryIcon(BalanceCategory category) => switch (category) {
      BalanceCategory.realEstate => Icons.home_work_rounded,
      BalanceCategory.gold => Icons.diamond_rounded,
      BalanceCategory.providentFund => Icons.account_balance_rounded,
      BalanceCategory.pension => Icons.elderly_rounded,
      BalanceCategory.mutualFunds => Icons.pie_chart_rounded,
      BalanceCategory.stocks => Icons.candlestick_chart_rounded,
      BalanceCategory.deposits => Icons.savings_rounded,
      BalanceCategory.cash => Icons.account_balance_wallet_rounded,
      BalanceCategory.bonds => Icons.receipt_long_rounded,
      BalanceCategory.crypto => Icons.currency_bitcoin_rounded,
      BalanceCategory.insurance => Icons.health_and_safety_rounded,
      BalanceCategory.vehicle => Icons.directions_car_rounded,
      BalanceCategory.otherAsset => Icons.category_rounded,
      BalanceCategory.homeLoan => Icons.house_rounded,
      BalanceCategory.vehicleLoan => Icons.car_rental_rounded,
      BalanceCategory.educationLoan => Icons.school_rounded,
      BalanceCategory.personalLoan => Icons.request_quote_rounded,
      BalanceCategory.creditCard => Icons.credit_card_rounded,
      BalanceCategory.otherLiability => Icons.money_off_rounded,
    };

/// Each category's own colour: gold is gold, property is terracotta, the
/// retirement funds are calm blues and greens, debts are warm reds.
Color balanceCategoryColor(BalanceCategory category, FinanceColors colors) {
  final dark = colors.isDark;
  final paper = colors.isPaper;
  Color pick(int light, int night, int warm) =>
      Color(paper ? warm : (dark ? night : light));
  return switch (category) {
    BalanceCategory.realEstate => pick(0xFFE76F51, 0xFFF4A261, 0xFFC0674E),
    BalanceCategory.gold => pick(0xFFE0A100, 0xFFF6C744, 0xFFB98B2A),
    BalanceCategory.providentFund => pick(0xFF3B82F6, 0xFF60A5FA, 0xFF4F7FB0),
    BalanceCategory.pension => pick(0xFF0EA5A4, 0xFF2DD4BF, 0xFF3C8F86),
    BalanceCategory.mutualFunds => pick(0xFF8B5CF6, 0xFFA78BFA, 0xFF8466B0),
    BalanceCategory.stocks => pick(0xFF6366F1, 0xFF818CF8, 0xFF6B6FB5),
    BalanceCategory.deposits => pick(0xFF10B981, 0xFF34D399, 0xFF4F9A72),
    BalanceCategory.cash => pick(0xFF22A06B, 0xFF4ADE80, 0xFF5C9A5A),
    BalanceCategory.bonds => pick(0xFF64748B, 0xFF94A3B8, 0xFF7E8A96),
    BalanceCategory.crypto => pick(0xFFF7931A, 0xFFFBBF24, 0xFFC4802E),
    BalanceCategory.insurance => pick(0xFF0891B2, 0xFF22D3EE, 0xFF3E8EA3),
    BalanceCategory.vehicle => pick(0xFF78716C, 0xFFA8A29E, 0xFF8C7B6B),
    BalanceCategory.otherAsset => pick(0xFF94A3B8, 0xFFCBD5E1, 0xFF9C8F80),
    BalanceCategory.homeLoan => pick(0xFFE11D48, 0xFFFB7185, 0xFFB8493A),
    BalanceCategory.vehicleLoan => pick(0xFFF97316, 0xFFFB923C, 0xFFC9733A),
    BalanceCategory.educationLoan => pick(0xFFDB2777, 0xFFF472B6, 0xFFB5628C),
    BalanceCategory.personalLoan => pick(0xFFEF4444, 0xFFF87171, 0xFFC25B5B),
    BalanceCategory.creditCard => pick(0xFFBE185D, 0xFFF9A8D4, 0xFFA8566F),
    BalanceCategory.otherLiability => pick(0xFFDC2626, 0xFFFCA5A5, 0xFFB0574A),
  };
}

String balanceLiquidityLabel(BalanceLiquidity liquidity) => switch (liquidity) {
      BalanceLiquidity.liquid =>
        LocaleKeys.dashboard_money_liquidityLiquid.tr(),
      BalanceLiquidity.moderate =>
        LocaleKeys.dashboard_money_liquidityModerate.tr(),
      BalanceLiquidity.locked =>
        LocaleKeys.dashboard_money_liquidityLocked.tr(),
    };

// ------------------------------------------------------------ configuration

DashboardConfigField financeTableField(
  DashboardWidgetContext data, {
  String? label,
}) =>
    DashboardConfigView(
      label: label ?? LocaleKeys.dashboard_money_table.tr(),
      viewId: data.spec.source.viewId,
      name: data.spec.source.name,
      filter: financeIsDatabase,
      onChanged: (viewId, name) => data.setSource(
        data.spec.source.copyWith(
          kind: viewId.isEmpty
              ? DashboardSourceKind.none
              : DashboardSourceKind.database,
          viewId: viewId,
          name: name,
        ),
      ),
    );

DashboardConfigField financeCurrencyField(DashboardWidgetContext data) =>
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_money_currency.tr(),
      value: data.spec.setting('currency', fallback: 'INR'),
      choices: [
        for (final code in MoneyStyle.currencies)
          DashboardChoice(
            value: code,
            label: code == 'NONE'
                ? LocaleKeys.dashboard_money_currencyNone.tr()
                : '${MoneyStyle.forCurrency(code).symbol}  $code',
          ),
      ],
      onChanged: (value) => data.setSettings({'currency': value}),
    );

/// Text fields that point each role at a column by name, collapsed until
/// somebody needs them: guessing from header words is right far more often.
DashboardConfigField financeColumnsField(
  DashboardWidgetContext data,
  List<(FinanceRole, String)> roles,
) =>
    DashboardConfigGroup(
      label: LocaleKeys.dashboard_money_columns.tr(),
      initiallyOpen: false,
      fields: [
        for (final (role, label) in roles)
          DashboardConfigText(
            label: label,
            hint: LocaleKeys.dashboard_money_columnHint.tr(),
            value: data.spec.setting(role.key),
            onChanged: (value) => data.setSettings({role.key: value.trim()}),
          ),
      ],
    );

// ----------------------------------------------------------------- writing

/// Adds a row to the widget's table: [values] are keyed by role, and each is
/// written into whichever column that role resolves to.
Future<bool> financeAddRow(
  DashboardWidgetContext data,
  ChartTable table,
  List<FinanceRole> roles,
  Map<String, String> values, {
  Map<String, String> fallbackColumns = const {},
}) async {
  final viewId = data.spec.source.viewId;
  if (viewId.isEmpty) {
    return false;
  }
  final columns = FinanceColumns.resolve(
    table,
    roles,
    settings: data.spec.settings,
  );
  final byColumn = <String, String>{};
  for (final role in roles) {
    final value = values[role.key];
    if (value == null || value.trim().isEmpty) {
      continue;
    }
    final index = columns[role];
    if (index >= 0) {
      final id = index < table.columnIds.length
          ? table.columnIds[index]
          : table.columns[index];
      byColumn[id] = value;
    } else if (fallbackColumns.containsKey(role.key)) {
      byColumn[fallbackColumns[role.key]!] = value;
    }
  }
  if (byColumn.isEmpty) {
    return false;
  }
  // Every reader of the table hears the new row through the database's own
  // notifications; refreshing the dashboard would also refetch every price.
  return await FinanceRowWriter(viewId).addRow(byColumn) != null;
}

/// A settings value read as a list of strings.
List<String> financeStringList(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }
  if (value is String) {
    return [
      for (final part in value.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }
  return const [];
}

/// The colour of a holding or category by its index, shared by every widget
/// that draws the same breakdown.
Color sliceColor(FinanceColors colors, int index, {bool other = false}) => other
    ? colors.palette.textMuted.withValues(alpha: 0.55)
    : colors.hue(index);

/// Room enough for [count] columns of at least [minimum] pixels.
int financeColumnsFor(double width, double minimum, {int maximum = 6}) =>
    math.max(1, math.min(maximum, (width / minimum).floor()));
