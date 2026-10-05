import 'dart:math' as math;

import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/finance/balance_sheet.dart';
import 'package:appflowy/workspace/application/finance/capital_series.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:appflowy/workspace/application/finance/options_model.dart';
import 'package:appflowy/workspace/application/finance/portfolio_model.dart';
import 'package:appflowy/workspace/application/finance/quote_model.dart';
import 'package:flutter_test/flutter_test.dart';

ChartTable _table(List<List<String>> rows) => ChartTable.fromRows(
      rows,
      rowIds: [for (var index = 1; index < rows.length; index++) 'r$index'],
    );

void main() {
  group('money is read and written the way a person writes it', () {
    test('reads amounts in every form a cell shows them', () {
      expect(parseMoney('₹12,34,567'), 1234567);
      // Eight digits is one crore, not a date in the year 1000.
      expect(parseMoney('10000000'), 10000000);
      expect(parseMoney('(1,200)'), -1200);
      expect(parseMoney('${financeMinus}1,200.50'), -1200.5);
      expect(parseMoney('1.2 Cr'), closeTo(12000000, 1e-6));
      expect(parseMoney('45 L'), closeTo(4500000, 1e-6));
      expect(parseMoney('12k'), 12000);
      expect(parseMoney('8.5%'), 8.5);
      expect(parseMoney(r'$4,200'), 4200);
      expect(parseMoney('1.204,50'), closeTo(1204.5, 1e-9));
      expect(parseMoney(''), isNull);
      expect(parseMoney('RELIANCE'), isNull);
      expect(parseMoney(null), isNull);
    });

    test('writes rupees in lakh and crore, everything else in thousands', () {
      const rupee = MoneyStyle.rupee;
      expect(rupee.format(1234567), '₹12,34,567');
      expect(rupee.format(999), '₹999');
      expect(rupee.format(-1250), '$financeMinus₹1,250');
      expect(rupee.format(1250, signed: true), '+₹1,250');
      expect(rupee.format(48.5), '₹48.50');
      expect(rupee.price(1167.7), '₹1,167.70');
      expect(rupee.compact(12500000), '₹1.25 Cr');
      expect(rupee.compact(1240000), '₹12.4 L');
      expect(rupee.compact(45200), '₹45.2K');
      expect(MoneyStyle.forCurrency('USD').format(1234567), r'$1,234,567');
      expect(MoneyStyle.forCurrency('USD').compact(4200000), r'$4.2M');
      expect(MoneyStyle.forCurrency('none').format(1500), '1,500');
    });

    test('writes percentages, counts and quantities', () {
      expect(formatPercent(12.4), '+12.40%');
      expect(formatPercent(-3.256, decimals: 1), '${financeMinus}3.3%');
      expect(formatPercent(null), '—');
      expect(formatCount(1250000), '1.25M');
      expect(formatQuantity(65), '65');
      expect(formatQuantity(12.3456), '12.346');
      expect(formatLevel(22421.95, decimals: 2), '22,421.95');
    });
  });

  group('columns are found by what they are called', () {
    test('a role claims its column so a later one cannot take it', () {
      final table = _table([
        ['Name', 'Avg price', 'Price', 'Qty'],
        ['A', '10', '12', '3'],
      ]);
      final columns = FinanceColumns.resolve(table, [
        FinanceRole.averagePrice,
        FinanceRole.lastPrice,
        FinanceRole.quantity,
      ]);
      expect(columns[FinanceRole.averagePrice], 1);
      expect(columns[FinanceRole.lastPrice], 2);
      expect(columns[FinanceRole.quantity], 3);
    });

    test('a setting points a role at any column', () {
      final table = _table([
        ['Name', 'Units', 'Paid'],
        ['A', '3', '10'],
      ]);
      final columns = FinanceColumns.resolve(
        table,
        [FinanceRole.quantity],
        settings: const {'quantityColumn': 'Units'},
      );
      expect(columns[FinanceRole.quantity], 1);
    });

    test('row ids stay beside their rows when empty rows are dropped', () {
      final table = ChartTable.fromRows(
        [
          ['Name', 'Value'],
          ['A', '1'],
          ['', ''],
          ['B', '2'],
        ],
        rowIds: ['a', 'blank', 'b'],
      );
      expect(table.rows.length, 2);
      expect(table.rowIds, ['a', 'b']);
      expect(FinanceSheet(table).rowId(1), 'b');
    });
  });

  group('a portfolio', () {
    final table = _table([
      ['Name', 'Symbol', 'Sector', 'Qty', 'Avg price', 'LTP', 'Bought on'],
      ['Reliance', 'RELIANCE.NS', 'Energy', '10', '100', '120', '2025-01-01'],
      ['HDFC Bank', 'HDFCBANK.NS', 'Banking', '20', '50', '45', '2025-01-01'],
      ['Gold fund', '', 'Gold', '1', '', '', ''],
    ]);

    test('reads its holdings and values them at the best price known', () {
      final holdings = Holding.read(table);
      expect(holdings.length, 2);
      final priced = [
        PricedHolding(holdings[0], livePrice: 130, previousClose: 125),
        PricedHolding(holdings[1]),
      ];
      final snapshot = PortfolioSnapshot.of(priced, now: DateTime(2026));
      expect(snapshot.value, 10 * 130 + 20 * 45);
      expect(snapshot.invested, 10 * 100 + 20 * 50);
      expect(snapshot.pnl, 2200 - 2000);
      expect(snapshot.dayChange, 50);
      expect(snapshot.liveCount, 1);
      expect(snapshot.dayPercent, closeTo(50 / 1250 * 100, 1e-9));
      expect(snapshot.bestToday?.holding.symbol, 'RELIANCE.NS');
      expect(snapshot.holdings.first.holding.rowId, 'r1');
    });

    test('folds a long tail into one slice', () {
      final slices = allocate(
        [for (var i = 0; i < 10; i++) ('S$i', 10.0 - i)],
        maxSlices: 4,
      );
      expect(slices.length, 4);
      expect(slices.last.isOther, isTrue);
      expect(
        slices.fold<double>(0, (sum, s) => sum + s.share),
        closeTo(1, 1e-9),
      );
    });

    test('annualises a return from dated cash flows', () {
      final rate = xirr([
        (DateTime(2025), -100),
        (DateTime(2026), 110),
      ]);
      expect(rate, closeTo(0.1, 1e-4));
      expect(xirr([(DateTime(2025), 100)]), isNull);
    });
  });

  group('a series over time', () {
    final series = TimeSeries([
      SeriesPoint(DateTime(2025), 100),
      SeriesPoint(DateTime(2025, 4), 120),
      SeriesPoint(DateTime(2025, 7), 90),
      SeriesPoint(DateTime(2026), 121),
    ]);

    test('knows its change, growth rate and deepest fall', () {
      expect(series.change, 21);
      expect(series.changePercent, closeTo(21, 1e-9));
      expect(series.cagr, closeTo(21, 0.2));
      expect(series.maxDrawdown.percent, closeTo(25, 1e-9));
      expect(series.maxDrawdown.peak, DateTime(2025, 4));
      expect(
        TimeSeries([
          SeriesPoint(DateTime(2025), 100),
          SeriesPoint(DateTime(2025, 1, 5), 120),
        ]).cagr,
        isNull,
      );
    });

    test('adds up trading days', () {
      final daily = TimeSeries([
        SeriesPoint(DateTime(2026, 1, 1, 10), 100),
        SeriesPoint(DateTime(2026, 1, 1, 14), -40),
        SeriesPoint(DateTime(2026, 1, 2), -50),
        SeriesPoint(DateTime(2026, 1, 5), 80),
        SeriesPoint(DateTime(2026, 1, 6), 20),
      ]).perDay();
      expect(daily.length, 4);
      final stats = PnlStats.of(daily);
      expect(stats.total, 110);
      expect(stats.wins, 3);
      expect(stats.losses, 1);
      expect(stats.winRate, 75);
      expect(stats.profitFactor, closeTo(160 / 50, 1e-9));
      expect(stats.streak, 2);
      expect(stats.drawdown.amount, 50);
    });

    test('reads a journal by its column names', () {
      final journal = _table([
        ['Note', 'Date', 'P&L', 'Capital', 'Deposits'],
        ['a', '2026-01-01', '100', '1100', '1000'],
        ['b', '2026-01-02', '-50', '1050', '1000'],
      ]);
      expect(readSeries(journal).last?.value, 1050);
      expect(
        readSeries(journal, valueRole: SeriesRoles.pnl)
            .points
            .map((p) => p.value),
        [100, -50],
      );
      expect(
        readCompanionSeries(journal, SeriesRoles.baseline).last?.value,
        1000,
      );
    });
  });

  group('growth net of money put in', () {
    TimeSeries series(List<(DateTime, double)> points) => TimeSeries([
          for (final (time, value) in points) SeriesPoint(time, value),
        ]);

    test('a deposit is not growth', () {
      final value = series([
        (DateTime(2026), 1000),
        (DateTime(2026, 2), 1000),
        (DateTime(2026, 3), 1100),
      ]);
      final paidIn = series([
        (DateTime(2026), 1000),
        (DateTime(2026, 3), 1100),
      ]);
      final result = ContributedReturn.of(value, paidIn)!;
      expect(result.gain, 0);
      expect(result.contributed, 100);
      expect(result.percent, closeTo(0, 1e-9));
      expect(result.drawdown.percent, 0);
      // Under a year is never annualised.
      expect(result.annualized, isNull);
    });

    test('a gain is counted without the money that came with it', () {
      final value = series([
        (DateTime(2026), 1000),
        (DateTime(2026, 2), 1100),
        (DateTime(2026, 3), 1650),
      ]);
      final paidIn = series([
        (DateTime(2026), 1000),
        (DateTime(2026, 3), 1500),
      ]);
      final result = ContributedReturn.of(value, paidIn)!;
      expect(result.gain, 150);
      // +10%, then 50 beyond the 500 paid in, on the 1100 already there and
      // half the new 500.
      expect(result.percent, closeTo((1.1 * (1 + 50 / 1350) - 1) * 100, 1e-9));
    });

    test('a whole history counts from the first money in', () {
      // The options template's journal, condensed: ₹10L, a ₹1L top-up.
      final value = series([
        (DateTime(2026), 1004200),
        (DateTime(2026, 1, 2), 1002350),
        (DateTime(2026, 1, 5), 1105450),
      ]);
      final paidIn = series([
        (DateTime(2026), 1000000),
        (DateTime(2026, 1, 5), 1100000),
      ]);
      final whole = ContributedReturn.of(value, paidIn, fromInception: true)!;
      expect(whole.gain, 5450);
      expect(whole.contributed, 1100000);
      final range = ContributedReturn.of(value, paidIn)!;
      expect(range.gain, 1250);
      expect(whole.percent, greaterThan(range.percent));
    });

    test('annualises from a year and measures falls of the growth', () {
      final value = series([
        (DateTime(2024), 1000),
        (DateTime(2024, 7), 800),
        (DateTime(2025), 1210),
      ]);
      final paidIn = series([(DateTime(2024), 1000)]);
      final result = ContributedReturn.of(value, paidIn)!;
      expect(result.percent, closeTo(21, 1e-9));
      expect(result.annualized, closeTo(21, 0.1));
      expect(result.drawdown.percent, closeTo(20, 1e-9));
      expect(ContributedReturn.of(value, TimeSeries.empty), isNull);
    });
  });

  group('an options book', () {
    final expiry = DateTime.now().add(const Duration(days: 7));
    String day(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final table = _table([
      [
        'Strategy',
        'Underlying',
        'Type',
        'Side',
        'Strike',
        'Qty',
        'Entry',
        'LTP',
        'Exit',
        'Expiry',
        'Status',
        'Margin',
      ],
      [
        'Condor',
        'NIFTY',
        'CE',
        'Sell',
        '22800',
        '65',
        '42.5',
        '30',
        '',
        day(expiry),
        'Open',
        '110000',
      ],
      [
        'Condor',
        'NIFTY',
        'CE',
        'Buy',
        '23000',
        '65',
        '16.8',
        '10',
        '',
        day(expiry),
        'Open',
        '',
      ],
      [
        'Condor',
        'NIFTY',
        'PE',
        'Sell',
        '22000',
        '65',
        '38.2',
        '28',
        '',
        day(expiry),
        'Open',
        '',
      ],
      [
        'Condor',
        'NIFTY',
        'PE',
        'Buy',
        '21800',
        '65',
        '14.6',
        '9',
        '',
        day(expiry),
        'Open',
        '',
      ],
      [
        'Straddle',
        'NIFTY',
        'CE',
        'Sell',
        '22500',
        '65',
        '118',
        '',
        '64',
        day(expiry),
        'Closed',
        '',
      ],
      [
        'Straddle',
        'NIFTY',
        'PE',
        'Sell',
        '22500',
        '65',
        '104',
        '',
        '131',
        day(expiry),
        'Closed',
        '',
      ],
      ['Half typed', 'NIFTY', '', 'Buy', '', '', '', '', '', '', '', ''],
    ]);

    test('reads complete legs and groups them into strategies', () {
      final legs = readOptionLegs(table);
      expect(legs.length, 6);
      expect(legs.first.side, OptionSide.sell);
      expect(legs.first.rowId, 'r1');
      final book = OptionsBook.of(legs);
      expect(book.strategies.map((s) => s.name), ['Condor', 'Straddle']);
      expect(book.realized, (118 - 64) * 65 - (131 - 104) * 65);
      expect(book.marginUsed, 110000);
      expect(
        book.openMarkToMarket(),
        closeTo(
          -(30 - 42.5) * 65 +
              (10 - 16.8) * 65 -
              (28 - 38.2) * 65 +
              (9 - 14.6) * 65,
          1e-6,
        ),
      );
    });

    test('knows an iron condor is bounded both ways', () {
      final condor = OptionsBook.of(readOptionLegs(table)).strategies.first;
      final credit = (42.5 - 16.8 + 38.2 - 14.6) * 65;
      final bounds = condor.bounds;
      expect(condor.netPremium, closeTo(credit, 1e-6));
      expect(bounds.maxProfit, closeTo(credit, 1e-6));
      expect(bounds.maxLoss, closeTo(credit - 200 * 65, 1e-6));
      expect(bounds.unlimitedProfit, isFalse);
      expect(bounds.unlimitedLoss, isFalse);
      expect(bounds.breakevens.length, 2);
      expect(bounds.breakevens.first, closeTo(22000 - credit / 65, 1e-6));
      expect(bounds.breakevens.last, closeTo(22800 + credit / 65, 1e-6));
      for (final breakeven in bounds.breakevens) {
        expect(condor.payoffAt(breakeven).abs(), lessThan(1e-6));
      }
    });

    test('knows a naked short call can lose without limit', () {
      final strategy = OptionStrategy(
        name: 'Naked',
        underlying: 'NIFTY',
        legs: [
          const OptionLeg(
            kind: LegKind.call,
            side: OptionSide.sell,
            quantity: 65,
            entry: 50,
            strike: 23000,
          ),
        ],
      );
      expect(strategy.bounds.unlimitedLoss, isTrue);
      expect(strategy.bounds.maxProfit, closeTo(50 * 65, 1e-9));
      expect(strategy.bounds.breakevens.single, closeTo(23050, 1e-9));
    });

    test('prices options the way Black and Scholes did', () {
      final call = BlackScholes.price(
        call: true,
        spot: 100,
        strike: 100,
        years: 1,
        volatility: 0.2,
        rate: 0.05,
      );
      final put = BlackScholes.price(
        call: false,
        spot: 100,
        strike: 100,
        years: 1,
        volatility: 0.2,
        rate: 0.05,
      );
      expect(call, closeTo(10.4506, 1e-3));
      expect(put, closeTo(5.5735, 1e-3));
      // Put-call parity.
      expect(call - put, closeTo(100 - 100 * math.exp(-0.05), 1e-6));
      final implied = BlackScholes.impliedVolatility(
        call: true,
        spot: 100,
        strike: 100,
        years: 1,
        price: call,
        rate: 0.05,
      );
      expect(implied, closeTo(0.2, 1e-4));
      final greeks = BlackScholes.greeks(
        call: true,
        spot: 100,
        strike: 100,
        years: 1,
        volatility: 0.2,
        rate: 0.05,
      );
      expect(greeks.delta, closeTo(0.6368, 1e-3));
      expect(greeks.theta, lessThan(0));
      expect(greeks.vega, greaterThan(0));
    });

    test('analyses a strategy against the market', () {
      final condor = OptionsBook.of(readOptionLegs(table)).strategies.first;
      final analysis = StrategyAnalysis(condor, spot: 22400);
      final pop = analysis.probabilityOfProfit!;
      expect(pop, greaterThan(0));
      expect(pop, lessThan(100));
      expect(analysis.hasTimeValue, isTrue);
      expect(analysis.greeks, isNotNull);
      final (low, high) = analysis.range;
      expect(low, lessThan(21800));
      expect(high, greaterThan(23000));
      // Today's value approaches the payoff far from the strikes.
      expect(analysis.todayAt(30000), closeTo(condor.payoffAt(30000), 50));
    });
  });

  group('a balance sheet', () {
    final table = _table([
      [
        'Name',
        'Type',
        'Category',
        'Value',
        'Invested',
        'Borrowed',
        'Rate %',
        'EMI',
      ],
      ['SGB 2028', 'Asset', '', '285000', '168000', '', '2.5', ''],
      ['Apartment', 'Asset', 'Real estate', '9500000', '6200000', '', '', ''],
      ['EPF', 'Asset', 'Provident fund', '1460000', '', '', '8.25', ''],
      ['NPS Tier I', 'Asset', 'NPS', '840000', '620000', '', '', ''],
      ['Savings', 'Asset', 'Cash & bank', '340000', '', '', '3', ''],
      [
        'HDFC home loan',
        'Liability',
        '',
        '4850000',
        '',
        '6000000',
        '8.5',
        '52068',
      ],
      ['Card', 'Liability', 'Credit card', '38000', '', '', '42', ''],
    ]);

    test('files every entry under what it is', () {
      final items = readBalanceItems(table);
      expect(items.length, 7);
      expect(items[0].category, BalanceCategory.gold);
      expect(items[1].category, BalanceCategory.realEstate);
      expect(items[2].category, BalanceCategory.providentFund);
      expect(items[3].category, BalanceCategory.pension);
      expect(items[4].category, BalanceCategory.cash);
      expect(items[5].category, BalanceCategory.homeLoan);
      expect(items[6].category, BalanceCategory.creditCard);
      expect(matchBalanceCategory('Gold loan'), BalanceCategory.personalLoan);
      expect(matchBalanceCategory('upfront fees'), isNull);
    });

    test('adds up to a net worth with its liquidity', () {
      final summary = BalanceSummary.of(readBalanceItems(table));
      expect(summary.assets, 12425000);
      expect(summary.liabilities, 4888000);
      expect(summary.netWorth, 12425000 - 4888000);
      expect(summary.locked, 9500000 + 1460000 + 840000);
      expect(summary.liquid, 340000);
      expect(summary.monthlyEmi, 52068);
      expect(summary.debtRatio, closeTo(4888000 / 12425000 * 100, 1e-9));
      expect(
        summary.assetCategories.first.category,
        BalanceCategory.realEstate,
      );
    });

    test('works out when a loan ends', () {
      final outlook = LoanOutlook.of(
        balance: 4850000,
        annualRate: 8.5,
        emi: 52068,
        borrowed: 6000000,
        asOf: DateTime(2026),
      );
      expect(outlook.monthsLeft, 153);
      expect(outlook.payoffDate, DateTime(2038, 10));
      expect(outlook.repaidShare, closeTo(1 - 4850000 / 6000000, 1e-9));
      expect(outlook.interestLeft, greaterThan(3000000));
      final stuck = LoanOutlook.of(balance: 100000, annualRate: 24, emi: 1000);
      expect(stuck.neverRepaid, isTrue);
      expect(stuck.monthsLeft, isNull);
    });
  });

  group('quotes', () {
    test('are read by their column names, favourites and all', () {
      final quotes = readQuotes(
        _table([
          ['Quote', 'Who said it', 'Where from', 'Theme', 'Favourite'],
          [
            '“Simplify, simplify.”',
            'Thoreau',
            'Walden',
            'Life, Stillness',
            'Yes',
          ],
          ['', 'Nobody', '', '', 'No'],
        ]),
      );
      expect(quotes.length, 1);
      expect(quotes.single.body, 'Simplify, simplify.');
      expect(quotes.single.author, 'Thoreau');
      expect(quotes.single.themes, ['Life', 'Stillness']);
      expect(quotes.single.favourite, isTrue);
      expect(quotes.single.length, QuoteLength.short);
      expect(QuoteLength.of('x' * 700), QuoteLength.epic);
    });

    test('come round once each before any comes round again', () {
      for (final count in [1, 2, 7, 12, 30]) {
        // A day on which a cycle of [count] quotes begins.
        final start = DateTime.utc(1970).add(Duration(days: count * 2000));
        final seen = <int>{
          for (var day = 0; day < count; day++)
            quoteOfTheDay(
              count,
              DateTime(start.year, start.month, start.day + day),
            ),
        };
        expect(seen.length, count, reason: '$count');
      }
      expect(
        quoteOfTheDay(10, DateTime(2026, 5, 4)),
        quoteOfTheDay(10, DateTime(2026, 5, 4, 23)),
      );
      expect(quoteOfTheDay(0, DateTime(2026)), -1);
    });
  });
}
