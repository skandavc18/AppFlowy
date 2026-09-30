import 'dart:ui';

import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboards, canvases and saved links keep their whole content on the view.
/// Their gallery previews come from there — never from an empty document, and
/// never "unavailable" for want of a file.
void main() {
  late _NoDocuments documents;
  late List<Uri> remote;
  late FolderGalleryPreviewLoader loader;

  setUp(() {
    documents = _NoDocuments();
    remote = [];
    loader = FolderGalleryPreviewLoader(
      documentService: documents,
      remoteReader: (uri, _) async {
        remote.add(uri);
        return null;
      },
    );
  });

  tearDown(() {
    expect(documents.requested, isEmpty);
    expect(remote, isEmpty);
  });

  Future<FolderGalleryPreview> load(ViewPB view) =>
      loader.load(view: view, item: WorkspaceExplorerItem.fromView(view));

  test('a dashboard previews its own widgets', () async {
    const heading = DashboardWidgetSpec(
      id: 'w-heading',
      type: 'heading',
      placement: DashboardPlacement(columnSpan: 12, rowSpan: 1),
      settings: {'text': 'Quarterly goals'},
    );
    final document = const DashboardDocument().addWidget(heading);
    final view = ViewPB(
      id: 'dashboard',
      name: 'Operations',
      layout: ViewLayoutPB.Document,
      extra: DashboardMetadata(document: document).mergeIntoExtra(''),
    );
    final preview = await load(view);
    expect(preview.kind, FolderGalleryPreviewKind.dashboard);
    expect(preview.unavailable, isFalse);
    expect(preview.hasHero, isFalse);
    expect(preview.fileTypeLabel, 'DASHBOARD');
    expect(preview.dashboard, document);
    expect(preview.dashboard!.widgetById('w-heading'), heading);
  });

  test('a canvas previews its own cards', () async {
    const document = CanvasDocument(
      nodes: [
        CanvasNode(
          id: 'idea',
          kind: CanvasNodeKind.text,
          position: Offset(40, 60),
          size: Size(260, 120),
          text: 'Launch idea',
        ),
      ],
    );
    final view = ViewPB(
      id: 'canvas',
      name: 'Brainstorm',
      layout: ViewLayoutPB.Document,
      extra: const CanvasMetadata(document: document).mergeIntoExtra(''),
    );
    final preview = await load(view);
    expect(preview.kind, FolderGalleryPreviewKind.canvas);
    expect(preview.unavailable, isFalse);
    expect(preview.fileTypeLabel, 'CANVAS');
    expect(preview.canvas?.nodes.single.text, 'Launch idea');
  });

  test('a saved link previews what was learned about its page', () async {
    final link = BookmarkMetadata(
      url: 'https://www.hindustantimes.com/india-news/story',
      title: 'A headline',
      description: 'What the story says about itself.',
      imageUrl: 'https://images.example.test/cover.jpg',
      tags: const ['news'],
    );
    final view = ViewPB(
      id: 'link',
      name: 'hindustantimes.com',
      layout: ViewLayoutPB.Document,
      extra: link.mergeIntoExtra(
        BookmarkMetadata.newExtra(link.url),
      ),
    );
    final item = WorkspaceExplorerItem.fromView(view);
    // It is a stored file with no stored bytes — the case that used to read
    // as "preview unavailable".
    expect(item.isFile, isTrue);
    expect(item.metadata?.storageUrl ?? '', isEmpty);

    final preview = await load(view);
    expect(preview.kind, FolderGalleryPreviewKind.link);
    expect(preview.unavailable, isFalse);
    expect(preview.fileTypeLabel, 'LINK');
    expect(preview.link?.description, 'What the story says about itself.');
    expect(preview.tags, ['news']);
    // The picture belongs to the link face, never to the image path.
    expect(preview.hasHero, isFalse);
  });

  test('a link that could not be fetched still has a preview', () async {
    final view = ViewPB(
      id: 'short-link',
      name: 'lnkd.in',
      layout: ViewLayoutPB.Document,
      extra: BookmarkMetadata(url: 'https://lnkd.in/abc', fetchFailed: true)
          .mergeIntoExtra(BookmarkMetadata.newExtra('https://lnkd.in/abc')),
    );
    final preview = await load(view);
    expect(preview.kind, FolderGalleryPreviewKind.link);
    expect(preview.unavailable, isFalse);
  });

  test('a failed read never turns these into unavailable previews', () {
    for (final view in [
      ViewPB(
        id: 'dashboard',
        layout: ViewLayoutPB.Document,
        extra: DashboardMetadata(document: DashboardDocument.blank())
            .mergeIntoExtra(''),
      ),
      ViewPB(
        id: 'canvas',
        layout: ViewLayoutPB.Document,
        extra: CanvasMetadata.newExtra(),
      ),
      ViewPB(
        id: 'link',
        layout: ViewLayoutPB.Document,
        extra: BookmarkMetadata.newExtra('https://example.test'),
      ),
    ]) {
      final preview = FolderGalleryPreviewParser.unavailable(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
      );
      expect(preview.unavailable, isFalse, reason: view.id);
      expect(
        preview.kind,
        switch (view.id) {
          'dashboard' => FolderGalleryPreviewKind.dashboard,
          'canvas' => FolderGalleryPreviewKind.canvas,
          _ => FolderGalleryPreviewKind.link,
        },
      );
    }
  });

  test('an ordinary page is still read from its document', () async {
    documents.answer = true;
    final preview = await load(
      ViewPB(id: 'page', name: 'Notes', layout: ViewLayoutPB.Document),
    );
    expect(preview.kind, FolderGalleryPreviewKind.document);
    expect(documents.requested, ['page']);
    documents.requested.clear();
  });
}

class _NoDocuments extends DocumentService {
  final requested = <String>[];
  bool answer = false;

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
  }) async {
    requested.add(documentId);
    if (!answer) throw StateError('Unexpected document read');
    return FlowyResult.success(
      DocumentDataPB(
        pageId: 'root',
        blocks: {
          'root': BlockPB(id: 'root', ty: 'page', childrenId: 'children'),
        },
        meta: MetaPB(childrenMap: {'children': ChildrenPB()}),
      ),
    );
  }
}
