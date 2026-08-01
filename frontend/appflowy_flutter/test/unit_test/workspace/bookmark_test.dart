import 'dart:io';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_state.dart';
import 'package:appflowy/workspace/application/collections/bookmark/link_metadata.dart';
import 'package:appflowy/workspace/application/collections/bookmark/readable_article.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

ViewPB _bookmarkView({
  required String id,
  required String url,
  String name = '',
  String? title,
  String? description,
  String? siteName,
  List<String> tags = const [],
  bool starred = false,
  BookmarkReadState readState = BookmarkReadState.unread,
  DateTime? addedAt,
  DateTime? publishedAt,
  String? snapshotPath,
}) {
  final metadata = BookmarkMetadata(
    url: url,
    title: title,
    description: description,
    siteName: siteName,
    tags: tags,
    starred: starred,
    readState: readState,
    addedAt: addedAt ?? DateTime(2026),
    publishedAt: publishedAt,
    snapshotPath: snapshotPath,
  );
  return ViewPB()
    ..id = id
    ..name = name.isEmpty ? (bookmarkHost(url) ?? url) : name
    ..layout = ViewLayoutPB.Document
    ..extra = metadata.mergeIntoExtra(
      const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        mimeType: bookmarkMimeType,
      ).mergeIntoExtra(''),
    );
}

void main() {
  group('bookmark addresses', () {
    test('adds a scheme to a bare host', () {
      expect(
        normalizeBookmarkUrl('example.com/posts'),
        'https://example.com/posts',
      );
    });

    test('drops campaign parameters but keeps real ones', () {
      expect(
        normalizeBookmarkUrl(
          'https://example.com/a?id=7&utm_source=news&fbclid=x',
        ),
        'https://example.com/a?id=7',
      );
    });

    test('refuses anything that is not a web address', () {
      expect(normalizeBookmarkUrl('mailto:someone@example.com'), isNull);
      expect(normalizeBookmarkUrl('just some words'), isNull);
      expect(normalizeBookmarkUrl(''), isNull);
    });

    test('lowercases the host and unwraps angle brackets', () {
      expect(
        normalizeBookmarkUrl('<HTTPS://Example.COM/Path>'),
        'https://example.com/Path',
      );
    });

    test('reads every address out of a block of text', () {
      const text = '''
        Read https://a.example.com/one, then www.b.example.com/two.
        Also see <https://a.example.com/one> again.
      ''';
      expect(extractBookmarkUrls(text), [
        'https://a.example.com/one',
        'https://www.b.example.com/two',
      ]);
    });

    test('names a site without its www', () {
      expect(bookmarkHost('https://www.example.com/a'), 'example.com');
      expect(bookmarkDisplayUrl('https://www.example.com/a'), 'example.com/a');
    });

    test('normalises a tag', () {
      expect(normalizeBookmarkTag('  #Design  '), 'design');
      expect(normalizeBookmarkTag('##  Deep   Work'), 'deep work');
      expect(normalizeBookmarkTag('#'), isNull);
    });
  });

  group('bookmark metadata envelope', () {
    test('round trips through a view extra', () {
      final metadata = BookmarkMetadata(
        url: 'https://example.com/a',
        title: 'A title',
        tags: const ['design', 'research'],
        starred: true,
        readState: BookmarkReadState.reading,
        readProgress: 0.42,
        addedAt: DateTime.fromMillisecondsSinceEpoch(1735689600000),
      );
      final extra = metadata.mergeIntoExtra(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );

      final decoded = BookmarkMetadata.fromExtra(extra)!;
      expect(decoded.url, metadata.url);
      expect(decoded.title, 'A title');
      expect(decoded.tags, ['design', 'research']);
      expect(decoded.starred, isTrue);
      expect(decoded.readState, BookmarkReadState.reading);
      expect(decoded.readProgress, closeTo(0.42, 0.0001));
      expect(decoded.addedAt, metadata.addedAt);
      // The workspace item envelope beside it is untouched.
      expect(WorkspaceItemMetadata.fromExtra(extra)?.isFolder, isTrue);
    });

    test('a new bookmark is a workspace file, not a folder', () {
      final extra = BookmarkMetadata.newExtra('https://example.com');
      expect(WorkspaceItemMetadata.fromExtra(extra)?.isFile, isTrue);
      expect(BookmarkMetadata.fromExtra(extra)?.url, 'https://example.com');
    });

    test('rejects an envelope from a newer version', () {
      expect(
        BookmarkMetadata.fromExtra(
          '{"appflowy_bookmark":{"version":99,"url":"https://a.com"}}',
        ),
        isNull,
      );
    });

    test('falls back through the page title to the host', () {
      const metadata = BookmarkMetadata(
        url: 'https://www.example.com/a',
        title: 'Page title',
      );
      expect(metadata.displayTitle(''), 'Page title');
      expect(metadata.displayTitle('Renamed'), 'Renamed');
      expect(
        const BookmarkMetadata(url: 'https://www.example.com/a')
            .displayTitle(''),
        'example.com',
      );
    });

    test('reports reading time only for something worth reading', () {
      expect(
        const BookmarkMetadata(url: 'https://a.com', wordCount: 40)
            .readingMinutes,
        isNull,
      );
      expect(
        const BookmarkMetadata(url: 'https://a.com', wordCount: 900)
            .readingMinutes,
        5,
      );
    });
  });

  group('link metadata extraction', () {
    test('prefers OpenGraph over the document head', () {
      const html = '''
<html><head>
  <title>Fallback title</title>
  <meta name="description" content="Fallback description">
  <meta property="og:title" content="Real title">
  <meta property="og:description" content="Real description">
  <meta property="og:site_name" content="Example">
  <meta property="og:image" content="/hero.png">
  <meta name="author" content="A Writer">
  <meta property="article:published_time" content="2026-03-04T10:00:00Z">
  <link rel="icon" href="/icon.png">
  <link rel="canonical" href="https://example.com/canonical">
</head><body></body></html>''';

      final metadata =
          parseLinkMetadata(html, Uri.parse('https://example.com/a/b'));
      expect(metadata.title, 'Real title');
      expect(metadata.description, 'Real description');
      expect(metadata.siteName, 'Example');
      expect(metadata.author, 'A Writer');
      expect(metadata.imageUrl, 'https://example.com/hero.png');
      expect(metadata.faviconUrl, 'https://example.com/icon.png');
      expect(metadata.canonicalUrl, 'https://example.com/canonical');
      expect(metadata.publishedAt?.year, 2026);
    });

    test('reads JSON-LD when the social tags are missing', () {
      const html = '''
<html><head><script type="application/ld+json">
{"@context":"https://schema.org","@type":"Article",
 "headline":"From JSON-LD","description":"A description",
 "author":{"name":"Someone"},"datePublished":"2025-11-02",
 "publisher":{"name":"A Journal"},"keywords":["Research","design"]}
</script></head><body></body></html>''';

      final metadata = parseLinkMetadata(html, Uri.parse('https://a.com/x'));
      expect(metadata.title, 'From JSON-LD');
      expect(metadata.author, 'Someone');
      expect(metadata.siteName, 'A Journal');
      expect(metadata.publishedAt, DateTime(2025, 11, 2));
      expect(metadata.keywords, ['research', 'design']);
    });

    test('falls back to the site root icon', () {
      final metadata = parseLinkMetadata(
        '<html><head><title>T</title></head><body></body></html>',
        Uri.parse('https://example.com/deep/page?q=1'),
      );
      expect(metadata.faviconUrl, 'https://example.com/favicon.ico');
      expect(metadata.siteName, 'example.com');
    });

    test('reads the date formats publishers emit', () {
      expect(parseLinkDate('2026-03-04'), DateTime(2026, 3, 4));
      expect(parseLinkDate('2026/03/04 10:11'), DateTime(2026, 3, 4));
      expect(parseLinkDate('not a date'), isNull);
    });
  });

  group('readable article', () {
    const article = '''
<html><head><title>The page</title></head><body>
  <nav><a href="/a">Home</a><a href="/b">About</a></nav>
  <div class="sidebar"><a href="/x">Related thing</a></div>
  <article>
    <h1>A heading</h1>
    <p>The first paragraph is long enough to count towards the score of its
       container, which is what picks the article out of the page.</p>
    <p>A second paragraph with a <a href="/link">link</a> and some
       <strong>bold</strong> text in it, again long enough to matter here.</p>
    <ul><li>First item</li><li>Second item</li></ul>
    <pre><code class="language-dart">void main() {}</code></pre>
    <img src="/hero.png" alt="A picture">
  </article>
  <footer>Copyright</footer>
</body></html>''';

    test('keeps the article and drops the furniture', () {
      final result =
          parseReadableArticle(article, baseUrl: Uri.parse('https://a.com/p'));
      expect(result.markdown, contains('# A heading'));
      expect(result.markdown, contains('- First item'));
      expect(result.markdown, contains('```dart'));
      expect(result.markdown, contains('[link](https://a.com/link)'));
      expect(result.markdown, contains('**bold**'));
      expect(result.markdown, contains('![A picture](https://a.com/hero.png)'));
      expect(result.markdown, isNot(contains('About')));
      expect(result.markdown, isNot(contains('Copyright')));
      expect(result.title, 'The page');
      expect(result.wordCount, greaterThan(30));
    });

    test('offers an excerpt that ends on a word', () {
      final result = parseReadableArticle(article);
      final excerpt = result.excerpt(maxLength: 40)!;
      expect(excerpt.length, lessThanOrEqualTo(41));
      expect(excerpt, endsWith('…'));
    });

    test('reports nothing for a page with no prose', () {
      final result = parseReadableArticle(
        '<html><body><nav><a href="/a">A</a></nav></body></html>',
      );
      expect(result.isEmpty, isTrue);
    });
  });

  group('bookmark library', () {
    late BookmarkController controller;

    setUp(() {
      controller = BookmarkController(
        persistDebounce: const Duration(days: 1),
      );
      controller.setViews([
        _bookmarkView(
          id: '1',
          url: 'https://alpha.example.com/one',
          title: 'Alpha one',
          tags: const ['design'],
          addedAt: DateTime(2026, 5),
          starred: true,
        ),
        _bookmarkView(
          id: '2',
          url: 'https://beta.example.com/two',
          title: 'Beta two',
          tags: const ['design', 'research'],
          addedAt: DateTime(2026, 5, 3),
          readState: BookmarkReadState.read,
        ),
        _bookmarkView(
          id: '3',
          url: 'https://alpha.example.com/three',
          title: 'Alpha three',
          addedAt: DateTime(2026, 5, 2),
        ),
        ViewPB()
          ..id = '4'
          ..name = 'Not a bookmark'
          ..layout = ViewLayoutPB.Document,
      ]);
    });

    tearDown(() => controller.dispose());

    test('adopts only the saved links', () {
      expect(controller.all.map((entry) => entry.id), ['1', '2', '3']);
    });

    test('counts sites, tags and states', () {
      final stats = controller.stats;
      expect(stats.total, 3);
      expect(stats.unread, 2);
      expect(stats.starred, 1);
      expect(stats.sites.first.label, 'alpha.example.com');
      expect(stats.sites.first.count, 2);
      expect(stats.tags.first.label, 'design');
      expect(stats.tags.first.count, 2);
    });

    test('sorts by when a link was saved', () {
      expect(controller.entries.map((entry) => entry.id), ['2', '3', '1']);
      controller.updateSettings(
        controller.settings.copyWith(sort: BookmarkSort.oldestFirst),
      );
      expect(controller.entries.map((entry) => entry.id), ['1', '3', '2']);
    });

    test('sorts unread ahead of read', () {
      controller.updateSettings(
        controller.settings.copyWith(sort: BookmarkSort.unreadFirst),
      );
      expect(controller.entries.last.id, '2');
    });

    test('filters by state, site and tag together', () {
      controller.updateSettings(
        controller.settings.copyWith(filter: BookmarkFilter.unread),
      );
      expect(controller.entries.map((entry) => entry.id), ['3', '1']);

      controller.setSiteFilter('alpha.example.com');
      expect(controller.entries.map((entry) => entry.id), ['3', '1']);

      controller.toggleTagFilter('design');
      expect(controller.entries.map((entry) => entry.id), ['1']);

      controller.clearFilters();
      expect(controller.entries.length, 3);
    });

    test('searches titles, tags and addresses', () {
      controller.setQuery('research');
      expect(controller.entries.map((entry) => entry.id), ['2']);
      controller.setQuery('alpha.example.com');
      expect(controller.entries.map((entry) => entry.id), ['3', '1']);
      controller.setQuery('');
      expect(controller.entries.length, 3);
    });

    test('groups by site, biggest first', () {
      final groups = controller.groups(grouping: BookmarkGrouping.site);
      expect(groups.first.label, 'alpha.example.com');
      expect(groups.first.entries.length, 2);
      expect(groups.last.label, 'beta.example.com');
    });

    test('groups by month newest first', () {
      final groups = controller.groups(grouping: BookmarkGrouping.month);
      expect(groups.single.label, '2026-05');
    });

    test('remembers its settings and filters', () {
      controller
        ..updateSettings(
          controller.settings.copyWith(
            sort: BookmarkSort.title,
            filter: BookmarkFilter.starred,
            density: BookmarkDensity.roomy,
          ),
        )
        ..toggleTagFilter('design')
        ..setSiteFilter('alpha.example.com');

      final restored = BookmarkState.fromJson(controller.state.toJson());
      expect(restored.settings.sort, BookmarkSort.title);
      expect(restored.settings.filter, BookmarkFilter.starred);
      expect(restored.settings.density, BookmarkDensity.roomy);
      expect(restored.activeTags, {'design'});
      expect(restored.activeSite, 'alpha.example.com');
    });
  });

  group('offline snapshots', () {
    late Directory root;
    late BookmarkSnapshotStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('bookmark_snapshot_test');
      store = BookmarkSnapshotStore(rootOverride: root.path);
    });

    tearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });

    test('writes the article, the page and a hero picture', () async {
      final article = parseReadableArticle(
        '<html><head><title>T</title></head><body><article>'
        '<p>A paragraph that is long enough to be treated as real content by '
        'the reader, which is the whole point of this test.</p>'
        '</article></body></html>',
      );

      final snapshot = await store.save(
        url: 'https://example.com/a',
        article: article,
        html: '<html><body>original</body></html>',
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.hasArticle, isTrue);
      expect(File(snapshot.articlePath!).existsSync(), isTrue);
      expect(File(snapshot.pagePath!).existsSync(), isTrue);
      expect(snapshot.bytes, greaterThan(0));

      final markdown = await File(snapshot.articlePath!).readAsString();
      expect(markdown, startsWith('# T'));
      expect(markdown, contains('https://example.com/a'));
    });

    test('does not repeat a heading the article already carries', () async {
      final article = parseReadableArticle(
        '<html><head><title>T</title></head><body><article>'
        '<h1>The article heading</h1>'
        '<p>A paragraph that is long enough to be treated as real content by '
        'the reader, which is the whole point of this test.</p>'
        '</article></body></html>',
      );

      final snapshot = await store.save(
        url: 'https://example.com/a',
        article: article,
      );
      final markdown = await File(snapshot!.articlePath!).readAsString();
      expect('# '.allMatches(markdown).length, 1);
      expect(markdown, contains('# The article heading'));
    });

    test('reuses one directory for the same address', () async {
      final first = await store.directoryFor('https://example.com/a');
      final second = await store.directoryFor('https://example.com/a');
      final other = await store.directoryFor('https://example.com/b');
      expect(first.path, second.path);
      expect(first.path, isNot(other.path));
      expect(p.dirname(first.path), root.path);
    });

    test('reads a snapshot back and then removes it', () async {
      final saved = await store.save(
        url: 'https://example.com/a',
        html: '<html><body>x</body></html>',
      );
      final read = await store.read(saved!.directory);
      expect(read?.pagePath, saved.pagePath);

      await store.delete(saved.directory);
      expect(await store.read(saved.directory), isNull);
    });

    test('keeps nothing when there is nothing to keep', () async {
      expect(await store.save(url: 'https://example.com/a'), isNull);
      expect(await store.read(null), isNull);
    });
  });
}
