// ThemeData in mobile
import 'package:appflowy/plugins/document/presentation/editor_plugins/mobile_toolbar_v3/aa_menu/_toolbar_theme.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';

class MobileAppearance extends BaseAppearance {
  @override
  ThemeData getThemeData(
    AppTheme appTheme,
    Brightness brightness,
    String fontFamily,
    String codeFontFamily,
  ) {
    assert(codeFontFamily.isNotEmpty);

    final theme = brightness == Brightness.light
        ? appTheme.lightTheme
        : appTheme.darkTheme;
    final palette = PremiumTheme.resolve(
      appTheme: appTheme,
      legacy: theme,
      brightness: brightness,
    );
    final isPaper = PaperTheme.isPaper(appTheme);
    final textTheme = getTextTheme(
      fontFamily: fontFamily,
      fontColor: palette.textPrimary,
    );
    final materialTheme = PremiumTheme.materialTheme(
      legacy: theme,
      palette: palette,
      brightness: brightness,
      fontFamily: resolveFontFamily(fontFamily),
      textTheme: textTheme,
      isDesktop: false,
    );

    return materialTheme.copyWith(
      primaryColor: palette.accent,
      primaryColorLight: palette.accentHover,
      appBarTheme: AppBarTheme(
        toolbarHeight: 44.0,
        foregroundColor: palette.textPrimary,
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: palette.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      indicatorColor: palette.accent,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.any(scrollbarInteractiveStates.contains)
              ? palette.accent
              : palette.textMuted.withValues(alpha: 0.4),
        ),
        thickness: const WidgetStatePropertyAll(3),
        radius: const Radius.circular(10),
      ),
      extensions: [
        palette,
        PaperThemeExtension(enabled: isPaper),
        AFThemeExtension(
          warning: PremiumTheme.semanticColorFor(theme.yellow, palette),
          success: PremiumTheme.semanticColorFor(theme.green, palette),
          tint1: PremiumTheme.tintFor(theme.tint1, palette),
          tint2: PremiumTheme.tintFor(theme.tint2, palette),
          tint3: PremiumTheme.tintFor(theme.tint3, palette),
          tint4: PremiumTheme.tintFor(theme.tint4, palette),
          tint5: PremiumTheme.tintFor(theme.tint5, palette),
          tint6: PremiumTheme.tintFor(theme.tint6, palette),
          tint7: PremiumTheme.tintFor(theme.tint7, palette),
          tint8: PremiumTheme.tintFor(theme.tint8, palette),
          tint9: PremiumTheme.tintFor(theme.tint9, palette),
          textColor: palette.textPrimary,
          secondaryTextColor: palette.textSecondary,
          strongText: palette.textPrimary,
          greyHover: palette.hover,
          greySelect: palette.selected,
          lightGreyHover: palette.mutedSurface,
          toggleOffFill: palette.pressed,
          progressBarBGColor: palette.mutedSurface,
          toggleButtonBGColor: palette.pressed,
          calendarWeekendBGColor: palette.surface,
          gridRowCountColor: palette.textSecondary,
          code: getFontStyle(
            fontFamily: codeFontFamily,
            fontColor: palette.textSecondary,
          ),
          callout: getFontStyle(
            fontFamily: fontFamily,
            fontSize: FontSizes.s11,
            fontColor: palette.textSecondary,
          ),
          calloutBGColor: EditorSurfaceStyle.calloutBackgroundFor(
            brightness,
            palette.mutedSurface,
            isPaper: isPaper,
          ),
          tableCellBGColor: palette.surface,
          caption: getFontStyle(
            fontFamily: fontFamily,
            fontSize: FontSizes.s11,
            fontWeight: defaultFontWeight,
            fontColor: palette.textMuted,
          ),
          onBackground: palette.textPrimary,
          background: palette.canvas,
          borderColor: palette.border,
          scrollbarColor: brightness == Brightness.dark
              ? theme.scrollbarColor
              : palette.textMuted.withValues(alpha: 0.4),
          scrollbarHoverColor: brightness == Brightness.dark
              ? theme.scrollbarHoverColor
              : palette.accent,
          lightIconColor: palette.textMuted,
          toolbarHoverColor: palette.hover,
        ),
        ToolbarColorExtension.fromPalette(palette, brightness),
      ],
    );
  }
}
