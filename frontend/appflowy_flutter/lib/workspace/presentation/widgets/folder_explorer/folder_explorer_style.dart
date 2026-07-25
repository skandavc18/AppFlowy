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
      hover: usePaperPalette
          ? PaperTheme.controlHover
          : premium?.hover ?? fallback.onSurface.withValues(alpha: 0.06),
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

abstract final class KnowledgeGalleryLayout {
  static const maxContentWidth = 1680.0;
  static const minimumHorizontalPadding = 36.0;
  static const cardSpacing = 30.0;
  static const minimumCardWidth = 285.0;

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
