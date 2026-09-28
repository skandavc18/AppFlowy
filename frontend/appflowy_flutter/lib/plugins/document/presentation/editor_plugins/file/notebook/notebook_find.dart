import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import 'notebook_document.dart';
import 'notebook_markup.dart';

typedef NotebookFindId = ({String cellId, int output, String part});

NotebookFindId notebookSourceFindId(String cellId) =>
    (cellId: cellId, output: -1, part: 'source');

NotebookFindId notebookOutputFindId(String cellId, int output, String part) =>
    (cellId: cellId, output: output, part: part);

/// One native text field, possibly containing several rendered paragraphs.
/// Search each paragraph separately, as the shared native painter does. Shift
/// offsets into the field for stable navigation, never for JSON replacement.
class NotebookFindField {
  NotebookFindField(this.id, this.paragraphs)
      : entry = SurfaceFindEntry(id, paragraphs.join('\n'));

  final NotebookFindId id;
  final List<String> paragraphs;
  final SurfaceFindEntry entry;

  Iterable<SurfaceFindMatch> search(String query, FindOptions options) sync* {
    var offset = 0;
    for (final paragraph in paragraphs) {
      for (final hit in searchSurfaceEntries(
        [SurfaceFindEntry(id, paragraph)],
        query,
        options,
      )) {
        yield SurfaceFindMatch(
          entry,
          _NotebookParagraphMatch(hit.range, entry.text, offset),
        );
      }
      offset += paragraph.length + 1;
    }
  }
}

class _NotebookParagraphMatch implements RegExpMatch {
  _NotebookParagraphMatch(this.original, this.input, this.offset);

  final RegExpMatch original;
  final int offset;

  @override
  final String input;
  @override
  int get start => original.start + offset;
  @override
  int get end => original.end + offset;
  @override
  RegExp get pattern => original.pattern;
  @override
  int get groupCount => original.groupCount;
  @override
  Iterable<String> get groupNames => original.groupNames;
  @override
  String? group(int group) => original.group(group);
  @override
  String? operator [](int group) => original[group];
  @override
  List<String?> groups(List<int> groupIndices) => original.groups(groupIndices);
  @override
  String? namedGroup(String name) => original.namedGroup(name);
}

/// Mirrors the renderer's MIME precedence. Hidden fallbacks, metadata,
/// attachments, image/SVG payloads and serialized output objects are never
/// entries. This only reads the already-loaded document; it performs no I/O.
List<NotebookFindField> notebookOutputFindFields(
  String cellId,
  int index,
  NotebookOutput output,
) {
  NotebookFindField field(String part, List<String> text) => NotebookFindField(
        notebookOutputFindId(cellId, index, part),
        text,
      );
  if (output.isEmpty) return const [];
  if (output.isError) {
    return [
      field('error', [
        [output.errorName, output.errorValue]
            .where((part) => part.isNotEmpty)
            .join(': '),
      ]),
      if (output.traceback.isNotEmpty) field('traceback', [output.errorText]),
    ];
  }
  if (output.kind == NotebookOutputKind.stream) {
    return [
      field('text', [output.text.trimRight()]),
    ];
  }
  final image = output.image;
  if (image != null && decodeBase64(image.value) != null) return const [];
  if (output.svg?.trim().isNotEmpty == true) return const [];
  final html = output.html;
  final markdown = output.markdown ?? output.latex;
  final isHtml = html?.trim().isNotEmpty == true;
  final markup = isHtml ? html : markdown;
  if (markup != null && markup.trim().isNotEmpty) {
    return [
      field(
        'markup',
        notebookMarkupFindParagraphs(
          markup,
          isHtml: isHtml,
        ),
      ),
    ];
  }
  return [
    field('text', [output.plainText ?? '']),
  ];
}

/// The text grouping used by NotebookMarkupBuilder, without constructing its
/// widgets: even constructing styled code can request a font. Parse only this
/// output's chosen markup representation; never visit attributes or MIME data.
/// Live native paragraphs replace this off-screen projection after layout.
List<String> notebookMarkupFindParagraphs(
  String source, {
  required bool isHtml,
}) {
  final math = isHtml ? null : extractNotebookMath(source);
  final html = isHtml
      ? source
      : md.markdownToHtml(math!.text, extensionSet: md.ExtensionSet.gitHubWeb);
  final projection = _NotebookMarkupText(math?.expressions.length ?? 0);
  projection.blocks(html_parser.parseFragment(html).nodes);
  return projection.paragraphs;
}

class _NotebookMarkupText {
  _NotebookMarkupText(this.mathCount);

  final int mathCount;
  final paragraphs = <String>[];

  // Keep in step with NotebookMarkupBuilder's inert element and block sets.
  static const ignored = {
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
  static const blockNames = {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'p',
    'ul',
    'ol',
    'pre',
    'blockquote',
    'hr',
    'table',
    'div',
    'section',
    'article',
    'header',
    'footer',
    'aside',
    'main',
    'center',
    'details',
    'figure',
    'dl',
    'dt',
    'dd',
    'address',
    'nav',
    'summary',
    'svg',
  };

  void blocks(List<dom.Node> nodes) {
    final inline = <dom.Node>[];
    void flush() {
      if (inline.isEmpty) return;
      final text = spans(inline);
      if (text.isNotEmpty) paragraphs.add(text);
      inline.clear();
    }

    for (final node in nodes) {
      if (node is dom.Element && ignored.contains(node.localName)) continue;
      if (node is dom.Element && blockNames.contains(node.localName)) {
        flush();
        block(node);
      } else if (node is! dom.Text || node.text.trim().isNotEmpty) {
        inline.add(node);
      }
    }
    flush();
  }

  String spans(List<dom.Node> nodes) {
    final text = StringBuffer();
    for (final node in nodes) {
      if (node is dom.Text) {
        text.write(
          mathCount == 0
              ? node.text
              : node.text.replaceAllMapped(notebookMathPattern, (match) {
                  return int.parse(match.group(1)!) < mathCount ? '\uFFFC' : '';
                }),
        );
      } else if (node is dom.Element && !ignored.contains(node.localName)) {
        switch (node.localName) {
          case 'br':
            text.write('\n');
          case 'img':
          case 'svg':
            // The same non-text placeholder as RenderParagraph.toPlainText;
            // no image name, alternative label, URL or bytes enter the index.
            text.write('\uFFFC');
          case 'code':
          case 'kbd':
          case 'samp':
          case 'tt':
            text.write(node.text);
          default:
            text.write(spans(node.nodes));
        }
      }
    }
    return text.toString();
  }

  void block(dom.Element element) {
    switch (element.localName) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
      case 'p':
      case 'summary':
      case 'dt':
        paragraphs.add(spans(element.nodes));
      case 'ul':
      case 'ol':
        final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
        var index = 0;
        for (final item
            in element.children.where((node) => node.localName == 'li')) {
          paragraphs.add(element.localName == 'ol' ? '${start + index}.' : '•');
          blocks(item.nodes);
          index++;
        }
      case 'pre':
        final code = element.children.firstOrNull?.localName == 'code'
            ? element.children.first
            : element;
        paragraphs.add(code.text.trimRight());
      case 'table':
        for (final row in element.querySelectorAll('tr')) {
          for (final cell in row.children) {
            if (cell.localName == 'td' || cell.localName == 'th') {
              paragraphs.add(spans(cell.nodes));
            }
          }
        }
      case 'details':
        final summary = element.children
            .where((node) => node.localName == 'summary')
            .firstOrNull;
        paragraphs.add(summary == null ? '' : spans(summary.nodes));
      // Its body is not displayed until opened by the reader. The live
      // observer updates this field without changing disclosure state.
      case 'hr':
      case 'svg':
        break;
      default:
        blocks(element.nodes);
    }
  }
}

/// Observes only the owned rich-text output. This keeps opened disclosures in
/// the model without rebuilding/reparenting the original NotebookMarkup.
/// Highlighting and word reveal remain entirely SurfaceFindTarget's job.
class NotebookFindRenderedText extends SingleChildRenderObjectWidget {
  const NotebookFindRenderedText({
    super.key,
    required this.onParagraphs,
    required super.child,
  });

  final ValueChanged<List<String>> onParagraphs;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNotebookFindText(onParagraphs);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _RenderNotebookFindText).onParagraphs = onParagraphs;
  }
}

class _RenderNotebookFindText extends RenderProxyBox {
  _RenderNotebookFindText(this.onParagraphs);

  ValueChanged<List<String>> onParagraphs;
  List<String>? _last;
  int _epoch = 0;

  @override
  void performLayout() {
    super.performLayout();
    final paragraphs = <String>[];
    void visit(RenderObject object) {
      if (!object.attached || (object is RenderOffstage && object.offstage)) {
        return;
      }
      if (object is RenderParagraph) {
        paragraphs.add(object.text.toPlainText());
        return; // Do not descend into inline images/math/platform widgets.
      }
      object.visitChildren((child) {
        if (object.paintsChild(child)) visit(child);
      });
    }

    if (child != null) visit(child!);
    if (listEquals(_last, paragraphs)) return;
    _last = paragraphs;
    final epoch = ++_epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && epoch == _epoch) onParagraphs(paragraphs);
    });
  }

  @override
  void detach() {
    _epoch++;
    super.detach();
  }
}
