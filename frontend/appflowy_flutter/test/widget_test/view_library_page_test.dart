import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/favorite/favorite_service.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/view/local_page_store.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_query.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_labels.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_library_page.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart' show vividIconTestTheme;

const _timeout = Timeout(Duration(seconds: 60));
late Map<String, dynamic> _translations;
final _now = DateTime(2026, 9, 30, 9, 5);

void main() {
  final allowFontFetching = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _translations = await const TestBundleAssetLoader().load(
      'assets/translations',
      const Locale('en', 'US'),
    );
  });
  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = allowFontFetching;
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
      '$appearance: Recents is a gallery with the table gallery controls',
      (tester) async {
        final fixture = _Fixture();
        try {
          await _pumpLibrary(tester, fixture, appearance: appearance);
          expect(find.text('Recents'), findsOneWidget);
          expect(
            find.text('Everything you opened lately, newest first.'),
            findsOneWidget,
          );
          expect(find.text('3 pages'), findsOneWidget);
          for (final id in ['launch', 'budget', 'notes']) {
            expect(_card(id), findsOneWidget);
          }
          // Newest first, and captions say when each was viewed.
          expect(
            tester.getTopLeft(_card('launch')).dx,
            lessThan(tester.getTopLeft(_card('budget')).dx),
          );
          expect(find.text('Viewed 2m ago'), findsOneWidget);

          final canvas = find.byWidgetPredicate(
            (widget) =>
                widget is WorkspaceSurface &&
                widget.kind == WorkspaceSurfaceKind.canvas,
          );
          final background = (tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: canvas,
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration! as BoxDecoration)
              .color!;
          expect(
            background,
            WorkspacePalette.of(tester.element(canvas)).background,
          );
          if (appearance == 'paper') {
            expect(background.r, greaterThan(background.b));
            expect(background, isNot(Colors.white));
          }

          // The same card-size control a table gallery has, remembered.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('view-library-card-size')),
          );
          expect(fixture.written.last.scale, GalleryCardScale.large);

          // A compact list, then back to the wall.
          await _chooseLayout(tester, 'List');
          expect(fixture.written.last.layout, ViewGalleryLayout.list);
          expect(_row('budget'), findsOneWidget);
          expect(_card('budget'), findsNothing);
          // What each page is and where it lives, beside its name.
          expect(find.text('Page · General'), findsNWidgets(3));
          await _tapVisible(tester, _row('budget'));
          expect(fixture.opened, ['budget']);

          // Every other reading a folder offers shows the same pages.
          await _chooseLayout(tester, 'Thumbnails');
          expect(fixture.written.last.layout, ViewGalleryLayout.thumbnails);
          expect(_thumbnail('launch'), findsOneWidget);
          await _tapVisible(tester, _thumbnail('notes'));
          expect(fixture.opened, ['budget', 'notes']);
          await _chooseLayout(tester, 'Tiles');
          expect(fixture.written.last.layout, ViewGalleryLayout.tiles);
          expect(_tile('launch'), findsOneWidget);
          expect(find.text('Viewed 2m ago'), findsOneWidget);
          await _chooseLayout(tester, 'Details');
          expect(fixture.written.last.layout, ViewGalleryLayout.details);
          expect(
            find.byKey(const ValueKey('view-library-details-heading')),
            findsOneWidget,
          );
          expect(_details('budget'), findsOneWidget);
          await _chooseLayout(tester, 'Gallery');
          expect(_card('budget'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );
  }

  testWidgets(
    'search narrows the wall; clearing brings everything back',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpLibrary(tester, fixture);
        await _tapVisible(tester, find.byTooltip('Search'));
        await tester.enterText(find.byType(TextField), 'bud');
        await _pumpInteraction(tester);
        expect(_card('budget'), findsOneWidget);
        expect(_card('launch'), findsNothing);
        expect(find.text('1 page'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'nothing like this');
        await _pumpInteraction(tester);
        expect(
          find.byKey(const ValueKey('view-library-no-match')),
          findsOneWidget,
        );
        await _tapVisible(tester, find.text('Clear the filter'));
        expect(find.text('3 pages'), findsOneWidget);
        // The search box is never remembered.
        expect(fixture.written, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'group by when shows calendar buckets newest first',
    (tester) async {
      final fixture = _Fixture(stored: const {'group': 'when'});
      try {
        await _pumpLibrary(tester, fixture);
        final today = tester.getTopLeft(find.text('Today')).dy;
        final yesterday = tester.getTopLeft(find.text('Yesterday')).dy;
        expect(today, lessThan(yesterday));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'Favorites: pinned first, and a card menu removes only the favorite',
    (tester) async {
      final fixture = _Fixture(library: ViewLibrary.favorites);
      try {
        await _pumpLibrary(tester, fixture);
        expect(find.text('Favorites'), findsOneWidget);
        expect(
          tester.getTopLeft(_card('reading')).dx,
          lessThan(tester.getTopLeft(_card('launch')).dx),
        );
        await tester.ensureVisible(_card('launch'));
        await tester.tap(_card('launch'), buttons: kSecondaryButton);
        await _pumpInteraction(tester);
        expect(find.text('Pin to sidebar'), findsOneWidget);
        await tester.tap(find.text('Remove from Favorites'));
        await _pumpInteraction(tester);
        expect(fixture.favorites.toggled, ['launch']);
        expect(_card('launch'), findsNothing);
        expect(_card('reading'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'an empty library explains itself',
    (tester) async {
      final fixture = _Fixture(empty: true);
      try {
        await _pumpLibrary(tester, fixture);
        expect(
          find.byKey(const ValueKey('view-library-empty')),
          findsOneWidget,
        );
        expect(find.text('Nothing opened yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'the title and controls scroll with the wall, so no card is clipped',
    (tester) async {
      final fixture = _Fixture(extra: 24);
      try {
        await _pumpLibrary(tester, fixture, size: const Size(1200, 700));
        final scroll = find.byKey(const ValueKey('view-library-scroll'));
        final controls = find.byType(TableViewHeader);
        // One scrolling surface: nothing is pinned above a clipped wall.
        for (final part in [
          find.byKey(const ValueKey('view-library-header')),
          controls,
          _card('launch'),
        ]) {
          expect(find.descendant(of: scroll, matching: part), findsOneWidget);
        }
        final controlsTop = tester.getTopLeft(controls).dy;
        final cardTop = tester.getTopLeft(_card('launch')).dy;
        await tester.drag(scroll, const Offset(0, -200));
        await _pumpInteraction(tester);
        expect(tester.getTopLeft(controls).dy, closeTo(controlsTop - 200, 1));
        expect(
          tester.getTopLeft(_card('launch')).dy,
          closeTo(cardTop - 200, 1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'a cover is added, resized and removed here, and kept on this device',
    (tester) async {
      final fixture = _Fixture();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(1, 1));
        await _pumpLibrary(tester, fixture);
        final id = localPageId(ViewLibrary.recents.name, null);
        expect(find.byType(ViewCoverImage), findsNothing);

        // The same picker every page uses.
        final add = find.text('Add Cover');
        expect(add, findsOneWidget);
        await mouse.moveTo(tester.getCenter(add));
        await tester.pump();
        await tester.tapAt(
          tester.getCenter(add),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        tester
            .widget<UploadImageMenu>(find.byType(UploadImageMenu))
            .onSelectedColor!('#C8B99A');
        await tester.pumpAndSettle();
        expect(find.byType(ViewCoverImage), findsOneWidget);
        expect(
          ViewCoverCodec.decodeCover(fixture.pages.peek(id)!)?.value,
          '#C8B99A',
        );

        // Resizable like any page cover; the height keeps the picture.
        final cover = find.byKey(const ValueKey('workspace-page-cover'));
        final before = tester.getRect(cover).height;
        final pointer = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('page-cover-resize'))),
          kind: PointerDeviceKind.mouse,
        );
        await pointer.moveBy(const Offset(0, 4));
        await tester.pump();
        await pointer.moveBy(const Offset(0, 36));
        await tester.pump();
        await pointer.up();
        await _pumpInteraction(tester);
        expect(tester.getRect(cover).height, closeTo(before + 40, 0.5));
        expect(
          PageCoverHeight.decode(fixture.pages.peek(id)!),
          closeTo(before + 40, 0.5),
        );
        expect(
          ViewCoverCodec.decodeCover(fixture.pages.peek(id)!)?.value,
          '#C8B99A',
        );

        final remove = find.byKey(const ValueKey('view-decoration-remove'));
        await mouse.moveTo(tester.getCenter(cover));
        await tester.pump();
        await mouse.moveTo(tester.getCenter(remove));
        await tester.pump();
        await tester.tapAt(
          tester.getCenter(remove),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ViewCoverImage), findsNothing);
        expect(find.text('Add Cover'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'the Library holds every page once, newest edit first',
    (tester) async {
      final fixture = _Fixture(library: ViewLibrary.all);
      try {
        await _pumpLibrary(tester, fixture);
        expect(find.text('Library'), findsOneWidget);
        expect(find.text('3 pages'), findsOneWidget);
        for (final id in ['launch', 'tasks', 'notes']) {
          expect(_card(id), findsOneWidget);
        }
        // Not the workspace, a space, a database's other tab or a row page.
        for (final id in ['workspace', 'space', 'tasks-board', 'row-page']) {
          expect(_card(id), findsNothing);
        }
        expect(
          tester.getTopLeft(_card('launch')).dx,
          lessThan(tester.getTopLeft(_card('tasks')).dx),
        );
        expect(
          tester.getTopLeft(_card('tasks')).dx,
          lessThan(tester.getTopLeft(_card('notes')).dx),
        );
        expect(find.text('Edited 2m ago'), findsOneWidget);

        // Every page belongs here: its menu favorites, it never removes.
        await tester.ensureVisible(_card('tasks'));
        await tester.tap(_card('tasks'), buttons: kSecondaryButton);
        await _pumpInteraction(tester);
        expect(find.text('Remove from Recents'), findsNothing);
        await tester.tap(find.text('Add to Favorites'));
        await _pumpInteraction(tester);
        expect(fixture.favorites.toggled, ['tasks']);
        expect(fixture.allReads, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'details shows the facts in columns and orders by any of them',
    (tester) async {
      final fixture = _Fixture(stored: const {'layout': 'details'});
      try {
        await _pumpLibrary(tester, fixture);
        final heading =
            find.byKey(const ValueKey('view-library-details-heading'));
        for (final label in ['Name', 'Last viewed', 'Type', 'Location']) {
          expect(
            find.descendant(of: heading, matching: find.text(label)),
            findsOneWidget,
          );
        }
        double top(String id) => tester.getTopLeft(_details(id)).dy;
        expect(top('launch'), lessThan(top('budget')));

        await _tapVisible(
          tester,
          find.byKey(const ValueKey('view-library-sort-name')),
        );
        expect(fixture.written.last.sortColumn, ViewGalleryColumns.name);
        expect(top('budget'), lessThan(top('launch')));
        expect(top('launch'), lessThan(top('notes')));

        // Pressed again, the same column runs the other way.
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('view-library-sort-name')),
        );
        expect(fixture.written.last.direction, TableSortDirection.descending);
        expect(top('notes'), lessThan(top('launch')));

        // A time starts newest first.
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('view-library-sort-when')),
        );
        expect(fixture.written.last.sortColumn, ViewGalleryColumns.when);
        expect(fixture.written.last.direction, TableSortDirection.descending);
        expect(top('launch'), lessThan(top('budget')));

        await _tapVisible(tester, _details('notes'));
        expect(fixture.opened, ['notes']);
        await tester.tap(_details('budget'), buttons: kSecondaryButton);
        await _pumpInteraction(tester);
        expect(find.text('Remove from Recents'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'every reading stays usable narrow, at 2x text and right to left',
    (tester) async {
      for (final layout in ViewGalleryLayout.values) {
        final fixture = _Fixture(stored: {'layout': layout.id});
        try {
          for (final (size, scale, direction) in [
            (const Size(1200, 800), 1.0, ui.TextDirection.ltr),
            (const Size(360, 640), 2.0, ui.TextDirection.rtl),
          ]) {
            await _pumpLibrary(
              tester,
              fixture,
              size: size,
              scale: scale,
              direction: direction,
            );
            expect(tester.takeException(), isNull, reason: '$layout $size');
            expect(_item(layout, 'launch'), findsOneWidget);
          }
        } finally {
          await fixture.dispose(tester);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  testWidgets(
    'narrow, 2x text and RTL stay usable in every card face',
    (tester) async {
      for (final face in GalleryCardFace.values) {
        final fixture = _Fixture(stored: {'face': face.id});
        try {
          for (final (size, scale, direction) in [
            (const Size(1200, 800), 1.0, ui.TextDirection.ltr),
            (const Size(360, 640), 2.0, ui.TextDirection.rtl),
          ]) {
            await _pumpLibrary(
              tester,
              fixture,
              size: size,
              scale: scale,
              direction: direction,
            );
            expect(tester.takeException(), isNull, reason: '$face $size');
            expect(_card('launch'), findsOneWidget);
          }
        } finally {
          await fixture.dispose(tester);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

Finder _card(String id) => find.byKey(ValueKey('view-library-card-$id'));
Finder _row(String id) => find.byKey(ValueKey('view-library-row-$id'));
Finder _thumbnail(String id) =>
    find.byKey(ValueKey('view-library-thumbnail-$id'));
Finder _tile(String id) => find.byKey(ValueKey('view-library-tile-$id'));
Finder _details(String id) => find.byKey(ValueKey('view-library-details-$id'));

Finder _item(ViewGalleryLayout layout, String id) => switch (layout) {
      ViewGalleryLayout.gallery => _card(id),
      ViewGalleryLayout.thumbnails => _thumbnail(id),
      ViewGalleryLayout.tiles => _tile(id),
      ViewGalleryLayout.list => _row(id),
      ViewGalleryLayout.details => _details(id),
    };

/// The layout button opens the same readings a folder's view menu offers.
Future<void> _chooseLayout(WidgetTester tester, String label) async {
  await _tapVisible(tester, find.byKey(const ValueKey('view-library-layout')));
  await tester.tap(find.text(label).last);
  await _pumpInteraction(tester);
}

Future<void> _pumpInteraction(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _pumpInteraction(tester);
  await tester.tap(finder);
  await _pumpInteraction(tester);
}

Future<void> _pumpLibrary(
  WidgetTester tester,
  _Fixture fixture, {
  String appearance = 'paper',
  Size size = const Size(1200, 900),
  double scale = 1,
  ui.TextDirection direction = ui.TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      startLocale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
      saveLocale: false,
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: vividIconTestTheme(appearance),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: Scaffold(
            body: DefaultIconStyleScope(
              styles: fixture.styles,
              child: ViewLibraryPage(
                library: fixture.library,
                source: fixture.source,
                locations: fixture.locations,
                specStore: fixture.store,
                previews: fixture.previews,
                pageStore: fixture.pages,
                favoriteService: fixture.favorites,
                onOpen: (view) => fixture.opened.add(view.id),
                onOpenInNewTab: (view) => fixture.tabs.add(view.id),
                now: () => _now,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _pumpInteraction(tester);
  await tester.pump();
}

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

ViewPB _view(String id, String name, {String extra = ''}) => ViewPB(
      id: id,
      name: name,
      parentViewId: 'space',
      layout: ViewLayoutPB.Document,
      extra: extra,
    );

Int64 _stamp(Duration ago) =>
    Int64(_now.subtract(ago).millisecondsSinceEpoch ~/ 1000);

/// Everything the folder holds: the workspace itself, a space, pages, a
/// database with a second tab, and a row page (an orphan).
List<ViewPB> _allViews() => [
      ViewPB(id: 'workspace', name: 'Workspace'),
      ViewPB(
        id: 'space',
        name: 'General',
        parentViewId: 'workspace',
        extra: '{"is_space":true}',
      ),
      _view('notes', 'Meeting notes')
        ..lastEdited = _stamp(const Duration(days: 1)),
      _view('launch', 'Launch plan')
        ..lastEdited = _stamp(const Duration(minutes: 2)),
      ViewPB(
        id: 'tasks',
        name: 'Tasks',
        parentViewId: 'space',
        layout: ViewLayoutPB.Grid,
        lastEdited: _stamp(const Duration(hours: 3)),
      ),
      ViewPB(
        id: 'tasks-board',
        name: 'Board',
        parentViewId: 'tasks',
        layout: ViewLayoutPB.Board,
        lastEdited: _stamp(const Duration(minutes: 1)),
      ),
      ViewPB(id: 'row-page', name: 'Row', parentViewId: 'row-page'),
    ];

class _MemoryStorage implements KeyValueStorage {
  _MemoryStorage(this.values);
  final Map<String, String> values;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();
}

class _Favorites extends FavoriteService {
  final toggled = <String>[];

  @override
  Future<FlowyResult<RepeatedFavoriteViewPB, FlowyError>>
      readFavorites() async => FlowyResult.success(
            RepeatedFavoriteViewPB(
              items: [
                for (final (view, age) in [
                  (_view('launch', 'Launch plan'), const Duration(days: 1)),
                  (
                    _view(
                      'reading',
                      'Reading list',
                      extra: '{"is_pinned":true}',
                    ),
                    const Duration(days: 4),
                  ),
                ])
                  if (!toggled.contains(view.id))
                    SectionViewPB(item: view, timestamp: _stamp(age)),
              ],
            ),
          );

  @override
  Future<FlowyResult<void, FlowyError>> toggleFavorite(String viewId) async {
    toggled.add(viewId);
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<void, FlowyError>> pinOrUnpinFavorite(
    ViewPB view,
    bool isPinned,
  ) async =>
      FlowyResult.success(null);
}

class _Previews extends FolderGalleryPreviewLoader {
  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async =>
      FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.document,
        blocks: [
          FolderGalleryPreviewBlock(
            kind: FolderGalleryPreviewBlockKind.paragraph,
            runs: [FolderGalleryTextRun(text: 'Notes on ${view.name}.')],
          ),
        ],
        wordCount: 12,
        readingMinutes: 1,
        tags: const [],
        fileTypeLabel: 'PAGE',
      );
}

class _Fixture {
  _Fixture({
    this.library = ViewLibrary.recents,
    Map<String, Object> stored = const {},
    bool empty = false,
    int extra = 0,
  }) : storage = _MemoryStorage({
          if (stored.isNotEmpty) _specKey(library): jsonEncode(stored),
        }) {
    source = switch (library) {
      ViewLibrary.recents => RecentViewGallerySource(
          read: () async => empty
              ? const []
              : [
                  SectionViewPB(
                    item: _view('launch', 'Launch plan'),
                    timestamp: _stamp(const Duration(minutes: 2)),
                  ),
                  SectionViewPB(
                    item: _view('budget', 'Budget'),
                    timestamp: _stamp(const Duration(hours: 3)),
                  ),
                  SectionViewPB(
                    item: _view('notes', 'Meeting notes'),
                    timestamp: _stamp(const Duration(days: 1)),
                  ),
                  for (var i = 0; i < extra; i++)
                    SectionViewPB(
                      item: _view('page-$i', 'Page $i'),
                      timestamp: _stamp(Duration(days: 2 + i)),
                    ),
                ],
          remove: (ids) async => removed.addAll(ids),
          live: live,
        ),
      ViewLibrary.favorites =>
        FavoriteViewGallerySource(service: favorites, listen: false),
      ViewLibrary.all => AllPagesGallerySource(
          read: () async {
            allReads++;
            return _allViews();
          },
          changes: live,
        ),
    };
    store = _RecordingSpecStore(_specKey(library), storage, written);
  }

  static String _specKey(ViewLibrary library) => switch (library) {
        ViewLibrary.recents => ViewGallerySpecStore.recentsKey,
        ViewLibrary.favorites => ViewGallerySpecStore.favoritesKey,
        ViewLibrary.all => ViewGallerySpecStore.libraryKey,
      };

  final ViewLibrary library;
  final _MemoryStorage storage;
  final live = ValueNotifier<List<SectionViewPB>>(const []);
  final removed = <String>[];
  final favorites = _Favorites();
  final written = <ViewGallerySpec>[];
  final opened = <String>[];
  final tabs = <String>[];
  final pages = LocalPageStore(persist: false);
  int allReads = 0;
  final styles = ValueNotifier(DefaultIconStyle.vivid);
  final locations = ViewGalleryLocations(
    readName: (id) async => id == 'space' ? 'General' : null,
  );
  final previews = FolderGalleryPreviewCache(loader: _Previews());
  late final ViewGallerySource source;
  late final ViewGallerySpecStore store;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    source.dispose();
    locations.dispose();
    live.dispose();
    styles.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

class _RecordingSpecStore extends ViewGallerySpecStore {
  _RecordingSpecStore(super.key, KeyValueStorage storage, this.written)
      : super(storage: storage);

  final List<ViewGallerySpec> written;

  @override
  Future<void> write(ViewGallerySpec spec) {
    written.add(spec);
    return super.write(spec);
  }
}
