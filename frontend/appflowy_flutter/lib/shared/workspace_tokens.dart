import 'package:flutter/widgets.dart';

/// Geometry and motion for the content-first workspace. These are semantic
/// roles, not a blanket rounding of every cell, badge and icon in the product.
abstract final class WorkspaceTokens {
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;
  static const space8 = 32.0;
  static const space12 = 48.0;
  static const space16 = 64.0;

  static const controlRadius = 8.0;
  static const inputRadius = 12.0;
  static const menuRadius = 16.0;
  static const cardRadius = 20.0;
  static const dialogRadius = 24.0;
  static const heroRadius = 28.0;

  static const headerHeight = 48.0;
  static const controlHeight = 32.0;
  static const navigationHeight = 34.0;
  static const navigationWidth = 248.0;
  static const iconSize = 18.0;
  static const pageIconSize = 56.0;
  static const pageMaxWidth = 1120.0;
  static const coverHeight = 176.0;
  static const compactCoverHeight = 160.0;
  static const coverInset = 8.0;
  static const pageTopWithoutCover = 20.0;
  static const pageTopWithCover = 8.0;
  static const pageIconCoverOverlap = 22.0;
  static const pageIconTitleGap = 6.0;
  static const pageActionsGap = 8.0;
  static const pageHeaderBottom = 12.0;

  static const hoverDuration = Duration(milliseconds: 140);
  static const transitionDuration = Duration(milliseconds: 200);
  static const entranceDuration = Duration(milliseconds: 180);
  static const exitDuration = Duration(milliseconds: 120);
  static const curve = Curves.easeOutCubic;

  static Duration motion(BuildContext context, Duration duration) {
    final media = MediaQuery.maybeOf(context);
    return (media?.disableAnimations ?? false) ||
            (media?.accessibleNavigation ?? false)
        ? Duration.zero
        : duration;
  }

  /// A compact pane changes composition, never the user's saved page width.
  static double pageInset(double width) => width < 600 ? space6 : space12;
}
