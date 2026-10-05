import 'dart:math' as math;

import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:flutter/foundation.dart';

enum BalanceSide { asset, liability }

/// How quickly something can become cash.
enum BalanceLiquidity {
  /// Days: cash, deposits that break, listed shares and funds.
  liquid,

  /// Weeks to months: gold, bonds, a vehicle.
  moderate,

  /// Locked until retirement or a sale: provident fund, NPS, property.
  locked,
}

/// What kind of thing an entry on a balance sheet is.
///
/// Matched from whatever a person typed in the category column, falling back
/// to the entry's name, so "SGB 2028" is gold and "HDFC home loan" is a home
/// loan even with no category at all.
enum BalanceCategory {
  realEstate(BalanceSide.asset, BalanceLiquidity.locked, [
    'real estate',
    'property',
    'apartment',
    'flat',
    'house',
    'land',
    'plot',
    'villa',
    'commercial',
  ]),
  gold(BalanceSide.asset, BalanceLiquidity.moderate, [
    'gold',
    'sgb',
    'sovereign gold',
    'silver',
    'jewellery',
    'jewelry',
    'bullion',
    'precious',
  ]),
  providentFund(BalanceSide.asset, BalanceLiquidity.locked, [
    'provident',
    'epf',
    'ppf',
    'vpf',
    'gpf',
    'pf',
  ]),
  pension(BalanceSide.asset, BalanceLiquidity.locked, [
    'nps',
    'pension',
    'retirement',
    'annuity',
    '401k',
    'ira',
    'apy',
    'superannuation',
  ]),
  mutualFunds(BalanceSide.asset, BalanceLiquidity.liquid, [
    'mutual fund',
    'mutual funds',
    'elss',
    'sip',
    'index fund',
    'etf',
    'fund',
    'mf',
  ]),
  stocks(BalanceSide.asset, BalanceLiquidity.liquid, [
    'stocks',
    'stock',
    'equity',
    'equities',
    'shares',
    'demat',
  ]),
  deposits(BalanceSide.asset, BalanceLiquidity.liquid, [
    'fixed deposit',
    'deposit',
    'deposits',
    'fd',
    'rd',
    'recurring',
    'nsc',
    'kvp',
    'post office',
    'scss',
  ]),
  cash(BalanceSide.asset, BalanceLiquidity.liquid, [
    'cash',
    'savings',
    'bank',
    'current account',
    'wallet',
    'emergency',
  ]),
  bonds(BalanceSide.asset, BalanceLiquidity.moderate, [
    'bond',
    'bonds',
    'debenture',
    'g-sec',
    'gsec',
    't-bill',
    'ncd',
    'debt fund',
  ]),
  crypto(BalanceSide.asset, BalanceLiquidity.liquid, [
    'crypto',
    'bitcoin',
    'btc',
    'ethereum',
    'eth',
  ]),
  insurance(BalanceSide.asset, BalanceLiquidity.locked, [
    'insurance',
    'ulip',
    'endowment',
    'policy',
    'lic',
  ]),
  vehicle(BalanceSide.asset, BalanceLiquidity.moderate, [
    'vehicle',
    'car',
    'bike',
    'scooter',
    'motorcycle',
  ]),
  otherAsset(BalanceSide.asset, BalanceLiquidity.moderate, []),
  homeLoan(BalanceSide.liability, BalanceLiquidity.locked, [
    'home loan',
    'housing loan',
    'mortgage',
  ]),
  vehicleLoan(BalanceSide.liability, BalanceLiquidity.moderate, [
    'car loan',
    'auto loan',
    'vehicle loan',
    'bike loan',
    'two-wheeler loan',
  ]),
  educationLoan(BalanceSide.liability, BalanceLiquidity.moderate, [
    'education loan',
    'student loan',
  ]),
  personalLoan(BalanceSide.liability, BalanceLiquidity.moderate, [
    'personal loan',
    'gold loan',
    'consumer loan',
  ]),
  creditCard(BalanceSide.liability, BalanceLiquidity.liquid, [
    'credit card',
    'card',
    'bnpl',
    'pay later',
  ]),
  otherLiability(BalanceSide.liability, BalanceLiquidity.moderate, [
    'loan',
    'borrowing',
    'debt',
    'emi',
    'owed',
  ]);

  const BalanceCategory(this.side, this.liquidity, this.words);

  final BalanceSide side;
  final BalanceLiquidity liquidity;
  final List<String> words;

  bool get isAsset => side == BalanceSide.asset;
}

/// The category [text] names, if any, among those on [side].
BalanceCategory? matchBalanceCategory(String text, {BalanceSide? side}) {
  final value = text.trim().toLowerCase();
  if (value.isEmpty) {
    return null;
  }
  final candidates = [
    for (final category in BalanceCategory.values)
      if (side == null || category.side == side) category,
  ];
  // The longest word wins: "home loan" beats "loan", "gold loan" beats
  // "gold". Short words only count as whole words, so "pf" is not "upfront".
  BalanceCategory? best;
  var bestLength = 0;
  for (final category in candidates) {
    for (final word in category.words) {
      if (word.length <= bestLength) {
        continue;
      }
      final hit = word.length <= 4
          ? RegExp('(^|[^a-z0-9])${RegExp.escape(word)}(\$|[^a-z0-9])')
              .hasMatch(value)
          : value.contains(word);
      if (hit) {
        best = category;
        bestLength = word.length;
      }
    }
  }
  return best;
}

const _liabilityWords = [
  'liability',
  'liabilities',
  'loan',
  'debt',
  'owe',
  'owed',
  'borrow',
  'credit card',
  'mortgage',
];

/// One line of a balance sheet.
@immutable
class BalanceItem {
  const BalanceItem({
    required this.name,
    required this.side,
    required this.category,
    required this.value,
    this.categoryLabel = '',
    this.invested,
    this.borrowed,
    this.rate,
    this.emi,
    this.updated,
    this.notes = '',
    this.rowId,
  });

  final String name;
  final BalanceSide side;
  final BalanceCategory category;

  /// What the person typed as the category, kept for display when it is more
  /// specific than [category] (an "SGB" is still shown as gold, but the
  /// words are not thrown away).
  final String categoryLabel;

  /// What an asset is worth, or what is still owed on a liability.
  final double value;

  /// What went into an asset.
  final double? invested;

  /// What was originally borrowed.
  final double? borrowed;

  /// The annual rate in percent: a loan's interest or an asset's return.
  final double? rate;
  final double? emi;
  final DateTime? updated;
  final String notes;
  final String? rowId;

  bool get isAsset => side == BalanceSide.asset;

  double? get gain {
    final invested = this.invested;
    if (!isAsset || invested == null || invested <= 0) {
      return null;
    }
    return value - invested;
  }

  double? get gainPercent {
    final gain = this.gain;
    return gain == null ? null : gain / invested! * 100;
  }

  LoanOutlook? get outlook => isAsset
      ? null
      : LoanOutlook.of(
          balance: value,
          annualRate: rate,
          emi: emi,
          borrowed: borrowed,
          asOf: updated,
        );
}

class BalanceRoles {
  static const name = FinanceRole.name;
  static const side = FinanceRole('sideColumn', [
    'type',
    'side',
    'kind',
    'asset/liability',
  ]);
  static const category = FinanceRole('categoryColumn', [
    'category',
    'asset class',
    'class',
    'group',
    'bucket',
  ]);
  static const value = FinanceRole('valueColumn', [
    'value',
    'current value',
    'balance',
    'outstanding',
    'amount',
    'worth',
  ]);
  static const invested = FinanceRole('investedColumn', [
    'invested',
    'cost basis',
    'cost',
    'purchase',
    'paid',
  ]);
  static const borrowed = FinanceRole('borrowedColumn', [
    'borrowed',
    'principal',
    'loan amount',
    'sanctioned',
    'original',
  ]);
  static const rate = FinanceRole('rateColumn', [
    'rate %',
    'rate',
    'interest',
    'roi',
    'apr',
    'return',
  ]);
  static const emi = FinanceRole('emiColumn', [
    'emi',
    'instalment',
    'installment',
    'monthly payment',
    'payment',
  ]);
  static const updated = FinanceRole('dateColumn', [
    'updated',
    'as of',
    'date',
    'valued on',
  ]);

  static const all = [
    side,
    category,
    value,
    invested,
    borrowed,
    rate,
    emi,
    updated,
    FinanceRole.notes,
    name,
  ];
}

/// Every entry a balance sheet lists.
List<BalanceItem> readBalanceItems(
  ChartTable table, {
  Map<String, Object?> settings = const {},
}) {
  final columns = FinanceColumns.resolve(
    table,
    BalanceRoles.all,
    settings: settings,
  );
  final sheet = FinanceSheet(table);
  final nameColumn =
      columns.has(BalanceRoles.name) ? columns[BalanceRoles.name] : 0;
  final items = <BalanceItem>[];
  for (var row = 0; row < sheet.length; row++) {
    final name = sheet.text(row, nameColumn);
    final value = sheet.number(row, columns[BalanceRoles.value]);
    if (value == null || (name.isEmpty && value == 0)) {
      continue;
    }
    final sideText = sheet.text(row, columns[BalanceRoles.side]).toLowerCase();
    final categoryText = sheet.text(row, columns[BalanceRoles.category]);
    final named = matchBalanceCategory(categoryText) ??
        matchBalanceCategory(name);
    final BalanceSide side;
    if (sideText.isNotEmpty) {
      side = _liabilityWords.any(sideText.contains) ||
              sideText == 'l' ||
              sideText == 'out'
          ? BalanceSide.liability
          : BalanceSide.asset;
    } else if (named != null) {
      side = named.side;
    } else {
      final words = '$categoryText $name'.toLowerCase();
      side = value < 0 || _liabilityWords.any(words.contains)
          ? BalanceSide.liability
          : BalanceSide.asset;
    }
    final category = matchBalanceCategory(categoryText, side: side) ??
        matchBalanceCategory(name, side: side) ??
        (side == BalanceSide.asset
            ? BalanceCategory.otherAsset
            : BalanceCategory.otherLiability);
    items.add(
      BalanceItem(
        name: name.isEmpty ? categoryText : name,
        side: side,
        category: category,
        categoryLabel: categoryText,
        value: value.abs(),
        invested: sheet.number(row, columns[BalanceRoles.invested]),
        borrowed: sheet.number(row, columns[BalanceRoles.borrowed]),
        rate: sheet.number(row, columns[BalanceRoles.rate]),
        emi: sheet.number(row, columns[BalanceRoles.emi]),
        updated: sheet.date(row, columns[BalanceRoles.updated]),
        notes: sheet.text(row, columns[FinanceRole.notes]),
        rowId: sheet.rowId(row),
      ),
    );
  }
  return items;
}

/// A category's share of one side of the sheet.
@immutable
class CategoryTotal {
  const CategoryTotal({
    required this.category,
    required this.value,
    required this.items,
    this.invested,
  });

  final BalanceCategory category;
  final double value;
  final List<BalanceItem> items;

  /// What went into the items that record it.
  final double? invested;

  double? get gainPercent {
    final invested = this.invested;
    if (invested == null || invested <= 0) {
      return null;
    }
    final tracked = items
        .where((item) => item.invested != null)
        .fold<double>(0, (sum, item) => sum + item.value);
    return (tracked - invested) / invested * 100;
  }
}

/// A balance sheet, added up.
@immutable
class BalanceSummary {
  const BalanceSummary._({
    required this.items,
    required this.assets,
    required this.liabilities,
    required this.liquid,
    required this.moderate,
    required this.locked,
    required this.assetCategories,
    required this.liabilityCategories,
    required this.monthlyEmi,
    required this.invested,
    required this.investedValue,
  });

  factory BalanceSummary.of(List<BalanceItem> items) {
    var assets = 0.0;
    var liabilities = 0.0;
    var liquid = 0.0;
    var moderate = 0.0;
    var locked = 0.0;
    var emi = 0.0;
    var invested = 0.0;
    var investedValue = 0.0;
    final byCategory = <BalanceCategory, List<BalanceItem>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
      if (item.isAsset) {
        assets += item.value;
        switch (item.category.liquidity) {
          case BalanceLiquidity.liquid:
            liquid += item.value;
          case BalanceLiquidity.moderate:
            moderate += item.value;
          case BalanceLiquidity.locked:
            locked += item.value;
        }
        if (item.invested != null && item.invested! > 0) {
          invested += item.invested!;
          investedValue += item.value;
        }
      } else {
        liabilities += item.value;
        emi += item.emi ?? 0;
      }
    }
    List<CategoryTotal> totals(BalanceSide side) {
      final result = [
        for (final entry in byCategory.entries)
          if (entry.key.side == side)
            CategoryTotal(
              category: entry.key,
              value: entry.value.fold(0, (sum, item) => sum + item.value),
              items: (List.of(entry.value)
                ..sort((a, b) => b.value.compareTo(a.value))),
              invested: entry.value.any((item) => item.invested != null)
                  ? entry.value.fold<double>(
                      0,
                      (sum, item) => sum + (item.invested ?? 0),
                    )
                  : null,
            ),
      ]..sort((a, b) => b.value.compareTo(a.value));
      return result;
    }

    return BalanceSummary._(
      items: items,
      assets: assets,
      liabilities: liabilities,
      liquid: liquid,
      moderate: moderate,
      locked: locked,
      assetCategories: totals(BalanceSide.asset),
      liabilityCategories: totals(BalanceSide.liability),
      monthlyEmi: emi,
      invested: invested,
      investedValue: investedValue,
    );
  }

  final List<BalanceItem> items;
  final double assets;
  final double liabilities;
  final double liquid;
  final double moderate;
  final double locked;
  final List<CategoryTotal> assetCategories;
  final List<CategoryTotal> liabilityCategories;
  final double monthlyEmi;

  /// What went into the assets that record it, and what those are worth.
  final double invested;
  final double investedValue;

  bool get isEmpty => items.isEmpty;

  double get netWorth => assets - liabilities;

  /// Debt for every rupee owned, in percent.
  double? get debtRatio => assets > 0 ? liabilities / assets * 100 : null;

  double? get liquidShare => assets > 0 ? liquid / assets * 100 : null;

  double? get gainPercent =>
      invested > 0 ? (investedValue - invested) / invested * 100 : null;

  Iterable<BalanceItem> get loans => items.where((item) => !item.isAsset);
}

/// When a loan ends, and what it still costs.
@immutable
class LoanOutlook {
  const LoanOutlook._({
    required this.balance,
    this.monthsLeft,
    this.payoffDate,
    this.interestLeft,
    this.repaidShare,
    this.neverRepaid = false,
    this.monthlyInterest,
  });

  /// Works out a loan's end from what is owed, the annual [annualRate] in
  /// percent and the monthly [emi]. With an [emi] no bigger than a month's
  /// interest the balance never falls, and [neverRepaid] says so.
  factory LoanOutlook.of({
    required double balance,
    double? annualRate,
    double? emi,
    double? borrowed,
    DateTime? asOf,
    DateTime? now,
  }) {
    final repaid = borrowed != null && borrowed > 0
        ? (1 - balance / borrowed).clamp(0, 1).toDouble()
        : null;
    final monthly = annualRate == null ? null : annualRate / 12 / 100;
    final interest = monthly == null ? null : balance * monthly;
    if (emi == null || emi <= 0 || balance <= 0) {
      return LoanOutlook._(
        balance: balance,
        repaidShare: repaid,
        monthlyInterest: interest,
      );
    }
    double months;
    if (monthly == null || monthly <= 0) {
      months = balance / emi;
    } else if (emi <= balance * monthly) {
      return LoanOutlook._(
        balance: balance,
        repaidShare: repaid,
        neverRepaid: true,
        monthlyInterest: interest,
      );
    } else {
      months = -math.log(1 - monthly * balance / emi) / math.log(1 + monthly);
    }
    final whole = months.ceil();
    final start = asOf ?? now ?? DateTime.now();
    return LoanOutlook._(
      balance: balance,
      monthsLeft: whole,
      payoffDate: DateTime(start.year, start.month + whole, start.day),
      interestLeft: math.max(0, emi * months - balance),
      repaidShare: repaid,
      monthlyInterest: interest,
    );
  }

  final double balance;
  final int? monthsLeft;
  final DateTime? payoffDate;
  final double? interestLeft;

  /// Between 0 and 1, when the original amount is known.
  final double? repaidShare;
  final bool neverRepaid;
  final double? monthlyInterest;
}
