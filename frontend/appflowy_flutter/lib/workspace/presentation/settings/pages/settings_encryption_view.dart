import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/presentation/encryption/encryption_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Settings ▸ Encryption.
///
/// One passphrase for the workspace, and the rules about when it is asked for.
/// Everything protected anywhere — a page, a folder, a table, a block, a
/// column — is protected with this one key, so there is one place to change it
/// and one place to turn it off.
class SettingsEncryptionView extends StatefulWidget {
  const SettingsEncryptionView({super.key});

  @override
  State<SettingsEncryptionView> createState() => _SettingsEncryptionViewState();
}

class _SettingsEncryptionViewState extends State<SettingsEncryptionView> {
  EncryptionVault get _vault => EncryptionVault.instance;

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onChanged);
    unawaited(_vault.ensureLoaded());
  }

  @override
  void dispose() {
    _vault.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _apply(EncryptionPolicy policy) => _vault.update(policy);

  @override
  Widget build(BuildContext context) {
    final policy = _vault.policy;
    final configured = _vault.isConfigured;

    return SettingsBody(
      title: LocaleKeys.encryption_settingsTitle.tr(),
      description: LocaleKeys.encryption_settingsDescription.tr(),
      children: [
        SettingsCategory(
          title: LocaleKeys.encryption_keyTitle.tr(),
          description: LocaleKeys.encryption_keyDescription.tr(),
          children: [
            _Status(
              configured: configured,
              unlocked: _vault.isUnlocked,
            ),
            const SizedBox(height: 14),
            if (!configured)
              _Action(
                label: LocaleKeys.encryption_setConfirm.tr(),
                description: LocaleKeys.encryption_setBody.tr(),
                icon: Icons.lock_outline_rounded,
                onPressed: () async {
                  final done = await showSetWorkspacePassphraseDialog(
                    context,
                    gateWholeWorkspace: true,
                  );
                  if (done && context.mounted) {
                    reportEncryptionOutcome(
                      context: context,
                      succeeded: true,
                      succeededMessage: LocaleKeys.encryption_nowProtected.tr(),
                    );
                  }
                },
              )
            else ...[
              _Action(
                label: _vault.isUnlocked
                    ? LocaleKeys.encryption_lockNow.tr()
                    : LocaleKeys.encryption_unlockConfirm.tr(),
                description: _vault.isUnlocked
                    ? LocaleKeys.encryption_lockNowHint.tr()
                    : LocaleKeys.encryption_unlockBody.tr(),
                icon: _vault.isUnlocked
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                onPressed: () async {
                  if (_vault.isUnlocked) {
                    _vault.lock();
                  } else {
                    await showUnlockWorkspaceDialog(context);
                  }
                },
              ),
              const SizedBox(height: 12),
              _Action(
                label: LocaleKeys.encryption_changeTitle.tr(),
                description: LocaleKeys.encryption_changeBody.tr(),
                icon: Icons.password_rounded,
                onPressed: () async {
                  final done =
                      await showChangeWorkspacePassphraseDialog(context);
                  if (done && context.mounted) {
                    reportEncryptionOutcome(
                      context: context,
                      succeeded: true,
                      succeededMessage: LocaleKeys.encryption_changed.tr(),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              _Action(
                label: LocaleKeys.encryption_removeTitle.tr(),
                description: LocaleKeys.encryption_removeBody.tr(),
                icon: Icons.lock_open_rounded,
                destructive: true,
                onPressed: () async {
                  final done =
                      await showRemoveWorkspacePassphraseDialog(context);
                  if (done && context.mounted) {
                    reportEncryptionOutcome(
                      context: context,
                      succeeded: true,
                      succeededMessage: LocaleKeys.encryption_removed.tr(),
                    );
                  }
                },
              ),
            ],
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.encryption_reachTitle.tr(),
          description: LocaleKeys.encryption_reachDescription.tr(),
          children: [
            _Toggle(
              label: LocaleKeys.encryption_gateWholeWorkspace.tr(),
              description: LocaleKeys.encryption_gateWholeWorkspaceHint.tr(),
              value: policy.gateWholeWorkspace,
              enabled: configured,
              onChanged: (value) => unawaited(
                _apply(policy.copyWith(gateWholeWorkspace: value)),
              ),
            ),
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.encryption_idleTitle.tr(),
          description: LocaleKeys.encryption_idleDescription.tr(),
          children: [
            _Choice<int>(
              label: LocaleKeys.encryption_lockAfter.tr(),
              description: LocaleKeys.encryption_lockAfterHint.tr(),
              value: policy.lockAfterMinutes,
              enabled: configured,
              entries: [
                for (final minutes in EncryptionPolicy.lockDelayChoices)
                  DropdownMenuEntry<int>(
                    value: minutes,
                    label: minutes == 0
                        ? LocaleKeys.encryption_lockNever.tr()
                        : LocaleKeys.encryption_lockMinutes
                            .tr(args: ['$minutes']),
                  ),
              ],
              onChanged: (value) => unawaited(
                _apply(policy.copyWith(lockAfterMinutes: value)),
              ),
            ),
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.encryption_howTitle.tr(),
          description: LocaleKeys.encryption_howDescription.tr(),
          children: [
            _Fact(
              label: LocaleKeys.encryption_factCipher.tr(),
              value: 'AES-256-GCM',
            ),
            _Fact(
              label: LocaleKeys.encryption_factDerivation.tr(),
              value: 'PBKDF2-HMAC-SHA256 · '
                  '${policy.iterations} ${LocaleKeys.encryption_rounds.tr()}',
            ),
            _Fact(
              label: LocaleKeys.encryption_factStored.tr(),
              value: LocaleKeys.encryption_factStoredValue.tr(),
            ),
          ],
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.configured, required this.unlocked});

  final bool configured;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final (colour, label) = switch ((configured, unlocked)) {
      (false, _) => (premium.textMuted, LocaleKeys.encryption_stateOff.tr()),
      (true, true) => (
          const Color(0xFF3E9B62),
          LocaleKeys.encryption_stateUnlocked.tr(),
        ),
      (true, false) => (
          const Color(0xFFD9922E),
          LocaleKeys.encryption_stateLocked.tr(),
        ),
    };

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: premium.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.description,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final String description;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final tint = destructive ? const Color(0xFFD1454B) : premium.accent;

    return Row(
      children: [
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: premium.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // The surface and the ink are both stated here. A tonal button takes
        // its container from the theme, which in this workspace is close
        // enough to the accent to render the label invisible.
        TextButton.icon(
          onPressed: () => unawaited(onPressed()),
          icon: Icon(icon, size: 16),
          label: Text(label),
          style: TextButton.styleFrom(
            foregroundColor: tint,
            backgroundColor: tint.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            minimumSize: const Size(0, 36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: premium.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: premium.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.description,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String description;
  final T value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: premium.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: premium.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          DropdownMenu<T>(
            // The menu reads its label once, so the key has to carry the value.
            key: ValueKey('$label-$value'),
            initialSelection: value,
            enabled: enabled,
            dropdownMenuEntries: entries,
            onSelected: (selected) {
              if (selected != null) {
                onChanged(selected);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: premium.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: premium.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
