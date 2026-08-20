import 'dart:async';
import 'dart:convert';
// `Path` in appflowy_editor is a node path (List<int>), not a canvas path.
import 'dart:ui' as ui;

import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/built_in/stock_chart.dart';
import 'package:appflowy/extensions/dart/built_in/stock_dashboard_widget.dart';
import 'package:appflowy/extensions/dart/extension_boundary.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// A share price that keeps itself up to date.
///
/// This is the extension that exercises the whole architecture at once, and it
/// is the story the design doc opens with:
///
/// * the **document** holds only WHICH ticker, never the price — a block that
///   stored the number would add an undo entry, a collab round and a page
///   version every time it ticked;
/// * the **price** lives in `af.data`, keyed `stock.quote.<SYMBOL>`, so the
///   block redraws the moment a fetch lands and nothing is written to the page;
/// * a **job** refreshes the watchlist while the app is open;
/// * a **command** refreshes on demand from the palette;
/// * turning the extension off unwinds all of it — timer, block, command —
///   through `ExtensionScope`, with no restart.
class StockExtension extends AppFlowyExtension {
  @override
  DartExtensionInfo get info => const DartExtensionInfo(
        id: 'stock',
        name: 'Stocks',
        description:
            'A block showing a share price that refreshes itself, plus a '
            'command to refresh every ticker on the watchlist.',
      );

  @override
  Future<void> activate(ExtensionContext context) async {
    final ctx = context as DartExtensionContext;
    final feed = StockFeed(ctx);

    StockFeed.active = feed;
    // ⚠️ Anything the block can reach has to be unreachable again once the
    // extension is off, or a stale feed keeps fetching for a block that is no
    // longer drawn.
    ctx.scope.onDispose(() => StockFeed.active = null);

    ctx.blocks.define(
      type: StockBlockKeys.type,
      builder: (configuration) =>
          StockBlockComponentBuilder(configuration: configuration),
      parser: StockNodeParser(),
      slashName: 'Stock',
      slashKeywords: const ['stock', 'share', 'ticker', 'price', 'quote'],
      slashIcon: Icons.trending_up_rounded,
      slashDescription: 'A share price that keeps itself up to date',
      newNode: stockNode,
      alignable: true,
    );

    ctx.commands.add(
      id: 'refresh',
      name: 'Stocks: refresh quotes',
      description: 'Fetch every ticker on the watchlist now',
      keywords: const ['stock', 'share', 'price', 'quote', 'refresh'],
      icon: Icons.trending_up_rounded,
      run: (_) => feed.refreshWatchlist(force: true),
    );

    ctx.dashboardWidgets.add(stockDashboardWidget());

    ctx.jobs.every(StockFeed.jobInterval, feed.refreshWatchlist);

    unawaited(feed.refreshWatchlist());
  }
}

/// How far back a chart looks, and how finely.
///
/// The pairs are what the quote service accepts: asking for a year of
/// five-minute candles returns nothing, so range and interval travel together.
enum StockRange {
  day1('1d', '5m', '1D', 'today', Duration(minutes: 5)),
  day5('5d', '30m', '5D', 'past week', Duration(minutes: 15)),
  month1('1mo', '1d', '1M', 'past month', Duration(minutes: 30)),
  month6('6mo', '1d', '6M', 'past 6 months', Duration(hours: 2)),
  ytd('ytd', '1d', 'YTD', 'this year', Duration(hours: 2)),
  year1('1y', '1d', '1Y', 'past year', Duration(hours: 4)),
  year5('5y', '1wk', '5Y', 'past 5 years', Duration(hours: 12)),
  max('max', '1mo', 'MAX', 'all time', Duration(days: 1));

  const StockRange(
    this.range,
    this.interval,
    this.label,
    this.caption,
    this.freshFor,
  );

  final String range;
  final String interval;

  /// What the picker shows.
  final String label;

  /// What the change is measured over, in words.
  final String caption;

  /// ⚠️ A five-year chart moves once a week; refetching it every five minutes
  /// would be pure noise on someone's connection.
  final Duration freshFor;

  static StockRange named(String name) => StockRange.values.firstWhere(
        (range) => range.name == name,
        orElse: () => StockRange.month1,
      );
}

/// Fetches quotes and puts them where the block can see them.
class StockFeed {
  StockFeed(this._context, {http.Client? client})
      : _client = client ?? http.Client();

  /// Set while the extension is on, null once it is off.
  static StockFeed? active;

  /// What a block shows when nobody has chosen a range.
  static const defaultRange = StockRange.month1;

  static const jobInterval = Duration(minutes: 5);
  static const requestTimeout = Duration(seconds: 20);

  static const maximumResponseBytes = 2 * 1024 * 1024;

  /// Enough to draw a smooth line without keeping a year of ticks per card.
  static const seriesLength = 180;

  static const watchlistKey = 'watchlist';

  static const _endpoint = 'https://query1.finance.yahoo.com/v8/finance/chart/';
  static const _searchEndpoint =
      'https://query1.finance.yahoo.com/v1/finance/search';

  final DartExtensionContext _context;
  final http.Client _client;

  final Set<String> _inFlight = {};
  final Map<String, List<StockMatch>> _searches = {};

  static String quoteKey(String symbol, StockRange range) =>
      'quote.${normalise(symbol)}.${range.name}';

  /// The full `af.data` key, extension prefix and all, as a card reads it.
  static String qualifiedQuoteKey(String symbol, StockRange range) =>
      ExtensionDataStore.qualify('stock', quoteKey(symbol, range));

  static String normalise(String symbol) => symbol.trim().toUpperCase();

  static String _watchEntry(String symbol, StockRange range) =>
      '${normalise(symbol)}@${range.name}';

  List<String> get watchlist {
    final stored = _context.data.read(watchlistKey);
    return stored is List ? stored.whereType<String>().toList() : const [];
  }

  /// A card says which ticker and range it needs; the job keeps that fresh.
  Future<void> watch(String symbol, StockRange range) async {
    final entry = _watchEntry(symbol, range);
    if (normalise(symbol).isEmpty || watchlist.contains(entry)) {
      return;
    }
    await _context.data.write(watchlistKey, [...watchlist, entry]);
  }

  Future<void> refreshWatchlist({bool force = false}) async {
    for (final entry in watchlist) {
      final parts = entry.split('@');
      if (parts.length != 2) {
        continue;
      }
      await refresh(parts.first, StockRange.named(parts.last), force: force);
    }
  }

  /// Fetches unless a fetch is already running or what is stored is still
  /// fresh for that range.
  Future<void> refresh(
    String symbol,
    StockRange range, {
    bool force = false,
  }) async {
    final wanted = normalise(symbol);
    final entry = _watchEntry(wanted, range);
    if (wanted.isEmpty || _inFlight.contains(entry)) {
      return;
    }
    if (!force && !_isStale(wanted, range)) {
      return;
    }
    _inFlight.add(entry);
    try {
      final quote = await _fetch(wanted, range);
      await _context.data.write(
        quoteKey(wanted, range),
        quote.toJson(),
        staleAfter: range.freshFor * 4,
      );
    } on Object catch (error) {
      await _context.data.write(
        quoteKey(wanted, range),
        StockQuote.failed(wanted, '$error').toJson(),
        staleAfter: range.freshFor * 4,
      );
    } finally {
      _inFlight.remove(entry);
    }
  }

  bool isFetching(String symbol, StockRange range) =>
      _inFlight.contains(_watchEntry(symbol, range));

  /// Tickers matching what someone has typed.
  ///
  /// Deliberately a name search, not a symbol prefix: nobody remembers that
  /// Reliance Industries is `RELIANCE.NS` or Tata Elxsi is `TATAELXSI.NS`. The
  /// service covers NSE, BSE and every other exchange it knows, so Indian
  /// listings need no special case.
  Future<List<StockMatch>> search(String query) async {
    final needle = query.trim();
    if (needle.length < 2) {
      return const [];
    }
    final cached = _searches[needle.toLowerCase()];
    if (cached != null) {
      return cached;
    }
    final uri = Uri.parse(
      '$_searchEndpoint?q=${Uri.encodeQueryComponent(needle)}'
      '&quotesCount=12&newsCount=0&listsCount=0',
    );
    try {
      final response = await _client.get(
        uri,
        headers: const {'User-Agent': 'AppFlowy', 'Accept': 'application/json'},
      ).timeout(requestTimeout);
      if (response.statusCode != 200) {
        return const [];
      }
      final matches = StockMatch.listFrom(response.body);
      // Small and short-lived: a picker types fast and asks the same thing.
      if (_searches.length > 60) {
        _searches.clear();
      }
      _searches[needle.toLowerCase()] = matches;
      return matches;
    } on Object {
      // A search that fails is not worth an error card; the box simply offers
      // nothing and whatever was typed is still usable as a symbol.
      return const [];
    }
  }

  bool _isStale(String symbol, StockRange range) {
    final entry = _context.data.entryFor(quoteKey(symbol, range));
    if (entry == null) {
      return true;
    }
    return DateTime.now().difference(entry.writtenAt) >= range.freshFor;
  }

  Future<StockQuote> _fetch(String symbol, StockRange range) async {
    final uri = Uri.parse(
      '$_endpoint${Uri.encodeComponent(symbol)}'
      '?interval=${range.interval}&range=${range.range}',
    );
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
    return StockQuote.fromChartResponse(symbol, response.body);
  }
}

/// One ticker the search offered.
@immutable
class StockMatch {
  const StockMatch({
    required this.symbol,
    required this.name,
    this.exchange = '',
    this.kind = '',
  });

  /// Parses the search response, keeping only rows that name a real symbol.
  static List<StockMatch> listFrom(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return const [];
    }
    final quotes = decoded['quotes'];
    if (quotes is! List) {
      return const [];
    }
    final matches = <StockMatch>[];
    for (final quote in quotes) {
      if (quote is! Map) {
        continue;
      }
      final symbol = quote['symbol'];
      if (symbol is! String || symbol.isEmpty) {
        continue;
      }
      final name = (quote['shortname'] ?? quote['longname']) as String?;
      matches.add(
        StockMatch(
          symbol: symbol,
          // Some rows carry no name at all — a fund code, say. The symbol is
          // still selectable, so it is shown rather than dropped.
          name: name == null || name.isEmpty ? symbol : name,
          exchange: (quote['exchDisp'] as String?) ?? '',
          kind: (quote['typeDisp'] as String?) ?? '',
        ),
      );
    }
    return matches;
  }

  final String symbol;
  final String name;
  final String exchange;
  final String kind;

  /// "NSE · Equity", or whichever half is known.
  String get where =>
      [exchange, kind].where((part) => part.isNotEmpty).join(' · ');
}

/// What is known about one ticker over one range, as stored in `af.data`.
@immutable
class StockQuote {
  const StockQuote({
    required this.symbol,
    this.price,
    this.previousClose,
    this.currency = '',
    this.series = const [],
    this.times = const [],
    this.error = '',
  });

  factory StockQuote.failed(String symbol, String error) =>
      StockQuote(symbol: symbol, error: error);

  factory StockQuote.fromChartResponse(String symbol, String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw StateError('The quote service sent something unreadable.');
    }
    final chart = decoded['chart'];
    if (chart is! Map) {
      throw StateError('The quote service sent no chart.');
    }
    final failure = chart['error'];
    if (failure is Map) {
      throw StateError('${failure['description'] ?? failure['code']}');
    }
    final results = chart['result'];
    final result = results is List && results.isNotEmpty ? results.first : null;
    if (result is! Map) {
      throw StateError('No such ticker.');
    }
    final meta = result['meta'];
    if (meta is! Map) {
      throw StateError('The quote carried no summary.');
    }

    final points = _pointsOf(result);
    final kept = points.length <= StockFeed.seriesLength
        ? points
        : _thin(points, StockFeed.seriesLength);
    return StockQuote(
      symbol: (meta['symbol'] as String?) ?? symbol,
      price: _toDouble(meta['regularMarketPrice']) ??
          (kept.isEmpty ? null : kept.last.$2),
      previousClose: _toDouble(meta['chartPreviousClose']) ??
          _toDouble(meta['previousClose']),
      currency: (meta['currency'] as String?) ?? '',
      series: [for (final point in kept) point.$2],
      times: [for (final point in kept) point.$1],
    );
  }

  factory StockQuote.fromJson(Map<String, Object?> values) => StockQuote(
        symbol: (values['symbol'] as String?) ?? '',
        price: _toDouble(values['price']),
        previousClose: _toDouble(values['previousClose']),
        currency: (values['currency'] as String?) ?? '',
        series: (values['series'] as List?)
                ?.map(_toDouble)
                .whereType<double>()
                .toList() ??
            const [],
        times: (values['times'] as List?)
                ?.map((value) => value is int ? value : null)
                .whereType<int>()
                .toList() ??
            const [],
        error: (values['error'] as String?) ?? '',
      );

  final String symbol;
  final double? price;
  final double? previousClose;
  final String currency;
  final List<double> series;

  /// Seconds since the epoch, one per point in [series].
  final List<int> times;
  final String error;

  bool get hasPrice => price != null;

  /// What the move is measured from over [range].
  ///
  /// A day is measured against yesterday's close, the way every quote page
  /// does it; a longer range is measured from where the line starts, because
  /// yesterday's close says nothing about a year.
  double? baselineFor(StockRange range) => range == StockRange.day1
      ? previousClose ?? series.firstOrNull
      : series.firstOrNull;

  double? changeOver(StockRange range) {
    final now = price;
    final before = baselineFor(range);
    return now == null || before == null ? null : now - before;
  }

  double? changePercentOver(StockRange range) {
    final moved = changeOver(range);
    final before = baselineFor(range);
    return moved == null || before == null || before == 0
        ? null
        : moved / before * 100;
  }

  DateTime? timeAt(int index) => index < 0 || index >= times.length
      ? null
      : DateTime.fromMillisecondsSinceEpoch(times[index] * 1000);

  double? get change {
    final now = price;
    final before = previousClose;
    return now == null || before == null ? null : now - before;
  }

  double? get changePercent {
    final moved = change;
    final before = previousClose;
    return moved == null || before == null || before == 0
        ? null
        : moved / before * 100;
  }

  Map<String, Object?> toJson() => {
        'symbol': symbol,
        if (price != null) 'price': price,
        if (previousClose != null) 'previousClose': previousClose,
        if (currency.isNotEmpty) 'currency': currency,
        if (series.isNotEmpty) 'series': series,
        if (times.isNotEmpty) 'times': times,
        if (error.isNotEmpty) 'error': error,
      };

  /// The closes, each with the moment it belongs to.
  static List<(int, double)> _pointsOf(Map result) {
    final indicators = result['indicators'];
    if (indicators is! Map) {
      return const [];
    }
    final quotes = indicators['quote'];
    final quote = quotes is List && quotes.isNotEmpty ? quotes.first : null;
    if (quote is! Map) {
      return const [];
    }
    final closes = quote['close'];
    if (closes is! List) {
      return const [];
    }
    final stamps = result['timestamp'];
    final times = stamps is List ? stamps : const [];

    final points = <(int, double)>[];
    for (var index = 0; index < closes.length; index++) {
      // A close is null when the market was shut; dropping the point keeps the
      // line continuous instead of dragging it to zero.
      final close = _toDouble(closes[index]);
      if (close == null) {
        continue;
      }
      final at =
          index < times.length && times[index] is int ? times[index] as int : 0;
      points.add((at, close));
    }
    return points;
  }

  /// Keeps [wanted] points spread evenly across [points], always including the
  /// last one so the line ends at the latest price.
  static List<(int, double)> _thin(List<(int, double)> points, int wanted) {
    final step = (points.length - 1) / (wanted - 1);
    return [
      for (var index = 0; index < wanted - 1; index++)
        points[(index * step).round()],
      points.last,
    ];
  }

  static double? _toDouble(Object? value) =>
      value is num ? value.toDouble() : null;
}

// --------------------------------------------------------------------- block

class StockBlockKeys {
  const StockBlockKeys._();

  static const String type = 'extension_stock';

  static const String symbol = 'symbol';
  static const String label = 'label';
  static const String range = 'range';

  /// Small price card rather than the full chart.
  static const String compact = 'compact';
  static const String width = 'width';
  static const String height = 'height';
}

Node stockNode({
  String symbol = 'AAPL',
  String label = '',
  StockRange range = StockFeed.defaultRange,
  bool compact = false,
}) =>
    Node(
      type: StockBlockKeys.type,
      attributes: {
        StockBlockKeys.symbol: symbol,
        StockBlockKeys.label: label,
        StockBlockKeys.range: range.name,
        StockBlockKeys.compact: compact,
      },
    );

class StockNodeParser extends NodeParser {
  @override
  String get id => StockBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final symbol = node.attributes[StockBlockKeys.symbol] as String? ?? '';
    if (symbol.isEmpty) {
      return '\n';
    }
    final range = StockRange.named(
      node.attributes[StockBlockKeys.range] as String? ?? '',
    );
    final stored = ExtensionDataStore.instance
        .read(StockFeed.qualifiedQuoteKey(symbol, range));
    if (stored is! Map) {
      return '$symbol\n';
    }
    final quote = StockQuote.fromJson(Map<String, Object?>.from(stored));
    final price = quote.price;
    return price == null
        ? '$symbol\n'
        : '$symbol ${price.toStringAsFixed(2)} ${quote.currency}\n';
  }
}

class StockBlockComponentBuilder extends BlockComponentBuilder {
  StockBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return StockBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class StockBlockComponent extends BlockComponentStatefulWidget {
  const StockBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<StockBlockComponent> createState() => _StockBlockComponentState();
}

class _StockBlockComponentState extends State<StockBlockComponent>
    with BlockComponentConfigurable {
  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  String get _symbol => node.attributes[StockBlockKeys.symbol] as String? ?? '';

  String get _label => node.attributes[StockBlockKeys.label] as String? ?? '';

  StockRange get _range => StockRange.named(
        node.attributes[StockBlockKeys.range] as String? ?? '',
      );

  bool get _compact => node.attributes[StockBlockKeys.compact] == true;

  double? get _width {
    final value = node.attributes[StockBlockKeys.width];
    return value is num ? value.toDouble() : null;
  }

  double get _height {
    final value = node.attributes[StockBlockKeys.height];
    return value is num ? value.toDouble() : 280;
  }

  /// Which point the pointer is over on the chart, or null when it is away.
  int? _scrubbed;

  @override
  void initState() {
    super.initState();
    _ensureFresh();
  }

  @override
  void didUpdateWidget(StockBlockComponent old) {
    super.didUpdateWidget(old);
    _ensureFresh();
  }

  void _ensureFresh() {
    final feed = StockFeed.active;
    final symbol = _symbol;
    if (feed == null || symbol.isEmpty) {
      return;
    }
    unawaited(feed.watch(symbol, _range));
    unawaited(feed.refresh(symbol, _range));
  }

  void _writeSize(String key, double value) {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction..updateNode(node, {key: value});
    unawaited(editorState.apply(transaction));
  }

  void _chooseRange(StockRange range) {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction
      ..updateNode(node, {StockBlockKeys.range: range.name});
    unawaited(editorState.apply(transaction));
    unawaited(StockFeed.active?.watch(_symbol, range));
    unawaited(StockFeed.active?.refresh(_symbol, range));
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ExtensionBoundary(
      extensionId: 'stock',
      label: 'a share price',
      child: ValueListenableBuilder<int>(
        valueListenable: ExtensionDataStore.instance.revision,
        builder: (context, _, __) => _buildCard(context),
      ),
    );

    child = ResizableMedia(
      width: _width ?? (_compact ? 300 : 520),
      minWidth: _compact ? 220 : 320,
      height: _compact ? null : _height,
      minHeight: 200,
      alignment: blockEmbedAlignment(node),
      onResize: (value) => _writeSize(StockBlockKeys.width, value),
      onResizeHeight:
          _compact ? null : (value) => _writeSize(StockBlockKeys.height, value),
      child: child,
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }
    return child;
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = _symbol;
    final entry = symbol.isEmpty
        ? null
        : ExtensionDataStore.instance
            .entryFor(StockFeed.qualifiedQuoteKey(symbol, _range));
    final stored = entry?.value;
    final quote = stored is Map
        ? StockQuote.fromJson(Map<String, Object?>.from(stored))
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      // A chart is scrubbed, not tapped; only the compact card opens settings
      // on a plain tap. Both keep the block action menu.
      onTap: _compact ? () => _configure(context) : null,
      onDoubleTap: _compact ? null : () => _configure(context),
      child: Container(
        constraints: _compact
            ? const BoxConstraints(minWidth: 220)
            : const BoxConstraints.expand(),
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        decoration: BoxDecoration(
          color: EditorSurfaceStyle.previewBackgroundFor(
            theme.brightness,
            PremiumThemeExtension.maybeOf(context)?.surface ??
                theme.colorScheme.surfaceContainerLowest,
            isPaper: PaperTheme.isEnabled(context),
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EditorSurfaceStyle.embedBorder(context)),
        ),
        child: symbol.isEmpty
            ? _hint(context, 'Choose a ticker')
            : _body(context, symbol, quote, entry?.writtenAt),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    String symbol,
    StockQuote? quote,
    DateTime? at,
  ) {
    final theme = Theme.of(context);
    final muted = PremiumThemeExtension.maybeOf(context)?.textSecondary ??
        theme.colorScheme.onSurfaceVariant;

    if (quote != null && quote.error.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context, symbol, muted),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 15,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  quote.error,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final price = quote?.price;
    if (price == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context, symbol, muted),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
              const SizedBox(width: 9),
              Text(
                'Fetching…',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ],
      );
    }

    final moved = quote!.changeOver(_range) ?? 0;
    final rising = moved >= 0;
    final tone = stockAccent(rising);
    final percent = quote.changePercentOver(_range);
    final stale =
        at != null && DateTime.now().difference(at) > _range.freshFor * 4;

    final scrubbed = _scrubbed;
    final showing = scrubbed != null && scrubbed < quote.series.length
        ? quote.series[scrubbed]
        : price;
    final scrubbedAt = scrubbed == null ? null : quote.timeAt(scrubbed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: _compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _header(context, symbol, muted),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              showing.toStringAsFixed(2),
              style: (_compact
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.headlineMedium)
                  ?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (quote.currency.isNotEmpty) ...[
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  quote.currency,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
            const Spacer(),
            if (_compact && quote.series.length > 1)
              SizedBox(
                width: 74,
                height: 26,
                child: CustomPaint(
                  painter: _SparklinePainter(quote.series, tone),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Icon(
              rising
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
              size: 19,
              color: tone,
            ),
            Flexible(
              child: Text(
                '${moved.abs().toStringAsFixed(2)}'
                '${percent == null ? '' : ' (${percent.abs().toStringAsFixed(2)}%)'}'
                '${_compact ? '' : ' · ${scrubbedAt == null ? _range.caption : _scrubLabel(scrubbedAt)}'}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scrubbedAt == null ? tone : muted,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
            if (at != null)
              Text(
                stale ? 'stale · ${_time(at)}' : _time(at),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: stale ? theme.colorScheme.error : muted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        if (!_compact) ...[
          const SizedBox(height: 12),
          Expanded(
            child: quote.series.length < 2
                ? const SizedBox.shrink()
                : StockChart(
                    values: quote.series,
                    color: tone,
                    baseline: quote.baselineFor(_range),
                    scrubbed: _scrubbed,
                    onScrub: (index) {
                      if (index != _scrubbed) {
                        setState(() => _scrubbed = index);
                      }
                    },
                  ),
          ),
          const SizedBox(height: 8),
          StockRangePicker(
            selected: _range,
            accent: tone,
            muted: muted,
            onSelected: _chooseRange,
          ),
        ],
      ],
    );
  }

  String _scrubLabel(DateTime at) =>
      _range == StockRange.day1 || _range == StockRange.day5
          ? DateFormat.MMMd().add_Hm().format(at)
          : DateFormat.yMMMd().format(at);

  Widget _header(BuildContext context, String symbol, Color muted) {
    final theme = Theme.of(context);
    final label = _label;
    return Row(
      children: [
        Text(
          symbol,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
        if (!_compact) ...[
          const Spacer(),
          // A chart swallows taps for scrubbing, so settings need their own way in.
          IconButton(
            onPressed: () => _configure(context),
            icon: const Icon(Icons.tune_rounded, size: 16),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
            color: muted,
            tooltip: 'Ticker and period',
          ),
        ],
      ],
    );
  }

  Widget _hint(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.trending_up_rounded, size: 16, color: theme.hintColor),
        const SizedBox(width: 8),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }

  static String _time(DateTime at) => DateFormat.Hm().format(at);

  Future<void> _configure(BuildContext context) async {
    final editorState = context.read<EditorState>();
    final result = await showDialog<
        ({String symbol, String label, StockRange range, bool compact})>(
      context: context,
      builder: (_) => _StockDialog(
        symbol: _symbol,
        label: _label,
        range: _range,
        compact: _compact,
      ),
    );
    if (result == null) {
      return;
    }
    final transaction = editorState.transaction
      ..updateNode(node, {
        StockBlockKeys.symbol: StockFeed.normalise(result.symbol),
        StockBlockKeys.label: result.label,
        StockBlockKeys.range: result.range.name,
        StockBlockKeys.compact: result.compact,
      });
    await editorState.apply(transaction);
    unawaited(StockFeed.active?.watch(result.symbol, result.range));
    unawaited(StockFeed.active?.refresh(result.symbol, result.range));
  }
}

/// A ticker box that suggests real symbols as you type.
///
/// Search runs against names as well as symbols, so "reliance" finds
/// `RELIANCE.NS` and "infosys" finds both `INFY` and `INFY.BO`. Whatever is
/// typed stays usable as a symbol even if nothing is chosen, so an exchange
/// suffix nobody suggested can still be entered by hand.
class StockSymbolField extends StatefulWidget {
  const StockSymbolField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.onSubmitted,
    this.onChosen,
  });

  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback? onSubmitted;
  final ValueChanged<StockMatch>? onChosen;

  @override
  State<StockSymbolField> createState() => _StockSymbolFieldState();
}

class _StockSymbolFieldState extends State<StockSymbolField> {
  static const _debounce = Duration(milliseconds: 260);

  Timer? _typing;
  List<StockMatch> _matches = const [];
  bool _searching = false;

  /// Rises on every keystroke so a slow answer for an older query is dropped.
  int _generation = 0;

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _typing?.cancel();
    final wanted = value.trim();
    if (wanted.length < 2) {
      setState(() {
        _matches = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _typing = Timer(_debounce, () => _run(wanted));
  }

  Future<void> _run(String query) async {
    final feed = StockFeed.active;
    if (feed == null) {
      setState(() => _searching = false);
      return;
    }
    final generation = ++_generation;
    final found = await feed.search(query);
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _matches = found;
      _searching = false;
    });
  }

  void _choose(StockMatch match) {
    widget.controller.text = match.symbol;
    widget.controller.selection =
        TextSelection.collapsed(offset: match.symbol.length);
    setState(() => _matches = const []);
    widget.onChosen?.call(match);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          decoration: InputDecoration(
            labelText: 'Ticker or company',
            hintText: 'AAPL, Reliance, Infosys, ^NSEI…',
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    ),
                  )
                : const Icon(Icons.search_rounded, size: 18),
          ),
          onChanged: _onChanged,
          onSubmitted: (_) => widget.onSubmitted?.call(),
        ),
        if (_matches.isNotEmpty) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 208),
            child: Material(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(9),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _matches.length,
                itemBuilder: (context, index) {
                  final match = _matches[index];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      match.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      match.where,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Text(
                      match.symbol,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => _choose(match),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// ⚠️ Owns its controllers. Creating them in `build` loses the caret on every
/// keystroke.
class _StockDialog extends StatefulWidget {
  const _StockDialog({
    required this.symbol,
    required this.label,
    required this.range,
    required this.compact,
  });

  final String symbol;
  final String label;
  final StockRange range;
  final bool compact;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final _symbol = TextEditingController(text: widget.symbol);
  late final _label = TextEditingController(text: widget.label);
  late var _range = widget.range;
  late var _compact = widget.compact;

  @override
  void dispose() {
    _symbol.dispose();
    _label.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(
        (
          symbol: _symbol.text,
          label: _label.text,
          range: _range,
          compact: _compact,
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Share price'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StockSymbolField(
                  controller: _symbol,
                  autofocus: true,
                  onSubmitted: _submit,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    hintText: 'Optional',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                Text('Period', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final range in StockRange.values)
                      ChoiceChip(
                        label: Text(range.label),
                        selected: _range == range,
                        onSelected: (_) => setState(() => _range = range),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Show as', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Chart'),
                      selected: !_compact,
                      onSelected: (_) => setState(() => _compact = false),
                    ),
                    ChoiceChip(
                      label: const Text('Compact'),
                      selected: _compact,
                      onSelected: (_) => setState(() => _compact = true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      );
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      return;
    }
    var lowest = values.first;
    var highest = values.first;
    for (final value in values) {
      lowest = value < lowest ? value : lowest;
      highest = value > highest ? value : highest;
    }
    // A flat line would divide by zero; draw it down the middle instead.
    final span = highest - lowest;
    final step = size.width / (values.length - 1);

    final path = ui.Path();
    for (var index = 0; index < values.length; index++) {
      final ratio = span == 0 ? 0.5 : (values[index] - lowest) / span;
      final point = Offset(step * index, size.height - ratio * size.height);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !listEquals(old.values, values);
}
