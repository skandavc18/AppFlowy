import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/native_markup_preview.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:path/path.dart' as p;

const _markdown = '''
# Title

Intro paragraph with a [link](https://example.com), a [bad link](javascript:alert(1)) and `code`.

- [x] Done task
- [ ] Open task

3. Third
4. Fourth

> Quoted text

| Name | Value |
|------|------:|
| a    | 1     |

```mermaid
graph TD
```

---

Closing words.
''';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  group('parsing', () {
    test('only raw HTML sends Markdown through the HTML converter', () {
      expect(markdownHasRawHtml('<p align="center">Logo</p>\n\n# Hi'), isTrue);
      expect(markdownHasRawHtml('Inline <b>bold</b> text'), isTrue);
      expect(markdownHasRawHtml('# Plain\n\nNo markup here.'), isFalse);
      expect(
        markdownHasRawHtml(
          'a < b and `x < y`\n\n```html\n<div>code</div>\n```\n\n'
          '<https://example.com>',
        ),
        isFalse,
      );
    });

    test("keeps a README's raw HTML header alongside its Markdown", () {
      final tree = _describe(
        parseNativeMarkup(
          '<p align="center">\n'
          '  <img src="logo.png" width="120px" alt="Logo">\n'
          '</p>\n\n'
          '# AppFlowy\n\n'
          '- [x] Shipped\n'
          '- [ ] Planned\n',
          NativeMarkupFormat.markdown,
        ),
      );
      expect(
        tree,
        contains('<p align=center><img src=logo.png alt=Logo width=120/></p>'),
      );
      expect(tree, contains('<h1>AppFlowy</h1>'));
      expect(tree, contains('<input type=checkbox checked=true/>'));
      expect(tree, contains('Shipped'));
      expect(tree, contains('Planned'));
    });

    test('decodes entities on both the Markdown and the HTML path', () {
      expect(
        _describe(
          parseNativeMarkup(
            'Fish &amp; chips &copy; 2024',
            NativeMarkupFormat.markdown,
          ),
        ),
        '<p>Fish & chips © 2024</p>',
      );
      expect(
        _describe(
          parseNativeMarkup(
            '<b>Fish &amp; chips</b> &lt;tag&gt;',
            NativeMarkupFormat.markdown,
          ),
        ),
        '<p><strong>Fish & chips</strong> <tag></p>',
      );
    });

    test('keeps the styling hooks of an alert exported from GitHub', () {
      final tree = _describe(
        parseNativeMarkup(
          '<div class="markdown-alert markdown-alert-note" style="x">'
          '<p class="markdown-alert-title" dir="auto">Note</p>'
          '<p class="lead">Useful <b>information</b>.</p></div>',
          NativeMarkupFormat.html,
        ),
      );
      expect(
        tree,
        '<div class=markdown-alert markdown-alert-note>'
        '<p class=markdown-alert-title>Note</p>'
        '<p>Useful <strong>information</strong>.</p></div>',
      );
    });

    test('drops what a page hides or runs', () {
      final tree = _describe(
        parseNativeMarkup(
          '<html><head><title>Page title</title><style>p{}</style></head>'
          '<body><script>alert(1)</script><p hidden>hidden text</p>'
          '<div style="color: red; display: none">invisible</div>'
          '<template>template</template><button>Press</button>'
          '<p>Visible <span>span</span></p></body></html>',
          NativeMarkupFormat.html,
        ),
      );
      expect(tree, '<p>Visible span</p>');
    });

    test('keeps preformatted text, its language and its line breaks', () {
      expect(
        _describe(
          parseNativeMarkup(
            '<pre class="language-dart"><code>void main() {}<br>'
            '// next</code></pre>',
            NativeMarkupFormat.html,
          ),
        ),
        '<pre><code class=language-dart>void main() {}\n// next</code></pre>',
      );
    });

    test('squares up ragged tables and keeps blocks inside cells apart', () {
      expect(
        _describe(
          parseNativeMarkup(
            '<table><caption>Cap</caption>'
            '<tr><th>A</th><th>B</th><th>C</th></tr>'
            '<tr><td colspan="2" align="right">wide</td></tr>'
            '<tr><td><p>one</p><p>two</p></td><td>x</td></tr>'
            '</table>',
            NativeMarkupFormat.html,
          ),
        ),
        '<p><em>Cap</em></p><table><tbody>'
        '<tr><th>A</th><th>B</th><th>C</th></tr>'
        '<tr><td align=right>wide</td><td></td></tr>'
        '<tr><td><appflowy-block-break/>one<appflowy-block-break/>'
        '<appflowy-block-break/>two<appflowy-block-break/></td><td>x</td></tr>'
        '</tbody></table>',
      );
    });

    test('nests stray lists under the item before them', () {
      expect(
        _describe(
          parseNativeMarkup(
            '<ul><li>a</li><ul><li>nested</li></ul><li>b</li></ul>'
            '<ol start="3"><li>three</li></ol><li>stray</li>',
            NativeMarkupFormat.html,
          ),
        ),
        '<ul><li>a<ul><li>nested</li></ul></li><li>b</li></ul>'
        '<ol start=3><li>three</li></ol><ul><li>stray</li></ul>',
      );
    });

    test('keeps alignment, checkboxes and inline formatting', () {
      expect(
        _describe(
          parseNativeMarkup(
            '<div align="center">centred</div><center>old</center>'
            '<div style="color: blue; text-align: end">right</div>'
            '<p><input type="checkbox" checked> done'
            '<input type="text" value="no"></p>'
            '<p><b>b</b><i>i</i><s>s</s><u>u</u><kbd>k</kbd><q>q</q>'
            '<a href="https://example.com">a</a><a>plain</a></p>',
            NativeMarkupFormat.html,
          ),
        ),
        '<div align=center>centred</div><div align=center>old</div>'
        '<div align=right>right</div>'
        '<p><input type=checkbox checked=true/> done</p>'
        '<p><strong>b</strong><em>i</em><del>s</del><u>u</u><code>k</code>'
        '“q”<a href=https://example.com>a</a>plain</p>',
      );
    });
  });

  group('image sources', () {
    const base = '/home/user/docs';
    String? resolve(String source) =>
        resolveNativeMarkupImageUri(source, base)?.toString();

    test('allows remote, raster data and contained relative images', () {
      expect(resolve('img/logo.png'), 'file:///home/user/docs/img/logo.png');
      expect(resolve('my%20logo.png'), 'file:///home/user/docs/my%20logo.png');
      expect(resolve('./a.png'), 'file:///home/user/docs/a.png');
      expect(resolve(r'img\logo.png'), 'file:///home/user/docs/img/logo.png');
      expect(resolve('a.png?raw=1'), 'file:///home/user/docs/a.png');
      expect(
        resolve(' https://example.com/a.png '),
        'https://example.com/a.png',
      );
      expect(resolve('data:image/png;base64,AAAA'), isNotNull);
    });

    test('refuses anything outside the document folder or not an image', () {
      for (final source in [
        '',
        '#fragment',
        '?query',
        '../secret.png',
        'sub/../../secret.png',
        '%2e%2e/secret.png',
        '/etc/passwd',
        'file:///etc/passwd',
        r'C:\secret.png',
        '//example.com/a.png',
        'http:///no-host.png',
        'javascript:alert(1)',
        'data:image/svg+xml;base64,AAAA',
        'data:text/html,<b>x</b>',
      ]) {
        expect(resolve(source), isNull, reason: source);
      }
    });
  });

  group('preview', () {
    for (final (name, brightness, paper) in [
      ('light', Brightness.light, false),
      ('dark', Brightness.dark, false),
      ('paper', Brightness.light, true),
    ]) {
      testWidgets('draws Markdown natively in $name mode', (tester) async {
        _tallView(tester);
        await tester.pumpWidget(
          _app(
            const NativeMarkupPreview(
              source: _markdown,
              format: NativeMarkupFormat.markdown,
              baseDirectory: '/tmp',
            ),
            brightness: brightness,
            paper: paper,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(_richText('Intro paragraph'), findsOneWidget);
        expect(_richText('Closing words.'), findsOneWidget);
        expect(_richText('Quoted text'), findsOneWidget);
        expect(_richText('graph TD'), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
        expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
        expect(
          find.byIcon(Icons.check_box_outline_blank_rounded),
          findsOneWidget,
        );
        expect(find.text('3.'), findsOneWidget);
        expect(find.text('4.'), findsOneWidget);

        expect(_span(tester, 'link').recognizer, isA<TapGestureRecognizer>());
        expect(_span(tester, 'bad link').recognizer, isNull);

        final theme = Theme.of(tester.element(find.byType(Scaffold)));
        final code = paper
            ? PaperTheme.codeBlockBackground
            : theme.colorScheme.surfaceContainer;
        expect(_codeBlockColors(tester), [code]);
        // The preview sits on the viewport's sheet instead of painting its
        // own, which keeps paper mode's warm surface.
        expect(
          find.descendant(
            of: find.byType(NativeMarkupPreview),
            matching: find.byWidgetPredicate(
              (widget) => widget is Material && widget.color != null,
            ),
          ),
          findsNothing,
        );
      });
    }

    testWidgets('colours a fenced block in a known language', (tester) async {
      const code = 'void nativeMarkupHighlight() => print(42);';
      await tester.pumpWidget(
        _app(
          const NativeMarkupPreview(
            source: '```dart\n$code\n```',
            format: NativeMarkupFormat.markdown,
            baseDirectory: '/tmp',
          ),
        ),
      );
      expect(_richText(code), findsOneWidget);
      await _settle(tester, () => _spanCount(tester, code) > 3);
      expect(_spanCount(tester, code), greaterThan(3));
      expect(
        tester.widget<RichText>(_richText(code)).text.toPlainText(),
        code,
      );
    });

    testWidgets('says an HTML page is simplified and never shows its scripts',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const NativeMarkupPreview(
            source: '<html><head><style>h1 { color: red }</style></head>'
                '<body><script>alert("x")</script><h1>Hello</h1>'
                '<p>World <a href="https://example.com">link</a></p>'
                '</body></html>',
            format: NativeMarkupFormat.html,
            baseDirectory: '/tmp',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(nativeHtmlPreviewNotice), findsOneWidget);
      expect(_richText('Hello'), findsOneWidget);
      expect(_richText('alert'), findsNothing);
      expect(_richText('color: red'), findsNothing);
      expect(_span(tester, 'link').recognizer, isA<TapGestureRecognizer>());
    });

    testWidgets('an HTML page with nothing readable says so', (tester) async {
      await tester.pumpWidget(
        _app(
          const NativeMarkupPreview(
            source: '<script>run()</script>',
            format: NativeMarkupFormat.html,
            baseDirectory: '/tmp',
          ),
        ),
      );
      expect(find.text(nativeHtmlPreviewEmpty), findsOneWidget);
    });

    testWidgets('survives pathologically deep nesting', (tester) async {
      await tester.pumpWidget(
        _app(
          NativeMarkupPreview(
            source: '${'> ' * 60}deep\n\n${'<div>' * 200}inner',
            format: NativeMarkupFormat.markdown,
            baseDirectory: '/tmp',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_richText('deep'), findsOneWidget);
      expect(_richText('inner'), findsOneWidget);
    });

    testWidgets('parses a very large file off the UI thread', (tester) async {
      final source = List.generate(30000, (i) => 'Paragraph $i').join('\n\n');
      await tester.pumpWidget(
        _app(
          NativeMarkupPreview(
            source: source,
            format: NativeMarkupFormat.markdown,
            baseDirectory: '/tmp',
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _settle(
        tester,
        () => _richText('Paragraph 0').evaluate().isNotEmpty,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_richText('Paragraph 0'), findsOneWidget);
    });

    testWidgets('loads local images only from inside the document folder',
        (tester) async {
      final root = (await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('native_markup_');
        final docs = await Directory(p.join(root.path, 'docs')).create();
        await File(p.join(docs.path, 'logo.png')).writeAsBytes(_png);
        await File(p.join(root.path, 'outside.png')).writeAsBytes(_png);
        await Link(p.join(docs.path, 'escape.png'))
            .create(p.join(root.path, 'outside.png'));
        return root;
      }))!;
      addTearDown(() => root.deleteSync(recursive: true));

      await tester.pumpWidget(
        _app(
          NativeMarkupPreview(
            source: '![logo](logo.png) ![escape](escape.png) '
                '![parent](../outside.png)',
            format: NativeMarkupFormat.markdown,
            baseDirectory: p.join(root.path, 'docs'),
          ),
        ),
      );
      await _settle(
        tester,
        () =>
            tester
                .widgetList<RawImage>(find.byType(RawImage))
                .any((image) => image.image != null) &&
            find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty,
      );
      // The contained image loads; a link out of the folder is refused once
      // resolved, and a path out of it is never read at all.
      expect(find.byType(Image), findsOneWidget);
      // A screen reader announces a loaded image by its alt text.
      expect(find.bySemanticsLabel('logo'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.text('escape'), findsOneWidget);
      expect(_richText('parent'), findsOneWidget);
    });

    testWidgets('FilePreview draws Markdown natively without a web view',
        (tester) async {
      expect(webMarkupPreviewAvailable, isFalse);
      await tester.pumpWidget(
        _app(
          FilePreview(
            file: _MemoryFile('/notes/readme.md', '# Wired\n\nNative body'),
            name: 'readme.md',
            kind: FilePreviewKind.markdown,
            metadata: const {},
            onMetadataChanged: (_) {},
            bare: true,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(NativeMarkupPreview), findsOneWidget);
      expect(_richText('Native body'), findsOneWidget);
    });
  });
}

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool paper = false,
}) =>
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [PaperThemeExtension(enabled: paper)],
      ),
      home: AppFlowyTheme(
        data: brightness == Brightness.light
            ? AppFlowyDefaultTheme().light()
            : AppFlowyDefaultTheme().dark(),
        child: Scaffold(body: child),
      ),
    );

/// Builds every block of the sample at once instead of only the first screen.
void _tallView(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1000, 4000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Lets isolate and file work finish, which fake time alone cannot do.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

Finder _richText(String text) => find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(text),
    );

TextSpan _span(WidgetTester tester, String text) {
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    TextSpan? found;
    widget.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span;
      return found == null;
    });
    if (found != null) return found!;
  }
  throw StateError('No span reads "$text".');
}

int _spanCount(WidgetTester tester, String text) {
  var count = 0;
  tester.widget<RichText>(_richText(text)).text.visitChildren((_) {
    count++;
    return true;
  });
  return count;
}

List<Color?> _codeBlockColors(WidgetTester tester) => [
      for (final box in tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(NativeMarkupPreview),
          matching: find.byType(DecoratedBox),
        ),
      ))
        if (box.decoration case final BoxDecoration decoration
            when decoration.borderRadius == BorderRadius.circular(10))
          decoration.color,
    ];

String _describe(List<m.Node> nodes) => nodes.map(_describeNode).join();

/// A compact, HTML-like dump of the tree. Whitespace-only text is left out:
/// the renderer collapses it either way.
String _describeNode(m.Node node) {
  if (node is m.Text) return node.text.trim().isEmpty ? '' : node.text;
  if (node is! m.Element) return '';
  final open = [
    node.tag,
    for (final MapEntry(:key, :value) in node.attributes.entries)
      if (key != 'id') value.isEmpty ? key : '$key=$value',
  ].join(' ');
  final children = node.children;
  return children == null
      ? '<$open/>'
      : '<$open>${_describe(children)}</${node.tag}>';
}

class _MemoryFile extends Fake implements File {
  _MemoryFile(this.path, this.contents);

  @override
  final String path;
  final String contents;

  @override
  Directory get parent => Directory(p.dirname(path));

  @override
  Future<bool> exists() async => true;

  @override
  Future<int> length() async => utf8.encode(contents).length;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async => contents;
}
