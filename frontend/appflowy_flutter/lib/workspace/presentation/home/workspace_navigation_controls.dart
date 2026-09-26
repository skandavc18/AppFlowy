import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Stable navigation targets beside the tabs, never inside a native drag area.
class WorkspaceNavigationControls extends StatelessWidget {
  const WorkspaceNavigationControls({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<HomeSettingBloc?>();
    final tabs = context.watch<TabsBloc?>();
    final workspace = context.watch<UserWorkspaceBloc?>();
    final workspaceId = workspace?.state.currentWorkspace?.workspaceId ??
        settings?.state.workspaceSetting.workspaceId;
    final palette = SidebarPalette.of(context);
    final expanded = settings?.state.menuStatus == MenuStatus.expanded;
    final plugin = tabs?.state.currentPageManager.plugin;
    final home = plugin != null &&
        (plugin.pluginType == PluginType.blank ||
            plugin.id == tabs?.homeViewId);
    final enabled = tabs != null && !tabs.isClosed;
    Widget button(
      String name,
      String glyph,
      String label,
      VoidCallback? onPressed, {
      bool selected = false,
    }) =>
        IconButton(
          key: ValueKey('workspace-navigation-$name'),
          tooltip: label,
          onPressed: onPressed,
          isSelected: selected,
          style: IconButton.styleFrom(
            foregroundColor: palette.icon,
            disabledForegroundColor:
                palette.textTertiary.withValues(alpha: 0.5),
            backgroundColor: selected ? palette.selected : palette.hoverAtRest,
            hoverColor: palette.hover,
            focusColor: palette.selected,
            highlightColor: palette.selected,
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(HomeSizes.navigationButtonSize),
            maximumSize: const Size.square(HomeSizes.navigationButtonSize),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          icon: DSWorkspaceGlyph.named(glyph),
        );

    return FocusTraversalGroup(
      child: Row(
        key: const ValueKey('workspace-navigation-controls'),
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            'sidebar',
            'sidebar-simple',
            expanded
                ? LocaleKeys.sideBar_closeSidebar.tr()
                : LocaleKeys.sideBar_openSidebar.tr(),
            settings == null || settings.isClosed
                ? null
                : settings.collapseMenu,
          ),
          button(
            'back',
            'caret-left',
            '${LocaleKeys.button_back.tr()} (Alt+←)',
            enabled && tabs.canGoBack ? tabs.goBack : null,
          ),
          button(
            'forward',
            'caret-right',
            '${LocaleKeys.button_next.tr()} (Alt+→)',
            enabled && tabs.canGoForward ? tabs.goForward : null,
          ),
          button(
            'home',
            'house',
            LocaleKeys.dashboard_home.tr(),
            enabled && workspaceId != null && workspaceId.isNotEmpty
                ? () => unawaited(openWorkspaceTab(context, newTab: false))
                : null,
            selected: home,
          ),
        ],
      ),
    );
  }
}
