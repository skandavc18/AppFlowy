import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('folder picker lists folders and returns the selected folder',
      (tester) async {
    final folder = ViewPB()
      ..id = 'folder-id'
      ..name = 'Projects'
      ..layout = ViewLayoutPB.Document
      ..extra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');
    final page = ViewPB()
      ..id = 'page-id'
      ..name = 'Project brief'
      ..layout = ViewLayoutPB.Document;
    ViewPB? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceFolderPickerMenu(
            repository: _PickerRepository([folder, page]),
            onSelected: (folder) => selected = folder,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Project brief'), findsNothing);

    await tester.tap(find.text('Projects'));
    await tester.pump();

    expect(selected?.id, 'folder-id');
  });

  testWidgets('file picker lists only stored workspace files', (tester) async {
    final file = ViewPB()
      ..id = 'file-id'
      ..name = 'report.pdf'
      ..layout = ViewLayoutPB.Document
      ..extra = const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        mimeType: 'application/pdf',
        storageUrl: 'C:\\AppFlowy\\files\\report.pdf',
      ).mergeIntoExtra('');
    final legacyFile = ViewPB()
      ..id = 'legacy-file-id'
      ..name = 'legacy.txt'
      ..layout = ViewLayoutPB.Document
      ..extra = const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.collaborativeText,
      ).mergeIntoExtra('');
    final folder = ViewPB()
      ..id = 'folder-id'
      ..name = 'Projects'
      ..layout = ViewLayoutPB.Document
      ..extra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');
    ViewPB? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceFilePickerMenu(
            repository: _PickerRepository([file, legacyFile, folder]),
            onSelected: (file) => selected = file,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('legacy.txt'), findsNothing);
    expect(find.text('Projects'), findsNothing);

    await tester.tap(find.text('report.pdf'));
    await tester.pump();

    expect(selected?.id, 'file-id');
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
