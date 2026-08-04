import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:flutter/material.dart';

/// The measurements every chart surface shares.
///
/// One place for the numbers so a chart in a page, a tab and a collection are
/// visibly the same object.
abstract final class ChartMetrics {
  static const cardRadius = 14.0;
  static const chipRadius = 8.0;
  static const tooltipRadius = 12.0;

  static const chipHeight = 28.0;
  static const headerGap = 8.0;
  static const plotGap = 24.0;
  static const legendGap = 16.0;

  /// Air above the highest gridline, so the top label and the tallest point
  /// are not pressed against whatever sits above the chart.
  static const plotHeadroom = 24.0;

  /// Air past the last category, so a label at the end is not cut off.
  static const plotSideroom = 10.0;

  /// A bar never grows past this, so two categories do not become two slabs.
  static const maximumBarWidth = 46.0;
  static const minimumBarWidth = 2.0;

  /// How much of a category slot the bars fill.
  static const barGroupFill = 0.62;
  static const barInnerGap = 3.0;
  static const barRadius = 5.0;

  static const pointRadius = 3.6;
  static const pointHoverRadius = 5.4;
  static const lineWidth = 2.0;
  static const gridWidth = 1.0;

  static const bubbleMinimumRadius = 5.0;
  static const bubbleMaximumRadius = 26.0;

  static const axisLabelSize = 10.5;
  static const axisTitleSize = 10.5;
  static const axisGap = 10.0;

  static const revealDuration = Duration(milliseconds: 620);
  static const hoverDuration = Duration(milliseconds: 150);
  static const morphDuration = Duration(milliseconds: 420);

  static const hoverCurve = Curves.easeOutCubic;
  static const revealCurve = Curves.easeOutCubic;

  /// How far a series fades when another one is being read.
  static const mutedOpacity = 0.22;
}

/// The ink a chart is drawn with.
@immutable
class ChartPalette {
  const ChartPalette({
    required this.background,
    required this.surface,
    required this.grid,
    required this.axis,
    required this.label,
    required this.strongLabel,
    required this.series,
    required this.baseTextStyle,
    required this.shadow,
    required this.border,
    required this.chip,
    required this.chipHover,
    required this.isDark,
  });

  /// Muted and evenly spaced, in the manner of Numbers and Linear rather than
  /// a set of primaries.
  static const List<Color> defaultSeries = [
    Color(0xFF5B8DEF),
    Color(0xFF3FBFA0),
    Color(0xFFE8A552),
    Color(0xFFE4738C),
    Color(0xFF9B87F5),
    Color(0xFF4EBBD5),
    Color(0xFFBE9A63),
    Color(0xFF7F8CA3),
    Color(0xFFD183C9),
    Color(0xFF8FAE68),
  ];

  /// A slightly brighter set, so a muted palette still reads on a dark canvas.
  static const List<Color> darkSeries = [
    Color(0xFF7BA5F5),
    Color(0xFF52D0B0),
    Color(0xFFF0B66B),
    Color(0xFFF08AA0),
    Color(0xFFB09CFF),
    Color(0xFF66CDE4),
    Color(0xFFD1AC76),
    Color(0xFF95A2B8),
    Color(0xFFE29ADA),
    Color(0xFFA5C37D),
  ];

  /// The sets a chart can be drawn in, each already balanced against itself.
  static const Map<ChartPaletteName, List<Color>> sets = {
    ChartPaletteName.classic: defaultSeries,
    ChartPaletteName.ocean: [
      Color(0xFF2E6F9E),
      Color(0xFF3E9BB5),
      Color(0xFF56BFC0),
      Color(0xFF7FD4B8),
      Color(0xFF9AA9D6),
      Color(0xFF5C7FC0),
      Color(0xFF6EC5DE),
      Color(0xFF89A7C4),
      Color(0xFFA8DCD2),
      Color(0xFF44567F),
    ],
    ChartPaletteName.sunset: [
      Color(0xFFE0725C),
      Color(0xFFEE9A5B),
      Color(0xFFF2C260),
      Color(0xFFD8607D),
      Color(0xFFB9587E),
      Color(0xFFF0AE86),
      Color(0xFFC96F53),
      Color(0xFFE8B4A0),
      Color(0xFF8E4F6B),
      Color(0xFFF5D69B),
    ],
    ChartPaletteName.meadow: [
      Color(0xFF6BA368),
      Color(0xFF95C07A),
      Color(0xFFC2D68A),
      Color(0xFF4E8B72),
      Color(0xFFA9C4A0),
      Color(0xFF7FB09B),
      Color(0xFFD3D98F),
      Color(0xFF3F6B57),
      Color(0xFFB5CDB0),
      Color(0xFF8AA05C),
    ],
    ChartPaletteName.berry: [
      Color(0xFF9B5FA8),
      Color(0xFFC2689F),
      Color(0xFFD9819C),
      Color(0xFF7A4E97),
      Color(0xFFE0A2BE),
      Color(0xFFA96FB8),
      Color(0xFF8C5A7E),
      Color(0xFFCB93CE),
      Color(0xFF63407A),
      Color(0xFFEBB9CE),
    ],
    ChartPaletteName.slate: [
      Color(0xFF5A6B80),
      Color(0xFF7E8FA3),
      Color(0xFF9EAAB9),
      Color(0xFF44515F),
      Color(0xFFB6BFC9),
      Color(0xFF6E7C8C),
      Color(0xFF8B98A6),
      Color(0xFF39434F),
      Color(0xFFC8CFD6),
      Color(0xFF515E6E),
    ],
  };

  final Color background;
  final Color surface;
  final Color grid;
  final Color axis;
  final Color label;
  final Color strongLabel;
  final List<Color> series;
  final TextStyle baseTextStyle;
  final Color shadow;
  final Color border;
  final Color chip;
  final Color chipHover;
  final bool isDark;

  Color colorAt(int index) => series[index % series.length];

  /// The same palette drawn from a different set.
  ChartPalette withSet(ChartPaletteName name) {
    final chosen = ChartPalette.sets[name] ?? ChartPalette.defaultSeries;
    return ChartPalette(
      background: background,
      surface: surface,
      grid: grid,
      axis: axis,
      label: label,
      strongLabel: strongLabel,
      // A dark canvas needs its colours lifted, whichever set was chosen.
      series: isDark ? [for (final color in chosen) _lift(color)] : chosen,
      baseTextStyle: baseTextStyle,
      shadow: shadow,
      border: border,
      chip: chip,
      chipHover: chipHover,
      isDark: isDark,
    );
  }

  static Color _lift(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + 0.12).clamp(0.0, 0.82))
        .withSaturation((hsl.saturation * 0.92).clamp(0.0, 1.0))
        .toColor();
  }

  TextStyle text({
    required double size,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.2,
    double? letterSpacing,
  }) =>
      baseTextStyle.copyWith(
        fontSize: size,
        color: color ?? label,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        leadingDistribution: TextLeadingDistribution.even,
      );
}

/// Reads a chart palette out of the surrounding theme.
///
/// Paper keeps its warm surfaces, dark gets the brighter series, and light
/// stays quiet — the chart never introduces a colour the app does not own.
ChartPalette chartPaletteOf(BuildContext context, {Color? background}) {
  final theme = Theme.of(context);
  final premium = PremiumThemeExtension.maybeOf(context);
  final isDark = theme.brightness == Brightness.dark;
  final onSurface = premium?.textPrimary ?? theme.colorScheme.onSurface;
  final canvas = background ?? premium?.surface ?? theme.colorScheme.surface;

  return ChartPalette(
    background: canvas,
    surface: premium?.floatingSurface ?? canvas,
    grid: onSurface.withValues(alpha: isDark ? 0.085 : 0.055),
    axis: onSurface.withValues(alpha: isDark ? 0.22 : 0.16),
    label: premium?.textMuted ?? onSurface.withValues(alpha: 0.48),
    strongLabel: onSurface.withValues(alpha: isDark ? 0.92 : 0.82),
    series: isDark ? ChartPalette.darkSeries : ChartPalette.defaultSeries,
    baseTextStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
    shadow:
        premium?.shadow ?? Colors.black.withValues(alpha: isDark ? 0.42 : 0.10),
    border: premium?.border ?? onSurface.withValues(alpha: 0.07),
    chip: premium?.mutedSurface ?? onSurface.withValues(alpha: 0.042),
    chipHover: premium?.hover ?? onSurface.withValues(alpha: 0.075),
    isDark: isDark,
  );
}

/// What colour each part of a chart is drawn in.
///
/// A chosen colour always wins; otherwise the palette's set answers by
/// position, so a chart looks settled before anyone touches it.
@immutable
class ChartColors {
  const ChartColors({required this.palette, required this.chosen});

  factory ChartColors.of(ChartPalette palette, ChartSpec spec) => ChartColors(
        palette: palette.withSet(spec.palette),
        chosen: spec.colors,
      );

  final ChartPalette palette;
  final Map<String, int> chosen;

  Color at(int index, String name) {
    final override = chosen[chartColorKey(name, index)];
    return override != null ? Color(override) : palette.colorAt(index);
  }

  /// Whether this one was chosen by hand rather than taken from the set.
  bool isChosen(int index, String name) =>
      chosen.containsKey(chartColorKey(name, index));

  /// A colour as a single number, which is how a spec stores one.
  static int packed(Color color) =>
      ((color.a * 255).round() << 24) |
      ((color.r * 255).round() << 16) |
      ((color.g * 255).round() << 8) |
      (color.b * 255).round();

  /// The colours someone can pick from, drawn wide enough to cover the sets.
  static const List<Color> swatches = [
    Color(0xFF5B8DEF),
    Color(0xFF3B6FD4),
    Color(0xFF4EBBD5),
    Color(0xFF3FBFA0),
    Color(0xFF5FA35C),
    Color(0xFF8FAE68),
    Color(0xFFD9C15E),
    Color(0xFFE8A552),
    Color(0xFFE07B4F),
    Color(0xFFD9534F),
    Color(0xFFE4738C),
    Color(0xFFD183C9),
    Color(0xFF9B87F5),
    Color(0xFF7A5FBF),
    Color(0xFFBE9A63),
    Color(0xFF8B6F52),
    Color(0xFF7F8CA3),
    Color(0xFF55606E),
  ];
}

/// The shadow under a chart card and its tooltip.
List<BoxShadow> chartCardShadow(ChartPalette palette) => [
      BoxShadow(
        color: palette.shadow.withValues(alpha: palette.shadow.a * 0.55),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: palette.shadow,
        blurRadius: 18,
        spreadRadius: -4,
        offset: const Offset(0, 6),
      ),
    ];

List<BoxShadow> chartTooltipShadow(ChartPalette palette) => [
      BoxShadow(
        color: palette.shadow.withValues(alpha: palette.shadow.a * 0.7),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: palette.shadow,
        blurRadius: 28,
        spreadRadius: -6,
        offset: const Offset(0, 10),
      ),
    ];
