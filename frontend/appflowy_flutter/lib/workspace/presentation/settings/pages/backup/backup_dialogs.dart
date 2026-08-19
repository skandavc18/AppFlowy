// The dialogs a backup needs: a passphrase, and somewhere to put a copy.

import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/external_picker.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What a backup passphrase dialog is being opened for.
enum BackupPassphrasePurpose { create, unlock, change, remove }

/// Chooses the passphrase a copy is sealed with.
Future<bool> showSetBackupPassphraseDialog(BuildContext context) =>
    _ask(context, BackupPassphrasePurpose.create);

/// Enters the passphrase for this session, so scheduled copies can run.
Future<bool> showUnlockBackupDialog(BuildContext context) =>
    _ask(context, BackupPassphrasePurpose.unlock);

Future<bool> showChangeBackupPassphraseDialog(BuildContext context) =>
    _ask(context, BackupPassphrasePurpose.change);

Future<bool> showRemoveBackupPassphraseDialog(BuildContext context) =>
    _ask(context, BackupPassphrasePurpose.remove);

/// Asks for the passphrase one particular copy was sealed with.
///
/// ⚠️ Reads the salt and work factor from the COPY's own manifest, never from
/// the settings on this computer. A restore usually happens on a machine that
/// has never seen this workspace, and on one that has, the passphrase may well
/// have been changed since that copy was taken.
Future<Uint8List?> askForBackupPassphrase(
  BuildContext context, {
  required BackupManifest manifest,
}) =>
    showDialog<Uint8List>(
      context: context,
      builder: (context) => _CopyPassphraseDialog(manifest: manifest),
    );

Future<bool> _ask(
        BuildContext context, BackupPassphrasePurpose purpose) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _BackupPassphraseDialog(purpose: purpose),
    ) ??
    false;

/// Picks where copies go.
///
/// Returns null when nothing was chosen, so a cancelled pick leaves the
/// existing destination alone rather than clearing it.
Future<BackupDestination?> chooseBackupDestination(
  BuildContext context, {
  required BackupDestination current,
}) async {
  final kind = await showDialog<BackupDestinationKind>(
    context: context,
    builder: (context) => _DestinationKindDialog(current: current.kind),
  );
  if (kind == null || !context.mounted) {
    return null;
  }

  switch (kind) {
    case BackupDestinationKind.none:
      return const BackupDestination();

    case BackupDestinationKind.appflowyCloud:
      return BackupDestination(kind: kind);

    case BackupDestinationKind.folder:
      final path = await getIt<FilePickerService>().getDirectoryPath();
      if (path == null || path.isEmpty) {
        return null;
      }
      return BackupDestination(kind: kind, localPath: path);

    case BackupDestinationKind.googleDrive:
    case BackupDestinationKind.oneDrive:
    case BackupDestinationKind.box:
      final service = kind.providerService!;
      // The picker already knows how to sign an account in when there is not
      // one yet, so there is no separate "connect first" step.
      final picked = await showExternalPicker(
        context,
        info: ProviderServices.of(service),
        containersOnly: true,
      );
      if (picked == null) {
        return null;
      }
      // A copy cannot be stored by an account that was only signed in to read,
      // and finding that out at the first backup would be too late.
      if (context.mounted) {
        await ensureProviderWriteAccess(context, source: picked.source);
      }
      return BackupDestination(
        kind: kind,
        connectionId: picked.source.connectionId,
        accountLabel: picked.source.remoteName,
        folderId: picked.node.id,
        folderName: picked.node.name,
      );
  }
}

/// Says how a copy ended, in the same voice as everything else.
void reportBackupOutcome({
  required BuildContext context,
  required bool succeeded,
  required String message,
}) =>
    showToastNotification(
      message: message,
      type: succeeded ? ToastificationType.success : ToastificationType.error,
    );

// --- Choosing a passphrase ----------------------------------------------------

class _BackupPassphraseDialog extends StatefulWidget {
  const _BackupPassphraseDialog({required this.purpose});

  final BackupPassphrasePurpose purpose;

  @override
  State<_BackupPassphraseDialog> createState() =>
      _BackupPassphraseDialogState();
}

class _BackupPassphraseDialogState extends State<_BackupPassphraseDialog> {
  // Each dialog owns its controllers and disposes them in `dispose`; handing
  // them to `showDialog(...).whenComplete(dispose)` reads a disposed field
  // during the closing animation and takes the window down with it.
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _hint = TextEditingController();

  String? _error;
  bool _working = false;
  bool _remember = false;

  BackupSettings get _settings => BackupSettings.instance;

  bool get _asksCurrent => widget.purpose != BackupPassphrasePurpose.create;

  bool get _asksNew =>
      widget.purpose == BackupPassphrasePurpose.create ||
      widget.purpose == BackupPassphrasePurpose.change;

  @override
  void initState() {
    super.initState();
    _hint.text = _settings.policy.hint;
    _remember = _settings.canRememberPassphrase;
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

  /// Null when it worked, or the sentence to show when it did not.
  Future<String?> _run() async {
    final policy = _settings.policy;

    if (_asksNew) {
      if (_next.text.length < minimumPassphraseLength) {
        return LocaleKeys.backup_passphraseTooShort.tr(
          args: ['$minimumPassphraseLength'],
        );
      }
      if (_next.text != _confirm.text) {
        return LocaleKeys.backup_passphraseDoesNotMatch.tr();
      }
    }

    if (_asksCurrent) {
      final key = unlockBackupKey(
        passphrase: _current.text,
        salt: policy.salt,
        verifier: policy.verifier,
        verifierPhrase: BackupPolicy.verifierPhrase,
        iterations: policy.iterations,
      );
      if (key == null) {
        return LocaleKeys.backup_passphraseWrong.tr();
      }
      if (widget.purpose == BackupPassphrasePurpose.unlock) {
        _settings.unlockWith(key);
        if (_remember) {
          await _settings.rememberPassphrase(_current.text);
        }
        return null;
      }
      if (widget.purpose == BackupPassphrasePurpose.remove) {
        await _settings.update(policy.withoutPassphrase());
        return null;
      }
    }

    // Creating or changing: a fresh salt every time, so two workspaces sealed
    // with the same words still have different keys.
    final chosen = newBackupPassphrase(
      passphrase: _next.text,
      verifierPhrase: BackupPolicy.verifierPhrase,
      iterations: policy.iterations,
    );
    await _settings.update(
      policy.copyWith(
        encrypt: true,
        salt: chosen.salt,
        verifier: chosen.verifier,
        hint: _hint.text.trim(),
      ),
    );
    final key = unlockBackupKey(
      passphrase: _next.text,
      salt: chosen.salt,
      verifier: chosen.verifier,
      verifierPhrase: BackupPolicy.verifierPhrase,
      iterations: policy.iterations,
    );
    if (key == null) {
      return LocaleKeys.backup_passphraseCouldNotSet.tr();
    }
    _settings.unlockWith(key);
    if (_remember) {
      await _settings.rememberPassphrase(_next.text);
    }
    return null;
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
              const SizedBox(height: 18),
              if (_asksCurrent) ...[
                ProviderTextField(
                  label: LocaleKeys.backup_passphrase.tr(),
                  controller: _current,
                  palette: palette,
                  obscure: true,
                  autofocus: true,
                  onSubmitted: (_) => unawaited(_submit()),
                ),
                if (_settings.policy.hint.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    LocaleKeys.backup_passphraseHintIs
                        .tr(args: [_settings.policy.hint]),
                    style: TextStyle(
                      fontSize: 12,
                      color: premium.textSecondary,
                    ),
                  ),
                ],
                if (_asksNew) const SizedBox(height: 14),
              ],
              if (_asksNew) ...[
                ProviderTextField(
                  label: LocaleKeys.backup_passphraseNew.tr(),
                  controller: _next,
                  palette: palette,
                  obscure: true,
                  autofocus: !_asksCurrent,
                  onSubmitted: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                _StrengthBar(strength: strength),
                const SizedBox(height: 14),
                ProviderTextField(
                  label: LocaleKeys.backup_passphraseConfirm.tr(),
                  controller: _confirm,
                  palette: palette,
                  obscure: true,
                  onSubmitted: (_) => unawaited(_submit()),
                ),
                const SizedBox(height: 14),
                ProviderTextField(
                  label: LocaleKeys.backup_passphraseHint.tr(),
                  controller: _hint,
                  palette: palette,
                  hint: LocaleKeys.backup_passphraseHintPlaceholder.tr(),
                ),
              ],
              if (widget.purpose != BackupPassphrasePurpose.remove) ...[
                const SizedBox(height: 14),
                _RememberRow(
                  value: _remember,
                  canPersist: _settings.canRememberPassphrase,
                  onChanged: (value) => setState(() => _remember = value),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12.5, color: Colors.red),
                ),
              ],
              const SizedBox(height: 14),
              _Warning(text: _warning),
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
          child: Text(_confirmLabel),
        ),
      ],
    );
  }

  String get _title => switch (widget.purpose) {
        BackupPassphrasePurpose.create => LocaleKeys.backup_sealTitle.tr(),
        BackupPassphrasePurpose.unlock => LocaleKeys.backup_unlockTitle.tr(),
        BackupPassphrasePurpose.change =>
          LocaleKeys.backup_changePassphraseTitle.tr(),
        BackupPassphrasePurpose.remove =>
          LocaleKeys.backup_removePassphraseTitle.tr(),
      };

  String get _body => switch (widget.purpose) {
        BackupPassphrasePurpose.create => LocaleKeys.backup_sealBody.tr(),
        BackupPassphrasePurpose.unlock => LocaleKeys.backup_unlockBody.tr(),
        BackupPassphrasePurpose.change =>
          LocaleKeys.backup_changePassphraseBody.tr(),
        BackupPassphrasePurpose.remove =>
          LocaleKeys.backup_removePassphraseBody.tr(),
      };

  String get _warning => switch (widget.purpose) {
        BackupPassphrasePurpose.remove =>
          LocaleKeys.backup_removePassphraseWarning.tr(),
        _ => LocaleKeys.backup_passphraseWarning.tr(),
      };

  String get _confirmLabel => switch (widget.purpose) {
        BackupPassphrasePurpose.create => LocaleKeys.backup_sealConfirm.tr(),
        BackupPassphrasePurpose.unlock => LocaleKeys.backup_unlockConfirm.tr(),
        BackupPassphrasePurpose.change => LocaleKeys.button_confirm.tr(),
        BackupPassphrasePurpose.remove => LocaleKeys.button_remove.tr(),
      };
}

/// Asks for the passphrase of one stored copy.
class _CopyPassphraseDialog extends StatefulWidget {
  const _CopyPassphraseDialog({required this.manifest});

  final BackupManifest manifest;

  @override
  State<_CopyPassphraseDialog> createState() => _CopyPassphraseDialogState();
}

class _CopyPassphraseDialogState extends State<_CopyPassphraseDialog> {
  final TextEditingController _passphrase = TextEditingController();

  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _passphrase.dispose();
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

    final key = unlockBackupKey(
      passphrase: _passphrase.text,
      salt: widget.manifest.salt,
      verifier: widget.manifest.verifier,
      verifierPhrase: BackupPolicy.verifierPhrase,
      iterations: widget.manifest.iterations,
    );
    if (!mounted) {
      return;
    }
    if (key == null) {
      setState(() {
        _working = false;
        _error = LocaleKeys.backup_passphraseWrong.tr();
      });
      return;
    }
    Navigator.of(context).pop(key);
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);

    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.backup_openCopyTitle.tr(),
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
              LocaleKeys.backup_openCopyBody.tr(),
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: premium.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            ProviderTextField(
              label: LocaleKeys.backup_passphrase.tr(),
              controller: _passphrase,
              palette: palette,
              obscure: true,
              autofocus: true,
              onSubmitted: (_) => unawaited(_submit()),
            ),
            if (widget.manifest.hint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                LocaleKeys.backup_passphraseHintIs
                    .tr(args: [widget.manifest.hint]),
                style: TextStyle(fontSize: 12, color: premium.textSecondary),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: _working ? null : () => unawaited(_submit()),
          child: Text(LocaleKeys.backup_openCopyConfirm.tr()),
        ),
      ],
    );
  }
}

// --- Choosing a destination ---------------------------------------------------

class _DestinationKindDialog extends StatelessWidget {
  const _DestinationKindDialog({required this.current});

  final BackupDestinationKind current;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ViewerCard(
          color: palette.floatingSurface,
          reactsToPointer: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocaleKeys.backup_destinationTitle.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: premium.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      LocaleKeys.backup_destinationBody.tr(),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: premium.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final kind in const [
                BackupDestinationKind.folder,
                BackupDestinationKind.googleDrive,
                BackupDestinationKind.oneDrive,
                BackupDestinationKind.box,
                BackupDestinationKind.appflowyCloud,
              ])
                _DestinationRow(
                  kind: kind,
                  selected: kind == current,
                  onTap: () => Navigator.of(context).pop(kind),
                ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(LocaleKeys.button_cancel.tr()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final BackupDestinationKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final accent = backupDestinationAccent(kind);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                widthFactor: 1,
                child: Icon(
                  backupDestinationIcon(kind),
                  size: 17,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    backupDestinationLabel(kind),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: premium.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    backupDestinationDescription(kind),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: premium.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_rounded, size: 17, color: accent),
          ],
        ),
      ),
    );
  }
}

// --- Words and glyphs for a destination ---------------------------------------

String backupDestinationLabel(BackupDestinationKind kind) => switch (kind) {
      BackupDestinationKind.none => LocaleKeys.backup_destinationNone.tr(),
      BackupDestinationKind.folder => LocaleKeys.backup_destinationFolder.tr(),
      BackupDestinationKind.googleDrive => 'Google Drive',
      BackupDestinationKind.oneDrive => 'OneDrive',
      BackupDestinationKind.box => 'Box',
      BackupDestinationKind.appflowyCloud => 'AppFlowy Cloud',
    };

String backupDestinationDescription(BackupDestinationKind kind) =>
    switch (kind) {
      BackupDestinationKind.none => LocaleKeys.backup_destinationNoneHint.tr(),
      BackupDestinationKind.folder =>
        LocaleKeys.backup_destinationFolderHint.tr(),
      BackupDestinationKind.googleDrive =>
        LocaleKeys.backup_destinationServiceHint.tr(args: ['Google Drive']),
      BackupDestinationKind.oneDrive =>
        LocaleKeys.backup_destinationServiceHint.tr(args: ['OneDrive']),
      BackupDestinationKind.box =>
        LocaleKeys.backup_destinationServiceHint.tr(args: ['Box']),
      BackupDestinationKind.appflowyCloud =>
        LocaleKeys.backup_destinationCloudHint.tr(),
    };

IconData backupDestinationIcon(BackupDestinationKind kind) => switch (kind) {
      BackupDestinationKind.none => Icons.block_rounded,
      BackupDestinationKind.folder => Icons.folder_rounded,
      BackupDestinationKind.googleDrive => Icons.add_to_drive_rounded,
      BackupDestinationKind.oneDrive => Icons.cloud_rounded,
      BackupDestinationKind.box => Icons.inbox_rounded,
      BackupDestinationKind.appflowyCloud => Icons.cloud_done_rounded,
    };

Color backupDestinationAccent(BackupDestinationKind kind) => switch (kind) {
      BackupDestinationKind.none => const Color(0xFF6B7280),
      BackupDestinationKind.folder => const Color(0xFF8B5E34),
      BackupDestinationKind.googleDrive => const Color(0xFF1A73E8),
      BackupDestinationKind.oneDrive => const Color(0xFF0364B8),
      BackupDestinationKind.box => const Color(0xFF0061D5),
      BackupDestinationKind.appflowyCloud => const Color(0xFF00BCF0),
    };

// --- Shared bits ---------------------------------------------------------------

class _RememberRow extends StatelessWidget {
  const _RememberRow({
    required this.value,
    required this.canPersist,
    required this.onChanged,
  });

  final bool value;
  final bool canPersist;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.backup_rememberPassphrase.tr(),
                style: TextStyle(fontSize: 13, color: premium.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                canPersist
                    ? LocaleKeys.backup_rememberPassphraseHint.tr()
                    : LocaleKeys.backup_rememberPassphraseSession.tr(),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: premium.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
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
    final tint = switch (strength) {
      PassphraseStrength.tooShort ||
      PassphraseStrength.weak =>
        const Color(0xFFD9534F),
      PassphraseStrength.fair => const Color(0xFFE0A800),
      PassphraseStrength.good ||
      PassphraseStrength.strong =>
        const Color(0xFF3E9C5A),
    };

    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: i < filled ? tint : premium.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 4),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: premium.hover,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
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
