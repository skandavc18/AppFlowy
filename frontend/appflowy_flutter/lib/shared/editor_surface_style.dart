import 'package:flutter/material.dart';

import 'paper_theme.dart';

abstract final class EditorSurfaceStyle {
  static const lightCanvasBackground = PaperTheme.editorBackground;
  static const lightPreviewBackground = PaperTheme.editorPreviewBackground;
  static const lightCodeBlockBackground = PaperTheme.codeBlockBackground;
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

  static Color calloutBackgroundFor(
    Brightness brightness,
    Color fallback, {
    bool isPaper = false,
  }) =>
      brightness == Brightness.light && isPaper
          ? lightCalloutBackground
          : fallback;
}
