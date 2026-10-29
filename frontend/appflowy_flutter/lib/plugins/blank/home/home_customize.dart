import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_standalone_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The strip above Home's content: a way into customising, and while
/// customising, the ways to add to Home, start over and finish.
class HomeCustomizeBar extends StatelessWidget {
  const HomeCustomizeBar({
    super.key,
    required this.customizing,
    this.canResizeWidths = true,
    required this.onCustomize,
    required this.onDone,
    required this.onReset,
    required this.addEntries,
  });

  final bool customizing;

  /// Whether sections can be made wider or narrower at this width; in a
  /// narrower window only their order and heights change.
  final bool canResizeWidths;
  final VoidCallback onCustomize;
  final VoidCallback onDone;
  final VoidCallback onReset;
  final List<AppMenuEntry> Function() addEntries;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    if (!customizing) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Tooltip(
          message: LocaleKeys.landing_customizeTooltip.tr(),
          child: TextButton.icon(
            key: const ValueKey('home-customize'),
            onPressed: onCustomize,
            style: WorkspaceChrome.controlStyle(context),
            icon: WorkspaceGlyph(
              Icons.dashboard_customize_rounded,
              size: 16,
              color: palette.secondaryText,
            ),
            label: Text(LocaleKeys.landing_customize.tr()),
          ),
        ),
      );
    }

    final hint = Row(
      children: [
        WorkspaceGlyph(
          Icons.dashboard_customize_rounded,
          color: palette.accent,
        ),
        const SizedBox(width: WorkspaceTokens.space2),
        Expanded(
          child: Text(
            canResizeWidths
                ? LocaleKeys.landing_customizeHint.tr()
                : LocaleKeys.landing_customizeHintNarrow.tr(),
            key: const ValueKey('home-customize-hint'),
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.metadata,
            ),
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: WorkspaceTokens.space1,
      runSpacing: WorkspaceTokens.space1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Builder(
          builder: (anchor) => TextButton.icon(
            key: const ValueKey('home-customize-add'),
            onPressed: () => showAppMenuForWidget<void>(
              context: anchor,
              entries: addEntries(),
            ),
            style: WorkspaceChrome.controlStyle(context),
            icon: const WorkspaceGlyph(Icons.add_rounded, size: 16),
            label: Text(LocaleKeys.landing_addToHome.tr()),
          ),
        ),
        TextButton.icon(
          key: const ValueKey('home-customize-reset'),
          onPressed: onReset,
          style: WorkspaceChrome.controlStyle(context),
          icon: const WorkspaceGlyph(Icons.restart_alt_rounded, size: 16),
          label: Text(LocaleKeys.landing_resetLayout.tr()),
        ),
        TextButton.icon(
          key: const ValueKey('home-customize-done'),
          onPressed: onDone,
          style: WorkspaceChrome.controlStyle(
            context,
            accent: palette.accent,
            selected: true,
          ),
          icon: WorkspaceGlyph(
            Icons.check_rounded,
            size: 16,
            color: palette.accent,
          ),
          label: Text(LocaleKeys.landing_customizeDone.tr()),
        ),
      ],
    );
    return WorkspaceSurface(
      key: const ValueKey('home-customize-bar'),
      kind: WorkspaceSurfaceKind.secondary,
      padding: const EdgeInsets.symmetric(
        horizontal: WorkspaceTokens.space3,
        vertical: WorkspaceTokens.space2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= MediaQuery.textScalerOf(context).scale(640)
                ? Row(
                    children: [
                      Expanded(child: hint),
                      const SizedBox(width: WorkspaceTokens.space3),
                      actions,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      hint,
                      const SizedBox(height: WorkspaceTokens.space2),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: actions,
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// A dashboard widget living on Home.
///
/// It is drawn from the same definition, with the same surface, title and
/// padding a dashboard card gives it, and it reads and writes through the
/// same controller — so a to-do list or a note works here exactly as it does
/// on a dashboard. Only a dashboard's grid, grips and hover controls are left
/// behind: on Home, a widget is arranged on Home's own grid, which also gives
/// it the height its height units make.
class HomeWidgetCard extends StatelessWidget {
  const HomeWidgetCard({
    super.key,
    required this.controller,
    required this.spec,
    required this.palette,
  });

  final DashboardController controller;
  final DashboardWidgetSpec spec;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => DashboardStandaloneCard(
        controller: controller,
        spec: spec,
        palette: palette,
        keyPrefix: 'home-widget',
      );
}
