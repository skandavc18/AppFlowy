import 'package:appflowy/shared/object_type_typography.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

enum SidebarTextRole {
  /// Utility actions: search, new page, templates, trash.
  standard,

  /// Page and collection names.
  page,

  /// A section heading such as the workspace name.
  heading,

  /// The quiet label above a section of the tree.
  section,

  /// Shortcuts and counts.
  meta,
}

abstract final class SidebarTypography {
  static const fontSize = 13.5;
  static const lineHeight = 18.0;
  static const pageFontSize = 13.5;
  static const pageLineHeight = 18.0;
  static const headingFontSize = 13.0;
  static const headingLineHeight = 18.0;
  static const sectionFontSize = 11.5;
  static const sectionLineHeight = 16.0;
  static const sectionLetterSpacing = 0.35;
  static const metaFontSize = 11.5;
  static const metaLineHeight = 16.0;

  /// Navigation copy is set at medium, never at the editor's semibold.
  ///
  /// [ObjectTypeTypography.fontWeightForPlatform] answers w600 on Windows,
  /// which is what made every row of the sidebar read as bold.
  static const navigationWeight = FontWeight.w500;
  static const pageWeight = FontWeight.w500;
  static const headingWeight = FontWeight.w600;

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

  static FontWeight fontWeightForRole(SidebarTextRole role) => switch (role) {
        SidebarTextRole.standard => navigationWeight,
        SidebarTextRole.page => pageWeight,
        SidebarTextRole.heading => headingWeight,
        SidebarTextRole.section => navigationWeight,
        SidebarTextRole.meta => pageWeight,
      };

  static double fontSizeForRole(SidebarTextRole role) => switch (role) {
        SidebarTextRole.standard => fontSize,
        SidebarTextRole.page => pageFontSize,
        SidebarTextRole.heading => headingFontSize,
        SidebarTextRole.section => sectionFontSize,
        SidebarTextRole.meta => metaFontSize,
      };

  static double lineHeightForRole(SidebarTextRole role) => switch (role) {
        SidebarTextRole.standard => lineHeight,
        SidebarTextRole.page => pageLineHeight,
        SidebarTextRole.heading => headingLineHeight,
        SidebarTextRole.section => sectionLineHeight,
        SidebarTextRole.meta => metaLineHeight,
      };

  static TextStyle textStyle(
    BuildContext context, {
    Color? color,
    SidebarTextRole role = SidebarTextRole.standard,
  }) {
    final theme = Theme.of(context);
    final resolvedFontSize = fontSizeForRole(role);
    final resolvedLineHeight = lineHeightForRole(role);
    return theme.textTheme.bodyMedium!.copyWith(
      color: color,
      fontFamily: fontFamilyForPlatform(theme.platform),
      fontFamilyFallback: fontFamilyFallbackForPlatform(theme.platform),
      fontSize: resolvedFontSize,
      fontWeight: fontWeightForRole(role),
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

  const SidebarText.heading(
    this.text, {
    super.key,
    this.overflow = TextOverflow.clip,
    this.textAlign,
    this.maxLines = 1,
    this.color,
    this.withTooltip = false,
    this.strutStyle,
  }) : role = SidebarTextRole.heading;

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
