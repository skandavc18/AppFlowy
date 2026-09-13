import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

import 'astrology_model.dart';

/// Semantic colors shared by the native astrology views and their overlays.
/// Also works in a plain MaterialApp, without an AppFlowyTheme ancestor.
@immutable
class AstrologyPalette {
  const AstrologyPalette._({
    required this.surface,
    required this.raised,
    required this.control,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.line,
    required this.hover,
    required this.selection,
    required this.danger,
    required bool isDark,
    required bool isPaper,
  })  : _isDark = isDark,
        _isPaper = isPaper;

  factory AstrologyPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final premium = PremiumThemeExtension.maybeOf(context);
    final dark = theme.brightness == Brightness.dark;
    final paper =
        !dark && (PaperTheme.isEnabled(context) || (premium?.isPaper ?? false));
    // A paper flag can precede the premium extension during a theme change.
    // Never let an old, non-paper extension introduce cold popup surfaces.
    final tokens = paper && !(premium?.isPaper ?? false) ? null : premium;
    final surface = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      tokens?.surface ?? colors.surface,
      isPaper: paper,
    );
    final accent =
        tokens?.accent ?? (paper ? PaperTheme.accent : colors.primary);

    return AstrologyPalette._(
      surface: surface,
      raised: tokens?.floatingSurface ??
          (paper ? PaperTheme.popupBackground : colors.surfaceContainerLow),
      control: tokens?.mutedSurface ??
          (paper ? PaperTheme.controlBackground : colors.surfaceContainer),
      ink: tokens?.textPrimary ??
          (paper ? PaperTheme.textPrimary : colors.onSurface),
      muted: tokens?.textSecondary ??
          (paper ? PaperTheme.textSecondary : colors.onSurfaceVariant),
      accent: accent,
      line: tokens?.border ??
          (paper ? PaperTheme.codeBlockBorder : colors.outlineVariant),
      hover: tokens?.hover ??
          (paper ? PaperTheme.controlHover : colors.surfaceContainerHigh),
      selection: tokens?.selected ??
          (paper
              ? PaperTheme.controlSelectedHover
              : Color.alphaBlend(accent.withValues(alpha: 0.14), surface)),
      danger: paper ? const Color(0xFF95534B) : colors.error,
      isDark: dark,
      isPaper: paper,
    );
  }

  final Color surface;
  final Color raised;
  final Color control;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color line;
  final Color hover;
  final Color selection;
  final Color danger;
  final bool _isDark;
  final bool _isPaper;

  /// Muted planetary inks, not background colors. A null body is a lagna.
  Color planetColor(VedicBody? body) {
    if (body == null) return accent;
    if (body == VedicBody.moon) return muted;

    final hue = switch (body) {
      VedicBody.sun => 38.0,
      VedicBody.mars => 12.0,
      VedicBody.mercury => 150.0,
      VedicBody.jupiter => 46.0,
      VedicBody.venus => 325.0,
      VedicBody.saturn => 260.0,
      VedicBody.rahu => 215.0,
      VedicBody.ketu => 24.0,
      VedicBody.moon => 38.0,
    };
    var hsl = HSLColor.fromAHSL(
      1,
      hue,
      _isPaper ? 0.30 : 0.46,
      _isDark ? 0.74 : 0.36,
    );
    // Small abbreviations need contrast on selected/hovered cells, too.
    for (var attempt = 0; attempt < 12; attempt++) {
      final color = hsl.toColor();
      if ([surface, hover, selection].every(
        (background) => _contrast(color, background) >= 4.5,
      )) {
        return color;
      }
      hsl = hsl.withLightness(
        (hsl.lightness + (_isDark ? 0.025 : -0.025)).clamp(0.0, 1.0),
      );
    }
    return hsl.toColor();
  }

  static double _contrast(Color foreground, Color background) {
    final a = foreground.computeLuminance();
    final b = background.computeLuminance();
    return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
  }
}
