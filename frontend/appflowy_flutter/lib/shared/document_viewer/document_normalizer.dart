import 'dart:ui' show TextAlign;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as markdown;

import 'document_content.dart';
import 'document_image.dart';

/// Lowers Markdown and HTML into the shared [DocumentBlock] model.
///
/// Markdown is converted to HTML first so both formats travel through exactly
/// one normalization path. Presentation is discarded entirely: no CSS, no
/// author fonts, no author colours. The renderer applies the application's own
/// typography, so an HTML file never looks like a web page.
abstract final class DocumentNormalizer {
  /// Elements whose content must never reach the reader.
  static const _ignoredElements = {
    'script',
    'style',
    'noscript',
    'iframe',
    'frame',
    'frameset',
    'object',
    'embed',
    'applet',
    'template',
    'link',
    'meta',
    'base',
    'form',
    'input',
    'button',
    'select',
    'textarea',
    'svg',
    'canvas',
    'audio',
    'video',
    'map',
    'area',
  };

  /// Containers that contribute no styling of their own.
  static const _transparentContainers = {
    'html',
    'body',
    'div',
    'section',
    'article',
    'main',
    'header',
    'footer',
    'aside',
    'nav',
    'details',
    'summary',
    'figure',
    'fieldset',
    'center',
    'dl',
    'dd',
    'colgroup',
    'col',
  };

  static const _blockElements = {
    ..._transparentContainers,
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'p',
    'pre',
    'blockquote',
    'ul',
    'ol',
    'li',
    'table',
    'hr',
    'figcaption',
    'dt',
  };

  /// Parses Markdown (GitHub flavoured) into normalized blocks.
  static List<DocumentBlock> fromMarkdown(
    String source, {
    String? baseDirectory,
  }) {
    final html = markdown.markdownToHtml(
      source,
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
      enableTagfilter: true,
    );
    return fromHtml(html, baseDirectory: baseDirectory);
  }

  /// Parses an HTML document or fragment into normalized blocks.
  static List<DocumentBlock> fromHtml(
    String source, {
    String? baseDirectory,
  }) {
    final document = html_parser.parse(source);
    final root = document.body ?? document.documentElement;
    if (root == null) {
      return const [];
    }
    final context = _NormalizeContext(baseDirectory);
    final blocks = _children(root, context);
    if (blocks.isNotEmpty) {
      return blocks;
    }
    // Fragments without recognizable structure still deserve their text.
    final fallback = root.text.trim();
    return fallback.isEmpty
        ? const []
        : [DocumentParagraphBlock(DocumentInline.text(fallback))];
  }

  /// Walks [parent]'s children, grouping loose inline runs into paragraphs.
  static List<DocumentBlock> _children(
    dom.Node parent,
    _NormalizeContext context,
  ) {
    final blocks = <DocumentBlock>[];
    final pending = <DocumentInlineSpan>[];

    void flush() {
      final inline = DocumentInline(_trimSpans(pending));
      pending.clear();
      if (!inline.isEmpty) {
        blocks.add(DocumentParagraphBlock(inline));
      }
    }

    for (final node in parent.nodes) {
      if (node is dom.Text) {
        pending.add(DocumentInlineSpan(text: node.text));
        continue;
      }
      if (node is! dom.Element) {
        continue;
      }
      final tag = node.localName?.toLowerCase();
      if (tag == null || _ignoredElements.contains(tag)) {
        continue;
      }
      if (_blockElements.contains(tag)) {
        flush();
        blocks.addAll(_block(node, tag, context));
        continue;
      }
      if (tag == 'img') {
        final image = _image(node, context);
        if (image != null) {
          flush();
          blocks.add(image);
        }
        continue;
      }
      pending.addAll(_inlineSpans(node, const DocumentInlineSpan(text: '')));
    }
    flush();
    return blocks;
  }

  static List<DocumentBlock> _block(
    dom.Element element,
    String tag,
    _NormalizeContext context,
  ) {
    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final text = _inline(element);
        if (text.isEmpty) {
          return const [];
        }
        return [
          DocumentHeadingBlock(
            level: int.parse(tag.substring(1)),
            text: text,
          ),
        ];

      case 'p':
      case 'dt':
        return _paragraph(element, context);

      case 'pre':
        return [_code(element)];

      case 'blockquote':
        return [_quoteOrCallout(element, context)];

      case 'ul':
      case 'ol':
        return [_list(element, tag == 'ol', context)];

      case 'li':
        // A stray list item outside a list still reads as a paragraph.
        return _children(element, context);

      case 'table':
        final table = _table(element);
        return table == null ? const [] : [table];

      case 'hr':
        return const [DocumentDividerBlock()];

      case 'figcaption':
        final caption = _inline(element);
        return caption.isEmpty
            ? const []
            : [DocumentParagraphBlock(caption, lead: true)];

      default:
        return _children(element, context);
    }
  }

  /// A paragraph holding images renders them at their own size.
  ///
  /// Text and images can coexist — a caption beside a badge — so the prose is
  /// kept and the images follow as their own run instead of being dropped.
  static List<DocumentBlock> _paragraph(
    dom.Element element,
    _NormalizeContext context,
  ) {
    final alignment = _alignmentOf(element) ?? TextAlign.start;
    final images = [
      for (final image in element.querySelectorAll('img'))
        if (_image(image, context, alignment) case final block?) block,
    ];
    final text = _inline(element);

    return [
      if (!text.isEmpty) DocumentParagraphBlock(text),
      if (images.length == 1) images.single,
      if (images.length > 1)
        DocumentImageRowBlock(images: images, alignment: alignment),
    ];
  }

  static DocumentCodeBlock _code(dom.Element element) {
    final code = element.querySelector('code');
    final source = (code ?? element).text;
    final classes = code?.className.split(RegExp(r'\s+')) ?? const [];
    String? language;
    for (final name in classes) {
      if (name.startsWith('language-')) {
        language = name.substring('language-'.length);
        break;
      }
      if (name.startsWith('lang-')) {
        language = name.substring('lang-'.length);
        break;
      }
    }
    return DocumentCodeBlock(
      code: _stripTrailingNewline(source),
      language: language?.isEmpty ?? true ? null : language,
    );
  }

  static final _alertPattern = RegExp(
    r'^\s*\[!(note|tip|important|warning|caution)\]\s*',
    caseSensitive: false,
  );

  static DocumentBlock _quoteOrCallout(
    dom.Element element,
    _NormalizeContext context,
  ) {
    final children = _children(element, context);
    if (children.isEmpty) {
      return DocumentQuoteBlock(children);
    }
    final first = children.first;
    if (first is! DocumentParagraphBlock) {
      return DocumentQuoteBlock(children);
    }
    final match = _alertPattern.firstMatch(first.text.plainText);
    if (match == null) {
      return DocumentQuoteBlock(children);
    }
    final tone = switch (match.group(1)!.toLowerCase()) {
      'tip' => DocumentCalloutTone.tip,
      'important' => DocumentCalloutTone.important,
      'warning' => DocumentCalloutTone.warning,
      'caution' => DocumentCalloutTone.caution,
      _ => DocumentCalloutTone.note,
    };
    final remainder = _stripLeading(first.text, match.end);
    return DocumentCalloutBlock(
      tone: tone,
      children: [
        if (!remainder.isEmpty) DocumentParagraphBlock(remainder),
        ...children.skip(1),
      ],
    );
  }

  static DocumentListBlock _list(
    dom.Element element,
    bool ordered,
    _NormalizeContext context,
  ) {
    final items = <DocumentListItem>[];
    for (final child in element.children) {
      if (child.localName?.toLowerCase() != 'li') {
        continue;
      }
      final checkbox = child.querySelector('input[type="checkbox"]');
      bool? checked;
      if (checkbox != null) {
        checked = checkbox.attributes.containsKey('checked') ||
            checkbox.attributes['checked'] == 'true';
        checkbox.remove();
      }
      items.add(
        DocumentListItem(
          checked: checked,
          children: _children(child, context),
        ),
      );
    }
    final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
    return DocumentListBlock(items: items, ordered: ordered, start: start);
  }

  static DocumentTableBlock? _table(dom.Element element) {
    final rows = <List<DocumentInline>>[];
    final alignments = <TextAlign?>[];
    var hasHeader = false;

    for (final row in element.querySelectorAll('tr')) {
      final cells = <DocumentInline>[];
      for (final cell in row.children) {
        final tag = cell.localName?.toLowerCase();
        if (tag != 'td' && tag != 'th') {
          continue;
        }
        if (tag == 'th' && rows.isEmpty) {
          hasHeader = true;
        }
        if (rows.isEmpty) {
          alignments.add(_alignmentOf(cell));
        }
        cells.add(_inline(cell));
      }
      if (cells.isNotEmpty) {
        rows.add(cells);
      }
    }
    if (rows.isEmpty) {
      return null;
    }
    return DocumentTableBlock(
      rows: rows,
      hasHeader: hasHeader,
      alignments: alignments,
    );
  }

  static TextAlign? _alignmentOf(dom.Element cell) {
    final declared = cell.attributes['align']?.toLowerCase() ??
        _styleAlignment(cell.attributes['style']);
    return switch (declared) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'left' => TextAlign.left,
      _ => null,
    };
  }

  static String? _styleAlignment(String? style) {
    if (style == null) {
      return null;
    }
    final match =
        RegExp(r'text-align\s*:\s*(\w+)', caseSensitive: false).firstMatch(
      style,
    );
    return match?.group(1)?.toLowerCase();
  }

  static DocumentImageBlock? _image(
    dom.Element element,
    _NormalizeContext context, [
    TextAlign alignment = TextAlign.start,
  ]) {
    final source = context.resolveUrl(
      element.attributes['src'],
      allowData: true,
    );
    if (source == null) {
      return null;
    }
    return DocumentImageBlock(
      source: source,
      alt: element.attributes['alt']?.trim(),
      width: parseCssLength(element.attributes['width']),
      height: parseCssLength(element.attributes['height']),
      alignment: _alignmentOf(element) ?? alignment,
    );
  }

  static DocumentInline _inline(dom.Element element) {
    final spans = _inlineSpans(element, const DocumentInlineSpan(text: ''));
    return DocumentInline(_trimSpans(spans));
  }

  static List<DocumentInlineSpan> _inlineSpans(
    dom.Node node,
    DocumentInlineSpan inherited,
  ) {
    final spans = <DocumentInlineSpan>[];
    for (final child in node.nodes) {
      if (child is dom.Text) {
        final text = child.text;
        if (text.isEmpty) {
          continue;
        }
        spans.add(inherited.copyWith(text: text));
        continue;
      }
      if (child is! dom.Element) {
        continue;
      }
      final tag = child.localName?.toLowerCase();
      if (tag == null || _ignoredElements.contains(tag)) {
        continue;
      }
      switch (tag) {
        case 'br':
          spans.add(inherited.copyWith(text: '\n'));
        case 'strong':
        case 'b':
          spans.addAll(_inlineSpans(child, inherited.copyWith(bold: true)));
        case 'em':
        case 'i':
        case 'cite':
        case 'var':
          spans.addAll(_inlineSpans(child, inherited.copyWith(italic: true)));
        case 'del':
        case 's':
        case 'strike':
          spans.addAll(
            _inlineSpans(child, inherited.copyWith(strikethrough: true)),
          );
        case 'code':
        case 'kbd':
        case 'samp':
          spans.addAll(_inlineSpans(child, inherited.copyWith(code: true)));
        case 'a':
          final href = child.attributes['href']?.trim();
          spans.addAll(
            _inlineSpans(
              child,
              href == null || href.isEmpty
                  ? inherited
                  : inherited.copyWith(link: href),
            ),
          );
        default:
          spans.addAll(_inlineSpans(child, inherited));
      }
    }
    return spans;
  }

  /// Collapses HTML whitespace and trims the run, preserving explicit breaks.
  static List<DocumentInlineSpan> _trimSpans(
    List<DocumentInlineSpan> spans,
  ) {
    final collapsed = <DocumentInlineSpan>[];
    for (final span in spans) {
      final text = span.code
          ? span.text
          : span.text
              .replaceAll(RegExp(r'[ \t\r\f\v]*\n[ \t\r\f\v]*'), '\n')
              .replaceAll(RegExp(r'[ \t]+'), ' ');
      if (text.isEmpty) {
        continue;
      }
      collapsed.add(span.copyWith(text: text));
    }
    while (collapsed.isNotEmpty && collapsed.first.text.trimLeft().isEmpty) {
      collapsed.removeAt(0);
    }
    while (collapsed.isNotEmpty && collapsed.last.text.trimRight().isEmpty) {
      collapsed.removeLast();
    }
    if (collapsed.isEmpty) {
      return const [];
    }
    collapsed[0] =
        collapsed.first.copyWith(text: collapsed.first.text.trimLeft());
    collapsed[collapsed.length - 1] =
        collapsed.last.copyWith(text: collapsed.last.text.trimRight());
    return collapsed;
  }

  static DocumentInline _stripLeading(DocumentInline inline, int characters) {
    var remaining = characters;
    final spans = <DocumentInlineSpan>[];
    for (final span in inline.spans) {
      if (remaining <= 0) {
        spans.add(span);
        continue;
      }
      if (span.text.length <= remaining) {
        remaining -= span.text.length;
        continue;
      }
      spans.add(span.copyWith(text: span.text.substring(remaining)));
      remaining = 0;
    }
    return DocumentInline(_trimSpans(spans));
  }

  static String _stripTrailingNewline(String value) =>
      value.endsWith('\n') ? value.substring(0, value.length - 1) : value;
}

class _NormalizeContext {
  const _NormalizeContext(this.baseDirectory);

  final String? baseDirectory;

  /// Resolves and sanitizes a document URL, rejecting active content schemes.
  String? resolveUrl(String? value, {required bool allowData}) {
    final normalized = value?.trim().replaceAll(RegExp(r'[\u0000-\u0020]'), '');
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    // Protocol-relative and UNC references escape the sandbox.
    if (normalized.startsWith('//') || normalized.startsWith(r'\\')) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return null;
    }
    if (!uri.hasScheme) {
      final base = baseDirectory;
      if (base == null) {
        return null;
      }
      return Uri.directory(base).resolveUri(uri).toString();
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https' || scheme == 'file') {
      return normalized;
    }
    if (allowData &&
        scheme == 'data' &&
        RegExp(
          '^data:image/(avif|bmp|gif|jpeg|jpg|png|webp)',
          caseSensitive: false,
        ).hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }
}
