import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart'
    show WorkspaceLatestPB;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_bloc.freezed.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc(
    WorkspaceLatestPB workspaceSetting, {
    FolderListener? workspaceListener,
  })  : _workspaceListener = workspaceListener ??
            FolderListener(
              workspaceId: workspaceSetting.workspaceId,
            ),
        super(HomeState.initial(workspaceSetting)) {
    _dispatch();
  }

  final FolderListener _workspaceListener;
  bool _started = false;
  bool _closing = false;

  @override
  Future<void> close() async {
    _closing = true;
    await _workspaceListener.stop();
    return super.close();
  }

  void _dispatch() {
    on<HomeEvent>(
      (event, emit) async {
        await event.map(
          initial: (_Initial value) {
            if (_started || _closing) return;
            _started = true;
            _workspaceListener.start(
              onLatestUpdated: (result) {
                if (_closing || isClosed) return;
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
          ) {
            if (_closing ||
                value.setting.workspaceId !=
                    state.workspaceSetting.workspaceId) {
              return;
            }
            // Latest is shared workspace metadata, not a navigation request.
            // Never restore it (or repair/erase it) during startup. A delayed
            // notification must not open a crash tab or switch the user's space.
            emit(state.copyWith(workspaceSetting: value.setting));
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
