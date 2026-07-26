import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// Chrome colours for the fullscreen image editor.
///
/// The photo never changes with the theme; only the surfaces around it do.
@immutable
class ImageEditorPalette {
  const ImageEditorPalette({
    required this.brightness,
    required this.backdrop,
    required this.canvas,
    required this.chrome,
    required this.chromeBorder,
    required this.control,
    required this.controlHover,
    required this.controlActive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.divider,
    required this.shadow,
  });

  factory ImageEditorPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPaper = !isDark && PaperTheme.isEnabled(context);

    if (isDark) {
      return const ImageEditorPalette(
        brightness: Brightness.dark,
        backdrop: Color(0xF20B0B0D),
        canvas: Color(0xFF121215),
        chrome: Color(0xF01A1A1E),
        chromeBorder: Color(0x1FFFFFFF),
        control: Color(0x14FFFFFF),
        controlHover: Color(0x24FFFFFF),
        controlActive: Color(0x33FFFFFF),
        textPrimary: Color(0xFFF2F2F4),
        textSecondary: Color(0xFFA9A9B2),
        textMuted: Color(0xFF74747E),
        accent: Color(0xFF7C9CFF),
        onAccent: Color(0xFF0B0B0D),
        divider: Color(0x14FFFFFF),
        shadow: Color(0x8A000000),
      );
    }

    if (isPaper) {
      return const ImageEditorPalette(
        brightness: Brightness.light,
        backdrop: Color(0xF23A342C),
        canvas: Color(0xFF2E2A24),
        chrome: Color(0xF5FBF6EC),
        chromeBorder: PaperTheme.strongBorder,
        control: PaperTheme.controlBackground,
        controlHover: PaperTheme.controlHover,
        controlActive: PaperTheme.controlSelected,
        textPrimary: PaperTheme.textPrimary,
        textSecondary: PaperTheme.textSecondary,
        textMuted: PaperTheme.textMuted,
        accent: Color(0xFF8A6A3E),
        onAccent: PaperTheme.onAccent,
        divider: PaperTheme.codeBlockBorder,
        shadow: Color(0x33453A2C),
      );
    }

    return ImageEditorPalette(
      brightness: Brightness.light,
      backdrop: const Color(0xF21C1D21),
      canvas: const Color(0xFF232428),
      chrome: const Color(0xF5FFFFFF),
      chromeBorder: premium?.border ?? const Color(0x1F000000),
      control: premium?.mutedSurface ?? const Color(0x0A000000),
      controlHover: premium?.hover ?? const Color(0x14000000),
      controlActive: premium?.selected ?? const Color(0x1F000000),
      textPrimary: premium?.textPrimary ?? const Color(0xFF1F2024),
      textSecondary: premium?.textSecondary ?? const Color(0xFF5B5D66),
      textMuted: premium?.textMuted ?? const Color(0xFF8A8C96),
      accent: premium?.accent ?? const Color(0xFF3B6FF5),
      onAccent: premium?.onAccent ?? const Color(0xFFFFFFFF),
      divider: premium?.border ?? const Color(0x14000000),
      shadow: const Color(0x2E101114),
    );
  }

  final Brightness brightness;

  /// Covers the app behind the editor.
  final Color backdrop;

  /// The area the photo floats on.
  final Color canvas;

  /// Header and side panel surfaces.
  final Color chrome;
  final Color chromeBorder;
  final Color control;
  final Color controlHover;
  final Color controlActive;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color divider;
  final Color shadow;
}

/// Motion tuned to feel immediate but never bouncy.
class ImageEditorMotion {
  const ImageEditorMotion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration reveal = Duration(milliseconds: 240);
  static const Curve curve = Curves.easeOutCubic;
}
