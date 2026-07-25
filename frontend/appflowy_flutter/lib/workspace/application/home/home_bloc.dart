import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart'
    show WorkspaceLatestPB;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_bloc.freezed.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc(WorkspaceLatestPB workspaceSetting)
      : _workspaceListener = FolderListener(
          workspaceId: workspaceSetting.workspaceId,
        ),
        super(HomeState.initial(workspaceSetting)) {
    _dispatch(workspaceSetting);
  }

  final FolderListener _workspaceListener;

  @override
  Future<void> close() async {
    await _workspaceListener.stop();
    return super.close();
  }

  void _dispatch(WorkspaceLatestPB workspaceSetting) {
    on<HomeEvent>(
      (event, emit) async {
        await event.map(
          initial: (_Initial value) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (!isClosed) {
                add(HomeEvent.didReceiveWorkspaceSetting(workspaceSetting));
              }
            });

            _workspaceListener.start(
              onLatestUpdated: (result) {
                result.fold(
                  (latest) => add(HomeEvent.didReceiveWorkspaceSetting(latest)),
                  (r) => Log.error(r),
                );
              },
            );
          },
          showLoading: (e) async {
            emit(state.copyWith(isLoading: e.isLoading));
          },
          didReceiveWorkspaceSetting: (
            _DidReceiveWorkspaceSetting value,
          ) async {
            // the latest view is shared across all the members of the workspace.

            final hasLatestView = value.setting.hasLatestView();
            var latestView =
                hasLatestView ? value.setting.latestView : state.latestView;
            var workspaceRootName = 'Workspace';

            if (hasLatestView &&
                latestView?.isWorkspaceRootFor(value.setting.workspaceId) ==
                    true) {
              if (latestView!.name.isNotEmpty) {
                workspaceRootName = latestView.name;
              }
              final result = await FolderEventSetLatestView(ViewIdPB()).send();
              result.fold(
                (_) {},
                (error) => Log.error(
                  'Failed to clear workspace root as latest view: $error',
                ),
              );
              latestView = null;
            }

            if ((latestView == null || latestView.isSpace) &&
                value.setting.workspaceId.isNotEmpty) {
              latestView = workspaceRootFolderView(
                workspaceId: value.setting.workspaceId,
                name: workspaceRootName,
              );
            }

            emit(
              state.copyWith(
                workspaceSetting: value.setting,
                latestView: latestView,
              ),
            );
          },
        );
      },
    );
  }
}

@freezed
class HomeEvent with _$HomeEvent {
  const factory HomeEvent.initial() = _Initial;
  const factory HomeEvent.showLoading(bool isLoading) = _ShowLoading;
  const factory HomeEvent.didReceiveWorkspaceSetting(
    WorkspaceLatestPB setting,
  ) = _DidReceiveWorkspaceSetting;
}

@freezed
class HomeState with _$HomeState {
  const factory HomeState({
    required bool isLoading,
    required WorkspaceLatestPB workspaceSetting,
    ViewPB? latestView,
  }) = _HomeState;

  factory HomeState.initial(WorkspaceLatestPB workspaceSetting) => HomeState(
        isLoading: false,
        workspaceSetting: workspaceSetting,
      );
}
