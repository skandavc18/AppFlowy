import 'dart:async';
import 'dart:ui';

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/data/repositories/workspace_repository.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/presentation/widgets/workspace_cover_actions.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_collection_preview.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart' as user;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

const _pointerAway = Offset(-10, -10);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  _desktopTest('renders and interacts with a rich gallery card in paper mode', (
    tester,
  ) async {
    final view = ViewPB(
      id: 'document',
      name: 'Project brief',
      layout: ViewLayoutPB.Document,
    );
    final item = WorkspaceExplorerItem.fromView(view);
    var openCount = 0;
    var moreCount = 0;
    var renameCount = 0;

    await tester.pumpWidget(
      WidgetTestApp(
        child: Builder(
          builder: (context) {
            return Theme(
              data: Theme.of(context).copyWith(
                extensions: [
                  ...Theme.of(context).extensions.values,
                  const PaperThemeExtension(enabled: true),
                ],
              ),
              child: Center(
                child: SizedBox(
                  width: 310,
                  child: FolderGalleryCard(
                    item: item,
                    view: view,
                    preview: Future.value(
                      const FolderGalleryPreview(
                        kind: FolderGalleryPreviewKind.document,
                        blocks: [
                          FolderGalleryPreviewBlock(
                            kind: FolderGalleryPreviewBlockKind.heading,
                            runs: [
                              FolderGalleryTextRun(text: 'Launch plan'),
                            ],
                            level: 2,
                          ),
                          FolderGalleryPreviewBlock(
                            kind: FolderGalleryPreviewBlockKind.todo,
                            runs: [
                              FolderGalleryTextRun(
                                text: 'Polish the gallery experience',
                                bold: true,
                              ),
                            ],
                            checked: true,
                          ),
                        ],
                        wordCount: 12,
                        readingMinutes: 1,
                        tags: ['planning'],
                        fileTypeLabel: 'PAGE',
                      ),
                    ),
                    userProfile: null,
                    selected: false,
                    editing: false,
                    onTap: () => openCount++,
                    onRename: () => renameCount++,
                    onRenameSubmitted: (_) async => true,
                    onRenameCancelled: () {},
                    onMore: (_) => moreCount++,
                    onContextMenu: (_) {},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project brief'), findsOneWidget);
    expect(find.text('Launch plan'), findsOneWidget);
    expect(find.text('Polish the gallery experience'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final surface = find.descendant(
      of: find.byType(FolderGalleryCard),
      matching: find.byType(GalleryCardSurface),
    );
    expect(surface, findsOneWidget);
    final palette = GalleryCardPalette.of(tester.element(surface));
    final cardSurface = tester.widget<DecoratedBox>(
      find.descendant(
        of: surface,
        matching: find.byKey(const ValueKey('gallery-card-surface')),
      ),
    );
    final decoration = cardSurface.decoration as BoxDecoration;
    expect(cardSurface.position, DecorationPosition.background);
    expect(decoration.color, palette.surface);
    // The gallery sheet now separates from the warm writing preview.
    expect(
      decoration.color,
      Color.lerp(
        PaperTheme.editorPreviewBackground,
        PaperTheme.controlBackground,
        0.75,
      ),
    );
    expect(decoration.border, isNull);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(WorkspaceTokens.cardRadius),
    );
    expect(decoration.boxShadow, palette.restingShadows);
    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

    final overflow = find.byKey(const ValueKey('folder-gallery-more'));
    expect(tester.widget(overflow), isA<IconButton>());
    final overflowIgnoring = find.ancestor(
      of: overflow,
      matching: find.byType(IgnorePointer),
    );
    expect(
      tester.widget<IgnorePointer>(overflowIgnoring.first).ignoring,
      isTrue,
    );
    expect(overflow.hitTestable(), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(FolderGalleryCard)),
    );
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester.widget<IgnorePointer>(overflowIgnoring.first).ignoring,
      isFalse,
    );
    await _mouseTap(tester, mouse, overflow);
    expect(moreCount, 1);

    await _mouseTap(tester, mouse, find.text('Launch plan'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(openCount, 1);
    final cardTitle = find.descendant(
      of: find.byType(FolderGalleryCard),
      matching: find.text('Project brief'),
    );
    await _mouseTap(tester, mouse, cardTitle);
    await tester.pump(const Duration(milliseconds: 50));
    await _mouseTap(tester, mouse, cardTitle);
    await tester.pump(const Duration(milliseconds: 350));
    expect(renameCount, 1);
    expect(openCount, 1);

    await mouse.moveTo(_pointerAway);
    await tester.pumpAndSettle();
    await _expectNativeFocusAndBlur(
      tester,
      button: overflow,
      content: find.descendant(
        of: overflow,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is WorkspaceGlyph &&
              widget.icon == Icons.more_horiz_rounded &&
              widget.name == 'dots-three',
        ),
      ),
      checkActivation: () {
        expect(moreCount, 2);
        expect(openCount, 1, reason: 'Overflow must not open the card.');
        expect(renameCount, 1);
      },
    );
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets('renders nested folders with the shared folder identity glyph', (
    tester,
  ) async {
    final view = ViewPB(
      id: 'collection',
      name: 'Research',
      layout: ViewLayoutPB.Document,
    );
    final item = WorkspaceExplorerItem(
      id: view.id,
      parentId: '',
      name: view.name,
      kind: WorkspaceExplorerItemKind.folder,
      metadata: null,
      hasChildren: true,
      lastEdited: null,
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: Center(
          child: SizedBox(
            width: 330,
            child: FolderGalleryCard(
              item: item,
              view: view,
              preview: Future.value(
                const FolderGalleryPreview(
                  kind: FolderGalleryPreviewKind.folder,
                  blocks: [],
                  wordCount: 0,
                  readingMinutes: 0,
                  tags: [],
                  fileTypeLabel: 'COLLECTION',
                ),
              ),
              userProfile: null,
              selected: false,
              editing: false,
              onTap: () {},
              onRename: () {},
              onRenameSubmitted: (_) async => true,
              onRenameCancelled: () {},
              onMore: (_) {},
              onContextMenu: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Research'), findsOneWidget);
    expect(find.byIcon(Icons.folder_rounded), findsNothing);
    expect(find.byIcon(Icons.folder_open_rounded), findsNothing);
    final glyph = tester.widget<WorkspaceGlyph>(
      find.descendant(
        of: find.byType(FolderGalleryCollectionArtwork),
        matching: find.byType(WorkspaceGlyph),
      ),
    );
    expect(glyph.name, 'folder');
    expect(glyph.size, 64);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content mode renders page content instead of its cover', (
    tester,
  ) async {
    final coverExtra = ViewCoverCodec.mergeCover(
      '',
      const PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#D9C7A4',
      ),
    );
    final view = ViewPB(
      id: 'content-page',
      name: 'Content page',
      layout: ViewLayoutPB.Document,
      extra: ViewPreviewModeCodec.merge(
        coverExtra,
        ViewPreviewMode.content,
      ),
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 310,
          child: FolderGalleryCard(
            item: WorkspaceExplorerItem.fromView(view),
            view: view,
            preview: Future.value(
              const FolderGalleryPreview(
                kind: FolderGalleryPreviewKind.document,
                blocks: [
                  FolderGalleryPreviewBlock(
                    kind: FolderGalleryPreviewBlockKind.paragraph,
                    runs: [
                      FolderGalleryTextRun(text: 'Rendered page content'),
                    ],
                  ),
                ],
                wordCount: 3,
                readingMinutes: 1,
                tags: [],
                fileTypeLabel: 'PAGE',
              ),
            ),
            userProfile: null,
            selected: false,
            editing: false,
            onTap: () {},
            onRename: () {},
            onRenameSubmitted: (_) async => true,
            onRenameCancelled: () {},
            onMore: (_) {},
            onContextMenu: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ViewCoverImage), findsNothing);
    expect(find.text('Rendered page content'), findsOneWidget);
  });

  testWidgets('collection content mode ignores the collection cover', (
    tester,
  ) async {
    final folder = ViewPB(
      id: 'folder',
      name: 'Research',
      layout: ViewLayoutPB.Document,
      extra: ViewCoverCodec.mergeCover(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
        const PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#D9C7A4',
        ),
      ),
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 640,
          child: FolderCollectionPreview(
            folder: folder,
            userProfile: null,
            repository: _HeaderRepository(folder),
            previewMode: ViewPreviewMode.content,
            onOpen: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ViewCoverImage), findsNothing);
    expect(
      find.byKey(const ValueKey('folder-collection-cover')),
      findsOneWidget,
    );
  });

  testWidgets('uses equal preview heights and renders real table values', (
    tester,
  ) async {
    final page = ViewPB(
      id: 'page',
      name: 'Launch notes',
      layout: ViewLayoutPB.Document,
    );
    final folder = ViewPB(
      id: 'folder',
      name: 'Planning',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    final table = ViewPB(
      id: 'table',
      name: 'Roadmap',
      layout: ViewLayoutPB.Grid,
    );
    final previews = <ViewPB, FolderGalleryPreview>{
      page: const FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.document,
        blocks: [],
        wordCount: 0,
        readingMinutes: 0,
        tags: [],
        fileTypeLabel: 'PAGE',
      ),
      folder: const FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.folder,
        blocks: [],
        wordCount: 0,
        readingMinutes: 0,
        tags: [],
        fileTypeLabel: 'COLLECTION',
      ),
      table: const FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.database,
        blocks: [],
        wordCount: 0,
        readingMinutes: 0,
        tags: [],
        fileTypeLabel: 'TABLE',
        database: FolderGalleryDatabaseSnapshot(
          columns: ['Task', 'Owner'],
          rows: [
            ['Launch website', 'Avery'],
            ['Write release notes', 'Morgan'],
          ],
          totalRowCount: 2,
        ),
      ),
    };

    await tester.pumpWidget(
      WidgetTestApp(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final view in previews.keys)
                SizedBox(
                  width: 290,
                  child: FolderGalleryCard(
                    item: WorkspaceExplorerItem.fromView(view),
                    view: view,
                    preview: Future.value(previews[view]),
                    userProfile: null,
                    selected: false,
                    editing: false,
                    onTap: () {},
                    onRename: () {},
                    onRenameSubmitted: (_) async => true,
                    onRenameCancelled: () {},
                    onMore: (_) {},
                    onContextMenu: (_) {},
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final previewStages =
        find.byKey(const ValueKey('folder-gallery-preview-stage'));
    expect(previewStages, findsNWidgets(3));
    // The stage fills whatever height the card is given, so what matters is
    // that a page, a folder and a table all end up on the same line — not the
    // particular figure, which follows the card width.
    final heights = <double>[
      for (final element in previewStages.evaluate())
        (element.renderObject! as RenderBox).size.height,
    ];
    expect(heights.first, greaterThan(0));
    expect(heights.every((height) => height == heights.first), isTrue);
    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Launch website'), findsOneWidget);
    expect(find.text('Avery'), findsOneWidget);
    expect(find.text('Write release notes'), findsOneWidget);
    expect(find.text('Morgan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses premium artwork for an empty table preview', (
    tester,
  ) async {
    final table = ViewPB(
      id: 'empty-table',
      name: 'Ideas',
      layout: ViewLayoutPB.Grid,
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: Center(
          child: SizedBox(
            width: 290,
            child: FolderGalleryCard(
              item: WorkspaceExplorerItem.fromView(table),
              view: table,
              preview: Future.value(
                const FolderGalleryPreview(
                  kind: FolderGalleryPreviewKind.database,
                  blocks: [],
                  wordCount: 0,
                  readingMinutes: 0,
                  tags: [],
                  fileTypeLabel: 'TABLE',
                  database: FolderGalleryDatabaseSnapshot(
                    columns: ['Name', 'Status'],
                    rows: [],
                    totalRowCount: 0,
                  ),
                ),
              ),
              userProfile: null,
              selected: false,
              editing: false,
              onTap: () {},
              onRename: () {},
              onRenameSubmitted: (_) async => true,
              onRenameCancelled: () {},
              onMore: (_) {},
              onContextMenu: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final artwork =
        find.byKey(const ValueKey('folder-gallery-empty-table-artwork'));
    expect(artwork, findsOneWidget);
    expect((tester.renderObject(artwork) as RenderBox).size.isEmpty, isFalse);
    expect(
      find.byKey(const ValueKey('folder-gallery-database-grid')),
      findsNothing,
    );
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits an unavailable preview inside a small card', (
    tester,
  ) async {
    final chat = ViewPB(
      id: 'chat',
      name: 'How to use Kanban to manage tasks',
      layout: ViewLayoutPB.Chat,
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: Center(
          child: SizedBox(
            width: 196,
            height: 196 * 1.18,
            child: FolderGalleryCard(
              item: WorkspaceExplorerItem.fromView(chat),
              view: chat,
              preview: Future.value(
                const FolderGalleryPreview(
                  kind: FolderGalleryPreviewKind.database,
                  blocks: [],
                  wordCount: 0,
                  readingMinutes: 0,
                  tags: [],
                  fileTypeLabel: 'TABLE',
                  unavailable: true,
                ),
              ),
              userProfile: null,
              selected: false,
              editing: false,
              onTap: () {},
              onRename: () {},
              onRenameSubmitted: (_) async => true,
              onRenameCancelled: () {},
              onMore: (_) {},
              onContextMenu: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps populated table previews legible in dark mode', (
    tester,
  ) async {
    final table = ViewPB(
      id: 'dark-table',
      name: 'Roadmap',
      layout: ViewLayoutPB.Grid,
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: Theme(
          data: ThemeData.dark(),
          child: Center(
            child: SizedBox(
              width: 290,
              child: FolderGalleryCard(
                item: WorkspaceExplorerItem.fromView(table),
                view: table,
                preview: Future.value(
                  const FolderGalleryPreview(
                    kind: FolderGalleryPreviewKind.database,
                    blocks: [],
                    wordCount: 0,
                    readingMinutes: 0,
                    tags: [],
                    fileTypeLabel: 'TABLE',
                    database: FolderGalleryDatabaseSnapshot(
                      columns: ['Task', 'Owner'],
                      rows: [
                        ['Launch website', 'Avery'],
                        ['Write release notes', 'Morgan'],
                      ],
                      totalRowCount: 2,
                    ),
                  ),
                ),
                userProfile: null,
                selected: false,
                editing: false,
                onTap: () {},
                onRename: () {},
                onRenameSubmitted: (_) async => true,
                onRenameCancelled: () {},
                onMore: (_) {},
                onContextMenu: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('folder-gallery-database-grid')),
    );
    final gridColor = (grid.decoration as BoxDecoration).color!;
    final header = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('folder-gallery-database-header-row')),
    );
    final headerColor = (header.decoration as BoxDecoration).color!;
    final taskColor = tester.widget<Text>(find.text('Task')).style!.color!;

    expect(gridColor.a, 1);
    expect(gridColor.computeLuminance(), lessThan(0.25));
    expect(headerColor, isNot(gridColor));
    expect(_contrastRatio(taskColor, headerColor), greaterThan(4.5));
    expect(find.text('Launch website'), findsOneWidget);
    expect(find.text('Avery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _desktopTest('clicking the gallery heading renames the folder inline', (
    tester,
  ) async {
    final root = ViewPB(
      id: 'root',
      name: 'Research',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    final repository = _HeaderRepository(root);
    final controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );
    final searchController = TextEditingController();
    await controller.initialize();

    await tester.pumpWidget(
      WidgetTestApp(
        child: _HeaderViewport(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => FolderGalleryHeader(
              controller: controller,
              workspace: user.UserWorkspacePB(
                workspaceId: 'workspace',
                cover: '{"cover":{"type":"color","value":"#D9C7A4"}}',
              ),
              searchController: searchController,
              onSearchChanged: (_) {},
              onNavigate: (_) {},
              onAddFile: (_) {},
              onCreateCollection: (_) {},
              onCreateDatabase: (_) {},
              onMore: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Research'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('folder-gallery-title-icon')),
      findsOneWidget,
    );
    expect(find.byType(ViewIconPicker), findsNWidgets(2));
    expect(find.text('Add icon'), findsOneWidget);
    expect(find.text('Add Cover'), findsOneWidget);
    expect(find.byType(ViewCoverImage), findsNothing);
    final addCover = find.widgetWithText(TextButton, 'Add Cover');
    final decorationOpacity = _actionOpacity(addCover);
    expect(
      tester.widget<AnimatedOpacity>(decorationOpacity).opacity,
      0,
    );
    expect(addCover.hitTestable(), findsNothing);
    expect(
      tester.widget<Text>(find.text('Add icon')).style?.fontSize,
      WorkspaceTypography.style(
        tester.element(find.text('Add icon')),
        WorkspaceTextRole.body,
      ).fontSize,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('folder-gallery-title')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widget<AnimatedOpacity>(decorationOpacity).opacity,
      1,
    );

    await _mouseTap(
      tester,
      mouse,
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Research' &&
            widget.style?.fontSize ==
                WorkspaceTypography.style(
                  tester.element(
                    find.byKey(const ValueKey('folder-gallery-title')),
                  ),
                  WorkspaceTextRole.pageTitle,
                ).fontSize,
      ),
    );
    await tester.pump();
    final editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
    expect(editor, findsOneWidget);

    await tester.enterText(editor, 'Design library');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.root.name, 'Design library');
    expect(editor, findsNothing);
    await mouse.moveTo(_pointerAway);
    await tester.pumpAndSettle();
    _expectActionVisibility(tester, addCover, visible: false);
    await _expectNativeFocusAndBlur(
      tester,
      button: addCover,
      content: find.text('Add Cover'),
    );
    expect(controller.root.name, 'Design library');
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    searchController.dispose();
    controller.dispose();
  });

  _desktopTest('missing table cover controls hide after header exit and blur', (
    tester,
  ) async {
    final table = ViewPB(
      id: 'table',
      name: 'Roadmap',
      layout: ViewLayoutPB.Grid,
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: _HeaderViewport(
          child: DatabasePageDecoration(
            view: table,
            userProfile: null,
            horizontalPadding: 28,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Roadmap'));
    expect(
      title.style?.fontSize,
      WorkspaceTypography.style(
        tester.element(find.text('Roadmap')),
        WorkspaceTextRole.pageTitle,
      ).fontSize,
    );
    expect(
      find.byKey(const ValueKey('database-page-title-icon')),
      findsOneWidget,
    );
    expect(find.byType(ViewIconPicker), findsNWidgets(2));
    final addCover = find.widgetWithText(TextButton, 'Add Cover');
    final decorationOpacity = _actionOpacity(addCover);
    expect(
      tester.widget<AnimatedOpacity>(decorationOpacity).opacity,
      0,
    );
    expect(addCover.hitTestable(), findsNothing);
    expect(
      tester.widget<Text>(find.text('Add icon')).style?.fontSize,
      WorkspaceTypography.style(
        tester.element(find.text('Add icon')),
        WorkspaceTextRole.body,
      ).fontSize,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('database-page-title')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      tester.widget<AnimatedOpacity>(decorationOpacity).opacity,
      1,
    );
    await mouse.moveTo(_pointerAway);
    await tester.pumpAndSettle();
    _expectActionVisibility(tester, addCover, visible: false);
    await _expectNativeFocusAndBlur(
      tester,
      button: addCover,
      content: find.text('Add Cover'),
    );
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets('gallery header and cards share one page scroll', (tester) async {
    final root = ViewPB(
      id: 'root',
      name: 'Research',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    final controller = WorkspaceExplorerController(
      root: root,
      repository: _HeaderRepository(root),
      listenForUpdates: false,
    );
    await controller.initialize();

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 900,
          height: 260,
          child: FolderGallery(
            controller: controller,
            previewCache: FolderGalleryPreviewCache(),
            userProfile: null,
            header: const SizedBox(
              key: ValueKey('gallery-scroll-header'),
              height: 380,
            ),
            onOpen: (_) {},
            onNavigate: (_) {},
            onContextMenu: (_, __) {},
            onRequestDelete: () {},
            onRename: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('gallery-scroll-header'));
    final before = tester.getTopLeft(header).dy;
    await tester.drag(
      find.byKey(const ValueKey('folder-gallery-scroll-view')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(header).dy, lessThan(before - 100));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  _desktopTest('gallery search remains legible when revealed in dark mode',
      (tester) async {
    final root = ViewPB(
      id: 'root',
      name: 'Research',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    final controller = WorkspaceExplorerController(
      root: root,
      repository: _HeaderRepository(root),
      listenForUpdates: false,
    );
    final searchController = TextEditingController();
    await controller.initialize();

    await tester.pumpWidget(
      WidgetTestApp(
        child: Theme(
          data: ThemeData.dark(),
          child: _HeaderViewport(
            child: FolderGalleryHeader(
              controller: controller,
              searchController: searchController,
              onSearchChanged: (_) {},
              onNavigate: (_) {},
              onAddFile: (_) {},
              onCreateCollection: (_) {},
              onCreateDatabase: (_) {},
              onMore: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchIcon = find.byWidgetPredicate(
      (widget) =>
          widget is WorkspaceGlyph && widget.icon == Icons.search_rounded,
    );
    final palette = FolderExplorerPalette.of(tester.element(searchIcon));
    expect(tester.widget<WorkspaceGlyph>(searchIcon).color, palette.accent);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(searchIcon),
    );
    await tester.pumpAndSettle();
    expect(searchIcon.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    searchController.dispose();
    controller.dispose();
  });

  testWidgets('context menu omits actions that do not apply', (tester) async {
    final item = WorkspaceExplorerItem.fromView(
      ViewPB(
        id: 'page',
        parentViewId: 'root',
        name: 'Page',
        layout: ViewLayoutPB.Document,
      ),
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-context-menu'),
            onPressed: () => unawaited(
              showExplorerContextMenu(
                context: context,
                globalPosition: const Offset(20, 20),
                item: item,
                canPaste: false,
                isFavorite: false,
                knowledgeMode: true,
              ),
            ),
            child: const Text('Menu'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-context-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Show content preview'), findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('New note'), findsNothing);
    expect(find.text('New collection'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace cover decorates only the workspace gallery root', (
    tester,
  ) async {
    final root = ViewPB(
      id: 'workspace',
      name: 'My Workspace',
      layout: ViewLayoutPB.Document,
    );
    final repository = _HeaderRepository(root);
    final controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );
    final searchController = TextEditingController();
    await controller.initialize();

    await tester.pumpWidget(
      WidgetTestApp(
        child: _HeaderViewport(
          child: FolderGalleryHeader(
            controller: controller,
            workspace: user.UserWorkspacePB(
              workspaceId: root.id,
              cover: '{"cover":{"type":"color","value":"#D9C7A4"}}',
              role: user.AFRolePB.Owner,
              workspaceType: user.WorkspaceTypePB.LocalW,
            ),
            searchController: searchController,
            onSearchChanged: (_) {},
            onNavigate: (_) {},
            onAddFile: (_) {},
            onCreateCollection: (_) {},
            onCreateDatabase: (_) {},
            onMore: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ViewCoverImage), findsOneWidget);
    expect(find.text('Change Cover'), findsOneWidget);
    expect(find.text('Add icon'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workspace-page-icon-row')),
        matching: find.byKey(const ValueKey('workspace-decoration-icon')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(WorkspacePageCover),
        matching: find.byKey(const ValueKey('workspace-decoration-cover')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-gallery-icon')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    searchController.dispose();
    controller.dispose();
  });

  testWidgets('workspace root leaves a missing cover absent without a write', (
    tester,
  ) async {
    final root = ViewPB(
      id: 'workspace',
      name: 'My Workspace',
      layout: ViewLayoutPB.Document,
    );
    final repository = _HeaderRepository(root);
    final controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );
    final searchController = TextEditingController();
    await controller.initialize();

    final workspace = user.UserWorkspacePB(
      workspaceId: root.id,
      name: root.name,
      role: user.AFRolePB.Owner,
      workspaceType: user.WorkspaceTypePB.LocalW,
    );
    final workspaceRepository = _MockWorkspaceRepository();
    when(
      () => workspaceRepository.updateWorkspaceCover(
        workspaceId: root.id,
        cover: any(named: 'cover'),
      ),
    ).thenAnswer((_) async => FlowyResult.success(null));
    final workspaceBloc = UserWorkspaceBloc(
      repository: workspaceRepository,
      userProfile: user.UserProfilePB(),
    );
    workspaceBloc.emit(
      workspaceBloc.state.copyWith(currentWorkspace: workspace),
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: BlocProvider<UserWorkspaceBloc>.value(
          value: workspaceBloc,
          child: _HeaderViewport(
            child: FolderGalleryHeader(
              controller: controller,
              workspace: workspace,
              searchController: searchController,
              onSearchChanged: (_) {},
              onNavigate: (_) {},
              onAddFile: (_) {},
              onCreateCollection: (_) {},
              onCreateDatabase: (_) {},
              onMore: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    verifyNever(
      () => workspaceRepository.updateWorkspaceCover(
        workspaceId: root.id,
        cover: any(named: 'cover'),
      ),
    );
    expect(find.byType(ViewCoverImage), findsNothing);
    expect(find.text('Add Cover'), findsOneWidget);
    expect(workspaceBloc.state.currentWorkspace?.cover, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    searchController.dispose();
    controller.dispose();
  });

  for (final delayed in [false, true]) {
    _desktopTest(
      delayed
          ? 'workspace cover actions persist delayed changes and removal'
          : 'workspace cover actions persist changes and removal',
      (tester) async {
        final root = ViewPB(
          id: 'workspace',
          name: 'My Workspace',
          layout: ViewLayoutPB.Document,
        );
        final repository = _HeaderRepository(root);
        final controller = WorkspaceExplorerController(
          root: root,
          repository: repository,
          listenForUpdates: false,
        );
        final searchController = TextEditingController();
        final outsideFocus = FocusNode(debugLabel: 'Outside workspace header');
        const outsideKey = ValueKey('workspace-cover-outside-focus');
        await controller.initialize();

        final workspace = user.UserWorkspacePB(
          workspaceId: root.id,
          name: root.name,
          cover: '{"cover":{"type":"color","value":"#D9C7A4"}}',
          role: user.AFRolePB.Owner,
          workspaceType: user.WorkspaceTypePB.LocalW,
        );
        final initialCover = WorkspaceCoverCodec.decode(workspace.cover)!;
        const changedCover = PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#B8D8D8',
        );
        var updateCount = 0;
        final updatedCovers = <String>[];
        final pendingWrites = <Completer<FlowyResult<void, FlowyError>>>[];
        final workspaceRepository = _MockWorkspaceRepository();
        when(
          () => workspaceRepository.updateWorkspaceCover(
            workspaceId: root.id,
            cover: any(named: 'cover'),
          ),
        ).thenAnswer((invocation) {
          updateCount++;
          updatedCovers.add(invocation.namedArguments[#cover]! as String);
          // Keep the original immediate completion as well as a pending write;
          // delaying every response could hide a popup-disposal regression.
          if (!delayed) return Future.value(FlowyResult.success(null));
          final completion = Completer<FlowyResult<void, FlowyError>>();
          pendingWrites.add(completion);
          return completion.future;
        });
        final workspaceBloc = UserWorkspaceBloc(
          repository: workspaceRepository,
          userProfile: user.UserProfilePB(),
        );
        workspaceBloc.emit(
          workspaceBloc.state.copyWith(currentWorkspace: workspace),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: _pointerAway);
          await tester.pumpWidget(
            WidgetTestApp(
              child: BlocProvider<UserWorkspaceBloc>.value(
                value: workspaceBloc,
                child: Column(
                  children: [
                    Expanded(
                      child: _HeaderViewport(
                        child:
                            BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
                          builder: (context, state) => FolderGalleryHeader(
                            controller: controller,
                            workspace: state.currentWorkspace,
                            searchController: searchController,
                            onSearchChanged: (_) {},
                            onNavigate: (_) {},
                            onAddFile: (_) {},
                            onCreateCollection: (_) {},
                            onCreateDatabase: (_) {},
                            onMore: (_) {},
                          ),
                        ),
                      ),
                    ),
                    TextField(
                      key: outsideKey,
                      focusNode: outsideFocus,
                      decoration: const InputDecoration(
                        hintText: 'Outside workspace header',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(updateCount, 0);
          expect(find.byType(ViewCoverImage), findsOneWidget);
          final header = find.byType(FolderGalleryHeader);
          final actions = find.byType(WorkspaceCoverActions);
          final coverButton = find.descendant(
            of: find.byKey(const ValueKey('workspace-decoration-cover')),
            matching: find.byType(TextButton),
          );
          await tester.ensureVisible(coverButton);
          await tester.pumpAndSettle();
          final headerState = tester.state(header);
          final actionsState = tester.state(actions);
          final coveredButtonElement = tester.element(coverButton);

          void expectRetained() {
            expect(tester.state(header), same(headerState));
            expect(tester.state(actions), same(actionsState));
            expect(
              tester.widget<FolderGalleryHeader>(header).controller,
              same(controller),
            );
            expect(
              tester
                  .widget<WorkspaceCoverActions>(actions)
                  .workspace
                  .workspaceId,
              root.id,
            );
          }

          Future<void> moveFocusOutside() async {
            // Removing the cover relocates this native button to the icon
            // region. Its owner/request survives, not the old button/focus.
            final buttonElement = tester.element(coverButton);
            final toolbarFocus = Focus.of(
              tester.element(_actionOpacity(coverButton)),
            );
            final outside = find.byKey(outsideKey);
            expect(outside.hitTestable(), findsOneWidget);
            expect(
              tester
                  .getRect(find.byType(_HeaderViewport))
                  .contains(tester.getCenter(outside)),
              isFalse,
            );
            // A mouse exit is not a blur. Click a real sibling field only
            // AFTER dismissal, rather than clearing the global focus tree.
            await _mouseTap(tester, mouse, outside);
            await tester.pumpAndSettle();
            expect(outsideFocus.hasPrimaryFocus, isTrue);
            expect(outsideFocus.ancestors, isNot(contains(toolbarFocus)));
            expect(toolbarFocus.hasFocus, isFalse);
            _expectActionVisibility(tester, coverButton, visible: false);
            expect(tester.element(coverButton), same(buttonElement));
            expectRetained();
          }

          Future<void> finishWrite(
            PageStyleCover expected, {
            required PageStyleCover previous,
          }) async {
            final buttonElement = tester.element(coverButton);
            final toolbarFocus = Focus.of(
              tester.element(_actionOpacity(coverButton)),
            );
            if (!expected.isNone) {
              expect(buttonElement, same(coveredButtonElement));
            }
            expect(find.byType(UploadImageMenu), findsNothing);
            expect(tester.takeException(), isNull);
            expect(WorkspaceCoverCodec.decode(updatedCovers.last), expected);
            if (delayed) {
              expect(pendingWrites.last.isCompleted, isFalse);
              expect(
                WorkspaceCoverCodec.decode(
                  workspaceBloc.state.currentWorkspace!.cover,
                ),
                previous,
              );
            }
            await moveFocusOutside();
            if (delayed) {
              pendingWrites.last.complete(FlowyResult.success(null));
            }
            await tester.pumpAndSettle();
            expect(workspaceBloc.state.actionResult?.result?.isSuccess, isTrue);
            expect(
              WorkspaceCoverCodec.decode(
                workspaceBloc.state.currentWorkspace!.cover,
              ),
              expected,
            );
            expect(
              WorkspaceCoverCodec.decode(
                tester.widget<FolderGalleryHeader>(header).workspace!.cover,
              ),
              expected,
            );
            if (expected.isNone) {
              expect(find.byType(ViewCoverImage), findsNothing);
              expect(
                find.descendant(
                  of: find.byKey(
                    const ValueKey('workspace-decoration-icon-actions'),
                  ),
                  matching: coverButton,
                ),
                findsOneWidget,
              );
              expect(
                find.byKey(
                  const ValueKey('workspace-decoration-cover-actions'),
                ),
                findsNothing,
              );
            } else {
              expect(
                tester
                    .widget<ViewCoverImage>(find.byType(ViewCoverImage))
                    .cover,
                expected,
              );
            }
            expect(outsideFocus.hasPrimaryFocus, isTrue);
            expect(toolbarFocus.hasFocus, isFalse);
            _expectActionVisibility(tester, coverButton, visible: false);
            // The save echo and blur must retain the current native control
            // within its region, on either side of the cover removal.
            expect(tester.element(coverButton), same(buttonElement));
            expectRetained();
            expect(tester.takeException(), isNull);
          }

          await _mouseTap(tester, mouse, coverButton);
          await tester.pumpAndSettle();
          final uploadMenu = tester.widget<UploadImageMenu>(
            find.byType(UploadImageMenu),
          );
          expect(uploadMenu.onSelectedColor, isNotNull);
          uploadMenu.onSelectedColor!(changedCover.value);
          await tester.pumpAndSettle();

          expect(updateCount, 1);
          expect(
            tester.widget<ViewCoverImage>(find.byType(ViewCoverImage)).cover,
            changedCover,
          );
          await finishWrite(changedCover, previous: initialCover);
          await _expectNativeFocusAndBlur(
            tester,
            button: coverButton,
            content: find.text('Change Cover'),
            moveFocusOutside: moveFocusOutside,
          );
          await _mouseTap(
            tester,
            mouse,
            find.widgetWithText(TextButton, 'Remove cover'),
          );
          await tester.pumpAndSettle();

          expect(updateCount, 2);
          expect(find.byType(ViewCoverImage), findsNothing);
          expect(find.widgetWithText(TextButton, 'Add Cover'), findsOneWidget);
          await finishWrite(
            const PageStyleCover.none(),
            previous: changedCover,
          );
          expect(find.byType(ViewCoverImage), findsNothing);
          expect(
            updatedCovers.map(WorkspaceCoverCodec.decode),
            [changedCover, const PageStyleCover.none()],
          );
          expect(
            updateCount,
            2,
            reason: 'Focus and save echoes must not write.',
          );
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          for (final pending in pendingWrites) {
            if (!pending.isCompleted) {
              pending.complete(FlowyResult.success(null));
            }
          }
          await tester.pump();
          await tester.runAsync(workspaceBloc.close);
          outsideFocus.dispose();
          searchController.dispose();
          controller.dispose();
        }
      },
    );
  }
}

// Flutter's default test platform is Android, whose touch controls correctly
// stay visible. Desktop hover assertions must exercise the Windows policy.
void _desktopTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

Future<void> _mouseTap(
  WidgetTester tester,
  TestGesture mouse,
  Finder target,
) async {
  final position = tester.getCenter(target);
  await mouse.moveTo(position);
  // Apply hover hit-testing before pressing, without introducing a touch
  // reveal latch or advancing the title's double-click deadline.
  await tester.pump();
  // Distinct clicks need distinct pointer IDs, including a double click.
  await tester.tapAt(position, kind: PointerDeviceKind.mouse);
}

Finder _actionOpacity(Finder button) =>
    find.ancestor(of: button, matching: find.byType(AnimatedOpacity)).first;

void _expectActionVisibility(
  WidgetTester tester,
  Finder button, {
  required bool visible,
}) {
  expect(
    tester.widget<AnimatedOpacity>(_actionOpacity(button)).opacity,
    visible ? 1 : 0,
  );
  expect(
    tester
        .widget<IgnorePointer>(
          find.ancestor(of: button, matching: find.byType(IgnorePointer)).first,
        )
        .ignoring,
    !visible,
  );
  expect(button.hitTestable(), visible ? findsOneWidget : findsNothing);
}

Future<void> _expectNativeFocusAndBlur(
  WidgetTester tester, {
  required Finder button,
  required Finder content,
  VoidCallback? checkActivation,
  Future<void> Function()? moveFocusOutside,
  bool remainsVisible = false,
}) async {
  final element = tester.element(button);
  final bounds = tester.getRect(button);
  final focus = Focus.of(tester.element(content));
  expect(focus.canRequestFocus, isTrue);
  expect(focus.skipTraversal, isFalse);
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
  _expectActionVisibility(tester, button, visible: true);
  if (checkActivation != null) {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    checkActivation();
  }

  // Mouse exit is not keyboard blur. Move focus out before asserting hidden;
  // never disable focus or remove the retained control to satisfy the test.
  if (moveFocusOutside != null) {
    await moveFocusOutside();
  } else {
    focus.unfocus();
  }
  await tester.pumpAndSettle();
  expect(focus.hasFocus, isFalse);
  _expectActionVisibility(tester, button, visible: remainsVisible);
  expect(tester.element(button), same(element));
  expect(tester.getRect(button), bounds);
}

/// Page identities are scroll content, not a fixed-height toolbar.
class _HeaderViewport extends StatelessWidget {
  const _HeaderViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 900,
        child: SingleChildScrollView(child: child),
      );
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final high = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final low = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (high + 0.05) / (low + 0.05);
}

class _HeaderRepository implements WorkspaceItemRepository {
  _HeaderRepository(this.root);

  ViewPB root;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async =>
      FlowyResult.success([]);

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    root = ViewPB.fromBuffer(root.writeToBuffer())..name = name;
    return FlowyResult.success(root);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockWorkspaceRepository extends Mock implements WorkspaceRepository {}
