import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/shared/workspace_layout.dart';
import 'package:appflowy/shared/workspace_tokens.dart';

class HomeSizes {
  static const double menuAddButtonHeight = 60;
  static const double topBarHeight = tabBarHeight + contextBarHeight;
  static const double editPanelTopBarHeight = 60;
  static const double editPanelWidth = 400;
  static const double notificationPanelWidth = 380;
  // Tabs meet the page-context row without a floating-card inset or shadow.
  static const double tabHeight = 40;
  static const double tabBarHeight = tabHeight;
  static const double contextBarHeight = 36;
  static const double navigationButtonSize = 28;
  static const double pinnedTabWidth = 72;
  static const double tabBarMinWidth = 144;
  static const double tabBarWidth = 224;
  static const double tabCornerRadius = 4;
  static const double pathMaxWidth = 320;
  static const double compactPathWidth = 40;
  static const double tabPaneMinWidth = tabBarMinWidth +
      2 * WorkspaceTokens.controlHeight +
      WorkspaceTokens.space6 +
      WorkspaceTokens.space2;
  static const double workspaceSectionHeight = WorkspaceTokens.navigationHeight;
  static const double searchSectionHeight = WorkspaceTokens.navigationHeight;
  static const double newPageSectionHeight = WorkspaceTokens.navigationHeight;
  static const double minimumSidebarWidth = WorkspaceLayout.minimumSidebarWidth;
  static const double sidebarHorizontalInset = SidebarMetrics.gutter;
  static const double sidebarButtonHorizontalMargin = 0;
  static const double sidebarActionIconSize = SidebarMetrics.iconSize;
  static const double sidebarActionIconTextSpacing = SidebarMetrics.iconGap;
}

class HomeInsets {
  static const double topBarTitleHorizontalPadding = WorkspaceTokens.space4;
  static const double topBarTitleVerticalPadding = WorkspaceTokens.space1;
}

class HomeSpaceViewSizes {
  static const double leftPadding = SidebarMetrics.indent;
  static const double viewHeight = SidebarMetrics.rowHeight;
  static const double viewIconSize = SidebarMetrics.iconSize;
  static const double viewIconLineHeight = 20.0;
  static const double viewIconTextSpacing = SidebarMetrics.iconGap;
  static const double viewListLeftPadding = 0.0;
  static const double viewListRightPadding = SidebarMetrics.gutter;
  static const double viewLeadingSpacing = 0.0;
  static const double viewIconOpacity = SidebarMetrics.iconRestingOpacity;

  // mobile, m represents mobile
  static const double mViewHeight = 48.0;
  static const double mViewButtonDimension = 34.0;
  static const double mHorizontalPadding = 20.0;
  static const double mVerticalPadding = 12.0;
}
