// Starts and stops sync with the workspace that is on screen.

import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/tasks/app_window_size_manager.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/user/application/user_settings_service.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/settings/notifications/notification_settings_cubit.dart';
import 'package:appflowy/workspace/application/sync/app_synced_preferences.dart';
import 'package:appflowy/workspace/application/sync/synced_automation_files.dart';
import 'package:appflowy/workflows/application/workflow_manager.dart';
import 'package:appflowy/extensions/application/extension_manager.dart';
import 'package:appflowy/workspace/application/sync/server_settings_sync.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/view/local_page_store.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_dialogs.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/sync_dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WorkspaceSyncHost extends StatefulWidget {
  const WorkspaceSyncHost({
    super.key,
    required this.userProfile,
    required this.workspaceId,
    required this.child,
  });

  final UserProfilePB userProfile;
  final String workspaceId;
  final Widget child;

  @override
  State<WorkspaceSyncHost> createState() => _WorkspaceSyncHostState();
}

class _WorkspaceSyncHostState extends State<WorkspaceSyncHost> {
  WorkspaceSyncEngine get _engine => WorkspaceSyncEngine.instance;

  String? _attachedTo;

  @override
  void initState() {
    super.initState();
    BackupService.instance.userProfile = widget.userProfile;
    _engine.configure(
      dataPath: () => getIt<ApplicationDataStorage>().getPath(),
      restart: () async {
        _engine.detach();
        await runAppFlowy();
      },
      safetyCopy: (reason) => BackupService.instance.takeSafetyCopy(
        reason: reason == 'join'
            ? BackupReason.beforeJoin
            : BackupReason.beforeRestore,
      ),
      preferences: AppSyncedPreferences(
        dataPath: () => getIt<ApplicationDataStorage>().getPath(),
        workspaceId: () => WorkspaceSyncEngine.instance.binding?.workspaceId,
        writeAppearance: _writeAppearance,
        writeDateTime: _writeDateTime,
        writeNotifications: _writeNotifications,
        onApplied: _onSettingsArrived,
      ),
      onFilesApplied: _onFilesArrived,
    );
    _engine.notify = (message, {bool isError = false}) {
      showToastNotification(
        message: message,
        type: isError ? ToastificationType.error : ToastificationType.success,
      );
    };
    _engine.onRestoredElsewhere = (restored) {
      final context = AppGlobals.rootNavKey.currentContext ?? this.context;
      if (context.mounted) {
        unawaited(showRestoredElsewhereDialog(context, restored));
      }
    };
    _engine.addListener(_onEngineChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  // Asked once per run each: the folder's password when the folder locks,
  // and sealing it again when a change of password here could not reach it.
  static bool _askedForFolderPassword = false;
  static bool _triedResealing = false;

  void _onEngineChanged() {
    if (_engine.isSuspended) return;
    final phase = _engine.phase;
    if (phase == SyncPhase.locked &&
        !_askedForFolderPassword &&
        !FlowyRunner.currentMode.isTest) {
      _askedForFolderPassword = true;
      final context = AppGlobals.rootNavKey.currentContext ?? this.context;
      if (context.mounted) {
        unawaited(
          askAppPassword(
            context,
            question: _engine.passwordChangedElsewhere
                ? AppPasswordQuestion.changedElsewhere
                : AppPasswordQuestion.typeForFolder,
            check: (password) async {
              try {
                await _engine.unlock(password);
                return null;
              } on Object catch (error) {
                return describeSyncError(error);
              }
            },
          ),
        );
      }
    }
    if (phase == SyncPhase.idle &&
        _engine.needsResealing &&
        !_engine.isBusy &&
        !_triedResealing) {
      _triedResealing = true;
      unawaited(
        _engine.sealWithAppPassword().catchError(
              (Object error) => Log.warn(
                'The sync folder was not sealed again yet: $error',
              ),
            ),
      );
    }
  }

  // Settings that arrive from another computer go through whatever shows them,
  // so it is not left holding an old copy to save over them later. Once this
  // host is gone they go straight to the backend.

  Future<void> _writeAppearance(AppearanceSettingsPB settings) async {
    if (!mounted) {
      await const UserSettingsBackendService().setAppearanceSetting(settings);
      return;
    }
    await context
        .read<AppearanceSettingsCubit>()
        .adoptSyncedAppearance(context, settings);
  }

  Future<void> _writeDateTime(DateTimeSettingsPB settings) async {
    if (!mounted) {
      await const UserSettingsBackendService().setDateTimeSettings(settings);
      return;
    }
    await context.read<AppearanceSettingsCubit>().adoptSyncedDateTime(settings);
  }

  Future<void> _writeNotifications(NotificationSettingsPB settings) async {
    if (!mounted) {
      await const UserSettingsBackendService()
          .setNotificationSettings(settings);
      return;
    }
    await context.read<NotificationSettingsCubit>().adoptSynced(settings);
  }

  /// Shows settings that arrived from another computer where something on
  /// screen holds them. The rest are read where they are used, or at the next
  /// start.
  Future<void> _onSettingsArrived(Set<String> keys) async {
    if (!mounted) {
      return;
    }
    if (keys.any((key) => key.startsWith('pref:kDocumentAppearance'))) {
      unawaited(context.read<DocumentAppearanceCubit>().fetch());
    }
    if (keys.contains(preferenceSyncKey(KVKeys.showNotificationIcon))) {
      unawaited(
        context.read<NotificationSettingsCubit>().reloadShowNotificationIcon(),
      );
    }
    if (keys.contains(preferenceSyncKey(DartExtensionHost.themeKey))) {
      unawaited(_reloadExtensionTheme());
    }
    final appearance = context.read<AppearanceSettingsCubit>();
    if (keys.contains(preferenceSyncKey(KVKeys.enableKineticScrolling))) {
      unawaited(appearance.readKineticScrolling());
    }
    if (keys.contains(preferenceSyncKey(KVKeys.textScaleFactor))) {
      unawaited(appearance.readTextScaleFactor());
    }
    if (keys.contains(preferenceSyncKey(KVKeys.scaleFactor))) {
      unawaited(
        WindowSizeManager().getScaleFactor().then(scaleApp),
      );
    }
    if (keys.contains(preferenceSyncKey(KVKeys.featureFlag))) {
      unawaited(FeatureFlag.initialize());
    }
    for (final key in keys) {
      final place = key.startsWith('pref:')
          ? LocalPageStore.idOfKey(key.substring('pref:'.length))
          : null;
      if (place != null) {
        unawaited(LocalPageStore.instance.reload(place));
      }
    }
    await _onFilesArrived({
      for (final key in keys)
        if (isAutomationFileSyncKey(key))
          key.substring(automationFileSyncPrefix.length),
    });
    if (keys.contains(preferenceSyncKey('appflowy_extensions_disabled')) ||
        keys.contains(preferenceSyncKey(DartExtensionHost.disabledKey))) {
      await ExtensionManager.instance.reloadSyncedFiles();
    }
  }

  Future<void> _onFilesArrived(Set<String> paths) async {
    if (paths.any((path) => path.startsWith('workflows/'))) {
      await WorkflowManager.instance.reloadSyncedFiles();
    }
    if (paths.any(
      (path) =>
          path.startsWith('extensions/') || path.startsWith('extension_data/'),
    )) {
      await ExtensionManager.instance.reloadSyncedFiles();
    }
  }

  Future<void> _reloadExtensionTheme() async {
    final stored =
        await getIt<KeyValueStorage>().get(DartExtensionHost.themeKey);
    ExtensionThemeRegistry.selected.value =
        stored != null && ExtensionThemeRegistry.byKey(stored) != null
            ? stored
            : '';
  }

  @override
  void didUpdateWidget(covariant WorkspaceSyncHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _attach();
    }
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _engine.detach();
    ServerSettingsSync.instance.detach();
    super.dispose();
  }

  // Asked once per run, so a computer signing in to a server where sync is
  // set up is offered its settings, accounts and keys straight away.
  static bool _askedForServerPassword = false;

  Future<void> _attachServer() async {
    final server = ServerSettingsSync.instance
      ..configure(
        preferences: AppSyncedPreferences(
          dataPath: () => getIt<ApplicationDataStorage>().getPath(),
          workspaceId: () => widget.workspaceId,
          syncAutomationFiles: true,
          writeAppearance: _writeAppearance,
          writeDateTime: _writeDateTime,
          writeNotifications: _writeNotifications,
          onApplied: _onSettingsArrived,
        ),
      );
    await server.attach(uid: widget.userProfile.id.toInt());
    final phase = server.phase;
    if (!mounted ||
        server.isSuspended ||
        _askedForServerPassword ||
        FlowyRunner.currentMode.isTest ||
        (phase != ServerSettingsPhase.locked &&
            phase != ServerSettingsPhase.notSetUp)) {
      return;
    }
    _askedForServerPassword = true;
    final context = AppGlobals.rootNavKey.currentContext ?? this.context;
    if (!context.mounted) {
      return;
    }
    if (phase == ServerSettingsPhase.locked) {
      await askAppPassword(
        context,
        question: server.passwordChangedElsewhere
            ? AppPasswordQuestion.changedElsewhere
            : AppPasswordQuestion.typeForServer,
        check: (password) async {
          try {
            await server.unlock(password);
            return null;
          } on Object catch (error) {
            return describeSyncError(error);
          }
        },
      );
      return;
    }
    // Signed in to a server for the first time on a computer with no
    // AppFlowy password: choosing one seals the settings kept there.
    final chosen = await askAppPassword(
      context,
      question: AppPasswordQuestion.choose,
      skipLabel: LocaleKeys.appPassword_skip.tr(),
      check: (password) async {
        await AppPassword.instance.choose(password);
        return null;
      },
    );
    if (chosen != null) {
      try {
        await server.setUp();
      } on Object catch (error) {
        Log.warn('The settings on the server were not set up: $error');
      }
    }
  }

  void _attach() {
    if (!mounted || _attachedTo == widget.workspaceId) {
      return;
    }
    final workspace = _workspaceOnScreen();
    if (workspace == null) {
      return;
    }
    _attachedTo = widget.workspaceId;
    final isLocal = workspace.workspaceType == WorkspaceTypePB.LocalW;
    unawaited(
      _engine.attach(
        workspaceId: widget.workspaceId,
        uid: widget.userProfile.id.toInt(),
        workspaceName: workspace.name,
        isLocalWorkspace: isLocal,
      ),
    );
    if (isLocal) {
      ServerSettingsSync.instance.detach();
    } else {
      unawaited(_attachServer());
    }
  }

  UserWorkspacePB? _workspaceOnScreen() {
    final state = context.read<UserWorkspaceBloc?>()?.state;
    if (state == null) {
      return null;
    }
    final current = state.currentWorkspace;
    if (current != null && current.workspaceId == widget.workspaceId) {
      return current;
    }
    for (final workspace in state.workspaces) {
      if (workspace.workspaceId == widget.workspaceId) {
        return workspace;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
        listenWhen: (previous, current) =>
            previous.currentWorkspace != current.currentWorkspace ||
            previous.workspaces != current.workspaces,
        listener: (_, __) => _attach(),
        child: widget.child,
      );
}
