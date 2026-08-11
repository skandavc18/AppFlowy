import 'package:flutter/material.dart';

import '../paper_theme.dart';
import '../premium_theme.dart';
import 'mermaid_scene.dart';

/// Resolves the colours a diagram is drawn with from the application's own
/// theme, so a chart blends into the page instead of arriving with a
/// renderer's palette.
///
/// Light, dark and paper each get their own series set: the same hues at the
/// saturation and lightness that reads correctly on that surface.
MermaidPalette mermaidPaletteOf(BuildContext context) {
  final theme = Theme.of(context);
  final premium = PremiumThemeExtension.maybeOf(context);
  final isDark = theme.brightness == Brightness.dark;
  final isPaper = !isDark && PaperTheme.isEnabled(context);

  if (isPaper) {
    return const MermaidPalette(
      canvas: PaperTheme.editorBackground,
      surface: PaperTheme.popupBackground,
      surfaceStrong: PaperTheme.controlBackground,
      line: Color(0xFF8A7A66),
      lineSoft: Color(0x40675443),
      text: PaperTheme.textPrimary,
      textMuted: PaperTheme.textMuted,
      accent: PaperTheme.accent,
      accentSoft: Color(0x1A715438),
      onAccent: PaperTheme.onAccent,
      series: _paperSeries,
    );
  }

  final canvas = premium?.canvas ?? theme.colorScheme.surface;
  final surface = premium?.floatingSurface ?? theme.colorScheme.surfaceBright;
  final accent = premium?.accent ?? theme.colorScheme.primary;

  return MermaidPalette(
    canvas: canvas,
    surface: surface,
    surfaceStrong: premium?.mutedSurface ?? theme.colorScheme.surfaceContainer,
    line: (premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant)
        .withValues(alpha: isDark ? 0.74 : 0.62),
    lineSoft: (premium?.border ?? theme.colorScheme.outlineVariant)
        .withValues(alpha: isDark ? 0.55 : 0.7),
    text: premium?.textPrimary ?? theme.colorScheme.onSurface,
    textMuted: premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant,
    accent: accent,
    accentSoft: accent.withValues(alpha: isDark ? 0.20 : 0.10),
    onAccent: premium?.onAccent ?? theme.colorScheme.onPrimary,
    series: isDark ? _darkSeries : _lightSeries,
  );
}

/// The muted, evenly spaced hues used for pie slices, sections and accents.
///
/// They are deliberately desaturated: a diagram sitting inside a page of prose
/// should not shout louder than the prose.
const _lightSeries = <Color>[
  Color(0xFF5B8DEF),
  Color(0xFF57B894),
  Color(0xFFE0995E),
  Color(0xFFCE6E7C),
  Color(0xFF8F7BD3),
  Color(0xFF4FADC4),
  Color(0xFFBE9A4C),
  Color(0xFF7E8CA0),
];

const _darkSeries = <Color>[
  Color(0xFF7BA6F5),
  Color(0xFF6FC9A6),
  Color(0xFFE8AC74),
  Color(0xFFDE8391),
  Color(0xFFA694E0),
  Color(0xFF69C2D6),
  Color(0xFFD1AF64),
  Color(0xFF95A2B5),
];

const _paperSeries = <Color>[
  Color(0xFF6E7FA8),
  Color(0xFF6F9077),
  Color(0xFFBF8A55),
  Color(0xFFB0707A),
  Color(0xFF8A7BA4),
  Color(0xFF5F94A0),
  Color(0xFF9B8046),
  Color(0xFF87816F),
];
