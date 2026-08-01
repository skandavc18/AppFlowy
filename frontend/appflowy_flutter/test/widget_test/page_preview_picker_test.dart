import 'dart:convert';
import 'dart:ui';

import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('page preview picker returns only previewable pages',
      (tester) async {
    final page = ViewPB(
      id: 'page-id',
      name: 'Project brief',
      parentViewId: 'space-id',
      layout: ViewLayoutPB.Document,
    );
    final currentPage = ViewPB(
      id: 'current-id',
      name: 'Current page',
      parentViewId: 'space-id',
      layout: ViewLayoutPB.Document,
    );
    final workspaceRoot = ViewPB(
      id: 'root-id',
      name: 'Workspace',
      layout: ViewLayoutPB.Document,
    );
    final space = ViewPB(
      id: 'space-id',
      name: 'Personal',
      parentViewId: 'root-id',
      layout: ViewLayoutPB.Document,
      extra: jsonEncode({'is_space': true}),
    );
    final folder = ViewPB(
      id: 'folder-id',
      name: 'Projects',
      parentViewId: 'space-id',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    final table = ViewPB(
      id: 'table-id',
      name: 'Project tracker',
      parentViewId: 'space-id',
      layout: ViewLayoutPB.Grid,
    );
    ViewPB? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceViewPickerMenu(
            title: 'Page preview',
            searchHint: 'Search',
            emptyMessage: 'No pages found',
            errorMessage: 'Failed to load pages',
            repository: _PickerRepository([
              page,
              currentPage,
              workspaceRoot,
              space,
              folder,
              table,
            ]),
            viewFilter: (view) => isPagePreviewCandidate(
              view,
              currentViewId: currentPage.id,
            ),
            leadingBuilder: (_, __, palette) => Icon(
              Icons.description_outlined,
              color: palette.textSecondary,
            ),
            onSelected: (view) => selected = view,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project brief'), findsOneWidget);
    expect(find.text('Project tracker'), findsOneWidget);
    expect(find.text('Current page'), findsNothing);
    expect(find.text('Workspace'), findsNothing);
    expect(find.text('Personal'), findsNothing);
    expect(find.text('Projects'), findsNothing);

    await tester.tap(find.text('Project tracker'));
    await tester.pump();

    expect(selected?.id, table.id);
  });

  testWidgets('page preview card invokes its open action', (tester) async {
    final page = ViewPB(
      id: 'page-id',
      name: 'Project brief',
      parentViewId: 'space-id',
      layout: ViewLayoutPB.Document,
    );
    var opened = false;

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 600,
          child: PagePreviewCard(
            view: page,
            userProfile: null,
            previewCache: FolderGalleryPreviewCache(
              loader: _PreviewLoader(),
            ),
            onOpen: () => opened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('page-preview-card'))),
    );
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('page preview menu switches between content and cover', (
    tester,
  ) async {
    final page = ViewPB(
      id: 'page-id',
      name: 'Project brief',
      parentViewId: 'space-id',
      layout: ViewLayoutPB.Document,
      extra: ViewCoverCodec.mergeCover(
        '',
        const PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#D9C7A4',
        ),
      ),
    );
    ViewPreviewMode? selectedMode;

    await tester.pumpWidget(
      WidgetTestApp(
        child: SizedBox(
          width: 600,
          child: PagePreviewCard(
            view: page,
            userProfile: null,
            previewCache: FolderGalleryPreviewCache(
              loader: _PreviewLoader(),
            ),
            previewMode: ViewPreviewMode.content,
            onPreviewModeChanged: (mode) => selectedMode = mode,
            onChangePage: () {},
            onOpen: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ViewCoverImage), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location:
          tester.getCenter(find.byKey(const ValueKey('page-preview-card'))),
    );
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(find.byKey(const ValueKey('page-preview-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.photo_rounded));
    await tester.pumpAndSettle();

    expect(selectedMode, ViewPreviewMode.cover);
    await mouse.removePointer();
  });
}

class _PickerRepository implements WorkspaceItemRepository {
  const _PickerRepository(this.views);

  final List<ViewPB> views;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async =>
      FlowyResult.success(views);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewLoader extends FolderGalleryPreviewLoader {
  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async =>
      const FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.document,
        blocks: [],
        wordCount: 0,
        readingMinutes: 0,
        tags: [],
        fileTypeLabel: 'PAGE',
      );
}
