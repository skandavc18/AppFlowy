// The AppFlowy password in Settings: whether it is set, whether this computer
// knows it, and the way to change it.

import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class AppPasswordSettingsSection extends StatefulWidget {
  const AppPasswordSettingsSection({super.key});

  @override
  State<AppPasswordSettingsSection> createState() =>
      _AppPasswordSettingsSectionState();
}

class _AppPasswordSettingsSectionState
    extends State<AppPasswordSettingsSection> {
  AppPassword get _passwords => AppPassword.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_passwords.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCategory(
      title: LocaleKeys.appPassword_title.tr(),
      description: LocaleKeys.appPassword_description.tr(),
      children: [
        ListenableBuilder(
          listenable: _passwords,
          builder: (context, _) => AppPasswordStateRow(
            onDone: () {
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ),
      ],
    );
  }
}

/// One line: what this computer knows of the AppFlowy password, and what can
/// be done about it.
class AppPasswordStateRow extends StatelessWidget {
  const AppPasswordStateRow({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final passwords = AppPassword.instance;
    final (icon, text) = !passwords.isSet
        ? (Icons.key_off_rounded, LocaleKeys.appPassword_stateNotSet.tr())
        : !passwords.isKnown
            ? (
                Icons.lock_clock_rounded,
                LocaleKeys.appPassword_stateNeedsTyping.tr(),
              )
            : passwords.canRemember
                ? (Icons.key_rounded, LocaleKeys.appPassword_stateKnown.tr())
                : (
                    Icons.key_rounded,
                    LocaleKeys.appPassword_stateSession.tr(),
                  );
    return Row(
      children: [
        Icon(icon, size: 16, color: premium.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: premium.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (!passwords.isKnown)
          TextButton(
            onPressed: () async {
              await ensureAppPassword(context);
              onDone?.call();
            },
            child: Text(
              passwords.isSet
                  ? LocaleKeys.appPassword_type.tr()
                  : LocaleKeys.appPassword_set.tr(),
            ),
          )
        else
          TextButton(
            onPressed: () async {
              await showChangeAppPasswordDialog(context);
              onDone?.call();
            },
            child: Text(LocaleKeys.appPassword_change.tr()),
          ),
      ],
    );
  }
}
