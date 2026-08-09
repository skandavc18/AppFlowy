import 'dart:io' show Platform;

import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

/// Sidebar top menu is the top bar of the sidebar.
///
/// Provides a draggable title-bar area and the close / expand sidebar button.
class SidebarTopMenu extends StatelessWidget {
  const SidebarTopMenu({
    super.key,
    required this.isSidebarOnHover,
  });

  final ValueNotifier<bool> isSidebarOnHover;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SidebarSectionsBloc, SidebarSectionsState>(
      builder: (context, _) => SizedBox(
        height: !UniversalPlatform.isWindows ? HomeSizes.topBarHeight : 36,
        child: MoveWindowDetector(
          child: Row(
            children: [
              const Spacer(),
              _buildCollapseMenuButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapseMenuButton(BuildContext context) {
    final settingState = context.read<HomeSettingBloc?>()?.state;
    final isNotificationPanelCollapsed =
        settingState?.isNotificationPanelCollapsed ?? true;

    final textSpan = TextSpan(
      children: [
        TextSpan(
          text: LocaleKeys.sideBar_closeSidebar.tr(),
          style: context.tooltipTextStyle(),
        ),
        if (isNotificationPanelCollapsed)
          TextSpan(
            text: '\n${Platform.isMacOS ? '⌘+.' : 'Ctrl+\\'}',
            style: context
                .tooltipTextStyle()
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
      ],
    );
    return ValueListenableBuilder(
      valueListenable: isSidebarOnHover,
      builder: (_, value, ___) => AnimatedOpacity(
        duration: SidebarMetrics.reveal,
        curve: SidebarMetrics.curve,
        opacity: value ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.only(top: SidebarMetrics.space2),
          child: FlowyTooltip(
            richMessage: textSpan,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) =>
                  context.read<HomeSettingBloc>().collapseMenu(),
              child: SidebarIconButton(
                icon: SidebarIcon.collapse,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}
