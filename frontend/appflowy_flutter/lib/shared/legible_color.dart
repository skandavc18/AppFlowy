import 'package:flutter/material.dart';

/// Keeps a fixed hue — a brand's, a category's, a language's — readable on
/// whatever surface the active theme puts beneath it.
///
/// Brand colours are published for a white page. GitHub's is almost black, so
/// on a dark surface it vanishes; GitLab's orange is too pale for small text on
/// cream. Neither hue has to change to read, only its lightness, so that is the
/// only thing [LegibleColor.on] moves. A colour that already reads comes back
/// untouched, which leaves every brand exactly as published where it works.
abstract final class LegibleColor {
  /// WCAG 2 minimum for body text.
  static const double text = 4.5;

  /// WCAG 2 minimum for glyphs, outlines and large text.
  static const double glyph = 3.0;

  /// Below this chroma a colour is ink rather than a hue.
  static const double _inkChroma = 0.15;

  /// The WCAG contrast ratio of two opaque colours, from 1 to 21.
  static double contrast(Color a, Color b) {
    final first = a.computeLuminance();
    final second = b.computeLuminance();
    final lighter = first > second ? first : second;
    final darker = first > second ? second : first;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// [color], moved along its own lightness until it reaches [minimum]
  /// contrast against the opaque [background]. Alpha is kept as given.
  ///
  /// Ink — a colour with next to no hue, like GitHub's — is mirrored rather
  /// than nudged: on a dark surface it becomes chalk, not a mid grey that
  /// reads as disabled.
  static Color on(Color background, Color color, {double minimum = text}) {
    final opaque = color.withValues(alpha: 1);
    if (contrast(opaque, background) >= minimum) {
      return color;
    }
    final hsl = HSLColor.fromColor(opaque);
    final lighten = contrast(Colors.white, background) >=
        contrast(Colors.black, background);
    final end = lighten ? 1.0 : 0.0;

    var start = hsl.lightness;
    final chroma = (1 - (2 * hsl.lightness - 1).abs()) * hsl.saturation;
    if (chroma < _inkChroma) {
      final mirrored = 1 - hsl.lightness;
      if (lighten ? mirrored > start : mirrored < start) {
        start = mirrored;
        final candidate = hsl.withLightness(start).toColor();
        if (contrast(candidate, background) >= minimum) {
          return candidate.withValues(alpha: color.a);
        }
      }
    }

    final extreme = hsl.withLightness(end).toColor();
    if (contrast(extreme, background) < minimum) {
      return extreme.withValues(alpha: color.a);
    }
    // Lightness is monotonic in every channel for a fixed hue and saturation,
    // so the smallest move that reads is a plain bisection away from [start].
    var failing = start;
    var passing = end;
    for (var step = 0; step < 18; step++) {
      final middle = (failing + passing) / 2;
      if (contrast(hsl.withLightness(middle).toColor(), background) >=
          minimum) {
        passing = middle;
      } else {
        failing = middle;
      }
    }
    return hsl.withLightness(passing).toColor().withValues(alpha: color.a);
  }

  /// The ink for [accent] on a tile or chip washed with [wash] of itself over
  /// [surface] — how most accent glyphs and labels are drawn. Measured against
  /// the washed fill, so the tint never eats into the contrast.
  static Color onWash(
    Color surface,
    Color accent, {
    required double wash,
    double minimum = text,
  }) {
    var ink = on(surface, accent, minimum: minimum);
    // The fill follows the ink, so settle the pair rather than measuring once.
    for (var pass = 0; pass < 3; pass++) {
      final fill = Color.alphaBlend(ink.withValues(alpha: wash), surface);
      final next = on(fill, ink, minimum: minimum);
      if (next == ink) {
        break;
      }
      ink = next;
    }
    return ink;
  }
}
