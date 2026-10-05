import 'package:flutter/material.dart';

/// The colours a row's values are drawn in, whichever view draws them.
///
/// Slides and the table views keep their own palettes; both hand the shared
/// value widgets these, so a status, a map or a file reads the same in each.
abstract interface class PropertyInk {
  Color get surface;
  Color get raised;
  Color get sunken;
  Color get hover;
  Color get border;
  Color get textPrimary;
  Color get textSecondary;
  Color get textMuted;
  Color get accent;
  Color get shadow;
  bool get isDark;
  List<BoxShadow> get chromeShadow;

  /// A steady colour for a value that has none of its own.
  Color swatchFor(String value);
}
