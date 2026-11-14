// Asking for the AppFlowy password: choosing one, typing it on a computer that
// does not know it, typing the one a sync folder or a server is sealed with,
// and changing it.

import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/encryption/encryption.dart'
    show PassphraseStrength, ratePassphrase;
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/app_password/app_password_change.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/backup_dialogs.dart'
    show PassphraseStrengthBar;
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What an AppFlowy password dialog asks for.
enum AppPasswordQuestion {
  /// A new one, typed twice, for a computer that has none.
  choose,

  /// The one set on this computer, which it does not remember.
  typeHere,

  /// The one a sync folder is sealed with: the one the other computers use.
  typeForFolder,

  /// The one the settings on a server are sealed with.
  typeForServer,

  /// The new one, after it was changed on another computer.
  changedElsewhere,
}

/// The AppFlowy password: the one this computer knows, typed here when it has
/// forgotten it, or chosen when there is none. Null when the question was put
/// away.
Future<String?> ensureAppPassword(BuildContext context) async {
  final passwords = AppPassword.instance;
  final known = await passwords.current();
  if (known != null || !context.mounted) {
    return known;
  }
  if (passwords.isSet) {
    return askAppPassword(
      context,
      question: AppPasswordQuestion.typeHere,
      check: (password) async => await passwords.unlock(password)
          ? null
          : LocaleKeys.appPassword_wrong.tr(),
    );
  }
  return askAppPassword(
    context,
    question: AppPasswordQuestion.choose,
    check: (password) async {
      await passwords.choose(password);
      return null;
    },
  );
}

/// Asks [question]. [check] says what is wrong with the password, or null
/// when it will do; the dialog stays open until then. Returns the password,
/// or null when the question was put away.
///
/// [skipLabel] offers a way past without one, where there is a way past.
Future<String?> askAppPassword(
  BuildContext context, {
  required AppPasswordQuestion question,
  required Future<String?> Function(String password) check,
  String? skipLabel,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppPasswordDialog(
        question: question,
        check: check,
        skipLabel: skipLabel,
      ),
    );

/// Sentinel returned by [AppPasswordDialog] when cloud encryption was toggled
/// off by the user.
const String _unencryptedSentinel = '__appflowy_sync_unencrypted__';

/// Resolves whether a new synced folder should be encrypted (`true`), started
/// unencrypted (`false`), or cancelled (`null`).
///
/// Encryption is ON by default. If this computer already knows the AppFlowy
/// password, `true` is returned without asking again unless [alwaysShow] is
/// set; otherwise the AppFlowy password dialog opens with an optional toggle
/// to turn cloud sync encryption off.
Future<bool?> ensureAppPasswordForNewSync(
  BuildContext context, {
  bool alwaysShow = false,
}) async {
  final passwords = AppPassword.instance;
  final known = await passwords.current();
  if (known != null && !alwaysShow) {
    return true;
  }
  if (!context.mounted) {
    return null;
  }
  if (known != null && alwaysShow) {
    return true;
  }
  final question = passwords.isSet
      ? AppPasswordQuestion.typeHere
      : AppPasswordQuestion.choose;
  final answer = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppPasswordDialog(
      question: question,
      allowUnencryptedSync: true,
      check: (password) async {
        if (passwords.isSet) {
          return await passwords.unlock(password)
              ? null
              : LocaleKeys.appPassword_wrong.tr();
        }
        await passwords.choose(password);
        return null;
      },
    ),
  );
  if (answer == null) {
    return null;
  }
  return answer != _unencryptedSentinel;
}

/// Changes the AppFlowy password, sealing everything that follows it again.
/// True when it was changed.
Future<bool> showChangeAppPasswordDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ChangeAppPasswordDialog(),
    ) ==
    true;

/// The question itself; [askAppPassword] shows it.
class AppPasswordDialog extends StatefulWidget {
  const AppPasswordDialog({
    super.key,
    required this.question,
    required this.check,
    this.skipLabel,
    this.allowUnencryptedSync = false,
  });

  final AppPasswordQuestion question;
  final Future<String?> Function(String password) check;
  final String? skipLabel;

  /// When true, shows a default-on toggle to encrypt synced cloud data,
  /// allowing the user to opt out of sync encryption if desired.
  final bool allowUnencryptedSync;

  @override
  State<AppPasswordDialog> createState() => _AppPasswordDialogState();
}

class _AppPasswordDialogState extends State<AppPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _again = TextEditingController();
  String? _error;
  bool _working = false;
  bool _encryptSync = true;

  bool get _choosing => widget.question == AppPasswordQuestion.choose;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) {
      return;
    }
    if (widget.allowUnencryptedSync && !_encryptSync) {
      Navigator.of(context).pop(_unencryptedSentinel);
      return;
    }
    final password = _password.text;
    final failure = _choosing
        ? appPasswordProblem(password, again: _again.text)
        : (password.isEmpty ? LocaleKeys.appPassword_empty.tr() : null);
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    String? problem;
    try {
      problem = await widget.check(password);
    } on Object catch (error) {
      problem = '$error';
    }
    if (!mounted) {
      return;
    }
    if (problem == null) {
      Navigator.of(context).pop(password);
      return;
    }
    setState(() {
      _working = false;
      _error = problem;
    });
  }

  String get _title => switch (widget.question) {
        AppPasswordQuestion.choose => LocaleKeys.appPassword_chooseTitle.tr(),
        AppPasswordQuestion.changedElsewhere =>
          LocaleKeys.appPassword_changedElsewhereTitle.tr(),
        _ => LocaleKeys.appPassword_typeTitle.tr(),
      };

  String get _body => switch (widget.question) {
        AppPasswordQuestion.choose => LocaleKeys.appPassword_chooseBody.tr(),
        AppPasswordQuestion.typeHere => LocaleKeys.appPassword_typeBody.tr(),
        AppPasswordQuestion.typeForFolder =>
          LocaleKeys.appPassword_folderBody.tr(),
        AppPasswordQuestion.typeForServer =>
          LocaleKeys.appPassword_serverBody.tr(),
        AppPasswordQuestion.changedElsewhere =>
          LocaleKeys.appPassword_changedElsewhereBody.tr(),
      };

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);
    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        _title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: premium.textSecondary,
                ),
              ),
              if (widget.allowUnencryptedSync) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocaleKeys.sync_encryptToggle.tr(),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: premium.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            LocaleKeys.sync_encryptToggleHint.tr(),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: premium.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value: _encryptSync,
                      onChanged: _working
                          ? null
                          : (value) => setState(() {
                                _encryptSync = value;
                                _error = null;
                              }),
                    ),
                  ],
                ),
              ],
              if (!widget.allowUnencryptedSync || _encryptSync) ...[
                const SizedBox(height: 18),
                ProviderTextField(
                  label: LocaleKeys.appPassword_field.tr(),
                  controller: _password,
                  palette: palette,
                  obscure: true,
                  autofocus: true,
                  onSubmitted: (_) =>
                      _choosing ? setState(() {}) : unawaited(_submit()),
                ),
                if (_choosing) ...[
                  const SizedBox(height: 8),
                  _Strength(controller: _password),
                  const SizedBox(height: 14),
                  ProviderTextField(
                    label: LocaleKeys.appPassword_fieldAgain.tr(),
                    controller: _again,
                    palette: palette,
                    obscure: true,
                    onSubmitted: (_) => unawaited(_submit()),
                  ),
                  const SizedBox(height: 14),
                  AppPasswordNote(text: LocaleKeys.appPassword_warning.tr()),
                ],
              ] else ...[
                const SizedBox(height: 14),
                AppPasswordNote(text: LocaleKeys.sync_unsealWarning.tr()),
              ],
              if (_error != null) _ErrorText(text: _error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: Text(widget.skipLabel ?? LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: _working ? null : () => unawaited(_submit()),
          child: _working
              ? const _Spinner()
              : Text(
                  widget.allowUnencryptedSync && !_encryptSync
                      ? LocaleKeys.appPassword_typeConfirm.tr()
                      : _choosing
                          ? LocaleKeys.appPassword_chooseConfirm.tr()
                          : LocaleKeys.appPassword_typeConfirm.tr(),
                ),
        ),
      ],
    );
  }
}

/// What is wrong with [password] as a new AppFlowy password, or null.
String? appPasswordProblem(String password, {required String again}) {
  if (password.length < AppPassword.minimumLength) {
    return LocaleKeys.appPassword_tooShort
        .tr(args: ['${AppPassword.minimumLength}']);
  }
  if (password != again) {
    return LocaleKeys.appPassword_mismatch.tr();
  }
  return null;
}

class _ChangeAppPasswordDialog extends StatefulWidget {
  const _ChangeAppPasswordDialog();

  @override
  State<_ChangeAppPasswordDialog> createState() =>
      _ChangeAppPasswordDialogState();
}

class _ChangeAppPasswordDialogState extends State<_ChangeAppPasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _again = TextEditingController();
  String? _error;
  String? _step;
  bool _working = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) {
      return;
    }
    final failure = _current.text.isEmpty
        ? LocaleKeys.appPassword_empty.tr()
        : appPasswordProblem(_next.text, again: _again.text);
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final outcome = await changeAppPassword(
      current: _current.text,
      next: _next.text,
      onStep: (step) {
        if (mounted) {
          setState(() => _step = step);
        }
      },
    );
    if (!mounted) {
      return;
    }
    if (outcome.changed) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(outcome.message)),
      );
      return;
    }
    setState(() {
      _working = false;
      _step = null;
      _error = outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);
    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.appPassword_changeTitle.tr(),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.appPassword_changeBody.tr(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: premium.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              ProviderTextField(
                label: LocaleKeys.appPassword_fieldCurrent.tr(),
                controller: _current,
                palette: palette,
                obscure: true,
                autofocus: true,
                onSubmitted: (_) {},
              ),
              const SizedBox(height: 14),
              ProviderTextField(
                label: LocaleKeys.appPassword_fieldNew.tr(),
                controller: _next,
                palette: palette,
                obscure: true,
                onSubmitted: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              _Strength(controller: _next),
              const SizedBox(height: 14),
              ProviderTextField(
                label: LocaleKeys.appPassword_fieldAgain.tr(),
                controller: _again,
                palette: palette,
                obscure: true,
                onSubmitted: (_) => unawaited(_submit()),
              ),
              const SizedBox(height: 14),
              AppPasswordNote(text: LocaleKeys.appPassword_warning.tr()),
              if (_step != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const _Spinner(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _step!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: premium.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) _ErrorText(text: _error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(false),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: _working ? null : () => unawaited(_submit()),
          child: _working
              ? const _Spinner()
              : Text(LocaleKeys.appPassword_changeConfirm.tr()),
        ),
      ],
    );
  }
}

class _Strength extends StatelessWidget {
  const _Strength({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, __) => PassphraseStrengthBar(
          strength: value.text.isEmpty
              ? PassphraseStrength.tooShort
              : ratePassphrase(value.text),
        ),
      );
}

/// A quiet sentence beside a password field.
class AppPasswordNote extends StatelessWidget {
  const AppPasswordNote({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: premium.hover,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? Icons.info_outline_rounded,
            size: 15,
            color: premium.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: premium.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFFD9534F)),
        ),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
