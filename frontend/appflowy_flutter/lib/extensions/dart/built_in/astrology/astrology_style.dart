import 'dart:math' as math;

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
    required this.onAccent,
    required this.shadow,
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
      onAccent:
          tokens?.onAccent ?? (paper ? PaperTheme.onAccent : colors.onPrimary),
      shadow: paper
          ? const Color(0x1A6B4B2A)
          : tokens?.shadow ?? Colors.black.withValues(alpha: dark ? 0.5 : 0.14),
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

  /// Text and icons drawn on a filled [accent].
  final Color onAccent;

  /// Card shadow ink: warm in paper mode, never a cool grey.
  final Color shadow;
  final bool _isDark;
  final bool _isPaper;

  /// A resting card's shadow; [raised] is the hovered/focused lift.
  List<BoxShadow> cardShadow({bool raised = false}) => [
        BoxShadow(
          color: shadow.withValues(
            alpha: _isDark ? (raised ? 0.34 : 0.22) : (raised ? 0.12 : 0.06),
          ),
          blurRadius: raised ? 16 : 8,
          spreadRadius: -3,
          offset: Offset(0, raised ? 6 : 2),
        ),
      ];

  /// A contact shadow that seats a card on the page, under a soft ambient
  /// one that deepens as the card [lifted] toward the pointer.
  List<BoxShadow> depthShadow({bool lifted = false}) => [
        BoxShadow(
          color: shadow.withValues(alpha: _isDark ? 0.32 : 0.08),
          blurRadius: lifted ? 3 : 2,
          offset: Offset(0, lifted ? 1.5 : 1),
        ),
        BoxShadow(
          color: shadow.withValues(
            alpha: _isDark ? (lifted ? 0.36 : 0.24) : (lifted ? 0.1 : 0.07),
          ),
          blurRadius: lifted ? 18 : 14,
          spreadRadius: lifted ? -5 : -4,
          offset: Offset(0, lifted ? 7 : 5),
        ),
      ];

  /// Muted planetary inks, not background colors. A null body is a lagna.
  Color planetColor(VedicBody? body) {
    if (body == null) return accent;
    if (body == VedicBody.moon) return muted;

    var hsl = HSLColor.fromAHSL(
      1,
      _hue(body),
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

  /// Spread around the wheel so the nine lords stay distinct side by side.
  static double _hue(VedicBody body) => switch (body) {
        VedicBody.mars => 2.0,
        VedicBody.sun => 28.0,
        VedicBody.jupiter => 46.0,
        VedicBody.mercury => 142.0,
        VedicBody.moon => 188.0,
        VedicBody.rahu => 220.0,
        VedicBody.saturn => 250.0,
        VedicBody.ketu => 282.0,
        VedicBody.venus => 322.0,
      };

  static const _darkInk = Color(0xFF17171C);

  /// A lord's gentle tone for its own cards, badges and rails. Fills are
  /// opaque on [surface], and the tone's ink reads on every one of them.
  AstrologyTone planetTone(VedicBody body) {
    final hue = _hue(body);
    // The Moon is pearl rather than a strong color.
    final chroma = body == VedicBody.moon ? 0.8 : 1.0;
    final saturation = (_isDark
            ? 0.5
            : _isPaper
                ? 0.42
                : 0.56) *
        chroma;
    final mark = HSLColor.fromAHSL(
      1,
      hue,
      saturation,
      _isDark
          ? 0.66
          : _isPaper
              ? 0.5
              : 0.54,
    ).toColor();
    // Cool tints fade toward grey on warm light surfaces; dark ones don't.
    final strength = (_isDark
            ? 0.11
            : _isPaper
                ? 0.065
                : 0.075) *
        (!_isDark && hue >= 170 && hue <= 265 ? 1.25 : 1.0);
    Color over(Color base, double alpha) =>
        Color.alphaBlend(mark.withValues(alpha: alpha), base);
    final wash = over(surface, strength * 0.35);
    final fill = over(surface, strength);
    final fillStrong = over(surface, strength * 1.7);
    final chip = over(fillStrong, _isDark ? 0.22 : 0.18);
    var ink = HSLColor.fromAHSL(
      1,
      hue,
      math.min(saturation, 0.55),
      _isDark ? 0.8 : 0.32,
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      final color = ink.toColor();
      if ([surface, wash, fill, fillStrong, chip].every(
        (background) => _contrast(color, background) >= 4.5,
      )) {
        break;
      }
      ink = ink.withLightness(
        (ink.lightness + (_isDark ? 0.02 : -0.02)).clamp(0.0, 1.0),
      );
    }
    return AstrologyTone(
      mark: mark,
      wash: wash,
      fill: fill,
      fillStrong: fillStrong,
      chip: chip,
      ink: ink.toColor(),
      onMark: _contrast(Colors.white, mark) >= _contrast(_darkInk, mark)
          ? Colors.white
          : _darkInk,
      glow: mark.withValues(alpha: _isDark ? 0.3 : 0.24),
    );
  }

  static double _contrast(Color foreground, Color background) {
    final a = foreground.computeLuminance();
    final b = background.computeLuminance();
    return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
  }
}

/// One lord's colors, from [AstrologyPalette.planetTone].
@immutable
class AstrologyTone {
  const AstrologyTone({
    required this.mark,
    required this.wash,
    required this.fill,
    required this.fillStrong,
    required this.chip,
    required this.ink,
    required this.onMark,
    required this.glow,
  });

  /// The lord's own color: filled badges, rails and progress.
  final Color mark;

  /// Where a card's gradient fades out.
  final Color wash;

  /// A resting card.
  final Color fill;

  /// A hovered, focused or running card.
  final Color fillStrong;

  /// A badge or pill on a card.
  final Color chip;

  /// Text and icons in this tone.
  final Color ink;

  /// Text on a solid [mark].
  final Color onMark;

  /// The colored shadow under a running card.
  final Color glow;
}
