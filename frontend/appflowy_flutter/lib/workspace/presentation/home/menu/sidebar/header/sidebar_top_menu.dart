import 'dart:io' show Platform;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

/// Identity joins the title/tab surface without another utility strip.
/// Native traffic lights retain their space; only the blank gap is draggable.
class SidebarTopMenu extends StatelessWidget {
  const SidebarTopMenu({
    super.key,
    required this.isSidebarOnHover,
    this.identity,
  });

  final ValueNotifier<bool> isSidebarOnHover;
  final Widget? identity;

  @override
  Widget build(BuildContext context) {
    return PreviewToolbarRegion(
      child: SizedBox(
        key: const ValueKey('sidebar-identity-header'),
        height: HomeSizes.tabBarHeight,
        child: Row(
          children: [
            if (UniversalPlatform.isMacOS) const SizedBox(width: 80),
            Expanded(child: identity ?? const WindowDragTarget()),
            const SizedBox(
              width: WorkspaceTokens.space3,
              child: WindowDragTarget(),
            ),
            // A narrow overlay drawer covers the shell's grouped controls.
            // Keep a local dismiss target only in that exceptional layout.
            if (context.watch<HomeSettingBloc?>()?.state.isScreenSmall == true)
              _buildCollapseMenuButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapseMenuButton(BuildContext context) {
    final settingState = context.watch<HomeSettingBloc?>()?.state;
    final isNotificationPanelCollapsed =
        settingState?.isNotificationPanelCollapsed ?? true;

    final shortcut = isNotificationPanelCollapsed
        ? '\n${Platform.isMacOS ? '⌘+.' : 'Ctrl+\\'}'
        : '';
    return ValueListenableBuilder(
      valueListenable: isSidebarOnHover,
      builder: (_, value, ___) => PreviewToolbar(
        keepVisible: value,
        child: SidebarIconButton(
          icon: SidebarIcon.collapse,
          tooltip: '${LocaleKeys.sideBar_closeSidebar.tr()}$shortcut',
          onPressed: () => context.read<HomeSettingBloc>().collapseMenu(),
        ),
      ),
    );
  }
}
