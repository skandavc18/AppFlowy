import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show InAppWebViewPlatform;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as m;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Whether this platform can host the web-based Markdown and HTML previews.
///
/// `flutter_inappwebview` only registers an implementation where it has one.
/// Linux has none, so there those previews are drawn natively instead.
bool get webMarkupPreviewAvailable => InAppWebViewPlatform.instance != null;

enum NativeMarkupFormat { markdown, html }

@visibleForTesting
const nativeHtmlPreviewNotice =
    "Simplified view — this system has no web renderer, so the page's own "
    "styles and scripts aren't applied.";

@visibleForTesting
const nativeHtmlPreviewEmpty = 'This page has no text to show.';

const _bodyFontSize = 14.5;
const _bodyLineHeight = 1.65;
const _codeScale = 0.88;
const _codeFontFallback = ['Geist Mono', 'monospace'];
const _listIndent = 26.0;
const _listItemMargin = _bodyFontSize * 0.25;
const _bulletSize = 5.0;
const _checkboxSize = 15.0;
const _maxColumnWidth = 360.0;
const _maxColumnSpan = 32;
const _maxNesting = 24;

/// Sources at least this long are parsed off the UI thread.
const _backgroundParseLength = 256 * 1024;

/// Where a block sat inside inline content, e.g. a paragraph in a table cell.
const _blockBreakTag = 'appflowy-block-break';

/// Marks inline code that keeps its line breaks, from a `<pre>` in a cell.
const _preserveAttribute = 'data-appflowy-preserve';

final _languageClassPattern = RegExp(r'(?:^|\s)(?:language|lang)-(\S+)');
final _trailingNewlines = RegExp(r'[\r\n]+$');
final _previewableDataImage = RegExp(
  '^data:image/(?:avif|bmp|gif|jpeg|png|webp)[;,]',
  caseSensitive: false,
);

/// Shows Markdown or HTML without a web view: the document is reduced to
/// headings, paragraphs, lists, quotes, code, tables, rules and images, laid
/// out with the same measurements as the web preview's stylesheet.
///
/// Nothing is executed or fetched beyond images. Like the web preview, local
/// images are only read from inside the document's own directory.
class NativeMarkupPreview extends StatefulWidget {
  const NativeMarkupPreview({
    super.key,
    required this.source,
    required this.format,
    required this.baseDirectory,
  });

  final String source;
  final NativeMarkupFormat format;
  final String baseDirectory;

  @override
  State<NativeMarkupPreview> createState() => _NativeMarkupPreviewState();
}

class _NativeMarkupPreviewState extends State<NativeMarkupPreview> {
  final _scrollController = ScrollController();
  final _recognizers = <GestureRecognizer>[];
  List<m.Node>? _nodes;
  List<_Block> _blocks = const [];
  _Palette? _palette;
  bool _layoutDirty = true;
  int _parseRequest = 0;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _layoutDirty = true;
  }

  @override
  void didUpdateWidget(covariant NativeMarkupPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.format != widget.format) {
      _parse();
      _layoutDirty = true;
    } else if (oldWidget.baseDirectory != widget.baseDirectory) {
      _layoutDirty = true;
    }
  }

  @override
  void dispose() {
    _parseRequest++;
    _disposeRecognizers();
    _scrollController.dispose();
    super.dispose();
  }

  void _parse() {
    final request = ++_parseRequest;
    final source = widget.source;
    final format = widget.format;
    if (source.length < _backgroundParseLength) {
      _nodes = parseNativeMarkup(source, format);
      return;
    }
    _nodes = null;
    unawaited(
      compute(
        _parseInBackground,
        (source: source, format: format),
        debugLabel: 'native-markup-parse',
      ).then<void>(
        (nodes) => _parsed(request, nodes),
        onError: (Object _, StackTrace __) =>
            _parsed(request, [_sourceBlock(source)]),
      ),
    );
  }

  void _parsed(int request, List<m.Node> nodes) {
    if (!mounted || request != _parseRequest) return;
    setState(() {
      _nodes = nodes;
      _layoutDirty = true;
    });
  }

  /// Builds every block widget once, so scrolling never walks the tree again.
  void _layout() {
    _layoutDirty = false;
    _disposeRecognizers();
    final palette = _palette = _Palette.of(context);
    final nodes = _nodes;
    if (nodes == null) {
      _blocks = const [];
      return;
    }
    final renderer = _MarkupRenderer(
      palette: palette,
      baseDirectory: widget.baseDirectory,
      textScaler: MediaQuery.textScalerOf(context),
      recognizers: _recognizers,
    );
    try {
      _blocks = renderer.render(nodes);
    } on Object {
      // A pathologically deep document falls back to its source.
      _disposeRecognizers();
      _blocks = renderer.render([_sourceBlock(widget.source)]);
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_layoutDirty) _layout();
    final palette = _palette!;
    final note = palette.body.copyWith(
      fontSize: 12.5,
      height: 1.45,
      color: palette.muted,
    );
    final html = widget.format == NativeMarkupFormat.html;
    final items = <_Block>[
      if (html) _Block(_notice(palette, note), bottom: 20),
      if (_nodes == null)
        const _Block(
          Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else if (_blocks.isEmpty && html)
        _Block(Text(nativeHtmlPreviewEmpty, style: note)),
      ..._blocks,
    ];
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle.merge(
        style: palette.body,
        child: StandaloneFileScrollRegion(
          controller: _scrollController,
          child: SelectionArea(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(36, 32, 36, 40),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final gap = index == 0
                    ? 0.0
                    : math.max(items[index - 1].bottom, item.top);
                return gap == 0
                    ? item.child
                    : Padding(
                        padding: EdgeInsets.only(top: gap),
                        child: item.child,
                      );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(_Palette palette, TextStyle style) =>
      SelectionContainer.disabled(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1.5),
              child: Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: palette.muted,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(nativeHtmlPreviewNotice, style: style)),
          ],
        ),
      );
}

// Parsing ---------------------------------------------------------------------

/// Parses [source] into the Markdown AST the native preview draws. HTML is
/// first reduced to the same small vocabulary of elements.
@visibleForTesting
List<m.Node> parseNativeMarkup(String source, NativeMarkupFormat format) {
  try {
    return switch (format) {
      NativeMarkupFormat.markdown => _parseMarkdown(source),
      NativeMarkupFormat.html => htmlToMarkupNodes(_htmlBody(source)),
    };
  } on Object {
    // A malformed or pathological file must not take the tab down with it.
    return [_sourceBlock(source)];
  }
}

List<m.Node> _parseInBackground(
  ({String source, NativeMarkupFormat format}) request,
) =>
    parseNativeMarkup(request.source, request.format);

m.Document _markdownDocument({required bool encodeHtml}) => m.Document(
      extensionSet: m.ExtensionSet.gitHubFlavored,
      encodeHtml: encodeHtml,
    );

List<m.Node> _parseMarkdown(String source) {
  // Raw HTML (a centred README logo, say) keeps its structure by going
  // through an HTML tree. With everything else escaped first, only genuine
  // raw HTML can still contain a `<`.
  if (source.contains('<')) {
    final escaped = _markdownDocument(encodeHtml: true).parse(source);
    if (_containsRawHtml(escaped)) {
      final html = m.renderToHtml(escaped, enableTagfilter: true);
      return htmlToMarkupNodes(html_parser.parseFragment(html).nodes);
    }
  }
  return _markdownDocument(encodeHtml: false).parse(source);
}

/// Whether [source] embeds raw HTML rather than only Markdown syntax.
@visibleForTesting
bool markdownHasRawHtml(String source) =>
    source.contains('<') &&
    _containsRawHtml(_markdownDocument(encodeHtml: true).parse(source));

bool _containsRawHtml(List<m.Node>? nodes) {
  if (nodes == null) return false;
  for (final node in nodes) {
    if (node is m.Text && node.text.contains('<')) return true;
    if (node is m.Element && _containsRawHtml(node.children)) return true;
  }
  return false;
}

List<dom.Node> _htmlBody(String source) {
  final document = html_parser.parse(source);
  return (document.body ?? document.documentElement)?.nodes ?? const [];
}

m.Element _sourceBlock(String source) =>
    m.Element('pre', [m.Element.text('code', source)]);

/// Reduces parsed HTML to the elements the native preview draws.
@visibleForTesting
List<m.Node> htmlToMarkupNodes(Iterable<dom.Node> nodes) =>
    const _HtmlToMarkup().flow(nodes);

const _droppedHtmlTags = {
  'applet',
  'area',
  'audio',
  'base',
  'button',
  'canvas',
  'datalist',
  'dialog',
  'embed',
  'frame',
  'frameset',
  'head',
  'iframe',
  'link',
  'map',
  'math',
  'meta',
  'meter',
  'noembed',
  'noframes',
  'noscript',
  'object',
  'optgroup',
  'option',
  'output',
  'param',
  'progress',
  'script',
  'select',
  'slot',
  'source',
  'style',
  'svg',
  'template',
  'textarea',
  'title',
  'track',
  'video',
};

const _htmlBlockTags = {
  'address',
  'article',
  'aside',
  'blockquote',
  'body',
  'caption',
  'center',
  'dd',
  'details',
  'dir',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hgroup',
  'hr',
  'html',
  'legend',
  'li',
  'listing',
  'main',
  'menu',
  'nav',
  'ol',
  'p',
  'plaintext',
  'pre',
  'section',
  'summary',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
  'xmp',
};

const _htmlListTags = {'ul', 'ol', 'menu', 'dir'};
const _htmlPreTags = {'pre', 'listing', 'xmp', 'plaintext'};

final _displayNonePattern =
    RegExp(r'(?:^|;)\s*display\s*:\s*none\b', caseSensitive: false);
final _textAlignPattern =
    RegExp(r'(?:^|;)\s*text-align\s*:\s*([a-z-]+)', caseSensitive: false);
final _pixelLengthPattern = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(?:px)?\s*$');

/// Keeps a browser's anonymous blocks: inline runs are left mixed in with
/// blocks instead of each being wrapped in a paragraph.
class _HtmlToMarkup {
  const _HtmlToMarkup();

  List<m.Node> flow(Iterable<dom.Node> nodes) {
    final result = <m.Node>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        result.add(m.Text(node.data));
      } else if (node is dom.Element && _isRendered(node)) {
        final tag = node.localName ?? '';
        result.addAll(
          _htmlBlockTags.contains(tag)
              ? _block(node, tag)
              : _inlineElement(node, tag),
        );
      }
    }
    return result;
  }

  List<m.Node> inline(Iterable<dom.Node> nodes) {
    final result = <m.Node>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        result.add(m.Text(node.data));
      } else if (node is dom.Element && _isRendered(node)) {
        final tag = node.localName ?? '';
        if (!_htmlBlockTags.contains(tag)) {
          result.addAll(_inlineElement(node, tag));
          continue;
        }
        // A block inside a table cell or a link still starts its own line.
        result
          ..add(m.Element.empty(_blockBreakTag))
          ..addAll(
            _htmlPreTags.contains(tag)
                ? [
                    m.Element.text('code', _preText(node))
                      ..attributes[_preserveAttribute] = '',
                  ]
                : inline(node.nodes),
          )
          ..add(m.Element.empty(_blockBreakTag));
      }
    }
    return result;
  }

  List<m.Node> _block(dom.Element element, String tag) {
    final m.Element block;
    switch (tag) {
      case 'p' || 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        block = m.Element(tag, inline(element.nodes));
      case 'ul' || 'ol' || 'menu' || 'dir':
        block = _list(element, tag == 'ol' ? 'ol' : 'ul');
      case 'li':
        block = m.Element('ul', [_listItem(element)]);
      case 'blockquote':
        block = m.Element('blockquote', flow(element.nodes));
      case 'pre' || 'listing' || 'xmp' || 'plaintext':
        block = _pre(element);
      case 'hr':
        block = m.Element.empty('hr');
      case 'table':
        return _table(element);
      case 'summary':
        block = m.Element('p', [m.Element('strong', inline(element.nodes))]);
      default:
        block = m.Element('div', flow(element.nodes));
    }
    final align = tag == 'center' ? 'center' : _alignOf(element);
    if (align != null) block.attributes['align'] = align;
    // Keeps a GitHub alert's styling when its Markdown also had raw HTML.
    final className = element.attributes['class'];
    if (className != null && className.contains('markdown-alert')) {
      block.attributes['class'] = className;
    }
    return [block];
  }

  m.Element _list(dom.Element element, String tag) {
    final items = <m.Element>[];
    for (final child in element.nodes) {
      if (child is dom.Element) {
        if (!_isRendered(child)) continue;
        final childTag = child.localName ?? '';
        if (childTag == 'li') {
          items.add(_listItem(child));
        } else if (_htmlListTags.contains(childTag) && items.isNotEmpty) {
          // `<ul><li>a</li><ul>…</ul></ul>` nests the inner list under "a".
          items.last.children!.addAll(_block(child, childTag));
        } else {
          items.add(m.Element('li', flow([child])));
        }
      } else if (child is dom.Text && child.data.trim().isNotEmpty) {
        items.add(m.Element('li', [m.Text(child.data)]));
      }
    }
    final list = m.Element(tag, List<m.Node>.of(items));
    final start = int.tryParse(element.attributes['start']?.trim() ?? '');
    if (tag == 'ol' && start != null) list.attributes['start'] = '$start';
    return list;
  }

  m.Element _listItem(dom.Element item) {
    final node = m.Element('li', flow(item.nodes));
    final align = _alignOf(item);
    if (align != null) node.attributes['align'] = align;
    return node;
  }

  m.Element _pre(dom.Element pre) {
    dom.Element? code;
    for (final child in pre.children) {
      if (child.localName == 'code') {
        code = child;
        break;
      }
    }
    final language = _languageOf(code) ?? _languageOf(pre);
    final text = m.Element.text('code', _preText(pre));
    if (language != null) text.attributes['class'] = 'language-$language';
    return m.Element('pre', [text]);
  }

  String? _languageOf(dom.Element? element) {
    final className = element?.attributes['class'];
    return className == null
        ? null
        : _languageClassPattern.firstMatch(className)?.group(1);
  }

  /// Preformatted text as a browser shows it, including `<br>` line breaks.
  String _preText(dom.Element pre) {
    final buffer = StringBuffer();
    void visit(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.data);
      } else if (node is dom.Element) {
        if (node.localName == 'br') {
          buffer.write('\n');
        } else if (_isRendered(node)) {
          for (final child in node.nodes) {
            visit(child);
          }
        }
      }
    }

    for (final child in pre.nodes) {
      visit(child);
    }
    return buffer.toString();
  }

  List<m.Node> _table(dom.Element table) {
    final caption = <m.Node>[];
    final head = <m.Node>[];
    final body = <m.Node>[];
    for (final child in table.children) {
      if (!_isRendered(child)) continue;
      switch (child.localName) {
        case 'caption':
          caption.add(
            m.Element('p', [m.Element('em', inline(child.nodes))]),
          );
        case 'thead':
          head.addAll(_rows(child));
        case 'tbody' || 'tfoot':
          body.addAll(_rows(child));
        case 'tr':
          body.add(_row(child));
      }
    }
    if (head.isEmpty && body.isEmpty) return caption;
    return [
      ...caption,
      m.Element('table', [
        if (head.isNotEmpty) m.Element('thead', head),
        if (body.isNotEmpty) m.Element('tbody', body),
      ]),
    ];
  }

  List<m.Node> _rows(dom.Element section) => [
        for (final row in section.children)
          if (row.localName == 'tr' && _isRendered(row)) _row(row),
      ];

  m.Element _row(dom.Element row) {
    final cells = <m.Node>[];
    for (final cell in row.children) {
      final tag = cell.localName ?? '';
      if ((tag != 'td' && tag != 'th') || !_isRendered(cell)) continue;
      final node = m.Element(tag, inline(cell.nodes));
      final align = _alignOf(cell);
      if (align != null) node.attributes['align'] = align;
      cells.add(node);
      final span = int.tryParse(cell.attributes['colspan']?.trim() ?? '') ?? 1;
      for (var extra = 1; extra < span.clamp(1, _maxColumnSpan); extra++) {
        cells.add(m.Element(tag, <m.Node>[]));
      }
    }
    return m.Element('tr', cells);
  }

  List<m.Node> _inlineElement(dom.Element element, String tag) {
    List<m.Node> children() => inline(element.nodes);
    switch (tag) {
      case 'br':
        return [m.Element.empty('br')];
      case 'img':
        return [_image(element)];
      case 'input':
        final checkbox = m.Element.empty('input')
          ..attributes['type'] = 'checkbox';
        if (element.attributes.containsKey('checked')) {
          checkbox.attributes['checked'] = 'true';
        }
        return [checkbox];
      case 'a':
        final href = element.attributes['href']?.trim() ?? '';
        if (href.isEmpty) return children();
        return [m.Element('a', children())..attributes['href'] = href];
      case 'b' || 'strong':
        return [m.Element('strong', children())];
      case 'i' || 'em' || 'cite' || 'dfn' || 'var':
        return [m.Element('em', children())];
      case 's' || 'strike' || 'del':
        return [m.Element('del', children())];
      case 'u' || 'ins':
        return [m.Element('u', children())];
      case 'sup' || 'sub':
        return [m.Element(tag, children())];
      case 'code' || 'kbd' || 'samp' || 'tt':
        return [m.Element.text('code', element.text)];
      case 'q':
        return [m.Text('“'), ...children(), m.Text('”')];
      default:
        return children();
    }
  }

  m.Element _image(dom.Element element) {
    final image = m.Element.empty('img')
      ..attributes['src'] = element.attributes['src']?.trim() ?? ''
      ..attributes['alt'] = element.attributes['alt'] ?? '';
    // Only a width is honoured: the web preview's `height: auto` keeps the
    // aspect ratio whatever height the page asked for.
    final width =
        _pixelLengthPattern.firstMatch(element.attributes['width'] ?? '');
    if (width != null) image.attributes['width'] = width.group(1)!;
    return image;
  }
}

bool _isRendered(dom.Element element) {
  final tag = element.localName ?? '';
  if (_droppedHtmlTags.contains(tag) ||
      element.attributes.containsKey('hidden')) {
    return false;
  }
  if (tag == 'input' &&
      element.attributes['type']?.trim().toLowerCase() != 'checkbox') {
    return false;
  }
  final style = element.attributes['style'];
  return style == null || !_displayNonePattern.hasMatch(style);
}

String? _alignOf(dom.Element element) {
  final style = element.attributes['style'];
  final value =
      (style == null ? null : _textAlignPattern.firstMatch(style)?.group(1)) ??
          element.attributes['align'];
  return switch (value?.trim().toLowerCase()) {
    'left' || 'start' => 'left',
    'right' || 'end' => 'right',
    'center' || 'middle' || '-webkit-center' => 'center',
    'justify' => 'justify',
    _ => null,
  };
}

// Resources -------------------------------------------------------------------

/// Where an image's [source] may be loaded from, mirroring the web preview:
/// remote http(s) images, raster `data:` images, and relative paths that stay
/// inside [baseDirectory]. Absolute paths and `file:` URIs are refused.
@visibleForTesting
Uri? resolveNativeMarkupImageUri(String source, String baseDirectory) {
  // Browsers read a backslash as a path separator, and so does the web
  // preview this stands in for.
  final value = source.trim().replaceAll('\\', '/');
  if (value.isEmpty || value.startsWith('//')) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  switch (uri.scheme.toLowerCase()) {
    case 'http' || 'https':
      return uri.host.isEmpty ? null : uri;
    case 'data':
      return _previewableDataImage.hasMatch(value) ? uri : null;
    case '':
      break;
    default:
      return null;
  }
  if (uri.path.isEmpty || uri.path.startsWith('/')) return null;
  final String relative;
  try {
    relative = Uri.decodeComponent(uri.path);
  } on Object {
    return null;
  }
  final root = p.normalize(p.absolute(baseDirectory));
  final path = p.normalize(p.join(root, relative));
  return p.isWithin(root, path) ? Uri.file(path) : null;
}

/// The image file behind [uri], or null when it is not an image or a link
/// resolves outside [baseDirectory].
Future<File?> _containedImageFile(Uri uri, String baseDirectory) async {
  try {
    final path = uri.toFilePath();
    if (!(lookupMimeType(path)?.startsWith('image/') ?? false)) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final root = await Directory(baseDirectory).resolveSymbolicLinks();
    final resolved = await file.resolveSymbolicLinks();
    return p.isWithin(root, resolved) ? File(resolved) : null;
  } on Object {
    return null;
  }
}

Uri? _launchableUri(String? href) {
  final uri = Uri.tryParse(href?.trim() ?? '');
  if (uri == null) return null;
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' when uri.host.isNotEmpty => uri,
    'mailto' when uri.path.isNotEmpty => uri,
    _ => null,
  };
}

void _openLink(Uri uri) {
  // afLaunchUri rewrites anything it cannot open as an https URL, which
  // would turn a mail address into a web address.
  final launch =
      uri.isScheme('mailto') ? launcher.launchUrl(uri) : afLaunchUri(uri);
  unawaited(launch.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
}

// Rendering -------------------------------------------------------------------

class _Palette {
  const _Palette({
    required this.text,
    required this.muted,
    required this.link,
    required this.rule,
    required this.ruleStrong,
    required this.codeBackground,
    required this.body,
    required this.brightness,
    required this.isPaper,
  });

  /// The web preview's palette: the same theme sources and alphas.
  factory _Palette.of(BuildContext context) {
    final theme = Theme.of(context);
    final appFlowy = AppFlowyTheme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final text = appFlowy.textColorScheme.primary;
    final border = appFlowy.borderColorScheme.primary;
    return _Palette(
      text: text,
      muted: text.withValues(alpha: 0.6),
      link: theme.colorScheme.primary,
      rule: border.withValues(alpha: 0.22),
      ruleStrong: border.withValues(alpha: 0.32),
      codeBackground: EditorSurfaceStyle.codeBlockBackgroundFor(
        theme.brightness,
        theme.colorScheme.surfaceContainer,
        isPaper: isPaper,
      ),
      body: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: _bodyFontSize,
        height: _bodyLineHeight,
        letterSpacing: 0,
        color: text,
      ),
      brightness: theme.brightness,
      isPaper: isPaper,
    );
  }

  final Color text;
  final Color muted;
  final Color link;
  final Color rule;
  final Color ruleStrong;
  final Color codeBackground;
  final TextStyle body;
  final Brightness brightness;
  final bool isPaper;

  TextStyle get code => TextStyle(
        fontFamily: builtInCodeFontFamily,
        fontFamilyFallback: [
          ..._codeFontFallback,
          ...?body.fontFamilyFallback,
        ],
        fontSize: _bodyFontSize * _codeScale,
        height: 1.55,
        letterSpacing: 0,
        color: text,
      );
}

/// A laid-out block and its CSS margins. Adjacent margins collapse to the
/// larger one, and a transparent container passes its children's through.
class _Block {
  const _Block(this.child, {this.top = 0, this.bottom = 0});

  final Widget child;
  final double top;
  final double bottom;
}

typedef _Flow = ({TextStyle style, TextAlign align, bool inListItem});
typedef _Link = ({Uri uri, GestureRecognizer recognizer});

const _rendererBlockTags = {
  'blockquote',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'li',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'ul',
};

class _MarkupRenderer {
  _MarkupRenderer({
    required this.palette,
    required this.baseDirectory,
    required this.textScaler,
    required this.recognizers,
  });

  final _Palette palette;
  final String baseDirectory;
  final TextScaler textScaler;

  /// Owned and disposed by the preview's state.
  final List<GestureRecognizer> recognizers;

  int _listDepth = 0;
  int _nesting = 0;

  List<_Block> render(List<m.Node> nodes) => _flow(
        nodes,
        (style: palette.body, align: TextAlign.start, inListItem: false),
      );

  List<_Block> _flow(List<m.Node> nodes, _Flow flow) {
    final blocks = <_Block>[];
    final run = <m.Node>[];
    void flushRun() {
      if (run.isEmpty) return;
      final paragraph = _paragraph(run, flow.style, flow.align);
      run.clear();
      if (paragraph != null) blocks.add(_Block(paragraph));
    }

    for (final node in nodes) {
      if (node is m.Element && _rendererBlockTags.contains(node.tag)) {
        flushRun();
        blocks.addAll(_block(node, flow));
      } else {
        run.add(node);
      }
    }
    flushRun();
    return blocks;
  }

  List<_Block> _block(m.Element element, _Flow flow) {
    final children = element.children ?? const <m.Node>[];
    final align = _textAlign(element, flow.align);
    switch (element.tag) {
      case 'p':
        final title = _hasClass(element, 'markdown-alert-title');
        final paragraph = _paragraph(
          children,
          title
              ? _weighted(
                  flow.style.copyWith(color: palette.link),
                  FontWeight.w600,
                )
              : flow.style,
          align,
        );
        return [
          if (paragraph != null) _Block(paragraph, bottom: title ? 6 : 14),
        ];
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        return _heading(
          children,
          int.parse(element.tag.substring(1)),
          flow.style,
          align,
        );
      case 'ul' || 'ol':
        return _list(element, flow, align);
      case 'li':
        return _list(m.Element('ul', [element]), flow, align);
      case 'blockquote':
        return _quote(
          children,
          flow.style.copyWith(color: palette.muted),
          palette.ruleStrong,
          align,
        );
      case 'div' when _hasClass(element, 'markdown-alert'):
        return _quote(children, flow.style, palette.link, align);
      case 'pre':
        return [_Block(_codeBlock(element), bottom: 16)];
      case 'table':
        final table = _table(element, flow.style);
        return [if (table != null) _Block(table, bottom: 16)];
      case 'hr':
        return [
          _Block(
            SizedBox(height: 1, child: ColoredBox(color: palette.rule)),
            top: 24,
            bottom: 24,
          ),
        ];
      default:
        return _flow(
          children,
          (style: flow.style, align: align, inListItem: false),
        );
    }
  }

  List<_Block> _heading(
    List<m.Node> children,
    int level,
    TextStyle base,
    TextAlign align,
  ) {
    const scales = [1.7, 1.32, 1.12, 1.0, 0.92, 0.92];
    final size = (base.fontSize ?? _bodyFontSize) * scales[level - 1];
    final style = _weighted(
      base.copyWith(
        fontSize: size,
        height: 1.3,
        letterSpacing: -0.014 * size,
        color: level >= 5 ? palette.muted : null,
      ),
      FontWeight.w600,
    );
    final text = _paragraph(children, style, align);
    if (text == null) return const [];
    return [
      _Block(
        level > 2
            ? text
            // A hairline under the two largest levels, as GitHub sets them.
            : DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.rule)),
                ),
                child: Padding(
                  padding: EdgeInsets.only(bottom: size * 0.32),
                  child: text,
                ),
              ),
        top: 28,
        bottom: 14,
      ),
    ];
  }

  List<_Block> _list(m.Element list, _Flow flow, TextAlign align) {
    final items = [
      for (final node in list.children ?? const <m.Node>[])
        if (node is m.Element && node.tag == 'li') node,
    ];
    if (items.isEmpty) return const [];
    if (_nesting >= _maxNesting) {
      return [
        for (final item in items) ..._flow(item.children ?? const [], flow),
      ];
    }
    final ordered = list.tag == 'ol';
    var number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    _listDepth++;
    _nesting++;
    try {
      final rows = [
        for (final item in items)
          _listItem(
            item,
            flow.style,
            _textAlign(item, align),
            ordered ? number++ : null,
          ),
      ];
      // A list directly inside a list item is spaced like an item.
      final nested = flow.inListItem;
      return [
        _Block(
          _column(rows),
          top: math.max(nested ? _listItemMargin : 0, rows.first.top),
          bottom: math.max(nested ? _listItemMargin : 14, rows.last.bottom),
        ),
      ];
    } finally {
      _listDepth--;
      _nesting--;
    }
  }

  _Block _listItem(
    m.Element item,
    TextStyle style,
    TextAlign align,
    int? number,
  ) {
    var content = item.children ?? const <m.Node>[];
    bool? checked;
    if (number == null) {
      (checked, content) = _splitTask(content);
    }
    final blocks =
        _flow(content, (style: style, align: align, inListItem: true));
    final Widget marker;
    if (checked != null) {
      marker = _alignedMarker(_checkbox(checked), _checkboxSize, style, 7);
    } else if (number != null) {
      marker = _orderedMarker(number, style);
    } else {
      marker = _alignedMarker(_bullet(style), _bulletSize, style, 8);
    }
    return _Block(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _listIndent,
            child: SelectionContainer.disabled(child: marker),
          ),
          Expanded(
            child: blocks.isEmpty
                ? SizedBox(height: _lineHeight(style))
                : _column(blocks),
          ),
        ],
      ),
      top: math.max(_listItemMargin, blocks.isEmpty ? 0 : blocks.first.top),
      bottom:
          math.max(_listItemMargin, blocks.isEmpty ? 0 : blocks.last.bottom),
    );
  }

  /// Lifts a task item's leading checkbox out of its content to stand in for
  /// the bullet. The parsed tree is left untouched.
  (bool?, List<m.Node>) _splitTask(List<m.Node> children) {
    final index = children.indexWhere((node) => !_isBlankText(node));
    if (index < 0) return (null, children);
    final first = children[index];
    final checked = _checkedState(first);
    if (checked != null) {
      return (
        checked,
        [...children.take(index), ...children.skip(index + 1)],
      );
    }
    if (first is m.Element && first.tag == 'p') {
      final inner = first.children ?? const <m.Node>[];
      final innerIndex = inner.indexWhere((node) => !_isBlankText(node));
      final innerChecked =
          innerIndex < 0 ? null : _checkedState(inner[innerIndex]);
      if (innerChecked != null) {
        final paragraph = m.Element('p', [
          ...inner.take(innerIndex),
          ...inner.skip(innerIndex + 1),
        ])
          ..attributes.addAll(first.attributes);
        return (
          innerChecked,
          [...children.take(index), paragraph, ...children.skip(index + 1)],
        );
      }
    }
    return (null, children);
  }

  double _lineHeight(TextStyle style) =>
      textScaler.scale(style.fontSize ?? _bodyFontSize) *
      (style.height ?? _bodyLineHeight);

  /// Centres a marker on the first line of its item.
  Widget _alignedMarker(
    Widget marker,
    double size,
    TextStyle style,
    double end,
  ) =>
      Padding(
        padding: EdgeInsetsDirectional.only(
          top: math.max(0.0, (_lineHeight(style) - size) / 2),
          end: end,
        ),
        child: Align(alignment: AlignmentDirectional.topEnd, child: marker),
      );

  Widget _bullet(TextStyle style) {
    final color = style.color ?? palette.text;
    final decoration = switch ((_listDepth - 1) % 3) {
      0 => BoxDecoration(color: color, shape: BoxShape.circle),
      1 => BoxDecoration(
          border: Border.all(color: color),
          shape: BoxShape.circle,
        ),
      _ => BoxDecoration(color: color),
    };
    return SizedBox.square(
      dimension: _bulletSize,
      child: DecoratedBox(decoration: decoration),
    );
  }

  /// Long numbers grow into the list's indent rather than wrapping.
  Widget _orderedMarker(int number, TextStyle style) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: OverflowBox(
          alignment: AlignmentDirectional.topEnd,
          minWidth: 0,
          maxWidth: double.infinity,
          fit: OverflowBoxFit.deferToChild,
          child: Text('$number.', style: style, maxLines: 1, softWrap: false),
        ),
      );

  Widget _checkbox(bool checked) => Icon(
        checked
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded,
        size: _checkboxSize,
        color: checked ? palette.link : palette.muted,
      );

  List<_Block> _quote(
    List<m.Node> children,
    TextStyle style,
    Color side,
    TextAlign align,
  ) {
    final flow = (style: style, align: align, inListItem: false);
    if (_nesting >= _maxNesting) return _flow(children, flow);
    _nesting++;
    final List<_Block> blocks;
    try {
      blocks = _flow(children, flow);
    } finally {
      _nesting--;
    }
    if (blocks.isEmpty) return const [];
    return [
      _Block(
        DecoratedBox(
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: side, width: 3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 0, 2),
            child: _column(blocks),
          ),
        ),
        bottom: 14,
      ),
    ];
  }

  Widget _codeBlock(m.Element pre) {
    m.Element? code;
    for (final child in pre.children ?? const <m.Node>[]) {
      if (child is m.Element && child.tag == 'code') {
        code = child;
        break;
      }
    }
    final className = code?.attributes['class'] ?? '';
    return _NativeCodeBlock(
      code: (code ?? pre).textContent.replaceFirst(_trailingNewlines, ''),
      language: _languageClassPattern.firstMatch(className)?.group(1) ?? '',
      style: palette.code,
      background: palette.codeBackground,
      brightness: palette.brightness,
      isPaper: palette.isPaper,
    );
  }

  Widget? _table(m.Element table, TextStyle style) {
    final rows = <({bool header, List<m.Element> cells})>[];
    void addRow(m.Node row, {required bool header}) {
      if (row is! m.Element || row.tag != 'tr') return;
      final cells = [
        for (final cell in row.children ?? const <m.Node>[])
          if (cell is m.Element && (cell.tag == 'td' || cell.tag == 'th')) cell,
      ];
      rows.add(
        (
          header: header ||
              (cells.isNotEmpty && cells.every((cell) => cell.tag == 'th')),
          cells: cells,
        ),
      );
    }

    for (final section in table.children ?? const <m.Node>[]) {
      if (section is! m.Element) continue;
      switch (section.tag) {
        case 'tr':
          addRow(section, header: false);
        case 'thead' || 'tbody' || 'tfoot':
          for (final row in section.children ?? const <m.Node>[]) {
            addRow(row, header: section.tag == 'thead');
          }
      }
    }
    final columns =
        rows.fold(0, (count, row) => math.max(count, row.cells.length));
    if (columns == 0) return null;
    final headerStyle = _weighted(style, FontWeight.w600);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: palette.rule),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Table(
            defaultColumnWidth: const MinColumnWidth(
              IntrinsicColumnWidth(),
              FixedColumnWidth(_maxColumnWidth),
            ),
            border: TableBorder(
              horizontalInside: BorderSide(color: palette.rule),
            ),
            children: [
              for (final row in rows)
                TableRow(
                  decoration: row.header
                      ? BoxDecoration(color: palette.codeBackground)
                      : null,
                  children: [
                    for (var column = 0; column < columns; column++)
                      _tableCell(
                        column < row.cells.length ? row.cells[column] : null,
                        style,
                        headerStyle,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableCell(m.Element? cell, TextStyle style, TextStyle headerStyle) {
    final span = cell == null
        ? null
        : _inlineSpan(
            cell.children ?? const [],
            cell.tag == 'th' ? headerStyle : style,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      child: span == null
          ? const SizedBox.shrink()
          : Text.rich(span, textAlign: _textAlign(cell!, TextAlign.start)),
    );
  }

  Widget? _paragraph(List<m.Node> nodes, TextStyle style, TextAlign align) {
    final span = _inlineSpan(nodes, style);
    return span == null ? null : Text.rich(span, textAlign: align);
  }

  InlineSpan? _inlineSpan(List<m.Node> nodes, TextStyle style) {
    final collector = _InlineCollector();
    _inline(nodes, collector, style, null);
    return collector.finish(style);
  }

  void _inline(
    List<m.Node> nodes,
    _InlineCollector out,
    TextStyle style,
    _Link? link, {
    bool preserve = false,
  }) {
    for (final node in nodes) {
      if (node is m.Text) {
        out.text(node.text, style, link?.recognizer, preserve: preserve);
        continue;
      }
      if (node is! m.Element) continue;
      final children = node.children ?? const <m.Node>[];
      void nested(
        TextStyle style, {
        _Link? link,
        bool keepWhitespace = false,
      }) =>
          _inline(
            children,
            out,
            style,
            link,
            preserve: preserve || keepWhitespace,
          );
      switch (node.tag) {
        case 'br':
          out.lineBreak(style);
        case _blockBreakTag:
          out.blockBreak(style);
        case 'strong' || 'b':
          nested(_weighted(style, FontWeight.w700), link: link);
        case 'em' || 'i':
          nested(style.copyWith(fontStyle: FontStyle.italic), link: link);
        case 'del' || 's':
          nested(_decorated(style, TextDecoration.lineThrough), link: link);
        case 'u':
          nested(_decorated(style, TextDecoration.underline), link: link);
        case 'sup' || 'sub':
          nested(
            style.copyWith(
              fontSize: (style.fontSize ?? _bodyFontSize) * 0.78,
            ),
            link: link,
          );
        case 'code':
          nested(
            _inlineCode(style),
            link: link,
            keepWhitespace: node.attributes.containsKey(_preserveAttribute),
          );
        case 'a':
          nested(
            style.copyWith(color: palette.link),
            link: _link(node.attributes['href']) ?? link,
          );
        case 'img':
          _image(node, out, style, link);
        case 'input':
          final checked = _checkedState(node);
          if (checked != null) {
            out.widget(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 5),
                  child: _checkbox(checked),
                ),
              ),
            );
          }
        default:
          // A block that ended up inside inline content keeps its own line.
          final block = _rendererBlockTags.contains(node.tag);
          if (block) out.blockBreak(style);
          nested(style, link: link);
          if (block) out.blockBreak(style);
      }
    }
  }

  _Link? _link(String? href) {
    final uri = _launchableUri(href);
    if (uri == null) return null;
    final recognizer = TapGestureRecognizer()..onTap = () => _openLink(uri);
    recognizers.add(recognizer);
    return (uri: uri, recognizer: recognizer);
  }

  void _image(
    m.Element image,
    _InlineCollector out,
    TextStyle style,
    _Link? link,
  ) {
    final alt = image.attributes['alt'] ?? '';
    final uri = resolveNativeMarkupImageUri(
      image.attributes['src'] ?? '',
      baseDirectory,
    );
    if (uri == null) {
      out.text(alt, style, link?.recognizer);
      return;
    }
    Widget child = _NativeImage(
      uri: uri,
      alt: alt,
      width: double.tryParse(image.attributes['width'] ?? ''),
      baseDirectory: baseDirectory,
      muted: palette.muted,
    );
    if (link != null) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openLink(link.uri),
          child: child,
        ),
      );
    }
    out.widget(
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: child),
    );
  }

  TextStyle _inlineCode(TextStyle style) => style.copyWith(
        fontFamily: builtInCodeFontFamily,
        fontFamilyFallback: [
          ..._codeFontFallback,
          ...?style.fontFamilyFallback,
        ],
        fontSize: (style.fontSize ?? _bodyFontSize) * _codeScale,
        height: 1.45,
        letterSpacing: 0,
        backgroundColor: palette.codeBackground,
      );
}

Widget _column(List<_Block> blocks) {
  if (blocks.length == 1) return blocks.single.child;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < blocks.length; index++)
        if (index == 0)
          blocks[index].child
        else
          Padding(
            padding: EdgeInsets.only(
              top: math.max(blocks[index - 1].bottom, blocks[index].top),
            ),
            child: blocks[index].child,
          ),
    ],
  );
}

TextAlign _textAlign(m.Element element, TextAlign inherited) =>
    switch (element.attributes['align']) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      _ => inherited,
    };

bool _hasClass(m.Element element, String name) =>
    (element.attributes['class'] ?? '').split(' ').contains(name);

bool _isBlankText(m.Node node) => node is m.Text && node.text.trim().isEmpty;

bool? _checkedState(m.Node node) => node is m.Element &&
        node.tag == 'input' &&
        node.attributes['type'] == 'checkbox'
    ? node.attributes.containsKey('checked')
    : null;

TextStyle _weighted(TextStyle style, FontWeight weight) => style.copyWith(
      fontWeight: weight,
      fontVariations: flowyFontVariationsForWeight(weight),
    );

TextStyle _decorated(TextStyle style, TextDecoration decoration) =>
    style.copyWith(
      decoration: TextDecoration.combine([
        if (style.decoration != null) style.decoration!,
        decoration,
      ]),
    );

final _collapsibleWhitespace = RegExp(r'[ \t\n\r\f]+');
final _trailingSpaces = RegExp(r' +$');
final _trailingSpacesAndBreaks = RegExp(r'[ \n]+$');

/// Collects one paragraph's spans, collapsing whitespace the way CSS does:
/// runs become one space, and none is kept at the start or end of a line.
class _InlineCollector {
  final _spans = <InlineSpan>[];
  final _text = StringBuffer();
  TextStyle? _style;
  GestureRecognizer? _recognizer;

  /// Nothing has been written on the current line yet.
  bool _lineStart = true;

  /// The last character written is a collapsible space.
  bool _space = false;

  void text(
    String value,
    TextStyle style,
    GestureRecognizer? recognizer, {
    bool preserve = false,
  }) {
    var text = preserve ? value : value.replaceAll(_collapsibleWhitespace, ' ');
    if (!preserve && text.startsWith(' ') && (_lineStart || _space)) {
      text = text.substring(1);
    }
    if (text.isEmpty) return;
    if (_text.isNotEmpty && (style != _style || recognizer != _recognizer)) {
      _flushText();
    }
    _style = style;
    _recognizer = recognizer;
    _text.write(text);
    _lineStart = text.endsWith('\n');
    _space = !preserve && text.endsWith(' ');
  }

  void lineBreak(TextStyle style) {
    _trimTrailing(_trailingSpaces);
    text('\n', style, null, preserve: true);
  }

  void blockBreak(TextStyle style) {
    if (!_lineStart) lineBreak(style);
  }

  void widget(InlineSpan span) {
    _flushText();
    _spans.add(span);
    _lineStart = false;
    _space = false;
  }

  InlineSpan? finish(TextStyle style) {
    _trimTrailing(_trailingSpacesAndBreaks);
    _flushText();
    return _spans.isEmpty ? null : TextSpan(style: style, children: _spans);
  }

  void _flushText() {
    if (_text.isEmpty) return;
    _spans.add(
      TextSpan(
        text: _text.toString(),
        style: _style,
        recognizer: _recognizer,
      ),
    );
    _text.clear();
  }

  void _trimTrailing(RegExp pattern) {
    while (true) {
      if (_text.isEmpty) {
        // Reopen the previous text span; a widget ends the search.
        if (_spans.isEmpty || _spans.last is! TextSpan) return;
        final last = _spans.removeLast() as TextSpan;
        _text.write(last.text ?? '');
        _style = last.style;
        _recognizer = last.recognizer;
        continue;
      }
      final value = _text.toString();
      final trimmed = value.replaceFirst(pattern, '');
      if (trimmed.length == value.length) return;
      _text
        ..clear()
        ..write(trimmed);
      if (trimmed.isNotEmpty) return;
    }
  }
}

class _NativeCodeBlock extends StatefulWidget {
  const _NativeCodeBlock({
    required this.code,
    required this.language,
    required this.style,
    required this.background,
    required this.brightness,
    required this.isPaper,
  });

  final String code;
  final String language;
  final TextStyle style;
  final Color background;
  final Brightness brightness;
  final bool isPaper;

  @override
  State<_NativeCodeBlock> createState() => _NativeCodeBlockState();
}

class _NativeCodeBlockState extends State<_NativeCodeBlock> {
  TextSpan? _highlighted;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _highlight();
  }

  @override
  void didUpdateWidget(covariant _NativeCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language ||
        oldWidget.style != widget.style ||
        oldWidget.brightness != widget.brightness ||
        oldWidget.isPaper != widget.isPaper) {
      _highlight();
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  /// Only a named, known language is coloured; guessing one is costly and
  /// the web preview never highlights at all.
  void _highlight() {
    final request = ++_request;
    _highlighted = null;
    if (!hasSyntaxGrammar(widget.language)) return;
    _highlighted = cachedSyntaxHighlightedTextSpan(
      code: widget.code,
      language: widget.language,
      brightness: widget.brightness,
      style: widget.style,
      isPaper: widget.isPaper,
    );
    if (_highlighted != null) return;
    unawaited(
      loadSyntaxHighlightedTextSpan(
        code: widget.code,
        language: widget.language,
        brightness: widget.brightness,
        style: widget.style,
        isPaper: widget.isPaper,
        isCancelled: () => !mounted || request != _request,
      ).then<void>(
        (span) {
          if (span != null && mounted && request == _request) {
            setState(() => _highlighted = span);
          }
        },
        onError: (Object _, StackTrace __) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: widget.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text.rich(
            _highlighted ?? TextSpan(text: widget.code, style: widget.style),
            softWrap: false,
          ),
        ),
      );
}

class _NativeImage extends StatefulWidget {
  const _NativeImage({
    required this.uri,
    required this.alt,
    required this.width,
    required this.baseDirectory,
    required this.muted,
  });

  final Uri uri;
  final String alt;
  final double? width;
  final String baseDirectory;
  final Color muted;

  @override
  State<_NativeImage> createState() => _NativeImageState();
}

class _NativeImageState extends State<_NativeImage> {
  Future<File?>? _localFile;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _NativeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.baseDirectory != widget.baseDirectory) {
      _resolve();
    }
  }

  void _resolve() {
    _localFile = null;
    _bytes = null;
    if (widget.uri.isScheme('file')) {
      _localFile = _containedImageFile(widget.uri, widget.baseDirectory);
    } else if (widget.uri.isScheme('data')) {
      try {
        _bytes = widget.uri.data?.contentAsBytes();
      } on Object {
        _bytes = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (widget.uri.isScheme('file')) {
      image = FutureBuilder<File?>(
        future: _localFile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          final file = snapshot.data;
          if (file == null) return _placeholder();
          return _isSvg(file.path)
              ? SvgPicture.file(
                  file,
                  width: widget.width,
                  semanticsLabel: _label,
                  excludeFromSemantics: _label == null,
                  errorBuilder: _error,
                )
              : Image.file(
                  file,
                  width: widget.width,
                  fit: BoxFit.contain,
                  semanticLabel: _label,
                  excludeFromSemantics: _label == null,
                  errorBuilder: _error,
                );
        },
      );
    } else if (widget.uri.isScheme('data')) {
      final bytes = _bytes;
      image = bytes == null
          ? _placeholder()
          : Image.memory(
              bytes,
              width: widget.width,
              fit: BoxFit.contain,
              semanticLabel: _label,
              excludeFromSemantics: _label == null,
              errorBuilder: _error,
            );
    } else {
      final url = widget.uri.toString();
      image = _isSvg(widget.uri.path)
          ? SvgPicture.network(
              url,
              width: widget.width,
              semanticsLabel: _label,
              excludeFromSemantics: _label == null,
              errorBuilder: _error,
            )
          : Image.network(
              url,
              width: widget.width,
              fit: BoxFit.contain,
              semanticLabel: _label,
              excludeFromSemantics: _label == null,
              // Badge services serve SVG from extensionless URLs.
              errorBuilder: (context, error, stackTrace) => SvgPicture.network(
                url,
                width: widget.width,
                semanticsLabel: _label,
                excludeFromSemantics: _label == null,
                errorBuilder: _error,
              ),
            );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(6), child: image);
  }

  /// Images without alt text are decorative, as with HTML's `alt=""`.
  String? get _label {
    final alt = widget.alt.trim();
    return alt.isEmpty ? null : alt;
  }

  bool _isSvg(String path) => p.url.extension(path).toLowerCase() == '.svg';

  Widget _error(BuildContext context, Object error, StackTrace? stackTrace) =>
      _placeholder();

  Widget _placeholder() {
    final alt = widget.alt.trim();
    final label = alt.isNotEmpty || widget.uri.isScheme('data')
        ? alt
        : p.url.basename(widget.uri.path);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 16, color: widget.muted),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: widget.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
