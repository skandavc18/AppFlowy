import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup.dart';
import 'package:appflowy/workspace/application/reset/app_reset.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/backup_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Offers "Reset everything and start fresh" on the Account & App settings
/// page, whether AppFlowy is running local-only, synced through a cloud drive,
/// or signed in to a self-hosted server.
class ResetEverythingSection extends StatelessWidget {
  const ResetEverythingSection({
    super.key,
    this.onBeforeRestart,
  });

  /// Called right before AppFlowy restarts (for instance to dismiss an open
  /// settings dialog).
  final VoidCallback? onBeforeRestart;

  static const Color _danger = Color(0xFFD1454B);

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return SettingsCategory(
      title: LocaleKeys.freshReset_sectionTitle.tr(),
      description: LocaleKeys.freshReset_sectionDescription.tr(),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                LocaleKeys.freshReset_rowHint.tr(),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: premium.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              key: const ValueKey('reset-everything-button'),
              onPressed: () => unawaited(
                showResetEverythingDialog(
                  context,
                  onBeforeRestart: onBeforeRestart,
                ),
              ),
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: Text(LocaleKeys.freshReset_button.tr()),
              style: TextButton.styleFrom(
                foregroundColor: _danger,
                backgroundColor: _danger.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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
        ),
      ],
    );
  }
}

Future<bool> showResetEverythingDialog(
  BuildContext context, {
  VoidCallback? onBeforeRestart,
}) async {
  final passwords = AppPassword.instance;
  final sync = WorkspaceSyncEngine.instance;
  await passwords.ensureLoaded();
  await sync.settings.ensureLoaded();
  if (!context.mounted) {
    return false;
  }
  final binding = sync.binding;
  final syncLabel =
      binding == null ? null : _syncDestinationLabel(binding.destination);

  final didReset = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ResetEverythingDialog(
      requiresPassword: passwords.isSet,
      syncDestinationLabel: syncLabel,
      onConfirm: ({required password, required clearCloudSync}) async {
        try {
          await AppFreshResetService(
            restart: () async {
              if (dialogContext.mounted &&
                  Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop(true);
              }
              onBeforeRestart?.call();
              if (!FlowyRunner.currentMode.isUnitTest) {
                await runAppFlowy();
              }
            },
          ).resetEverything(
            password: password,
            clearCloudSync: clearCloudSync,
          );
          return null;
        } on AppResetError catch (error) {
          if (error.message == 'wrong_password') {
            return LocaleKeys.appPassword_wrong.tr();
          }
          return error.message;
        } on Object catch (error) {
          return describeSyncError(error);
        }
      },
    ),
  );
  return didReset == true;
}

String _syncDestinationLabel(BackupDestination destination) {
  final where = switch (destination.kind) {
    BackupDestinationKind.folder => destination.localPath,
    _ => destination.folderName.isEmpty
        ? destination.accountLabel
        : '${destination.folderName} · ${destination.accountLabel}',
  };
  final service = backupDestinationLabel(destination.kind);
  return where.isEmpty ? service : '$service ($where)';
}

/// Confirmation dialog for "Reset everything and start fresh".
///
/// Asks for the AppFlowy password iff [requiresPassword] is true, and offers
/// an optional checkbox to clear the synced cloud folder when
/// [syncDestinationLabel] is present.
class ResetEverythingDialog extends StatefulWidget {
  const ResetEverythingDialog({
    super.key,
    required this.requiresPassword,
    required this.onConfirm,
    this.syncDestinationLabel,
  });

  final bool requiresPassword;
  final String? syncDestinationLabel;

  /// Returns `null` on success, or an error string to display in the dialog.
  final Future<String?> Function({
    required String? password,
    required bool clearCloudSync,
  }) onConfirm;

  @override
  State<ResetEverythingDialog> createState() => _ResetEverythingDialogState();
}

class _ResetEverythingDialogState extends State<ResetEverythingDialog> {
  static const Color _danger = Color(0xFFD1454B);
  static const Color _warning = Color(0xFFD9922E);

  final TextEditingController _password = TextEditingController();
  bool _clearCloudSync = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) {
      return;
    }
    if (widget.requiresPassword && _password.text.isEmpty) {
      setState(() => _error = LocaleKeys.appPassword_empty.tr());
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final problem = await widget.onConfirm(
      password: widget.requiresPassword ? _password.text : null,
      clearCloudSync: _clearCloudSync,
    );
    if (!mounted) {
      return;
    }
    if (problem == null) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _working = false);
      }
      return;
    }
    setState(() {
      _working = false;
      _error = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);
    final syncTarget = widget.syncDestinationLabel;

    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.freshReset_dialogTitle.tr(),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.freshReset_dialogBody.tr(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: premium.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 17,
                      color: _warning,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        syncTarget != null
                            ? LocaleKeys.freshReset_warningWithSync
                                .tr(args: [syncTarget])
                            : LocaleKeys.freshReset_warningLocal.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: premium.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (syncTarget != null) ...[
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: _working
                      ? null
                      : () => setState(
                            () => _clearCloudSync = !_clearCloudSync,
                          ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            key: const ValueKey('reset-clear-cloud-checkbox'),
                            value: _clearCloudSync,
                            onChanged: _working
                                ? null
                                : (value) => setState(
                                      () => _clearCloudSync = value ?? false,
                                    ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            LocaleKeys.freshReset_alsoClearCloud
                                .tr(args: [syncTarget]),
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: premium.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (widget.requiresPassword) ...[
                const SizedBox(height: 16),
                ProviderTextField(
                  key: const ValueKey('reset-app-password-field'),
                  label: LocaleKeys.freshReset_passwordPrompt.tr(),
                  controller: _password,
                  palette: palette,
                  obscure: true,
                  autofocus: true,
                  onSubmitted: (_) => unawaited(_submit()),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12.5, color: _danger),
                ),
              ],
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
          key: const ValueKey('reset-confirm-button'),
          onPressed: _working ? null : () => unawaited(_submit()),
          style: TextButton.styleFrom(
            foregroundColor: _danger,
            backgroundColor: _danger.withValues(alpha: 0.12),
          ),
          child: _working
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(LocaleKeys.freshReset_confirm.tr()),
        ),
      ],
    );
  }
}
