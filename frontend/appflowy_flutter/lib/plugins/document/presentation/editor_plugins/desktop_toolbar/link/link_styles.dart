import 'package:appflowy/plugins/document/presentation/editor_chrome_style.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class LinkStyle {
  static Color borderColor(BuildContext context) =>
      Theme.of(context).isLightMode ? Color(0xFFE8ECF3) : Color(0x64BDBDBD);

  static InputDecoration buildLinkTextFieldInputDecoration(
    String hintText,
    BuildContext context, {
    bool showErrorBorder = false,
    EdgeInsets? contentPadding,
    double? radius,
  }) {
    final theme = AppFlowyTheme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius ?? 8.0)),
      borderSide: BorderSide(color: borderColor(context)),
    );
    final enableBorder = border.copyWith(
      borderSide: BorderSide(
        color: showErrorBorder
            ? theme.textColorScheme.error
            : theme.fillColorScheme.themeThick,
      ),
    );
    final hintStyle = EditorChromeStyle.textStyle(context).copyWith(
      height: 20 / 14,
      color: theme.textColorScheme.tertiary,
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle,
      contentPadding: contentPadding ?? const EdgeInsets.fromLTRB(8, 6, 8, 6),
      isDense: true,
      border: border,
      enabledBorder: border,
      focusedBorder: enableBorder,
    );
  }
}
