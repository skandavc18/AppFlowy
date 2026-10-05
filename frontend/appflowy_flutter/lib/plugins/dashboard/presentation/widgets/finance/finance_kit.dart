import 'dart:math' as math;

import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

/// The colours money is drawn in: what rose, what fell, and the hues
/// categories wear. Light, dark and paper each get their own family — on
/// paper the green is sage and the red is brick, so a P&L still reads at a
/// glance without breaking the warmth of the page.
@immutable
class FinanceColors {
  const FinanceColors._({
    required this.gain,
    required this.loss,
    required this.flat,
    required this.series,
    required this.palette,
  });

  factory FinanceColors.of(DashboardPalette palette) {
    if (palette.isPaper) {
      return FinanceColors._(
        gain: const Color(0xFF3F8F5A),
        loss: const Color(0xFFC0503F),
        flat: palette.textMuted,
        series: _paperSeries,
        palette: palette,
      );
    }
    if (palette.isDark) {
      return FinanceColors._(
        gain: const Color(0xFF34D399),
        loss: const Color(0xFFF87171),
        flat: palette.textMuted,
        series: _darkSeries,
        palette: palette,
      );
    }
    return FinanceColors._(
      gain: const Color(0xFF0E9F6E),
      loss: const Color(0xFFE5484D),
      flat: palette.textMuted,
      series: _lightSeries,
      palette: palette,
    );
  }

  final Color gain;
  final Color loss;
  final Color flat;
  final List<Color> series;
  final DashboardPalette palette;

  bool get isDark => palette.isDark;
  bool get isPaper => palette.isPaper;

  /// Green for up, red for down, grey for nothing moved.
  Color change(double? value) {
    if (value == null || value.abs() < 1e-9) {
      return flat;
    }
    return value > 0 ? gain : loss;
  }

  /// One of the category hues, cycling.
  Color hue(int index) => series[index.abs() % series.length];

  /// A stable hue for a name, so RELIANCE is always the same colour.
  Color hueFor(String name) => hue(_hash(name.toLowerCase()));

  /// A soft wash of [color] to sit something on.
  Color wash(Color color, [double amount = 0.13]) =>
      color.withValues(alpha: isDark ? amount + 0.07 : amount);

  /// [color] blended onto the card, opaque, for fills that must not let a
  /// grid line show through.
  Color solidWash(Color color, Color onto, [double amount = 0.14]) =>
      Color.alphaBlend(wash(color, amount), onto);

  /// The two stops of a jewel-like fill in [color].
  List<Color> gradientOf(Color color) {
    final hsl = HSLColor.fromColor(color);
    final light = hsl
        .withLightness((hsl.lightness + (isDark ? 0.08 : 0.12)).clamp(0, 0.92))
        .withHue((hsl.hue + 12) % 360)
        .toColor();
    final deep = hsl
        .withLightness((hsl.lightness - (isDark ? 0.04 : 0.08)).clamp(0.08, 1))
        .toColor();
    return [light, deep];
  }

  /// A soft coloured lift under something in [color].
  List<BoxShadow> glow(Color color, {double strength = 1, bool lifted = false}) {
    if (isDark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.32 * strength),
          blurRadius: lifted ? 18 : 12,
          spreadRadius: -4,
          offset: Offset(0, lifted ? 8 : 5),
        ),
        BoxShadow(
          color: color.withValues(alpha: (lifted ? 0.22 : 0.12) * strength),
          blurRadius: lifted ? 22 : 14,
          spreadRadius: -6,
        ),
      ];
    }
    final tint = isPaper ? 0.6 : 1.0;
    return [
      BoxShadow(
        color: color.withValues(alpha: (lifted ? 0.26 : 0.16) * strength * tint),
        blurRadius: lifted ? 22 : 14,
        spreadRadius: -6,
        offset: Offset(0, lifted ? 10 : 6),
      ),
      BoxShadow(
        color: palette.shadowColor.withValues(alpha: 0.05 * strength),
        blurRadius: 2,
        spreadRadius: -1,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// A raised inner panel: a strategy card, a category tile.
  BoxDecoration panel({
    bool hovered = false,
    Color? hue,
    double radius = DashboardMetrics.innerRadius,
  }) {
    final base = isPaper
        ? Color.alphaBlend(
            const Color(0xFFFFFFFF).withValues(alpha: 0.42),
            palette.surface,
          )
        : (isDark
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: hovered ? 0.06 : 0.035),
                palette.surface,
              )
            : palette.raised);
    return BoxDecoration(
      color: base,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: hovered && hue != null
            ? hue.withValues(alpha: isDark ? 0.45 : 0.32)
            : palette.border.withValues(alpha: isDark ? 0.42 : 0.5),
      ),
      boxShadow: hovered
          ? glow(hue ?? palette.accent, lifted: true, strength: 0.9)
          : [
              BoxShadow(
                color: palette.shadowColor.withValues(
                  alpha: isDark ? 0.18 : 0.045,
                ),
                blurRadius: 8,
                spreadRadius: -3,
                offset: const Offset(0, 3),
              ),
            ],
    );
  }

  static int _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

const _lightSeries = [
  Color(0xFF6366F1),
  Color(0xFF0EA5E9),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFF43F5E),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFFF97316),
  Color(0xFFEC4899),
  Color(0xFF84CC16),
  Color(0xFF06B6D4),
  Color(0xFF64748B),
];

const _darkSeries = [
  Color(0xFF818CF8),
  Color(0xFF38BDF8),
  Color(0xFF34D399),
  Color(0xFFFBBF24),
  Color(0xFFFB7185),
  Color(0xFFA78BFA),
  Color(0xFF2DD4BF),
  Color(0xFFFB923C),
  Color(0xFFF472B6),
  Color(0xFFA3E635),
  Color(0xFF22D3EE),
  Color(0xFF94A3B8),
];

const _paperSeries = [
  Color(0xFF6B6FB5),
  Color(0xFF4C8FB0),
  Color(0xFF4F9A72),
  Color(0xFFC08A2E),
  Color(0xFFC25B5B),
  Color(0xFF8A6BB0),
  Color(0xFF3F948A),
  Color(0xFFC9733A),
  Color(0xFFB5628C),
  Color(0xFF8A9A3E),
  Color(0xFF3E8EA3),
  Color(0xFF8C7B6B),
];

/// Whether this widget should hold still: the dashboard asked for no motion,
/// or the platform did.
bool financeStill(DashboardWidgetContext data, BuildContext context) =>
    data.controller.document.settings.reduceMotion ||
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

/// How a widget writes money, from its `currency` setting.
MoneyStyle financeMoney(DashboardWidgetContext data) =>
    MoneyStyle.forCurrency(data.spec.setting('currency', fallback: 'INR'));

/// Numbers set for reading in columns: tabular figures, tight tracking.
TextStyle financeNumber(
  Color color, {
  double size = 13,
  FontWeight weight = FontWeight.w600,
  double letterSpacing = -0.2,
}) =>
    TextStyle(
      fontSize: size,
      height: 1.2,
      letterSpacing: letterSpacing,
      color: color,
      fontWeight: weight,
      fontVariations: flowyFontVariationsForWeight(weight),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle financeLabel(
  Color color, {
  double size = 11.5,
  FontWeight weight = FontWeight.w500,
  double letterSpacing = 0.1,
}) =>
    TextStyle(
      fontSize: size,
      height: 1.25,
      letterSpacing: letterSpacing,
      color: color,
      fontWeight: weight,
      fontVariations: flowyFontVariationsForWeight(weight),
    );

/// A figure that counts to its value, then glides between values as they
/// change. A new widget counts up once; later updates only glide.
class AnimatedFigure extends StatefulWidget {
  const AnimatedFigure({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.still = false,
    this.countUp = false,
    this.duration = const Duration(milliseconds: 900),
    this.maxLines = 1,
    this.textAlign,
  });

  final double value;
  final String Function(double value) format;
  final TextStyle style;
  final bool still;

  /// Count up from zero when first shown, rather than appearing at value.
  final bool countUp;
  final Duration duration;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  State<AnimatedFigure> createState() => _AnimatedFigureState();
}

class _AnimatedFigureState extends State<AnimatedFigure> {
  late final double _start =
      widget.countUp && !widget.still ? widget.value * 0.72 : widget.value;

  @override
  Widget build(BuildContext context) {
    final text = TweenAnimationBuilder<double>(
      tween: Tween(begin: _start, end: widget.value),
      duration: widget.still ? Duration.zero : widget.duration,
      curve: Curves.easeOutExpo,
      builder: (context, value, _) => Text(
        widget.format(value),
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textAlign: widget.textAlign,
        style: widget.style,
      ),
    );
    return text;
  }
}

/// A change written as a soft pill: `▲ 1.24%`.
class ChangePill extends StatelessWidget {
  const ChangePill({
    super.key,
    required this.colors,
    required this.value,
    required this.text,
    this.dense = false,
    this.solid = false,
  });

  final FinanceColors colors;

  /// Decides the colour and the arrow.
  final double? value;
  final String text;
  final bool dense;

  /// A filled pill for use on colour, rather than a wash.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final color = colors.change(value);
    final up = (value ?? 0) > 0;
    final flat = value == null || value!.abs() < 1e-9;
    final ink = solid ? Colors.white : color;
    return AnimatedContainer(
      duration: DashboardMetrics.settle,
      curve: DashboardMetrics.curve,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3.5,
      ),
      decoration: BoxDecoration(
        color: solid ? color : colors.wash(color, 0.12),
        borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!flat)
            Icon(
              up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
              size: dense ? 15 : 17,
              color: ink,
            ),
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: financeNumber(ink, size: dense ? 11 : 12),
          ),
          if (!flat) SizedBox(width: dense ? 1 : 2),
        ],
      ),
    );
  }
}

/// A small dot that breathes while prices are live.
class LiveDot extends StatefulWidget {
  const LiveDot({
    super.key,
    required this.color,
    this.live = true,
    this.still = false,
    this.size = 7,
  });

  final Color color;
  final bool live;
  final bool still;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  bool get _animates => widget.live && !widget.still;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_animates) {
      final controller = _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      );
      if (!controller.isAnimating) {
        controller.repeat();
      }
    } else {
      _controller?.stop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: widget.live ? widget.color : widget.color.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
    );
    final controller = _controller;
    if (!_animates || controller == null) {
      return SizedBox.square(dimension: size * 2.2, child: Center(child: dot));
    }
    return SizedBox.square(
      dimension: size * 2.2,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final t = Curves.easeOut.transform(controller.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size * (1 + 1.2 * t),
                height: size * (1 + 1.2 * t),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                  shape: BoxShape.circle,
                ),
              ),
              child!,
            ],
          );
        },
        child: dot,
      ),
    );
  }
}

/// An icon on a jewel-like tile with a glow of its own colour.
class FinanceIconTile extends StatelessWidget {
  const FinanceIconTile({
    super.key,
    required this.icon,
    required this.color,
    required this.colors,
    this.size = 36,
    this.soft = false,
  });

  final IconData icon;
  final Color color;
  final FinanceColors colors;
  final double size;

  /// A wash with a coloured icon, for dense rows, instead of a solid tile.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.32);
    if (soft) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.wash(color, 0.14),
          borderRadius: radius,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.52, color: color),
      );
    }
    final stops = colors.gradientOf(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: stops,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(
              alpha: colors.isDark ? 0.28 : (colors.isPaper ? 0.2 : 0.32),
            ),
            blurRadius: size * 0.4,
            spreadRadius: -size * 0.12,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: Colors.white),
    );
  }
}

/// Letters on a gradient disc for something with no logo.
class FinanceAvatar extends StatelessWidget {
  const FinanceAvatar({
    super.key,
    required this.label,
    required this.colors,
    this.size = 34,
    this.color,
  });

  final String label;
  final FinanceColors colors;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hue = color ?? colors.hueFor(label);
    final stops = colors.gradientOf(hue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: stops,
        ),
        boxShadow: [
          BoxShadow(
            color: hue.withValues(alpha: colors.isDark ? 0.25 : 0.28),
            blurRadius: size * 0.35,
            spreadRadius: -size * 0.12,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        financeInitials(label),
        maxLines: 1,
        style: financeLabel(
          Colors.white,
          size: size * 0.36,
          weight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// The letters that stand for [name]: RELIANCE.NS is RE, "HDFC Bank" is HB.
String financeInitials(String name) {
  final clean = name.split('.').first.replaceAll('^', '').trim();
  final words = clean
      .split(RegExp(r'[\s_&-]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    final word = words.first;
    return word.substring(0, math.min(2, word.length)).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// A pill of choices with a sliding highlight.
class FinanceSegmented<T> extends StatelessWidget {
  const FinanceSegmented({
    super.key,
    required this.palette,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.color,
  });

  final DashboardPalette palette;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T>? onSelected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? palette.textPrimary;
    // A header can be narrower than every choice: the pill shrinks to fit
    // rather than spilling past the card.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: palette.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : palette.sunken.withValues(alpha: palette.isPaper ? 0.9 : 1),
          borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in values)
              _Segment(
                label: labelOf(value),
                selected: value == selected,
                palette: palette,
                ink: ink,
                onTap: onSelected == null ? null : () => onSelected!(value),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.palette,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final DashboardPalette palette;
  final Color ink;
  final VoidCallback? onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final selected = widget.selected;
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
          decoration: BoxDecoration(
            color: selected
                ? (palette.isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : palette.raised)
                : (_hovered
                    ? palette.hover.withValues(alpha: 0.7)
                    : palette.hoverBase),
            borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
            boxShadow: selected && !palette.isDark
                ? [
                    BoxShadow(
                      color: palette.shadowColor.withValues(alpha: 0.12),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            style: financeLabel(
              selected ? widget.ink : palette.textSecondary,
              weight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Something fading and rising into place, [index] steps after the first.
class FinanceEntrance extends StatefulWidget {
  const FinanceEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.still = false,
    this.offset = 10,
  });

  final Widget child;
  final int index;
  final bool still;
  final double offset;

  @override
  State<FinanceEntrance> createState() => _FinanceEntranceState();
}

class _FinanceEntranceState extends State<FinanceEntrance>
    with SingleTickerProviderStateMixin {
  static const _step = 45;
  static const _length = 420;

  AnimationController? _controller;
  Animation<double>? _curve;

  @override
  void initState() {
    super.initState();
    if (!widget.still) {
      final delay = math.min(widget.index, 12) * _step;
      final total = delay + _length;
      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: total),
      );
      _controller = controller;
      _curve = CurvedAnimation(
        parent: controller,
        curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      );
      controller.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    if (curve == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// A grey block where something is still loading, with light passing over.
class FinanceShimmer extends StatefulWidget {
  const FinanceShimmer({
    super.key,
    required this.palette,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.still = false,
  });

  final DashboardPalette palette;
  final double? width;
  final double height;
  final double radius;
  final bool still;

  @override
  State<FinanceShimmer> createState() => _FinanceShimmerState();
}

class _FinanceShimmerState extends State<FinanceShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!widget.still) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final base = palette.isDark
        ? Colors.white.withValues(alpha: 0.07)
        : palette.sunken;
    final light = palette.isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Color.alphaBlend(Colors.white.withValues(alpha: 0.7), palette.sunken);
    final controller = _controller;
    Widget block(double t) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.6 + 3.2 * t, 0),
              end: Alignment(-0.6 + 3.2 * t, 0),
              colors: [base, light, base],
            ),
          ),
        );
    if (controller == null) {
      return block(0.5);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => block(controller.value),
    );
  }
}

/// Soft coloured light pooling behind a hero card.
class FinanceOrbs extends StatelessWidget {
  const FinanceOrbs({
    super.key,
    required this.colors,
    required this.first,
    required this.second,
  });

  final FinanceColors colors;
  final Color first;
  final Color second;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _OrbPainter(
            first: first,
            second: second,
            strength: colors.isDark ? 0.22 : (colors.isPaper ? 0.14 : 0.2),
          ),
          child: const SizedBox.expand(),
        ),
      );
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.first,
    required this.second,
    required this.strength,
  });

  final Color first;
  final Color second;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    void orb(Offset centre, double radius, Color color) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: strength),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    final reach = math.max(size.width, size.height);
    orb(Offset(size.width * 0.92, -size.height * 0.05), reach * 0.55, first);
    orb(Offset(size.width * 0.12, size.height * 1.15), reach * 0.5, second);
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) =>
      oldDelegate.first != first ||
      oldDelegate.second != second ||
      oldDelegate.strength != strength;
}

/// One line of chips. Whatever does not fit is left out rather than wrapped
/// onto a second line, so a small card never overflows.
class FinanceRun extends StatelessWidget {
  const FinanceRun({
    super.key,
    required this.height,
    required this.children,
    this.spacing = 8,
    this.crossAxisAlignment = WrapCrossAlignment.center,
  });

  final double height;
  final List<Widget> children;
  final double spacing;

  /// Chips sit on the line's middle; figures with captions under them line
  /// up along the top instead, so their labels read across as one row.
  final WrapCrossAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Wrap(
          spacing: spacing,
          // Anything that wraps lands far below the line and is clipped.
          runSpacing: height * 4,
          crossAxisAlignment: crossAxisAlignment,
          clipBehavior: Clip.hardEdge,
          children: [
            // A chip wider than the whole line, or taller than it, is shrunk
            // to fit rather than cut off: a Wrap hands its children no
            // height limit of their own, so the line's is given here.
            for (final child in children)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: child,
                ),
              ),
          ],
        ),
      );
}

/// Hover state for a row or a tile, without a ripple.
class FinanceHover extends StatefulWidget {
  const FinanceHover({
    super.key,
    required this.builder,
    this.onTap,
    this.cursor,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final MouseCursor? cursor;

  @override
  State<FinanceHover> createState() => _FinanceHoverState();
}

class _FinanceHoverState extends State<FinanceHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(context, _hovered);
    return MouseRegion(
      cursor: widget.cursor ??
          (widget.onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click),
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.onTap == null
          ? child
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: child,
            ),
    );
  }
}

/// A small caption over a figure.
class FinanceStat extends StatelessWidget {
  const FinanceStat({
    super.key,
    required this.label,
    required this.value,
    required this.palette,
    this.valueColor,
    this.caption,
    this.size = 15,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final DashboardPalette palette;
  final Color? valueColor;
  final String? caption;
  final double size;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: financeLabel(palette.textMuted, size: 11),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: financeNumber(
              valueColor ?? palette.textPrimary,
              size: size,
            ),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: financeLabel(palette.textMuted, size: 10.5),
            ),
          ],
        ],
      );
}

/// What a finance chart looks like before it has data, drawn faintly behind
/// the invitation so an empty card already hints at what it will become.
enum FinanceGhostShape { line, donut, bars, rows, grid, payoff, tiles, quote }

class FinanceGhost extends StatelessWidget {
  const FinanceGhost({
    super.key,
    required this.palette,
    required this.shape,
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
    this.color,
  });

  final DashboardPalette palette;
  final FinanceGhostShape shape;
  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hue = color ?? palette.accent;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GhostPainter(
                shape: shape,
                color: hue.withValues(alpha: palette.isDark ? 0.16 : 0.11),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DashboardPlaceholder(
            palette: palette,
            icon: icon,
            message: message,
            action: action,
            onAction: onAction,
            color: hue,
          ),
        ),
      ],
    );
  }
}

class _GhostPainter extends CustomPainter {
  const _GhostPainter({required this.shape, required this.color});

  final FinanceGhostShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color.withValues(alpha: color.a * 0.55);
    final w = size.width;
    final h = size.height;
    switch (shape) {
      case FinanceGhostShape.line:
      case FinanceGhostShape.payoff:
        final path = Path()..moveTo(0, h * 0.78);
        const points = [0.7, 0.74, 0.58, 0.64, 0.46, 0.52, 0.34, 0.4, 0.26];
        for (var index = 0; index < points.length; index++) {
          path.lineTo(w * (index + 1) / points.length, h * points[index]);
        }
        canvas.drawPath(path, stroke);
        final area = Path.from(path)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        canvas.drawPath(area, fill);
      case FinanceGhostShape.donut:
        final radius = math.min(w, h) * 0.32;
        canvas.drawCircle(
          Offset(w / 2, h / 2),
          radius,
          stroke..strokeWidth = radius * 0.32,
        );
      case FinanceGhostShape.bars:
        const heights = [0.3, 0.5, 0.42, 0.66, 0.54, 0.78, 0.6];
        final gap = w / (heights.length * 2 + 1);
        for (var index = 0; index < heights.length; index++) {
          final left = gap + index * gap * 2;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, h * (1 - heights[index]), gap, h),
              const Radius.circular(4),
            ),
            fill,
          );
        }
      case FinanceGhostShape.rows:
        for (var y = 14.0; y < h - 8; y += 40) {
          canvas.drawCircle(Offset(26, y + 12), 12, fill);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(48, y + 4, w * 0.4, 8),
              const Radius.circular(4),
            ),
            fill,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(w - 96, y + 4, 80, 8),
              const Radius.circular(4),
            ),
            fill,
          );
        }
      case FinanceGhostShape.grid:
        const columns = 7;
        final cell = math.min(w / columns, h / 6) - 4;
        for (var row = 0; row < 5; row++) {
          for (var column = 0; column < columns; column++) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  (w - columns * (cell + 4)) / 2 + column * (cell + 4),
                  h * 0.12 + row * (cell + 4),
                  cell,
                  cell,
                ),
                const Radius.circular(5),
              ),
              fill,
            );
          }
        }
      case FinanceGhostShape.tiles:
        final tile = Size(w / 3 - 10, h / 2 - 10);
        for (var index = 0; index < 6; index++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                6 + (index % 3) * (tile.width + 10),
                6 + (index ~/ 3) * (tile.height + 10),
                tile.width,
                tile.height,
              ),
              const Radius.circular(12),
            ),
            fill,
          );
        }
      case FinanceGhostShape.quote:
        final text = TextPainter(
          text: TextSpan(
            text: '“',
            style: TextStyle(
              fontSize: math.min(h * 0.8, 140),
              color: color,
              fontFamily: 'Georgia',
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(w * 0.06, h * 0.02));
    }
  }

  @override
  bool shouldRepaint(_GhostPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

/// A quiet uppercase label over a section of a widget.
class FinanceEyebrow extends StatelessWidget {
  const FinanceEyebrow(
    this.text, {
    super.key,
    required this.color,
    this.trailing,
  });

  final String text;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: financeLabel(
                color,
                size: 10.5,
                weight: FontWeight.w700,
                letterSpacing: 0.9,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      );
}
