import 'dart:async';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/env/env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/user/settings_user_bloc.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_section.dart';
import 'package:appflowy/workspace/presentation/settings/pages/about/app_version.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/account.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/email/email_section.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/reset_everything_section.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/appflowy_server.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/sync_section.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_backup_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_encryption_view.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsAccountView extends StatefulWidget {
  const SettingsAccountView({
    super.key,
    required this.userProfile,
    required this.didLogin,
    required this.didLogout,
    this.restartApp,
  });

  final UserProfilePB userProfile;

  // Called when the user signs in from the setting dialog
  final VoidCallback didLogin;

  // Called when the user logout in the setting dialog
  final VoidCallback didLogout;

  // Called when a cloud server switch requests restarting AppFlowy
  final VoidCallback? restartApp;

  @override
  State<SettingsAccountView> createState() => _SettingsAccountViewState();
}

class _SettingsAccountViewState extends State<SettingsAccountView> {
  late String userName = widget.userProfile.name;

  @override
  void didUpdateWidget(covariant SettingsAccountView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile.id != widget.userProfile.id) {
      userName = widget.userProfile.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final restart = widget.restartApp ?? () => unawaited(runAppFlowy());
    return BlocProvider<SettingsUserViewBloc>(
      key: ValueKey(widget.userProfile.id),
      create: (context) =>
          getIt<SettingsUserViewBloc>(param1: widget.userProfile)
            ..add(const SettingsUserEvent.initial()),
      child: BlocBuilder<SettingsUserViewBloc, SettingsUserState>(
        builder: (context, state) {
          return SettingsBody(
            title: LocaleKeys.settings_accountPage_menuLabel.tr(),
            children: [
              // 1. User profile
              SettingsCategory(
                title: LocaleKeys.newSettings_myAccount_myProfile.tr(),
                children: [
                  AccountUserProfile(
                    name: userName,
                    iconUrl: state.userProfile.iconUrl,
                    onSave: (newName) {
                      setState(() => userName = newName);
                      context
                          .read<SettingsUserViewBloc>()
                          .add(SettingsUserEvent.updateUserName(name: newName));
                    },
                  ),
                ],
              ),

              // 2. Server account sign-in / sign-out when authenticated
              if (isAuthEnabled &&
                  state.userProfile.userAuthType != AuthTypePB.Local) ...[
                SettingsCategory(
                  title: LocaleKeys.newSettings_myAccount_myAccount.tr(),
                  children: [
                    SettingsEmailSection(
                      userProfile: state.userProfile,
                    ),
                    AccountSignInOutSection(
                      userProfile: state.userProfile,
                      onAction: widget.didLogout,
                      signIn: false,
                    ),
                  ],
                ),
              ],

              // 3. Single unified AppFlowy password
              const AppPasswordSettingsSection(),

              // 4. Workspace & page encryption / lock
              const SettingsEncryptionSections(),

              // 5. Sync between computers (Google Drive, OneDrive, Box, a
              // self-hosted AppFlowy Cloud, a folder), and the AppFlowy server
              // the workspace is worked on, when it is
              SyncSettingsSection(
                serverPanel: Env.enableCustomCloud
                    ? AppFlowyServerPanel(
                        userProfile: state.userProfile,
                        restart: restart,
                      )
                    : null,
              ),

              // 6. Backups & restore
              const BackupOnlySettingsSections(),

              // 7. About AppFlowy
              SettingsCategory(
                title: LocaleKeys.newSettings_myAccount_aboutAppFlowy.tr(),
                children: const [
                  SettingsAppVersion(),
                ],
              ),

              // 8. Reset everything & start fresh (always offered, local or synced)
              ResetEverythingSection(onBeforeRestart: widget.didLogin),

              // 9. Server account deletion (only when signed into a server)
              if (widget.userProfile.userAuthType == AuthTypePB.Server)
                const AccountDeletionButton(),
            ],
          );
        },
      ),
    );
  }
}
