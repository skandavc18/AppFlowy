import 'dart:convert';

import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import 'news_publishers.dart';
import 'web_embed_fetch.dart';
import 'web_embed_site_base.dart';

/// Where a site joins its own name onto a page's title.
final _titleJoint = RegExp(r'\s+[|\-–—•»]\s+|\s*\|\s*');

/// Words that name a masthead rather than say what happened.
final _mastheadWords = RegExp(
  r'\b(news|times|today|express|herald|post|live|online|tribune|journal'
  '|daily|samachar|patrika|chronicle|standard|mail|telegraph|guardian'
  r'|breaking|latest|headlines)\b',
);

/// [title] without the masthead a site adds to a headline, so
/// `Budget 2026: what changes - The Times of India` reads
/// `Budget 2026: what changes`.
String tidyWebEmbedHeadline(String title, String site) {
  var text = title.trim();
  final stem = site.toLowerCase().replaceFirst(RegExp(r'^the\s+'), '');
  for (var cut = 0; cut < 3; cut++) {
    final joints = _titleJoint.allMatches(text).toList();
    if (joints.isEmpty || joints.last.start == 0) {
      break;
    }
    final tail = text.substring(joints.last.end).trim().toLowerCase();
    final words = tail.split(RegExp(r'\s+')).length;
    final masthead = tail.isEmpty ||
        tail.contains(stem) ||
        stem.contains(tail) ||
        (words <= 5 && _mastheadWords.hasMatch(tail));
    if (!masthead) {
      break;
    }
    text = text.substring(0, joints.last.start).trim();
  }
  return text;
}

/// [html] as the plain text it reads as.
String? _plainText(String? html) {
  if (html == null) {
    return null;
  }
  final document = html_parser.parse(html.replaceAll('<p>', '\n<p>'));
  final text = document.documentElement?.text.trim();
  return text == null || text.isEmpty ? null : text;
}

/// Articles, videos and live coverage from news sites around the world and
/// across India, shown as the site's own phone page, with its masthead's
/// name and colour on the card.
class NewsEmbeds extends FramedWebEmbedProvider {
  const NewsEmbeds();

  /// What news sites add to an address to see where a reader came from.
  static const _tracking = {
    'at_bbc_team',
    'at_campaign',
    'at_campaign_type',
    'at_custom1',
    'at_custom2',
    'at_custom3',
    'at_custom4',
    'at_format',
    'at_link_id',
    'at_link_origin',
    'at_link_type',
    'at_medium',
    'at_ptr_name',
    'cmp',
    'cmpid',
    'ftag',
    'guccounter',
    'guce_referrer',
    'guce_referrer_sig',
    'int_campaign',
    'int_medium',
    'int_source',
    'itm_campaign',
    'itm_content',
    'itm_medium',
    'itm_source',
    'mc_cid',
    'mc_eid',
    'ncid',
    'ns_campaign',
    'ns_fee',
    'ns_linkname',
    'ns_mchannel',
    'ns_source',
    'ocid',
    'smid',
    'smtyp',
    'sr_share',
    'taid',
    'tpcc',
    'traffic_source',
    'xtor',
  };
  static const _articleMarkers = {
    'article',
    'articles',
    'articleshow',
    'amp_articleshow',
    'story',
    'stories',
    'news-story',
    'newsid',
  };
  static const _liveMarkers = {
    'live',
    'live-updates',
    'liveblog',
    'live-blog',
    'live-news',
    'live-score',
    'livescore',
  };
  static const _videoMarkers = {
    'video',
    'videos',
    'videoshow',
    'watch',
    'av',
  };
  static const _galleryMarkers = {
    'gallery',
    'photos',
    'photogallery',
    'photo-gallery',
    'slideshow',
    'in-pictures',
  };
  static final _articleId = RegExp(r'(?:^|[/_-])\d{6,}(?:[/._-]|$)');
  static final _datedPath =
      RegExp(r'(?:^|/)(?:19|20)\d{2}/(?:0?[1-9]|1[0-2])/');
  static final _pageFile =
      RegExp(r'\.(?:s?html?|cms|ece|php|aspx?)$', caseSensitive: false);

  @override
  String get id => 'news';

  @override
  String get name => 'News';

  @override
  List<String> get keywords => const [
        'news',
        'article',
        'headline',
        'newspaper',
        'bbc',
        'cnn',
        'reuters',
        'times of india',
        'hindustan times',
        'the hindu',
        'ndtv',
        'indian express',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Video' => Icons.movie_rounded,
        'Live' => Icons.wifi_tethering_rounded,
        'Gallery' => Icons.photo_library_rounded,
        'Section' => Icons.feed_rounded,
        'Front page' => Icons.newspaper_rounded,
        _ => Icons.article_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF3B5BDB);

  @override
  bool ownsHost(String host) => webEmbedPublisherFor(host) != null;

  @override
  WebEmbedLink? recognize(Uri uri) {
    final publisher = webEmbedPublisherFor(uri.host.toLowerCase());
    if (publisher == null || isWebEmbedDocument(uri)) {
      return null;
    }
    final page = withoutWebEmbedTracking(
      uri.replace(scheme: 'https'),
      _tracking,
    ).removeFragment();
    final segments = webEmbedSegments(page);
    final kind = _kindOf(page, segments);
    return webEmbedPage(
      this,
      kind,
      page.toString(),
      siteName: publisher.name,
      title: switch (kind) {
        'Front page' => publisher.name,
        'Section' => webEmbedTitleFromSlug(segments.last),
        _ => webEmbedArticleTitle(page),
      },
      height: 720,
      accent: publisher.accent,
    );
  }

  static String _kindOf(Uri page, List<String> segments) {
    if (segments.isEmpty) {
      return 'Front page';
    }
    final lower = [for (final segment in segments) segment.toLowerCase()];
    bool marked(Set<String> markers) => lower.any(markers.contains);
    if (marked(_liveMarkers) ||
        lower.any((segment) => segment.startsWith('live-'))) {
      return 'Live';
    }
    if (marked(_videoMarkers)) {
      return 'Video';
    }
    if (marked(_galleryMarkers)) {
      return 'Gallery';
    }
    final path = lower.join('/');
    if (marked(_articleMarkers) ||
        webEmbedArticleTitle(page) != null ||
        _articleId.hasMatch(path) ||
        _datedPath.hasMatch(path) ||
        _pageFile.hasMatch(path)) {
      return 'Article';
    }
    return 'Section';
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    // A front page or a section only names the paper and what it covers.
    if (link.kind == 'Front page' || link.kind == 'Section') {
      return null;
    }
    return fetchWebEmbedPageDetails(
      link,
      tidyTitle: (title) => tidyWebEmbedHeadline(title, link.site),
    );
  }
}

/// Articles from Google News, which carry the publisher's own address
/// inside their link: shown as that article, the way the publisher's site is
/// shown, and topics, stories and the front page as Google News' phone page.
class GoogleNewsEmbeds extends FramedWebEmbedProvider {
  const GoogleNewsEmbeds();

  /// The language and edition Google News was read in.
  static const _edition = {'hl', 'gl', 'ceid'};

  @override
  String get id => 'google_news';

  @override
  String get name => 'Google News';

  @override
  List<String> get keywords =>
      const ['google news', 'news', 'headlines', 'article', 'topic'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Article' => Icons.article_rounded,
        'Story' => Icons.feed_rounded,
        'Topic' => Icons.tag_rounded,
        'Search' => Icons.search_rounded,
        _ => Icons.newspaper_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF4285F4);

  @override
  bool ownsHost(String host) => host == 'news.google.com';

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (uri.host.toLowerCase() != 'news.google.com') {
      return null;
    }
    final segments = webEmbedSegments(uri);
    final edition = {
      for (final entry in uri.queryParameters.entries)
        if (_edition.contains(entry.key)) entry.key: entry.value,
    };
    String page(List<String> path) => Uri.https(
          'news.google.com',
          path.join('/'),
          edition.isEmpty ? null : edition,
        ).toString();

    final at = segments.indexWhere(
      (segment) => segment == 'articles' || segment == 'read',
    );
    if (at >= 0 && at + 1 < segments.length) {
      final token = segments[at + 1];
      final address = decodeArticle(token);
      if (address != null) {
        final article = ExtensionWebEmbedRegistry.recognize(address);
        if (article != null && article.provider.id != id) {
          return article;
        }
        final target = Uri.parse(address);
        return webEmbedPage(
          this,
          'Article',
          address,
          siteName: target.host.startsWith('www.')
              ? target.host.substring(4)
              : target.host,
          title: webEmbedArticleTitle(target),
          height: 720,
        );
      }
      // Newer links only say where they lead when Google's page is opened,
      // which the frame does, landing on the article itself.
      return webEmbedPage(
        this,
        'Article',
        page(['articles', token]),
        id: token,
        height: 720,
      );
    }
    final first = segments.isEmpty ? '' : segments.first;
    final kind = switch (first) {
      'stories' || 'story' => 'Story',
      'topics' => 'Topic',
      'search' => 'Search',
      'publications' => 'Publication',
      _ => 'Front page',
    };
    return webEmbedPage(
      this,
      kind,
      kind == 'Search'
          ? Uri.https('news.google.com', '/search', {
              ...edition,
              if (uri.queryParameters['q'] != null)
                'q': uri.queryParameters['q']!,
            }).toString()
          : page(segments),
      title: kind == 'Search' ? uri.queryParameters['q'] : null,
      height: 720,
    );
  }

  /// The publisher's address inside an article link's token, which older
  /// links carry as a small protobuf: `08 13 22 <length> <address>…`.
  ///
  /// Null for the newer tokens, which only Google can read.
  static String? decodeArticle(String token) {
    try {
      var text = token.replaceAll('-', '+').replaceAll('_', '/');
      text = text.padRight(text.length + (4 - text.length % 4) % 4, '=');
      final bytes = base64.decode(text);
      var i = bytes.indexOf(0x22);
      if (i < 0 || i > 4) {
        return null;
      }
      i++;
      var length = 0;
      var shift = 0;
      while (i < bytes.length) {
        final byte = bytes[i++];
        length |= (byte & 0x7f) << shift;
        if (byte < 0x80) {
          break;
        }
        shift += 7;
        if (shift > 28) {
          return null;
        }
      }
      if (length <= 0 || i + length > bytes.length) {
        return null;
      }
      final address = utf8.decode(bytes.sublist(i, i + length));
      final uri = parseWebEmbedUri(address);
      return uri == null ||
              !address.startsWith('http') ||
              uri.host.toLowerCase() == 'news.google.com'
          ? null
          : uri.toString();
    } on FormatException {
      return null;
    }
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    if (link.kind != 'Article' || link.host == 'news.google.com') {
      return null;
    }
    return fetchWebEmbedPageDetails(
      link,
      tidyTitle: (title) => tidyWebEmbedHeadline(title, link.site),
    );
  }
}

/// Articles, videos and slideshows from MSN, shown as its phone page.
class MsnEmbeds extends FramedWebEmbedProvider {
  const MsnEmbeds();

  /// `ar-AA1abcde`, the id at the end of every MSN story's address.
  static final _story = RegExp(r'^(ar|vi|ss|gm|cm)-([A-Za-z0-9]{5,})$');

  @override
  String get id => 'msn';

  @override
  String get name => 'MSN';

  @override
  List<String> get keywords =>
      const ['msn', 'microsoft start', 'news', 'article'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Video' => Icons.movie_rounded,
        'Slideshow' => Icons.photo_library_rounded,
        'Front page' || 'Section' => Icons.newspaper_rounded,
        _ => Icons.article_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF1F80E0);

  @override
  bool ownsHost(String host) => host == 'msn.com' || host == 'www.msn.com';

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (!ownsHost(uri.host.toLowerCase())) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    final url = Uri.https('www.msn.com', segments.join('/')).toString();
    final story = segments.isEmpty ? null : _story.firstMatch(segments.last);
    if (story == null) {
      return segments.length <= 2
          ? webEmbedPage(
              this,
              segments.length <= 1 ? 'Front page' : 'Section',
              url,
              height: 720,
            )
          : null;
    }
    return webEmbedPage(
      this,
      switch (story.group(1)) {
        'vi' => 'Video',
        'ss' => 'Slideshow',
        _ => 'Article',
      },
      url,
      id: story.group(2),
      title: segments.length >= 2
          ? webEmbedTitleFromSlug(segments[segments.length - 2])
          : null,
      height: 720,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async =>
      link.kind == 'Front page' || link.kind == 'Section'
          ? null
          : fetchWebEmbedPageDetails(
              link,
              tidyTitle: (title) => tidyWebEmbedHeadline(title, 'MSN'),
            );
}

/// Wikipedia articles in any language, shown as Wikipedia's own phone page,
/// with the article's summary and picture on the card.
class WikipediaEmbeds extends FramedWebEmbedProvider {
  const WikipediaEmbeds();

  static final _host = RegExp(
    r'^([a-z]{2,12}(?:-[a-z0-9]+)*)\.(?:m\.)?wikipedia\.org$',
  );

  @override
  String get id => 'wikipedia';

  @override
  String get name => 'Wikipedia';

  @override
  List<String> get keywords =>
      const ['wikipedia', 'wiki', 'encyclopedia', 'article', 'reference'];

  @override
  IconData iconFor(String kind) => Icons.menu_book_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF3366CC);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'wikipedia.org');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final match = _host.firstMatch(uri.host.toLowerCase());
    final language = match?.group(1);
    if (language == null || language == 'www') {
      return null;
    }
    final segments = webEmbedSegments(uri);
    final title = segments.length >= 2 && segments.first == 'wiki'
        ? segments.skip(1).join('/')
        : segments.length == 2 && segments[1] == 'index.php'
            ? uri.queryParameters['title']
            : null;
    if (title == null || title.trim().isEmpty) {
      return null;
    }
    final path = '/wiki/${title.trim().replaceAll(' ', '_')}';
    final section = uri.hasFragment ? uri.fragment : null;
    String address(String host) =>
        Uri(scheme: 'https', host: host, path: path, fragment: section)
            .toString();
    return webEmbedPage(
      this,
      'Article',
      address('$language.wikipedia.org'),
      id: title,
      title: title.replaceAll('_', ' '),
      height: 720,
    ).copyWith(embedUrl: address('$language.m.wikipedia.org'));
  }

  /// Wikipedia's own summary of the article: its lead and its picture.
  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final title = link.id;
    final host = Uri.tryParse(link.url)?.host;
    if (title == null || host == null) {
      return null;
    }
    final json = await fetchWebEmbedJson(
      Uri.parse(
        'https://$host/api/rest_v1/page/summary/'
        '${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
      ),
    );
    if (json == null) {
      return null;
    }
    final thumbnail = json['thumbnail'];
    final picture = thumbnail is Map<String, dynamic> ? thumbnail : null;
    return WebEmbedDetails(
      title: webEmbedField(json, 'title'),
      description:
          webEmbedField(json, 'extract') ?? webEmbedField(json, 'description'),
      thumbnailUrl: webEmbedField(picture, 'source'),
    );
  }
}

/// Stories, writers and publications from Medium, shown as its phone page.
class MediumEmbeds extends FramedWebEmbedProvider {
  const MediumEmbeds();

  static final _storyId = RegExp(r'-([0-9a-f]{10,12})$');

  /// Medium's own pages rather than a publication.
  static const _reserved = {
    'about',
    'creators',
    'm',
    'me',
    'membership',
    'new-story',
    'plans',
    'policy',
    'search',
    'signin',
    'sitemap',
    'tag',
    'topics',
  };

  @override
  String get id => 'medium';

  @override
  String get name => 'Medium';

  @override
  List<String> get keywords =>
      const ['medium', 'blog', 'story', 'article', 'post', 'writing'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Profile' => Icons.person_rounded,
        'Publication' => Icons.newspaper_rounded,
        'List' => Icons.list_alt_rounded,
        _ => Icons.article_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF242424);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'medium.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!isWebEmbedHost(host, 'medium.com')) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    final url = webEmbedBareAddress(uri);
    final personal = host != 'medium.com' && host != 'www.medium.com';
    if (segments.isEmpty) {
      return personal
          ? webEmbedPage(this, 'Profile', url, title: host.split('.').first)
          : null;
    }
    final last = segments.last;
    final story = _storyId.firstMatch(last);
    if (story != null || (segments.first == 'p' && segments.length >= 2)) {
      return webEmbedPage(
        this,
        'Story',
        url,
        id: story?.group(1) ?? segments[1],
        title: story == null
            ? null
            : webEmbedTitleFromSlug(last.substring(0, story.start)),
        height: 720,
      );
    }
    if (segments.contains('list')) {
      return webEmbedPage(this, 'List', url);
    }
    if (segments.length == 1 && segments.first.startsWith('@')) {
      return webEmbedPage(this, 'Profile', url, title: segments.first);
    }
    return segments.length == 1 &&
            !personal &&
            !_reserved.contains(segments.first.toLowerCase())
        ? webEmbedPage(
            this,
            'Publication',
            url,
            title: webEmbedTitleFromSlug(segments.first),
          )
        : null;
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title.split(' | ').first.trim(),
      );
}

/// Posts, notes and newsletters from Substack, shown as its phone page.
class SubstackEmbeds extends FramedWebEmbedProvider {
  const SubstackEmbeds();

  @override
  String get id => 'substack';

  @override
  String get name => 'Substack';

  @override
  List<String> get keywords =>
      const ['substack', 'newsletter', 'post', 'blog', 'note'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Profile' => Icons.person_rounded,
        'Newsletter' => Icons.newspaper_rounded,
        'Note' => Icons.sticky_note_2_rounded,
        _ => Icons.article_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFFF6719);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'substack.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!isWebEmbedHost(host, 'substack.com')) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (host == 'open.substack.com') {
      return segments.length >= 4 && segments[0] == 'pub' && segments[2] == 'p'
          ? _post(segments[1], segments[3])
          : null;
    }
    if (host == 'substack.com' || host == 'www.substack.com') {
      final url = webEmbedBareAddress(uri);
      if (segments.isNotEmpty && segments.first.startsWith('@')) {
        if (segments.length >= 3 && segments[1] == 'note') {
          return webEmbedPage(this, 'Note', url);
        }
        return segments.length >= 2 && segments[1].startsWith('p-')
            ? webEmbedPage(this, 'Post', url, height: 720)
            : webEmbedPage(this, 'Profile', url, title: segments.first);
      }
      return segments.length >= 3 &&
              segments[0] == 'home' &&
              segments[1] == 'post'
          ? webEmbedPage(this, 'Post', url, height: 720)
          : null;
    }
    final publication = host.substring(0, host.length - '.substack.com'.length);
    if (segments.isEmpty ||
        segments.first == 'archive' ||
        segments.first == 'about') {
      return webEmbedPage(
        this,
        'Newsletter',
        webEmbedBareAddress(uri),
        title: publication,
      );
    }
    return segments.first == 'p' && segments.length >= 2
        ? _post(publication, segments[1])
        : null;
  }

  WebEmbedLink _post(String publication, String slug) => webEmbedPage(
        this,
        'Post',
        'https://$publication.substack.com/p/$slug',
        id: slug,
        title: webEmbedTitleFromSlug(slug),
        height: 720,
      );

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title.split(' - by ').first.trim(),
      );
}

/// Stories, comments and profiles from Hacker News, shown as its page, with
/// the story's title and author from Hacker News' own API.
class HackerNewsEmbeds extends FramedWebEmbedProvider {
  const HackerNewsEmbeds();

  static final _id = RegExp(r'^\d{1,10}$');
  static const _lists = {'news', 'newest', 'front', 'ask', 'show', 'best'};

  @override
  String get id => 'hacker_news';

  @override
  String get name => 'Hacker News';

  @override
  List<String> get keywords => const [
        'hacker news',
        'hn',
        'ycombinator',
        'discussion',
        'tech news',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Profile' => Icons.person_rounded,
        'Front page' => Icons.newspaper_rounded,
        _ => Icons.forum_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFFF6600);

  @override
  bool ownsHost(String host) => host == 'news.ycombinator.com';

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (uri.host.toLowerCase() != 'news.ycombinator.com') {
      return null;
    }
    final segments = webEmbedSegments(uri);
    final item = uri.queryParameters['id'];
    if (segments.length == 1 &&
        segments.first == 'item' &&
        item != null &&
        _id.hasMatch(item)) {
      return webEmbedPage(
        this,
        'Discussion',
        'https://news.ycombinator.com/item?id=$item',
        id: item,
        height: 720,
      );
    }
    if (segments.length == 1 && segments.first == 'user' && item != null) {
      return webEmbedPage(
        this,
        'Profile',
        Uri.https('news.ycombinator.com', '/user', {'id': item}).toString(),
        id: item,
        title: item,
      );
    }
    return segments.isEmpty || _lists.contains(segments.first)
        ? webEmbedPage(
            this,
            'Front page',
            Uri.https('news.ycombinator.com', segments.join('/')).toString(),
            height: 720,
          )
        : null;
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    if (link.kind != 'Discussion' || link.id == null) {
      return null;
    }
    final json = await fetchWebEmbedJson(
      Uri.https('hacker-news.firebaseio.com', '/v0/item/${link.id}.json'),
    );
    if (json == null) {
      return null;
    }
    final text = _plainText(webEmbedField(json, 'text'));
    return WebEmbedDetails(
      title: webEmbedField(json, 'title') ?? webEmbedFirstLine(text),
      author: webEmbedField(json, 'by'),
      description: text,
    );
  }
}

/// Questions and answers from Stack Overflow and the other Stack Exchange
/// sites, shown as the site's own phone page.
class StackExchangeEmbeds extends FramedWebEmbedProvider {
  const StackExchangeEmbeds();

  static const _sites = {
    'stackoverflow.com': 'Stack Overflow',
    'superuser.com': 'Super User',
    'serverfault.com': 'Server Fault',
    'askubuntu.com': 'Ask Ubuntu',
    'mathoverflow.net': 'MathOverflow',
    'stackapps.com': 'Stack Apps',
    'stackexchange.com': 'Stack Exchange',
  };
  static final _id = RegExp(r'^\d{1,12}$');

  @override
  String get id => 'stack_exchange';

  @override
  String get name => 'Stack Overflow';

  @override
  List<String> get keywords => const [
        'stack overflow',
        'stackoverflow',
        'stack exchange',
        'question',
        'answer',
        'programming',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Answer' => Icons.check_circle_rounded,
        'Profile' => Icons.person_rounded,
        _ => Icons.help_outline_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFF48024);

  @override
  bool ownsHost(String host) => isWebEmbedHostOf(host, _sites.keys);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    String? domain;
    for (final candidate in _sites.keys) {
      if (isWebEmbedHost(host, candidate)) {
        domain = candidate;
      }
    }
    if (domain == null) {
      return null;
    }
    // `math.stackexchange.com` is Math Stack Exchange.
    final community = domain == 'stackexchange.com' && host != domain
        ? webEmbedTitleFromSlug(host.split('.').first)
        : null;
    final site =
        community == null ? _sites[domain]! : '$community Stack Exchange';
    final segments = webEmbedSegments(uri);
    if (segments.length < 2 || !_id.hasMatch(segments[1])) {
      return null;
    }
    switch (segments.first) {
      case 'questions':
      case 'q':
        final fragment = uri.hasFragment ? uri.fragment : null;
        final answer = segments.length >= 4 && _id.hasMatch(segments[3])
            ? segments[3]
            : fragment != null && _id.hasMatch(fragment)
                ? fragment
                : null;
        return webEmbedPage(
          this,
          answer == null ? 'Question' : 'Answer',
          Uri(
            scheme: 'https',
            host: host,
            path: uri.path,
            fragment: answer,
          ).toString(),
          siteName: site,
          id: answer ?? segments[1],
          title: segments.length >= 3 && segments.first == 'questions'
              ? webEmbedTitleFromSlug(segments[2], question: true)
              : null,
          height: 720,
        );
      case 'a':
        return webEmbedPage(
          this,
          'Answer',
          'https://$host/a/${segments[1]}',
          siteName: site,
          id: segments[1],
          height: 720,
        );
      case 'users':
        return webEmbedPage(
          this,
          'Profile',
          'https://$host/users/${segments.skip(1).take(2).join('/')}',
          siteName: site,
          id: segments[1],
          title:
              segments.length >= 3 ? webEmbedNameFromSlug(segments[2]) : null,
        );
    }
    return null;
  }

  /// `python - How do I merge two dictionaries? - Stack Overflow` reads
  /// `How do I merge two dictionaries?`.
  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) {
          final parts = title.split(' - ');
          return switch (parts.length) {
            1 => title,
            2 => parts.first,
            _ => parts.sublist(1, parts.length - 1).join(' - '),
          };
        },
      );
}

/// Films, shows, people and lists from IMDb, shown as its phone page.
class IMDbEmbeds extends FramedWebEmbedProvider {
  const IMDbEmbeds();

  static final _title = RegExp(r'^tt\d{5,10}$');
  static final _person = RegExp(r'^nm\d{5,10}$');
  static final _list = RegExp(r'^ls\d{5,12}$');

  @override
  String get id => 'imdb';

  @override
  String get name => 'IMDb';

  @override
  List<String> get keywords => const [
        'imdb',
        'movie',
        'film',
        'tv show',
        'series',
        'actor',
        'cast',
        'rating',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Person' => Icons.person_rounded,
        'List' => Icons.list_alt_rounded,
        _ => Icons.movie_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFF5C518);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'imdb.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final segments = webEmbedSegments(uri);
    if (!isWebEmbedHost(uri.host.toLowerCase(), 'imdb.com') ||
        segments.length < 2) {
      return null;
    }
    final item = segments[1];
    final kind = switch (segments.first) {
      'title' when _title.hasMatch(item) => 'Film or show',
      'name' when _person.hasMatch(item) => 'Person',
      'list' when _list.hasMatch(item) => 'List',
      _ => null,
    };
    return kind == null
        ? null
        : webEmbedPage(
            this,
            kind,
            'https://www.imdb.com/${segments.first}/$item/',
            id: item,
            height: 720,
          );
  }

  /// `Oppenheimer (2023) ⭐ 8.3 | Biography, Drama` reads
  /// `Oppenheimer (2023)`.
  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title
            .split(' ⭐')
            .first
            .split(' | ')
            .first
            .replaceFirst(RegExp(r'\s+-\s+IMDb$'), '')
            .trim(),
      );
}

/// Books, authors, series and lists from Goodreads, shown as its phone page.
class GoodreadsEmbeds extends FramedWebEmbedProvider {
  const GoodreadsEmbeds();

  /// `2767052-the-hunger-games` or `5907.The_Hobbit`.
  static final _item = RegExp(r'^(\d+)(?:[-.](.+))?$');

  @override
  String get id => 'goodreads';

  @override
  String get name => 'Goodreads';

  @override
  List<String> get keywords =>
      const ['goodreads', 'book', 'author', 'review', 'reading list'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Author' => Icons.person_rounded,
        'List' => Icons.list_alt_rounded,
        _ => Icons.book_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF8A6A3B);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'goodreads.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final segments = webEmbedSegments(uri);
    if (!isWebEmbedHost(uri.host.toLowerCase(), 'goodreads.com') ||
        segments.length < 2) {
      return null;
    }
    final section = segments.first;
    final last = segments.last;
    final match = _item.firstMatch(last);
    if (match == null) {
      return null;
    }
    final kind = switch (section) {
      'book' => 'Book',
      'author' => 'Author',
      'series' => 'Series',
      'list' => 'List',
      _ => null,
    };
    if (kind == null) {
      return null;
    }
    final words = match.group(2)?.replaceAll('_', '-');
    return webEmbedPage(
      this,
      kind,
      Uri.https('www.goodreads.com', segments.join('/')).toString(),
      id: match.group(1),
      title: words == null ? null : webEmbedTitleFromSlug(words),
      height: 720,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title.split(' | ').first.trim(),
      );
}

/// Books, films, recordings and software from the Internet Archive, shown in
/// its own embedded player and reader, and Wayback Machine snapshots as the
/// archived page.
class InternetArchiveEmbeds extends FramedWebEmbedProvider {
  const InternetArchiveEmbeds();

  @override
  String get id => 'internet_archive';

  @override
  String get name => 'Internet Archive';

  @override
  List<String> get keywords => const [
        'internet archive',
        'archive.org',
        'wayback machine',
        'archived page',
        'old book',
        'public domain',
      ];

  @override
  IconData iconFor(String kind) => kind == 'Snapshot'
      ? Icons.travel_explore_rounded
      : Icons.menu_book_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF5F6B7A);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'archive.org');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'web.archive.org') {
      return segments.length >= 3 && segments.first == 'web'
          ? webEmbedPage(
              this,
              'Snapshot',
              uri.replace(scheme: 'https').toString(),
              siteName: 'Wayback Machine',
              width: 720,
              height: 720,
            )
          : null;
    }
    if ((host != 'archive.org' && host != 'www.archive.org') ||
        segments.length < 2 ||
        (segments.first != 'details' && segments.first != 'embed')) {
      return null;
    }
    final item = segments.skip(1).join('/');
    return WebEmbedLink(
      provider: this,
      kind: 'Item',
      url: 'https://archive.org/details/$item',
      id: segments[1],
      embedUrl: 'https://archive.org/embed/$item',
      defaultWidth: 640,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    if (link.kind != 'Item') {
      return null;
    }
    return fetchWebEmbedPageDetails(
      link,
      tidyTitle: (title) =>
          title.replaceFirst(RegExp(r'\s*:\s*Free Download.*$'), '').trim(),
    );
  }
}
