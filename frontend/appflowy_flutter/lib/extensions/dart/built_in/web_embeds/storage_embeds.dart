import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:flutter/material.dart';

import 'document_embeds.dart';
import 'web_embed_fetch.dart';
import 'web_embed_site_base.dart';

/// [fragment] decoded, or as it is when it is not valid percent-encoding.
String _decoded(String fragment) {
  try {
    return Uri.decodeComponent(fragment);
  } on ArgumentError {
    return fragment;
  } on FormatException {
    return fragment;
  }
}

/// Shared files and folders, and Paper docs, from Dropbox, shown as its own
/// preview page. Word, Excel and PowerPoint files are left to Office's viewer,
/// which reads them better.
class DropboxEmbeds extends AppPageWebEmbedProvider {
  const DropboxEmbeds();

  /// The parts of a shared link's query that are the share itself.
  static const _kept = {'rlkey', 'st', 'dl', 'e'};

  @override
  String get id => 'dropbox';

  @override
  String get name => 'Dropbox';

  @override
  List<String> get keywords => const [
        'dropbox',
        'file',
        'folder',
        'shared link',
        'paper',
        'transfer',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Folder' => Icons.folder_rounded,
        'Transfer' => Icons.send_rounded,
        'Paper doc' => Icons.description_rounded,
        _ => Icons.insert_drive_file_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF0061FE);

  @override
  bool ownsHost(String host) =>
      isWebEmbedHost(host, 'dropbox.com') || host == 'db.tt';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'db.tt') {
      return segments.length == 1
          ? WebEmbedLink(
              provider: this,
              kind: 'File',
              url: 'https://db.tt/${segments.first}',
              defaultWidth: 640,
              needsResolution: true,
            )
          : null;
    }
    if (host == 'paper.dropbox.com') {
      return segments.length >= 2 && segments.first == 'doc'
          ? webEmbedPage(
              this,
              'Paper doc',
              webEmbedBareAddress(uri),
              title: webEmbedTitleFromSlug(segments[1].split('--').first),
              width: 680,
              height: 720,
            )
          : null;
    }
    if ((host != 'dropbox.com' && host != 'www.dropbox.com') ||
        segments.isEmpty) {
      return null;
    }
    final extension = webEmbedFileExtension(uri);
    if (extension != 'pdf' && isWebEmbedDocument(uri)) {
      return null;
    }
    final kind = switch (segments.first) {
      'scl' when segments.length >= 3 => switch (segments[1]) {
          'fi' => 'File',
          'fo' => 'Folder',
          _ => null,
        },
      's' when segments.length >= 2 => 'File',
      'sh' when segments.length >= 2 => 'Folder',
      't' when segments.length >= 2 => 'Transfer',
      _ => null,
    };
    if (kind == null) {
      return null;
    }
    final kept = {
      for (final entry in uri.queryParameters.entries)
        if (_kept.contains(entry.key)) entry.key: entry.value,
    };
    // `/scl/fi/<id>/<name>` and `/s/<id>/<name>` end with the file's name.
    final named =
        kind == 'File' && segments.length >= (segments.first == 'scl' ? 4 : 3);
    return webEmbedPage(
      this,
      kind,
      Uri(
        scheme: 'https',
        host: 'www.dropbox.com',
        path: uri.path,
        queryParameters: kept.isEmpty ? null : kept,
      ).toString(),
      title: named ? segments.last : null,
      width: 640,
      height: 480,
    );
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) =>
            title.replaceFirst(RegExp(r'\s+[-|]\s+Dropbox(?: Paper)?$'), ''),
      );
}

/// Shared links from Box, shown in Box's own embedded file and folder
/// viewer, and its file, folder and Box Notes pages whole.
class BoxEmbeds extends AppPageWebEmbedProvider {
  const BoxEmbeds();

  /// Box's own sites, which are not anyone's files.
  static const _excluded = {
    'account.box.com',
    'blog.box.com',
    'community.box.com',
    'developer.box.com',
    'status.box.com',
    'support.box.com',
  };
  static final _shared = RegExp(r'^[A-Za-z0-9]{10,}$');

  @override
  String get id => 'box';

  @override
  String get name => 'Box';

  @override
  List<String> get keywords => const [
        'box',
        'box.com',
        'file',
        'folder',
        'shared link',
        'box notes',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Folder' => Icons.folder_rounded,
        'File' => Icons.insert_drive_file_rounded,
        'Box Note' => Icons.sticky_note_2_rounded,
        _ => Icons.link_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF0061D5);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'box.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    var host = uri.host.toLowerCase();
    if (!isWebEmbedHost(host, 'box.com') || _excluded.contains(host)) {
      return null;
    }
    if (host == 'box.com' || host == 'www.box.com') {
      host = 'app.box.com';
    }
    var segments = webEmbedSegments(uri);
    // The viewer inside an embed code: `/embed/s/<share>`.
    if (segments.isNotEmpty &&
        (segments.first == 'embed' || segments.first == 'embed_widget')) {
      segments = segments.sublist(1);
    }
    if (segments.length < 2) {
      return null;
    }
    final item = segments[1];
    switch (segments.first) {
      case 's':
        if (!_shared.hasMatch(item)) {
          return null;
        }
        return WebEmbedLink(
          provider: this,
          kind: 'Shared link',
          url: 'https://$host/s/$item',
          id: item,
          embedUrl: 'https://$host/embed/s/$item?view=list',
          defaultWidth: 640,
        );
      case 'v':
        return webEmbedPage(this, 'Shared link', 'https://$host/v/$item');
      case 'file':
        return webEmbedPage(this, 'File', 'https://$host/file/$item');
      case 'folder':
        return webEmbedPage(this, 'Folder', 'https://$host/folder/$item');
      case 'notes':
        return webEmbedPage(this, 'Box Note', 'https://$host/notes/$item');
    }
    return null;
  }

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) =>
            title.replaceFirst(RegExp(r'\s+[-|]\s+Box$'), '').trim(),
      );
}

/// Files from MEGA, played and previewed in MEGA's own embed, and folders as
/// its page. The decryption key after `#` is part of the share and is kept.
class MegaEmbeds extends AppPageWebEmbedProvider {
  const MegaEmbeds();

  static const _hosts = {
    'mega.nz',
    'www.mega.nz',
    'mega.co.nz',
    'www.mega.co.nz',
    'mega.io',
    'www.mega.io',
  };
  static final _id = RegExp(r'^[A-Za-z0-9_-]{6,}$');

  @override
  String get id => 'mega';

  @override
  String get name => 'MEGA';

  @override
  List<String> get keywords =>
      const ['mega', 'mega.nz', 'file', 'folder', 'cloud storage'];

  @override
  IconData iconFor(String kind) =>
      kind == 'Folder' ? Icons.folder_rounded : Icons.insert_drive_file_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFFD9272E);

  @override
  bool ownsHost(String host) => _hosts.contains(host);

  @override
  WebEmbedLink? recognize(Uri uri) {
    if (!_hosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    final segments = webEmbedSegments(uri);
    final fragment = uri.hasFragment ? uri.fragment : '';
    if (segments.isEmpty) {
      // `#!<id>!<key>` and `#F!<id>!<key>`, from before the addresses changed.
      final parts = fragment.split('!');
      if (parts.length < 2 || (parts[0] != '' && parts[0] != 'F')) {
        return null;
      }
      final key = parts.length >= 3 ? parts[2] : '';
      return parts[0] == 'F' ? _folder(parts[1], key) : _file(parts[1], key);
    }
    if (segments.length < 2) {
      return null;
    }
    return switch (segments.first) {
      'file' || 'embed' => _file(segments[1], fragment),
      'folder' => _folder(segments[1], fragment),
      _ => null,
    };
  }

  WebEmbedLink? _file(String id, String key) {
    if (!_id.hasMatch(id)) {
      return null;
    }
    final share = key.isEmpty ? '' : '#$key';
    return WebEmbedLink(
      provider: this,
      kind: 'File',
      url: 'https://mega.nz/file/$id$share',
      id: id,
      embedUrl: 'https://mega.nz/embed/$id$share',
      defaultWidth: 640,
      defaultHeight: 360,
    );
  }

  WebEmbedLink? _folder(String id, String key) {
    if (!_id.hasMatch(id)) {
      return null;
    }
    return webEmbedPage(
      this,
      'Folder',
      'https://mega.nz/folder/$id${key.isEmpty ? '' : '#$key'}',
      id: id,
      width: 720,
      height: 520,
    );
  }
}

/// Folders, photos, videos and other files from OneDrive and SharePoint,
/// shown as their own page. Word, Excel and PowerPoint files, which Office's
/// viewer shows, are recognised before this.
class OneDriveEmbeds extends AppPageWebEmbedProvider {
  const OneDriveEmbeds();

  /// The `1drv.ms/f/…` a OneDrive short link starts with.
  static const _shortKinds = {
    'f': 'Folder',
    'i': 'Photo',
    'v': 'Video',
    'u': 'File',
    'b': 'File',
    't': 'File',
    'o': 'Notebook',
  };

  /// The `/:f:/` a SharePoint sharing link starts with.
  static const _markers = {
    ':f:': 'Folder',
    ':i:': 'Photo',
    ':v:': 'Video',
    ':u:': 'File',
    ':b:': 'File',
    ':t:': 'File',
    ':o:': 'Notebook',
  };

  @override
  String get id => 'onedrive';

  @override
  String get name => 'OneDrive';

  @override
  List<String> get keywords => const [
        'onedrive',
        'one drive',
        'sharepoint',
        'microsoft',
        'folder',
        'file',
        'photo',
        'onenote',
        'shared link',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Folder' => Icons.folder_rounded,
        'Photo' => Icons.image_rounded,
        'Video' => Icons.movie_rounded,
        'Notebook' => Icons.book_rounded,
        _ => Icons.insert_drive_file_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF0078D4);

  @override
  bool ownsHost(String host) =>
      const MicrosoftOfficeEmbeds().ownsHost(host) ||
      isWebEmbedHost(host, 'onedrive.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == '1drv.ms') {
      final kind = segments.length >= 2 ? _shortKinds[segments.first] : null;
      return kind == null
          ? null
          : WebEmbedLink(
              provider: this,
              kind: kind,
              url: uri.replace(scheme: 'https').toString(),
              defaultWidth: 720,
              defaultHeight: 520,
              needsResolution: true,
            );
    }
    final clean = withoutWebEmbedTracking(uri.replace(scheme: 'https'));
    if (isWebEmbedHost(host, 'sharepoint.com')) {
      final kind = segments.isEmpty ? null : _markers[segments.first];
      return kind == null
          ? null
          : webEmbedPage(
              this,
              kind,
              clean.toString(),
              siteName: 'SharePoint',
              width: 720,
              height: 520,
            );
    }
    if (host == 'onedrive.live.com' || isWebEmbedHost(host, 'onedrive.com')) {
      final query = uri.queryParameters;
      final shared = query.containsKey('id') ||
          query.containsKey('resid') ||
          query.containsKey('cid') ||
          segments.contains('redir');
      if (!shared || const MicrosoftOfficeEmbeds().recognize(uri) != null) {
        return null;
      }
      return webEmbedPage(
        this,
        segments.contains('photos') ? 'Photo' : 'File',
        clean.toString(),
        width: 720,
        height: 520,
      );
    }
    return null;
  }

  /// A short link may lead to a Word, Excel or PowerPoint file after all,
  /// which Office's viewer then shows; anything else shows as its page.
  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) async {
    const office = MicrosoftOfficeEmbeds();
    final target = await followWebEmbedRedirects(
      Uri.parse(link.url),
      stopAt: (uri) => office.recognize(uri)?.needsResolution == false,
    );
    final file = target == null ? null : office.recognize(target);
    if (file != null && !file.needsResolution) {
      return file;
    }
    // Microsoft sends some clients to a sign-in first; the frame shares the
    // reader's sign-in, so it follows the link itself.
    return webEmbedAsFullPage(link);
  }
}

/// Shared iCloud Drive files, Notes, Pages, Numbers, Keynote, Freeform and
/// Reminders, and shared photo albums, shown as iCloud's own page.
class ICloudEmbeds extends AppPageWebEmbedProvider {
  const ICloudEmbeds();

  static const _apps = {
    'iclouddrive': ('File', 'iCloud Drive'),
    'attachment': ('File', 'Mail Drop'),
    'notes': ('Note', 'Apple Notes'),
    'pages': ('Document', 'Pages'),
    'numbers': ('Spreadsheet', 'Numbers'),
    'keynote': ('Presentation', 'Keynote'),
    'keynote-live': ('Presentation', 'Keynote'),
    'freeform': ('Board', 'Freeform'),
    'reminders': ('List', 'Reminders'),
    'sharedalbum': ('Album', 'iCloud Photos'),
    'photos': ('Photos', 'iCloud Photos'),
  };

  @override
  String get id => 'icloud';

  @override
  String get name => 'iCloud';

  @override
  List<String> get keywords => const [
        'icloud',
        'apple',
        'icloud drive',
        'apple notes',
        'notes',
        'pages',
        'numbers',
        'keynote',
        'freeform',
        'shared album',
        'photos',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Album' || 'Photos' => Icons.photo_library_rounded,
        'Note' => Icons.sticky_note_2_rounded,
        'Document' => Icons.description_rounded,
        'Spreadsheet' => Icons.table_chart_rounded,
        'Presentation' => Icons.slideshow_rounded,
        'Board' => Icons.dashboard_customize_rounded,
        'List' => Icons.checklist_rounded,
        _ => Icons.cloud_rounded,
      };

  @override
  Color colorFor(String kind) => switch (kind) {
        'Note' => const Color(0xFFE6B800),
        'Document' => const Color(0xFFFF9500),
        'Spreadsheet' => const Color(0xFF34C759),
        'Presentation' => const Color(0xFF0A84FF),
        'Board' => const Color(0xFF32ADE6),
        'List' => const Color(0xFFFF9F0A),
        'Album' || 'Photos' => const Color(0xFFFF2D55),
        _ => const Color(0xFF3693F3),
      };

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'icloud.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'share.icloud.com') {
      return segments.length >= 2 && segments.first == 'photos'
          ? webEmbedPage(
              this,
              'Photos',
              'https://share.icloud.com/${segments.join('/')}',
              siteName: 'iCloud Photos',
              width: 720,
            )
          : null;
    }
    if ((host != 'icloud.com' && host != 'www.icloud.com') ||
        segments.isEmpty) {
      return null;
    }
    final app = _apps[segments.first];
    // A share is its id after the app, or for an album, after the `#`.
    if (app == null || (segments.length < 2 && !uri.hasFragment)) {
      return null;
    }
    final (kind, site) = app;
    final photos = kind == 'Album' || kind == 'Photos';
    // `notes/0abc…#Groceries`: what follows the `#` names the item.
    final named = photos || !uri.hasFragment
        ? null
        : _decoded(uri.fragment).replaceAll('_', ' ').trim();
    return webEmbedPage(
      this,
      kind,
      Uri(
        scheme: 'https',
        host: 'www.icloud.com',
        path: uri.path,
        fragment: uri.hasFragment ? uri.fragment : null,
      ).toString(),
      siteName: site,
      title: named == null || named.isEmpty ? null : named,
      width: 720,
    );
  }
}

/// Shared files and transfers from JioCloud, shown as JioCloud's own page.
class JioCloudEmbeds extends AppPageWebEmbedProvider {
  const JioCloudEmbeds();

  @override
  String get id => 'jiocloud';

  @override
  String get name => 'JioCloud';

  @override
  List<String> get keywords => const [
        'jiocloud',
        'jio cloud',
        'jio',
        'file',
        'shared link',
        'transfer',
      ];

  @override
  IconData iconFor(String kind) =>
      kind == 'Transfer' ? Icons.send_rounded : Icons.cloud_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF0F3CC9);

  @override
  bool ownsHost(String host) => isWebEmbedHost(host, 'jiocloud.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    final token = uri.queryParameters['t'];
    if (!isWebEmbedHost(host, 'jiocloud.com') ||
        segments.isEmpty ||
        segments.first != 's' ||
        token == null ||
        token.isEmpty) {
      return null;
    }
    final transfer = host == 'transfer.jiocloud.com';
    final share = uri.queryParameters['s'];
    return webEmbedPage(
      this,
      transfer ? 'Transfer' : 'Shared file',
      Uri.https(
        transfer ? 'transfer.jiocloud.com' : 'www.jiocloud.com',
        '/s/',
        {'t': token, if (share != null) 's': share},
      ).toString(),
      id: token,
      width: 640,
      height: 560,
    );
  }
}

/// Shared albums and photos from Google Photos, shown as its phone page.
class GooglePhotosEmbeds extends FramedWebEmbedProvider {
  const GooglePhotosEmbeds();

  @override
  String get id => 'google_photos';

  @override
  String get name => 'Google Photos';

  @override
  List<String> get keywords => const [
        'google photos',
        'photos',
        'album',
        'shared album',
        'pictures',
      ];

  @override
  IconData iconFor(String kind) =>
      kind == 'Photo' ? Icons.image_rounded : Icons.photo_library_rounded;

  @override
  Color colorFor(String kind) => const Color(0xFF1A73E8);

  @override
  bool ownsHost(String host) =>
      host == 'photos.google.com' || host == 'photos.app.goo.gl';

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    var segments = webEmbedSegments(uri);
    if (host == 'photos.app.goo.gl') {
      return segments.length == 1
          ? WebEmbedLink(
              provider: this,
              kind: 'Album',
              url: 'https://photos.app.goo.gl/${segments.first}',
              defaultHeight: 640,
              needsResolution: true,
            )
          : null;
    }
    if (host != 'photos.google.com') {
      return null;
    }
    // `u/1/…` only says which account was signed in.
    if (segments.length >= 2 &&
        segments[0] == 'u' &&
        int.tryParse(segments[1]) != null) {
      segments = segments.sublist(2);
    }
    if (segments.length < 2 ||
        !const {'share', 'album', 'photo'}.contains(segments.first)) {
      return null;
    }
    final key = uri.queryParameters['key'];
    return webEmbedPage(
      this,
      segments.contains('photo') ? 'Photo' : 'Album',
      Uri.https(
        'photos.google.com',
        segments.join('/'),
        key == null ? null : {'key': key},
      ).toString(),
      id: segments[1],
    );
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);

  @override
  Future<WebEmbedDetails?> fetchDetails(WebEmbedLink link) =>
      fetchWebEmbedPageDetails(
        link,
        tidyTitle: (title) =>
            title.replaceFirst(RegExp(r'\s+[-–]\s+Google Photos$'), '').trim(),
      );
}

/// Downloads shared through WeTransfer, TeraBox, MediaFire and pCloud, shown
/// as the service's own page, which offers the files.
class FileTransferEmbeds extends AppPageWebEmbedProvider {
  const FileTransferEmbeds();

  static const _teraBox = {
    'terabox.com',
    '1024terabox.com',
    'teraboxapp.com',
    'terabox.app',
    'teraboxlink.com',
    'freeterabox.com',
  };

  @override
  String get id => 'file_transfer';

  @override
  String get name => 'File sharing';

  @override
  List<String> get keywords => const [
        'wetransfer',
        'terabox',
        'mediafire',
        'pcloud',
        'transfer',
        'download',
        'file',
        'shared link',
      ];

  @override
  IconData iconFor(String kind) => switch (kind) {
        'Folder' => Icons.folder_rounded,
        'Transfer' => Icons.send_rounded,
        'Shared link' => Icons.link_rounded,
        _ => Icons.insert_drive_file_rounded,
      };

  @override
  Color colorFor(String kind) => const Color(0xFF409FFF);

  @override
  bool ownsHost(String host) =>
      host == 'we.tl' ||
      isWebEmbedHost(host, 'wetransfer.com') ||
      isWebEmbedHostOf(host, _teraBox) ||
      isWebEmbedHost(host, 'mediafire.com') ||
      isWebEmbedHost(host, 'pcloud.link') ||
      isWebEmbedHost(host, 'pcloud.com');

  @override
  WebEmbedLink? recognize(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = webEmbedSegments(uri);
    if (host == 'we.tl') {
      return segments.length == 1
          ? WebEmbedLink(
              provider: this,
              kind: 'Transfer',
              siteName: 'WeTransfer',
              url: 'https://we.tl/${segments.first}',
              defaultWidth: 640,
              defaultHeight: 560,
              needsResolution: true,
              accent: const Color(0xFF409FFF),
            )
          : null;
    }
    if (isWebEmbedHost(host, 'wetransfer.com')) {
      return segments.length >= 3 && segments.first == 'downloads'
          ? webEmbedPage(
              this,
              'Transfer',
              webEmbedBareAddress(uri),
              siteName: 'WeTransfer',
              width: 640,
              height: 560,
              accent: const Color(0xFF409FFF),
            )
          : null;
    }
    if (isWebEmbedHostOf(host, _teraBox)) {
      final code = segments.length >= 2 && segments.first == 's'
          ? segments[1]
          : segments.length >= 2 && segments[0] == 'sharing'
              ? uri.queryParameters['surl']
              : null;
      return code == null || code.isEmpty
          ? null
          : webEmbedPage(
              this,
              'Shared file',
              'https://www.terabox.com/s/$code',
              siteName: 'TeraBox',
              id: code,
              accent: const Color(0xFF3B6BF5),
            );
    }
    if (isWebEmbedHost(host, 'mediafire.com')) {
      if (segments.length < 2 ||
          (segments.first != 'file' && segments.first != 'folder')) {
        return null;
      }
      final folder = segments.first == 'folder';
      // `/file/<key>/<name>/file`
      return webEmbedPage(
        this,
        folder ? 'Folder' : 'File',
        webEmbedBareAddress(uri),
        siteName: 'MediaFire',
        id: segments[1],
        title: !folder && segments.length >= 3 ? segments[2] : null,
        accent: const Color(0xFF1299F3),
      );
    }
    if (isWebEmbedHost(host, 'pcloud.link') ||
        isWebEmbedHost(host, 'pcloud.com')) {
      final code = uri.queryParameters['code'];
      return segments.contains('publink') && code != null && code.isNotEmpty
          ? webEmbedPage(
              this,
              'Shared link',
              Uri.https(host, segments.join('/'), {'code': code}).toString(),
              siteName: 'pCloud',
              id: code,
              accent: const Color(0xFF17BED0),
            )
          : null;
    }
    return null;
  }

  @override
  Future<WebEmbedLink?> resolve(WebEmbedLink link) =>
      followWebEmbedShortLink(this, link);
}
