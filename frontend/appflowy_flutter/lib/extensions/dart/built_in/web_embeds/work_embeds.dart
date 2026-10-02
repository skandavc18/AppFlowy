import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:flutter/material.dart';

import 'web_embed_fetch.dart';
import 'web_embed_site_base.dart';

/// A short link that only says which site it is on until it is followed.
WebEmbedLink _shortLink(
  WebEmbedProvider provider,
  String kind,
  String url, {
  double width = 800,
  double height = 480,
}) =>
    WebEmbedLink(
      provider: provider,
      kind: kind,
      url: url,
      defaultWidth: width,
      defaultHeight: height,
      needsResolution: true,
    );

/// [title]'s first part, before the site's own name joined on with [joint].
String _firstPart(String title, String joint) =>
    title.split(joint).first.trim();

/// Notion pages and databases, shown as Notion's own page. A public page
/// reads without an account; a private one asks the reader to sign in, which
/// the frame keeps.
class NotionEmbeds extends AppPageWebEmbedProvider {
  const NotionEmbeds();

  static final _pageId = RegExp(r'([0-9a-f]{32})$', caseSensitive: false);
  static final _dashedId = RegExp(
    r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
    caseSensitive: false,
  );

  @override
  String get id => 'notion';

  @override
  String get name => 'Notion';

  @override
  List<String> get keywords => const [
        'notion',
        'page',
        'wiki',
        'database',
        'notes',
        'doc',
        'notion.site',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Database' => Icons.table_chart_rounded,
        'Form' => Icons.list_alt_rounded,
        _ => Icons.description_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF37352F);

  @override
  bool ownsHost(String host) =>
      isWebEmbedHost(host, 'notion.so') ||
      isWebEmbedHost(host, 'notion.site') ||
      isWebEmbedHost(host, 'notion.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!ownsHost(host)) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (segments.isEmpty) {
      return null;
    }
    final last = segments.last;
    final match = _pageId.firstMatch(last) ?? _dashedId.firstMatch(last);
    final id = match?.group(1)?.replaceAll('-', '').toLowerCase();
    final form = segments.first == 'form' || segments.contains('forms');
    if (id == null && !form) {
      return null;
    }
    // A page's slug is its title with the id on the end.
    final slug = match == null || match.start < 2
        ? null
        : last.substring(0, match.start - 1);
    final view = uri.queryParameters['v'];
    final peek = uri.queryParameters['p'];
    final kind = form
        ? 'Form'
        : view != null
            ? 'Database'
            : 'Page';
    return webEmbedPage(
      this,
      kind,
      Uri(
        scheme: 'https',
        host: host == 'notion.so' ? 'www.notion.so' : host,
        path: uri.path,
        queryParameters: view == null && peek == null
            ? null
            : {
                if (view != null) 'v': view,
                if (peek != null) 'p': peek,
              },
      ).toString(),
      id: id,
      title: slug == null ? null : webEmbedTitleFromSlug(slug),
      width: 720,
      height: 720,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => _firstPart(title, ' | Notion'),
      );
}

/// Designs, prototypes, FigJam boards and slides, shown in Figma's own
/// embedded viewer.
class FigmaEmbeds extends FramedWebEmbedProvider {
  const FigmaEmbeds();

  static const _kinds = {
    'file': 'Design',
    'design': 'Design',
    'proto': 'Prototype',
    'board': 'Board',
    'slides': 'Slides',
    'deck': 'Slides',
    'site': 'Site',
  };
  static const _kept = {
    'node-id',
    'page-id',
    'starting-point-node-id',
    'scaling',
    'content-scaling',
  };
  static final _key = RegExp(r'^[A-Za-z0-9]{10,}$');

  @override
  String get id => 'figma';

  @override
  String get name => 'Figma';

  @override
  List<String> get keywords => const [
        'figma',
        'figjam',
        'design',
        'prototype',
        'mockup',
        'whiteboard',
        'ui',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Prototype' => Icons.touch_app_rounded,
        'Board' => Icons.dashboard_customize_rounded,
        'Slides' => Icons.slideshow_rounded,
        _ => Icons.palette_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFA259FF);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'figma.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'figma.com' &&
        host != 'www.figma.com' &&
        host != 'embed.figma.com') {
      return null;
    }
    final segments = webEmbedSegments(uri);
    // The viewer inside an embed code names the design in `url`.
    if (segments.length == 1 && segments.first == 'embed') {
      final inner = Uri.tryParse(uri.queryParameters['url'] ?? '');
      return inner == null ||
              !isWebEmbedHost(inner.host.toLowerCase(), 'figma.com')
          ? null
          : _design(inner);
    }
    return _design(uri);
  }

  WebEmbedLink? _design(Uri uri) {
    final segments = webEmbedSegments(uri);
    if (segments.length < 2) {
      return null;
    }
    final kind = _kinds[segments[0]];
    final key = segments[1];
    if (kind == null || !_key.hasMatch(key)) {
      return null;
    }
    final kept = {
      for (final entry in uri.queryParameters.entries)
        if (_kept.contains(entry.key)) entry.key: entry.value,
    };
    final url = Uri(
      scheme: 'https',
      host: 'www.figma.com',
      path: segments.take(3).join('/'),
      queryParameters: kept.isEmpty ? null : kept,
    ).toString();
    return WebEmbedLink(
      provider: this,
      kind: kind,
      siteName: switch (kind) {
        'Board' => 'FigJam',
        'Slides' => 'Figma Slides',
        'Site' => 'Figma Sites',
        _ => null,
      },
      url: url,
      id: key,
      embedUrl: Uri.https('www.figma.com', '/embed', {
        'embed_host': 'share',
        'url': url,
      }).toString(),
      title: segments.length >= 3 ? webEmbedTitleFromSlug(segments[2]) : null,
      defaultWidth: 800,
      defaultHeight: 450,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final json = await fetchWebEmbedJson(
      Uri.https('www.figma.com', '/api/oembed', {'url': link.url}),
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

/// Canva designs shared with a public view link, shown in Canva's own
/// embedded viewer, and those only shared to edit, as Canva's page.
class CanvaEmbeds extends AppPageWebEmbedProvider {
  const CanvaEmbeds();

  static final _design = RegExp(r'^DA[A-Za-z0-9_-]{6,}$');
  static const _modes = {'view', 'edit', 'watch', 'present'};

  @override
  String get id => 'canva';

  @override
  String get name => 'Canva';

  @override
  List<String> get keywords => const [
        'canva',
        'design',
        'presentation',
        'poster',
        'graphic',
        'slides',
      ];

  @override
  IconData iconFor(String kind) => Icons.brush_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF00C4CC);

  @override
  bool ownsHost(String host) =>
      isWebEmbedHost(host, 'canva.com') || host == 'canva.link';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'canva.link') {
      return segments.length == 1
          ? _shortLink(this, 'Design', 'https://canva.link/${segments.first}')
          : null;
    }
    if (!isWebEmbedHost(host, 'canva.com') ||
        segments.length < 2 ||
        segments[0] != 'design' ||
        !_design.hasMatch(segments[1])) {
      return null;
    }
    final id = segments[1];
    final token = segments.length >= 3 && !_modes.contains(segments[2])
        ? segments[2]
        : null;
    final editing = segments.contains('edit');
    if (token == null || editing) {
      return webEmbedPage(
        this,
        'Design',
        'https://www.canva.com/design/${segments.skip(1).join('/')}',
        id: id,
        width: 800,
        height: 560,
      );
    }
    final view = 'https://www.canva.com/design/$id/$token/view';
    return WebEmbedLink(
      provider: this,
      kind: 'Design',
      url: view,
      id: id,
      embedUrl: '$view?embed',
      defaultWidth: 800,
      defaultHeight: 450,
    );
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => _firstPart(title, ' - Canva'),
      );
}

/// Miro boards, shown in Miro's own live embed.
class MiroEmbeds extends AppPageWebEmbedProvider {
  const MiroEmbeds();

  static final _board = RegExp(r'^[A-Za-z0-9_=-]{8,}$');
  static const _pages = {'board', 'live-embed', 'embed'};

  @override
  String get id => 'miro';

  @override
  String get name => 'Miro';

  @override
  List<String> get keywords =>
      const ['miro', 'whiteboard', 'board', 'diagram', 'brainstorm'];

  @override
  IconData iconFor(String kind) => Icons.dashboard_customize_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFFFFD02F);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'miro.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final segments = webEmbedSegments(uri);
    if (!isWebEmbedHost(uri.host.toLowerCase(), 'miro.com') ||
        segments.length < 3 ||
        segments[0] != 'app' ||
        !_pages.contains(segments[1]) ||
        !_board.hasMatch(segments[2])) {
      return null;
    }
    final board = segments[2];
    return WebEmbedLink(
      provider: this,
      kind: 'Board',
      url: 'https://miro.com/app/board/$board/',
      id: board,
      embedUrl: 'https://miro.com/app/live-embed/$board/?autoplay=true',
      defaultWidth: 768,
      defaultHeight: 432,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => _firstPart(title, ', Online Whiteboard'),
      );
}

/// Shared Airtable views and forms, shown in Airtable's own embed.
class AirtableEmbeds extends FramedWebEmbedProvider {
  const AirtableEmbeds();

  static final _share = RegExp(r'^shr[A-Za-z0-9]{10,}$');
  static final _base = RegExp(r'^app[A-Za-z0-9]{10,}$');
  static final _page = RegExp(r'^pag[A-Za-z0-9]{10,}$');

  @override
  String get id => 'airtable';

  @override
  String get name => 'Airtable';

  @override
  List<String> get keywords => const [
        'airtable',
        'base',
        'table',
        'database',
        'spreadsheet',
        'form',
      ];

  @override
  IconData iconFor(String kind) =>
      kind == 'Form' ? Icons.list_alt_rounded : Icons.table_chart_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF18BFFF);

  @override
  bool ownsHost(String host) => host == 'airtable.com';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'airtable.com' && host != 'www.airtable.com') {
      return null;
    }
    var segments = webEmbedSegments(uri);
    if (segments.isNotEmpty && segments.first == 'embed') {
      segments = segments.sublist(1);
    }
    final path = <String>[];
    var kind = 'Shared view';
    for (final segment in segments) {
      if (_base.hasMatch(segment) || _page.hasMatch(segment)) {
        path.add(segment);
      } else if (_share.hasMatch(segment)) {
        path.add(segment);
        break;
      } else if (segment == 'form' && path.isNotEmpty) {
        path.add(segment);
        kind = 'Form';
        break;
      } else {
        return null;
      }
    }
    if (path.isEmpty || !(path.any(_share.hasMatch) || kind == 'Form')) {
      return null;
    }
    final joined = path.join('/');
    return WebEmbedLink(
      provider: this,
      kind: kind,
      url: 'https://airtable.com/$joined',
      id: path.last,
      embedUrl: 'https://airtable.com/embed/$joined',
      defaultWidth: 800,
      defaultHeight: kind == 'Form' ? 720 : 533,
    );
  }

  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) =>
      WebEmbedPageStyle(stayInFrame: (uri) => ownsHost(uri.host.toLowerCase()));
}

/// Forms and surveys from Typeform, Tally, Jotform and Microsoft Forms,
/// filled in right in their own embed.
class FormEmbeds extends FramedWebEmbedProvider {
  const FormEmbeds();

  static final _jotform = RegExp(r'^\d{12,}$');

  @override
  String get id => 'forms';

  @override
  String get name => 'Forms';

  @override
  List<String> get keywords => const [
        'form',
        'survey',
        'quiz',
        'typeform',
        'tally',
        'jotform',
        'microsoft forms',
      ];

  @override
  IconData iconFor(String kind) => Icons.list_alt_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF5B5BD6);

  @override
  bool ownsHost(String host) =>
      isWebEmbedHost(host, 'typeform.com') ||
      host == 'tally.so' ||
      isWebEmbedHost(host, 'jotform.com') ||
      host == 'forms.office.com' ||
      host == 'forms.cloud.microsoft';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (isWebEmbedHost(host, 'typeform.com')) {
      return segments.length >= 2 && segments.first == 'to'
          ? _form(
              'https://form.typeform.com/to/${segments[1]}',
              'Typeform',
              const Color(0xFF262627),
            )
          : null;
    }
    if (host == 'tally.so') {
      if (segments.length < 2 ||
          (segments.first != 'r' && segments.first != 'embed')) {
        return null;
      }
      final form = segments[1];
      return _form(
        'https://tally.so/r/$form',
        'Tally',
        const Color(0xFF0B7AE0),
        embed: 'https://tally.so/embed/$form'
            '?alignLeft=1&transparentBackground=1',
      );
    }
    if (isWebEmbedHost(host, 'jotform.com')) {
      final form = segments.isEmpty
          ? null
          : _jotform.hasMatch(segments.last)
              ? segments.last
              : null;
      return form == null
          ? null
          : _form(
              'https://form.jotform.com/$form',
              'Jotform',
              const Color(0xFFFF6100),
            );
    }
    if (host == 'forms.office.com' || host == 'forms.cloud.microsoft') {
      final response = uri.queryParameters['id'];
      if (segments.isNotEmpty &&
          segments.last.toLowerCase() == 'responsepage.aspx' &&
          response != null) {
        return _form(
          Uri.https(host, '/Pages/ResponsePage.aspx', {'id': response})
              .toString(),
          'Microsoft Forms',
          const Color(0xFF008272),
          embed: Uri.https(host, '/Pages/ResponsePage.aspx', {
            'id': response,
            'embed': 'true',
          }).toString(),
        );
      }
      // `/r/<code>` leads to the form itself; the frame follows it.
      return segments.length == 2 && segments.first == 'r'
          ? _form(
              'https://$host/r/${segments[1]}',
              'Microsoft Forms',
              const Color(0xFF008272),
            )
          : null;
    }
    return null;
  }

  WebEmbedLink _form(String url, String site, Color accent, {String? embed}) =>
      WebEmbedLink(
        provider: this,
        kind: 'Form',
        siteName: site,
        url: url,
        embedUrl: embed ?? url,
        defaultWidth: 640,
        defaultHeight: 600,
        accent: accent,
      );

  /// A form turns its pages and sends its answers on its own site, so those
  /// stay in the frame.
  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => WebEmbedPageStyle(
        stayInFrame: (uri) {
          final host = uri.host.toLowerCase();
          return ownsHost(host) || host == 'login.microsoftonline.com';
        },
      );
}

/// Repositories, issues, pull requests, code, commits, releases and
/// profiles from GitHub, shown as GitHub's own page, and gists as GitHub's
/// own rendering of their files.
class GitHubEmbeds extends AppPageWebEmbedProvider {
  const GitHubEmbeds();

  static final _owner = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$');
  static final _repository = RegExp(r'^[A-Za-z0-9._-]{1,100}$');
  static final _number = RegExp(r'^\d{1,9}$');
  static final _gist = RegExp(r'^[0-9a-f]{20,40}$');

  /// First segments that are GitHub's own pages rather than an owner.
  static const _reserved = {
    'about',
    'account',
    'apps',
    'codespaces',
    'collections',
    'contact',
    'copilot',
    'customer-stories',
    'dashboard',
    'enterprise',
    'events',
    'explore',
    'features',
    'home',
    'issues',
    'join',
    'login',
    'logout',
    'marketplace',
    'new',
    'notifications',
    'organizations',
    'orgs',
    'pricing',
    'pulls',
    'readme',
    'search',
    'security',
    'sessions',
    'settings',
    'signup',
    'site',
    'sponsors',
    'stars',
    'team',
    'topics',
    'trending',
    'users',
    'watching',
  };

  @override
  String get id => 'github';

  @override
  String get name => 'GitHub';

  @override
  List<String> get keywords => const [
        'github',
        'repository',
        'repo',
        'issue',
        'pull request',
        'pr',
        'code',
        'gist',
        'commit',
        'release',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Issue' || 'Issues' => Icons.adjust_rounded,
        'Pull request' || 'Pull requests' => Icons.merge_rounded,
        'Commit' => Icons.commit_rounded,
        'Code' => Icons.code_rounded,
        'Folder' => Icons.folder_rounded,
        'Release' => Icons.local_offer_rounded,
        'Discussion' => Icons.forum_rounded,
        'Gist' => Icons.integration_instructions_rounded,
        'Profile' => Icons.person_rounded,
        'Wiki' => Icons.menu_book_rounded,
        'Workflow' => Icons.terminal_rounded,
        _ => Icons.source_rounded,
      };

  @override
  Color colorFor(String kind) => switch (kind) {
        'Issue' || 'Issues' => const Color(0xFF1A7F37),
        'Pull request' || 'Pull requests' => const Color(0xFF8250DF),
        _ => const Color(0xFF24292F),
      };

  @override
  bool ownsHost(String host) =>
      host == 'github.com' ||
      host == 'www.github.com' ||
      host == 'gist.github.com';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'gist.github.com') {
      return _gistLink(segments);
    }
    if (host != 'github.com' && host != 'www.github.com') {
      return null;
    }
    // Word, Excel and PowerPoint files read better in Office's viewer.
    if (webEmbedFileExtension(uri) != 'pdf' && isWebEmbedDocument(uri)) {
      return null;
    }
    if (segments.isEmpty ||
        _reserved.contains(segments[0].toLowerCase()) ||
        !_owner.hasMatch(segments[0])) {
      return null;
    }
    final owner = segments[0];
    if (segments.length == 1) {
      return webEmbedPage(
        this,
        'Profile',
        'https://github.com/$owner',
        id: owner,
        title: owner,
        thumbnailUrl: 'https://github.com/$owner.png',
        width: 720,
      );
    }
    final repository = segments[1].endsWith('.git')
        ? segments[1].substring(0, segments[1].length - 4)
        : segments[1];
    if (!_repository.hasMatch(repository)) {
      return null;
    }
    final name = '$owner/$repository';
    final social = 'https://opengraph.githubassets.com/1/$name';
    final path = [owner, repository, ...segments.skip(2)];
    WebEmbedLink page(
      String kind, {
      String? title,
      String? thumbnail,
      bool keepFragment = false,
    }) =>
        webEmbedPage(
          this,
          kind,
          Uri(
            scheme: 'https',
            host: 'github.com',
            path: path.join('/'),
            fragment: keepFragment && uri.hasFragment ? uri.fragment : null,
          ).toString(),
          id: name,
          title: title ?? name,
          thumbnailUrl: thumbnail ?? social,
          width: 720,
        );

    if (segments.length == 2) {
      return page('Repository');
    }
    final section = segments[2];
    final rest = segments.skip(3).toList();
    final number =
        rest.isNotEmpty && _number.hasMatch(rest.first) ? rest.first : null;
    switch (section) {
      case 'issues':
        return number == null
            ? page('Issues', title: '$name issues')
            : page(
                'Issue',
                title: '$name#$number',
                thumbnail: '$social/issues/$number',
              );
      case 'pull':
        return number == null
            ? null
            : page(
                'Pull request',
                title: '$name#$number',
                thumbnail: '$social/pull/$number',
              );
      case 'pulls':
        return page('Pull requests', title: '$name pull requests');
      case 'discussions':
        return page(
          'Discussion',
          title: number == null ? '$name discussions' : '$name#$number',
        );
      case 'commit':
        if (rest.isEmpty) {
          return null;
        }
        final sha = rest.first;
        return page(
          'Commit',
          title: '$name@${sha.length > 7 ? sha.substring(0, 7) : sha}',
          thumbnail: '$social/commit/$sha',
        );
      case 'blob':
        return rest.length < 2
            ? null
            : page('Code', title: rest.last, keepFragment: true);
      case 'tree':
        return page('Folder', title: rest.length >= 2 ? rest.last : name);
      case 'releases':
        return rest.length >= 2 && rest.first == 'tag'
            ? page('Release', title: '$repository ${rest[1]}')
            : page('Release', title: '$name releases');
      case 'wiki':
        return page(
          'Wiki',
          title: rest.isEmpty
              ? '$name wiki'
              : webEmbedTitleFromSlug(rest.last) ?? '$name wiki',
        );
      case 'actions':
        return page('Workflow', title: '$name actions');
    }
    return page('Repository');
  }

  WebEmbedLink? _gistLink(List<String> segments) {
    final id = segments.isEmpty
        ? null
        : segments.length >= 2
            ? segments[1]
            : segments[0];
    if (id == null || !_gist.hasMatch(id)) {
      return null;
    }
    final url = segments.length >= 2
        ? 'https://gist.github.com/${segments[0]}/$id'
        : 'https://gist.github.com/$id';
    return WebEmbedLink(
      provider: this,
      kind: 'Gist',
      url: url,
      id: id,
      // GitHub's own plain rendering of every file in the gist.
      embedUrl: '$url.pibb',
      defaultWidth: 680,
      defaultHeight: 420,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) =>
            _firstPart(title.replaceFirst(RegExp('^GitHub - '), ''), ' · '),
      );
}

/// Projects, issues, merge requests, code, snippets and wikis from GitLab
/// and the GitLab servers that projects run themselves, shown as their page.
class GitLabEmbeds extends AppPageWebEmbedProvider {
  const GitLabEmbeds();

  /// Well-known servers that run GitLab under their own name.
  static const _servers = {
    'framagit.org',
    'invent.kde.org',
    'salsa.debian.org',
    'code.videolan.org',
    'git.drupalcode.org',
  };
  static final _number = RegExp(r'^\d{1,9}$');

  /// First segments that are GitLab's own pages rather than a group.
  static const _reserved = {
    'admin',
    'api',
    'dashboard',
    'explore',
    'help',
    'oauth',
    'profile',
    'search',
    'users',
  };

  @override
  String get id => 'gitlab';

  @override
  String get name => 'GitLab';

  @override
  List<String> get keywords => const [
        'gitlab',
        'repository',
        'repo',
        'merge request',
        'mr',
        'issue',
        'snippet',
        'code',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Issue' || 'Issues' => Icons.adjust_rounded,
        'Merge request' || 'Merge requests' => Icons.merge_rounded,
        'Commit' => Icons.commit_rounded,
        'Code' => Icons.code_rounded,
        'Folder' => Icons.folder_rounded,
        'Snippet' => Icons.integration_instructions_rounded,
        'Wiki' => Icons.menu_book_rounded,
        'Release' => Icons.local_offer_rounded,
        'Pipeline' => Icons.terminal_rounded,
        'Group' => Icons.groups_rounded,
        _ => Icons.source_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFFFC6D26);

  @override
  bool ownsHost(String host) =>
      host == 'gitlab.com' ||
      host == 'www.gitlab.com' ||
      host.startsWith('gitlab.') ||
      _servers.contains(host);

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!ownsHost(host) ||
        (webEmbedFileExtension(uri) != 'pdf' && isWebEmbedDocument(uri))) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    if (segments.isEmpty || _reserved.contains(segments.first)) {
      return null;
    }
    final dash = segments.indexOf('-');
    final project = (dash < 0 ? segments : segments.sublist(0, dash)).join('/');
    final section =
        dash >= 0 && dash + 1 < segments.length ? segments[dash + 1] : null;
    final rest =
        dash >= 0 ? segments.skip(dash + 2).toList() : const <String>[];
    final number =
        rest.isNotEmpty && _number.hasMatch(rest.first) ? rest.first : null;
    final kind = switch (section) {
      null => segments.length == 1 ? 'Group' : 'Repository',
      'issues' || 'work_items' => number == null ? 'Issues' : 'Issue',
      'merge_requests' => number == null ? 'Merge requests' : 'Merge request',
      'blob' => 'Code',
      'tree' => 'Folder',
      'commit' => 'Commit',
      'snippets' => 'Snippet',
      'wikis' => 'Wiki',
      'releases' || 'tags' => 'Release',
      'pipelines' || 'jobs' => 'Pipeline',
      _ => 'Repository',
    };
    final title = switch (kind) {
      'Issue' => '$project#$number',
      'Merge request' => '$project!$number',
      'Code' || 'Folder' when rest.length >= 2 => rest.last,
      _ => project.isEmpty ? null : project,
    };
    return webEmbedPage(
      this,
      kind,
      Uri(
        scheme: 'https',
        host: host,
        path: segments.join('/'),
        fragment: kind == 'Code' && uri.hasFragment ? uri.fragment : null,
      ).toString(),
      id: project.isEmpty ? null : project,
      title: title,
      width: 720,
    );
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) => _firstPart(title, ' · '),
      );
}

/// Live code from CodePen, CodeSandbox, StackBlitz, JSFiddle and Replit,
/// run in each site's own embed.
class CodePlaygroundEmbeds extends FramedWebEmbedProvider {
  const CodePlaygroundEmbeds();

  static final _fiddle = RegExp(r'^[A-Za-z0-9]{4,12}$');
  static final _revision = RegExp(r'^\d{1,4}$');

  /// JSFiddle's own pages rather than a fiddle or its author.
  static const _fiddleReserved = {
    'about',
    'api',
    'blog',
    'docs',
    'login',
    'signup',
    'user',
  };

  @override
  String get id => 'code_playground';

  @override
  String get name => 'Code playground';

  @override
  List<String> get keywords => const [
        'codepen',
        'codesandbox',
        'stackblitz',
        'jsfiddle',
        'replit',
        'code',
        'demo',
        'playground',
        'sandbox',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Sandbox' => Icons.integration_instructions_rounded,
        'Project' || 'Repl' => Icons.terminal_rounded,
        _ => Icons.code_rounded,
      };

  @override
  Color colorFor(String kind) => switch (kind) {
        'Sandbox' => const Color(0xFF0971F1),
        'Project' => const Color(0xFF1389FD),
        'Fiddle' => const Color(0xFF4679A4),
        'Repl' => const Color(0xFFF26207),
        _ => const Color(0xFF47CF73),
      };

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    switch (host) {
      case 'codepen.io':
        // `/<user>/pen/<id>`, and the `embed`, `full` and `details` views.
        if (segments.length < 3 ||
            !const {'pen', 'embed', 'full', 'details', 'pres', 'debug'}
                .contains(segments[1])) {
          return null;
        }
        final user = segments[0];
        final pen = segments[2];
        return _link(
          'Pen',
          'CodePen',
          'https://codepen.io/$user/pen/$pen',
          'https://codepen.io/$user/embed/$pen?default-tab=result',
        );
      case 'codesandbox.io':
        if (segments.length >= 2 &&
            (segments[0] == 's' || segments[0] == 'embed')) {
          return _link(
            'Sandbox',
            'CodeSandbox',
            'https://codesandbox.io/s/${segments[1]}',
            'https://codesandbox.io/embed/${segments[1]}?hidenavigation=1',
          );
        }
        if (segments.length >= 3 && segments[0] == 'p') {
          final url = 'https://codesandbox.io/${segments.join('/')}';
          return _link('Sandbox', 'CodeSandbox', url, '$url?embed=1');
        }
        return null;
      case 'stackblitz.com':
        if (segments.length < 2 ||
            !const {'edit', 'github', '~'}.contains(segments[0])) {
          return null;
        }
        final url = 'https://stackblitz.com/${segments.join('/')}';
        return _link('Project', 'StackBlitz', url, '$url?embed=1');
      case 'jsfiddle.net':
        return _fiddleLink(segments);
      case 'replit.com':
        if (segments.length < 2 || !segments[0].startsWith('@')) {
          return null;
        }
        final url = 'https://replit.com/${segments[0]}/${segments[1]}';
        return _link('Repl', 'Replit', url, '$url?embed=true');
    }
    return null;
  }

  WebEmbedLink? _fiddleLink(List<String> segments) {
    // `/<user>/<id>/<revision>/` or `/<id>/`, with `embedded/…` after.
    final cut = segments.indexOf('embedded');
    final path = cut < 0 ? segments : segments.sublist(0, cut);
    if (path.isEmpty || _fiddleReserved.contains(path.first.toLowerCase())) {
      return null;
    }
    String? user;
    var rest = path;
    if (rest.length >= 2 && !_revision.hasMatch(rest[1])) {
      user = rest.first;
      rest = rest.sublist(1);
    }
    final fiddle = rest.first;
    if (!_fiddle.hasMatch(fiddle) || _revision.hasMatch(fiddle)) {
      return null;
    }
    final revision =
        rest.length >= 2 && _revision.hasMatch(rest[1]) ? '${rest[1]}/' : '';
    final url =
        'https://jsfiddle.net/${user == null ? '' : '$user/'}$fiddle/$revision';
    return _link(
      'Fiddle',
      'JSFiddle',
      url,
      '${url}embedded/result,js,html,css/',
    );
  }

  WebEmbedLink _link(String kind, String site, String url, String embed) =>
      WebEmbedLink(
        provider: this,
        kind: kind,
        siteName: site,
        url: url,
        embedUrl: embed,
        defaultWidth: 800,
      );

  /// Each site's own dark or light editor, to match the workspace.
  @override
  String frameUrlFor(WebEmbedLink link, WebEmbedViewOptions options) {
    final embed = link.embedUrl ?? link.url;
    final dark = options.brightness == Brightness.dark;
    return switch (link.kind) {
      'Pen' => '$embed&theme-id=${dark ? 'dark' : 'light'}',
      'Sandbox' when embed.contains('/embed/') =>
        '$embed&theme=${dark ? 'dark' : 'light'}',
      'Project' => '$embed&theme=${dark ? 'dark' : 'light'}',
      'Fiddle' => '$embed${dark ? 'dark' : 'light'}/',
      _ => embed,
    };
  }
}
