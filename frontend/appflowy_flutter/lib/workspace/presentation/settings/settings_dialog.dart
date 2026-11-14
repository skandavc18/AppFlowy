import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/appflowy_cache_manager.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/share_log_files.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/pages/setting_ai_view/settings_ai_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_account_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_billing_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_manage_data_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_connections_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_editor_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_maps_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_page_versions_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_office_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_plan_view.dart';
import 'package:appflowy/extensions/presentation/settings_extensions_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_shortcuts_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_workspace_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/sites/settings_sites_view.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_header.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_workspace_layout.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/feature_flags/feature_flag_page.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_page.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_notifications_view.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'pages/setting_ai_view/local_settings_ai_view.dart';

class SettingsDialog extends StatelessWidget {
  SettingsDialog(
    this.user, {
    required this.dismissDialog,
    required this.didLogout,
    required this.restartApp,
    this.initPage,
  }) : super(key: ValueKey(user.id));

  final UserProfilePB user;
  final SettingsPage? initPage;
  final VoidCallback dismissDialog;
  final VoidCallback didLogout;
  final VoidCallback restartApp;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = EdgeInsets.all(media.size.shortestSide < 600 ? 16 : 32);
    final width =
        (media.size.width - media.viewInsets.horizontal - inset.horizontal)
            .clamp(0.0, 1120.0)
            .toDouble();
    final height =
        (media.size.height - media.viewInsets.vertical - inset.vertical)
            .clamp(0.0, 820.0)
            .toDouble();
    final palette = WorkspacePalette.of(context);
    final currentWorkspaceMemberRole =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.role;
    return BlocProvider<SettingsDialogBloc>(
      create: (context) => SettingsDialogBloc(
        user,
        currentWorkspaceMemberRole,
        initPage: initPage,
      )..add(const SettingsDialogEvent.initial()),
      child: BlocBuilder<SettingsDialogBloc, SettingsDialogState>(
        builder: (context, state) => FlowyDialog(
          width: width,
          expandHeight: false,
          constraints: BoxConstraints.tightFor(height: height),
          insetPadding: inset,
          padding: EdgeInsets.zero,
          backgroundColor: palette.elevatedSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkspaceTokens.dialogRadius),
          ),
          child: ScaffoldMessenger(
            child: Scaffold(
              backgroundColor: palette.elevatedSurface,
              body: SettingsWorkspaceLayout(
                onClose: dismissDialog,
                navigation: SettingsMenu(
                  userProfile: state.userProfile,
                  changeSelectedPage: (SettingsPage page) => context
                      .read<SettingsDialogBloc>()
                      .add(SettingsDialogEvent.setSelectedPage(page)),
                  currentPage: state.page,
                  currentUserRole: currentWorkspaceMemberRole,
                  isBillingEnabled: state.isBillingEnabled,
                ),
                navigationPicker: SettingsMenu(
                  compact: true,
                  userProfile: state.userProfile,
                  changeSelectedPage: (SettingsPage page) => context
                      .read<SettingsDialogBloc>()
                      .add(SettingsDialogEvent.setSelectedPage(page)),
                  currentPage: state.page,
                  currentUserRole: currentWorkspaceMemberRole,
                  isBillingEnabled: state.isBillingEnabled,
                ),
                child: BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
                  builder: (context, workspaceState) => getSettingsView(
                    workspaceState.currentWorkspace!,
                    state.page,
                    workspaceState.userProfile,
                    workspaceState.currentWorkspace?.role,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget getSettingsView(
    UserWorkspacePB workspace,
    SettingsPage page,
    UserProfilePB user,
    AFRolePB? currentWorkspaceMemberRole,
  ) =>
      buildSettingsPageView(
        page: page,
        workspace: workspace,
        user: user,
        currentWorkspaceMemberRole: currentWorkspaceMemberRole,
        didLogout: didLogout,
        didLogin: dismissDialog,
        restartApp: restartApp,
      );
}

/// The content of one settings page. The desktop dialog and the mobile
/// settings screens both host exactly this widget for [page].
Widget buildSettingsPageView({
  required SettingsPage page,
  required UserWorkspacePB workspace,
  required UserProfilePB user,
  required AFRolePB? currentWorkspaceMemberRole,
  required VoidCallback didLogout,
  required VoidCallback didLogin,
  required VoidCallback restartApp,
}) {
  switch (normalizeSettingsPage(page)) {
    case SettingsPage.account:
    case SettingsPage.cloud:
    case SettingsPage.encryption:
    case SettingsPage.backup:
      return SettingsAccountView(
        userProfile: user,
        didLogout: didLogout,
        didLogin: didLogin,
        restartApp: restartApp,
      );
    case SettingsPage.workspace:
      return SettingsWorkspaceView(
        userProfile: user,
        currentWorkspaceMemberRole: currentWorkspaceMemberRole,
      );
    case SettingsPage.manageData:
      return SettingsManageDataView(
        userProfile: user,
        workspace: workspace,
      );
    case SettingsPage.notifications:
      return const SettingsNotificationsView();
    case SettingsPage.documentEditing:
      return SettingsOfficeView(userProfile: user);
    case SettingsPage.editor:
      return const SettingsEditorView();
    case SettingsPage.pageVersions:
      return const SettingsPageVersionsView();
    case SettingsPage.maps:
      return const SettingsMapsView();
    case SettingsPage.connections:
      return const SettingsConnectionsView();
    case SettingsPage.extensions:
      return const SettingsExtensionsView();
    case SettingsPage.shortcuts:
      return const SettingsShortcutsView();
    case SettingsPage.ai:
      if (user.workspaceType == WorkspaceTypePB.ServerW) {
        return SettingsAIView(
          key: ValueKey(workspace.workspaceId),
          userProfile: user,
          currentWorkspaceMemberRole: currentWorkspaceMemberRole,
          workspaceId: workspace.workspaceId,
        );
      } else {
        return LocalSettingsAIView(
          key: ValueKey(workspace.workspaceId),
          userProfile: user,
          workspaceId: workspace.workspaceId,
        );
      }
    case SettingsPage.member:
      return WorkspaceMembersPage(
        userProfile: user,
        workspaceId: workspace.workspaceId,
      );
    case SettingsPage.plan:
      return SettingsPlanView(
        workspaceId: workspace.workspaceId,
        user: user,
      );
    case SettingsPage.billing:
      return SettingsBillingView(
        workspaceId: workspace.workspaceId,
        user: user,
      );
    case SettingsPage.sites:
      return SettingsSitesPage(
        workspaceId: workspace.workspaceId,
        user: user,
      );
    case SettingsPage.featureFlags:
      return const FeatureFlagsPage();
  }
}

class SimpleSettingsDialog extends StatefulWidget {
  const SimpleSettingsDialog({super.key});

  @override
  State<SimpleSettingsDialog> createState() => _SimpleSettingsDialogState();
}

class _SimpleSettingsDialogState extends State<SimpleSettingsDialog> {
  SettingsPage page = SettingsPage.cloud;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppearanceSettingsCubit>().state;

    return FlowyDialog(
      width: 784,
      constraints: const BoxConstraints(maxWidth: 784),
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header
              SettingsHeader(
                title: LocaleKeys.signIn_settings.tr(),
              ),
              const VSpace(WorkspaceTokens.space8),

              // language
              _LanguageSettings(key: ValueKey('language${settings.hashCode}')),
              const VSpace(22.0),

              // support
              _SupportSettings(key: ValueKey('support${settings.hashCode}')),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageSettings extends StatelessWidget {
  const _LanguageSettings({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCategory(
      title: LocaleKeys.settings_workspacePage_language_title.tr(),
      children: const [LanguageDropdown()],
    );
  }
}

class _SupportSettings extends StatelessWidget {
  const _SupportSettings({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCategory(
      title: LocaleKeys.settings_mobile_support.tr(),
      children: [
        // export logs
        Row(
          children: [
            Expanded(
              child: FlowyText(
                LocaleKeys.workspace_errorActions_exportLogFiles.tr(),
                maxLines: null,
              ),
            ),
            const HSpace(WorkspaceTokens.space3),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 78),
              child: OutlinedRoundedButton(
                text: LocaleKeys.settings_files_export.tr(),
                onTap: () {
                  shareLogFiles(context);
                },
              ),
            ),
          ],
        ),
        // clear cache
        Row(
          children: [
            Expanded(
              child: FlowyText(
                LocaleKeys.settings_files_clearCache.tr(),
                maxLines: null,
              ),
            ),
            const HSpace(WorkspaceTokens.space3),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 78),
              child: OutlinedRoundedButton(
                text: LocaleKeys.button_clear.tr(),
                onTap: () async {
                  await getIt<FlowyCacheManager>().clearAllCache();
                  if (context.mounted) {
                    showToastNotification(
                      message: LocaleKeys
                          .settings_manageDataPage_cache_dialog_successHint
                          .tr(),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
