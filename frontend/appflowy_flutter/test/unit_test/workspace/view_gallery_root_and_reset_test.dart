import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

const _stamped = PageStyleCover(
  type: PageStyleCoverImageType.builtInImage,
  value: '3',
);

void main() {
  test('a canvas never wears the cover stamped on it; a dashboard does', () {
    final canvas = ViewPB(
      id: 'canvas',
      layout: ViewLayoutPB.Document,
      extra: ViewCoverCodec.mergeCover(
        CanvasMetadata.newExtra(document: CanvasDocument.blank()),
        _stamped,
      ),
    );
    final dashboard = ViewPB(
      id: 'dashboard',
      layout: ViewLayoutPB.Document,
      extra: ViewCoverCodec.mergeCover(
        const DashboardMetadata(document: DashboardDocument())
            .mergeIntoExtra(''),
        _stamped,
      ),
    );
    expect(canvas.isCanvas, isTrue);
    expect(canvas.cover, isNull);
    expect(dashboard.cover, _stamped);
  });

  group('the workspace itself in a library', () {
    final workspace = UserWorkspacePB(
      workspaceId: 'ws',
      name: 'My Workspace',
      icon: '🌿',
    );
    final root = ViewPB(id: 'ws', name: '', layout: ViewLayoutPB.Document);
    final page = ViewPB(
      id: 'page',
      name: 'Notes',
      parentViewId: 'ws',
      layout: ViewLayoutPB.Document,
    );

    test('is listed as its folder, with its name and icon', () {
      final entries = viewGalleryEntriesWithRoot(
        [ViewGalleryEntry(view: root), ViewGalleryEntry(view: page)],
        workspace,
      );
      expect(entries.first.view.isWorkspaceRootFolder, isTrue);
      expect(entries.first.view.name, 'My Workspace');
      expect(entries.first.view.icon.value, isNotEmpty);
      expect(entries.last.view, same(page));
    });

    test('lists without a workspace are left alone', () {
      final entries = [ViewGalleryEntry(view: page)];
      expect(viewGalleryEntriesWithRoot(entries, null), same(entries));
      expect(viewGalleryEntriesWithRoot(entries, workspace), same(entries));
    });

    test('previews as a folder without reading a document', () async {
      final documents = _Documents();
      final loader = FolderGalleryPreviewLoader(documentService: documents);
      final folder = viewGalleryEntriesWithRoot(
        [ViewGalleryEntry(view: root)],
        workspace,
      ).single.view;
      final preview = await loader.load(
        view: folder,
        item: WorkspaceExplorerItem.fromView(folder),
      );
      expect(preview.kind, FolderGalleryPreviewKind.folder);
      expect(preview.unavailable, isFalse);
      expect(documents.requested, isEmpty);
    });
  });

  test('recent pages survive a workspace reset of the shared history',
      () async {
    final recents = _SharedRecents([_section('launch'), _section('notes')]);
    final source = RecentViewGallerySource(
      read: () async => recents.stored,
      remove: (_) async {},
      recents: recents,
    );
    await source.load();
    await _settle();
    expect(source.entries.map((entry) => entry.id), ['launch', 'notes']);

    // What the sidebar does once the workspace is known at launch.
    await recents.reset();
    await _settle();
    expect(source.entries.map((entry) => entry.id), ['launch', 'notes']);
    expect(recents.reads, 2);

    // A history that really is empty still shows as empty.
    recents.stored = [];
    await recents.reset();
    await _settle();
    expect(source.entries, isEmpty);

    source.dispose();
    await recents.dispose();
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

SectionViewPB _section(String id) => SectionViewPB(
      item: ViewPB(
        id: id,
        name: id,
        parentViewId: 'space',
        layout: ViewLayoutPB.Document,
      ),
    );

/// The shared history without its backend: a reset empties it and leaves it
/// idle until it is asked again, as the real one does.
class _SharedRecents extends CachedRecentService {
  _SharedRecents(this.stored);

  List<SectionViewPB> stored;
  bool _armed = false;
  int reads = 0;

  @override
  Future<List<SectionViewPB>> recentViews() async {
    if (_armed) return notifier.value;
    _armed = true;
    reads++;
    await Future<void>.delayed(Duration.zero);
    notifier.value = stored;
    return notifier.value;
  }

  @override
  Future<void> reset() async {
    _armed = false;
    notifier.value = const [];
  }
}

class _Documents extends DocumentService {
  final requested = <String>[];

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
  }) async {
    requested.add(documentId);
    return FlowyResult.failure(FlowyError(msg: 'Lack of document data'));
  }
}
