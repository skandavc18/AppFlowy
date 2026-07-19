import 'package:appflowy/shared/object_type_typography.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:flutter/material.dart';

enum EditorToolbarGlyph {
  textFormat('Aa'),
  bold('B'),
  underline('U'),
  italic('I');

  const EditorToolbarGlyph(this.text);

  final String text;
}

abstract final class EditorChromeStyle {
  static const lightForeground = Color(0xFF2C2C2C);
  static const darkForeground = Color(0xE6FFFFFF);
  static const lightIcon = Color(0xFF37352F);
  static const darkIcon = Color(0xE6FFFFFF);
  static const lightMenuBackground = Color(0xFFFFFEFC);
  static const menuFontWeight = FontWeight.w600;
  static const menuFontSize = 14.0;

  static Color foregroundFor(Brightness brightness) =>
      brightness == Brightness.light ? lightForeground : darkForeground;

  static Color iconColorFor(Brightness brightness) =>
      brightness == Brightness.light ? lightIcon : darkIcon;

  static Color iconColor(BuildContext context) =>
      iconColorFor(Theme.of(context).brightness);

  static TextStyle textStyleFor(
    TargetPlatform platform,
    Brightness brightness, {
    double fontSize = menuFontSize,
    FontWeight fontWeight = menuFontWeight,
  }) {
    final style = AppTextRendering.polish(
      ObjectTypeTypography.textStyleForPlatform(
        platform,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
    return ObjectTypeTypography.enhanceEditorTextStyle(
      style,
      platform: platform,
      brightness: brightness,
      fallbackColor: foregroundFor(brightness),
    );
  }

  static TextStyle textStyle(BuildContext context, {double? fontSize}) {
    final theme = Theme.of(context);
    return textStyleFor(
      theme.platform,
      theme.brightness,
      fontSize: fontSize ?? menuFontSize,
    );
  }

  static TextStyle toolbarLabelTextStyle(BuildContext context) {
    final theme = Theme.of(context);
    return textStyleFor(
      theme.platform,
      theme.brightness,
    ).copyWith(height: 20 / 14);
  }

  static TextStyle toolbarGlyphTextStyleFor(
    TargetPlatform platform,
    Brightness brightness,
    EditorToolbarGlyph glyph, {
    Color? color,
  }) {
    final fontSize = glyph == EditorToolbarGlyph.textFormat ? 16.0 : 18.0;
    final style = textStyleFor(
      platform,
      brightness,
      fontSize: fontSize,
      fontWeight:
          glyph == EditorToolbarGlyph.bold ? FontWeight.w700 : FontWeight.w600,
    );
    final effectiveColor = color ?? style.color;

    return style.copyWith(
      color: effectiveColor,
      height: 1,
      letterSpacing: glyph == EditorToolbarGlyph.textFormat ? -0.3 : 0,
      fontStyle: glyph == EditorToolbarGlyph.italic
          ? FontStyle.italic
          : FontStyle.normal,
      decoration: glyph == EditorToolbarGlyph.underline
          ? TextDecoration.underline
          : TextDecoration.none,
      decorationColor: effectiveColor,
      decorationThickness: glyph == EditorToolbarGlyph.underline ? 1.8 : null,
    );
  }

  static TextStyle toolbarGlyphTextStyle(
    BuildContext context,
    EditorToolbarGlyph glyph, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    return toolbarGlyphTextStyleFor(
      theme.platform,
      theme.brightness,
      glyph,
      color: color,
    );
  }

  static ThemeData themeData(BuildContext context) {
    final base = Theme.of(context);
    final textStyle = EditorChromeStyle.textStyle(context);
    final iconColor = iconColorFor(base.brightness);
    final menuBackground = base.brightness == Brightness.light
        ? lightMenuBackground
        : base.cardColor;

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        onSurface: iconColor,
      ),
      iconTheme: base.iconTheme.copyWith(color: iconColor),
      textTheme: base.textTheme.copyWith(
        bodyMedium: textStyle,
        bodySmall: textStyle.copyWith(fontSize: 12),
        labelLarge: textStyle,
        labelMedium: textStyle,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: menuBackground,
        textStyle: textStyle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuBackground),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          foregroundColor:
              WidgetStatePropertyAll(foregroundFor(base.brightness)),
          iconColor: WidgetStatePropertyAll(iconColor),
          textStyle: WidgetStatePropertyAll(textStyle),
        ),
      ),
    );
  }
}

class EditorToolbarGlyphIcon extends StatelessWidget {
  const EditorToolbarGlyphIcon({
    super.key,
    required this.glyph,
    this.color,
  });

  final EditorToolbarGlyph glyph;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        glyph.text,
        style: EditorChromeStyle.toolbarGlyphTextStyle(
          context,
          glyph,
          color: color,
        ),
      );
}

class EditorChromeTheme extends StatelessWidget {
  const EditorChromeTheme({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: EditorChromeStyle.themeData(context),
        child: child,
      );
}
