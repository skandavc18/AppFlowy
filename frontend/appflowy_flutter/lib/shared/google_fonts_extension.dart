import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _localFontFamilies = [
  preferredFontFamily,
  bundledFontFamily,
  builtInCodeFontFamily,
];

// DM Sans provides the rounded default UI face, with bundled Inter as fallback.
TextStyle getGoogleFontSafely(
  String fontFamily, {
  FontWeight? fontWeight,
  double? fontSize,
  Color? fontColor,
  double? letterSpacing,
  double? lineHeight,
}) {
  final resolvedFontFamily = resolveFontFamily(fontFamily);
  final fontVariations =
      fontWeight == null ? null : flowyFontVariationsForWeight(fontWeight);
  final TextStyle style;
  if (_localFontFamilies.contains(resolvedFontFamily)) {
    style = TextStyle(
      fontFamily: resolvedFontFamily,
      fontFamilyFallback: resolvedFontFamily == bundledFontFamily
          ? null
          : defaultFontFamilyFallback,
      fontWeight: fontWeight,
      fontVariations: fontVariations,
      fontSize: fontSize,
      color: fontColor,
      letterSpacing: letterSpacing,
      height: lineHeight,
    );
  } else if (GoogleFonts.asMap().containsKey(resolvedFontFamily)) {
    style = GoogleFonts.getFont(
      resolvedFontFamily,
      fontWeight: fontWeight,
      fontSize: fontSize,
      color: fontColor,
      letterSpacing: letterSpacing,
      height: lineHeight,
    ).copyWith(
      fontVariations: fontVariations,
      fontFamilyFallback: const [
        preferredFontFamily,
        bundledFontFamily,
      ],
    );
  } else {
    style = TextStyle(
      fontFamily: preferredFontFamily,
      fontFamilyFallback: defaultFontFamilyFallback,
      fontWeight: fontWeight,
      fontVariations: fontVariations,
      fontSize: fontSize,
      color: fontColor,
      letterSpacing: letterSpacing,
      height: lineHeight,
    );
  }

  return AppTextRendering.polish(style);
}
