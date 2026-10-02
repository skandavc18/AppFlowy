import 'dart:async';
import 'dart:collection';

import 'package:appflowy/shared/unusable_page_title.dart';
import 'package:flutter/material.dart';

/// Marks a link that is shown as the site's whole page rather than an embed
/// card, because the site has no embed for it or the link could not be
/// followed to one.
const webEmbedFullPage = 'full_page';

/// A link some registered site knows how to show properly, worked out from the
/// address alone.
///
/// Recognising a link never touches the network, so documents, bookmark cards,
/// dashboards and canvases can all ask "is this a Pinterest pin?" while they
/// build. Anything that needs the network — following a short link, reading a
/// title — goes through [ExtensionWebEmbedRegistry.resolve] and
/// [ExtensionWebEmbedRegistry.details] instead.
@immutable
class WebEmbedLink {
  const WebEmbedLink({
    required this.provider,
    required this.kind,
    required this.url,
    this.siteName,
    this.id,
    this.embedUrl,
    this.thumbnailUrl,
    this.title,
    this.defaultWidth = 560,
    this.defaultHeight = 480,
    this.needsResolution = false,
    this.parameters = const {},
    this.accent,
  });

  final WebEmbedProvider provider;

  /// What the link points at within its site: `Pin`, `Comment`, `Answer`,
  /// `Short`, `Spreadsheet`…
  final String kind;

  /// The product's own name when one provider covers several, like
  /// `Google Sheets` or `PowerPoint`.
  final String? siteName;

  /// The address to save and to open in a browser, tidied of share tracking.
  final String url;

  /// The site's own identifier for the thing, when the address carries one.
  final String? id;

  /// What a frame should load to show it, or null when the provider draws it
  /// natively or the link has to be resolved first.
  final String? embedUrl;

  /// A picture for cards, when one can be named without asking the site.
  final String? thumbnailUrl;

  /// A readable name, when the address spells one out.
  final String? title;

  /// The size a new embed starts at before anyone drags it.
  final double defaultWidth;
  final double defaultHeight;

  /// A short link that must be followed before it can be shown.
  final bool needsResolution;

  /// Whatever else the provider parsed out of the address.
  final Map<String, String> parameters;

  /// The colour of the brand behind the link, where one provider covers many,
  /// like the publishers of the news or the stores of a shop.
  final Color? accent;

  String get site => siteName ?? provider.name;

  /// `Reddit · Comment`, or just `Google Sheets` where the product says it.
  String get label => siteName ?? '${provider.name} · $kind';

  IconData get icon => provider.iconFor(kind);

  Color get color => accent ?? provider.colorFor(kind);

  /// A portrait frame reads better for pins, reels and Shorts.
  bool get isPortrait => defaultHeight > defaultWidth * 1.2;

  /// Shown as the site's whole page: an article, a product or a profile the
  /// site has no embed card for.
  bool get showsWholePage => parameters[webEmbedFullPage] == 'true';

  /// The address's host without `www.`, for a card's byline.
  String get host {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  WebEmbedLink copyWith({
    String? kind,
    String? url,
    String? siteName,
    String? id,
    String? embedUrl,
    String? thumbnailUrl,
    String? title,
    double? defaultWidth,
    double? defaultHeight,
    bool? needsResolution,
    Map<String, String>? parameters,
    Color? accent,
  }) =>
      WebEmbedLink(
        provider: provider,
        kind: kind ?? this.kind,
        url: url ?? this.url,
        siteName: siteName ?? this.siteName,
        id: id ?? this.id,
        embedUrl: embedUrl ?? this.embedUrl,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        title: title ?? this.title,
        defaultWidth: defaultWidth ?? this.defaultWidth,
        defaultHeight: defaultHeight ?? this.defaultHeight,
        needsResolution: needsResolution ?? this.needsResolution,
        parameters: parameters ?? this.parameters,
        accent: accent ?? this.accent,
      );

  @override
  bool operator ==(Object other) =>
      other is WebEmbedLink &&
      other.provider.id == provider.id &&
      other.kind == kind &&
      other.url == url &&
      other.embedUrl == embedUrl &&
      other.needsResolution == needsResolution;

  @override
  int get hashCode =>
      Object.hash(provider.id, kind, url, embedUrl, needsResolution);
}

/// What a site says about one of its links when asked.
@immutable
class WebEmbedDetails {
  const WebEmbedDetails({
    this.title,
    this.author,
    this.description,
    this.thumbnailUrl,
    this.width,
    this.height,
  });

  final String? title;
  final String? author;
  final String? description;
  final String? thumbnailUrl;

  /// The natural size of the embedded thing, when the site reports it.
  final double? width;
  final double? height;

  bool get isEmpty =>
      title == null &&
      author == null &&
      description == null &&
      thumbnailUrl == null;
}

/// How a view is being shown, so a provider can draw less where less fits.
@immutable
class WebEmbedViewOptions {
  const WebEmbedViewOptions({
    this.interactive = true,
    this.brightness = Brightness.light,
    this.reloadToken = 0,
    this.onContentHeight,
  });

  /// False on a canvas that is being dragged or zoomed, or anywhere a live
  /// page would steal the pointer; the page is still shown but not touched.
  final bool interactive;

  final Brightness brightness;

  /// Changed by the host to load the page again.
  final int reloadToken;

  /// Told how tall the page's own content is, for a host that sizes itself
  /// to it. Only pages that fit their content report.
  final ValueChanged<double>? onContentHeight;
}

/// A site whose links deserve better than a generic preview card.
abstract class WebEmbedProvider {
  const WebEmbedProvider();

  /// Stable, never renamed: it is what cards and filters key on.
  String get id;

  /// The site's own name, shown on badges.
  String get name;

  /// Words a search or a slash menu should find the site by.
  List<String> get keywords => const [];

  IconData iconFor(String kind);

  Color colorFor(String kind);

  /// The link, if it belongs to this site and can be shown. Offline and cheap.
  WebEmbedLink? recognize(Uri uri);

  /// A short link followed to the address it stands for; others unchanged.
  Future<WebEmbedLink?> resolve(WebEmbedLink link) async => link;

  /// Title, author and picture, from the site's oEmbed endpoint where it has
  /// one. Null when the site will not say.
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async => null;

  /// The live view of [link], filling whatever size it is given.
  Widget buildView(
    BuildContext context,
    WebEmbedLink link,
    WebEmbedViewOptions options,
  );
}

@immutable
class _RegisteredWebEmbed {
  const _RegisteredWebEmbed(this.extensionId, this.provider);

  final String extensionId;
  final WebEmbedProvider provider;
}

/// Every site extensions have taught the app to embed.
///
/// Documents, bookmark collections, dashboards and canvases all ask here, so
/// turning the extension off drops each of them back to the generic link card
/// at once, and turning it on upgrades links that were saved before.
abstract final class ExtensionWebEmbedRegistry {
  static final Map<String, _RegisteredWebEmbed> _providers = {};

  /// Answers already fetched, so a card that scrolls back into view does not
  /// ask the site again. Failures are not kept, so they are retried.
  static final LinkedHashMap<String, Future<WebEmbedLink?>> _resolved =
      LinkedHashMap();
  static final LinkedHashMap<String, Future<WebEmbedDetails?>> _details =
      LinkedHashMap();

  static const int _cacheLimit = 256;
  static const Duration _deadline = Duration(seconds: 15);

  /// Bumped whenever the set changes, so whatever drew a link can redraw it.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void register(String extensionId, WebEmbedProvider provider) {
    _providers['$extensionId/${provider.id}'] =
        _RegisteredWebEmbed(extensionId, provider);
    _raise();
  }

  static void unregisterAll(String extensionId) {
    final doomed = [
      for (final entry in _providers.entries)
        if (entry.value.extensionId == extensionId) entry.key,
    ];
    if (doomed.isEmpty) {
      return;
    }
    for (final key in doomed) {
      _providers.remove(key);
    }
    _resolved.clear();
    _details.clear();
    _raise();
  }

  static List<WebEmbedProvider> all() => List.unmodifiable(
        [for (final entry in _providers.values) entry.provider],
      );

  /// The extension that registered [provider], to name it when it fails.
  static String? extensionIdOf(WebEmbedProvider provider) {
    for (final entry in _providers.values) {
      if (entry.provider.id == provider.id) {
        return entry.extensionId;
      }
    }
    return null;
  }

  static WebEmbedProvider? providerById(String id) {
    for (final entry in _providers.values) {
      if (entry.provider.id == id) {
        return entry.provider;
      }
    }
    return null;
  }

  /// The first registered site that recognises [url], or null.
  ///
  /// ⚠️ A provider that throws is treated as not recognising the link: a bad
  /// pattern in one site must not break every card in a collection.
  static WebEmbedLink? recognize(String? url) {
    final uri = parseWebEmbedUri(url);
    if (uri == null || _providers.isEmpty) {
      return null;
    }
    for (final entry in _providers.values) {
      try {
        final link = entry.provider.recognize(uri);
        if (link != null) {
          return link;
        }
      } on Object catch (error) {
        debugPrint('Web embed ${entry.provider.id} failed on $url: $error');
      }
    }
    return null;
  }

  /// [link] with its short link followed, or null when it leads nowhere
  /// showable. A link that needs no following comes straight back.
  static Future<WebEmbedLink?> resolve(WebEmbedLink link) {
    if (!link.needsResolution) {
      return Future.value(link);
    }
    return _remember(
      _resolved,
      '${link.provider.id} ${link.url}',
      () => link.provider.resolve(link),
    );
  }

  /// What the site says about [link], asked once per address.
  static Future<WebEmbedDetails?> details(WebEmbedLink link) => _remember(
        _details,
        '${link.provider.id} ${link.url}',
        () => link.provider.fetchDetails(link),
      );

  /// The address a bookmark should be saved under: a site's canonical form of
  /// [url] when one is registered, [url] itself otherwise.
  static String canonicalUrl(String url) {
    final link = recognize(url);
    return link == null || link.needsResolution ? url : link.url;
  }

  /// The address to keep for [link]: where its short link leads, when a site
  /// recognises that on its own, or else the short link, which is followed
  /// again each time it is shown.
  static Future<String> settledUrl(
    WebEmbedLink link, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!link.needsResolution) {
      return link.url;
    }
    final resolved =
        await resolve(link).timeout(timeout, onTimeout: () => null);
    final settled = recognize(resolved?.url);
    return settled == null || settled.needsResolution ? link.url : settled.url;
  }

  static Future<T?> _remember<T>(
    LinkedHashMap<String, Future<T?>> cache,
    String key,
    Future<T?> Function() load,
  ) {
    final existing = cache.remove(key);
    if (existing != null) {
      // Most recently used goes last, so the oldest is dropped first.
      cache[key] = existing;
      return existing;
    }
    late final Future<T?> future;
    future = Future<T?>.sync(load).timeout(_deadline).then<T?>(
      (value) {
        if (value == null && identical(cache[key], future)) {
          cache.remove(key);
        }
        return value;
      },
      onError: (Object error) {
        if (identical(cache[key], future)) {
          cache.remove(key);
        }
        debugPrint('Web embed lookup failed for $key: $error');
        return null;
      },
    );
    cache[key] = future;
    while (cache.length > _cacheLimit) {
      cache.remove(cache.keys.first);
    }
    return future;
  }

  static void _raise() => revision.value = revision.value + 1;
}

/// [title], read off [link]'s own page, or null when it is only what a site
/// shows a visitor it will not answer: its bare name, or a sign-in page.
String? webEmbedPageTitle(WebEmbedLink link, String? title) {
  final value = title?.trim() ?? '';
  final lower = value.toLowerCase();
  if (lower.isEmpty ||
      lower == link.site.toLowerCase() ||
      lower == link.provider.name.toLowerCase() ||
      _signInTitle.hasMatch(lower) ||
      isUnusablePageTitle(value, url: link.url)) {
    return null;
  }
  return value;
}

/// `Sign in to your account`, `Login • Instagram`, `Google Docs: Sign-in`.
final _signInTitle = RegExp(
  r'^(sign[ -]?in|log[ -]?in|login)\b'
  r'|[:•·|–-]\s*(sign[ -]?in|log[ -]?in|login)\b'
  r'|\b(sign[ -]?in|log[ -]?in|login)\s*[:•·|–-]',
);

/// The address in whatever was pasted: a link, or a site's embed code —
/// a permalink attribute such as Instagram's or Threads', an `<iframe src>`,
/// or the `href`s Pinterest's, Reddit's and X's codes name the post with.
///
/// Embed code also links the author, the community and the hashtags, so the
/// address a registered site can show as a post is preferred over the rest.
String? webEmbedAddressFrom(String? text) {
  final value = text?.trim() ?? '';
  if (!value.contains('<')) {
    return parseWebEmbedUri(value)?.toString();
  }
  final found = <Uri>[];
  for (final pattern in _embedCodeAddresses) {
    for (final match in pattern.allMatches(value)) {
      final address = match
          .group(1)!
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'");
      final uri = parseWebEmbedUri(address);
      if (uri != null) {
        found.add(uri);
      }
    }
  }
  Uri? known;
  for (final uri in found) {
    final link = ExtensionWebEmbedRegistry.recognize(uri.toString());
    if (link == null) {
      continue;
    }
    if (!link.needsResolution && !link.showsWholePage) {
      return uri.toString();
    }
    known ??= uri;
  }
  return (known ?? (found.isEmpty ? null : found.first))?.toString();
}

final _embedCodeAddresses = [
  for (final attribute in const [
    'data-instgrm-permalink',
    'data-text-post-permalink',
    'data-snapchat-embed-url',
    'cite',
    'data-href',
  ])
    RegExp(
      '\\s$attribute\\s*=\\s*["\']([^"\']+)["\']',
      caseSensitive: false,
    ),
  RegExp(
    r'''<iframe\b[^>]*?\ssrc\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ),
  RegExp(r'''\shref\s*=\s*["']([^"']+)["']''', caseSensitive: false),
];

/// [text] as a web address, accepting the bare `www.site.com/…` people paste.
Uri? parseWebEmbedUri(String? text) {
  var value = text?.trim() ?? '';
  if (value.isEmpty || value.contains(RegExp(r'\s'))) {
    return null;
  }
  if (!value.contains('://')) {
    value = 'https://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' ? uri : null;
}
