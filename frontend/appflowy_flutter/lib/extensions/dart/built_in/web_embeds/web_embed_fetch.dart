import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/collections/bookmark/link_metadata.dart';

/// What a desktop browser says it is. Sites answer a bare client with an error
/// page or a challenge, so embeds ask the way a browser would.
const webEmbedDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// What a phone browser says it is, for sites whose phone page is the one
/// that reads well in a narrow frame.
const webEmbedMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36';

const _timeout = Duration(seconds: 10);
const _maxTextBytes = 2 * 1024 * 1024;
const _maxHeadBytes = 384 * 1024;

/// Where a short link leads.
///
/// Redirects are followed one at a time so each hop can be looked at: it
/// stops at the first address [stopAt] accepts, before the site gets a chance
/// to answer a client it does not like with a challenge page. Null when
/// nothing answered.
Future<Uri?> followWebEmbedRedirects(
  Uri start, {
  bool Function(Uri uri)? stopAt,
  String userAgent = webEmbedDesktopUserAgent,
  int maxHops = 8,
}) async {
  final client = _client(userAgent);
  try {
    var current = start;
    for (var hop = 0; hop <= maxHops; hop++) {
      if (hop > 0 && (stopAt?.call(current) ?? false)) {
        return current;
      }
      final request = await client.getUrl(current).timeout(_timeout);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptHeader, _htmlAccept)
        ..headers.set(HttpHeaders.acceptLanguageHeader, _language);
      final response = await request.close().timeout(_timeout);
      final location = response.headers.value(HttpHeaders.locationHeader);
      // The body is never needed; closing the client drops it.
      if (!response.isRedirect || location == null || location.isEmpty) {
        return response.statusCode < 400 ? current : null;
      }
      current = current.resolve(location);
    }
    return (stopAt?.call(current) ?? true) ? current : null;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// [uri]'s body as text, or null on any failure, a non-200 answer or a body
/// too large to be what was asked for.
///
/// With [headOnly] a large page is cut short instead of refused: a title and
/// its meta tags sit at the top, and an editor's page can run to megabytes.
Future<String?> fetchWebEmbedText(
  Uri uri, {
  String userAgent = webEmbedDesktopUserAgent,
  String accept = _htmlAccept,
  bool headOnly = false,
}) async {
  final client = _client(userAgent);
  try {
    final request = await client.getUrl(uri).timeout(_timeout);
    request
      ..followRedirects = true
      ..maxRedirects = 5
      ..headers.set(HttpHeaders.acceptHeader, accept)
      ..headers.set(HttpHeaders.acceptLanguageHeader, _language);
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) {
      return null;
    }
    final limit = headOnly ? _maxHeadBytes : _maxTextBytes;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(_timeout)) {
      bytes.add(chunk);
      if (bytes.length > limit) {
        if (!headOnly) {
          return null;
        }
        break;
      }
    }
    final charset = response.headers.contentType?.charset?.toLowerCase();
    final body = bytes.takeBytes();
    return charset == 'iso-8859-1' || charset == 'latin1'
        ? latin1.decode(body, allowInvalid: true)
        : utf8.decode(body, allowMalformed: true);
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// [uri]'s answer read as a JSON object, the shape every oEmbed endpoint
/// replies in.
Future<Map<String, dynamic>?> fetchWebEmbedJson(
  Uri uri, {
  String userAgent = webEmbedDesktopUserAgent,
}) async {
  final text = await fetchWebEmbedText(
    uri,
    userAgent: userAgent,
    accept: 'application/json, text/javascript;q=0.9, */*;q=0.5',
  );
  if (text == null) {
    return null;
  }
  try {
    final value = jsonDecode(text);
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

/// The page at [uri] read the way a bookmark reads it.
Future<LinkMetadata?> fetchWebEmbedPageMetadata(
  Uri uri, {
  String userAgent = webEmbedDesktopUserAgent,
}) async {
  final html =
      await fetchWebEmbedText(uri, userAgent: userAgent, headOnly: true);
  return html == null ? null : readLinkMetadata(html, uri);
}

/// A string field of an oEmbed answer, when it holds something.
String? webEmbedField(Map<String, dynamic>? json, String key) {
  final value = json?[key];
  if (value is! String) {
    return null;
  }
  final text = value.trim();
  return text.isEmpty ? null : text;
}

/// A number field of an oEmbed answer, which some sites send as a string.
double? webEmbedNumber(Map<String, dynamic>? json, String key) {
  final value = json?[key];
  if (value is num) {
    return value.toDouble();
  }
  return value is String ? double.tryParse(value) : null;
}

/// [uri]'s body saved as [target], or false on any failure, a non-200
/// answer, a body larger than [maxBytes] or one [validate] refuses by its
/// first kilobyte.
///
/// The body is written beside [target] and moved into place only once it is
/// whole, so a cut-off download is never mistaken for the file.
Future<bool> downloadWebEmbedFile(
  Uri uri,
  File target, {
  required int maxBytes,
  String accept = '*/*',
  bool Function(List<int> head)? validate,
  String userAgent = webEmbedDesktopUserAgent,
}) async {
  final client = _client(userAgent);
  final partial =
      File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.part');
  IOSink? sink;
  try {
    final request = await client.getUrl(uri).timeout(_timeout);
    request
      ..followRedirects = true
      ..maxRedirects = 5
      ..headers.set(HttpHeaders.acceptHeader, accept)
      ..headers.set(HttpHeaders.acceptLanguageHeader, _language);
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > maxBytes) {
      return false;
    }
    await partial.parent.create(recursive: true);
    final output = partial.openWrite();
    sink = output;
    final head = <int>[];
    var total = 0;
    // Each wait is bounded, so a stalled server ends the download.
    await for (final chunk in response.timeout(_timeout)) {
      total += chunk.length;
      if (total > maxBytes) {
        return false;
      }
      if (head.length < 1024) {
        head.addAll(chunk.take(1024 - head.length));
      }
      output.add(chunk);
    }
    sink = null;
    await output.close();
    if (total == 0 || (validate != null && !validate(head))) {
      return false;
    }
    if (target.existsSync()) {
      target.deleteSync();
    }
    await partial.rename(target.path);
    return true;
  } on Object {
    return false;
  } finally {
    try {
      await sink?.close();
    } on Object {
      // The download already failed; its partial file goes next.
    }
    try {
      if (partial.existsSync()) {
        partial.deleteSync();
      }
    } on Object {
      // A temporary file left behind is cleared with the cache.
    }
    client.close(force: true);
  }
}

const _htmlAccept =
    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
const _language = 'en;q=0.9,*;q=0.5';

HttpClient _client(String userAgent) => HttpClient()
  ..connectionTimeout = _timeout
  ..idleTimeout = const Duration(seconds: 2)
  ..userAgent = userAgent;
