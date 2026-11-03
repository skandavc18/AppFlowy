import 'dart:math' as math;

import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

abstract final class ObjectTypeTypography {
  static const cssFontWeight = FontWeight.w500;

  /// The weight emphasised text sits at inside a table cell.
  ///
  /// One step above ordinary body copy rather than the editor's full bold:
  /// [FontWeight.bold] is what a hand-bolded span already uses, so a header
  /// set at it shouts and reads as marked-up text rather than as a heading.
  static const emphasisFontWeight = FontWeight.w600;
  static const letterSpacingEm = -0.01;
  static const editorFontSize = 16.0;
  static const editorLineHeight = 1.6;
  static const lightEditorTextColor = Color(0xFF2C2C2C);
  static const _windowsEditorTextShadows = <Shadow>[
    Shadow(
      color: Color(0x18000000),
    ),
  ];
  static const _macOSEditorTextShadows = <Shadow>[
    Shadow(
      color: Color(0x0C000000),
    ),
  ];
  static const _linuxEditorTextShadows = <Shadow>[
    Shadow(
      color: Color(0x12000000),
    ),
  ];

  static double letterSpacingForFontSize(double fontSize) =>
      fontSize * letterSpacingEm;

  /// Every desktop platform sets this text in the same bundled Inter, so one
  /// weight serves them all.
  static FontWeight fontWeightForPlatform(TargetPlatform platform) =>
      cssFontWeight;

  /// Whether [platform] sets ObjectType text in the bundled Inter rather than
  /// its system face.
  static bool usesBundledFontForPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows =>
          true,
        TargetPlatform.android ||
        TargetPlatform.fuchsia ||
        TargetPlatform.iOS =>
          false,
      };

  /// The `wght` axis for [weight] on the shared ladder, or null where the
  /// system face picks its own weight.
  ///
  /// Inter itself is cut into static weights, so this only matters to a
  /// variable face that inherits the style, such as inline code.
  static List<FontVariation>? fontVariationsForPlatform(
    TargetPlatform platform,
    FontWeight weight,
  ) =>
      usesBundledFontForPlatform(platform)
          ? flowyFontVariationsForWeight(weight)
          : null;

  static Color editorTextColorForBrightness(
    Brightness brightness,
    Color fallback,
  ) =>
      brightness == Brightness.light ? lightEditorTextColor : fallback;

  static List<Shadow> editorTextShadowsForPlatform(
    TargetPlatform platform,
    Brightness brightness,
  ) {
    if (brightness == Brightness.dark) {
      return const [];
    }

    return switch (platform) {
      TargetPlatform.windows => _windowsEditorTextShadows,
      TargetPlatform.macOS => _macOSEditorTextShadows,
      TargetPlatform.linux => _linuxEditorTextShadows,
      _ => const [],
    };
  }

  static TextStyle enhanceEditorTextStyle(
    TextStyle style, {
    required TargetPlatform platform,
    required Brightness brightness,
    required Color fallbackColor,
  }) {
    return style.copyWith(
      color: editorTextColorForBrightness(brightness, fallbackColor),
      shadows: editorTextShadowsForPlatform(platform, brightness),
    );
  }

  /// Lifts table header and bolded cells above the text around them without
  /// ever going below it, and moves the variable-weight axis with the weight
  /// so a variable face actually responds.
  static TextStyle emphasizeTableCellText(TextStyle style) {
    final base = style.fontWeight ?? FontWeight.w400;
    final weight =
        base.index >= emphasisFontWeight.index ? base : emphasisFontWeight;
    final variations = style.fontVariations;
    if (variations == null) {
      return style.copyWith(fontWeight: weight);
    }
    return style.copyWith(
      fontWeight: weight,
      fontVariations: [
        for (final variation in variations)
          if (variation.axis == 'wght')
            FontVariation.weight(
              math.max(variation.value, weight.value.toDouble()),
            )
          else
            variation,
      ],
    );
  }

  static String fontFamilyForPlatform(TargetPlatform platform) {
    if (usesBundledFontForPlatform(platform)) {
      return bundledFontFamily;
    }
    return platform == TargetPlatform.iOS ? '.AppleSystemUIFont' : 'Roboto';
  }

  static List<String> fontFamilyFallbackForPlatform(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.fuchsia => const [
          'Helvetica Neue',
          'Arial',
          'Noto Sans Arabic',
          'Noto Sans Hebrew',
        ],
      TargetPlatform.iOS || TargetPlatform.macOS => const [
          '.AppleSystemUIFont',
          'SF Pro Text',
          'Helvetica Neue',
          'Arial',
          'Apple Color Emoji',
          'Noto Sans Arabic',
          'Noto Sans Hebrew',
        ],
      TargetPlatform.linux => const [
          'Roboto',
          'Helvetica Neue',
          'Arial',
          'Noto Sans',
          'Noto Sans Arabic',
          'Noto Sans Hebrew',
        ],
      TargetPlatform.windows => const [
          'Segoe UI',
          'Roboto',
          'Helvetica Neue',
          'Arial',
          'Segoe UI Emoji',
          'Segoe UI Symbol',
          'Noto Sans Arabic',
          'Noto Sans Hebrew',
        ],
    };
  }

  static TextStyle textStyleForPlatform(
    TargetPlatform platform, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    final resolvedFontWeight = fontWeight ?? fontWeightForPlatform(platform);
    return TextStyle(
      color: color,
      fontFamily: fontFamilyForPlatform(platform),
      fontFamilyFallback: fontFamilyFallbackForPlatform(platform),
      fontSize: fontSize,
      fontWeight: resolvedFontWeight,
      fontVariations: fontVariationsForPlatform(platform, resolvedFontWeight),
      letterSpacing:
          fontSize == null ? null : letterSpacingForFontSize(fontSize),
      height: height,
    );
  }
}
