import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_views.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_host.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_toolbar.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_views.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

// Author-only. Real CollectionPage, BookmarkHost, toolbar and primary listing.
void main() {
  fileControlTestSetup();
  for (final mode in [AlbumViewIds.filmstrip, AlbumViewIds.map]) {
    for (final reduced in [false, true]) {
      testWidgets(
          '$mode reduced=$reduced: bounded album header and tools retire',
          (tester) async {
        final root = _root(CollectionKind.album, mode);
        final repository = _Repository(root.id, bookmarks: false);
        final explorer = WorkspaceExplorerController(
          root: root,
          repository: repository,
          listenForUpdates: false,
        );
        try {
          await explorer.initialize();
          await mountFileControls(
            tester,
            PremiumScrollScope(
              enabled: true,
              child: CollectionPage(
                view: root,
                controller: explorer,
                shellOwnsBreadcrumbs: true,
              ),
            ),
            mode: 'paper',
            width: 1000,
            height: 850,
            textScale: 2,
            reduced: reduced,
          );
          final page = tester
              .state<NestedScrollViewState>(find.byType(NestedScrollView));
          expect(page.innerController.positions, hasLength(1));
          final identity = find.byKey(
            const ValueKey('collection-page-identity'),
            skipOffstage: false,
          );
          final tools =
              find.byType(CollectionWorkspaceToolbar, skipOffstage: false);
          final identityElement = tester.element(identity);
          final toolsElement = tester.element(tools);
          final initialIdentityRect = tester.getRect(identity);
          final initialToolsRect = tester.getRect(tools);
          final stage = tester.getRect(find.byType(CollectionPage));
          final empty = tester.element(find.byType(AlbumEmptyState));
          final model = tester
              .widget<AlbumScaffold>(find.byType(AlbumScaffold))
              .controller;
          expect(
            tester.widget<CollectionWorkspaceToolbar>(tools).keepVisible,
            isTrue,
          );

          Finder action(IconData icon) => find.descendant(
                of: tools,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is CollectionWorkspaceAction &&
                      widget.icon == icon,
                  skipOffstage: false,
                ),
                skipOffstage: false,
              );
          final sort = action(Icons.swap_vert_rounded);
          final slideshow = action(Icons.slideshow_rounded);
          final actionRects = <Finder, Rect>{};
          if (mode == AlbumViewIds.filmstrip) {
            expect(sort, findsOneWidget);
            expect(slideshow, findsOneWidget);
            actionRects[sort] = tester.getRect(sort);
            actionRects[slideshow] = tester.getRect(slideshow);
            expect(
              actionRects[slideshow]!.right,
              greaterThan(actionRects[sort]!.right),
            );
          } else {
            // Empty Places has no actions, rather than disabled controls.
            expect(
              tester.widget<CollectionWorkspaceToolbar>(tools).actions,
              isEmpty,
            );
          }

          bool hitsAction(Finder control, Offset point) {
            // A disabled TextButton still has a pointer region. Check the
            // actual control subtree, not the blank center of the wide toolbar
            // or whether this button offers an enabled activation callback.
            final targets = find
                .descendant(
                  of: control,
                  matching: find.byWidgetPredicate(
                    (widget) => widget is RenderObjectWidget,
                    skipOffstage: false,
                  ),
                  skipOffstage: false,
                )
                .evaluate()
                .map((element) => element.findRenderObject())
                .toSet();
            return tester
                .hitTestOnBinding(point)
                .path
                .any((entry) => targets.contains(entry.target));
          }

          void expectActionsRestored() {
            for (final entry in actionRects.entries) {
              final rect = tester.getRect(entry.key);
              expect(rect, entry.value);
              expect(stage.deflate(8).contains(rect.center), isTrue);
              expect(hitsAction(entry.key, rect.center), isTrue);
            }
            if (mode == AlbumViewIds.filmstrip) {
              final sortButton =
                  find.descendant(of: sort, matching: find.byType(TextButton));
              final slideshowButton = find.descendant(
                of: slideshow,
                matching: find.byType(TextButton),
              );
              expect(
                tester.widget<TextButton>(sortButton).onPressed,
                isNotNull,
              );
              expect(sortButton.hitTestable(), findsOneWidget);
              expect(
                tester.widget<TextButton>(slideshowButton).onPressed,
                isNull,
              );
            }
          }

          expectActionsRestored();
          final point = stage.bottomCenter - const Offset(0, 32);
          for (var i = 0; i < 12; i++) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: point,
                scrollDelta: const Offset(0, 100),
              ),
            );
            await tester.pumpAndSettle();
          }
          expect(
            page.outerController.offset,
            closeTo(page.outerController.position.maxScrollExtent, .01),
          );
          expect(
            page.innerController.offset,
            closeTo(page.innerController.position.maxScrollExtent, .01),
          );
          final travel =
              page.outerController.offset + page.innerController.offset;
          final retiredToolsRect = tester.getRect(tools);
          expect(retiredToolsRect.size, initialToolsRect.size);
          expect(retiredToolsRect.left, initialToolsRect.left);
          expect(
            retiredToolsRect.top,
            closeTo(initialToolsRect.top - travel, .01),
          );
          expect(retiredToolsRect.bottom, lessThanOrEqualTo(stage.top + .01));
          expect(
            tester.getRect(identity).top,
            closeTo(
              initialIdentityRect.top - page.outerController.offset,
              .01,
            ),
          );
          expect(identity.hitTestable(), findsNothing);
          expect(tools.hitTestable(), findsNothing);
          for (final control in actionRects.keys) {
            expect(hitsAction(control, tester.getCenter(control)), isFalse);
            expect(hitsAction(control, actionRects[control]!.center), isFalse);
          }
          expect(tester.element(identity), same(identityElement));
          expect(tester.element(tools), same(toolsElement));
          expect(tester.element(find.byType(AlbumEmptyState)), same(empty));
          for (var i = 0; i < 12; i++) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: point,
                scrollDelta: const Offset(0, -100),
              ),
            );
            await tester.pumpAndSettle();
          }
          expect(page.outerController.offset, closeTo(0, .01));
          expect(page.innerController.offset, closeTo(0, .01));
          expect(tester.getRect(tools), initialToolsRect);
          expect(tester.getRect(identity), initialIdentityRect);
          expect(tester.element(identity), same(identityElement));
          expect(tester.element(tools), same(toolsElement));
          expectActionsRestored();
          expect(
            tester.widget<AlbumScaffold>(find.byType(AlbumScaffold)).controller,
            same(model),
          );
          expect(repository.reads, 1);
          expect(tester.takeException(), isNull);
        } finally {
          try {
            await unmountFileControls(tester);
          } finally {
            explorer.dispose();
          }
        }
      });
    }
  }
  for (final appearance in fileControlAppearances) {
    for (final mode in [BookmarkViewIds.feed, BookmarkViewIds.timeline]) {
      testWidgets('$appearance: $mode controls follow the real primary list',
          (tester) async {
        final root = _root(CollectionKind.bookmark, mode);
        final repository = _Repository(root.id, bookmarks: true);
        final explorer = WorkspaceExplorerController(
          root: root,
          repository: repository,
          listenForUpdates: false,
        );
        await explorer.initialize();
        await mountFileControls(
          tester,
          CollectionPage(
            view: root,
            controller: explorer,
            shellOwnsBreadcrumbs: true,
          ),
          mode: appearance,
          width: 1000,
          height: 850,
          textScale: 2,
          reduced: true,
        );
        final page =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        final host = tester.state(find.byType(BookmarkHost));
        final scaffold =
            tester.widget<BookmarkScaffold>(find.byType(BookmarkScaffold));
        final model = scaffold.controller;
        final toolbar = find.byType(BookmarkToolbar, skipOffstage: false);
        final toolbarElement = tester.element(toolbar);
        final initialTop = tester.getTopLeft(toolbar).dy;
        expect(scaffold.pageFlow, isTrue);
        expect(tester.widget<BookmarkToolbar>(toolbar).persistent, isTrue);
        expect(page.innerController.positions, hasLength(1));
        final sort = find.byWidgetPredicate(
          (widget) =>
              widget is BookmarkAction &&
              widget.icon == Icons.swap_vert_rounded,
        );
        expect(sort.hitTestable(), findsOneWidget);
        await tester.tap(sort);
        await settleFileControls(tester);
        final reveals =
            find.descendant(of: toolbar, matching: find.byType(PreviewToolbar));
        expect(reveals, findsWidgets);
        for (final widget in tester.widgetList<PreviewToolbar>(reveals)) {
          expect(widget.keepVisible, isTrue);
        }
        await tester.sendKeyEvent(
          LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await settleFileControls(tester);
        final stage = tester.getRect(find.byType(CollectionPage));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: stage.bottomCenter - const Offset(0, 30),
            scrollDelta: const Offset(0, 800),
          ),
        );
        await tester.pumpAndSettle();
        final travel =
            page.outerController.offset + page.innerController.offset;
        expect(travel, closeTo(800, .01));
        expect(
          tester.getTopLeft(toolbar).dy,
          closeTo(initialTop - travel, .01),
        );
        expect(tester.element(toolbar), same(toolbarElement));
        expect(toolbar.hitTestable(), findsNothing);
        expect(tester.state(find.byType(BookmarkHost)), same(host));
        model.setQuery('no entry matches this');
        await settleFileControls(tester);
        expect(find.byType(BookmarkEmptyState), findsOneWidget);
        expect(page.innerController.positions, hasLength(1));
        expect(tester.element(toolbar), same(toolbarElement));
        model.setQuery('');
        await settleFileControls(tester);
        expect(
          tester
              .widget<BookmarkScaffold>(find.byType(BookmarkScaffold))
              .controller,
          same(model),
        );
        expect(page.innerController.positions, hasLength(1));
        expect(repository.reads, 1);
        expect(tester.takeException(), isNull);
        await unmountFileControls(tester);
        explorer.dispose();
      });
    }

    testWidgets(
        '$appearance: empty Playlist has one page owner and persistent real controls',
        (tester) async {
      final root = _root(CollectionKind.album, AlbumViewIds.playlist);
      final repository = _Repository(root.id, bookmarks: false);
      final explorer = WorkspaceExplorerController(
        root: root,
        repository: repository,
        listenForUpdates: false,
      );
      await explorer.initialize();
      await mountFileControls(
        tester,
        CollectionPage(
          view: root,
          controller: explorer,
          shellOwnsBreadcrumbs: true,
        ),
        mode: appearance,
        width: 1000,
        height: 850,
        textScale: 2,
        reduced: true,
      );
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(find.byType(AlbumEmptyState), findsOneWidget);
      final page =
          tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      expect(page.innerController.positions, hasLength(1));
      final toolbar = tester.widget<CollectionWorkspaceToolbar>(
        find.byType(CollectionWorkspaceToolbar),
      );
      expect(toolbar.keepVisible, isTrue);
      expect(
        albumCollectionViews()
            .singleWhere((view) => view.id == AlbumViewIds.playlist)
            .supportsPageHeader,
        isTrue,
      );
      expect(repository.reads, 1);
      expect(tester.takeException(), isNull);
      await unmountFileControls(tester);
      explorer.dispose();
    });
  }
}

ViewPB _root(CollectionKind kind, String mode) => ViewPB(
      id: 'collection-$mode',
      name: 'Actual collection title',
      layout: ViewLayoutPB.Document,
      extra: CollectionMetadata(kind: kind, activeViewId: mode).mergeIntoExtra(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      ),
    );

class _Repository extends Fake implements WorkspaceItemRepository {
  _Repository(this.id, {required this.bookmarks});
  final String id;
  final bool bookmarks;
  int reads = 0;
  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async {
    reads++;
    return FlowyResult.success([
      if (bookmarks)
        for (var i = 0; i < 80; i++)
          ViewPB(
            id: 'entry-$i',
            parentViewId: id,
            name: 'Saved entry $i',
            layout: ViewLayoutPB.Document,
            extra: BookmarkMetadata(
              url: 'https://fixture.invalid/article-$i',
              title: 'Saved entry $i',
              description: 'Indexed locally; no fetch needed.',
              addedAt: DateTime(2026, 9).add(Duration(days: i)),
            ).mergeIntoExtra(
              const WorkspaceItemMetadata.file(
                contentKind: WorkspaceFileContentKind.binary,
                mimeType: bookmarkMimeType,
              ).mergeIntoExtra(''),
            ),
          ),
    ]);
  }
}
