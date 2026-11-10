import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/settings/show_settings.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/first_run_sync_options.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/widgets.dart';
import 'package:appflowy/user/presentation/widgets/widgets.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

class DesktopSignInScreen extends StatefulWidget {
  const DesktopSignInScreen({
    super.key,
  });

  @override
  State<DesktopSignInScreen> createState() => _DesktopSignInScreenState();
}

class _DesktopSignInScreenState extends State<DesktopSignInScreen>
    with WindowListener {
  @override
  Widget build(BuildContext context) {
    // A computer pointed at a self-hosted AppFlowy server signs in to it.
    // Everywhere else the first screen asks where the workspace should live.
    final selfHosted = isAuthEnabled &&
        currentCloudType() == AuthenticatorType.appflowyCloudSelfHost;

    return BlocBuilder<SignInBloc, SignInState>(
      builder: (context, state) {
        final bottomPadding = UniversalPlatform.isDesktop ? 20.0 : 24.0;
        return Scaffold(
          appBar: _buildAppBar(),
          body: Center(
            child: selfHosted
                ? _serverSignIn(context, bottomPadding)
                : _welcome(context, bottomPadding),
          ),
        );
      },
    );
  }

  Widget _welcome(BuildContext context, double bottomPadding) {
    final theme = AppFlowyTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              VSpace(theme.spacing.xxl),
              FlowyLogoTitle(
                title: LocaleKeys.welcomeText.tr(),
                logoSize: const Size.square(36),
              ),
              VSpace(theme.spacing.xxl),
              const FirstRunSyncOptions(),
              VSpace(theme.spacing.xxl),
              const DesktopSignInSettingsButton(),
              VSpace(bottomPadding),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serverSignIn(BuildContext context, double bottomPadding) {
    final theme = AppFlowyTheme.of(context);
    final server = Uri.tryParse(
          getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url,
        )?.host ??
        '';
    return AuthFormContainer(
      children: [
        const Spacer(),
        FlowyLogoTitle(
          title: server.isEmpty
              ? LocaleKeys.welcomeText.tr()
              : LocaleKeys.firstRun_signInTo.tr(args: [server]),
          logoSize: const Size.square(36),
        ),
        VSpace(theme.spacing.xxl),
        const ContinueWithEmailAndPassword(),
        VSpace(theme.spacing.l),
        const SignUpPrompt(),
        VSpace(theme.spacing.xxl),
        // Whatever the server itself offers to sign in with.
        const _OrDivider(),
        VSpace(theme.spacing.xxl),
        const ThirdPartySignInButtons(),
        VSpace(theme.spacing.xxl),
        const SignInAgreement(),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DesktopSignInSettingsButton(),
            const HSpace(20),
            AFGhostTextButton(
              text: LocaleKeys.firstRun_anotherWay.tr(),
              size: AFButtonSize.s,
              onTap: () => chooseAnotherWayToStart(),
            ),
            const HSpace(20),
            const SignInAnonymousButtonV2(),
          ],
        ),
        VSpace(bottomPadding),
      ],
    );
  }

  PreferredSize _buildAppBar() {
    return PreferredSize(
      preferredSize: Size.fromHeight(UniversalPlatform.isWindows ? 40 : 60),
      child: UniversalPlatform.isWindows
          ? const WindowTitleBar()
          : const MoveWindowDetector(),
    );
  }

  @override
  void onWindowFocus() {
    // https://pub.dev/packages/window_manager#windows
    // must call setState once when the window is focused
    setState(() {});
  }
}

class DesktopSignInSettingsButton extends StatelessWidget {
  const DesktopSignInSettingsButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
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
      onTap: () => showSimpleSettingsDialog(context),
      iconBuilder: (context, isHovering, disabled) {
        return FlowySvg(
          FlowySvgs.settings_s,
          size: Size.square(20),
          color: theme.textColorScheme.secondary,
        );
      },
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Row(
      children: [
        Flexible(
          child: AFDivider(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            LocaleKeys.signIn_or.tr(),
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
        Flexible(
          child: AFDivider(),
        ),
      ],
    );
  }
}
