import 'package:appflowy/features/workspace/data/repositories/rust_workspace_repository_impl.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/app_bar.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_mobile_state_container.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/password/password_bloc.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/settings_catalogue.dart';
import 'package:appflowy/workspace/presentation/settings/settings_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_header.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// One settings page, full screen on mobile.
///
/// It hosts the same widget as the desktop settings dialog, so every setting
/// available on desktop is available, and stays in step, on mobile.
class MobileSettingsPageScreen extends StatelessWidget {
  const MobileSettingsPageScreen({super.key, required this.page});

  static const routeName = '/settings/page';
  static const pageArgument = 'page';

  static String location(SettingsPage page) => Uri(
        path: routeName,
        queryParameters: {pageArgument: page.name},
      ).toString();

  static SettingsPage? pageFromName(String? name) =>
      SettingsPage.values.where((page) => page.name == name).firstOrNull;

  final SettingsPage page;

  @override
  Widget build(BuildContext context) {
    final title = settingsCatalogueEntry(page).label;
    return FutureBuilder(
      future: getIt<AuthService>().getUser(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _MobileSettingsPageScaffold(
            title: title,
            body: const Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        String? errorMessage;
        final userProfile = snapshot.data!.fold(
          (userProfile) => userProfile,
          (error) {
            errorMessage = error.msg;
            return null;
          },
        );
        if (userProfile == null) {
          return _MobileSettingsPageScaffold(
            title: title,
            body: FlowyMobileStateContainer.error(
              emoji: '🛸',
              title: LocaleKeys.settings_mobile_userprofileError.tr(),
              description:
                  LocaleKeys.settings_mobile_userprofileErrorDescription.tr(),
              errorMsg: errorMessage,
            ),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => UserWorkspaceBloc(
                userProfile: userProfile,
                repository: RustWorkspaceRepositoryImpl(
                  userId: userProfile.id,
                ),
              )..add(UserWorkspaceEvent.initialize()),
            ),
            BlocProvider(
              create: (_) => PasswordBloc(userProfile)
                ..add(PasswordEvent.init())
                ..add(PasswordEvent.checkHasPassword()),
            ),
          ],
          child: BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
            builder: (context, state) {
              final workspace = state.currentWorkspace;
              return _MobileSettingsPageScaffold(
                title: title,
                body: workspace == null
                    ? const Center(
                        child: CircularProgressIndicator.adaptive(),
                      )
                    : SettingsHeaderScope(
                        showTitle: false,
                        child: buildSettingsPageView(
                          page: page,
                          workspace: workspace,
                          user: state.userProfile,
                          currentWorkspaceMemberRole: workspace.role,
                          didLogout: () => runAppFlowy(),
                          didLogin: () {
                            if (context.canPop()) context.pop();
                          },
                          restartApp: () => runAppFlowy(),
                        ),
                      ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MobileSettingsPageScaffold extends StatelessWidget {
  const _MobileSettingsPageScaffold({required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    // Matches the desktop settings surface, including paper mode's warm tint.
    final surface = WorkspacePalette.of(context).elevatedSurface;
    return Scaffold(
      backgroundColor: surface,
      appBar: FlowyAppBar(titleText: title, backgroundColor: surface),
      body: SafeArea(top: false, child: body),
    );
  }
}
