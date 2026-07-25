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
