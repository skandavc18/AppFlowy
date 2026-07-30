import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// Colour and metric tokens for the inline spreadsheet.
///
/// Resolved from the ambient AppFlowy theme so the grid inherits dark, light
/// and paper appearances without any of its own hard-coded surfaces. In paper
/// mode the palette leans on the warm stationery tokens so the sheet reads as
/// a printed worksheet rather than a white panel dropped on parchment.
@immutable
class SpreadsheetPalette {
  const SpreadsheetPalette({
    required this.surface,
    required this.headerSurface,
    required this.gutterSurface,
    required this.bandedSurface,
    required this.gridLine,
    required this.divider,
    required this.hover,
    required this.selection,
    required this.selectionBorder,
    required this.focusRing,
    required this.focusHalo,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.placeholder,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.chrome,
    required this.floating,
    required this.shadow,
    required this.isPaper,
  });

  factory SpreadsheetPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isPaper = PaperTheme.isEnabled(context) && !isDark;

    if (isPaper) {
      return const SpreadsheetPalette(
        surface: PaperTheme.editorBackground,
        headerSurface: PaperTheme.editorBackground,
        gutterSurface: PaperTheme.editorBackground,
        bandedSurface: Color(0xFFF3EDE1),
        gridLine: Color(0x1F675443),
        divider: Color(0x2E675443),
        hover: Color(0x0F675443),
        selection: Color(0x14715438),
        selectionBorder: Color(0x66715438),
        focusRing: PaperTheme.accent,
        focusHalo: Color(0x24715438),
        textPrimary: PaperTheme.textPrimary,
        textSecondary: PaperTheme.textSecondary,
        textMuted: PaperTheme.textMuted,
        placeholder: Color(0x73918577),
        accent: PaperTheme.accent,
        onAccent: PaperTheme.onAccent,
        danger: Color(0xFFA23F32),
        chrome: PaperTheme.editorBackground,
        floating: PaperTheme.popupBackground,
        shadow: PaperTheme.shadow,
        isPaper: true,
      );
    }

    // The sheet is not a card: cells take the page's own canvas colour so the
    // block reads as part of the document, the way a database grid does.
    final canvas = premium?.canvas ?? scheme.surface;
    final accent = premium?.accent ?? scheme.primary;
    final onSurface = premium?.textPrimary ?? scheme.onSurface;

    Color tint(double amount) =>
        Color.alphaBlend(onSurface.withValues(alpha: amount), canvas);

    return SpreadsheetPalette(
      surface: canvas,
      headerSurface: canvas,
      gutterSurface: canvas,
      bandedSurface: tint(isDark ? 0.016 : 0.011),
      gridLine: (premium?.border ?? scheme.outlineVariant)
          .withValues(alpha: isDark ? 0.18 : 0.26),
      divider: (premium?.border ?? scheme.outlineVariant)
          .withValues(alpha: isDark ? 0.28 : 0.38),
      hover: onSurface.withValues(alpha: isDark ? 0.045 : 0.030),
      selection: accent.withValues(alpha: isDark ? 0.16 : 0.10),
      selectionBorder: accent.withValues(alpha: isDark ? 0.55 : 0.45),
      focusRing: accent,
      focusHalo: accent.withValues(alpha: isDark ? 0.24 : 0.16),
      textPrimary: onSurface,
      textSecondary: premium?.textSecondary ?? scheme.onSurfaceVariant,
      textMuted:
          premium?.textMuted ?? scheme.onSurfaceVariant.withValues(alpha: 0.7),
      placeholder: onSurface.withValues(alpha: isDark ? 0.32 : 0.28),
      accent: accent,
      onAccent: premium?.onAccent ?? scheme.onPrimary,
      danger: scheme.error,
      chrome: canvas,
      floating: premium?.floatingSurface ?? scheme.surfaceContainer,
      shadow: premium?.shadow ?? Colors.black.withValues(alpha: 0.14),
      isPaper: false,
    );
  }

  final Color surface;
  final Color headerSurface;
  final Color gutterSurface;
  final Color bandedSurface;

  /// The hairline between cells. Barely there by design.
  final Color gridLine;

  /// A slightly firmer hairline, used only where two regions meet.
  final Color divider;

  final Color hover;
  final Color selection;
  final Color selectionBorder;

  /// The ring drawn around the active cell.
  final Color focusRing;

  /// A soft glow outside the focus ring so the cursor reads at a glance.
  final Color focusHalo;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color placeholder;
  final Color accent;
  final Color onAccent;
  final Color danger;

  /// The sheet's own bands. Flush with the page by design.
  final Color chrome;

  /// Menus, panels and the floating toolbar, which do lift off the page.
  final Color floating;

  final Color shadow;
  final bool isPaper;

  BorderRadius get cardRadius =>
      BorderRadius.circular(SpreadsheetMetrics.cardRadius);
}

/// Fixed metrics shared by the grid, its chrome and the tests.
abstract final class SpreadsheetMetrics {
  /// Only the floating chrome is rounded — the sheet itself is flush.
  static const double cardRadius = 12;

  static const double gutterWidth = 40;
  static const double headerHeight = 34;
  static const double blockHeaderHeight = 30;
  static const double footerHeight = 30;

  /// The trailing cell in the header strip that appends a column, and the
  /// trailing band under the last row that appends a row.
  static const double addColumnWidth = 40;
  static const double addRowHeight = 34;

  static const double floatingToolbarHeight = 40;
  static const double controlSize = 26;
  static const double controlRadius = 7;
  static const double cellPaddingHorizontal = 12;
  static const double cellPaddingVertical = 6;
  static const double resizeHandleWidth = 10;
  static const double fillHandleSize = 8;

  /// The handle is drawn small but grabbed with a mouse, so it is worth
  /// catching a press that lands near the corner rather than on it.
  static const double fillHandleTargetSize = 20;
  static const double cellFontSize = 13.5;
  static const double defaultBlockWidth = 760;
  static const double defaultBlockHeight = 340;
  static const double minBlockWidth = 320;

  /// Chrome is a header row and a footer, so the floor has to leave room for
  /// the column headers and a few body rows underneath them.
  static const double minBlockHeight = 190;
  static const double maxBlockHeight = 900;

  /// How many rows and columns are rendered beyond the viewport so a fast
  /// fling never shows an empty band.
  static const int overscanRows = 4;
  static const int overscanColumns = 2;
}

/// Typography for cell content.
///
/// Built from the document's own body style when one is supplied, so a sheet
/// is set in the same face as the paragraph above it rather than in whatever
/// Material happens to default to.
class SpreadsheetTypography {
  const SpreadsheetTypography({
    required this.cell,
    required this.header,
    required this.gutter,
    required this.chrome,
    required this.placeholder,
  });

  factory SpreadsheetTypography.of(
    BuildContext context,
    SpreadsheetPalette palette, {
    TextStyle? base,
  }) {
    final source =
        base ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    // The weight is inherited, never restated: the editor sets its body face
    // per platform (Segoe UI Semibold on Windows) and a variable face carries
    // its axis in fontVariations, so naming a weight here renders the grid
    // lighter than the paragraph above it.
    final cell = source.copyWith(
      fontSize: SpreadsheetMetrics.cellFontSize,
      height: 1.25,
      letterSpacing: 0,
      color: palette.textPrimary,
      decoration: TextDecoration.none,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SpreadsheetTypography(
      cell: cell,
      header: cell.copyWith(
        fontSize: 12,
        color: palette.textSecondary,
        letterSpacing: 0.15,
      ),
      gutter: cell.copyWith(
        fontSize: 10.5,
        color: palette.textMuted,
        letterSpacing: 0.2,
      ),
      chrome: cell.copyWith(
        fontSize: 12,
        color: palette.textSecondary,
      ),
      placeholder: cell.copyWith(color: palette.placeholder),
    );
  }

  final TextStyle cell;
  final TextStyle header;
  final TextStyle gutter;
  final TextStyle chrome;
  final TextStyle placeholder;
}

/// The card shadow: wide and soft rather than a drawn outline.
List<BoxShadow> spreadsheetCardShadow(
  BuildContext context, {
  bool raised = false,
}) =>
    EditorSurfaceStyle.embedShadow(context, raised: raised);
