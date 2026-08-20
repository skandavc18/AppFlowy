import 'dart:async';
import 'dart:convert';

import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/built_in/news_dashboard_widget.dart';
import 'package:appflowy/extensions/dart/built_in/news_views.dart';
import 'package:appflowy/extensions/dart/extension_boundary.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';

/// Headlines from any feed, in a page or on a dashboard.
///
/// Built on RSS and Atom rather than a news API on purpose: every publisher
/// already has a feed, none of them need a key, and it works as well for a
/// personal blog or a subreddit as it does for a newspaper.
class NewsExtension extends AppFlowyExtension {
  @override
  DartExtensionInfo get info => const DartExtensionInfo(
        id: 'news',
        name: 'News',
        description: 'Headlines from any RSS or Atom feed, kept up to date.',
      );

  @override
  Future<void> activate(ExtensionContext context) async {
    final ctx = context as DartExtensionContext;
    final feed = NewsFeed(ctx);

    NewsFeed.active = feed;
    ctx.scope.onDispose(() => NewsFeed.active = null);

    ctx.blocks.define(
      type: NewsBlockKeys.type,
      builder: (configuration) =>
          NewsBlockComponentBuilder(configuration: configuration),
      parser: NewsNodeParser(),
      slashName: 'News',
      slashKeywords: const ['news', 'feed', 'rss', 'atom', 'headlines'],
      slashIcon: Icons.newspaper_rounded,
      slashDescription: 'Headlines from a feed you choose',
      newNode: newsNode,
      alignable: true,
    );

    ctx.commands.add(
      id: 'refresh',
      name: 'News: refresh feeds',
      description: 'Fetch every feed being shown now',
      keywords: const ['news', 'feed', 'rss', 'refresh'],
      icon: Icons.newspaper_rounded,
      run: (_) => feed.refreshAll(force: true),
    );

    ctx.dashboardWidgets.add(newsDashboardWidget());

    ctx.jobs.every(NewsFeed.jobInterval, feed.refreshAll);

    unawaited(feed.refreshAll());
  }
}

/// A feed worth offering before anybody has typed a URL.
@immutable
class NewsSource {
  const NewsSource(this.name, this.url);

  final String name;
  final String url;
}

/// Deliberately broad rather than one region's papers.
const newsSources = <NewsSource>[
  NewsSource('BBC World', 'https://feeds.bbci.co.uk/news/world/rss.xml'),
  NewsSource('Reuters Top', 'https://www.reutersagency.com/feed/'),
  NewsSource(
    'Economic Times',
    'https://economictimes.indiatimes.com/rssfeedstopstories.cms',
  ),
  NewsSource(
    'Economic Times · Markets',
    'https://economictimes.indiatimes.com/markets/rssfeeds/1977021501.cms',
  ),
  NewsSource(
    'The Hindu · National',
    'https://www.thehindu.com/news/national/feeder/default.rss',
  ),
  NewsSource('Hacker News', 'https://hnrss.org/frontpage'),
  NewsSource('NASA', 'https://www.nasa.gov/rss/dyn/breaking_news.rss'),
];

/// Fetches feeds and puts them where a card can see them.
class NewsFeed {
  NewsFeed(this._context, {http.Client? client})
      : _client = client ?? http.Client();

  /// Set while the extension is on, null once it is off.
  static NewsFeed? active;

  static const jobInterval = Duration(minutes: 15);
  static const freshFor = Duration(minutes: 15);
  static const requestTimeout = Duration(seconds: 20);
  static const maximumResponseBytes = 4 * 1024 * 1024;

  /// More than any card shows, so changing the count needs no refetch.
  static const maximumItems = 40;

  static const watchlistKey = 'feeds';

  final DartExtensionContext _context;
  final http.Client _client;

  final Set<String> _inFlight = {};

  /// A short, stable key for a URL. Hashed because a URL is full of dots and
  /// slashes, and `af.data` keys are dotted paths.
  static String keyFor(String url) =>
      'feed.${sha1.convert(utf8.encode(url.trim())).toString().substring(0, 16)}';

  static String qualifiedKeyFor(String url) =>
      ExtensionDataStore.qualify('news', keyFor(url));

  List<String> get watchlist {
    final stored = _context.data.read(watchlistKey);
    return stored is List ? stored.whereType<String>().toList() : const [];
  }

  /// A card says which feed it needs; the job keeps that feed fresh.
  Future<void> watch(String url) async {
    final wanted = url.trim();
    if (wanted.isEmpty || watchlist.contains(wanted)) {
      return;
    }
    await _context.data.write(watchlistKey, [...watchlist, wanted]);
  }

  Future<void> refreshAll({bool force = false}) async {
    for (final url in watchlist) {
      await refresh(url, force: force);
    }
  }

  Future<void> refresh(String url, {bool force = false}) async {
    final wanted = url.trim();
    if (wanted.isEmpty || _inFlight.contains(wanted)) {
      return;
    }
    if (!force && !_isStale(wanted)) {
      return;
    }
    _inFlight.add(wanted);
    try {
      final channel = await _fetch(wanted);
      await _context.data
          .write(keyFor(wanted), channel.toJson(), staleAfter: freshFor * 4);
    } on Object catch (error) {
      await _context.data.write(
        keyFor(wanted),
        NewsChannel.failed('$error').toJson(),
        staleAfter: freshFor * 4,
      );
    } finally {
      _inFlight.remove(wanted);
    }
  }

  bool _isStale(String url) {
    final entry = _context.data.entryFor(keyFor(url));
    return entry == null ||
        DateTime.now().difference(entry.writtenAt) >= freshFor;
  }

  Future<NewsChannel> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.isScheme('https')) {
      // ⚠️ https only: a feed is fetched unattended in the background, and a
      // plaintext one is a silent tamper point.
      throw StateError('A feed address must start with https://');
    }
    final response = await _client.get(
      uri,
      headers: const {
        'User-Agent': 'AppFlowy',
        'Accept': 'application/rss+xml, application/atom+xml, application/xml',
      },
    ).timeout(requestTimeout);
    if (response.statusCode != 200) {
      throw StateError('The feed answered ${response.statusCode}.');
    }
    if (response.bodyBytes.length > maximumResponseBytes) {
      throw StateError('That feed is larger than 4 MB.');
    }
    return NewsChannel.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
  }
}

/// One headline.
@immutable
class NewsItem {
  const NewsItem({
    required this.title,
    this.link = '',
    this.summary = '',
    this.image = '',
    this.publishedAt,
  });

  final String title;
  final String link;
  final String summary;

  /// A thumbnail, when the feed offers one. Plenty of feeds do not.
  final String image;
  final DateTime? publishedAt;

  bool get hasImage => image.isNotEmpty;

  Map<String, Object?> toJson() => {
        'title': title,
        if (link.isNotEmpty) 'link': link,
        if (summary.isNotEmpty) 'summary': summary,
        if (image.isNotEmpty) 'image': image,
        if (publishedAt != null) 'at': publishedAt!.toIso8601String(),
      };

  static NewsItem fromJson(Map<String, Object?> values) => NewsItem(
        title: (values['title'] as String?) ?? '',
        link: (values['link'] as String?) ?? '',
        summary: (values['summary'] as String?) ?? '',
        image: (values['image'] as String?) ?? '',
        publishedAt: DateTime.tryParse((values['at'] as String?) ?? ''),
      );
}

/// A whole feed as stored in `af.data`.
@immutable
class NewsChannel {
  const NewsChannel({
    this.title = '',
    this.items = const [],
    this.error = '',
  });

  factory NewsChannel.failed(String error) => NewsChannel(error: error);

  /// Reads RSS 2.0 and Atom, which between them cover essentially every feed.
  factory NewsChannel.parse(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException {
      throw StateError('That address did not return a feed.');
    }
    final root = document.rootElement;
    final isAtom = root.name.local == 'feed';
    final entries =
        isAtom ? root.findElements('entry') : root.findAllElements('item');

    final items = <NewsItem>[];
    for (final entry in entries) {
      final title = _clean(_textOf(entry, 'title'));
      if (title.isEmpty) {
        continue;
      }
      items.add(
        NewsItem(
          title: title,
          link: isAtom ? _atomLink(entry) : _textOf(entry, 'link'),
          summary: _clean(
            _textOf(entry, isAtom ? 'summary' : 'description'),
          ),
          image: _imageOf(entry),
          publishedAt: _dateOf(
            _textOf(entry, isAtom ? 'published' : 'pubDate'),
          ) ??
              _dateOf(_textOf(entry, 'updated')),
        ),
      );
      if (items.length >= NewsFeed.maximumItems) {
        break;
      }
    }
    if (items.isEmpty) {
      throw StateError('That feed carried no headlines.');
    }

    final channelTitle = isAtom
        ? _textOf(root, 'title')
        : root
            .findElements('channel')
            .map((channel) => _textOf(channel, 'title'))
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    return NewsChannel(title: _clean(channelTitle), items: items);
  }

  factory NewsChannel.fromJson(Map<String, Object?> values) => NewsChannel(
        title: (values['title'] as String?) ?? '',
        items: [
          for (final item in (values['items'] as List?) ?? const [])
            if (item is Map) NewsItem.fromJson(Map<String, Object?>.from(item)),
        ],
        error: (values['error'] as String?) ?? '',
      );

  final String title;
  final List<NewsItem> items;
  final String error;

  Map<String, Object?> toJson() => {
        if (title.isNotEmpty) 'title': title,
        if (items.isNotEmpty)
          'items': [for (final item in items) item.toJson()],
        if (error.isNotEmpty) 'error': error,
      };

  static String _textOf(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (child.name.local == name) {
        return child.innerText.trim();
      }
    }
    return '';
  }

  /// A thumbnail, however this particular publisher advertises one.
  ///
  /// There is no single convention: the BBC uses `media:thumbnail`, WordPress
  /// sites tend to use `enclosure` or `media:content`, and many feeds only
  /// have a picture inside the HTML of the description. All four are tried,
  /// and plenty of feeds simply have none.
  static String _imageOf(XmlElement entry) {
    for (final child in entry.childElements) {
      final name = child.name.local;
      if (name == 'thumbnail') {
        final url = child.getAttribute('url');
        if (_looksLikeImage(url)) {
          return url!;
        }
      }
      if (name == 'content' || name == 'enclosure') {
        final type = child.getAttribute('type') ?? '';
        final medium = child.getAttribute('medium') ?? '';
        final url = child.getAttribute('url') ?? child.getAttribute('href');
        final claimsImage = type.startsWith('image/') || medium == 'image';
        if (url != null && url.isNotEmpty && (claimsImage || _looksLikeImage(url))) {
          return url;
        }
      }
      if (name == 'link' && child.getAttribute('rel') == 'enclosure') {
        final url = child.getAttribute('href');
        final type = child.getAttribute('type') ?? '';
        if (url != null && (type.startsWith('image/') || _looksLikeImage(url))) {
          return url;
        }
      }
    }
    // Last resort: the first picture in whatever HTML the item carries.
    for (final child in entry.childElements) {
      if (child.name.local != 'description' &&
          child.name.local != 'encoded' &&
          child.name.local != 'content' &&
          child.name.local != 'summary') {
        continue;
      }
      final found =
          RegExp('<img[^>]+src=["\']([^"\']+)').firstMatch(child.innerText);
      final url = found?.group(1);
      if (url != null && url.startsWith('http')) {
        return url;
      }
    }
    return '';
  }

  static bool _looksLikeImage(String? url) =>
      url != null &&
      url.startsWith('http') &&
      RegExp(r'\.(jpe?g|png|webp|gif|avif)(\?|$)', caseSensitive: false)
          .hasMatch(url);

  /// Atom puts the address in an attribute, and often lists several.
  static String _atomLink(XmlElement entry) {    for (final link in entry.childElements) {
      if (link.name.local != 'link') {
        continue;
      }
      final rel = link.getAttribute('rel');
      if (rel == null || rel == 'alternate') {
        return link.getAttribute('href') ?? '';
      }
    }
    return '';
  }

  /// Strips the markup publishers put in a summary, so a card shows words
  /// rather than a paragraph of tags.
  static String _clean(String value) {
    if (value.isEmpty) {
      return '';
    }
    final withoutTags = value.replaceAll(RegExp('<[^>]*>'), ' ');
    final unescaped = withoutTags
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    return unescaped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Atom dates are ISO 8601; RSS dates are RFC 822, which `DateTime.parse`
  /// refuses outright.
  static DateTime? _dateOf(String value) {
    if (value.isEmpty) {
      return null;
    }
    final iso = DateTime.tryParse(value);
    if (iso != null) {
      return iso.toLocal();
    }
    final match = RegExp(
      r'(\d{1,2})\s+(\w{3})\w*\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|\w+)?',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    final month = _months[match.group(2)!.toLowerCase()];
    if (month == null) {
      return null;
    }
    final utc = DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
    );
    final zone = match.group(7);
    if (zone != null && RegExp(r'^[+-]\d{4}$').hasMatch(zone)) {
      final sign = zone.startsWith('-') ? 1 : -1;
      final offset = Duration(
        hours: int.parse(zone.substring(1, 3)),
        minutes: int.parse(zone.substring(3, 5)),
      );
      return utc.add(offset * sign).toLocal();
    }
    return utc.toLocal();
  }
}

/// Opens a headline in the reader's own browser.
Future<void> openNewsLink(String link) async {
  final uri = Uri.tryParse(link);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String newsAgeLabel(DateTime? at) {
  if (at == null) {
    return '';
  }
  final since = DateTime.now().difference(at);
  if (since.inMinutes < 1) {
    return 'just now';
  }
  if (since.inMinutes < 60) {
    return '${since.inMinutes}m ago';
  }
  if (since.inHours < 24) {
    return '${since.inHours}h ago';
  }
  if (since.inDays < 7) {
    return '${since.inDays}d ago';
  }
  return DateFormat.MMMd().format(at);
}

// --------------------------------------------------------------------- block

class NewsBlockKeys {
  const NewsBlockKeys._();

  static const String type = 'extension_news';

  static const String url = 'url';
  static const String label = 'label';
  static const String count = 'count';
  static const String showSummary = 'showSummary';
  static const String showImages = 'showImages';
  static const String width = 'width';
  static const String height = 'height';
}

Node newsNode({
  String url = '',
  String label = '',
  int count = 6,
  bool showSummary = true,
  bool showImages = true,
}) =>
    Node(
      type: NewsBlockKeys.type,
      attributes: {
        NewsBlockKeys.url: url.isEmpty ? newsSources.first.url : url,
        NewsBlockKeys.label: label,
        NewsBlockKeys.count: count,
        NewsBlockKeys.showSummary: showSummary,
        NewsBlockKeys.showImages: showImages,
      },
    );

class NewsNodeParser extends NodeParser {
  @override
  String get id => NewsBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final url = node.attributes[NewsBlockKeys.url] as String? ?? '';
    if (url.isEmpty) {
      return '\n';
    }
    final stored =
        ExtensionDataStore.instance.read(NewsFeed.qualifiedKeyFor(url));
    if (stored is! Map) {
      return '[Feed]($url)\n';
    }
    final channel = NewsChannel.fromJson(Map<String, Object?>.from(stored));
    final count = (node.attributes[NewsBlockKeys.count] as int?) ?? 6;
    final buffer = StringBuffer();
    if (channel.title.isNotEmpty) {
      buffer.writeln('**${channel.title}**');
      buffer.writeln();
    }
    for (final item in channel.items.take(count)) {
      buffer.writeln(
        item.link.isEmpty ? '- ${item.title}' : '- [${item.title}](${item.link})',
      );
    }
    return '$buffer\n';
  }
}

class NewsBlockComponentBuilder extends BlockComponentBuilder {
  NewsBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return NewsBlockComponent(
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

class NewsBlockComponent extends BlockComponentStatefulWidget {
  const NewsBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<NewsBlockComponent> createState() => _NewsBlockComponentState();
}

class _NewsBlockComponentState extends State<NewsBlockComponent>
    with BlockComponentConfigurable {
  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  String get _url => node.attributes[NewsBlockKeys.url] as String? ?? '';

  String get _label => node.attributes[NewsBlockKeys.label] as String? ?? '';

  int get _count => (node.attributes[NewsBlockKeys.count] as int?) ?? 6;

  bool get _showSummary =>
      node.attributes[NewsBlockKeys.showSummary] != false;

  bool get _showImages => node.attributes[NewsBlockKeys.showImages] != false;

  double? get _width {
    final value = node.attributes[NewsBlockKeys.width];
    return value is num ? value.toDouble() : null;
  }

  double get _height {
    final value = node.attributes[NewsBlockKeys.height];
    return value is num ? value.toDouble() : 320;
  }

  @override
  void initState() {
    super.initState();
    _ensureFresh();
  }

  @override
  void didUpdateWidget(NewsBlockComponent old) {
    super.didUpdateWidget(old);
    _ensureFresh();
  }

  void _ensureFresh() {
    final feed = NewsFeed.active;
    final url = _url;
    if (feed == null || url.isEmpty) {
      return;
    }
    unawaited(feed.watch(url));
    unawaited(feed.refresh(url));
  }

  void _writeSize(String key, double value) {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction..updateNode(node, {key: value});
    unawaited(editorState.apply(transaction));
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ExtensionBoundary(
      extensionId: 'news',
      label: 'a news feed',
      child: ValueListenableBuilder<int>(
        valueListenable: ExtensionDataStore.instance.revision,
        builder: (context, _, __) => _buildCard(context),
      ),
    );

    child = ResizableMedia(
      width: _width ?? 520,
      minWidth: 280,
      height: _height,
      minHeight: 160,
      alignment: blockEmbedAlignment(node),
      onResize: (value) => _writeSize(NewsBlockKeys.width, value),
      onResizeHeight: (value) => _writeSize(NewsBlockKeys.height, value),
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
    final url = _url;
    final entry = url.isEmpty
        ? null
        : ExtensionDataStore.instance.entryFor(NewsFeed.qualifiedKeyFor(url));
    final stored = entry?.value;
    final channel = stored is Map
        ? NewsChannel.fromJson(Map<String, Object?>.from(stored))
        : null;

    return Container(
      constraints: const BoxConstraints.expand(),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
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
      child: NewsBody(
        channel: channel,
        heading: _label.isNotEmpty ? _label : channel?.title ?? '',
        count: _count,
        showSummary: _showSummary,
        showImages: _showImages,
        fetchedAt: entry?.writtenAt,
        onConfigure: () => _configure(context),
      ),
    );
  }

  Future<void> _configure(BuildContext context) async {
    final editorState = context.read<EditorState>();
    final result = await showDialog<
        ({
          String url,
          String label,
          int count,
          bool showSummary,
          bool showImages,
        })>(
      context: context,
      builder: (_) => NewsDialog(
        url: _url,
        label: _label,
        count: _count,
        showSummary: _showSummary,
        showImages: _showImages,
      ),
    );
    if (result == null) {
      return;
    }
    final transaction = editorState.transaction
      ..updateNode(node, {
        NewsBlockKeys.url: result.url,
        NewsBlockKeys.label: result.label,
        NewsBlockKeys.count: result.count,
        NewsBlockKeys.showSummary: result.showSummary,
        NewsBlockKeys.showImages: result.showImages,
      });
    await editorState.apply(transaction);
    unawaited(NewsFeed.active?.watch(result.url));
    unawaited(NewsFeed.active?.refresh(result.url));
  }
}
