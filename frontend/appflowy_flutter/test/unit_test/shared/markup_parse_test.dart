import 'dart:io';
import 'dart:isolate';

import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/link_parsers/default_parser.dart';
import 'package:appflowy/shared/markup_parse.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_fetcher.dart';
import 'package:appflowy/workspace/application/collections/bookmark/link_metadata.dart';
import 'package:appflowy/workspace/application/collections/bookmark/readable_article.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _story = 'https://news.example/2026/05/a-quiet-week-in-the-markets';
const _headline = 'A quiet week in the markets';

/// A news page as it is fetched: what it says about itself at the top, then
/// the story, [paragraphs] long.
String _newsPage({
  String title = _headline,
  int paragraphs = 400,
  bool styled = false,
}) {
  final page = StringBuffer()
    ..write('<!doctype html><html lang="en"><head><meta charset="utf-8">')
    ..write('<title>$title</title>')
    ..write('<meta property="og:site_name" content="News Example">')
    ..write('<meta property="og:title" content="$title">')
    ..write('<meta property="og:description" content="Stocks barely moved.">')
    ..write('<meta property="og:image" content="/img/markets.jpg">')
    ..write('<link rel="canonical" href="$_story">');
  if (styled) {
    page.write('<style>.lede { font-weight: 600 }</style>');
  }
  page.write('</head><body><article><h1>$title</h1>');
  for (var i = 0; i < paragraphs; i++) {
    page.write('<p>Paragraph $i of the story: traders waited, prices held '
        'and the week ended much as it began, with little to say.</p>');
  }
  page.write('</article></body></html>');
  return '$page';
}

/// The isolate a parse ran on.
SendPort _isolateOf(String markup) => Isolate.current.controlPort;

http.Response _html(String page) => http.Response(
      page,
      200,
      headers: const {'content-type': 'text/html; charset=utf-8'},
    );

void main() {
  test('a snippet is read in place and a whole page off the UI isolate',
      () async {
    final here = Isolate.current.controlPort;
    expect(await parseMarkup('<p>Hello</p>', _isolateOf), here);
    final page = _newsPage();
    expect(page.length, greaterThan(backgroundMarkupLength));
    expect(await parseMarkup(page, _isolateOf), isNot(here));
  });

  test('a page read off the UI isolate says what it says in place', () async {
    final page = _newsPage();
    final url = Uri.parse(_story);

    final inPlace = parseLinkMetadata(page, url);
    final read = await readLinkMetadata(page, url);
    expect(read.title, _headline);
    expect(read.title, inPlace.title);
    expect(read.description, inPlace.description);
    expect(read.siteName, inPlace.siteName);
    expect(read.imageUrl, 'https://news.example/img/markets.jpg');
    expect(read.imageUrl, inPlace.imageUrl);
    expect(read.faviconUrl, inPlace.faviconUrl);
    expect(read.canonicalUrl, inPlace.canonicalUrl);
    expect(read.keywords, inPlace.keywords);

    final article = await readReadableArticle(page, baseUrl: url);
    final articleInPlace = parseReadableArticle(page, baseUrl: url);
    expect(article.wordCount, greaterThan(1000));
    expect(article.wordCount, articleInPlace.wordCount);
    expect(article.markdown, articleInPlace.markdown);
  });

  test('a link preview reads a long page off the UI isolate', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      // Longer than the part of a page a preview reads.
      final page = request.uri.path == '/check'
          ? _newsPage(title: 'Just a moment...')
          : _newsPage(paragraphs: 4000);
      request.response
        ..headers.contentType = ContentType.html
        ..write(page);
      request.response.close();
    });
    final site = 'http://${server.address.host}:${server.port}';

    final info = await DefaultParser().parse(Uri.parse('$site/story'));
    expect(info?.title, _headline);
    expect(info?.siteName, 'News Example');
    expect(info?.description, 'Stocks barely moved.');
    expect(info?.imageUrl, '$site/img/markets.jpg');
    // A bot check still stands in for nothing.
    expect(await DefaultParser().parse(Uri.parse('$site/check')), isNull);
  });

  test('a bookmark reads a long page off the UI isolate', () async {
    final page = _newsPage();
    final fetcher =
        BookmarkFetcher(client: MockClient((_) async => _html(page)));
    addTearDown(fetcher.close);

    final result = await fetcher.fetch(_story);
    expect(result.metadata?.title, _headline);
    expect(result.metadata?.description, 'Stocks barely moved.');
    expect(
      result.article?.markdown,
      parseReadableArticle(page, baseUrl: Uri.parse(_story)).markdown,
    );

    // The reader's check for styled text is read off the UI isolate too.
    final reader = await fetcher.fetch(
      _story,
      allowBrowserFallback: false,
      readerOnly: true,
    );
    expect(reader.article?.wordCount, result.article?.wordCount);
    final styled = BookmarkFetcher(
      client: MockClient((_) async => _html(_newsPage(styled: true))),
    );
    addTearDown(styled.close);
    final refused = await styled.fetch(
      _story,
      allowBrowserFallback: false,
      readerOnly: true,
    );
    expect(refused.succeeded, isFalse);
    expect(refused.error, 'Reader unavailable');
  });
}
