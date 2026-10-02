import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/shared/markup_parse.dart';
import 'package:appflowy/shared/unusable_page_title.dart';
import 'package:appflowy/workspace/application/collections/bookmark/link_metadata.dart';
import 'package:appflowy/workspace/application/collections/bookmark/readable_article.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

/// The most of a page that is ever read.
///
/// A bookmark only needs the head and the article; a page that keeps going
/// past this is a stream, an application shell or a mistake.
const maxBookmarkPageBytes = 4 * 1024 * 1024;

/// The most of an illustration that is ever kept offline.
const maxBookmarkImageBytes = 6 * 1024 * 1024;

const _requestTimeout = Duration(seconds: 12);

/// A plain, current browser string.
///
/// Many publishers serve a stub or an error to an unknown agent, so a
/// bookmark that identifies itself honestly gets no metadata at all.
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/// Whether what came back for [url] is a bot check rather than the page.
bool looksLikeChallenge(
  LinkMetadata? metadata,
  int? statusCode, {
  String? url,
}) {
  if (statusCode == 401 ||
      statusCode == 403 ||
      statusCode == 429 ||
      statusCode == 503) {
    return true;
  }
  if (metadata == null) {
    return true;
  }
  final title = metadata.title;
  if (title == null) {
    return metadata.imageUrl == null && metadata.description == null;
  }
  return isUnusablePageTitle(title, url: url);
}

/// Whether [body] styles or gates its text in ways only a browser can tell
/// apart from what is shown.
bool _mayHideProse(String body) =>
    html_parser.parse(body).querySelector(
              'style,link[rel="stylesheet"],[style],'
              '[hidden],[aria-hidden="true"],[aria-modal="true"],dialog',
            ) !=
        null ||
    RegExp(
      'paywall|access-gate|subscription-wall|regwall',
      caseSensitive: false,
    ).hasMatch(body);

/// What one visit to a saved address produced.
@immutable
class BookmarkFetchResult {
  const BookmarkFetchResult({
    required this.url,
    this.metadata,
    this.article,
    this.html,
    this.statusCode,
    this.error,
  });

  const BookmarkFetchResult.failed(this.url, this.error)
      : metadata = null,
        article = null,
        html = null,
        statusCode = null;

  final String url;
  final LinkMetadata? metadata;
  final ReadableArticle? article;

  /// The page as served, kept only when an offline copy was asked for.
  final String? html;

  final int? statusCode;
  final String? error;

  bool get succeeded => metadata != null;
}

/// Reads what a saved address says about itself.
class BookmarkFetcher {
  BookmarkFetcher({http.Client? client, this.browserFallback})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Re-reads a page in a real renderer when the plain read came back as a
  /// bot check. Left unset the fetcher stays pure and offline-testable.
  final Future<String?> Function(Uri uri)? browserFallback;

  /// Visits [url] and reads its metadata, and its article when
  /// [readArticle] is set.
  Future<BookmarkFetchResult> fetch(
    String url, {
    bool readArticle = true,
    bool keepHtml = false,
    bool allowBrowserFallback = true,
    bool readerOnly = false,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return BookmarkFetchResult.failed(url, 'Not a web address');
    }

    try {
      final response = await _read(uri);
      if (response == null) {
        return BookmarkFetchResult.failed(url, 'The page could not be read');
      }
      final (body, statusCode, contentType, resolved) = response;

      if (!_isHtml(contentType)) {
        // A PDF or an image is still worth saving; it just has no markup to
        // read, so the address itself becomes the description.
        return BookmarkFetchResult(
          url: url,
          statusCode: statusCode,
          metadata: LinkMetadata(
            title: _fileNameOf(resolved),
            siteName: resolved.host,
            faviconUrl: resolved
                .replace(path: '/favicon.ico', query: '', fragment: '')
                .toString(),
          ),
        );
      }

      final metadata = await readLinkMetadata(body, resolved);
      final address = resolved.toString();
      if (readerOnly) {
        if (statusCode < 200 ||
            statusCode >= 300 ||
            looksLikeChallenge(metadata, statusCode, url: address)) {
          return BookmarkFetchResult.failed(url, 'Reader unavailable');
        }
        // Without a browser there is no computed visibility. Conservatively
        // refuse styled/gated pages rather than exposing CSS-hidden prose.
        if (await parseMarkup(body, _mayHideProse)) {
          return BookmarkFetchResult.failed(url, 'Reader unavailable');
        }
      }
      if (!readerOnly &&
          allowBrowserFallback &&
          looksLikeChallenge(metadata, statusCode, url: address) &&
          browserFallback != null) {
        final rendered = await browserFallback!(resolved);
        if (rendered != null) {
          final second = await readLinkMetadata(rendered, resolved);
          if (!looksLikeChallenge(second, null, url: address)) {
            return BookmarkFetchResult(
              url: url,
              statusCode: statusCode,
              metadata: second,
              article: readArticle
                  ? await readReadableArticle(rendered, baseUrl: resolved)
                  : null,
              html: keepHtml ? rendered : null,
            );
          }
        }
      }
      // Neither read reached the page: its title, text and picture describe
      // the check the site put in front of it.
      if (isStandInPageTitle(metadata.title)) {
        return BookmarkFetchResult.failed(
          url,
          'The site did not show the page',
        );
      }
      final article = readArticle
          ? await readReadableArticle(body, baseUrl: resolved)
          : null;
      return BookmarkFetchResult(
        url: url,
        statusCode: statusCode,
        metadata: metadata,
        article: article,
        html: keepHtml ? body : null,
      );
    } on TimeoutException {
      return BookmarkFetchResult.failed(
        url,
        'The page took too long to answer',
      );
    } on Object catch (error) {
      return BookmarkFetchResult.failed(url, '$error');
    }
  }

  /// Downloads an illustration, within the size budget.
  Future<Uint8List?> fetchImage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    try {
      final request = http.Request('GET', uri)
        ..headers.addAll({'user-agent': _userAgent})
        ..followRedirects = true
        ..maxRedirects = 5;
      final response = await _client.send(request).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return null;
      }
      final bytes = await _readCapped(response.stream, maxBookmarkImageBytes)
          .timeout(_requestTimeout);
      return bytes.isEmpty ? null : bytes;
    } on Object {
      return null;
    }
  }

  void close() => _client.close();

  Future<(String, int, String?, Uri)?> _read(Uri uri) async {
    final request = http.Request('GET', uri)
      ..headers.addAll({
        'user-agent': _userAgent,
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'accept-language': 'en;q=0.9,*;q=0.5',
      })
      ..followRedirects = true
      ..maxRedirects = 6;

    final response = await _client.send(request).timeout(_requestTimeout);
    final bytes =
        await _readCapped(response.stream, maxBookmarkPageBytes).timeout(
      _requestTimeout,
    );
    final contentType = response.headers['content-type'];
    final resolved = response.request?.url ?? uri;
    return (
      _decode(bytes, contentType),
      response.statusCode,
      contentType,
      resolved
    );
  }

  static Future<Uint8List> _readCapped(
    Stream<List<int>> stream,
    int limit,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length + chunk.length > limit) {
        throw const FormatException('Bookmark response exceeds size budget');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static String _decode(Uint8List bytes, String? contentType) {
    final charset = contentType?.toLowerCase().split('charset=').lastOrNull;
    if (charset != null &&
        (charset.startsWith('latin-1') ||
            charset.startsWith('iso-8859-1') ||
            charset.startsWith('windows-1252'))) {
      return latin1.decode(bytes, allowInvalid: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static bool _isHtml(String? contentType) {
    if (contentType == null) {
      return true;
    }
    final type = contentType.toLowerCase();
    return type.contains('text/html') ||
        type.contains('application/xhtml') ||
        type.contains('text/plain');
  }

  static String? _fileNameOf(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? null : Uri.decodeComponent(segments.last);
  }
}
