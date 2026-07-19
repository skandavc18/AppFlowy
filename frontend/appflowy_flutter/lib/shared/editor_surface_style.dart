import 'package:flutter/material.dart';

abstract final class EditorSurfaceStyle {
  static const lightCanvasBackground = Color(0xFFFDFCFB);
  static const lightPreviewBackground = Color(0xFFFCFBF9);
  static const lightCodeBlockBackground = Color(0xFFF7F4ED);
  static const lightCalloutBackground = Color(0xFFF8F5EE);

  static Color canvasBackgroundFor(
    Brightness brightness,
    Color darkFallback,
  ) =>
      brightness == Brightness.light ? lightCanvasBackground : darkFallback;

  static Color previewBackgroundFor(
    Brightness brightness,
    Color darkFallback,
  ) =>
      brightness == Brightness.light ? lightPreviewBackground : darkFallback;

  static Color codeBlockBackgroundFor(
    Brightness brightness,
    Color darkFallback,
  ) =>
      brightness == Brightness.light ? lightCodeBlockBackground : darkFallback;

  static Color calloutBackgroundFor(
    Brightness brightness,
    Color darkFallback,
  ) =>
      brightness == Brightness.light ? lightCalloutBackground : darkFallback;
}
