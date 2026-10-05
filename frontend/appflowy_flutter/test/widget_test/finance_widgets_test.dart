import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_binding.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_kit.dart';
import 'package:appflowy/shared/market/market_data.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

/// The money widgets — portfolio, options, net worth and quotes — drawn from
/// real tables in every appearance, at the size they are added at and at
/// the smallest they may be made, with and without live prices.
const _appearances = ['light', 'dark', 'paper'];

String _day(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final _today = DateTime.now();
final _expiry = DateTime(_today.year, _today.month, _today.day + 5);

ChartTable _table(List<List<String>> rows) => ChartTable.fromRows(
      rows,
      rowIds: [for (var index = 1; index < rows.length; index++) 'row$index'],
    );

final _tables = <String, ChartTable>{
  'holdings': _table([
    ['Name', 'Symbol', 'Sector', 'Qty', 'Avg price', 'LTP', 'Bought on'],
    [
      'Reliance Industries',
      'RELIANCE.NS',
      'Energy',
      '40',
      '1185.5',
      '1167.7',
      '2025-04-01'
    ],
    [
      'HDFC Bank',
      'HDFCBANK.NS',
      'Banking',
      '120',
      '612.4',
      '721.2',
      '2024-10-01'
    ],
    ['Infosys', 'INFY.NS', 'Technology', '60', '1420', '1035', '2025-01-15'],
    [
      'Nifty 50 index fund',
      'NIFTYBEES.NS',
      'Index fund',
      '400',
      '236.8',
      '257.25',
      '2024-04-01'
    ],
  ]),
  'history': _table([
    ['Label', 'Date', 'Value', 'Invested'],
    for (var month = 0; month < 8; month++)
      [
        'M$month',
        _day(DateTime(_today.year, _today.month - 7 + month)),
        '${600000 + month * 21000 + (month.isEven ? 9000 : -6000)}',
        '${590000 + month * 15000}',
      ],
  ]),
  'legs': _table([
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
      'Margin'
    ],
    [
      'NIFTY condor',
      'NIFTY',
      'CE',
      'Sell',
      '22800',
      '65',
      '42.5',
      '31.4',
      '',
      _day(_expiry),
      'Open',
      '110000'
    ],
    [
      'NIFTY condor',
      'NIFTY',
      'CE',
      'Buy',
      '23000',
      '65',
      '16.8',
      '11.2',
      '',
      _day(_expiry),
      'Open',
      ''
    ],
    [
      'NIFTY condor',
      'NIFTY',
      'PE',
      'Sell',
      '22000',
      '65',
      '38.2',
      '29.5',
      '',
      _day(_expiry),
      'Open',
      ''
    ],
    [
      'NIFTY condor',
      'NIFTY',
      'PE',
      'Buy',
      '21800',
      '65',
      '14.6',
      '10.1',
      '',
      _day(_expiry),
      'Open',
      ''
    ],
    [
      'NIFTY straddle',
      'NIFTY',
      'CE',
      'Sell',
      '22500',
      '65',
      '118',
      '',
      '64',
      _day(_expiry),
      'Closed',
      ''
    ],
    [
      'NIFTY straddle',
      'NIFTY',
      'PE',
      'Sell',
      '22500',
      '65',
      '104',
      '',
      '131',
      _day(_expiry),
      'Closed',
      ''
    ],
  ]),
  'journal': _table([
    ['Note', 'Date', 'P&L', 'Capital', 'Deposits'],
    for (var day = 0; day < 14; day++)
      [
        'Day $day',
        _day(DateTime(_today.year, _today.month, _today.day - 20 + day)),
        '${day.isEven ? 2400 + day * 100 : -1300 - day * 50}',
        '${1000000 + day * 900}',
        '1000000',
      ],
  ]),
  'sheet': _table([
    [
      'Name',
      'Type',
      'Category',
      'Value',
      'Invested',
      'Borrowed',
      'Rate %',
      'EMI'
    ],
    ['Gold jewellery', 'Asset', 'Gold', '620000', '410000', '', '', ''],
    ['Apartment', 'Asset', 'Real estate', '9500000', '6200000', '', '', ''],
    ['EPF', 'Asset', 'Provident fund', '1460000', '', '', '8.25', ''],
    ['NPS Tier I', 'Asset', 'NPS', '840000', '620000', '', '', ''],
    ['Savings', 'Asset', 'Cash & bank', '340000', '', '', '3', ''],
    [
      'Home loan',
      'Liability',
      'Home loan',
      '4850000',
      '',
      '6000000',
      '8.5',
      '52068'
    ],
    [
      'Car loan',
      'Liability',
      'Vehicle loan',
      '420000',
      '',
      '800000',
      '9.2',
      '16700'
    ],
  ]),
  'quotes': _table([
    ['Quote', 'Who said it', 'Where from', 'Theme', 'Favourite'],
    [
      'I went to the woods because I wished to live deliberately, to front '
          'only the essential facts of life, and see if I could not learn '
          'what it had to teach, and not, when I came to die, discover that '
          'I had not lived. I did not wish to live what was not life, living '
          'is so dear; nor did I wish to practise resignation, unless it was '
          'quite necessary. I wanted to live deep and suck out all the marrow '
          'of life, to live so sturdily and Spartan-like as to put to rout '
          'all that was not life.',
      'Henry David Thoreau',
      'Walden',
      'Life, Stillness',
      'Yes',
    ],
    [
      'We suffer more often in imagination than in reality.',
      'Seneca',
      'Letters',
      'Courage',
      'No'
    ],
    ['Simplify, simplify.', 'Thoreau', 'Walden', 'Stillness', 'No'],
    [
      'Well done is better than well said.',
      'Benjamin Franklin',
      '',
      'Work',
      'No'
    ],
  ]),
};

/// Every money widget, with the table it reads.
const _cases = <(String, String)>[
  ('portfolio', 'holdings'),
  ('holdings', 'holdings'),
  ('heatmap', 'holdings'),
  ('watchlist', ''),
  ('trend', 'history'),
  ('allocation', 'holdings'),
  ('pnl_calendar', 'journal'),
  ('pnl_stats', 'journal'),
  ('options_summary', 'legs'),
  ('options_book', 'legs'),
  ('options_payoff', 'legs'),
  ('option_chain', 'legs'),
  ('net_worth', 'sheet'),
  ('balance_sheet', 'sheet'),
  ('loans', 'sheet'),
  ('quote_spotlight', 'quotes'),
  ('quote_wall', 'quotes'),
];

/// A dashboard of twelve columns on a wide screen.
Size _cells(int columns, int rows) =>
    Size(columns * 87.0 + (columns - 1) * 14, rows * 46.0 + (rows - 1) * 14);

class _Lease implements MarketLease {
  @override
  void want({
    required Set<String> symbols,
    required Set<ChainRequest> chains,
  }) {}

  @override
  void release() {}
}

class _FakeMarket extends ChangeNotifier implements MarketDataProvider {
  _FakeMarket() {
    final now = DateTime.now();
    for (final (symbol, price, close) in [
      ('^NSEI', 22421.95, 22620.45),
      ('^NSEBANK', 54450.75, 54633.05),
      ('^BSESN', 71909.7, 72480.29),
      ('GC=F', 4162.3, 4202.3),
      ('INR=X', 96.3, 96.31),
      ('RELIANCE.NS', 1167.7, 1187.0),
      ('HDFCBANK.NS', 721.2, 708.7),
      ('INFY.NS', 1035.0, 994.1),
    ]) {
      _quotes[symbol] = MarketQuote(
        symbol: symbol,
        price: price,
        previousClose: close,
        closes: [
          for (var day = 0; day < 20; day++) close * (1 + (day % 5 - 2) / 100)
        ],
        updatedAt: now,
      );
    }
  }

  final _quotes = <String, MarketQuote>{};

  late final OptionChain _chain = OptionChain(
    underlying: 'NIFTY',
    expiry: DateTime(_expiry.year, _expiry.month, _expiry.day),
    spot: 22421.95,
    fetchedAt: DateTime.now(),
    expiries: [DateTime(_expiry.year, _expiry.month, _expiry.day)],
    totalCallOpenInterest: 25000,
    totalPutOpenInterest: 27000,
    maxPain: 22400,
    rows: [
      for (var strike = 21600.0; strike <= 23200; strike += 100)
        OptionChainRow(
          strike: strike,
          call: OptionQuote(
            lastPrice: (22421.95 - strike).clamp(0, 1e9).toDouble() + 25,
            change: -2.5,
            openInterest: 1000 + (strike - 21600) * 3,
            openInterestChange: 120,
            impliedVolatility: 13.5,
          ),
          put: OptionQuote(
            lastPrice: (strike - 22421.95).clamp(0, 1e9).toDouble() + 22,
            change: 1.5,
            openInterest: 6000 - (strike - 21600) * 2,
            openInterestChange: -80,
            impliedVolatility: 14.2,
          ),
        ),
    ],
  );

  @override
  MarketQuote? quote(String symbol) => _quotes[symbol.toUpperCase()];

  @override
  bool isFetching(String symbol) => false;

  @override
  MarketLease lease() => _Lease();

  @override
  Future<void> refresh({bool force = false}) async {}

  @override
  Future<List<MarketSymbol>> search(String query) async => const [];

  @override
  bool supportsChain(String underlying) => underlying != 'SENSEX';

  @override
  OptionChain? chain(ChainRequest request) =>
      request.underlying == 'NIFTY' ? _chain : null;

  @override
  bool isFetchingChain(ChainRequest request) => false;

  @override
  String? chainError(ChainRequest request) => null;

  @override
  List<DateTime> expiries(String underlying) => _chain.expiries;
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      '',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

DashboardWidgetSpec _spec(String type, String table) {
  final spec = DashboardWidgetRegistry.definitionFor(type)!.create();
  return table.isEmpty
      ? spec
      : spec.copyWith(
          source: DashboardDataSource(
            kind: DashboardSourceKind.database,
            viewId: table,
            name: table,
          ),
        );
}

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  DashboardWidgetSpec spec,
  Size size,
) async {
  final theme = _theme(appearance);
  final controller = DashboardController(
    viewId: '',
    document: DashboardDocument(
      sections: [
        DashboardSection(id: 'section', widgets: [spec])
      ],
    ),
    mode: DashboardMode.focus,
    persistDebounce: const Duration(days: 1),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: theme,
          themeAnimationDuration: Duration.zero,
          builder: (context, navigator) => AppFlowyTheme(
            data: PremiumTheme.appFlowyTheme(
              base: appearance == 'dark'
                  ? AppFlowyDefaultTheme().dark()
                  : AppFlowyDefaultTheme().light(),
              palette: theme.extension<PremiumThemeExtension>()!,
              brightness: theme.brightness,
            ),
            child: TooltipVisibility(visible: false, child: navigator!),
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: Builder(
                  builder: (context) => DashboardCard(
                    controller: controller,
                    spec: spec,
                    palette: DashboardPalette.of(context),
                    selected: false,
                    dragging: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Live dots breathe for as long as prices are live, so the animations are
  // run to their end rather than waited out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late _FakeMarket market;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    financeTableLoader = (viewId) async => _tables[viewId] ?? ChartTable.empty;
  });

  tearDownAll(() => financeTableLoader = null);

  setUp(() => market = _FakeMarket());

  tearDown(() => MarketData.detach(market));

  for (final live in [true, false]) {
    testWidgets(
      'every money widget fits its default and smallest size '
      '${live ? 'with' : 'without'} live prices',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1400, 1100);
        addTearDown(tester.view.reset);
        if (live) {
          MarketData.attach(market);
        }
        // Every failure is gathered with where it came from, so one run
        // shows them all instead of stopping at the first.
        final failures = <String>[];
        var current = '';
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          final location = RegExp(r'lib/[\w/]+\.dart:\d+:\d+')
              .firstMatch(details.toString())
              ?.group(0);
          failures.add(
            '$current: ${details.exceptionAsString().split('\n').first}'
            ' at ${location ?? 'unknown'}',
          );
        };
        try {
          for (final (type, table) in _cases) {
            final definition = DashboardWidgetRegistry.definitionFor(type);
            expect(definition, isNotNull, reason: type);
            expect(
              definition!.group,
              anyOf(DashboardWidgetGroup.money, DashboardWidgetGroup.text),
            );
            final sizes = {
              _cells(definition.defaultColumnSpan, definition.defaultRowSpan),
              _cells(definition.minimumColumnSpan, definition.minimumRowSpan),
            };
            for (final appearance in _appearances) {
              for (final size in sizes) {
                current = '$type in $appearance at '
                    '${size.width.round()}x${size.height.round()}';
                await _mount(tester, appearance, _spec(type, table), size);
                await _unmount(tester);
              }
            }
          }
        } finally {
          FlutterError.onError = original;
        }
        expect(failures, isEmpty, reason: failures.toSet().join('\n'));
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }

  testWidgets('a holding opens to show what went into it', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(tester.view.reset);
    MarketData.attach(market);
    await _mount(tester, 'light', _spec('holdings', 'holdings'), _cells(8, 9));
    expect(find.text('Reliance Industries'), findsOneWidget);
    expect(find.text(LocaleKeys.dashboard_money_invested.tr()), findsNothing);
    await tester.tap(find.text('Reliance Industries'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(LocaleKeys.dashboard_money_invested.tr()), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the quote wall filters by what is typed', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(tester.view.reset);
    await _mount(
        tester, 'paper', _spec('quote_wall', 'quotes'), _cells(12, 12));
    expect(find.text('Seneca'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'simplify');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Seneca'), findsNothing);
    expect(find.text('Simplify, simplify.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the spotlight steps through the quotes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(tester.view.reset);
    await _mount(
      tester,
      'dark',
      _spec('quote_spotlight', 'quotes'),
      _cells(8, 7),
    );
    const authors = [
      'Henry David Thoreau',
      'Seneca',
      'Thoreau',
      'Benjamin Franklin'
    ];
    String shown() => authors.firstWhere(
          (author) => find.text(author).evaluate().isNotEmpty,
        );
    final before = shown();
    await tester.tap(
      find.byTooltip(LocaleKeys.dashboard_money_nextQuote.tr()),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(shown(), isNot(before));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the option chain marks the spot and reads the totals',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(tester.view.reset);
    MarketData.attach(market);
    await _mount(
        tester, 'light', _spec('option_chain', 'legs'), _cells(12, 10));
    expect(
      find.textContaining(LocaleKeys.dashboard_money_spot.tr()),
      findsWidgets,
    );
    expect(find.textContaining('1.08', findRichText: true), findsOneWidget);
    expect(find.text('22,800'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('without the extension the chain says where prices come from',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(tester.view.reset);
    await _mount(
        tester, 'light', _spec('option_chain', 'legs'), _cells(12, 10));
    expect(
      find.text(LocaleKeys.dashboard_money_chainNeedsExtension.tr()),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('a balance sheet is split by category, in paper colours too',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(tester.view.reset);
    await _mount(tester, 'paper', _spec('allocation', 'sheet'), _cells(6, 7));
    expect(
      find.text(LocaleKeys.dashboard_money_categoryRealEstate.tr()),
      findsOneWidget,
    );
    final context = tester.element(find.byType(DashboardCard));
    final palette = DashboardPalette.of(context);
    expect(palette.isPaper, isTrue);
    expect(FinanceColors.of(palette).gain, const Color(0xFF3F8F5A));
    await _unmount(tester);
  });
}
