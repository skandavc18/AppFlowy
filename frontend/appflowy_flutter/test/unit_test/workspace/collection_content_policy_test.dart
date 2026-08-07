import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_content_policy.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CollectionContentPolicy', () {
    test('every collection type says what it holds', () {
      for (final kind in CollectionKind.values) {
        final policy = CollectionContentPolicy.of(kind);
        expect(policy.isEmpty, isFalse, reason: '$kind offers nothing');
      }
    });

    test('an album takes photographs, film and sound and nothing else', () {
      final policy = CollectionContentPolicy.of(CollectionKind.album);
      expect(
        policy.fileKinds,
        {
          WorkspaceFileKind.image,
          WorkspaceFileKind.video,
          WorkspaceFileKind.audio,
        },
      );
      expect(policy.allowsTables, isFalse);
      expect(policy.allowsCollections, isFalse);
      expect(policy.allowsLinks, isFalse);
      // None of the three can be authored blank, so the album only ever
      // offers to take one from disk.
      expect(
        policy.fileActions.every(
          (action) => action.source == WorkspaceFileSource.upload,
        ),
        isTrue,
      );
    });

    test('a book takes the forms a chapter is written or scanned in', () {
      final policy = CollectionContentPolicy.of(CollectionKind.book);
      expect(
        policy.fileKinds,
        containsAll([
          WorkspaceFileKind.markdown,
          WorkspaceFileKind.html,
          WorkspaceFileKind.pdf,
          WorkspaceFileKind.word,
          WorkspaceFileKind.excel,
          WorkspaceFileKind.powerpoint,
          WorkspaceFileKind.code,
          WorkspaceFileKind.image,
          WorkspaceFileKind.video,
          WorkspaceFileKind.audio,
        ]),
      );
      expect(policy.allowsPages, isTrue);
      expect(policy.allowsTables, isFalse);
      expect(policy.accepts(WorkspaceFileKind.archive), isFalse);
    });

    test('a repository takes anything on disk, but never a table', () {
      final policy = CollectionContentPolicy.of(CollectionKind.repository);
      expect(policy.fileKinds, WorkspaceFileKind.values.toSet());
      expect(policy.allowsPages, isTrue);
      expect(policy.allowsCollections, isTrue);
      expect(policy.allowsTables, isFalse);
    });

    test('a database takes tables, a spreadsheet and a csv', () {
      final policy = CollectionContentPolicy.of(CollectionKind.database);
      expect(policy.allowsTables, isTrue);
      expect(
        policy.fileKinds,
        {WorkspaceFileKind.excel, WorkspaceFileKind.csv},
      );
      expect(policy.allowsPages, isFalse);
      expect(policy.allowsCollections, isFalse);
    });

    test('a bookmark library takes addresses and nothing from disk', () {
      final policy = CollectionContentPolicy.of(CollectionKind.bookmark);
      expect(policy.allowsLinks, isTrue);
      expect(policy.fileKinds, isEmpty);
      expect(policy.fileActions, isEmpty);
      expect(policy.allowsTables, isFalse);
    });

    test('a mailbox takes messages, notes and a folder to file them in', () {
      final policy = CollectionContentPolicy.of(CollectionKind.email);
      expect(policy.allowsMail, isTrue);
      expect(policy.allowsPages, isTrue);
      expect(policy.allowsFolders, isTrue);
      expect(policy.fileKinds, isEmpty);
      expect(policy.allowsTables, isFalse);
    });

    test('offers the shared menu rows in the catalogue order', () {
      final policy = CollectionContentPolicy.of(CollectionKind.database);
      final actions = policy.fileActions;
      expect(
        actions.map((action) => action.kind).toSet(),
        {WorkspaceFileKind.excel, WorkspaceFileKind.csv},
      );
      expect(
        actions.indexWhere(
          (action) => action.source == WorkspaceFileSource.upload,
        ),
        greaterThan(
          actions.lastIndexWhere(
            (action) => action.source == WorkspaceFileSource.create,
          ),
        ),
      );
    });
  });
}
