import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_article_document.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_fetcher.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/collections/bookmark/readable_article.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:markdown/markdown.dart' as markdown;

/// An offline copy of a saved page.
@immutable
class BookmarkSnapshot {
  const BookmarkSnapshot({
    required this.directory,
    required this.savedAt,
    required this.bytes,
    this.articlePath,
    this.pagePath,
    this.heroPath,
  });

  final String directory;
  final DateTime savedAt;
  final int bytes;

  /// The readable article, as Markdown, so the application's own document
  /// viewer renders it.
  final String? articlePath;

  /// Passive archival markup, never the original executable website.
  final String? pagePath;

  final String? heroPath;

  bool get hasArticle => articlePath != null;
}

/// Keeps offline copies of saved pages on disk.
///
/// The snapshot is a small directory per bookmark rather than one blob, so a
/// reader can open the article without decoding anything else.
class BookmarkSnapshotStore {
  BookmarkSnapshotStore({this.rootOverride});

  static final BookmarkSnapshotStore instance = BookmarkSnapshotStore();

  static const folderName = 'bookmark_snapshots';
  static const articleFileName = 'article.md';
  static const pageFileName = 'page.html';
  static const metaFileName = 'snapshot.json';

  /// Set in tests, where the application directories do not exist.
  @visibleForTesting
  final String? rootOverride;

  String? _root;

  Future<String> resolveRoot() async {
    final override = rootOverride;
    if (override != null) {
      return override;
    }
    final cached = _root;
    if (cached != null) {
      return cached;
    }
    String base;
    try {
      base = await getIt<ApplicationDataStorage>().getPath();
    } on Object {
      // A snapshot is worth keeping even without the workspace directory.
      base = (await getTemporaryDirectory()).path;
    }
    return _root = p.join(base, folderName);
  }

  /// The directory a page is kept in, named by its address so the same link
  /// saved twice reuses one copy.
  Future<Directory> directoryFor(String url) async {
    final root = await resolveRoot();
    final key = sha1.convert(utf8.encode(url)).toString().substring(0, 24);
    return Directory(p.join(root, key));
  }

  /// Writes an offline copy and returns what was kept.
  Future<BookmarkSnapshot?> save({
    required String url,
    ReadableArticle? article,
    String? html,
    Uint8List? heroBytes,
    String heroExtension = 'jpg',
    bool isolated = false,
  }) async {
    if (article == null && html == null) {
      return null;
    }
    if ((html != null && utf8.encode(html).length > maxBookmarkPageBytes) ||
        (article != null &&
            utf8.encode(article.markdown).length > maxBookmarkPageBytes) ||
        (heroBytes != null && heroBytes.length > maxBookmarkImageBytes) ||
        !RegExp(r'^[a-zA-Z0-9]{1,5}$').hasMatch(heroExtension)) {
      return null;
    }
    try {
      final Directory directory;
      if (isolated) {
        final root = Directory(await resolveRoot());
        await root.create(recursive: true);
        directory = await root.createTemp('reader-');
      } else {
        directory = await directoryFor(url);
      }
      await directory.create(recursive: true);

      String? articlePath;
      if (article != null && article.markdown.trim().isNotEmpty) {
        final file = File(p.join(directory.path, articleFileName));
        await file.writeAsString(_articleDocument(article, url), flush: true);
        articlePath = file.path;
      }

      String? pagePath;
      if (html != null && html.trim().isNotEmpty) {
        final file = File(p.join(directory.path, pageFileName));
        await file.writeAsString(passiveBookmarkHtml(html), flush: true);
        pagePath = file.path;
      }

      String? heroPath;
      if (heroBytes != null && heroBytes.isNotEmpty) {
        final file = File(p.join(directory.path, 'hero.$heroExtension'));
        await file.writeAsBytes(heroBytes, flush: true);
        heroPath = file.path;
      }

      final savedAt = DateTime.now();
      final bytes = await _sizeOf(directory);
      await File(p.join(directory.path, metaFileName)).writeAsString(
        jsonEncode({
          'url': bookmarkPublicSource(url),
          'saved_at': savedAt.millisecondsSinceEpoch,
          'words': article?.wordCount ?? 0,
        }),
      );

      return BookmarkSnapshot(
        directory: directory.path,
        savedAt: savedAt,
        bytes: bytes,
        articlePath: articlePath,
        pagePath: pagePath,
        heroPath: heroPath,
      );
    } on Object {
      return null;
    }
  }

  /// Reads a snapshot back, or null when it is gone from disk.
  Future<BookmarkSnapshot?> read(String? directoryPath) async {
    try {
      return await _read(directoryPath).timeout(bookmarkReaderDeadline);
    } on Object {
      return null;
    }
  }

  Future<BookmarkSnapshot?> _read(String? directoryPath) async {
    if (directoryPath == null || directoryPath.isEmpty) {
      return null;
    }
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return null;
    }
    final article = File(p.join(directoryPath, articleFileName));
    final page = File(p.join(directoryPath, pageFileName));
    final hero = directory
        .listSync()
        .whereType<File>()
        .firstWhereOrNull((file) => p.basename(file.path).startsWith('hero.'));

    var savedAt = DateTime.fromMillisecondsSinceEpoch(0);
    final meta = File(p.join(directoryPath, metaFileName));
    if (meta.existsSync()) {
      if (await meta.length() > 64 * 1024) return null;
      final value = jsonDecode(await meta.readAsString());
      if (value is Map && value['saved_at'] is int) {
        savedAt = DateTime.fromMillisecondsSinceEpoch(value['saved_at'] as int);
      }
    }

    return BookmarkSnapshot(
      directory: directoryPath,
      savedAt: savedAt,
      bytes: await _sizeOf(directory),
      articlePath: article.existsSync() ? article.path : null,
      pagePath: page.existsSync() ? page.path : null,
      heroPath: hero?.path,
    );
  }

  /// Bounded local read, including legacy snapshots; never opens a browser.
  Future<String?> readArticleText(BookmarkSnapshot snapshot) async {
    final path = snapshot.articlePath;
    if (path == null) return null;
    try {
      final bytes = BytesBuilder(copy: false);
      await File(path).openRead().forEach((chunk) {
        if (bytes.length + chunk.length > maxBookmarkPageBytes) {
          throw const FormatException('Offline article exceeds size budget');
        }
        bytes.add(chunk);
      }).timeout(bookmarkReaderDeadline);
      return bookmarkArticleText(utf8.decode(bytes.takeBytes()));
    } on Object {
      return null;
    }
  }

  Future<void> delete(String? directoryPath) async {
    if (directoryPath == null || directoryPath.isEmpty) {
      return;
    }
    final directory = Directory(directoryPath);
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }

  /// The Markdown document written to disk: a title and source line above the
  /// article, so the offline copy stands on its own.
  static String _articleDocument(ReadableArticle article, String url) {
    // Lower through the same parser after removing active/remote markup.
    // Reader captures are already passive; this also protects HTTP snapshots.
    final safe = parseReadableArticle(
      passiveBookmarkHtml(markdown.markdownToHtml(article.markdown)),
    );
    final buffer = StringBuffer();
    final title = article.title?.trim();
    // The article usually opens with its own heading; a second one above it
    // would read as a repeated title.
    if (title != null &&
        title.isNotEmpty &&
        !safe.markdown.trimLeft().startsWith('# ')) {
      buffer.writeln('# ${_escapeMetadata(title)}');
      buffer.writeln();
    }
    final byline = article.byline?.trim();
    if (byline != null && byline.isNotEmpty) {
      buffer.writeln('*${_escapeMetadata(byline)}*');
      buffer.writeln();
    }
    buffer.writeln(bookmarkPublicSource(url));
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.write(safe.markdown);
    return buffer.toString();
  }

  static String _escapeMetadata(String value) => value
      .replaceAll(RegExp(r'[\r\n]'), ' ')
      .replaceAllMapped(RegExp(r'([\\`*_\[\]<>])'), (m) => '\\${m[1]}');

  static Future<int> _sizeOf(Directory directory) async {
    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}

extension on Iterable<File> {
  File? firstWhereOrNull(bool Function(File) test) {
    for (final file in this) {
      if (test(file)) {
        return file;
      }
    }
    return null;
  }
}
