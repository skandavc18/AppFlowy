import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:flutter/material.dart';

/// The colours a book is read in.
///
/// [BookReaderTheme.workspace] follows AppFlowy itself, so a book sits inside
/// the application rather than beside it — and in paper mode it inherits the
/// stationery the workspace already wears. The named themes are explicit
/// choices for when the reader wants a different surface.
@immutable
class BookReaderPalette {
  const BookReaderPalette._({
    required this.theme,
    required this.isDark,
    required this.isPaper,
    required this.canvas,
    required this.page,
    required this.chrome,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.rule,
    required this.hover,
    required this.selected,
    required this.shadow,
  });

  factory BookReaderPalette.of(BuildContext context, BookReaderTheme theme) {
    if (theme != BookReaderTheme.workspace) {
      return _fixed(theme);
    }

    final base = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isDark = base.brightness == Brightness.dark;
    final scheme = base.colorScheme;

    // Paper mode already reads as a printed sheet, so the page is its own
    // preview surface rather than a whiter card laid on top of it.
    if (PaperTheme.isEnabled(context) && !isDark) {
      return const BookReaderPalette._(
        theme: BookReaderTheme.workspace,
        isDark: false,
        isPaper: true,
        canvas: PaperTheme.editorBackground,
        page: PaperTheme.editorPreviewBackground,
        chrome: PaperTheme.popupBackground,
        ink: PaperTheme.textPrimary,
        inkMuted: PaperTheme.textSecondary,
        inkFaint: PaperTheme.textMuted,
        accent: PaperTheme.accent,
        rule: PaperTheme.strongBorder,
        hover: PaperTheme.controlHover,
        selected: PaperTheme.controlSelected,
        shadow: PaperTheme.shadow,
      );
    }

    return BookReaderPalette._(
      theme: BookReaderTheme.workspace,
      isDark: isDark,
      isPaper: false,
      canvas: premium?.canvas ?? scheme.surface,
      page: premium?.surface ?? scheme.surface,
      chrome: premium?.floatingSurface ?? scheme.surfaceContainer,
      ink: premium?.textPrimary ?? scheme.onSurface,
      inkMuted: premium?.textSecondary ?? scheme.onSurfaceVariant,
      inkFaint:
          premium?.textMuted ?? scheme.onSurfaceVariant.withValues(alpha: 0.7),
      accent: premium?.accent ?? scheme.primary,
      rule: premium?.border ?? scheme.outlineVariant,
      hover: premium?.hover ?? scheme.onSurface.withValues(alpha: 0.06),
      selected: premium?.selected ??
          Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.10),
            scheme.surface,
          ),
      shadow: premium?.shadow ?? Colors.black.withValues(alpha: 0.12),
    );
  }

  static BookReaderPalette _fixed(BookReaderTheme theme) => switch (theme) {
        // Workspace needs a context, so its swatch falls back to paper.
        BookReaderTheme.workspace ||
        BookReaderTheme.paper =>
          const BookReaderPalette._(
            theme: BookReaderTheme.paper,
            isDark: false,
            isPaper: true,
            canvas: Color(0xFFEFE8DA),
            page: Color(0xFFF8F3E9),
            chrome: Color(0xFFFCF8F0),
            ink: Color(0xFF2E2820),
            inkMuted: Color(0xFF6B6155),
            inkFaint: Color(0xFF938878),
            accent: Color(0xFF7A5C39),
            rule: Color(0x2E6B5843),
            hover: Color(0xFFEBE2D2),
            selected: Color(0xFFE1D5C1),
            shadow: Color(0x14584735),
          ),
        BookReaderTheme.sepia => const BookReaderPalette._(
            theme: BookReaderTheme.sepia,
            isDark: false,
            isPaper: true,
            canvas: Color(0xFFE4D3B4),
            page: Color(0xFFF0E2C6),
            chrome: Color(0xFFF4E8D2),
            ink: Color(0xFF392E1F),
            inkMuted: Color(0xFF6E5B42),
            inkFaint: Color(0xFF95805F),
            accent: Color(0xFF95592A),
            rule: Color(0x33654A2C),
            hover: Color(0xFFE7D8BB),
            selected: Color(0xFFDCC9A5),
            shadow: Color(0x1A5A4324),
          ),
        BookReaderTheme.light => const BookReaderPalette._(
            theme: BookReaderTheme.light,
            isDark: false,
            isPaper: false,
            canvas: Color(0xFFF2F3F5),
            page: Color(0xFFFFFFFF),
            chrome: Color(0xFFFAFAFB),
            ink: Color(0xFF17181B),
            inkMuted: Color(0xFF5C6068),
            inkFaint: Color(0xFF8A8F98),
            accent: Color(0xFF2563EB),
            rule: Color(0x1F0B0D12),
            hover: Color(0xFFEFF0F3),
            selected: Color(0xFFE3E8F6),
            shadow: Color(0x140B0D12),
          ),
        BookReaderTheme.dark => const BookReaderPalette._(
            theme: BookReaderTheme.dark,
            isDark: true,
            isPaper: false,
            canvas: Color(0xFF15171A),
            page: Color(0xFF1D2024),
            chrome: Color(0xFF23262B),
            ink: Color(0xFFDCDFE4),
            inkMuted: Color(0xFF9AA1AB),
            inkFaint: Color(0xFF6E757F),
            accent: Color(0xFF89B0F5),
            rule: Color(0x26FFFFFF),
            hover: Color(0xFF2A2E34),
            selected: Color(0xFF313742),
            shadow: Color(0x59000000),
          ),
        BookReaderTheme.night => const BookReaderPalette._(
            theme: BookReaderTheme.night,
            isDark: true,
            isPaper: false,
            canvas: Color(0xFF06070A),
            page: Color(0xFF0B0D11),
            chrome: Color(0xFF111419),
            ink: Color(0xFF9BA2AC),
            inkMuted: Color(0xFF6B727C),
            inkFaint: Color(0xFF4C525B),
            accent: Color(0xFF6E8CC4),
            rule: Color(0x1AFFFFFF),
            hover: Color(0xFF161A20),
            selected: Color(0xFF1D232B),
            shadow: Color(0x73000000),
          ),
      };

  /// The swatch shown in the theme picker.
  static BookReaderPalette swatch(BookReaderTheme theme) => _fixed(theme);

  final BookReaderTheme theme;
  final bool isDark;

  /// Whether the surface is warm stationery, which the page texture keys off.
  final bool isPaper;

  /// Behind the page — the desk the book sits on.
  final Color canvas;

  /// The sheet the text is set on.
  final Color page;

  /// Toolbars, the contents rail and popovers.
  final Color chrome;

  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color accent;
  final Color rule;
  final Color hover;
  final Color selected;
  final Color shadow;

  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  /// A theme for the widgets a hosted renderer builds.
  ///
  /// The reading surface is projected onto [PremiumThemeExtension] and
  /// [PaperThemeExtension] as well as the colour scheme, because every
  /// AppFlowy palette — the PDF viewer, the file preview, the folder explorer
  /// — derives from those. That is what makes a PDF chapter and a markdown
  /// chapter look like two pages of one book.
  ThemeData themeFor(ThemeData base) {
    final scheme = base.colorScheme.copyWith(
      brightness: brightness,
      surface: page,
      surfaceContainer: chrome,
      surfaceContainerHighest: chrome,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      primary: accent,
      outline: rule,
      outlineVariant: rule,
    );
    return base.copyWith(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: page,
      cardColor: page,
      dividerColor: rule,
      hoverColor: hover,
      shadowColor: shadow,
      iconTheme: base.iconTheme.copyWith(color: inkMuted),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      extensions: _projectExtensions(base),
    );
  }

  Iterable<ThemeExtension<dynamic>> _projectExtensions(ThemeData base) sync* {
    for (final extension in base.extensions.values) {
      if (extension is PremiumThemeExtension) {
        yield extension.copyWith(
          isPaper: isPaper,
          canvas: canvas,
          surface: page,
          floatingSurface: chrome,
          mutedSurface: chrome,
          sidebar: chrome,
          hover: hover,
          selected: selected,
          border: rule,
          borderStrong: rule,
          textPrimary: ink,
          textSecondary: inkMuted,
          textMuted: inkFaint,
          accent: accent,
          shadow: shadow,
        );
      } else if (extension is PaperThemeExtension) {
        yield PaperThemeExtension(enabled: isPaper);
      } else {
        yield extension;
      }
    }
  }
}

abstract final class BookReaderMetrics {
  static const railWidth = 268.0;
  static const railCollapsedWidth = 0.0;
  static const chromeHeight = 52.0;
  static const footerHeight = 44.0;

  /// A book page has corners, not a card's radius.
  static const pageRadius = 3.0;
  static const pageMargin = 24.0;
  static const controlSize = 30.0;
  static const controlRadius = 8.0;
  static const motion = Duration(milliseconds: 220);
  static const railMotion = Duration(milliseconds: 240);
  static const turnMotion = Duration(milliseconds: 460);
  static const curve = Curves.easeOutCubic;

  static const bodyFontSize = 17.0;
  static const titleFontSize = 26.0;
}
