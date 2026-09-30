import 'package:appflowy/plugins/canvas/presentation/canvas_board.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_preview.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_preview_face.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_preview.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_overlay_test_app.dart';

const _heading = DashboardWidgetSpec(
  id: 'w-heading',
  type: 'heading',
  placement: DashboardPlacement(columnSpan: 12, rowSpan: 1),
  settings: {'text': 'Quarterly goals'},
);

const _note = DashboardWidgetSpec(
  id: 'w-note',
  type: 'text',
  placement: DashboardPlacement(row: 1, columnSpan: 6, rowSpan: 3),
  settings: {'text': 'Ship the preview'},
);

const _hidden = DashboardWidgetSpec(
  id: 'w-hidden',
  type: 'text',
  placement: DashboardPlacement(row: 1, column: 6, columnSpan: 6),
  settings: {'text': 'Not for the picture'},
  hidden: true,
);

final _dashboard = const DashboardDocument()
    .addWidget(_heading)
    .addWidget(_note)
    .addWidget(_hidden);

const _canvas = CanvasDocument(
  nodes: [
    CanvasNode(
      id: 'idea',
      kind: CanvasNodeKind.text,
      position: Offset(40, 60),
      size: Size(260, 120),
      text: 'Launch idea',
    ),
    CanvasNode(
      id: 'plan',
      kind: CanvasNodeKind.text,
      position: Offset(420, 60),
      size: Size(260, 120),
      text: 'Plan it',
    ),
  ],
  edges: [CanvasEdge(id: 'link', from: 'idea', to: 'plan')],
);

void main() {
  setUpAll(initializeWorkspaceOverlayTests);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    String appearance = 'light',
    Size size = const Size(420, 320),
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        appearance: appearance,
        textScale: textScale,
        child: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance: a dashboard previews as its real board',
        (tester) async {
      await pump(
        tester,
        DashboardLivePreview(document: _dashboard),
        appearance: appearance,
        size: const Size(560, 420),
      );
      final board = find.byKey(const ValueKey('dashboard-preview-board'));
      expect(board, findsOneWidget);
      expect(
        find.descendant(of: board, matching: find.text('Quarterly goals')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: board, matching: find.text('Ship the preview')),
        findsOneWidget,
      );
      // Drawn small, and never used: nothing inside takes the pointer.
      final boardBox = tester.getRect(board);
      expect(boardBox.width, lessThanOrEqualTo(560));
      expect(
        find.descendant(
          of: board,
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: a dashboard previews as its whole page',
        (tester) async {
      final view = ViewPB(
        id: 'dashboard',
        name: 'Quarterly plan',
        layout: ViewLayoutPB.Document,
        extra: ViewCoverCodec.mergeCover(
          DashboardMetadata(document: _dashboard).mergeIntoExtra(''),
          const PageStyleCover(
            type: PageStyleCoverImageType.pureColor,
            value: '#D9C7A4',
          ),
        ),
      );
      await pump(
        tester,
        DashboardLivePreview(document: _dashboard, view: view),
        appearance: appearance,
        size: const Size(480, 420),
      );
      final header = find.byKey(const ValueKey('dashboard-preview-header'));
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.byType(ViewCoverImage)),
        findsOneWidget,
      );
      final title = find.text('Quarterly plan');
      expect(title, findsOneWidget);
      // Cover, title and board are one page at one scale: the title and the
      // board start at the same page inset, and the cover spans the page less
      // its own small inset on either side.
      final board = find.byType(DashboardBoard);
      expect(
        tester.getTopLeft(title).dx,
        closeTo(tester.getTopLeft(board).dx, 1),
      );
      final page = tester.getRect(find.byType(DashboardLivePreview));
      final cover = tester.getRect(
        find.byKey(const ValueKey('workspace-page-cover')),
      );
      expect(page.right - cover.right, closeTo(cover.left - page.left, 0.5));
      expect(cover.left - page.left, lessThan(8));
      expect(cover.bottom, lessThan(tester.getTopLeft(title).dy));
      expect(
        tester.getTopLeft(title).dy,
        lessThan(tester.getTopLeft(board).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: a dashboard miniature draws its arrangement',
        (tester) async {
      await pump(
        tester,
        DashboardMiniature(document: _dashboard),
        appearance: appearance,
        size: const Size(260, 190),
        textScale: 2,
      );
      final miniature = find.byKey(const ValueKey('dashboard-miniature'));
      expect(miniature, findsOneWidget);
      expect(tester.getSize(miniature), const Size(260, 190));
      // Every visible widget becomes a card; a hidden one does not.
      expect(
        find.descendant(of: miniature, matching: find.byType(Positioned)),
        findsNWidgets(2),
      );
      expect(find.text('Not for the picture'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: a canvas previews as its real board',
        (tester) async {
      await pump(
        tester,
        const CanvasLivePreview(document: _canvas),
        appearance: appearance,
        size: const Size(560, 420),
      );
      expect(
        find.byKey(const ValueKey('canvas-preview-board')),
        findsOneWidget,
      );
      expect(find.textContaining('Launch idea'), findsWidgets);
      expect(find.textContaining('Plan it'), findsWidgets);
      expect(find.byKey(const ValueKey('canvas-preview-empty')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: a canvas miniature paints its cards',
        (tester) async {
      await pump(
        tester,
        const CanvasMiniature(document: _canvas),
        appearance: appearance,
        size: const Size(260, 190),
      );
      final miniature = find.byKey(const ValueKey('canvas-miniature'));
      expect(miniature, findsOneWidget);
      expect(tester.getSize(miniature), const Size(260, 190));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: a saved link previews as its page',
        (tester) async {
      final entry = BookmarkEntry(
        view: ViewPB(id: 'link', name: 'A headline'),
        metadata: const BookmarkMetadata(
          url: 'https://www.hindustantimes.com/india-news/story',
          description: 'What the story says about itself.',
        ),
      );
      await pump(
        tester,
        BookmarkPreviewFace(entry: entry),
        appearance: appearance,
        size: const Size(260, 220),
        textScale: 2,
      );
      expect(
        find.byKey(const ValueKey('bookmark-preview-cover')),
        findsOneWidget,
      );
      expect(find.text('hindustantimes.com'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('bookmark-preview-site')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a canvas preview fills a small pane and follows its size',
      (tester) async {
    // How much wider than the canvas the pane's view of it is.
    Future<double> slack(Size size) async {
      await pump(
        tester,
        const CanvasLivePreview(document: _canvas),
        size: size,
      );
      final board = tester.state<CanvasBoardState>(find.byType(CanvasBoard));
      return board.visibleScene.width / _canvas.bounds.width;
    }

    // A short search pane: the page's roomy margin would leave a stamp.
    expect(await slack(const Size(560, 220)), lessThan(1.15));
    // Resized, it frames everything again.
    expect(await slack(const Size(700, 260)), lessThan(1.15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty boards say so instead of drawing nothing', (tester) async {
    await pump(
      tester,
      const DashboardLivePreview(document: DashboardDocument()),
    );
    expect(find.text('Nothing on this dashboard yet'), findsOneWidget);

    await pump(tester, const CanvasLivePreview(document: CanvasDocument()));
    expect(find.text('Nothing on this canvas yet'), findsOneWidget);

    await pump(
      tester,
      const DashboardMiniature(document: DashboardDocument()),
      size: const Size(200, 150),
    );
    expect(find.text('Nothing on this dashboard yet'), findsOneWidget);

    await pump(
      tester,
      const CanvasMiniature(document: CanvasDocument()),
      size: const Size(200, 150),
    );
    expect(find.text('Nothing on this canvas yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a link with nothing learned shows where it lives',
      (tester) async {
    final entry = BookmarkEntry(
      view: ViewPB(id: 'short', name: 'lnkd.in'),
      metadata: const BookmarkMetadata(
        url: 'https://lnkd.in/abc',
        fetchFailed: true,
      ),
    );
    await pump(tester, BookmarkPreviewFace(entry: entry));
    expect(
      find.byKey(const ValueKey('bookmark-preview-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('lnkd.in/abc'), findsOneWidget);
    // A short card keeps only the picture.
    await pump(
      tester,
      BookmarkPreviewFace(entry: entry),
      size: const Size(200, 90),
    );
    expect(find.byKey(const ValueKey('bookmark-preview-site')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
