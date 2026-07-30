import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// The fixed geometry and motion every menu in the application is drawn to.
///
/// Nothing here depends on the theme, so a row in the sidebar, a row in the
/// spreadsheet and a row in the slash menu occupy exactly the same box.
abstract final class AppMenuMetrics {
  /// Floating surface.
  static const double cornerRadius = 14;
  static const double minWidth = 200;
  static const double maxWidth = 380;
  static const double defaultMaxHeight = 520;
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 6,
  );

  /// Rows.
  static const double rowHeight = 32;
  static const double rowHeightWithSubtitle = 46;
  static const double rowRadius = 9;
  static const double rowHorizontalPadding = 10;

  /// Icons sit in a fixed slot so every label starts on the same pixel,
  /// whether or not its neighbour has an icon.
  static const double iconSize = 17;
  static const double iconSlot = 18;
  static const double iconGap = 11;
  static const double submenuArrowSize = 16;

  /// Typography.
  static const double labelSize = 13.5;
  static const double subtitleSize = 11.5;
  static const double shortcutSize = 11.5;
  static const double headerSize = 10.5;

  /// Tracking is set as a fraction of the size, the way the rest of the
  /// application sets it, so a menu label sits on the same rhythm as body text.
  static const double labelTracking = -0.004;
  static const double headerTracking = 0.058;

  /// The variable-weight axis each role is set on, a step above the
  /// application's regular (550) so menu text reads firmer than body copy at
  /// its smaller size without tipping into bold.
  static const double labelWeightAxis = 590;
  static const double subtitleWeightAxis = 520;
  static const double shortcutWeightAxis = 570;
  static const double headerWeightAxis = 660;

  /// Grouping.
  static const double separatorThickness = 1;
  static const double separatorInset = 10;
  static const double separatorSpacing = 6;
  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(12, 9, 12, 5);

  /// Placement.
  static const double screenInset = 8;
  static const double anchorGap = 4;
  static const double submenuGap = 2;
  static const double blurSigma = 22;

  /// Motion. Restrained on purpose — no bounce, no spring.
  static const Duration openDuration = Duration(milliseconds: 150);
  static const Duration closeDuration = Duration(milliseconds: 110);
  static const Duration submenuDuration = Duration(milliseconds: 120);
  static const Duration hoverDuration = Duration(milliseconds: 150);
  static const Duration hoverOutDuration = Duration(milliseconds: 130);
  static const Duration pressDuration = Duration(milliseconds: 90);
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve hoverCurve = Curves.easeOutCubic;

  /// The scale a menu grows from while it fades in.
  static const double openScale = 0.97;

  /// How far a submenu slides in from its parent.
  static const double submenuSlide = 8;

  /// Hover intent.
  static const Duration submenuOpenDelay = Duration(milliseconds: 120);
  static const Duration submenuCloseDelay = Duration(milliseconds: 200);
  static const Duration aimRetryInterval = Duration(milliseconds: 80);

  /// However determined the pointer looks, it only gets this long to reach an
  /// open submenu before the hovered sibling wins.
  static const Duration aimGracePeriod = Duration(milliseconds: 520);
}

/// Every colour a menu draws with, resolved once per menu from the ambient
/// theme so dark, light and paper all read as the same component.
@immutable
class AppMenuStyle {
  const AppMenuStyle({
    required this.brightness,
    required this.surface,
    required this.translucentSurface,
    required this.border,
    required this.separator,
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.labelRest,
    required this.labelStrong,
    required this.icon,
    required this.iconStrong,
    required this.iconMuted,
    required this.accent,
    required this.danger,
    required this.shadows,
    required this.blurred,
    required this.baseTextStyle,
  });

  factory AppMenuStyle.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isPaper = PaperTheme.isEnabled(context) && !isDark;

    final surface = isPaper
        ? PaperTheme.popupBackground
        : premium?.floatingSurface ?? scheme.surfaceContainer;
    final shadowColor = isPaper
        ? PaperTheme.shadow
        : premium?.shadow ?? Colors.black.withValues(alpha: 0.14);

    // Depth comes from three stacked shadows rather than one heavy drop: a
    // wide ambient pool, a mid lift and a hairline contact edge. Kept low in
    // alpha and wide in blur so the card reads as floating, not printed on.
    final shadows = <BoxShadow>[
      BoxShadow(
        color: shadowColor.withValues(alpha: isDark ? 0.40 : 0.10),
        blurRadius: 56,
        offset: const Offset(0, 22),
        spreadRadius: -20,
      ),
      BoxShadow(
        color: shadowColor.withValues(alpha: isDark ? 0.30 : 0.07),
        blurRadius: 20,
        offset: const Offset(0, 8),
        spreadRadius: -9,
      ),
      BoxShadow(
        color: shadowColor.withValues(alpha: isDark ? 0.26 : 0.05),
        blurRadius: 3,
        offset: const Offset(0, 1),
        spreadRadius: -1,
      ),
    ];

    final textPrimary = isPaper
        ? PaperTheme.textPrimary
        : premium?.textPrimary ?? scheme.onSurface;
    final textSecondary = isPaper
        ? PaperTheme.textSecondary
        : premium?.textSecondary ?? scheme.onSurfaceVariant;
    final textMuted = isPaper
        ? PaperTheme.textMuted
        : premium?.textMuted ?? scheme.onSurfaceVariant.withValues(alpha: 0.72);

    // Light and paper menus want richer ink than body text; dark menus want
    // less glare than pure foreground white.
    final labelRest = isDark
        ? Color.lerp(textPrimary, surface, 0.10)!
        : Color.lerp(textPrimary, Colors.black, 0.14)!;
    final labelStrong =
        isDark ? textPrimary : Color.lerp(labelRest, Colors.black, 0.22)!;

    // Icons read one step back from the label, nowhere near as faint as
    // secondary text — a washed-out glyph is what makes a menu look generic.
    final icon = isDark
        ? Color.lerp(textSecondary, textPrimary, 0.28)!
        : Color.lerp(textSecondary, labelStrong, 0.52)!;
    final iconStrong = isDark ? textPrimary : labelStrong;

    // Deliberately desaturated: a destructive row is recognisable without
    // shouting over the rest of the list.
    final danger = isPaper
        ? const Color(0xFFA8442F)
        : isDark
            ? const Color(0xFFE18378)
            : const Color(0xFFBE3A2B);

    return AppMenuStyle(
      brightness: theme.brightness,
      surface: surface,
      translucentSurface: surface.withValues(alpha: isDark ? 0.84 : 0.88),
      border: isPaper
          ? PaperTheme.strongBorder.withValues(alpha: 0.20)
          : (premium?.border ?? scheme.outlineVariant)
              .withValues(alpha: isDark ? 0.34 : 0.22),
      separator: isPaper
          ? PaperTheme.strongBorder.withValues(alpha: 0.18)
          : (premium?.border ?? scheme.outlineVariant)
              .withValues(alpha: isDark ? 0.26 : 0.22),
      hover: isPaper
          ? PaperTheme.controlHover
          : premium?.hover ??
              scheme.onSurface.withValues(alpha: isDark ? 0.09 : 0.055),
      pressed: isPaper
          ? PaperTheme.controlSelected
          : premium?.pressed ??
              scheme.onSurface.withValues(alpha: isDark ? 0.14 : 0.09),
      selected: isPaper
          ? PaperTheme.selectedOverlay
          : premium?.selectedOverlay ??
              scheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      labelRest: labelRest,
      labelStrong: labelStrong,
      icon: icon,
      iconStrong: iconStrong,
      iconMuted: textMuted,
      accent: isPaper ? PaperTheme.accent : premium?.accent ?? scheme.primary,
      danger: danger,
      shadows: shadows,
      blurred: true,
      baseTextStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
    );
  }

  final Brightness brightness;

  /// The opaque menu background.
  final Color surface;

  /// The background used when the card sits over a blur.
  final Color translucentSurface;

  final Color border;
  final Color separator;
  final Color hover;
  final Color pressed;
  final Color selected;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// The ink a row's label is set in, and the slightly richer ink it settles
  /// into while the pointer rests on it.
  final Color labelRest;
  final Color labelStrong;

  final Color icon;
  final Color iconStrong;
  final Color iconMuted;
  final Color accent;
  final Color danger;
  final List<BoxShadow> shadows;
  final bool blurred;

  /// The application's own body face, carrying its family, fallbacks and
  /// variable-weight axis. Menu styles are derived from it so a menu is set in
  /// the same type as the page behind it.
  final TextStyle baseTextStyle;

  bool get isDark => brightness == Brightness.dark;

  BorderRadius get borderRadius =>
      BorderRadius.circular(AppMenuMetrics.cornerRadius);

  BorderRadius get rowBorderRadius =>
      BorderRadius.circular(AppMenuMetrics.rowRadius);

  /// A transparent stand-in that keeps the hover colour's own channels.
  ///
  /// Animating to or from [Colors.transparent] interpolates through
  /// transparent *black*, which flashes dark before it settles.
  Color get hoverBase => hover.withValues(alpha: 0);

  Color get selectedBase => selected.withValues(alpha: 0);

  /// The zero-offset underprint the rest of the application uses to firm up
  /// antialiased edges on light backgrounds.
  List<Shadow> get textUnderprint =>
      AppTextRendering.rootStyleFor(brightness).shadows ?? const [];

  TextStyle _face({
    required double fontSize,
    required FontWeight weight,
    required double tracking,
    required Color color,
    required double axis,
    double height = 1.0,
  }) =>
      AppTextRendering.polish(
        baseTextStyle.copyWith(
          fontSize: fontSize,
          fontWeight: weight,
          // The bundled UI face is variable: without an explicit axis it
          // renders at its default instance and looks thin next to the app.
          fontVariations: [FontVariation.weight(axis)],
          height: height,
          letterSpacing: fontSize * tracking,
          color: color,
          shadows: textUnderprint,
          decoration: TextDecoration.none,
        ),
      );

  TextStyle get labelStyle => _face(
        fontSize: AppMenuMetrics.labelSize,
        weight: FontWeight.w500,
        axis: AppMenuMetrics.labelWeightAxis,
        tracking: AppMenuMetrics.labelTracking,
        color: labelRest,
      );

  TextStyle get subtitleStyle => _face(
        fontSize: AppMenuMetrics.subtitleSize,
        weight: FontWeight.w400,
        axis: AppMenuMetrics.subtitleWeightAxis,
        tracking: AppMenuMetrics.labelTracking,
        color: textMuted,
        height: 1.25,
      );

  TextStyle get shortcutStyle => _face(
        fontSize: AppMenuMetrics.shortcutSize,
        weight: FontWeight.w500,
        axis: AppMenuMetrics.shortcutWeightAxis,
        tracking: 0.012,
        color: textMuted,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  TextStyle get headerStyle => _face(
        fontSize: AppMenuMetrics.headerSize,
        weight: FontWeight.w600,
        axis: AppMenuMetrics.headerWeightAxis,
        tracking: AppMenuMetrics.headerTracking,
        color: textMuted,
      );

  /// The colour a row's label rests at, before the pointer emphasises it.
  Color labelColorFor({
    required bool enabled,
    required bool destructive,
  }) {
    if (!enabled) {
      return textMuted.withValues(alpha: 0.55);
    }
    return destructive ? danger : labelRest;
  }

  /// The colour a row's label settles into under the pointer.
  Color labelEmphasisFor({
    required bool enabled,
    required bool destructive,
  }) {
    if (!enabled) {
      return textMuted.withValues(alpha: 0.55);
    }
    return destructive ? danger : labelStrong;
  }

  /// The colour a row's icon rests at.
  Color iconColorFor({
    required bool enabled,
    required bool destructive,
    required bool selected,
  }) {
    if (!enabled) {
      return iconMuted.withValues(alpha: 0.5);
    }
    if (destructive) {
      return danger;
    }
    return selected ? accent : icon;
  }

  /// The colour a row's icon settles into under the pointer.
  Color iconEmphasisFor({
    required bool enabled,
    required bool destructive,
    required bool selected,
  }) {
    if (!enabled) {
      return iconMuted.withValues(alpha: 0.5);
    }
    if (destructive) {
      return danger;
    }
    return selected ? accent : iconStrong;
  }

  AppMenuStyle copyWith({bool? blurred}) => AppMenuStyle(
        brightness: brightness,
        surface: surface,
        translucentSurface: translucentSurface,
        border: border,
        separator: separator,
        hover: hover,
        pressed: pressed,
        selected: selected,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textMuted: textMuted,
        labelRest: labelRest,
        labelStrong: labelStrong,
        icon: icon,
        iconStrong: iconStrong,
        iconMuted: iconMuted,
        accent: accent,
        danger: danger,
        shadows: shadows,
        blurred: blurred ?? this.blurred,
        baseTextStyle: baseTextStyle,
      );
}

/// Motion tokens re-exported so menu code reads from one place.
abstract final class AppMenuMotion {
  static const Duration hover = AppMenuMetrics.hoverDuration;
  static const Curve hoverCurve = AppMenuMetrics.hoverCurve;
  static const Duration standard = AppFlowyMotion.standard;
}
