import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

// Keep the persisted default value empty so existing settings remain compatible.
const defaultFontFamily = '';

const preferredFontFamily = 'DM Sans';
const bundledFontFamily = 'Inter';
const builtInCodeFontFamily = 'RobotoMono';
const defaultFontWeight = flowyRegularFontWeight;
const defaultFontWeightValue = flowyRegularFontWeightValue;
const defaultFontVariations = flowyRegularFontVariations;
const emphasizedFontWeight = FontWeight.w600;
const defaultLetterSpacing = -0.005;
const defaultFontFamilyFallback = [bundledFontFamily];

String resolveFontFamily(String? fontFamily) =>
    fontFamily == null || fontFamily.isEmpty ? preferredFontFamily : fontFamily;

abstract class BaseAppearance {
  final white = const Color(0xFFFFFFFF);

  final Set<WidgetState> scrollbarInteractiveStates = <WidgetState>{
    WidgetState.pressed,
    WidgetState.hovered,
    WidgetState.dragged,
  };

  TextStyle getFontStyle({
    required String fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    Color? fontColor,
    double? letterSpacing,
    double? lineHeight,
  }) {
    fontSize = fontSize ?? FontSizes.s14;
    fontWeight = fontWeight ?? defaultFontWeight;
    letterSpacing = fontSize * (letterSpacing ?? defaultLetterSpacing);

    return getGoogleFontSafely(
      fontFamily,
      fontSize: fontSize,
      fontColor: fontColor,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      lineHeight: lineHeight,
    );
  }

  TextTheme getTextTheme({
    required String fontFamily,
    required Color fontColor,
  }) {
    return TextTheme(
      displayLarge: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s32,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 40.0 / 32.0,
      ),
      displayMedium: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s24,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 34.0 / 24.0,
      ),
      displaySmall: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s20,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 28.0 / 20.0,
      ),
      headlineLarge: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s24,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 32.0 / 24.0,
      ),
      headlineMedium: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s20,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 28.0 / 20.0,
      ),
      headlineSmall: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s18,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 26.0 / 18.0,
      ),
      titleLarge: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s18,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 26.0 / 18.0,
      ),
      titleMedium: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s16,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 24.0 / 16.0,
      ),
      titleSmall: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s14,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 20.0 / 14.0,
      ),
      bodyLarge: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s16,
        fontColor: fontColor,
        lineHeight: 24.0 / 16.0,
      ),
      bodyMedium: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s14,
        fontColor: fontColor,
        lineHeight: 21.0 / 14.0,
      ),
      bodySmall: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s12,
        fontColor: fontColor,
        fontWeight: defaultFontWeight,
        lineHeight: 18.0 / 12.0,
      ),
      labelLarge: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s14,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 20.0 / 14.0,
      ),
      labelMedium: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s12,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 18.0 / 12.0,
      ),
      labelSmall: getFontStyle(
        fontFamily: fontFamily,
        fontSize: FontSizes.s11,
        fontColor: fontColor,
        fontWeight: emphasizedFontWeight,
        lineHeight: 16.0 / 11.0,
      ),
    );
  }

  ThemeData getThemeData(
    AppTheme appTheme,
    Brightness brightness,
    String fontFamily,
    String codeFontFamily,
  );
}
