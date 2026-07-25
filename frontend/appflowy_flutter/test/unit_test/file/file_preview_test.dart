import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  test('renders Markdown and embedded HTML into the preview document', () {
    final html = buildMarkdownPreviewHtml(
      '# Markdown heading\n\n'
      '<h1 align="center"><b>AppFlowy</b><br></h1>\n\n'
      '- First item\n\n'
      '<script>alert("blocked")</script>',
      brightness: Brightness.light,
      backgroundColor: const Color(0xFFFBFAF7),
      textColor: const Color(0xFF111111),
      linkColor: const Color(0xFF0000EE),
      borderColor: const Color(0xFFCCCCCC),
      codeBackground: const Color(0xFFF5F5F5),
    );

    expect(html, contains('<h1>Markdown heading</h1>'));
    expect(html, contains('<h1 align="center"><b>AppFlowy</b><br></h1>'));
    expect(html, contains('<li>First item</li>'));
    expect(html, isNot(contains('&lt;h1 align=')));
    expect(html, contains('&lt;script>'));
  });

  test('paints the Markdown preview with the AppFlowy appearance', () {
    String render(Brightness brightness, Color background) =>
        buildMarkdownPreviewHtml(
          '# Heading',
          brightness: brightness,
          backgroundColor: background,
          textColor: const Color(0xFF111111),
          linkColor: const Color(0xFF0000EE),
          borderColor: const Color(0xFFCCCCCC),
          codeBackground: const Color(0xFFF5F5F5),
        );

    final light = render(Brightness.light, const Color(0xFFFBFAF7));
    expect(light, contains('color-scheme: light;'));
    expect(light, isNot(contains('color-scheme: light dark')));
    expect(light, contains('html { background: #fbfaf7; }'));
    expect(light, contains('background: #fbfaf7;\n'));

    final dark = render(Brightness.dark, const Color(0xFF17181B));
    expect(dark, contains('color-scheme: dark;'));
    expect(dark, contains('html { background: #17181b; }'));
  });

  test('matches the renderer appearance to the requested brightness', () {
    String stabilityCss(String prepared) => html_parser
        .parse(prepared)
        .querySelector('style[data-appflowy-preview-stability]')!
        .text;

    expect(
      stabilityCss(
        prepareHtmlPreviewDocument('<p>Preview</p>'),
      ),
      contains('color-scheme: light;'),
    );
    expect(
      stabilityCss(
        prepareHtmlPreviewDocument(
          '<p>Preview</p>',
          brightness: Brightness.dark,
        ),
      ),
      contains('color-scheme: dark;'),
    );
  });

  test('reveals renderer scrollbars only while the preview scrolls', () {
    final css = buildHtmlPreviewStabilityCss(
      brightness: Brightness.light,
      scrollbarThumbColor: const Color(0x5C1A1A1A),
      autoHideScrollbars: true,
    );

    expect(css, contains('::-webkit-scrollbar-thumb {'));
    expect(
      css,
      contains(
        'html.$htmlPreviewScrollingClassName::-webkit-scrollbar-thumb',
      ),
    );
    expect(css, contains('rgba(26, 26, 26, 0.361)'));
    expect(
      buildHtmlPreviewStabilityCss(
        brightness: Brightness.light,
        scrollbarThumbColor: const Color(0x5C1A1A1A),
        autoHideScrollbars: false,
      ),
      isNot(contains('::-webkit-scrollbar')),
    );

    final script = buildHtmlPreviewScrollbarAutoHideScript();
    expect(script, contains("classList.add('$htmlPreviewScrollingClassName')"));
    expect(
      script,
      contains("classList.remove('$htmlPreviewScrollingClassName')"),
    );
    expect(
      script,
      contains('${htmlPreviewScrollbarIdleDelay.inMilliseconds}'),
    );
  });

  test('sanitizes active HTML before enabling the host scroll runtime', () {
    final prepared = prepareHtmlPreviewDocument(
      '''
      <html>
        <head>
          <base href="https://example.com">
          <meta http-equiv="refresh" content="0; url=https://example.com">
          <meta http-equiv="Content-Security-Policy" content="script-src *">
          <script>window.compromised = true</script>
          <link id="remote-css" rel="stylesheet"
                href="https://cdn.example.com/styles.css">
          <link id="prefetch" rel="prefetch"
                href="https://cdn.example.com/tracker">
        </head>
        <body onload="window.compromised = true">
          <a href="javascript:alert(1)" target="_blank">Unsafe link</a>
          <a id="local-link" href="other.html">Local navigation</a>
          <img src="javascript:alert(1)" onerror="alert(1)">
          <img id="remote-image" class="aspect-square"
               src="https://images.example.com/photo.png">
          <iframe srcdoc="<script>alert(1)</script>"></iframe>
          <svg><animate attributeName="x"></animate></svg>
        </body>
      </html>
      ''',
    );
    final document = html_parser.parse(prepared);

    expect(document.querySelector('script'), isNull);
    expect(document.querySelector('base'), isNull);
    expect(document.querySelector('iframe'), isNull);
    expect(document.querySelector('animate'), isNull);
    expect(
      document.querySelector('#remote-css')!.attributes['href'],
      'https://cdn.example.com/styles.css',
    );
    expect(document.querySelector('#prefetch'), isNull);
    expect(document.body!.attributes.containsKey('onload'), isFalse);
    expect(
      document.querySelector('a')!.attributes.containsKey('href'),
      isFalse,
    );
    expect(
      document.querySelector('#local-link')!.attributes.containsKey('href'),
      isFalse,
    );
    final image = document.querySelector('img:not(#remote-image)')!;
    expect(image.attributes.containsKey('src'), isFalse);
    expect(image.attributes.containsKey('onerror'), isFalse);
    expect(image.attributes.containsKey('width'), isFalse);
    expect(image.attributes.containsKey('height'), isFalse);
    expect(image.attributes['loading'], 'eager');
    expect(image.attributes['decoding'], 'sync');
    final remoteImage = document.querySelector('#remote-image')!;
    expect(
      remoteImage.attributes['src'],
      'https://images.example.com/photo.png',
    );
    expect(remoteImage.attributes['class'], 'aspect-square');
    expect(remoteImage.attributes.containsKey('width'), isFalse);
    expect(remoteImage.attributes.containsKey('height'), isFalse);
    final policies = document.querySelectorAll(
      'meta[http-equiv="Content-Security-Policy"]',
    );
    expect(policies, hasLength(1));
    expect(
      policies.single.attributes['content'],
      contains("script-src 'none'"),
    );
    expect(
      policies.single.attributes['content'],
      isNot(contains("default-src 'none'")),
    );
  });

  test('preserves authored image geometry and nested scrolling styles', () {
    final document = html_parser.parse(
      prepareHtmlPreviewDocument(
        '''
        <img id="sized" src="local.png" width="320" height="200">
        <img id="partial" src="data:image/png;base64,AA==" width="320">
        <pre><code>long code</code></pre>
        ''',
      ),
    );

    final sized = document.querySelector('#sized')!;
    final partial = document.querySelector('#partial')!;
    expect(sized.attributes['src'], 'local.png');
    expect(sized.attributes['width'], '320');
    expect(sized.attributes['height'], '200');
    expect(sized.attributes.containsKey('style'), isFalse);
    expect(partial.attributes['src'], startsWith('data:image/png'));
    expect(partial.attributes.containsKey('height'), isFalse);
    final stabilityCss =
        document.querySelector('style[data-appflowy-preview-stability]')!.text;
    expect(stabilityCss, contains('overflow-anchor: none'));
    expect(stabilityCss, isNot(contains('body *')));
    expect(stabilityCss, isNot(contains('overflow-y: visible')));
    expect(stabilityCss, isNot(contains('aspect-ratio')));
  });

  test('builds the reduced-motion direct scroll fallback', () {
    expect(
      buildWebViewDirectScrollScript(const Offset(-12.5, 120)),
      'window.scrollBy(-12.5, 120.0);',
    );
  });

  test('starts queued scrolling before a load callback marks it ready', () {
    expect(
      canStartHtmlPreviewScrollFlush(
        scrollOperationInFlight: false,
        hasController: true,
        hasPendingCommands: true,
      ),
      isTrue,
    );
    expect(
      canStartHtmlPreviewScrollFlush(
        scrollOperationInFlight: true,
        hasController: true,
        hasPendingCommands: true,
      ),
      isFalse,
    );
  });
}
