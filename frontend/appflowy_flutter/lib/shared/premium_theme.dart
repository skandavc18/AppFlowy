import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/colorscheme/colorscheme.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';

/// Semantic surface and interaction tokens that are not represented directly
/// by Material's [ColorScheme].
///
/// Keeping these roles in one extension lets legacy and Material 3 widgets use
/// the same hierarchy without branching on brightness or theme names.
@immutable
class PremiumThemeExtension extends ThemeExtension<PremiumThemeExtension> {
  const PremiumThemeExtension({
    required this.isPaper,
    required this.canvas,
    required this.surface,
    required this.floatingSurface,
    required this.mutedSurface,
    required this.sidebar,
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.hoverOverlay,
    required this.selectedOverlay,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.onAccent,
    required this.focusRing,
    required this.shadow,
    required this.scrim,
    required this.paperGrain,
  });

  final bool isPaper;
  final Color canvas;
  final Color surface;
  final Color floatingSurface;
  final Color mutedSurface;
  final Color sidebar;
  final Color hover;
  final Color pressed;
  final Color selected;
  final Color hoverOverlay;
  final Color selectedOverlay;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color onAccent;
  final Color focusRing;
  final Color shadow;
  final Color scrim;
  final Color paperGrain;

  static PremiumThemeExtension of(BuildContext context) {
    final extension = Theme.of(context).extension<PremiumThemeExtension>();
    assert(
      extension != null,
      'PremiumThemeExtension is missing from ThemeData',
    );
    return extension!;
  }

  static PremiumThemeExtension? maybeOf(BuildContext context) =>
      Theme.of(context).extension<PremiumThemeExtension>();

  @override
  PremiumThemeExtension copyWith({
    bool? isPaper,
    Color? canvas,
    Color? surface,
    Color? floatingSurface,
    Color? mutedSurface,
    Color? sidebar,
    Color? hover,
    Color? pressed,
    Color? selected,
    Color? hoverOverlay,
    Color? selectedOverlay,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentHover,
    Color? accentPressed,
    Color? onAccent,
    Color? focusRing,
    Color? shadow,
    Color? scrim,
    Color? paperGrain,
  }) =>
      PremiumThemeExtension(
        isPaper: isPaper ?? this.isPaper,
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        floatingSurface: floatingSurface ?? this.floatingSurface,
        mutedSurface: mutedSurface ?? this.mutedSurface,
        sidebar: sidebar ?? this.sidebar,
        hover: hover ?? this.hover,
        pressed: pressed ?? this.pressed,
        selected: selected ?? this.selected,
        hoverOverlay: hoverOverlay ?? this.hoverOverlay,
        selectedOverlay: selectedOverlay ?? this.selectedOverlay,
        border: border ?? this.border,
        borderStrong: borderStrong ?? this.borderStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        accent: accent ?? this.accent,
        accentHover: accentHover ?? this.accentHover,
        accentPressed: accentPressed ?? this.accentPressed,
        onAccent: onAccent ?? this.onAccent,
        focusRing: focusRing ?? this.focusRing,
        shadow: shadow ?? this.shadow,
        scrim: scrim ?? this.scrim,
        paperGrain: paperGrain ?? this.paperGrain,
      );

  @override
  PremiumThemeExtension lerp(
    covariant ThemeExtension<PremiumThemeExtension>? other,
    double t,
  ) {
    if (other is! PremiumThemeExtension) {
      return this;
    }

    Color blend(Color start, Color end) => Color.lerp(start, end, t)!;

    return PremiumThemeExtension(
      isPaper: t < 0.5 ? isPaper : other.isPaper,
      canvas: blend(canvas, other.canvas),
      surface: blend(surface, other.surface),
      floatingSurface: blend(floatingSurface, other.floatingSurface),
      mutedSurface: blend(mutedSurface, other.mutedSurface),
      sidebar: blend(sidebar, other.sidebar),
      hover: blend(hover, other.hover),
      pressed: blend(pressed, other.pressed),
      selected: blend(selected, other.selected),
      hoverOverlay: blend(hoverOverlay, other.hoverOverlay),
      selectedOverlay: blend(selectedOverlay, other.selectedOverlay),
      border: blend(border, other.border),
      borderStrong: blend(borderStrong, other.borderStrong),
      textPrimary: blend(textPrimary, other.textPrimary),
      textSecondary: blend(textSecondary, other.textSecondary),
      textMuted: blend(textMuted, other.textMuted),
      accent: blend(accent, other.accent),
      accentHover: blend(accentHover, other.accentHover),
      accentPressed: blend(accentPressed, other.accentPressed),
      onAccent: blend(onAccent, other.onAccent),
      focusRing: blend(focusRing, other.focusRing),
      shadow: blend(shadow, other.shadow),
      scrim: blend(scrim, other.scrim),
      paperGrain: blend(paperGrain, other.paperGrain),
    );
  }
}

abstract final class PremiumTheme {
  static const controlRadius = 9.0;
  static const surfaceRadius = 13.0;
  static const dialogRadius = 17.0;
  static const largeSurfaceRadius = 19.0;
  static const transitionDuration = AppFlowyMotion.standard;
  static const themeTransitionDuration = AppFlowyMotion.deliberate;

  static PremiumThemeExtension resolve({
    required AppTheme appTheme,
    required FlowyColorScheme legacy,
    required Brightness brightness,
  }) {
    if (brightness == Brightness.dark) {
      return _dark(legacy);
    }
    if (PaperTheme.isPaper(appTheme)) {
      return _paper();
    }
    return _light(
      legacy,
      preserveThemeCharacter: appTheme.themeName != BuiltInTheme.defaultTheme,
    );
  }

  static Color semanticColorFor(
    Color source,
    PremiumThemeExtension palette,
  ) =>
      palette.isPaper
          ? _softenSemantic(source, maximumSaturation: 0.34)
          : source;

  static Color tintFor(
    Color source,
    PremiumThemeExtension palette,
  ) =>
      palette.isPaper
          ? Color.alphaBlend(
              source.withValues(alpha: 0.38),
              palette.surface,
            )
          : source;

  static PremiumThemeExtension _light(
    FlowyColorScheme legacy, {
    required bool preserveThemeCharacter,
  }) {
    final accent = _mutedAccent(legacy.primary);
    final accentHover = _shiftLightness(accent, -0.06);
    final accentPressed = _shiftLightness(accent, -0.11);
    const canvas = Color(0xFFF8F8F5);
    const surface = Color(0xFFFCFCF9);
    const neutralSidebar = Color(0xFFF1F1ED);
    const textPrimary = Color(0xFF252522);
    const lightOnAccent = Color(0xFFFAFAF6);
    final onAccent = _contrastRatio(lightOnAccent, accent) >= 4.5
        ? lightOnAccent
        : textPrimary;
    final sidebar = preserveThemeCharacter
        ? Color.alphaBlend(
            legacy.sidebarBg.withValues(alpha: 0.22),
            neutralSidebar,
          )
        : neutralSidebar;

    return PremiumThemeExtension(
      isPaper: false,
      canvas: canvas,
      surface: surface,
      floatingSurface: const Color(0xFFFFFEFA),
      mutedSurface: const Color(0xFFF3F3EF),
      sidebar: sidebar,
      hover: const Color(0xFFEDEDE8),
      pressed: const Color(0xFFE5E5DF),
      selected: Color.alphaBlend(
        accent.withValues(alpha: 0.11),
        surface,
      ),
      hoverOverlay: const Color(0x0F252522),
      selectedOverlay: accent.withValues(alpha: 0.14),
      border: const Color(0x16252522),
      borderStrong: const Color(0x29252522),
      textPrimary: textPrimary,
      textSecondary: const Color(0xFF62625D),
      textMuted: const Color(0xFF8D8C84),
      accent: accent,
      accentHover: accentHover,
      accentPressed: accentPressed,
      onAccent: onAccent,
      focusRing: accent.withValues(alpha: 0.28),
      shadow: const Color(0x14211F1B),
      scrim: const Color(0x70211F1B),
      paperGrain: Colors.transparent,
    );
  }

  static PremiumThemeExtension _paper() => PremiumThemeExtension(
        isPaper: true,
        canvas: PaperTheme.editorBackground,
        surface: PaperTheme.editorPreviewBackground,
        floatingSurface: PaperTheme.popupBackground,
        mutedSurface: PaperTheme.controlBackground,
        sidebar: PaperTheme.sidebarBackground,
        hover: PaperTheme.controlHover,
        pressed: PaperTheme.controlSelected,
        selected: PaperTheme.controlSelectedHover,
        hoverOverlay: PaperTheme.hoverOverlay,
        selectedOverlay: PaperTheme.selectedOverlay,
        border: PaperTheme.codeBlockBorder,
        borderStrong: PaperTheme.strongBorder,
        textPrimary: PaperTheme.textPrimary,
        textSecondary: PaperTheme.textSecondary,
        textMuted: PaperTheme.textMuted,
        accent: PaperTheme.accent,
        accentHover: PaperTheme.accentHover,
        accentPressed: PaperTheme.accentPressed,
        onAccent: PaperTheme.onAccent,
        focusRing: PaperTheme.focusRing,
        shadow: PaperTheme.shadow,
        scrim: PaperTheme.scrim,
        paperGrain: PaperTheme.grain,
      );

  static PremiumThemeExtension _dark(FlowyColorScheme theme) =>
      PremiumThemeExtension(
        isPaper: false,
        canvas: theme.surface,
        surface: theme.surface,
        floatingSurface: theme.input,
        mutedSurface: theme.hoverBG3,
        sidebar: theme.sidebarBg,
        hover: theme.hoverBG1,
        pressed: theme.bg3,
        selected: theme.selector,
        hoverOverlay: theme.hoverBG1,
        selectedOverlay: theme.hoverBG1,
        border: theme.borderColor,
        borderStrong: theme.shader4,
        textPrimary: theme.text,
        textSecondary: theme.secondaryText,
        textMuted: theme.hint,
        accent: theme.primary,
        accentHover: theme.main2,
        accentPressed: theme.main2,
        onAccent: theme.onPrimary,
        focusRing: theme.primary.withValues(alpha: 0.34),
        shadow: theme.shadow,
        scrim: const Color(0x99000000),
        paperGrain: Colors.transparent,
      );

  static ColorScheme colorScheme({
    required FlowyColorScheme legacy,
    required PremiumThemeExtension palette,
    required Brightness brightness,
  }) {
    if (brightness == Brightness.dark) {
      return ColorScheme(
        brightness: brightness,
        primary: legacy.primary,
        onPrimary: legacy.onPrimary,
        primaryContainer: legacy.main2,
        onPrimaryContainer: legacy.strongText,
        secondary: legacy.hoverBG1,
        onSecondary: legacy.shader1,
        secondaryContainer: legacy.selector,
        onSecondaryContainer: legacy.topbarBg,
        tertiary: legacy.shader7,
        onTertiary: legacy.toolbarColor,
        tertiaryContainer: legacy.questionBubbleBG,
        onTertiaryContainer: legacy.text,
        error: legacy.red,
        onError: legacy.onPrimary,
        errorContainer: legacy.red.withValues(alpha: 0.16),
        onErrorContainer: legacy.red,
        surface: legacy.surface,
        onSurface: legacy.hoverFG,
        surfaceDim: legacy.surface,
        surfaceBright: legacy.input,
        surfaceContainerLowest: legacy.surface,
        surfaceContainerLow: legacy.input,
        surfaceContainer: legacy.hoverBG3,
        surfaceContainerHigh: legacy.input,
        surfaceContainerHighest: legacy.sidebarBg,
        onSurfaceVariant: legacy.secondaryText,
        outline: legacy.shader4,
        outlineVariant: legacy.borderColor,
        shadow: legacy.shadow,
        scrim: palette.scrim,
        inverseSurface: legacy.hoverBG3,
        onInverseSurface: legacy.text,
        inversePrimary: legacy.main2,
        surfaceTint: Colors.transparent,
      );
    }

    final error =
        palette.isPaper ? const Color(0xFF95534B) : const Color(0xFFB34C53);
    final errorContainer = Color.alphaBlend(
      error.withValues(alpha: palette.isPaper ? 0.11 : 0.09),
      palette.surface,
    );

    return ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      primaryContainer: palette.selected,
      onPrimaryContainer: palette.textPrimary,
      secondary: palette.hover,
      onSecondary: palette.textPrimary,
      secondaryContainer: palette.pressed,
      onSecondaryContainer: palette.textPrimary,
      tertiary: palette.textSecondary,
      onTertiary: palette.floatingSurface,
      tertiaryContainer: palette.mutedSurface,
      onTertiaryContainer: palette.textPrimary,
      error: error,
      onError: palette.onAccent,
      errorContainer: errorContainer,
      onErrorContainer: error,
      surface: palette.canvas,
      onSurface: palette.textPrimary,
      surfaceDim: palette.mutedSurface,
      surfaceBright: palette.floatingSurface,
      surfaceContainerLowest: palette.floatingSurface,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.mutedSurface,
      surfaceContainerHigh: palette.hover,
      surfaceContainerHighest: palette.sidebar,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.borderStrong,
      outlineVariant: palette.border,
      shadow: palette.shadow,
      scrim: palette.scrim,
      inverseSurface: palette.textPrimary,
      onInverseSurface: palette.floatingSurface,
      inversePrimary: palette.accentHover,
      surfaceTint: Colors.transparent,
    );
  }

  /// Applies explicit Material 3 component styling instead of relying on the
  /// platform defaults, which are intentionally generic and relatively boxy.
  static ThemeData materialTheme({
    required FlowyColorScheme legacy,
    required PremiumThemeExtension palette,
    required Brightness brightness,
    required String fontFamily,
    required TextTheme textTheme,
    required bool isDesktop,
  }) {
    final colors = colorScheme(
      legacy: legacy,
      palette: palette,
      brightness: brightness,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    final borderedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(surfaceRadius),
      side: BorderSide(color: palette.border, width: 0.5),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(controlRadius),
      borderSide: BorderSide(color: palette.border, width: 0.6),
    );
    final focusedInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(controlRadius),
      borderSide: BorderSide(color: palette.accent),
    );
    final minimumButtonSize = Size(0, isDesktop ? 32 : 42);
    final buttonPadding = EdgeInsets.symmetric(
      horizontal: isDesktop ? 12 : 14,
      vertical: isDesktop ? 7 : 10,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      fontFamily: fontFamily,
      textTheme: textTheme,
      visualDensity: isDesktop
          ? const VisualDensity(horizontal: -0.5, vertical: -0.5)
          : VisualDensity.standard,
      materialTapTargetSize: isDesktop
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      splashFactory: isDesktop ? NoSplash.splashFactory : null,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      cardColor: palette.floatingSurface,
      dialogBackgroundColor: palette.floatingSurface,
      dividerColor: palette.border,
      disabledColor: palette.textMuted.withValues(alpha: 0.48),
      focusColor: palette.focusRing,
      hoverColor: palette.hoverOverlay,
      highlightColor: palette.selectedOverlay,
      hintColor: palette.textMuted,
      shadowColor: palette.shadow,
      iconTheme: IconThemeData(color: palette.textSecondary, size: 20),
      primaryIconTheme: IconThemeData(color: palette.onAccent, size: 20),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.accent,
        selectionColor: palette.accent.withValues(alpha: 0.2),
        selectionHandleColor: palette.accent,
      ),
      cardTheme: CardTheme(
        color: palette.floatingSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: borderedShape,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: palette.floatingSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogRadius),
          side: BorderSide(color: palette.border, width: 0.5),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.floatingSurface,
        modalBackgroundColor: palette.floatingSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(dialogRadius),
          ),
        ),
        showDragHandle: !isDesktop,
        dragHandleColor: palette.borderStrong,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.floatingSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        elevation: 0,
        shape: borderedShape,
        menuPadding: const EdgeInsets.all(6),
        textStyle: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.floatingSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(palette.shadow),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(borderedShape),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: palette.mutedSurface,
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: focusedInputBorder,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.floatingSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(palette.shadow),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(borderedShape),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _primaryButtonStyle(
          palette: palette,
          minimumSize: minimumButtonSize,
          padding: buttonPadding,
          textStyle: textTheme.labelLarge,
          shape: shape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _primaryButtonStyle(
          palette: palette,
          minimumSize: minimumButtonSize,
          padding: buttonPadding,
          textStyle: textTheme.labelLarge,
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          animationDuration: transitionDuration,
          minimumSize: WidgetStatePropertyAll(minimumButtonSize),
          padding: WidgetStatePropertyAll(buttonPadding),
          shape: WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          elevation: const WidgetStatePropertyAll(0),
          foregroundColor: _stateColor(
            normal: palette.textPrimary,
            disabled: palette.textMuted,
          ),
          backgroundColor: _stateColor(
            normal: Colors.transparent,
            hovered: palette.hover,
            pressed: palette.pressed,
            disabled: Colors.transparent,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? palette.border.withValues(alpha: 0.55)
                  : states.contains(WidgetState.hovered)
                      ? palette.borderStrong
                      : palette.border,
              width: states.contains(WidgetState.focused) ? 1 : 0.6,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          animationDuration: transitionDuration,
          minimumSize: WidgetStatePropertyAll(minimumButtonSize),
          padding: WidgetStatePropertyAll(buttonPadding),
          shape: WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          foregroundColor: _stateColor(
            normal: palette.textPrimary,
            hovered: palette.accentHover,
            pressed: palette.accentPressed,
            disabled: palette.textMuted,
          ),
          backgroundColor: _stateColor(
            normal: Colors.transparent,
            hovered: palette.hover,
            pressed: palette.pressed,
            disabled: Colors.transparent,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          animationDuration: transitionDuration,
          minimumSize: WidgetStatePropertyAll(
            Size.square(isDesktop ? 30 : 40),
          ),
          iconSize: const WidgetStatePropertyAll(20),
          shape: WidgetStatePropertyAll(shape),
          foregroundColor: _stateColor(
            normal: palette.textSecondary,
            hovered: palette.textPrimary,
            pressed: palette.textPrimary,
            disabled: palette.textMuted,
          ),
          backgroundColor: _stateColor(
            normal: Colors.transparent,
            hovered: palette.hover,
            pressed: palette.pressed,
            disabled: Colors.transparent,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: palette.borderStrong),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accent
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(palette.onAccent),
        overlayColor: WidgetStatePropertyAll(palette.focusRing),
      ),
      radioTheme: RadioThemeData(
        fillColor: _stateColor(
          normal: palette.borderStrong,
          hovered: palette.accentHover,
          selected: palette.accent,
          disabled: palette.textMuted,
        ),
        overlayColor: WidgetStatePropertyAll(palette.focusRing),
      ),
      switchTheme: SwitchThemeData(
        trackColor: _stateColor(
          normal: palette.pressed,
          hovered: palette.hover,
          selected: palette.accent,
          disabled: palette.mutedSurface,
        ),
        thumbColor: _stateColor(
          normal: palette.floatingSurface,
          selected: palette.onAccent,
          disabled: palette.textMuted,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStatePropertyAll(palette.focusRing),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.mutedSurface,
        selectedColor: palette.selected,
        disabledColor: palette.mutedSurface,
        side: BorderSide(color: palette.border, width: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: palette.textSecondary,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 0.5,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        dense: isDesktop,
        iconColor: palette.textSecondary,
        textColor: palette.textPrimary,
        selectedColor: palette.textPrimary,
        selectedTileColor: palette.selected,
        shape: shape,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minVerticalPadding: 6,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colors.onInverseSurface,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 16 / 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        waitDuration: const Duration(milliseconds: 500),
        showDuration: const Duration(seconds: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        actionTextColor: colors.inversePrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.mutedSurface,
        circularTrackColor: palette.mutedSurface,
      ),
    );
  }

  /// Maps the same semantic hierarchy into AppFlowy's custom design system.
  static AppFlowyThemeData appFlowyTheme({
    required AppFlowyThemeData base,
    required PremiumThemeExtension palette,
    required Brightness brightness,
  }) {
    if (brightness == Brightness.dark) {
      return base;
    }

    final text = base.textColorScheme;
    final icon = base.iconColorScheme;
    final border = base.borderColorScheme;
    final fill = base.fillColorScheme;
    final semanticSaturation = palette.isPaper ? 0.34 : 0.58;
    Color semantic(Color source) => _softenSemantic(
          source,
          maximumSaturation: semanticSaturation,
        );
    Color semanticSurface(Color source) => Color.alphaBlend(
          semantic(source).withValues(alpha: palette.isPaper ? 0.11 : 0.09),
          palette.surface,
        );

    final info = semantic(text.info);
    final infoHover = semantic(text.infoHover);
    final success = semantic(text.success);
    final successHover = semantic(text.successHover);
    final warning = semantic(text.warning);
    final warningHover = semantic(text.warningHover);
    final error = semantic(text.error);
    final errorHover = semantic(text.errorHover);
    final featured = semantic(text.featured);
    final featuredHover = semantic(text.featuredHover);

    return AppFlowyThemeData(
      textColorScheme: AppFlowyTextColorScheme(
        primary: palette.textPrimary,
        secondary: palette.textSecondary,
        tertiary: palette.textMuted,
        quaternary: palette.borderStrong,
        onFill: palette.onAccent,
        action: palette.accent,
        actionHover: palette.accentHover,
        info: info,
        infoHover: infoHover,
        success: success,
        successHover: successHover,
        warning: warning,
        warningHover: warningHover,
        error: error,
        errorHover: errorHover,
        featured: featured,
        featuredHover: featuredHover,
      ),
      textStyle: base.textStyle,
      iconColorScheme: AppFlowyIconColorScheme(
        primary: palette.textPrimary,
        secondary: palette.textSecondary,
        tertiary: palette.textMuted,
        quaternary: palette.borderStrong,
        onFill: palette.onAccent,
        featuredThick: semantic(icon.featuredThick),
        featuredThickHover: semantic(icon.featuredThickHover),
        infoThick: semantic(icon.infoThick),
        infoThickHover: semantic(icon.infoThickHover),
        successThick: semantic(icon.successThick),
        successThickHover: semantic(icon.successThickHover),
        warningThick: semantic(icon.warningThick),
        warningThickHover: semantic(icon.warningThickHover),
        errorThick: semantic(icon.errorThick),
        errorThickHover: semantic(icon.errorThickHover),
      ),
      borderColorScheme: AppFlowyBorderColorScheme(
        primary: palette.border,
        primaryHover: palette.borderStrong,
        secondary: palette.textSecondary,
        secondaryHover: palette.textPrimary,
        tertiary: palette.textPrimary,
        tertiaryHover: palette.accentHover,
        themeThick: palette.accent,
        themeThickHover: palette.accentHover,
        infoThick: semantic(border.infoThick),
        infoThickHover: semantic(border.infoThickHover),
        successThick: semantic(border.successThick),
        successThickHover: semantic(border.successThickHover),
        warningThick: semantic(border.warningThick),
        warningThickHover: semantic(border.warningThickHover),
        errorThick: semantic(border.errorThick),
        errorThickHover: semantic(border.errorThickHover),
        featuredThick: semantic(border.featuredThick),
        featuredThickHover: semantic(border.featuredThickHover),
      ),
      backgroundColorScheme: AppFlowyBackgroundColorScheme(
        primary: palette.canvas,
      ),
      fillColorScheme: AppFlowyFillColorScheme(
        primary: palette.mutedSurface,
        primaryHover: palette.hover,
        secondary: palette.pressed,
        secondaryHover: palette.selected,
        tertiary: palette.textMuted,
        tertiaryHover: palette.textSecondary,
        quaternary: palette.textPrimary,
        quaternaryHover: palette.accentPressed,
        content: palette.floatingSurface.withValues(alpha: 0),
        contentHover: palette.hoverOverlay,
        contentVisible: palette.selectedOverlay,
        contentVisibleHover: palette.focusRing,
        themeThick: palette.accent,
        themeThickHover: palette.accentHover,
        themeSelect: palette.selectedOverlay,
        textSelect: palette.accent.withValues(alpha: 0.22),
        infoLight: semanticSurface(fill.infoThick),
        infoLightHover: semanticSurface(fill.infoThickHover),
        infoThick: semantic(fill.infoThick),
        infoThickHover: semantic(fill.infoThickHover),
        successLight: semanticSurface(success),
        successLightHover: semanticSurface(successHover),
        warningLight: semanticSurface(warning),
        warningLightHover: semanticSurface(warningHover),
        errorLight: semanticSurface(fill.errorThick),
        errorLightHover: semanticSurface(fill.errorThickHover),
        errorThick: semantic(fill.errorThick),
        errorThickHover: semantic(fill.errorThickHover),
        errorSelect: semantic(fill.errorThick).withValues(alpha: 0.12),
        featuredLight: semanticSurface(fill.featuredThick),
        featuredLightHover: semanticSurface(fill.featuredThickHover),
        featuredThick: semantic(fill.featuredThick),
        featuredThickHover: semantic(fill.featuredThickHover),
      ),
      surfaceColorScheme: AppFlowySurfaceColorScheme(
        primary: palette.floatingSurface,
        primaryHover: palette.hover,
        layer01: palette.surface,
        layer01Hover: palette.hover,
        layer02: palette.floatingSurface,
        layer02Hover: palette.hover,
        layer03: palette.floatingSurface,
        layer03Hover: palette.pressed,
        layer04: palette.floatingSurface,
        layer04Hover: palette.pressed,
        inverse: palette.textPrimary,
        secondary: palette.mutedSurface,
        overlay: palette.scrim,
      ),
      borderRadius: base.borderRadius,
      spacing: base.spacing,
      shadow: AppFlowyShadow(
        small: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 8,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
        medium: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 20,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      brandColorScheme: base.brandColorScheme,
      surfaceContainerColorScheme: AppFlowySurfaceContainerColorScheme(
        layer01: palette.sidebar,
        layer02: palette.mutedSurface,
        layer03: palette.pressed,
      ),
      badgeColorScheme: base.badgeColorScheme,
      otherColorsColorScheme: base.otherColorsColorScheme,
    );
  }

  static ButtonStyle _primaryButtonStyle({
    required PremiumThemeExtension palette,
    required Size minimumSize,
    required EdgeInsetsGeometry padding,
    required TextStyle? textStyle,
    required OutlinedBorder shape,
  }) =>
      ButtonStyle(
        animationDuration: transitionDuration,
        minimumSize: WidgetStatePropertyAll(minimumSize),
        padding: WidgetStatePropertyAll(padding),
        shape: WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(textStyle),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: _stateColor(
          normal: palette.onAccent,
          disabled: palette.textMuted,
        ),
        backgroundColor: _stateColor(
          normal: palette.accent,
          hovered: palette.accentHover,
          pressed: palette.accentPressed,
          disabled: palette.mutedSurface,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      );

  static WidgetStateProperty<Color?> _stateColor({
    required Color normal,
    Color? hovered,
    Color? pressed,
    Color? selected,
    Color? disabled,
  }) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled) && disabled != null) {
          return disabled;
        }
        if (states.contains(WidgetState.pressed) && pressed != null) {
          return pressed;
        }
        if (states.contains(WidgetState.selected) && selected != null) {
          return selected;
        }
        if (states.contains(WidgetState.hovered) && hovered != null) {
          return hovered;
        }
        return normal;
      });

  static Color _mutedAccent(Color source) {
    final hsl = HSLColor.fromColor(source);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.18, 0.40))
        .withLightness(hsl.lightness.clamp(0.30, 0.36))
        .toColor();
  }

  static Color _softenSemantic(
    Color source, {
    required double maximumSaturation,
  }) {
    final hsl = HSLColor.fromColor(source);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.18, maximumSaturation))
        .withLightness(hsl.lightness.clamp(0.34, 0.48))
        .toColor();
  }

  static Color _shiftLightness(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  static double _contrastRatio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
