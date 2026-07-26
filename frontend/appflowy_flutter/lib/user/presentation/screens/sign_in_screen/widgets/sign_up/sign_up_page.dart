import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/auth/sign_up_http_service.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/back_to_login_in_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_button.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/title_logo.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/verifying_button.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/password/password_suffix_icon.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:string_validator/string_validator.dart';

/// Creates a new account.
///
/// * With AppFlowy Cloud (hosted or self-hosted) the account is created on the
///   GoTrue service. When the deployment auto-confirms new emails the user is
///   signed in right away, otherwise a confirmation notice is shown.
/// * In local mode the account is created on this device only, so a display
///   name is requested as well.
class SignUpPage extends StatefulWidget {
  const SignUpPage({
    super.key,
    required this.backToLogin,
    this.initialEmail,
  });

  final VoidCallback backToLogin;
  final String? initialEmail;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final nameKey = GlobalKey<AFTextFieldState>();
  final emailKey = GlobalKey<AFTextFieldState>();
  final passwordKey = GlobalKey<AFTextFieldState>();
  final confirmPasswordKey = GlobalKey<AFTextFieldState>();

  late final TextEditingController nameController = TextEditingController();
  late final TextEditingController emailController =
      TextEditingController(text: widget.initialEmail ?? '');
  late final TextEditingController passwordController =
      TextEditingController();
  late final TextEditingController confirmPasswordController =
      TextEditingController();

  bool get isLocalMode => isLocalAuthEnabled;

  bool isSubmitting = false;
  String? confirmationEmail;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: theme.spacing.xxl),
          child: SizedBox(
            width: 320,
            child: BlocListener<SignInBloc, SignInState>(
              listener: _onSignInStateChanged,
              child: confirmationEmail != null
                  ? _buildEmailConfirmation(context)
                  : _buildForm(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailConfirmation(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TitleLogo(
          title: LocaleKeys.signUp_emailConfirmationTitle.tr(),
          description: LocaleKeys.signUp_emailConfirmationDescription.tr(),
          informationBuilder: (context) {
            final theme = AppFlowyTheme.of(context);
            return Text(
              confirmationEmail ?? '',
              style: theme.textStyle.body.enhanced(
                color: theme.textColorScheme.primary,
              ),
            );
          },
        ),
        BackToLoginButton(onTap: widget.backToLogin),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final iconSize = 20.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TitleLogo(
          title: isLocalMode
              ? LocaleKeys.signUp_createLocalAccountTitle.tr()
              : LocaleKeys.signUp_createAccountTitle.tr(),
          description: isLocalMode
              ? LocaleKeys.signUp_createLocalAccountDescription.tr()
              : LocaleKeys.signUp_createAccountDescription.tr(),
        ),

        if (isLocalMode) ...[
          AFTextField(
            key: nameKey,
            controller: nameController,
            hintText: LocaleKeys.signUp_nameHint.tr(),
            autoFocus: true,
          ),
          VSpace(theme.spacing.l),
        ],

        AFTextField(
          key: emailKey,
          controller: emailController,
          hintText: LocaleKeys.signUp_emailHint.tr(),
          keyboardType: TextInputType.emailAddress,
          autoFocus: !isLocalMode,
          autofillHints: const [AutofillHints.email],
        ),
        VSpace(theme.spacing.l),

        AFTextField(
          key: passwordKey,
          controller: passwordController,
          hintText: LocaleKeys.signUp_passwordHint.tr(),
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          suffixIconConstraints: BoxConstraints.tightFor(
            width: iconSize + theme.spacing.m,
            height: iconSize,
          ),
          suffixIconBuilder: (context, isObscured) => PasswordSuffixIcon(
            isObscured: isObscured,
            onTap: () => passwordKey.currentState?.syncObscured(!isObscured),
          ),
        ),
        VSpace(theme.spacing.l),

        AFTextField(
          key: confirmPasswordKey,
          controller: confirmPasswordController,
          hintText: LocaleKeys.signUp_repeatPasswordHint.tr(),
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          suffixIconConstraints: BoxConstraints.tightFor(
            width: iconSize + theme.spacing.m,
            height: iconSize,
          ),
          suffixIconBuilder: (context, isObscured) => PasswordSuffixIcon(
            isObscured: isObscured,
            onTap: () =>
                confirmPasswordKey.currentState?.syncObscured(!isObscured),
          ),
          onSubmitted: (_) => _submit(),
        ),
        VSpace(theme.spacing.xxl),

        isSubmitting
            ? const VerifyingButton()
            : ContinueWithButton(
                text: LocaleKeys.signUp_buttonText.tr(),
                onTap: _submit,
              ),
        VSpace(theme.spacing.l),

        BackToLoginButton(onTap: widget.backToLogin),
      ],
    );
  }

  void _onSignInStateChanged(BuildContext context, SignInState state) {
    // The sign in that follows a successful cloud sign up reports its progress
    // and its failures through the sign in bloc.
    if (isSubmitting != state.isSubmitting && mounted) {
      setState(() => isSubmitting = state.isSubmitting);
    }

    state.successOrFail?.onFailure((error) {
      passwordKey.currentState?.syncError(errorText: error.msg);
    });
  }

  bool _validate() {
    _clearErrors();

    if (isLocalMode && nameController.text.trim().isEmpty) {
      nameKey.currentState?.syncError(
        errorText: LocaleKeys.signUp_emptyNameError.tr(),
      );
      return false;
    }

    if (!isEmail(emailController.text)) {
      emailKey.currentState?.syncError(
        errorText: LocaleKeys.signIn_invalidEmail.tr(),
      );
      return false;
    }

    if (passwordController.text.isEmpty) {
      passwordKey.currentState?.syncError(
        errorText: LocaleKeys.signUp_emptyPasswordError.tr(),
      );
      return false;
    }

    if (confirmPasswordController.text.isEmpty) {
      confirmPasswordKey.currentState?.syncError(
        errorText: LocaleKeys.signUp_repeatPasswordEmptyError.tr(),
      );
      return false;
    }

    if (passwordController.text != confirmPasswordController.text) {
      confirmPasswordKey.currentState?.syncError(
        errorText: LocaleKeys.signUp_unmatchedPasswordError.tr(),
      );
      return false;
    }

    return true;
  }

  void _clearErrors() {
    nameKey.currentState?.clearError();
    emailKey.currentState?.clearError();
    passwordKey.currentState?.clearError();
    confirmPasswordKey.currentState?.clearError();
  }

  Future<void> _submit() async {
    if (isSubmitting || !_validate()) {
      return;
    }

    setState(() => isSubmitting = true);

    if (isLocalMode) {
      await _signUpLocally();
    } else {
      await _signUpWithCloud();
    }
  }

  Future<void> _signUpLocally() async {
    final result = await getIt<AuthService>().signUp(
      name: nameController.text.trim(),
      email: emailController.text.trim(),
      password: passwordController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() => isSubmitting = false);

    result.fold(
      (userProfile) => getIt<AuthRouter>().goHomeScreen(context, userProfile),
      (error) => emailKey.currentState?.syncError(errorText: error.msg),
    );
  }

  Future<void> _signUpWithCloud() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final baseUrl = await getAppFlowyCloudUrl();

    final result = await SignUpHttpService(baseUrl: baseUrl)
        .signUpWithEmailAndPassword(email: email, password: password);

    if (!mounted) {
      return;
    }

    result.fold(
      (signUp) {
        if (!signUp.hasSession) {
          setState(() {
            isSubmitting = false;
            confirmationEmail = email;
          });
          return;
        }

        // The deployment auto-confirms new emails, so the account can be used
        // straight away. Reuse the regular sign in path so the session, the
        // workspace and the navigation are all set up the usual way.
        context.read<SignInBloc>().add(
              SignInEvent.signInWithEmailAndPassword(
                email: email,
                password: password,
              ),
            );
      },
      (error) {
        setState(() => isSubmitting = false);
        passwordKey.currentState?.syncError(errorText: error.msg);
      },
    );
  }
}
