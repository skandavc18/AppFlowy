import 'dart:math' as math;

import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:flutter/foundation.dart';

/// One position, as a table describes it.
@immutable
class Holding {
  const Holding({
    required this.name,
    this.symbol = '',
    this.sector = '',
    this.quantity = 0,
    this.averagePrice,
    this.lastPrice,
    this.value,
    this.invested,
    this.boughtOn,
    this.notes = '',
    this.rowId,
  });

  final String name;

  /// The market symbol, `RELIANCE.NS`. Empty for something without a market
  /// price, such as a private holding valued by hand.
  final String symbol;
  final String sector;
  final double quantity;
  final double? averagePrice;

  /// The price the table holds, used whenever no live price is known.
  final double? lastPrice;

  /// A value written straight into the table, for holdings priced by hand.
  final double? value;
  final double? invested;
  final DateTime? boughtOn;
  final String notes;
  final String? rowId;

  /// What went in: the column when there is one, else quantity at cost.
  double get investedAmount {
    if (invested != null) {
      return invested!;
    }
    if (averagePrice != null && quantity > 0) {
      return averagePrice! * quantity;
    }
    return value ?? 0;
  }

  static const roles = [
    FinanceRole.symbol,
    FinanceRole.quantity,
    FinanceRole.averagePrice,
    FinanceRole.lastPrice,
    FinanceRole.invested,
    FinanceRole.value,
    FinanceRole.date,
    FinanceRole.sector,
    FinanceRole.name,
    FinanceRole.notes,
  ];

  /// Every position a table lists. Rows with no name, symbol or amount are
  /// half-typed and left out.
  static List<Holding> read(
    ChartTable table, {
    Map<String, Object?> settings = const {},
  }) {
    final columns = FinanceColumns.resolve(table, roles, settings: settings);
    final sheet = FinanceSheet(table);
    final nameColumn =
        columns.has(FinanceRole.name) ? columns[FinanceRole.name] : 0;
    final holdings = <Holding>[];
    for (var row = 0; row < sheet.length; row++) {
      final symbol = sheet.text(row, columns[FinanceRole.symbol]).toUpperCase();
      final name = sheet.text(row, nameColumn);
      final quantity = sheet.number(row, columns[FinanceRole.quantity]) ?? 0;
      final average = sheet.number(row, columns[FinanceRole.averagePrice]);
      final price = sheet.number(row, columns[FinanceRole.lastPrice]);
      final value = sheet.number(row, columns[FinanceRole.value]);
      final invested = sheet.number(row, columns[FinanceRole.invested]);
      final priced = quantity != 0 &&
          (average != null || price != null || symbol.isNotEmpty);
      // A row with nothing to value it by is still being typed.
      if ((name.isEmpty && symbol.isEmpty) ||
          (!priced && value == null && invested == null)) {
        continue;
      }
      holdings.add(
        Holding(
          name: name.isEmpty ? symbol : name,
          symbol: symbol,
          sector: sheet.text(row, columns[FinanceRole.sector]),
          quantity: quantity,
          averagePrice: average,
          lastPrice: price,
          value: value,
          invested: invested,
          boughtOn: sheet.date(row, columns[FinanceRole.date]),
          notes: sheet.text(row, columns[FinanceRole.notes]),
          rowId: sheet.rowId(row),
        ),
      );
    }
    return holdings;
  }
}

/// A holding valued at the best price known right now.
@immutable
class PricedHolding {
  const PricedHolding(
    this.holding, {
    this.livePrice,
    this.previousClose,
    this.intraday = const [],
  });

  final Holding holding;

  /// The market's price, when a feed supplied one.
  final double? livePrice;
  final double? previousClose;

  /// Today's prices, oldest first, for a sparkline.
  final List<double> intraday;

  bool get isLive => livePrice != null;

  /// The price the holding is valued at.
  double? get price => livePrice ?? holding.lastPrice;

  double get value {
    final price = this.price;
    if (price != null && holding.quantity > 0) {
      return price * holding.quantity;
    }
    return holding.value ?? holding.investedAmount;
  }

  double get invested => holding.investedAmount;

  double get pnl => value - invested;

  double? get pnlPercent => invested > 0 ? pnl / invested * 100 : null;

  /// How far the price moved today, per share.
  double? get dayMove {
    final price = livePrice;
    final close = previousClose;
    if (price == null || close == null) {
      return null;
    }
    return price - close;
  }

  /// What today's move made or lost on the whole position.
  double? get dayChange {
    final move = dayMove;
    return move == null ? null : move * holding.quantity;
  }

  double? get dayPercent {
    final move = dayMove;
    final close = previousClose;
    if (move == null || close == null || close == 0) {
      return null;
    }
    return move / close * 100;
  }
}

/// A slice of a whole, for a donut, a bar or a treemap.
@immutable
class AllocationSlice {
  const AllocationSlice({
    required this.label,
    required this.value,
    required this.share,
    this.isOther = false,
  });

  final String label;
  final double value;

  /// Of the whole, between 0 and 1.
  final double share;

  /// Whether this gathers the long tail.
  final bool isOther;
}

/// Sums [parts] by label and keeps the largest, folding the rest into one
/// [otherLabel] slice so a long tail does not crowd out the picture.
List<AllocationSlice> allocate(
  Iterable<(String, double)> parts, {
  int maxSlices = 7,
  String otherLabel = 'Other',
}) {
  final totals = <String, double>{};
  for (final (label, value) in parts) {
    if (value <= 0 || !value.isFinite) {
      continue;
    }
    final key = label.trim().isEmpty ? otherLabel : label.trim();
    totals[key] = (totals[key] ?? 0) + value;
  }
  final total = totals.values.fold<double>(0, (sum, value) => sum + value);
  if (total <= 0) {
    return const [];
  }
  final sorted = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final slices = <AllocationSlice>[];
  var rest = 0.0;
  for (var index = 0; index < sorted.length; index++) {
    final entry = sorted[index];
    final keep = index < maxSlices - 1 ||
        (index == maxSlices - 1 && sorted.length == maxSlices);
    if (keep && entry.key != otherLabel) {
      slices.add(
        AllocationSlice(
          label: entry.key,
          value: entry.value,
          share: entry.value / total,
        ),
      );
    } else {
      rest += entry.value;
    }
  }
  if (rest > 0) {
    slices.add(
      AllocationSlice(
        label: otherLabel,
        value: rest,
        share: rest / total,
        isOther: true,
      ),
    );
  }
  return slices;
}

/// The whole portfolio, added up.
@immutable
class PortfolioSnapshot {
  const PortfolioSnapshot._({
    required this.holdings,
    required this.value,
    required this.invested,
    required this.dayChange,
    required this.dayBase,
    required this.liveCount,
    required this.xirr,
  });

  factory PortfolioSnapshot.of(
    List<PricedHolding> holdings, {
    DateTime? now,
  }) {
    var value = 0.0;
    var invested = 0.0;
    var dayChange = 0.0;
    var dayBase = 0.0;
    var live = 0;
    for (final holding in holdings) {
      value += holding.value;
      invested += holding.invested;
      final change = holding.dayChange;
      if (change != null) {
        live++;
        dayChange += change;
        dayBase += holding.value - change;
      }
    }
    return PortfolioSnapshot._(
      holdings: holdings,
      value: value,
      invested: invested,
      dayChange: dayChange,
      dayBase: dayBase,
      liveCount: live,
      xirr: _portfolioXirr(holdings, now ?? DateTime.now()),
    );
  }

  static const empty = PortfolioSnapshot._(
    holdings: [],
    value: 0,
    invested: 0,
    dayChange: 0,
    dayBase: 0,
    liveCount: 0,
    xirr: null,
  );

  final List<PricedHolding> holdings;
  final double value;
  final double invested;

  /// Today's change on the holdings with a live price.
  final double dayChange;

  /// Yesterday's value of the holdings [dayChange] covers.
  final double dayBase;
  final int liveCount;

  /// Annualised return from the dates holdings were bought, in percent.
  final double? xirr;

  bool get isEmpty => holdings.isEmpty;

  double get pnl => value - invested;

  double? get pnlPercent => invested > 0 ? pnl / invested * 100 : null;

  double? get dayPercent =>
      liveCount > 0 && dayBase > 0 ? dayChange / dayBase * 100 : null;

  /// The holding that rose most today, by percent.
  PricedHolding? get bestToday => _extreme(1);

  /// The holding that fell most today, by percent.
  PricedHolding? get worstToday => _extreme(-1);

  PricedHolding? _extreme(int direction) {
    PricedHolding? found;
    for (final holding in holdings) {
      final percent = holding.dayPercent;
      if (percent == null) {
        continue;
      }
      if (found == null ||
          percent * direction > found.dayPercent! * direction) {
        found = holding;
      }
    }
    return found;
  }

  /// The value grouped by [labelOf].
  List<AllocationSlice> allocation(
    String Function(PricedHolding holding) labelOf, {
    int maxSlices = 7,
    String otherLabel = 'Other',
  }) =>
      allocate(
        [for (final holding in holdings) (labelOf(holding), holding.value)],
        maxSlices: maxSlices,
        otherLabel: otherLabel,
      );
}

double? _portfolioXirr(List<PricedHolding> holdings, DateTime now) {
  final flows = <(DateTime, double)>[];
  var dated = 0.0;
  var total = 0.0;
  var value = 0.0;
  for (final holding in holdings) {
    final invested = holding.invested;
    total += invested;
    final bought = holding.holding.boughtOn;
    if (bought == null || invested <= 0 || bought.isAfter(now)) {
      continue;
    }
    dated += invested;
    value += holding.value;
    flows.add((bought, -invested));
  }
  // Annualising a few undated positions away would be a made-up number.
  if (flows.isEmpty || total <= 0 || dated < total * 0.7) {
    return null;
  }
  final earliest = flows.map((flow) => flow.$1).reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
  if (now.difference(earliest).inDays < 30) {
    return null;
  }
  flows.add((now, value));
  final rate = xirr(flows);
  return rate == null ? null : rate * 100;
}

/// The annual rate that makes [flows] — dated cash, out negative and in
/// positive — worth nothing today. Null when no such rate exists.
double? xirr(List<(DateTime, double)> flows) {
  if (flows.length < 2 ||
      !flows.any((flow) => flow.$2 < 0) ||
      !flows.any((flow) => flow.$2 > 0)) {
    return null;
  }
  final start = flows.map((flow) => flow.$1).reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
  final years = [
    for (final flow in flows) flow.$1.difference(start).inHours / 24 / 365.0,
  ];

  double worth(double rate) {
    var sum = 0.0;
    for (var index = 0; index < flows.length; index++) {
      sum += flows[index].$2 / math.pow(1 + rate, years[index]);
    }
    return sum;
  }

  // Bisection is slower than Newton but cannot wander off; worth falls as
  // the rate rises whenever money goes in before it comes out.
  var low = -0.9999;
  var high = 10.0;
  var lowWorth = worth(low);
  final highWorth = worth(high);
  if (lowWorth.isNaN || highWorth.isNaN || lowWorth * highWorth > 0) {
    return null;
  }
  for (var step = 0; step < 200; step++) {
    final middle = (low + high) / 2;
    final middleWorth = worth(middle);
    if (middleWorth.abs() < 1e-7 || (high - low) < 1e-9) {
      return middle;
    }
    if (middleWorth * lowWorth > 0) {
      low = middle;
      lowWorth = middleWorth;
    } else {
      high = middle;
    }
  }
  return (low + high) / 2;
}
