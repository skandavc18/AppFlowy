// Settings ▸ Backup & sync ▸ Sync between computers.

import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/sync/server_settings_sync.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/sync/sync_settings.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/backup_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/sync_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_dropdown.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({super.key, this.serverPanel});

  /// The AppFlowy server card: right under the note on a workspace kept on
  /// the server, and after folder sync otherwise.
  final Widget? serverPanel;

  @override
  State<SyncSettingsSection> createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection> {
  WorkspaceSyncEngine get _engine => WorkspaceSyncEngine.instance;

  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onChanged);
    _engine.settings.addListener(_onChanged);
    unawaited(_engine.settings.ensureLoaded());
    // "Checked 20 seconds ago" has to keep up with the clock.
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => _onChanged());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _engine.removeListener(_onChanged);
    _engine.settings.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final binding = _engine.binding;
    final serverPanel = widget.serverPanel;
    final onServer = !_engine.canSyncThisWorkspace && binding == null;
    return SettingsCategory(
      title: LocaleKeys.sync_title.tr(),
      description: LocaleKeys.sync_description.tr(),
      children: [
        if (onServer) ...[
          SyncNoteBox(
            text: LocaleKeys.sync_cloudWorkspace.tr(),
            icon: Icons.cloud_done_outlined,
          ),
          if (serverPanel != null) ...[
            const SizedBox(height: 14),
            serverPanel,
          ],
          const SizedBox(height: 14),
          const _ServerSettingsPanel(),
        ] else if (binding == null)
          _SyncCard(
            destination: const BackupDestination(),
            title: LocaleKeys.sync_notSet.tr(),
            subtitle: LocaleKeys.sync_notSetHint.tr(),
            actions: [
              _AccentButton(
                label: LocaleKeys.sync_setUp.tr(),
                onPressed: _engine.isBusy
                    ? null
                    : () => unawaited(setUpWorkspaceSync(context)),
              ),
            ],
          )
        else if (!_engine.isBoundHere)
          _SyncCard(
            destination: binding.destination,
            title: _destinationTitle(binding.destination),
            subtitle: LocaleKeys.sync_statusOtherWorkspace
                .tr(args: [binding.workspaceName]),
            actions: [
              TextButton(
                onPressed: () => unawaited(_disconnect()),
                child: Text(LocaleKeys.sync_disconnectConfirm.tr()),
              ),
            ],
          )
        else
          ..._bound(context, binding),
        if (!onServer && serverPanel != null) ...[
          const SizedBox(height: 18),
          serverPanel,
        ],
      ],
    );
  }

  List<Widget> _bound(BuildContext context, SyncBinding binding) {
    final premium = PremiumThemeExtension.of(context);
    final phase = _engine.phase;
    final working = phase == SyncPhase.working || _engine.isBusy;
    final restored = _engine.restoredElsewhere;

    return [
      _SyncCard(
        destination: binding.destination,
        title: _destinationTitle(binding.destination),
        subtitle: _status(binding),
        failed: phase == SyncPhase.failed,
        busy: working,
        actions: [
          if (_engine.needsSignIn && binding.destination.kind.needsConnection)
            TextButton(
              onPressed: () async {
                if (await signInAgainForDestination(
                      context,
                      binding.destination,
                    ) &&
                    mounted) {
                  unawaited(_engine.syncNow());
                }
              },
              child: Text(LocaleKeys.backup_signInAgain.tr()),
            ),
          _AccentButton(
            label: LocaleKeys.sync_syncNow.tr(),
            onPressed: working ||
                    binding.paused ||
                    phase == SyncPhase.restoredElsewhere ||
                    phase == SyncPhase.locked
                ? null
                : () => unawaited(_engine.syncNow()),
          ),
        ],
      ),
      if (restored != null) ...[
        const SizedBox(height: 10),
        _Banner(
          icon: Icons.history_rounded,
          text: LocaleKeys.sync_restoredTitle.tr(),
          action: LocaleKeys.sync_restoredConfirm.tr(),
          onPressed: () =>
              unawaited(showRestoredElsewhereDialog(context, restored)),
        ),
      ] else if (phase == SyncPhase.locked) ...[
        const SizedBox(height: 10),
        _Banner(
          icon: Icons.lock_outline_rounded,
          text: _engine.passwordChangedElsewhere
              ? LocaleKeys.sync_lockedChangedBody.tr()
              : LocaleKeys.sync_lockedBody.tr(),
          action: LocaleKeys.sync_unlock.tr(),
          onPressed: () => unawaited(_unlock()),
        ),
      ] else if (binding.vaultId.isEmpty) ...[
        const SizedBox(height: 10),
        _Banner(
          icon: Icons.lock_open_rounded,
          text: LocaleKeys.sync_sealBody.tr(),
          action: LocaleKeys.sync_sealConfirm.tr(),
          onPressed: _engine.isBusy ? null : () => unawaited(_seal()),
        ),
      ] else if (binding.resealPending) ...[
        const SizedBox(height: 10),
        _Banner(
          icon: Icons.lock_reset_rounded,
          text: LocaleKeys.sync_resealBody.tr(),
          action: LocaleKeys.sync_resealConfirm.tr(),
          onPressed: _engine.isBusy ? null : () => unawaited(_seal()),
        ),
      ],
      const SizedBox(height: 14),
      SyncDevicesList(
        devices: _engine.devices,
        thisComputer: _engine.thisDeviceName,
      ),
      const SizedBox(height: 6),
      _IntervalRow(
        seconds: binding.intervalSeconds,
        enabled: !binding.paused,
        onChanged: (seconds) => unawaited(_engine.setInterval(seconds)),
      ),
      const SizedBox(height: 12),
      _ToggleRow(
        label: LocaleKeys.sync_encryptToggle.tr(),
        hint: LocaleKeys.sync_encryptToggleHint.tr(),
        value: binding.vaultId.isNotEmpty,
        enabled: !_engine.isBusy && phase != SyncPhase.locked,
        onChanged: (on) => unawaited(on ? _seal() : _unseal()),
      ),
      const SizedBox(height: 12),
      _ToggleRow(
        label: LocaleKeys.sync_settingsToggle.tr(),
        hint: LocaleKeys.sync_settingsToggleHint.tr(),
        value: binding.syncPreferences,
        enabled: !_engine.isBusy && binding.vaultId.isNotEmpty,
        onChanged: (on) => unawaited(_engine.setSyncPreferences(on)),
      ),
      const SizedBox(height: 12),
      _ToggleRow(
        label: LocaleKeys.sync_credentialsToggle.tr(),
        hint: LocaleKeys.sync_credentialsToggleHint.tr(),
        value: _engine.credentialsSynced,
        enabled: !_engine.isBusy &&
            binding.vaultId.isNotEmpty &&
            phase != SyncPhase.locked,
        onChanged: (on) => unawaited(_setCredentials(on)),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          TextButton.icon(
            onPressed: _engine.isBusy
                ? null
                : () => unawaited(_engine.setPaused(!binding.paused)),
            icon: Icon(
              binding.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 16,
            ),
            label: Text(
              binding.paused
                  ? LocaleKeys.sync_resume.tr()
                  : LocaleKeys.sync_pause.tr(),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _engine.isBusy ? null : () => unawaited(_disconnect()),
            style: TextButton.styleFrom(
              foregroundColor: premium.textSecondary,
            ),
            child: Text(LocaleKeys.sync_disconnect.tr()),
          ),
        ],
      ),
    ];
  }

  String _status(SyncBinding binding) {
    if (binding.paused) {
      return LocaleKeys.sync_statusPaused.tr();
    }
    switch (_engine.phase) {
      case SyncPhase.working:
        return _engine.activity.isEmpty
            ? LocaleKeys.sync_statusWorking.tr()
            : _engine.activity;
      case SyncPhase.failed:
        return LocaleKeys.sync_statusFailed.tr(
          args: [
            binding.lastError.isNotEmpty ? binding.lastError : _engine.activity,
          ],
        );
      case SyncPhase.restoredElsewhere:
        return LocaleKeys.sync_restoredTitle.tr();
      case SyncPhase.locked:
        return LocaleKeys.sync_statusLocked.tr();
      case SyncPhase.off:
      case SyncPhase.idle:
      case SyncPhase.paused:
        final last = binding.lastSyncedAt;
        return last == null
            ? LocaleKeys.sync_statusNever.tr()
            : LocaleKeys.sync_statusChecked.tr(args: [_ago(last)]);
    }
  }

  Future<void> _unlock() => askAppPassword(
        context,
        question: _engine.passwordChangedElsewhere
            ? AppPasswordQuestion.changedElsewhere
            : AppPasswordQuestion.typeForFolder,
        check: (password) async {
          try {
            await _engine.unlock(password);
            return null;
          } on SyncError catch (error) {
            return error.detail;
          }
        },
      );

  /// Seals the folder with the AppFlowy password — choosing one first when
  /// this computer has none.
  Future<void> _seal() async {
    final password = await ensureAppPassword(context);
    if (password == null || !mounted) {
      return;
    }
    final sealed = await runWithSyncProgress(
      context,
      title: LocaleKeys.sync_sealing.tr(),
      work: () async {
        await _engine.sealWithAppPassword();
        return true;
      },
    );
    if (sealed == true && mounted) {
      reportBackupOutcome(
        context: context,
        succeeded: true,
        message: LocaleKeys.sync_sealed.tr(),
      );
    }
  }

  /// Turns sync folder encryption off after confirming and verifying the
  /// AppFlowy password when one is set.
  Future<void> _unseal() async {
    final confirmed = await confirmSyncStep(
      context,
      title: LocaleKeys.sync_unsealTitle.tr(),
      body: LocaleKeys.sync_unsealBody.tr(),
      note: LocaleKeys.sync_unsealWarning.tr(),
      confirm: LocaleKeys.sync_unsealConfirm.tr(),
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final passwords = AppPassword.instance;
    await passwords.ensureLoaded();
    if (!mounted) {
      return;
    }
    if (passwords.isSet) {
      final verified = await askAppPassword(
        context,
        question: AppPasswordQuestion.typeHere,
        check: (password) async => await passwords.check(password)
            ? null
            : LocaleKeys.appPassword_wrong.tr(),
      );
      if (verified == null || !mounted) {
        return;
      }
    }
    final unsealed = await runWithSyncProgress(
      context,
      title: LocaleKeys.sync_unsealing.tr(),
      work: () async {
        await _engine.unsealSyncFolder();
        return true;
      },
    );
    if (unsealed == true && mounted) {
      reportBackupOutcome(
        context: context,
        succeeded: true,
        message: LocaleKeys.sync_unsealed.tr(),
      );
    }
  }

  Future<void> _setCredentials(bool on) async {
    if (!on) {
      final confirmed = await confirmSyncStep(
        context,
        title: LocaleKeys.sync_credentialsOffTitle.tr(),
        body: LocaleKeys.sync_credentialsOffBody.tr(),
        confirm: LocaleKeys.sync_credentialsOffConfirm.tr(),
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    await runWithSyncProgress(
      context,
      title: on
          ? LocaleKeys.sync_credentialsToggle.tr()
          : LocaleKeys.sync_credentialsOffConfirm.tr(),
      work: () async {
        await _engine.setSyncCredentials(on);
        return true;
      },
    );
  }

  Future<void> _disconnect() async {
    final confirmed = await confirmSyncStep(
      context,
      title: LocaleKeys.sync_disconnectTitle.tr(),
      body: LocaleKeys.sync_disconnectBody.tr(),
      confirm: LocaleKeys.sync_disconnectConfirm.tr(),
    );
    if (confirmed) {
      await _engine.disconnect();
    }
  }

  static String _destinationTitle(BackupDestination destination) {
    final where = switch (destination.kind) {
      BackupDestinationKind.folder => destination.localPath,
      _ => destination.folderName.isEmpty
          ? destination.accountLabel
          : '${destination.folderName} · ${destination.accountLabel}',
    };
    return '${backupDestinationLabel(destination.kind)} · $where';
  }
}

/// "12 seconds ago", "3 minutes ago", or a date for anything older than a day.
String _ago(DateTime moment) {
  final elapsed = DateTime.now().difference(moment);
  if (elapsed.inDays >= 1) {
    return DateFormat.yMMMd().add_jm().format(moment);
  }
  return DateFormat.jm().format(moment);
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.destination,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.failed = false,
    this.busy = false,
  });

  final BackupDestination destination;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final bool failed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final accent = destination.isSet
        ? backupDestinationAccent(destination.kind)
        : premium.accent;

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
              child: busy
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  : Icon(
                      destination.isSet
                          ? backupDestinationIcon(destination.kind)
                          : Icons.sync_rounded,
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: premium.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: failed
                        ? const Color(0xFFD9534F)
                        : premium.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ...actions,
        ],
      ),
    );
  }
}

class _AccentButton extends StatelessWidget {
  const _AccentButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: premium.accent,
        backgroundColor: premium.accent.withValues(alpha: 0.12),
      ),
      child: Text(label),
    );
  }
}

/// Every computer and phone syncing through the folder.
class SyncDevicesList extends StatelessWidget {
  const SyncDevicesList({
    super.key,
    required this.devices,
    required this.thisComputer,
  });

  final List<SyncDeviceSummary> devices;
  final String thisComputer;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    // This computer is always one of them, even before the first round has
    // read the folder.
    final shown = [
      if (!devices.any((device) => device.isThisComputer))
        SyncDeviceSummary(
          id: '',
          name: thisComputer,
          isThisComputer: true,
          platform: _platformOfThisComputer,
        ),
      ...devices,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.sync_devicesTitle.tr(args: ['${shown.length}']),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: premium.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          LocaleKeys.sync_devicesHint.tr(),
          style: TextStyle(fontSize: 12, color: premium.textSecondary),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: premium.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: premium.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) Divider(height: 1, color: premium.border),
                _DeviceRow(device: shown[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String get _platformOfThisComputer => Platform.operatingSystem;
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final SyncDeviceSummary device;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final platform = _platformName(device.platform);
    final joined = device.joinedAt;
    final details = [
      if (platform.isNotEmpty) platform,
      if (joined != null && joined.millisecondsSinceEpoch > 0)
        LocaleKeys.sync_deviceLinked
            .tr(args: [DateFormat.yMMMd().format(joined.toLocal())]),
    ].join(' · ');
    final lastSeen = device.lastSeen;
    final status = device.waiting
        ? LocaleKeys.sync_deviceWaiting.tr()
        : lastSeen == null
            ? LocaleKeys.sync_deviceNotYet.tr()
            : LocaleKeys.sync_deviceSynced.tr(args: [_ago(lastSeen.toLocal())]);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: premium.hover,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              switch (device.platform) {
                'android' || 'ios' => Icons.smartphone_rounded,
                'macos' || 'linux' || 'windows' => Icons.laptop_rounded,
                _ => Icons.devices_rounded,
              },
              size: 17,
              color: premium.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: premium.textPrimary,
                        ),
                      ),
                    ),
                    if (device.isThisComputer) ...[
                      const SizedBox(width: 6),
                      _Tag(text: LocaleKeys.sync_thisComputer.tr()),
                    ],
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: premium.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (device.waiting) ...[
                Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: premium.textSecondary,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                status,
                style: TextStyle(fontSize: 11.5, color: premium.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
    return device.waiting
        ? Tooltip(message: LocaleKeys.sync_deviceWaitingHint.tr(), child: row)
        : row;
  }

  static String _platformName(String platform) => switch (platform) {
        'linux' => 'Linux',
        'windows' => 'Windows',
        'macos' => 'macOS',
        'android' => 'Android',
        'ios' => 'iOS',
        _ => '',
      };
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: premium.hover,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, color: premium.textSecondary),
      ),
    );
  }
}

/// A switch with what it does beside it.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

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
                  hint,
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

/// A line that needs somebody to do something, with the thing to do.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: premium.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: premium.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: premium.textPrimary,
              ),
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}

class _IntervalRow extends StatelessWidget {
  const _IntervalRow({
    required this.seconds,
    required this.enabled,
    required this.onChanged,
  });

  final int seconds;
  final bool enabled;
  final ValueChanged<int> onChanged;

  static String label(int seconds) {
    if (seconds < 60) {
      return LocaleKeys.sync_intervalSeconds.tr(args: ['$seconds']);
    }
    if (seconds == 60) {
      return LocaleKeys.sync_intervalMinute.tr();
    }
    return LocaleKeys.sync_intervalMinutes.tr(args: ['${seconds ~/ 60}']);
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final choices = {...syncIntervalChoices, seconds}.toList()..sort();
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
                  LocaleKeys.sync_interval.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: premium.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  LocaleKeys.sync_intervalHint.tr(),
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
              child: SettingsDropdown<int>(
                key: ValueKey('sync-interval-$seconds'),
                selectedOption: seconds,
                options: [
                  for (final choice in choices)
                    DropdownMenuEntry(value: choice, label: label(choice)),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings, accounts and keys that follow the account on an AppFlowy server.
class _ServerSettingsPanel extends StatefulWidget {
  const _ServerSettingsPanel();

  @override
  State<_ServerSettingsPanel> createState() => _ServerSettingsPanelState();
}

class _ServerSettingsPanelState extends State<_ServerSettingsPanel> {
  ServerSettingsSync get _server => ServerSettingsSync.instance;

  @override
  void initState() {
    super.initState();
    _server.addListener(_onChanged);
  }

  @override
  void dispose() {
    _server.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _server.phase;
    if (phase == ServerSettingsPhase.off) {
      return const SizedBox.shrink();
    }
    final busy = _server.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SyncCard(
          destination: const BackupDestination(),
          title: LocaleKeys.sync_serverTitle.tr(),
          subtitle: switch (phase) {
            ServerSettingsPhase.notSetUp => LocaleKeys.sync_serverNotSetUp.tr(),
            ServerSettingsPhase.locked => _server.passwordChangedElsewhere
                ? LocaleKeys.sync_lockedChangedBody.tr()
                : LocaleKeys.sync_lockedBody.tr(),
            ServerSettingsPhase.working => LocaleKeys.sync_statusWorking.tr(),
            ServerSettingsPhase.failed =>
              LocaleKeys.sync_statusFailed.tr(args: [_server.lastError]),
            _ => _server.lastSyncedAt == null
                ? LocaleKeys.sync_statusNever.tr()
                : LocaleKeys.sync_statusChecked
                    .tr(args: [_ago(_server.lastSyncedAt!)]),
          },
          failed: phase == ServerSettingsPhase.failed,
          busy: busy,
          actions: [
            switch (phase) {
              ServerSettingsPhase.notSetUp => _AccentButton(
                  label: LocaleKeys.sync_serverSetUp.tr(),
                  onPressed: () => unawaited(_setUp()),
                ),
              ServerSettingsPhase.locked => _AccentButton(
                  label: LocaleKeys.sync_unlock.tr(),
                  onPressed: () => unawaited(_unlock()),
                ),
              _ => _AccentButton(
                  label: LocaleKeys.sync_syncNow.tr(),
                  onPressed: busy ? null : () => unawaited(_server.syncNow()),
                ),
            },
          ],
        ),
        if (phase == ServerSettingsPhase.idle ||
            phase == ServerSettingsPhase.working ||
            phase == ServerSettingsPhase.failed) ...[
          const SizedBox(height: 14),
          _ToggleRow(
            label: LocaleKeys.sync_settingsToggle.tr(),
            hint: LocaleKeys.sync_settingsToggleHint.tr(),
            value: _server.syncsHere,
            enabled: !busy,
            onChanged: (on) => unawaited(_server.setSyncHere(on)),
          ),
          const SizedBox(height: 12),
          _ToggleRow(
            label: LocaleKeys.sync_credentialsToggle.tr(),
            hint: LocaleKeys.sync_credentialsToggleHint.tr(),
            value: _server.credentialsSynced,
            enabled: !busy,
            onChanged: (on) => unawaited(_setCredentials(on)),
          ),
        ],
      ],
    );
  }

  Future<void> _setUp() async {
    final password = await ensureAppPassword(context);
    if (password == null || !mounted) {
      return;
    }
    final problem = await _attempt(_server.setUp);
    if (problem != null && mounted) {
      await showSyncNotice(
        context,
        title: LocaleKeys.sync_serverTitle.tr(),
        body: problem,
      );
    }
  }

  Future<void> _unlock() => askAppPassword(
        context,
        question: _server.passwordChangedElsewhere
            ? AppPasswordQuestion.changedElsewhere
            : AppPasswordQuestion.typeForServer,
        check: (password) => _attempt(() => _server.unlock(password)),
      );

  static Future<String?> _attempt(Future<void> Function() work) async {
    try {
      await work();
      return null;
    } on SyncError catch (error) {
      return error.detail;
    } on Object catch (error) {
      return describeSyncError(error);
    }
  }

  Future<void> _setCredentials(bool on) async {
    if (!on) {
      final confirmed = await confirmSyncStep(
        context,
        title: LocaleKeys.sync_credentialsOffTitle.tr(),
        body: LocaleKeys.sync_serverCredentialsOffBody.tr(),
        confirm: LocaleKeys.sync_credentialsOffConfirm.tr(),
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    await _server.setSyncCredentials(on);
  }
}
