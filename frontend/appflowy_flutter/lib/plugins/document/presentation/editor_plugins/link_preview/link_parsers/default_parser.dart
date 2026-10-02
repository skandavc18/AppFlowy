import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/custom_link_parser.dart';
import 'package:appflowy/shared/markup_parse.dart';
import 'package:appflowy/shared/unusable_page_title.dart';
import 'package:appflowy_backend/log.dart';
// ignore: depend_on_referenced_packages
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';

abstract class LinkInfoParser {
  Future<LinkInfo?> parse(
    Uri link, {
    Duration timeout = const Duration(seconds: 8),
    Map<String, String>? headers,
  });

  static String formatUrl(String url) {
    Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (!uri.hasScheme) uri = Uri.tryParse('http://$url');
    if (uri == null) return url;
    final isHome = (uri.hasEmptyPath || uri.path == '/') && !uri.hasQuery;
    final homeUrl = '${uri.scheme}://${uri.host}/';
    if (isHome) return homeUrl;
    return '$uri';
  }
}

class DefaultParser implements LinkInfoParser {
  @override
  Future<LinkInfo?> parse(
    Uri link, {
    Duration timeout = const Duration(seconds: 8),
    Map<String, String>? headers,
  }) async {
    try {
      final isHome = (link.hasEmptyPath || link.path == '/') && !link.hasQuery;
      final http.Response response =
          await http.get(link, headers: headers).timeout(timeout);
      final code = response.statusCode;
      if (code != 200 && isHome) {
        throw Exception('Http request error: $code');
      }

      final contentType = response.headers['content-type'];
      final charset = contentType?.split('charset=').lastOrNull;
      final bytes = response.bodyBytes;
      final head = bytes.length > _maxReadBytes
          ? Uint8List.sublistView(bytes, 0, _maxReadBytes)
          : bytes;
      String body = '';
      if (charset == null ||
          charset.toLowerCase() == 'latin-1' ||
          charset.toLowerCase() == 'iso-8859-1') {
        body = latin1.decode(head);
      } else {
        body = utf8.decode(head, allowMalformed: true);
      }

      return await readLinkInfo(body, link);
    } catch (e) {
      Log.error('Parse link $link error: $e');
      return null;
    }
  }
}

/// The most of a page that is read: a title and its meta tags sit at the
/// top, and a page can run to megabytes.
const _maxReadBytes = 384 * 1024;

/// [parseLinkInfo], read off the UI isolate when [html] is a whole page.
///
/// Every link mention, preview and embed on a page reads its page as the
/// page opens, so parsing them on the UI isolate stalled loading.
Future<LinkInfo?> readLinkInfo(String html, Uri link) =>
    parseMarkup(html, (html) => parseLinkInfo(html, link));

/// What [html], the page at [link], says about itself, or null when it is a
/// bot check standing in for the page.
LinkInfo? parseLinkInfo(String html, Uri link) {
  final document = html_parser.parse(html);

  final siteName = document
      .querySelector('meta[property="og:site_name"]')
      ?.attributes['content'];

  String? title = document
      .querySelector('meta[property="og:title"]')
      ?.attributes['content'];
  title ??= document.querySelector('title')?.text;
  // A bot check's title, text and picture describe the check.
  if (isStandInPageTitle(title)) {
    return null;
  }

  String? description = document
      .querySelector('meta[property="og:description"]')
      ?.attributes['content'];
  description ??=
      document.querySelector('meta[name="description"]')?.attributes['content'];

  String? imageUrl = document
      .querySelector('meta[property="og:image"]')
      ?.attributes['content'];
  if (imageUrl != null && !imageUrl.startsWith('http')) {
    imageUrl = link.resolve(imageUrl).toString();
  }

  final favicon =
      'https://www.faviconextractor.com/favicon/${link.host}?larger=true';

  return LinkInfo(
    url: '$link',
    siteName: siteName,
    title: title,
    description: description,
    imageUrl: imageUrl,
    faviconUrl: favicon,
  );
}
