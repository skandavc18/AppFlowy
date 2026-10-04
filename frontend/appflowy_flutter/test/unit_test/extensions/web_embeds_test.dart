import 'dart:convert';

import 'package:appflowy/extensions/dart/built_in/web_embeds/document_embeds.dart';
import 'package:appflowy/extensions/dart/built_in/web_embeds/reading_embeds.dart';
import 'package:appflowy/extensions/dart/built_in/web_embeds/web_embed_sites.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _extension = 'test.web_embeds';

const _fileId = '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms';
const _video = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
const _pin = 'https://www.pinterest.com/pin/123456789012345678/';
const _sheet = 'https://docs.google.com/spreadsheets/d/$_fileId/edit#gid=0';
const _document = 'https://docs.google.com/document/d/$_fileId/edit';
const _wordCode =
    'https://onedrive.live.com/embed?resid=ABC123%21456&authkey=!AbC&em=2';

const _instagramCode =
    '<blockquote class="instagram-media" data-instgrm-permalink="https://www.instagram.com/p/C1a2B3c4D5e/?utm_source=ig_embed&amp;utm_campaign=loading" data-instgrm-version="14"></blockquote>'
    '<script async src="//www.instagram.com/embed.js"></script>';
const _redditCode =
    '<blockquote class="reddit-embed-bq" style="height:500px" data-embed-height="740">'
    '<a href="https://www.reddit.com/r/FlutterDev/comments/1abcde/some_post_title/">Some post title</a><br> by'
    '<a href="https://www.reddit.com/user/someone/">u/someone</a> in'
    '<a href="https://www.reddit.com/r/FlutterDev/">FlutterDev</a></blockquote>'
    '<script async="" src="https://embed.reddit.com/widgets.js" charset="UTF-8"></script>';
const _pinterestCode =
    '<iframe src="https://assets.pinterest.com/ext/embed.html?id=123456789012345678" height="714" width="345" frameborder="0" scrolling="no" ></iframe>';
const _oneDriveCode =
    '<iframe src="https://onedrive.live.com/embed?resid=ABC123%21456&amp;authkey=!AbC&amp;em=2" width="476px" height="288px" frameborder="0">'
    'This is an embedded <a target="_blank" href="https://office.com">Microsoft Office</a> document, '
    'powered by <a target="_blank" href="https://office.com/webapps">Office</a>.</iframe>';

const _tweet = 'https://x.com/jack/status/1790000000000000001';
const _tweetCode =
    '<blockquote class="twitter-tweet"><p lang="en" dir="ltr">Hello '
    '<a href="https://twitter.com/jack">@jack</a></p>&mdash; Jack (@jack) '
    '<a href="https://twitter.com/jack/status/1790000000000000001?ref_src=twsrc%5Etfw">May 1, 2024</a></blockquote> '
    '<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>';
const _tiktok = 'https://www.tiktok.com/@scout2015/video/6718335390845095173';
const _tiktokCode =
    '<blockquote class="tiktok-embed" cite="$_tiktok" data-video-id="6718335390845095173" style="max-width: 605px;min-width: 325px;" > '
    '<section> <a target="_blank" title="@scout2015" href="https://www.tiktok.com/@scout2015?refer=embed">@scout2015</a> </section> </blockquote> '
    '<script async src="https://www.tiktok.com/embed.js"></script>';
const _threadsPost = 'https://www.threads.net/@zuck/post/C8abcdEFgh1';
const _threadsCode =
    '<blockquote class="text-post-media" data-text-post-permalink="$_threadsPost" data-text-post-version="0">'
    '<a href="https://www.threads.net/@zuck">@zuck</a></blockquote>';
const _linkedInCode =
    '<iframe src="https://www.linkedin.com/embed/feed/update/urn:li:share:7123456789012345678" height="600" width="504" frameborder="0" allowfullscreen="" title="Embedded post"></iframe>';
const _bbcArticle = 'https://www.bbc.com/news/articles/c4g2l1z0pz5o';

/// A Google News article link of the older kind, which carries the
/// publisher's address inside it.
String _googleNewsToken(String address) => base64Url.encode([
      0x08,
      0x13,
      0x22,
      address.length,
      ...utf8.encode(address),
      0xd2,
      0x01,
      0x00,
    ]).replaceAll('=', '');

/// A site whose pattern is broken.
class _BrokenSite extends WebEmbedProvider {
  const _BrokenSite();

  @override
  String get id => 'broken';

  @override
  String get name => 'Broken';

  @override
  IconData iconFor(String kind) => Icons.error_outline;

  @override
  Color colorFor(String kind) => Colors.red;

  @override
  WebEmbedLink? recognize(Uri uri) => throw StateError('bad pattern');

  @override
  Widget buildView(
    BuildContext context,
    WebEmbedLink link,
    WebEmbedViewOptions options,
  ) =>
      const SizedBox.shrink();
}

WebEmbedLink _read(String url) {
  final link = ExtensionWebEmbedRegistry.recognize(url);
  expect(link, isNotNull, reason: url);
  return link!;
}

/// Expects [url] to be read by [site] as a [kind], saved as [address].
void _expectLink(
  String url, {
  required String site,
  required String kind,
  String? address,
  String? title,
  bool needsResolution = false,
  bool? wholePage,
  String? siteName,
  String? embed,
}) {
  final link = _read(url);
  expect(link.provider.id, site, reason: url);
  expect(link.kind, kind, reason: url);
  expect(link.url, address ?? url, reason: url);
  expect(link.needsResolution, needsResolution, reason: url);
  if (title != null) {
    expect(link.title, title, reason: url);
  }
  if (wholePage != null) {
    expect(link.showsWholePage, wholePage, reason: url);
  }
  if (siteName != null) {
    expect(link.site, siteName, reason: url);
  }
  if (embed != null) {
    expect(link.embedUrl, embed, reason: url);
  }
}

void _expectUnknown(String url) =>
    expect(ExtensionWebEmbedRegistry.recognize(url), isNull, reason: url);

void main() {
  setUp(() {
    for (final site in webEmbedSites()) {
      ExtensionWebEmbedRegistry.register(_extension, site);
    }
  });

  tearDown(() => ExtensionWebEmbedRegistry.unregisterAll(_extension));

  group('YouTube', () {
    test('videos are saved as a watch page, whatever form they come in', () {
      _expectLink(_video, site: 'youtube', kind: 'Video');
      _expectLink(
        'https://youtu.be/dQw4w9WgXcQ?t=42',
        site: 'youtube',
        kind: 'Video',
        address: '$_video&t=42',
      );
      for (final url in [
        'https://www.youtube.com/embed/dQw4w9WgXcQ?si=abc',
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
        'https://www.youtube.com/live/dQw4w9WgXcQ',
      ]) {
        _expectLink(url, site: 'youtube', kind: 'Video', address: _video);
      }
    });

    test('shorts stay shorts, without the share tracking', () {
      _expectLink(
        'https://youtube.com/shorts/abcdefghijk?feature=share',
        site: 'youtube',
        kind: 'Short',
        address: 'https://www.youtube.com/shorts/abcdefghijk',
      );
    });

    test('channels and playlist embeds name no video', () {
      _expectUnknown('https://www.youtube.com/@channel');
      _expectUnknown(
        'https://www.youtube.com/embed/videoseries?list=PL1234567890',
      );
    });
  });

  group('Pinterest', () {
    test('a pin from any country site is the same pin', () {
      _expectLink(
        'https://in.pinterest.com/pin/cozy-reading-nook--123456789012345678/',
        site: 'pinterest',
        kind: 'Pin',
        address: _pin,
        title: 'Cozy reading nook',
      );
      _expectLink(
        'https://assets.pinterest.com/ext/embed.html?id=123456789012345678',
        site: 'pinterest',
        kind: 'Pin',
        address: _pin,
      );
    });

    test('boards and short links', () {
      _expectLink(
        'https://www.pinterest.com/someone/recipes/',
        site: 'pinterest',
        kind: 'Board',
        title: 'Recipes',
      );
      _expectLink(
        'https://pin.it/abcDEF1',
        site: 'pinterest',
        kind: 'Pin',
        needsResolution: true,
      );
    });
  });

  group('Reddit', () {
    test('posts, comments and communities', () {
      _expectLink(
        'https://old.reddit.com/r/FlutterDev/comments/1abcde/some_post_title/kx12ab3/',
        site: 'reddit',
        kind: 'Comment',
        address:
            'https://www.reddit.com/r/FlutterDev/comments/1abcde/some_post_title/kx12ab3/',
        title: 'Some post title',
      );
      _expectLink(
        'https://redd.it/1abcde',
        site: 'reddit',
        kind: 'Post',
        address: 'https://www.reddit.com/comments/1abcde/',
      );
      _expectLink(
        'https://www.reddit.com/r/FlutterDev/',
        site: 'reddit',
        kind: 'Community',
        title: 'r/FlutterDev',
      );
    });

    test('share links are followed before they are shown', () {
      _expectLink(
        'https://www.reddit.com/r/FlutterDev/s/AbCdEf123',
        site: 'reddit',
        kind: 'Post',
        needsResolution: true,
      );
    });
  });

  group('Quora', () {
    test('questions, answers, Spaces and their posts', () {
      _expectLink(
        'https://www.quora.com/What-is-Flutter',
        site: 'quora',
        kind: 'Question',
        title: 'What is Flutter?',
      );
      _expectLink(
        'https://www.quora.com/What-is-Flutter/answer/Jane-Doe',
        site: 'quora',
        kind: 'Answer',
        title: 'What is Flutter?',
      );
      _expectLink(
        'https://www.quora.com/q/somespace/Some-post-title',
        site: 'quora',
        kind: 'Post',
        title: 'Some post title',
      );
      _expectLink(
        'https://www.quora.com/q/somespace',
        site: 'quora',
        kind: 'Space',
      );
    });
  });

  group('Instagram', () {
    test('posts and reels, without whose profile they were opened from', () {
      _expectLink(
        'https://www.instagram.com/reel/C1a2B3c4D5e/?igsh=abc',
        site: 'instagram',
        kind: 'Reel',
        address: 'https://www.instagram.com/reel/C1a2B3c4D5e/',
      );
      _expectLink(
        'https://www.instagram.com/someone/p/C1a2B3c4D5e/',
        site: 'instagram',
        kind: 'Post',
        address: 'https://www.instagram.com/p/C1a2B3c4D5e/',
      );
    });

    test('profiles are not embedded', () {
      _expectUnknown('https://www.instagram.com/someone/');
    });
  });

  group('Google Maps', () {
    test('places, directions and views', () {
      _expectLink(
        'https://www.google.com/maps/place/Eiffel+Tower/@48.8583701,2.2944813,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d48.8583701!4d2.2944813',
        site: 'google_maps',
        kind: 'Place',
        title: 'Eiffel Tower',
      );
      _expectLink(
        'https://www.google.com/maps/dir/Paris/Lyon/',
        site: 'google_maps',
        kind: 'Directions',
        title: 'Paris to Lyon',
      );
      _expectLink(
        'https://www.google.com/maps/@48.8583701,2.2944813,15z',
        site: 'google_maps',
        kind: 'Map',
      );
      _expectLink(
        'https://maps.app.goo.gl/AbCdEf123',
        site: 'google_maps',
        kind: 'Place',
        needsResolution: true,
      );
    });
  });

  group('Google Workspace', () {
    test('each product by its own name', () {
      final files = {
        '$_document?usp=sharing': ('Document', 'Google Docs', _document),
        _sheet: ('Spreadsheet', 'Google Sheets', _sheet),
        'https://docs.google.com/presentation/u/1/d/$_fileId/edit#slide=id.p': (
          'Presentation',
          'Google Slides',
          null
        ),
        'https://docs.google.com/forms/d/e/1FAIpQLSf9aB8cD7eF6gH5iJ4kL3mN2oP1qR0sT9uV8wX7yZ6aB5cD4e/viewform':
            ('Form', 'Google Forms', null),
        'https://drive.google.com/file/d/$_fileId/view': (
          'File',
          'Google Drive',
          null
        ),
      };
      files.forEach((url, expected) {
        final (kind, site, address) = expected;
        _expectLink(
          url,
          site: 'google_workspace',
          kind: kind,
          address: address,
        );
        expect(_read(url).site, site);
      });
      expect(_read(_sheet).id, _fileId);
    });

    test('files published to the web', () {
      const published =
          'https://docs.google.com/spreadsheets/d/e/2PACX-1vQx9bSgVb2rV1Q8mZ3hX7kP4cT6wN0yJ5aL2dE8fG1hI3jK4lM5nO6pQ7rS8tU9vW0xY1zA2bC3dE4fG5hI/pubhtml';
      _expectLink(published, site: 'google_workspace', kind: 'Spreadsheet');
    });

    test("titles lose Google's product name, and sign-in pages say nothing",
        () {
      expect(
        GoogleWorkspaceEmbeds.tidyGoogleFileTitle(
          'Budget 2026 - Google Sheets',
        ),
        'Budget 2026',
      );
      expect(
        GoogleWorkspaceEmbeds.tidyGoogleFileTitle('Q3 plan – Google Slides'),
        'Q3 plan',
      );
      for (final title in [
        null,
        'Google Docs: Sign-in',
        'Google Sheets',
        'Meet Google Drive – One place for all your files',
      ]) {
        expect(GoogleWorkspaceEmbeds.tidyGoogleFileTitle(title), isNull);
      }
    });
  });

  group('Microsoft Office', () {
    test("OneDrive's embed codes by the options each app adds", () {
      _expectLink(
        _wordCode,
        site: 'microsoft_office',
        kind: 'Document',
        address: _wordCode.replaceFirst('!AbC', '%21AbC'),
      );
      expect(_read(_wordCode).site, 'Word');
      expect(
        _read('$_wordCode&wdAllowInteractivity=False').kind,
        'Workbook',
      );
      expect(_read('$_wordCode&wdAr=1.7777777777777777').kind, 'Presentation');
    });

    test('share links, SharePoint, the viewer and public files', () {
      for (final (url, kind) in [
        ('https://1drv.ms/w/s!AbCdEf', 'Document'),
        ('https://1drv.ms/x/s!AbCdEf', 'Workbook'),
        ('https://1drv.ms/p/s!AbCdEf', 'Presentation'),
      ]) {
        _expectLink(
          url,
          site: 'microsoft_office',
          kind: kind,
          needsResolution: true,
        );
      }
      _expectLink(
        'https://contoso.sharepoint.com/:w:/g/personal/jane/EabcDEF?e=xyz',
        site: 'microsoft_office',
        kind: 'Document',
      );
      _expectLink(
        'https://view.officeapps.live.com/op/view.aspx?src=https%3A%2F%2Fexample.com%2Fdeck.pptx',
        site: 'microsoft_office',
        kind: 'Presentation',
        title: 'deck',
      );
      _expectLink(
        'https://example.com/files/report.docx',
        site: 'microsoft_office',
        kind: 'Document',
        title: 'report',
      );
      // A PDF is left to the PDF viewer.
      expect(
        _read('https://example.com/files/report.pdf').provider.id,
        'pdf',
      );
      _expectUnknown('https://example.com/');
    });
  });

  group('social networks', () {
    test('X posts from any of its addresses, and profiles as pages', () {
      for (final url in [
        'https://twitter.com/jack/status/1790000000000000001?s=20',
        'https://mobile.twitter.com/jack/status/1790000000000000001',
        'https://fxtwitter.com/jack/status/1790000000000000001',
      ]) {
        _expectLink(url, site: 'x', kind: 'Post', address: _tweet);
      }
      _expectLink(
        'https://x.com/i/web/status/1790000000000000001',
        site: 'x',
        kind: 'Post',
        address: 'https://x.com/i/status/1790000000000000001',
        wholePage: false,
      );
      expect(
        _read(_tweet).embedUrl,
        'https://platform.twitter.com/embed/Tweet.html'
        '?id=1790000000000000001&dnt=true',
      );
      _expectLink(
        'https://x.com/jack',
        site: 'x',
        kind: 'Profile',
        title: '@jack',
        wholePage: true,
      );
      _expectUnknown('https://x.com/home');
      _expectUnknown('https://twitter.com/search?q=flutter');
    });

    test('LinkedIn posts embed, and profiles, companies and jobs show whole',
        () {
      _expectLink(
        'https://www.linkedin.com/posts/jane-doe_hiring-activity-7123456789012345678-AbCd?utm_source=share',
        site: 'linkedin',
        kind: 'Post',
        address:
            'https://www.linkedin.com/posts/jane-doe_hiring-activity-7123456789012345678-AbCd/',
        embed: 'https://www.linkedin.com/embed/feed/update/'
            'urn:li:activity:7123456789012345678',
        wholePage: false,
      );
      _expectLink(
        'https://www.linkedin.com/feed/update/urn:li:activity:7123456789012345678/',
        site: 'linkedin',
        kind: 'Post',
      );
      _expectLink(
        'https://in.linkedin.com/in/jane-doe-12a345b6',
        site: 'linkedin',
        kind: 'Profile',
        address: 'https://www.linkedin.com/in/jane-doe-12a345b6/',
        title: 'Jane Doe',
        wholePage: true,
      );
      _expectLink(
        'https://www.linkedin.com/company/microsoft/',
        site: 'linkedin',
        kind: 'Company',
        wholePage: true,
      );
      _expectLink(
        'https://www.linkedin.com/jobs/view/3901234567/',
        site: 'linkedin',
        kind: 'Job',
        wholePage: true,
      );
    });

    test('Facebook posts, videos, reels, Pages and share links', () {
      _expectLink(
        'https://www.facebook.com/zuck/posts/10114617232315431',
        site: 'facebook',
        kind: 'Post',
        wholePage: false,
      );
      expect(
        _read('https://www.facebook.com/zuck/posts/10114617232315431').embedUrl,
        startsWith('https://www.facebook.com/plugins/post.php?href='),
      );
      _expectLink(
        'https://m.facebook.com/watch/?v=123456789012345',
        site: 'facebook',
        kind: 'Video',
        address: 'https://www.facebook.com/watch?v=123456789012345',
      );
      _expectLink(
        'https://www.facebook.com/reel/123456789012345',
        site: 'facebook',
        kind: 'Reel',
      );
      _expectLink(
        'https://fb.watch/abcDEF123/',
        site: 'facebook',
        kind: 'Video',
        needsResolution: true,
      );
      _expectLink(
        'https://www.facebook.com/share/p/1AbCdEfGh/',
        site: 'facebook',
        kind: 'Post',
        needsResolution: true,
      );
      _expectLink(
        'https://www.facebook.com/NASA',
        site: 'facebook',
        kind: 'Page',
        wholePage: false,
      );
      _expectLink(
        'https://www.facebook.com/groups/flutterdev',
        site: 'facebook',
        kind: 'Group',
        wholePage: true,
      );
      _expectUnknown('https://www.facebook.com/login');
    });

    test('Threads, TikTok, Snapchat and Telegram', () {
      _expectLink(
        '$_threadsPost?xmt=abc',
        site: 'threads',
        kind: 'Post',
        address: _threadsPost,
        embed: '$_threadsPost/embed',
      );
      _expectLink(
        'https://www.threads.com/@zuck',
        site: 'threads',
        kind: 'Profile',
        wholePage: true,
      );
      _expectLink(
        '$_tiktok?is_from_webapp=1',
        site: 'tiktok',
        kind: 'Video',
        address: _tiktok,
        embed: 'https://www.tiktok.com/embed/v2/6718335390845095173',
      );
      _expectLink(
        'https://vm.tiktok.com/ZMabc123/',
        site: 'tiktok',
        kind: 'Video',
        needsResolution: true,
      );
      const spotlight =
          'https://www.snapchat.com/spotlight/W7_EDlXWTBiXAEEniNoMPwAAYYWl0Y2Ft';
      _expectLink(
        spotlight,
        site: 'snapchat',
        kind: 'Spotlight',
        embed: '$spotlight/embed',
      );
      _expectLink(
        'https://www.snapchat.com/add/someone',
        site: 'snapchat',
        kind: 'Profile',
        wholePage: true,
      );
      _expectLink(
        'https://t.me/durov/123',
        site: 'telegram',
        kind: 'Post',
        embed: 'https://t.me/durov/123?embed=1&userpic=true',
      );
      _expectLink(
        'https://t.me/s/durov',
        site: 'telegram',
        kind: 'Channel',
        wholePage: true,
      );
      _expectUnknown('https://t.me/joinchat/AbCdEf');
      _expectUnknown('https://t.me/+AbCdEf');
    });

    test('Blind and Bluesky show their own pages', () {
      _expectLink(
        'https://www.teamblind.com/post/Is-it-worth-joining-Google-in-2024-xY7a9b2C',
        site: 'blind',
        kind: 'Post',
        address:
            'https://www.teamblind.com/post/Is-it-worth-joining-Google-in-2024-xY7a9b2C',
        title: 'Is it worth joining Google in 2024?',
        wholePage: true,
      );
      _expectLink(
        'https://www.teamblind.com/company/Google/',
        site: 'blind',
        kind: 'Company',
        address: 'https://www.teamblind.com/company/Google',
        wholePage: true,
      );
      _expectLink(
        'https://bsky.app/profile/jay.bsky.team/post/3kabc123xyz',
        site: 'bluesky',
        kind: 'Post',
        wholePage: true,
      );
    });
  });

  group('music and video', () {
    test('Spotify, in any language, and its short links', () {
      _expectLink(
        'https://open.spotify.com/intl-de/track/4cOdK2wGLETKBW3PvgPWqT?si=abc',
        site: 'spotify',
        kind: 'Track',
        address: 'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
        embed: 'https://open.spotify.com/embed/track/4cOdK2wGLETKBW3PvgPWqT',
      );
      _expectLink(
        'https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M',
        site: 'spotify',
        kind: 'Playlist',
        address: 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );
      _expectLink(
        'https://open.spotify.com/show/2MAi0BvDc6GTFvKFPXnkCL',
        site: 'spotify',
        kind: 'Podcast',
      );
      _expectLink(
        'https://spotify.link/AbCdEf123',
        site: 'spotify',
        kind: 'Music',
        needsResolution: true,
      );
    });

    test('Apple Music and Apple Podcasts', () {
      _expectLink(
        'https://music.apple.com/in/album/folklore/1524801260?i=1524801263',
        site: 'apple_media',
        kind: 'Song',
        siteName: 'Apple Music',
        title: 'Folklore',
        embed: 'https://embed.music.apple.com/in/album/folklore/1524801260'
            '?i=1524801263',
      );
      _expectLink(
        'https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb',
        site: 'apple_media',
        kind: 'Playlist',
      );
      _expectLink(
        'https://podcasts.apple.com/us/podcast/the-daily/id1200361736',
        site: 'apple_media',
        kind: 'Podcast',
        siteName: 'Apple Podcasts',
        embed: 'https://embed.podcasts.apple.com/us/podcast/the-daily/'
            'id1200361736',
      );
    });

    test('SoundCloud, Vimeo, Dailymotion, Loom, TED and Twitch', () {
      _expectLink(
        'https://soundcloud.com/forss/flickermood',
        site: 'soundcloud',
        kind: 'Track',
        embed: 'https://w.soundcloud.com/player/'
            '?url=https%3A%2F%2Fsoundcloud.com%2Fforss%2Fflickermood'
            '&visual=true&show_comments=false',
      );
      _expectLink(
        'https://soundcloud.com/forss/sets/soulhack',
        site: 'soundcloud',
        kind: 'Playlist',
      );
      _expectLink(
        'https://soundcloud.com/forss',
        site: 'soundcloud',
        kind: 'Artist',
      );
      _expectUnknown('https://soundcloud.com/discover');
      _expectLink(
        'https://vimeo.com/76979871/abcdef1234',
        site: 'vimeo',
        kind: 'Video',
        embed: 'https://player.vimeo.com/video/76979871?h=abcdef1234&dnt=1',
      );
      _expectLink(
        'https://vimeo.com/channels/staffpicks/76979871',
        site: 'vimeo',
        kind: 'Video',
        address: 'https://vimeo.com/76979871',
      );
      _expectUnknown('https://vimeo.com/showcase/1234567');
      _expectLink(
        'https://dai.ly/x8abc12',
        site: 'dailymotion',
        kind: 'Video',
        address: 'https://www.dailymotion.com/video/x8abc12',
      );
      _expectLink(
        'https://www.loom.com/share/0123456789abcdef0123456789abcdef?sid=x',
        site: 'loom',
        kind: 'Video',
        address: 'https://www.loom.com/share/0123456789abcdef0123456789abcdef',
        embed: 'https://www.loom.com/embed/0123456789abcdef0123456789abcdef',
      );
      _expectLink(
        'https://www.ted.com/talks/ken_robinson_do_schools_kill_creativity',
        site: 'ted',
        kind: 'Talk',
      );
      _expectLink(
        'https://www.twitch.tv/shroud',
        site: 'twitch',
        kind: 'Channel',
        wholePage: true,
      );
    });
  });

  group('work, design and code', () {
    test('Notion pages and databases show whole, titled by their slug', () {
      _expectLink(
        'https://www.notion.so/acme/Meeting-notes-0123456789abcdef0123456789abcdef?pvs=4',
        site: 'notion',
        kind: 'Page',
        address: 'https://www.notion.so/acme/'
            'Meeting-notes-0123456789abcdef0123456789abcdef',
        title: 'Meeting notes',
        wholePage: true,
      );
      _expectLink(
        'https://acme.notion.site/0123456789abcdef0123456789abcdef?v=fedcba9876543210fedcba9876543210',
        site: 'notion',
        kind: 'Database',
      );
      _expectUnknown('https://www.notion.so/pricing');
    });

    test('Figma, Canva and Miro in their own viewers', () {
      _expectLink(
        'https://www.figma.com/design/AbCdEfGhIjKlMnOpQrStUv/My-App?node-id=1-2&t=xyz',
        site: 'figma',
        kind: 'Design',
        address: 'https://www.figma.com/design/AbCdEfGhIjKlMnOpQrStUv/My-App'
            '?node-id=1-2',
        title: 'My App',
      );
      _expectLink(
        'https://www.figma.com/board/AbCdEfGhIjKlMnOpQrStUv/Brainstorm',
        site: 'figma',
        kind: 'Board',
        siteName: 'FigJam',
      );
      _expectLink(
        'https://www.canva.com/design/DAFabc123/xyzTOKEN/view?utm_content=x',
        site: 'canva',
        kind: 'Design',
        address: 'https://www.canva.com/design/DAFabc123/xyzTOKEN/view',
        embed: 'https://www.canva.com/design/DAFabc123/xyzTOKEN/view?embed',
      );
      _expectLink(
        'https://miro.com/app/board/uXjVPabcdef=/',
        site: 'miro',
        kind: 'Board',
        embed: 'https://miro.com/app/live-embed/uXjVPabcdef=/?autoplay=true',
      );
    });

    test('GitHub repositories, issues, pull requests, code and gists', () {
      _expectLink(
        'https://github.com/flutter/flutter',
        site: 'github',
        kind: 'Repository',
        title: 'flutter/flutter',
        wholePage: true,
      );
      _expectLink(
        'https://github.com/flutter/flutter/issues/12345',
        site: 'github',
        kind: 'Issue',
        title: 'flutter/flutter#12345',
      );
      _expectLink(
        'https://github.com/flutter/flutter/pull/678',
        site: 'github',
        kind: 'Pull request',
      );
      _expectLink(
        'https://github.com/flutter/flutter/blob/master/README.md#L10',
        site: 'github',
        kind: 'Code',
        title: 'README.md',
      );
      _expectLink(
        'https://github.com/torvalds',
        site: 'github',
        kind: 'Profile',
      );
      _expectUnknown('https://github.com/settings/profile');
      _expectLink(
        'https://gist.github.com/octocat/0123456789abcdef0123',
        site: 'github',
        kind: 'Gist',
        embed: 'https://gist.github.com/octocat/0123456789abcdef0123.pibb',
        wholePage: false,
      );
      // Office reads a Word file better than GitHub's page about it.
      expect(
        _read('https://github.com/acme/docs/blob/main/spec.docx').provider.id,
        'microsoft_office',
      );
    });

    test('GitLab, on gitlab.com and on its own servers', () {
      _expectLink(
        'https://gitlab.com/gitlab-org/gitlab/-/issues/123',
        site: 'gitlab',
        kind: 'Issue',
        title: 'gitlab-org/gitlab#123',
      );
      _expectLink(
        'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/45',
        site: 'gitlab',
        kind: 'Merge request',
        title: 'gitlab-org/gitlab!45',
      );
      _expectLink(
        'https://gitlab.gnome.org/GNOME/gtk',
        site: 'gitlab',
        kind: 'Repository',
      );
    });

    test('code playgrounds run in their own embeds', () {
      _expectLink(
        'https://codepen.io/team/pen/AbCdEf',
        site: 'code_playground',
        kind: 'Pen',
        siteName: 'CodePen',
        embed: 'https://codepen.io/team/embed/AbCdEf?default-tab=result',
      );
      _expectLink(
        'https://jsfiddle.net/user1/abc12345/3/',
        site: 'code_playground',
        kind: 'Fiddle',
      );
    });
  });

  group('files and storage', () {
    test('Google Drive files from old addresses too', () {
      _expectLink(
        'https://docs.google.com/file/d/$_fileId/edit',
        site: 'google_workspace',
        kind: 'File',
        embed: 'https://drive.google.com/file/d/$_fileId/preview',
      );
    });

    test('Dropbox keeps the share, and leaves Office files to Office', () {
      _expectLink(
        'https://www.dropbox.com/scl/fi/abc123xyz/Report%20Q3.pdf?rlkey=k1&dl=0&e=1&st=x9&utm_source=y',
        site: 'dropbox',
        kind: 'File',
        address: 'https://www.dropbox.com/scl/fi/abc123xyz/Report%20Q3.pdf'
            '?rlkey=k1&dl=0&e=1&st=x9',
        title: 'Report Q3.pdf',
        wholePage: true,
      );
      expect(
        _read('https://www.dropbox.com/scl/fi/abc123xyz/Budget.xlsx?rlkey=k1')
            .provider
            .id,
        'microsoft_office',
      );
    });

    test('Box, MEGA and the file-sharing sites', () {
      _expectLink(
        'https://app.box.com/s/abcdefghij1234567890',
        site: 'box',
        kind: 'Shared link',
        embed: 'https://app.box.com/embed/s/abcdefghij1234567890?view=list',
      );
      _expectLink(
        'https://mega.nz/file/AbCdEfGh#KeyKeyKey',
        site: 'mega',
        kind: 'File',
        embed: 'https://mega.nz/embed/AbCdEfGh#KeyKeyKey',
      );
      _expectLink(
        'https://mega.nz/#!AbCdEfGh!KeyKeyKey',
        site: 'mega',
        kind: 'File',
        address: 'https://mega.nz/file/AbCdEfGh#KeyKeyKey',
      );
      _expectLink(
        'https://mega.nz/folder/AbCdEfGh#KeyKeyKey',
        site: 'mega',
        kind: 'Folder',
        wholePage: true,
      );
      _expectLink(
        'https://we.tl/t-AbCdEf123',
        site: 'file_transfer',
        kind: 'Transfer',
        siteName: 'WeTransfer',
        needsResolution: true,
      );
    });

    test('OneDrive folders and photos follow Office, which keeps documents',
        () {
      _expectLink(
        'https://1drv.ms/f/s!AbCdEf',
        site: 'onedrive',
        kind: 'Folder',
        needsResolution: true,
      );
      _expectLink(
        'https://contoso.sharepoint.com/:f:/g/personal/jane/EabcDEF?e=xyz',
        site: 'onedrive',
        kind: 'Folder',
        siteName: 'SharePoint',
        wholePage: true,
      );
      expect(
        _read('https://1drv.ms/w/s!AbCdEf').provider.id,
        'microsoft_office',
      );
    });

    test('iCloud, Apple Notes and JioCloud', () {
      _expectLink(
        'https://www.icloud.com/notes/0abcDEF123#Groceries_list',
        site: 'icloud',
        kind: 'Note',
        siteName: 'Apple Notes',
        title: 'Groceries list',
        wholePage: true,
      );
      _expectLink(
        'https://www.icloud.com/iclouddrive/0abc123#Report',
        site: 'icloud',
        kind: 'File',
        siteName: 'iCloud Drive',
      );
      _expectLink(
        'https://www.icloud.com/sharedalbum/#B0abc123',
        site: 'icloud',
        kind: 'Album',
      );
      _expectLink(
        'https://www.jiocloud.com/s/?t=AbCd1234&s=a2',
        site: 'jiocloud',
        kind: 'Shared file',
        wholePage: true,
      );
    });
  });

  group('news and reading', () {
    test('news articles, by their masthead, without the tracking', () {
      const article =
          'https://timesofindia.indiatimes.com/india/budget-2026-what-changes-for-you/articleshow/112233445.cms';
      _expectLink(
        '$article?utm_source=x&ncid=y',
        site: 'news',
        kind: 'Article',
        address: article,
        siteName: 'The Times of India',
        title: 'Budget 2026 what changes for you',
        wholePage: true,
      );
      expect(_read(article).color, const Color(0xFFE21B22));
      _expectLink(
        'https://economictimes.indiatimes.com/markets/stocks/news/sensex-rises-300-points/articleshow/1234567.cms',
        site: 'news',
        kind: 'Article',
        siteName: 'The Economic Times',
      );
      _expectLink(
        _bbcArticle,
        site: 'news',
        kind: 'Article',
        siteName: 'BBC',
      );
      _expectLink(
        'https://www.bbc.co.uk/news/live/world-123456',
        site: 'news',
        kind: 'Live',
      );
      _expectLink(
        'https://www.ndtv.com/',
        site: 'news',
        kind: 'Front page',
        title: 'NDTV',
      );
      _expectLink(
        'https://www.thehindu.com/news/national/',
        site: 'news',
        kind: 'Section',
        title: 'National',
      );
      // A paper's PDF is a PDF, not a page.
      expect(
        _read('https://www.reuters.com/files/annual-report.pdf').provider.id,
        'pdf',
      );
      _expectUnknown('https://www.example.com/news/x');
    });

    test('headlines lose their masthead', () {
      expect(
        tidyWebEmbedHeadline(
          'Budget 2026: what changes for you - The Times of India',
          'The Times of India',
        ),
        'Budget 2026: what changes for you',
      );
      expect(
        tidyWebEmbedHeadline(
          'Floods hit Assam | India News - Times of India',
          'The Times of India',
        ),
        'Floods hit Assam',
      );
      expect(
        tidyWebEmbedHeadline('Rates cut - what it means', 'BBC'),
        'Rates cut - what it means',
      );
    });

    test('Google News links open the article they carry', () {
      final token = _googleNewsToken(_bbcArticle);
      expect(GoogleNewsEmbeds.decodeArticle(token), _bbcArticle);
      _expectLink(
        'https://news.google.com/rss/articles/$token?oc=5',
        site: 'news',
        kind: 'Article',
        address: _bbcArticle,
        siteName: 'BBC',
      );
      expect(GoogleNewsEmbeds.decodeArticle('AU_yqLabcdef'), isNull);
      final opaque = _read(
        'https://news.google.com/articles/AU_yqLabcdef?hl=en-IN&gl=IN&ceid=IN:en',
      );
      expect(opaque.provider.id, 'google_news');
      expect(opaque.showsWholePage, isTrue);
      expect(
        opaque.url,
        startsWith('https://news.google.com/articles/AU_yqLabcdef?hl=en-IN'),
      );
    });

    test('MSN, Wikipedia and the reading sites', () {
      _expectLink(
        'https://www.msn.com/en-in/news/india/heavy-rain-lashes-mumbai/ar-AA1abcde?ocid=msedgntp',
        site: 'msn',
        kind: 'Article',
        address:
            'https://www.msn.com/en-in/news/india/heavy-rain-lashes-mumbai/'
            'ar-AA1abcde',
        title: 'Heavy rain lashes mumbai',
      );
      _expectLink(
        'https://en.m.wikipedia.org/wiki/Alan_Turing#Early_life',
        site: 'wikipedia',
        kind: 'Article',
        address: 'https://en.wikipedia.org/wiki/Alan_Turing#Early_life',
        embed: 'https://en.m.wikipedia.org/wiki/Alan_Turing#Early_life',
        title: 'Alan Turing',
      );
      expect(_read('https://hi.wikipedia.org/wiki/भारत').title, 'भारत');
      _expectUnknown('https://www.wikipedia.org/');
      _expectLink(
        'https://medium.com/@jane/how-i-learned-flutter-1a2b3c4d5e6f?source=rss',
        site: 'medium',
        kind: 'Story',
        address: 'https://medium.com/@jane/how-i-learned-flutter-1a2b3c4d5e6f',
        title: 'How i learned flutter',
      );
      _expectLink(
        'https://open.substack.com/pub/platformer/p/the-week-in-ai?r=abc',
        site: 'substack',
        kind: 'Post',
        address: 'https://platformer.substack.com/p/the-week-in-ai',
      );
      _expectLink(
        'https://news.ycombinator.com/item?id=8863',
        site: 'hacker_news',
        kind: 'Discussion',
      );
      _expectLink(
        'https://stackoverflow.com/questions/38987/how-do-i-merge-two-dictionaries',
        site: 'stack_exchange',
        kind: 'Question',
        siteName: 'Stack Overflow',
        title: 'How do i merge two dictionaries?',
      );
      expect(
        _read('https://math.stackexchange.com/questions/12345/why-is-it').site,
        'Math Stack Exchange',
      );
      _expectLink(
        'https://m.imdb.com/title/tt15398776/?ref_=nv_sr',
        site: 'imdb',
        kind: 'Film or show',
        address: 'https://www.imdb.com/title/tt15398776/',
      );
      _expectLink(
        'https://www.goodreads.com/book/show/5907.The_Hobbit',
        site: 'goodreads',
        kind: 'Book',
        title: 'The Hobbit',
      );
      _expectLink(
        'https://archive.org/details/alice_in_wonderland_librivox',
        site: 'internet_archive',
        kind: 'Item',
        embed: 'https://archive.org/embed/alice_in_wonderland_librivox',
      );
    });
  });

  group('shopping and places', () {
    test('Amazon products from any store, by their ASIN', () {
      _expectLink(
        'https://www.amazon.in/Apple-iPhone-15-128-GB/dp/B0CHX1W1XY/ref=sr_1_1?crid=X&keywords=iphone',
        site: 'amazon',
        kind: 'Product',
        address: 'https://www.amazon.in/dp/B0CHX1W1XY',
        title: 'Apple iPhone 15 128 GB',
        wholePage: true,
      );
      _expectLink(
        'https://amazon.com/gp/product/B08N5WRWNW',
        site: 'amazon',
        kind: 'Product',
        address: 'https://www.amazon.com/dp/B08N5WRWNW',
      );
      _expectLink(
        'https://amzn.to/3abcXYZ',
        site: 'amazon',
        kind: 'Product',
        needsResolution: true,
        wholePage: true,
      );
      _expectLink(
        'https://www.amazon.co.uk/hz/wishlist/ls/ABC123XYZ',
        site: 'amazon',
        kind: 'Wish list',
      );
      _expectUnknown('https://www.amazon.in/');
    });

    test('Flipkart keeps the product id it needs', () {
      _expectLink(
        'https://www.flipkart.com/apple-iphone-15-black-128-gb/p/itm6ac6485515ae4?pid=MOBGTAGPTB3VS24W&lid=X&marketplace=FLIPKART',
        site: 'flipkart',
        kind: 'Product',
        address: 'https://www.flipkart.com/apple-iphone-15-black-128-gb/p/'
            'itm6ac6485515ae4?pid=MOBGTAGPTB3VS24W',
      );
      _expectLink(
        'https://dl.flipkart.com/s/AbCdEfuuuN',
        site: 'flipkart',
        kind: 'Product',
        needsResolution: true,
      );
    });

    test('other stores and places, by name', () {
      _expectLink(
        'https://www.myntra.com/tshirts/roadster/roadster-men-black-t-shirt/1234567/buy',
        site: 'stores',
        kind: 'Product',
        siteName: 'Myntra',
      );
      _expectLink(
        'https://www.myntra.com/men-tshirts',
        site: 'stores',
        kind: 'Store page',
      );
      _expectLink(
        'https://www.airbnb.co.in/rooms/12345678?adults=2',
        site: 'places',
        kind: 'Stay',
        siteName: 'Airbnb',
      );
      _expectLink(
        'https://www.zomato.com/bangalore/truffles-koramangala/order',
        site: 'places',
        kind: 'Restaurant',
        siteName: 'Zomato',
      );
      _expectUnknown('https://www.myntra.com/');
    });
  });

  group('PDF', () {
    test('any PDF on the web, and arXiv papers', () {
      _expectLink(
        'https://example.com/files/annual_report.pdf?token=abc#page=2',
        site: 'pdf',
        kind: 'Document',
        address: 'https://example.com/files/annual_report.pdf?token=abc',
        title: 'annual report',
      );
      _expectLink(
        'https://arxiv.org/abs/1706.03762v5',
        site: 'pdf',
        kind: 'Paper',
        siteName: 'arXiv',
        embed: 'https://arxiv.org/pdf/1706.03762v5',
      );
      _expectLink(
        'https://arxiv.org/pdf/1706.03762.pdf',
        site: 'pdf',
        kind: 'Paper',
        address: 'https://arxiv.org/abs/1706.03762',
      );
    });
  });

  group('the / menu', () {
    test('each site entry takes only its own kind of link', () {
      final word = _read(_wordCode);
      final document = _read(_document);
      final sheet = _read(_sheet);
      final workbook = _read('https://1drv.ms/x/s!AbCdEf');

      expect(webEmbedEntryById('word').accepts(word), isTrue);
      expect(webEmbedEntryById('word').accepts(document), isFalse);
      expect(webEmbedEntryById('excel').accepts(word), isFalse);
      expect(webEmbedEntryById('excel').accepts(workbook), isTrue);
      expect(webEmbedEntryById('google_docs').accepts(document), isTrue);
      expect(webEmbedEntryById('google_sheets').accepts(document), isFalse);
      expect(webEmbedEntryById('google_sheets').accepts(sheet), isTrue);
      expect(webEmbedEntryById('').accepts(workbook), isTrue);
    });

    test('entries that take related sites', () {
      final news = _read(
        'https://news.google.com/rss/articles/AU_yqLabcdef?oc=5',
      );
      final msn = _read(
        'https://www.msn.com/en-in/news/india/heavy-rain/ar-AA1abcde',
      );
      final folder = _read('https://drive.google.com/drive/folders/$_fileId');
      final note = _read('https://www.icloud.com/notes/0abcDEF123#Groceries');
      final drive = _read('https://www.icloud.com/iclouddrive/0abc123#Report');

      expect(webEmbedEntryById('news').accepts(news), isTrue);
      expect(webEmbedEntryById('news').accepts(msn), isTrue);
      expect(webEmbedEntryById('news').accepts(folder), isFalse);
      expect(webEmbedEntryById('google_drive').accepts(folder), isTrue);
      expect(
        webEmbedEntryById('google_drive').accepts(_read(_document)),
        isFalse,
      );
      expect(
        webEmbedEntryById('onedrive').accepts(_read('https://1drv.ms/w/s!Ab')),
        isTrue,
      );
      expect(webEmbedEntryById('apple_notes').accepts(note), isTrue);
      expect(webEmbedEntryById('apple_notes').accepts(drive), isFalse);
      expect(webEmbedEntryById('icloud').accepts(drive), isTrue);
    });

    test('every entry names a site that is registered', () {
      final sites = {for (final site in webEmbedSites()) site.id};
      final ids = {for (final entry in webEmbedEntries) entry.id};
      expect(ids.length, webEmbedEntries.length);
      for (final entry in webEmbedEntries.where((e) => !e.isAnySite)) {
        expect(sites, contains(entry.provider!.id), reason: entry.id);
      }
    });
  });

  group('registry', () {
    test('embed codes give the one address they show', () {
      expect(
        webEmbedAddressFrom(_instagramCode),
        'https://www.instagram.com/p/C1a2B3c4D5e/?utm_source=ig_embed&utm_campaign=loading',
      );
      expect(
        webEmbedAddressFrom(_redditCode),
        'https://www.reddit.com/r/FlutterDev/comments/1abcde/some_post_title/',
      );
      expect(
        webEmbedAddressFrom(_pinterestCode),
        'https://assets.pinterest.com/ext/embed.html?id=123456789012345678',
      );
      expect(webEmbedAddressFrom(_oneDriveCode), _wordCode);
      // The post is preferred over the author's and hashtags' links.
      expect(
        webEmbedAddressFrom(_tweetCode),
        'https://twitter.com/jack/status/1790000000000000001?ref_src=twsrc%5Etfw',
      );
      expect(webEmbedAddressFrom(_tiktokCode), _tiktok);
      expect(webEmbedAddressFrom(_threadsCode), _threadsPost);
      expect(
        ExtensionWebEmbedRegistry.recognize(webEmbedAddressFrom(_linkedInCode))
            ?.url,
        'https://www.linkedin.com/feed/update/'
        'urn:li:share:7123456789012345678/',
      );
      expect(
        webEmbedAddressFrom('www.youtube.com/watch?v=dQw4w9WgXcQ'),
        _video,
      );
      expect(webEmbedAddressFrom('just some text'), isNull);
    });

    test("a page's title is kept only when it says what the link is", () {
      final pin = _read(_pin);
      final post = _read('https://www.instagram.com/p/C1a2B3c4D5e/');
      expect(
        webEmbedPageTitle(pin, ' Cozy reading nook '),
        'Cozy reading nook',
      );
      expect(
        webEmbedPageTitle(pin, 'How do I build a login page?'),
        'How do I build a login page?',
      );
      expect(webEmbedPageTitle(pin, 'Pinterest'), isNull);
      expect(webEmbedPageTitle(pin, ''), isNull);
      expect(webEmbedPageTitle(post, 'Login • Instagram'), isNull);
      expect(webEmbedPageTitle(post, 'Sign in - Google Accounts'), isNull);
    });

    test('canonical addresses', () {
      expect(
        ExtensionWebEmbedRegistry.canonicalUrl('https://youtu.be/dQw4w9WgXcQ'),
        _video,
      );
      // A short link is kept until it has been followed.
      expect(
        ExtensionWebEmbedRegistry.canonicalUrl('https://pin.it/abcDEF1'),
        'https://pin.it/abcDEF1',
      );
      expect(
        ExtensionWebEmbedRegistry.canonicalUrl('https://example.com/a'),
        'https://example.com/a',
      );
    });

    test('a site that throws is passed over', () {
      ExtensionWebEmbedRegistry.unregisterAll(_extension);
      ExtensionWebEmbedRegistry.register('test.broken', const _BrokenSite());
      addTearDown(() => ExtensionWebEmbedRegistry.unregisterAll('test.broken'));
      for (final site in webEmbedSites()) {
        ExtensionWebEmbedRegistry.register(_extension, site);
      }

      expect(_read(_pin).provider.id, 'pinterest');
      _expectUnknown('https://example.com/');
    });
  });

  group('bookmarks', () {
    test('are saved under the address the site knows them by', () {
      expect(bookmarkAddress('youtu.be/dQw4w9WgXcQ'), _video);
      expect(
        bookmarkAddress(
          'https://in.pinterest.com/pin/cozy-reading-nook--123456789012345678/?utm_source=x',
        ),
        _pin,
      );
      expect(
        bookmarkAddress('https://example.com/a?utm_source=x'),
        'https://example.com/a',
      );
      expect(bookmarkAddress('not a link'), isNull);
    });

    test("a site's embed code saves only the post it shows", () {
      expect(
        extractBookmarkUrls(_instagramCode),
        ['https://www.instagram.com/p/C1a2B3c4D5e/'],
      );
      expect(
        extractBookmarkUrls(_redditCode),
        [
          'https://www.reddit.com/r/FlutterDev/comments/1abcde/some_post_title/',
        ],
      );
      expect(extractBookmarkUrls(_pinterestCode), [_pin]);
    });

    test('a pasted list is saved once per page', () {
      expect(
        extractBookmarkUrls(
          'https://youtu.be/dQw4w9WgXcQ and $_video, plus https://example.com/page.',
        ),
        [_video, 'https://example.com/page'],
      );
      expect(
        extractBookmarkUrls(
          '<p><a href="https://example.com/one">one</a> and '
          '<a href="https://example.com/two">two</a></p>',
        ),
        ['https://example.com/one', 'https://example.com/two'],
      );
    });

    test('are grouped by the site an extension knows them as', () {
      expect(bookmarkSite(_sheet), 'Google Sheets');
      expect(bookmarkSite('https://youtu.be/dQw4w9WgXcQ'), 'YouTube');
      expect(bookmarkSite('https://www.example.com/a'), 'example.com');
    });

    test('forget what a site made of them once the site is gone', () {
      expect(bookmarkEmbed(_sheet)?.site, 'Google Sheets');
      ExtensionWebEmbedRegistry.unregisterAll(_extension);
      expect(bookmarkEmbed(_sheet), isNull);
      expect(bookmarkSite(_sheet), 'docs.google.com');
    });

    test("are named by the page's title until renamed", () {
      const saved = BookmarkMetadata(url: _pin, title: 'Cozy reading nook');
      expect(saved.displayTitle('pinterest.com'), 'Cozy reading nook');
      expect(saved.displayTitle('My reading corner'), 'My reading corner');
      expect(
        const BookmarkMetadata(url: _pin).displayTitle('pinterest.com'),
        'pinterest.com',
      );
    });
  });
}
