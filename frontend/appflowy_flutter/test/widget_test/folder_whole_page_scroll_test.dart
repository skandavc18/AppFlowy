import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_host.dart';
import 'package:appflowy/plugins/collection/views/album/album_views.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/workspace_explorer_permission_fakes.dart';
import 'file_controls_test_support.dart';

void main() {
  fileControlTestSetup();

  for (final mode in FileBrowserViewMode.values) {
    testWidgets(
        '${mode.name}: a clipped title keeps its native draft and selection',
        (tester) async {
      final repository = _FolderRepository();
      final controller = _controller(repository);
      try {
        await controller.initialize();
        await mountFileControls(
          tester,
          FolderExplorer(
            rootView: repository.root,
            controller: controller,
            initialViewMode: mode,
            onOpen: (_) {},
          ),
          mode: 'paper',
          reduced: true,
        );
        controller.beginRename('root');
        await settleFileControls(tester);
        final editor = find.byKey(
          const ValueKey('workspace-inline-name-editor'),
          skipOffstage: false,
        );
        await tester.enterText(editor, 'Unsubmitted title');
        final field = tester.widget<EditableText>(editor);
        field.controller.value = field.controller.value.copyWith(
          selection: const TextSelection(baseOffset: 2, extentOffset: 7),
          composing: const TextRange(start: 1, end: 5),
        );
        final value = field.controller.value;
        await settleFileControls(tester);
        final state = tester.state(editor);
        final header = find.byType(FolderGalleryHeader, skipOffstage: false);
        final position = Scrollable.of(tester.element(header)).position;
        position.jumpTo(tester.getSize(header).height);
        await settleFileControls(tester);
        expect(editor.hitTestable(), findsNothing);
        expect(tester.state(editor), same(state));
        expect(
          tester.widget<EditableText>(editor).controller,
          same(field.controller),
        );
        expect(field.controller.value, value);
        expect(field.focusNode.hasFocus, isTrue);
        position.jumpTo(0);
        await settleFileControls(tester);
        expect(editor.hitTestable(), findsOneWidget);
        expect(field.controller.value, value);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await settleFileControls(tester);
        expect(repository.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        controller.cancelEditing();
        await unmountFileControls(tester);
        controller.dispose();
      }
    });
  }

  for (final mode in [
    AlbumViewIds.gallery,
    AlbumViewIds.masonry,
    AlbumViewIds.timeline,
  ]) {
    testWidgets(
        '$mode: real album header and lazy wall consume one coordinated wheel',
        (tester) async {
      final repository = _FolderRepository();
      repository.root.extra =
          CollectionMetadata(kind: CollectionKind.album, activeViewId: mode)
              .mergeIntoExtra(repository.root.extra);
      repository.views
        ..clear()
        ..['root'] = repository.root;
      // Audio placeholders exercise the actual wall/delegates with no image
      // fixtures, decoding, native player, filesystem or provider requests.
      for (var i = 0; i < 200; i++) {
        repository.views['audio-$i'] =
            permissionFile('audio-$i', 'root', 'Audio $i.mp3');
      }
      final controller = _controller(repository);
      final service = _MemoryCollectionService();
      try {
        await controller.initialize();
        await mountFileControls(
          tester,
          CollectionPage(
            view: repository.root,
            controller: controller,
            service: service,
            shellOwnsBreadcrumbs: true,
            onOpen: (_) {},
          ),
          mode: 'paper',
          height: 620,
          reduced: true,
        );
        final title =
            find.byKey(const ValueKey('collection-title'), skipOffstage: false);
        final cover = find.byType(ViewCoverImage, skipOffstage: false).first;
        final position = Scrollable.of(tester.element(title)).position;
        final first = find.byType(AlbumTile, skipOffstage: false).first;
        final tileElement = tester.element(first);
        final hostState = tester.state(find.byType(AlbumHost));
        final nested =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        expect(nested.innerController.positions, hasLength(1));
        expect(position, same(nested.outerController.position));
        expect(
          Scrollable.of(tileElement).position,
          same(nested.innerController.position),
        );
        expect(Scrollable.of(tester.element(cover)).position, same(position));
        expect(find.byType(NestedScrollView), findsOneWidget);
        expect(
          find.byType(AlbumTile, skipOffstage: false).evaluate().length,
          inExclusiveRange(0, 40),
        );
        final top = tester.getTopLeft(title).dy;
        final point =
            tester.getRect(find.byType(NestedScrollView)).bottomCenter -
                const Offset(0, 32);
        Future<void> wheel(double delta) async {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: point,
              scrollDelta: Offset(0, delta),
            ),
          );
          await tester.pump();
        }

        await wheel(120);
        expect(position.pixels, closeTo(120, .01));
        expect(nested.innerController.offset, 0);
        expect(tester.getTopLeft(title).dy, closeTo(top - 120, 0.01));
        expect(tester.state(find.byType(AlbumHost)), same(hostState));
        final extent = position.maxScrollExtent;
        await wheel(extent + 80 - 120);
        expect(position.pixels, closeTo(extent, .01));
        expect(nested.innerController.offset, closeTo(80, .01));
        await settleFileControls(tester);
        expect(title.hitTestable(), findsNothing);
        await wheel(-100);
        expect(nested.innerController.offset, closeTo(0, .01));
        expect(position.pixels, closeTo(extent - 20, .01));
        await wheel(-extent);
        await settleFileControls(tester);
        expect(tester.getTopLeft(title).dy, closeTo(top, 0.01));
        expect(title.hitTestable(), findsOneWidget);
        expect(repository.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        controller.dispose();
      }
    });
  }

  for (final appearance in fileControlAppearances) {
    for (final mode in FileBrowserViewMode.values) {
      testWidgets(
          '$appearance/${mode.name}: whole header scrolls, clips and returns; listing stays lazy',
          (tester) async {
        final repository = _FolderRepository();
        final controller = _controller(repository);
        try {
          await controller.initialize();
          await mountFileControls(
            tester,
            FolderExplorer(
              rootView: repository.root,
              controller: controller,
              initialViewMode: mode,
              onOpen: (_) {},
            ),
            mode: appearance,
            height: 620,
            reduced: true,
            accessible: true,
          );
          final header = find.byType(FolderGalleryHeader, skipOffstage: false);
          final title = find.byKey(
            const ValueKey('folder-gallery-title'),
            skipOffstage: false,
          );
          final cover = find.byType(ViewCoverImage, skipOffstage: false).first;
          final headerElement = tester.element(header);
          final titleElement = tester.element(title);
          final coverElement = tester.element(cover);
          final position = Scrollable.of(tester.element(header)).position;
          final top = tester.getTopLeft(title).dy;
          final coverTop = tester.getTopLeft(cover).dy;
          final extent = tester.getSize(header).height;
          expect(extent, greaterThan(0));
          expect(
            find.byKey(const ValueKey('folder-explorer-header-scroll')),
            findsNothing,
          );

          if (mode != FileBrowserViewMode.columns) {
            final listing = find.byType(FileBrowserScrollView).first;
            expect(
              find.ancestor(of: header, matching: listing),
              findsOneWidget,
            );
            // At rest only nearby entries are built, not the entire folder.
            expect(_mountedItems(tester), lessThan(80));
            expect(find.byType(NestedScrollView), findsNothing);
          } else {
            expect(find.byType(FileBrowserColumns), findsOneWidget);
            final nested = tester
                .state<NestedScrollViewState>(find.byType(NestedScrollView));
            expect(nested.innerController.positions, hasLength(1));
          }
          position.jumpTo(80);
          await tester.pump();
          expect(tester.getTopLeft(title).dy, closeTo(top - 80, 0.01));
          expect(tester.getTopLeft(cover).dy, closeTo(coverTop - 80, 0.01));
          final content = tester
              .getRect(find.byKey(const ValueKey('folder-explorer-content')));
          if (mode == FileBrowserViewMode.columns) {
            // A touch drag on a column row owns file drag/drop. Trackpad
            // pan-zoom exercises the native coordinated scrolling path.
            final point = content.bottomLeft + const Offset(32, -32);
            final pan =
                await tester.createGesture(kind: PointerDeviceKind.trackpad);
            await pan.panZoomStart(point);
            for (var step = 1; step <= (extent / 32).ceil() + 6; step++) {
              await pan.panZoomUpdate(
                point,
                pan: Offset(0, -32.0 * step),
                timeStamp: Duration(milliseconds: step * 16),
              );
              await tester.pump(const Duration(milliseconds: 16));
            }
            await pan.panZoomEnd();
          } else {
            final gesture = await tester
                .startGesture(content.bottomLeft + const Offset(32, -32));
            await gesture.moveBy(const Offset(0, -24));
            await tester.pump();
            for (var step = 0; step < (extent / 32).ceil() + 6; step++) {
              await gesture.moveBy(const Offset(0, -32));
              await tester.pump(const Duration(milliseconds: 16));
            }
            await gesture.cancel();
          }
          await settleFileControls(tester);
          expect(
            tester.getBottomLeft(header).dy,
            lessThanOrEqualTo(content.top + 0.01),
          );
          expect(title.hitTestable(), findsNothing);
          expect(cover.hitTestable(), findsNothing);
          expect(tester.element(header), same(headerElement));
          expect(tester.element(title), same(titleElement));
          expect(tester.element(cover), same(coverElement));
          expect(tester.renderObject(header).attached, isTrue);
          expect(_mountedItems(tester), lessThan(80));

          if (mode == FileBrowserViewMode.columns) {
            tester
                .state<NestedScrollViewState>(find.byType(NestedScrollView))
                .innerController
                .jumpTo(0);
          }
          position.jumpTo(0);
          await settleFileControls(tester);
          expect(
            find.byKey(const ValueKey('folder-gallery-title')),
            findsOneWidget,
          );
          expect(tester.getTopLeft(title).dy, closeTo(top, 0.01));
          expect(title.hitTestable(), findsOneWidget);
          expect(controller.childrenOf('root'), hasLength(254));
          expect(repository.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await unmountFileControls(tester);
          controller.dispose();
        }
      });
    }
  }

  for (final style in DefaultIconStyle.values) {
    for (final mode in FileBrowserViewMode.values) {
      testWidgets(
          '${style.name}/${mode.name}: real listing distinguishes folder, file and saved identity',
          (tester) async {
        final repository = ExplorerPermissionRepository();
        // Omitted layout exercises the protobuf Document default, not a fake
        // folder-shaped glyph widget. Classification comes from the view.
        repository.views['folder']!.clearLayout();
        final styles = ValueNotifier(style);
        final controller = WorkspaceExplorerController(
          root: repository.root,
          repository: repository,
          listenForUpdates: false,
        );
        final opened = <String>[];
        try {
          await controller.initialize();
          await mountFileControls(
            tester,
            DefaultIconStyleScope(
              styles: styles,
              child: FolderExplorer(
                rootView: repository.root,
                controller: controller,
                initialViewMode: mode,
                showHeader: false,
                showControls: false,
                onOpen: (view) => opened.add(view.id),
              ),
            ),
            mode: 'paper',
            reduced: true,
            accessible: true,
          );
          final folderIcon = find.byWidgetPredicate(
            (widget) =>
                widget is WorkspaceItemIcon && widget.item.id == 'folder',
          );
          final fileIcon = find.byWidgetPredicate(
            (widget) =>
                widget is WorkspaceItemIcon && widget.item.id == 'first',
          );
          expect(folderIcon, findsWidgets);
          expect(fileIcon, findsWidgets);
          expect(
            find.descendant(
              of: folderIcon,
              matching: find.byWidgetPredicate(
                (widget) => widget is WorkspaceGlyph && widget.name == 'folder',
              ),
            ),
            findsWidgets,
          );
          expect(
            find.descendant(
              of: fileIcon,
              matching: find.byWidgetPredicate(
                (widget) => widget is WorkspaceGlyph && widget.name == 'folder',
              ),
            ),
            findsNothing,
          );
          expect(controller.itemForId('folder')!.isFolder, isTrue);
          expect(controller.itemForId('first')!.isFile, isTrue);
          final saved = EmojiIconData.emoji('🌿');
          controller.updateView(
            ViewPB.fromBuffer(repository.views['folder']!.writeToBuffer())
              ..icon = saved.toViewIcon(),
          );
          await settleFileControls(tester);
          expect(
            find.descendant(
              of: folderIcon,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RawEmojiIconWidget &&
                    widget.emoji.type == saved.type &&
                    widget.emoji.emoji == saved.emoji,
              ),
            ),
            findsWidgets,
          );
          expect(
            find.descendant(
              of: fileIcon,
              matching: find.byWidgetPredicate(
                (widget) => widget is WorkspaceGlyph && widget.name == 'folder',
              ),
            ),
            findsNothing,
          );
          expect(repository.writes, isEmpty);
          expect(opened, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await unmountFileControls(tester);
          controller.dispose();
          styles.dispose();
        }
      });
    }
  }

  testWidgets(
      'gallery reflow/update retains lazy preview and selection; layouts restore their own offset',
      (tester) async {
    final repository = _FolderRepository();
    final controller = _controller(repository);
    final width = ValueNotifier(780.0);
    try {
      await controller.initialize();
      await mountFileControls(
        tester,
        ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (_, value, __) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: value,
              child: FolderExplorer(
                rootView: repository.root,
                controller: controller,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
        reduced: true,
        accessible: true,
      );
      final header = find.byType(FolderGalleryHeader, skipOffstage: false);
      final headerElement = tester.element(header);
      final initial = tester.widget<FolderGalleryHeader>(header);
      final gallery = tester.widget<FolderGallery>(find.byType(FolderGallery));
      final scroll = gallery.scrollController!;
      final headerExtent = tester.getSize(header).height;
      scroll.jumpTo(headerExtent + 40);
      await settleFileControls(tester);
      final card = find.byType(FolderGalleryCard).first;
      final cardWidget = tester.widget<FolderGalleryCard>(card);
      final cardState = tester.state(card);
      final id = cardWidget.item.id;
      final preview = cardWidget.preview;
      controller.selection.selectOnly(id);
      width.value = 720;
      controller.updateView(
        ViewPB.fromBuffer(controller.viewForId(id)!.writeToBuffer())
          ..name = 'Updated name',
      );
      await settleFileControls(tester);
      final retained = find.byKey(ValueKey('gallery-card-$id'));
      expect(tester.getSize(find.byType(FolderExplorer)).width, 720);
      expect(tester.state(retained), same(cardState));
      expect(controller.selection.ids, {id});
      expect(
        tester.widget<FolderGallery>(find.byType(FolderGallery)).previewCache,
        same(gallery.previewCache),
      );
      // A changed view intentionally invalidates its old preview, without
      // replacing the controller, card state or other cached entries.
      expect(
        tester.widget<FolderGalleryCard>(retained).preview,
        isNot(same(preview)),
      );
      final offset = scroll.offset;
      initial.onViewModeChanged!(FileBrowserViewMode.thumbnails);
      await settleFileControls(tester);
      final thumbnails = tester
          .widget<FolderGallery>(find.byType(FolderGallery))
          .scrollController!;
      expect(thumbnails, isNot(same(scroll)));
      expect(thumbnails.offset, 0);
      thumbnails.jumpTo(120);
      await tester.pump();
      tester
          .widget<FolderGalleryHeader>(header)
          .onViewModeChanged!(FileBrowserViewMode.gallery);
      await settleFileControls(tester);
      expect(
        tester
            .widget<FolderGallery>(find.byType(FolderGallery))
            .scrollController,
        same(scroll),
      );
      expect(scroll.offset, closeTo(offset, 0.01));
      expect(tester.element(header), same(headerElement));
      expect(repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      width.dispose();
      controller.dispose();
    }
  });

  testWidgets(
      'real collection parent lends cover and title to its lazy contents viewport',
      (tester) async {
    final repository = _FolderRepository();
    repository.root.extra = const CollectionMetadata(
      kind: CollectionKind.book,
      activeViewId: 'gallery',
    ).mergeIntoExtra(repository.root.extra);
    repository.views['root'] = repository.root;
    final controller = _controller(repository);
    try {
      await controller.initialize();
      await mountFileControls(
        tester,
        CollectionPage(
          view: repository.root,
          controller: controller,
          shellOwnsBreadcrumbs: true,
          onOpen: (_) {},
        ),
        mode: 'paper',
        reduced: true,
      );
      final title =
          find.byKey(const ValueKey('collection-title'), skipOffstage: false);
      final cover = find.byType(ViewCoverImage, skipOffstage: false).first;
      final element = tester.element(title);
      final scroll = tester
          .widget<FolderGallery>(find.byType(FolderGallery))
          .scrollController!;
      expect(find.byType(NestedScrollView), findsNothing);
      expect(
        Scrollable.of(tester.element(title)).position,
        same(scroll.position),
      );
      expect(
        Scrollable.of(tester.element(cover)).position,
        same(scroll.position),
      );
      final top = tester.getTopLeft(title).dy;
      scroll.jumpTo(120);
      await tester.pump();
      expect(tester.getTopLeft(title).dy, closeTo(top - 120, 0.01));
      expect(tester.element(title), same(element));
      expect(_mountedItems(tester), lessThan(80));
      expect(repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      controller.dispose();
    }
  });
}

int _mountedItems(WidgetTester tester) =>
    tester
        .widgetList<WorkspaceItemIcon>(
          find.byType(WorkspaceItemIcon, skipOffstage: false),
        )
        .length +
    tester
        .widgetList<FolderGalleryCard>(
          find.byType(FolderGalleryCard, skipOffstage: false),
        )
        .length;

WorkspaceExplorerController _controller(
  ExplorerPermissionRepository repository,
) =>
    WorkspaceExplorerController(
      root: repository.root,
      repository: repository,
      listenForUpdates: false,
    );

class _FolderRepository extends ExplorerPermissionRepository {
  _FolderRepository() {
    root.extra = ViewCoverCodec.mergeCover(
      root.extra,
      const PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#C8B99A',
      ),
    );
    views['root'] = ViewPB.fromBuffer(root.writeToBuffer());
    for (var i = 0; i < 251; i++) {
      views['lazy-$i'] = permissionFile('lazy-$i', 'root', 'Lazy $i.bin');
    }
  }
}

class _MemoryCollectionService extends CollectionService {
  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required CollectionMetadata metadata,
  }) async =>
      FlowyResult.success(
        ViewPB.fromBuffer(view.writeToBuffer())
          ..extra = metadata.mergeIntoExtra(view.extra),
      );
}
