import 'package:flutter/material.dart';

import 'paper_theme.dart';

abstract final class ContextMenuSurfaceStyle {
  static const lightBackground = PaperTheme.popupBackground;

  static Color backgroundFor(
    Brightness brightness,
    Color fallback, {
    bool isPaper = false,
  }) =>
      brightness == Brightness.light && isPaper ? lightBackground : fallback;

  static Color background(BuildContext context) => backgroundFor(
        Theme.of(context).brightness,
        Theme.of(context).cardColor,
        isPaper: PaperTheme.isEnabled(context),
      );
}
