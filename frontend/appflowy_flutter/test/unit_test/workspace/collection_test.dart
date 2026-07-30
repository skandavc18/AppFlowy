import 'dart:convert';

import 'package:appflowy/plugins/collection/collection_views.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('collection metadata', () {
    test('round trips through the view extra envelope', () {
      const metadata = CollectionMetadata(
        kind: CollectionKind.album,
        activeViewId: CollectionViewIds.list,
      );
      final decoded = CollectionMetadata.fromExtra(metadata.mergeIntoExtra(''));

      expect(decoded, isNotNull);
      expect(decoded!.kind, CollectionKind.album);
      expect(decoded.activeViewId, CollectionViewIds.list);
    });

    test('leaves every other key in extra untouched', () {
      final existing = jsonEncode({
        'font': 'Inter',
        WorkspaceItemMetadata.envelopeKey:
            const WorkspaceItemMetadata.folder().toJson(),
      });
      const metadata = CollectionMetadata(kind: CollectionKind.book);

      final values = jsonDecode(metadata.mergeIntoExtra(existing)) as Map;

      expect(values['font'], 'Inter');
      expect(values[WorkspaceItemMetadata.envelopeKey], isA<Map>());
      expect(values[CollectionMetadata.envelopeKey], isA<Map>());
    });

    test('a new collection is also a workspace folder', () {
      final view = ViewPB(extra: CollectionMetadata.newExtra(CollectionKind.book));

      expect(view.isCollection, isTrue);
      expect(view.isWorkspaceFolder, isTrue);
      expect(view.collection!.kind, CollectionKind.book);
      expect(view.collection!.createdAt, isNotNull);
    });

    test('a plain folder is not a collection', () {
      final view = ViewPB(
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );

      expect(view.isCollection, isFalse);
      expect(view.isWorkspaceFolder, isTrue);
    });

    test('rejects an unknown kind and a newer envelope version', () {
      final unknownKind = jsonEncode({
        CollectionMetadata.envelopeKey: {'version': 1, 'kind': 'podcast'},
      });
      final futureVersion = jsonEncode({
        CollectionMetadata.envelopeKey: {
          'version': CollectionMetadata.currentVersion + 1,
          'kind': 'book',
        },
      });

      expect(CollectionMetadata.fromExtra(unknownKind), isNull);
      expect(CollectionMetadata.fromExtra(futureVersion), isNull);
      expect(CollectionMetadata.fromExtra('not json'), isNull);
      expect(CollectionMetadata.fromExtra(''), isNull);
    });

    test('per view state is stored and cleared by view id', () {
      const metadata = CollectionMetadata(kind: CollectionKind.book);

      final withState = metadata.withStateFor('reader', {'page': 12});
      expect(withState.stateFor('reader'), {'page': 12});
      expect(withState.stateFor('gallery'), isEmpty);

      final restored =
          CollectionMetadata.fromExtra(withState.mergeIntoExtra(''))!;
      expect(restored.stateFor('reader'), {'page': 12});

      expect(restored.withStateFor('reader', {}).viewState, isEmpty);
    });
  });

  group('collection registry', () {
    test('every kind is registered with at least one adaptive view', () {
      for (final kind in CollectionKind.values) {
        final definition = CollectionRegistry.typeFor(kind);
        expect(definition.kind, kind);
        expect(definition.views, isNotEmpty);
        expect(definition.icon, isA<IconData>());
      }
      expect(CollectionRegistry.types.length, CollectionKind.values.length);
    });

    test('resolves a stored view and falls back to the default', () {
      final resolved = CollectionRegistry.resolveView(
        CollectionKind.album,
        CollectionViewIds.list,
      );
      expect(resolved.id, CollectionViewIds.list);

      final fallback =
          CollectionRegistry.resolveView(CollectionKind.album, 'retired-view');
      expect(
        fallback.id,
        CollectionRegistry.typeFor(CollectionKind.album).defaultView.id,
      );
    });

    test('a new visualisation registers itself without touching the type', () {
      addTearDown(CollectionRegistry.reset);

      final before = CollectionRegistry.typeFor(CollectionKind.book).views.length;
      CollectionRegistry.registerView(
        CollectionKind.book,
        CollectionViewDefinition(
          id: 'reader',
          labelKey: 'collections.views.gallery',
          icon: Icons.chrome_reader_mode_rounded,
          builder: (_, __) => const SizedBox.shrink(),
        ),
        index: 0,
      );

      final views = CollectionRegistry.typeFor(CollectionKind.book).views;
      expect(views.length, before + 1);
      expect(views.first.id, 'reader');
      expect(
        CollectionRegistry.typeFor(CollectionKind.album)
            .views
            .map((view) => view.id),
        isNot(contains('reader')),
      );
    });

    test('registering the same view id replaces it', () {
      addTearDown(CollectionRegistry.reset);

      final before =
          CollectionRegistry.typeFor(CollectionKind.email).views.length;
      CollectionRegistry.registerView(
        CollectionKind.email,
        CollectionViewDefinition(
          id: CollectionViewIds.list,
          labelKey: 'collections.views.list',
          icon: Icons.forum_rounded,
          builder: (_, __) => const SizedBox.shrink(),
        ),
      );

      final views = CollectionRegistry.typeFor(CollectionKind.email).views;
      expect(views.length, before);
      expect(
        views.where((view) => view.id == CollectionViewIds.list).single.icon,
        Icons.forum_rounded,
      );
    });
  });

  group('explorer items', () {
    test('carry the collection kind so containers are told apart', () {
      final collection = WorkspaceExplorerItem.fromView(
        ViewPB(extra: CollectionMetadata.newExtra(CollectionKind.repository)),
      );
      final folder = WorkspaceExplorerItem.fromView(
        ViewPB(extra: const WorkspaceItemMetadata.folder().mergeIntoExtra('')),
      );

      expect(collection.isFolder, isTrue);
      expect(collection.isCollection, isTrue);
      expect(collection.collection!.kind, CollectionKind.repository);
      expect(folder.isCollection, isFalse);
    });
  });
}
