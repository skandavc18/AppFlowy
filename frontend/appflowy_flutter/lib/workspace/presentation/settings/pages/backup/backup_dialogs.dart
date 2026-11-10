// The dialogs a backup needs: a passphrase, and somewhere to put a copy.

import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/external_picker.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The key of one stored copy: the AppFlowy password's, when the copy was
/// sealed with it, or the one made from the password the copy asks for.
///
/// ⚠️ Reads the salt and work factor from the COPY's own manifest, never from
/// the settings on this computer. A restore usually happens on a machine that
/// has never seen this workspace, and on one that has, the password may well
/// have been changed since that copy was taken.
Future<Uint8List?> askForBackupPassphrase(
  BuildContext context, {
  required BackupManifest manifest,
}) async {
  final password = await AppPassword.instance.current();
  if (password != null) {
    final key = await BackupSettings.keyForCopy(password, manifest);
    if (key != null) {
      return key;
    }
  }
  if (!context.mounted) {
    return null;
  }
  return showDialog<Uint8List>(
    context: context,
    builder: (context) => _CopyPassphraseDialog(manifest: manifest),
  );
}

/// Picks where copies go.
///
/// Returns null when nothing was chosen, so a cancelled pick leaves the
/// existing destination alone rather than clearing it. Sync passes its own
/// [title] and [body], and leaves AppFlowy Cloud out: a folder there cannot be
/// listed, which sync depends on.
Future<BackupDestination?> chooseBackupDestination(
  BuildContext context, {
  required BackupDestination current,
  bool allowAppFlowyCloud = true,
  String? title,
  String? body,
}) async {
  final kind = await showDialog<BackupDestinationKind>(
    context: context,
    builder: (context) => _DestinationKindDialog(
      current: current.kind,
      allowAppFlowyCloud: allowAppFlowyCloud,
      title: title,
      body: body,
    ),
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
      return chooseProviderFolder(context, kind);
  }
}

/// Signs in to Google Drive, OneDrive or Box when needed, and picks a folder
/// there that AppFlowy may write to.
Future<BackupDestination?> chooseProviderFolder(
  BuildContext context,
  BackupDestinationKind kind,
) async {
  final service = kind.providerService;
  if (service == null) {
    return null;
  }
  // The picker already knows how to sign an account in when there is not one
  // yet, so there is no separate "connect first" step.
  final picked = await showExternalPicker(
    context,
    info: ProviderServices.of(service),
    containersOnly: true,
  );
  if (picked == null) {
    return null;
  }
  // A copy cannot be stored by an account that was only signed in to read, and
  // finding that out at the first copy would be too late.
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

/// Signs in again to the account [destination] is kept in, after its sign in
/// lapsed or was lost, under the very connection the destination names. True
/// when the account is signed in afterwards.
Future<bool> signInAgainForDestination(
  BuildContext context,
  BackupDestination destination,
) async {
  final service = destination.kind.providerService;
  if (service == null) {
    return false;
  }
  final connection = await showProviderConnectDialog(
    context,
    info: ProviderServices.of(service),
    // Copies and sync both write to the folder.
    requestWriteAccess: true,
    reconnectId:
        destination.connectionId.isEmpty ? null : destination.connectionId,
  );
  return connection != null;
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
  const _DestinationKindDialog({
    required this.current,
    this.allowAppFlowyCloud = true,
    this.title,
    this.body,
  });

  final BackupDestinationKind current;
  final bool allowAppFlowyCloud;
  final String? title;
  final String? body;

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
                      title ?? LocaleKeys.backup_destinationTitle.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: premium.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body ?? LocaleKeys.backup_destinationBody.tr(),
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
              for (final kind in [
                BackupDestinationKind.folder,
                BackupDestinationKind.googleDrive,
                BackupDestinationKind.oneDrive,
                BackupDestinationKind.box,
                if (allowAppFlowyCloud) BackupDestinationKind.appflowyCloud,
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
    final accent = LegibleColor.onWash(
      premium.floatingSurface,
      backupDestinationAccent(kind),
      wash: 0.12,
    );

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

/// How well a passphrase being chosen would stand up, as four bars.
class PassphraseStrengthBar extends StatelessWidget {
  const PassphraseStrengthBar({super.key, required this.strength});

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

