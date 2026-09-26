import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

@immutable
class FolderExplorerPalette {
  const FolderExplorerPalette({
    required this.background,
    required this.surface,
    required this.floatingSurface,
    required this.hover,
    required this.selected,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.danger,
    required this.shadow,
  });

  factory FolderExplorerPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isPaper = PaperTheme.isEnabled(context);
    final usePaperPalette = isPaper && theme.brightness == Brightness.light;
    final fallback = theme.colorScheme;
    final baseSurface = premium?.surface ?? fallback.surface;
    return FolderExplorerPalette(
      background: EditorSurfaceStyle.previewBackgroundFor(
        theme.brightness,
        premium?.canvas ?? fallback.surface,
        isPaper: isPaper,
      ),
      surface: EditorSurfaceStyle.previewBackgroundFor(
        theme.brightness,
        baseSurface,
        isPaper: isPaper,
      ),
      floatingSurface: usePaperPalette
          ? PaperTheme.popupBackground
          : premium?.floatingSurface ?? fallback.surfaceContainer,
      hover: premium?.subtleHover ??
          (usePaperPalette
              ? PaperTheme.hoverOverlay.withValues(
                  alpha: PaperTheme.hoverOverlay.a * 0.65,
                )
              : fallback.onSurface.withValues(
                  alpha: fallback.onSurface.a * 0.04,
                )),
      selected: usePaperPalette
          ? PaperTheme.controlSelected
          : premium?.selected ??
              Color.alphaBlend(
                fallback.primary.withValues(alpha: 0.10),
                baseSurface,
              ),
      border: usePaperPalette
          ? PaperTheme.strongBorder
          : premium?.border ?? fallback.outlineVariant.withValues(alpha: 0.45),
      textPrimary: usePaperPalette
          ? PaperTheme.textPrimary
          : premium?.textPrimary ?? fallback.onSurface,
      textSecondary: usePaperPalette
          ? PaperTheme.textSecondary
          : premium?.textSecondary ?? fallback.onSurfaceVariant,
      textMuted: usePaperPalette
          ? PaperTheme.textMuted
          : premium?.textMuted ??
              fallback.onSurfaceVariant.withValues(alpha: 0.7),
      accent: usePaperPalette
          ? PaperTheme.accent
          : premium?.accent ?? fallback.primary,
      danger: fallback.error,
      shadow: usePaperPalette
          ? PaperTheme.shadow
          : premium?.shadow ?? Colors.black.withValues(alpha: 0.12),
    );
  }

  final Color background;
  final Color surface;
  final Color floatingSurface;

  /// A translucent wash, not a replacement surface. Attenuate by multiplying
  /// its existing alpha; use [selected] for selection rather than boosting it.
  final Color hover;
  final Color selected;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color danger;
  final Color shadow;
}

/// One reading measure for folder identity, actions and every presentation.
/// Embeds use the same alignment without inheriting desktop-sized gutters.
abstract final class FolderExplorerLayout {
  static const maxContentWidth = 1200.0;

  static double horizontalPadding(double width, {bool embedded = false}) {
    if (!width.isFinite || width <= 0) return 0;
    final minimum =
        (embedded || width < 600 ? 16.0 : 36.0).clamp(0.0, width / 2);
    return ((width - maxContentWidth) / 2)
        .clamp(minimum, double.infinity)
        .toDouble();
  }
}

abstract final class KnowledgeGalleryLayout {
  static const maxContentWidth = 1680.0;
  static const minimumHorizontalPadding = 36.0;
  static const cardSpacing = 30.0;
  static const minimumCardWidth = 285.0;

  /// Every card is the same height, so the grid reads as rows and columns
  /// rather than a staggered wall with holes in it.
  static const cardHeight = 376.0;

  static double horizontalPadding(double width) {
    if (!width.isFinite || width <= 0) {
      return minimumHorizontalPadding;
    }
    return ((width - maxContentWidth) / 2).clamp(
      minimumHorizontalPadding,
      double.infinity,
    );
  }
}
