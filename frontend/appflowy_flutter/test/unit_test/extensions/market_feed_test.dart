import 'dart:convert';

import 'package:appflowy/extensions/dart/built_in/market_feed.dart';
import 'package:appflowy/shared/market/market_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The shape the quote service's batch endpoint answers with (recorded
/// 2026-10-04): a month of daily closes, the last one null on a holiday.
const _spark = '''
{
  "^NSEI": {"timestamp": [1790653500, 1790739900, 1790826300], "symbol": "^NSEI",
    "previousClose": null, "chartPreviousClose": 22900.0, "fulldayChange": -198.5,
    "fulldayChangePercent": -0.878, "fulldayPrice": 22421.95, "dataGranularity": 300,
    "close": [22700.1, 22620.45, 22421.95, null], "start": null, "end": null},
  "INFY.NS": {"timestamp": [], "symbol": "INFY.NS", "previousClose": 994.1,
    "chartPreviousClose": 994.1, "fulldayChange": 40.9, "fulldayChangePercent": 4.114,
    "fulldayPrice": 1035.0, "close": null}
}
''';

Map<String, Object?> _chainJson({
  String expiry = '06-Oct-2026',
  double spot = 22421.95,
}) {
  Map<String, Object?> side(double strike, double oi, double price) => {
        'strikePrice': strike,
        'expiryDate': '06-10-2026',
        'lastPrice': price,
        'change': -2.5,
        'openInterest': oi,
        'changeinOpenInterest': oi / 10,
        'impliedVolatility': 13.2,
        'totalTradedVolume': oi * 4,
        'buyPrice1': price - 0.1,
        'sellPrice1': price + 0.1,
        'pChange': -1.0,
        'PChange': -1.0,
      };
  return {
    'records': {
      'timestamp': '01-Oct-2026 15:40:00',
      'underlyingValue': spot,
      'expiryDates': ['06-Oct-2026', '13-Oct-2026'],
      'data': [
        for (final (strike, callInterest, putInterest) in [
          (22200.0, 1000.0, 9000.0),
          (22300.0, 2000.0, 7000.0),
          (22400.0, 5000.0, 5000.0),
          (22500.0, 8000.0, 2000.0),
          (22600.0, 9000.0, 1000.0),
        ])
          {
            'strikePrice': strike,
            'expiryDates': expiry,
            'CE': side(strike, callInterest, 120 - (strike - 22200) / 5),
            'PE': side(strike, putInterest, 20 + (strike - 22200) / 5),
          },
        {
          'strikePrice': 22400.0,
          'expiryDates': '13-Oct-2026',
          'CE': side(22400, 99999, 999),
        },
      ],
    },
  };
}

class _FakeExchange extends NseSession {
  final requests = <String>[];

  @override
  Future<Object?> getJson(String path, Map<String, String> query) async {
    requests.add('$path?${Uri(queryParameters: query).query}');
    if (path.endsWith('contract-info')) {
      return {
        'expiryDates': ['06-Oct-2026', '13-Oct-2026', '27-Oct-2026'],
      };
    }
    return _chainJson(expiry: query['expiry'] ?? '06-Oct-2026');
  }

  @override
  void close() {}
}

void main() {
  group('reading the quote service', () {
    test('takes the full day price, the change and the closes', () {
      final quotes = parseSparkQuotes(_spark, now: DateTime(2026, 10, 4));
      expect(quotes.keys, containsAll(['^NSEI', 'INFY.NS']));
      final nifty = quotes['^NSEI']!;
      expect(nifty.price, 22421.95);
      expect(nifty.previousClose, closeTo(22620.45, 1e-9));
      expect(nifty.closes, [22700.1, 22620.45, 22421.95]);
      expect(nifty.changePercent, closeTo(-0.8775, 1e-3));
      final infosys = quotes['INFY.NS']!;
      expect(infosys.previousClose, 994.1);
      expect(infosys.closes, isEmpty);
    });

    test('reports the service turning a request away', () {
      expect(
        () => parseSparkQuotes(
          '{"spark":{"result":null,"error":{"code":"Bad Request",'
          '"description":"Number of symbols needs to be less than or equal to 20"}}}',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('round-trips a quote through storage', () {
      final quote = parseSparkQuotes(_spark)['^NSEI']!;
      final restored = MarketQuote.fromJson(
        jsonDecode(jsonEncode(quote.toJson())),
      )!;
      expect(restored.price, quote.price);
      expect(restored.previousClose, quote.previousClose);
      expect(restored.closes, quote.closes);
    });
  });

  group('reading the exchange', () {
    test('reads its dates and writes them back', () {
      expect(parseNseDate('06-Oct-2026'), DateTime(2026, 10, 6));
      expect(parseNseDate('06-10-2026'), DateTime(2026, 10, 6));
      expect(
        parseNseDate('01-Oct-2026 15:40:00')!.toUtc(),
        DateTime.utc(2026, 10, 1, 10, 10),
      );
      expect(parseNseDate('nonsense'), isNull);
      expect(formatNseDate(DateTime(2026, 10, 6)), '06-Oct-2026');
      expect(
        parseNseExpiries({
          'expiryDates': ['13-Oct-2026', '06-Oct-2026', 'bad'],
        }),
        [DateTime(2026, 10, 6), DateTime(2026, 10, 13)],
      );
    });

    test('reads one expiry of a chain with its totals', () {
      final chain = parseNseChain(
        _chainJson(),
        underlying: 'NIFTY',
        expiry: DateTime(2026, 10, 6),
      );
      expect(chain.rows.map((row) => row.strike), [
        22200,
        22300,
        22400,
        22500,
        22600,
      ]);
      // The other expiry's row is left out of the totals.
      expect(chain.totalCallOpenInterest, 25000);
      expect(chain.totalPutOpenInterest, 24000);
      expect(chain.putCallRatio, closeTo(0.96, 1e-9));
      expect(chain.spot, 22421.95);
      expect(chain.atmIndex, 2);
      expect(chain.maxPain, 22400);
      expect(chain.quoteAt(22400, call: true)?.impliedVolatility, 13.2);
      expect(chain.expiries, [DateTime(2026, 10, 6), DateTime(2026, 10, 13)]);
      expect(chain.timestamp, isNotNull);
    });

    test('keeps only the strikes around the money', () {
      final chain = parseNseChain(
        _chainJson(),
        underlying: 'NIFTY',
        expiry: DateTime(2026, 10, 6),
        around: 1,
      );
      expect(chain.rows.map((row) => row.strike), [22300, 22400, 22500]);
      // Totals still count every strike.
      expect(chain.totalCallOpenInterest, 25000);
    });

    test('refuses an empty answer', () {
      expect(
        () => parseNseChain(
          {
            'records': {'data': []}
          },
          underlying: 'NIFTY',
          expiry: DateTime(2026, 10, 6),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('the live market', () {
    late List<Uri> requests;
    late StockMarketProvider provider;
    late _FakeExchange exchange;
    late DateTime now;

    setUp(() {
      requests = [];
      now = DateTime(2026, 10, 4, 10);
      exchange = _FakeExchange();
      provider = StockMarketProvider(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(_spark, 200);
        }),
        exchange: exchange,
        clock: () => now,
      );
    });

    tearDown(() => provider.dispose());

    test('fetches only what a lease wants, in one batch', () async {
      final lease = provider.lease()
        ..want(symbols: {'^nsei', 'INFY.NS', 'NOPE.NS'}, chains: const {});
      await provider.refresh();
      expect(requests.length, 1);
      expect(requests.single.queryParameters['range'], '1mo');
      expect(
        requests.single.queryParameters['symbols']!.split(',').toSet(),
        {'^NSEI', 'INFY.NS', 'NOPE.NS'},
      );
      expect(provider.quote('^NSEI')?.price, 22421.95);
      expect(provider.quote('nope.ns')?.error, isNotNull);
      expect(provider.quote('NOPE.NS')?.hasPrice, isFalse);

      // Fresh quotes are not fetched again; a forced refresh is.
      await provider.refresh();
      expect(requests.length, 1);
      await provider.refresh(force: true);
      expect(requests.length, 2);

      lease.release();
      await provider.refresh(force: true);
      expect(requests.length, 2);
    });

    test('fetches again on every one-minute job', () async {
      provider.lease().want(symbols: {'^NSEI'}, chains: const {});
      await provider.refresh();
      expect(requests, hasLength(1));
      now = now.add(const Duration(seconds: 30));
      await provider.refresh();
      expect(requests, hasLength(1));
      // Jobs a minute apart can read a little under a minute apart on the
      // clock, since a fetch is stamped when it starts; the next job counts.
      now = now.add(const Duration(seconds: 29, milliseconds: 900));
      await provider.refresh();
      expect(requests, hasLength(2));
    });

    test('reads a chain for the nearest expiry, then a chosen one', () async {
      provider.lease().want(
        symbols: const {},
        chains: {
          ChainRequest('nifty'),
          ChainRequest('NIFTY', DateTime(2026, 10, 13))
        },
      );
      await provider.refresh();
      final nearest = provider.chain(ChainRequest('NIFTY'));
      expect(nearest?.expiry, DateTime(2026, 10, 6));
      expect(nearest?.rows, isNotEmpty);
      final chosen =
          provider.chain(ChainRequest('NIFTY', DateTime(2026, 10, 13)));
      expect(chosen?.expiry, DateTime(2026, 10, 13));
      expect(provider.expiries('NIFTY').length, 3);
      // The expiry list is read once and reused.
      expect(
        exchange.requests.where((request) => request.contains('contract-info')),
        hasLength(1),
      );
    });

    test('says why a chain could not be read', () async {
      final request = ChainRequest('NIFTY', DateTime(2026, 10, 7));
      provider.lease().want(symbols: const {}, chains: {request});
      await provider.refresh();
      expect(provider.chain(request), isNull);
      expect(provider.chainError(request), isNotNull);
      expect(provider.supportsChain('SENSEX'), isFalse);
      expect(provider.supportsChain('^NSEI'), isFalse);
      expect(provider.supportsChain('RELIANCE'), isTrue);
    });

    test('is what widgets see while it is attached', () async {
      final watch = MarketWatch();
      addTearDown(watch.dispose);
      expect(watch.isLive, isFalse);
      MarketData.attach(provider);
      addTearDown(() => MarketData.detach(provider));
      expect(watch.isLive, isTrue);
      watch.want(symbols: {'^NSEI'});
      await provider.refresh();
      expect(watch.quote('^nsei')?.price, 22421.95);
      MarketData.detach(provider);
      expect(watch.isLive, isFalse);
      expect(watch.quote('^NSEI'), isNull);
    });
  });

  test('names symbols the way people know them', () {
    expect(marketSymbolForUnderlying('nifty'), '^NSEI');
    expect(marketSymbolForUnderlying('RELIANCE'), 'RELIANCE.NS');
    expect(marketDisplayName('^NSEBANK'), 'BANK NIFTY');
    expect(marketDisplayName('RELIANCE.NS'), 'RELIANCE');
    expect(marketCurrencySymbol('RELIANCE.NS'), '₹');
    expect(marketCurrencySymbol('^NSEI'), '');
    expect(marketCurrencySymbol('AAPL'), r'$');
    expect(chainUnderlyingFor('^NSEI'), 'NIFTY');
    expect(chainUnderlyingFor('INFY.NS'), 'INFY');
  });
}
