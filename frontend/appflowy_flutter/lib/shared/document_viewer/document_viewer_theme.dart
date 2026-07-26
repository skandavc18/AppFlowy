import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// The three intentionally designed document appearances.
enum DocumentViewerMode {
  /// Arc Browser / Cursor: deep neutral canvas, near-black floating pages.
  dark,

  /// Apple Preview: cool-neutral canvas with a clean white page.
  light,

  /// Premium notebook: warm ivory surfaces and calm reading contrast.
  paper,
}

/// Every visual token used by the unified document viewer.
///
/// A single palette drives every renderer — Markdown, HTML, PDF, images, code,
/// video and audio — so switching file types never feels like switching apps.
@immutable
class DocumentViewerTheme extends ThemeExtension<DocumentViewerTheme> {
  const DocumentViewerTheme({
    required this.mode,
    required this.canvas,
    required this.canvasEdge,
    required this.page,
    required this.pageBorder,
    required this.chrome,
    required this.chromeBorder,
    required this.control,
    required this.controlHover,
    required this.controlPressed,
    required this.controlSelected,
    required this.hairline,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.icon,
    required this.iconMuted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.codeSurface,
    required this.codeBorder,
    required this.quoteBar,
    required this.selection,
    required this.scrollThumb,
    required this.pageShadow,
    required this.floatShadow,
    required this.shellShadow,
    required this.scrim,
  });

  /// Resolves the palette for the ambient AppFlowy appearance.
  ///
  /// Prefers an explicitly installed extension so hosts can override tokens,
  /// and otherwise derives a palette from the active theme.
  factory DocumentViewerTheme.of(BuildContext context) =>
      Theme.of(context).extension<DocumentViewerTheme>() ??
      DocumentViewerTheme.resolve(context);

  /// Derives the palette from the ambient AppFlowy/Material theme.
  factory DocumentViewerTheme.resolve(BuildContext context) {
    final materialTheme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isDark = materialTheme.brightness == Brightness.dark;
    final isPaper =
        !isDark && (premium?.isPaper ?? PaperTheme.isEnabled(context));

    if (isDark) {
      return DocumentViewerTheme._dark(materialTheme, premium);
    }
    if (isPaper) {
      return DocumentViewerTheme._paper();
    }
    return DocumentViewerTheme._light(materialTheme, premium);
  }

  /// Arc Browser / Cursor: the page floats a shade above a deep canvas.
  factory DocumentViewerTheme._dark(
    ThemeData materialTheme,
    PremiumThemeExtension? premium,
  ) {
    final accent = premium?.accent ?? materialTheme.colorScheme.primary;
    return DocumentViewerTheme(
      mode: DocumentViewerMode.dark,
      canvas: const Color(0xFF141517),
      canvasEdge: const Color(0xFF0F1012),
      page: const Color(0xFF1B1D20),
      pageBorder: const Color(0x14FFFFFF),
      chrome: const Color(0xF21E2023),
      chromeBorder: const Color(0x1AFFFFFF),
      control: const Color(0x0DFFFFFF),
      controlHover: const Color(0x17FFFFFF),
      controlPressed: const Color(0x24FFFFFF),
      controlSelected: const Color(0x2EFFFFFF),
      hairline: const Color(0x14FFFFFF),
      divider: const Color(0x1FFFFFFF),
      textPrimary: const Color(0xFFE9EAEC),
      textSecondary: const Color(0xFFA4A7AD),
      textMuted: const Color(0xFF74787F),
      icon: const Color(0xFFB6B9BF),
      iconMuted: const Color(0xFF6C7076),
      accent: accent,
      accentSoft: accent.withValues(alpha: 0.16),
      onAccent: const Color(0xFFF7F8FA),
      codeSurface: const Color(0xFF17181B),
      codeBorder: const Color(0x14FFFFFF),
      quoteBar: const Color(0x33FFFFFF),
      selection: accent.withValues(alpha: 0.28),
      scrollThumb: const Color(0x59FFFFFF),
      pageShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 26,
          offset: Offset(0, 10),
          spreadRadius: -12,
        ),
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 6,
          offset: Offset(0, 2),
          spreadRadius: -3,
        ),
      ],
      floatShadow: const [
        BoxShadow(
          color: Color(0x59000000),
          blurRadius: 18,
          offset: Offset(0, 6),
          spreadRadius: -8,
        ),
        BoxShadow(
          color: Color(0x2E000000),
          blurRadius: 4,
          offset: Offset(0, 1),
          spreadRadius: -1,
        ),
      ],
      shellShadow: const [
        BoxShadow(
          color: Color(0x3D000000),
          blurRadius: 20,
          offset: Offset(0, 8),
          spreadRadius: -10,
        ),
      ],
      scrim: const Color(0xB30B0C0E),
    );
  }

  /// Apple Preview: quiet cool-grey canvas, crisp white page.
  factory DocumentViewerTheme._light(
    ThemeData materialTheme,
    PremiumThemeExtension? premium,
  ) {
    final accent = premium?.accent ?? materialTheme.colorScheme.primary;
    return DocumentViewerTheme(
      mode: DocumentViewerMode.light,
      canvas: const Color(0xFFF4F4F6),
      canvasEdge: const Color(0xFFEDEDF0),
      page: const Color(0xFFFDFDFE),
      pageBorder: const Color(0x0F0F172A),
      chrome: const Color(0xF5FCFCFD),
      chromeBorder: const Color(0x140F172A),
      control: const Color(0x080F172A),
      controlHover: const Color(0x0F0F172A),
      controlPressed: const Color(0x1A0F172A),
      controlSelected: const Color(0x1F0F172A),
      hairline: const Color(0x0F0F172A),
      divider: const Color(0x160F172A),
      textPrimary: const Color(0xFF15181D),
      textSecondary: const Color(0xFF585F6B),
      textMuted: const Color(0xFF8A919C),
      icon: const Color(0xFF4E5561),
      iconMuted: const Color(0xFF9AA0AA),
      accent: accent,
      accentSoft: accent.withValues(alpha: 0.12),
      onAccent: const Color(0xFFFFFFFF),
      codeSurface: const Color(0xFFF6F6F8),
      codeBorder: const Color(0x120F172A),
      quoteBar: const Color(0x1F0F172A),
      selection: accent.withValues(alpha: 0.20),
      scrollThumb: const Color(0x520F172A),
      pageShadow: const [
        BoxShadow(
          color: Color(0x1A0F172A),
          blurRadius: 24,
          offset: Offset(0, 8),
          spreadRadius: -12,
        ),
        BoxShadow(
          color: Color(0x0F0F172A),
          blurRadius: 5,
          offset: Offset(0, 2),
          spreadRadius: -2,
        ),
      ],
      floatShadow: const [
        BoxShadow(
          color: Color(0x140F172A),
          blurRadius: 16,
          offset: Offset(0, 6),
          spreadRadius: -7,
        ),
        BoxShadow(
          color: Color(0x0A0F172A),
          blurRadius: 4,
          offset: Offset(0, 1),
          spreadRadius: -1,
        ),
      ],
      shellShadow: const [
        BoxShadow(
          color: Color(0x120F172A),
          blurRadius: 18,
          offset: Offset(0, 6),
          spreadRadius: -8,
        ),
      ],
      scrim: const Color(0x8A1D2230),
    );
  }

  /// Premium notebook: warm ivory stationery with calm brown ink.
  factory DocumentViewerTheme._paper() {
    return const DocumentViewerTheme(
      mode: DocumentViewerMode.paper,
      canvas: PaperTheme.editorBackground,
      canvasEdge: Color(0xFFF2EBDF),
      page: Color(0xFFFDF9F1),
      pageBorder: PaperTheme.codeBlockBorder,
      chrome: PaperTheme.popupBackground,
      chromeBorder: PaperTheme.codeBlockBorder,
      control: PaperTheme.controlBackground,
      controlHover: PaperTheme.controlHover,
      controlPressed: PaperTheme.controlSelectedHover,
      controlSelected: PaperTheme.controlSelected,
      hairline: PaperTheme.codeBlockBorder,
      divider: PaperTheme.strongBorder,
      textPrimary: PaperTheme.textPrimary,
      textSecondary: PaperTheme.textSecondary,
      textMuted: PaperTheme.textMuted,
      icon: PaperTheme.textSecondary,
      iconMuted: PaperTheme.textMuted,
      accent: PaperTheme.accent,
      accentSoft: PaperTheme.selectedOverlay,
      onAccent: PaperTheme.onAccent,
      codeSurface: PaperTheme.codeBlockBackground,
      codeBorder: PaperTheme.codeBlockBorder,
      quoteBar: Color(0x4D8A6C48),
      selection: PaperTheme.textSelection,
      scrollThumb: Color(0x59685440),
      pageShadow: [
        BoxShadow(
          color: Color(0x1F5F503D),
          blurRadius: 22,
          offset: Offset(0, 8),
          spreadRadius: -11,
        ),
        BoxShadow(
          color: Color(0x145F503D),
          blurRadius: 5,
          offset: Offset(0, 2),
          spreadRadius: -2,
        ),
      ],
      floatShadow: [
        BoxShadow(
          color: Color(0x1A5F503D),
          blurRadius: 16,
          offset: Offset(0, 6),
          spreadRadius: -7,
        ),
        BoxShadow(
          color: Color(0x0D5F503D),
          blurRadius: 4,
          offset: Offset(0, 1),
          spreadRadius: -1,
        ),
      ],
      shellShadow: [
        BoxShadow(
          color: Color(0x145F503D),
          blurRadius: 18,
          offset: Offset(0, 6),
          spreadRadius: -8,
        ),
      ],
      scrim: PaperTheme.scrim,
    );
  }

  final DocumentViewerMode mode;

  /// The recessed area behind the floating document surface.
  final Color canvas;

  /// A slightly deeper canvas used for immersive media backdrops.
  final Color canvasEdge;

  /// The reading surface itself.
  final Color page;
  final Color pageBorder;

  /// Header and floating toolbar surfaces.
  final Color chrome;
  final Color chromeBorder;

  final Color control;
  final Color controlHover;
  final Color controlPressed;
  final Color controlSelected;

  /// Very subtle separators. [hairline] is nearly invisible, [divider] reads.
  final Color hairline;
  final Color divider;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color icon;
  final Color iconMuted;

  final Color accent;
  final Color accentSoft;
  final Color onAccent;

  final Color codeSurface;
  final Color codeBorder;
  final Color quoteBar;
  final Color selection;
  final Color scrollThumb;

  final List<BoxShadow> pageShadow;
  final List<BoxShadow> floatShadow;
  final List<BoxShadow> shellShadow;
  final Color scrim;

  bool get isDark => mode == DocumentViewerMode.dark;
  bool get isPaper => mode == DocumentViewerMode.paper;

  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  /// Geometry shared by every renderer.
  static const double pageRadius = 14;
  static const double surfaceRadius = 12;
  static const double controlRadius = 9;
  static const double chromeHeight = 46;
  static const double toolbarHeight = 34;
  static const double controlSize = 28;
  static const double iconSize = 16;

  /// Comfortable measure for prose. Roughly 70-80 characters.
  static const double readingWidth = 720;

  /// Wider measure for tabular and code content that must not wrap.
  static const double wideReadingWidth = 1080;

  /// Breathing room around the reading column.
  static const EdgeInsets readingPadding =
      EdgeInsets.symmetric(horizontal: 56, vertical: 48);

  static const EdgeInsets compactReadingPadding =
      EdgeInsets.symmetric(horizontal: 28, vertical: 28);

  @override
  DocumentViewerTheme copyWith({
    DocumentViewerMode? mode,
    Color? canvas,
    Color? canvasEdge,
    Color? page,
    Color? pageBorder,
    Color? chrome,
    Color? chromeBorder,
    Color? control,
    Color? controlHover,
    Color? controlPressed,
    Color? controlSelected,
    Color? hairline,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? icon,
    Color? iconMuted,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? codeSurface,
    Color? codeBorder,
    Color? quoteBar,
    Color? selection,
    Color? scrollThumb,
    List<BoxShadow>? pageShadow,
    List<BoxShadow>? floatShadow,
    List<BoxShadow>? shellShadow,
    Color? scrim,
  }) =>
      DocumentViewerTheme(
        mode: mode ?? this.mode,
        canvas: canvas ?? this.canvas,
        canvasEdge: canvasEdge ?? this.canvasEdge,
        page: page ?? this.page,
        pageBorder: pageBorder ?? this.pageBorder,
        chrome: chrome ?? this.chrome,
        chromeBorder: chromeBorder ?? this.chromeBorder,
        control: control ?? this.control,
        controlHover: controlHover ?? this.controlHover,
        controlPressed: controlPressed ?? this.controlPressed,
        controlSelected: controlSelected ?? this.controlSelected,
        hairline: hairline ?? this.hairline,
        divider: divider ?? this.divider,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        icon: icon ?? this.icon,
        iconMuted: iconMuted ?? this.iconMuted,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        onAccent: onAccent ?? this.onAccent,
        codeSurface: codeSurface ?? this.codeSurface,
        codeBorder: codeBorder ?? this.codeBorder,
        quoteBar: quoteBar ?? this.quoteBar,
        selection: selection ?? this.selection,
        scrollThumb: scrollThumb ?? this.scrollThumb,
        pageShadow: pageShadow ?? this.pageShadow,
        floatShadow: floatShadow ?? this.floatShadow,
        shellShadow: shellShadow ?? this.shellShadow,
        scrim: scrim ?? this.scrim,
      );

  @override
  DocumentViewerTheme lerp(
    covariant ThemeExtension<DocumentViewerTheme>? other,
    double t,
  ) {
    if (other is! DocumentViewerTheme) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return DocumentViewerTheme(
      mode: t < 0.5 ? mode : other.mode,
      canvas: mix(canvas, other.canvas),
      canvasEdge: mix(canvasEdge, other.canvasEdge),
      page: mix(page, other.page),
      pageBorder: mix(pageBorder, other.pageBorder),
      chrome: mix(chrome, other.chrome),
      chromeBorder: mix(chromeBorder, other.chromeBorder),
      control: mix(control, other.control),
      controlHover: mix(controlHover, other.controlHover),
      controlPressed: mix(controlPressed, other.controlPressed),
      controlSelected: mix(controlSelected, other.controlSelected),
      hairline: mix(hairline, other.hairline),
      divider: mix(divider, other.divider),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      icon: mix(icon, other.icon),
      iconMuted: mix(iconMuted, other.iconMuted),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      onAccent: mix(onAccent, other.onAccent),
      codeSurface: mix(codeSurface, other.codeSurface),
      codeBorder: mix(codeBorder, other.codeBorder),
      quoteBar: mix(quoteBar, other.quoteBar),
      selection: mix(selection, other.selection),
      scrollThumb: mix(scrollThumb, other.scrollThumb),
      pageShadow: BoxShadow.lerpList(pageShadow, other.pageShadow, t) ??
          other.pageShadow,
      floatShadow: BoxShadow.lerpList(floatShadow, other.floatShadow, t) ??
          other.floatShadow,
      shellShadow: BoxShadow.lerpList(shellShadow, other.shellShadow, t) ??
          other.shellShadow,
      scrim: mix(scrim, other.scrim),
    );
  }
}

/// Provides [DocumentViewerTheme] to a subtree without touching [ThemeData].
///
/// Renderers read the palette through [DocumentViewerTheme.of], which resolves
/// this scope first so nested surfaces (fullscreen, overlays) stay consistent.
class DocumentViewerThemeScope extends StatelessWidget {
  const DocumentViewerThemeScope({
    super.key,
    required this.theme,
    required this.child,
  });

  final DocumentViewerTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inherited = Theme.of(context);
    return Theme(
      data: inherited
          .copyWith(extensions: [...inherited.extensions.values, theme]),
      child: child,
    );
  }
}
