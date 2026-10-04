import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as markdown;

/// Passive, text-only archival markup. Allowlisting elements AND discarding
/// all attributes prevents scripts, forms, event handlers, CSS, embeds,
/// javascript URLs and remote assets from surviving into an offline copy.
String passiveBookmarkHtml(String source) {
  final document = html.parse(source);
  const remove = 'script,style,noscript,template,iframe,object,embed,form,'
      'input,textarea,select,button,svg,canvas,img,video,audio,source,link,meta,base';
  for (final node in document.querySelectorAll(remove)) {
    node.remove();
  }
  const allowed = {
    'html',
    'head',
    'title',
    'body',
    'article',
    'main',
    'div',
    'span',
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'li',
    'blockquote',
    'pre',
    'code',
    'strong',
    'em',
    'b',
    'i',
    'br',
    'hr',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
  };
  for (final node in document.querySelectorAll('*').reversed) {
    if (node.attributes.containsKey('hidden') ||
        node.attributes['aria-hidden'] == 'true' ||
        RegExp(
          r'display\s*:\s*none|visibility\s*:\s*hidden',
          caseSensitive: false,
        ).hasMatch(node.attributes['style'] ?? '')) {
      node.remove();
    } else if (!allowed.contains(node.localName)) {
      node.replaceWith(
        dom.Element.tag('span')..nodes.addAll(node.nodes.toList()),
      );
    } else {
      node.attributes.clear();
    }
  }
  return document.outerHtml;
}

/// Decode Markdown as data, never a browser document. Even legacy snapshots
/// with remote images or raw active HTML cannot trigger any resource loading.
String bookmarkArticleText(String source) {
  final document =
      html.parse(passiveBookmarkHtml(markdown.markdownToHtml(source)));
  final buffer = StringBuffer();
  const blocks = {
    'p',
    'div',
    'article',
    'main',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'pre',
    'blockquote',
    'tr',
  };
  void visit(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text);
    } else if (node is dom.Element) {
      if (node.localName == 'br') buffer.writeln();
      for (final child in node.nodes) {
        visit(child);
      }
      if (blocks.contains(node.localName)) buffer.write('\n\n');
      if (node.localName == 'td' || node.localName == 'th') buffer.write('  ');
    }
  }

  if (document.body != null) visit(document.body!);
  return buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Source attribution is useful offline; URL credentials/tokens are not.
String bookmarkPublicSource(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) return '';
  // replace(query: '', fragment: '') retains empty ?/# delimiters in Dart.
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}
