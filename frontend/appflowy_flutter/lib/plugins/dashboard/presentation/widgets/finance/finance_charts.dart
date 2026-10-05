import 'dart:math' as math;

import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_kit.dart';
import 'package:flutter/material.dart';

// ------------------------------------------------------------------ geometry

/// A smooth line through [points] that never overshoots them: a monotone
/// cubic, so a curve between two equal values stays flat and a peak is never
/// drawn higher than it was.
Path smoothPath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) {
    return path;
  }
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length < 3) {
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }
  final count = points.length;
  final widths = [
    for (var index = 0; index < count - 1; index++)
      points[index + 1].dx - points[index].dx,
  ];
  final slopes = [
    for (var index = 0; index < count - 1; index++)
      widths[index] == 0
          ? 0.0
          : (points[index + 1].dy - points[index].dy) / widths[index],
  ];
  final tangents = List<double>.filled(count, 0);
  tangents[0] = slopes.first;
  tangents[count - 1] = slopes.last;
  for (var index = 1; index < count - 1; index++) {
    final before = slopes[index - 1];
    final after = slopes[index];
    if (before * after <= 0) {
      tangents[index] = 0;
    } else {
      final a = widths[index - 1];
      final b = widths[index];
      tangents[index] =
          3 * (a + b) / ((2 * b + a) / before + (b + 2 * a) / after);
    }
  }
  for (var index = 0; index < count - 1; index++) {
    final step = widths[index] / 3;
    final from = points[index];
    final to = points[index + 1];
    path.cubicTo(
      from.dx + step,
      from.dy + tangents[index] * step,
      to.dx - step,
      to.dy - tangents[index + 1] * step,
      to.dx,
      to.dy,
    );
  }
  return path;
}

/// [source] drawn as dashes.
Path dashedPath(Path source, {double dash = 5, double gap = 4}) {
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final end = math.min(distance + dash, metric.length);
      result.addPath(metric.extractPath(distance, end), Offset.zero);
      distance = end + gap;
    }
  }
  return result;
}

/// Round numbers for an axis between [low] and [high].
List<double> niceTicks(double low, double high, {int count = 4}) {
  if (!low.isFinite || !high.isFinite) {
    return const [];
  }
  if (high <= low) {
    return [low];
  }
  final raw = (high - low) / count;
  final magnitude =
      math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1.0, 2.0, 2.5, 5.0, 10.0]
          .map((factor) => factor * magnitude)
          .firstWhere((candidate) => candidate >= raw, orElse: () => raw) *
      1.0;
  final first = (low / step).ceil() * step;
  return [
    for (var tick = first; tick <= high + step * 1e-6; tick += step) tick,
  ];
}

TextPainter _label(String text, TextStyle style, {double? maxWidth}) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);

// ----------------------------------------------------------------- sparkline

class FinanceSparkline extends StatelessWidget {
  const FinanceSparkline({
    super.key,
    required this.values,
    required this.color,
    this.baseline,
    this.fill = true,
    this.strokeWidth = 1.6,
    this.dot = true,
  });

  final List<double> values;
  final Color color;

  /// Drawn as a faint dashed line: yesterday's close, say.
  final double? baseline;
  final bool fill;
  final double strokeWidth;
  final bool dot;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _SparkPainter(
            values: values,
            color: color,
            baseline: baseline,
            fill: fill,
            strokeWidth: strokeWidth,
            dot: dot,
          ),
          child: const SizedBox.expand(),
        ),
      );
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.values,
    required this.color,
    required this.baseline,
    required this.fill,
    required this.strokeWidth,
    required this.dot,
  });

  final List<double> values;
  final Color color;
  final double? baseline;
  final bool fill;
  final double strokeWidth;
  final bool dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) {
      return;
    }
    var low = values.reduce(math.min);
    var high = values.reduce(math.max);
    final base = baseline;
    if (base != null) {
      low = math.min(low, base);
      high = math.max(high, base);
    }
    if (high - low < 1e-9) {
      high = low + 1;
    }
    const pad = 3.0;
    final usable = size.height - pad * 2;
    double y(double value) =>
        pad + usable - (value - low) / (high - low) * usable;
    final step = (size.width - (dot ? 4 : 0)) / (values.length - 1);
    final points = [
      for (var index = 0; index < values.length; index++)
        Offset(index * step, y(values[index])),
    ];
    final line = smoothPath(points);
    if (base != null) {
      canvas.drawPath(
        dashedPath(
          Path()
            ..moveTo(0, y(base))
            ..lineTo(size.width, y(base)),
          dash: 2,
          gap: 3,
        ),
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    if (fill) {
      final area = Path.from(line)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.24),
              color.withValues(alpha: 0),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (dot) {
      canvas.drawCircle(
        points.last,
        4.5,
        Paint()..color = color.withValues(alpha: 0.2),
      );
      canvas.drawCircle(points.last, 2.4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.baseline != baseline ||
      oldDelegate.fill != fill ||
      !_sameValues(oldDelegate.values, values);
}

bool _sameValues(List<double> a, List<double> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

// --------------------------------------------------------------- trend chart

/// One line on a trend chart.
@immutable
class TrendLine {
  const TrendLine({
    required this.label,
    required this.times,
    required this.values,
    required this.color,
    this.dashed = false,
    this.fill = false,
  });

  final String label;
  final List<DateTime> times;
  final List<double> values;
  final Color color;
  final bool dashed;
  final bool fill;

  bool get isEmpty => times.isEmpty;

  /// The value at [time]: the last one on or before it.
  double? valueAt(DateTime time) {
    double? found;
    for (var index = 0; index < times.length; index++) {
      if (times[index].isAfter(time)) {
        break;
      }
      found = values[index];
    }
    return found ?? (values.isEmpty ? null : values.first);
  }
}

/// A time series drawn with care: a smooth line with a soft glow, a wash
/// beneath it, an optional second line to compare against with the space
/// between shaded green where the first is ahead and red where it is behind,
/// and a crosshair that follows the pointer with a tooltip.
class FinanceTrendChart extends StatefulWidget {
  const FinanceTrendChart({
    super.key,
    required this.lines,
    required this.palette,
    required this.colors,
    required this.formatValue,
    required this.formatTime,
    this.compare = false,
    this.still = false,
    this.axes = true,
  });

  /// The first line is the one that matters; the second, when [compare] is
  /// set, is what it is measured against.
  final List<TrendLine> lines;
  final DashboardPalette palette;
  final FinanceColors colors;
  final String Function(double value) formatValue;
  final String Function(DateTime time) formatTime;
  final bool compare;
  final bool still;
  final bool axes;

  @override
  State<FinanceTrendChart> createState() => _FinanceTrendChartState();
}

class _FinanceTrendChartState extends State<FinanceTrendChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: widget.still ? 1 : 0,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic);
  Offset? _hover;

  @override
  void initState() {
    super.initState();
    if (!widget.still) {
      _reveal.forward();
    }
  }

  @override
  void didUpdateWidget(FinanceTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.lines.isEmpty ? null : oldWidget.lines.first;
    final after = widget.lines.isEmpty ? null : widget.lines.first;
    // A new range is a new picture and is drawn in again; a refreshed value
    // at the end of the same range is not.
    final redraw = before == null ||
        after == null ||
        before.times.length != after.times.length ||
        (before.times.isNotEmpty &&
            after.times.isNotEmpty &&
            before.times.first != after.times.first);
    if (redraw && !widget.still) {
      _reveal.forward(from: 0);
    } else if (widget.still) {
      _reveal.value = 1;
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // A painter inherits nothing: without the ambient style its labels
        // fall back to the engine's font rather than the app's.
        final labelStyle = DefaultTextStyle.of(context)
            .style
            .merge(financeLabel(widget.palette.textMuted, size: 10));
        final geometry = _TrendGeometry.of(
          widget.lines,
          size,
          axes: widget.axes,
          formatValue: widget.formatValue,
          labelStyle: labelStyle,
        );
        final hover = _hover;
        final index = hover == null ? null : geometry.nearestIndex(hover.dx);
        return MouseRegion(
          onHover: (event) => setState(() => _hover = event.localPosition),
          onExit: (_) => setState(() => _hover = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _curve,
                    builder: (context, _) => CustomPaint(
                      painter: _TrendPainter(
                        geometry: geometry,
                        lines: widget.lines,
                        palette: widget.palette,
                        colors: widget.colors,
                        compare: widget.compare,
                        progress: _curve.value,
                        hoverIndex: index,
                        formatValue: widget.formatValue,
                        formatTime: widget.formatTime,
                        axes: widget.axes,
                        labelStyle: labelStyle,
                      ),
                    ),
                  ),
                ),
              ),
              if (index != null)
                _TrendTooltip(
                  geometry: geometry,
                  index: index,
                  lines: widget.lines,
                  palette: widget.palette,
                  formatValue: widget.formatValue,
                  formatTime: widget.formatTime,
                  size: size,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TrendGeometry {
  _TrendGeometry({
    required this.plot,
    required this.start,
    required this.end,
    required this.low,
    required this.high,
    required this.ticks,
    required this.primaryTimes,
  });

  factory _TrendGeometry.of(
    List<TrendLine> lines,
    Size size, {
    required bool axes,
    required String Function(double value) formatValue,
    required TextStyle labelStyle,
  }) {
    DateTime? start;
    DateTime? end;
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (final line in lines) {
      for (var index = 0; index < line.times.length; index++) {
        final time = line.times[index];
        final value = line.values[index];
        start = start == null || time.isBefore(start) ? time : start;
        end = end == null || time.isAfter(end) ? time : end;
        low = math.min(low, value);
        high = math.max(high, value);
      }
    }
    if (start == null || end == null || !low.isFinite) {
      return _TrendGeometry(
        plot: Offset.zero & size,
        start: DateTime(2000),
        end: DateTime(2000),
        low: 0,
        high: 1,
        ticks: const [],
        primaryTimes: const [],
      );
    }
    if (high - low < 1e-9) {
      final pad = high.abs() * 0.05 + 1;
      low -= pad;
      high += pad;
    } else {
      final pad = (high - low) * 0.12;
      high += pad;
      low -= pad * 0.6;
    }
    final ticks = axes ? niceTicks(low, high) : const <double>[];
    var left = 0.0;
    if (axes) {
      for (final tick in ticks) {
        left = math.max(left, _label(formatValue(tick), labelStyle).width);
      }
      left += 10;
    }
    final plot = Rect.fromLTRB(
      left,
      8,
      size.width - (axes ? 6 : 4),
      size.height - (axes ? 20 : 4),
    );
    return _TrendGeometry(
      plot: plot,
      start: start,
      end: end,
      low: low,
      high: high,
      ticks: ticks,
      primaryTimes: lines.first.times,
    );
  }

  final Rect plot;
  final DateTime start;
  final DateTime end;
  final double low;
  final double high;
  final List<double> ticks;

  /// The first line's times, which the crosshair snaps to.
  final List<DateTime> primaryTimes;

  int get _span => math.max(1, end.difference(start).inMinutes);

  double x(DateTime time) =>
      plot.left + time.difference(start).inMinutes / _span * plot.width;

  double y(double value) =>
      plot.bottom - (value - low) / (high - low) * plot.height;

  DateTime timeAt(double dx) => start.add(
        Duration(
          minutes: ((dx - plot.left) / math.max(1, plot.width) * _span).round(),
        ),
      );

  List<Offset> pointsOf(TrendLine line) => [
        for (var index = 0; index < line.times.length; index++)
          Offset(x(line.times[index]), y(line.values[index])),
      ];

  /// The index of the first line's point nearest [dx].
  int? nearestIndex(double dx) {
    if (primaryTimes.isEmpty) {
      return null;
    }
    var best = 0;
    var distance = double.infinity;
    for (var index = 0; index < primaryTimes.length; index++) {
      final gap = (x(primaryTimes[index]) - dx).abs();
      if (gap < distance) {
        distance = gap;
        best = index;
      }
    }
    return best;
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.geometry,
    required this.lines,
    required this.palette,
    required this.colors,
    required this.compare,
    required this.progress,
    required this.hoverIndex,
    required this.formatValue,
    required this.formatTime,
    required this.axes,
    required this.labelStyle,
  });

  final _TrendGeometry geometry;
  final List<TrendLine> lines;
  final DashboardPalette palette;
  final FinanceColors colors;
  final bool compare;
  final double progress;
  final int? hoverIndex;
  final String Function(double value) formatValue;
  final String Function(DateTime time) formatTime;
  final bool axes;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty || lines.first.times.isEmpty || size.isEmpty) {
      return;
    }
    final plot = geometry.plot;

    // The grid: a few quiet lines at round values.
    final grid = Paint()
      ..color = palette.gridLine.withValues(alpha: palette.isDark ? 0.5 : 0.7)
      ..strokeWidth = 1;
    for (final tick in geometry.ticks) {
      final y = geometry.y(tick);
      if (y < plot.top - 1 || y > plot.bottom + 1) {
        continue;
      }
      canvas.drawPath(
        dashedPath(
          Path()
            ..moveTo(plot.left, y)
            ..lineTo(plot.right, y),
          dash: 3,
        ),
        grid,
      );
    }

    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        0,
        0,
        plot.left + (plot.width + 8) * progress,
        size.height,
      ),
    );

    final primary = lines.first;
    final primaryPoints = geometry.pointsOf(primary);
    final primaryPath = smoothPath(primaryPoints);

    // The difference between the line and what it is compared against.
    if (compare && lines.length > 1 && primaryPoints.length > 1) {
      final other = lines[1];
      final otherPoints = [
        for (final time in primary.times)
          Offset(geometry.x(time), geometry.y(other.valueAt(time) ?? 0)),
      ];
      final otherPath = smoothPath(otherPoints);
      final band = Path.from(primaryPath);
      for (final point in otherPoints.reversed) {
        band.lineTo(point.dx, point.dy);
      }
      band.close();
      final above = Path.from(otherPath)
        ..lineTo(plot.right + 10, -10)
        ..lineTo(plot.left - 10, -10)
        ..close();
      final below = Path.from(otherPath)
        ..lineTo(plot.right + 10, size.height + 10)
        ..lineTo(plot.left - 10, size.height + 10)
        ..close();
      canvas
        ..save()
        ..clipPath(above)
        ..drawPath(
          band,
          Paint()..color = colors.gain.withValues(alpha: 0.14),
        )
        ..restore()
        ..save()
        ..clipPath(below)
        ..drawPath(
          band,
          Paint()..color = colors.loss.withValues(alpha: 0.14),
        )
        ..restore();
    }

    // Washes under filled lines.
    for (final line in lines) {
      if (!line.fill || line.times.length < 2) {
        continue;
      }
      final points = geometry.pointsOf(line);
      final area = smoothPath(points)
        ..lineTo(points.last.dx, plot.bottom)
        ..lineTo(points.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              line.color.withValues(alpha: palette.isDark ? 0.30 : 0.22),
              line.color.withValues(alpha: 0),
            ],
          ).createShader(plot),
      );
    }

    // Secondary lines first, so the primary sits on top.
    for (final line in lines.skip(1)) {
      if (line.times.length < 2) {
        continue;
      }
      final path = smoothPath(geometry.pointsOf(line));
      canvas.drawPath(
        line.dashed ? dashedPath(path) : path,
        Paint()
          ..color = line.color.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }

    if (primaryPoints.length > 1) {
      // A soft glow under the line, then the line itself.
      canvas.drawPath(
        primaryPath,
        Paint()
          ..color = primary.color.withValues(alpha: palette.isDark ? 0.5 : 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        primaryPath,
        Paint()
          ..color = primary.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    // The latest point, once the line has reached it.
    if (progress > 0.98 && primaryPoints.isNotEmpty) {
      final last = primaryPoints.last;
      canvas
        ..drawCircle(
          last,
          8,
          Paint()..color = primary.color.withValues(alpha: 0.18),
        )
        ..drawCircle(last, 4.5, Paint()..color = palette.surface)
        ..drawCircle(last, 3.2, Paint()..color = primary.color);
    }

    if (axes) {
      for (final tick in geometry.ticks) {
        final y = geometry.y(tick);
        if (y < plot.top - 1 || y > plot.bottom + 1) {
          continue;
        }
        final text = _label(formatValue(tick), labelStyle);
        text.paint(
          canvas,
          Offset(plot.left - text.width - 8, y - text.height / 2),
        );
      }
      final times = primary.times;
      final marks = <int>{
        0,
        if (times.length > 4) times.length ~/ 2,
        times.length - 1,
      };
      for (final index in marks) {
        final text = _label(formatTime(times[index]), labelStyle);
        final x = geometry.x(times[index]);
        final left = (x - text.width / 2)
            .clamp(plot.left, math.max(plot.left, plot.right - text.width))
            .toDouble();
        text.paint(canvas, Offset(left, plot.bottom + 6));
      }
    }

    final hover = hoverIndex;
    if (hover != null && hover < primary.times.length) {
      final time = primary.times[hover];
      final x = geometry.x(time);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = palette.textMuted.withValues(alpha: 0.45)
          ..strokeWidth = 1,
      );
      for (final line in lines.reversed) {
        final value = line.valueAt(time);
        if (value == null) {
          continue;
        }
        final point = Offset(x, geometry.y(value));
        canvas
          ..drawCircle(
            point,
            7,
            Paint()..color = line.color.withValues(alpha: 0.2),
          )
          ..drawCircle(point, 4.2, Paint()..color = palette.surface)
          ..drawCircle(point, 3, Paint()..color = line.color);
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.hoverIndex != hoverIndex ||
      oldDelegate.lines != lines ||
      oldDelegate.palette != palette ||
      oldDelegate.compare != compare ||
      oldDelegate.labelStyle != labelStyle;
}

class _TrendTooltip extends StatelessWidget {
  const _TrendTooltip({
    required this.geometry,
    required this.index,
    required this.lines,
    required this.palette,
    required this.formatValue,
    required this.formatTime,
    required this.size,
  });

  final _TrendGeometry geometry;
  final int index;
  final List<TrendLine> lines;
  final DashboardPalette palette;
  final String Function(double value) formatValue;
  final String Function(DateTime time) formatTime;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final primary = lines.first;
    if (index >= primary.times.length) {
      return const SizedBox.shrink();
    }
    final time = primary.times[index];
    final x = geometry.x(time);
    final y = geometry.y(primary.values[index]);
    const width = 168.0;
    final left = x + 14 + width > size.width ? x - 14 - width : x + 14;
    final top = (y - 26).clamp(0.0, math.max(0.0, size.height - 80)).toDouble();
    return Positioned(
      left: left.clamp(0.0, math.max(0.0, size.width - width)).toDouble(),
      top: top,
      width: width,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: palette.border.withValues(alpha: 0.6),
            ),
            boxShadow: palette.cardShadow(raised: true),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatTime(time),
                style: financeLabel(palette.textMuted, size: 10.5),
              ),
              const SizedBox(height: 4),
              for (final line in lines)
                if (line.valueAt(time) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: line.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            line.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: financeLabel(
                              palette.textSecondary,
                              size: 11,
                            ),
                          ),
                        ),
                        Text(
                          formatValue(line.valueAt(time)!),
                          style: financeNumber(palette.textPrimary, size: 11.5),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- donut

@immutable
class DonutSlice {
  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

/// A ring of slices that sweeps in, with a gap between each and the hovered
/// one lifted out of the ring.
class FinanceDonut extends StatefulWidget {
  const FinanceDonut({
    super.key,
    required this.slices,
    required this.palette,
    this.center,
    this.thickness = 0.24,
    this.still = false,
    this.hovered,
    this.onHover,
  });

  final List<DonutSlice> slices;
  final DashboardPalette palette;
  final Widget? center;

  /// Of the radius.
  final double thickness;
  final bool still;
  final int? hovered;
  final ValueChanged<int?>? onHover;

  @override
  State<FinanceDonut> createState() => _FinanceDonutState();
}

class _FinanceDonutState extends State<FinanceDonut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
    value: widget.still ? 1 : 0,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic);
  int? _hovered;

  @override
  void initState() {
    super.initState();
    if (!widget.still) {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  int? _sliceAt(Offset position, Size size) {
    final centre = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final offset = position - centre;
    final distance = offset.distance;
    if (distance > radius || distance < radius * (1 - widget.thickness) - 6) {
      return null;
    }
    var angle = math.atan2(offset.dy, offset.dx) + math.pi / 2;
    if (angle < 0) {
      angle += math.pi * 2;
    }
    final total = widget.slices.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) {
      return null;
    }
    var start = 0.0;
    for (var index = 0; index < widget.slices.length; index++) {
      final sweep = widget.slices[index].value / total * math.pi * 2;
      if (angle >= start && angle < start + sweep) {
        return index;
      }
      start += sweep;
    }
    return null;
  }

  void _setHover(int? index) {
    if (index == _hovered) {
      return;
    }
    setState(() => _hovered = index);
    widget.onHover?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final hovered = widget.hovered ?? _hovered;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final size = Size.square(side);
        return Center(
          child: SizedBox.fromSize(
            size: size,
            child: MouseRegion(
              onHover: (event) =>
                  _setHover(_sliceAt(event.localPosition, size)),
              onExit: (_) => _setHover(null),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _curve,
                      builder: (context, _) => CustomPaint(
                        painter: _DonutPainter(
                          slices: widget.slices,
                          progress: _curve.value,
                          hovered: hovered,
                          thickness: widget.thickness,
                          track: widget.palette.isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : widget.palette.sunken,
                        ),
                      ),
                    ),
                  ),
                  if (widget.center != null)
                    Padding(
                      padding: EdgeInsets.all(side * widget.thickness + 8),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: widget.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.slices,
    required this.progress,
    required this.hovered,
    required this.thickness,
    required this.track,
  });

  final List<DonutSlice> slices;
  final double progress;
  final int? hovered;
  final double thickness;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * thickness;
    final ring = radius - stroke / 2 - 4;
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
      centre,
      ring,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) {
      return;
    }
    final gap = slices.length > 1 ? (3.5 / ring) : 0.0;
    final cap = stroke / 2 / ring;
    var start = -math.pi / 2;
    final limit = -math.pi / 2 + math.pi * 2 * progress;
    for (var index = 0; index < slices.length; index++) {
      final slice = slices[index];
      final full = slice.value / total * math.pi * 2;
      final from = start + gap / 2;
      var sweep = full - gap;
      start += full;
      if (from >= limit || sweep <= 0) {
        continue;
      }
      sweep = math.min(sweep, limit - from);
      final rounded = sweep > cap * 2 + 0.01;
      final isHovered = hovered == index;
      final dim = hovered != null && !isHovered;
      final paint = Paint()
        ..color = slice.color.withValues(alpha: dim ? 0.38 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + (isHovered ? 6 : 0)
        ..strokeCap = rounded ? StrokeCap.round : StrokeCap.butt;
      final drawFrom = rounded ? from + cap : from;
      final drawSweep = rounded ? sweep - cap * 2 : sweep;
      if (isHovered) {
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: ring),
          drawFrom,
          drawSweep,
          false,
          Paint()
            ..color = slice.color.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke + 10
            ..strokeCap = paint.strokeCap
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
      }
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: ring),
        drawFrom,
        drawSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.hovered != hovered ||
      oldDelegate.slices != slices ||
      oldDelegate.track != track;
}

// ------------------------------------------------------------------- treemap

@immutable
class TreemapItem {
  const TreemapItem({
    required this.label,
    required this.value,
    required this.color,
    this.caption = '',
    this.detail = '',
  });

  final String label;

  /// Decides the area.
  final double value;
  final Color color;

  /// A second line: today's move, say.
  final String caption;

  /// What a hover reveals.
  final String detail;
}

/// Rectangles sized by value, laid out to stay as square as possible.
List<Rect> squarify(List<double> values, Rect bounds) {
  final results = List<Rect>.filled(values.length, Rect.zero);
  final total = values.fold<double>(0, (sum, value) => sum + value);
  if (total <= 0 || bounds.isEmpty) {
    return results;
  }
  final scale = bounds.width * bounds.height / total;
  final areas = [for (final value in values) value * scale];
  var rect = bounds;
  var start = 0;

  double worst(int from, int to, double side) {
    var sum = 0.0;
    var largest = 0.0;
    var smallest = double.infinity;
    for (var index = from; index < to; index++) {
      sum += areas[index];
      largest = math.max(largest, areas[index]);
      smallest = math.min(smallest, areas[index]);
    }
    if (sum <= 0 || smallest <= 0) {
      return double.infinity;
    }
    final square = side * side;
    return math.max(
      square * largest / (sum * sum),
      sum * sum / (square * smallest),
    );
  }

  while (start < values.length) {
    final side = math.min(rect.width, rect.height);
    var end = start + 1;
    var current = worst(start, end, side);
    while (end < values.length) {
      final next = worst(start, end + 1, side);
      if (next > current) {
        break;
      }
      current = next;
      end++;
    }
    final rowArea =
        areas.sublist(start, end).fold<double>(0, (sum, area) => sum + area);
    if (rect.width >= rect.height) {
      final width = rect.height <= 0 ? 0.0 : rowArea / rect.height;
      var y = rect.top;
      for (var index = start; index < end; index++) {
        final height = width <= 0 ? 0.0 : areas[index] / width;
        results[index] = Rect.fromLTWH(rect.left, y, width, height);
        y += height;
      }
      rect =
          Rect.fromLTRB(rect.left + width, rect.top, rect.right, rect.bottom);
    } else {
      final height = rect.width <= 0 ? 0.0 : rowArea / rect.width;
      var x = rect.left;
      for (var index = start; index < end; index++) {
        final width = height <= 0 ? 0.0 : areas[index] / height;
        results[index] = Rect.fromLTWH(x, rect.top, width, height);
        x += width;
      }
      rect =
          Rect.fromLTRB(rect.left, rect.top + height, rect.right, rect.bottom);
    }
    start = end;
  }
  return results;
}

/// The colour of a day's move on a heat map: grey for flat, deepening to
/// green or red by three percent either way.
Color heatColor(double? percent, FinanceColors colors) {
  final neutral = colors.isPaper
      ? const Color(0xFFB2A797)
      : (colors.isDark ? const Color(0xFF3A404C) : const Color(0xFF959DAB));
  if (percent == null) {
    return neutral;
  }
  final strength = (percent.abs() / 3).clamp(0.0, 1.0);
  final eased = Curves.easeOut.transform(strength);
  final far = percent >= 0
      ? (colors.isPaper
          ? const Color(0xFF3D8A55)
          : (colors.isDark ? const Color(0xFF0F9D6B) : const Color(0xFF058C5C)))
      : (colors.isPaper
          ? const Color(0xFFB8493A)
          : (colors.isDark
              ? const Color(0xFFD9363E)
              : const Color(0xFFDC2F37)));
  return Color.lerp(neutral, far, 0.25 + 0.75 * eased)!;
}

class FinanceTreemap extends StatelessWidget {
  const FinanceTreemap({
    super.key,
    required this.items,
    required this.palette,
    this.still = false,
    this.onTap,
  });

  final List<TreemapItem> items;
  final DashboardPalette palette;
  final bool still;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Offset.zero & constraints.biggest;
        final order = List<int>.generate(items.length, (index) => index)
          ..sort((a, b) => items[b].value.compareTo(items[a].value));
        final rects = squarify(
          [for (final index in order) math.max(0, items[index].value)],
          bounds,
        );
        return Stack(
          children: [
            for (var position = 0; position < order.length; position++)
              Positioned.fromRect(
                rect: rects[position],
                child: FinanceEntrance(
                  index: position,
                  still: still,
                  offset: 0,
                  child: _TreemapCell(
                    item: items[order[position]],
                    palette: palette,
                    onTap: onTap == null ? null : () => onTap!(order[position]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TreemapCell extends StatelessWidget {
  const _TreemapCell({
    required this.item,
    required this.palette,
    this.onTap,
  });

  final TreemapItem item;
  final DashboardPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FinanceHover(
      onTap: onTap,
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered) {
        final cell = LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final roomy = width > 64 && height > 40;
            final big = width > 120 && height > 70;
            return AnimatedContainer(
              duration: DashboardMetrics.hover,
              curve: DashboardMetrics.curve,
              margin: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(
                      item.color,
                      Colors.white,
                      hovered ? 0.16 : 0.08,
                    )!,
                    item.color,
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: hovered ? 0.55 : 0),
                  width: 1.5,
                ),
                boxShadow: hovered
                    ? [
                        BoxShadow(
                          color: item.color.withValues(alpha: 0.45),
                          blurRadius: 14,
                          spreadRadius: -4,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              padding: EdgeInsets.all(big ? 10 : 5),
              child: !roomy
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisAlignment: big
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      crossAxisAlignment: big
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: financeLabel(
                            Colors.white,
                            size: big ? 13.5 : 11.5,
                            weight: FontWeight.w700,
                          ),
                        ),
                        if (item.caption.isNotEmpty && height > 52)
                          Text(
                            item.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: financeNumber(
                              Colors.white.withValues(alpha: 0.92),
                              size: big ? 13 : 11,
                              weight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
            );
          },
        );
        return item.detail.isEmpty
            ? cell
            : Tooltip(
                message: item.detail,
                waitDuration: const Duration(milliseconds: 250),
                child: cell,
              );
      },
    );
  }
}

// ------------------------------------------------------------- the calendar

/// A month of daily results as tiles that deepen with the size of the day.
class FinanceCalendar extends StatelessWidget {
  const FinanceCalendar({
    super.key,
    required this.month,
    required this.values,
    required this.colors,
    required this.palette,
    required this.formatValue,
    required this.formatDay,
    required this.weekdays,
    this.today,
  });

  /// Any day in the month shown.
  final DateTime month;

  /// Results by local midnight.
  final Map<DateTime, double> values;
  final FinanceColors colors;
  final DashboardPalette palette;
  final String Function(double value) formatValue;
  final String Function(DateTime day) formatDay;

  /// Seven short names, Monday first.
  final List<String> weekdays;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = (first.weekday + 6) % 7;
    final weeks = ((lead + days) / 7).ceil();
    var largest = 0.0;
    for (var day = 1; day <= days; day++) {
      final value = values[DateTime(month.year, month.month, day)];
      if (value != null) {
        largest = math.max(largest, value.abs());
      }
    }
    final now = today;
    return Column(
      children: [
        Row(
          children: [
            for (final name in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    name,
                    maxLines: 1,
                    style: financeLabel(palette.textMuted, size: 10),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Column(
            children: [
              for (var week = 0; week < weeks; week++)
                Expanded(
                  child: Row(
                    children: [
                      for (var weekday = 0; weekday < 7; weekday++)
                        Expanded(
                          child: _dayCell(
                            week * 7 + weekday - lead + 1,
                            days,
                            largest,
                            now,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayCell(int day, int days, double largest, DateTime? now) {
    if (day < 1 || day > days) {
      return const SizedBox.shrink();
    }
    final date = DateTime(month.year, month.month, day);
    final value = values[date];
    final isToday = now != null &&
        now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
    final strength = value == null || largest <= 0
        ? 0.0
        : (value.abs() / largest).clamp(0.0, 1.0);
    final hue = value == null ? palette.textMuted : colors.change(value);
    final fill = value == null
        ? (palette.isDark
            ? Colors.white.withValues(alpha: 0.03)
            : palette.sunken.withValues(alpha: 0.6))
        : hue.withValues(
            alpha: (palette.isDark ? 0.22 : 0.16) + 0.62 * strength,
          );
    final strong = value != null && strength > 0.45;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: value == null
            ? formatDay(date)
            : '${formatDay(date)}\n${formatValue(value)}',
        waitDuration: const Duration(milliseconds: 200),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showValue = value != null &&
                constraints.maxWidth >= 46 &&
                constraints.maxHeight >= 34;
            return AnimatedContainer(
              duration: DashboardMetrics.settle,
              curve: DashboardMetrics.curve,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(7),
                border: isToday
                    ? Border.all(color: palette.accent, width: 1.5)
                    : null,
              ),
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      '$day',
                      style: financeLabel(
                        strong
                            ? Colors.white.withValues(alpha: 0.9)
                            : palette.textMuted,
                        size: 9.5,
                      ),
                    ),
                  ),
                  if (showValue)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatValue(value),
                          style: financeNumber(
                            strong ? Colors.white : hue,
                            size: 10.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- the payoff

@immutable
class PayoffMark {
  const PayoffMark(this.price, this.label, {this.buy = true});

  final double price;
  final String label;
  final bool buy;
}

/// Words a payoff chart writes, translated by whoever draws it.
@immutable
class PayoffLabels {
  const PayoffLabels({
    required this.expiry,
    required this.today,
    required this.spot,
    required this.price,
  });

  final String expiry;
  final String today;
  final String spot;
  final String price;
}

/// A strategy's profit across prices of the underlying: green above zero and
/// red below, the theoretical value today as a dashed line, the spot and the
/// breakevens marked, and a crosshair to read any price.
class FinancePayoffChart extends StatefulWidget {
  const FinancePayoffChart({
    super.key,
    required this.low,
    required this.high,
    required this.expiry,
    required this.colors,
    required this.palette,
    required this.formatMoney,
    required this.formatPrice,
    required this.labels,
    this.today,
    this.spot,
    this.breakevens = const [],
    this.strikes = const [],
    this.compact = false,
    this.still = false,
  });

  final double low;
  final double high;
  final double Function(double price) expiry;
  final double Function(double price)? today;
  final double? spot;
  final List<double> breakevens;
  final List<PayoffMark> strikes;
  final FinanceColors colors;
  final DashboardPalette palette;
  final String Function(double value) formatMoney;
  final String Function(double value) formatPrice;
  final PayoffLabels labels;

  /// A thumbnail: no axes, no labels, no crosshair.
  final bool compact;
  final bool still;

  @override
  State<FinancePayoffChart> createState() => _FinancePayoffChartState();
}

class _FinancePayoffChartState extends State<FinancePayoffChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: widget.still ? 1 : 0,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _reveal, curve: Curves.easeOutBack);
  double? _hoverX;
  _PayoffSamples? _samples;
  Size? _samplesSize;
  FinancePayoffChart? _samplesFor;

  _PayoffSamples _samplesOf(Size size) {
    final cached = _samples;
    if (cached != null &&
        _samplesSize == size &&
        identical(_samplesFor, widget)) {
      return cached;
    }
    _samplesSize = size;
    _samplesFor = widget;
    return _samples = _PayoffSamples.of(widget, size);
  }

  @override
  void initState() {
    super.initState();
    if (!widget.still) {
      _reveal.forward();
    }
  }

  @override
  void didUpdateWidget(FinancePayoffChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.low != widget.low || oldWidget.high != widget.high) &&
        !widget.still) {
      _reveal.forward(from: 0.4);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final samples = _samplesOf(size);
        final hoverX = _hoverX;
        final hoverPrice =
            hoverX == null || widget.compact ? null : samples.priceAt(hoverX);
        final chart = RepaintBoundary(
          child: AnimatedBuilder(
            animation: _curve,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _PayoffPainter(
                samples: samples,
                chart: widget,
                progress: _curve.value,
                hoverPrice: hoverPrice,
                textStyle: DefaultTextStyle.of(context).style,
              ),
            ),
          ),
        );
        if (widget.compact) {
          return chart;
        }
        return MouseRegion(
          onHover: (event) => setState(() => _hoverX = event.localPosition.dx),
          onExit: (_) => setState(() => _hoverX = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: chart),
              if (hoverPrice != null)
                _PayoffTooltip(
                  samples: samples,
                  chart: widget,
                  price: hoverPrice,
                  size: size,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PayoffSamples {
  _PayoffSamples({
    required this.plot,
    required this.prices,
    required this.atExpiry,
    required this.atToday,
    required this.low,
    required this.high,
    required this.bottom,
    required this.top,
  });

  factory _PayoffSamples.of(FinancePayoffChart chart, Size size) {
    final compact = chart.compact;
    final plot = Rect.fromLTRB(
      compact ? 2 : 8,
      compact ? 4 : 26,
      size.width - (compact ? 2 : 8),
      size.height - (compact ? 4 : 30),
    );
    final low = chart.low;
    final high = math.max(chart.high, low + 1);
    const count = 160;
    final prices = <double>{
      for (var index = 0; index <= count; index++)
        low + (high - low) * index / count,
      for (final mark in chart.strikes)
        if (mark.price > low && mark.price < high) mark.price,
      for (final breakeven in chart.breakevens)
        if (breakeven > low && breakeven < high) breakeven,
    }.toList()
      ..sort();
    final atExpiry = [for (final price in prices) chart.expiry(price)];
    final today = chart.today;
    final atToday =
        today == null ? null : [for (final price in prices) today(price)];
    var bottom = 0.0;
    var top = 0.0;
    for (final value in [...atExpiry, ...?atToday]) {
      if (value.isFinite) {
        bottom = math.min(bottom, value);
        top = math.max(top, value);
      }
    }
    final span = math.max(top - bottom, 1.0);
    return _PayoffSamples(
      plot: plot,
      prices: prices,
      atExpiry: atExpiry,
      atToday: atToday,
      low: low,
      high: high,
      bottom: bottom - span * 0.1,
      top: top + span * 0.12,
    );
  }

  final Rect plot;
  final List<double> prices;
  final List<double> atExpiry;
  final List<double>? atToday;
  final double low;
  final double high;
  final double bottom;
  final double top;

  double x(double price) =>
      plot.left + (price - low) / (high - low) * plot.width;

  double y(double value) =>
      plot.bottom - (value - bottom) / (top - bottom) * plot.height;

  double priceAt(double dx) =>
      (low + (dx - plot.left) / math.max(1, plot.width) * (high - low))
          .clamp(low, high)
          .toDouble();
}

class _PayoffPainter extends CustomPainter {
  const _PayoffPainter({
    required this.samples,
    required this.chart,
    required this.progress,
    required this.hoverPrice,
    required this.textStyle,
  });

  final _PayoffSamples samples;
  final FinancePayoffChart chart;
  final double progress;
  final double? hoverPrice;

  /// The ambient style, which carries the app's font to the labels.
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || samples.prices.length < 2) {
      return;
    }
    final colors = chart.colors;
    final palette = chart.palette;
    final plot = samples.plot;
    final zero = samples.y(0);

    double grown(double value) => zero + (samples.y(value) - zero) * progress;

    final points = [
      for (var index = 0; index < samples.prices.length; index++)
        Offset(
          samples.x(samples.prices[index]),
          grown(samples.atExpiry[index]),
        ),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final area = Path.from(line)
      ..lineTo(points.last.dx, zero)
      ..lineTo(points.first.dx, zero)
      ..close();

    // Profit above the line, loss below, each fading towards zero.
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, 0, size.width, zero))
      ..drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.gain.withValues(alpha: palette.isDark ? 0.42 : 0.30),
              colors.gain.withValues(alpha: 0.04),
            ],
          ).createShader(Rect.fromLTRB(0, plot.top, size.width, zero)),
      )
      ..restore()
      ..save()
      ..clipRect(Rect.fromLTRB(0, zero, size.width, size.height))
      ..drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.loss.withValues(alpha: 0.04),
              colors.loss.withValues(alpha: palette.isDark ? 0.42 : 0.30),
            ],
          ).createShader(Rect.fromLTRB(0, zero, size.width, plot.bottom)),
      )
      ..restore();

    // The zero line.
    canvas.drawLine(
      Offset(plot.left, zero),
      Offset(plot.right, zero),
      Paint()
        ..color = palette.textMuted.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );

    // The strikes, as ticks along the bottom.
    if (!chart.compact) {
      for (final mark in chart.strikes) {
        if (mark.price < samples.low || mark.price > samples.high) {
          continue;
        }
        final x = samples.x(mark.price);
        canvas.drawLine(
          Offset(x, plot.bottom + 2),
          Offset(x, plot.bottom + 7),
          Paint()
            ..color =
                (mark.buy ? colors.gain : colors.loss).withValues(alpha: 0.8)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        final text = _label(
          chart.formatPrice(mark.price),
          textStyle.merge(financeLabel(palette.textMuted, size: 9.5)),
        );
        text.paint(canvas, Offset(x - text.width / 2, plot.bottom + 10));
      }
    }

    // The theoretical value today.
    final today = samples.atToday;
    if (today != null) {
      final todayPoints = [
        for (var index = 0; index < samples.prices.length; index++)
          Offset(samples.x(samples.prices[index]), grown(today[index])),
      ];
      canvas.drawPath(
        dashedPath(smoothPath(todayPoints)),
        Paint()
          ..color = _todayColor(palette)
          ..style = PaintingStyle.stroke
          ..strokeWidth = chart.compact ? 1.2 : 1.6,
      );
    }

    // The payoff at expiry, green above zero and red below.
    final fraction = ((zero - 0) / size.height).clamp(0.0, 1.0);
    canvas.drawPath(
      line,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.gain, colors.gain, colors.loss, colors.loss],
          stops: [0, fraction, fraction, 1],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = chart.compact ? 1.8 : 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Breakevens on the zero line.
    for (final breakeven in chart.breakevens) {
      if (breakeven < samples.low || breakeven > samples.high) {
        continue;
      }
      final point = Offset(samples.x(breakeven), zero);
      canvas
        ..drawCircle(
          point,
          chart.compact ? 3 : 4.5,
          Paint()..color = palette.surface,
        )
        ..drawCircle(
          point,
          chart.compact ? 3 : 4.5,
          Paint()
            ..color = palette.textSecondary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      if (!chart.compact) {
        final text = _label(
          chart.formatPrice(breakeven),
          textStyle.merge(
            financeLabel(
              palette.textSecondary,
              size: 9.5,
              weight: FontWeight.w600,
            ),
          ),
        );
        final below = zero + 8 + text.height < plot.bottom;
        // The line crosses zero here, so beside the point, on the side the
        // line has already left, is the one place the label is never struck
        // through.
        final nudge = (samples.high - samples.low) / 400;
        final rising =
            chart.expiry(breakeven + nudge) >= chart.expiry(breakeven - nudge);
        final toRight = rising == below;
        final left = (toRight ? point.dx + 7 : point.dx - 7 - text.width)
            .clamp(
              plot.left,
              math.max(plot.left, plot.right - text.width),
            )
            .toDouble();
        text.paint(
          canvas,
          Offset(left, below ? zero + 5 : zero - 5 - text.height),
        );
      }
    }

    // The spot.
    final spot = chart.spot;
    if (spot != null && spot >= samples.low && spot <= samples.high) {
      final x = samples.x(spot);
      canvas.drawPath(
        dashedPath(
          Path()
            ..moveTo(x, plot.top - (chart.compact ? 0 : 6))
            ..lineTo(x, plot.bottom),
          dash: 3,
          gap: 3,
        ),
        Paint()
          ..color = palette.accent.withValues(alpha: 0.8)
          ..strokeWidth = 1.2,
      );
      if (!chart.compact) {
        final text = _label(
          '${chart.labels.spot} ${chart.formatPrice(spot)}',
          textStyle.merge(
            financeLabel(palette.onAccent, size: 10, weight: FontWeight.w600),
          ),
        );
        final pill = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(
              x.clamp(text.width / 2 + 10, size.width - text.width / 2 - 10),
              plot.top - 14,
            ),
            width: text.width + 14,
            height: text.height + 6,
          ),
          const Radius.circular(999),
        );
        canvas.drawRRect(pill, Paint()..color = palette.accent);
        text.paint(
          canvas,
          Offset(pill.left + 7, pill.top + 3),
        );
      } else {
        canvas.drawCircle(
          Offset(x, grown(chart.expiry(spot))),
          2.8,
          Paint()..color = palette.accent,
        );
      }
    }

    // Axis values at the top, zero and the bottom.
    if (!chart.compact) {
      final style = textStyle.merge(financeLabel(palette.textMuted, size: 9.5));
      for (final value in [samples.top, samples.bottom]) {
        final text = _label(chart.formatMoney(value), style);
        final y = samples.y(value);
        text.paint(
          canvas,
          Offset(plot.left + 2, value > 0 ? y + 2 : y - text.height - 2),
        );
      }
    }

    final price = hoverPrice;
    if (price != null) {
      final x = samples.x(price);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = palette.textMuted.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      final value = chart.expiry(price);
      final point = Offset(x, samples.y(value));
      final hue = colors.change(value);
      canvas
        ..drawCircle(point, 7, Paint()..color = hue.withValues(alpha: 0.2))
        ..drawCircle(point, 4, Paint()..color = palette.surface)
        ..drawCircle(point, 3, Paint()..color = hue);
      final todayFunction = chart.today;
      if (todayFunction != null) {
        canvas.drawCircle(
          Offset(x, samples.y(todayFunction(price))),
          3,
          Paint()..color = _todayColor(palette),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PayoffPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.hoverPrice != hoverPrice ||
      oldDelegate.samples != samples ||
      oldDelegate.textStyle != textStyle;
}

Color _todayColor(DashboardPalette palette) => palette.isPaper
    ? const Color(0xFF7A62A8)
    : (palette.isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C5CF5));

class _PayoffTooltip extends StatelessWidget {
  const _PayoffTooltip({
    required this.samples,
    required this.chart,
    required this.price,
    required this.size,
  });

  final _PayoffSamples samples;
  final FinancePayoffChart chart;
  final double price;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final palette = chart.palette;
    final colors = chart.colors;
    final expiry = chart.expiry(price);
    final today = chart.today?.call(price);
    final x = samples.x(price);
    const width = 176.0;
    final left = x + 14 + width > size.width ? x - 14 - width : x + 14;
    Widget row(String label, double value, Color dot) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: financeLabel(palette.textSecondary, size: 11),
                ),
              ),
              Text(
                chart.formatMoney(value),
                style: financeNumber(colors.change(value), size: 11.5),
              ),
            ],
          ),
        );
    return Positioned(
      left: left.clamp(0.0, math.max(0.0, size.width - width)),
      top: samples.plot.top + 4,
      width: width,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border.withValues(alpha: 0.6)),
            boxShadow: palette.cardShadow(raised: true),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${chart.labels.price} ${chart.formatPrice(price)}',
                style: financeLabel(palette.textMuted, size: 10.5),
              ),
              row(chart.labels.expiry, expiry, colors.change(expiry)),
              if (today != null)
                row(chart.labels.today, today, _todayColor(palette)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the rings

/// A ring that fills to [value], with a gradient along its sweep.
class FinanceRing extends StatelessWidget {
  const FinanceRing({
    super.key,
    required this.value,
    required this.colors,
    required this.track,
    this.thickness = 8,
    this.arc = math.pi * 2,
    this.child,
    this.still = false,
  });

  /// Between 0 and 1.
  final double value;

  /// Painted along the sweep, start to end.
  final List<Color> colors;
  final Color track;
  final double thickness;

  /// How much of a circle the ring covers: all of it, or a gauge's 270°.
  final double arc;
  final Widget? child;
  final bool still;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
      duration: still ? Duration.zero : const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => CustomPaint(
        painter: _RingPainter(
          value: progress,
          colors: colors,
          track: track,
          thickness: thickness,
          arc: arc,
        ),
        child: child,
      ),
      child: child == null ? null : Center(child: child),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.colors,
    required this.track,
    required this.thickness,
    required this.arc,
  });

  final double value;
  final List<Color> colors;
  final Color track;
  final double thickness;
  final double arc;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 - thickness / 2 - 1;
    if (radius <= 0) {
      return;
    }
    final centre = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final start = -math.pi / 2 - arc / 2 + (arc >= math.pi * 2 ? arc / 2 : 0);
    canvas.drawArc(
      rect,
      start,
      arc,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round,
    );
    if (value <= 0) {
      return;
    }
    final sweep = arc * value;
    final shader = SweepGradient(
      endAngle: math.max(sweep, 0.01),
      colors: colors.length == 1 ? [colors.first, colors.first] : colors,
      transform: GradientRotation(start),
    ).createShader(rect);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.track != track ||
      oldDelegate.thickness != thickness;
}

// ---------------------------------------------------------- the stacked bar

@immutable
class StackSegment {
  const StackSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

/// Shares of a whole as one rounded bar that grows into place.
class FinanceStackedBar extends StatelessWidget {
  const FinanceStackedBar({
    super.key,
    required this.segments,
    required this.palette,
    this.height = 10,
    this.still = false,
    this.describe,
  });

  final List<StackSegment> segments;
  final DashboardPalette palette;
  final double height;
  final bool still;

  /// What hovering a segment says.
  final String Function(StackSegment segment, double share)? describe;

  @override
  Widget build(BuildContext context) {
    final total =
        segments.fold<double>(0, (sum, segment) => sum + segment.value);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (total <= 0) {
              return Container(color: palette.sunken);
            }
            final width = constraints.maxWidth;
            final gaps = math.max(0, segments.length - 1) * 2.0;
            final usable = math.max(0.0, width - gaps);
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: still ? 1 : 0, end: 1),
              duration:
                  still ? Duration.zero : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, grow, _) => Row(
                children: [
                  for (var index = 0; index < segments.length; index++) ...[
                    if (index > 0) const SizedBox(width: 2),
                    _segment(segments[index], usable * grow, total),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _segment(StackSegment segment, double usable, double total) {
    final share = segment.value / total;
    final bar = AnimatedContainer(
      duration: DashboardMetrics.settle,
      curve: DashboardMetrics.curve,
      width: math.max(0, usable * share),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(segment.color, Colors.white, 0.12)!,
            segment.color,
          ],
        ),
      ),
    );
    final describe = this.describe;
    return describe == null
        ? bar
        : Tooltip(
            message: describe(segment, share),
            waitDuration: const Duration(milliseconds: 200),
            child: bar,
          );
  }
}

/// Paints [text] in [style] with a soft gradient — for a hero figure.
class FinanceGradientText extends StatelessWidget {
  const FinanceGradientText(
    this.text, {
    super.key,
    required this.style,
    required this.colors,
  });

  final String text;
  final TextStyle style;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: colors,
        ).createShader(bounds),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );
}
