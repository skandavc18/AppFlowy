import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy/extensions/dart/built_in/stock_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/shared/market/market_data.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Live prices for dashboards while the Stocks extension is on.
///
/// Quotes come from the same service the stock block reads, many symbols to
/// a request; option chains come from the exchange itself. Nothing is
/// fetched that no widget currently wants, and a widget's want lapses the
/// moment it is gone.
///
/// The last known quotes are kept in `af.data` so a dashboard opens with
/// yesterday's prices instead of blanks while today's are fetched. Chains
/// are a quarter of a megabyte each and stale within a minute, so they stay
/// in memory only.
class StockMarketProvider extends ChangeNotifier implements MarketDataProvider {
  StockMarketProvider({
    DartExtensionContext? context,
    http.Client? client,
    NseSession? exchange,
    Future<List<MarketSymbol>> Function(String query)? search,
    DateTime Function()? clock,
  })  : _context = context,
        _client = client ?? http.Client(),
        _exchange = exchange ?? NseSession(),
        _search = search,
        _clock = clock ?? DateTime.now {
    _restore();
  }

  static const jobInterval = Duration(minutes: 1);

  /// A quote this old is fetched again on the next minute's job. Exchange
  /// data is published about once a minute, so asking more often only adds
  /// load; the margin under a minute absorbs timer jitter, which would
  /// otherwise skip every other job.
  static const quoteFreshness = Duration(seconds: 55);
  static const chainFreshness = Duration(seconds: 55);
  static const expiryFreshness = Duration(hours: 6);

  /// The last known quotes are kept for the next start, not as a live
  /// record, so writing them every minute would be wasted disk.
  static const persistEvery = Duration(minutes: 10);

  /// The quote service refuses more than twenty symbols at once.
  static const batchSize = 15;
  static const snapshotKey = 'market.quotes';
  static const requestTimeout = Duration(seconds: 20);
  static const maximumResponseBytes = 2 * 1024 * 1024;

  static const _sparkEndpoint =
      'https://query1.finance.yahoo.com/v8/finance/spark';

  final DartExtensionContext? _context;
  final http.Client _client;
  final NseSession _exchange;
  final Future<List<MarketSymbol>> Function(String query)? _search;
  final DateTime Function() _clock;

  final Map<String, MarketQuote> _quotes = {};
  final Map<String, DateTime> _attempted = {};
  final Set<String> _fetching = {};
  final Set<_Lease> _leases = {};

  final Map<ChainRequest, OptionChain> _chains = {};
  final Map<ChainRequest, DateTime> _chainAttempted = {};
  final Set<ChainRequest> _chainFetching = {};
  final Map<ChainRequest, String> _chainErrors = {};
  final Map<String, List<DateTime>> _expiries = {};
  final Map<String, DateTime> _expiriesFetchedAt = {};

  late final MarketDebounce _soon = MarketDebounce(
    const Duration(milliseconds: 250),
    () => refresh(),
  );
  DateTime? _persistedAt;
  bool _disposed = false;

  void _restore() {
    final stored = _context?.data.read(snapshotKey);
    if (stored is! Map) {
      return;
    }
    for (final value in stored.values) {
      final quote = MarketQuote.fromJson(value);
      if (quote != null && quote.hasPrice) {
        _quotes[quote.symbol] = quote;
      }
    }
  }

  Set<String> get _wantedSymbols => {
        for (final lease in _leases) ...lease.symbols,
      };

  Set<ChainRequest> get _wantedChains => {
        for (final lease in _leases) ...lease.chains,
      };

  @override
  MarketQuote? quote(String symbol) => _quotes[symbol.trim().toUpperCase()];

  @override
  bool isFetching(String symbol) =>
      _fetching.contains(symbol.trim().toUpperCase());

  @override
  MarketLease lease() {
    final lease = _Lease(this);
    _leases.add(lease);
    return lease;
  }

  void _leaseChanged() {
    if (!_disposed) {
      _soon.schedule();
    }
  }

  @override
  Future<void> refresh({bool force = false}) async {
    if (_disposed) {
      return;
    }
    await Future.wait([
      _refreshQuotes(force),
      _refreshChains(force),
    ]);
  }

  bool _quoteIsStale(String symbol, DateTime now) {
    final attempted = _attempted[symbol];
    return attempted == null || now.difference(attempted) >= quoteFreshness;
  }

  Future<void> _refreshQuotes(bool force) async {
    final now = _clock();
    final due = [
      for (final symbol in _wantedSymbols)
        if (!_fetching.contains(symbol) &&
            (force || _quoteIsStale(symbol, now)))
          symbol,
    ];
    if (due.isEmpty) {
      return;
    }
    _fetching.addAll(due);
    _notify();
    var changed = false;
    try {
      for (var start = 0; start < due.length; start += batchSize) {
        final batch =
            due.sublist(start, math.min(start + batchSize, due.length));
        for (final symbol in batch) {
          _attempted[symbol] = now;
        }
        try {
          final body = await _get(
            Uri.parse(
              '$_sparkEndpoint?symbols='
              '${batch.map(Uri.encodeComponent).join(',')}'
              '&range=1mo&interval=1d',
            ),
          );
          final quotes = parseSparkQuotes(body, now: _clock());
          for (final symbol in batch) {
            final quote = quotes[symbol];
            if (quote != null && quote.hasPrice) {
              _quotes[symbol] = quote;
              changed = true;
            } else if (!(_quotes[symbol]?.hasPrice ?? false)) {
              // Nothing known and nothing found: say so, so a card can tell
              // a mistyped symbol from a slow network.
              _quotes[symbol] = MarketQuote(
                symbol: symbol,
                error: 'not-found',
                updatedAt: now,
              );
            }
          }
        } on Object catch (error) {
          Log.warn('Could not fetch quotes for ${batch.join(', ')}: $error');
        }
        if (_disposed) {
          return;
        }
      }
    } finally {
      _fetching.removeAll(due);
      _notify();
    }
    if (changed) {
      _persist();
    }
  }

  void _persist() {
    final context = _context;
    if (context == null || _disposed) {
      return;
    }
    final now = _clock();
    final last = _persistedAt;
    if (last != null && now.difference(last) < persistEvery) {
      return;
    }
    _persistedAt = now;
    final snapshot = <String, Object?>{
      for (final quote in _quotes.values)
        if (quote.hasPrice) quote.symbol: quote.toJson(),
    };
    unawaited(context.data.write(snapshotKey, snapshot));
  }

  Future<String> _get(Uri uri) async {
    // Quote services routinely refuse a request with no user agent.
    final response = await _client.get(
      uri,
      headers: const {'User-Agent': 'AppFlowy', 'Accept': 'application/json'},
    ).timeout(requestTimeout);
    if (response.statusCode != 200) {
      throw StateError('The quote service answered ${response.statusCode}.');
    }
    if (response.bodyBytes.length > maximumResponseBytes) {
      throw StateError('The quote service sent more than 2 MB.');
    }
    return response.body;
  }

  @override
  Future<List<MarketSymbol>> search(String query) async {
    final search = _search;
    if (search == null || query.trim().length < 2) {
      return const [];
    }
    try {
      return await search(query);
    } on Object {
      return const [];
    }
  }

  // ------------------------------------------------------------ the chains

  @override
  bool supportsChain(String underlying) {
    final name = underlying.trim().toUpperCase();
    if (name.isEmpty ||
        name.startsWith('^') ||
        name.contains('=') ||
        name == 'SENSEX' ||
        name == 'BANKEX') {
      return false;
    }
    return !name.contains('.') || name.endsWith('.NS');
  }

  @override
  OptionChain? chain(ChainRequest request) => _chains[request];

  @override
  bool isFetchingChain(ChainRequest request) =>
      _chainFetching.contains(request);

  @override
  String? chainError(ChainRequest request) => _chainErrors[request];

  @override
  List<DateTime> expiries(String underlying) =>
      _expiries[underlying.trim().toUpperCase()] ?? const [];

  Future<void> _refreshChains(bool force) async {
    for (final request in _wantedChains) {
      if (_disposed) {
        return;
      }
      if (!supportsChain(request.underlying) ||
          _chainFetching.contains(request)) {
        continue;
      }
      final now = _clock();
      final last = _chainAttempted[request];
      if (!force && last != null && now.difference(last) < chainFreshness) {
        continue;
      }
      _chainFetching.add(request);
      _chainAttempted[request] = now;
      _notify();
      try {
        _chains[request] = await _fetchChain(request);
        _chainErrors.remove(request);
      } on Object catch (error) {
        _chainErrors[request] = '$error';
        Log.warn('Could not fetch the option chain $request: $error');
      } finally {
        _chainFetching.remove(request);
        _notify();
      }
    }
  }

  Future<OptionChain> _fetchChain(ChainRequest request) async {
    final underlying = chainUnderlyingFor(request.underlying);
    final now = _clock();
    final cached = _expiries[underlying];
    final fetchedAt = _expiriesFetchedAt[underlying];
    final List<DateTime> expiries;
    if (cached == null ||
        fetchedAt == null ||
        now.difference(fetchedAt) > expiryFreshness ||
        (cached.isNotEmpty && _dayOf(cached.first).isBefore(_dayOf(now)))) {
      expiries = parseNseExpiries(
        await _exchange.getJson(
          '/api/option-chain-contract-info',
          {'symbol': underlying},
        ),
      );
      _expiries[underlying] = expiries;
      _expiriesFetchedAt[underlying] = now;
    } else {
      expiries = cached;
    }
    if (expiries.isEmpty) {
      throw StateError('The exchange lists no option expiries.');
    }
    final today = _dayOf(now);
    final wanted = request.expiry;
    final DateTime expiry;
    if (wanted == null) {
      expiry = expiries.firstWhere(
        (date) => !date.isBefore(today),
        orElse: () => expiries.last,
      );
    } else if (expiries.contains(wanted)) {
      expiry = wanted;
    } else {
      throw StateError('No contracts expire on that day.');
    }
    final json = await _exchange.getJson('/api/option-chain-v3', {
      'type': isIndexUnderlying(underlying) ? 'Indices' : 'Equity',
      'symbol': underlying,
      'expiry': formatNseDate(expiry),
    });
    return parseNseChain(
      json,
      underlying: underlying,
      expiry: expiry,
      expiries: expiries,
      fetchedAt: _clock(),
    );
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _soon.cancel();
    _leases.clear();
    _exchange.close();
    _client.close();
    super.dispose();
  }
}

class _Lease implements MarketLease {
  _Lease(this._owner);

  final StockMarketProvider _owner;
  Set<String> symbols = const {};
  Set<ChainRequest> chains = const {};
  bool _released = false;

  @override
  void want({
    required Set<String> symbols,
    required Set<ChainRequest> chains,
  }) {
    if (_released) {
      return;
    }
    this.symbols = {
      for (final symbol in symbols) symbol.trim().toUpperCase(),
    };
    this.chains = Set.of(chains);
    _owner._leaseChanged();
  }

  @override
  void release() {
    _released = true;
    _owner._leases.remove(this);
  }
}

DateTime _dayOf(DateTime time) => DateTime(time.year, time.month, time.day);

/// The search the stock block already uses, offered as market listings.
Future<List<MarketSymbol>> searchWithStockFeed(String query) async {
  final feed = StockFeed.active;
  if (feed == null) {
    return const [];
  }
  final matches = await feed.search(query);
  return [
    for (final match in matches)
      MarketSymbol(
        symbol: match.symbol,
        name: match.name,
        exchange: match.exchange,
        kind: match.kind,
      ),
  ];
}

// ------------------------------------------------------------- the parsing

/// Reads the quote service's batch answer: one entry per symbol it knows,
/// each with the full day's price and change and a month of daily closes.
/// Symbols it does not know are simply absent.
@visibleForTesting
Map<String, MarketQuote> parseSparkQuotes(String body, {DateTime? now}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw StateError('The quote service sent something unreadable.');
  }
  final failure = decoded['spark'];
  if (failure is Map && failure['error'] is Map) {
    final error = failure['error'] as Map;
    throw StateError('${error['description'] ?? error['code']}');
  }
  final quotes = <String, MarketQuote>{};
  for (final entry in decoded.entries) {
    final value = entry.value;
    if (value is! Map) {
      continue;
    }
    final symbol = '${value['symbol'] ?? entry.key}'.toUpperCase();
    final rawCloses = value['close'];
    final closes = <double>[
      if (rawCloses is List)
        for (final close in rawCloses)
          if (close is num && close.isFinite && close > 0) close.toDouble(),
    ];
    final fullDay = _finite(value['fulldayPrice']);
    final price = fullDay ?? (closes.isEmpty ? null : closes.last);
    if (price == null) {
      continue;
    }
    final change = _finite(value['fulldayChange']);
    final previous = _finite(value['previousClose']) ??
        (change != null ? price - change : null);
    quotes[symbol] = MarketQuote(
      symbol: symbol,
      price: price,
      previousClose: previous,
      closes: closes,
      updatedAt: now ?? DateTime.now(),
    );
  }
  return quotes;
}

double? _finite(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    final parsed = double.tryParse(value.replaceAll(',', ''));
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// The exchange writes days as `06-Oct-2026`, and inside a contract as
/// `06-10-2026`.
@visibleForTesting
DateTime? parseNseDate(String text) {
  final match = RegExp(r'^(\d{1,2})-([A-Za-z]{3}|\d{1,2})-(\d{4})')
      .firstMatch(text.trim());
  if (match == null) {
    return null;
  }
  final day = int.parse(match.group(1)!);
  final monthText = match.group(2)!;
  final month =
      int.tryParse(monthText) ?? (_months.indexOf(monthText.toLowerCase()) + 1);
  final year = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final time = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?')
      .firstMatch(text.substring(match.end));
  if (time == null) {
    return DateTime(year, month, day);
  }
  // Exchange times are Indian Standard Time.
  return DateTime.utc(
    year,
    month,
    day,
    int.parse(time.group(1)!),
    int.parse(time.group(2)!),
    int.tryParse(time.group(3) ?? '') ?? 0,
  ).subtract(const Duration(hours: 5, minutes: 30)).toLocal();
}

@visibleForTesting
String formatNseDate(DateTime day) {
  final month = _months[day.month - 1];
  return '${day.day.toString().padLeft(2, '0')}-'
      '${month[0].toUpperCase()}${month.substring(1)}-${day.year}';
}

/// The expiries the contract list names, nearest first.
@visibleForTesting
List<DateTime> parseNseExpiries(Object? json) {
  if (json is! Map) {
    return const [];
  }
  final dates = json['expiryDates'] ??
      (json['records'] is Map ? (json['records'] as Map)['expiryDates'] : null);
  if (dates is! List) {
    return const [];
  }
  final parsed = <DateTime>{
    for (final date in dates)
      if (date is String && parseNseDate(date) != null) parseNseDate(date)!,
  }.toList()
    ..sort();
  return parsed;
}

/// Reads one expiry's chain, keeping [around] strikes either side of the
/// money. Totals, the put-call ratio and max pain are worked out over every
/// strike first, so trimming does not change them.
@visibleForTesting
OptionChain parseNseChain(
  Object? json, {
  required String underlying,
  required DateTime expiry,
  List<DateTime> expiries = const [],
  DateTime? fetchedAt,
  int around = 30,
}) {
  if (json is! Map || json['records'] is! Map) {
    throw StateError('The exchange sent no option chain.');
  }
  final records = json['records'] as Map;
  final data = records['data'];
  if (data is! List || data.isEmpty) {
    throw StateError('The exchange sent an empty option chain.');
  }
  final spot = _finite(records['underlyingValue']);
  final wanted = DateTime(expiry.year, expiry.month, expiry.day);
  final byStrike = <double, (OptionQuote?, OptionQuote?)>{};
  for (final row in data) {
    if (row is! Map) {
      continue;
    }
    final strike = _finite(row['strikePrice']);
    if (strike == null) {
      continue;
    }
    final rowExpiry = row['expiryDate'] ?? row['expiryDates'];
    if (rowExpiry is String) {
      final date = parseNseDate(rowExpiry);
      if (date != null && date != wanted) {
        continue;
      }
    }
    final call = _optionQuote(row['CE']);
    final put = _optionQuote(row['PE']);
    if (call == null && put == null) {
      continue;
    }
    final existing = byStrike[strike];
    byStrike[strike] = (call ?? existing?.$1, put ?? existing?.$2);
  }
  if (byStrike.isEmpty) {
    throw StateError('The exchange sent no strikes for that expiry.');
  }
  final strikes = byStrike.keys.toList()..sort();
  var callInterest = 0.0;
  var putInterest = 0.0;
  for (final strike in strikes) {
    callInterest += byStrike[strike]!.$1?.openInterest ?? 0;
    putInterest += byStrike[strike]!.$2?.openInterest ?? 0;
  }

  double? maxPain;
  var leastPain = double.infinity;
  for (final settle in strikes) {
    var pain = 0.0;
    for (final strike in strikes) {
      final (call, put) = byStrike[strike]!;
      pain += (call?.openInterest ?? 0) * math.max(0, settle - strike);
      pain += (put?.openInterest ?? 0) * math.max(0, strike - settle);
    }
    if (pain < leastPain) {
      leastPain = pain;
      maxPain = settle;
    }
  }

  var centre = strikes.length ~/ 2;
  if (spot != null) {
    for (var index = 0; index < strikes.length; index++) {
      if ((strikes[index] - spot).abs() < (strikes[centre] - spot).abs()) {
        centre = index;
      }
    }
  }
  final first = math.max(0, centre - around);
  final last = math.min(strikes.length, centre + around + 1);
  final timestamp = records['timestamp'];

  return OptionChain(
    underlying: underlying,
    expiry: wanted,
    spot: spot,
    timestamp: timestamp is String ? parseNseDate(timestamp) : null,
    expiries: expiries.isNotEmpty ? expiries : parseNseExpiries(json),
    rows: [
      for (final strike in strikes.sublist(first, last))
        OptionChainRow(
          strike: strike,
          call: byStrike[strike]!.$1,
          put: byStrike[strike]!.$2,
        ),
    ],
    totalCallOpenInterest: callInterest,
    totalPutOpenInterest: putInterest,
    maxPain: maxPain,
    fetchedAt: fetchedAt,
  );
}

OptionQuote? _optionQuote(Object? json) {
  if (json is! Map) {
    return null;
  }
  return OptionQuote(
    lastPrice: _finite(json['lastPrice']),
    change: _finite(json['change']),
    openInterest: _finite(json['openInterest']),
    openInterestChange: _finite(json['changeinOpenInterest']),
    impliedVolatility: _positive(json['impliedVolatility']),
    volume: _finite(json['totalTradedVolume']),
    bid: _positive(json['buyPrice1']),
    ask: _positive(json['sellPrice1']),
  );
}

double? _positive(Object? value) {
  final number = _finite(value);
  return number != null && number > 0 ? number : null;
}

// ------------------------------------------------------------ the exchange

/// A conversation with the exchange's website.
///
/// Its data API answers only a visitor who has loaded a page first and
/// carries the cookies that page set, so the session loads the option chain
/// page, keeps what it was given, and does so again every few minutes or
/// whenever the API turns it away.
class NseSession {
  NseSession({HttpClient Function()? createClient})
      : _createClient = createClient ?? HttpClient.new;

  static const origin = 'https://www.nseindia.com';
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';
  static const primeEvery = Duration(minutes: 4);
  static const timeout = Duration(seconds: 20);
  static const maximumBytes = 8 * 1024 * 1024;

  final HttpClient Function() _createClient;
  HttpClient? _client;
  final Map<String, String> _cookies = {};
  DateTime? _primedAt;
  Future<void>? _priming;

  Future<Object?> getJson(String path, Map<String, String> query) async {
    final uri = Uri.parse('$origin$path').replace(queryParameters: query);
    await _ensurePrimed();
    var reply = await _send(uri, json: true);
    if (reply.$1 == 401 || reply.$1 == 403) {
      _primedAt = null;
      await _ensurePrimed();
      reply = await _send(uri, json: true);
    }
    if (reply.$1 != 200) {
      throw StateError('The exchange answered ${reply.$1}.');
    }
    final body = reply.$2.trim();
    if (body.isEmpty || body == '{}') {
      throw StateError('The exchange sent nothing for that request.');
    }
    return jsonDecode(body);
  }

  Future<void> _ensurePrimed() {
    final primed = _primedAt;
    if (primed != null && DateTime.now().difference(primed) < primeEvery) {
      return Future.value();
    }
    return _priming ??= () async {
      try {
        await _send(Uri.parse('$origin/option-chain'), json: false);
        _primedAt = DateTime.now();
      } finally {
        _priming = null;
      }
    }();
  }

  Future<(int, String)> _send(Uri uri, {required bool json}) async {
    final client = _client ??= _createClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..autoUncompress = true
      ..userAgent = userAgent;
    final request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = true;
    request.headers
      ..set(
        HttpHeaders.acceptHeader,
        json
            ? 'application/json, text/plain, */*'
            : 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      )
      ..set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9')
      ..set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate')
      ..set(HttpHeaders.refererHeader, '$origin/option-chain');
    if (_cookies.isNotEmpty) {
      // Written by hand: the exchange's cookies carry characters the strict
      // cookie parser rejects, and one bad cookie must not lose the rest.
      request.headers.set(
        HttpHeaders.cookieHeader,
        _cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; '),
      );
    }
    final response = await request.close().timeout(timeout);
    for (final header
        in response.headers[HttpHeaders.setCookieHeader] ?? const <String>[]) {
      final pair = header.split(';').first;
      final equals = pair.indexOf('=');
      if (equals > 0) {
        _cookies[pair.substring(0, equals).trim()] =
            pair.substring(equals + 1).trim();
      }
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maximumBytes) {
        throw StateError('The exchange sent more than 8 MB.');
      }
    }
    return (response.statusCode, utf8.decode(bytes, allowMalformed: true));
  }

  void close() {
    _client?.close(force: true);
    _client = null;
  }
}
