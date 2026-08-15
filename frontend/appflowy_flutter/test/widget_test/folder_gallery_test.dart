import 'dart:async';
import 'dart:ui';

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/data/repositories/workspace_repository.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
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
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart' as user;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders and interacts with a rich gallery card in paper mode', (
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

    final cardContainer = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(FolderGalleryCard),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(
      (cardContainer.decoration! as BoxDecoration).color,
      PaperTheme.editorPreviewBackground,
    );
    expect((cardContainer.decoration! as BoxDecoration).border, isNull);
    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

    final overflowIgnoring = find.ancestor(
      of: find.byIcon(Icons.more_horiz_rounded),
      matching: find.byType(IgnorePointer),
    );
    expect(
      tester.widget<IgnorePointer>(overflowIgnoring.first).ignoring,
      isTrue,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(FolderGalleryCard)),
    );
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester.widget<IgnorePointer>(overflowIgnoring.first).ignoring,
      isFalse,
    );
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    expect(moreCount, 1);

    await tester.tap(find.text('Launch plan'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(openCount, 1);
    await tester.tap(find.text('Project brief'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Project brief'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(renameCount, 1);
    expect(openCount, 1);
    await mouse.removePointer();
  });

  testWidgets('renders collections as custom note artwork without folder icons',
      (
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
    expect(find.byType(CustomPaint), findsWidgets);
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

  testWidgets('clicking the gallery heading renames the folder inline', (
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
        child: SizedBox(
          width: 900,
          height: 260,
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
    expect(find.byType(ViewIconPicker), findsWidgets);
    expect(find.text('Add icon'), findsOneWidget);
    expect(find.text('Add Cover'), findsOneWidget);
    expect(find.byType(ViewCoverImage), findsNothing);
    final decorationOpacity = find.descendant(
      of: find.byType(ViewDecorationActions),
      matching: find.byKey(const ValueKey('view-decoration-actions-opacity')),
    );
    expect(
      tester.widget<AnimatedOpacity>(decorationOpacity).opacity,
      0,
    );
    expect(tester.widget<Text>(find.text('Add icon')).style?.fontSize, 14);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(FolderGalleryHeader)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widget<AnimatedOpacity>(decorationOpacity).opacity,
      1,
    );

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Research' &&
            widget.style?.fontSize == 32,
      ),
    );
    await tester.pump();
    final editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
    expect(editor, findsOneWidget);

    await tester.enterText(editor, 'Design library');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.root.name, 'Design library');
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    searchController.dispose();
    controller.dispose();
  });

  testWidgets('full-page tables show a title and hover-only cover controls', (
    tester,
  ) async {
    final table = ViewPB(
      id: 'table',
      name: 'Roadmap',
      layout: ViewLayoutPB.Grid,
    );

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 900,
          height: 180,
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
    expect(title.style?.fontSize, 40);
    expect(
      find.byKey(const ValueKey('database-page-title-icon')),
      findsOneWidget,
    );
    expect(find.byType(ViewIconPicker), findsWidgets);
    final decorationOpacity = find.descendant(
      of: find.byType(ViewDecorationActions),
      matching: find.byKey(const ValueKey('view-decoration-actions-opacity')),
    );
    expect(
      tester.widget<AnimatedOpacity>(decorationOpacity).opacity,
      0,
    );
    expect(tester.widget<Text>(find.text('Add icon')).style?.fontSize, 14);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(DatabasePageDecoration)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      tester.widget<AnimatedOpacity>(decorationOpacity).opacity,
      1,
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

  testWidgets('gallery search remains visible in dark mode', (tester) async {
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
          child: SizedBox(
            width: 900,
            height: 260,
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

    final searchIcon = find.byIcon(Icons.search_rounded);
    final palette = FolderExplorerPalette.of(tester.element(searchIcon));
    expect(tester.widget<Icon>(searchIcon).color, palette.accent);
    expect(tester.takeException(), isNull);
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
        child: SizedBox(
          width: 900,
          height: 520,
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
    expect(find.text('Add icon'), findsNothing);
    expect(
      find.byKey(const ValueKey('workspace-gallery-icon')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    searchController.dispose();
    controller.dispose();
  });

  testWidgets('workspace root generates a missing cover without an eager write',
      (
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
          child: SizedBox(
            width: 900,
            height: 520,
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
    expect(find.byType(ViewCoverImage), findsOneWidget);
    expect(find.text('Change Cover'), findsOneWidget);
    expect(workspaceBloc.state.currentWorkspace?.cover, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    searchController.dispose();
    controller.dispose();
  });

  testWidgets('workspace cover actions persist changes and removal', (
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
      cover: '{"cover":{"type":"color","value":"#D9C7A4"}}',
      role: user.AFRolePB.Owner,
      workspaceType: user.WorkspaceTypePB.LocalW,
    );
    var updateCount = 0;
    final updatedCovers = <String>[];
    final workspaceRepository = _MockWorkspaceRepository();
    when(
      () => workspaceRepository.updateWorkspaceCover(
        workspaceId: root.id,
        cover: any(named: 'cover'),
      ),
    ).thenAnswer((invocation) {
      updateCount++;
      updatedCovers.add(
        invocation.namedArguments[#cover]! as String,
      );
      return Future.value(FlowyResult.success(null));
    });
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
          child: SizedBox(
            width: 900,
            height: 520,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(updateCount, 0);
    expect(find.byType(ViewCoverImage), findsOneWidget);

    await tester.tap(find.text('Change Cover'));
    await tester.pumpAndSettle();
    final uploadMenu = tester.widget<UploadImageMenu>(
      find.byType(UploadImageMenu),
    );
    uploadMenu.onSelectedColor?.call('#B8D8D8');
    await tester.pumpAndSettle();

    expect(updateCount, 1);
    await tester.tap(find.text('Remove cover'));
    await tester.pumpAndSettle();

    expect(updateCount, 2);
    expect(find.byType(ViewCoverImage), findsNothing);
    expect(
      WorkspaceCoverCodec.decode(updatedCovers.first),
      const PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#B8D8D8',
      ),
    );
    expect(
      WorkspaceCoverCodec.decode(updatedCovers.last),
      const PageStyleCover.none(),
    );
    expect(
      WorkspaceCoverCodec.decode(
        workspaceBloc.state.currentWorkspace!.cover,
      ),
      const PageStyleCover.none(),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    searchController.dispose();
    controller.dispose();
  });
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
