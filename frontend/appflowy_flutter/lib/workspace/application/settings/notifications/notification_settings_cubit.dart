import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_settings_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_settings_cubit.freezed.dart';

class NotificationSettingsCubit extends Cubit<NotificationSettingsState> {
  NotificationSettingsCubit() : super(NotificationSettingsState.initial()) {
    _initialize();
  }

  final Completer<void> _initCompleter = Completer();

  late final NotificationSettingsPB _notificationSettings;

  Future<void> _initialize() async {
    _notificationSettings =
        await UserSettingsBackendService().getNotificationSettings();

    final showNotificationSetting = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.showNotificationIcon, (v) => bool.parse(v));

    emit(
      state.copyWith(
        isNotificationsEnabled: _notificationSettings.notificationsEnabled,
        isShowNotificationsIconEnabled: showNotificationSetting ?? true,
      ),
    );

    _initCompleter.complete();
  }

  Future<void> toggleNotificationsEnabled() async {
    await _initCompleter.future;

    _notificationSettings.notificationsEnabled = !state.isNotificationsEnabled;

    emit(
      state.copyWith(
        isNotificationsEnabled: _notificationSettings.notificationsEnabled,
      ),
    );

    await _saveNotificationSettings();
  }

  Future<void> toggleShowNotificationIconEnabled() async {
    await _initCompleter.future;

    emit(
      state.copyWith(
        isShowNotificationsIconEnabled: !state.isShowNotificationsIconEnabled,
      ),
    );
  }

  /// Takes notification settings that arrived from another computer.
  Future<void> adoptSynced(NotificationSettingsPB settings) async {
    await _initCompleter.future;
    _notificationSettings.notificationsEnabled = settings.notificationsEnabled;
    final result = await UserSettingsBackendService()
        .setNotificationSettings(_notificationSettings);
    result.fold((_) => null, (error) => Log.error(error));
    if (!isClosed) {
      emit(
        state.copyWith(isNotificationsEnabled: settings.notificationsEnabled),
      );
    }
  }

  /// Reads again whether the notification icon shows, after the setting
  /// arrived from another computer.
  Future<void> reloadShowNotificationIcon() async {
    await _initCompleter.future;
    final show = await getIt<KeyValueStorage>()
        .getWithFormat(KVKeys.showNotificationIcon, (v) => bool.parse(v));
    if (!isClosed) {
      emit(state.copyWith(isShowNotificationsIconEnabled: show ?? true));
    }
  }

  Future<void> _saveNotificationSettings() async {
    await _initCompleter.future;

    await getIt<KeyValueStorage>().set(
      KVKeys.showNotificationIcon,
      state.isShowNotificationsIconEnabled.toString(),
    );

    final result = await UserSettingsBackendService()
        .setNotificationSettings(_notificationSettings);
    result.fold(
      (r) => null,
      (error) => Log.error(error),
    );
  }
}

@freezed
class NotificationSettingsState with _$NotificationSettingsState {
  const NotificationSettingsState._();

  const factory NotificationSettingsState({
    required bool isNotificationsEnabled,
    required bool isShowNotificationsIconEnabled,
  }) = _NotificationSettingsState;

  factory NotificationSettingsState.initial() =>
      const NotificationSettingsState(
        isNotificationsEnabled: true,
        isShowNotificationsIconEnabled: true,
      );
}
