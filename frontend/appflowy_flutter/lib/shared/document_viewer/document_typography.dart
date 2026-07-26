import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:flutter/material.dart';

import 'document_viewer_theme.dart';

/// Reading-first typography shared by every document renderer.
///
/// Markdown, HTML, plain text, notebooks and archives all resolve their styles
/// here, so a heading looks identical no matter which parser produced it.
@immutable
class DocumentTypography {
  const DocumentTypography({
    required this.display,
    required this.title,
    required this.heading,
    required this.subheading,
    required this.minorHeading,
    required this.overline,
    required this.body,
    required this.lead,
    required this.caption,
    required this.quote,
    required this.code,
    required this.inlineCode,
    required this.tableHeader,
    required this.tableCell,
  });

  /// Builds the scale for [theme]. [scale] applies the reader's zoom level.
  ///
  /// [monoFamily] exists so hosts without network access — tests, offline
  /// first runs — can resolve code type from a bundled face.
  factory DocumentTypography.resolve(
    DocumentViewerTheme theme, {
    double scale = 1,
    String? monoFamily,
  }) {
    final codeFamily =
        monoFamily ?? debugMonoFamilyOverride ?? defaultMonoFamily;
    TextStyle prose(
      double size,
      FontWeight weight,
      double lineHeight, {
      Color? color,
      double letterSpacing = 0,
    }) =>
        getGoogleFontSafely(
          'DM Sans',
          fontSize: size * scale,
          fontWeight: weight,
          fontColor: color ?? theme.textPrimary,
          lineHeight: lineHeight,
          letterSpacing: letterSpacing * scale,
        );

    TextStyle mono(
      double size,
      FontWeight weight,
      double lineHeight, {
      Color? color,
    }) =>
        getGoogleFontSafely(
          codeFamily,
          fontSize: size * scale,
          fontWeight: weight,
          fontColor: color ?? theme.textPrimary,
          lineHeight: lineHeight,
        ).copyWith(fontFamilyFallback: monoFallback);

    return DocumentTypography(
      // Optical letter-spacing: large type tightens, small type opens up.
      display: prose(34, FontWeight.w700, 1.18, letterSpacing: -0.7),
      title: prose(26, FontWeight.w700, 1.24, letterSpacing: -0.5),
      heading: prose(21, FontWeight.w600, 1.3, letterSpacing: -0.3),
      subheading: prose(18, FontWeight.w600, 1.35, letterSpacing: -0.15),
      minorHeading: prose(16, FontWeight.w600, 1.4),
      overline: prose(
        12,
        FontWeight.w600,
        1.4,
        color: theme.textMuted,
        letterSpacing: 0.6,
      ),
      body: prose(16, FontWeight.w400, 1.72),
      lead: prose(17, FontWeight.w400, 1.68, color: theme.textSecondary),
      caption: prose(13, FontWeight.w400, 1.5, color: theme.textMuted),
      quote: prose(16, FontWeight.w400, 1.7, color: theme.textSecondary),
      code: mono(13.5, FontWeight.w400, 1.62),
      inlineCode: mono(13.5, FontWeight.w500, 1.5),
      tableHeader: prose(14, FontWeight.w600, 1.45, color: theme.textSecondary),
      tableCell: prose(14, FontWeight.w400, 1.5),
    );
  }

  static const List<String> monoFallback = [
    'Geist Mono',
    'SF Mono',
    'Cascadia Code',
    'RobotoMono',
    'monospace',
  ];

  /// The code face used across code blocks, listings and notebooks.
  static const String defaultMonoFamily = 'JetBrains Mono';

  /// Replaces the code face process-wide. Tests use a bundled font so the
  /// scale resolves without reaching the network.
  @visibleForTesting
  static String? debugMonoFamilyOverride;

  final TextStyle display;
  final TextStyle title;
  final TextStyle heading;
  final TextStyle subheading;
  final TextStyle minorHeading;
  final TextStyle overline;
  final TextStyle body;
  final TextStyle lead;
  final TextStyle caption;
  final TextStyle quote;
  final TextStyle code;
  final TextStyle inlineCode;
  final TextStyle tableHeader;
  final TextStyle tableCell;

  /// Heading style for markdown/HTML levels 1-6.
  TextStyle headingFor(int level) => switch (level) {
        1 => display,
        2 => title,
        3 => heading,
        4 => subheading,
        5 => minorHeading,
        _ => minorHeading,
      };

  /// Space above a heading of [level]; the first block never gets leading gap.
  double spaceAboveHeading(int level) => switch (level) {
        1 => 8,
        2 => 34,
        3 => 28,
        4 => 24,
        _ => 20,
      };

  double spaceBelowHeading(int level) => switch (level) {
        1 => 14,
        2 => 12,
        3 => 10,
        _ => 8,
      };
}
