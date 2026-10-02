import 'package:appflowy/extensions/dart/built_in/web_embeds/web_embed_sites.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/shared/unusable_page_title.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_fetcher.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _extension = 'test.stand_in_titles';
const _post =
    'https://www.reddit.com/r/FlutterDev/comments/1abcde/some_post_title/';
const _story = 'https://news.example/2026/05/a-quiet-week-in-the-markets';
const _verification = 'Reddit - Please wait for verification';

String _page(String title, {String? description}) => '<html><head>'
    '<title>$title</title>'
    '${description == null ? '' : '<meta name="description" content="$description">'}'
    '</head><body><p>$title</p></body></html>';

ViewPB _view(
  String url, {
  String? title,
  String? description,
  List<String> tags = const [],
}) =>
    ViewPB()
      ..id = 'bookmark'
      ..name = bookmarkHost(url) ?? url
      ..extra = BookmarkMetadata(
        url: url,
        title: title,
        description: description,
        tags: tags,
      ).mergeIntoExtra('');

void main() {
  group('page titles', () {
    test('a bot check, a refusal or an error page stands in for the page', () {
      for (final title in [
        _verification,
        'Just a moment...',
        'Attention Required! | Cloudflare',
        'Access Denied',
        '403 Forbidden',
        '404 Not Found',
        'Page Not Found | The Verge',
        'Are you a robot?',
        'Robot Check',
        'Pardon Our Interruption',
        'Verifying you are human. This may take a few seconds.',
        'DDoS-Guard',
        'Too Many Requests',
        'Enable JavaScript and cookies to continue',
        'Error',
        'Blocked',
      ]) {
        expect(isStandInPageTitle(title), isTrue, reason: title);
        expect(isUnusablePageTitle(title, url: _post), isTrue, reason: title);
      }
    });

    test('a headline that only uses those words names its page', () {
      for (final title in [
        'Bill blocked by Senate',
        'Just a moment in time',
        'Security · GitHub',
        'Error - Wikipedia',
        'How to fix a 404 error in Next.js',
        'Access denied to journalists at the summit',
        'Some post title : r/FlutterDev',
      ]) {
        expect(isStandInPageTitle(title), isFalse, reason: title);
        expect(isUnusablePageTitle(title, url: _post), isFalse, reason: title);
      }
    });

    test("a site's bare name cannot name one of its posts", () {
      expect(isUnusablePageTitle('Reddit', url: _post), isTrue);
      expect(isUnusablePageTitle('reddit.com', url: _post), isTrue);
      expect(
        isUnusablePageTitle('Medium', url: 'https://medium.com/@a/b-1'),
        isTrue,
      );
      expect(isUnusablePageTitle('  ', url: _post), isTrue);
      // The home page is rightly named after the site, and a blog after its
      // writer.
      expect(
        isUnusablePageTitle('Reddit', url: 'https://www.reddit.com/'),
        isFalse,
      );
      expect(
        isUnusablePageTitle('Jane Doe', url: 'https://jane.dev/posts/hello'),
        isFalse,
      );
      // Only a check spoils the rest of what the page said.
      expect(isStandInPageTitle('Reddit'), isFalse);
    });
  });

  group('fetching', () {
    test('a page still behind its check fails instead of being saved',
        () async {
      var rendered = 0;
      final fetcher = BookmarkFetcher(
        client: MockClient(
          (_) async => http.Response(_page(_verification), 200),
        ),
        browserFallback: (_) async {
          rendered++;
          return _page(_verification);
        },
      );
      addTearDown(fetcher.close);
      final result = await fetcher.fetch(_post);
      expect(rendered, 1);
      expect(result.succeeded, isFalse);
      expect(result.metadata, isNull);
      expect(result.article, isNull);
    });

    test('a browser that gets past the check supplies the page', () async {
      final fetcher = BookmarkFetcher(
        client: MockClient(
          (_) async => http.Response(_page('Just a moment...'), 403),
        ),
        browserFallback: (_) async => _page(
          'A quiet week in the markets',
          description: 'Stocks barely moved.',
        ),
      );
      addTearDown(fetcher.close);
      final result = await fetcher.fetch(_story);
      expect(result.metadata?.title, 'A quiet week in the markets');
      expect(result.metadata?.description, 'Stocks barely moved.');
    });

    test("a page naming only its site keeps what else it said", () async {
      var rendered = 0;
      final fetcher = BookmarkFetcher(
        client: MockClient(
          (_) async => http.Response(
            _page('news.example', description: 'Markets were calm.'),
            200,
          ),
        ),
        browserFallback: (_) async {
          rendered++;
          return null;
        },
      );
      addTearDown(fetcher.close);
      final result = await fetcher.fetch(_story);
      // The bare name sends it to a real browser first.
      expect(rendered, 1);
      expect(result.succeeded, isTrue);
      expect(result.metadata?.description, 'Markets were calm.');
    });
  });

  group('a bookmark saved behind a check', () {
    test('is read again and forgets what the check said', () async {
      final service = _Service();
      final fetcher = BookmarkFetcher(
        client: MockClient(
          (_) async => http.Response(
            _page('Just a moment...', description: 'Checking your browser'),
            403,
          ),
        ),
        browserFallback: (_) async => null,
      );
      final controller = BookmarkController(
        service: service,
        fetcher: fetcher,
        persistDebounce: const Duration(days: 1),
      )..setViews([
          _view(
            _story,
            title: 'Just a moment...',
            description: 'Checking your browser',
            tags: const ['markets'],
          ),
        ]);
      addTearDown(controller.dispose);
      expect(controller.all.single.metadata.hasMetadata, isFalse);
      expect(controller.all.single.title, 'news.example');

      await controller.refreshMissing();
      final saved = service.writes.single;
      expect(saved.title, isNull);
      expect(saved.description, isNull);
      expect(saved.fetchFailed, isTrue);
      expect(saved.tags, ['markets']);
      expect(controller.all.single.title, 'news.example');

      // A failed read is offered as a retry, not repeated on every visit.
      await controller.refreshMissing();
      expect(service.writes, hasLength(1));
    });

    test('takes the page once the site shows it', () async {
      final service = _Service();
      final fetcher = BookmarkFetcher(
        client: MockClient(
          (_) async => http.Response(
            _page(
              'A quiet week in the markets',
              description: 'Stocks barely moved.',
            ),
            200,
          ),
        ),
      );
      final controller = BookmarkController(
        service: service,
        fetcher: fetcher,
        persistDebounce: const Duration(days: 1),
      )..setViews([_view(_story, title: _verification)]);
      addTearDown(controller.dispose);

      await controller.refreshMissing();
      final saved = service.writes.single;
      expect(saved.title, 'A quiet week in the markets');
      expect(saved.description, 'Stocks barely moved.');
      expect(saved.fetchFailed, isFalse);
      expect(controller.all.single.title, 'A quiet week in the markets');
    });
  });

  group('with site extensions', () {
    setUp(() {
      for (final site in webEmbedSites()) {
        ExtensionWebEmbedRegistry.register(_extension, site);
      }
    });
    tearDown(() => ExtensionWebEmbedRegistry.unregisterAll(_extension));

    test('a post its site would not show is named after its address', () {
      const metadata = BookmarkMetadata(url: _post, title: _verification);
      expect(metadata.pageTitle, isNull);
      expect(metadata.displayTitle('reddit.com'), 'Some post title');
      expect(
        const BookmarkMetadata(url: _post, title: 'Reddit')
            .displayTitle('reddit.com'),
        'Some post title',
      );
      expect(metadata.displayTitle('My saved thread'), 'My saved thread');
    });

    test('an embed never takes a check for its title', () {
      final link = ExtensionWebEmbedRegistry.recognize(_post)!;
      expect(webEmbedPageTitle(link, _verification), isNull);
      expect(
          webEmbedPageTitle(link, 'Attention Required! | Cloudflare'), isNull);
      expect(
        webEmbedPageTitle(link, 'Some post title : r/FlutterDev'),
        'Some post title : r/FlutterDev',
      );
    });
  });
}

class _Service extends BookmarkService {
  final writes = <BookmarkMetadata>[];

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required BookmarkMetadata metadata,
  }) async {
    writes.add(metadata);
    return FlowyResult.success(view);
  }
}
