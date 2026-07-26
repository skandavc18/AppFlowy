import 'package:flutter/material.dart';

import 'paper_theme.dart';
import 'premium_theme.dart';

abstract final class EditorSurfaceStyle {
  static const lightCanvasBackground = PaperTheme.editorBackground;
  static const lightPreviewBackground = PaperTheme.editorPreviewBackground;
  static const lightCodeBlockBackground = PaperTheme.codeBlockBackground;
  static const lightCodeBlockHeaderBackground =
      PaperTheme.codeBlockHeaderBackground;
  static const lightCodeBlockBorder = PaperTheme.codeBlockBorder;
  static const lightCalloutBackground = PaperTheme.calloutBackground;

  static Color canvasBackgroundFor(
    Brightness brightness,
    Color fallback, {
    bool isPaper = false,
  }) =>
      brightness == Brightness.light && isPaper
          ? lightCanvasBackground
          : fallback;

  static Color previewBackgroundFor(
    Brightness brightness,
    Color fallback, {
    bool isPaper = false,
  }) =>
      brightness == Brightness.light && isPaper
          ? lightPreviewBackground
          : fallback;

  static Color codeBlockBackgroundFor(
    Brightness brightness,
    Color fallback, {
    bool isPaper = false,
  }) =>
      brightness == Brightness.light && isPaper
          ? lightCodeBlockBackground
          : fallback;

  static Color codeBlockHeaderBackgroundFor(
    Brightness brightness,
    Color fallback, {
    bool isPaper = false,
  }) =>
      brightness == Brightness.light && isPaper
          ? lightCodeBlockHeaderBackground
          : fallback;

  static Color codeBlockBorderFor(
    Brightness brightness,
    Color fallback, {
    bool isPaper = false,
  }) =>
      brightness == Brightness.light && isPaper
          ? lightCodeBlockBorder
          : fallback;

  static Color calloutBackgroundFor(
    Brightness brightness,
    Color fallback, {
    bool isPaper = false,
  }) =>
      brightness == Brightness.light && isPaper
          ? lightCalloutBackground
          : fallback;

  static Color inlineCodeBackground(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumThemeExtension.maybeOf(context)?.mutedSurface ??
        theme.colorScheme.surfaceContainer;
  }

  static Color inlineCodeForeground(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumThemeExtension.maybeOf(context)?.textPrimary ??
        theme.colorScheme.onSurface;
  }

  /// Corner radius shared by embedded blocks — file previews, media players
  /// and PDF shells.
  ///
  /// Matches the page and folder preview cards so every embed inside a
  /// document reads as the same kind of object.
  static const double embedCornerRadius = 20;

  static BorderRadius get embedBorderRadius =>
      BorderRadius.circular(embedCornerRadius);

  /// A hairline edge. Depth comes from [embedShadow], not from the border.
  static Color embedBorder(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final base =
        theme.brightness == Brightness.light && PaperTheme.isEnabled(context)
            ? PaperTheme.strongBorder
            : premium?.border ?? theme.colorScheme.outlineVariant;
    return base.withValues(alpha: 0.38);
  }

  /// Soft, single-source depth that lifts an embed off the page.
  ///
  /// [raised] deepens the shadow while the pointer rests on the card.
  static List<BoxShadow> embedShadow(
    BuildContext context, {
    bool raised = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = !isDark && PaperTheme.isEnabled(context)
        ? PaperTheme.shadow
        : PremiumThemeExtension.maybeOf(context)?.shadow ??
            Colors.black.withValues(alpha: 0.12);
    return [
      BoxShadow(
        color: color.withValues(
          alpha: raised ? (isDark ? 0.24 : 0.11) : (isDark ? 0.16 : 0.065),
        ),
        blurRadius: raised ? 32 : 23,
        offset: Offset(0, raised ? 13 : 9),
        spreadRadius: -11,
      ),
    ];
  }
}
