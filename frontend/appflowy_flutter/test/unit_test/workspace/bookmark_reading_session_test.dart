import 'dart:async';
import 'dart:convert';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_article_document.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_fetcher.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/collections/bookmark/readable_article.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _url = 'https://news.example/article';
const _html =
    '<html><head><title>Ordinary article</title></head><body><article>'
    '<p>Visible prose from the page the reader already loaded, without a second request.</p>'
    '</article></body></html>';
String _payload({String url = _url, String html = _html}) =>
    jsonEncode({'url': url, 'html': html});

void main() {
  test('capture reuses one evaluation; Reader has no persistence dependency',
      () async {
    final session = BookmarkReadingSession();
    final gate = Completer<dynamic>();
    var calls = 0;
    session.attach(Object(), (_) {
      calls++;
      return gate.future;
    });
    session.navigationStarted(_url);
    expect(await session.capture(), isNull);
    session.navigationFinished(_url);
    final first = session.capture();
    final second = session.capture();
    expect(identical(first, second), isTrue);
    gate.complete(_payload());
    final capture = await first;
    expect(capture, isNotNull);
    expect(calls, 1);
    expect(capture!.article.plainText, contains('Visible prose'));
    expect(session.isCurrent(capture), isTrue);
    session.historyChanged('$_url#next');
    expect(session.isCurrent(capture), isFalse);
    session.dispose();
  });

  for (final change in ['navigation', 'same-url-reload', 'detach', 'dispose']) {
    test('$change rejects a late capture', () async {
      final session = BookmarkReadingSession();
      final owner = Object();
      final gate = Completer<dynamic>();
      session.attach(owner, (_) => gate.future);
      session.navigationStarted(_url);
      session.navigationFinished(_url);
      final pending = session.capture();
      switch (change) {
        case 'navigation':
          session.navigationStarted('https://news.example/other');
        case 'same-url-reload':
          session.navigationStarted(_url);
          session.navigationFinished(_url);
        case 'detach':
          session.detach(owner);
        case 'dispose':
          session.dispose();
      }
      gate.complete(_payload());
      expect(await pending, isNull);
      if (change != 'dispose') session.dispose();
    });
  }

  for (final payload in [
    null,
    'not JSON',
    '{}',
    _payload(url: 'https://news.example/wrong'),
    _payload(html: '<article>${'界' * bookmarkReaderCaptureLimit}</article>')
  ]) {
    test(
        'rejects missing, malformed, mismatched or oversized capture ${payload?.length}',
        () async {
      final session = BookmarkReadingSession();
      session.attach(Object(), (_) async => payload);
      session.navigationStarted(_url);
      session.navigationFinished(_url);
      expect(await session.capture(), isNull);
      session.dispose();
    });
  }

  testWidgets('capture deadline releases UI and rejects later completion',
      (tester) async {
    final session = BookmarkReadingSession();
    final gate = Completer<dynamic>();
    session.attach(Object(), (_) => gate.future);
    session.navigationStarted(_url);
    session.navigationFinished(_url);
    BookmarkReaderCapture? result;
    var completed = false;
    unawaited(session.capture().then((value) {
      result = value;
      completed = true;
    }));
    await tester.pump(bookmarkReaderDeadline + const Duration(milliseconds: 1));
    expect(completed, isTrue);
    expect(result, isNull);
    gate.complete(_payload());
    await tester.pump();
    expect(result, isNull);
    session.dispose();
  });

  test('parser rejects hidden prose and unsafe links', () {
    final article = parseReadableArticle(
        '<article><p>Visible ordinary content long enough to select.</p>'
        '<p hidden>Hidden subscriber text</p><p style="display: none">Hidden CSS</p>'
        '<p><a href="javascript:alert(1)">Readable label</a>'
        '<a href="file:///C:/secret">File label</a></p></article>',
        baseUrl: Uri.parse(_url));
    expect(article.plainText, isNot(contains('Hidden')));
    expect(article.markdown, isNot(contains('javascript:')));
    expect(article.markdown, isNot(contains('file:')));
    expect(article.markdown, contains('Readable label'));
  });

  test(
      'passive archival HTML strips active tags, credentials and remote assets',
      () {
    final passive = passiveBookmarkHtml(
        '<article onclick="steal()"><p>Keep this paragraph.</p>'
        '<script>credential</script><form><input value="password">form secret</form>'
        '<img src="https://tracker.example/pixel"><a href="javascript:bad()">label</a>'
        '<iframe src="https://tracker.example"></iframe></article>');
    for (final forbidden in [
      'onclick',
      'credential',
      'password',
      'form secret',
      'src=',
      'href=',
      'javascript:',
      'iframe'
    ]) {
      expect(passive, isNot(contains(forbidden)));
    }
    expect(passive, contains('Keep this paragraph.'));
    expect(
        bookmarkArticleText(
            '![remote](https://tracker.example/x)\n\n# Heading\n\nText'),
        contains('Heading'));
    expect(
        bookmarkArticleText('![remote](https://tracker.example/x)'), isEmpty);
    expect(
        bookmarkPublicSource(
            'https://user:secret@news.example/a?token=secret#token'),
        'https://news.example/a');
  });

  test(
      'public source omits empty delimiters and preserves path and explicit port',
      () {
    for (final input in [
      'https://news.example/a',
      'https://news.example/a?',
      'https://news.example/a#',
      'https://user:secret@news.example/a?token=secret#token',
    ]) {
      final public = bookmarkPublicSource(input);
      expect(public, 'https://news.example/a');
      expect(Uri.parse(public).hasQuery, isFalse);
      expect(Uri.parse(public).hasFragment, isFalse);
      expect(Uri.parse(public).userInfo, isEmpty);
    }
    expect(bookmarkPublicSource('http://user:secret@[::1]:8080/a%20b?q=x#y'),
        'http://[::1]:8080/a%20b');
    expect(bookmarkPublicSource('file:///C:/private'), isEmpty);
  });

  for (final body in [
    '<title>Access denied</title>',
    '<style>.hidden{display:none}</style>$_html',
    '<div class="paywall">Subscribe</div>$_html'
  ]) {
    test(
        'HTTP Reader declines gate/style/challenge without browser fallback ${body.length}',
        () async {
      var browserReads = 0;
      final fetcher = BookmarkFetcher(
          client: MockClient((_) async => http.Response(body, 200)),
          browserFallback: (_) async {
            browserReads++;
            return _html;
          });
      final result = await fetcher.fetch(_url,
          readerOnly: true, allowBrowserFallback: false);
      expect(result.succeeded, isFalse);
      expect(browserReads, 0);
      fetcher.close();
    });
  }

  test('ordinary unstyled HTTP article works and oversize response fails',
      () async {
    var oversized = false;
    final fetcher = BookmarkFetcher(
        client: MockClient((_) async => http.Response(
            oversized ? 'x' * (maxBookmarkPageBytes + 1) : _html, 200)));
    expect((await fetcher.fetch(_url, readerOnly: true)).article?.isEmpty,
        isFalse);
    oversized = true;
    expect((await fetcher.fetch(_url, readerOnly: true)).succeeded, isFalse);
    fetcher.close();
  });
}
