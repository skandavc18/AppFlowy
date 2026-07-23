import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:flutter/material.dart';

import '../../../../shared/paper_theme.dart';
import '../../../../shared/premium_theme.dart';

abstract final class SidebarStyle {
  static const defaultLightBackground = Color(0xFFFAF9F6);
  static const lightBackground = PaperTheme.sidebarBackground;
  static const darkBackground = Color(0xFF202020);
  static const lightPrimaryText = Color(0xFF37352F);
  static const darkPrimaryText = Color(0xCFFFFFFF);
  static const lightSecondaryText = Color(0xA637352F);
  static const darkSecondaryText = Color(0x8FFFFFFF);
  static const lightIcon = Color(0xD137352F);
  static const darkIcon = Color(0xCFFFFFFF);
  static const lightSearchIcon = Color(0xFF403E39);
  static const darkSearchIcon = Color(0xE6FFFFFF);
  static const lightHover = Color(0x0D37352F);
  static const darkHover = Color(0x0DFFFFFF);
  static const lightSelected = Color(0x1437352F);
  static const darkSelected = Color(0x14FFFFFF);
  static const lightEdge = Color(0x1437352F);
  static const darkEdge = Color(0x1AFFFFFF);

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
      PremiumThemeExtension.maybeOf(context)?.textSecondary ??
      searchIconColorFor(Theme.of(context).brightness);

  static Color hoverBackgroundFor(Brightness brightness) =>
      brightness == Brightness.light ? lightHover : darkHover;

  static Color selectedBackgroundFor(Brightness brightness) =>
      brightness == Brightness.light ? lightSelected : darkSelected;

  static Color edgeBorderFor(Brightness brightness) =>
      brightness == Brightness.light ? lightEdge : darkEdge;

  static Color background(BuildContext context) => backgroundFor(
        Theme.of(context).brightness,
        isPaper: PaperTheme.isEnabled(context),
        lightFallback: PremiumThemeExtension.maybeOf(context)?.sidebar ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
      );

  static Color selectedBackground(BuildContext context) =>
      PremiumThemeExtension.maybeOf(context)?.selected ??
      selectedBackgroundFor(Theme.of(context).brightness);

  static Color edgeBorder(BuildContext context) =>
      PremiumThemeExtension.maybeOf(context)?.border ??
      edgeBorderFor(Theme.of(context).brightness);

  static ThemeData themeData(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final base = SidebarTypography.themeData(context);
    final palette = PremiumThemeExtension.maybeOf(context);
    final primaryText = palette?.textPrimary ?? primaryTextFor(brightness);
    final secondaryText =
        palette?.textSecondary ?? secondaryTextFor(brightness);

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        secondary: palette?.hoverOverlay ?? hoverBackgroundFor(brightness),
        onSecondary: primaryText,
        tertiary: primaryText,
        onSurface: primaryText,
        surfaceContainerHighest: palette?.sidebar ?? backgroundFor(brightness),
      ),
      dividerColor: palette?.border ?? edgeBorderFor(brightness),
      hintColor: secondaryText,
      iconTheme: base.iconTheme.copyWith(
        color: palette?.textSecondary ?? iconColorFor(brightness),
        size: HomeSizes.sidebarActionIconSize,
      ),
      textTheme: base.textTheme.copyWith(
        bodyMedium: SidebarTypography.textStyle(
          context,
          color: primaryText,
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
