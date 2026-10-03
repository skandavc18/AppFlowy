import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/workflows/application/workflow_background.dart';
import 'package:appflowy/workflows/application/workflow_manager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'workflow_style.dart';

/// How workflows live alongside the window: closing to the notification area,
/// starting with Windows, failure notices and the master pause.
Future<void> showWorkflowBackgroundDialog(
  BuildContext context, {
  WorkflowManager? manager,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (_) => WorkflowBackgroundDialog(
        manager: manager ?? WorkflowManager.instance,
      ),
    );

class WorkflowBackgroundDialog extends StatelessWidget {
  const WorkflowBackgroundDialog({super.key, required this.manager});

  final WorkflowManager manager;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: palette.shadowColor.withValues(
                  alpha: palette.isDark ? 0.5 : 0.16,
                ),
                blurRadius: 40,
                spreadRadius: -12,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ListenableBuilder(
            listenable: Listenable.merge([manager, manager.store]),
            builder: (context, _) {
              final settings = manager.store.settings;
              final supported = WorkflowBackground.isSupported;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const WorkflowGlyphTile(
                        glyph: 'moon',
                        accent: WorkflowVisuals.triggerAccent,
                        size: 38,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LocaleKeys.workflows_background_title.tr(),
                              style: DashboardType.sectionTitle(palette),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              LocaleKeys.workflows_background_body.tr(),
                              style: DashboardType.caption(palette)
                                  .copyWith(fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (supported) ...[
                    _SettingRow(
                      key: const ValueKey('workflow-keep-running'),
                      title: LocaleKeys.workflows_background_keepRunning.tr(),
                      hint:
                          LocaleKeys.workflows_background_keepRunningHint.tr(),
                      value: settings.keepRunningInBackground,
                      onChanged: (value) => unawaited(
                        manager.updateSettings(
                          settings.copyWith(keepRunningInBackground: value),
                        ),
                      ),
                    ),
                    _SettingRow(
                      key: const ValueKey('workflow-launch-at-login'),
                      title: LocaleKeys.workflows_background_launchAtLogin.tr(),
                      hint: LocaleKeys.workflows_background_launchAtLoginHint
                          .tr(),
                      value: manager.launchAtLogin,
                      onChanged: settings.keepRunningInBackground
                          ? (value) =>
                              unawaited(manager.setLaunchAtLogin(value))
                          : null,
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: WorkflowHint(
                        LocaleKeys.workflows_background_unsupported.tr(),
                        glyph: 'info',
                      ),
                    ),
                  _SettingRow(
                    key: const ValueKey('workflow-notify-failure'),
                    title: LocaleKeys.workflows_background_notifyOnFailure.tr(),
                    value: settings.notifyOnFailure,
                    onChanged: (value) => unawaited(
                      manager.updateSettings(
                        settings.copyWith(notifyOnFailure: value),
                      ),
                    ),
                  ),
                  _SettingRow(
                    key: const ValueKey('workflow-pause-all'),
                    title: LocaleKeys.workflows_background_pauseAll.tr(),
                    hint: LocaleKeys.workflows_background_pauseAllHint.tr(),
                    value: settings.pausedAll,
                    onChanged: (value) => unawaited(
                      manager.updateSettings(
                        settings.copyWith(pausedAll: value),
                      ),
                    ),
                  ),
                  if (manager.webhooks.isRunning) ...[
                    const SizedBox(height: 4),
                    WorkflowHint(
                      LocaleKeys.workflows_background_webhookPort
                          .tr(args: ['${manager.webhooks.port}']),
                      glyph: 'link-simple',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: WorkflowButton(
                      label: LocaleKeys.workflows_background_done.tr(),
                      kind: WorkflowButtonKind.primary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DashboardType.body(palette).copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      hint!,
                      style: DashboardType.caption(palette)
                          .copyWith(fontSize: 12, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: WorkflowSwitch(
                value: value,
                onChanged: onChanged,
                semanticLabel: title,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
