import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

import 'excalidraw_painter.dart';

/// The colours the drawing surface and its chrome are dressed in.
///
/// A scene carries its own `viewBackgroundColor`, but a white sheet inside a
/// dark page reads as a hole, so a drawing that has not chosen a background
/// takes the application's canvas instead.
@immutable
class DrawPalette {
  const DrawPalette({
    required this.brightness,
    required this.canvas,
    required this.chrome,
    required this.chromeHover,
    required this.border,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.shadow,
    required this.strokeSwatches,
    required this.fillSwatches,
  });

  factory DrawPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final isPaper = !isDark && PaperTheme.isEnabled(context);

    if (isPaper) {
      return const DrawPalette(
        brightness: Brightness.light,
        canvas: PaperTheme.editorPreviewBackground,
        chrome: PaperTheme.popupBackground,
        chromeHover: PaperTheme.controlHover,
        border: PaperTheme.strongBorder,
        ink: PaperTheme.textPrimary,
        inkMuted: PaperTheme.textMuted,
        accent: PaperTheme.accent,
        accentSoft: Color(0x1A715438),
        onAccent: PaperTheme.onAccent,
        shadow: PaperTheme.shadow,
        strokeSwatches: _paperStrokes,
        fillSwatches: _paperFills,
      );
    }

    final accent = premium?.accent ?? theme.colorScheme.primary;
    return DrawPalette(
      brightness: brightness,
      canvas: premium?.canvas ?? theme.colorScheme.surface,
      chrome: premium?.floatingSurface ?? theme.colorScheme.surfaceBright,
      chromeHover: premium?.hover ?? theme.colorScheme.surfaceContainerHighest,
      border: premium?.border ?? theme.colorScheme.outlineVariant,
      ink: premium?.textPrimary ?? theme.colorScheme.onSurface,
      inkMuted: premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant,
      accent: accent,
      accentSoft: accent.withValues(alpha: isDark ? 0.22 : 0.12),
      onAccent: premium?.onAccent ?? theme.colorScheme.onPrimary,
      shadow: (premium?.shadow ?? Colors.black)
          .withValues(alpha: isDark ? 0.44 : 0.12),
      strokeSwatches: isDark ? _darkStrokes : _lightStrokes,
      fillSwatches: isDark ? _darkFills : _lightFills,
    );
  }

  final Brightness brightness;
  final Color canvas;
  final Color chrome;
  final Color chromeHover;
  final Color border;
  final Color ink;
  final Color inkMuted;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color shadow;
  final List<String> strokeSwatches;
  final List<String> fillSwatches;

  /// The sheet colour, honouring a scene that asked for one.
  Color canvasFor(String stored) {
    final chosen = drawColour(stored, brightness);
    if (chosen == null) {
      return canvas;
    }
    // A default white sheet follows the theme instead; anything a person
    // actually picked is respected.
    final isDefaultWhite = stored.toLowerCase() == '#ffffff';
    return isDefaultWhite ? canvas : chosen;
  }

  /// The default stroke colour for the current appearance, so a new shape is
  /// visible on the sheet it lands on.
  String get defaultStroke =>
      brightness == Brightness.dark ? '#e3e3e3' : '#1e1e1e';
}

const _lightStrokes = <String>[
  '#1e1e1e',
  '#e03131',
  '#2f9e44',
  '#1971c2',
  '#f08c00',
  '#9c36b5',
  '#0c8599',
];

const _darkStrokes = <String>[
  '#e3e3e3',
  '#ff8787',
  '#69db7c',
  '#74c0fc',
  '#ffd43b',
  '#da77f2',
  '#66d9e8',
];

const _paperStrokes = <String>[
  '#3b352e',
  '#a34b45',
  '#4f7a53',
  '#4b6a92',
  '#b3803c',
  '#7a5b8f',
  '#3f7f8c',
];

const _lightFills = <String>[
  'transparent',
  '#ffc9c9',
  '#b2f2bb',
  '#a5d8ff',
  '#ffec99',
  '#eebefa',
  '#e9ecef',
];

const _darkFills = <String>[
  'transparent',
  '#5b2c2c',
  '#2b5b36',
  '#24466b',
  '#5c4b1c',
  '#4b2d59',
  '#343a40',
];

const _paperFills = <String>[
  'transparent',
  '#efd8cf',
  '#dbe7d4',
  '#d6e0ec',
  '#f0e2c2',
  '#e4d8ea',
  '#e8e2d6',
];
