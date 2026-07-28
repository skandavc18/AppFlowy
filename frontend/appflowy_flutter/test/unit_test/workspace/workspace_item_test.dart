import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceItemMetadata', () {
    test('merges into existing view metadata without overwriting it', () {
      const metadata = WorkspaceItemMetadata.folder();
      final extra = metadata.mergeIntoExtra(
        jsonEncode({
          'cover': {'type': 1, 'value': 'cover'},
          'is_space': true,
          'future_key': {'enabled': true},
        }),
      );
      final decoded = jsonDecode(extra) as Map<String, dynamic>;

      expect(decoded['cover'], {'type': 1, 'value': 'cover'});
      expect(decoded['is_space'], isTrue);
      expect(decoded['future_key'], {'enabled': true});
      expect(
        decoded[WorkspaceItemMetadata.envelopeKey],
        containsPair('kind', 'folder'),
      );
    });

    test('round trips file metadata', () {
      final modifiedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final metadata = WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        mimeType: 'application/pdf',
        storageUrl: 'https://example.test/file',
        size: 4096,
        modifiedAt: modifiedAt,
      );

      final parsed =
          WorkspaceItemMetadata.fromExtra(metadata.mergeIntoExtra(''));

      expect(parsed?.kind, WorkspaceItemKind.file);
      expect(parsed?.contentKind, WorkspaceFileContentKind.binary);
      expect(parsed?.mimeType, 'application/pdf');
      expect(parsed?.storageUrl, 'https://example.test/file');
      expect(parsed?.size, 4096);
      expect(parsed?.modifiedAt, modifiedAt);
    });

    test('exposes an existing stored file as an embeddable reference', () {
      final view = ViewPB(
        id: 'file-id',
        name: 'report.pdf',
        extra: const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          mimeType: 'application/pdf',
          storageUrl: 'C:\\AppFlowy\\files\\report.pdf',
        ).mergeIntoExtra(''),
      );

      final reference = view.workspaceFileReference;

      expect(reference?.viewId, 'file-id');
      expect(reference?.name, 'report.pdf');
      expect(reference?.url, 'C:\\AppFlowy\\files\\report.pdf');
      expect(reference?.mimeType, 'application/pdf');
      expect(reference?.isLocal, isTrue);
    });

    test('derives reference locality from its storage URL', () {
      const remote = WorkspaceFileReference(
        viewId: 'remote-file',
        name: 'report.pdf',
        url: 'https://cloud.appflowy.test/report.pdf',
        mimeType: 'application/pdf',
      );
      const localUri = WorkspaceFileReference(
        viewId: 'local-file',
        name: 'report.pdf',
        url: 'file:///C:/AppFlowy/files/report.pdf',
        mimeType: 'application/pdf',
      );

      expect(remote.isLocal, isFalse);
      expect(localUri.isLocal, isTrue);
    });

    test('does not expose workspace files without stored content', () {
      final legacyFile = ViewPB(
        id: 'legacy-file',
        extra: const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.collaborativeText,
        ).mergeIntoExtra(''),
      );

      expect(legacyFile.workspaceFileReference, isNull);
    });

    test('ignores malformed and unsupported metadata', () {
      expect(WorkspaceItemMetadata.fromExtra('{invalid'), isNull);
      expect(
        WorkspaceItemMetadata.fromExtra(
          jsonEncode({
            WorkspaceItemMetadata.envelopeKey: {
              'version': WorkspaceItemMetadata.currentVersion + 1,
              'kind': 'folder',
            },
          }),
        ),
        isNull,
      );
      expect(
        WorkspaceItemMetadata.fromExtra(
          jsonEncode({
            WorkspaceItemMetadata.envelopeKey: {
              'version': 1,
              'kind': 'file',
              'content_kind': 'unknown',
            },
          }),
        ),
        isNull,
      );
    });

    test('classifies only views with a valid envelope', () {
      final folder = ViewPB(
        id: 'folder',
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final document = ViewPB(id: 'document', extra: '{}');

      expect(folder.isWorkspaceFolder, isTrue);
      expect(folder.isWorkspaceFile, isFalse);
      expect(document.isWorkspaceItem, isFalse);
    });

    test('recognizes only the backing view for the active workspace as root',
        () {
      final root = ViewPB(id: 'workspace', parentViewId: '');
      final child = ViewPB(id: 'workspace', parentViewId: 'parent');

      expect(root.isWorkspaceRootFor('workspace'), isTrue);
      expect(root.isWorkspaceRootFor('other-workspace'), isFalse);
      expect(root.isWorkspaceRootFor(''), isFalse);
      expect(child.isWorkspaceRootFor('workspace'), isFalse);
    });

    test('builds a synthetic workspace root folder view', () {
      final root = workspaceRootFolderView(
        workspaceId: 'workspace',
        name: 'Knowledge HQ',
        icon: '🚀',
        cover: const PageStyleCover(
          type: PageStyleCoverImageType.builtInImage,
          value: '7',
        ),
      );

      expect(root.id, 'workspace');
      expect(root.name, 'Knowledge HQ');
      expect(root.parentViewId, isEmpty);
      expect(root.layout, ViewLayoutPB.Document);
      expect(root.isWorkspaceFolder, isTrue);
      expect(root.icon.value, '🚀');
      expect(
        ViewCoverCodec.decodeCover(root.extra),
        const PageStyleCover(
          type: PageStyleCoverImageType.builtInImage,
          value: '7',
        ),
      );
    });

    test('normalizes a backend workspace root without losing its fields', () {
      final root = ViewPB(
        id: 'workspace',
        parentViewId: '',
        name: 'Backend root',
        layout: ViewLayoutPB.Document,
        extra: jsonEncode({
          'cover': {'type': 1, 'value': 'cover'},
        }),
        lastEdited: Int64(1800000000),
      );

      final normalized = root.asWorkspaceRootFolder(
        workspaceId: 'workspace',
        name: 'Knowledge HQ',
        icon: '🧠',
      );
      final extra = jsonDecode(normalized.extra) as Map<String, dynamic>;

      expect(root.isWorkspaceFolder, isFalse);
      expect(normalized.name, 'Knowledge HQ');
      expect(normalized.isWorkspaceRootFolder, isTrue);
      expect(normalized.icon.value, '🧠');
      expect(normalized.lastEdited, root.lastEdited);
      expect(extra['cover'], {'type': 1, 'value': 'cover'});
    });

    test('normalizes a workspace cover into the synthetic root', () {
      final root = ViewPB(
        id: 'workspace',
        parentViewId: '',
        name: 'Backend root',
        layout: ViewLayoutPB.Document,
      );
      const cover = PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#C0D7B7',
      );

      final normalized = root.asWorkspaceRootFolder(
        workspaceId: 'workspace',
        cover: cover,
      );

      expect(normalized.isWorkspaceRootFolder, isTrue);
      expect(ViewCoverCodec.decodeCover(normalized.extra), cover);
    });

    test('allows folders and ordinary documents to contain moved items', () {
      final folder = ViewPB(
        layout: ViewLayoutPB.Document,
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final document = ViewPB(layout: ViewLayoutPB.Document);
      final file = ViewPB(
        layout: ViewLayoutPB.Document,
        extra: const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.collaborativeText,
        ).mergeIntoExtra(''),
      );
      final grid = ViewPB(layout: ViewLayoutPB.Grid);

      expect(folder.canContainWorkspaceItems, isTrue);
      expect(document.canContainWorkspaceItems, isTrue);
      expect(file.canContainWorkspaceItems, isFalse);
      expect(grid.canContainWorkspaceItems, isFalse);
    });
  });

  test('explorer item prefers the backend last-edited timestamp', () {
    final view = ViewPB(
      id: 'file',
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ).mergeIntoExtra(''),
      lastEdited: Int64(1800000000),
    );

    final item = WorkspaceExplorerItem.fromView(view);

    expect(
      item.lastEdited,
      DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000),
    );
  });

  test('image data preserves its workspace file reference', () {
    final encoded = ImageBlockData(
      url: 'C:\\AppFlowy\\files\\photo.png',
      type: CustomImageType.local,
      workspaceFileId: 'workspace-image-id',
    ).toJson();

    final decoded = ImageBlockData.fromJson(encoded);

    expect(decoded.url, 'C:\\AppFlowy\\files\\photo.png');
    expect(decoded.type, CustomImageType.local);
    expect(decoded.workspaceFileId, 'workspace-image-id');
  });
}
