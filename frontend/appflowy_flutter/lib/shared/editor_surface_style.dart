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
}
