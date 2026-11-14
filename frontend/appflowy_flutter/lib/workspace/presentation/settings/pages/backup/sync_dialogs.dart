// The questions sync and restore ask, and the progress they show while they
// work.

import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/backup_dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

WorkspaceSyncEngine get _sync => WorkspaceSyncEngine.instance;

/// Chooses a folder and, depending on what is in it, starts syncing this
/// workspace there, reconnects to it, or joins the workspace it holds.
Future<void> setUpWorkspaceSync(BuildContext context) async {
  final destination = await chooseBackupDestination(
    context,
    current: _sync.binding?.destination ?? const BackupDestination(),
    allowAppFlowyCloud: false,
    allowSelfHostedCloud: true,
    title: LocaleKeys.sync_chooseTitle.tr(),
    body: LocaleKeys.sync_chooseBody.tr(),
  );
  if (destination == null || !context.mounted) {
    return;
  }
  await continueSyncSetup(context, destination);
}

/// Goes on with a folder already chosen: reads it, asks for the AppFlowy
/// password it is sealed with when this computer does not know it, and
/// starts, reconnects or joins.
///
/// Also how the first screen sets sync up, before any workspace is open:
/// then a folder holding a workspace is joined, and an empty one is
/// remembered for [onEmptyFolder] to start in once a workspace exists.
Future<void> continueSyncSetup(
  BuildContext context,
  BackupDestination destination, {
  Future<void> Function(bool encrypt)? onEmptyFolder,
}) async {
  var inspection = await runWithSyncProgress(
    context,
    title: LocaleKeys.sync_reading.tr(),
    work: () => _sync.inspect(destination),
  );
  if (inspection == null || !context.mounted) {
    return;
  }

  if (inspection.needsPassword) {
    final opened = inspection;
    final typed = await askAppPassword(
      context,
      question: AppPasswordQuestion.typeForFolder,
      check: (password) async {
        try {
          inspection = await _sync.unlockFolder(destination, opened, password);
          return null;
        } on SyncError catch (error) {
          return error.detail;
        }
      },
    );
    if (typed == null || !context.mounted) {
      return;
    }
  }
  final found = inspection!;

  final where = destination.folderName.isNotEmpty
      ? destination.folderName
      : destination.localPath;

  switch (found.state) {
    case SyncFolderState.unreadable:
    case SyncFolderState.locked:
      await showSyncNotice(
        context,
        title: LocaleKeys.sync_title.tr(),
        body: LocaleKeys.sync_unreadable.tr(),
      );
    case SyncFolderState.empty:
      if (onEmptyFolder != null) {
        final encrypt = await ensureAppPasswordForNewSync(context);
        if (encrypt == null || !context.mounted) {
          return;
        }
        await onEmptyFolder(encrypt);
        return;
      }
      final encrypt = await _confirmStartSyncStep(
        context,
        where: where,
      );
      if (encrypt == null || !context.mounted) {
        return;
      }
      if (encrypt) {
        final password = await ensureAppPassword(context);
        if (password == null || !context.mounted) {
          return;
        }
      }
      final done = await runWithSyncProgress(
        context,
        title: LocaleKeys.sync_startConfirm.tr(),
        work: () async {
          await _sync.startNew(destination, encrypt: encrypt);
          return true;
        },
      );
      if (done == true && context.mounted) {
        reportBackupOutcome(
          context: context,
          succeeded: true,
          message: LocaleKeys.sync_started.tr(args: [_sync.workspaceName]),
        );
      }
    case SyncFolderState.thisWorkspace:
      final confirmed = await confirmSyncStep(
        context,
        title: LocaleKeys.sync_reconnectTitle.tr(),
        body: LocaleKeys.sync_reconnectBody.tr(),
        confirm: LocaleKeys.sync_reconnectConfirm.tr(),
      );
      if (!confirmed || !context.mounted) {
        return;
      }
      final done = await runWithSyncProgress(
        context,
        title: LocaleKeys.sync_reconnectConfirm.tr(),
        work: () async {
          await _sync.reconnect(destination, found);
          return true;
        },
      );
      if (done == true && context.mounted) {
        reportBackupOutcome(
          context: context,
          succeeded: true,
          message: LocaleKeys.sync_reconnected.tr(),
        );
      }
    case SyncFolderState.otherWorkspace:
      final info = found.epoch!;
      final confirmed = await confirmSyncStep(
        context,
        title: LocaleKeys.sync_joinTitle.tr(args: [info.workspaceName]),
        body: LocaleKeys.sync_joinBody.tr(
          args: [
            info.workspaceName,
            info.deviceName.isEmpty
                ? LocaleKeys.sync_otherComputer.tr()
                : info.deviceName,
            DateFormat.yMMMd().format(info.createdAt.toLocal()),
          ],
        ),
        note:
            _sync.canSyncThisWorkspace ? LocaleKeys.sync_joinSafety.tr() : null,
        confirm: LocaleKeys.sync_joinConfirm.tr(),
        destructive: _sync.canSyncThisWorkspace,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
      await runWithSyncProgress(
        context,
        title: LocaleKeys.sync_joinConfirm.tr(),
        work: () async {
          await _sync.join(destination, found);
          return true;
        },
      );
  }
}

/// Asks before starting sync into an empty folder, with cloud encryption ON by
/// default and toggleable. Returns `true` for encrypted, `false` for
/// unencrypted, or `null` when cancelled.
Future<bool?> _confirmStartSyncStep(
  BuildContext context, {
  required String where,
}) =>
    showDialog<bool>(
      context: context,
      builder: (context) => _StartSyncQuestion(
        workspaceName: _sync.workspaceName,
        where: where,
      ),
    );

class _StartSyncQuestion extends StatefulWidget {
  const _StartSyncQuestion({
    required this.workspaceName,
    required this.where,
  });

  final String workspaceName;
  final String where;

  @override
  State<_StartSyncQuestion> createState() => _StartSyncQuestionState();
}

class _StartSyncQuestionState extends State<_StartSyncQuestion> {
  bool _encrypt = true;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.sync_startTitle.tr(),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.sync_startBody
                  .tr(args: [widget.workspaceName, widget.where]),
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: premium.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
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
                  value: _encrypt,
                  onChanged: (value) => setState(() => _encrypt = value),
                ),
              ],
            ),
            if (!_encrypt) ...[
              const SizedBox(height: 12),
              SyncNoteBox(text: LocaleKeys.sync_unsealWarning.tr()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_encrypt),
          style: TextButton.styleFrom(foregroundColor: premium.accent),
          child: Text(LocaleKeys.sync_startConfirm.tr()),
        ),
      ],
    );
  }
}

/// Asks before something sync does that cannot simply be taken back.
Future<bool> confirmSyncStep(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  String? note,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _SyncQuestion(
        title: title,
        body: body,
        note: note,
        confirm: confirm,
        destructive: destructive,
      ),
    ) ??
    false;

/// Says something, with nothing to choose.
Future<void> showSyncNotice(
  BuildContext context, {
  required String title,
  required String body,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _SyncQuestion(
        title: title,
        body: body,
        confirm: LocaleKeys.button_ok.tr(),
        cancellable: false,
      ),
    );

/// Runs [work] behind a dialog that says what it is doing, and reports a
/// failure there rather than leaving it to a toast that vanishes.
///
/// Returns null when [work] failed.
Future<T?> runWithSyncProgress<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function() work,
}) async {
  T? result;
  Object? failure;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SyncProgressDialog(
      title: title,
      work: () async {
        try {
          result = await work();
        } on Object catch (error) {
          failure = error;
        }
      },
    ),
  );
  if (failure != null && context.mounted) {
    await showSyncNotice(
      context,
      title: title,
      body: describeSyncError(failure!),
    );
    return null;
  }
  return result;
}

/// Offers the workspace another computer restored.
Future<void> showRestoredElsewhereDialog(
  BuildContext context,
  SyncEpochInfo restored,
) async {
  final load = await confirmSyncStep(
    context,
    title: LocaleKeys.sync_restoredTitle.tr(),
    body: LocaleKeys.sync_restoredBody.tr(
      args: [
        restored.workspaceName,
        restored.deviceName.isEmpty
            ? LocaleKeys.sync_otherComputer.tr()
            : restored.deviceName,
        DateFormat.yMMMd().add_jm().format(restored.createdAt.toLocal()),
      ],
    ),
    confirm: LocaleKeys.sync_restoredConfirm.tr(),
  );
  if (!load || !context.mounted) {
    return;
  }
  await runWithSyncProgress(
    context,
    title: LocaleKeys.sync_restoredConfirm.tr(),
    work: () async {
      await _sync.loadRestoredWorkspace();
      return true;
    },
  );
}

/// How a copy is to be restored.
enum BackupRestoreChoice { inPlace, intoFolder }

/// Asks how to restore [copy].
Future<BackupRestoreChoice?> chooseBackupRestore(
  BuildContext context, {
  required BackupCopy copy,
}) =>
    showDialog<BackupRestoreChoice>(
      context: context,
      builder: (context) => _RestoreChoiceDialog(copy: copy),
    );

/// Restores [copy] in place, behind a dialog that follows each step, and
/// restarts AppFlowy to finish.
Future<void> runBackupRestoreInPlace(
  BuildContext context, {
  required BackupCopy copy,
  Uint8List? key,
  BackupTarget? from,
}) async {
  final result = await runWithSyncProgress(
    context,
    title: LocaleKeys.backup_restoringTitle.tr(),
    work: () => BackupService.instance.restoreInPlace(
      copy: copy,
      key: key,
      from: from,
    ),
  );
  if (result == null || !context.mounted) {
    return;
  }
  if (!result.syncedEverywhere && result.syncDetail.isNotEmpty) {
    await showSyncNotice(
      context,
      title: LocaleKeys.backup_restoringTitle.tr(),
      body: LocaleKeys.backup_restoredSyncOff.tr(args: [result.syncDetail]),
    );
  }
  if (context.mounted) {
    reportBackupOutcome(
      context: context,
      succeeded: true,
      message:
          LocaleKeys.backup_restoredInPlace.tr(args: [result.workspaceName]),
    );
  }
  WorkspaceSyncEngine.instance.detach();
  await runAppFlowy();
}

// --- The dialogs ----------------------------------------------------------------

class _SyncQuestion extends StatelessWidget {
  const _SyncQuestion({
    required this.title,
    required this.body,
    required this.confirm,
    this.note,
    this.destructive = false,
    this.cancellable = true,
  });

  final String title;
  final String body;
  final String? note;
  final String confirm;
  final bool destructive;
  final bool cancellable;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: premium.textSecondary,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 14),
              SyncNoteBox(text: note!),
            ],
          ],
        ),
      ),
      actions: [
        if (cancellable)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: const Color(0xFFD9534F))
              : null,
          child: Text(confirm),
        ),
      ],
    );
  }
}

/// A quiet box for something worth knowing before agreeing.
class SyncNoteBox extends StatelessWidget {
  const SyncNoteBox({super.key, required this.text, this.icon});

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

class _SyncProgressDialog extends StatefulWidget {
  const _SyncProgressDialog({required this.title, required this.work});

  final String title;
  final Future<void> Function() work;

  @override
  State<_SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<_SyncProgressDialog> {
  @override
  void initState() {
    super.initState();
    _sync.addListener(_onChanged);
    BackupService.instance.addListener(_onChanged);
    unawaited(_run());
  }

  @override
  void dispose() {
    _sync.removeListener(_onChanged);
    BackupService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _run() async {
    await widget.work();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String get _detail {
    final restore = BackupService.instance.restoreProgress;
    if (restore.isRunning) {
      return switch (restore.stage) {
        RestoreStage.fetching => LocaleKeys.backup_restoreStageFetching.tr(),
        RestoreStage.opening => LocaleKeys.backup_restoreStageOpening.tr(),
        RestoreStage.unpacking => restore.detail == 'safety'
            ? LocaleKeys.backup_restoreStageSafety.tr()
            : LocaleKeys.backup_restoreStageUnpacking.tr(),
        _ => LocaleKeys.sync_working.tr(),
      };
    }
    final activity = _sync.activity;
    return activity.isEmpty ? LocaleKeys.sync_working.tr() : activity;
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final restore = BackupService.instance.restoreProgress;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: premium.floatingSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: premium.textPrimary,
          ),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _detail,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: premium.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: restore.isRunning ? restore.fraction : null,
                  minHeight: 4,
                  backgroundColor: premium.border,
                  color: premium.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestoreChoiceDialog extends StatelessWidget {
  const _RestoreChoiceDialog({required this.copy});

  final BackupCopy copy;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final manifest = copy.manifest;
    // A copy whose record says nothing either way may still carry a snapshot;
    // the restore finds out once it is unpacked.
    final canRestoreInPlace =
        manifest == null || manifest.hasWorkspaceSnapshot || manifest.encrypted;
    final syncing = WorkspaceSyncEngine.instance.isBoundHere;
    final when = DateFormat.yMMMd().add_jm().format(copy.takenAt.toLocal());

    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.backup_restoreTitle.tr(),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              canRestoreInPlace
                  ? LocaleKeys.backup_restoreBody.tr(args: [when])
                  : LocaleKeys.backup_restoreUnavailable.tr(),
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: premium.textSecondary,
              ),
            ),
            if (canRestoreInPlace && syncing) ...[
              const SizedBox(height: 14),
              SyncNoteBox(
                text: LocaleKeys.backup_restoreSyncNote.tr(),
                icon: Icons.sync_rounded,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(BackupRestoreChoice.intoFolder),
          child: Text(LocaleKeys.backup_restoreToFolder.tr()),
        ),
        if (canRestoreInPlace)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(BackupRestoreChoice.inPlace),
            style: TextButton.styleFrom(
              foregroundColor: premium.accent,
              backgroundColor: premium.accent.withValues(alpha: 0.12),
            ),
            child: Text(LocaleKeys.backup_restoreInPlace.tr()),
          ),
      ],
    );
  }
}
