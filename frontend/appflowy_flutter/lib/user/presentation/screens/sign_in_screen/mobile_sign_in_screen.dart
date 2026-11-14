import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/setting/launch_settings_page.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/first_run_sync_options.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/widgets.dart';
import 'package:appflowy/user/presentation/widgets/flowy_logo_title.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class MobileSignInScreen extends StatelessWidget {
  const MobileSignInScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final selfHosted = isServerChosen;

    return BlocBuilder<SignInBloc, SignInState>(
      builder: (context, state) {
        final theme = AppFlowyTheme.of(context);
        if (!selfHosted) {
          return Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: 28,
                    horizontal: 24,
                  ),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 56),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FlowyLogoTitle(title: LocaleKeys.welcomeText.tr()),
                        VSpace(theme.spacing.xxl),
                        const FirstRunSyncOptions(),
                        VSpace(theme.spacing.xxl),
                        _buildSettingsOnlyButton(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final server = Uri.tryParse(
              getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url,
            )?.host ??
            '';
        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: Padding(
            padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 40),
            child: Column(
              children: [
                const Spacer(),
                FlowyLogoTitle(
                  title: server.isEmpty
                      ? LocaleKeys.welcomeText.tr()
                      : LocaleKeys.firstRun_signInTo.tr(args: [server]),
                ),
                VSpace(theme.spacing.xxl),
                const ContinueWithEmailAndPassword(),
                VSpace(theme.spacing.l),
                const SignUpPrompt(),
                VSpace(theme.spacing.xxl),
                _buildThirdPartySignInButtons(context),
                VSpace(theme.spacing.xxl),
                const SignInAgreement(),
                const Spacer(),
                _buildSettingsButton(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsOnlyButton(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFGhostIconTextButton(
      text: LocaleKeys.signIn_settings.tr(),
      textColor: (context, isHovering, disabled) {
        return theme.textColorScheme.secondary;
      },
      size: AFButtonSize.s,
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.m,
        vertical: theme.spacing.xs,
      ),
      onTap: () => context.push(MobileLaunchSettingsPage.routeName),
      iconBuilder: (context, isHovering, disabled) {
        return FlowySvg(
          FlowySvgs.settings_s,
          size: const Size.square(20),
          color: theme.textColorScheme.secondary,
        );
      },
    );
  }

  Widget _buildThirdPartySignInButtons(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                LocaleKeys.signIn_or.tr(),
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textColorScheme.secondary,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const VSpace(16),
        // expand third-party sign in buttons on Android by default.
        // on iOS, the github and discord buttons are collapsed by default.
        ThirdPartySignInButtons(
          expanded: Platform.isAndroid,
        ),
      ],
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 4,
      children: [
        AFGhostIconTextButton(
          text: LocaleKeys.signIn_settings.tr(),
          textColor: (context, isHovering, disabled) {
            return theme.textColorScheme.secondary;
          },
          size: AFButtonSize.s,
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.m,
            vertical: theme.spacing.xs,
          ),
          onTap: () => context.push(MobileLaunchSettingsPage.routeName),
          iconBuilder: (context, isHovering, disabled) {
            return FlowySvg(
              FlowySvgs.settings_s,
              size: Size.square(20),
              color: theme.textColorScheme.secondary,
            );
          },
        ),
        AFGhostTextButton(
          text: LocaleKeys.firstRun_anotherWay.tr(),
          size: AFButtonSize.s,
          onTap: () => chooseAnotherWayToStart(),
        ),
        isLocalAuthEnabled
            ? const ChangeCloudModeButton()
            : const SignInAnonymousButtonV2(),
      ],
    );
  }
}
