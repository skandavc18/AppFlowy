import 'dart:io' show Platform;

import 'package:appflowy/shared/workspace_layout.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'home_sizes.dart';

class HomeLayout {
  factory HomeLayout(BuildContext context, {BoxConstraints? constraints}) {
    final homeSetting = context.read<HomeSettingBloc>();
    final available = WorkspaceLayout.availableWidth(
      constraints ?? const BoxConstraints(),
      fallbackWidth: MediaQuery.sizeOf(context).width,
    );
    if (homeSetting.state.isScreenSmall !=
        WorkspaceLayout.sidebarIsDrawer(available)) {
      homeSetting.add(HomeSettingEvent.checkScreenSize(available));
    }
    return HomeLayout.fromState(
      homeSetting.state,
      availableWidth: available,
      isMacOS: Platform.isMacOS,
      disableAnimations: MediaQuery.disableAnimationsOf(context),
    );
  }

  HomeLayout.fromState(
    HomeSettingState homeSetting, {
    required double availableWidth,
    bool isMacOS = false,
    bool disableAnimations = false,
  }) {
    showEditPanel = homeSetting.panelContext != null;
    showMenu = homeSetting.menuStatus == MenuStatus.expanded;
    final geometry = WorkspaceShellGeometry.resolve(
      availableWidth: availableWidth,
      preferredSidebarWidth:
          HomeSizes.minimumSidebarWidth + homeSetting.resizeOffset,
      showSidebar: showMenu,
      showEditPanel: showEditPanel,
      preferredEditPanelWidth: HomeSizes.editPanelWidth,
    );
    menuWidth = geometry.sidebarWidth;
    menuIsDrawer = geometry.sidebarIsDrawer;
    showNotificationPanel = !homeSetting.isNotificationPanelCollapsed;
    homePageLOffset = geometry.contentLeft;
    homePageROffset = geometry.contentRight;
    menuSpacing = !showMenu && isMacOS ? 80.0 : 0.0;
    final sidebarWasConstrained =
        menuWidth < HomeSizes.minimumSidebarWidth + homeSetting.resizeOffset;
    // Do not tween a previous docked offset through a now-smaller viewport.
    animDuration = disableAnimations || menuIsDrawer || sidebarWasConstrained
        ? Duration.zero
        : homeSetting.resizeType.duration();
    editPanelWidth = geometry.editPanelWidth;
    notificationPanelWidth = geometry.contentWidth;
  }

  late bool showEditPanel;
  late double menuWidth;
  late bool showMenu;
  late bool menuIsDrawer;
  late bool showNotificationPanel;
  late double homePageLOffset;
  late double menuSpacing;
  late Duration animDuration;
  late double editPanelWidth;
  late double notificationPanelWidth;
  late double homePageROffset;
}
