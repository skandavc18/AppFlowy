import 'dart:convert';

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
}
