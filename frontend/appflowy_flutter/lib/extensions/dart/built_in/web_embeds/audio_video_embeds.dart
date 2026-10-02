import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:flutter/material.dart';

import 'web_embed_fetch.dart';
import 'web_embed_site_base.dart';

/// Tracks, albums, playlists, artists, podcasts and audiobooks, played in
/// Spotify's own embedded player.
class SpotifyEmbeds extends FramedWebEmbedProvider {
  const SpotifyEmbeds();

  static const _kinds = {
    'track': 'Track',
    'album': 'Album',
    'playlist': 'Playlist',
    'artist': 'Artist',
    'episode': 'Episode',
    'show': 'Podcast',
    'audiobook': 'Audiobook',
  };
  static final _id = RegExp(r'^[A-Za-z0-9]{22}$');

  /// `/intl-de/track/…` names the reader's language, not the music.
  static final _locale = RegExp(r'^intl-[a-z]{2}(?:-[a-z]{2})?$');

  @override
  String get id => 'spotify';

  @override
  String get name => 'Spotify';

  @override
  List<String> get keywords => const [
        'spotify',
        'music',
        'song',
        'track',
        'album',
        'playlist',
        'podcast',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Album' => Icons.album_rounded,
        'Playlist' => Icons.queue_music_rounded,
        'Artist' => Icons.person_rounded,
        'Episode' || 'Podcast' => Icons.podcasts_rounded,
        'Audiobook' => Icons.menu_book_rounded,
        _ => Icons.music_note_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF1DB954);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    var segments = webEmbedSegments(uri);
    if (host == 'spotify.link' || host == 'spoti.fi') {
      return segments.length == 1
          ? WebEmbedLink(
              provider: this,
              kind: 'Music',
              url: 'https://$host/${segments.first}',
              defaultHeight: 352,
              needsResolution: true,
            )
          : null;
    }
    if (host != 'open.spotify.com' && host != 'play.spotify.com') {
      return null;
    }
    segments = [
      for (final segment in segments)
        if (segment != 'embed' && !_locale.hasMatch(segment)) segment,
    ];
    if (segments.length < 2) {
      return null;
    }
    final kind = _kinds[segments[0]];
    final id = segments[1];
    if (kind == null || !_id.hasMatch(id)) {
      return null;
    }
    return WebEmbedLink(
      provider: this,
      kind: kind,
      url: 'https://open.spotify.com/${segments[0]}/$id',
      id: id,
      embedUrl: 'https://open.spotify.com/embed/${segments[0]}/$id',
      defaultHeight: switch (kind) {
        'Track' => 152,
        'Episode' => 232,
        _ => 352,
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
    return found == null || found.needsResolution ? null : found;
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final json = await fetchWebEmbedJson(
      Uri.https('open.spotify.com', '/oembed', {'url': link.url}),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedField(json, 'title'),
      thumbnailUrl: webEmbedField(json, 'thumbnail_url'),
      width: webEmbedNumber(json, 'thumbnail_width'),
      height: webEmbedNumber(json, 'thumbnail_height'),
    );
  }
}

/// Songs, albums, playlists and artists from Apple Music, and shows and
/// episodes from Apple Podcasts, played in Apple's own embedded players.
class AppleMediaEmbeds extends FramedWebEmbedProvider {
  const AppleMediaEmbeds();

  static const _music = {
    'album': 'Album',
    'playlist': 'Playlist',
    'artist': 'Artist',
    'song': 'Song',
    'music-video': 'Music video',
    'station': 'Station',
  };
  static final _country = RegExp(r'^[a-z]{2}$');

  @override
  String get id => 'apple_media';

  @override
  String get name => 'Apple Music';

  @override
  List<String> get keywords => const [
        'apple music',
        'apple podcasts',
        'itunes',
        'music',
        'song',
        'album',
        'playlist',
        'podcast',
      ];

  static bool isPodcast(String kind) => kind == 'Podcast' || kind == 'Episode';

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Album' => Icons.album_rounded,
        'Playlist' => Icons.queue_music_rounded,
        'Artist' => Icons.person_rounded,
        'Music video' => Icons.movie_rounded,
        'Station' => Icons.graphic_eq_rounded,
        'Podcast' || 'Episode' => Icons.podcasts_rounded,
        _ => Icons.music_note_rounded,
      };

  @override
  Color colorFor(String kind) =>
      isPodcast(kind) ? const Color(0xFF9933CC) : const Color(0xFFFA2D48);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    final song = uri.queryParameters['i'];
    if (host == 'music.apple.com' || host == 'embed.music.apple.com') {
      // The storefront's country leads every address but a rare few.
      final rest = segments.isNotEmpty && _country.hasMatch(segments.first)
          ? segments.sublist(1)
          : segments;
      final kind = rest.length >= 2 ? _music[rest.first] : null;
      if (kind == null) {
        return null;
      }
      final single = kind == 'Song' || (kind == 'Album' && song != null);
      final path = segments.join('/');
      final query = song == null ? '' : '?i=$song';
      return WebEmbedLink(
        provider: this,
        kind: single ? 'Song' : kind,
        siteName: 'Apple Music',
        url: 'https://music.apple.com/$path$query',
        id: song ?? rest.last,
        embedUrl: 'https://embed.music.apple.com/$path$query',
        title: rest.length >= 3 ? webEmbedTitleFromSlug(rest[1]) : null,
        defaultWidth: 660,
        defaultHeight: single
            ? 175
            : kind == 'Music video'
                ? 372
                : 450,
      );
    }
    if (host == 'podcasts.apple.com' ||
        host == 'embed.podcasts.apple.com' ||
        host == 'itunes.apple.com') {
      final at = segments.indexOf('podcast');
      if (at < 0 ||
          at + 1 >= segments.length ||
          !segments.last.startsWith('id')) {
        return null;
      }
      final path = segments.join('/');
      final query = song == null ? '' : '?i=$song';
      return WebEmbedLink(
        provider: this,
        kind: song == null ? 'Podcast' : 'Episode',
        siteName: 'Apple Podcasts',
        url: 'https://podcasts.apple.com/$path$query',
        id: song ?? segments.last.substring(2),
        embedUrl: 'https://embed.podcasts.apple.com/$path$query',
        title: segments.length > at + 2
            ? webEmbedTitleFromSlug(segments[at + 1])
            : null,
        defaultWidth: 660,
        defaultHeight: song == null ? 450 : 175,
      );
    }
    return null;
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title
            .replaceFirst(
              RegExp(r'\s+(?:on|[-\u2013\u2014])\s+Apple (?:Music|Podcasts)$'),
              '',
            )
            .trim(),
      );
}

/// Tracks, playlists and artists, played in SoundCloud's own visual player.
class SoundCloudEmbeds extends FramedWebEmbedProvider {
  const SoundCloudEmbeds();

  static const _hosts = {
    'soundcloud.com',
    'www.soundcloud.com',
    'm.soundcloud.com',
  };

  /// First segments that are SoundCloud's own pages rather than an artist.
  static const _reserved = {
    'charts',
    'connect',
    'discover',
    'feed',
    'jobs',
    'messages',
    'mobile',
    'notifications',
    'pages',
    'people',
    'pro',
    'search',
    'settings',
    'signin',
    'stations',
    'stream',
    'tags',
    'terms-of-use',
    'upload',
    'you',
  };

  /// Tabs of an artist's page, which are still the artist.
  static const _artistTabs = {
    'albums',
    'comments',
    'followers',
    'following',
    'likes',
    'popular-tracks',
    'reposts',
    'tracks',
  };

  @override
  String get id => 'soundcloud';

  @override
  String get name => 'SoundCloud';

  @override
  List<String> get keywords =>
      const ['soundcloud', 'music', 'track', 'audio', 'mix', 'playlist'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Playlist' => Icons.queue_music_rounded,
        'Artist' => Icons.person_rounded,
        _ => Icons.graphic_eq_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFFF5500);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'on.soundcloud.com') {
      return segments.length == 1
          ? WebEmbedLink(
              provider: this,
              kind: 'Track',
              url: 'https://on.soundcloud.com/${segments.first}',
              defaultHeight: 300,
              needsResolution: true,
            )
          : null;
    }
    // The player inside an embed code names what it plays in `url`.
    if (host == 'w.soundcloud.com') {
      final inner = Uri.tryParse(uri.queryParameters['url'] ?? '');
      if (inner == null) {
        return null;
      }
      final permalink =
          _hosts.contains(inner.host.toLowerCase()) ? recognize(inner) : null;
      if (permalink != null) {
        return permalink;
      }
      final playlist = inner.path.contains('/playlists/');
      return _link(
        playlist ? 'Playlist' : 'Track',
        uri.toString(),
        embed: uri.toString(),
      );
    }
    if (!_hosts.contains(host) || segments.isEmpty) {
      return null;
    }
    final artist = segments.first;
    if (_reserved.contains(artist.toLowerCase())) {
      return null;
    }
    final base = 'https://soundcloud.com/$artist';
    if (segments.length == 1 ||
        (segments.length == 2 && _artistTabs.contains(segments[1]))) {
      return _link('Artist', base, title: artist);
    }
    if (segments[1] == 'sets') {
      return segments.length >= 3
          ? _link(
              'Playlist',
              '$base/sets/${segments[2]}',
              title: webEmbedTitleFromSlug(segments[2]),
            )
          : null;
    }
    // A private track keeps its secret token as a third segment.
    final track = segments.take(segments.length >= 3 ? 3 : 2).join('/');
    return _link(
      'Track',
      'https://soundcloud.com/$track',
      title: webEmbedTitleFromSlug(segments[1]),
    );
  }

  WebEmbedLink _link(
    String kind,
    String url, {
    String? embed,
    String? title,
  }) =>
      WebEmbedLink(
        provider: this,
        kind: kind,
        url: url,
        embedUrl: embed ??
            Uri.https('w.soundcloud.com', '/player/', {
              'url': url,
              'visual': 'true',
              'show_comments': 'false',
            }).toString(),
        title: title,
        defaultHeight: kind == 'Track' ? 300 : 450,
      );

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final json = await fetchWebEmbedJson(
      Uri.https('soundcloud.com', '/oembed', {
        'format': 'json',
        'url': link.url,
      }),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedField(json, 'title'),
      author: webEmbedField(json, 'author_name'),
      description: webEmbedField(json, 'description'),
      thumbnailUrl: webEmbedField(json, 'thumbnail_url'),
    );
  }
}

/// Videos, played in Vimeo's own player.
class VimeoEmbeds extends FramedWebEmbedProvider {
  const VimeoEmbeds();

  static final _id = RegExp(r'^\d{5,12}$');
  static final _hash = RegExp(r'^[0-9a-f]{6,20}$');

  /// Collections whose own number follows them: `/showcase/<id>` is a
  /// showcase, not a video.
  static const _collections = {
    'album',
    'categories',
    'channels',
    'groups',
    'ondemand',
    'showcase',
    'user',
  };

  @override
  String get id => 'vimeo';

  @override
  String get name => 'Vimeo';

  @override
  List<String> get keywords => const ['vimeo', 'video', 'film'];

  @override
  IconData iconFor(String kind) => Icons.movie_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF1AB7EA);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    String? id;
    String? hash = uri.queryParameters['h'];
    if (host == 'player.vimeo.com') {
      if (segments.length >= 2 && segments[0] == 'video') {
        id = segments[1];
      }
    } else if (host == 'vimeo.com' || host == 'www.vimeo.com') {
      // `/<id>`, `/<id>/<hash>`, `/channels/<name>/<id>`,
      // `/showcase/<id>/video/<id>` and the like end with the video.
      for (var i = segments.length - 1; i >= 0; i--) {
        if (_id.hasMatch(segments[i])) {
          if (i == 1 && _collections.contains(segments[0])) {
            break;
          }
          id = segments[i];
          if (i + 1 < segments.length && _hash.hasMatch(segments[i + 1])) {
            hash ??= segments[i + 1];
          }
          break;
        }
      }
    }
    if (id == null || !_id.hasMatch(id)) {
      return null;
    }
    return WebEmbedLink(
      provider: this,
      kind: 'Video',
      url: hash == null
          ? 'https://vimeo.com/$id'
          : 'https://vimeo.com/$id/$hash',
      id: id,
      embedUrl: Uri.https('player.vimeo.com', '/video/$id', {
        if (hash != null) 'h': hash,
        'dnt': '1',
      }).toString(),
      defaultWidth: 640,
      defaultHeight: 360,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final json = await fetchWebEmbedJson(
      Uri.https('vimeo.com', '/api/oembed.json', {'url': link.url}),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedField(json, 'title'),
      author: webEmbedField(json, 'author_name'),
      description: webEmbedField(json, 'description'),
      thumbnailUrl: webEmbedField(json, 'thumbnail_url'),
      width: webEmbedNumber(json, 'width'),
      height: webEmbedNumber(json, 'height'),
    );
  }
}

/// Videos, played in Dailymotion's own player.
class DailymotionEmbeds extends FramedWebEmbedProvider {
  const DailymotionEmbeds();

  static final _id = RegExp(r'^x[a-z0-9]{4,12}$', caseSensitive: false);

  @override
  String get id => 'dailymotion';

  @override
  String get name => 'Dailymotion';

  @override
  List<String> get keywords => const ['dailymotion', 'video'];

  @override
  IconData iconFor(String kind) => Icons.movie_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF0066DC);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    String? id;
    if (host == 'dai.ly' && segments.length == 1) {
      id = segments.first;
    } else if (host == 'dailymotion.com' || host == 'www.dailymotion.com') {
      final at = segments.indexOf('video');
      if (at >= 0 && at + 1 < segments.length) {
        // Old addresses add the title: `x8abc12_my-video`.
        id = segments[at + 1].split('_').first;
      }
    }
    if (id == null || !_id.hasMatch(id)) {
      return null;
    }
    return WebEmbedLink(
      provider: this,
      kind: 'Video',
      url: 'https://www.dailymotion.com/video/$id',
      id: id,
      embedUrl: 'https://www.dailymotion.com/embed/video/$id',
      thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/$id',
      defaultWidth: 640,
      defaultHeight: 360,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final json = await fetchWebEmbedJson(
      Uri.https('www.dailymotion.com', '/services/oembed', {
        'url': link.url,
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
    );
  }
}

/// Screen recordings, played in Loom's own player.
class LoomEmbeds extends FramedWebEmbedProvider {
  const LoomEmbeds();

  static final _id = RegExp(r'^[0-9a-f]{32}$');

  @override
  String get id => 'loom';

  @override
  String get name => 'Loom';

  @override
  List<String> get keywords =>
      const ['loom', 'screen recording', 'video', 'walkthrough'];

  @override
  IconData iconFor(String kind) => Icons.videocam_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF625DF5);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if ((host != 'loom.com' && host != 'www.loom.com') ||
        segments.length < 2 ||
        (segments[0] != 'share' && segments[0] != 'embed')) {
      return null;
    }
    // A shared recording's address can carry its title before the id.
    final id = segments[1].split('-').last;
    if (!_id.hasMatch(id)) {
      return null;
    }
    return WebEmbedLink(
      provider: this,
      kind: 'Video',
      url: 'https://www.loom.com/share/$id',
      id: id,
      embedUrl: 'https://www.loom.com/embed/$id',
      defaultWidth: 640,
      defaultHeight: 400,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final json = await fetchWebEmbedJson(
      Uri.https('www.loom.com', '/v1/oembed', {'url': link.url}),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedField(json, 'title'),
      thumbnailUrl: webEmbedField(json, 'thumbnail_url'),
    );
  }
}

/// Songs, albums, playlists, artists and podcasts from JioSaavn, which has no
/// embed, shown as its phone page, which plays them.
class JioSaavnEmbeds extends FramedWebEmbedProvider {
  const JioSaavnEmbeds();

  static const _kinds = {
    'song': 'Song',
    'album': 'Album',
    'featured': 'Playlist',
    's': 'Playlist',
    'artist': 'Artist',
    'shows': 'Podcast',
  };

  @override
  String get id => 'jiosaavn';

  @override
  String get name => 'JioSaavn';

  @override
  List<String> get keywords =>
      const ['jiosaavn', 'saavn', 'music', 'song', 'bollywood', 'playlist'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Album' => Icons.album_rounded,
        'Playlist' => Icons.queue_music_rounded,
        'Artist' => Icons.person_rounded,
        'Podcast' => Icons.podcasts_rounded,
        _ => Icons.music_note_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF2BC5B4);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'jiosaavn.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final segments = webEmbedSegments(uri);
    if (!isWebEmbedHost(uri.host.toLowerCase(), 'jiosaavn.com') ||
        segments.length < 2) {
      return null;
    }
    final kind = _kinds[segments.first];
    if (kind == null) {
      return null;
    }
    return webEmbedPage(
      this,
      kind,
      Uri.https('www.jiosaavn.com', segments.join('/')).toString(),
      title: webEmbedTitleFromSlug(segments[1]),
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title
            .replaceFirst(RegExp(r'\s+[-|]\s+JioSaavn.*$'), '')
            .replaceFirst(RegExp(r'^Listen to\s+'), '')
            .trim(),
      );
}

/// TED talks, played in TED's own player.
class TedEmbeds extends FramedWebEmbedProvider {
  const TedEmbeds();

  static final _slug = RegExp(r'^[A-Za-z0-9_-]{3,}$');

  @override
  String get id => 'ted';

  @override
  String get name => 'TED';

  @override
  List<String> get keywords =>
      const ['ted', 'ted talk', 'talk', 'lecture', 'ideas'];

  @override
  IconData iconFor(String kind) => Icons.campaign_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFFE62B1E);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if ((host != 'ted.com' &&
            host != 'www.ted.com' &&
            host != 'embed.ted.com') ||
        segments.length < 2 ||
        segments.first != 'talks' ||
        !_slug.hasMatch(segments[1])) {
      return null;
    }
    final talk = segments[1];
    return WebEmbedLink(
      provider: this,
      kind: 'Talk',
      url: 'https://www.ted.com/talks/$talk',
      id: talk,
      embedUrl: 'https://embed.ted.com/talks/$talk',
      title: webEmbedTitleFromSlug(talk, separator: '_'),
      defaultWidth: 640,
      defaultHeight: 360,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final json = await fetchWebEmbedJson(
      Uri.https('www.ted.com', '/services/v1/oembed.json', {'url': link.url}),
    );
    if (json == null) {
      return null;
    }
    return WebEmbedDetails(
      title: webEmbedField(json, 'title'),
      author: webEmbedField(json, 'author_name'),
      description: webEmbedField(json, 'description'),
      thumbnailUrl: webEmbedField(json, 'thumbnail_url'),
    );
  }
}

/// Channels, past broadcasts and clips from Twitch, shown as its phone
/// page, which plays them: Twitch's own player only plays inside a page on
/// a site it was told about.
class TwitchEmbeds extends FramedWebEmbedProvider {
  const TwitchEmbeds();

  static const _hosts = {
    'twitch.tv',
    'www.twitch.tv',
    'm.twitch.tv',
    'clips.twitch.tv',
  };
  static final _channel = RegExp(r'^[A-Za-z0-9_]{3,25}$');

  /// Twitch's own pages rather than a channel.
  static const _reserved = {
    'directory',
    'downloads',
    'drops',
    'friends',
    'inventory',
    'jobs',
    'messages',
    'p',
    'prime',
    'search',
    'settings',
    'store',
    'subscriptions',
    'turbo',
    'videos',
    'wallet',
  };

  @override
  String get id => 'twitch';

  @override
  String get name => 'Twitch';

  @override
  List<String> get keywords =>
      const ['twitch', 'stream', 'live', 'gaming', 'clip', 'broadcast'];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Clip' => Icons.movie_filter_rounded,
        'Video' => Icons.movie_rounded,
        _ => Icons.videocam_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF9146FF);

  @override
  bool ownsHost(String host) => _hosts.contains(host);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!_hosts.contains(host)) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (segments.isEmpty) {
      return null;
    }
    if (host == 'clips.twitch.tv') {
      return webEmbedPage(
        this,
        'Clip',
        'https://clips.twitch.tv/${segments.first}',
        id: segments.first,
        height: 520,
      );
    }
    if (segments.first == 'videos') {
      return segments.length >= 2
          ? webEmbedPage(
              this,
              'Video',
              'https://www.twitch.tv/videos/${segments[1]}',
              id: segments[1],
              height: 520,
            )
          : null;
    }
    final channel = segments.first;
    if (_reserved.contains(channel.toLowerCase()) ||
        !_channel.hasMatch(channel)) {
      return null;
    }
    if (segments.length >= 3 && segments[1] == 'clip') {
      return webEmbedPage(
        this,
        'Clip',
        'https://www.twitch.tv/$channel/clip/${segments[2]}',
        id: segments[2],
        height: 520,
      );
    }
    return segments.length == 1
        ? webEmbedPage(
            this,
            'Channel',
            'https://www.twitch.tv/$channel',
            id: channel,
            title: channel,
            height: 520,
          )
        : null;
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => title.replaceFirst(RegExp(r'\s+-\s+Twitch$'), ''),
      );
}
