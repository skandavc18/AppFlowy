import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_dropdown.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Settings ▸ Version history.
///
/// Everything about keeping earlier states of a page, a table, a folder or a
/// file: when a copy is taken, how many survive, how long they live and how
/// much room they may take.
class SettingsPageVersionsView extends StatefulWidget {
  const SettingsPageVersionsView({super.key});

  @override
  State<SettingsPageVersionsView> createState() =>
      _SettingsPageVersionsViewState();
}

class _SettingsPageVersionsViewState extends State<SettingsPageVersionsView> {
  PageVersionSettings get _settings => PageVersionSettings.instance;

  PageVersionPolicy get _policy => _settings.policy;

  PageVersionUsage? _usage;
  bool _sweeping = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onChanged);
    unawaited(_settings.ensureLoaded());
    unawaited(_measure());
  }

  @override
  void dispose() {
    _settings.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _measure() async {
    final usage = await PageVersionStore.instance.measureUsage();
    if (mounted) {
      setState(() => _usage = usage);
    }
  }

  Future<void> _apply(PageVersionPolicy policy) async {
    await _settings.update(policy);
    // A rule that only applied to the page in front of you would be no rule at
    // all, so the sweep runs over everything already stored.
    if (mounted) {
      setState(() => _sweeping = true);
    }
    await PageVersionStore.instance.pruneEverything(policy);
    await _measure();
    if (mounted) {
      setState(() => _sweeping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    final limited = !policy.keepEveryVersion;
    final automatic = policy.captureAutomatically;

    return SettingsBody(
      title: LocaleKeys.pageVersions_settingsTitle.tr(),
      description: LocaleKeys.pageVersions_settingsDescription.tr(),
      children: [
        SettingsCategory(
          title: LocaleKeys.pageVersions_settingsWhenTitle.tr(),
          description: LocaleKeys.pageVersions_settingsWhenDescription.tr(),
          children: [
            _Toggle(
              label: LocaleKeys.pageVersions_settingsAutomatic.tr(),
              description: LocaleKeys.pageVersions_settingsAutomaticHint.tr(),
              value: automatic,
              onChanged: (value) => unawaited(
                _apply(policy.copyWith(captureAutomatically: value)),
              ),
            ),
            _Toggle(
              label: LocaleKeys.pageVersions_settingsOnOpen.tr(),
              description: LocaleKeys.pageVersions_settingsOnOpenHint.tr(),
              enabled: automatic,
              value: policy.captureOnOpen,
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(captureOnOpen: value))),
            ),
            _Toggle(
              label: LocaleKeys.pageVersions_settingsOnClose.tr(),
              description: LocaleKeys.pageVersions_settingsOnCloseHint.tr(),
              enabled: automatic,
              value: policy.captureOnClose,
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(captureOnClose: value))),
            ),
            _Choice<int>(
              label: LocaleKeys.pageVersions_settingsQuiet.tr(),
              description: LocaleKeys.pageVersions_settingsQuietHint.tr(),
              enabled: automatic,
              value: policy.quietPeriod.inSeconds,
              entries: [
                for (final quiet in PageVersionPolicy.quietChoices)
                  DropdownMenuEntry(
                    value: quiet.inSeconds,
                    label: _spanLabel(quiet),
                  ),
              ],
              onChanged: (value) => unawaited(
                _apply(policy.copyWith(quietPeriod: Duration(seconds: value))),
              ),
            ),
            _Choice<int>(
              label: LocaleKeys.pageVersions_settingsInterval.tr(),
              description: LocaleKeys.pageVersions_settingsIntervalHint.tr(),
              enabled: automatic,
              value: policy.captureInterval.inSeconds,
              entries: [
                for (final interval in PageVersionPolicy.intervalChoices)
                  DropdownMenuEntry(
                    value: interval.inSeconds,
                    label: interval == Duration.zero
                        ? LocaleKeys.pageVersions_settingsIntervalNone.tr()
                        : _spanLabel(interval),
                  ),
              ],
              onChanged: (value) => unawaited(
                _apply(
                  policy.copyWith(captureInterval: Duration(seconds: value)),
                ),
              ),
            ),
            _Choice<int>(
              label: LocaleKeys.pageVersions_settingsSpacing.tr(),
              description: LocaleKeys.pageVersions_settingsSpacingHint.tr(),
              enabled: automatic,
              value: policy.minimumSpacing.inSeconds,
              entries: [
                for (final spacing in PageVersionPolicy.spacingChoices)
                  DropdownMenuEntry(
                    value: spacing.inSeconds,
                    label: spacing == Duration.zero
                        ? LocaleKeys.pageVersions_settingsSpacingNone.tr()
                        : _spanLabel(spacing),
                  ),
              ],
              onChanged: (value) => unawaited(
                _apply(
                  policy.copyWith(minimumSpacing: Duration(seconds: value)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsCategory(
          title: LocaleKeys.pageVersions_settingsKeepTitle.tr(),
          description: LocaleKeys.pageVersions_settingsKeepDescription.tr(),
          children: [
            _Toggle(
              label: LocaleKeys.pageVersions_settingsKeepAll.tr(),
              description: LocaleKeys.pageVersions_settingsKeepAllHint.tr(),
              value: policy.keepEveryVersion,
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(keepEveryVersion: value))),
            ),
            _Choice<int>(
              label: LocaleKeys.pageVersions_settingsCopies.tr(),
              description: LocaleKeys.pageVersions_settingsCopiesHint.tr(),
              enabled: limited,
              value: policy.maximumCopies,
              entries: [
                for (final count in PageVersionPolicy.copyChoices)
                  DropdownMenuEntry(
                    value: count,
                    label: LocaleKeys.pageVersions_settingsCopiesValue.tr(
                      args: ['$count'],
                    ),
                  ),
              ],
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(maximumCopies: value))),
            ),
            _Choice<int>(
              label: LocaleKeys.pageVersions_settingsDays.tr(),
              description: LocaleKeys.pageVersions_settingsDaysHint.tr(),
              enabled: limited,
              value: policy.retainedDays,
              entries: [
                for (final days in PageVersionPolicy.dayChoices)
                  DropdownMenuEntry(
                    value: days,
                    label: days == 0
                        ? LocaleKeys.pageVersions_settingsDaysForever.tr()
                        : LocaleKeys.pageVersions_settingsDaysValue.tr(
                            args: ['$days'],
                          ),
                  ),
              ],
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(retainedDays: value))),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsCategory(
          title: LocaleKeys.pageVersions_settingsRoomTitle.tr(),
          description: LocaleKeys.pageVersions_settingsRoomDescription.tr(),
          children: [
            _Choice<int>(
              label: LocaleKeys.pageVersions_settingsPageBytes.tr(),
              description: LocaleKeys.pageVersions_settingsPageBytesHint.tr(),
              enabled: limited,
              value: policy.maximumPageBytes,
              entries: [
                for (final bytes in PageVersionPolicy.pageByteChoices)
                  DropdownMenuEntry(
                    value: bytes,
                    label: bytes == 0
                        ? LocaleKeys.pageVersions_settingsNoLimit.tr()
                        : pageVersionSizeLabel(bytes),
                  ),
              ],
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(maximumPageBytes: value))),
            ),
            _Choice<int>(
              label: LocaleKeys.pageVersions_settingsTotalBytes.tr(),
              description: LocaleKeys.pageVersions_settingsTotalBytesHint.tr(),
              enabled: limited,
              value: policy.maximumTotalBytes,
              entries: [
                for (final bytes in PageVersionPolicy.totalByteChoices)
                  DropdownMenuEntry(
                    value: bytes,
                    label: bytes == 0
                        ? LocaleKeys.pageVersions_settingsNoLimit.tr()
                        : pageVersionSizeLabel(bytes),
                  ),
              ],
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(maximumTotalBytes: value))),
            ),
            _Choice<int>(
              label: LocaleKeys.pageVersions_settingsFileBytes.tr(),
              description: LocaleKeys.pageVersions_settingsFileBytesHint.tr(),
              value: policy.maximumFileBytes,
              entries: [
                for (final bytes in PageVersionPolicy.fileByteChoices)
                  DropdownMenuEntry(
                    value: bytes,
                    label: switch (bytes) {
                      0 => LocaleKeys.pageVersions_settingsFileBytesNever.tr(),
                      PageVersionPolicy.anySize =>
                        LocaleKeys.pageVersions_settingsFileBytesAny.tr(),
                      _ => pageVersionSizeLabel(bytes),
                    },
                  ),
              ],
              onChanged: (value) =>
                  unawaited(_apply(policy.copyWith(maximumFileBytes: value))),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsCategory(
          title: LocaleKeys.pageVersions_settingsLinkedTitle.tr(),
          description: LocaleKeys.pageVersions_settingsLinkedDescription.tr(),
          children: [
            _Toggle(
              label: LocaleKeys.pageVersions_settingsLinked.tr(),
              description: LocaleKeys.pageVersions_settingsLinkedHint.tr(),
              value: policy.readLinkedCollections,
              onChanged: (value) => unawaited(
                _apply(policy.copyWith(readLinkedCollections: value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsCategory(
          title: LocaleKeys.pageVersions_settingsStoredTitle.tr(),
          children: [
            _Usage(
              usage: _usage,
              sweeping: _sweeping,
              onSweep: () => _apply(_policy),
              onCleared: _measure,
            ),
          ],
        ),
      ],
    );
  }

  static String _spanLabel(Duration span) {
    if (span.inDays >= 1) {
      return LocaleKeys.pageVersions_settingsDaysValue.tr(
        args: ['${span.inDays}'],
      );
    }
    if (span.inHours >= 1) {
      return LocaleKeys.pageVersions_settingsHoursValue.tr(
        args: ['${span.inHours}'],
      );
    }
    if (span.inMinutes >= 1) {
      return LocaleKeys.pageVersions_settingsMinutesValue.tr(
        args: ['${span.inMinutes}'],
      );
    }
    return LocaleKeys.pageVersions_settingsSecondsValue.tr(
      args: ['${span.inSeconds}'],
    );
  }
}

/// A size written the way the settings offer it.
String pageVersionSizeLabel(int bytes) {
  const megabyte = PageVersionPolicy.megabyte;
  if (bytes >= 1024 * megabyte) {
    final gigabytes = bytes / (1024 * megabyte);
    return '${gigabytes.toStringAsFixed(gigabytes % 1 == 0 ? 0 : 1)} GB';
  }
  if (bytes >= megabyte) {
    return '${(bytes / megabyte).round()} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).round()} KB';
  }
  return '$bytes B';
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

class _Usage extends StatelessWidget {
  const _Usage({
    required this.usage,
    required this.sweeping,
    required this.onSweep,
    required this.onCleared,
  });

  final PageVersionUsage? usage;
  final bool sweeping;
  final Future<void> Function() onSweep;
  final Future<void> Function() onCleared;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final measured = usage;
    final summary = measured == null
        ? LocaleKeys.pageVersions_settingsMeasuring.tr()
        : measured.isEmpty
            ? LocaleKeys.pageVersions_settingsNothingStored.tr()
            : LocaleKeys.pageVersions_settingsUsage.tr(
                args: [
                  '${measured.versions}',
                  '${measured.pages}',
                  pageVersionSizeLabel(measured.bytes),
                ],
              );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                sweeping
                    ? LocaleKeys.pageVersions_settingsSweeping.tr()
                    : summary,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: premium.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: sweeping ? null : () => unawaited(onSweep()),
              icon: const Icon(Icons.cleaning_services_rounded, size: 15),
              label: Text(LocaleKeys.pageVersions_settingsSweepNow.tr()),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: measured == null || measured.isEmpty
                  ? null
                  : () => unawaited(_clear(context)),
              child: Text(LocaleKeys.pageVersions_settingsClear.tr()),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(LocaleKeys.pageVersions_settingsClear.tr()),
        content: Text(LocaleKeys.pageVersions_settingsClearBody.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(LocaleKeys.button_delete.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await PageVersionStore.instance.discardEverything();
    await onCleared();
  }
}
