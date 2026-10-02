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
final _loading = jsonEncode({'url': _url, 'loading': true});

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
    // Nothing on its way yet: there is nothing to wait for.
    expect(session.canRead, isFalse);
    expect(await session.capture(), isNull);
    expect(session.lastFailure, BookmarkReaderFailure.unavailable);
    expect(calls, 0);
    // A page still loading can already be read.
    session.navigationStarted(_url);
    expect(session.ready, isFalse);
    expect(session.canRead, isTrue);
    final first = session.capture();
    final second = session.capture();
    expect(identical(first, second), isTrue);
    gate.complete(_payload());
    final capture = await first;
    expect(capture, isNotNull);
    expect(calls, 1);
    expect(session.lastFailure, isNull);
    expect(capture!.article.plainText, contains('Visible prose'));
    expect(session.isCurrent(capture), isTrue);
    session.navigationFinished(_url);
    expect(session.isCurrent(capture), isTrue);
    session.historyChanged('$_url#next');
    expect(session.isCurrent(capture), isFalse);
    session.dispose();
  });

  test('a page that is not on the web cannot be read', () async {
    final session = BookmarkReadingSession();
    var calls = 0;
    session.attach(Object(), (_) async {
      calls++;
      return _payload();
    });
    for (final url in ['about:blank', 'file:///C:/page.html', null]) {
      session.navigationStarted(url);
      session.navigationFinished(url);
      expect(session.canRead, isFalse);
      expect(await session.capture(), isNull);
    }
    expect(calls, 0);
    session.dispose();
  });

  testWidgets('waits for a loading page, past the document it replaces',
      (tester) async {
    final session = BookmarkReadingSession();
    final answers = <Object? Function()>[
      // The blank page a view starts on, the document being left, the new
      // one still parsing, then the new one.
      () => null,
      () => _payload(url: 'https://news.example/previous'),
      () => throw StateError('the document went away mid-answer'),
      () => _loading,
      _payload,
    ];
    var calls = 0;
    session.attach(Object(), (_) async => answers[calls++]());
    session.navigationStarted(_url);
    BookmarkReaderCapture? result;
    var completed = false;
    unawaited(session.capture().then((value) {
      result = value;
      completed = true;
    }));
    await tester.pump();
    expect(calls, 1);
    for (var i = 0; i < 4; i++) {
      expect(completed, isFalse);
      await tester.pump(bookmarkReaderRetryInterval);
    }
    await tester.pump();
    expect(completed, isTrue);
    expect(calls, 5);
    expect(result?.article.plainText, contains('Visible prose'));
    expect(session.lastFailure, isNull);
    session.dispose();
  });

  testWidgets('the end of the load wakes a waiting capture at once',
      (tester) async {
    final session = BookmarkReadingSession();
    var loaded = false;
    var calls = 0;
    session.attach(Object(), (_) async {
      calls++;
      return loaded ? _payload() : _loading;
    });
    session.navigationStarted(_url);
    BookmarkReaderCapture? result;
    unawaited(session.capture().then((value) => result = value));
    await tester.pump();
    expect(calls, 1);
    loaded = true;
    session.navigationFinished(_url);
    await tester.pump();
    expect(calls, 2);
    expect(result, isNotNull);
    session.dispose();
  });

  testWidgets('a page that never becomes readable fails at the page deadline',
      (tester) async {
    final session = BookmarkReadingSession(
      pageDeadline: bookmarkReaderRetryInterval * 4,
    );
    var calls = 0;
    session.attach(Object(), (_) async {
      calls++;
      return _loading;
    });
    session.navigationStarted(_url);
    var completed = false;
    BookmarkReaderCapture? result;
    unawaited(session.capture().then((value) {
      result = value;
      completed = true;
    }));
    for (var i = 0; i < 4; i++) {
      await tester.pump(bookmarkReaderRetryInterval);
    }
    await tester.pump();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(calls, 5);
    expect(session.lastFailure, BookmarkReaderFailure.unavailable);
    session.dispose();
  });

  for (final change in ['navigation', 'detach', 'dispose']) {
    testWidgets('$change ends a wait for a loading page', (tester) async {
      final session = BookmarkReadingSession();
      final owner = Object();
      var calls = 0;
      session.attach(owner, (_) async {
        calls++;
        return _loading;
      });
      session.navigationStarted(_url);
      var completed = false;
      BookmarkReaderCapture? result;
      unawaited(session.capture().then((value) {
        result = value;
        completed = true;
      }));
      await tester.pump();
      expect(calls, 1);
      switch (change) {
        case 'navigation':
          session.navigationStarted('https://news.example/other');
        case 'detach':
          session.detach(owner);
        case 'dispose':
          session.dispose();
      }
      await tester.pump();
      expect(completed, isTrue);
      expect(result, isNull);
      expect(calls, 1);
      expect(session.lastFailure, BookmarkReaderFailure.navigated);
      if (change != 'dispose') session.dispose();
    });
  }

  test('a visible access gate is reported as one', () async {
    final session = BookmarkReadingSession();
    session.attach(
        Object(), (_) async => jsonEncode({'url': _url, 'gate': true}));
    session.navigationStarted(_url);
    expect(await session.capture(), isNull);
    expect(session.lastFailure, BookmarkReaderFailure.gated);
    session.dispose();
  });

  test('a loaded page that cannot answer fails at once', () async {
    final session = BookmarkReadingSession();
    var calls = 0;
    session.attach(Object(), (_) async {
      calls++;
      throw StateError('renderer gone');
    });
    session.navigationStarted(_url);
    session.navigationFinished(_url);
    expect(await session.capture(), isNull);
    expect(calls, 1);
    expect(session.lastFailure, BookmarkReaderFailure.unavailable);
    session.dispose();
  });

  test('a long article is parsed in the background', () async {
    final paragraphs = List.generate(
        800,
        (i) => '<p>Paragraph $i of a long article, with enough ordinary words '
            'in it to be read as prose rather than navigation.</p>').join();
    final html = '<html><body><article>$paragraphs</article></body></html>';
    expect(html.length, greaterThan(64 * 1024));
    final session = BookmarkReadingSession();
    session.attach(Object(), (_) async => _payload(html: html));
    session.navigationStarted(_url);
    session.navigationFinished(_url);
    final capture = await session.capture();
    expect(capture, isNotNull);
    expect(capture!.article.plainText, contains('Paragraph 799'));
    expect(session.isCurrent(capture), isTrue);
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
      expect(session.lastFailure, BookmarkReaderFailure.navigated);
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
      // A mismatched page is waited for; here the wait has no time at all.
      final session = BookmarkReadingSession(pageDeadline: Duration.zero);
      session.attach(Object(), (_) async => payload);
      session.navigationStarted(_url);
      session.navigationFinished(_url);
      expect(await session.capture(), isNull);
      expect(session.lastFailure, BookmarkReaderFailure.unavailable);
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

  test('a list of citations is not mistaken for the article', () {
    // Commas everywhere: a references list outscores the prose it cites.
    final citations = List.generate(
        60,
        (i) => '<li>"Source $i". Publisher, City, 2021. Archived, '
            'retrieved 2021-02-07, page $i.</li>').join();
    final paragraphs = List.generate(
        12,
        (i) => '<p>Paragraph $i of the article itself, long enough to '
            'read as prose.</p>').join();
    final article = parseReadableArticle(
        '<html><body><div class="content"><h1>Reading</h1>$paragraphs'
        '<div class="reflist"><ol class="references">$citations</ol></div>'
        '</div></body></html>',
        baseUrl: Uri.parse(_url));
    expect(article.plainText, contains('Paragraph 0 of the article'));
    expect(article.plainText, contains('Paragraph 11 of the article'));
  });

  test('a paragraph per nested wrapper still reads as the whole article', () {
    // BBC's layout: no scored container ever holds more than one paragraph.
    String block(String text) =>
        '<div><div><div><div><p>$text</p></div></div></div></div>';
    final blocks = [
      for (var i = 0; i < 20; i++)
        block('Paragraph $i of the story, long enough to read as prose.'),
      block('One paragraph, with commas, many commas, more, still more, '
          'and yet more, outscores every other paragraph on its own.'),
    ].join();
    final article = parseReadableArticle(
        '<html><body><main><article><h1>Story</h1>$blocks</article></main>'
        '<ul><li><a href="/next">A related story with a long headline</a></li>'
        '</ul></body></html>',
        baseUrl: Uri.parse(_url));
    expect(article.plainText, contains('Paragraph 0 of the story'));
    expect(article.plainText, contains('Paragraph 19 of the story'));
    expect(article.plainText, contains('outscores every other paragraph'));
    expect(article.plainText, isNot(contains('A related story')));
  });

  test('comments beside an article are not gathered into it', () {
    final story = List.generate(
        6,
        (i) => '<p>Paragraph $i, with a clause, another clause, and a third, '
            'of the story itself.</p>').join();
    final comments = List.generate(
        30,
        (i) => '<div class="comment"><p>Comment $i says something long '
            'enough to be read as prose here and there.</p></div>').join();
    final article = parseReadableArticle(
        '<html><body><article>$story</article>'
        '<section class="comments">$comments</section></body></html>',
        baseUrl: Uri.parse(_url));
    expect(article.plainText, contains('Paragraph 5'));
    expect(article.plainText, isNot(contains('Comment 0 says')));
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
