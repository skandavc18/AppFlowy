import 'dart:math' as math;

import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:flutter/foundation.dart';

/// One dated value.
@immutable
class SeriesPoint {
  const SeriesPoint(this.time, this.value);

  final DateTime time;
  final double value;
}

/// The worst fall from a high to a later low.
@immutable
class Drawdown {
  const Drawdown({this.percent = 0, this.amount = 0, this.peak, this.trough});

  /// How far it fell, as a positive percentage of the high.
  final double percent;

  /// How far it fell, as a positive amount.
  final double amount;
  final DateTime? peak;
  final DateTime? trough;
}

/// Dated values in time order: a capital curve, a net-worth history.
@immutable
class TimeSeries {
  TimeSeries(Iterable<SeriesPoint> points)
      : points = List.unmodifiable(
          points.where((point) => point.value.isFinite).toList()
            ..sort((a, b) => a.time.compareTo(b.time)),
        );

  static final empty = TimeSeries(const []);

  final List<SeriesPoint> points;

  bool get isEmpty => points.isEmpty;
  int get length => points.length;

  SeriesPoint? get first => points.isEmpty ? null : points.first;
  SeriesPoint? get last => points.isEmpty ? null : points.last;

  double? get change =>
      points.length < 2 ? null : points.last.value - points.first.value;

  double? get changePercent {
    final first = this.first?.value;
    final change = this.change;
    if (first == null || change == null || first == 0) {
      return null;
    }
    return change / first.abs() * 100;
  }

  /// The points from [start] on.
  TimeSeries since(DateTime start) =>
      TimeSeries(points.where((point) => !point.time.isBefore(start)));

  /// The annual growth rate that turns the first value into the last, in
  /// percent. Null for less than a month of history, where annualising
  /// a lucky week would promise the moon.
  double? get cagr {
    if (points.length < 2) {
      return null;
    }
    final start = points.first;
    final end = points.last;
    final days = end.time.difference(start.time).inHours / 24;
    if (days < 28 || start.value <= 0 || end.value <= 0) {
      return null;
    }
    return (math.pow(end.value / start.value, 365 / days) - 1) * 100;
  }

  Drawdown get maxDrawdown {
    if (points.length < 2) {
      return const Drawdown();
    }
    var peak = points.first;
    var worst = const Drawdown();
    for (final point in points) {
      if (point.value > peak.value) {
        peak = point;
        continue;
      }
      final amount = peak.value - point.value;
      final percent = peak.value > 0 ? amount / peak.value * 100 : 0.0;
      if (amount > worst.amount) {
        worst = Drawdown(
          percent: percent,
          amount: amount,
          peak: peak.time,
          trough: point.time,
        );
      }
    }
    return worst;
  }

  /// Values summed per calendar day, for a ledger that logs several trades a
  /// day. The day keeps local midnight.
  TimeSeries perDay() {
    final days = <DateTime, double>{};
    for (final point in points) {
      final day = DateTime(point.time.year, point.time.month, point.time.day);
      days[day] = (days[day] ?? 0) + point.value;
    }
    return TimeSeries([
      for (final entry in days.entries) SeriesPoint(entry.key, entry.value),
    ]);
  }

  /// A running total, turning daily profits into a curve.
  TimeSeries cumulative({double start = 0}) {
    var total = start;
    return TimeSeries([
      for (final point in points) SeriesPoint(point.time, total += point.value),
    ]);
  }
}

/// How a value grew once the money put into it is taken out: a portfolio
/// against what was invested, an account against its deposits.
///
/// Money paid in is not growth. Each step's return is what the value gained
/// beyond that step's new money, over what was at work — the new money
/// counted for half the step (modified Dietz). Steps chain into a
/// time-weighted return, which a top-up can neither flatter nor dent.
@immutable
class ContributedReturn {
  const ContributedReturn._({
    required this.gain,
    required this.contributed,
    required this.percent,
    required this.annualized,
    required this.drawdown,
  });

  /// [value] measured against the running total in [paidIn], matched by
  /// date; dates [paidIn] does not reach take its latest earlier total.
  /// Null when the two never overlap.
  ///
  /// [fromInception] counts from the money first put in rather than from the
  /// first value, so a whole history reads the same as the cards beside it:
  /// an account's capital less its deposits, a portfolio's value less what
  /// went into it.
  static ContributedReturn? of(
    TimeSeries value,
    TimeSeries paidIn, {
    bool fromInception = false,
  }) {
    if (value.length < 2 || paidIn.isEmpty) {
      return null;
    }
    double? paidAt(DateTime time) {
      double? latest;
      for (final point in paidIn.points) {
        if (point.time.isAfter(time)) {
          break;
        }
        latest = point.value;
      }
      return latest;
    }

    final steps = <(DateTime, double, double)>[
      for (final point in value.points)
        if (paidAt(point.time) case final paid?) (point.time, point.value, paid),
    ];
    if (steps.length < 2) {
      return null;
    }
    final (start, firstValue, firstPaid) = steps.first;
    var growth = 1.0;
    var peak = 1.0;
    var worst = const Drawdown();
    void track(DateTime time) {
      if (growth > peak) {
        peak = growth;
      } else if (peak > 0) {
        final percent = (peak - growth) / peak * 100;
        if (percent > worst.percent) {
          worst = Drawdown(percent: percent, trough: time);
        }
      }
    }

    if (fromInception && firstPaid > 0) {
      growth = firstValue / firstPaid;
      track(start);
    }
    for (var index = 1; index < steps.length; index++) {
      final (_, before, paidBefore) = steps[index - 1];
      final (time, after, paidAfter) = steps[index];
      final flow = paidAfter - paidBefore;
      final atWork = before + flow / 2;
      if (atWork > 0) {
        growth *= 1 + (after - before - flow) / atWork;
      }
      track(time);
    }
    final (end, lastValue, lastPaid) = steps.last;
    final contributed = fromInception ? lastPaid : lastPaid - firstPaid;
    final days = end.difference(start).inHours / 24;
    return ContributedReturn._(
      gain: fromInception
          ? lastValue - lastPaid
          : lastValue - firstValue - contributed,
      contributed: contributed,
      percent: (growth - 1) * 100,
      // A year is the shortest span worth annualising: a good quarter
      // compounded to a year promises what nobody earned.
      annualized: days >= 365 && growth > 0
          ? (math.pow(growth, 365 / days) - 1) * 100
          : null,
      drawdown: worst,
    );
  }

  /// What the value gained beyond the money put in.
  final double gain;

  /// The money put in over the span.
  final double contributed;

  /// The time-weighted return over the span, in percent.
  final double percent;

  /// [percent] as a yearly rate, once the span reaches a year.
  final double? annualized;

  /// The deepest fall of the growth itself, which a deposit cannot hide.
  final Drawdown drawdown;
}

/// Columns a series is read from.
class SeriesRoles {
  static const date = FinanceRole.date;
  static const value = FinanceRole('valueColumn', [
    'net worth',
    'capital',
    'equity',
    'portfolio value',
    'value',
    'balance',
    'total',
    'nav',
    'close',
  ]);
  static const baseline = FinanceRole('baselineColumn', [
    'invested',
    'deposits',
    'deposited',
    'contributions',
    'principal',
    'cost',
    'benchmark',
  ]);
  static const pnl = FinanceRole('pnlColumn', [
    'p&l',
    'pnl',
    'p/l',
    'profit',
    'net p&l',
    'realized',
    'realised',
    'result',
    'gain',
  ]);
}

/// A dated column read as a series. Rows without a date or a number are
/// left out; [valueRole] falls back to the first other numeric column.
TimeSeries readSeries(
  ChartTable table, {
  FinanceRole valueRole = SeriesRoles.value,
  Map<String, Object?> settings = const {},
  bool fallbackToNumeric = true,
}) {
  final columns = FinanceColumns.resolve(
    table,
    [SeriesRoles.date, valueRole],
    settings: settings,
  );
  final dateColumn = columns[SeriesRoles.date];
  var valueColumn = columns[valueRole];
  if (dateColumn < 0) {
    return TimeSeries.empty;
  }
  final sheet = FinanceSheet(table);
  if (valueColumn < 0 && fallbackToNumeric) {
    valueColumn = _firstNumericColumn(sheet, exclude: {dateColumn});
  }
  if (valueColumn < 0) {
    return TimeSeries.empty;
  }
  return _read(sheet, dateColumn, valueColumn);
}

/// The column holding [role], read against the date column, or an empty
/// series when the table has no such column.
TimeSeries readCompanionSeries(
  ChartTable table,
  FinanceRole role, {
  Map<String, Object?> settings = const {},
  FinanceRole valueRole = SeriesRoles.value,
}) {
  final columns = FinanceColumns.resolve(
    table,
    [SeriesRoles.date, valueRole, role],
    settings: settings,
  );
  final dateColumn = columns[SeriesRoles.date];
  final column = columns[role];
  if (dateColumn < 0 || column < 0) {
    return TimeSeries.empty;
  }
  return _read(FinanceSheet(table), dateColumn, column);
}

TimeSeries _read(FinanceSheet sheet, int dateColumn, int valueColumn) {
  final points = <SeriesPoint>[];
  for (var row = 0; row < sheet.length; row++) {
    final date = sheet.date(row, dateColumn);
    final value = sheet.number(row, valueColumn);
    if (date != null && value != null) {
      points.add(SeriesPoint(date, value));
    }
  }
  return TimeSeries(points);
}

int _firstNumericColumn(FinanceSheet sheet, {Set<int> exclude = const {}}) {
  for (var column = 0; column < sheet.table.columns.length; column++) {
    if (exclude.contains(column)) {
      continue;
    }
    var seen = 0;
    var numbers = 0;
    for (var row = 0; row < sheet.length && seen < 40; row++) {
      final text = sheet.text(row, column);
      if (text.isEmpty) {
        continue;
      }
      seen++;
      if (sheet.number(row, column) != null) {
        numbers++;
      }
    }
    if (seen > 0 && numbers * 2 > seen) {
      return column;
    }
  }
  return -1;
}

/// How a run of daily profits and losses went.
@immutable
class PnlStats {
  const PnlStats._({
    required this.days,
    required this.wins,
    required this.losses,
    required this.total,
    required this.grossProfit,
    required this.grossLoss,
    required this.best,
    required this.worst,
    required this.streak,
    required this.longestWinStreak,
    required this.longestLossStreak,
    required this.drawdown,
  });

  factory PnlStats.of(TimeSeries daily) {
    var wins = 0;
    var losses = 0;
    var total = 0.0;
    var profit = 0.0;
    var loss = 0.0;
    double? best;
    double? worst;
    var streak = 0;
    var longestWin = 0;
    var longestLoss = 0;
    for (final point in daily.points) {
      final value = point.value;
      total += value;
      best = best == null ? value : math.max(best, value);
      worst = worst == null ? value : math.min(worst, value);
      if (value > 0) {
        wins++;
        profit += value;
        streak = streak > 0 ? streak + 1 : 1;
        longestWin = math.max(longestWin, streak);
      } else if (value < 0) {
        losses++;
        loss += -value;
        streak = streak < 0 ? streak - 1 : -1;
        longestLoss = math.max(longestLoss, -streak);
      }
    }
    return PnlStats._(
      days: daily.length,
      wins: wins,
      losses: losses,
      total: total,
      grossProfit: profit,
      grossLoss: loss,
      best: best ?? 0,
      worst: worst ?? 0,
      streak: streak,
      longestWinStreak: longestWin,
      longestLossStreak: longestLoss,
      drawdown: daily.cumulative().maxDrawdown,
    );
  }

  final int days;
  final int wins;
  final int losses;
  final double total;
  final double grossProfit;
  final double grossLoss;
  final double best;
  final double worst;

  /// The current run: positive for winning days, negative for losing ones.
  final int streak;
  final int longestWinStreak;
  final int longestLossStreak;

  /// The deepest fall of the running total.
  final Drawdown drawdown;

  bool get isEmpty => days == 0;

  double? get winRate =>
      wins + losses == 0 ? null : wins / (wins + losses) * 100;

  /// Gross profit for every rupee lost; null when nothing was lost yet.
  double? get profitFactor => grossLoss == 0 ? null : grossProfit / grossLoss;

  double get averageWin => wins == 0 ? 0 : grossProfit / wins;

  double get averageLoss => losses == 0 ? 0 : grossLoss / losses;

  /// What an average day is worth.
  double get expectancy => days == 0 ? 0 : total / days;
}
