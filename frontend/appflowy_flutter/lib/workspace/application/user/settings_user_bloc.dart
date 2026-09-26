import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_user_bloc.freezed.dart';

class SettingsUserViewBloc extends Bloc<SettingsUserEvent, SettingsUserState> {
  SettingsUserViewBloc(
    this.userProfile, {
    UserListener? userListener,
    UserBackendService? userService,
    Future<FlowyResult<UserProfilePB, FlowyError>> Function()? loadUserProfile,
  })  : _userListener = userListener ?? UserListener(userProfile: userProfile),
        _userService =
            userService ?? UserBackendService(userId: userProfile.id),
        _loadProfile =
            loadUserProfile ?? UserBackendService.getCurrentUserProfile,
        super(SettingsUserState.initial(userProfile)) {
    _dispatch();
  }

  final UserBackendService _userService;
  final UserListener _userListener;
  final UserProfilePB userProfile;
  final Future<FlowyResult<UserProfilePB, FlowyError>> Function() _loadProfile;
  bool _started = false;
  bool _closing = false;
  int _profileRevision = 0;

  Future<FlowyResult<void, FlowyError>> saveUserIcon(String iconUrl) {
    if (_closing || isClosed) {
      return Future.error(StateError('The profile is no longer active'));
    }
    return _userService.updateUserProfile(iconUrl: iconUrl);
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _userListener.stop();
    return super.close();
  }

  void _dispatch() {
    on<SettingsUserEvent>(
      (event, emit) async {
        await event.when(
          initial: () async {
            if (_started || _closing) return;
            _started = true;
            _userListener.start(onProfileUpdated: _profileUpdated);
            await _loadUserProfile();
          },
          didReceiveUserProfile: (UserProfilePB newUserProfile) {
            if (_closing || newUserProfile.id != userProfile.id) return;
            _profileRevision++;
            emit(state.copyWith(userProfile: newUserProfile));
          },
          updateUserName: (String name) {
            _userService.updateUserProfile(name: name).then((result) {
              result.fold(
                (l) => null,
                (err) => Log.error(err),
              );
            });
          },
          updateUserIcon: (String iconUrl) {
            saveUserIcon(iconUrl).then((result) {
              result.fold(
                (l) => null,
                (err) => Log.error(err),
              );
            });
          },
          updateUserEmail: (String email) {
            _userService.updateUserProfile(email: email).then((result) {
              result.fold(
                (l) => null,
                (err) => Log.error(err),
              );
            });
          },
          updateUserPassword: (String oldPassword, String newPassword) {
            _userService
                .updateUserProfile(password: newPassword)
                .then((result) {
              result.fold(
                (l) => null,
                (err) => Log.error(err),
              );
            });
          },
          removeUserIcon: () {
            // Empty Icon URL = No icon
            saveUserIcon('').then((result) {
              result.fold(
                (l) => null,
                (err) => Log.error(err),
              );
            });
          },
        );
      },
    );
  }

  Future<void> _loadUserProfile() async {
    final revision = _profileRevision;
    final result = await _loadProfile();
    if (_closing || isClosed || revision != _profileRevision) return;
    _profileUpdated(result);
  }

  void _profileUpdated(
    FlowyResult<UserProfilePB, FlowyError> userProfileOrFailed,
  ) {
    if (_closing || isClosed) return;
    userProfileOrFailed.fold(
      (profile) {
        if (profile.id != userProfile.id) return;
        _profileRevision++;
        add(SettingsUserEvent.didReceiveUserProfile(profile));
      },
      (err) => Log.error(err),
    );
  }
}

@freezed
class SettingsUserEvent with _$SettingsUserEvent {
  const factory SettingsUserEvent.initial() = _Initial;
  const factory SettingsUserEvent.updateUserName({
    required String name,
  }) = _UpdateUserName;
  const factory SettingsUserEvent.updateUserEmail({
    required String email,
  }) = _UpdateEmail;
  const factory SettingsUserEvent.updateUserIcon({
    required String iconUrl,
  }) = _UpdateUserIcon;
  const factory SettingsUserEvent.updateUserPassword({
    required String oldPassword,
    required String newPassword,
  }) = _UpdateUserPassword;
  const factory SettingsUserEvent.removeUserIcon() = _RemoveUserIcon;
  const factory SettingsUserEvent.didReceiveUserProfile(
    UserProfilePB newUserProfile,
  ) = _DidReceiveUserProfile;
}

@freezed
class SettingsUserState with _$SettingsUserState {
  const factory SettingsUserState({
    required UserProfilePB userProfile,
    required FlowyResult<void, String> successOrFailure,
  }) = _SettingsUserState;

  factory SettingsUserState.initial(UserProfilePB userProfile) =>
      SettingsUserState(
        userProfile: userProfile,
        successOrFailure: FlowyResult.success(null),
      );
}
