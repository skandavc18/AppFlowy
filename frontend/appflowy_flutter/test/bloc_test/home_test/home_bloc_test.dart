import 'dart:async';

import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/workspace/application/home/home_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../util/home_profile_test_support.dart';

void main() {
  for (final latest in [null, 'workspace', 'last-crash-collection']) {
    testWidgets(
      'startup leaves saved latest $latest untouched',
      (tester) async {
        final setting = WorkspaceLatestPB(
          workspaceId: 'workspace',
          latestView: latest == null ? null : ViewPB(id: latest),
        );
        final bytes = setting.writeToBuffer();
        final listener = _FolderListener();
        final home = HomeBloc(setting, workspaceListener: listener)
          ..add(const HomeEvent.initial())
          ..add(const HomeEvent.initial());
        Future<void>? closing;
        try {
          await tester.pump();
          await tester
              .pump(const Duration(seconds: 1)); // Past the old 300ms restore.
          expect(listener.starts, 1);
          expect(home.state.latestView, isNull);
          expect(home.state.workspaceSetting.writeToBuffer(), bytes);
          expect(setting.writeToBuffer(), bytes);
          closing = home.close();
          await pumpHomeProfileClose(tester, closing);
          expect(listener.stops, 1);
        } finally {
          await pumpHomeProfileClose(tester, closing ?? home.close());
        }
      },
      timeout: homeProfileTestTimeout,
    );
  }

  testWidgets(
    'latest notifications update metadata, never a navigation target',
    (tester) async {
      final listener = _FolderListener();
      final home = HomeBloc(
        WorkspaceLatestPB(workspaceId: 'workspace'),
        workspaceListener: listener,
      )..add(const HomeEvent.initial());
      Future<void>? closing;
      try {
        await tester.pump();
        final latest = WorkspaceLatestPB(
          workspaceId: 'workspace',
          latestView: ViewPB(id: 'remote-latest'),
        );
        listener.notify(latest);
        await tester.pump();
        expect(home.state.workspaceSetting, latest);
        expect(home.state.latestView, isNull);
        listener.notify(WorkspaceLatestPB(workspaceId: 'old-workspace'));
        await tester.pump();
        expect(home.state.workspaceSetting, latest);

        // Even a callback already captured by the native listener is safe during
        // its asynchronous stop, and after close. There is no native listener here.
        listener.stopping = Completer<void>();
        closing = home.close();
        listener.notify(WorkspaceLatestPB(workspaceId: 'workspace'));
        listener.stopping!.complete();
        await pumpHomeProfileClose(tester, closing);
        listener.notify(latest);
        await tester.pump();
        expect(home.state.workspaceSetting, latest);
        expect(tester.takeException(), isNull);
      } finally {
        final stopping = listener.stopping;
        if (stopping != null && !stopping.isCompleted) stopping.complete();
        await pumpHomeProfileClose(tester, closing ?? home.close());
      }
    },
    timeout: homeProfileTestTimeout,
  );
}

class _FolderListener extends FolderListener {
  _FolderListener() : super(workspaceId: 'workspace');

  void Function(WorkspaceLatestNotifyValue)? callback;
  Completer<void>? stopping;
  int starts = 0;
  int stops = 0;

  @override
  void start({void Function(WorkspaceLatestNotifyValue)? onLatestUpdated}) {
    starts++;
    callback = onLatestUpdated;
  }

  void notify(WorkspaceLatestPB setting) =>
      callback?.call(FlowyResult.success(setting));

  @override
  Future<void> stop() async {
    stops++;
    await stopping?.future;
  }
}
