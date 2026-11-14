import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum _SyncMenuAction { syncNow, togglePause, openSettings }

/// Compact sidebar header button showing live non-blocking sync activity and
/// offering quick Sync Now / Pause / Resume / Settings actions.
class SidebarSyncStatusButton extends StatelessWidget {
  const SidebarSyncStatusButton({
    super.key,
    required this.isHover,
  });

  final bool isHover;

  @override
  Widget build(BuildContext context) {
    final engine = WorkspaceSyncEngine.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([engine, engine.settings]),
      builder: (context, _) {
        final bound = engine.boundBindings;
        final settingUp = engine.settingUpDestination;
        if (bound.isEmpty && settingUp == null) {
          return const SizedBox.shrink();
        }
        final working = engine.phase == SyncPhase.working || engine.isBusy;
        final paused = engine.isAllPaused;
        final attention = engine.phase == SyncPhase.failed ||
            engine.phase == SyncPhase.locked ||
            engine.phase == SyncPhase.restoredElsewhere;
        final alwaysVisible = working || paused || attention;
        if (!alwaysVisible && !isHover) {
          return const SizedBox.shrink();
        }

        final palette = SidebarPalette.of(context);
        final premium = PremiumThemeExtension.of(context);
        final tooltip = working
            ? (engine.activity.isEmpty
                ? LocaleKeys.sync_statusWorking.tr()
                : engine.activity)
            : paused
                ? LocaleKeys.sync_statusPaused.tr()
                : attention
                    ? LocaleKeys.sync_title.tr()
                    : LocaleKeys.sync_syncNow.tr();

        final iconColor = attention
            ? const Color(0xFFD9922E)
            : paused
                ? palette.textSecondary
                : palette.icon;

        return SizedBox.square(
          dimension: SidebarMetrics.actionSlot,
          child: FlowyTooltip(
            message: tooltip,
            child: InkWell(
              key: const ValueKey('sidebar-sync-status-button'),
              borderRadius: BorderRadius.circular(6),
              hoverColor: palette.hover,
              onTap: () => unawaited(_openMenu(context, engine)),
              child: Center(
                child: working
                    ? SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.7,
                          color: premium.accent,
                        ),
                      )
                    : Icon(
                        paused
                            ? Icons.sync_disabled_rounded
                            : attention
                                ? Icons.sync_problem_rounded
                                : Icons.sync_rounded,
                        size: 16,
                        color: iconColor,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    WorkspaceSyncEngine engine,
  ) async {
    final bound = engine.boundBindings;
    final multi = bound.length > 1;
    final paused = engine.isAllPaused;
    final working = engine.phase == SyncPhase.working || engine.isBusy;

    final chosen = await showAppMenuForWidget<_SyncMenuAction>(
      context: context,
      entries: [
        if (!working && !paused && bound.isNotEmpty)
          AppMenuItem(
            label: multi
                ? LocaleKeys.sync_syncAllNow.tr()
                : LocaleKeys.sync_syncNow.tr(),
            icon: Icons.sync_rounded,
            value: _SyncMenuAction.syncNow,
          ),
        if (bound.isNotEmpty)
          AppMenuItem(
            label: paused
                ? (multi
                    ? LocaleKeys.sync_resumeAll.tr()
                    : LocaleKeys.sync_resume.tr())
                : (multi
                    ? LocaleKeys.sync_pauseAll.tr()
                    : LocaleKeys.sync_pause.tr()),
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            value: _SyncMenuAction.togglePause,
          ),
        AppMenuItem(
          label: LocaleKeys.sync_title.tr(),
          icon: Icons.settings_outlined,
          value: _SyncMenuAction.openSettings,
        ),
      ],
    );
    if (!context.mounted || chosen == null) {
      return;
    }
    switch (chosen) {
      case _SyncMenuAction.syncNow:
        unawaited(engine.syncNow());
      case _SyncMenuAction.togglePause:
        unawaited(engine.setPaused(!paused));
      case _SyncMenuAction.openSettings:
        final workspaceBloc = context.read<UserWorkspaceBloc?>();
        if (workspaceBloc != null) {
          showSettingsDialog(
            context,
            userWorkspaceBloc: workspaceBloc,
            initPage: SettingsPage.account,
          );
        }
    }
  }
}
