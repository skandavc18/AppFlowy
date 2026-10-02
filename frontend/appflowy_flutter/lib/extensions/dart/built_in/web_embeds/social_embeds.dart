import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_embed_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_video_download.dart';
import 'package:appflowy/shared/markup_parse.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import 'web_embed_fetch.dart';
import 'web_embed_site_base.dart';

/// Videos and Shorts, played by the app's own player rather than YouTube's
/// page, exactly as a pasted YouTube link already plays in a document.
class YoutubeEmbeds extends WebEmbedProvider {
  const YoutubeEmbeds();

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  @override
  List<String> get keywords => const ['youtube', 'video', 'shorts', 'yt'];

  @override
  IconData iconFor(String kind) => Icons.smart_display_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFFFF0033);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final url = uri.toString();
    final id = youtubeVideoId(url);
    if (id == null) {
      return null;
    }
    final short = isYoutubeShortsUrl(url);
    final start = uri.queryParameters['t'] ?? uri.queryParameters['start'];
    final list = uri.queryParameters['list'];
    return WebEmbedLink(
      provider: this,
      kind: short ? 'Short' : 'Video',
      url: short
          ? 'https://www.youtube.com/shorts/$id'
          : Uri.https('www.youtube.com', '/watch', {
              'v': id,
              if (list != null && list.isNotEmpty) 'list': list,
              if (start != null && start.isNotEmpty) 't': start,
            }).toString(),
      id: id,
      thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      defaultWidth: short ? 340 : 640,
      defaultHeight: short ? 604 : 360,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final json = await fetchWebEmbedJson(
      Uri.https('www.youtube.com', '/oembed', {
        'url': 'https://www.youtube.com/watch?v=${link.id}',
        'format': 'json',
      }),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedField(json, 'title'),
      author: webEmbedField(json, 'author_name'),
      thumbnailUrl: webEmbedField(json, 'thumbnail_url') ?? link.thumbnailUrl,
      width: webEmbedNumber(json, 'width'),
      height: webEmbedNumber(json, 'height'),
    );
  }

  @override
  Widget buildView(
    BuildContext context,
    WebEmbedLink link,
    WebEmbedViewOptions options,
  ) =>
      IgnorePointer(
        ignoring: !options.interactive,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            // Not a web view, so a key is safe: it is how a reload restarts
            // the player.
            child: YoutubeEmbedPlayer(
              key: ValueKey('${link.id} ${options.reloadToken}'),
              url: link.url,
            ),
          ),
        ),
      );
}

/// Pins, shown as Pinterest's own pin card, and boards and profiles, which
/// Pinterest has no card for, as its phone page.
class PinterestEmbeds extends FramedWebEmbedProvider {
  const PinterestEmbeds();

  static final _host = RegExp(
    r'^(?:[a-z]{2}\.|www\.)?pinterest\.(?:com|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})$',
  );
  static final _slugId = RegExp(r'--(\d{6,})$');
  static final _numericId = RegExp(r'^\d{6,}$');

  /// Where Pinterest's own embed code frames a pin from.
  static const _assets = 'assets.pinterest.com';

  /// First segments that are Pinterest's own pages rather than someone's
  /// name, so `/ideas/…` is not read as a board called `ideas`.
  static const _reserved = {
    '_',
    'about',
    'business',
    'categories',
    'discover',
    'explore',
    'homefeed',
    'ideas',
    'login',
    'news_hub',
    'oauth',
    'password',
    'pin',
    'resource',
    'search',
    'settings',
    'shopping',
    'signup',
    'today',
    'topics',
    'videos',
  };

  @override
  String get id => 'pinterest';

  @override
  String get name => 'Pinterest';

  @override
  List<String> get keywords =>
      const ['pinterest', 'pin', 'pins', 'moodboard', 'inspiration'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Board' => Icons.dashboard_rounded,
        'Profile' => Icons.person_rounded,
        _ => Icons.push_pin_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFE60023);

  @override
  bool ownsHost(String host) =>
      _host.hasMatch(host) || host == 'pin.it' || host == _assets;

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'pin.it') {
      if (segments.length != 1) {
        return null;
      }
      return WebEmbedLink(
        provider: this,
        kind: 'Pin',
        url: 'https://pin.it/${segments.first}',
        needsResolution: true,
        defaultWidth: 380,
        defaultHeight: 640,
      );
    }
    // The address inside the `<iframe>` of a pin's Embed code.
    if (host == _assets) {
      final id = uri.queryParameters['id'];
      return segments.join('/') == 'ext/embed.html' &&
              id != null &&
              _numericId.hasMatch(id)
          ? _pin(id)
          : null;
    }
    if (!_host.hasMatch(host) || segments.isEmpty) {
      return null;
    }
    if (segments[0] != 'pin') {
      return _boardOrProfile(segments);
    }
    if (segments.length < 2) {
      return null;
    }
    final slug = segments[1];
    final id =
        _numericId.hasMatch(slug) ? slug : _slugId.firstMatch(slug)?.group(1);
    if (id == null) {
      return null;
    }
    return _pin(
      id,
      title: id == slug
          ? null
          : webEmbedTitleFromSlug(slug.substring(0, slug.lastIndexOf('--'))),
    );
  }

  WebEmbedLink _pin(String id, {String? title}) => WebEmbedLink(
        provider: this,
        kind: 'Pin',
        url: 'https://www.pinterest.com/pin/$id/',
        id: id,
        embedUrl: 'https://$_assets/ext/embed.html?id=$id',
        title: title,
        defaultWidth: 380,
        defaultHeight: 640,
      );

  /// `/<user>/` or `/<user>/<board>/`.
  WebEmbedLink? _boardOrProfile(List<String> segments) {
    if (segments.length > 2 || _reserved.contains(segments[0].toLowerCase())) {
      return null;
    }
    final path = segments.map(Uri.encodeComponent).join('/');
    final url = 'https://www.pinterest.com/$path/';
    return WebEmbedLink(
      provider: this,
      kind: segments.length == 1 ? 'Profile' : 'Board',
      url: url,
      embedUrl: url,
      title: segments.length == 1
          ? segments[0]
          : webEmbedTitleFromSlug(segments[1]),
      defaultHeight: 640,
      parameters: const {webEmbedFullPage: 'true'},
    );
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) async {
    final target = await followWebEmbedRedirects(
      Uri.parse(link.url),
      stopAt: (uri) => recognize(uri)?.needsResolution == false,
    );
    final found = target == null ? null : recognize(target);
    if (found != null && !found.needsResolution) {
      return found;
    }
    // An idea page, a search, or Pinterest would not say: its own phone page
    // still follows the short link.
    return webEmbedAsFullPage(
      link,
      url: target != null && ownsHost(target.host.toLowerCase())
          ? target.toString()
          : null,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    if (isWebEmbedFullPage(link)) {
      return null;
    }
    final json = await fetchWebEmbedJson(
      Uri.https('www.pinterest.com', '/oembed.json', {'url': link.url}),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedField(json, 'title') ?? link.title,
      author: webEmbedField(json, 'author_name'),
      description: webEmbedField(json, 'description'),
      thumbnailUrl: webEmbedField(json, 'thumbnail_url'),
      width: webEmbedNumber(json, 'thumbnail_width'),
      height: webEmbedNumber(json, 'thumbnail_height'),
    );
  }

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => isWebEmbedFullPage(link)
      ? super.styleFor(link)
      : const WebEmbedPageStyle(
          fitsContent: true,
          css: 'html, body { background: transparent !important; }',
        );
}

/// Posts, comments and communities. Posts and comments use Reddit's own embed
/// card; a community has none, so it shows Reddit's phone page.
class RedditEmbeds extends FramedWebEmbedProvider {
  const RedditEmbeds();

  static const _hosts = {
    'reddit.com',
    'www.reddit.com',
    'old.reddit.com',
    'new.reddit.com',
    'np.reddit.com',
    'm.reddit.com',
    'i.reddit.com',
    'amp.reddit.com',
    'sh.reddit.com',
    'embed.reddit.com',
  };

  /// Reddit's ids are short base-36 numbers.
  static final _idPattern = RegExp(r'^[a-z0-9]{2,12}$');
  static const _listings = {'hot', 'new', 'top', 'rising', 'controversial'};

  @override
  String get id => 'reddit';

  @override
  String get name => 'Reddit';

  @override
  List<String> get keywords => const [
        'reddit',
        'subreddit',
        'thread',
        'post',
        'comment',
        'answer',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Comment' => Icons.mode_comment_rounded,
        'Community' => Icons.groups_rounded,
        _ => Icons.forum_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFFF4500);

  @override
  bool ownsHost(String host) =>
      _hosts.contains(host) ||
      host == 'redd.it' ||
      host == 'www.redditstatic.com';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'redd.it') {
      return segments.length == 1 && _idPattern.hasMatch(segments.first)
          ? _thread(const [], segments.first)
          : null;
    }
    if (!_hosts.contains(host)) {
      return null;
    }

    var rest = segments;
    var owner = const <String>[];
    if (rest.length >= 2 &&
        (rest[0] == 'r' || rest[0] == 'user' || rest[0] == 'u')) {
      owner = [if (rest[0] == 'r') 'r' else 'user', rest[1]];
      rest = rest.sublist(2);
    }
    final community = owner.isNotEmpty && owner[0] == 'r';

    if (community && rest.length == 2 && rest[0] == 's') {
      // A share link; only following it says which post it is.
      return WebEmbedLink(
        provider: this,
        kind: 'Post',
        url: 'https://www.reddit.com/r/${owner[1]}/s/${rest[1]}',
        needsResolution: true,
        defaultHeight: 520,
      );
    }
    if (rest.isEmpty || (rest.length == 1 && _listings.contains(rest[0]))) {
      if (!community) {
        return null;
      }
      final url = 'https://www.reddit.com/r/${owner[1]}/';
      return WebEmbedLink(
        provider: this,
        kind: 'Community',
        url: url,
        id: owner[1],
        embedUrl: url,
        title: 'r/${owner[1]}',
        defaultHeight: 640,
        parameters: const {webEmbedFullPage: 'true'},
      );
    }
    if (rest.length >= 2 &&
        (rest[0] == 'comments' || rest[0] == 'gallery') &&
        _idPattern.hasMatch(rest[1])) {
      String? slug;
      String? comment;
      if (rest.length >= 4 && rest[2] == 'comment') {
        comment = rest[3];
      } else {
        slug = rest.length >= 3 ? rest[2] : null;
        comment = rest.length >= 4 ? rest[3] : null;
      }
      if (comment != null && !_idPattern.hasMatch(comment)) {
        comment = null;
      }
      return _thread(owner, rest[1], slug: slug, comment: comment);
    }
    return null;
  }

  WebEmbedLink _thread(
    List<String> owner,
    String post, {
    String? slug,
    String? comment,
  }) {
    final path = [
      ...owner,
      'comments',
      post,
      if (comment != null) ...[
        if (slug == null || slug.isEmpty) '_' else slug,
        comment,
      ] else if (slug != null && slug.isNotEmpty)
        slug,
    ].join('/');
    return WebEmbedLink(
      provider: this,
      kind: comment == null ? 'Post' : 'Comment',
      url: 'https://www.reddit.com/$path/',
      id: comment ?? post,
      embedUrl: 'https://embed.reddit.com/$path/',
      title: slug == null || slug == '_'
          ? null
          : webEmbedTitleFromSlug(slug, separator: '_'),
      defaultHeight: comment == null ? 520 : 320,
      parameters: {
        'post': post,
        if (comment != null) 'comment': comment,
        if (owner.isNotEmpty) 'owner': owner.join('/'),
      },
    );
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) async {
    final target = await followWebEmbedRedirects(
      Uri.parse(link.url),
      stopAt: (uri) => recognize(uri)?.needsResolution == false,
    );
    final found = target == null ? null : recognize(target);
    if (found != null && !found.needsResolution) {
      return found;
    }
    // Reddit turns some clients away before saying where a share link goes;
    // its phone page still follows the link and shows the post.
    return webEmbedAsFullPage(link);
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    if (link.kind == 'Community' || isWebEmbedFullPage(link)) {
      return null;
    }
    final json = await fetchWebEmbedJson(
      Uri.https('www.reddit.com', '/oembed', {'url': link.url}),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedField(json, 'title') ?? link.title,
      author: webEmbedField(json, 'author_name'),
    );
  }

  @override
  String frameUrlFor(WebEmbedLink link, WebEmbedViewOptions options) {
    final embed = link.embedUrl ?? link.url;
    if (isWebEmbedFullPage(link)) {
      return embed;
    }
    final theme = options.brightness == Brightness.dark ? 'dark' : 'light';
    return Uri.parse(embed).replace(
      queryParameters: {
        'embed': 'true',
        'theme': theme,
        if (link.kind == 'Comment') ...{
          'showmedia': 'false',
          'showmore': 'false',
          'depth': '1',
          'context': '1',
        },
      },
    ).toString();
  }

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => isWebEmbedFullPage(link)
      ? super.styleFor(link)
      : const WebEmbedPageStyle(fitsContent: true);
}

/// Questions, answers, posts, profiles and Spaces. Quora has no embed and
/// refuses plain requests, so its phone page is shown whole.
class QuoraEmbeds extends FramedWebEmbedProvider {
  const QuoraEmbeds();

  /// First path segments that are Quora's own pages, not questions.
  static const _reserved = {
    'about',
    'ads',
    'answer',
    'api',
    'bookmarks',
    'business',
    'careers',
    'contact',
    'content',
    'following',
    'index',
    'login',
    'main',
    'messages',
    'notifications',
    'partners',
    'poll',
    'press',
    'qemail',
    'search',
    'settings',
    'share',
    'signup',
    'sitemap',
    'spaces',
    'stats',
    'unanswered',
  };

  /// Tabs of a profile page, which are still the profile.
  static const _profileTabs = {
    'answers',
    'questions',
    'posts',
    'followers',
    'following',
    'log',
    'spaces',
    'shares',
  };

  @override
  String get id => 'quora';

  @override
  String get name => 'Quora';

  @override
  List<String> get keywords =>
      const ['quora', 'question', 'answer', 'post', 'space', 'q&a'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Answer' => Icons.question_answer_rounded,
        'Post' => Icons.article_rounded,
        'Profile' => Icons.person_rounded,
        'Space' => Icons.groups_rounded,
        'Topic' => Icons.tag_rounded,
        _ => Icons.help_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFB92B27);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'quora.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    var host = uri.host.toLowerCase();
    if (!isWebEmbedHost(host, 'quora.com')) {
      return null;
    }
    if (host == 'quora.com' || host == 'm.quora.com') {
      host = 'www.quora.com';
    }
    final sub = host == 'www.quora.com'
        ? null
        : host.substring(0, host.length - '.quora.com'.length);
    // Two letters is a language edition; anything else is a Space.
    final space = sub != null && sub.length != 2 ? sub : null;
    final segments = webEmbedSegments(uri);

    WebEmbedLink link(
      String kind, {
      String? title,
      String? author,
      int keep = 99,
    }) {
      final path = segments.take(keep).join('/');
      final url = 'https://$host/$path';
      return WebEmbedLink(
        provider: this,
        kind: kind,
        url: url,
        embedUrl: url,
        title: title,
        defaultHeight: 640,
        parameters: {
          webEmbedFullPage: 'true',
          if (author != null) 'author': author,
        },
      );
    }

    if (space != null) {
      if (segments.isEmpty) {
        return link('Space', title: webEmbedTitleFromSlug(space));
      }
      if (_reserved.contains(segments.first.toLowerCase())) {
        return null;
      }
      if (segments.length >= 3 && segments[1] == 'answer') {
        return link(
          'Answer',
          title: webEmbedTitleFromSlug(segments.first, question: true),
          author: webEmbedNameFromSlug(segments[2]),
          keep: 3,
        );
      }
      return segments.length == 1
          ? link('Post', title: webEmbedTitleFromSlug(segments.first))
          : null;
    }

    if (segments.isEmpty) {
      return null;
    }
    final first = segments.first;
    switch (first) {
      case 'profile':
        if (segments.length < 2) {
          return null;
        }
        final person = webEmbedNameFromSlug(segments[1]);
        if (segments.length == 2 || _profileTabs.contains(segments[2])) {
          return link('Profile', title: person, keep: 2);
        }
        return link(
          'Post',
          title: webEmbedTitleFromSlug(segments[2]),
          author: person,
          keep: 3,
        );
      case 'q':
        if (segments.length < 2) {
          return null;
        }
        final tab = segments.length > 2 ? segments[2].toLowerCase() : null;
        // A post from before Spaces had addresses of their own, which Quora
        // still sends on to where the post lives now.
        if (tab != null &&
            !_reserved.contains(tab) &&
            !_profileTabs.contains(tab)) {
          return link(
            'Post',
            title: webEmbedTitleFromSlug(segments[2]),
            keep: 3,
          );
        }
        return link(
          'Space',
          title: webEmbedTitleFromSlug(segments[1]),
          keep: 2,
        );
      case 'topic':
        return segments.length >= 2
            ? link('Topic', title: webEmbedTitleFromSlug(segments[1]), keep: 2)
            : null;
    }
    if (_reserved.contains(first.toLowerCase())) {
      return null;
    }
    final question = webEmbedTitleFromSlug(first, question: true);
    if (segments.length == 1) {
      return link('Question', title: question);
    }
    if (segments.length >= 3 &&
        (segments[1] == 'answer' || segments[1] == 'answers')) {
      return link(
        'Answer',
        title: question,
        author:
            segments[1] == 'answer' ? webEmbedNameFromSlug(segments[2]) : null,
        keep: 3,
      );
    }
    return null;
  }
}

/// Posts, reels and videos, shown as Instagram's own captioned embed card.
class InstagramEmbeds extends FramedWebEmbedProvider {
  const InstagramEmbeds();

  static const _hosts = {
    'instagram.com',
    'www.instagram.com',
    'm.instagram.com',
    'instagr.am',
    'www.instagr.am',
  };
  static const _kinds = {
    'p': 'Post',
    'reel': 'Reel',
    'reels': 'Reel',
    'tv': 'Video',
  };
  static final _code = RegExp(r'^[A-Za-z0-9_-]{5,}$');

  @override
  String get id => 'instagram';

  @override
  String get name => 'Instagram';

  @override
  List<String> get keywords =>
      const ['instagram', 'insta', 'ig', 'reel', 'photo', 'post'];

  @override
  IconData iconFor(String kind) =>
      kind == 'Post' ? Icons.photo_camera_rounded : Icons.movie_filter_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFFE1306C);

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (!_hosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    var segments = webEmbedSegments(uri);
    // `instagram.com/<user>/p/<code>/` names the account first.
    if (segments.length >= 3 && _kinds.containsKey(segments[1])) {
      segments = segments.sublist(1);
    }
    if (segments.length < 2 || !_kinds.containsKey(segments[0])) {
      return null;
    }
    final code = segments[1];
    if (!_code.hasMatch(code)) {
      return null;
    }
    final kind = _kinds[segments[0]]!;
    final path = kind == 'Reel' ? 'reel' : segments[0];
    return WebEmbedLink(
      provider: this,
      kind: kind,
      url: 'https://www.instagram.com/$path/$code/',
      id: code,
      embedUrl: 'https://www.instagram.com/p/$code/embed/captioned/',
      defaultWidth: 400,
      defaultHeight: kind == 'Post' ? 700 : 860,
    );
  }

  /// Instagram's oEmbed wants an app token, but its embed page names the
  /// account and carries the picture.
  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final embed = link.embedUrl;
    if (embed == null) {
      return null;
    }
    final html = await fetchWebEmbedText(Uri.parse(embed));
    if (html == null) {
      return null;
    }
    final details = await parseMarkup(html, _detailsOf);
    return details.isEmpty ? null : details;
  }

  /// What the embed page [html] says about its post.
  static WebEmbedDetails _detailsOf(String html) {
    final document = html_parser.parse(html);
    final image = document
        .querySelector('img.EmbeddedMediaImage')
        ?.attributes['src']
        ?.trim();
    final author = document.querySelector('.UsernameText')?.text.trim();
    var caption = document.querySelector('.Caption')?.text.trim();
    if (caption != null && author != null && caption.startsWith(author)) {
      caption = caption.substring(author.length).trim();
    }
    return WebEmbedDetails(
      title: _firstLine(caption),
      author: author == null || author.isEmpty ? null : author,
      description: caption == null || caption.isEmpty ? null : caption,
      thumbnailUrl: image == null || image.isEmpty ? null : image,
    );
  }

  static String? _firstLine(String? text) {
    final line = text?.split('\n').first.trim();
    if (line == null || line.isEmpty) {
      return null;
    }
    return line.length <= 90 ? line : '${line.substring(0, 89).trim()}…';
  }

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) =>
      const WebEmbedPageStyle(fitsContent: true);
}
