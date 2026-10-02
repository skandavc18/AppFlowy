import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/extensions/presentation/web_embed_widgets.dart';
import 'package:flutter/material.dart';

import 'web_embed_fetch.dart';

/// A site shown by loading one of its pages in a [WebEmbedFrame].
abstract class FramedWebEmbedProvider extends WebEmbedProvider {
  const FramedWebEmbedProvider();

  /// Whether a click on [uri] inside one of this site's whole pages should
  /// stay in the frame, like browsing within the site.
  bool ownsHost(String host) => false;

  /// The address the frame loads, which may follow the colour scheme.
  String frameUrlFor(WebEmbedLink link, WebEmbedViewOptions options) =>
      link.embedUrl ?? link.url;

  /// How the page is dressed. A whole page gets the phone layout, which reads
  /// far better than a desktop layout squeezed into a document column.
  WebEmbedPageStyle styleFor(WebEmbedLink link) => isWebEmbedFullPage(link)
      ? WebEmbedPageStyle(
          userAgent: webEmbedMobileUserAgent,
          stayInFrame: (uri) => ownsHost(uri.host.toLowerCase()),
        )
      : const WebEmbedPageStyle();

  @override
  Widget buildView(
    BuildContext context,
    WebEmbedLink link,
    WebEmbedViewOptions options,
  ) =>
      WebEmbedFrame(
        url: frameUrlFor(link, options),
        style: styleFor(link),
        options: options,
        placeholder: WebEmbedLoadingPlaceholder(link: link),
      );
}

bool isWebEmbedFullPage(WebEmbedLink link) => link.showsWholePage;

/// A site whose pages are web apps that lay themselves out for any width,
/// like a file share or a design board, so they keep the renderer's own
/// desktop identity rather than a phone's, which only offers the app.
abstract class AppPageWebEmbedProvider extends FramedWebEmbedProvider {
  const AppPageWebEmbedProvider();

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => link.showsWholePage
      ? WebEmbedPageStyle(
          stayInFrame: (uri) => ownsHost(uri.host.toLowerCase()),
        )
      : const WebEmbedPageStyle();
}

/// [url], a page [provider] has no embed card for, shown as the site's whole
/// page.
WebEmbedLink webEmbedPage(
  WebEmbedProvider provider,
  String kind,
  String url, {
  String? siteName,
  String? id,
  String? title,
  String? thumbnailUrl,
  double width = 560,
  double height = 640,
  bool needsResolution = false,
  Map<String, String> parameters = const {},
  Color? accent,
}) =>
    WebEmbedLink(
      provider: provider,
      kind: kind,
      siteName: siteName,
      url: url,
      id: id,
      embedUrl: needsResolution ? null : url,
      title: title,
      thumbnailUrl: thumbnailUrl,
      defaultWidth: width,
      defaultHeight: height,
      needsResolution: needsResolution,
      parameters: {...parameters, webEmbedFullPage: 'true'},
      accent: accent,
    );

/// What [link]'s own page tells any visitor: its title, summary and picture.
///
/// Null for a sign-in, a bot check or a page that only names its site, whose
/// summary and picture describe the site rather than the link.
Future<WebEmbedDetails?> fetchWebEmbedPageDetails(
  WebEmbedLink link, {
  String? page,
  String userAgent = webEmbedDesktopUserAgent,
  String? Function(String title)? tidyTitle,
}) async {
  final metadata = await fetchWebEmbedPageMetadata(
    Uri.parse(page ?? link.url),
    userAgent: userAgent,
  );
  if (metadata == null) {
    return null;
  }
  var title = webEmbedPageTitle(link, metadata.title);
  if (title != null && tidyTitle != null) {
    title = tidyTitle(title);
  }
  if (title == null) {
    return null;
  }
  return WebEmbedDetails(
    title: title,
    author: metadata.author,
    description: metadata.description,
    thumbnailUrl: metadata.imageUrl ?? link.thumbnailUrl,
  );
}

/// [link] once its short link is followed: what [provider] recognises where
/// it leads, or else the page it lands on, shown whole.
Future<WebEmbedLink?> followWebEmbedShortLink(
  WebEmbedProvider provider,
  WebEmbedLink link,
) async {
  final target = await followWebEmbedRedirects(
    Uri.parse(link.url),
    stopAt: (uri) => provider.recognize(uri)?.needsResolution == false,
  );
  final found = target == null ? null : provider.recognize(target);
  if (found != null && !found.needsResolution) {
    return found;
  }
  // Offline, or the site would not say where it goes: its own page follows
  // the short link in the frame.
  return webEmbedAsFullPage(link, url: target?.toString());
}

/// [link] shown as whatever page [url] is, for a short link that could not be
/// followed to anything more specific.
WebEmbedLink webEmbedAsFullPage(WebEmbedLink link, {String? url}) =>
    link.copyWith(
      needsResolution: false,
      embedUrl: url ?? link.url,
      parameters: {...link.parameters, webEmbedFullPage: 'true'},
    );

/// [uri]'s path segments without the empty ones a trailing slash leaves.
List<String> webEmbedSegments(Uri uri) => [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];

/// Whether [host] is [domain] or one of its subdomains.
bool isWebEmbedHost(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

/// Whether [host] belongs to any of [domains].
bool isWebEmbedHostOf(String host, Iterable<String> domains) =>
    domains.any((domain) => isWebEmbedHost(host, domain));

/// The file type a page's address ends in, like `pdf` or `docx`, or null.
String? webEmbedFileExtension(Uri uri) {
  final segments = webEmbedSegments(uri);
  if (segments.isEmpty) {
    return null;
  }
  final name = segments.last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? null : name.substring(dot + 1).toLowerCase();
}

/// Documents a file viewer shows better than the site around them.
const webEmbedDocumentExtensions = {
  'pdf',
  'doc',
  'docx',
  'docm',
  'dot',
  'dotx',
  'dotm',
  'xls',
  'xlsx',
  'xlsm',
  'xlsb',
  'ppt',
  'pptx',
  'pptm',
  'pps',
  'ppsx',
  'potx',
};

/// Whether [uri] is a document a file viewer should show, not a page.
bool isWebEmbedDocument(Uri uri) =>
    webEmbedDocumentExtensions.contains(webEmbedFileExtension(uri));

/// [uri] without its query and fragment, for sites whose addresses carry
/// only tracking there.
String webEmbedBareAddress(Uri uri) => Uri(
      scheme: 'https',
      host: uri.host.toLowerCase(),
      path: uri.path,
    ).toString();

/// [uri] without the query parameters sites add to track who shared it.
Uri withoutWebEmbedTracking(Uri uri, [Set<String> extra = const {}]) {
  if (!uri.hasQuery) {
    return uri;
  }
  final kept = <String, List<String>>{};
  uri.queryParametersAll.forEach((key, values) {
    final lower = key.toLowerCase();
    if (lower.startsWith('utm_') ||
        _sharedTracking.contains(lower) ||
        extra.contains(lower)) {
      return;
    }
    kept[key] = values;
  });
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: kept.isEmpty ? null : kept,
    fragment: uri.hasFragment ? uri.fragment : null,
  );
}

const _sharedTracking = {
  'fbclid',
  'gclid',
  'igsh',
  'igshid',
  'si',
  'share_id',
  'ref_source',
  'ref',
  'feature',
};

/// A readable title from an address slug, like `best_way_to_learn_dart`.
///
/// Question slugs lose their question mark, so [question] puts one back when
/// the words read like a question.
String? webEmbedTitleFromSlug(
  String slug, {
  String separator = '-',
  bool question = false,
}) {
  // Path segments arrive decoded, so a literal `%` is just a character here.
  final words = slug
      .split(separator)
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty || (words.length == 1 && words.first.length < 3)) {
    return null;
  }
  var title = words.join(' ');
  title = title[0].toUpperCase() + title.substring(1);
  if (question &&
      !title.endsWith('?') &&
      _questionWords.contains(words.first.toLowerCase())) {
    title = '$title?';
  }
  return title;
}

const _questionWords = {
  'what',
  'how',
  'why',
  'when',
  'where',
  'who',
  'whom',
  'whose',
  'which',
  'is',
  'are',
  'am',
  'was',
  'were',
  'can',
  'could',
  'do',
  'does',
  'did',
  'should',
  'would',
  'will',
  'has',
  'have',
  'had',
  'may',
  'might',
  'shall',
};

/// The first line of a post's text, shortened to fit a card's title.
String? webEmbedFirstLine(String? text, {int maxLength = 90}) {
  final line = text?.trim().split('\n').first.trim();
  if (line == null || line.isEmpty) {
    return null;
  }
  return line.length <= maxLength
      ? line
      : '${line.substring(0, maxLength - 1).trim()}…';
}

/// A person's name from a profile slug like `Jane-Doe-12`: the number only
/// tells two people of the same name apart.
String? webEmbedNameFromSlug(String slug) {
  final name =
      slug.replaceAll(RegExp(r'-\d+$'), '').replaceAll('-', ' ').trim();
  return name.isEmpty ? null : name;
}

/// A headline from an article's address: the most worded part of the path,
/// without the id and the `.html` a publisher adds to it, so
/// `/india/budget-2026-what-changes-for-you-1234567.cms` reads
/// `Budget 2026 what changes for you`.
///
/// Null when no part of the path has words enough to be a headline.
String? webEmbedArticleTitle(Uri uri, {int minimumWords = 3}) {
  String? best;
  var bestWords = 0;
  for (final segment in webEmbedSegments(uri)) {
    final slug = segment
        .replaceFirst(_pageExtension, '')
        .replaceFirst(_trailingId, '')
        .replaceAll('_', '-')
        .replaceAll('+', '-');
    final words =
        slug.split('-').where((word) => word.trim().isNotEmpty).length;
    if (words > bestWords) {
      best = slug;
      bestWords = words;
    }
  }
  if (best == null || bestWords < minimumWords) {
    return null;
  }
  return webEmbedTitleFromSlug(best);
}

final _pageExtension = RegExp(
  r'\.(?:s?html?|cms|ece|php|aspx?|jsp|amp)$',
  caseSensitive: false,
);

/// The id a publisher hangs off a headline: `-1234567`, `-a1b2c3d4e5f6` or
/// `-ar-AA1abcd`.
final _trailingId = RegExp(
  r'[-_](?:[a-z]{0,4}-?\d[a-z0-9]{4,}|[0-9a-f]{10,})$',
  caseSensitive: false,
);
