// Drawing a notebook's prose.
//
// Markdown cells, `text/html` outputs and `text/markdown` outputs are rendered
// with real Flutter widgets rather than shown as source. A notebook's prose is
// half markdown and half raw HTML — `<div class="alert">`, `<img>`, `<table>`,
// `<details>` — so a renderer that only understands markdown shows the tags
// verbatim, which is exactly what a reader is not asking for.
//
// Nothing is executed: no scripts, no stylesheets, no frames. The markup is
// parsed and mapped onto widgets, so the page cannot do anything but be read.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../code_block_chrome.dart';

/// Elements that are dropped outright: they either run code, load something
/// from elsewhere, or take input a reader never asked to give.
const Set<String> _ignoredElements = {
  'script',
  'style',
  'link',
  'meta',
  'iframe',
  'frame',
  'frameset',
  'object',
  'embed',
  'applet',
  'form',
  'input',
  'button',
  'select',
  'textarea',
  'noscript',
  'base',
};

/// Renders one piece of notebook prose.
class NotebookMarkup extends StatefulWidget {
  const NotebookMarkup({
    super.key,
    required this.source,
    required this.palette,
    this.isHtml = false,
    this.baseDirectory,
    this.attachments,
    this.textScale = 1,
  });

  /// Markdown, or HTML when [isHtml] is set.
  final String source;

  final CodeBlockPalette palette;

  final bool isHtml;

  /// Where relative image paths point, normally the notebook's own folder.
  final String? baseDirectory;

  /// Images stored inside the cell, addressed as `attachment:name`.
  final Map<String, dynamic>? attachments;

  final double textScale;

  @override
  State<NotebookMarkup> createState() => _NotebookMarkupState();
}

class _NotebookMarkupState extends State<NotebookMarkup> {
  final List<GestureRecognizer> _recognizers = [];
  List<Widget> _blocks = const [];
  Brightness _brightness = Brightness.light;
  bool _isPaper = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _brightness = Theme.of(context).brightness;
    _isPaper = PaperTheme.isEnabled(context);
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant NotebookMarkup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.isHtml != widget.isHtml ||
        oldWidget.textScale != widget.textScale ||
        oldWidget.palette != widget.palette) {
      _rebuild();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _rebuild() {
    _disposeRecognizers();
    _blocks = NotebookMarkupBuilder(
      palette: widget.palette,
      brightness: _brightness,
      isPaper: _isPaper,
      baseDirectory: widget.baseDirectory,
      attachments: widget.attachments,
      textScale: widget.textScale,
      recognizers: _recognizers,
    ).build(widget.source, isHtml: widget.isHtml);
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _blocks,
    );
  }
}

/// Turns markdown or HTML into the widgets a notebook cell shows.
///
/// Kept separate from the widget so the mapping can be exercised on its own.
class NotebookMarkupBuilder {
  NotebookMarkupBuilder({
    required this.palette,
    required this.brightness,
    required this.isPaper,
    required this.recognizers,
    this.baseDirectory,
    this.attachments,
    this.textScale = 1,
  });

  final CodeBlockPalette palette;
  final Brightness brightness;
  final bool isPaper;
  final String? baseDirectory;
  final Map<String, dynamic>? attachments;
  final double textScale;
  final List<GestureRecognizer> recognizers;

  late List<String> _math = const [];

  double get _bodySize => 14.5 * textScale;

  TextStyle get _bodyStyle => TextStyle(
        color: palette.textPrimary,
        fontSize: _bodySize,
        height: 1.62,
      );

  TextStyle get _monoStyle => codeUiTextStyle(
        color: palette.textPrimary,
        fontSize: _bodySize * 0.92,
        fontWeight: FontWeight.w500,
      );

  List<Widget> build(String source, {required bool isHtml}) {
    final String html;
    if (isHtml) {
      _math = const [];
      html = source;
    } else {
      final extracted = extractNotebookMath(source);
      _math = extracted.expressions;
      html = md.markdownToHtml(
        extracted.text,
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
    }
    final fragment = html_parser.parseFragment(html);
    return _blocks(fragment.nodes);
  }

  /// Walks a run of nodes, gathering loose inline content into paragraphs.
  List<Widget> _blocks(List<dom.Node> nodes) {
    final blocks = <Widget>[];
    final inline = <dom.Node>[];

    void flush() {
      if (inline.isEmpty) {
        return;
      }
      final spans = _spans(inline, _bodyStyle);
      inline.clear();
      if (spans.isEmpty) {
        return;
      }
      blocks.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4 * textScale),
          child: Text.rich(TextSpan(children: spans, style: _bodyStyle)),
        ),
      );
    }

    for (final node in nodes) {
      if (node is dom.Element && _ignoredElements.contains(node.localName)) {
        continue;
      }
      if (node is dom.Element && _isBlock(node.localName!)) {
        flush();
        final block = _block(node);
        if (block != null) {
          blocks.add(block);
        }
        continue;
      }
      if (node is dom.Text && node.text.trim().isEmpty) {
        continue;
      }
      inline.add(node);
    }
    flush();
    return blocks;
  }

  bool _isBlock(String name) => const {
        'h1', 'h2', 'h3', 'h4', 'h5', 'h6', //
        'p', 'ul', 'ol', 'pre', 'blockquote', 'hr', 'table', 'div', 'section',
        'article', 'header', 'footer', 'aside', 'main', 'center', 'details',
        'figure', 'dl', 'dt', 'dd', 'address', 'nav', 'summary', 'svg',
      }.contains(name);

  Widget? _block(dom.Element element) {
    final name = element.localName ?? '';
    switch (name) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _heading(element, int.parse(name.substring(1)));
      case 'p':
        final spans = _spans(element.nodes, _bodyStyle);
        if (spans.isEmpty) {
          return null;
        }
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 4 * textScale),
          child: Text.rich(TextSpan(children: spans, style: _bodyStyle)),
        );
      case 'ul':
      case 'ol':
        return _list(element, ordered: name == 'ol');
      case 'pre':
        return _codeBlock(element);
      case 'blockquote':
        return _quote(element);
      case 'hr':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, thickness: 1, color: palette.divider),
        );
      case 'table':
        return _table(element);
      case 'svg':
        return _svg(element.outerHtml);
      case 'figure':
      case 'div':
      case 'section':
      case 'article':
      case 'header':
      case 'footer':
      case 'aside':
      case 'main':
      case 'nav':
      case 'address':
      case 'center':
        return _container(element);
      case 'details':
        return _details(element);
      case 'summary':
      case 'dt':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text.rich(
            TextSpan(
              children: _spans(
                element.nodes,
                _bodyStyle.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
      case 'dl':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: _blocks(element.nodes),
        );
      case 'dd':
        return Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _blocks(element.nodes),
          ),
        );
      default:
        return null;
    }
  }

  Widget _heading(dom.Element element, int level) {
    final sizes = [1.72, 1.4, 1.18, 1.05, 0.96, 0.9];
    final style = _bodyStyle.copyWith(
      fontSize: _bodySize * sizes[(level - 1).clamp(0, 5)],
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.2,
    );
    return Padding(
      padding: EdgeInsets.only(top: level <= 2 ? 18 : 14, bottom: 6),
      child: Text.rich(TextSpan(children: _spans(element.nodes, style))),
    );
  }

  Widget _list(dom.Element element, {required bool ordered}) {
    final items = element.children
        .where((child) => child.localName == 'li')
        .toList(growable: false);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
    final markerStyle = _bodyStyle.copyWith(color: palette.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26 * textScale,
                    child: Padding(
                      padding: EdgeInsets.only(top: 3 * textScale, right: 6),
                      child: Text(
                        ordered ? '${start + index}.' : '•',
                        textAlign: TextAlign.right,
                        style: markerStyle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: _blocks(items[index].nodes),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _codeBlock(dom.Element element) {
    final code = element.children.isNotEmpty &&
            element.children.first.localName == 'code'
        ? element.children.first
        : element;
    final language = code.className
        .split(RegExp(r'\s+'))
        .firstWhere(
          (name) => name.startsWith('language-'),
          orElse: () => '',
        )
        .replaceFirst('language-', '');
    final text = code.text.trimRight();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.terminal,
        borderRadius: BorderRadius.circular(codeSurfaceRadius),
      ),
      child: Text.rich(
        buildSyntaxHighlightedTextSpan(
          code: text,
          language: language,
          brightness: brightness,
          isPaper: isPaper,
          style: _monoStyle,
        ),
      ),
    );
  }

  Widget _quote(dom.Element element) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: palette.accent.withValues(alpha: 0.5),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: _blocks(element.nodes),
        ),
      );

  Widget _details(dom.Element element) {
    final summary = element.children
        .where((child) => child.localName == 'summary')
        .toList(growable: false);
    final body = element.nodes
        .where((node) => node is! dom.Element || node.localName != 'summary')
        .toList(growable: false);
    return NotebookDisclosure(
      palette: palette,
      summary: Text.rich(
        TextSpan(
          children: _spans(
            summary.isEmpty ? const [] : summary.first.nodes,
            _bodyStyle.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      children: _blocks(body),
    );
  }

  /// A `div` is usually just grouping — unless it is one of the callouts a
  /// notebook writer reaches for, which deserve to look like callouts.
  Widget _container(dom.Element element) {
    final children = _blocks(element.nodes);
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final accent = _calloutColor(element.className);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    if (accent == null) {
      return body;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: brightness == Brightness.dark ? 0.14 : 0.1,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: body,
    );
  }

  /// The Bootstrap alert palette notebooks are written against.
  Color? _calloutColor(String className) {
    final classes = className.toLowerCase();
    if (!classes.contains('alert') &&
        !classes.contains('admonition') &&
        !classes.contains('callout')) {
      return null;
    }
    if (classes.contains('success') || classes.contains('tip')) {
      return palette.success;
    }
    if (classes.contains('danger') || classes.contains('error')) {
      return palette.error;
    }
    if (classes.contains('warning') || classes.contains('caution')) {
      return const Color(0xFFD9A441);
    }
    return palette.accent;
  }

  Widget _table(dom.Element element) {
    final rows = <List<dom.Element>>[];
    final headerFlags = <bool>[];
    for (final row in element.querySelectorAll('tr')) {
      final cells = row.children
          .where(
            (cell) => cell.localName == 'td' || cell.localName == 'th',
          )
          .toList(growable: false);
      if (cells.isEmpty) {
        continue;
      }
      rows.add(cells);
      headerFlags.add(cells.every((cell) => cell.localName == 'th'));
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final columns = rows.fold<int>(
      0,
      (widest, row) => row.length > widest ? row.length : widest,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(color: palette.divider, width: 0.7),
          ),
          children: [
            for (var index = 0; index < rows.length; index++)
              TableRow(
                decoration: BoxDecoration(
                  color: headerFlags[index]
                      ? palette.hover
                      : index.isOdd
                          ? palette.hover.withValues(alpha: 0.35)
                          : null,
                ),
                children: [
                  for (var column = 0; column < columns; column++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: column < rows[index].length
                          ? Text.rich(
                              TextSpan(
                                children: _spans(
                                  rows[index][column].nodes,
                                  headerFlags[index]
                                      ? _bodyStyle.copyWith(
                                          fontWeight: FontWeight.w700,
                                        )
                                      : _bodyStyle,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _spans(List<dom.Node> nodes, TextStyle style) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        spans.addAll(_textSpans(node.text, style));
        continue;
      }
      if (node is! dom.Element) {
        continue;
      }
      final name = node.localName ?? '';
      if (_ignoredElements.contains(name)) {
        continue;
      }
      switch (name) {
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        case 'strong':
        case 'b':
          spans.addAll(
            _spans(node.nodes, style.copyWith(fontWeight: FontWeight.w700)),
          );
        case 'em':
        case 'i':
        case 'cite':
        case 'var':
          spans.addAll(
            _spans(node.nodes, style.copyWith(fontStyle: FontStyle.italic)),
          );
        case 'del':
        case 's':
        case 'strike':
          spans.addAll(
            _spans(
              node.nodes,
              style.copyWith(decoration: TextDecoration.lineThrough),
            ),
          );
        case 'u':
        case 'ins':
          spans.addAll(
            _spans(
              node.nodes,
              style.copyWith(decoration: TextDecoration.underline),
            ),
          );
        case 'mark':
          spans.addAll(
            _spans(
              node.nodes,
              style.copyWith(
                backgroundColor: palette.accent.withValues(alpha: 0.22),
              ),
            ),
          );
        case 'code':
        case 'kbd':
        case 'samp':
        case 'tt':
          spans.add(
            TextSpan(
              text: node.text,
              style: _monoStyle.copyWith(
                fontSize: style.fontSize == null
                    ? _monoStyle.fontSize
                    : style.fontSize! * 0.92,
                color: palette.accent,
                background: Paint()..color = palette.input,
              ),
            ),
          );
        case 'a':
          spans.addAll(_link(node, style));
        case 'img':
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _image(node),
            ),
          );
        case 'svg':
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _svg(node.outerHtml),
            ),
          );
        case 'sub':
        case 'sup':
          spans.addAll(
            _spans(
              node.nodes,
              style.copyWith(
                fontSize: (style.fontSize ?? _bodySize) * 0.75,
              ),
            ),
          );
        default:
          spans.addAll(_spans(node.nodes, style));
      }
    }
    return spans;
  }

  List<InlineSpan> _link(dom.Element element, TextStyle style) {
    final href = element.attributes['href'] ?? '';
    final linkStyle = style.copyWith(
      color: palette.accent,
      decoration: TextDecoration.underline,
      decorationColor: palette.accent.withValues(alpha: 0.5),
    );
    final body = _spans(element.nodes, linkStyle);
    if (href.isEmpty) {
      return body;
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () => afLaunchUrlString(href, addingHttpSchemeWhenFailed: true);
    recognizers.add(recognizer);
    // Hit testing resolves to the innermost span, so the recognizer has to be
    // on the spans that actually carry the text.
    return [for (final span in body) _withRecognizer(span, recognizer)];
  }

  InlineSpan _withRecognizer(InlineSpan span, GestureRecognizer recognizer) {
    if (span is! TextSpan) {
      return span;
    }
    return TextSpan(
      text: span.text,
      style: span.style,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.click,
      children: span.children
          ?.map((child) => _withRecognizer(child, recognizer))
          .toList(),
    );
  }

  Widget _svg(String source) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: SvgPicture.string(
          source,
          errorBuilder: (context, error, stackTrace) => _brokenMedia('SVG'),
        ),
      );

  Widget _image(dom.Element element) {
    final source = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    final width = double.tryParse(element.attributes['width'] ?? '');
    final image = _imageFor(source, alt);
    if (image == null) {
      return _brokenMedia(alt.isEmpty ? 'image' : alt);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: 460,
          maxWidth: width ?? double.infinity,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: image,
        ),
      ),
    );
  }

  Widget? _imageFor(String source, String alt) {
    if (source.isEmpty) {
      return null;
    }
    final label = alt.isEmpty ? 'image' : alt;
    Widget broken(BuildContext _, Object __, StackTrace? ___) =>
        _brokenMedia(label);

    if (source.startsWith('data:')) {
      final bytes = decodeDataUri(source);
      if (bytes == null) {
        return null;
      }
      return Image.memory(bytes, errorBuilder: broken);
    }
    if (source.startsWith('attachment:')) {
      final name = source.substring('attachment:'.length);
      final bundle = attachments?[name];
      if (bundle is Map) {
        for (final entry in bundle.entries) {
          final decoded = decodeBase64(entry.value?.toString() ?? '');
          if (decoded != null) {
            return Image.memory(decoded, errorBuilder: broken);
          }
        }
      }
      return null;
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return _NetworkMarkupImage(source: source, broken: _brokenMedia(label));
    }
    final directory = baseDirectory;
    if (directory == null) {
      return null;
    }
    final path = p.isAbsolute(source) ? source : p.join(directory, source);
    return Image.file(File(path), errorBuilder: broken);
  }

  Widget _brokenMedia(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: palette.input,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_rounded,
              size: 14,
              color: palette.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: _bodyStyle.copyWith(
                fontSize: _bodySize * 0.86,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      );

  /// Splits plain text around the maths that was lifted out of the markdown.
  List<InlineSpan> _textSpans(String text, TextStyle style) {
    if (_math.isEmpty || !text.contains(notebookMathToken)) {
      return [TextSpan(text: text, style: style)];
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in notebookMathPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, match.start), style: style),
        );
      }
      final index = int.parse(match.group(1)!);
      if (index < _math.length) {
        spans.add(_mathSpan(_math[index], style));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return spans;
  }

  InlineSpan _mathSpan(String expression, TextStyle style) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          expression,
          textStyle: style,
          mathStyle: MathStyle.text,
          onErrorFallback: (error) => Text(
            expression,
            style: _monoStyle.copyWith(color: palette.textSecondary),
          ),
        ),
      );
}

/// A `<details>` block, opened and closed by its own summary row.
///
/// Material's `ExpansionTile` brings a whole theme with it, which would reset
/// the typography the rest of the cell is set in.
class NotebookDisclosure extends StatefulWidget {
  const NotebookDisclosure({
    super.key,
    required this.palette,
    required this.summary,
    required this.children,
  });

  final CodeBlockPalette palette;
  final Widget summary;
  final List<Widget> children;

  @override
  State<NotebookDisclosure> createState() => _NotebookDisclosureState();
}

class _NotebookDisclosureState extends State<NotebookDisclosure> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          borderRadius: BorderRadius.circular(7),
          hoverColor: widget.palette.hover,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: codeBlockAnimationDuration,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: widget.palette.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(child: widget.summary),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 22, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

/// A picture from the web, decoded by what it actually is.
///
/// A README's badges come from addresses with no extension that answer with
/// SVG, which the bitmap decoder cannot read — so the payload decides, not the
/// address. Nothing is executed: an SVG is drawn by the vector renderer.
class _NetworkMarkupImage extends StatefulWidget {
  const _NetworkMarkupImage({required this.source, required this.broken});

  final String source;
  final Widget broken;

  /// A page of badges must not be fetched again on every theme change.
  static final Map<String, _FetchedImage?> _cache = {};
  static const _maximumCached = 96;
  static const _maximumBytes = 4 << 20;

  @override
  State<_NetworkMarkupImage> createState() => _NetworkMarkupImageState();
}

@immutable
class _FetchedImage {
  const _FetchedImage({required this.bytes, required this.isSvg});

  final Uint8List bytes;
  final bool isSvg;
}

class _NetworkMarkupImageState extends State<_NetworkMarkupImage> {
  _FetchedImage? image;
  bool settled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    if (_NetworkMarkupImage._cache.containsKey(widget.source)) {
      setState(() {
        image = _NetworkMarkupImage._cache[widget.source];
        settled = true;
      });
      return;
    }

    _FetchedImage? fetched;
    try {
      final response = await http
          .get(Uri.parse(widget.source))
          .timeout(const Duration(seconds: 12));
      final bytes = response.bodyBytes;
      if (response.statusCode == 200 &&
          bytes.isNotEmpty &&
          bytes.length <= _NetworkMarkupImage._maximumBytes) {
        fetched = _FetchedImage(
          bytes: bytes,
          isSvg: _looksLikeSvg(response.headers['content-type'], bytes),
        );
      }
    } catch (error) {
      Log.debug('Unable to read a picture in some markup: $error');
    }

    if (_NetworkMarkupImage._cache.length >=
        _NetworkMarkupImage._maximumCached) {
      _NetworkMarkupImage._cache.remove(_NetworkMarkupImage._cache.keys.first);
    }
    _NetworkMarkupImage._cache[widget.source] = fetched;
    if (mounted) {
      setState(() {
        image = fetched;
        settled = true;
      });
    }
  }

  /// The declared type first, then the payload's own opening.
  ///
  /// Merely containing `<svg>` is not enough — a sign-in page redirected to
  /// from a picture's address would match that.
  static bool _looksLikeSvg(String? contentType, Uint8List bytes) {
    if (contentType != null && contentType.contains('image/svg')) {
      return true;
    }
    final head = const Utf8Decoder(allowMalformed: true)
        .convert(bytes.sublist(0, bytes.length < 128 ? bytes.length : 128))
        .trimLeft()
        .toLowerCase();
    return head.startsWith('<svg') || head.startsWith('<?xml');
  }

  @override
  Widget build(BuildContext context) {
    final fetched = image;
    if (fetched == null) {
      return settled ? widget.broken : const SizedBox(width: 1, height: 18);
    }
    if (fetched.isSvg) {
      return SvgPicture.memory(
        fetched.bytes,
        errorBuilder: (context, error, stackTrace) => widget.broken,
      );
    }
    return Image.memory(
      fetched.bytes,
      errorBuilder: (context, error, stackTrace) => widget.broken,
    );
  }
}

/// The placeholder a lifted maths expression leaves behind.
const String notebookMathToken = 'AFNBMATH';

final RegExp notebookMathPattern = RegExp('$notebookMathToken(\\d+)ENDMATH');

/// Markdown with its maths lifted out.
@immutable
class NotebookMathExtraction {
  const NotebookMathExtraction(this.text, this.expressions);

  final String text;
  final List<String> expressions;
}

/// Takes `$…$`, `$$…$$`, `\(…\)` and `\[…\]` out of the markdown before it is
/// converted.
///
/// The markdown converter would otherwise read `x_1` as emphasis and `\\` as
/// an escape, so the expression that reaches the renderer is no longer the one
/// that was written. Code spans and fences are left alone: a dollar sign in a
/// shell snippet is a prompt, not an equation.
NotebookMathExtraction extractNotebookMath(String source) {
  final expressions = <String>[];
  final buffer = StringBuffer();
  var index = 0;

  String token(String expression) {
    expressions.add(expression);
    return '$notebookMathToken${expressions.length - 1}ENDMATH';
  }

  while (index < source.length) {
    final character = source[index];

    // A fenced block runs to its closing fence, whatever it holds.
    if ((character == '`' || character == '~') &&
        (index == 0 || source[index - 1] == '\n') &&
        index + 2 < source.length &&
        source[index + 1] == character &&
        source[index + 2] == character) {
      final fence = character * 3;
      final end = source.indexOf('\n$fence', index + 3);
      final stop = end == -1 ? source.length : end + fence.length + 1;
      buffer.write(source.substring(index, stop));
      index = stop;
      continue;
    }

    // An inline code span runs to the matching run of backticks.
    if (character == '`') {
      var ticks = 0;
      while (index + ticks < source.length && source[index + ticks] == '`') {
        ticks++;
      }
      final marker = '`' * ticks;
      final end = source.indexOf(marker, index + ticks);
      final stop = end == -1 ? source.length : end + ticks;
      buffer.write(source.substring(index, stop));
      index = stop;
      continue;
    }

    if (character == r'\' && index + 1 < source.length) {
      final next = source[index + 1];
      if (next == '[' || next == '(') {
        final closing = next == '[' ? r'\]' : r'\)';
        final end = source.indexOf(closing, index + 2);
        if (end != -1) {
          buffer.write(token(source.substring(index + 2, end).trim()));
          index = end + 2;
          continue;
        }
      }
      // An escaped character is copied through, escape and all.
      buffer.write(source.substring(index, index + 2));
      index += 2;
      continue;
    }

    if (character == r'$') {
      final isDisplay = index + 1 < source.length && source[index + 1] == r'$';
      final marker = isDisplay ? r'$$' : r'$';
      final start = index + marker.length;
      final end = source.indexOf(marker, start);
      if (end != -1 && end > start) {
        final body = source.substring(start, end);
        final isMath = isDisplay ||
            (!body.contains('\n\n') &&
                body.trim().isNotEmpty &&
                !body.startsWith(' ') &&
                !body.endsWith(' '));
        if (isMath) {
          buffer.write(token(body.trim()));
          index = end + marker.length;
          continue;
        }
      }
    }

    buffer.write(character);
    index++;
  }

  return NotebookMathExtraction(buffer.toString(), expressions);
}

/// Bytes of a `data:` URI, or null when it holds nothing readable.
Uint8List? decodeDataUri(String source) {
  final separator = source.indexOf(',');
  if (separator == -1) {
    return null;
  }
  final header = source.substring(0, separator);
  final payload = source.substring(separator + 1);
  if (!header.contains(';base64')) {
    return Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
  }
  return decodeBase64(payload);
}

/// Base64 as notebooks store it: wrapped over many lines.
Uint8List? decodeBase64(String source) {
  final cleaned = source.replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) {
    return null;
  }
  try {
    return base64Decode(cleaned);
  } on FormatException {
    return null;
  }
}
