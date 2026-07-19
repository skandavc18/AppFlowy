import 'package:appflowy/shared/object_type_typography.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

enum SidebarTextRole {
  standard,
  page,
  section,
}

abstract final class SidebarTypography {
  static const fontSize = 14.0;
  static const lineHeight = 20.0;
  static const pageFontSize = 15.0;
  static const pageLineHeight = 21.0;
  static const sectionFontSize = 11.0;
  static const sectionLineHeight = 16.0;
  static const sectionLetterSpacing = 0.5;
  // Prevent FlowyText from synthesizing a variable weight axis.
  static const fontVariations = <FontVariation>[];

  static double letterSpacingForFontSize(double fontSize) =>
      ObjectTypeTypography.letterSpacingForFontSize(fontSize);

  static String fontFamilyForPlatform(TargetPlatform platform) {
    return ObjectTypeTypography.fontFamilyForPlatform(platform);
  }

  static List<String> fontFamilyFallbackForPlatform(TargetPlatform platform) {
    return ObjectTypeTypography.fontFamilyFallbackForPlatform(platform);
  }

  static FontWeight fontWeightForPlatform(TargetPlatform platform) {
    return ObjectTypeTypography.fontWeightForPlatform(platform);
  }

  static TextStyle textStyle(
    BuildContext context, {
    Color? color,
    SidebarTextRole role = SidebarTextRole.standard,
  }) {
    final theme = Theme.of(context);
    final resolvedFontSize = switch (role) {
      SidebarTextRole.standard => fontSize,
      SidebarTextRole.page => pageFontSize,
      SidebarTextRole.section => sectionFontSize,
    };
    final resolvedLineHeight = switch (role) {
      SidebarTextRole.standard => lineHeight,
      SidebarTextRole.page => pageLineHeight,
      SidebarTextRole.section => sectionLineHeight,
    };
    return theme.textTheme.bodyMedium!.copyWith(
      color: color,
      fontFamily: fontFamilyForPlatform(theme.platform),
      fontFamilyFallback: fontFamilyFallbackForPlatform(theme.platform),
      fontSize: resolvedFontSize,
      fontWeight: fontWeightForPlatform(theme.platform),
      fontVariations: fontVariations,
      height: resolvedLineHeight / resolvedFontSize,
      letterSpacing: role == SidebarTextRole.section
          ? sectionLetterSpacing
          : letterSpacingForFontSize(resolvedFontSize),
    );
  }

  static ThemeData themeData(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        bodyMedium: textStyle(context),
      ),
    );
  }
}

class SidebarText extends StatelessWidget {
  const SidebarText(
    this.text, {
    super.key,
    this.overflow = TextOverflow.clip,
    this.textAlign,
    this.maxLines = 1,
    this.color,
    this.withTooltip = false,
    this.strutStyle,
  }) : role = SidebarTextRole.standard;

  const SidebarText.page(
    this.text, {
    super.key,
    this.overflow = TextOverflow.clip,
    this.textAlign,
    this.maxLines = 1,
    this.color,
    this.withTooltip = false,
    this.strutStyle,
  }) : role = SidebarTextRole.page;

  const SidebarText.section(
    this.text, {
    super.key,
    this.overflow = TextOverflow.clip,
    this.textAlign,
    this.maxLines = 1,
    this.color,
    this.withTooltip = false,
    this.strutStyle,
  }) : role = SidebarTextRole.section;

  final String text;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final int? maxLines;
  final Color? color;
  final bool withTooltip;
  final StrutStyle? strutStyle;
  final SidebarTextRole role;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ??
        (role == SidebarTextRole.section
            ? Theme.of(context).hintColor
            : Theme.of(context).colorScheme.onSecondary);
    final style = SidebarTypography.textStyle(
      context,
      color: resolvedColor,
      role: role,
    );
    return FlowyText(
      text,
      overflow: overflow,
      textAlign: textAlign,
      maxLines: maxLines,
      color: resolvedColor,
      withTooltip: withTooltip,
      strutStyle: strutStyle,
      fontFamily: style.fontFamily,
      fallbackFontFamily: style.fontFamilyFallback,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontVariations: style.fontVariations,
      letterSpacing: style.letterSpacing,
      figmaLineHeight: style.fontSize! * style.height!,
    );
  }
}
