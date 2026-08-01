import 'dart:convert';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// What a page says about itself.
///
/// Read from OpenGraph, Twitter cards, JSON-LD and the plain document head,
/// in that order of trust — the social tags are what a site maintains for
/// exactly this purpose.
@immutable
class LinkMetadata {
  const LinkMetadata({
    this.title,
    this.description,
    this.siteName,
    this.author,
    this.imageUrl,
    this.faviconUrl,
    this.canonicalUrl,
    this.publishedAt,
    this.keywords = const <String>[],
  });

  final String? title;
  final String? description;
  final String? siteName;
  final String? author;
  final String? imageUrl;
  final String? faviconUrl;
  final String? canonicalUrl;
  final DateTime? publishedAt;

  /// The page's own keywords and article tags, offered as suggested tags.
  final List<String> keywords;

  bool get isEmpty => title == null && description == null && imageUrl == null;
}

/// Reads [html] as the page at [url].
///
/// Pure, so the whole extraction is testable without a network.
LinkMetadata parseLinkMetadata(String html, Uri url) {
  final document = html_parser.parse(html);
  final jsonLd = _readJsonLd(document);

  final canonical = _absolute(
    document.querySelector('link[rel="canonical"]')?.attributes['href'],
    url,
  );

  final title = _firstNonEmpty([
    _meta(document, 'property', 'og:title'),
    _meta(document, 'name', 'twitter:title'),
    _jsonLdString(jsonLd, const ['headline', 'name']),
    document.querySelector('title')?.text,
    document.querySelector('h1')?.text,
  ]);

  final description = _firstNonEmpty([
    _meta(document, 'property', 'og:description'),
    _meta(document, 'name', 'twitter:description'),
    _meta(document, 'name', 'description'),
    _jsonLdString(jsonLd, const ['description']),
  ]);

  final siteName = _firstNonEmpty([
    _meta(document, 'property', 'og:site_name'),
    _meta(document, 'name', 'application-name'),
    _jsonLdPublisher(jsonLd),
    bookmarkHost(url.toString()),
  ]);

  final author = _firstNonEmpty([
    _meta(document, 'name', 'author'),
    _meta(document, 'property', 'article:author'),
    _jsonLdAuthor(jsonLd),
    document.querySelector('[rel="author"]')?.text,
  ]);

  final image = _absolute(
    _firstNonEmpty([
      _meta(document, 'property', 'og:image:secure_url'),
      _meta(document, 'property', 'og:image'),
      _meta(document, 'name', 'twitter:image'),
      _meta(document, 'name', 'twitter:image:src'),
      _jsonLdImage(jsonLd),
    ]),
    url,
  );

  final published = _firstDate([
    _meta(document, 'property', 'article:published_time'),
    _meta(document, 'property', 'og:published_time'),
    _meta(document, 'name', 'date'),
    _meta(document, 'itemprop', 'datePublished'),
    _jsonLdString(jsonLd, const ['datePublished', 'dateCreated']),
    document.querySelector('time[datetime]')?.attributes['datetime'],
  ]);

  return LinkMetadata(
    title: _clean(title),
    description: _clean(description),
    siteName: _clean(siteName),
    author: _clean(author, maxLength: 80),
    imageUrl: image,
    faviconUrl: _favicon(document, url),
    canonicalUrl: canonical,
    publishedAt: published,
    keywords: _keywords(document, jsonLd),
  );
}

/// The site's icon, taken from the page's own declaration.
///
/// Deliberately not a third-party favicon service: a bookmark library should
/// not tell a stranger's server every address someone saves.
String? _favicon(dom.Document document, Uri url) {
  const selectors = [
    'link[rel="apple-touch-icon"]',
    'link[rel="apple-touch-icon-precomposed"]',
    'link[rel="icon"]',
    'link[rel="shortcut icon"]',
    'link[rel="ICON"]',
    'link[rel="mask-icon"]',
  ];
  for (final selector in selectors) {
    for (final element in document.querySelectorAll(selector)) {
      final href = _absolute(element.attributes['href'], url);
      if (href != null) {
        return href;
      }
    }
  }
  return Uri(
    scheme: url.scheme,
    host: url.host,
    port: url.hasPort ? url.port : null,
    path: '/favicon.ico',
  ).toString();
}

List<String> _keywords(
  dom.Document document,
  List<Map<String, dynamic>> jsonLd,
) {
  final raw = <String>[
    ...?_meta(document, 'name', 'keywords')?.split(','),
    for (final element
        in document.querySelectorAll('meta[property="article:tag"]'))
      element.attributes['content'] ?? '',
    ...jsonLd.map((entry) => entry['keywords']).expand<String>(
          (value) => switch (value) {
            final String text => text.split(','),
            final List<dynamic> list => list.whereType<String>(),
            _ => const <String>[],
          },
        ),
  ];

  final tags = <String>[];
  for (final entry in raw) {
    final tag = normalizeBookmarkTag(entry);
    // A keyword list stuffed for search engines is noise, not a tag.
    if (tag != null && tag.length > 1 && !tags.contains(tag)) {
      tags.add(tag);
    }
    if (tags.length >= 8) {
      break;
    }
  }
  return tags;
}

String? _meta(dom.Document document, String attribute, String value) {
  final element = document.querySelector('meta[$attribute="$value"]') ??
      document.querySelector('meta[$attribute="${value.toUpperCase()}"]');
  final content = element?.attributes['content']?.trim();
  return content == null || content.isEmpty ? null : content;
}

List<Map<String, dynamic>> _readJsonLd(dom.Document document) {
  final entries = <Map<String, dynamic>>[];
  for (final script
      in document.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      _collectJsonLd(jsonDecode(script.text), entries);
    } on FormatException {
      // A malformed block is common and never worth failing the read over.
      continue;
    }
  }
  return entries;
}

void _collectJsonLd(Object? value, List<Map<String, dynamic>> out) {
  if (value is List) {
    for (final entry in value) {
      _collectJsonLd(entry, out);
    }
    return;
  }
  if (value is! Map) {
    return;
  }
  final map = Map<String, dynamic>.from(value);
  out.add(map);
  _collectJsonLd(map['@graph'], out);
}

String? _jsonLdString(List<Map<String, dynamic>> entries, List<String> keys) {
  for (final entry in entries) {
    for (final key in keys) {
      final value = entry[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
  }
  return null;
}

String? _jsonLdAuthor(List<Map<String, dynamic>> entries) {
  for (final entry in entries) {
    final author = entry['author'];
    final name = switch (author) {
      final String text => text,
      final Map<dynamic, dynamic> map => map['name'],
      final List<dynamic> list => list.isEmpty
          ? null
          : (list.first is Map ? list.first['name'] : list.first),
      _ => null,
    };
    if (name is String && name.trim().isNotEmpty) {
      return name;
    }
  }
  return null;
}

String? _jsonLdPublisher(List<Map<String, dynamic>> entries) {
  for (final entry in entries) {
    final publisher = entry['publisher'];
    if (publisher is Map && publisher['name'] is String) {
      return publisher['name'] as String;
    }
  }
  return null;
}

String? _jsonLdImage(List<Map<String, dynamic>> entries) {
  for (final entry in entries) {
    final image = entry['image'];
    final url = switch (image) {
      final String text => text,
      final Map<dynamic, dynamic> map => map['url'],
      final List<dynamic> list => list.isEmpty
          ? null
          : (list.first is Map ? list.first['url'] : list.first),
      _ => null,
    };
    if (url is String && url.trim().isNotEmpty) {
      return url;
    }
  }
  return null;
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

DateTime? _firstDate(List<String?> values) {
  for (final value in values) {
    final parsed = parseLinkDate(value);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

/// Reads the date formats publishers actually emit.
DateTime? parseLinkDate(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  final iso = DateTime.tryParse(text);
  if (iso != null) {
    return iso.isUtc ? iso.toLocal() : iso;
  }
  // `2026-08-01 10:30:00` without the separator, and bare `2026/08/01`.
  final numeric = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(text);
  if (numeric != null) {
    return DateTime(
      int.parse(numeric.group(1)!),
      int.parse(numeric.group(2)!),
      int.parse(numeric.group(3)!),
    );
  }
  return null;
}

String? _absolute(String? url, Uri base) {
  final text = url?.trim();
  if (text == null || text.isEmpty || text.startsWith('data:')) {
    return null;
  }
  final resolved =
      text.startsWith('http') ? Uri.tryParse(text) : base.tryResolve(text);
  if (resolved == null || !resolved.hasScheme) {
    return null;
  }
  return resolved.toString();
}

String? _clean(String? value, {int maxLength = 400}) {
  if (value == null) {
    return null;
  }
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) {
    return null;
  }
  return text.length <= maxLength
      ? text
      : '${text.substring(0, maxLength).trimRight()}…';
}

extension on Uri {
  Uri? tryResolve(String reference) {
    try {
      return resolve(reference);
    } on FormatException {
      return null;
    }
  }
}
