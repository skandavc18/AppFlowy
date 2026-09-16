import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// Every colour and measurement used by the chrome around a document.
///
/// Renderers never read this: it describes the viewer, not the document. One
/// palette for every file type is what makes a PDF, a Markdown file and a
/// video feel like pages of the same notebook.
@immutable
class DocumentViewportStyle {
  const DocumentViewportStyle({
    required this.canvas,
    required this.chrome,
    required this.hairline,
    required this.control,
    required this.controlHover,
    required this.controlActive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.icon,
    required this.iconMuted,
    required this.accent,
    required this.scrollThumb,
    required this.shellShadow,
    required this.chromeShadow,
  });

  factory DocumentViewportStyle.of(BuildContext context) {
    final theme = Theme.of(context);
    final appFlowy = AppFlowyTheme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPaper = PaperTheme.isEnabled(context);
    final isLightPaper = !isDark && isPaper;

    final canvas = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      premium?.surface ?? appFlowy.fillColorScheme.content,
      isPaper: isPaper,
    );

    return DocumentViewportStyle(
      canvas: canvas,
      // Identity and content share a sheet. A different toolbar fill would
      // leave a hard seam even without a drawn divider.
      chrome: canvas,
      hairline: EditorSurfaceStyle.embedBorder(context),
      control: (premium?.hover ?? appFlowy.fillColorScheme.contentHover)
          .withValues(alpha: 0),
      controlHover: isLightPaper
          ? PaperTheme.hoverOverlay
          : isDark
              ? const Color(0x14FFFFFF)
              : premium?.hover ?? appFlowy.fillColorScheme.contentHover,
      controlActive: isLightPaper
          ? PaperTheme.selectedOverlay
          : isDark
              ? const Color(0x24FFFFFF)
              : premium?.selected ?? appFlowy.fillColorScheme.themeSelect,
      textPrimary: appFlowy.textColorScheme.primary,
      textSecondary: appFlowy.textColorScheme.secondary,
      textMuted: appFlowy.textColorScheme.tertiary,
      icon: appFlowy.iconColorScheme.secondary,
      iconMuted: appFlowy.iconColorScheme.tertiary,
      accent: isLightPaper ? PaperTheme.accent : theme.colorScheme.primary,
      scrollThumb: isDark
          ? const Color(0x59FFFFFF)
          : isLightPaper
              ? const Color(0x59685440)
              : const Color(0x520F172A),
      shellShadow: EditorSurfaceStyle.embedShadow(context),
      chromeShadow: const [],
    );
  }

  final Color canvas;
  final Color chrome;

  /// Reserved for the rare separator that genuinely needs to read.
  final Color hairline;

  final Color control;
  final Color controlHover;
  final Color controlActive;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color icon;
  final Color iconMuted;
  final Color accent;
  final Color scrollThumb;
  final List<BoxShadow> shellShadow;
  final List<BoxShadow> chromeShadow;

  /// Card geometry, shared with the page and folder preview cards.
  static const double radius = EditorSurfaceStyle.embedCornerRadius;

  static BorderRadius get borderRadius => BorderRadius.circular(radius);

  /// Minimum height; larger text can grow the header without clipping it.
  static const double headerHeight = 44;

  /// Spacing inside the chrome, never a margin around it.
  static const double gutter = 8;
  static const double horizontalPadding = 16;
  static const double toolbarBreakpoint = 960;

  static const double controlSize = 28;
  static const double iconSize = 16;
  static const double blurSigma = 18;

  /// Default header extent. Layout measures the actual header at larger scales.
  static const double contentTopInset = headerHeight;
}
