import 'dart:async';

import 'package:flutter/foundation.dart';

/// A price as the market last reported it.
@immutable
class MarketQuote {
  const MarketQuote({
    required this.symbol,
    this.price,
    this.previousClose,
    this.closes = const [],
    this.updatedAt,
    this.error,
  });

  final String symbol;
  final double? price;

  /// Yesterday's close, which today's change is measured from.
  final double? previousClose;

  /// Recent daily closes, oldest first, for a sparkline.
  final List<double> closes;
  final DateTime? updatedAt;
  final String? error;

  bool get hasPrice => price != null;

  double? get change {
    final price = this.price;
    final close = previousClose;
    return price == null || close == null ? null : price - close;
  }

  double? get changePercent {
    final change = this.change;
    final close = previousClose;
    if (change == null || close == null || close == 0) {
      return null;
    }
    return change / close * 100;
  }

  Map<String, Object?> toJson() => {
        'symbol': symbol,
        if (price != null) 'price': price,
        if (previousClose != null) 'previousClose': previousClose,
        if (closes.isNotEmpty) 'closes': closes,
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  static MarketQuote? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final symbol = json['symbol'];
    if (symbol is! String || symbol.isEmpty) {
      return null;
    }
    final closes = json['closes'];
    return MarketQuote(
      symbol: symbol,
      price: _number(json['price']),
      previousClose: _number(json['previousClose']),
      closes: closes is List
          ? [
              for (final value in closes)
                if (_number(value) != null) _number(value)!,
            ]
          : const [],
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt'] as String)?.toLocal()
          : null,
    );
  }
}

double? _number(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
  return null;
}

/// One listing a symbol search offered.
@immutable
class MarketSymbol {
  const MarketSymbol({
    required this.symbol,
    required this.name,
    this.exchange = '',
    this.kind = '',
  });

  final String symbol;
  final String name;
  final String exchange;
  final String kind;

  /// "NSE · Equity", or whichever half is known.
  String get where =>
      [exchange, kind].where((part) => part.isNotEmpty).join(' · ');
}

/// One side of one strike.
@immutable
class OptionQuote {
  const OptionQuote({
    this.lastPrice,
    this.change,
    this.openInterest,
    this.openInterestChange,
    this.impliedVolatility,
    this.volume,
    this.bid,
    this.ask,
  });

  final double? lastPrice;
  final double? change;

  /// Contracts open, as the exchange counts them.
  final double? openInterest;
  final double? openInterestChange;

  /// In percent, as the exchange quotes it.
  final double? impliedVolatility;
  final double? volume;
  final double? bid;
  final double? ask;
}

/// A strike with its call and its put.
@immutable
class OptionChainRow {
  const OptionChainRow({required this.strike, this.call, this.put});

  final double strike;
  final OptionQuote? call;
  final OptionQuote? put;
}

/// Which chain somebody wants: an underlying and, optionally, an expiry.
/// No expiry means the nearest one.
@immutable
class ChainRequest {
  ChainRequest(String underlying, [DateTime? expiry])
      : underlying = underlying.trim().toUpperCase(),
        expiry = expiry == null
            ? null
            : DateTime(expiry.year, expiry.month, expiry.day);

  final String underlying;
  final DateTime? expiry;

  @override
  bool operator ==(Object other) =>
      other is ChainRequest &&
      other.underlying == underlying &&
      other.expiry == expiry;

  @override
  int get hashCode => Object.hash(underlying, expiry);

  @override
  String toString() =>
      '$underlying@${expiry?.toIso8601String().substring(0, 10) ?? 'next'}';
}

/// Every strike of one expiry around the money, as the exchange last
/// published it.
@immutable
class OptionChain {
  const OptionChain({
    required this.underlying,
    required this.expiry,
    required this.rows,
    this.spot,
    this.timestamp,
    this.expiries = const [],
    this.totalCallOpenInterest = 0,
    this.totalPutOpenInterest = 0,
    this.maxPain,
    this.fetchedAt,
  });

  final String underlying;
  final DateTime expiry;

  /// In strike order.
  final List<OptionChainRow> rows;
  final double? spot;

  /// When the exchange stamped the data.
  final DateTime? timestamp;

  /// Every expiry the underlying trades, nearest first.
  final List<DateTime> expiries;
  final double totalCallOpenInterest;
  final double totalPutOpenInterest;

  /// The strike at which option writers, as a whole, pay out least.
  final double? maxPain;
  final DateTime? fetchedAt;

  /// Put open interest for every call's: above one leans bullish.
  double? get putCallRatio => totalCallOpenInterest > 0
      ? totalPutOpenInterest / totalCallOpenInterest
      : null;

  /// The row nearest the spot.
  int get atmIndex {
    final spot = this.spot;
    if (rows.isEmpty) {
      return -1;
    }
    if (spot == null) {
      return rows.length ~/ 2;
    }
    var best = 0;
    for (var index = 1; index < rows.length; index++) {
      if ((rows[index].strike - spot).abs() <
          (rows[best].strike - spot).abs()) {
        best = index;
      }
    }
    return best;
  }

  OptionChainRow? rowAt(double strike) {
    for (final row in rows) {
      if ((row.strike - strike).abs() < 0.001) {
        return row;
      }
    }
    return null;
  }

  /// The side of [strike] a call ([call] true) or a put reads.
  OptionQuote? quoteAt(double strike, {required bool call}) {
    final row = rowAt(strike);
    return call ? row?.call : row?.put;
  }
}

/// A claim on some quotes and chains, kept fresh for as long as it is held.
abstract class MarketLease {
  /// Replaces what this lease wants.
  void want({
    required Set<String> symbols,
    required Set<ChainRequest> chains,
  });

  /// Stops wanting anything.
  void release();
}

/// Where live prices come from. The Stocks extension provides one; with it
/// switched off there is none and widgets show what their tables hold.
abstract class MarketDataProvider implements Listenable {
  MarketQuote? quote(String symbol);

  bool isFetching(String symbol);

  /// Keeps what the lease wants fresh until it is released.
  MarketLease lease();

  /// Fetches everything leased now, stale or not.
  Future<void> refresh({bool force = false});

  /// Listings matching what somebody typed.
  Future<List<MarketSymbol>> search(String query);

  /// Whether [underlying] has option chains this provider can read.
  bool supportsChain(String underlying);

  OptionChain? chain(ChainRequest request);

  bool isFetchingChain(ChainRequest request);

  /// Why the last fetch of [request] failed, if it did.
  String? chainError(ChainRequest request);

  /// The expiries [underlying] trades, nearest first, once known.
  List<DateTime> expiries(String underlying);
}

/// The live market, when something provides one.
class MarketData {
  MarketData._();

  static final ValueNotifier<MarketDataProvider?> _current =
      ValueNotifier(null);

  static MarketDataProvider? get provider => _current.value;

  /// Raised when a provider arrives or leaves.
  static ValueListenable<MarketDataProvider?> get changes => _current;

  static void attach(MarketDataProvider provider) => _current.value = provider;

  static void detach(MarketDataProvider provider) {
    if (identical(_current.value, provider)) {
      _current.value = null;
    }
  }
}

/// What one widget wants from the market, for as long as the widget lives.
///
/// A widget owns one of these and says what it needs; the watch keeps the
/// claim alive across the extension being switched off and on again, and
/// tells the widget whenever anything it might draw has changed.
class MarketWatch extends ChangeNotifier {
  MarketWatch() {
    MarketData.changes.addListener(_providerChanged);
    _providerChanged();
  }

  MarketDataProvider? _provider;
  MarketLease? _lease;
  Set<String> _symbols = const {};
  Set<ChainRequest> _chains = const {};
  bool _disposed = false;

  MarketDataProvider? get provider => _provider;

  bool get isLive => _provider != null;

  /// Says what is wanted now. Cheap to call on every build: nothing happens
  /// unless the wants changed.
  void want({Set<String>? symbols, Set<ChainRequest>? chains}) {
    final nextSymbols = symbols == null
        ? _symbols
        : {
            for (final symbol in symbols)
              if (symbol.trim().isNotEmpty) symbol.trim().toUpperCase(),
          };
    final nextChains = chains ?? _chains;
    if (setEquals(nextSymbols, _symbols) && setEquals(nextChains, _chains)) {
      return;
    }
    _symbols = nextSymbols;
    _chains = nextChains;
    _lease?.want(symbols: _symbols, chains: _chains);
  }

  MarketQuote? quote(String symbol) =>
      symbol.isEmpty ? null : _provider?.quote(symbol.trim().toUpperCase());

  OptionChain? chain(ChainRequest request) => _provider?.chain(request);

  void _providerChanged() {
    final next = MarketData.provider;
    if (identical(next, _provider)) {
      return;
    }
    _lease?.release();
    _provider?.removeListener(_marketChanged);
    _provider = next;
    _lease = null;
    if (next != null) {
      next.addListener(_marketChanged);
      _lease = next.lease()..want(symbols: _symbols, chains: _chains);
    }
    _marketChanged();
  }

  void _marketChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    MarketData.changes.removeListener(_providerChanged);
    _provider?.removeListener(_marketChanged);
    _lease?.release();
    _lease = null;
    super.dispose();
  }
}

// ------------------------------------------------------------- the symbols

/// Index underlyings, by the name their options trade under, with the symbol
/// their level is quoted as.
const marketIndexSymbols = <String, String>{
  'NIFTY': '^NSEI',
  'BANKNIFTY': '^NSEBANK',
  'FINNIFTY': 'NIFTY_FIN_SERVICE.NS',
  'MIDCPNIFTY': '^NSEMDCP50',
  'NIFTYNXT50': '^NSMIDCP',
  'SENSEX': '^BSESN',
};

/// What the market quotes [underlying]'s level as: NIFTY is `^NSEI`, and a
/// share's options trade on its NSE listing.
String marketSymbolForUnderlying(String underlying) {
  final name = underlying.trim().toUpperCase();
  if (name.isEmpty) {
    return '';
  }
  final index = marketIndexSymbols[name];
  if (index != null) {
    return index;
  }
  if (name.contains('.') || name.startsWith('^') || name.contains('=')) {
    return name;
  }
  return '$name.NS';
}

bool isIndexUnderlying(String underlying) =>
    marketIndexSymbols.containsKey(underlying.trim().toUpperCase());

const _displayNames = <String, String>{
  '^NSEI': 'NIFTY 50',
  '^NSEBANK': 'BANK NIFTY',
  '^BSESN': 'SENSEX',
  '^CNXIT': 'NIFTY IT',
  '^NSEMDCP50': 'NIFTY MIDCAP 50',
  '^NSMIDCP': 'NIFTY NEXT 50',
  '^CNXAUTO': 'NIFTY AUTO',
  '^CNXPHARMA': 'NIFTY PHARMA',
  '^CNXFMCG': 'NIFTY FMCG',
  '^INDIAVIX': 'INDIA VIX',
  'NIFTY_FIN_SERVICE.NS': 'FIN NIFTY',
  '^GSPC': 'S&P 500',
  '^IXIC': 'NASDAQ',
  '^DJI': 'DOW JONES',
  'GC=F': 'Gold',
  'SI=F': 'Silver',
  'CL=F': 'Crude oil',
  'INR=X': 'USD/INR',
  'BTC-USD': 'Bitcoin',
  'ETH-USD': 'Ethereum',
};

/// A name a person recognises for [symbol]: `^NSEI` is NIFTY 50 and
/// `RELIANCE.NS` is RELIANCE.
String marketDisplayName(String symbol) {
  final upper = symbol.trim().toUpperCase();
  final known = _displayNames[upper];
  if (known != null) {
    return known;
  }
  final dot = upper.lastIndexOf('.');
  if (dot > 0 && (upper.endsWith('.NS') || upper.endsWith('.BO'))) {
    return upper.substring(0, dot);
  }
  return upper.startsWith('^') ? upper.substring(1) : upper;
}

/// The currency mark [symbol] is priced in, or empty for an index level or
/// an exchange rate, which are not amounts of money.
String marketCurrencySymbol(String symbol) {
  final upper = symbol.trim().toUpperCase();
  if (upper.startsWith('^') || upper.endsWith('=X')) {
    return '';
  }
  if (upper.endsWith('.NS') || upper.endsWith('.BO')) {
    return '₹';
  }
  if (upper.endsWith('.L')) {
    return '£';
  }
  if (upper.endsWith('-INR')) {
    return '₹';
  }
  return r'$';
}

/// The exchange's own name for an Indian listing: `RELIANCE.NS` is
/// `RELIANCE`, and the NIFTY index is `NIFTY`.
String chainUnderlyingFor(String symbol) {
  final upper = symbol.trim().toUpperCase();
  for (final entry in marketIndexSymbols.entries) {
    if (entry.value == upper) {
      return entry.key;
    }
  }
  if (upper.endsWith('.NS') || upper.endsWith('.BO')) {
    return upper.substring(0, upper.length - 3);
  }
  return upper;
}

/// Coalesces bursts of wants into one fetch, after the current frame.
class MarketDebounce {
  MarketDebounce(this.delay, this.action);

  final Duration delay;
  final FutureOr<void> Function() action;
  Timer? _timer;

  void schedule() {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      action();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
