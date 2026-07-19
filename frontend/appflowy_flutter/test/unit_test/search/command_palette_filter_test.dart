import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
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
  });
}
