import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

abstract final class AppFlowyEditorMenuStyle {
  static const menuWidth = 280.0;
  static const slashMenuMaxHeight = 400.0;
  static const slashMenuContentMaxHeight = slashMenuMaxHeight - 16.0;
  static const contextMenuEstimatedHeight = 192.0;

  static TextStyle itemTextStyle(
    BuildContext context, {
    Color? color,
  }) {
    final appTheme = AppFlowyTheme.of(context);
    return _polish(
      context,
      appTheme.textStyle.body.standard(
        color: color ?? appTheme.textColorScheme.primary,
      ),
    );
  }

  static TextStyle sectionTextStyle(BuildContext context) {
    final appTheme = AppFlowyTheme.of(context);
    return _polish(
      context,
      appTheme.textStyle.caption
          .enhanced(
            color: appTheme.textColorScheme.tertiary,
          )
          .copyWith(
            fontSize: 12,
            height: 16 / 12,
          ),
    );
  }

  static TextStyle shortcutTextStyle(BuildContext context) {
    final appTheme = AppFlowyTheme.of(context);
    return _polish(
      context,
      appTheme.textStyle.caption
          .standard(
            color: appTheme.textColorScheme.secondary,
          )
          .copyWith(
            fontSize: 12,
            height: 16 / 12,
          ),
    );
  }

  static TextStyle badgeTextStyle(BuildContext context) {
    final appTheme = AppFlowyTheme.of(context);
    return _polish(
      context,
      appTheme.textStyle.caption
          .enhanced(
            color: appTheme.textColorScheme.featured,
          )
          .copyWith(
            fontSize: 12,
            height: 16 / 12,
          ),
    );
  }

  static TextStyle _polish(BuildContext context, TextStyle style) {
    final brightness = Theme.of(context).brightness;
    return AppTextRendering.polish(style).copyWith(
      shadows: AppTextRendering.rootStyleFor(brightness).shadows,
    );
  }
}
