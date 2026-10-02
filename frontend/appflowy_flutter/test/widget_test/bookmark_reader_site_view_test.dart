import 'dart:convert';

import 'package:appflowy/extensions/dart/built_in/web_embeds/web_embed_sites.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_article_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bookmark_reader_test_localizations.dart';

// Real BookmarkReader on a link a site extension knows. The site's own view,
// the website leaf and snapshot IO are substituted.
const _extension = 'test.web_embeds';
const _url =
    'https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit';
final _payload = jsonEncode({
  'url': _url,
  'html': '<article><h1>Budget</h1>'
      '<p>An ordinary paragraph about the budget that is long enough to read.</p>'
      '</article>',
});

final _site = find.byKey(const ValueKey('site-probe'));
final _live = find.byKey(const ValueKey('live-probe'), skipOffstage: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fetchFonts = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await BookmarkReaderTestLocalizations.initialize();
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fetchFonts);

  setUp(() {
    for (final site in webEmbedSites()) {
      ExtensionWebEmbedRegistry.register(_extension, site);
    }
  });
  tearDown(() => ExtensionWebEmbedRegistry.unregisterAll(_extension));

  testWidgets(
    'opens as the site shows it, and loads the live page only on ask',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.mount(tester);
        expect(find.text('site:Google Sheets'), findsOneWidget);
        expect(_live, findsNothing);
        expect(fixture.button(tester, 'site').active, isTrue);
        // Its offline copy is taken from the live page, which is not there.
        expect(fixture.download(tester).onPressed, isNull);

        fixture.button(tester, 'live').onPressed!();
        await tester.pump();
        expect(_site, findsNothing);
        expect(find.byKey(const ValueKey('live-probe')), findsOneWidget);
        expect(fixture.button(tester, 'live').active, isTrue);
        expect(fixture.download(tester).onPressed, isNotNull);
        final leaf = tester.element(_live);

        fixture.button(tester, 'site').onPressed!();
        await tester.pump();
        expect(_site, findsOneWidget);
        expect(find.byKey(const ValueKey('live-probe')), findsNothing);
        expect(tester.element(_live), same(leaf));
        expect(TickerMode.of(tester.element(_live)), isFalse);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !canShowWebEmbedPages,
  );

  testWidgets(
    'Reader from the site view waits for the page to load',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.mount(tester);
        fixture.button(tester, 'reader').onPressed!();
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const ValueKey('live-probe')), findsOneWidget);
        expect(fixture.captureCalls, 0);
        // Asked again meanwhile, it would read a page that is not there yet.
        expect(fixture.button(tester, 'reader').onPressed, isNull);
        expect(fixture.download(tester).onPressed, isNull);

        fixture.session.navigationStarted(_url);
        fixture.session.navigationFinished(_url);
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(fixture.captureCalls, 1);
        expect(find.byType(BookmarkArticleView), findsOneWidget);
        expect(find.text(BookmarkReaderStrings.unavailable), findsNothing);
        expect(fixture.button(tester, 'reader').active, isTrue);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !canShowWebEmbedPages,
  );

  testWidgets(
    'a site switched off takes its view with it',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.mount(tester);
        expect(_site, findsOneWidget);

        ExtensionWebEmbedRegistry.unregisterAll(_extension);
        await tester.pump();
        expect(_site, findsNothing);
        expect(
          find.byKey(const ValueKey('bookmark-reader-site')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('live-probe')), findsOneWidget);
        expect(fixture.button(tester, 'live').active, isTrue);
      } finally {
        await fixture.dispose(tester);
      }
    },
    skip: !canShowWebEmbedPages,
  );
}

class _Fixture {
  _Fixture() {
    controller = BookmarkController()
      ..setViews([
        ViewPB(
          id: 'bookmark',
          name: 'Budget',
          extra: const BookmarkMetadata(
            url: _url,
            readState: BookmarkReadState.reading,
          ).mergeIntoExtra(''),
        ),
      ]);
    // Attached, as the live page would be, but nothing has loaded yet.
    session.attach(this, (_) {
      captureCalls++;
      return Future.value(_payload);
    });
  }

  late final BookmarkController controller;
  final BookmarkReadingSession session = BookmarkReadingSession();
  int captureCalls = 0;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = DesktopAppearance().getThemeData(
      AppTheme.fallback,
      Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );
    await tester.pumpWidget(
      BookmarkReaderTestLocalizations.wrap(
        theme: theme,
        home: Scaffold(
          body: ContextualFindScope(
            child: BookmarkReader(
              entryId: 'bookmark',
              controller: controller,
              standalone: true,
              readingSession: session,
              snapshots: _NoSnapshots(),
              webPageBuilder: (_) => const ColoredBox(
                key: ValueKey('live-probe'),
                color: Colors.white,
              ),
              sitePageBuilder: (_, link) =>
                  Text('site:${link.site}', key: const ValueKey('site-probe')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(BookmarkReader), findsOneWidget);
  }

  BookmarkAction button(WidgetTester tester, String name) => tester
      .widget<BookmarkAction>(find.byKey(ValueKey('bookmark-reader-$name')));

  BookmarkAction download(WidgetTester tester) => tester.widget<BookmarkAction>(
        find.byWidgetPredicate(
          (w) =>
              w is BookmarkAction &&
              (w.icon == Icons.download_rounded ||
                  w.icon == Icons.hourglass_top_rounded),
        ),
      );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    session.dispose();
    expect(tester.takeException(), isNull);
  }
}

class _NoSnapshots extends BookmarkSnapshotStore {
  @override
  Future<BookmarkSnapshot?> read(String? directoryPath) async => null;
}
