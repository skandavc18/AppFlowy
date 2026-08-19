// Settings ▸ Backup.
//
// Where copies go, when they are taken, what goes in them, how hard they are
// squeezed — separately for the copy that stays here and the copy that is sent
// away — and whether they are sealed before they leave.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/backup_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_dropdown.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';

class SettingsBackupView extends StatefulWidget {
  const SettingsBackupView({super.key});

  @override
  State<SettingsBackupView> createState() => _SettingsBackupViewState();
}

class _SettingsBackupViewState extends State<SettingsBackupView> {
  BackupSettings get _settings => BackupSettings.instance;

  BackupService get _service => BackupService.instance;

  BackupPolicy get _policy => _settings.policy;

  List<BackupCopy>? _copies;
  String? _listingFailure;
  bool _listing = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onChanged);
    _service.addListener(_onChanged);
    unawaited(_settings.ensureLoaded().then((_) => _refresh()));
  }

  @override
  void dispose() {
    _settings.removeListener(_onChanged);
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _apply(BackupPolicy policy) => _settings.update(policy);

  Future<void> _refresh() async {
    if (!_policy.destination.isReady) {
      if (mounted) {
        setState(() {
          _copies = const [];
          _listingFailure = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _listing = true;
        _listingFailure = null;
      });
    }
    try {
      final copies = await _service.listCopies();
      if (mounted) {
        setState(() {
          _copies = copies;
          _listing = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _listing = false;
          _listingFailure = error is BackupTargetError
              ? error.detail
              : error is BackupError
                  ? error.detail
                  : error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    final remote = policy.destination.kind.isRemote;

    return SettingsBody(
      title: LocaleKeys.backup_settingsTitle.tr(),
      description: LocaleKeys.backup_settingsDescription.tr(),
      children: [
        SettingsCategory(
          title: LocaleKeys.backup_whereTitle.tr(),
          description: LocaleKeys.backup_whereDescription.tr(),
          children: [
            _DestinationCard(
              destination: policy.destination,
              onChange: () async {
                final chosen = await chooseBackupDestination(
                  context,
                  current: policy.destination,
                );
                if (chosen == null) {
                  return;
                }
                await _apply(_policy.copyWith(destination: chosen));
                await _refresh();
              },
            ),
            const SizedBox(height: 14),
            _Toggle(
              label: LocaleKeys.backup_enabled.tr(),
              description: LocaleKeys.backup_enabledHint.tr(),
              value: policy.enabled,
              enabled: policy.destination.isReady,
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(enabled: value))),
            ),
            _Choice<BackupSchedule>(
              label: LocaleKeys.backup_schedule.tr(),
              description: LocaleKeys.backup_scheduleHint.tr(),
              value: policy.schedule,
              enabled: policy.enabled,
              entries: [
                for (final schedule in BackupSchedule.values)
                  DropdownMenuEntry(
                    value: schedule,
                    label: _scheduleLabel(schedule),
                  ),
              ],
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(schedule: value))),
            ),
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.backup_contentsTitle.tr(),
          description: LocaleKeys.backup_contentsDescription.tr(),
          children: [
            for (final part in BackupPart.values)
              _Toggle(
                label: _partLabel(part),
                description: _partHint(part),
                value: policy.parts.contains(part),
                // A backup of nothing is not a backup: the last part standing
                // cannot be turned off.
                enabled: !(policy.parts.length == 1 &&
                    policy.parts.contains(part)),
                onChanged: (value) => unawaited(
                  _apply(
                    policy.copyWith(
                      parts: {
                        for (final existing in policy.parts)
                          if (existing != part) existing,
                        if (value) part,
                      },
                    ),
                  ),
                ),
              ),
            _Choice<int>(
              label: LocaleKeys.backup_maximumFile.tr(),
              description: LocaleKeys.backup_maximumFileHint.tr(),
              value: policy.maximumFileBytes,
              entries: [
                for (final bytes in BackupPolicy.fileSizeChoices)
                  DropdownMenuEntry(
                    value: bytes,
                    label: bytes == BackupPolicy.anySize
                        ? LocaleKeys.backup_maximumFileAny.tr()
                        : backupSizeLabel(bytes),
                  ),
              ],
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(maximumFileBytes: value))),
            ),
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.backup_compressionTitle.tr(),
          description: LocaleKeys.backup_compressionDescription.tr(),
          children: [
            _Choice<BackupCompression>(
              label: LocaleKeys.backup_localCompression.tr(),
              description: LocaleKeys.backup_localCompressionHint.tr(),
              value: policy.localCompression,
              entries: _compressionEntries,
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(localCompression: value))),
            ),
            _Choice<BackupCompression>(
              label: LocaleKeys.backup_remoteCompression.tr(),
              description: LocaleKeys.backup_remoteCompressionHint.tr(),
              value: policy.remoteCompression,
              enabled: remote,
              entries: _compressionEntries,
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(remoteCompression: value))),
            ),
            if (policy.needsTwoArchives)
              _Note(text: LocaleKeys.backup_compressionTwice.tr()),
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.backup_sealingTitle.tr(),
          description: LocaleKeys.backup_sealingDescription.tr(),
          children: [
            _Toggle(
              label: LocaleKeys.backup_encrypt.tr(),
              description: LocaleKeys.backup_encryptHint.tr(),
              value: policy.encrypt,
              onChanged: (value) async {
                if (!value) {
                  await showRemoveBackupPassphraseDialog(context);
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                await showSetBackupPassphraseDialog(context);
              },
            ),
            if (policy.encrypt) ...[
              const SizedBox(height: 12),
              _SealState(
                unlocked: _settings.isUnlocked,
                onUnlock: () async {
                  await showUnlockBackupDialog(context);
                },
                onLock: _settings.lock,
                onChange: () async {
                  await showChangeBackupPassphraseDialog(context);
                },
              ),
            ],
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.backup_keepTitle.tr(),
          description: LocaleKeys.backup_keepDescription.tr(),
          children: [
            if (remote) ...[
              _Toggle(
                label: LocaleKeys.backup_keepLocalCopy.tr(),
                description: LocaleKeys.backup_keepLocalCopyHint.tr(),
                value: policy.keepLocalCopy,
                onChanged: (value) =>
                    unawaited(_apply(policy.copyWith(keepLocalCopy: value))),
              ),
              _Action(
                label: LocaleKeys.backup_localFolder.tr(),
                description: policy.localCopyPath.isEmpty
                    ? LocaleKeys.backup_localFolderDefault.tr()
                    : policy.localCopyPath,
                icon: Icons.folder_open_rounded,
                enabled: policy.keepLocalCopy,
                onPressed: () async {
                  final path =
                      await getIt<FilePickerService>().getDirectoryPath();
                  if (path == null || path.isEmpty) {
                    return;
                  }
                  await _apply(_policy.copyWith(localCopyPath: path));
                },
              ),
            ],
            _Choice<int>(
              label: remote
                  ? LocaleKeys.backup_localCopies.tr()
                  : LocaleKeys.backup_copiesKept.tr(),
              description: LocaleKeys.backup_localCopiesHint.tr(),
              value: policy.localCopies,
              enabled: !remote || policy.keepLocalCopy,
              entries: _copyEntries,
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(localCopies: value))),
            ),
            if (remote)
              _Choice<int>(
                label: LocaleKeys.backup_remoteCopies.tr(),
                description: LocaleKeys.backup_remoteCopiesHint.tr(),
                value: policy.remoteCopies,
                entries: _copyEntries,
                onChanged: (value) =>
                    unawaited(_apply(policy.copyWith(remoteCopies: value))),
              ),
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.backup_nowTitle.tr(),
          description: LocaleKeys.backup_nowDescription.tr(),
          children: [
            _RunRow(
              policy: policy,
              progress: _service.progress,
              outcome: _settings.lastOutcome,
              onRun: _runNow,
            ),
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.backup_copiesTitle.tr(),
          description: policy.destination.kind.canListRemotely
              ? LocaleKeys.backup_copiesDescription.tr()
              : LocaleKeys.backup_copiesDescriptionCloud.tr(),
          children: [
            _CopiesList(
              copies: _copies,
              listing: _listing,
              failure: _listingFailure,
              onRefresh: _refresh,
              onRestore: _restore,
              onRemove: _remove,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _runNow() async {
    try {
      final outcome = await _service.runNow();
      if (!mounted) {
        return;
      }
      reportBackupOutcome(
        context: context,
        succeeded: outcome.succeeded,
        message: outcome.succeeded
            ? LocaleKeys.backup_ranMessage
                .tr(args: [backupSizeLabel(outcome.bytes)])
            : outcome.detail,
      );
      await _refresh();
    } on BackupError catch (error) {
      if (!mounted) {
        return;
      }
      if (error.needsPassphrase) {
        final unlocked = await showUnlockBackupDialog(context);
        if (unlocked && mounted) {
          await _runNow();
        }
        return;
      }
      reportBackupOutcome(
        context: context,
        succeeded: false,
        message: error.detail,
      );
    } on Object catch (error) {
      if (mounted) {
        reportBackupOutcome(
          context: context,
          succeeded: false,
          message: error.toString(),
        );
      }
    }
  }

  Future<void> _restore(BackupCopy copy) async {
    final folder = await getIt<FilePickerService>().getDirectoryPath();
    if (folder == null || folder.isEmpty || !mounted) {
      return;
    }

    Uint8List? key;
    final manifest = copy.manifest;
    if (manifest != null && manifest.encrypted) {
      key = await askForBackupPassphrase(context, manifest: manifest);
      if (key == null || !mounted) {
        return;
      }
    }

    try {
      final result = await _service.restore(
        copy: copy,
        into: Directory(folder),
        key: key,
      );
      if (!mounted) {
        return;
      }
      reportBackupOutcome(
        context: context,
        succeeded: true,
        message: LocaleKeys.backup_restoredMessage.tr(
          args: ['${result.fileCount}', result.dataFolder.path],
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        reportBackupOutcome(
          context: context,
          succeeded: false,
          message: error is BackupError ? error.detail : error.toString(),
        );
      }
    }
  }

  Future<void> _remove(BackupCopy copy) async {
    try {
      await _service.removeCopy(copy);
      await _refresh();
    } on Object catch (error) {
      if (mounted) {
        reportBackupOutcome(
          context: context,
          succeeded: false,
          message: error.toString(),
        );
      }
    }
  }

  static List<DropdownMenuEntry<BackupCompression>> get _compressionEntries => [
        for (final level in BackupCompression.values)
          DropdownMenuEntry(value: level, label: _compressionLabel(level)),
      ];

  static List<DropdownMenuEntry<int>> get _copyEntries => [
        for (final count in BackupPolicy.copyChoices)
          DropdownMenuEntry(
            value: count,
            label: count == BackupPolicy.keepEveryCopy
                ? LocaleKeys.backup_copiesEvery.tr()
                : LocaleKeys.backup_copiesCount.tr(args: ['$count']),
          ),
      ];

  static String _compressionLabel(BackupCompression level) => switch (level) {
        BackupCompression.none => LocaleKeys.backup_compressionNone.tr(),
        BackupCompression.fast => LocaleKeys.backup_compressionFast.tr(),
        BackupCompression.balanced =>
          LocaleKeys.backup_compressionBalanced.tr(),
        BackupCompression.maximum => LocaleKeys.backup_compressionMaximum.tr(),
      };

  static String _scheduleLabel(BackupSchedule schedule) => switch (schedule) {
        BackupSchedule.manual => LocaleKeys.backup_scheduleManual.tr(),
        BackupSchedule.onClose => LocaleKeys.backup_scheduleOnClose.tr(),
        BackupSchedule.hourly => LocaleKeys.backup_scheduleHourly.tr(),
        BackupSchedule.daily => LocaleKeys.backup_scheduleDaily.tr(),
        BackupSchedule.weekly => LocaleKeys.backup_scheduleWeekly.tr(),
      };

  static String _partLabel(BackupPart part) => switch (part) {
        BackupPart.workspace => LocaleKeys.backup_partWorkspace.tr(),
        BackupPart.attachments => LocaleKeys.backup_partAttachments.tr(),
        BackupPart.pageVersions => LocaleKeys.backup_partPageVersions.tr(),
        BackupPart.preferences => LocaleKeys.backup_partPreferences.tr(),
      };

  static String _partHint(BackupPart part) => switch (part) {
        BackupPart.workspace => LocaleKeys.backup_partWorkspaceHint.tr(),
        BackupPart.attachments => LocaleKeys.backup_partAttachmentsHint.tr(),
        BackupPart.pageVersions => LocaleKeys.backup_partPageVersionsHint.tr(),
        BackupPart.preferences => LocaleKeys.backup_partPreferencesHint.tr(),
      };
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination, required this.onChange});

  final BackupDestination destination;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final accent = backupDestinationAccent(destination.kind);
    final where = switch (destination.kind) {
      BackupDestinationKind.none => LocaleKeys.backup_destinationNoneHint.tr(),
      BackupDestinationKind.folder => destination.localPath,
      BackupDestinationKind.appflowyCloud =>
        LocaleKeys.backup_destinationCloudHint.tr(),
      _ => destination.folderName.isEmpty
          ? destination.accountLabel
          : '${destination.folderName} · ${destination.accountLabel}',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: premium.hover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              widthFactor: 1,
              child: Icon(
                backupDestinationIcon(destination.kind),
                size: 18,
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
                  backupDestinationLabel(destination.kind),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: premium.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  where,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              foregroundColor: premium.accent,
              backgroundColor: premium.accent.withValues(alpha: 0.12),
            ),
            child: Text(
              destination.isSet
                  ? LocaleKeys.backup_changeDestination.tr()
                  : LocaleKeys.backup_chooseDestination.tr(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SealState extends StatelessWidget {
  const _SealState({
    required this.unlocked,
    required this.onUnlock,
    required this.onLock,
    required this.onChange,
  });

  final bool unlocked;
  final Future<void> Function() onUnlock;
  final VoidCallback onLock;
  final Future<void> Function() onChange;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Row(
      children: [
        Icon(
          unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
          size: 16,
          color: premium.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            unlocked
                ? LocaleKeys.backup_sealUnlocked.tr()
                : LocaleKeys.backup_sealLocked.tr(),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: premium.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: unlocked ? onLock : () => unawaited(onUnlock()),
          child: Text(
            unlocked
                ? LocaleKeys.backup_lockNow.tr()
                : LocaleKeys.backup_unlockConfirm.tr(),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(onChange()),
          child: Text(LocaleKeys.backup_changePassphrase.tr()),
        ),
      ],
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({
    required this.policy,
    required this.progress,
    required this.outcome,
    required this.onRun,
  });

  final BackupPolicy policy;
  final BackupProgress progress;
  final BackupOutcome? outcome;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final running = progress.isRunning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                running ? _stageLabel(progress) : _lastLabel(outcome),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: premium.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: running || !policy.destination.isReady
                  ? null
                  : () => unawaited(onRun()),
              style: TextButton.styleFrom(
                foregroundColor: premium.accent,
                backgroundColor: premium.accent.withValues(alpha: 0.12),
              ),
              child: Text(LocaleKeys.backup_runNow.tr()),
            ),
          ],
        ),
        if (running) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 4,
              backgroundColor: premium.border,
            ),
          ),
        ],
      ],
    );
  }

  static String _stageLabel(BackupProgress progress) => switch (progress.stage) {
        BackupStage.gathering => LocaleKeys.backup_stageGathering.tr(),
        BackupStage.sealing => LocaleKeys.backup_stageSealing.tr(),
        BackupStage.sending => LocaleKeys.backup_stageSending.tr(),
        BackupStage.keeping => LocaleKeys.backup_stageKeeping.tr(),
        BackupStage.tidying => LocaleKeys.backup_stageTidying.tr(),
        _ => LocaleKeys.backup_stageWorking.tr(),
      };

  static String _lastLabel(BackupOutcome? outcome) {
    if (outcome == null) {
      return LocaleKeys.backup_neverRun.tr();
    }
    final moment = DateFormat.yMMMd().add_jm().format(outcome.at);
    return outcome.succeeded
        ? LocaleKeys.backup_lastSucceeded
            .tr(args: [moment, backupSizeLabel(outcome.bytes)])
        : LocaleKeys.backup_lastFailed.tr(args: [moment, outcome.detail]);
  }
}

class _CopiesList extends StatelessWidget {
  const _CopiesList({
    required this.copies,
    required this.listing,
    required this.failure,
    required this.onRefresh,
    required this.onRestore,
    required this.onRemove,
  });

  final List<BackupCopy>? copies;
  final bool listing;
  final String? failure;
  final Future<void> Function() onRefresh;
  final Future<void> Function(BackupCopy) onRestore;
  final Future<void> Function(BackupCopy) onRemove;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final found = copies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                listing
                    ? LocaleKeys.backup_copiesLoading.tr()
                    : failure ??
                        (found == null || found.isEmpty
                            ? LocaleKeys.backup_copiesNone.tr()
                            : LocaleKeys.backup_copiesCounted
                                .tr(args: ['${found.length}'])),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: failure == null
                      ? premium.textSecondary
                      : const Color(0xFFD9534F),
                ),
              ),
            ),
            TextButton(
              onPressed: listing ? null : () => unawaited(onRefresh()),
              child: Text(LocaleKeys.backup_refresh.tr()),
            ),
          ],
        ),
        if (found != null && found.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final copy in found)
            _CopyRow(
              copy: copy,
              onRestore: () => unawaited(onRestore(copy)),
              onRemove: () => unawaited(onRemove(copy)),
            ),
        ],
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.copy,
    required this.onRestore,
    required this.onRemove,
  });

  final BackupCopy copy;
  final VoidCallback onRestore;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final manifest = copy.manifest;
    final facts = <String>[
      backupSizeLabel(copy.bytes),
      if (manifest != null)
        LocaleKeys.backup_copyFiles.tr(args: ['${manifest.fileCount}']),
      if (copy.isSealed) LocaleKeys.backup_copySealed.tr(),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            copy.isSealed ? Icons.lock_rounded : Icons.archive_rounded,
            size: 16,
            color: premium.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMd().add_jm().format(copy.takenAt.toLocal()),
                  style: TextStyle(fontSize: 13, color: premium.textPrimary),
                ),
                const SizedBox(height: 1),
                Text(
                  facts.join(' · '),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: premium.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRestore,
            child: Text(LocaleKeys.backup_restore.tr()),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: LocaleKeys.button_delete.tr(),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 17,
              color: premium.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: premium.textSecondary,
          ),
          const SizedBox(width: 7),
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

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.description,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final String description;
  final IconData icon;
  final Future<void> Function() onPressed;
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
          TextButton.icon(
            onPressed: enabled ? () => unawaited(onPressed()) : null,
            icon: Icon(icon, size: 16),
            label: Text(LocaleKeys.backup_choose.tr()),
          ),
        ],
      ),
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
          SizedBox(
            width: 200,
            child: IgnorePointer(
              ignoring: !enabled,
              child: SettingsDropdown<T>(
                // The dropdown reads its label once, so a fresh one is built
                // whenever the chosen value changes.
                key: ValueKey('$label-$value'),
                selectedOption: value,
                options: entries,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
