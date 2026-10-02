import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/unusable_page_title.dart';
import 'package:flutter/material.dart';

import 'web_embed_fetch.dart';
import 'web_embed_site_base.dart';

/// Places, directions and My Maps, shown as Google's own embedded map.
class GoogleMapsEmbeds extends FramedWebEmbedProvider {
  const GoogleMapsEmbeds();

  static final _googleHost =
      RegExp(r'^(?:www\.)?google\.[a-z]{2,3}(?:\.[a-z]{2})?$');
  static final _mapsHost = RegExp(r'^maps\.google\.[a-z]{2,3}(?:\.[a-z]{2})?$');

  /// The pin a place link is about, which is not the `@` centre of the view.
  static final _pin =
      RegExp(r'!3d(-?\d{1,3}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)');
  static final _centre = RegExp(
    r'^@(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)(?:,(\d{1,2}(?:\.\d+)?)z)?',
  );
  static final _travelMode = RegExp(r'!3e(\d)');
  static const _tracking = {'entry', 'g_ep', 'g_st', 'shorturl'};

  @override
  String get id => 'google_maps';

  @override
  String get name => 'Google Maps';

  @override
  List<String> get keywords => const [
        'google maps',
        'maps',
        'map',
        'location',
        'place',
        'address',
        'directions',
        'route',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Directions' => Icons.directions_rounded,
        'Map' => Icons.map_rounded,
        _ => Icons.place_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF34A853);

  @override
  bool ownsHost(String host) =>
      _googleHost.hasMatch(host) ||
      _mapsHost.hasMatch(host) ||
      host == 'maps.app.goo.gl';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if ((host == 'maps.app.goo.gl' && segments.length == 1) ||
        (host == 'goo.gl' && segments.length == 2 && segments[0] == 'maps')) {
      return _link(
        'Place',
        Uri.https(host, '/${segments.join('/')}').toString(),
        needsResolution: true,
      );
    }

    List<String> rest;
    if (_googleHost.hasMatch(host)) {
      if (segments.isEmpty || segments.first != 'maps') {
        return null;
      }
      rest = segments.sublist(1);
    } else if (_mapsHost.hasMatch(host)) {
      rest = segments.isNotEmpty && segments.first == 'maps'
          ? segments.sublist(1)
          : segments;
    } else {
      return null;
    }

    final url = withoutWebEmbedTracking(uri.replace(scheme: 'https'), _tracking)
        .toString();
    if (rest.isNotEmpty && rest.first == 'embed') {
      // Already an embed, from Google's own "Embed a map".
      return _link('Place', url, embed: url);
    }
    if (rest.isNotEmpty && rest.first == 'd') {
      final mid = uri.queryParameters['mid'];
      if (mid == null || mid.isEmpty) {
        return null;
      }
      return _link(
        'Map',
        url,
        embed: Uri.https('www.google.com', '/maps/d/embed', {'mid': mid})
            .toString(),
      );
    }
    return _directions(uri, rest, url) ?? _place(uri, rest, url);
  }

  WebEmbedLink? _directions(Uri uri, List<String> rest, String url) {
    final query = uri.queryParameters;
    String? origin;
    String? destination;
    if (rest.isNotEmpty && rest.first == 'dir') {
      if (query['api'] == '1') {
        origin = query['origin'];
        destination = query['destination'];
      } else {
        // An empty stop is the reader's own location, so empty segments keep
        // their place; only the one a trailing slash leaves is dropped.
        final raw = uri.pathSegments;
        final stops = [
          for (final segment in raw.skip(raw.indexOf('dir') + 1))
            if (!segment.startsWith('@') &&
                !segment.startsWith('data=') &&
                !segment.startsWith('am='))
              segment.replaceAll('+', ' ').trim(),
        ];
        if (stops.isNotEmpty && stops.last.isEmpty) {
          stops.removeLast();
        }
        if (stops.isEmpty) {
          return null;
        }
        origin = stops.length > 1 ? stops.first : null;
        destination = stops.last;
      }
    } else if (query.containsKey('daddr')) {
      origin = query['saddr'];
      destination = query['daddr'];
    } else {
      return null;
    }

    origin = origin?.trim();
    destination = destination?.trim();
    if (destination == null || destination.isEmpty) {
      return null;
    }
    final from = origin == null || origin.isEmpty ? null : origin;
    final mode = _travelModeOf(uri);
    return _link(
      'Directions',
      url,
      embed: Uri.https('www.google.com', '/maps', {
        if (from != null) 'saddr': from,
        'daddr': destination,
        if (mode != null) 'dirflg': mode,
        'output': 'embed',
      }).toString(),
      title:
          from == null ? 'Directions to $destination' : '$from to $destination',
    );
  }

  WebEmbedLink? _place(Uri uri, List<String> rest, String url) {
    final query = uri.queryParameters;
    String? name;
    for (final marker in const ['place', 'search']) {
      final at = rest.indexOf(marker);
      if (at >= 0 && at + 1 < rest.length && !rest[at + 1].startsWith('@')) {
        name = rest[at + 1];
        break;
      }
    }
    name ??= query['query'] ?? query['q'];
    name = name?.replaceAll('+', ' ').trim();

    var pin = _pinOf(uri.path);
    if (name != null && name.isNotEmpty) {
      // `?q=48.85,2.29` names a point, not a place.
      final point = parseMapLocation(name).point;
      if (point != null && !name.contains(RegExp('[A-Za-z]{2}'))) {
        pin ??= point;
        name = null;
      }
    } else {
      name = null;
    }

    LatLng? centre;
    double? zoom;
    for (final segment in rest) {
      final match = _centre.firstMatch(segment);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);
        if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
          centre = LatLng(lat, lng);
        }
        zoom = double.tryParse(match.group(3) ?? '');
        break;
      }
    }
    final ll = query['ll'] ?? query['center'];
    if (centre == null && ll != null) {
      centre = parseMapLocation(ll).point;
    }
    zoom ??= double.tryParse(query['z'] ?? query['zoom'] ?? '');
    final z = (zoom ?? 15).round().clamp(1, 21);

    final q = name ?? (pin == null ? null : _coordinates(pin));
    final near = pin ?? centre;
    if (q == null && near == null) {
      return null;
    }
    return _link(
      q == null ? 'Map' : 'Place',
      url,
      embed: Uri.https('www.google.com', '/maps', {
        if (q != null) 'q': q,
        if (near != null) 'll': '${near.latitude},${near.longitude}',
        'z': '$z',
        'output': 'embed',
      }).toString(),
      title: name ?? (pin == null ? null : _coordinates(pin)),
    );
  }

  static LatLng? _pinOf(String path) {
    final match = _pin.firstMatch(path);
    if (match == null) {
      return null;
    }
    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    return LatLng(lat, lng);
  }

  static String _coordinates(LatLng point) =>
      '${point.latitude.toStringAsFixed(5)}, '
      '${point.longitude.toStringAsFixed(5)}';

  /// The legacy embed's `dirflg`, from either kind of directions link.
  static String? _travelModeOf(Uri uri) {
    final named =
        uri.queryParameters['travelmode'] ?? uri.queryParameters['dirflg'];
    switch (named) {
      case 'driving' || 'd':
        return 'd';
      case 'walking' || 'w':
        return 'w';
      case 'bicycling' || 'b':
        return 'b';
      case 'transit' || 'r':
        return 'r';
    }
    return switch (_travelMode.firstMatch(uri.path)?.group(1)) {
      '0' => 'd',
      '1' => 'b',
      '2' => 'w',
      '3' => 'r',
      _ => null,
    };
  }

  WebEmbedLink _link(
    String kind,
    String url, {
    String? embed,
    String? title,
    bool needsResolution = false,
  }) =>
      WebEmbedLink(
        provider: this,
        kind: kind,
        url: url,
        embedUrl: embed,
        title: title,
        defaultWidth: 640,
        defaultHeight: 420,
        needsResolution: needsResolution,
      );

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) async {
    final target = await followWebEmbedRedirects(
      Uri.parse(link.url),
      stopAt: (uri) => _landing(uri) != null,
    );
    // Offline, or Google would not say: its own page still follows the link.
    return (target == null ? null : _landing(target)) ??
        webEmbedAsFullPage(link);
  }

  /// What a short link has arrived at, looking through Google's consent page
  /// to the address it continues to.
  WebEmbedLink? _landing(Uri uri) {
    var target = uri;
    if (target.host.toLowerCase() == 'consent.google.com') {
      final next = Uri.tryParse(target.queryParameters['continue'] ?? '');
      if (next == null) {
        return null;
      }
      target = next;
    }
    final found = recognize(target);
    return found == null || found.needsResolution ? null : found;
  }
}

/// Docs, Sheets, Slides and Forms, plus Drive files and folders, shown as
/// Google's own read-only preview.
class GoogleWorkspaceEmbeds extends FramedWebEmbedProvider {
  const GoogleWorkspaceEmbeds();

  static const _products = {
    'document': ('Document', 'Google Docs', 680.0, 720.0),
    'spreadsheets': ('Spreadsheet', 'Google Sheets', 720.0, 480.0),
    'presentation': ('Presentation', 'Google Slides', 640.0, 389.0),
    'forms': ('Form', 'Google Forms', 640.0, 720.0),
  };
  static final _fileId = RegExp(r'^[A-Za-z0-9_-]{15,}$');
  static final _gid = RegExp(r'gid=(\d+)');
  static final _productSuffix =
      RegExp(r'\s+[-–—]\s+Google (?:Docs|Sheets|Slides|Drive|Forms)$');
  static const _tracking = {'usp', 'ouid', 'rtpof', 'sd'};

  @override
  bool ownsHost(String host) =>
      host == 'docs.google.com' ||
      host == 'drive.google.com' ||
      host == 'forms.gle';

  /// A form sends its answers and turns its pages by loading Google's own
  /// addresses, so those stay in the frame; any other click leaves for the
  /// browser.
  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) =>
      link.kind == 'Form' || isWebEmbedFullPage(link)
          ? WebEmbedPageStyle(
              stayInFrame: (uri) => ownsHost(uri.host.toLowerCase()),
            )
          : const WebEmbedPageStyle();

  @override
  String get id => 'google_workspace';

  @override
  String get name => 'Google Workspace';

  @override
  List<String> get keywords => const [
        'google docs',
        'google sheets',
        'google slides',
        'google forms',
        'google drive',
        'docs',
        'sheets',
        'slides',
        'forms',
        'drive',
        'document',
        'spreadsheet',
        'presentation',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Document' => Icons.description_rounded,
        'Spreadsheet' => Icons.table_chart_rounded,
        'Presentation' => Icons.slideshow_rounded,
        'Form' => Icons.list_alt_rounded,
        'Folder' => Icons.folder_rounded,
        _ => Icons.insert_drive_file_rounded,
      };

  @override
  Color colorFor(String kind) => switch (kind) {
        'Document' => const Color(0xFF4285F4),
        'Spreadsheet' => const Color(0xFF0F9D58),
        'Presentation' => const Color(0xFFF4B400),
        'Form' => const Color(0xFF7248B9),
        _ => const Color(0xFF1FA463),
      };

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'forms.gle') {
      final segments = webEmbedSegments(uri);
      if (segments.length != 1) {
        return null;
      }
      return WebEmbedLink(
        provider: this,
        kind: 'Form',
        siteName: 'Google Forms',
        url: 'https://forms.gle/${segments.first}',
        defaultWidth: 640,
        defaultHeight: 720,
        needsResolution: true,
      );
    }
    if (host != 'docs.google.com' && host != 'drive.google.com') {
      return null;
    }
    final segments = _withoutAccount(webEmbedSegments(uri));
    final url = withoutWebEmbedTracking(uri.replace(scheme: 'https'), _tracking)
        .toString();
    return host == 'docs.google.com'
        ? _file(uri, segments, url)
        : _drive(uri, segments, url);
  }

  /// [segments] without the `a/<domain>` and `u/<n>` that say which account
  /// was signed in, which is no part of what the link points at.
  static List<String> _withoutAccount(List<String> segments) {
    final kept = <String>[];
    for (var i = 0; i < segments.length; i++) {
      if (i == 0 && segments[0] == 'a' && segments.length > 1) {
        i++;
        continue;
      }
      if (segments[i] == 'u' &&
          i + 1 < segments.length &&
          int.tryParse(segments[i + 1]) != null) {
        i++;
        continue;
      }
      kept.add(segments[i]);
    }
    return kept;
  }

  WebEmbedLink? _file(Uri uri, List<String> segments, String url) {
    if (segments.length < 3 || segments[1] != 'd') {
      return null;
    }
    final type = segments[0];
    // `docs.google.com/file/d/<id>`, from before Drive had its own address.
    if (type == 'file') {
      return _drive(uri, segments, url);
    }
    final product = _products[type];
    if (product == null) {
      return null;
    }
    // `d/e/<id>` is a copy published to the web, readable by anyone.
    final published = segments[2] == 'e';
    final id =
        published ? (segments.length > 3 ? segments[3] : null) : segments[2];
    if (id == null || !_fileId.hasMatch(id)) {
      return null;
    }
    final base = 'https://docs.google.com/$type/d/${published ? 'e/' : ''}$id';
    final gid =
        uri.queryParameters['gid'] ?? _gid.firstMatch(uri.fragment)?.group(1);
    final embed = switch (type) {
      'document' => published ? '$base/pub?embedded=true' : '$base/preview',
      'spreadsheets' => published
          ? '$base/pubhtml?widget=true&headers=false'
              '${gid == null ? '' : '&gid=$gid&single=true'}'
          : '$base/preview${gid == null ? '' : '?gid=$gid#gid=$gid'}',
      'presentation' => '$base/embed?start=false&loop=false&delayms=3000',
      _ => '$base/viewform?embedded=true',
    };
    final (kind, site, width, height) = product;
    return WebEmbedLink(
      provider: this,
      kind: kind,
      siteName: site,
      url: url,
      id: id,
      embedUrl: embed,
      thumbnailUrl: published ? null : _thumbnail(id),
      defaultWidth: width,
      defaultHeight: height,
    );
  }

  WebEmbedLink? _drive(Uri uri, List<String> segments, String url) {
    String? id;
    var folder = false;
    if (segments.length >= 3 && segments[0] == 'file' && segments[1] == 'd') {
      id = segments[2];
    } else if (segments.isNotEmpty &&
        (segments[0] == 'open' || segments[0] == 'uc')) {
      id = uri.queryParameters['id'];
    } else if (segments.isNotEmpty &&
        (segments[0] == 'embeddedfolderview' || segments[0] == 'folderview')) {
      id = uri.queryParameters['id'];
      folder = true;
    } else {
      final at = segments.indexOf('folders');
      if (at >= 0 && at + 1 < segments.length) {
        id = segments[at + 1];
        folder = true;
      }
    }
    if (id == null || !_fileId.hasMatch(id)) {
      return null;
    }
    return WebEmbedLink(
      provider: this,
      kind: folder ? 'Folder' : 'File',
      siteName: 'Google Drive',
      url: url,
      id: id,
      embedUrl: folder
          ? 'https://drive.google.com/embeddedfolderview?id=$id#grid'
          : 'https://drive.google.com/file/d/$id/preview',
      thumbnailUrl: folder ? null : _thumbnail(id),
      defaultWidth: 640,
      defaultHeight: folder ? 420 : 480,
    );
  }

  static String _thumbnail(String id) =>
      'https://drive.google.com/thumbnail?id=$id&sz=w640';

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) async {
    final target = await followWebEmbedRedirects(
      Uri.parse(link.url),
      stopAt: (uri) => recognize(uri)?.needsResolution == false,
    );
    final found = target == null ? null : recognize(target);
    // Offline, or Google would not say: the form's own page follows the link.
    return found == null || found.needsResolution
        ? webEmbedAsFullPage(link)
        : found;
  }

  /// The file's own title, which Google only tells when the file is shared
  /// beyond its owner; anything else answers with a sign-in page.
  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) async {
    final metadata = await fetchWebEmbedPageMetadata(Uri.parse(link.url));
    final title = tidyGoogleFileTitle(metadata?.title);
    if (metadata == null || title == null) {
      return null;
    }
    return WebEmbedDetails(
      title: title,
      description: metadata.description,
      thumbnailUrl: metadata.imageUrl ?? link.thumbnailUrl,
    );
  }

  /// [title] without Google's " - Google Docs", or null for a sign-in page
  /// or a bot check.
  static String? tidyGoogleFileTitle(String? title) {
    if (title == null || isStandInPageTitle(title)) {
      return null;
    }
    final lower = title.toLowerCase();
    if (lower.contains('sign-in') ||
        lower.contains('sign in') ||
        lower.startsWith('meet google drive') ||
        lower == 'google docs' ||
        lower == 'google sheets' ||
        lower == 'google slides' ||
        lower == 'google drive' ||
        lower == 'google forms') {
      return null;
    }
    final tidy = title.replaceFirst(_productSuffix, '').trim();
    return tidy.isEmpty ? null : tidy;
  }
}

/// Word, Excel and PowerPoint files from OneDrive, SharePoint or any public
/// address, shown in Office for the web's viewer.
class MicrosoftOfficeEmbeds extends FramedWebEmbedProvider {
  const MicrosoftOfficeEmbeds();

  static const _extensions = {
    'doc': 'Document',
    'docx': 'Document',
    'docm': 'Document',
    'dot': 'Document',
    'dotx': 'Document',
    'dotm': 'Document',
    'xls': 'Workbook',
    'xlsx': 'Workbook',
    'xlsm': 'Workbook',
    'xlsb': 'Workbook',
    'ppt': 'Presentation',
    'pptx': 'Presentation',
    'pptm': 'Presentation',
    'pps': 'Presentation',
    'ppsx': 'Presentation',
    'potx': 'Presentation',
  };

  /// The `/:w:/` a SharePoint sharing link starts with.
  static const _markers = {
    ':w:': 'Document',
    ':x:': 'Workbook',
    ':p:': 'Presentation',
  };

  /// The `1drv.ms/w/…` a OneDrive short link starts with.
  static const _shortKinds = {
    'w': 'Document',
    'x': 'Workbook',
    'p': 'Presentation',
  };
  static const _apps = {
    'word': 'Document',
    'excel': 'Workbook',
    'powerpoint': 'Presentation',
  };

  /// Office for the web's own pages, which embed with `action=embedview`.
  static const _viewerPages = {
    'doc.aspx',
    'doc2.aspx',
    'wopiframe.aspx',
    'wopiframe2.aspx',
    'xlviewer.aspx',
  };

  @override
  String get id => 'microsoft_office';

  @override
  String get name => 'Microsoft Office';

  @override
  List<String> get keywords => const [
        'word',
        'excel',
        'powerpoint',
        'office',
        'microsoft',
        'onedrive',
        'sharepoint',
        'docx',
        'xlsx',
        'pptx',
        'document',
        'spreadsheet',
        'presentation',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Workbook' => Icons.grid_on_rounded,
        'Presentation' => Icons.co_present_rounded,
        _ => Icons.article_rounded,
      };

  @override
  Color colorFor(String kind) => switch (kind) {
        'Workbook' => const Color(0xFF107C41),
        'Presentation' => const Color(0xFFC43E1C),
        _ => const Color(0xFF185ABD),
      };

  @override
  bool ownsHost(String host) =>
      host == '1drv.ms' ||
      isWebEmbedHost(host, 'sharepoint.com') ||
      isWebEmbedHost(host, 'onedrive.live.com') ||
      isWebEmbedHost(host, 'officeapps.live.com') ||
      isWebEmbedHost(host, 'office.com') ||
      isWebEmbedHost(host, 'microsoft365.com') ||
      isWebEmbedHost(host, 'cloud.microsoft');

  @override
  WebEmbedLink? recognize(Uri uri) => _recognize(uri);

  /// [kindHint] is what a short link said the file was, for the addresses
  /// along its redirects that no longer say.
  WebEmbedLink? _recognize(Uri uri, {String? kindHint}) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    final query = uri.queryParameters;

    if (host == '1drv.ms') {
      final kind = segments.length >= 2 ? _shortKinds[segments.first] : null;
      if (kind == null) {
        return null;
      }
      // The `e=` query is part of the share, so it stays.
      return _link(kind, uri.replace(scheme: 'https').toString())
          .copyWith(needsResolution: true);
    }

    if (host == 'view.officeapps.live.com') {
      final src = query['src'];
      final kind = src == null ? null : _kindOfFile(_nameInAddress(src));
      if (src == null || kind == null) {
        return null;
      }
      return _link(
        kind,
        Uri.https(host, '/op/view.aspx', {'src': src}).toString(),
        embed: Uri.https(host, '/op/embed.aspx', {'src': src}).toString(),
        title: _stem(_nameInAddress(src)),
      );
    }

    final sharePoint = isWebEmbedHost(host, 'sharepoint.com');
    final oneDrive = host == 'onedrive.live.com';
    if (sharePoint || oneDrive) {
      final clean = withoutWebEmbedTracking(uri.replace(scheme: 'https'));
      final marker = segments.isEmpty ? null : _markers[segments.first];
      final page = segments.isEmpty ? '' : segments.last.toLowerCase();
      if (marker != null || _viewerPages.contains(page)) {
        final file = query['file'];
        final kind = marker ??
            (file == null ? null : _kindOfFile(file)) ??
            _kindOfApp(query) ??
            kindHint ??
            'Document';
        return _link(
          kind,
          clean.toString(),
          embed: clean.replace(
            queryParameters: {...clean.queryParameters, 'action': 'embedview'},
          ).toString(),
          title: file == null ? null : _stem(file),
        );
      }
      if (oneDrive) {
        final resid = query['resid'];
        // Word's embed code is the one that says nothing: Excel's and
        // PowerPoint's carry their own options.
        final kind = _kindOfApp(query) ??
            kindHint ??
            (page == 'embed' ? 'Document' : null);
        if (resid == null || resid.isEmpty || kind == null) {
          return null;
        }
        return _link(
          kind,
          clean.toString(),
          embed: Uri.https('onedrive.live.com', '/embed', {
            'resid': resid,
            if (query['authkey'] != null) 'authkey': query['authkey']!,
            if (query['redeem'] != null) 'redeem': query['redeem']!,
            'em': '2',
          }).toString(),
        );
      }
      // A file straight out of a library opens in Office for the web with
      // `web=1`, after the reader has signed in.
      final kind = segments.isEmpty ? null : _kindOfFile(segments.last);
      if (kind == null) {
        return null;
      }
      return webEmbedAsFullPage(
        _link(kind, clean.toString(), title: _stem(segments.last)),
        url: clean.replace(
          queryParameters: {...clean.queryParameters, 'web': '1'},
        ).toString(),
      );
    }

    // Any other public file opens in Office's own viewer. The address is kept
    // whole: a signed download link breaks without its query.
    final kind = segments.isEmpty ? null : _kindOfFile(segments.last);
    if (kind == null) {
      return null;
    }
    return _link(
      kind,
      uri.toString(),
      embed: Uri.https('view.officeapps.live.com', '/op/embed.aspx', {
        'src': _fileAddress(uri, host),
      }).toString(),
      title: _stem(segments.last),
    );
  }

  WebEmbedLink _link(String kind, String url, {String? embed, String? title}) =>
      WebEmbedLink(
        provider: this,
        kind: kind,
        siteName: switch (kind) {
          'Workbook' => 'Excel',
          'Presentation' => 'PowerPoint',
          _ => 'Word',
        },
        url: url,
        embedUrl: embed,
        title: title,
        defaultWidth: switch (kind) {
          'Workbook' => 720,
          'Presentation' => 640,
          _ => 680,
        },
        defaultHeight: switch (kind) {
          'Workbook' => 480,
          'Presentation' => 400,
          _ => 720,
        },
      );

  /// Where the file itself is: Dropbox and GitHub share a page about it
  /// unless asked for the file.
  static String _fileAddress(Uri uri, String host) {
    if (isWebEmbedHost(host, 'dropbox.com')) {
      return uri.replace(
        queryParameters: {...uri.queryParameters, 'dl': '1'},
      ).toString();
    }
    if (host == 'github.com' && uri.pathSegments.contains('blob')) {
      return uri.replace(
        queryParameters: {...uri.queryParameters, 'raw': 'true'},
      ).toString();
    }
    return uri.toString();
  }

  static String? _kindOfFile(String? name) {
    if (name == null) {
      return null;
    }
    final dot = name.lastIndexOf('.');
    return dot < 0 ? null : _extensions[name.substring(dot + 1).toLowerCase()];
  }

  static String? _kindOfApp(Map<String, String> query) {
    final app = query['app']?.toLowerCase();
    if (app != null && _apps.containsKey(app)) {
      return _apps[app];
    }
    // `ithint=file,docx`
    final hint = query['ithint']?.toLowerCase();
    final hinted =
        hint == null ? null : _extensions[hint.split(',').last.trim()];
    if (hinted != null) {
      return hinted;
    }
    // An embed code only says it through the app's own options.
    if (query.containsKey('wdAr')) {
      return 'Presentation';
    }
    if (query.containsKey('wdAllowInteractivity') ||
        query.containsKey('wdHideGridlines') ||
        query.containsKey('ActiveCell')) {
      return 'Workbook';
    }
    return query.containsKey('wdStartOn') ? 'Document' : null;
  }

  /// The file name at the end of an address given as a parameter.
  static String? _nameInAddress(String address) {
    final segments = Uri.tryParse(address)?.pathSegments ?? const [];
    for (final segment in segments.reversed) {
      if (segment.isNotEmpty) {
        return segment;
      }
    }
    return null;
  }

  static String? _stem(String? name) {
    if (name == null) {
      return null;
    }
    final dot = name.lastIndexOf('.');
    final stem = (dot > 0 ? name.substring(0, dot) : name).trim();
    return stem.isEmpty ? null : stem;
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) async {
    final target = await followWebEmbedRedirects(
      Uri.parse(link.url),
      stopAt: (uri) =>
          _recognize(uri, kindHint: link.kind)?.needsResolution == false,
    );
    final found =
        target == null ? null : _recognize(target, kindHint: link.kind);
    if (found != null && !found.needsResolution) {
      return found;
    }
    // Microsoft sends some clients to a sign-in before saying where a link
    // goes. The frame shares the reader's sign-in, so it gets there itself.
    return webEmbedAsFullPage(link);
  }

  /// Office for the web lays itself out for the window it is in; a phone's
  /// page would only offer to open the app.
  @override
  WebEmbedPageStyle styleFor(WebEmbedLink link) => isWebEmbedFullPage(link)
      ? WebEmbedPageStyle(
          stayInFrame: (uri) => ownsHost(uri.host.toLowerCase()),
        )
      : const WebEmbedPageStyle();
}
