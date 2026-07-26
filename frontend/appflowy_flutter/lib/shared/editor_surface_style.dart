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

  /// A hairline edge for floating chrome — menus, chips, toolbars.
  ///
  /// Document cards do not use this: their depth comes from [embedShadow]
  /// alone, so nothing in a page is drawn inside an outline.
  static Color embedBorder(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final base =
        theme.brightness == Brightness.light && PaperTheme.isEnabled(context)
            ? PaperTheme.strongBorder
            : premium?.border ?? theme.colorScheme.outlineVariant;
    return base.withValues(alpha: 0.38);
  }

  /// Soft, layered depth that lifts an embed off the page — the only thing
  /// that separates a document card from the canvas behind it.
  ///
  /// Two shadows do the work an outline used to. A wide ambient one gives the
  /// card height; a tight contact one keeps its edge legible where it meets
  /// the page. In dark themes a luminous hairline replaces the contact
  /// shadow, because black on near-black reads as nothing at all.
  ///
  /// [raised] deepens the whole set while the pointer rests on the card or
  /// something inside it holds focus. The character never changes, only the
  /// height.
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
          alpha: raised ? (isDark ? 0.28 : 0.11) : (isDark ? 0.2 : 0.065),
        ),
        blurRadius: raised ? 32 : 23,
        offset: Offset(0, raised ? 13 : 9),
        spreadRadius: -11,
      ),
      if (isDark)
        BoxShadow(
          color: Colors.white.withValues(alpha: raised ? 0.1 : 0.07),
          spreadRadius: 0.6,
        )
      else
        BoxShadow(
          color: color.withValues(alpha: raised ? 0.06 : 0.045),
          blurRadius: raised ? 5 : 3,
          offset: Offset(0, raised ? 2 : 1),
          spreadRadius: -2,
        ),
    ];
  }
}
