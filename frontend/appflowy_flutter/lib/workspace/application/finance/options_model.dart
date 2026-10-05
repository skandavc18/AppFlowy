import 'dart:math' as math;

import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:flutter/foundation.dart';

enum OptionSide { buy, sell }

enum LegKind { call, put, future }

/// One leg of a position, as a trade journal row describes it.
@immutable
class OptionLeg {
  const OptionLeg({
    required this.kind,
    required this.side,
    required this.quantity,
    required this.entry,
    this.strategy = '',
    this.underlying = '',
    this.strike,
    this.lastPrice,
    this.exit,
    this.expiry,
    this.isOpen = true,
    this.margin,
    this.opened,
    this.notes = '',
    this.rowId,
  });

  final String strategy;

  /// The underlying as the exchange names it: NIFTY, BANKNIFTY, RELIANCE.
  final String underlying;
  final LegKind kind;
  final OptionSide side;

  /// Null for a future.
  final double? strike;

  /// Units, which is lots times the lot size.
  final double quantity;

  /// The premium paid or received per unit, or a future's entry price.
  final double entry;

  /// The last price the table holds; a live price replaces it.
  final double? lastPrice;
  final double? exit;

  /// The calendar day of expiry.
  final DateTime? expiry;
  final bool isOpen;
  final double? margin;
  final DateTime? opened;
  final String notes;
  final String? rowId;

  double get sign => side == OptionSide.buy ? 1 : -1;

  bool get isOption => kind != LegKind.future;

  /// Where a leg's payoff bends. A future's entry plays no such part.
  double get pivot => strike ?? entry;

  double intrinsic(double spot) => switch (kind) {
        LegKind.call => math.max(spot - strike!, 0),
        LegKind.put => math.max(strike! - spot, 0),
        LegKind.future => spot,
      };

  /// What the leg is worth at expiry with the underlying at [spot]. A closed
  /// leg is simply what it booked.
  double payoffAt(double spot) {
    if (!isOpen) {
      return realized;
    }
    return sign * quantity * (intrinsic(spot) - entry);
  }

  /// What a closed leg made or lost.
  double get realized {
    final exit = this.exit;
    if (isOpen || exit == null) {
      return 0;
    }
    return sign * quantity * (exit - entry);
  }

  /// The leg's profit at [price], or at the table's last price.
  double? markToMarket([double? price]) {
    if (!isOpen) {
      return realized;
    }
    final mark = price ?? lastPrice;
    return mark == null ? null : sign * quantity * (mark - entry);
  }

  /// Premium received (positive) or paid (negative) on opening.
  double get premium => isOption ? -sign * quantity * entry : 0;
}

/// The columns a leg is read from.
class OptionRoles {
  static const strategy = FinanceRole('strategyColumn', [
    'strategy',
    'position',
    'trade',
    'setup',
  ]);
  static const underlying = FinanceRole('underlyingColumn', [
    'underlying',
    'symbol',
    'index',
    'instrument',
    'scrip',
  ]);
  static const kind = FinanceRole('kindColumn', [
    'type',
    'option type',
    'ce/pe',
    'kind',
    'right',
  ]);
  static const side = FinanceRole('sideColumn', [
    'side',
    'action',
    'buy/sell',
    'b/s',
    'direction',
  ]);
  static const strike = FinanceRole('strikeColumn', ['strike', 'strike price']);
  static const quantity = FinanceRole.quantity;
  static const entry = FinanceRole('entryColumn', [
    'entry',
    'entry price',
    'avg price',
    'avg',
    'premium',
    'open price',
  ]);
  static const exit = FinanceRole('exitColumn', [
    'exit',
    'exit price',
    'close price',
    'closed at',
  ]);
  static const lastPrice = FinanceRole.lastPrice;
  static const expiry = FinanceRole('expiryColumn', [
    'expiry',
    'expiration',
    'expiry date',
    'exp',
  ]);
  static const status = FinanceRole('statusColumn', [
    'status',
    'state',
    'open/closed',
  ]);
  static const margin = FinanceRole('marginColumn', [
    'margin',
    'margin used',
    'capital used',
    'blocked',
  ]);
  static const opened = FinanceRole('openedColumn', [
    'opened',
    'entry date',
    'trade date',
    'date',
  ]);

  static const all = [
    strategy,
    underlying,
    kind,
    side,
    strike,
    quantity,
    entry,
    exit,
    lastPrice,
    expiry,
    status,
    margin,
    opened,
    FinanceRole.notes,
  ];
}

LegKind? parseLegKind(String text) {
  final value = text.trim().toLowerCase();
  if (value.isEmpty) {
    return null;
  }
  if (value == 'ce' || value == 'c' || value.startsWith('call')) {
    return LegKind.call;
  }
  if (value == 'pe' || value == 'p' || value.startsWith('put')) {
    return LegKind.put;
  }
  if (value == 'f' || value.startsWith('fut')) {
    return LegKind.future;
  }
  return null;
}

OptionSide? parseOptionSide(String text) {
  final value = text.trim().toLowerCase();
  const buys = {'buy', 'b', 'long', 'bought', '+', 'bot'};
  const sells = {'sell', 's', 'short', 'sold', 'write', 'written', '-', 'sld'};
  if (buys.contains(value)) {
    return OptionSide.buy;
  }
  if (sells.contains(value)) {
    return OptionSide.sell;
  }
  return null;
}

bool _closedStatus(String text) {
  final value = text.trim().toLowerCase();
  return const {
    'closed',
    'close',
    'exited',
    'exit',
    'squared off',
    'settled',
    'expired',
    'done',
  }.contains(value);
}

/// Reads every complete leg a journal lists.
List<OptionLeg> readOptionLegs(
  ChartTable table, {
  Map<String, Object?> settings = const {},
}) {
  final columns = FinanceColumns.resolve(
    table,
    OptionRoles.all,
    settings: settings,
  );
  final sheet = FinanceSheet(table);
  final legs = <OptionLeg>[];
  for (var row = 0; row < sheet.length; row++) {
    final kind = parseLegKind(sheet.text(row, columns[OptionRoles.kind]));
    final entry = sheet.number(row, columns[OptionRoles.entry]);
    var quantity = sheet.number(row, columns[OptionRoles.quantity]);
    final strike = sheet.number(row, columns[OptionRoles.strike]);
    if (kind == null ||
        entry == null ||
        quantity == null ||
        quantity == 0 ||
        (kind != LegKind.future && strike == null)) {
      continue;
    }
    final side = parseOptionSide(sheet.text(row, columns[OptionRoles.side])) ??
        (quantity < 0 ? OptionSide.sell : OptionSide.buy);
    quantity = quantity.abs();
    final exit = sheet.number(row, columns[OptionRoles.exit]);
    final statusText = sheet.text(row, columns[OptionRoles.status]);
    final closed =
        statusText.isEmpty ? exit != null : _closedStatus(statusText);
    legs.add(
      OptionLeg(
        strategy: sheet.text(row, columns[OptionRoles.strategy]),
        underlying:
            sheet.text(row, columns[OptionRoles.underlying]).toUpperCase(),
        kind: kind,
        side: side,
        strike: kind == LegKind.future ? null : strike,
        quantity: quantity,
        entry: entry,
        lastPrice: sheet.number(row, columns[OptionRoles.lastPrice]),
        exit: exit,
        expiry: sheet.date(row, columns[OptionRoles.expiry]),
        isOpen: !closed,
        margin: sheet.number(row, columns[OptionRoles.margin]),
        opened: sheet.date(row, columns[OptionRoles.opened]),
        notes: sheet.text(row, columns[FinanceRole.notes]),
        rowId: sheet.rowId(row),
      ),
    );
  }
  return legs;
}

/// Prices a leg right now, or null when nothing is known.
typedef LegPricer = double? Function(OptionLeg leg);

/// The legs traded together under one name.
@immutable
class OptionStrategy {
  const OptionStrategy({
    required this.name,
    required this.underlying,
    required this.legs,
  });

  final String name;
  final String underlying;
  final List<OptionLeg> legs;

  bool get isOpen => legs.any((leg) => leg.isOpen);

  Iterable<OptionLeg> get openLegs => legs.where((leg) => leg.isOpen);

  /// The first open expiry, or the last one for a finished strategy.
  DateTime? get expiry {
    final open = [
      for (final leg in openLegs)
        if (leg.expiry != null) leg.expiry!,
    ]..sort();
    if (open.isNotEmpty) {
      return open.first;
    }
    final all = [
      for (final leg in legs)
        if (leg.expiry != null) leg.expiry!,
    ]..sort();
    return all.isEmpty ? null : all.last;
  }

  DateTime? get opened {
    final dates = [
      for (final leg in legs)
        if (leg.opened != null) leg.opened!,
    ]..sort();
    return dates.isEmpty ? null : dates.first;
  }

  double get realized =>
      legs.fold(0, (sum, leg) => sum + (leg.isOpen ? 0 : leg.realized));

  /// Premium collected (positive) or paid (negative) by the open legs.
  double get netPremium => openLegs.fold(0, (sum, leg) => sum + leg.premium);

  double get margin => legs.fold(
        0,
        (sum, leg) => sum + (leg.isOpen ? (leg.margin ?? 0) : 0),
      );

  /// Profit now: open legs at [priceOf] (or their table price) plus what the
  /// closed legs booked. Null when an open leg has no price at all.
  double? markToMarket([LegPricer? priceOf]) {
    var total = 0.0;
    for (final leg in legs) {
      final mark = leg.markToMarket(leg.isOpen ? priceOf?.call(leg) : null);
      if (mark == null) {
        return null;
      }
      total += mark;
    }
    return total;
  }

  /// Profit at expiry with the underlying at [spot].
  double payoffAt(double spot) =>
      legs.fold(0, (sum, leg) => sum + leg.payoffAt(spot));

  List<double> get strikes => {
        for (final leg in openLegs) leg.pivot,
      }.toList()
        ..sort();

  PayoffBounds get bounds => PayoffBounds.of(this);
}

/// Every strategy in a journal, open ones first.
List<OptionStrategy> groupStrategies(List<OptionLeg> legs) {
  final groups = <String, List<OptionLeg>>{};
  final names = <String, String>{};
  for (final leg in legs) {
    final named = leg.strategy.trim();
    final key = named.isNotEmpty
        ? named.toLowerCase()
        : '${leg.underlying}|${leg.expiry?.toIso8601String() ?? ''}';
    groups.putIfAbsent(key, () => []).add(leg);
    names.putIfAbsent(
      key,
      () => named.isNotEmpty ? named : leg.underlying,
    );
  }
  final strategies = [
    for (final entry in groups.entries)
      OptionStrategy(
        name: names[entry.key]!,
        underlying: entry.value
            .map((leg) => leg.underlying)
            .firstWhere((name) => name.isNotEmpty, orElse: () => ''),
        legs: List.unmodifiable(entry.value),
      ),
  ];
  strategies.sort((a, b) {
    if (a.isOpen != b.isOpen) {
      return a.isOpen ? -1 : 1;
    }
    final first = a.expiry;
    final second = b.expiry;
    if (first == null || second == null) {
      return first == null ? (second == null ? 0 : 1) : -1;
    }
    return a.isOpen ? first.compareTo(second) : second.compareTo(first);
  });
  return strategies;
}

/// The best and worst a strategy can do at expiry.
///
/// A payoff is straight between strikes, so the extremes can only sit at
/// zero, at a strike, or off towards infinity — which is read from the slope
/// the calls and futures leave beyond the last strike.
@immutable
class PayoffBounds {
  const PayoffBounds({
    required this.maxProfit,
    required this.maxLoss,
    required this.unlimitedProfit,
    required this.unlimitedLoss,
    required this.breakevens,
  });

  factory PayoffBounds.of(OptionStrategy strategy) {
    final points = <double>{0, ...strategy.strikes}.toList()..sort();
    var slope = 0.0;
    for (final leg in strategy.openLegs) {
      if (leg.kind != LegKind.put) {
        slope += leg.sign * leg.quantity;
      }
    }
    var best = double.negativeInfinity;
    var worst = double.infinity;
    for (final point in points) {
      final value = strategy.payoffAt(point);
      best = math.max(best, value);
      worst = math.min(worst, value);
    }
    final last = points.last;
    final beyond = strategy.payoffAt(last + math.max(1, last));
    if (slope.abs() < 1e-9) {
      best = math.max(best, beyond);
      worst = math.min(worst, beyond);
    }
    return PayoffBounds(
      maxProfit: best,
      maxLoss: worst,
      unlimitedProfit: slope > 1e-9,
      unlimitedLoss: slope < -1e-9,
      breakevens: _breakevens(strategy, points, slope),
    );
  }

  final double maxProfit;
  final double maxLoss;
  final bool unlimitedProfit;
  final bool unlimitedLoss;
  final List<double> breakevens;

  /// Reward for every rupee risked, when both sides are bounded.
  double? get rewardToRisk {
    if (unlimitedProfit || unlimitedLoss || maxLoss >= 0) {
      return null;
    }
    return maxProfit / -maxLoss;
  }
}

List<double> _breakevens(
  OptionStrategy strategy,
  List<double> points,
  double slope,
) {
  // Each straight piece crosses zero at most once.
  final found = <double>[];
  final ends = [...points];
  if (slope.abs() > 1e-9) {
    final last = points.last;
    final value = strategy.payoffAt(last);
    final root = last - value / slope;
    if (root > last) {
      ends.add(root + 1);
    }
  }
  for (var index = 0; index < ends.length - 1; index++) {
    final a = ends[index];
    final b = ends[index + 1];
    final fa = strategy.payoffAt(a);
    final fb = strategy.payoffAt(b);
    if (fa == 0 && index > 0) {
      found.add(a);
      continue;
    }
    if (fa * fb < 0) {
      found.add(a + (b - a) * (fa / (fa - fb)));
    }
  }
  return found;
}

// ------------------------------------------------------------- the pricing

/// India's risk-free rate, near enough for a theoretical curve.
const optionRiskFreeRate = 0.065;

/// A volatility assumed when nothing better is known.
const optionDefaultVolatility = 0.15;

/// When a contract expiring on [day] stops trading: 15:30 in India.
DateTime optionExpiryInstant(DateTime day) {
  if (day.hour != 0 || day.minute != 0) {
    return day.toUtc();
  }
  return DateTime.utc(day.year, day.month, day.day, 10);
}

/// The years left until [expiry], never negative.
double optionYearsLeft(DateTime expiry, {DateTime? now}) {
  final left = optionExpiryInstant(expiry)
      .difference((now ?? DateTime.now()).toUtc())
      .inSeconds;
  return math.max(0, left) / (365 * 24 * 3600);
}

@immutable
class Greeks {
  const Greeks({
    this.delta = 0,
    this.gamma = 0,
    this.theta = 0,
    this.vega = 0,
  });

  static const zero = Greeks();

  /// Change in value per point of the underlying.
  final double delta;
  final double gamma;

  /// Change in value per calendar day.
  final double theta;

  /// Change in value per percentage point of volatility.
  final double vega;

  Greeks operator +(Greeks other) => Greeks(
        delta: delta + other.delta,
        gamma: gamma + other.gamma,
        theta: theta + other.theta,
        vega: vega + other.vega,
      );

  Greeks scale(double factor) => Greeks(
        delta: delta * factor,
        gamma: gamma * factor,
        theta: theta * factor,
        vega: vega * factor,
      );
}

/// The standard normal distribution.
double normalCdf(double x) {
  // Abramowitz and Stegun 26.2.17, accurate to 7.5e-8.
  if (x.isNaN) {
    return double.nan;
  }
  if (x < -10) {
    return 0;
  }
  if (x > 10) {
    return 1;
  }
  final t = 1 / (1 + 0.2316419 * x.abs());
  final poly = t *
      (0.319381530 +
          t *
              (-0.356563782 +
                  t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  final tail = normalPdf(x) * poly;
  return x >= 0 ? 1 - tail : tail;
}

double normalPdf(double x) => math.exp(-x * x / 2) / math.sqrt(2 * math.pi);

/// Black–Scholes for a European option, which index options in India are.
class BlackScholes {
  const BlackScholes._();

  static double price({
    required bool call,
    required double spot,
    required double strike,
    required double years,
    required double volatility,
    double rate = optionRiskFreeRate,
  }) {
    if (years <= 0 || volatility <= 0 || spot <= 0 || strike <= 0) {
      return call ? math.max(spot - strike, 0) : math.max(strike - spot, 0);
    }
    final root = math.sqrt(years);
    final d1 = (math.log(spot / strike) +
            (rate + volatility * volatility / 2) * years) /
        (volatility * root);
    final d2 = d1 - volatility * root;
    final discount = strike * math.exp(-rate * years);
    return call
        ? spot * normalCdf(d1) - discount * normalCdf(d2)
        : discount * normalCdf(-d2) - spot * normalCdf(-d1);
  }

  static Greeks greeks({
    required bool call,
    required double spot,
    required double strike,
    required double years,
    required double volatility,
    double rate = optionRiskFreeRate,
  }) {
    if (years <= 0 || volatility <= 0 || spot <= 0 || strike <= 0) {
      final inTheMoney = call ? spot > strike : spot < strike;
      return Greeks(delta: inTheMoney ? (call ? 1 : -1) : 0);
    }
    final root = math.sqrt(years);
    final d1 = (math.log(spot / strike) +
            (rate + volatility * volatility / 2) * years) /
        (volatility * root);
    final d2 = d1 - volatility * root;
    final density = normalPdf(d1);
    final discount = strike * math.exp(-rate * years);
    final decay = -spot * density * volatility / (2 * root);
    final theta = call
        ? decay - rate * discount * normalCdf(d2)
        : decay + rate * discount * normalCdf(-d2);
    return Greeks(
      delta: call ? normalCdf(d1) : normalCdf(d1) - 1,
      gamma: density / (spot * volatility * root),
      theta: theta / 365,
      vega: spot * density * root / 100,
    );
  }

  /// The volatility at which the model prices an option at [price], or null
  /// when no volatility could (a price below intrinsic value, say).
  static double? impliedVolatility({
    required bool call,
    required double spot,
    required double strike,
    required double years,
    required double price,
    double rate = optionRiskFreeRate,
  }) {
    if (years <= 0 || price <= 0 || spot <= 0 || strike <= 0) {
      return null;
    }
    var low = 0.005;
    var high = 5.0;
    double at(double volatility) => BlackScholes.price(
          call: call,
          spot: spot,
          strike: strike,
          years: years,
          volatility: volatility,
          rate: rate,
        );
    if (price < at(low) || price > at(high)) {
      return null;
    }
    for (var step = 0; step < 80; step++) {
      final middle = (low + high) / 2;
      if (at(middle) > price) {
        high = middle;
      } else {
        low = middle;
      }
      if (high - low < 1e-6) {
        break;
      }
    }
    return (low + high) / 2;
  }
}

/// A strategy read against the market: what it is worth now, what it would
/// be worth today at other prices, its Greeks, and its chance of profit.
class StrategyAnalysis {
  StrategyAnalysis(
    this.strategy, {
    this.spot,
    LegPricer? priceOf,
    double? Function(OptionLeg leg)? volatilityOf,
    DateTime? now,
  })  : _now = now ?? DateTime.now(),
        _priceOf = priceOf,
        _volatilityOf = volatilityOf {
    _volatilities = {
      for (final leg in strategy.openLegs)
        if (leg.isOption) leg: _volatilityFor(leg),
    };
  }

  final OptionStrategy strategy;
  final double? spot;
  final DateTime _now;
  final LegPricer? _priceOf;
  final double? Function(OptionLeg leg)? _volatilityOf;
  late final Map<OptionLeg, double> _volatilities;

  late final PayoffBounds bounds = strategy.bounds;

  /// Profit now, at live prices where known.
  late final double? markToMarket = strategy.markToMarket(_priceOf);

  double? priceOf(OptionLeg leg) => _priceOf?.call(leg) ?? leg.lastPrice;

  double _volatilityFor(OptionLeg leg) {
    final given = _volatilityOf?.call(leg);
    if (given != null && given > 0) {
      return given;
    }
    final spot = this.spot;
    final price = priceOf(leg);
    final expiry = leg.expiry;
    if (spot != null && price != null && expiry != null) {
      final implied = BlackScholes.impliedVolatility(
        call: leg.kind == LegKind.call,
        spot: spot,
        strike: leg.strike!,
        years: optionYearsLeft(expiry, now: _now),
        price: price,
      );
      if (implied != null) {
        return implied;
      }
    }
    return optionDefaultVolatility;
  }

  /// Whether a today curve can be drawn: there is a spot and time left.
  bool get hasTimeValue =>
      spot != null &&
      strategy.openLegs.any(
        (leg) =>
            leg.isOption &&
            leg.expiry != null &&
            optionYearsLeft(leg.expiry!, now: _now) > 0,
      );

  /// What the strategy would be worth today with the underlying at [price].
  double todayAt(double price) {
    var total = 0.0;
    for (final leg in strategy.legs) {
      if (!leg.isOpen) {
        total += leg.realized;
        continue;
      }
      if (!leg.isOption) {
        total += leg.sign * leg.quantity * (price - leg.entry);
        continue;
      }
      final expiry = leg.expiry;
      final value = expiry == null
          ? leg.intrinsic(price)
          : BlackScholes.price(
              call: leg.kind == LegKind.call,
              spot: price,
              strike: leg.strike!,
              years: optionYearsLeft(expiry, now: _now),
              volatility: _volatilities[leg] ?? optionDefaultVolatility,
            );
      total += leg.sign * leg.quantity * (value - leg.entry);
    }
    return total;
  }

  /// The position's Greeks at the current spot.
  Greeks? get greeks {
    final spot = this.spot;
    if (spot == null) {
      return null;
    }
    var total = Greeks.zero;
    for (final leg in strategy.openLegs) {
      if (!leg.isOption) {
        total = total + Greeks(delta: leg.sign * leg.quantity);
        continue;
      }
      final expiry = leg.expiry;
      if (expiry == null) {
        continue;
      }
      total = total +
          BlackScholes.greeks(
            call: leg.kind == LegKind.call,
            spot: spot,
            strike: leg.strike!,
            years: optionYearsLeft(expiry, now: _now),
            volatility: _volatilities[leg] ?? optionDefaultVolatility,
          ).scale(leg.sign * leg.quantity);
    }
    return total;
  }

  /// The average volatility of the open option legs.
  double get volatility {
    if (_volatilities.isEmpty) {
      return optionDefaultVolatility;
    }
    return _volatilities.values.reduce((a, b) => a + b) / _volatilities.length;
  }

  /// The chance, in percent, that the strategy ends in profit at its first
  /// expiry, with prices spread lognormally at [volatility].
  double? get probabilityOfProfit {
    final spot = this.spot;
    final expiry = strategy.expiry;
    if (spot == null || spot <= 0 || expiry == null || !strategy.isOpen) {
      return null;
    }
    final years = optionYearsLeft(expiry, now: _now);
    final sigma = volatility;
    if (years <= 0) {
      return strategy.payoffAt(spot) > 0 ? 100 : 0;
    }
    final spread = sigma * math.sqrt(years);
    final drift = (optionRiskFreeRate - sigma * sigma / 2) * years;
    double below(double price) =>
        price <= 0 ? 0 : normalCdf((math.log(price / spot) - drift) / spread);

    final edges = [0.0, ...bounds.breakevens, double.infinity];
    var chance = 0.0;
    for (var index = 0; index < edges.length - 1; index++) {
      final low = edges[index];
      final high = edges[index + 1];
      final probe =
          high.isInfinite ? math.max(low * 1.5, low + 1) : (low + high) / 2;
      if (strategy.payoffAt(probe) > 0) {
        chance += (high.isInfinite ? 1 : below(high)) - below(low);
      }
    }
    return (chance * 100).clamp(0, 100).toDouble();
  }

  /// A price range that shows the whole shape: every strike and the spot,
  /// with room either side for the wings.
  (double, double) get range {
    final strikes = strategy.strikes;
    final marks = [...strikes, if (spot != null) spot!];
    if (marks.isEmpty) {
      return (0, 1);
    }
    final low = marks.reduce(math.min);
    final high = marks.reduce(math.max);
    final centre = (low + high) / 2;
    final pad = math.max((high - low) * 0.6, centre * 0.035);
    return (math.max(0, low - pad), high + pad);
  }
}

/// Every strategy in a journal, added up.
@immutable
class OptionsBook {
  const OptionsBook._(this.legs, this.strategies);

  factory OptionsBook.of(List<OptionLeg> legs) =>
      OptionsBook._(legs, groupStrategies(legs));

  final List<OptionLeg> legs;
  final List<OptionStrategy> strategies;

  Iterable<OptionStrategy> get open =>
      strategies.where((strategy) => strategy.isOpen);

  Iterable<OptionStrategy> get closed =>
      strategies.where((strategy) => !strategy.isOpen);

  /// What every closed leg booked.
  double get realized =>
      legs.fold(0, (sum, leg) => sum + (leg.isOpen ? 0 : leg.realized));

  /// The open legs' profit at live prices where known. Legs with no price
  /// at all are left out rather than sinking the whole figure.
  double openMarkToMarket([LegPricer? priceOf]) {
    var total = 0.0;
    for (final leg in legs) {
      if (!leg.isOpen) {
        continue;
      }
      total += leg.markToMarket(priceOf?.call(leg)) ?? 0;
    }
    return total;
  }

  double get marginUsed => legs.fold(
        0,
        (sum, leg) => sum + (leg.isOpen ? (leg.margin ?? 0) : 0),
      );

  DateTime? get nextExpiry {
    final dates = [
      for (final leg in legs)
        if (leg.isOpen && leg.expiry != null) leg.expiry!,
    ]..sort();
    return dates.isEmpty ? null : dates.first;
  }

  /// The underlyings with open positions, each with the expiries they need.
  Map<String, Set<DateTime>> get openExpiries {
    final result = <String, Set<DateTime>>{};
    for (final leg in legs) {
      if (leg.isOpen && leg.underlying.isNotEmpty && leg.expiry != null) {
        result.putIfAbsent(leg.underlying, () => {}).add(
              DateTime(leg.expiry!.year, leg.expiry!.month, leg.expiry!.day),
            );
      }
    }
    return result;
  }
}
