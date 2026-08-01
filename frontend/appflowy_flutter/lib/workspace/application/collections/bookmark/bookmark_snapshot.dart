import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/bookmark/readable_article.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  /// The page exactly as it was served.
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
  }) async {
    if (article == null && html == null) {
      return null;
    }
    try {
      final directory = await directoryFor(url);
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
        await file.writeAsString(html, flush: true);
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
          'url': url,
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
    final buffer = StringBuffer();
    final title = article.title?.trim();
    // The article usually opens with its own heading; a second one above it
    // would read as a repeated title.
    if (title != null &&
        title.isNotEmpty &&
        !article.markdown.trimLeft().startsWith('# ')) {
      buffer.writeln('# $title');
      buffer.writeln();
    }
    final byline = article.byline?.trim();
    if (byline != null && byline.isNotEmpty) {
      buffer.writeln('*$byline*');
      buffer.writeln();
    }
    buffer.writeln('[$url]($url)');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.write(article.markdown);
    return buffer.toString();
  }

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
