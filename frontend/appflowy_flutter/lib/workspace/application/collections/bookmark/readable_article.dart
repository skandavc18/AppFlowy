import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The readable part of a web page, lowered to Markdown.
///
/// Markdown is deliberate: an offline copy is then rendered by the
/// application's own markdown viewer, so a saved article reads in the same
/// type as every other document instead of needing a second renderer.
@immutable
class ReadableArticle {
  const ReadableArticle({
    required this.markdown,
    required this.plainText,
    required this.wordCount,
    this.title,
    this.byline,
    this.leadImageUrl,
  });

  final String markdown;
  final String plainText;
  final int wordCount;
  final String? title;
  final String? byline;
  final String? leadImageUrl;

  bool get isEmpty => wordCount == 0;

  /// The opening of the article, for a card that has no description.
  String? excerpt({int maxLength = 260}) {
    final text = plainText.trim();
    if (text.isEmpty) {
      return null;
    }
    if (text.length <= maxLength) {
      return text;
    }
    final cut = text.lastIndexOf(' ', maxLength);
    return '${text.substring(0, cut > 40 ? cut : maxLength).trimRight()}…';
  }
}

/// Elements that are never part of what someone came to read.
const _strippedTags = <String>{
  'script',
  'style',
  'noscript',
  'template',
  'iframe',
  'object',
  'embed',
  'form',
  'button',
  'input',
  'select',
  'textarea',
  'svg',
  'canvas',
  'nav',
  'aside',
  'footer',
  'dialog',
};

/// Words in a class or id that mark furniture rather than content.
final _furniturePattern = RegExp(
  r'(^|[\s_-])('
  'ad|ads|advert|advertisement|banner|breadcrumb|byline|comment|comments|'
  'cookie|disqus|footer|header|hidden|masthead|menu|modal|nav|navbar|newsletter|'
  'paywall|popup|promo|related|share|sharing|sidebar|signup|social|sponsor|'
  'subscribe|toolbar|widget'
  r')([\s_-]|$)',
  caseSensitive: false,
);

/// Words that mark the element someone actually came for.
final _contentPattern = RegExp(
  r'(^|[\s_-])(article|body|content|entry|main|markdown|post|prose|story|text)'
  r'([\s_-]|$)',
  caseSensitive: false,
);

/// Reads the main content out of [html].
///
/// This is a scoring heuristic, not a browser: it finds the element holding
/// the densest run of prose and keeps that. Pages that are not articles come
/// back with a low word count, which callers should treat as "no snapshot
/// worth taking" rather than as a failure.
ReadableArticle parseReadableArticle(String html, {Uri? baseUrl}) {
  final document = html_parser.parse(html);
  final base = _resolveBase(document, baseUrl);

  final pageTitle = _documentTitle(document);
  final byline = _byline(document);

  for (final element in document.querySelectorAll(_strippedTags.join(','))) {
    element.remove();
  }

  final candidate = _pickContent(document);
  if (candidate == null) {
    return ReadableArticle(
      markdown: '',
      plainText: '',
      wordCount: 0,
      title: pageTitle,
      byline: byline,
    );
  }

  _pruneFurniture(candidate);

  final writer = _MarkdownWriter(base: base);
  writer.writeChildren(candidate);
  final markdown = writer.result();
  final plainText = _collapse(candidate.text);

  return ReadableArticle(
    markdown: markdown,
    plainText: plainText,
    wordCount: _countWords(plainText),
    title: pageTitle,
    byline: byline,
    leadImageUrl: writer.firstImage,
  );
}

Uri? _resolveBase(dom.Document document, Uri? baseUrl) {
  final declared = document.querySelector('base[href]')?.attributes['href'];
  if (declared != null && declared.isNotEmpty) {
    final resolved = baseUrl?.resolve(declared) ?? Uri.tryParse(declared);
    if (resolved != null) {
      return resolved;
    }
  }
  return baseUrl;
}

String? _documentTitle(dom.Document document) {
  final og = document
      .querySelector('meta[property="og:title"]')
      ?.attributes['content']
      ?.trim();
  if (og != null && og.isNotEmpty) {
    return og;
  }
  final title = document.querySelector('title')?.text.trim();
  if (title != null && title.isNotEmpty) {
    return _collapse(title);
  }
  final heading = document.querySelector('h1')?.text.trim();
  return heading == null || heading.isEmpty ? null : _collapse(heading);
}

String? _byline(dom.Document document) {
  const selectors = [
    'meta[name="author"]',
    'meta[property="article:author"]',
    'meta[name="twitter:creator"]',
  ];
  for (final selector in selectors) {
    final value =
        document.querySelector(selector)?.attributes['content']?.trim();
    if (value != null && value.isNotEmpty && !value.startsWith('http')) {
      return value;
    }
  }
  final rel = document.querySelector('[rel="author"]')?.text.trim();
  if (rel != null && rel.isNotEmpty && rel.length < 80) {
    return _collapse(rel);
  }
  return null;
}

/// Scores every block that holds prose and returns the best container.
dom.Element? _pickContent(dom.Document document) {
  final body = document.body;
  if (body == null) {
    return null;
  }

  final scores = <dom.Element, double>{};
  for (final paragraph in body.querySelectorAll('p, pre, blockquote, li')) {
    final text = _collapse(paragraph.text);
    if (text.length < 25) {
      continue;
    }
    final score =
        1 + ','.allMatches(text).length + (text.length / 100).clamp(0, 3);
    var ancestor = paragraph.parent;
    var depth = 0;
    while (ancestor != null && depth < 3) {
      scores[ancestor] = (scores[ancestor] ?? 0) + score / (depth + 1);
      ancestor = ancestor.parent;
      depth++;
    }
  }

  if (scores.isEmpty) {
    return body.querySelector('article') ?? body.querySelector('main') ?? body;
  }

  dom.Element? best;
  var bestScore = 0.0;
  for (final entry in scores.entries) {
    final element = entry.key;
    var score = entry.value * (1 - _linkDensity(element));
    final marker = '${element.className} ${element.id}';
    if (_contentPattern.hasMatch(marker) ||
        const {'article', 'main'}.contains(element.localName)) {
      score *= 1.5;
    }
    if (_furniturePattern.hasMatch(marker)) {
      score *= 0.2;
    }
    if (score > bestScore) {
      bestScore = score;
      best = element;
    }
  }
  return best ?? body;
}

/// How much of an element's text is inside links.
///
/// A navigation column scores well on raw text but is nearly all links, which
/// is what tells the two apart.
double _linkDensity(dom.Element element) {
  final total = _collapse(element.text).length;
  if (total == 0) {
    return 0;
  }
  var linked = 0;
  for (final anchor in element.querySelectorAll('a')) {
    linked += _collapse(anchor.text).length;
  }
  return (linked / total).clamp(0.0, 1.0);
}

/// Drops the furniture left inside the chosen container.
void _pruneFurniture(dom.Element root) {
  for (final element in root.querySelectorAll('*').toList()) {
    if (element.parent == null) {
      continue;
    }
    final marker = '${element.className} ${element.id}';
    if (marker.trim().isEmpty || !_furniturePattern.hasMatch(marker)) {
      continue;
    }
    // A container that holds most of the prose is furniture in name only.
    if (_collapse(element.text).length > _collapse(root.text).length * 0.5) {
      continue;
    }
    element.remove();
  }
}

int _countWords(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

/// Names that mark an image as furniture rather than the post's own picture.
final _decorativeImagePattern = RegExp(
  'avatar|profile|icon|logo|sprite|emoji|badge|button|spacer|pixel|'
  'tracking|beacon|placeholder|thumb_?small|1x1|blank',
  caseSensitive: false,
);

String _collapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Walks the chosen subtree and writes Markdown.
class _MarkdownWriter {
  _MarkdownWriter({this.base});

  final Uri? base;
  final StringBuffer _buffer = StringBuffer();
  String? firstImage;

  String result() =>
      _buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

  void writeChildren(dom.Element element, {int listDepth = 0}) {
    for (final node in element.nodes) {
      if (node is dom.Element) {
        _writeElement(node, listDepth: listDepth);
      } else if (node is dom.Text) {
        final text = _collapse(node.text);
        if (text.isNotEmpty) {
          _buffer.write(_escape(text));
        }
      }
    }
  }

  void _writeElement(dom.Element element, {required int listDepth}) {
    switch (element.localName) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(element.localName!.substring(1));
        _block('${'#' * level} ${_inline(element)}');
      case 'p':
        _block(_inline(element));
      case 'br':
        _buffer.write('  \n');
      case 'hr':
        _block('---');
      case 'blockquote':
        final inner = _child(element);
        if (inner.isNotEmpty) {
          _block(inner.split('\n').map((line) => '> $line').join('\n'));
        }
      case 'pre':
        final code = element.querySelector('code') ?? element;
        final language = _codeLanguage(code);
        _block('```$language\n${code.text.trimRight()}\n```');
      case 'ul':
      case 'ol':
        _writeList(
          element,
          ordered: element.localName == 'ol',
          depth: listDepth,
        );
      case 'img':
        _writeImage(element);
      case 'figure':
        final image = element.querySelector('img');
        if (image != null) {
          _writeImage(image);
        }
        final caption = element.querySelector('figcaption');
        if (caption != null) {
          final text = _inline(caption);
          if (text.isNotEmpty) {
            _block('*$text*');
          }
        }
      case 'table':
        _writeTable(element);
      case 'li':
        _block(_inline(element));
      default:
        writeChildren(element, listDepth: listDepth);
    }
  }

  void _writeList(
    dom.Element list, {
    required bool ordered,
    required int depth,
  }) {
    final indent = '  ' * depth;
    var index = 1;
    final lines = <String>[];
    for (final item in list.children) {
      if (item.localName != 'li') {
        continue;
      }
      final nested = item.querySelectorAll('ul, ol');
      for (final child in nested) {
        child.remove();
      }
      final text = _inline(item);
      if (text.isNotEmpty) {
        lines.add('$indent${ordered ? '${index++}.' : '-'} $text');
      }
      for (final child in nested) {
        final writer = _MarkdownWriter(base: base)
          .._writeList(
            child,
            ordered: child.localName == 'ol',
            depth: depth + 1,
          );
        final rendered = writer.result();
        if (rendered.isNotEmpty) {
          lines.add(rendered);
        }
      }
    }
    if (lines.isNotEmpty) {
      _block(lines.join('\n'));
    }
  }

  void _writeImage(dom.Element image) {
    final source = _absolute(
      image.attributes['src'] ??
          image.attributes['data-src'] ??
          _firstSourceOf(image.attributes['srcset']),
    );
    if (source == null) {
      return;
    }
    _considerLeadImage(source, image);
    final alt = _collapse(image.attributes['alt'] ?? '');
    _block('![$alt]($source)');
  }

  void _writeTable(dom.Element table) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) {
      return;
    }
    final lines = <String>[];
    for (var i = 0; i < rows.length; i++) {
      final cells = rows[i].querySelectorAll('th, td');
      if (cells.isEmpty) {
        continue;
      }
      lines.add('| ${cells.map(_inline).join(' | ')} |');
      if (i == 0) {
        lines.add('| ${List.filled(cells.length, '---').join(' | ')} |');
      }
    }
    if (lines.length > 1) {
      _block(lines.join('\n'));
    }
  }

  /// Renders an element's inline content on one line.
  String _inline(dom.Element element) {
    final writer = _MarkdownWriter(base: base);
    for (final node in element.nodes) {
      if (node is dom.Text) {
        writer._buffer
            .write(_escape(node.text.replaceAll(RegExp(r'\s+'), ' ')));
        continue;
      }
      if (node is! dom.Element) {
        continue;
      }
      switch (node.localName) {
        case 'a':
          final label = writer._inline(node);
          final href = _absolute(node.attributes['href']);
          writer._buffer
              .write(href == null || label.isEmpty ? label : '[$label]($href)');
        case 'strong':
        case 'b':
          final label = writer._inline(node);
          writer._buffer.write(label.isEmpty ? '' : '**$label**');
        case 'em':
        case 'i':
          final label = writer._inline(node);
          writer._buffer.write(label.isEmpty ? '' : '*$label*');
        case 'code':
          final label = node.text.trim();
          writer._buffer.write(label.isEmpty ? '' : '`$label`');
        case 'br':
          writer._buffer.write(' ');
        case 'img':
          final source = _absolute(node.attributes['src']);
          if (source != null) {
            _considerLeadImage(source, node);
            final alt = _collapse(node.attributes['alt'] ?? '');
            writer._buffer.write('![$alt]($source)');
          }
        default:
          writer._buffer.write(writer._inline(node));
      }
    }
    firstImage ??= writer.firstImage;
    return _collapse(writer._buffer.toString());
  }

  String _child(dom.Element element) {
    final writer = _MarkdownWriter(base: base)..writeChildren(element);
    firstImage ??= writer.firstImage;
    return writer.result();
  }

  /// Keeps the best illustration seen so far.
  ///
  /// A post's own picture is what belongs on a card, so avatars, logos,
  /// buttons and tracking pixels are passed over even when they come first.
  void _considerLeadImage(String source, dom.Element image) {
    if (firstImage != null || _looksDecorative(source, image)) {
      return;
    }
    firstImage = source;
  }

  static bool _looksDecorative(String source, dom.Element image) {
    final width = int.tryParse(image.attributes['width'] ?? '');
    final height = int.tryParse(image.attributes['height'] ?? '');
    if ((width != null && width < 128) || (height != null && height < 128)) {
      return true;
    }
    final haystack =
        '$source ${image.className} ${image.attributes['alt'] ?? ''}'
            .toLowerCase();
    return _decorativeImagePattern.hasMatch(haystack);
  }

  void _block(String text) {
    if (text.trim().isEmpty) {
      return;
    }
    if (_buffer.isNotEmpty) {
      _buffer.write('\n\n');
    }
    _buffer.write(text.trim());
  }

  String? _absolute(String? url) {
    if (url == null) {
      return null;
    }
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.startsWith('data:')) {
      return null;
    }
    if (base == null || trimmed.startsWith('http')) {
      return trimmed;
    }
    return base!.resolve(trimmed).toString();
  }

  static String? _firstSourceOf(String? srcset) {
    if (srcset == null || srcset.trim().isEmpty) {
      return null;
    }
    return srcset.split(',').first.trim().split(RegExp(r'\s+')).first;
  }

  static String _codeLanguage(dom.Element code) {
    for (final name in code.classes) {
      if (name.startsWith('language-')) {
        return name.substring(9);
      }
      if (name.startsWith('lang-')) {
        return name.substring(5);
      }
    }
    return '';
  }

  /// Escapes only what would otherwise become markup by accident.
  static String _escape(String text) =>
      text.replaceAllMapped(RegExp(r'([\\`*_\[\]])'), (m) => '\\${m[1]}');
}
