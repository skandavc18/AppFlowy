import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/collection/views/book/book_contents_rail.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_toolbar.dart';
import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/plugins/collection/views/database/database_schema_panel.dart';
import 'package:appflowy/plugins/collection/views/database/database_workbench_view.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_tree_view.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/database/database_collection_controller.dart';
import 'package:appflowy/workspace/application/collections/database/database_schema.dart';
import 'package:appflowy/workspace/application/collections/database/database_summary_cache.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _pane = ValueKey('collection-layout-test-pane');
const _navigation = ValueKey('collection-workspace-navigation');
const _stage = ValueKey('collection-workspace-stage');

void main() {
  setUpAll(prepareVividIconTestAssets);

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
        '$appearance: real table rail collapses without losing the active editor',
        (tester) async {
      _viewport(tester);
      final fixture = _CollectionFixture(CollectionKind.database, [
        ViewPB(id: 'table-a', name: 'First table', layout: ViewLayoutPB.Grid),
        ViewPB(id: 'table-b', name: 'Second table', layout: ViewLayoutPB.Grid),
      ]);
      final controller = DatabaseCollectionController(summaries: _Summaries());
      controller.setViews(fixture.children);
      controller.setSchemaVisible(true);
      final geometry = _Geometry();
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            geometry,
            (context) => AnimatedBuilder(
              animation: controller,
              builder: (context, _) => DatabaseWorkbenchBody(
                collection: fixture.context,
                controller: controller,
                theme: databaseThemeOf(context),
                tableBuilder: (_, table) =>
                    _NativeBoundary(key: ValueKey(table.id)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(_NativeBoundary, skipOffstage: false),
          findsNothing,
          reason:
              'A schema-only visit does not initialize an unseen native editor.',
        );
        controller.setSchemaVisible(false);
        await tester.pumpAndSettle();
        final paneRect = tester.getRect(find.byKey(_pane));
        expect(
          tester.getTopLeft(find.byType(DatabaseTableRail)),
          paneRect.topLeft + const Offset(24, 16),
        );
        expect(tester.getTopLeft(find.byKey(_stage)).dy,
            greaterThan(paneRect.top + 16));
        expect(find.byType(CollectionWorkspacePicker), findsNothing);
        expect(find.byType(ViewerCard), findsNothing);
        _expectQuietSurfaces(tester);

        final row = tester.widget<DatabaseRow>(
          find.byKey(const ValueKey('collection-table-row-table-a')),
        );
        expect(row.selected, isTrue);
        final name = tester.widget<Text>(find.text('First table'));
        expect(name.style!.fontWeight, FontWeight.w500);
        expect(name.style!.fontVariations, const [FontVariation.weight(500)]);

        final editor = await _draft(tester);
        final element = tester.element(find.byType(_NativeBoundary));
        final toggle = find.byKey(
          const ValueKey('database-workbench-tables-toggle'),
        );
        // The pinned control is available without a toolbar hover or picker.
        expect(toggle.hitTestable(), findsOneWidget);
        expect(tester.widget<DatabaseAction>(toggle).active, isTrue);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(controller.state.showRail, isFalse);
        expect(toggle.hitTestable(), findsOneWidget);
        expect(tester.widget<DatabaseAction>(toggle).active, isFalse);
        expect(find.byType(CollectionWorkspacePicker), findsOneWidget);
        expect(tester.element(find.byType(_NativeBoundary)), same(element));
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(controller.state.showRail, isTrue);
        expect(toggle.hitTestable(), findsOneWidget);
        expect(tester.element(find.byType(_NativeBoundary)), same(element));
        editor.focus.requestFocus();
        await tester.pump();
        for (final (width, scale) in [
          (760.0, 1.0),
          (1020.0, 2.0),
          (360.0, 2.0),
          (1320.0, 1.0),
        ]) {
          geometry.change(width, scale);
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(_NativeBoundary)), same(element));
          _expectDraft(tester, editor);
          expect(controller.activeTable!.id, 'table-a');
          expect(
            controller.state.showRail,
            isTrue,
            reason: 'Responsive collapse is not a saved preference.',
          );
          final compact = width < 1200;
          expect(toggle.hitTestable(), findsOneWidget);
          expect(tester.widget<DatabaseAction>(toggle).active, !compact);
          expect(
            tester
                .widget<Offstage>(
                  find.byKey(_navigation, skipOffstage: false),
                )
                .offstage,
            compact,
          );
          if (compact) {
            expect(find.byType(CollectionWorkspacePicker), findsOneWidget);
            expect(
              tester.getSize(find.byKey(_stage)).width,
              closeTo(width - 48, 0.01),
            );
          }
          expect(tester.takeException(), isNull);
        }

        // Schema is a real pane; switching it must not close the live table.
        controller.setSchemaVisible(true);
        await tester.pumpAndSettle();
        expect(find.byType(DatabaseSchemaPanel), findsOneWidget);
        expect(find.text('Title column'), findsOneWidget);
        expect(editor.disposed, isFalse);
        controller.setSchemaVisible(false);
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(_NativeBoundary)), same(element));
        _expectDraft(tester, editor, focused: false);

        // A renderer-owned pointer gesture survives a layout frame mid-drag.
        final drag = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('native-drag'))),
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveBy(const Offset(12, 0));
        await tester.pump();
        geometry.change(760, 1);
        await tester.pump();
        await drag.moveBy(const Offset(36, 0));
        await tester.pump();
        await drag.up();
        expect(editor.dragUpdates, greaterThan(0));
        expect(editor.dragEnds, 1);
        expect(tester.element(find.byType(_NativeBoundary)), same(element));

        await tester.tap(
          find.descendant(
            of: find.byType(CollectionWorkspacePicker),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Second table'));
        await tester.pumpAndSettle();
        expect(controller.activeTable!.id, 'table-b');
        expect(
          editor.disposed,
          isTrue,
          reason:
              'A different table retains its own identity, not the old controllers.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        geometry.dispose();
        fixture.dispose();
      }
    });

    testWidgets(
        '$appearance: repository tree retains its filter, file draft and scroll across pane thresholds',
        (tester) async {
      _viewport(tester);
      final fixture = _CollectionFixture(CollectionKind.repository, const []);
      final controller =
          RepositoryController(initialState: const {}, onPersist: (_) {});
      controller.setEntries([
        for (var i = 0; i < 30; i++)
          RepoEntry(
            view: ViewPB(
              id: 'file-$i',
              name: 'source-$i.dart',
              layout: ViewLayoutPB.Document,
            ),
            kind: RepoEntryKind.source,
            path: 'source-$i.dart',
            depth: 0,
            parentPath: '',
          ),
      ]);
      controller.openFile('file-0');
      final filter = TextEditingController(text: 'source');
      final geometry = _Geometry();
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            geometry,
            (context) => AnimatedBuilder(
              animation: Listenable.merge([controller, filter]),
              builder: (context, _) {
                final palette = CollectionPalette.of(
                  context,
                  CollectionKind.repository,
                );
                final theme = repoThemeOf(context, palette);
                return RepoScaffold(
                  controller: controller,
                  palette: palette,
                  padded: false,
                  leading: [
                    repoViewControls(
                      context: context,
                      controller: controller,
                      theme: theme,
                    ),
                  ],
                  child: RepositoryTreeBody(
                    collection: fixture.context,
                    controller: controller,
                    theme: theme,
                    active:
                        controller.entryForId(controller.state.activeFileId!),
                    filter: filter,
                    editing: const {},
                    onFilterChanged: (_) {},
                    onToggleEditing: (_) {},
                    fileBuilder: (_, entry) =>
                        _NativeBoundary(key: ValueKey(entry.id)),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RepoTreePane), findsOneWidget);
        expect(find.byType(ViewerCard), findsNothing);
        final railElement = tester.element(find.byType(RepoTreePane));
        final editor = await _draft(tester);
        final element = tester.element(find.byType(_NativeBoundary));
        for (final (width, scale) in [
          (760.0, 1.0),
          (360.0, 2.0),
          (1400.0, 1.0),
        ]) {
          geometry.change(width, scale);
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(_NativeBoundary)), same(element));
          expect(
            tester.element(find.byType(RepoTreePane, skipOffstage: false)),
            same(railElement),
          );
          expect(filter.text, 'source');
          _expectDraft(tester, editor);
          expect(tester.takeException(), isNull);
        }
        controller
            .updateSettings(controller.settings.copyWith(showOutline: false));
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(_NativeBoundary)), same(element));
        _expectDraft(tester, editor);
        _expectQuietSurfaces(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        filter.dispose();
        geometry.dispose();
        fixture.dispose();
      }
    });

    testWidgets(
        '$appearance: real book rail and chapter stage preserve drafts and the borrowed controller',
        (tester) async {
      _viewport(tester);
      final fixture = _CollectionFixture(CollectionKind.book, [
        ViewPB(
          id: 'chapter-a',
          name: 'Opening chapter',
          layout: ViewLayoutPB.Document,
        ),
        ViewPB(
          id: 'chapter-b',
          name: 'Second chapter',
          layout: ViewLayoutPB.Document,
        ),
      ]);
      final reading = _BorrowedReading();
      final geometry = _Geometry();
      try {
        await fixture.explorer.initialize();
        await tester.pumpWidget(
          _app(
            appearance,
            geometry,
            (_) => BookReaderView(
              collection: fixture.context,
              reading: reading,
              chapterBuilder: (_, chapter, __, ___) =>
                  _NativeBoundary(key: ValueKey(chapter.id)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final railState = tester.state(find.byType(BookContentsRail));
        final editor = await _draft(tester);
        final element = tester.element(find.byType(_NativeBoundary));
        for (final (width, scale) in [
          (700.0, 1.0),
          (360.0, 2.0),
          (1320.0, 1.0),
        ]) {
          geometry.change(width, scale);
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(_NativeBoundary)), same(element));
          expect(
            tester.state(find.byType(BookContentsRail, skipOffstage: false)),
            same(railState),
          );
          expect(reading.currentChapter!.id, 'chapter-a');
          _expectDraft(tester, editor);
          expect(tester.takeException(), isNull);
        }
        expect(fixture.repository.reads, 1);
        expect(reading.disposals, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(reading.disposals, 0);
        reading.openChapter('chapter-b');
        expect(reading.currentChapter!.id, 'chapter-b');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        reading.dispose();
        geometry.dispose();
        fixture.dispose();
      }
    });

    testWidgets(
        '$appearance: album toolbar wraps, reveals to keyboard and holds its sort popup',
        (tester) async {
      _viewport(tester);
      final controller =
          AlbumController(initialState: const {}, onPersist: (_) {});
      final geometry = _Geometry();
      try {
        await tester.pumpWidget(
          _app(appearance, geometry, (context) {
            final palette = CollectionPalette.of(context, CollectionKind.album);
            return AlbumScaffold(
              controller: controller,
              palette: palette,
              leading: albumArrangementControls(
                context: context,
                controller: controller,
                palette: palette,
                showGrouping: true,
              ),
              child: const _NativeBoundary(),
            );
          }),
        );
        await tester.pumpAndSettle();
        final button = find.byWidgetPredicate(
          (widget) =>
              widget is AlbumToolbarButton &&
              widget.icon == Icons.swap_vert_rounded,
        );
        expect(button.hitTestable(), findsNothing);
        final stage =
            tester.state<_NativeBoundaryState>(find.byType(_NativeBoundary));
        final before = tester.getRect(find.byType(_NativeBoundary));
        await _focusAction(tester, button);
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(_NativeBoundary)), before);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final reveal = find
            .descendant(
              of: find.byType(CollectionWorkspaceToolbar),
              matching: find.byType(PreviewToolbar),
            )
            .first;
        expect(
          _opacity(tester, reveal),
          1,
          reason: 'The sort menu owns a hold after focus leaves.',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        geometry.change(360, 2);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(_NativeBoundary)), same(stage));
        expect(tester.getSize(find.byType(_NativeBoundary)).width, 312);
        expect(find.byType(WorkspaceGlyph), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        geometry.dispose();
      }
    });

    testWidgets(
        '$appearance: bookmark scaffold retains the borrowed vertical scroll lease',
        (tester) async {
      _viewport(tester);
      final fixture = _CollectionFixture(CollectionKind.bookmark, const []);
      final controller = BookmarkController();
      final borrowed = _BorrowedScroll();
      final geometry = _Geometry();
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            geometry,
            (context) => CollectionPageScrollScope(
              controller: borrowed,
              child: BookmarkScaffold(
                collection: fixture.context,
                controller: controller,
                theme: bookmarkThemeOf(context),
                showGrouping: true,
                showDensity: true,
                child: Builder(
                  builder: (context) => BookmarkScrollArea(
                    controller: CollectionPageScrollScope.maybeOf(context)!,
                    child: ListView.builder(
                      controller: CollectionPageScrollScope.maybeOf(context),
                      itemCount: 80,
                      itemExtent: 40,
                      itemBuilder: (_, i) => Text('Saved page $i'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final area = tester.element(find.byType(BookmarkScrollArea));
        borrowed.jumpTo(240);
        geometry.change(360, 2);
        await tester.pumpAndSettle();
        expect(borrowed.positions, hasLength(1));
        expect(borrowed.offset, 240);
        expect(tester.element(find.byType(BookmarkScrollArea)), same(area));
        final action = find.byWidgetPredicate(
          (widget) =>
              widget is BookmarkAction &&
              widget.icon == Icons.swap_vert_rounded,
        );
        await _focusAction(tester, action);
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(borrowed.disposals, 0);
        expect(borrowed.hasClients, isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        borrowed.dispose();
        controller.dispose();
        geometry.dispose();
        fixture.dispose();
      }
    });

    testWidgets(
        '$appearance: all shared collection regions are unboxed and actions have native semantics',
        (tester) async {
      _viewport(tester);
      final semantics = tester.ensureSemantics();
      var activated = 0;
      try {
        await tester.pumpWidget(
          vividIconTestApp(
            appearance,
            Builder(
              builder: (context) => SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const DatabasePanel(child: Text('Tables')),
                    RepoPanel(
                      theme: repoThemeOf(
                        context,
                        CollectionPalette.of(
                          context,
                          CollectionKind.repository,
                        ),
                      ),
                      child: const Text('Files'),
                    ),
                    const BookmarkPanel(child: Text('Bookmarks')),
                    const EmailPanel(child: Text('Mail')),
                    CollectionWorkspaceAction(
                      icon: Icons.add_rounded,
                      tooltip: 'Add item',
                      label: 'Add item',
                      onPressed: () => activated++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ViewerCard), findsNothing);
        _expectQuietSurfaces(tester);
        final button = find.byType(TextButton);
        expect(
          tester.getSemantics(button).hasFlag(SemanticsFlag.isButton),
          isTrue,
        );
        expect(
          tester
              .getSemantics(button)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(tester.getSemantics(button).label, 'Add item');
        await _focusAction(tester, find.byType(CollectionWorkspaceAction));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(activated, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(tester.view.reset);
}

class _Geometry extends ChangeNotifier {
  double width = 1320;
  double scale = 1;
  void change(double nextWidth, double nextScale) {
    width = nextWidth;
    scale = nextScale;
    notifyListeners();
  }
}

Widget _app(String appearance, _Geometry geometry, WidgetBuilder builder) =>
    vividIconTestApp(
      appearance,
      AnimatedBuilder(
        animation: geometry,
        builder: (context, _) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(geometry.scale)),
          child: SizedBox(
            key: _pane,
            width: geometry.width,
            height: 820,
            child: Builder(builder: builder),
          ),
        ),
      ),
    );

Future<_NativeBoundaryState> _draft(WidgetTester tester) async {
  final state =
      tester.state<_NativeBoundaryState>(find.byType(_NativeBoundary));
  await tester.enterText(
    find.descendant(
      of: find.byType(_NativeBoundary),
      matching: find.byType(TextField),
    ),
    'Unsaved draft',
  );
  state.text.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
  state.scroll.jumpTo(180);
  await tester.pump();
  return state;
}

void _expectDraft(
  WidgetTester tester,
  _NativeBoundaryState state, {
  bool focused = true,
}) {
  expect(tester.state(find.byType(_NativeBoundary)), same(state));
  expect(state.disposed, isFalse);
  expect(state.text.text, 'Unsaved draft');
  expect(
    state.text.selection,
    const TextSelection(baseOffset: 2, extentOffset: 7),
  );
  expect(state.scroll.offset, 180);
  if (focused) expect(state.focus.hasFocus, isTrue);
}

Future<void> _focusAction(WidgetTester tester, Finder action) async {
  final glyph =
      find.descendant(of: action, matching: find.byType(WorkspaceGlyph)).first;
  Focus.of(tester.element(glyph)).requestFocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 160));
}

double _opacity(WidgetTester tester, Finder toolbar) => tester
    .widget<AnimatedOpacity>(
      find
          .descendant(of: toolbar, matching: find.byType(AnimatedOpacity))
          .first,
    )
    .opacity;

void _expectQuietSurfaces(WidgetTester tester) {
  for (final element in find.byType(CollectionWorkspaceSurface).evaluate()) {
    final decoration = tester
        .widget<DecoratedBox>(
          find
              .descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(DecoratedBox),
              )
              .first,
        )
        .decoration as BoxDecoration;
    expect(decoration.boxShadow, isNull);
    expect(decoration.border, isNull);
    expect(decoration.color, WorkspacePalette.of(element).background);
    expect(decoration.borderRadius, BorderRadius.zero);
  }
}

/// Stateful stand-in for the native table/document/webview boundary only.
/// Local keys deliberately do NOT rescue reparenting mistakes like GlobalKeys.
class _NativeBoundary extends StatefulWidget {
  const _NativeBoundary({super.key});
  @override
  State<_NativeBoundary> createState() => _NativeBoundaryState();
}

class _NativeBoundaryState extends State<_NativeBoundary> {
  final text = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  bool disposed = false;
  int dragUpdates = 0;
  int dragEnds = 0;

  @override
  void dispose() {
    disposed = true;
    text.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(controller: text, focusNode: focus),
          GestureDetector(
            key: const ValueKey('native-drag'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (_) => dragUpdates++,
            onPanEnd: (_) => dragEnds++,
            child: const SizedBox(
              height: 44,
              width: double.infinity,
              child: Text(
                'Column drag boundary',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              primary: false,
              itemExtent: 40,
              itemCount: 80,
              itemBuilder: (_, i) => Text('Content row $i'),
            ),
          ),
        ],
      );
}

class _Summaries extends DatabaseSummaryCache {
  @override
  DatabaseTableSummary summaryFor(String viewId) => DatabaseTableSummary(
        viewId: viewId,
        databaseId: viewId,
        rowCount: 80,
        fields: [
          DatabaseFieldSummary(
            id: 'title',
            name: 'Title column',
            type: FieldType.RichText,
            isPrimary: true,
          ),
        ],
      );

  @override
  Future<void> readAll(
    List<ViewPB> views, {
    void Function()? onProgress,
  }) async {}
}

class _BorrowedReading extends BookReadingController {
  _BorrowedReading() : super(initialState: const {}, onPersist: (_) {});
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _BorrowedScroll extends ScrollController {
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _CollectionFixture {
  _CollectionFixture(CollectionKind kind, this.children) {
    root = ViewPB(
      id: 'layout-${kind.name}',
      name: 'Collection fixture',
      layout: ViewLayoutPB.Document,
      extra: CollectionMetadata(kind: kind).mergeIntoExtra(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      ),
    );
    repository = _Repository(children);
    explorer = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );
  }

  final List<ViewPB> children;
  late final ViewPB root;
  late final _Repository repository;
  late final WorkspaceExplorerController explorer;

  CollectionViewContext get context => CollectionViewContext(
        collectionView: root,
        metadata: root.collection!,
        definition: CollectionViewDefinition(
          id: 'fixture',
          labelKey: 'fixture',
          icon: Icons.folder_rounded,
          builder: (_, __) => const SizedBox.shrink(),
        ),
        explorer: explorer,
        onOpen: (_) {},
        onOpenView: (_) {},
        onStateChanged: (_, __) {},
      );

  void dispose() => explorer.dispose();
}

class _Repository implements WorkspaceItemRepository {
  _Repository(this.children);
  final List<ViewPB> children;
  int reads = 0;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) async {
    reads++;
    return FlowyResult.success(children);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
