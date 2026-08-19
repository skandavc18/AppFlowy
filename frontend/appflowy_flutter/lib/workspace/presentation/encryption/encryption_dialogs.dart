import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What a passphrase dialog is being opened for.
enum _PassphrasePurpose { create, unlock, change, remove, reveal }

/// Asks for a passphrase and turns it into whatever the caller needs.
///
/// Every one of these is the same shape — a title, a sentence, one or two
/// fields and a confirm — so they share one widget. Each dialog owns its own
/// controllers and disposes them in `dispose`; handing them to
/// `showDialog(...).whenComplete(dispose)` reads the field again during the
/// closing animation and takes the whole window down with it.
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.purpose,
    this.gatesWholeWorkspace = false,
  });

  final _PassphrasePurpose purpose;

  /// Only meaningful while creating: whether the key being chosen closes the
  /// way into the whole workspace or only into the item it was asked for.
  final bool gatesWholeWorkspace;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _hint = TextEditingController();

  String? _error;
  bool _working = false;

  bool get _asksCurrent =>
      widget.purpose == _PassphrasePurpose.unlock ||
      widget.purpose == _PassphrasePurpose.change ||
      widget.purpose == _PassphrasePurpose.remove ||
      widget.purpose == _PassphrasePurpose.reveal;

  bool get _asksNew =>
      widget.purpose == _PassphrasePurpose.create ||
      widget.purpose == _PassphrasePurpose.change;

  @override
  void initState() {
    super.initState();
    _hint.text = EncryptionVault.instance.hint;
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    _hint.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });

    final failure = await _run();
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _working = false;
      _error = failure;
    });
  }

  /// Returns null when it worked, or the sentence to show when it did not.
  Future<String?> _run() async {
    final vault = EncryptionVault.instance;

    if (_asksNew) {
      final chosen = _next.text;
      if (chosen.length < minimumPassphraseLength) {
        return LocaleKeys.encryption_tooShort.tr(
          args: ['$minimumPassphraseLength'],
        );
      }
      if (chosen != _confirm.text) {
        return LocaleKeys.encryption_doesNotMatch.tr();
      }
    }

    switch (widget.purpose) {
      case _PassphrasePurpose.create:
        final done = await vault.enable(
          passphrase: _next.text,
          hint: _hint.text.trim(),
          gateWholeWorkspace: widget.gatesWholeWorkspace,
        );
        return done ? null : LocaleKeys.encryption_couldNotSet.tr();

      case _PassphrasePurpose.unlock:
        final done = await vault.unlock(_current.text);
        return done ? null : LocaleKeys.encryption_wrongPassphrase.tr();

      case _PassphrasePurpose.reveal:
        // Checked against the policy's own verifier, so the key already in
        // memory cannot answer for a passphrase nobody typed.
        final key = unlockEncryptionKey(
          policy: vault.policy,
          passphrase: _current.text,
        );
        if (key == null) {
          return LocaleKeys.encryption_wrongPassphrase.tr();
        }
        vault.touch();
        return null;

      case _PassphrasePurpose.change:
        final done = await vault.changePassphrase(
          current: _current.text,
          next: _next.text,
          hint: _hint.text.trim(),
        );
        return done ? null : LocaleKeys.encryption_wrongPassphrase.tr();

      case _PassphrasePurpose.remove:
        final done = await vault.disable(
          passphrase: _current.text,
          // A gate whose key has gone must not outlive it: a mark left behind
          // would close the same item again the moment a new key is set.
          beforeRemoval: (_) async {
            await EncryptionMarkService.clearEveryMark();
            return true;
          },
        );
        return done ? null : LocaleKeys.encryption_wrongPassphrase.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);
    final strength = ratePassphrase(_next.text);

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
        width: 400,
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
            const SizedBox(height: 18),
            if (_asksCurrent) ...[
              ProviderTextField(
                label: widget.purpose == _PassphrasePurpose.unlock ||
                        widget.purpose == _PassphrasePurpose.reveal
                    ? LocaleKeys.encryption_passphrase.tr()
                    : LocaleKeys.encryption_currentPassphrase.tr(),
                controller: _current,
                palette: palette,
                obscure: true,
                autofocus: true,
                onSubmitted: (_) => unawaited(_submit()),
              ),
              if ((widget.purpose == _PassphrasePurpose.unlock ||
                      widget.purpose == _PassphrasePurpose.reveal) &&
                  EncryptionVault.instance.hint.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    LocaleKeys.encryption_hintIs
                        .tr(args: [EncryptionVault.instance.hint]),
                    style: TextStyle(
                      fontSize: 12,
                      color: premium.textMuted,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (_asksNew) ...[
              ProviderTextField(
                label: LocaleKeys.encryption_newPassphrase.tr(),
                controller: _next,
                palette: palette,
                obscure: true,
                autofocus: widget.purpose == _PassphrasePurpose.create,
                onSubmitted: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              _StrengthBar(strength: strength),
              const SizedBox(height: 12),
              ProviderTextField(
                label: LocaleKeys.encryption_confirmPassphrase.tr(),
                controller: _confirm,
                palette: palette,
                obscure: true,
                onSubmitted: (_) => unawaited(_submit()),
              ),
              const SizedBox(height: 12),
              ProviderTextField(
                label: LocaleKeys.encryption_hintLabel.tr(),
                controller: _hint,
                palette: palette,
                hint: LocaleKeys.encryption_hintPlaceholder.tr(),
              ),
              const SizedBox(height: 10),
              _Warning(text: LocaleKeys.encryption_noRecovery.tr()),
            ],
            if (widget.purpose == _PassphrasePurpose.remove) ...[
              const SizedBox(height: 10),
              _Warning(text: LocaleKeys.encryption_removeWarning.tr()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFFD1454B),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _working ? null : () => Navigator.of(context).pop(false),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        FilledButton(
          onPressed: _working ? null : () => unawaited(_submit()),
          child: _working
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_confirmLabel),
        ),
      ],
    );
  }

  String get _title => switch (widget.purpose) {
        _PassphrasePurpose.create => LocaleKeys.encryption_setTitle.tr(),
        _PassphrasePurpose.unlock => LocaleKeys.encryption_unlockTitle.tr(),
        _PassphrasePurpose.change => LocaleKeys.encryption_changeTitle.tr(),
        _PassphrasePurpose.remove => LocaleKeys.encryption_removeTitle.tr(),
        _PassphrasePurpose.reveal => LocaleKeys.encryption_revealTitle.tr(),
      };

  String get _body => switch (widget.purpose) {
        _PassphrasePurpose.create => widget.gatesWholeWorkspace
            ? LocaleKeys.encryption_setBodyWorkspace.tr()
            : LocaleKeys.encryption_setBody.tr(),
        _PassphrasePurpose.unlock => LocaleKeys.encryption_unlockBody.tr(),
        _PassphrasePurpose.change => LocaleKeys.encryption_changeBody.tr(),
        _PassphrasePurpose.remove => LocaleKeys.encryption_removeBody.tr(),
        _PassphrasePurpose.reveal => LocaleKeys.encryption_revealBody.tr(),
      };

  String get _confirmLabel => switch (widget.purpose) {
        _PassphrasePurpose.create => LocaleKeys.encryption_setConfirm.tr(),
        _PassphrasePurpose.unlock => LocaleKeys.encryption_unlockConfirm.tr(),
        _PassphrasePurpose.change => LocaleKeys.encryption_changeConfirm.tr(),
        _PassphrasePurpose.remove => LocaleKeys.encryption_removeConfirm.tr(),
        _PassphrasePurpose.reveal => LocaleKeys.encryption_revealConfirm.tr(),
      };
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength});

  final PassphraseStrength strength;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final filled = switch (strength) {
      PassphraseStrength.tooShort => 0,
      PassphraseStrength.weak => 1,
      PassphraseStrength.fair => 2,
      PassphraseStrength.good => 3,
      PassphraseStrength.strong => 4,
    };
    final colour = switch (strength) {
      PassphraseStrength.tooShort ||
      PassphraseStrength.weak =>
        const Color(0xFFD1454B),
      PassphraseStrength.fair => const Color(0xFFD9922E),
      PassphraseStrength.good ||
      PassphraseStrength.strong =>
        const Color(0xFF3E9B62),
    };

    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: i < filled ? colour : premium.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 4),
        ],
        const SizedBox(width: 10),
        Text(
          switch (strength) {
            PassphraseStrength.tooShort =>
              LocaleKeys.encryption_strengthTooShort.tr(),
            PassphraseStrength.weak => LocaleKeys.encryption_strengthWeak.tr(),
            PassphraseStrength.fair => LocaleKeys.encryption_strengthFair.tr(),
            PassphraseStrength.good => LocaleKeys.encryption_strengthGood.tr(),
            PassphraseStrength.strong =>
              LocaleKeys.encryption_strengthStrong.tr(),
          },
          style: TextStyle(fontSize: 11.5, color: premium.textMuted),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFD9922E).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Color(0xFFD9922E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: premium.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _ask(
  BuildContext context,
  _PassphrasePurpose purpose, {
  bool gatesWholeWorkspace = false,
}) async {
  await EncryptionVault.instance.ensureLoaded();
  if (!context.mounted) {
    return false;
  }
  final answer = await showDialog<bool>(
    context: context,
    builder: (_) => _PassphraseDialog(
      purpose: purpose,
      gatesWholeWorkspace: gatesWholeWorkspace,
    ),
  );
  return answer ?? false;
}

/// Chooses a passphrase for a workspace that has none.
///
/// [gateWholeWorkspace] says what the person was actually asking for. Settings
/// passes true ("ask before opening this workspace"); a page, block or column
/// menu leaves it false, so protecting one thing protects one thing.
Future<bool> showSetWorkspacePassphraseDialog(
  BuildContext context, {
  bool gateWholeWorkspace = false,
}) =>
    _ask(
      context,
      _PassphrasePurpose.create,
      gatesWholeWorkspace: gateWholeWorkspace,
    );

/// Asks for the passphrase so the key goes back into memory.
Future<bool> showUnlockWorkspaceDialog(BuildContext context) =>
    _ask(context, _PassphrasePurpose.unlock);

Future<bool> showChangeWorkspacePassphraseDialog(BuildContext context) =>
    _ask(context, _PassphrasePurpose.change);

Future<bool> showRemoveWorkspacePassphraseDialog(BuildContext context) =>
    _ask(context, _PassphrasePurpose.remove);

/// Makes sure the key is in memory before doing something that needs it.
///
/// This is what every menu row calls first. A workspace with no passphrase is
/// sent to the "choose one" dialog rather than being told it cannot do the
/// thing, because "encrypt this page" with no key is a request to set one up.
Future<bool> ensureWorkspaceUnlocked(BuildContext context) async {
  final vault = EncryptionVault.instance;
  await vault.ensureLoaded();
  if (vault.isUnlocked) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  return vault.isConfigured
      ? showUnlockWorkspaceDialog(context)
      : showSetWorkspacePassphraseDialog(context);
}

/// Asks for the passphrase again, right before sealed content is revealed.
///
/// The key staying in memory is a convenience for writing; it is not a reason
/// to hand a sealed block or column to whoever is at the keyboard now. When the
/// workspace is locked, unlocking is already that question, so it is asked once
/// rather than twice in a row.
Future<bool> confirmWorkspaceKey(BuildContext context) async {
  final vault = EncryptionVault.instance;
  await vault.ensureLoaded();
  if (!context.mounted) {
    return false;
  }
  if (!vault.isUnlocked) {
    return ensureWorkspaceUnlocked(context);
  }
  return _ask(context, _PassphrasePurpose.reveal);
}

/// Puts the whole workspace behind the key, asking for one if there is none.
///
/// This is the workspace's own menu asking, so the intent really is "ask before
/// opening this workspace" — unlike an item menu, which only wants a key for
/// the thing it was opened from.
Future<bool> protectWholeWorkspace(BuildContext context) async {
  final vault = EncryptionVault.instance;
  await vault.ensureLoaded();

  if (!vault.isConfigured) {
    if (!context.mounted) {
      return false;
    }
    return showSetWorkspacePassphraseDialog(context, gateWholeWorkspace: true);
  }

  if (!vault.isUnlocked) {
    if (!context.mounted || !await showUnlockWorkspaceDialog(context)) {
      return false;
    }
  }
  await vault.update(vault.policy.copyWith(gateWholeWorkspace: true));
  return true;
}

/// Stops asking for the key to open the workspace, without removing the key.
///
/// Anything protected one at a time stays protected — this is only about the
/// way in to the workspace itself.
Future<bool> stopProtectingWholeWorkspace(BuildContext context) async {
  final vault = EncryptionVault.instance;
  await vault.ensureLoaded();
  if (!vault.isConfigured) {
    return false;
  }
  if (!vault.isUnlocked) {
    if (!context.mounted || !await showUnlockWorkspaceDialog(context)) {
      return false;
    }
  }
  await vault.update(vault.policy.copyWith(gateWholeWorkspace: false));
  return true;
}

/// Opens one protected item for the rest of this session.
///
/// The passphrase is asked for every time, not only when the workspace key has
/// left memory. Protecting a page is a request to be asked before it opens, and
/// "the key happens to still be loaded" is not an answer to that.
Future<bool> unlockProtectedItem(BuildContext context, String id) async {
  if (!await confirmWorkspaceKey(context)) {
    return false;
  }
  EncryptionVault.instance.reveal(id);
  return true;
}

/// Shuts one protected item again, without touching the workspace key.
void lockProtectedItem(String id) => EncryptionVault.instance.conceal(id);

/// Says what happened, in the words the rest of the application uses.
void reportEncryptionOutcome({
  required BuildContext context,
  required bool succeeded,
  required String succeededMessage,
  String? failedMessage,
}) {
  showToastNotification(
    context: context,
    message: succeeded
        ? succeededMessage
        : failedMessage ?? LocaleKeys.encryption_couldNotChange.tr(),
    type: succeeded ? ToastificationType.success : ToastificationType.error,
  );
}
