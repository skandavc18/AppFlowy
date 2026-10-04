import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/collection/views/bookmark/bookmark_article_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bookmark_reader_test_localizations.dart';

// Real BookmarkReader, local renderer, controls and Find. The website leaf and
// snapshot IO are substituted. These do not claim native CDP/DOM validation.
const _url = 'https://reader.example/article';
String _payload({String url = _url}) => jsonEncode({
      'url': url,
      'html': '<article><h1>Reading</h1>'
          '<p>Visible needle in an ordinary article paragraph that is long enough to read.</p>'
          '<p>Another needle in a second visible paragraph.</p></article>',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fetchFonts = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await BookmarkReaderTestLocalizations.initialize();
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fetchFonts);

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance: Reader needs no save; live leaf retained and hidden safely',
        (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.mount(tester, appearance: appearance);
        final leaf = tester.element(find.byKey(const ValueKey('live-probe')));
        await tester.tap(find.byKey(const ValueKey('live-field')));
        await tester.pump();
        expect(fixture.focus.hasFocus, isTrue);
        fixture.action(tester, 'reader')();
        await tester.pump();
        await tester.pump();
        expect(find.byType(BookmarkArticleView), findsOneWidget);
        expect(fixture.saves, 0);
        expect(fixture.captureCalls, 1);
        expect(fixture.focus.hasFocus, isFalse);
        expect(find.byKey(const ValueKey('live-probe')), findsNothing);
        expect(
          tester.element(
            find.byKey(const ValueKey('live-probe'), skipOffstage: false),
          ),
          same(leaf),
        );
        final hidden = tester.element(
          find.byKey(const ValueKey('live-field'), skipOffstage: false),
        );
        expect(TickerMode.of(hidden), isFalse);
        expect(
          find
              .byKey(const ValueKey('live-field'), skipOffstage: false)
              .hitTestable(),
          findsNothing,
        );
        final local = tester.element(
          find.byKey(const ValueKey('bookmark-local-article-scroll')),
        );
        final canvas = tester
            .widgetList<ColoredBox>(
              find.descendant(
                of: find.byType(BookmarkArticleView),
                matching: find.byType(ColoredBox),
              ),
            )
            .first;
        expect(canvas.color, EditorSurfaceStyle.canvasBackground(local));
        expect(ContextualFindRegion.dispatch(local), isTrue);
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'needle',
        );
        await tester.pump();
        final bar = tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));
        expect(bar.matchCount, 2);
        expect(bar.replaceController, isNull);
        expect(bar.currentMatch, 1);
        bar.onNext!();
        await tester.pump();
        expect(
          tester
              .widget<FindReplaceBar>(find.byType(FindReplaceBar))
              .currentMatch,
          2,
        );
        fixture.action(tester, 'offline')();
        await tester.pump();
        expect(
          tester
              .widget<BookmarkArticleView>(find.byType(BookmarkArticleView))
              .text,
          contains('Offline article'),
        );
        fixture.action(tester, 'live')();
        await tester.pump();
        expect(
          tester.element(find.byKey(const ValueKey('live-probe'))),
          same(leaf),
        );
        expect(
          TickerMode.of(
            tester.element(find.byKey(const ValueKey('live-field'))),
          ),
          isTrue,
        );
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
      'read-only Reader can read/search but cannot save; offline unavailable is disabled',
      (tester) async {
    final fixture = _Fixture(offline: false);
    try {
      await fixture.mount(tester);
      expect(find.text('Unread'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
      final aside = tester
          .getRect(find.byKey(const ValueKey('bookmark-reader-aside-scroll')));
      for (final chip in find.byType(BookmarkChip).evaluate()) {
        final bounds = tester.getRect(find.byWidget(chip.widget));
        expect(bounds.left, greaterThanOrEqualTo(aside.left));
        expect(bounds.right, lessThanOrEqualTo(aside.right));
      }
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<BookmarkAction>(
              find.byKey(const ValueKey('bookmark-reader-offline')),
            )
            .onPressed,
        isNull,
      );
      fixture.action(tester, 'reader')();
      await tester.pump();
      await tester.pump();
      expect(find.byType(BookmarkArticleView), findsOneWidget);
      expect(
        ContextualFindRegion.dispatch(
          tester.element(
            find.byKey(const ValueKey('bookmark-local-article-scroll')),
          ),
        ),
        isTrue,
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      await tester.pump();
      expect(
        tester.widget<FindReplaceBar>(find.byType(FindReplaceBar)).matchCount,
        2,
      );
      final download = tester.widget<BookmarkAction>(
        find.byWidgetPredicate(
          (w) => w is BookmarkAction && w.icon == Icons.download_rounded,
        ),
      );
      expect(download.onPressed, isNull);
      expect(fixture.saves, 0);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final change in ['navigate', 'dispose', 'live']) {
    testWidgets('$change while capturing cannot display stale Reader',
        (tester) async {
      final fixture = _Fixture();
      final gate = fixture.captureGate = Completer<dynamic>();
      try {
        await fixture.mount(tester);
        fixture.action(tester, 'reader')();
        await tester.pump();
        if (change == 'navigate') {
          fixture.session.navigationStarted('https://reader.example/other');
        }
        if (change == 'live') fixture.action(tester, 'live')();
        if (change == 'dispose') {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        gate.complete(_payload());
        await tester.pump();
        await tester.pump();
        expect(find.byType(BookmarkArticleView), findsNothing);
        expect(fixture.saves, 0);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('local Ctrl+F works on a narrow scaled reading surface',
      (tester) async {
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: const ContextualFindScope(
                    child: BookmarkArticleView(
                      text: 'A readable needle.\n\nAnother needle.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.sendKeyEvent(
        LogicalKeyboardKey.keyF,
        physicalKey: PhysicalKeyboardKey.keyF,
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.pump();
      expect(find.byType(FindReplaceBar), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      await tester.pump();
      expect(
        tester.widget<FindReplaceBar>(find.byType(FindReplaceBar)).matchCount,
        2,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final failure in ['error', 'timeout']) {
    testWidgets(
      '$failure releases Reader controls without saving',
      (tester) async {
        final fixture = _Fixture();
        final gate = fixture.captureGate = Completer<dynamic>();
        try {
          await fixture.mount(tester);
          fixture.action(tester, 'reader')();
          await tester.pump();
          if (failure == 'error') {
            gate.completeError(StateError('capture failed'));
          } else {
            await tester
                .pump(bookmarkReaderDeadline + const Duration(milliseconds: 1));
          }
          await tester.pump();
          expect(find.text(BookmarkReaderStrings.unavailable), findsOneWidget);
          expect(
            tester
                .widget<BookmarkAction>(
                  find.byKey(const ValueKey('bookmark-reader-reader')),
                )
                .onPressed,
            isNotNull,
          );
          expect(fixture.saves, 0);
          expect(find.byType(BookmarkArticleView), findsNothing);
          if (!gate.isCompleted) gate.complete(_payload());
          await tester.pump();
          expect(find.byType(BookmarkArticleView), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets(
    'a visible access gate is named rather than unavailable',
    (tester) async {
      final fixture = _Fixture();
      final gate = fixture.captureGate = Completer<dynamic>();
      try {
        await fixture.mount(tester);
        fixture.action(tester, 'reader')();
        await tester.pump();
        gate.complete(jsonEncode({'url': _url, 'gate': true}));
        await tester.pump();
        await tester.pump();
        expect(find.text(BookmarkReaderStrings.gated), findsOneWidget);
        expect(find.text(BookmarkReaderStrings.unavailable), findsNothing);
        expect(find.byType(BookmarkArticleView), findsNothing);
        expect(fixture.action(tester, 'reader'), isNotNull);
        expect(fixture.saves, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
      '$appearance: Reader reads a page still loading, saying so',
      (tester) async {
        final fixture = _Fixture();
        try {
          await fixture.mount(tester, appearance: appearance);
          // Loading again: not finished, but already on its way.
          fixture.session.navigationStarted(_url);
          fixture.captureGate = Completer<dynamic>()
            ..complete(jsonEncode({'url': _url, 'loading': true}));
          fixture.action(tester, 'reader')();
          await tester.pump();
          await tester.pump();
          expect(fixture.captureCalls, 1);
          final chip = find.byKey(const ValueKey('bookmark-reader-preparing'));
          expect(chip, findsOneWidget);
          expect(find.text(BookmarkReaderStrings.preparing), findsOneWidget);
          // The workspace's own surface, warm in paper mode, like the error.
          expect(
            tester.widget<Material>(chip).color,
            bookmarkThemeOf(tester.element(chip)).panel,
          );
          expect(find.byType(BookmarkArticleView), findsNothing);
          // The live page stays usable underneath while Reader waits.
          expect(
            find.byKey(const ValueKey('live-field')).hitTestable(),
            findsOneWidget,
          );
          expect(
            tester
                .widget<BookmarkAction>(
                  find.byKey(const ValueKey('bookmark-reader-reader')),
                )
                .onPressed,
            isNull,
          );

          fixture.captureGate = null;
          await tester.pump(bookmarkReaderRetryInterval);
          await tester.pump();
          await tester.pump();
          expect(fixture.captureCalls, 2);
          expect(find.byType(BookmarkArticleView), findsOneWidget);
          expect(chip, findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets(
    'Reader follows a page that moves on while it is read',
    (tester) async {
      final fixture = _Fixture();
      final gate = fixture.captureGate = Completer<dynamic>();
      try {
        await fixture.mount(tester);
        fixture.action(tester, 'reader')();
        await tester.pump();
        expect(fixture.captureCalls, 1);
        // A redirect, or a route the site pushes as it loads.
        const moved = 'https://reader.example/article?view=full';
        fixture.session.navigationStarted(moved);
        fixture.captureGate = Completer<dynamic>()
          ..complete(_payload(url: moved));
        gate.complete(_payload());
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(fixture.captureCalls, 2);
        expect(find.byType(BookmarkArticleView), findsOneWidget);
        expect(find.text(BookmarkReaderStrings.unavailable), findsNothing);
        expect(fixture.saves, 0);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  for (final invalidation in ['source', 'permission']) {
    testWidgets(
      '$invalidation during capture cannot save bookmark metadata',
      (tester) async {
        final fixture = _Fixture(readOnly: false);
        final gate = fixture.captureGate = Completer<dynamic>();
        try {
          await fixture.mount(tester);
          final url = invalidation == 'source'
              ? 'https://reader.example/followed'
              : _url;
          fixture.session.navigationStarted(url);
          fixture.session.navigationFinished(url);
          tester
              .widget<BookmarkAction>(
                find.byWidgetPredicate(
                  (w) =>
                      w is BookmarkAction && w.icon == Icons.download_rounded,
                ),
              )
              .onPressed!();
          await tester.pump();
          if (invalidation == 'permission') fixture.canEdit = false;
          gate.complete(_payload(url: url));
          await tester.pump();
          await tester.pump();
          expect(fixture.captureCalls, 1);
          expect(fixture.saves, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}

class _Fixture {
  _Fixture({bool offline = true, this.readOnly = true})
      : snapshots = _Snapshots(offline) {
    controller = _Controller()
      ..setViews([
        ViewPB(
          id: 'bookmark',
          name: 'Saved page',
          extra: const BookmarkMetadata(
            url: _url,
            readState: BookmarkReadState.reading,
            snapshotPath: 'local-copy',
          ).mergeIntoExtra(''),
        ),
      ]);
    session.attach(this, (_) {
      captureCalls++;
      return captureGate?.future ?? Future.value(_payload());
    });
    session.navigationStarted(_url);
    session.navigationFinished(_url);
  }
  late final _Controller controller;
  final BookmarkReadingSession session = BookmarkReadingSession();
  final _Snapshots snapshots;
  final focus = FocusNode();
  final bool readOnly;
  bool canEdit = true;
  int captureCalls = 0;
  Completer<dynamic>? captureGate;
  int get saves => controller.saves;

  Future<void> mount(WidgetTester tester, {String appearance = 'light'}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = DesktopAppearance().getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((t) => t.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
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
              readOnly: readOnly,
              canEdit: () => canEdit,
              readingSession: session,
              snapshots: snapshots,
              webPageBuilder: (_) => Column(
                key: const ValueKey('live-probe'),
                children: [
                  TextField(
                    key: const ValueKey('live-field'),
                    focusNode: focus,
                  ),
                ],
              ),
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

  VoidCallback action(WidgetTester tester, String name) => tester
      .widget<BookmarkAction>(find.byKey(ValueKey('bookmark-reader-$name')))
      .onPressed!;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final gate = captureGate;
    if (gate != null && !gate.isCompleted) gate.complete(null);
    await tester.pump();
    controller.dispose();
    session.dispose();
    focus.dispose();
    expect(tester.takeException(), isNull);
  }
}

class _Snapshots extends BookmarkSnapshotStore {
  _Snapshots(this.available);
  final bool available;
  @override
  Future<BookmarkSnapshot?> read(String? directoryPath) async => available
      ? BookmarkSnapshot(
          directory: 'local-copy',
          savedAt: DateTime(2026),
          bytes: 64,
          articlePath: 'local-copy/article.md',
        )
      : null;
  @override
  Future<String?> readArticleText(BookmarkSnapshot snapshot) async =>
      'Offline article with no network assets.';
}

class _Controller extends BookmarkController {
  int saves = 0;
  @override
  Future<bool> saveReaderCapture(
    BookmarkEntry entry,
    BookmarkReaderCapture capture, {
    required bool Function() isCurrent,
    BookmarkSnapshotStore? store,
  }) async {
    saves++;
    return false;
  }
}
