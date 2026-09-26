import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

const _rootId = 'activation-root';
const _folderId = 'activation-root::nested%2Ffolder';
const _childId = 'activation-nested-child';
const _emptyId = 'activation-empty-page';
const _writtenId = 'activation-written-page';
const _fileId = 'activation-file';
const _coverId = 'activation-cover';
const _tableId = 'activation-table';
const _away = Offset(2, 2);
const _stageKey = ValueKey('folder-gallery-preview-stage');
const _editorKey = ValueKey('workspace-inline-name-editor');
const _loadingKey = ValueKey('folder-gallery-preview-loading');
const _retryKey = ValueKey('folder-gallery-preview-retry');
const _emptyPreview = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: [],
  wordCount: 0,
  readingMinutes: 0,
  tags: [],
  fileTypeLabel: 'PAGE',
);
const _writtenPreview = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: [
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.heading,
      runs: [FolderGalleryTextRun(text: 'Authored heading', bold: true)],
    ),
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.bulletedList,
      runs: [FolderGalleryTextRun(text: 'Authored list entry')],
    ),
  ],
  wordCount: 5,
  readingMinutes: 1,
  tags: [],
  fileTypeLabel: 'PAGE',
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    _test(
      '$appearance: real gallery bodies open their exact views',
      (tester, fixture) async {
        expect(find.byType(SliverGrid), findsOneWidget);
        expect(find.byType(FolderGalleryHeader), findsOneWidget);
        for (final id in [_emptyId, _writtenId, _fileId, _coverId, _tableId]) {
          fixture.expectInteractiveTree(tester, id);
          await fixture.click(tester, _body(id));
          expect(
            fixture.opened.last.writeToBuffer(),
            fixture.controller.viewForId(id)!.writeToBuffer(),
          );
          expect(fixture.controller.currentFolder.id, _rootId);
        }
        expect(
          fixture.opened.map((view) => view.id),
          [_emptyId, _writtenId, _fileId, _coverId, _tableId],
        );
        expect(fixture.navigated, isEmpty);
        expect(fixture.renamed, isEmpty);
        expect(fixture.repository.moves, isEmpty);
      },
      appearance: appearance,
    );

    _test(
      '$appearance: folder glyph navigates and paints children and path',
      (tester, fixture) async {
        fixture.expectInteractiveTree(tester, _folderId);
        await fixture.click(tester, _body(_folderId));
        await _until(tester, () => _card(_childId).evaluate().isNotEmpty);
        expect(fixture.navigated, [_folderId]);
        expect(fixture.opened, isEmpty);
        expect(fixture.controller.currentFolder.id, _folderId);
        expect(
          fixture.controller.breadcrumbs.map((item) => item.id),
          [_rootId, _folderId],
        );
        expect(fixture.repository.reads, [_rootId, _folderId]);
        expect(_card(_emptyId), findsNothing);
        expect(_card(_childId), findsOneWidget);
        expect(
          tester
              .widget<WorkspaceInlineEditableText>(
                find.byKey(const ValueKey('folder-gallery-title')),
              )
              .text,
          'Nested folder',
        );
        final breadcrumb = find.widgetWithText(TextButton, 'Library');
        expect(breadcrumb, findsOneWidget);
        await fixture.click(tester, breadcrumb);
        await _until(tester, () => _card(_folderId).evaluate().isNotEmpty);
        expect(fixture.controller.currentFolder.id, _rootId);
        expect(fixture.navigated, [_folderId, _rootId]);
        expect(fixture.repository.reads, [_rootId, _folderId]);
      },
      appearance: appearance,
    );

    for (final kind in CollectionKind.values) {
      _test(
        '$appearance: ${kind.name} has its typed thumbnail and opens itself',
        (tester, fixture) async {
          final id = _collectionId(kind);
          final glyph = tester.widget<WorkspaceGlyph>(
            find.descendant(
              of: _stage(id),
              matching: find.byType(WorkspaceGlyph),
            ),
          );
          expect(glyph.name, WorkspaceGlyphs.nameForCollection(kind));
          expect(glyph.size, 64);
          expect(glyph.color, isNull);
          expect(
            PaperTheme.isEnabled(tester.element(_card(id))),
            appearance == 'paper',
          );
          expect(
            find.descendant(
              of: _stage(id),
              matching: find.byType(FolderGalleryRichTextPreview),
            ),
            findsNothing,
          );
          await fixture.click(tester, _stage(id));
          expect(fixture.opened.single.id, id);
          expect(fixture.navigated, isEmpty);
          expect(fixture.controller.currentFolder.id, _rootId);
          expect(fixture.repository.reads, [_rootId]);
        },
        appearance: appearance,
        create: () => _Fixture(collectionsOnly: true),
      );
    }
  }

  for (final id in [
    _folderId,
    _emptyId,
    _writtenId,
    _collectionId(CollectionKind.database),
    _fileId,
    _coverId,
    _tableId,
  ]) {
    _test('title single-click activates $id in the actual Draggable tree',
        (tester, fixture) async {
      fixture.expectInteractiveTree(tester, id);
      await fixture.click(tester, _title(id));
      await fixture.expectActivated(tester, id);
      expect(fixture.renamed, isEmpty);
      expect(find.byKey(_editorKey), findsNothing);
    });
  }

  for (final (id, title) in [
    (_folderId, false),
    (_emptyId, false),
    (_writtenId, false),
    (_coverId, false),
    (_fileId, true),
  ]) {
    for (final movement in [const Offset(2, 0), const Offset(0, 2)]) {
      _test('2px mouse wobble is a click: $id title=$title delta=$movement',
          (tester, fixture) async {
        fixture.expectInteractiveTree(tester, id);
        await fixture.hover(tester, title ? _title(id) : _body(id));
        await fixture.mouse.down(
          tester.getCenter(title ? _title(id) : _body(id)),
        );
        await tester.pump();
        await fixture.mouse.moveBy(movement);
        await tester.pump();
        final dragged = find
            .text(LocaleKeys.workspaceFolderExplorer_movingItem.tr())
            .evaluate()
            .isNotEmpty;
        await fixture.mouse.up();
        await _finishClick(tester);
        expect(
          dragged,
          isFalse,
          reason: 'An ordinary mouse wobble must not start a move.',
        );
        await fixture.expectActivated(tester, id);
        expect(fixture.repository.moves, isEmpty);
        expect(fixture.renamed, isEmpty);
      });
    }
  }

  for (final id in [_folderId, _writtenId, _fileId]) {
    _test('title double-click renames $id without opening or navigating',
        (tester, fixture) async {
      await fixture.hover(tester, _title(id));
      final position = tester.getCenter(_title(id));
      // Flutter gives each press a new pointer ID, even for one mouse. Reusing
      // TestGesture here enters the first tap's still-held arena a second time.
      await tester.tapAt(position, kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapMinTime + const Duration(milliseconds: 10));
      await tester.tapAt(position, kind: PointerDeviceKind.mouse);
      await _finishClick(tester);
      expect(fixture.renamed, [id]);
      expect(fixture.controller.editingId, id);
      expect(fixture.opened, isEmpty);
      expect(fixture.navigated, isEmpty);
      final editor = tester.widget<EditableText>(find.byKey(_editorKey));
      final name = fixture.controller.viewForId(id)!.name;
      expect(editor.controller.text, name);
      expect(
        editor.controller.selection,
        TextSelection(
          baseOffset: 0,
          extentOffset: id == _fileId ? 5 : name.length,
        ),
      );
      await tester.enterText(find.byKey(_editorKey), 'Uncommitted name');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester);
      expect(fixture.controller.editingId, isNull);
      expect(fixture.repository.renames, isEmpty);
      await fixture.click(tester, _title(id));
      await fixture.expectActivated(tester, id);
    });
  }

  _test('Ctrl and Shift on titles and populated bodies select, never open',
      (tester, fixture) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await fixture.click(tester, _title(_emptyId));
      await fixture.click(tester, _body(_writtenId));
      expect(
        fixture.controller.selection.ids,
        unorderedEquals([_emptyId, _writtenId]),
      );
      await fixture.click(tester, _title(_writtenId));
      expect(fixture.controller.selection.ids, [_emptyId]);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      await fixture.click(tester, _title(_fileId));
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    expect(
      fixture.controller.selection.ids,
      unorderedEquals([
        _writtenId,
        _collectionId(CollectionKind.database),
        _fileId,
      ]),
    );
    expect(fixture.opened, isEmpty);
    expect(fixture.navigated, isEmpty);
    expect(fixture.renamed, isEmpty);
    expect(fixture.repository.moves, isEmpty);
  });

  for (final readOnly in [false, true]) {
    _test(
      'no rename, readOnly=$readOnly: title and body still open',
      (tester, fixture) async {
        for (final id in [_emptyId, _writtenId, _fileId]) {
          fixture.expectInteractiveTree(tester, id, draggable: !readOnly);
          expect(fixture.controller.canRename(id), isFalse);
          await fixture.click(tester, _title(id));
          await fixture.click(tester, _body(id));
        }
        expect(fixture.opened.map((view) => view.id), [
          _emptyId,
          _emptyId,
          _writtenId,
          _writtenId,
          _fileId,
          _fileId,
        ]);
        expect(fixture.renamed, isEmpty);
        expect(find.byKey(_editorKey), findsNothing);
        await fixture.click(tester, _title(_folderId));
        await _until(tester, () => _card(_childId).evaluate().isNotEmpty);
        expect(fixture.controller.currentFolder.id, _folderId);
      },
      create: () => _Fixture(readOnly: readOnly, allowRename: false),
    );
  }

  _test('hover and cover toggles retain the renderer and keep clicks working',
      (tester, fixture) async {
    final cardState = tester.state(_card(_writtenId));
    final scrollable = find.descendant(
      of: _stage(_writtenId),
      matching: find.byType(Scrollable),
    );
    final renderer = tester.state<ScrollableState>(scrollable);
    final future = tester.widget<FolderGalleryCard>(_card(_writtenId)).preview;
    final bounds = tester.getRect(_stage(_writtenId));
    for (final mode in [
      ViewPreviewMode.content,
      ViewPreviewMode.cover,
      ViewPreviewMode.content,
      ViewPreviewMode.cover,
    ]) {
      fixture.update(_coverId, (view) {
        view.extra = ViewPreviewModeCodec.merge(view.extra, mode);
      });
      await _frames(tester);
      expect(
        find.descendant(
          of: _stage(_coverId),
          matching: find.byType(ViewCoverImage),
        ),
        mode == ViewPreviewMode.cover ? findsOneWidget : findsNothing,
      );
      for (final visible in [true, false]) {
        await fixture.mouse.moveTo(visible ? bounds.center : _away);
        await _frames(tester);
        expect(
          tester.widget<AnimatedOpacity>(_toolbarFade(_writtenId)).opacity,
          visible ? 1 : 0,
        );
        expect(tester.state(_card(_writtenId)), same(cardState));
        expect(tester.state<ScrollableState>(scrollable), same(renderer));
        expect(
          tester.widget<FolderGalleryCard>(_card(_writtenId)).preview,
          same(future),
        );
        expect(tester.getRect(_stage(_writtenId)), bounds);
      }
      await fixture.click(tester, _body(_writtenId));
      await fixture.click(tester, _body(_coverId));
    }
    expect(fixture.opened.map((view) => view.id), [
      for (var index = 0; index < 4; index++) ...[_writtenId, _coverId],
    ]);
  });

  _test(
    'pending preview opens; completion during a press does not lose it',
    (tester, fixture) async {
      expect(
        find.descendant(
          of: _stage(_writtenId),
          matching: find.byKey(_loadingKey),
        ),
        findsOneWidget,
      );
      await fixture.click(tester, _stage(_writtenId));
      expect(fixture.opened.map((view) => view.id), [_writtenId]);
      final state = tester.state(_card(_writtenId));
      await fixture.hover(tester, _stage(_writtenId));
      await fixture.mouse.down(tester.getCenter(_stage(_writtenId)));
      fixture.loader.pending.complete(_writtenPreview);
      await _frames(tester);
      expect(
        find.descendant(
          of: _stage(_writtenId),
          matching: find.byType(ListView),
        ),
        findsOneWidget,
      );
      expect(tester.state(_card(_writtenId)), same(state));
      await fixture.mouse.up();
      await _finishClick(tester);
      await fixture.click(tester, _body(_writtenId));
      expect(
        fixture.opened.map((view) => view.id),
        [_writtenId, _writtenId, _writtenId],
      );
      expect(fixture.loader.loads[_writtenId], 1);
    },
    create: () => _Fixture(pendingWritten: true),
  );

  _test(
    'late preview completion cannot undo a real folder navigation',
    (tester, fixture) async {
      await fixture.click(tester, _body(_folderId));
      await _until(tester, () => _card(_childId).evaluate().isNotEmpty);
      fixture.loader.pending.complete(_writtenPreview);
      await _frames(tester);
      expect(fixture.controller.currentFolder.id, _folderId);
      expect(_card(_childId), findsOneWidget);
      expect(_card(_writtenId), findsNothing);
      expect(fixture.navigated, [_folderId]);
      expect(fixture.opened, isEmpty);
    },
    create: () => _Fixture(pendingWritten: true),
  );

  _test(
    'retry is a real button, not a card open; recovery still opens',
    (tester, fixture) async {
      final retry = find.descendant(
        of: _card(_writtenId),
        matching: find.byKey(_retryKey),
      );
      expect(retry, findsOneWidget);
      await fixture.click(tester, retry);
      expect(fixture.opened, isEmpty);
      expect(fixture.navigated, isEmpty);
      expect(fixture.loader.loads[_writtenId], 2);
      expect(
        find.descendant(
          of: _stage(_writtenId),
          matching: find.byKey(_loadingKey),
        ),
        findsOneWidget,
      );
      fixture.loader.pending.complete(_writtenPreview);
      await _frames(tester);
      await fixture.click(tester, _body(_writtenId));
      expect(fixture.opened.single.id, _writtenId);
    },
    create: () => _Fixture(failedWritten: true),
  );

  _test('hover overflow and secondary click keep their own actual menu',
      (tester, fixture) async {
    await fixture.hover(tester, _stage(_writtenId));
    final more = find.descendant(
      of: _card(_writtenId),
      matching: find.byKey(const ValueKey('folder-gallery-more')),
    );
    expect(more.hitTestable(), findsOneWidget);
    await fixture.click(tester, more);
    expect(find.byType(AppMenuSurface), findsOneWidget);
    expect(fixture.menus, [_writtenId]);
    expect(fixture.opened, isEmpty);
    await fixture.click(tester, find.text('Inspect fixture item'));
    expect(fixture.inspected, [_writtenId]);
    expect(find.byType(AppMenuSurface), findsNothing);
    await tester.tap(
      _body(_writtenId),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await _frames(tester);
    expect(find.byType(AppMenuSurface), findsOneWidget);
    expect(fixture.menus, [_writtenId, _writtenId]);
    expect(fixture.opened, isEmpty);
    expect(fixture.repository.moves, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester);
    await fixture.click(tester, _body(_writtenId));
    expect(fixture.opened.single.id, _writtenId);
  });

  _test('a deliberate mouse drag still moves the view and never opens it',
      (tester, fixture) async {
    await fixture.hover(tester, _body(_writtenId));
    final draggable = tester.widget<Draggable<ViewPB>>(
      find.descendant(
        of: find.byKey(const ValueKey('gallery-drag-$_writtenId')),
        matching:
            find.byWidgetPredicate((widget) => widget is Draggable<ViewPB>),
      ),
    );
    await fixture.mouse.down(tester.getCenter(_body(_writtenId)));
    await tester.pump();
    await fixture.mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    await fixture.mouse.moveBy(const Offset(24, 0));
    await tester.pump();
    final feedbackShown =
        find.byWidget(draggable.feedback).evaluate().isNotEmpty;
    final sourceDimmed =
        find.byWidget(draggable.childWhenDragging!).evaluate().isNotEmpty;
    await fixture.mouse.moveTo(tester.getCenter(_stage(_folderId)));
    await tester.pump();
    await fixture.mouse.up();
    expect(feedbackShown, isTrue, reason: 'The real Draggable must start.');
    expect(sourceDimmed, isTrue);
    await _until(tester, () => fixture.repository.moves.isNotEmpty);
    await _frames(tester);
    expect(fixture.repository.moves, [(_writtenId, _folderId)]);
    expect(fixture.controller.viewForId(_writtenId)!.parentViewId, _folderId);
    expect(_card(_writtenId), findsNothing);
    expect(fixture.opened, isEmpty);
    expect(fixture.navigated, isEmpty);
    await fixture.click(tester, _body(_folderId));
    await _until(tester, () => _card(_writtenId).evaluate().isNotEmpty);
    expect(_card(_childId), findsOneWidget);
  });

  _test('a cancelled mouse press neither opens nor moves the view',
      (tester, fixture) async {
    await fixture.hover(tester, _body(_writtenId));
    await fixture.mouse.down(tester.getCenter(_body(_writtenId)));
    await fixture.mouse.moveBy(const Offset(2, 0));
    await tester.pump();
    await fixture.mouse.cancel();
    await _finishClick(tester);
    expect(fixture.opened, isEmpty);
    expect(fixture.navigated, isEmpty);
    expect(fixture.repository.moves, isEmpty);
  });

  _test('collection custom icons and saved covers still outrank type glyphs',
      (tester, fixture) async {
    final id = _collectionId(CollectionKind.database);
    fixture.update(id, (view) {
      view.icon = ViewIconPB(ty: ViewIconTypePB.Emoji, value: '📚');
    });
    await _frames(tester);
    final saved = tester.widget<RawEmojiIconWidget>(
      find.descendant(
        of: _stage(id),
        matching: find.byType(RawEmojiIconWidget),
      ),
    );
    expect(saved.emoji.emoji, '📚');
    expect(saved.emojiSize, 64);
    expect(
      find.descendant(of: _stage(id), matching: find.byType(WorkspaceGlyph)),
      findsNothing,
    );
    fixture.update(id, (view) {
      view.extra = ViewCoverCodec.mergeCover(view.extra, _cover);
    });
    await _frames(tester);
    final cover =
        find.descendant(of: _stage(id), matching: find.byType(ViewCoverImage));
    expect(tester.widget<ViewCoverImage>(cover).cover, _cover);
    await fixture.click(tester, cover);
    expect(fixture.opened.single.id, id);
    fixture.update(id, (view) {
      view.extra =
          ViewPreviewModeCodec.merge(view.extra, ViewPreviewMode.content);
    });
    await _frames(tester);
    expect(cover, findsNothing);
    expect(
      find.descendant(
        of: _stage(id),
        matching: find.byType(RawEmojiIconWidget),
      ),
      findsOneWidget,
    );
  });
}

void _test(
  String name,
  Future<void> Function(WidgetTester, _Fixture) body, {
  String appearance = 'light',
  _Fixture Function()? create,
}) {
  testWidgets(
    name,
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1320, 1100);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = create?.call() ?? _Fixture();
      try {
        await fixture.mount(tester, appearance);
        await body(tester, fixture);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
        await tester.pump();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

String _collectionId(CollectionKind kind) =>
    'activation-collection-${kind.name}';
Finder _card(String id) => find.byKey(ValueKey('gallery-card-$id'));
Finder _stage(String id) =>
    find.descendant(of: _card(id), matching: find.byKey(_stageKey));
Finder _title(String id) => find
    .descendant(
      of: find.descendant(
        of: _card(id),
        matching: find.byType(WorkspaceInlineEditableText),
      ),
      matching: find.byType(Text),
    )
    .first;
Finder _body(String id) => id == _writtenId || id == _fileId
    ? find.descendant(of: _stage(id), matching: find.text('Authored heading'))
    : id == _folderId || id == _emptyId
        ? find.descendant(of: _stage(id), matching: find.byType(WorkspaceGlyph))
        : _stage(id);
Finder _toolbarFade(String id) => find.descendant(
      of: find.descendant(of: _card(id), matching: find.byType(PreviewToolbar)),
      matching: find.byType(AnimatedOpacity),
    );

// Never pumpAndSettle: pending previews, an active editor and hover animations
// are intentional states, not reasons to wait for the entire app to go idle.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 160));
  await tester.pump();
}

Future<void> _finishClick(WidgetTester tester) async {
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
  await _frames(tester);
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var frame = 0; frame < 12 && !condition(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    condition(),
    isTrue,
    reason: 'Expected gallery result within 12 frames.',
  );
}

const _cover = PageStyleCover(
  type: PageStyleCoverImageType.pureColor,
  value: '#B8C6AF',
);

ViewPB _page(
  String id,
  String name, {
  String parent = _rootId,
  String extra = '',
}) =>
    ViewPB(
      id: id,
      parentViewId: parent,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: extra,
    );

ViewPB _folder(String id, String name, {String parent = _rootId}) => _page(
      id,
      name,
      parent: parent,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

class _Fixture {
  _Fixture({
    this.readOnly = false,
    bool allowRename = true,
    bool collectionsOnly = false,
    bool pendingWritten = false,
    bool failedWritten = false,
  }) {
    final root = _folder(_rootId, 'Library', parent: '');
    final collections = [
      for (final kind in CollectionKind.values)
        _page(
          _collectionId(kind),
          '${kind.name} collection',
          extra: CollectionMetadata.newExtra(kind),
        ),
    ];
    repository = _Repository([
      root,
      if (collectionsOnly)
        ...collections
      else ...[
        _folder(_folderId, 'Nested folder'),
        _page(_emptyId, 'Empty page'),
        _page(_writtenId, 'Written page'),
        collections.singleWhere(
          (view) => view.id == _collectionId(CollectionKind.database),
        ),
        _page(
          _fileId,
          'Draft.txt',
          extra: const WorkspaceItemMetadata.file(
            contentKind: WorkspaceFileContentKind.binary,
          ).mergeIntoExtra(''),
        ),
        _page(
          _coverId,
          'Covered page',
          extra: ViewCoverCodec.mergeCover('', _cover),
        ),
        ViewPB(
          id: _tableId,
          parentViewId: _rootId,
          name: 'Real table',
          layout: ViewLayoutPB.Grid,
        ),
        _page(_childId, 'Inside the folder', parent: _folderId),
      ],
    ]);
    controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
      canWrite: () => !readOnly,
    );
    if (!allowRename) {
      releaseGuard = controller.restrictWrites(
        canWrite: () => true,
        canRename: (_) => false,
      );
    }
    loader = _PreviewLoader(
      pendingWritten: pendingWritten,
      failedWritten: failedWritten,
    );
    cache = FolderGalleryPreviewCache(loader: loader);
  }

  final bool readOnly;
  late final _Repository repository;
  late final WorkspaceExplorerController controller;
  late final _PreviewLoader loader;
  late final FolderGalleryPreviewCache cache;
  late final TestGesture mouse;
  final search = TextEditingController();
  VoidCallback? releaseGuard;
  final opened = <ViewPB>[];
  final navigated = <String>[];
  final renamed = <String>[];
  final menus = <String>[];
  final inspected = <String>[];

  Future<void> mount(WidgetTester tester, String appearance) async {
    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _away);
    await controller.initialize();
    final theme = DesktopAppearance().getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      preferredFontFamily,
      builtInCodeFontFamily,
    );
    await tester.pumpWidget(
      WidgetTestApp(
        child: Theme(
          data: theme.copyWith(platform: TargetPlatform.windows),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => FolderGallery(
              controller: controller,
              previewCache: cache,
              userProfile: null,
              onOpen: opened.add,
              onNavigate: navigate,
              onRename: (id) {
                renamed.add(id);
                controller.beginRename(id);
              },
              onRequestDelete: () => throw StateError('Unexpected delete'),
              onContextMenu: (item, position) {
                menus.add(item.id);
                unawaited(
                  showAppMenu<String>(
                    context: context,
                    globalPosition: position,
                    entries: const [
                      AppMenuItem(
                        label: 'Inspect fixture item',
                        value: 'inspect',
                      ),
                    ],
                  ).then((value) {
                    if (value == 'inspect') inspected.add(item.id);
                  }),
                );
              },
              header: FolderGalleryHeader(
                controller: controller,
                searchController: search,
                onSearchChanged: (_) {},
                onNavigate: navigate,
                onAddFile: (_) {},
                onCreateCollection: (_) {},
                onCreateDatabase: (_) {},
                onMore: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await _until(tester, () => find.byType(SliverGrid).evaluate().isNotEmpty);
    await _frames(tester);
    expect(tester.takeException(), isNull);
  }

  void navigate(String id) {
    navigated.add(id);
    // Exercise the real model and the listening host, not a counter pretending
    // to navigate. The assertions wait for the resulting child widgets.
    unawaited(controller.navigateTo(id));
  }

  void update(String id, void Function(ViewPB) change) {
    final view = ViewPB.fromBuffer(controller.viewForId(id)!.writeToBuffer());
    change(view);
    repository.views[id] = view;
    controller.updateView(view);
  }

  void expectInteractiveTree(
    WidgetTester tester,
    String id, {
    bool draggable = true,
  }) {
    expect(
      find.descendant(
        of: find.byKey(ValueKey('gallery-drag-$id')),
        matching:
            find.byWidgetPredicate((widget) => widget is Draggable<ViewPB>),
      ),
      draggable ? findsOneWidget : findsNothing,
    );
    final region = find.descendant(
      of: _card(id),
      matching: find.byType(PreviewToolbarRegion),
    );
    expect(tester.widget<PreviewToolbarRegion>(region).enabled, isTrue);
    expect(
      find.descendant(of: _card(id), matching: find.byType(Focus)),
      findsWidgets,
    );
    expect(tester.getSize(_stage(id)).height, greaterThan(0));
  }

  Future<void> hover(WidgetTester tester, Finder target) async {
    expect(target, findsOneWidget);
    await mouse.moveTo(tester.getCenter(target));
    await _frames(tester);
  }

  Future<void> click(WidgetTester tester, Finder target) async {
    await hover(tester, target);
    await tester.tapAt(tester.getCenter(target), kind: PointerDeviceKind.mouse);
    await _finishClick(tester);
  }

  Future<void> expectActivated(WidgetTester tester, String id) async {
    if (id == _folderId) {
      await _until(tester, () => _card(_childId).evaluate().isNotEmpty);
      expect(controller.currentFolder.id, _folderId);
      expect(navigated, [_folderId]);
      expect(opened, isEmpty);
    } else {
      expect(opened.map((view) => view.id), [id]);
      expect(navigated, isEmpty);
    }
  }

  void dispose() {
    releaseGuard?.call();
    controller.dispose();
    search.dispose();
    cache.clear();
  }
}

class _Repository implements WorkspaceItemRepository {
  _Repository(List<ViewPB> entries)
      : views = {
          for (final view in entries)
            view.id: ViewPB.fromBuffer(view.writeToBuffer()),
        };

  final Map<String, ViewPB> views;
  final reads = <String>[];
  final moves = <(String, String)>[];
  final renames = <(String, String)>[];

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async {
    reads.add(parentViewId);
    if (!views.containsKey(parentViewId)) throw StateError('Unknown folder');
    return FlowyResult.success([
      for (final view in views.values)
        if (view.parentViewId == parentViewId)
          ViewPB.fromBuffer(view.writeToBuffer()),
    ]);
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAncestors(
    String viewId,
  ) async {
    final result = <ViewPB>[];
    for (var view = views[viewId];
        view != null;
        view = views[view.parentViewId]) {
      result.insert(0, view);
    }
    return FlowyResult.success(result);
  }

  @override
  Future<FlowyResult<void, FlowyError>> move({
    required String viewId,
    required String parentViewId,
    String? previousViewId,
  }) async {
    moves.add((viewId, parentViewId));
    views[viewId]!.parentViewId = parentViewId;
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    renames.add((viewId, name));
    final view = views[viewId]!;
    view.name = name;
    return FlowyResult.success(view);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewLoader extends FolderGalleryPreviewLoader {
  _PreviewLoader({required this.pendingWritten, required this.failedWritten});

  final bool pendingWritten;
  final bool failedWritten;
  final pending = Completer<FolderGalleryPreview>();
  final loads = <String, int>{};

  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    final count =
        loads.update(view.id, (value) => value + 1, ifAbsent: () => 1);
    if (view.id == _writtenId) {
      if (failedWritten && count == 1) {
        return FolderGalleryPreviewParser.unavailable(view: view, item: item);
      }
      if (pendingWritten || failedWritten) return pending.future;
    }
    if (item.isFolder) {
      return FolderGalleryPreviewParser.withoutDocument(
        view: view,
        item: item,
      )!;
    }
    if (view.id == _tableId) {
      return const FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.database,
        blocks: [],
        wordCount: 0,
        readingMinutes: 0,
        tags: [],
        fileTypeLabel: 'TABLE',
        database: FolderGalleryDatabaseSnapshot(
          columns: [
            'Name',
          ],
          rows: [
            ['Stored row'],
          ],
          totalRowCount: 1,
        ),
      );
    }
    return view.id == _writtenId || view.id == _fileId
        ? _writtenPreview
        : _emptyPreview;
  }
}
