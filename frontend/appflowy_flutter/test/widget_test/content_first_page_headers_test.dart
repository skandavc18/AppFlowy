import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_add_button.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_header.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/document_cover_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/breadcrumb_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _cover = PageStyleCover(
  type: PageStyleCoverImageType.pureColor,
  value: '#D9C7A4',
);
const _inlineEditor = ValueKey('workspace-inline-name-editor');

void main() {
  final previousRecents = RecentIcons.enable;
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = previousRecents);

  for (final appearance in vividIconTestAppearances) {
    testWidgets('$appearance: folder identity retains a rename through reflow',
        (tester) async {
      _largeViewport(tester);
      final frame = _Frame();
      final root = _folder('Research library');
      final repository = _Repository(root);
      final controller = _controller(root, repository);
      final search = TextEditingController();
      var viewOptionsOpened = 0;
      await controller.initialize();
      await tester.pumpWidget(
        _app(
          appearance,
          frame,
          (_) => AnimatedBuilder(
            animation: controller,
            builder: (_, __) => FolderGalleryHeader(
              controller: controller,
              searchController: search,
              onSearchChanged: (query) => unawaited(controller.search(query)),
              onNavigate: (id) => unawaited(controller.navigateTo(id)),
              onAddFile: (_) {},
              onCreateCollection: (_) {},
              onCreateDatabase: (_) {},
              onMore: (_) => viewOptionsOpened++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectIdentity(
        tester,
        'folder-gallery-title-icon',
        'folder-gallery-title',
      );
      _expectCover(tester);
      final viewChoice =
          find.byKey(const ValueKey('folder-gallery-view-switcher'));
      expect(
        tester.getTopLeft(viewChoice).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(const ValueKey('folder-gallery-title')))
              .dy,
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(viewChoice));
      await tester.pumpAndSettle();
      await tester.tap(viewChoice);
      await tester.pumpAndSettle();
      await mouse.removePointer();
      expect(viewOptionsOpened, 1);
      expect(controller.visibleFileCount, 1);
      expect(controller.visibleFolderCount, 1);
      expect(
        PaperTheme.isEnabled(
          tester.element(find.byType(WorkspacePageIdentity)),
        ),
        appearance == 'paper',
      );

      await tester.tap(find.byKey(const ValueKey('folder-gallery-title')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_inlineEditor), 'An unfinished name');
      final field = tester.widget<EditableText>(find.byKey(_inlineEditor));
      final state = tester.state(find.byKey(_inlineEditor));
      const selection = TextSelection(baseOffset: 3, extentOffset: 9);
      field.controller.selection = selection;
      for (final width in [320.0, 760.0, 1280.0]) {
        for (final direction in [ui.TextDirection.ltr, ui.TextDirection.rtl]) {
          frame
            ..width = width
            ..scale = 2
            ..direction = direction;
          for (final hasCover in [false, true]) {
            controller.updateView(
              ViewPB()
                ..mergeFromMessage(root)
                ..extra = ViewCoverCodec.mergeCover(
                  root.extra,
                  hasCover ? _cover : const PageStyleCover.none(),
                ),
            );
            frame.rebuild();
            await tester.pumpAndSettle();
            expect(tester.state(find.byKey(_inlineEditor)), same(state));
            final current =
                tester.widget<EditableText>(find.byKey(_inlineEditor));
            expect(current.controller, same(field.controller));
            expect(current.focusNode, same(field.focusNode));
            expect(current.focusNode.hasFocus, isTrue);
            expect(current.controller.text, 'An unfinished name');
            expect(current.controller.selection, selection);
            expect(
              find.byType(ViewCoverImage),
              hasCover ? findsOneWidget : findsNothing,
            );
            expect(repository.renameCount, 0);
            expect(tester.takeException(), isNull);
          }
        }
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.root.name, root.name);
      expect(repository.renameCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      search.dispose();
      frame.dispose();
    });

    testWidgets(
        '$appearance: database hero retains the title and respects locks',
        (tester) async {
      _largeViewport(tester);
      final frame = _Frame();
      var view = ViewPB(
        id: 'database-header-test',
        name: 'Project roadmap',
        layout: ViewLayoutPB.Grid,
        icon: EmojiIconData.emoji('📘').toViewIcon(),
        extra: AutomaticViewCover.markCoverChosenByHand(
          ViewCoverCodec.mergeCover('', _cover),
        ),
      );
      final original = ViewPB.fromBuffer(view.writeToBuffer());
      await tester.pumpWidget(
        _app(
          appearance,
          frame,
          (_) => DatabasePageDecoration(
            view: view,
            userProfile: null,
            horizontalPadding: 80,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final decorationState = tester.state(find.byType(ViewDecorationActions));
      _expectIdentity(
        tester,
        'database-page-title-icon',
        'database-page-title',
      );
      _expectCover(tester);
      expect(find.byType(ViewIconPicker), findsNWidgets(2));
      expect(find.byType(WorkspaceActionRow), findsNothing);
      expect(
        find.byKey(const ValueKey('workspace-page-actions')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('database-page-title')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_inlineEditor), 'A local title draft');
      final field = tester.widget<EditableText>(find.byKey(_inlineEditor));
      final state = tester.state(find.byKey(_inlineEditor));
      const selection = TextSelection(baseOffset: 2, extentOffset: 7);
      field.controller.selection = selection;
      for (final width in [320.0, 900.0, 1280.0]) {
        for (final decorated in [false, true]) {
          view = ViewPB()
            ..mergeFromMessage(original)
            ..icon =
                decorated ? original.icon : EmojiIconData.none().toViewIcon()
            ..extra = ViewCoverCodec.mergeCover(
              original.extra,
              decorated ? _cover : const PageStyleCover.none(),
            );
          frame
            ..width = width
            ..scale = 2
            ..direction = ui.TextDirection.rtl
            ..rebuild();
          await tester.pumpAndSettle();
          expect(
            tester.state(find.byType(ViewDecorationActions)),
            same(decorationState),
          );
          expect(tester.state(find.byKey(_inlineEditor)), same(state));
          expect(field.focusNode.hasFocus, isTrue);
          expect(field.controller.text, 'A local title draft');
          expect(field.controller.selection, selection);
          expect(view.name, original.name);
          expect(
            find.byType(ViewCoverImage),
            decorated ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      view = ViewPB()
        ..mergeFromMessage(original)
        ..isLocked = true;
      frame.rebuild();
      await tester.pumpAndSettle();
      expect(find.byType(ViewIconPicker), findsNothing);
      expect(find.byType(ViewDecorationActions), findsOneWidget);
      expect(
        tester.state(find.byType(ViewDecorationActions)),
        same(decorationState),
      );
      expect(find.byType(DecorationActionButton), findsNothing);
      expect(find.byType(WorkspaceActionRow), findsNothing);
      expect(find.byType(ViewCoverImage), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('database-page-title')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_inlineEditor), findsNothing);
      expect(view.name, original.name);
      // Read-only removes mutation controls, not downloading a saved image.
      view = ViewPB.fromBuffer(view.writeToBuffer())
        ..extra = ViewCoverCodec.mergeCover(
          view.extra,
          const PageStyleCover(
            type: PageStyleCoverImageType.builtInImage,
            value: 'n1',
          ),
        );
      final lockedSnapshot = view.writeToBuffer();
      frame.rebuild();
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(ViewDecorationActions)),
        same(decorationState),
      );
      expect(find.byType(ViewIconPicker), findsNothing);
      expect(find.byType(WorkspaceActionRow), findsNothing);
      expect(find.byType(DecorationActionButton), findsOneWidget);
      final cover = find.byType(WorkspacePageCover);
      final download = find.descendant(
        of: cover,
        matching: find.byKey(const ValueKey('view-decoration-download')),
      );
      expect(download, findsOneWidget);
      final button = find.descendant(
        of: download,
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      expect(button.hitTestable(), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(cover));
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      expect(view.writeToBuffer(), lockedSnapshot);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      frame.dispose();
    });

    for (final kind in CollectionKind.values) {
      testWidgets(
          '$appearance: ${kind.name} retains content and internal navigation',
          (tester) async {
        _largeViewport(tester);
        final frame = _Frame();
        final definition = CollectionRegistry.typeFor(kind);
        // Only the native/backend content boundary is replaced. The real page,
        // catalogue, saved view ids, graph, header and navigation are exercised.
        CollectionRegistry.register(
          definition.withViews([
            for (final mode in definition.views)
              CollectionViewDefinition(
                id: mode.id,
                labelKey: mode.labelKey,
                icon: mode.icon,
                isAvailable: mode.isAvailable,
                builder: (_, collection) =>
                    _CollectionReading(collection: collection),
              ),
          ]),
        );
        final root = _folder('My ${kind.name}')
          ..extra = CollectionMetadata(kind: kind).mergeIntoExtra(
            ViewCoverCodec.mergeCover(
              const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
              _cover,
            ),
          );
        final repository = _Repository(root);
        final controller = _controller(root, repository);
        await controller.initialize();
        final saved = root.writeToBuffer();
        try {
          await tester.pumpWidget(
            _app(
              appearance,
              frame,
              (_) => CollectionPage(
                view: root,
                controller: controller,
                shellOwnsBreadcrumbs: true,
              ),
              scrollHeader: false,
            ),
          );
          await tester.pumpAndSettle();
          _expectIdentity(tester, 'collection-header-icon', 'collection-title');
          _expectCover(tester);
          expect(find.byIcon(Icons.workspaces_rounded), findsNothing);
          expect(find.byType(BreadcrumbBar), findsNothing);
          expect(find.text('A stored note'), findsOneWidget);
          final switcher = tester.widget<CollectionViewSwitcher>(
            find.byType(CollectionViewSwitcher),
          );
          expect(
            switcher.views.map((view) => view.id),
            definition.views
                .where((view) => view.availableFor(root.source))
                .map((view) => view.id),
          );
          expect(
            tester.getTopLeft(find.byType(CollectionViewSwitcher)).dy,
            greaterThan(
              tester
                  .getBottomLeft(find.byKey(const ValueKey('collection-title')))
                  .dy,
            ),
          );
          final reading = tester.state(find.byType(_CollectionReading));
          final updatedIcon = EmojiIconData.emoji('🌿').toViewIcon();
          final updated = ViewPB()
            ..mergeFromMessage(controller.viewForId(root.id)!)
            ..icon = updatedIcon;
          controller.updateView(updated);
          frame.width = 320;
          frame.rebuild();
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(_CollectionReading)), same(reading));
          expect(controller.viewForId(root.id)!.icon, updatedIcon);
          await controller.navigateTo(repository.nested.id);
          await tester.pumpAndSettle();
          expect(find.byType(BreadcrumbBar), findsOneWidget);
          expect(controller.currentFolder.id, repository.nested.id);
          expect(find.text('Nested stored note'), findsOneWidget);
          tester
              .widget<BreadcrumbBar>(find.byType(BreadcrumbBar))
              .onSelected(root.id);
          await tester.pumpAndSettle();
          expect(controller.currentFolder.id, root.id);
          expect(find.byType(BreadcrumbBar), findsNothing);
          expect(tester.state(find.byType(_CollectionReading)), same(reading));
          final retained = controller.viewForId(root.id)!;
          expect(retained.writeToBuffer(), updated.writeToBuffer());
          expect(retained.icon, updatedIcon);
          expect(retained.extra, root.extra);
          expect(root.writeToBuffer(), saved);
          expect(repository.renameCount, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          // Borrowing a graph must not destroy the embedding host's graph.
          expect(() => controller.updateRoot(root), returnsNormally);
          controller.dispose();
          frame.dispose();
          CollectionRegistry.register(definition);
        }
      });
    }
  }

  testWidgets(
      'document tools are inert while hidden and reveal for keyboard and touch',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final editor = EditorState.blank()..disableSealTimer = true;
    final hover = ValueNotifier(false);
    final outside = FocusNode();
    final changes = <(CoverType, String?)>[];
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pumpWidget(
      vividIconTestApp(
        'paper',
        SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PreviewToolbarRegion(
                key: const ValueKey('document-tools-region'),
                child: DocumentHeaderToolbar(
                  node: editor.document.root,
                  editorState: editor,
                  hasCover: false,
                  hasIcon: true,
                  offset: 0,
                  isCoverTitleHovered: hover,
                  tabs: kAllIconPickerTabs,
                  onIconOrCoverChanged: ({cover, icon}) {
                    if (cover != null) changes.add(cover);
                  },
                ),
              ),
              TextButton(
                focusNode: outside,
                onPressed: () {},
                child: const Text('Outside'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final add = find.widgetWithText(TextButton, 'Add Cover');
    expect(add, findsOneWidget);
    expect(add.hitTestable(), findsNothing);
    expect(find.semantics.byLabel('Add Cover'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_toolbarOpacity(tester), 1);
    final node = tester.getSemantics(add);
    expect(node.getSemanticsData().hasFlag(ui.SemanticsFlag.isButton), isTrue);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(changes, [(CoverType.asset, '1')]);
    outside.requestFocus();
    await tester.pumpAndSettle();
    expect(_toolbarOpacity(tester), 0);
    final region =
        tester.getRect(find.byKey(const ValueKey('document-tools-region')));
    await tester.tapAt(Offset(region.right - 4, region.center.dy));
    await tester.pumpAndSettle();
    expect(_toolbarOpacity(tester), 1);
    expect(changes, hasLength(1));
    await tester.tap(add);
    expect(changes, hasLength(2));
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    hover.dispose();
    outside.dispose();
    semantics.dispose();
  });

  testWidgets(
      'a legacy cover popover stays revealed and has a native keyboard trigger',
      (tester) async {
    final controller = PopoverController();
    final outside = FocusNode();
    await tester.pumpWidget(
      vividIconTestApp(
        'paper',
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PreviewToolbarRegion(
              child: PreviewToolbar(
                child: AppFlowyPopover(
                  controller: controller,
                  child: const DecorationActionButton(
                    icon: FlowySvgs.add_cover_s,
                    label: 'Choose cover',
                  ),
                  popupBuilder: (_) => const SizedBox(
                    width: 140,
                    height: 80,
                    child: Text('Cover choices'),
                  ),
                ),
              ),
            ),
            TextButton(
              focusNode: outside,
              onPressed: () {},
              child: const Text('Outside'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_toolbarOpacity(tester), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Cover choices'), findsOneWidget);
    expect(_toolbarOpacity(tester), 1);
    controller.close();
    await tester.pumpAndSettle();
    outside.requestFocus();
    await tester.pumpAndSettle();
    expect(_toolbarOpacity(tester), 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    outside.dispose();
  });

  testWidgets('locking an open document icon picker releases it for reopening',
      (tester) async {
    final editor = EditorState.blank()..disableSealTimer = true;
    late StateSetter rebuild;
    var changes = 0;
    await tester.pumpWidget(
      vividIconTestApp(
        'paper',
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return PreviewToolbarRegion(
              child: SizedBox.square(
                dimension: WorkspaceTokens.pageIconSize,
                child: DocumentIcon(
                  node: editor.document.root,
                  editorState: editor,
                  icon: EmojiIconData.emoji('📘'),
                  emojiSize: WorkspaceTokens.pageIconSize,
                  documentId: 'document-icon-header-test',
                  onChangeIcon: (_) => changes++,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DocumentIcon));
    await tester.pumpAndSettle();
    expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
    final select = tester
        .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
        .onSelectedEmoji!;
    rebuild(() => editor.editable = false);
    await tester.pumpAndSettle();
    expect(find.byType(FlowyIconEmojiPicker), findsNothing);
    select(EmojiIconData.emoji('🌿').toSelectedResult());
    expect(changes, 0);
    rebuild(() => editor.editable = true);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DocumentIcon));
    await tester.pumpAndSettle();
    expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
    expect(changes, 0);
    expect(tester.takeException(), isNull);
    await disposeVividIconPicker(tester);
    editor.dispose();
  });

  testWidgets('standalone decoration actions honor an explicit hidden state',
      (tester) async {
    await tester.pumpWidget(
      vividIconTestApp(
        'paper',
        ViewDecorationActions(
          view: ViewPB(id: 'hidden-actions'),
          visible: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_toolbarOpacity(tester), 0);
    expect(find.byType(TextButton).hitTestable(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_toolbarOpacity(tester), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'narrow, scaled cover actions stay inside the picture and read-only stays inert',
      (tester) async {
    _largeViewport(tester);
    final frame = _Frame()
      ..width = 320
      ..scale = 2;
    final editor = EditorState.blank()..disableSealTimer = true;
    editor.document.root.updateAttributes({
      DocumentHeaderBlockKeys.coverType: CoverType.color.toString(),
      DocumentHeaderBlockKeys.coverDetails: '0xffd9c7a4',
    });
    var changes = 0;
    await tester.pumpWidget(
      _app(
        'paper',
        frame,
        (_) => DocumentHeaderLayout(
          editorStyle: EditorStyle.desktop(maxWidth: 960),
          title: const Text('Document title'),
          cover: DocumentCover(
            view: ViewPB(id: 'legacy-cover'),
            node: editor.document.root,
            editorState: editor,
            coverType: CoverType.color,
            coverDetails: '0xffd9c7a4',
            onChangeCover: (_, __) => changes++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final coverState = tester.state(find.byType(DocumentCover));
    expect(
      tester.getTopLeft(find.text('Document title')).dy -
          tester.getBottomLeft(find.byType(WorkspacePageCover).first).dy,
      closeTo(8, .01),
      reason:
          'A document without an icon must not overlap its title onto the cover.',
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(DocumentCover)),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(DocumentCover));
    final actions = find.descendant(
      of: find.byType(DocumentCover),
      matching: find.byType(TextButton),
    );
    expect(actions, findsNWidgets(2));
    expect(actions.hitTestable(), findsNWidgets(2));
    for (final element in actions.evaluate()) {
      final action = tester.getRect(find.byWidget(element.widget));
      expect(rect.contains(action.topLeft), isTrue);
      expect(rect.contains(action.bottomRight), isTrue);
    }
    expect(tester.takeException(), isNull);
    editor.editable = false;
    frame.rebuild();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(DocumentCover)), same(coverState));
    expect(actions, findsNothing);
    expect(changes, 0);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    frame.dispose();
  });

  testWidgets(
      'database tabs are native, quiet controls and add remains reachable',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final view = ViewPB(id: 'tab', name: 'Planning', layout: ViewLayoutPB.Grid);
    final selected = <String>[];
    await tester.pumpWidget(
      vividIconTestApp(
        'paper',
        SizedBox(
          width: 250,
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: DatabaseTabBarItem(
                  view: view,
                  isSelected: false,
                  onTap: (view) => selected.add(view.id),
                ),
              ),
              AddDatabaseViewButton(onTap: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VerticalDivider), findsNothing);
    final tab = find.widgetWithText(TextButton, 'Planning');
    final button = tester.widget<TextButton>(tab);
    expect(button.style!.backgroundColor!.resolve({})!.a, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, ['tab']);
    expect(
      tester
          .getSemantics(tab)
          .getSemanticsData()
          .hasFlag(ui.SemanticsFlag.isButton),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TabBarAddButtonAction), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester
        .widget<AppFlowyPopover>(
          find.descendant(
            of: find.byType(AddDatabaseViewButton),
            matching: find.byType(AppFlowyPopover),
          ),
        )
        .controller!
        .close();
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  test('title Tab traversal consumes the event instead of indenting the body',
      () {
    final source = File(
      'lib/plugins/document/presentation/editor_plugins/header/cover_title.dart',
    ).readAsStringSync();
    final tab = source.substring(
      source.indexOf('event.logicalKey == LogicalKeyboardKey.tab'),
    );
    expect(tab, contains('titleFocusNode.previousFocus();'));
    expect(tab, contains('titleFocusNode.nextFocus();'));
    expect(tab, contains('return KeyEventResult.handled;'));
  });

  test('embedded database identity is guarded without changing wrapContent',
      () {
    final source = File('lib/plugins/database/tab_bar/tab_bar_view.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      source,
      contains(
        'widget.showPageDecoration && widget.node == null && !widget.shrinkWrap',
      ),
    );
    expect(
      source,
      contains('if (layout.shrinkWrappable) {\n        return child;'),
    );
    expect(source, contains('return Expanded(child: child);'));
    expect(
      source,
      contains("key: const ValueKey('database-page-scroll-view')"),
    );
  });
}

void _largeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.reset);
}

void _expectIdentity(WidgetTester tester, String iconKey, String titleKey) {
  final icon = tester.getRect(find.byKey(ValueKey(iconKey)));
  final title = tester.getRect(find.byKey(ValueKey(titleKey)));
  expect(icon.bottom, lessThan(title.top));
  expect(
    title.top - icon.bottom,
    closeTo(WorkspaceTokens.pageIconTitleGap, 0.01),
  );
  expect(icon.left, closeTo(title.left, 0.01));
  expect(icon.height, greaterThanOrEqualTo(48));
}

void _expectCover(WidgetTester tester) {
  final header = tester.getRect(find.byType(WorkspacePageHeader));
  final cover = tester.getRect(find.byType(ViewCoverImage));
  final identity = tester.getRect(find.byType(WorkspacePageIdentity));
  expect(cover.left, closeTo(header.left + WorkspaceTokens.coverInset, 0.01));
  expect(cover.right, closeTo(header.right - WorkspaceTokens.coverInset, 0.01));
  expect(cover.width, greaterThanOrEqualTo(identity.width));
  expect(
    cover.height,
    header.width < 600
        ? WorkspaceTokens.compactCoverHeight
        : WorkspaceTokens.coverHeight,
  );
  expect(
    identity.top - cover.bottom,
    closeTo(-22, 0.01),
  );
  expect(
    header.bottom - identity.bottom,
    closeTo(WorkspaceTokens.pageHeaderBottom, 0.01),
  );
}

double _toolbarOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find
          .descendant(
            of: find.byType(PreviewToolbar).first,
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

class _Frame extends ChangeNotifier {
  double width = 1280;
  double scale = 1;
  ui.TextDirection direction = ui.TextDirection.ltr;
  void rebuild() => notifyListeners();
}

Widget _app(
  String appearance,
  _Frame frame,
  WidgetBuilder builder, {
  bool scrollHeader = true,
}) =>
    vividIconTestApp(
      appearance,
      AnimatedBuilder(
        animation: frame,
        builder: (context, _) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(frame.scale)),
          child: Directionality(
            textDirection: frame.direction,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: frame.width,
                height: 1000,
                child: scrollHeader
                    ? SingleChildScrollView(child: Builder(builder: builder))
                    : Builder(builder: builder),
              ),
            ),
          ),
        ),
      ),
    );

ViewPB _folder(String name) => ViewPB(
      id: 'header-test-root',
      name: name,
      layout: ViewLayoutPB.Document,
      icon: EmojiIconData.emoji('📘').toViewIcon(),
      extra: ViewCoverCodec.mergeCover(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
        _cover,
      ),
    );

WorkspaceExplorerController _controller(ViewPB root, _Repository repository) =>
    WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );

class _Repository implements WorkspaceItemRepository {
  _Repository(this.root);

  ViewPB root;
  int renameCount = 0;
  late final nested = ViewPB(
    id: 'nested-folder',
    parentViewId: root.id,
    name: 'Filed notes',
    layout: ViewLayoutPB.Document,
    extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
  );

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async =>
      FlowyResult.success([
        ViewPB(
          id: '$parentViewId-note',
          parentViewId: parentViewId,
          name:
              parentViewId == root.id ? 'A stored note' : 'Nested stored note',
          layout: ViewLayoutPB.Document,
        ),
        if (parentViewId == root.id) nested,
      ]);

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    renameCount++;
    root = ViewPB()
      ..mergeFromMessage(root)
      ..name = name;
    return FlowyResult.success(root);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CollectionReading extends StatefulWidget {
  const _CollectionReading({required this.collection});
  final CollectionViewContext collection;

  @override
  State<_CollectionReading> createState() => _CollectionReadingState();
}

class _CollectionReadingState extends State<_CollectionReading> {
  @override
  Widget build(BuildContext context) => ListView(
        children: [
          for (final row in widget.collection.explorer.rows)
            ListTile(title: Text(row.item.name)),
        ],
      );
}
