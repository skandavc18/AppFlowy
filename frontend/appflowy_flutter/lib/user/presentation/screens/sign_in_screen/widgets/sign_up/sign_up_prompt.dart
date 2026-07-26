import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/sign_up/sign_up_page.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens the sign up page on top of the current route.
///
/// The [SignInBloc] of [context] is handed over so the page can complete the
/// sign in once the account has been created.
Future<void> pushSignUpPage(
  BuildContext context, {
  String? initialEmail,
}) {
  final signInBloc = context.read<SignInBloc>();

  return Navigator.push(
    context,
    MaterialPageRoute(
      settings: const RouteSettings(name: '/sign-up'),
      builder: (pageContext) => BlocProvider.value(
        value: signInBloc,
        child: SignUpPage(
          initialEmail: initialEmail,
          backToLogin: () => Navigator.of(pageContext).pop(),
        ),
      ),
    ),
  );
}

/// "Don't have an account? Create account"
class SignUpPrompt extends StatelessWidget {
  const SignUpPrompt({
    super.key,
    this.onTap,
  });

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            LocaleKeys.signIn_dontHaveAnAccount.tr(),
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
        const HSpace(4),
        AFGhostTextButton(
          text: LocaleKeys.signIn_createAccount.tr(),
          size: AFButtonSize.s,
          padding: EdgeInsets.zero,
          onTap: onTap ?? () => pushSignUpPage(context),
          textColor: (context, isHovering, disabled) {
            final theme = AppFlowyTheme.of(context);
            if (isHovering) {
              return theme.textColorScheme.actionHover;
            }
            return theme.textColorScheme.action;
          },
        ),
      ],
    );
  }
}
