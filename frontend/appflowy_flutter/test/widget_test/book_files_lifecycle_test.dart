import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/collection_views.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_view.dart';
import 'package:appflowy/plugins/collection/views/book/book_views.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_tree.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

void main() {
  final recents = RecentIcons.enable;
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  tearDownAll(() => RecentIcons.enable = recents);

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
      '$appearance: Files refresh never writes into its parent build',
      (tester) async {
        final fixture = _Book(CollectionViewIds.gallery);
        try {
          await fixture.controller.initialize();
          await tester.pumpWidget(vividIconTestApp(appearance, fixture.page));
          await tester.pumpAndSettle();
          final explorer = tester.state(find.byType(FolderExplorer));
          final gallery = tester.state(find.byType(FolderGallery));
          final nested = tester.state<NestedScrollViewState>(
            find.byType(NestedScrollView),
          );
          final root = ViewPB.fromBuffer(fixture.root.writeToBuffer())
            ..name = 'The live collection name';
          fixture.controller.updateView(root);
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(FolderExplorer)), same(explorer));
          expect(tester.state(find.byType(FolderGallery)), same(gallery));
          expect(
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView)),
            same(nested),
          );
          expect(fixture.controller.root.name, root.name);
          expect(fixture.repository.reads, 1);
          expect(fixture.service.writes, isEmpty);
          expect(tester.binding.hasScheduledFrame, isFalse);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          fixture.controller.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$appearance: Reader Files List switches flush without lifecycle errors',
      (tester) async {
        final fixture = _Book(BookViewIds.reader);
        try {
          await fixture.controller.initialize();
          await tester.pumpWidget(vividIconTestApp(appearance, fixture.page));
          await tester.pumpAndSettle();
          expect(find.byType(BookReaderView), findsOneWidget);
          for (var round = 0; round < 3; round++) {
            for (final id in [
              CollectionViewIds.gallery,
              CollectionViewIds.list,
              BookViewIds.reader,
            ]) {
              final tab = find.descendant(
                of: find.byType(CollectionViewSwitcher),
                matching: find.byKey(ValueKey(id)),
              );
              await tester.tap(
                find.descendant(of: tab, matching: find.byType(TextButton)),
              );
              await tester.pump();
              expect(tester.takeException(), isNull);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(
                tester
                    .widget<CollectionViewSwitcher>(
                      find.byType(CollectionViewSwitcher),
                    )
                    .activeViewId,
                id,
              );
              expect(fixture.service.writes.last.activeViewId, id);
              expect(
                find.byType(
                  switch (id) {
                    CollectionViewIds.gallery => FolderGallery,
                    CollectionViewIds.list => ExplorerTree,
                    _ => BookReaderView,
                  },
                ),
                findsOneWidget,
              );
              expect(tester.binding.hasScheduledFrame, isFalse);
            }
          }
          final savedBook = fixture.service.writes.last.stateFor(bookStateKey);
          expect(
            savedBook['stats'],
            isNotNull,
            reason:
                'The reader still saves its final session, not just its tab.',
          );
          expect(fixture.repository.reads, 1);
          expect(fixture.controller.childrenOf(fixture.root.id), hasLength(1));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Closing the book also flushes while the tree is locked.',
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          fixture.controller.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}

class _Book {
  _Book(String mode) {
    root = ViewPB(
      id: 'books-lifecycle',
      name: 'Books',
      layout: ViewLayoutPB.Document,
      extra: CollectionMetadata(kind: CollectionKind.book, activeViewId: mode)
          .mergeIntoExtra(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      ),
    );
    repository = _Repository(root.id);
    controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );
  }

  late final ViewPB root;
  late final _Repository repository;
  late final WorkspaceExplorerController controller;
  final service = _Service();

  Widget get page => SizedBox(
        width: 780,
        height: 580,
        child: CollectionPage(
          view: root,
          controller: controller,
          service: service,
          shellOwnsBreadcrumbs: true,
        ),
      );
}

class _Repository extends Fake implements WorkspaceItemRepository {
  _Repository(this.rootId);
  final String rootId;
  int reads = 0;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) async {
    reads++;
    return FlowyResult.success([
      // A book part exercises real Files cards but needs no native renderer.
      ViewPB(
        id: 'part-one',
        parentViewId: rootId,
        name: 'Part one',
        layout: ViewLayoutPB.Document,
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      ),
    ]);
  }
}

class _Service extends CollectionService {
  final writes = <CollectionMetadata>[];

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required CollectionMetadata metadata,
  }) async {
    writes.add(metadata);
    return FlowyResult.success(ViewPB());
  }
}
