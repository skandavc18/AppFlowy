import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// Every fixed size and duration the map uses.
///
/// Geometry only — nothing here knows about colour, so the same numbers serve
/// light, dark and paper.
abstract final class MapMetrics {
  static const double markerWidth = 30;
  static const double markerHeight = 38;
  static const double markerRadius = 11;
  static const double markerTail = 7;
  static const double markerIcon = 15;
  static const double markerBorder = 2;

  static const double clusterMin = 34;
  static const double clusterMax = 60;
  static const double clusterRing = 8;

  static const double controlSize = 34;
  static const double controlRadius = 10;
  static const double controlGroupRadius = 12;
  static const double controlGap = 8;
  static const double controlInset = 14;

  static const double popupWidth = 296;
  static const double popupRadius = 16;
  static const double popupCover = 116;
  static const double popupGap = 12;

  static const double searchWidth = 300;
  static const double searchHeight = 36;

  static const double attributionInset = 6;

  static const Duration drop = Duration(milliseconds: 420);
  static const Duration hover = Duration(milliseconds: 140);
  static const Duration popup = Duration(milliseconds: 170);
  static const Duration fly = Duration(milliseconds: 560);
  static const Duration wheelSettle = Duration(milliseconds: 180);

  static const Curve dropCurve = Curves.easeOutBack;
  static const Curve flyCurve = Curves.easeInOutCubic;

  /// How far a marker rises when the pointer is over it.
  static const double hoverLift = 4;

  /// How much bigger the chosen marker is drawn.
  static const double selectedScale = 1.18;
}

/// The colours the map chrome is drawn in.
@immutable
class MapPalette {
  const MapPalette({
    required this.canvas,
    required this.surface,
    required this.floating,
    required this.hover,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.shadow,
    required this.isDark,
    required this.isPaper,
  });

  final Color canvas;
  final Color surface;
  final Color floating;
  final Color hover;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color shadow;
  final bool isDark;
  final bool isPaper;

  /// The basemap that matches the application's appearance.
  MapStyleName get defaultStyle {
    if (isPaper) {
      return MapStyleName.paper;
    }
    return isDark ? MapStyleName.dark : MapStyleName.light;
  }

  /// Markers with no colour of their own cycle through these, so a table with
  /// no status column is still readable.
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

  Color swatchAt(int index) => swatches[index.abs() % swatches.length];

  /// A colour picked from the text itself, so the same status is always the
  /// same colour without anyone having to choose one.
  Color swatchFor(String value) {
    if (value.isEmpty) {
      return accent;
    }
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return swatchAt(hash);
  }

  List<BoxShadow> get chromeShadow => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.44 : 0.13),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.28 : 0.07),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  List<BoxShadow> get popupShadow => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.5 : 0.16),
          blurRadius: 34,
          spreadRadius: -8,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.3 : 0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  List<BoxShadow> get markerShadow => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.55 : 0.28),
          blurRadius: 8,
          spreadRadius: -1,
          offset: const Offset(0, 3),
        ),
      ];
}

/// The map palette for the appearance the application is wearing.
MapPalette mapPaletteOf(BuildContext context) {
  final theme = Theme.of(context);
  final premium = theme.extension<PremiumThemeExtension>();
  final isDark = theme.brightness == Brightness.dark;
  final isPaper = PaperTheme.isEnabled(context);

  if (premium == null) {
    return MapPalette(
      canvas: theme.colorScheme.surface,
      surface: theme.colorScheme.surface,
      floating: theme.colorScheme.surface,
      hover: theme.colorScheme.onSurface.withValues(alpha: 0.06),
      border: theme.dividerColor,
      textPrimary: theme.colorScheme.onSurface,
      textMuted: theme.hintColor,
      accent: theme.colorScheme.primary,
      shadow: Colors.black,
      isDark: isDark,
      isPaper: isPaper,
    );
  }

  return MapPalette(
    canvas: premium.canvas,
    surface: premium.surface,
    floating: premium.floatingSurface,
    hover: premium.hover,
    border: premium.border,
    textPrimary: premium.textPrimary,
    textMuted: premium.textMuted,
    accent: theme.colorScheme.primary,
    shadow: premium.shadow,
    isDark: isDark,
    isPaper: isPaper,
  );
}
