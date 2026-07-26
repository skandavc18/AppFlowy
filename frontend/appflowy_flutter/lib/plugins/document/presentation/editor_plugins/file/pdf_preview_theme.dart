import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

@immutable
class PdfPreviewPalette {
  const PdfPreviewPalette({
    required this.canvas,
    required this.chrome,
    required this.sidebar,
    required this.control,
    required this.controlHover,
    required this.controlSelected,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.icon,
    required this.iconDisabled,
    required this.accent,
    required this.searchMatch,
    required this.activeSearchMatch,
    required this.pageShadow,
    required this.chromeShadow,
    required this.shellShadows,
  });

  factory PdfPreviewPalette.of(BuildContext context) {
    final materialTheme = Theme.of(context);
    final appFlowyTheme = AppFlowyTheme.of(context);
    final brightness = materialTheme.brightness;
    final isDark = brightness == Brightness.dark;
    final isPaper = PaperTheme.isEnabled(context);
    final isLightPaper = brightness == Brightness.light && isPaper;
    final premiumPalette = PremiumThemeExtension.maybeOf(context);

    final canvas = isLightPaper
        ? PaperTheme.editorPreviewBackground
        : isDark
            ? const Color(0xFF17181B)
            : premiumPalette?.surface ??
                appFlowyTheme.surfaceColorScheme.layer01;
    final chrome = isLightPaper
        ? PaperTheme.popupBackground
        : isDark
            ? const Color(0xF225262A)
            : premiumPalette?.floatingSurface.withValues(alpha: 0.96) ??
                appFlowyTheme.surfaceColorScheme.primary
                    .withValues(alpha: 0.96);
    final sidebar = isLightPaper
        ? PaperTheme.sidebarBackground
        : isDark
            ? const Color(0xFF1D1E22)
            : premiumPalette?.sidebar ??
                appFlowyTheme.surfaceContainerColorScheme.layer01;
    final border = isDark
        ? const Color(0x24FFFFFF)
        : EditorSurfaceStyle.codeBlockBorderFor(
            brightness,
            premiumPalette?.border ?? appFlowyTheme.borderColorScheme.primary,
            isPaper: isPaper,
          );

    return PdfPreviewPalette(
      canvas: canvas,
      chrome: chrome,
      sidebar: sidebar,
      control: isLightPaper
          ? PaperTheme.controlBackground
          : isDark
              ? const Color(0xFF2B2C31)
              : premiumPalette?.mutedSurface ??
                  appFlowyTheme.fillColorScheme.primary,
      controlHover: isLightPaper
          ? PaperTheme.hoverOverlay
          : isDark
              ? const Color(0x12FFFFFF)
              : premiumPalette?.hover ??
                  appFlowyTheme.fillColorScheme.contentHover,
      controlSelected: isLightPaper
          ? PaperTheme.selectedOverlay
          : isDark
              ? appFlowyTheme.fillColorScheme.themeSelect
              : premiumPalette?.selected ??
                  appFlowyTheme.fillColorScheme.themeSelect,
      border: border,
      textPrimary: appFlowyTheme.textColorScheme.primary,
      textSecondary: appFlowyTheme.textColorScheme.secondary,
      icon: appFlowyTheme.iconColorScheme.secondary,
      iconDisabled: appFlowyTheme.iconColorScheme.quaternary,
      accent:
          isLightPaper ? PaperTheme.accent : materialTheme.colorScheme.primary,
      searchMatch: const Color(0x73E0B84F),
      activeSearchMatch: const Color(0xB3D8893D),
      pageShadow: isDark
          ? const Color(0x52000000)
          : isLightPaper
              ? const Color(0x1F5F503D)
              : const Color(0x160F172A),
      chromeShadow: isDark
          ? const Color(0x3D000000)
          : isLightPaper
              ? const Color(0x184C3F30)
              : const Color(0x140F172A),
      shellShadows: EditorSurfaceStyle.embedShadow(context),
    );
  }

  final Color canvas;
  final Color chrome;
  final Color sidebar;
  final Color control;
  final Color controlHover;
  final Color controlSelected;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color icon;
  final Color iconDisabled;
  final Color accent;
  final Color searchMatch;
  final Color activeSearchMatch;
  final Color pageShadow;
  final Color chromeShadow;
  final List<BoxShadow> shellShadows;
}
