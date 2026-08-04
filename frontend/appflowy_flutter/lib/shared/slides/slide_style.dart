import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// Every fixed size and duration a deck uses.
abstract final class SlideMetrics {
  static const double cardRadius = 22;
  static const double coverHeight = 168;
  static const double cardPadding = 26;
  static const double propertyGap = 16;
  static const double iconSize = 40;

  static const double badgeRadius = 8;
  static const double avatarSize = 26;
  static const double progressHeight = 6;
  static const double mapPreviewHeight = 132;
  static const double imagePreviewHeight = 148;

  static const double controlSize = 34;
  static const double controlRadius = 10;
  static const double controlGap = 8;
  static const double headerHeight = 40;
  static const double searchWidth = 240;
  static const double railHeight = 4;
  static const double railWidth = 22;

  /// How far the pointer lifts a slide off the page.
  static const double hoverLift = 6;

  /// The perspective the rack is seen through. Small on purpose — anything
  /// stronger reads as a gimmick rather than depth.
  static const double perspective = 0.0011;

  static const Duration settle = Duration(milliseconds: 380);
  static const Duration change = Duration(milliseconds: 300);
  static const Duration hover = Duration(milliseconds: 180);
  static const Duration enter = Duration(milliseconds: 420);

  static const Curve settleCurve = Curves.easeInOutCubic;
  static const Curve enterCurve = Curves.easeOutCubic;

  /// How far a wheel notch moves the deck.
  static const double wheelStep = 1 / 3;

  /// How fast a drag has to be released to carry on to the next slide.
  static const double flingVelocity = 320;
}

/// The colours a deck is drawn in.
@immutable
class SlidePalette {
  const SlidePalette({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.hover,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.shadow,
    required this.isDark,
    required this.isPaper,
  });

  /// Behind the deck.
  final Color canvas;

  /// The face of a slide.
  final Color surface;

  /// A panel standing on a slide.
  final Color raised;

  /// A well cut into a slide, such as a progress track.
  final Color sunken;

  final Color hover;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color shadow;
  final bool isDark;
  final bool isPaper;

  /// Values with no colour of their own cycle through these.
  static const List<Color> swatches = [
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
  ];

  Color swatchFor(String value) {
    if (value.trim().isEmpty) {
      return accent;
    }
    var hash = 0;
    for (final unit in value.trim().toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return swatches[hash % swatches.length];
  }

  /// A slide's own shadow, deepening as it comes forward.
  List<BoxShadow> cardShadow(double prominence, {double lift = 0}) {
    final depth = 0.35 + 0.65 * prominence.clamp(0.0, 1.0);
    return [
      BoxShadow(
        color: shadow.withValues(alpha: (isDark ? 0.5 : 0.16) * depth),
        blurRadius: 38 + lift * 3,
        spreadRadius: -12,
        offset: Offset(0, 18 + lift),
      ),
      BoxShadow(
        color: shadow.withValues(alpha: (isDark ? 0.32 : 0.08) * depth),
        blurRadius: 9,
        offset: Offset(0, 2 + lift / 3),
      ),
    ];
  }

  List<BoxShadow> get chromeShadow => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.42 : 0.12),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
}

/// The deck palette for the appearance the application is wearing.
SlidePalette slidePaletteOf(BuildContext context) {
  final theme = Theme.of(context);
  final premium = theme.extension<PremiumThemeExtension>();
  final isDark = theme.brightness == Brightness.dark;
  final isPaper = PaperTheme.isEnabled(context);

  if (premium == null) {
    final onSurface = theme.colorScheme.onSurface;
    return SlidePalette(
      canvas: theme.colorScheme.surface,
      surface: theme.colorScheme.surface,
      raised: theme.colorScheme.surface,
      sunken: onSurface.withValues(alpha: 0.08),
      hover: onSurface.withValues(alpha: 0.06),
      border: theme.dividerColor,
      textPrimary: onSurface,
      textSecondary: onSurface.withValues(alpha: 0.78),
      textMuted: theme.hintColor,
      accent: theme.colorScheme.primary,
      shadow: Colors.black,
      isDark: isDark,
      isPaper: isPaper,
    );
  }

  return SlidePalette(
    canvas: premium.canvas,
    surface: premium.floatingSurface,
    raised: premium.mutedSurface,
    sunken: premium.mutedSurface,
    hover: premium.hover,
    border: premium.border,
    textPrimary: premium.textPrimary,
    textSecondary: Color.lerp(premium.textMuted, premium.textPrimary, 0.55) ??
        premium.textPrimary,
    textMuted: premium.textMuted,
    accent: theme.colorScheme.primary,
    shadow: premium.shadow,
    isDark: isDark,
    isPaper: isPaper,
  );
}
