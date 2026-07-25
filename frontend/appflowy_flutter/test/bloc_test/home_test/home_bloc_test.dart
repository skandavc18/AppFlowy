import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/workspace/application/home/home_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../util.dart';

void main() {
  late AppFlowyUnitTest testContext;
  setUpAll(() async {
    testContext = await AppFlowyUnitTest.ensureInitialized();
  });

  test('init home screen', () async {
    final workspaceSetting = await FolderEventGetCurrentWorkspaceSetting()
        .send()
        .then((result) => result.fold((l) => l, (r) => throw Exception()));
    await blocResponseFuture();

    final homeBloc = HomeBloc(workspaceSetting)..add(const HomeEvent.initial());
    await blocResponseFuture();

    assert(homeBloc.state.workspaceSetting.hasLatestView());
  });

  test('open the document', () async {
    final workspaceSetting = await FolderEventGetCurrentWorkspaceSetting()
        .send()
        .then((result) => result.fold((l) => l, (r) => throw Exception()));
    await blocResponseFuture();

    final homeBloc = HomeBloc(workspaceSetting)..add(const HomeEvent.initial());
    await blocResponseFuture();

    final app = await testContext.createWorkspace();
    final appBloc = ViewBloc(view: app)..add(const ViewEvent.initial());
    assert(appBloc.state.lastCreatedView == null);

    appBloc.add(
      const ViewEvent.createView(
        "New document",
        ViewLayoutPB.Document,
        section: ViewSectionPB.Public,
      ),
    );
    await blocResponseFuture();

    assert(appBloc.state.lastCreatedView != null);
    final latestView = appBloc.state.lastCreatedView!;
    final _ = DocumentBloc(documentId: latestView.id)
      ..add(const DocumentEvent.initial());

    await FolderEventSetLatestView(ViewIdPB(value: latestView.id)).send();
    await blocResponseFuture();

    final actual = homeBloc.state.workspaceSetting.latestView.id;
    assert(actual == latestView.id);
  });

  test('clears a workspace root saved as the latest document view', () async {
    final original = await FolderEventGetCurrentWorkspaceSetting().send().then(
          (result) => result.fold(
            (setting) => setting,
            (error) => throw Exception(error),
          ),
        );
    final originalLatestId =
        original.hasLatestView() ? original.latestView.id : null;
    addTearDown(() async {
      await FolderEventSetLatestView(
        ViewIdPB(value: originalLatestId ?? ''),
      ).send();
    });

    final poisoned = WorkspaceLatestPB(
      workspaceId: 'workspace',
      latestView: ViewPB(
        id: 'workspace',
        parentViewId: '',
        layout: ViewLayoutPB.Document,
      ),
    );

    final homeBloc = HomeBloc(poisoned)..add(const HomeEvent.initial());
    addTearDown(homeBloc.close);
    await blocResponseFuture(millisecond: 800);

    expect(homeBloc.state.latestView?.id, 'workspace');
    expect(homeBloc.state.latestView?.isWorkspaceFolder, isTrue);
    final repaired = await FolderEventGetCurrentWorkspaceSetting().send().then(
          (result) => result.fold(
            (setting) => setting,
            (error) => throw Exception(error),
          ),
        );
    expect(repaired.hasLatestView(), isFalse);
  });

  test('opens the workspace folder when no latest view exists', () async {
    final homeBloc = HomeBloc(
      WorkspaceLatestPB(workspaceId: 'workspace'),
    )..add(const HomeEvent.initial());
    addTearDown(homeBloc.close);
    await blocResponseFuture(millisecond: 500);

    final latestView = homeBloc.state.latestView;
    expect(latestView?.id, 'workspace');
    expect(latestView?.parentViewId, isEmpty);
    expect(latestView?.isWorkspaceFolder, isTrue);
  });
}
