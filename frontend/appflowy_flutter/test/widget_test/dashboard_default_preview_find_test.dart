import 'dart:async';

import 'package:appflowy/plugins/dashboard/presentation/dashboard_embed_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart'
    show FieldType;
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database_find_test_support.dart';
import 'surface_find_test_support.dart';

void main() {
  surfaceFindTestEnvironment();

  for (final appearance in WorkspaceDesignAppearance.values) {
    for (final kind in [
      ('page', ViewLayoutPB.Document),
      ('page_link', ViewLayoutPB.Document),
      ('page_link', ViewLayoutPB.Grid),
      ('page_link', ViewLayoutPB.Board),
      ('page_link', ViewLayoutPB.Calendar),
    ]) {
      testWidgets('real default ${kind.$1}/${kind.$2} preview body Find '
          'has native visible ranges in ${appearance.name}', (tester) async {
        final page = _PreviewHarness(type: kind.$1, layout: kind.$2);
        try {
          page.loader.value = Future.value(kind.$2 == ViewLayoutPB.Document
              ? _document('lead bodyneedle bodyneedle')
              : _table());
          await page.mount(tester, appearance: appearance);
          expect(find.byType(PagePreviewCard), findsOneWidget);
          final originalDocument = page.dashboard.document;
          final originalSource = page.reads.snapshot();
          await page.query(tester, 'bodyneedle');
          expect(page.find.matches, hasLength(2));
          expect(page.find.matches.every((hit) =>
              hit.id is DashboardEmbedFindId && !hit.entry.replaceable), isTrue);
          final paint = page.paint(tester);
          final native = <Rect>[];
          for (final run in paint.textRuns) {
            expect(run.render, isA<RenderParagraph>());
            for (final match in RegExp('bodyneedle').allMatches(run.text)) {
              native.addAll((run.render as RenderParagraph)
                  .getBoxesForSelection(TextSelection(
                    baseOffset: run.start + match.start,
                    extentOffset: run.start + match.end,
                  ))
                  .map((box) => MatrixUtils.transformRect(
                      run.render.getTransformTo(paint), box.toRect())));
            }
          }
          expect(native, hasLength(2));
          expect(paint.matchRects, native);
          page.find.step(1);
          await pumpSurfaceFind(tester);
          expect(paint.currentRect, native.last);
          final viewport = tester.getRect(find.byType(SurfaceFindHost));
          final current = page.find.currentTargetRect!;
          expect(viewport.contains(current.topLeft), isTrue);
          expect(viewport.contains(current.bottomRight), isTrue);
          expect(page.scroll.offset, greaterThan(0));

          // A valid match is read-only even on an editable dashboard.
          page.find.replacementController.text = 'changed';
          page.find.replaceCurrent();
          page.find.replaceAll();
          await pumpSurfaceFind(tester);
          expect(page.find.matches, hasLength(2));
          expect(page.dashboard.document, same(originalDocument));
          expect(page.dashboard.canUndo, isFalse);
          expect(page.reads.snapshot(), originalSource);
          expect(page.loader.calls, 1,
              reason: 'Find never rereads or expands the preview target');
          expect(page.reads.forbiddenReads, isEmpty);
          expect(page.reads.calls.where((call) => call.startsWith('preflight:')),
              hasLength(4), reason: 'Owner and target, before and after');

            page.dashboard.setReadOnly(true);
            await pumpSurfaceFind(tester);
            await pumpSurfaceFind(tester);
            expect(page.find.matches, hasLength(2));
            expect(page.find.supportsReplace, isFalse);
            page.find.replaceAll();
            expect(page.dashboard.document, same(originalDocument));

          for (final excluded in [
            'target-title-only',
            'raw_metadata_sentinel',
            'url-secret',
            'hidden_row_sentinel',
          ]) {
            await page.query(tester, excluded);
            expect(page.find.matches, isEmpty, reason: excluded);
            expect(paint.matchRects, isEmpty);
          }
          await page.query(tester, 'bodyneedle');
          page.reads.allowed = false;
          page.reads.access.value++;
          expect(page.find.matches, isEmpty,
              reason: 'Revocation clears cached text synchronously');
          expect(paint.matchRects, isEmpty);
          await pumpSurfaceFind(tester);
          expect(page.find.matches, isEmpty);
        } finally {
          await page.dispose(tester);
        }
      });
    }
  }

  testWidgets('real preview skeleton registers late body, then replaces its '
      'snapshot without keeping old or duplicate results', (tester) async {
    final page = _PreviewHarness();
    final loaded = Completer<FolderGalleryPreview>();
    page.loader.value = loaded.future;
    try {
      await page.mount(tester);
      await page.query(tester, 'bodyneedle');
      expect(page.find.matches, isEmpty);
      expect(page.paint(tester).textRuns, isEmpty);
      loaded.complete(_document('bodyneedle'));
      await pumpSurfaceFind(tester);
      await pumpSurfaceFind(tester);
      expect(page.find.matches, hasLength(1));
      final gate = page.reads.hold('view:${_PreviewHarness.ownerId}');
      page.replacePreview(_document('replacement bodyneedle bodyneedle'));
      await databaseFindUntil(tester, () => page.reads.inFlight == 1);
      expect(page.find.matches, isEmpty);
      expect(page.paint(tester).matchRects, isEmpty);
      expect(page.reads.inFlight, 1);
      gate.complete();
      await pumpSurfaceFind(tester);
      await pumpSurfaceFind(tester);
      expect(page.find.matches, hasLength(2));
      expect(page.find.current!.entry.text, 'replacement bodyneedle bodyneedle');
      expect(page.find.matches.any((hit) => hit.entry.text == 'bodyneedle'), isFalse);
      expect(page.paint(tester).matchRects, hasLength(2));
      expect(page.dashboard.canUndo, isFalse);
    } finally {
      if (!loaded.isCompleted) loaded.complete(_document(''));
      await page.dispose(tester);
    }
  });

  testWidgets('real preview excludes ellipsized suffix and clipped lazy blocks '
      'without expanding or changing saved layout', (tester) async {
    final page = _PreviewHarness();
    page.loader.value = Future.value(_document(
      'bodyneedle ${List.filled(180, 'filler').join(' ')} invisible-suffix',
      tail: 'unloaded-tail',
    ));
    try {
      await page.mount(tester);
      final before = page.dashboard.document;
      await page.query(tester, 'bodyneedle');
      expect(page.find.matches, hasLength(1));
      final run = page.paint(tester).textRuns.first;
      expect((run.render as RenderParagraph).didExceedMaxLines, isTrue);
      expect(run.text, contains('invisible-suffix'));
      for (final hidden in ['invisible-suffix', 'unloaded-tail']) {
        await page.query(tester, hidden);
        expect(page.find.matches, isEmpty);
        expect(page.paint(tester).matchRects, isEmpty);
      }
      page.find.setOptions(const FindOptions(useRegex: true));
      await page.query(tester, 'bodyneedle[\\s\\S]*invisible-suffix');
      expect(page.find.matches, isEmpty,
          reason: 'A visible prefix is not an exact hit for a clipped phrase');
      expect(page.paint(tester).matchRects, isEmpty);
      expect(page.dashboard.document, same(before));
      expect(page.dashboard.canUndo, isFalse);
    } finally {
      await page.dispose(tester);
    }
  });

  testWidgets('real rich preview preserves styled spans and newlines in native '
      'range geometry', (tester) async {
    final page = _PreviewHarness();
    page.loader.value = Future.value(const FolderGalleryPreview(
      kind: FolderGalleryPreviewKind.document,
      blocks: [FolderGalleryPreviewBlock(
        kind: FolderGalleryPreviewBlockKind.paragraph,
        runs: [
          FolderGalleryTextRun(text: 'body', bold: true),
          FolderGalleryTextRun(text: 'needle\nsecond e\u0301', italic: true),
        ],
      )],
      wordCount: 0, readingMinutes: 0, tags: [], fileTypeLabel: 'PAGE',
    ));
    try {
      await page.mount(tester);
      await page.query(tester, 'bodyneedle\nsecond');
      expect(page.find.matches, hasLength(1));
      final paint = page.paint(tester);
      final run = paint.textRuns.single;
      expect(run.text, 'bodyneedle\nsecond e\u0301');
      final hit = page.find.current!;
      final native = run.boxes(hit.range.start, hit.range.end)
          .map((box) => MatrixUtils.transformRect(
              run.render.getTransformTo(paint), box.toRect())).toList();
      expect(native.length, greaterThanOrEqualTo(2));
      expect(paint.matchRects, native);
      await page.query(tester, 'e\u0301');
      expect(page.find.matches, hasLength(1));
      expect(paint.matchRects, isNotEmpty);
      expect(page.dashboard.canUndo, isFalse);
    } finally {
      await page.dispose(tester);
    }
  });

  for (final excluded in ['hidden', 'collapsed', 'protected', 'provider',
    'cover', 'wrong-view', 'stale-view', 'unavailable', 'sealed']) {
    testWidgets('real default preview excludes $excluded body', (tester) async {
      final page = _PreviewHarness(
          hidden: excluded == 'hidden', collapsed: excluded == 'collapsed');
        page.loader.value = Future.value(_document(
          excluded == 'sealed' ? 'af1.nonce.bodyneedle' : 'bodyneedle',
          unavailable: excluded == 'unavailable'));
      if (excluded == 'protected') page.reads.allowed = false;
      if (excluded == 'provider') {
        page.view.extra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');
      }
      if (excluded == 'cover') {
        page.view.extra = ViewCoverCodec.mergeCover('', const PageStyleCover(
          type: PageStyleCoverImageType.pureColor, value: '#D9C7A4'));
      }
      if (excluded == 'wrong-view') {
        page.reads.wrongView = ViewPB(id: 'not-the-embed', layout: ViewLayoutPB.Document);
      }
      if (excluded == 'stale-view') {
        page.renderedView = ViewPB.fromBuffer(page.view.writeToBuffer())
          ..lastEdited = Int64(99);
      }
      try {
        await page.mount(tester);
        await page.query(tester, 'bodyneedle');
        expect(page.find.matches, isEmpty);
        expect(page.paint(tester).matchRects, isEmpty);
        expect(page.dashboard.canUndo, isFalse);
        expect(page.reads.forbiddenReads, isEmpty);
      } finally {
        await page.dispose(tester);
      }
    });
  }

  testWidgets('cancelled real-preview read retains shared scheduler slot and '
      'cannot publish after close', (tester) async {
    final page = _PreviewHarness();
    page.loader.value = Future.value(_document('bodyneedle'));
    final gate = page.reads.hold('view:${_PreviewHarness.ownerId}');
    try {
      await page.mount(tester);
      await page.query(tester, 'bodyneedle');
      expect(page.reads.inFlight, 1);
      page.find.close();
      var nextStarted = false;
      page.reads.scheduler.schedule(Object(), () => true, () async {
        nextStarted = true;
      });
      await tester.pump();
      expect(nextStarted, isFalse);
      expect(page.find.matches, isEmpty);
      gate.complete();
      await pumpSurfaceFind(tester);
      expect(nextStarted, isTrue);
      expect(page.reads.maxInFlight, 1);
      expect(page.find.matches, isEmpty);
      expect(page.paint(tester).matchRects, isEmpty);
    } finally {
      await page.dispose(tester);
    }
  });
}

FolderGalleryPreview _document(String text, {
  String? tail,
  bool unavailable = false,
}) => FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: [
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.paragraph,
      runs: [FolderGalleryTextRun(text: text, bold: true)],
    ),
    if (tail != null) ...[
      for (var index = 0; index < 20; index++)
        const FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.paragraph,
          runs: [FolderGalleryTextRun(text: 'ordinary filler line')],
        ),
      FolderGalleryPreviewBlock(
        kind: FolderGalleryPreviewBlockKind.paragraph,
        runs: [FolderGalleryTextRun(text: tail)],
      ),
    ],
  ],
  wordCount: 0,
  readingMinutes: 0,
  tags: const ['unrendered-tag'],
  fileTypeLabel: 'PAGE',
  unavailable: unavailable,
);

FolderGalleryPreview _table() => const FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.database,
  blocks: [], wordCount: 0, readingMinutes: 0, tags: [], fileTypeLabel: 'TABLE',
  database: FolderGalleryDatabaseSnapshot(
    columns: ['Task', 'Link'],
    rows: [
      ['bodyneedle', 'https://example.test/url-secret'],
      ['bodyneedle', 'https://example.test/url-secret'],
    ],
    totalRowCount: 25,
    fieldTypes: [FieldType.RichText, FieldType.URL],
  ),
);

/// Only IO is injected. The production PagePreviewCard, cache, thumbnail,
/// rich paragraphs/table rows, dashboard bridge and shared painter are real.
class _PreviewLoader extends FolderGalleryPreviewLoader {
  Future<FolderGalleryPreview> value = Future.value(_document(''));
  int calls = 0;

  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) {
    calls++;
    return value;
  }
}

class _PreviewHarness {
  _PreviewHarness({String type = 'page',
    ViewLayoutPB layout = ViewLayoutPB.Document,
    bool hidden = false, bool collapsed = false,
  }) : reads = DatabaseFindReads(layout: layout) {
    view.name = 'target-title-only';
    reads.addView(ownerId, 'dashboard owner', layout: ViewLayoutPB.Document);
    final spec = DashboardWidgetSpec(
      id: 'preview', type: type, title: 'widget-title-only',
      showTitle: false,
      hidden: hidden, collapsed: collapsed,
      source: const DashboardDataSource(kind: DashboardSourceKind.page,
          viewId: databaseFindViewId),
    );
    dashboard = DashboardController(viewId: ownerId,
      document: DashboardDocument(sections: [
        DashboardSection(id: 'section', widgets: [spec]),
      ]));
    find = DashboardFindController(dashboard,
        title: () => 'dashboard title', readProvider: reads.provider());
    cache = FolderGalleryPreviewCache(loader: loader);
  }

  static const ownerId = 'dashboard-owner';
  final DatabaseFindReads reads;
  final loader = _PreviewLoader();
  final scroll = ScrollController();
  final revision = ValueNotifier(0);
  late final FolderGalleryPreviewCache cache;
  late final DashboardController dashboard;
  late final DashboardFindController find;
  ViewPB? renderedView;
  ViewPB get view => reads.views[databaseFindViewId]!;

  Future<void> mount(WidgetTester tester, {
    WorkspaceDesignAppearance appearance = WorkspaceDesignAppearance.light,
  }) async {
    await tester.pumpWidget(surfaceFindTestApp(SurfaceFindHost(
      controller: find,
      child: SingleChildScrollView(controller: scroll, child: Column(children: [
        const SizedBox(height: 850),
        SizedBox(width: 480, height: 320,
          child: DashboardFindEmbed(dashboard: dashboard,
            spec: dashboard.document.allWidgets.single,
            child: ValueListenableBuilder<int>(valueListenable: revision,
              builder: (_, __, ___) => PagePreviewCard(
                view: renderedView ?? view, userProfile: null,
                previewCache: cache, onOpen: () {},
              ),
            ),
          ),
        ),
        const SizedBox(height: 200),
      ])),
    ), appearance: appearance));
    await pumpSurfaceFind(tester);
  }

  Future<void> query(WidgetTester tester, String query) async {
    if (!find.isOpen) find.open();
    find.setQuery(query);
    await pumpSurfaceFind(tester);
    await pumpSurfaceFind(tester);
  }

  void replacePreview(FolderGalleryPreview preview) {
    loader.value = Future.value(preview);
    cache.invalidate(view.id);
    revision.value++;
  }

  RenderSurfaceFindHighlight paint(WidgetTester tester) =>
      tester.renderObject<RenderSurfaceFindHighlight>(
        findHighlight(),
      );

  Finder findHighlight() => _findByTypeHighlight();

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    find.dispose();
    dashboard.dispose();
    scroll.dispose();
    revision.dispose();
    reads.dispose();
  }
}

// Outside the harness because its controller deliberately has the name find.
Finder _findByTypeHighlight() => find.descendant(
  of: find.byType(DashboardFindEmbed),
  matching: find.byType(SurfaceFindHighlight),
);