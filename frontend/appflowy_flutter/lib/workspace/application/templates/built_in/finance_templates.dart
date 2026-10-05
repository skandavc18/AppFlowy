import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/market/market_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/template_pieces.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Money: what it is worth, where it went, and what the market is doing.
void registerFinanceTemplates() {
  TemplateRegistry.register(_stocks);
  TemplateRegistry.register(_options);
  TemplateRegistry.register(_assets);
  TemplateRegistry.register(_expenses);
  TemplateRegistry.register(_subscriptions);
}

/// A day the way a template seeds a date column.
String _day(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _ago(int days) {
  final today = _today();
  return _day(DateTime(today.year, today.month, today.day - days));
}

String _amount(num value) =>
    value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(2);

DashboardWidgetSpec _quote(
  String symbol, {
  int x = 0,
  int y = 0,
  int w = 4,
  int h = 5,
  String range = 'month1',
  bool chart = true,
}) =>
    widget(
      'ext.stock.quote',
      x: x,
      y: y,
      w: w,
      h: h,
      settings: {
        'symbol': symbol,
        'range': range,
        'showChart': chart,
        'showPicker': chart,
        'filled': true,
      },
    );

// --------------------------------------------------------------------- stocks

final _stocks = WorkspaceTemplate(
  id: 'stocks',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_stocks.tr(),
  description: () => LocaleKeys.templates_item_stocksHint.tr(),
  icon: Icons.show_chart_rounded,
  accent: DashboardAccent.blue,
  keywords: const [
    'stocks',
    'shares',
    'market',
    'portfolio',
    'holdings',
    'watchlist',
    'returns',
    'nifty',
    'sensex',
  ],
  requires: const {'stock'},
  build: () => [
    TemplatePart(
      key: 'holdings',
      icon: '💼',
      name: () => LocaleKeys.templates_text_holdings.tr(),
      blueprint: TemplateDatabase((_) => _holdingsTable()),
    ),
    TemplatePart(
      key: 'history',
      icon: '📈',
      name: () => LocaleKeys.templates_text_valueHistory.tr(),
      blueprint: TemplateDatabase((_) => _valueHistoryTable()),
    ),
    TemplatePart(
      key: 'board',
      icon: '📊',
      name: () => LocaleKeys.templates_item_stocks.tr(),
      blueprint: TemplateDashboard(_stocksBoard),
    ),
  ],
);

TemplateTable _holdingsTable() {
  final banking = LocaleKeys.templates_option_banking.tr();
  final technology = LocaleKeys.templates_option_technology.tr();
  final energy = LocaleKeys.templates_option_energy.tr();
  final consumer = LocaleKeys.templates_option_consumer.tr();
  final auto = LocaleKeys.templates_option_auto.tr();
  final pharma = LocaleKeys.templates_option_pharma.tr();
  final telecom = LocaleKeys.templates_option_telecom.tr();
  final indexFund = LocaleKeys.templates_option_indexFund.tr();
  return TemplateTable(
    columns: [
      TemplateColumn.text(LocaleKeys.templates_column_name.tr()),
      TemplateColumn.text(LocaleKeys.templates_column_symbol.tr()),
      TemplateColumn.select(LocaleKeys.templates_column_sector.tr(), [
        banking,
        technology,
        energy,
        consumer,
        auto,
        pharma,
        telecom,
        indexFund,
        LocaleKeys.templates_option_infrastructure.tr(),
        LocaleKeys.templates_option_otherKind.tr(),
      ]),
      TemplateColumn.number(LocaleKeys.templates_column_qty.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_avgPrice.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_ltp.tr()),
      TemplateColumn.date(LocaleKeys.templates_column_boughtOn.tr()),
      TemplateColumn.text(LocaleKeys.templates_column_notes.tr()),
    ],
    rows: [
      for (final (name, symbol, sector, quantity, average, last, days) in [
        ('Reliance Industries', 'RELIANCE.NS', energy, 40, 1185.5, 1167.7, 540),
        ('HDFC Bank', 'HDFCBANK.NS', banking, 120, 612.4, 721.2, 720),
        ('Infosys', 'INFY.NS', technology, 60, 1420.0, 1035.0, 610),
        ('Tata Consultancy Services', 'TCS.NS', technology, 25, 2950.0, 2075.0, 480),
        ('ICICI Bank', 'ICICIBANK.NS', banking, 70, 988.0, 1310.6, 820),
        ('Bharti Airtel', 'BHARTIARTL.NS', telecom, 45, 1180.0, 1741.1, 700),
        ('ITC', 'ITC.NS', consumer, 300, 289.5, 255.9, 380),
        ('Maruti Suzuki', 'MARUTI.NS', auto, 6, 10450.0, 11386.0, 400),
        ('Sun Pharma', 'SUNPHARMA.NS', pharma, 30, 1520.0, 1801.0, 560),
        ('Nifty 50 index fund', 'NIFTYBEES.NS', indexFund, 400, 236.8, 257.25, 900),
      ])
        [
          name,
          symbol,
          sector,
          '$quantity',
          _amount(average),
          _amount(_marketPrice(symbol) ?? last),
          _ago(days),
          '',
        ],
    ],
  );
}

/// The market's last known price for [symbol], when the Stocks extension has
/// one, so a new portfolio opens at today's prices rather than old ones.
double? _marketPrice(String symbol) => MarketData.provider?.quote(symbol)?.price;

/// A year of month-ends: what went in, and what it was worth.
TemplateTable _valueHistoryTable() {
  const invested = [
    420000,
    445000,
    468000,
    492000,
    515000,
    540000,
    565000,
    588000,
    612000,
    636000,
    660000,
    676000,
    691988,
  ];
  const growth = [
    1.012,
    1.034,
    1.008,
    0.982,
    1.026,
    1.058,
    1.041,
    1.019,
    1.066,
    1.081,
    1.052,
    1.028,
    1.0395,
  ];
  final today = _today();
  return TemplateTable(
    columns: [
      TemplateColumn.text(LocaleKeys.templates_column_label.tr()),
      TemplateColumn.date(LocaleKeys.templates_column_date.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_value.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_invested.tr()),
    ],
    rows: [
      for (var index = 0; index < invested.length; index++)
        () {
          final date = index == invested.length - 1
              ? today
              : DateTime(today.year, today.month - 12 + index);
          return [
            DateFormat('MMM yyyy').format(date),
            _day(date),
            '${(invested[index] * growth[index]).round()}',
            '${invested[index]}',
          ];
        }(),
    ],
  );
}

DashboardDocument _stocksBoard(TemplateContext created) {
  final holdings = created['holdings'];
  final history = created['history'];
  final holdingsName = LocaleKeys.templates_text_holdings.tr();
  final historyName = LocaleKeys.templates_text_valueHistory.tr();
  return document(
    [
      section([
        widget(
          'portfolio',
          w: 8,
          h: 5,
          source: table(holdings, name: holdingsName),
        ),
        widget(
          'watchlist',
          x: 8,
          h: 5,
          title: LocaleKeys.templates_text_indices.tr(),
          settings: const {
            'symbols': ['^NSEI', '^NSEBANK', '^BSESN', '^CNXIT', 'GC=F', 'INR=X'],
          },
        ),
      ]),
      section([
        widget(
          'holdings',
          w: 8,
          h: 9,
          title: holdingsName,
          source: table(holdings, name: holdingsName),
        ),
        widget(
          'allocation',
          x: 8,
          h: 9,
          title: LocaleKeys.templates_text_bySector.tr(),
          source: table(holdings, name: holdingsName),
        ),
      ]),
      section(
        [
          widget(
            'trend',
            w: 8,
            h: 7,
            title: LocaleKeys.templates_text_portfolioVsInvested.tr(),
            source: table(history, name: historyName),
          ),
          widget(
            'watchlist',
            x: 8,
            h: 7,
            title: LocaleKeys.templates_text_myWatchlist.tr(),
            settings: const {
              'symbols': [
                'LT.NS',
                'SBIN.NS',
                'AXISBANK.NS',
                'TITAN.NS',
                'BAJFINANCE.NS',
                'ASIANPAINT.NS',
              ],
            },
          ),
        ],
        title: LocaleKeys.templates_text_performance.tr(),
      ),
      section(
        [
          widget(
            'heatmap',
            w: 12,
            h: 6,
            source: table(holdings, name: holdingsName),
          ),
        ],
        title: LocaleKeys.templates_text_marketMap.tr(),
      ),
      section(
        [
          _quote('^NSEI', w: 6, h: 6, range: 'year1'),
          _quote('^NSEBANK', x: 6, w: 6, h: 6, range: 'year1'),
        ],
        title: LocaleKeys.templates_text_takeACloserLook.tr(),
      ),
      section(
        [
          widget(
            'database',
            w: 12,
            h: 8,
            source: table(holdings, name: holdingsName),
          ),
        ],
        title: LocaleKeys.templates_text_theTables.tr(),
      ),
    ],
    subtitle: LocaleKeys.templates_item_stocksHint.tr(),
  );
}

// -------------------------------------------------------------------- options

final _options = WorkspaceTemplate(
  id: 'options',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_options.tr(),
  description: () => LocaleKeys.templates_item_optionsHint.tr(),
  icon: Icons.stacked_line_chart_rounded,
  accent: DashboardAccent.purple,
  keywords: const [
    'options',
    'f&o',
    'derivatives',
    'option chain',
    'iron condor',
    'straddle',
    'banknifty',
    'payoff',
    'greeks',
    'trading journal',
  ],
  requires: const {'stock'},
  build: () => [
    TemplatePart(
      key: 'legs',
      icon: '🎯',
      name: () => LocaleKeys.templates_text_optionLegs.tr(),
      blueprint: TemplateDatabase((_) => _legsTable()),
    ),
    TemplatePart(
      key: 'journal',
      icon: '📒',
      name: () => LocaleKeys.templates_text_tradingJournal.tr(),
      blueprint: TemplateDatabase((_) => _journalTable()),
    ),
    TemplatePart(
      key: 'board',
      icon: '📉',
      name: () => LocaleKeys.templates_item_options.tr(),
      blueprint: TemplateDashboard(_optionsBoard),
    ),
  ],
);

DateTime _weekday(DateTime from, int weekday, {int step = 1}) {
  var day = DateTime(from.year, from.month, from.day);
  while (day.weekday != weekday) {
    day = DateTime(day.year, day.month, day.day + step);
  }
  return day;
}

/// The month's last Tuesday, when NSE index options settle, at least ten
/// days away.
DateTime _monthlyExpiry(DateTime from) {
  DateTime lastTuesday(int year, int month) =>
      _weekday(DateTime(year, month + 1, 0), DateTime.tuesday, step: -1);
  final expiry = lastTuesday(from.year, from.month);
  return expiry.difference(from).inDays >= 10
      ? expiry
      : lastTuesday(from.year, from.month + 1);
}

/// [spot] moved by [offset] and rounded onto the strike grid.
String _strike(double spot, double offset, double step) =>
    '${(((spot + offset) / step).round() * step).round()}';

TemplateTable _legsTable() {
  final today = _today();
  final weekly = _weekday(
    DateTime(today.year, today.month, today.day + 3),
    DateTime.tuesday,
  );
  final monthly = _monthlyExpiry(today);
  final lastWeek = _weekday(
    DateTime(today.year, today.month, today.day - 1),
    DateTime.tuesday,
    step: -1,
  );
  // Strikes sit around where the indices trade now, when that is known.
  final nifty = _marketPrice('^NSEI') ?? 22420;
  final bank = _marketPrice('^NSEBANK') ?? 54450;
  final buy = LocaleKeys.templates_option_buy.tr();
  final sell = LocaleKeys.templates_option_sell.tr();
  final open = LocaleKeys.templates_option_openPosition.tr();
  final closed = LocaleKeys.templates_option_closed.tr();
  final condor = 'NIFTY ${LocaleKeys.templates_option_ironCondor.tr()}';
  final putSpread = 'BANKNIFTY ${LocaleKeys.templates_option_spread.tr()}';
  final callSpread = 'NIFTY ${LocaleKeys.templates_option_spread.tr()}';
  final straddle = 'NIFTY ${LocaleKeys.templates_option_straddle.tr()}';
  return TemplateTable(
    columns: [
      TemplateColumn.text(LocaleKeys.templates_column_strategy.tr()),
      TemplateColumn.select(LocaleKeys.templates_column_underlying.tr(), const [
        'NIFTY',
        'BANKNIFTY',
        'FINNIFTY',
        'MIDCPNIFTY',
        'RELIANCE',
      ]),
      TemplateColumn.select(
        LocaleKeys.templates_column_type.tr(),
        const ['CE', 'PE', 'FUT'],
      ),
      TemplateColumn.select(LocaleKeys.templates_column_side.tr(), [buy, sell]),
      TemplateColumn.number(LocaleKeys.templates_column_strike.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_qty.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_entry.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_ltp.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_exit.tr()),
      TemplateColumn.date(LocaleKeys.templates_column_expiry.tr()),
      TemplateColumn.select(
        LocaleKeys.templates_column_status.tr(),
        [open, closed],
      ),
      TemplateColumn.number(LocaleKeys.templates_column_margin.tr()),
      TemplateColumn.date(LocaleKeys.templates_column_opened.tr()),
      TemplateColumn.text(LocaleKeys.templates_column_notes.tr()),
    ],
    rows: [
      [condor, 'NIFTY', 'CE', sell, _strike(nifty, 400, 50), '65', '42.5', '31.4', '', _day(weekly), open, '110000', _ago(4), ''],
      [condor, 'NIFTY', 'CE', buy, _strike(nifty, 600, 50), '65', '16.8', '11.2', '', _day(weekly), open, '', _ago(4), ''],
      [condor, 'NIFTY', 'PE', sell, _strike(nifty, -400, 50), '65', '38.2', '29.5', '', _day(weekly), open, '', _ago(4), ''],
      [condor, 'NIFTY', 'PE', buy, _strike(nifty, -600, 50), '65', '14.6', '10.1', '', _day(weekly), open, '', _ago(4), ''],
      [putSpread, 'BANKNIFTY', 'PE', sell, _strike(bank, -500, 100), '30', '412', '356', '', _day(monthly), open, '95000', _ago(6), ''],
      [putSpread, 'BANKNIFTY', 'PE', buy, _strike(bank, -1000, 100), '30', '268', '231', '', _day(monthly), open, '', _ago(6), ''],
      [callSpread, 'NIFTY', 'CE', sell, _strike(nifty, 800, 50), '65', '96', '84.5', '', _day(monthly), open, '62000', _ago(2), ''],
      [callSpread, 'NIFTY', 'CE', buy, _strike(nifty, 1100, 50), '65', '48', '41', '', _day(monthly), open, '', _ago(2), ''],
      [straddle, 'NIFTY', 'CE', sell, _strike(nifty, 0, 50), '65', '118', '', '64', _day(lastWeek), closed, '', _ago(9), ''],
      [straddle, 'NIFTY', 'PE', sell, _strike(nifty, 0, 50), '65', '104', '', '131', _day(lastWeek), closed, '', _ago(9), ''],
    ],
  );
}

/// Thirty trading days of results on a ₹10 lakh account, with one top-up.
const _journalResults = [
  4200, -1850, 3100, 6250, -3400, 1200, 2850, -950, 5100, -6200, //
  3300, 1750, 4800, -2100, 2600, 900, -1400, 3900, 5600, -2800, //
  1500, 3200, -700, 4400, 2100, -3600, 2900, 1800, 6100, -1200,
];
const _journalOpening = 1000000;
const _journalTopUp = 100000;
const _journalTopUpDay = 15;

/// The account's capital after the journal's last day — what the summary
/// starts from, so it and the trading stats tell one story.
int _journalCapital() =>
    _journalOpening +
    _journalTopUp +
    _journalResults.fold<int>(0, (total, result) => total + result);

TemplateTable _journalTable() {
  const results = _journalResults;
  final setups = [
    LocaleKeys.templates_option_ironCondor.tr(),
    LocaleKeys.templates_option_straddle.tr(),
    LocaleKeys.templates_option_spread.tr(),
    LocaleKeys.templates_option_directional.tr(),
    LocaleKeys.templates_option_strangle.tr(),
    LocaleKeys.templates_option_hedge.tr(),
  ];
  const notes = [
    'Adjusted the put side on the dip',
    'Closed early at half the credit',
    'Rolled to the next week',
    'Stopped out on a gap open',
    'Quiet theta day',
    'Hedged ahead of results',
  ];
  // The trading days before today, oldest first.
  final days = <DateTime>[];
  var day = _today();
  while (days.length < results.length) {
    day = DateTime(day.year, day.month, day.day - 1);
    if (day.weekday != DateTime.saturday && day.weekday != DateTime.sunday) {
      days.insert(0, day);
    }
  }
  var capital = _journalOpening;
  var deposits = _journalOpening;
  final rows = <List<String>>[];
  for (var index = 0; index < results.length; index++) {
    if (index == _journalTopUpDay) {
      deposits += _journalTopUp;
      capital += _journalTopUp;
    }
    capital += results[index];
    rows.add([
      notes[index % notes.length],
      _day(days[index]),
      '${results[index]}',
      '$capital',
      '$deposits',
      setups[index % setups.length],
    ]);
  }
  return TemplateTable(
    columns: [
      TemplateColumn.text(LocaleKeys.templates_column_note.tr()),
      TemplateColumn.date(LocaleKeys.templates_column_date.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_pnl.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_capital.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_deposits.tr()),
      TemplateColumn.select(LocaleKeys.templates_column_setup.tr(), setups),
    ],
    rows: rows,
  );
}

DashboardDocument _optionsBoard(TemplateContext created) {
  final legs = created['legs'];
  final journal = created['journal'];
  final legsName = LocaleKeys.templates_text_optionLegs.tr();
  final journalName = LocaleKeys.templates_text_tradingJournal.tr();
  return document(
    [
      section([
        widget(
          'options_summary',
          w: 8,
          h: 5,
          settings: {'capital': _journalCapital()},
          source: table(legs, name: legsName),
        ),
        widget(
          'pnl_stats',
          x: 8,
          h: 5,
          title: LocaleKeys.dashboard_money_pnlStats.tr(),
          source: table(journal, name: journalName),
        ),
      ]),
      section(
        [
          widget(
            'options_book',
            w: 12,
            h: 9,
            source: table(legs, name: legsName),
          ),
        ],
        title: LocaleKeys.templates_text_strategies.tr(),
      ),
      section(
        [
          widget(
            'options_payoff',
            w: 8,
            h: 9,
            title: LocaleKeys.dashboard_money_payoff.tr(),
            source: table(legs, name: legsName),
          ),
          widget(
            'pnl_calendar',
            x: 8,
            h: 9,
            title: LocaleKeys.dashboard_money_pnlCalendar.tr(),
            source: table(journal, name: journalName),
          ),
        ],
        title: LocaleKeys.templates_text_payoffAndDays.tr(),
      ),
      section(
        [
          widget(
            'option_chain',
            w: 12,
            h: 11,
            settings: const {'underlying': 'NIFTY', 'strikes': 12},
            source: table(legs, name: legsName),
          ),
        ],
        title: LocaleKeys.templates_text_optionChain.tr(),
      ),
      section([
        widget(
          'trend',
          w: 12,
          h: 7,
          title: LocaleKeys.templates_text_capitalCurve.tr(),
          source: table(journal, name: journalName),
        ),
      ]),
      section(
        [
          widget('database', w: 12, h: 8, source: table(legs, name: legsName)),
          widget(
            'database',
            y: 8,
            w: 12,
            h: 8,
            source: table(journal, name: journalName),
          ),
        ],
        title: LocaleKeys.templates_text_theTables.tr(),
      ),
    ],
    subtitle: LocaleKeys.templates_item_optionsHint.tr(),
  );
}

// ------------------------------------------------------------------ net worth

final _assets = WorkspaceTemplate(
  id: 'assets',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_assets.tr(),
  description: () => LocaleKeys.templates_item_assetsHint.tr(),
  icon: Icons.account_balance_rounded,
  accent: DashboardAccent.teal,
  keywords: const [
    'assets',
    'net worth',
    'wealth',
    'gold',
    'real estate',
    'provident fund',
    'nps',
    'retirement',
    'loans',
    'emi',
  ],
  build: () => [
    TemplatePart(
      key: 'holdings',
      icon: '🏦',
      name: () => LocaleKeys.templates_text_balanceSheet.tr(),
      blueprint: TemplateDatabase((_) => _balanceSheetTable()),
    ),
    TemplatePart(
      key: 'history',
      icon: '📈',
      name: () => LocaleKeys.templates_text_netWorthHistory.tr(),
      blueprint: TemplateDatabase((_) => _netWorthHistoryTable()),
    ),
    TemplatePart(
      key: 'board',
      icon: '💎',
      name: () => LocaleKeys.templates_item_assets.tr(),
      blueprint: TemplateDashboard(_netWorthBoard),
    ),
  ],
);

TemplateTable _balanceSheetTable() {
  final asset = LocaleKeys.templates_option_asset.tr();
  final liability = LocaleKeys.templates_option_liability.tr();
  final gold = LocaleKeys.templates_option_gold.tr();
  final realEstate = LocaleKeys.templates_option_realEstate.tr();
  final providentFund = LocaleKeys.templates_option_providentFund.tr();
  final nps = LocaleKeys.templates_option_nps.tr();
  final mutualFunds = LocaleKeys.templates_option_mutualFunds.tr();
  final stocks = LocaleKeys.templates_option_stocks.tr();
  final deposits = LocaleKeys.templates_option_fixedDeposits.tr();
  final cash = LocaleKeys.templates_option_cashAndBank.tr();
  final homeLoan = LocaleKeys.templates_option_homeLoan.tr();
  final vehicleLoan = LocaleKeys.templates_option_vehicleLoan.tr();
  final creditCard = LocaleKeys.templates_option_creditCard.tr();
  return TemplateTable(
    columns: [
      TemplateColumn.text(LocaleKeys.templates_column_name.tr()),
      TemplateColumn.select(
        LocaleKeys.templates_column_type.tr(),
        [asset, liability],
      ),
      TemplateColumn.select(LocaleKeys.templates_column_category.tr(), [
        gold,
        realEstate,
        providentFund,
        nps,
        mutualFunds,
        stocks,
        deposits,
        cash,
        LocaleKeys.templates_option_crypto.tr(),
        LocaleKeys.templates_option_bond.tr(),
        LocaleKeys.templates_option_insurance.tr(),
        LocaleKeys.templates_option_vehicle.tr(),
        homeLoan,
        vehicleLoan,
        LocaleKeys.templates_option_personalLoan.tr(),
        creditCard,
        LocaleKeys.templates_option_otherKind.tr(),
      ]),
      TemplateColumn.number(LocaleKeys.templates_column_value.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_invested.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_borrowed.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_ratePercent.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_emi.tr()),
      TemplateColumn.date(LocaleKeys.templates_column_updated.tr()),
      TemplateColumn.text(LocaleKeys.templates_column_notes.tr()),
    ],
    rows: [
      // Name, type, category, value, invested, borrowed, rate, EMI, updated.
      ['Gold jewellery', asset, gold, '620000', '410000', '', '', '', _ago(12), '22 carat, 52 g'],
      ['Sovereign Gold Bonds', asset, gold, '285000', '168000', '', '2.5', '', _ago(12), 'Tax-free at maturity'],
      ['Apartment in Pune', asset, realEstate, '9500000', '6200000', '', '', '', _ago(40), '2 BHK, self-occupied'],
      ['Employee Provident Fund', asset, providentFund, '1460000', '', '', '8.25', '', _ago(20), ''],
      ['Public Provident Fund', asset, providentFund, '610000', '480000', '', '7.1', '', _ago(20), 'Matures in 2031'],
      ['NPS Tier I', asset, nps, '840000', '620000', '', '', '', _ago(9), '75% equity'],
      ['Flexi-cap mutual funds', asset, mutualFunds, '1275000', '960000', '', '', '', _ago(3), 'Monthly SIP'],
      ['Direct equity', asset, stocks, '930000', '690000', '', '', '', _ago(1), ''],
      ['Fixed deposits', asset, deposits, '500000', '500000', '', '7.25', '', _ago(30), ''],
      ['Savings account', asset, cash, '340000', '', '', '3', '', _ago(1), 'Emergency fund'],
      ['Home loan', liability, homeLoan, '4850000', '', '6000000', '8.5', '52068', _ago(5), ''],
      ['Car loan', liability, vehicleLoan, '420000', '', '800000', '9.2', '16700', _ago(5), ''],
      ['Credit card', liability, creditCard, '38000', '', '', '42', '', _ago(2), 'Due on the 18th'],
    ],
  );
}

/// A year of month-ends, owned against owed.
TemplateTable _netWorthHistoryTable() {
  const assets = [
    14920000,
    15040000,
    15110000,
    15060000,
    15250000,
    15420000,
    15510000,
    15630000,
    15800000,
    15910000,
    16090000,
    16220000,
    16360000,
  ];
  final today = _today();
  return TemplateTable(
    columns: [
      TemplateColumn.text(LocaleKeys.templates_column_label.tr()),
      TemplateColumn.date(LocaleKeys.templates_column_month.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_assets.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_liabilities.tr()),
      TemplateColumn.number(LocaleKeys.templates_column_netWorth.tr()),
    ],
    rows: [
      for (var index = 0; index < assets.length; index++)
        () {
          final date = index == assets.length - 1
              ? today
              : DateTime(today.year, today.month - 12 + index);
          // Loans fall a little every month as EMIs are paid.
          final owed = index == assets.length - 1
              ? 5308000
              : (5640000 - index * 27000 + math.sin(index * 1.3) * 9000).round();
          return [
            DateFormat('MMM yyyy').format(date),
            _day(date),
            '${assets[index]}',
            '$owed',
            '${assets[index] - owed}',
          ];
        }(),
    ],
  );
}

DashboardDocument _netWorthBoard(TemplateContext created) {
  final sheet = created['holdings'];
  final history = created['history'];
  final sheetName = LocaleKeys.templates_text_balanceSheet.tr();
  final historyName = LocaleKeys.templates_text_netWorthHistory.tr();
  return document(
    [
      section([
        widget(
          'net_worth',
          w: 8,
          h: 6,
          settings: {
            if (history != null && history.isNotEmpty) ...{
              'history_view': history,
              'history_name': historyName,
            },
          },
          source: table(sheet, name: sheetName),
        ),
        widget(
          'allocation',
          x: 8,
          h: 6,
          title: LocaleKeys.templates_text_assetMix.tr(),
          source: table(sheet, name: sheetName),
        ),
      ]),
      section(
        [
          widget(
            'balance_sheet',
            w: 12,
            h: 8,
            source: table(sheet, name: sheetName),
          ),
        ],
        title: LocaleKeys.templates_text_whatYouOwn.tr(),
      ),
      section(
        [
          widget(
            'loans',
            w: 12,
            h: 6,
            source: table(sheet, name: sheetName),
          ),
        ],
        title: LocaleKeys.templates_text_whatYouOwe.tr(),
      ),
      section(
        [
          widget(
            'trend',
            w: 12,
            h: 7,
            title: LocaleKeys.templates_text_netWorthHistory.tr(),
            source: table(history, name: historyName),
          ),
        ],
        title: LocaleKeys.templates_text_growth.tr(),
      ),
      section(
        [
          widget(
            'database',
            w: 12,
            h: 9,
            source: table(sheet, name: sheetName),
          ),
        ],
        title: LocaleKeys.templates_text_theTables.tr(),
      ),
    ],
    subtitle: LocaleKeys.templates_item_assetsHint.tr(),
  );
}

// ------------------------------------------------------------------- expenses

final _expenses = WorkspaceTemplate(
  id: 'expenses',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_expenses.tr(),
  description: () => LocaleKeys.templates_item_expensesHint.tr(),
  icon: Icons.receipt_long_rounded,
  accent: DashboardAccent.orange,
  keywords: const ['expenses', 'spending', 'budget', 'money', 'costs'],
  build: () => [
    TemplatePart(
      key: 'spend',
      icon: '🧾',
      name: () => LocaleKeys.templates_text_spending.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_what.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_amount.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_category.tr(), [
              LocaleKeys.templates_option_home.tr(),
              LocaleKeys.templates_option_food.tr(),
              LocaleKeys.templates_option_travel.tr(),
              LocaleKeys.templates_option_health.tr(),
              LocaleKeys.templates_option_fun.tr(),
              LocaleKeys.templates_option_otherKind.tr(),
            ]),
            TemplateColumn.date(LocaleKeys.templates_column_when.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_paidWith.tr(), [
              LocaleKeys.templates_option_card.tr(),
              LocaleKeys.templates_option_cashPayment.tr(),
              LocaleKeys.templates_option_transfer.tr(),
            ]),
            TemplateColumn.checkbox(LocaleKeys.templates_column_recurring.tr()),
          ],
          rows: [
            [
              LocaleKeys.templates_text_rent.tr(),
              '1200',
              LocaleKeys.templates_option_home.tr(),
              '',
              LocaleKeys.templates_option_transfer.tr(),
              'yes',
            ],
            [
              LocaleKeys.templates_text_groceries.tr(),
              '86',
              LocaleKeys.templates_option_food.tr(),
              '',
              LocaleKeys.templates_option_card.tr(),
              'no',
            ],
            [
              LocaleKeys.templates_text_trainTicket.tr(),
              '32',
              LocaleKeys.templates_option_travel.tr(),
              '',
              LocaleKeys.templates_option_card.tr(),
              'no',
            ],
          ],
        ),
      ),
    ),
    TemplatePart(
      key: 'board',
      icon: '💸',
      name: () => LocaleKeys.templates_item_expenses.tr(),
      blueprint: TemplateDashboard(
        (created) {
          final spend = created['spend'];
          final amount = LocaleKeys.templates_column_amount.tr();
          final category = LocaleKeys.templates_column_category.tr();
          final name = LocaleKeys.templates_text_spending.tr();
          return document(
            [
              section([
                widget(
                  'metric',
                  h: 3,
                  title: LocaleKeys.templates_text_spentSoFar.tr(),
                  accent: DashboardAccent.orange,
                  settings: const {'aggregate': 'sum', 'prefix': r'$'},
                  source: table(spend, name: name, field: amount),
                ),
                widget(
                  'progress',
                  x: 4,
                  h: 3,
                  title: LocaleKeys.templates_text_monthlyBudget.tr(),
                  accent: DashboardAccent.green,
                  settings: const {
                    'aggregate': 'sum',
                    'target': 2000,
                    'style': 'ring',
                  },
                  source: table(spend, name: name, field: amount),
                ),
                widget(
                  'metric',
                  x: 8,
                  h: 3,
                  title: LocaleKeys.templates_text_biggest.tr(),
                  settings: const {'aggregate': 'max', 'prefix': r'$'},
                  source: table(spend, name: name, field: amount),
                ),
              ]),
              section([
                widget(
                  'chart',
                  w: 6,
                  h: 7,
                  title: LocaleKeys.templates_text_whereItGoes.tr(),
                  accent: DashboardAccent.orange,
                  settings: const {'chart_type': 'donut'},
                  source: table(
                    spend,
                    name: name,
                    field: amount,
                    groupField: category,
                  ),
                ),
                widget(
                  'database',
                  x: 6,
                  w: 6,
                  h: 7,
                  source: table(spend, name: name),
                ),
              ]),
            ],
            subtitle: LocaleKeys.templates_item_expensesHint.tr(),
          );
        },
      ),
    ),
  ],
);

// -------------------------------------------------------------- subscriptions

final _subscriptions = WorkspaceTemplate(
  id: 'subscriptions',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_subscriptions.tr(),
  description: () => LocaleKeys.templates_item_subscriptionsHint.tr(),
  icon: Icons.autorenew_rounded,
  accent: DashboardAccent.purple,
  keywords: const ['subscriptions', 'recurring', 'bills', 'renewals'],
  build: () => [
    TemplatePart(
      key: 'subscriptions',
      icon: '🔁',
      name: () => LocaleKeys.templates_item_subscriptions.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_service.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_amount.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_billing.tr(), [
              LocaleKeys.templates_option_monthly.tr(),
              LocaleKeys.templates_option_yearly.tr(),
            ]),
            TemplateColumn.date(LocaleKeys.templates_column_renews.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_category.tr(), [
              LocaleKeys.templates_option_work.tr(),
              LocaleKeys.templates_option_fun.tr(),
              LocaleKeys.templates_option_home.tr(),
            ]),
            TemplateColumn.checkbox(LocaleKeys.templates_column_keeping.tr()),
            TemplateColumn.url(LocaleKeys.templates_column_manage.tr()),
          ],
          rows: [
            [
              'Music',
              '11',
              LocaleKeys.templates_option_monthly.tr(),
              '',
              LocaleKeys.templates_option_fun.tr(),
              'yes',
              '',
            ],
            [
              'Cloud storage',
              '99',
              LocaleKeys.templates_option_yearly.tr(),
              '',
              LocaleKeys.templates_option_work.tr(),
              'yes',
              '',
            ],
          ],
        ),
      ),
    ),
  ],
);
