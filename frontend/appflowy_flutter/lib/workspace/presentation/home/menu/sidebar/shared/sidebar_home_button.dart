import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Home is the selected dashboard (or the existing Home fallback), not the
/// Workspace folder. Navigation never creates a page or rewrites preferences.
class SidebarHomeButton extends StatelessWidget {
  const SidebarHomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<UserWorkspaceBloc>();
    final workspaceId = workspace.state.currentWorkspace?.workspaceId;
    final userId = workspace.state.userProfile.id;
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tabs = context.read<TabsBloc>();
        final plugin = state.currentPageManager.plugin;
        return SidebarNavItem(
          key: const ValueKey('sidebar-home'),
          icon: SidebarIcon.home,
          label: LocaleKeys.dashboard_home.tr(),
          selected: plugin.pluginType == PluginType.blank ||
              plugin.id == tabs.homeViewId,
          onTap: workspaceId == null || workspaceId.isEmpty
              ? null
              : () => unawaited(
                    tabs.openHome(
                      workspaceId: workspaceId,
                      isCurrent: () =>
                          context.mounted &&
                          !workspace.isClosed &&
                          workspace.state.userProfile.id == userId &&
                          workspace.state.currentWorkspace?.workspaceId ==
                              workspaceId,
                    ),
                  ),
        );
      },
    );
  }
}
