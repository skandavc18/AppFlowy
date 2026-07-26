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
      // Translucent so the document reads through the blur behind it.
      chrome: isLightPaper
          ? PaperTheme.popupBackground.withValues(alpha: 0.86)
          : isDark
              ? const Color(0xFF1D1F23).withValues(alpha: 0.82)
              : (premium?.floatingSurface ?? Colors.white)
                  .withValues(alpha: 0.84),
      hairline: EditorSurfaceStyle.embedBorder(context),
      control: Colors.transparent,
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
      // A whisper of depth so the header reads as floating without an outline.
      chromeShadow: [
        BoxShadow(
          color: (isLightPaper
                  ? PaperTheme.shadow
                  : premium?.shadow ?? Colors.black)
              .withValues(alpha: isDark ? 0.22 : 0.06),
          blurRadius: 14,
          offset: const Offset(0, 4),
          spreadRadius: -6,
        ),
      ],
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

  /// The floating header occupies this much space at the top of the viewport.
  static const double headerHeight = 44;

  /// Breathing room between the floating chrome and the viewport edge.
  static const double gutter = 8;

  static const double controlSize = 28;
  static const double iconSize = 16;
  static const double blurSigma = 18;

  /// Content inset so nothing hides beneath the floating header.
  static const double contentTopInset = headerHeight + gutter;
}
