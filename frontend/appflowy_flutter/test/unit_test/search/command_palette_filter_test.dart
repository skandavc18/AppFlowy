import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const query = 'roadmap';
  final currentUserId = Int64(42);

  SearchResultItem item({
    required String id,
    required String title,
    String content = '',
  }) {
    return SearchResultItem(
      id: id,
      icon: ResultIconPB(),
      content: content,
      displayName: title,
    );
  }

  group('CommandPaletteFilter', () {
    test('title-only matches titles instead of document content', () {
      const filter = CommandPaletteFilter(titleOnly: true);
      final view = ViewPB(id: 'document');

      expect(
        filter.matchesSearchResult(
          item: item(
            id: view.id,
            title: 'Product roadmap',
            content: 'Unrelated content',
          ),
          view: view,
          query: query,
          cachedViews: {view.id: view},
          currentUserId: currentUserId,
        ),
        isTrue,
      );
      expect(
        filter.matchesSearchResult(
          item: item(
            id: view.id,
            title: 'Product planning',
            content: 'The roadmap is in this document',
          ),
          view: view,
          query: query,
          cachedViews: {view.id: view},
          currentUserId: currentUserId,
        ),
        isFalse,
      );
    });

    test('combines creator and page-type filters', () {
      final filter = CommandPaletteFilter(
        createdByMe: true,
        pageType: ViewLayoutPB.Board,
      );
      final ownBoard = ViewPB(
        id: 'own-board',
        layout: ViewLayoutPB.Board,
        createdBy: currentUserId,
      );
      final otherBoard = ViewPB(
        id: 'other-board',
        layout: ViewLayoutPB.Board,
        createdBy: Int64(7),
      );
      final ownDocument = ViewPB(
        id: 'own-document',
        layout: ViewLayoutPB.Document,
        createdBy: currentUserId,
      );

      bool matches(ViewPB view) => filter.matchesRecentView(
            view: view,
            cachedViews: {
              ownBoard.id: ownBoard,
              otherBoard.id: otherBoard,
              ownDocument.id: ownDocument,
            },
            currentUserId: currentUserId,
          );

      expect(matches(ownBoard), isTrue);
      expect(matches(otherBoard), isFalse);
      expect(matches(ownDocument), isFalse);
    });

    test('matches descendants of the selected space', () {
      final space = ViewPB(id: 'space');
      final folder = ViewPB(id: 'folder', parentViewId: space.id);
      final document = ViewPB(id: 'document', parentViewId: folder.id);
      final otherSpace = ViewPB(id: 'other-space');
      final otherDocument = ViewPB(
        id: 'other-document',
        parentViewId: otherSpace.id,
      );
      final views = {
        space.id: space,
        folder.id: folder,
        document.id: document,
        otherSpace.id: otherSpace,
        otherDocument.id: otherDocument,
      };
      final filter = CommandPaletteFilter(spaceId: space.id);

      expect(
        filter.matchesRecentView(
          view: document,
          cachedViews: views,
          currentUserId: currentUserId,
        ),
        isTrue,
      );
      expect(
        filter.matchesRecentView(
          view: otherDocument,
          cachedViews: views,
          currentUserId: currentUserId,
        ),
        isFalse,
      );
    });

    test('can clear nullable filters', () {
      final filter = CommandPaletteFilter(
        spaceId: 'space',
        pageType: ViewLayoutPB.Grid,
      );

      final cleared = filter.copyWith(
        clearSpace: true,
        clearPageType: true,
      );

      expect(cleared.spaceId, isNull);
      expect(cleared.pageType, isNull);
      expect(cleared.isActive, isFalse);
    });

    test('adds title-matching workspace folders to search results', () {
      final folder = ViewPB(
        id: 'research-folder',
        name: 'Product research',
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final otherFolder = ViewPB(
        id: 'other-folder',
        name: 'Meeting notes',
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final ordinaryPage = ViewPB(
        id: 'ordinary-page',
        name: 'Research page',
      );

      final results = includeWorkspaceFolderSearchResults(
        searchResults: const [],
        cachedViews: {
          folder.id: folder,
          otherFolder.id: otherFolder,
          ordinaryPage.id: ordinaryPage,
        },
        query: 'research',
      );

      expect(results.map((item) => item.id), [folder.id]);
      expect(results.single.displayName, folder.name);
    });

    test('does not duplicate a folder already returned by backend search', () {
      final folder = ViewPB(
        id: 'folder',
        name: 'Research',
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final backendResult = item(id: folder.id, title: folder.name);

      final results = includeWorkspaceFolderSearchResults(
        searchResults: [backendResult],
        cachedViews: {folder.id: folder},
        query: 'research',
      );

      expect(results, [same(backendResult)]);
    });

    test('clearing search preserves cached folder views', () {
      final folder = ViewPB(
        id: 'folder',
        name: 'Research',
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final state = CommandPaletteState.initial().copyWith(
        query: 'research',
        searching: true,
        cachedViews: {folder.id: folder},
        combinedResponseItems: {
          folder.id: item(id: folder.id, title: folder.name),
        },
      );

      final cleared = commandPaletteStateAfterClear(state);

      expect(cleared.query, isNull);
      expect(cleared.searching, isFalse);
      expect(cleared.combinedResponseItems, isEmpty);
      expect(cleared.cachedViews, {folder.id: same(folder)});
    });
  });
}
