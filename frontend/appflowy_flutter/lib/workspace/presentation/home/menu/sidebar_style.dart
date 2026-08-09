import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:flutter/material.dart';

import '../../../../shared/paper_theme.dart';

abstract final class SidebarStyle {
  static const defaultLightBackground = Color(0xFFFAF9F6);
  static const lightBackground = PaperTheme.sidebarBackground;
  static const darkBackground = Color(0xFF1F1F1F);
  static const lightPrimaryText = Color(0xFF2B2A28);
  static const darkPrimaryText = Color(0xE8FFFFFF);
  static const lightSecondaryText = Color(0xFF6B6963);
  static const darkSecondaryText = Color(0x9EFFFFFF);
  static const lightIcon = Color(0xFF6F6C66);
  static const darkIcon = Color(0xAEFFFFFF);
  static const lightSearchIcon = Color(0xFF6F6C66);
  static const darkSearchIcon = Color(0xAEFFFFFF);
  static const lightHover = Color(0x0A16150F);
  static const darkHover = Color(0x0FFFFFFF);
  static const lightSelected = Color(0x1416150F);
  static const darkSelected = Color(0x1FFFFFFF);
  static const lightEdge = Color(0x0F16150F);
  static const darkEdge = Color(0x14FFFFFF);

  static Color backgroundFor(
    Brightness brightness, {
    bool isPaper = false,
    Color? lightFallback,
  }) =>
      brightness == Brightness.light
          ? isPaper
              ? lightBackground
              : lightFallback ?? defaultLightBackground
          : darkBackground;

  static Color primaryTextFor(Brightness brightness) =>
      brightness == Brightness.light ? lightPrimaryText : darkPrimaryText;

  static Color secondaryTextFor(Brightness brightness) =>
      brightness == Brightness.light ? lightSecondaryText : darkSecondaryText;

  static Color iconColorFor(Brightness brightness) =>
      brightness == Brightness.light ? lightIcon : darkIcon;

  static Color searchIconColorFor(Brightness brightness) =>
      brightness == Brightness.light ? lightSearchIcon : darkSearchIcon;

  static Color searchIconColor(BuildContext context) =>
      SidebarPalette.of(context).icon;

  static Color hoverBackgroundFor(Brightness brightness) =>
      brightness == Brightness.light ? lightHover : darkHover;

  static Color selectedBackgroundFor(Brightness brightness) =>
      brightness == Brightness.light ? lightSelected : darkSelected;

  static Color edgeBorderFor(Brightness brightness) =>
      brightness == Brightness.light ? lightEdge : darkEdge;

  static Color background(BuildContext context) =>
      SidebarPalette.of(context).background;

  static Color selectedBackground(BuildContext context) =>
      SidebarPalette.of(context).selected;

  static Color edgeBorder(BuildContext context) =>
      SidebarPalette.of(context).edge;

  static ThemeData themeData(BuildContext context) {
    final base = SidebarTypography.themeData(context);
    final palette = SidebarPalette.of(context);

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        secondary: palette.hover,
        onSecondary: palette.textPrimary,
        tertiary: palette.textPrimary,
        onSurface: palette.textPrimary,
        surfaceContainerHighest: palette.background,
      ),
      dividerColor: palette.edge,
      hintColor: palette.textTertiary,
      iconTheme: base.iconTheme.copyWith(
        color: palette.icon,
        size: HomeSizes.sidebarActionIconSize,
      ),
      textTheme: base.textTheme.copyWith(
        bodyMedium: SidebarTypography.textStyle(
          context,
          color: palette.textPrimary,
        ),
      ),
    );
  }
}

class SidebarSearchIcon extends StatelessWidget {
  const SidebarSearchIcon({
    super.key,
    this.color,
    this.size = HomeSizes.sidebarActionIconSize,
  });

  final Color? color;
  final double size;

  static const iconData = Icons.search_rounded;

  @override
  Widget build(BuildContext context) => Icon(
        iconData,
        size: size,
        color: color ?? SidebarStyle.searchIconColor(context),
        opticalSize: size,
        applyTextScaling: false,
      );
}
