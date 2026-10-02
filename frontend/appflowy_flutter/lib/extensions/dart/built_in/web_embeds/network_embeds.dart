import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/shared/unusable_page_title.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import 'web_embed_fetch.dart';
import 'web_embed_site_base.dart';

/// A card page draws on whatever surface holds its frame.
const _transparentPage = 'html, body { background: transparent !important; }';

/// What a post's own page says: its text as the title and whoever wrote it,
/// for sites whose page title only names the author.
Future<WebEmbedDetails?> _postPageDetails(
  WebEmbedLink link, {
  String? Function(String title)? author,
}) async {
  final metadata = await fetchWebEmbedPageMetadata(Uri.parse(link.url));
  // A bot check's text would read as the post's.
  if (metadata == null || isStandInPageTitle(metadata.title)) {
    return null;
  }
  final named = webEmbedPageTitle(link, metadata.title);
  final text = metadata.description?.trim();
  final details = WebEmbedDetails(
    title: webEmbedFirstLine(text) ?? link.title,
    author: named == null ? null : (author?.call(named) ?? named),
    description: text == null || text.isEmpty ? null : text,
    thumbnailUrl: metadata.imageUrl,
  );
  return named == null && text == null ? null : details;
}

/// Posts, shown as X's own embedded post, and profiles, lists and Spaces,
/// which X has no card for, as its phone page.
class XEmbeds extends FramedWebEmbedProvider {
  const XEmbeds();

  static const _hosts = {
    'x.com',
    'www.x.com',
    'mobile.x.com',
    'twitter.com',
    'www.twitter.com',
    'mobile.twitter.com',
    'm.twitter.com',
    // Mirrors people share so that a post previews in chat apps.
    'fxtwitter.com',
    'vxtwitter.com',
    'fixupx.com',
    'fixvx.com',
  };
  static final _id = RegExp(r'^\d{5,25}$');
  static final _token = RegExp(r'^[A-Za-z0-9]{5,25}$');
  static final _handle = RegExp(r'^[A-Za-z0-9_]{1,15}$');

  /// First segments that are X's own pages rather than someone's handle.
  static const _reserved = {
    'about',
    'account',
    'compose',
    'download',
    'explore',
    'hashtag',
    'home',
    'i',
    'intent',
    'jobs',
    'login',
    'logout',
    'messages',
    'notifications',
    'privacy',
    'search',
    'settings',
    'share',
    'signup',
    'tos',
  };

  /// Tabs of a profile, which are still the profile.
  static const _profileTabs = {
    'with_replies',
    'media',
    'likes',
    'highlights',
    'articles',
    'lists',
    'followers',
    'following',
    'verified_followers',
  };

  @override
  String get id => 'x';

  @override
  String get name => 'X';

  @override
  List<String> get keywords =>
      const ['x', 'twitter', 'tweet', 'post', 'thread', 'x.com'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Profile' => Icons.person_rounded,
        'List' => Icons.list_alt_rounded,
        'Space' => Icons.graphic_eq_rounded,
        'Community' => Icons.groups_rounded,
        _ => Icons.chat_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF0F1419);

  @override
  bool ownsHost(String host) => _hosts.contains(host);

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (!_hosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (segments.isEmpty) {
      return null;
    }
    var at = segments.indexOf('status');
    if (at < 0) {
      at = segments.indexOf('statuses');
    }
    if (at >= 0 && at + 1 < segments.length && _id.hasMatch(segments[at + 1])) {
      final handle = at == 1 &&
              !_reserved.contains(segments[0].toLowerCase()) &&
              _handle.hasMatch(segments[0])
          ? segments[0]
          : null;
      return _post(segments[at + 1], handle);
    }
    if (segments.first == 'i') {
      if (segments.length < 3 || !_token.hasMatch(segments[2])) {
        return null;
      }
      final kind = switch (segments[1]) {
        'lists' => 'List',
        'spaces' => 'Space',
        'communities' => 'Community',
        _ => null,
      };
      return kind == null
          ? null
          : webEmbedPage(
              this,
              kind,
              'https://x.com/i/${segments[1]}/${segments[2]}',
              id: segments[2],
            );
    }
    final handle = segments.first;
    if (segments.length > 2 ||
        _reserved.contains(handle.toLowerCase()) ||
        !_handle.hasMatch(handle) ||
        (segments.length == 2 &&
            !_profileTabs.contains(segments[1].toLowerCase()))) {
      return null;
    }
    return webEmbedPage(
      this,
      'Profile',
      'https://x.com/$handle',
      id: handle,
      title: '@$handle',
    );
  }

  WebEmbedLink _post(String id, String? handle) => WebEmbedLink(
        provider: this,
        kind: 'Post',
        url: handle == null
            ? 'https://x.com/i/status/$id'
            : 'https://x.com/$handle/status/$id',
        id: id,
        embedUrl: Uri.https('platform.twitter.com', '/embed/Tweet.html', {
          'id': id,
          'dnt': 'true',
        }).toString(),
        defaultWidth: 550,
        defaultHeight: 600,
        parameters: {if (handle != null) 'author': handle},
      );

  @override
  String frameUrlFor(WebEmbedLink link, WebEmbedViewOptions options) {
    final embed = link.embedUrl ?? link.url;
    if (link.showsWholePage) {
      return embed;
    }
    final uri = Uri.parse(embed);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'theme': options.brightness == Brightness.dark ? 'dark' : 'light',
      },
    ).toString();
  }

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => link.showsWholePage
      ? super.styleFor(link)
      : const WebEmbedPageStyle(fitsContent: true, css: _transparentPage);

  /// X's oEmbed answers for any public post, with its text in the markup.
  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    if (link.showsWholePage) {
      return null;
    }
    final json = await fetchWebEmbedJson(
      Uri.https('publish.twitter.com', '/oembed', {
        'url': link.url,
        'omit_script': 'true',
        'dnt': 'true',
      }),
    );
    if (json == null) {
      return null;
    }
    final html = webEmbedField(json, 'html');
    final text = html == null
        ? null
        : html_parser.parse(html).querySelector('p')?.text.trim();
    return WebEmbedDetails(
      title: webEmbedFirstLine(text),
      author: webEmbedField(json, 'author_name'),
      description: text == null || text.isEmpty ? null : text,
    );
  }
}

/// Posts, shown as LinkedIn's own embedded post, and profiles, companies,
/// jobs and articles, which LinkedIn has no card for, as its phone page.
class LinkedInEmbeds extends FramedWebEmbedProvider {
  const LinkedInEmbeds();

  static final _urn = RegExp(r'^urn:li:(activity|share|ugcPost):(\d{10,25})$');

  /// `jane-doe_hiring-activity-7123456789012345678-AbCd`
  static final _postSlug =
      RegExp(r'-(activity|share|ugcPost)-(\d{10,25})(?:-|$)');
  static final _jobId = RegExp(r'(\d{6,})$');

  /// Profile slugs end in a token that only tells namesakes apart.
  static final _profileSuffix = RegExp(r'-[a-z0-9]*\d[a-z0-9]*$');

  static const _pages = {
    'in': 'Profile',
    'company': 'Company',
    'showcase': 'Company',
    'school': 'School',
    'pulse': 'Article',
    'newsletters': 'Newsletter',
    'events': 'Event',
    'groups': 'Group',
    'learning': 'Course',
  };

  @override
  String get id => 'linkedin';

  @override
  String get name => 'LinkedIn';

  @override
  List<String> get keywords => const [
        'linkedin',
        'post',
        'profile',
        'company',
        'job',
        'article',
        'professional',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Profile' => Icons.person_rounded,
        'Company' => Icons.business_rounded,
        'School' || 'Course' => Icons.school_rounded,
        'Article' => Icons.article_rounded,
        'Newsletter' => Icons.newspaper_rounded,
        'Event' => Icons.event_rounded,
        'Group' => Icons.groups_rounded,
        'Job' => Icons.work_outline_rounded,
        _ => Icons.work_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF0A66C2);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'linkedin.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (!isWebEmbedHost(uri.host.toLowerCase(), 'linkedin.com')) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (segments.isEmpty) {
      return null;
    }
    // The address inside a post's Embed code.
    if (segments.length >= 4 &&
        segments[0] == 'embed' &&
        segments[1] == 'feed' &&
        segments[2] == 'update') {
      return _post(segments[3]);
    }
    if (segments.length >= 3 &&
        segments[0] == 'feed' &&
        segments[1] == 'update') {
      return _post(segments[2]);
    }
    if (segments[0] == 'posts' && segments.length >= 2) {
      final page = 'https://www.linkedin.com/posts/${segments[1]}/';
      final match = _postSlug.firstMatch(segments[1]);
      return (match == null
              ? null
              : _post('urn:li:${match.group(1)}:${match.group(2)}', page)) ??
          webEmbedPage(this, 'Post', page);
    }
    if (segments[0] == 'jobs' &&
        segments.length >= 3 &&
        segments[1] == 'view') {
      final id = _jobId.firstMatch(segments[2])?.group(1);
      return id == null
          ? null
          : webEmbedPage(
              this,
              'Job',
              'https://www.linkedin.com/jobs/view/$id/',
              id: id,
              title: id == segments[2]
                  ? null
                  : webEmbedTitleFromSlug(
                      segments[2].substring(0, segments[2].length - id.length),
                    ),
            );
    }
    final kind = _pages[segments[0]];
    if (kind == null || segments.length < 2) {
      return null;
    }
    final slug = segments[1];
    return webEmbedPage(
      this,
      kind,
      Uri.https('www.linkedin.com', '/${segments[0]}/$slug/').toString(),
      id: slug,
      title:
          kind == 'Profile' ? _personName(slug) : webEmbedTitleFromSlug(slug),
    );
  }

  WebEmbedLink? _post(String urn, [String? page]) {
    final match = _urn.firstMatch(urn);
    if (match == null) {
      return null;
    }
    final normalized = 'urn:li:${match.group(1)}:${match.group(2)}';
    return WebEmbedLink(
      provider: this,
      kind: 'Post',
      url: page ?? 'https://www.linkedin.com/feed/update/$normalized/',
      id: match.group(2),
      embedUrl: 'https://www.linkedin.com/embed/feed/update/$normalized',
      defaultWidth: 504,
      defaultHeight: 600,
    );
  }

  static String? _personName(String slug) {
    final words = slug
        .replaceFirst(_profileSuffix, '')
        .split('-')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1));
    final name = words.join(' ');
    return name.isEmpty ? null : name;
  }

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => link.showsWholePage
      ? super.styleFor(link)
      : const WebEmbedPageStyle(fitsContent: true);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) =>
            title.replaceFirst(RegExp(r'\s*\|\s*LinkedIn$'), '').trim(),
      );
}

/// Posts, photos and videos, shown in Facebook's own post and video plugins,
/// and Pages in its Page plugin. Groups, events and profiles, which have no
/// plugin, show as Facebook's phone page.
class FacebookEmbeds extends FramedWebEmbedProvider {
  const FacebookEmbeds();

  static const _hosts = {
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'mbasic.facebook.com',
    'web.facebook.com',
    'touch.facebook.com',
    'fb.com',
    'www.fb.com',
  };
  static final _numeric = RegExp(r'^\d{5,25}$');

  /// First segments that are Facebook's own pages rather than a Page's name.
  static const _reserved = {
    'about',
    'ads',
    'bookmarks',
    'business',
    'careers',
    'checkpoint',
    'dialog',
    'friends',
    'gaming',
    'hashtag',
    'help',
    'home.php',
    'l.php',
    'legal',
    'login',
    'login.php',
    'media',
    'memories',
    'messages',
    'notifications',
    'pages',
    'plugins',
    'policies',
    'privacy',
    'recover',
    'reg',
    'saved',
    'search',
    'settings',
    'sharer',
    'sharer.php',
    'signup',
    'stories',
    'terms',
    'video.php',
  };

  @override
  String get id => 'facebook';

  @override
  String get name => 'Facebook';

  @override
  List<String> get keywords => const [
        'facebook',
        'fb',
        'post',
        'page',
        'video',
        'reel',
        'group',
        'meta',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Video' => Icons.movie_rounded,
        'Reel' => Icons.movie_filter_rounded,
        'Photo' => Icons.image_rounded,
        'Page' => Icons.flag_rounded,
        'Group' => Icons.groups_rounded,
        'Event' => Icons.event_rounded,
        'Profile' => Icons.person_rounded,
        'Listing' => Icons.local_offer_rounded,
        _ => Icons.thumb_up_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF1877F2);

  @override
  bool ownsHost(String host) => _hosts.contains(host) || host == 'fb.watch';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    final query = uri.queryParameters;
    if (host == 'fb.watch') {
      return segments.length == 1
          ? _short('Video', 'https://fb.watch/${segments.first}/')
          : null;
    }
    if (!_hosts.contains(host) || segments.isEmpty) {
      return null;
    }

    String page(Iterable<String> path, [Map<String, String>? keep]) =>
        Uri.https(
          'www.facebook.com',
          path.join('/'),
          keep == null || keep.isEmpty ? null : keep,
        ).toString();

    switch (segments.first.toLowerCase()) {
      case 'share':
        // `/share/p/<code>/`, `/share/v/<code>/`, `/share/r/<code>/`: only
        // following them says which post they are.
        if (segments.length < 2) {
          return null;
        }
        return _short(
          switch (segments[1]) {
            'v' => 'Video',
            'r' => 'Reel',
            _ => 'Post',
          },
          '${page(segments)}/',
        );
      case 'watch':
        final video = query['v'];
        return video != null && _numeric.hasMatch(video)
            ? _video('Video', page(['watch'], {'v': video}), video)
            : null;
      case 'reel':
        return segments.length >= 2 && _numeric.hasMatch(segments[1])
            ? _video('Reel', page(segments.take(2)), segments[1])
            : null;
      case 'permalink.php':
      case 'story.php':
        final story = query['story_fbid'];
        final owner = query['id'];
        return story == null || owner == null
            ? null
            : _post(
                'Post',
                page(['permalink.php'], {'story_fbid': story, 'id': owner}),
                story,
              );
      case 'photo.php':
      case 'photo':
        final photo = query['fbid'];
        return photo == null
            ? null
            : _post('Photo', page(['photo'], {'fbid': photo}), photo);
      case 'groups':
        if (segments.length >= 4 &&
            (segments[2] == 'posts' || segments[2] == 'permalink')) {
          return _post('Post', page(segments.take(4)), segments[3]);
        }
        return segments.length >= 2
            ? webEmbedPage(
                this,
                'Group',
                page(segments.take(2)),
                id: segments[1],
              )
            : null;
      case 'events':
        return segments.length >= 2
            ? webEmbedPage(this, 'Event', page(segments.take(2)))
            : null;
      case 'marketplace':
        return segments.length >= 3 && segments[1] == 'item'
            ? webEmbedPage(this, 'Listing', page(segments.take(3)))
            : null;
      case 'profile.php':
        final person = query['id'];
        return person == null
            ? null
            : webEmbedPage(
                this,
                'Profile',
                page(['profile.php'], {'id': person}),
              );
    }
    if (_reserved.contains(segments.first.toLowerCase())) {
      return null;
    }
    // `/<page>/posts/<id>`, `/<page>/videos/…/<id>`, `/<page>/photos/…/<id>`.
    if (segments.length >= 3) {
      final section = segments[1].toLowerCase();
      final last = segments.last;
      if (section == 'posts') {
        return _post('Post', page(segments.take(3)), segments[2]);
      }
      if (section == 'videos' && _numeric.hasMatch(last)) {
        return _video('Video', page(segments), last);
      }
      if (section == 'photos' && _numeric.hasMatch(last)) {
        return _post('Photo', page(segments), last);
      }
      return null;
    }
    return _pagePlugin(segments.first);
  }

  static String _plugin(
    String kind,
    String href,
    Map<String, String> options,
  ) =>
      Uri.https('www.facebook.com', '/plugins/$kind.php', {
        'href': href,
        ...options,
      }).toString();

  WebEmbedLink _post(String kind, String url, String id) => WebEmbedLink(
        provider: this,
        kind: kind,
        url: url,
        id: id,
        embedUrl: _plugin('post', url, {'show_text': 'true', 'width': '500'}),
        defaultWidth: 500,
        defaultHeight: 600,
      );

  WebEmbedLink _video(String kind, String url, String id) {
    final reel = kind == 'Reel';
    return WebEmbedLink(
      provider: this,
      kind: kind,
      url: url,
      id: id,
      embedUrl: _plugin('video', url, {
        'show_text': 'false',
        'width': reel ? '340' : '560',
      }),
      defaultWidth: reel ? 340 : 560,
      defaultHeight: reel ? 604 : 315,
    );
  }

  WebEmbedLink _pagePlugin(String name) {
    final url = 'https://www.facebook.com/$name';
    return WebEmbedLink(
      provider: this,
      kind: 'Page',
      url: url,
      id: name,
      embedUrl: _plugin('page', url, {
        'tabs': 'timeline',
        'width': '500',
        'height': '700',
        'small_header': 'false',
        'adapt_container_width': 'true',
        'hide_cover': 'false',
        'show_facepile': 'true',
      }),
      title: name,
      defaultWidth: 500,
      defaultHeight: 700,
    );
  }

  WebEmbedLink _short(String kind, String url) => WebEmbedLink(
        provider: this,
        kind: kind,
        url: url,
        defaultWidth: kind == 'Reel' ? 340 : 500,
        defaultHeight: kind == 'Reel' ? 604 : 600,
        needsResolution: true,
      );

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) {
    if (link.showsWholePage) {
      return super.styleFor(link);
    }
    return WebEmbedPageStyle(
      fitsContent: link.kind == 'Post' || link.kind == 'Photo',
    );
  }
}

/// Posts, shown as Threads' own embedded post, and profiles as its phone
/// page.
class ThreadsEmbeds extends FramedWebEmbedProvider {
  const ThreadsEmbeds();

  /// Threads moved from `threads.net` to `threads.com`; both still answer.
  static const _domains = {'threads.com', 'threads.net'};
  static final _code = RegExp(r'^[A-Za-z0-9_-]{6,}$');

  @override
  String get id => 'threads';

  @override
  String get name => 'Threads';

  @override
  List<String> get keywords => const ['threads', 'post', 'meta', 'thread'];

  @override
  IconData iconFor(String kind) =>
      kind == 'Profile' ? Icons.person_rounded : Icons.alternate_email_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF101010);

  @override
  bool ownsHost(String host) => isWebEmbedHostOf(host, _domains);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    String? domain;
    for (final candidate in _domains) {
      if (isWebEmbedHost(host, candidate)) {
        domain = candidate;
      }
    }
    final segments = webEmbedSegments(uri);
    if (domain == null || segments.isEmpty || !segments[0].startsWith('@')) {
      return null;
    }
    final user = segments[0].substring(1);
    if (user.isEmpty) {
      return null;
    }
    if (segments.length >= 3 &&
        (segments[1] == 'post' || segments[1] == 't') &&
        _code.hasMatch(segments[2])) {
      final url = 'https://www.$domain/@$user/post/${segments[2]}';
      return WebEmbedLink(
        provider: this,
        kind: 'Post',
        url: url,
        id: segments[2],
        embedUrl: '$url/embed',
        defaultWidth: 540,
        defaultHeight: 640,
        parameters: {'author': user},
      );
    }
    return segments.length == 1
        ? webEmbedPage(
            this,
            'Profile',
            'https://www.$domain/@$user',
            id: user,
            title: '@$user',
          )
        : null;
  }

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => link.showsWholePage
      ? super.styleFor(link)
      : const WebEmbedPageStyle(fitsContent: true, css: _transparentPage);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) => _postPageDetails(
        link,
        author: (title) => title.replaceFirst(RegExp(r'\s+on Threads$'), ''),
      );
}

/// Videos and photo posts, shown in TikTok's own player, and profiles as its
/// phone page.
class TikTokEmbeds extends FramedWebEmbedProvider {
  const TikTokEmbeds();

  static final _id = RegExp(r'^\d{10,25}$');

  @override
  String get id => 'tiktok';

  @override
  String get name => 'TikTok';

  @override
  List<String> get keywords =>
      const ['tiktok', 'tik tok', 'video', 'short video', 'clip'];

  @override
  IconData iconFor(String kind) =>
      kind == 'Profile' ? Icons.person_rounded : Icons.music_note_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFFFE2C55);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'tiktok.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!isWebEmbedHost(host, 'tiktok.com')) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (host == 'vm.tiktok.com' || host == 'vt.tiktok.com') {
      return segments.length == 1
          ? _short('https://$host/${segments.first}/')
          : null;
    }
    if (segments.isEmpty) {
      return null;
    }
    if (segments.first == 't' && segments.length == 2) {
      return _short('https://www.tiktok.com/t/${segments[1]}/');
    }
    // The player inside an embed code: `/embed/v2/<id>`, `/player/v1/<id>`.
    if ((segments.first == 'embed' || segments.first == 'player') &&
        _id.hasMatch(segments.last)) {
      return _video(segments.last, null);
    }
    if (!segments.first.startsWith('@') || segments.first.length < 2) {
      return null;
    }
    final user = segments.first.substring(1);
    if (segments.length >= 3 &&
        (segments[1] == 'video' || segments[1] == 'photo') &&
        _id.hasMatch(segments[2])) {
      return _video(segments[2], user, photo: segments[1] == 'photo');
    }
    return segments.length == 1
        ? webEmbedPage(
            this,
            'Profile',
            'https://www.tiktok.com/@$user',
            id: user,
            title: '@$user',
          )
        : null;
  }

  WebEmbedLink _video(String id, String? user, {bool photo = false}) {
    final embed = 'https://www.tiktok.com/embed/v2/$id';
    return WebEmbedLink(
      provider: this,
      kind: photo ? 'Photo' : 'Video',
      url: user == null
          ? embed
          : 'https://www.tiktok.com/@$user/${photo ? 'photo' : 'video'}/$id',
      id: id,
      embedUrl: embed,
      defaultWidth: 340,
      defaultHeight: 720,
    );
  }

  WebEmbedLink _short(String url) => WebEmbedLink(
        provider: this,
        kind: 'Video',
        url: url,
        defaultWidth: 340,
        defaultHeight: 720,
        needsResolution: true,
      );

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    if (link.showsWholePage) {
      return null;
    }
    final json = await fetchWebEmbedJson(
      Uri.https('www.tiktok.com', '/oembed', {'url': link.url}),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedFirstLine(webEmbedField(json, 'title')),
      author: webEmbedField(json, 'author_name'),
      description: webEmbedField(json, 'title'),
      thumbnailUrl: webEmbedField(json, 'thumbnail_url'),
      width: webEmbedNumber(json, 'thumbnail_width'),
      height: webEmbedNumber(json, 'thumbnail_height'),
    );
  }
}

/// Spotlight snaps, shown in Snapchat's own embed, and profiles, lenses and
/// stories as its phone page.
class SnapchatEmbeds extends FramedWebEmbedProvider {
  const SnapchatEmbeds();

  static final _token = RegExp(r'^[A-Za-z0-9_-]{6,}$');

  @override
  String get id => 'snapchat';

  @override
  String get name => 'Snapchat';

  @override
  List<String> get keywords =>
      const ['snapchat', 'snap', 'spotlight', 'story', 'lens'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Spotlight' => Icons.movie_filter_rounded,
        'Profile' => Icons.person_rounded,
        'Lens' => Icons.auto_awesome_rounded,
        _ => Icons.camera_alt_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFFFFC00);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'snapchat.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!isWebEmbedHost(host, 'snapchat.com')) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (segments.isEmpty) {
      return null;
    }
    final path = segments.join('/');
    if (host == 't.snapchat.com') {
      return segments.length == 1
          ? _short('https://t.snapchat.com/${segments.first}')
          : null;
    }
    if (host == 'story.snapchat.com') {
      return webEmbedPage(this, 'Story', 'https://story.snapchat.com/$path');
    }
    if (host == 'lens.snapchat.com') {
      return webEmbedPage(this, 'Lens', 'https://lens.snapchat.com/$path');
    }
    final first = segments.first;
    if (first.startsWith('@') && first.length > 1) {
      return webEmbedPage(
        this,
        'Profile',
        'https://www.snapchat.com/$first',
        id: first.substring(1),
        title: first,
      );
    }
    if (segments.length < 2) {
      return null;
    }
    switch (first) {
      case 't':
        return _short('https://www.snapchat.com/t/${segments[1]}');
      case 'spotlight':
        if (!_token.hasMatch(segments[1])) {
          return null;
        }
        final url = 'https://www.snapchat.com/spotlight/${segments[1]}';
        return WebEmbedLink(
          provider: this,
          kind: 'Spotlight',
          url: url,
          id: segments[1],
          embedUrl: '$url/embed',
          defaultWidth: 416,
          defaultHeight: 692,
        );
      case 'add':
        return webEmbedPage(
          this,
          'Profile',
          'https://www.snapchat.com/add/${segments[1]}',
          id: segments[1],
          title: '@${segments[1]}',
        );
      case 'lens':
        return webEmbedPage(
          this,
          'Lens',
          'https://www.snapchat.com/lens/${segments[1]}',
          id: segments[1],
        );
      case 'p':
      case 'discover':
        return webEmbedPage(this, 'Story', 'https://www.snapchat.com/$path');
    }
    return null;
  }

  WebEmbedLink _short(String url) => WebEmbedLink(
        provider: this,
        kind: 'Spotlight',
        url: url,
        defaultWidth: 416,
        defaultHeight: 692,
        needsResolution: true,
      );

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(link);
}

/// Posts from public channels, shown as Telegram's own post widget, and the
/// channels themselves as their public preview page.
class TelegramEmbeds extends FramedWebEmbedProvider {
  const TelegramEmbeds();

  static const _hosts = {
    't.me',
    'www.t.me',
    'telegram.me',
    'www.telegram.me',
    'telegram.dog',
  };
  static final _name = RegExp(r'^[A-Za-z][A-Za-z0-9_]{3,31}$');
  static final _post = RegExp(r'^\d{1,10}$');

  /// Telegram's own pages: invites, sticker sets, private chats.
  static const _reserved = {
    'addemoji',
    'addlist',
    'addstickers',
    'addtheme',
    'bg',
    'boost',
    'c',
    'confirmphone',
    'contact',
    'giftcode',
    'invoice',
    'iv',
    'joinchat',
    'login',
    'proxy',
    'setlanguage',
    'share',
    'socks',
  };

  @override
  String get id => 'telegram';

  @override
  String get name => 'Telegram';

  @override
  List<String> get keywords =>
      const ['telegram', 'channel', 'post', 't.me', 'message'];

  @override
  IconData iconFor(String kind) =>
      kind == 'Channel' ? Icons.campaign_rounded : Icons.send_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF229ED9);

  @override
  bool ownsHost(String host) => _hosts.contains(host);

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (!_hosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    var rest = webEmbedSegments(uri);
    if (rest.isNotEmpty && rest.first == 's') {
      rest = rest.sublist(1);
    }
    if (rest.isEmpty) {
      return null;
    }
    final channel = rest.first;
    if (_reserved.contains(channel.toLowerCase()) || !_name.hasMatch(channel)) {
      return null;
    }
    if (rest.length >= 2 && _post.hasMatch(rest[1])) {
      final url = 'https://t.me/$channel/${rest[1]}';
      return WebEmbedLink(
        provider: this,
        kind: 'Post',
        url: url,
        id: rest[1],
        embedUrl: '$url?embed=1&userpic=true',
        defaultWidth: 520,
        parameters: {'author': channel},
      );
    }
    return rest.length == 1
        ? webEmbedPage(
            this,
            'Channel',
            'https://t.me/s/$channel',
            id: channel,
            title: '@$channel',
          )
        : null;
  }

  @override
  String frameUrlFor(WebEmbedLink link, WebEmbedViewOptions options) {
    final embed = link.embedUrl ?? link.url;
    return !link.showsWholePage && options.brightness == Brightness.dark
        ? '$embed&dark=1'
        : embed;
  }

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => link.showsWholePage
      ? super.styleFor(link)
      : const WebEmbedPageStyle(fitsContent: true, css: _transparentPage);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      _postPageDetails(link);
}

/// Posts, companies and topics from Blind, which has no embed, shown as its
/// phone page.
class BlindEmbeds extends FramedWebEmbedProvider {
  const BlindEmbeds();

  /// The id Blind ends a post's address with, like `-xY7a9b2C`: letters and
  /// digits both, so a title's last word is never mistaken for it.
  static final _postId = RegExp(r'^(?=.*\d)(?=.*[A-Za-z])[A-Za-z0-9]{6,12}$');

  @override
  String get id => 'blind';

  @override
  String get name => 'Blind';

  @override
  List<String> get keywords => const [
        'blind',
        'teamblind',
        'anonymous',
        'workplace',
        'salary',
        'layoffs',
        'company reviews',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Company' => Icons.business_rounded,
        'Topic' => Icons.tag_rounded,
        _ => Icons.forum_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFE2273D);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'teamblind.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (!isWebEmbedHost(uri.host.toLowerCase(), 'teamblind.com')) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (segments.length < 2) {
      return null;
    }
    String page(int keep) =>
        Uri.https('www.teamblind.com', segments.take(keep).join('/'))
            .toString();
    switch (segments.first.toLowerCase()) {
      case 'post':
        return webEmbedPage(
          this,
          'Post',
          page(2),
          title: _postTitle(segments[1]),
        );
      case 'company':
        return webEmbedPage(
          this,
          'Company',
          page(segments.length >= 3 ? 3 : 2),
          id: segments[1],
          title: segments[1].replaceAll('-', ' '),
        );
      case 'topics':
      case 'channels':
        return webEmbedPage(
          this,
          'Topic',
          page(2),
          title: segments[1].replaceAll('-', ' '),
        );
    }
    return null;
  }

  static String? _postTitle(String slug) {
    final words = slug.split('-');
    if (words.length > 1 && _postId.hasMatch(words.last)) {
      words.removeLast();
    }
    return webEmbedTitleFromSlug(words.join('-'), question: true);
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title
            .split(' | ')
            .first
            .replaceFirst(RegExp(r'\s+-\s+Blind$'), '')
            .trim(),
      );
}

/// Posts, profiles and feeds from Bluesky, shown as its phone page, which
/// needs no account to read.
class BlueskyEmbeds extends FramedWebEmbedProvider {
  const BlueskyEmbeds();

  @override
  String get id => 'bluesky';

  @override
  String get name => 'Bluesky';

  @override
  List<String> get keywords => const ['bluesky', 'bsky', 'post', 'skeet'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Profile' => Icons.person_rounded,
        'Feed' => Icons.feed_rounded,
        'List' => Icons.list_alt_rounded,
        _ => Icons.forum_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF0085FF);

  @override
  bool ownsHost(String host) => host == 'bsky.app' || host == 'www.bsky.app';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final segments = webEmbedSegments(uri);
    if (!ownsHost(uri.host.toLowerCase()) ||
        segments.length < 2 ||
        segments[0] != 'profile') {
      return null;
    }
    final handle = segments[1];
    final base = 'https://bsky.app/profile/$handle';
    if (segments.length == 2) {
      return webEmbedPage(this, 'Profile', base, id: handle, title: '@$handle');
    }
    if (segments.length < 4) {
      return null;
    }
    final kind = switch (segments[2]) {
      'post' => 'Post',
      'feed' => 'Feed',
      'lists' => 'List',
      _ => null,
    };
    return kind == null
        ? null
        : webEmbedPage(
            this,
            kind,
            '$base/${segments[2]}/${segments[3]}',
            id: segments[3],
            parameters: {'author': handle},
          );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      _postPageDetails(link);
}
