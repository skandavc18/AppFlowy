import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_number.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What the pointer is over, so the chart can answer it.
@immutable
class ChartHit {
  const ChartHit({
    required this.seriesIndex,
    required this.pointIndex,
    required this.rect,
    required this.anchor,
  });

  final int seriesIndex;
  final int pointIndex;

  /// The area that answers the pointer.
  final Rect rect;

  /// Where a tooltip should point, which is the top of a bar or the centre of
  /// a dot rather than the middle of its hit area.
  final Offset anchor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartHit &&
          other.seriesIndex == seriesIndex &&
          other.pointIndex == pointIndex;

  @override
  int get hashCode => Object.hash(seriesIndex, pointIndex);
}

/// How far the chart has been zoomed into its horizontal axis, and where.
@immutable
class ChartViewport {
  const ChartViewport({this.scale = 1, this.offset = 0});

  static const identity = ChartViewport();

  /// 1 shows everything; 4 shows a quarter of it.
  final double scale;

  /// The left edge, in fractions of the whole run.
  final double offset;

  bool get isIdentity => scale <= 1.0001;

  double get end => offset + 1 / scale;

  ChartViewport zoomed(double factor, double focus) {
    final next = (scale * factor).clamp(1.0, 40.0);
    if (next <= 1.0001) {
      return identity;
    }
    // Keep whatever sits under the pointer exactly where it is.
    final anchor = offset + focus / scale;
    return ChartViewport(scale: next, offset: anchor - focus / next).clamped();
  }

  ChartViewport panned(double fraction) =>
      ChartViewport(scale: scale, offset: offset + fraction).clamped();

  ChartViewport clamped() {
    final span = 1 / scale;
    return ChartViewport(
      scale: scale,
      offset: offset.clamp(0.0, (1 - span).clamp(0.0, 1.0)),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartViewport && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);
}

/// One step on an axis.
@immutable
class _Tick {
  const _Tick(this.value, this.label);
  final double value;
  final String label;
}

/// Draws a chart, and reports what each part of it occupies so the widget
/// above can answer the pointer without the painter knowing about gestures.
class ChartPainter extends CustomPainter {
  ChartPainter({
    required this.data,
    required this.spec,
    required this.palette,
    required this.colors,
    required this.hidden,
    required this.highlight,
    required this.focusedSeries,
    required this.reveal,
    required this.emphasis,
    required this.viewport,
    required this.crosshair,
    required this.hits,
  }) : super(repaint: Listenable.merge([reveal, emphasis]));

  final ChartData data;
  final ChartSpec spec;
  final ChartPalette palette;
  final ChartColors colors;
  final Set<int> hidden;
  final ChartHit? highlight;

  /// The series the legend is being hovered over, which the rest fade behind.
  final int? focusedSeries;

  final Animation<double> reveal;

  /// How far into the hover transition the chart is.
  final Animation<double> emphasis;

  final ChartViewport viewport;
  final Offset? crosshair;

  /// Filled while painting; read by hit testing.
  final List<ChartHit> hits;

  double get _t => reveal.value;

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    if (data.isEmpty || size.width < 60 || size.height < 60) {
      return;
    }
    if (spec.type.isCircular) {
      _paintCircular(canvas, size);
      return;
    }
    _paintCartesian(canvas, size);
  }

  List<int> get _visible => [
        for (var index = 0; index < data.series.length; index++)
          if (!hidden.contains(index)) index,
      ];

  /// How strongly a series is drawn, given what is being read.
  double _weight(int seriesIndex) {
    final focus = focusedSeries ?? highlight?.seriesIndex;
    if (focus == null || focus == seriesIndex) {
      return 1;
    }
    return 1 - (1 - ChartMetrics.mutedOpacity) * emphasis.value;
  }

  Color _colorFor(int seriesIndex, {int? sliceIndex}) {
    final base = sliceIndex != null
        ? colors.at(sliceIndex, _sliceName(sliceIndex))
        : colors.at(seriesIndex, data.series[seriesIndex].name);
    final weight = _weight(seriesIndex);
    return weight >= 1 ? base : base.withValues(alpha: base.a * weight);
  }

  String _sliceName(int index) {
    final points = data.series.isEmpty ? const [] : data.series.first.points;
    return index < points.length ? points[index].label as String : '';
  }

  // ------------------------------------------------------------------ layout

  /// The plot area, after the axes have taken what they need.
  ({Rect plot, List<_Tick> value, List<_Tick> across}) _frame(Size size) {
    final horizontal = spec.type.isHorizontal;
    final valueTicks = _scaleTicks;
    final acrossTicks = _acrossScaleTicks;

    // The measured axis sits along whichever edge carries the numbers.
    final valueLabels = horizontal ? acrossTicks : valueTicks;
    final gutter = _widestLabel(valueLabels) + ChartMetrics.axisGap;
    final bottom = ChartMetrics.axisLabelSize + ChartMetrics.axisGap + 4;
    // A short chart cannot afford the full headroom and still say anything.
    final headroom = math.min(ChartMetrics.plotHeadroom, size.height * 0.12);

    return (
      plot: Rect.fromLTRB(
        gutter,
        headroom,
        size.width - ChartMetrics.plotSideroom,
        size.height - bottom,
      ),
      value: valueTicks,
      across: acrossTicks,
    );
  }

  List<_Tick> _valueTicks() => _niceTicks(data.minimum, data.maximum);

  /// The steps along the axis that runs across the plot.
  List<_Tick> _acrossTicks() {
    if (!data.measuresX) {
      return const [];
    }
    return _niceTicks(data.xMinimum, data.xMaximum);
  }

  /// Steps that cover the run and a little beyond, so the highest point has a
  /// gridline above it rather than sitting on the edge of the plot.
  List<_Tick> _niceTicks(double low, double high) {
    if (!low.isFinite || !high.isFinite || high <= low) {
      return [_Tick(low, formatChartNumber(low))];
    }
    final room = (high - low) * 0.08;
    final to = high + room;
    // A run that rests on zero keeps its baseline there.
    final from = low < 0 ? low - room : low;

    final rough = (to - from) / 5;
    final magnitude =
        math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final scaled = rough / magnitude;
    final step = (scaled >= 5
            ? 10
            : scaled >= 2.5
                ? 5
                : scaled >= 2
                    ? 2.5
                    : scaled >= 1
                        ? 2
                        : 1) *
        magnitude;

    final ticks = <_Tick>[];
    // Run to the first step at or past the padded top, so the last gridline
    // always sits above the data rather than through it.
    final last = (to / step).ceil() * step;
    var value = (from / step).floor() * step;
    while (value <= last + step * 0.001 && ticks.length < 14) {
      // Steps land on ugly values after division, so settle them first.
      final settled = (value / step).round() * step;
      ticks.add(_Tick(settled, formatChartNumber(settled)));
      value += step;
    }
    return ticks.isEmpty ? [_Tick(low, formatChartNumber(low))] : ticks;
  }

  double _widestLabel(List<_Tick> ticks) {
    var widest = 0.0;
    for (final tick in ticks) {
      final painter =
          _text(tick.label, ChartMetrics.axisLabelSize, palette.label);
      widest = math.max(widest, painter.width);
    }
    return math.max(widest, 16);
  }

  // --------------------------------------------------------------- cartesian

  void _paintCartesian(Canvas canvas, Size size) {
    final visible = _visible;
    if (visible.isEmpty) {
      return;
    }
    final frame = _frame(size);
    final plot = frame.plot;
    if (plot.width < 24 || plot.height < 24) {
      return;
    }

    _paintGrid(canvas, plot, frame.value, frame.across);

    canvas.save();
    // A dot sitting on a gridline still owns its ring, so the clip gives it
    // room rather than shaving it flat.
    canvas.clipRect(plot.inflate(9));
    if (data.measuresX) {
      _paintMeasured(canvas, plot, visible);
    } else if (spec.type.drawsBars) {
      _paintBars(canvas, plot, visible);
    } else {
      _paintBands(canvas, plot, visible);
    }
    canvas.restore();

    _paintAxisLabels(canvas, plot, frame.value, frame.across);
    _paintCrosshair(canvas, plot);
  }

  // The horizontal position of a slot, honouring the zoom.
  double _slotSpan(Rect plot, int count) =>
      (spec.type.isHorizontal ? plot.height : plot.width) *
      viewport.scale /
      math.max(count, 1);

  double _slotStart(Rect plot) {
    final length = spec.type.isHorizontal ? plot.height : plot.width;
    final origin = spec.type.isHorizontal ? plot.top : plot.left;
    return origin - viewport.offset * length * viewport.scale;
  }

  /// The run the plot actually covers, which is the gridlines rather than the
  /// raw numbers — so the tallest bar or point stops short of the edge.
  late final List<_Tick> _scaleTicks = _valueTicks();
  late final double _scaleLow = _scaleTicks.first.value;
  late final double _scaleSpan = _scaleTicks.last.value - _scaleLow == 0
      ? 1
      : _scaleTicks.last.value - _scaleLow;

  late final List<_Tick> _acrossScaleTicks = _acrossTicks();
  late final double _acrossLow =
      _acrossScaleTicks.isEmpty ? data.xMinimum : _acrossScaleTicks.first.value;
  late final double _acrossSpan = _acrossScaleTicks.isEmpty ||
          _acrossScaleTicks.last.value - _acrossLow == 0
      ? data.xSpan
      : _acrossScaleTicks.last.value - _acrossLow;

  /// Where a value sits along the measured axis.
  double _measure(Rect plot, double value) {
    final fraction = (value - _scaleLow) / _scaleSpan;
    return spec.type.isHorizontal
        ? plot.left + fraction * plot.width
        : plot.bottom - fraction * plot.height;
  }

  double get _zeroFraction => ((0 - _scaleLow) / _scaleSpan).clamp(0.0, 1.0);

  double _zeroLine(Rect plot) => spec.type.isHorizontal
      ? plot.left + _zeroFraction * plot.width
      : plot.bottom - _zeroFraction * plot.height;

  // ------------------------------------------------------------------- grid

  void _paintGrid(
    Canvas canvas,
    Rect plot,
    List<_Tick> value,
    List<_Tick> across,
  ) {
    if (!spec.showGrid) {
      return;
    }
    final paint = Paint()
      ..color = palette.grid
      ..strokeWidth = ChartMetrics.gridWidth
      ..isAntiAlias = true;

    final horizontal = spec.type.isHorizontal;
    for (final tick in value) {
      final at = _measure(plot, tick.value);
      canvas.drawLine(
        horizontal ? Offset(at, plot.top) : Offset(plot.left, at),
        horizontal ? Offset(at, plot.bottom) : Offset(plot.right, at),
        paint,
      );
    }

    if (data.measuresX && across.isNotEmpty) {
      final light = Paint()
        ..color = palette.grid.withValues(alpha: palette.grid.a * 0.6)
        ..strokeWidth = ChartMetrics.gridWidth;
      for (final tick in across) {
        final at = _acrossPosition(plot, tick.value);
        if (at < plot.left - 1 || at > plot.right + 1) {
          continue;
        }
        canvas.drawLine(
          Offset(at, plot.top),
          Offset(at, plot.bottom),
          light,
        );
      }
    }

    // The baseline earns a firmer line than the rest.
    final zero = _zeroLine(plot);
    canvas.drawLine(
      horizontal ? Offset(zero, plot.top) : Offset(plot.left, zero),
      horizontal ? Offset(zero, plot.bottom) : Offset(plot.right, zero),
      Paint()
        ..color = palette.axis
        ..strokeWidth = 1,
    );
  }

  double _acrossPosition(Rect plot, double x) {
    final fraction = (x - _acrossLow) / _acrossSpan;
    final zoomed = (fraction - viewport.offset) * viewport.scale;
    return plot.left + zoomed * plot.width;
  }

  void _paintAxisLabels(
    Canvas canvas,
    Rect plot,
    List<_Tick> value,
    List<_Tick> across,
  ) {
    final horizontal = spec.type.isHorizontal;

    // The measured axis.
    for (final tick in value) {
      final at = _measure(plot, tick.value);
      final painter =
          _text(tick.label, ChartMetrics.axisLabelSize, palette.label);
      if (horizontal) {
        painter.paint(
          canvas,
          Offset(at - painter.width / 2, plot.bottom + ChartMetrics.axisGap),
        );
      } else {
        painter.paint(
          canvas,
          Offset(
            plot.left - ChartMetrics.axisGap - painter.width,
            at - painter.height / 2,
          ),
        );
      }
    }

    if (data.measuresX) {
      for (final tick in across) {
        final at = _acrossPosition(plot, tick.value);
        final painter =
            _text(tick.label, ChartMetrics.axisLabelSize, palette.label);
        if (at - painter.width / 2 < plot.left - 4 ||
            at + painter.width / 2 > plot.right + 4) {
          continue;
        }
        painter.paint(
          canvas,
          Offset(at - painter.width / 2, plot.bottom + ChartMetrics.axisGap),
        );
      }
      return;
    }

    _paintCategoryLabels(canvas, plot);
  }

  void _paintCategoryLabels(Canvas canvas, Rect plot) {
    final count = data.categories.length;
    if (count == 0) {
      return;
    }
    final horizontal = spec.type.isHorizontal;
    final span = _slotSpan(plot, count);
    final start = _slotStart(plot);

    // Only draw as many labels as will fit without touching.
    final room = horizontal ? span : span - 6;
    var every = 1;
    if (!horizontal) {
      var widest = 0.0;
      for (final category in data.categories) {
        widest = math.max(
          widest,
          _text(category, ChartMetrics.axisLabelSize, palette.label).width,
        );
      }
      every = room <= 0 ? count : math.max(1, (widest / room).ceil());
    } else {
      every = room < 14 ? math.max(1, (14 / room).ceil()) : 1;
    }

    for (var index = 0; index < count; index++) {
      if (index % every != 0) {
        continue;
      }
      final centre = start + span * (index + 0.5);
      final focused = highlight?.pointIndex == index;
      final painter = _text(
        data.categories[index],
        ChartMetrics.axisLabelSize,
        focused ? palette.strongLabel : palette.label,
        weight: focused ? FontWeight.w600 : FontWeight.w400,
        maxWidth: horizontal ? plot.left - ChartMetrics.axisGap : span,
      );
      if (horizontal) {
        if (centre < plot.top - 8 || centre > plot.bottom + 8) {
          continue;
        }
        painter.paint(
          canvas,
          Offset(
            plot.left - ChartMetrics.axisGap - painter.width,
            centre - painter.height / 2,
          ),
        );
      } else {
        if (centre < plot.left - span || centre > plot.right + span) {
          continue;
        }
        painter.paint(
          canvas,
          Offset(
            centre - painter.width / 2,
            plot.bottom + ChartMetrics.axisGap,
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------------- bars

  void _paintBars(Canvas canvas, Rect plot, List<int> visible) {
    final count = data.categories.length;
    if (count == 0) {
      return;
    }
    final horizontal = spec.type.isHorizontal;
    final stacked = spec.type.isStacked;
    final span = _slotSpan(plot, count);
    final start = _slotStart(plot);
    final lanes = stacked ? 1 : visible.length;

    // A bar has a size it wants; a wide chart with two categories should not
    // become two slabs.
    final group = math.min(
      span * ChartMetrics.barGroupFill,
      ChartMetrics.maximumBarWidth * lanes +
          ChartMetrics.barInnerGap * (lanes - 1),
    );
    final thickness = math.max(
      ChartMetrics.minimumBarWidth,
      (group - ChartMetrics.barInnerGap * (lanes - 1)) / lanes,
    );
    final zero = _zeroLine(plot);
    final radius = math.min(ChartMetrics.barRadius, thickness / 2.4);

    for (var lane = 0; lane < visible.length; lane++) {
      final seriesIndex = visible[lane];
      final series = data.series[seriesIndex];
      final color = _colorFor(seriesIndex);

      for (var index = 0;
          index < count && index < series.points.length;
          index++) {
        final point = series.points[index];
        // Each bar starts a moment after the one before it.
        final progress = _stagger(index, count);
        if (progress <= 0) {
          continue;
        }

        double from = zero;
        var value = point.value;
        if (stacked) {
          var below = 0.0;
          for (final other in visible.take(lane)) {
            below += data.series[other].points[index].value;
          }
          from = _measure(plot, below);
          value = below + point.value;
        }
        final to = _measure(plot, stacked ? value : point.value);
        final grown = from + (to - from) * progress;

        final centre = start +
            span * (index + 0.5) +
            (stacked
                ? 0
                : (lane - (lanes - 1) / 2) *
                    (thickness + ChartMetrics.barInnerGap));

        final rect = horizontal
            ? Rect.fromLTRB(
                math.min(from, grown),
                centre - thickness / 2,
                math.max(from, grown),
                centre + thickness / 2,
              )
            : Rect.fromLTRB(
                centre - thickness / 2,
                math.min(from, grown),
                centre + thickness / 2,
                math.max(from, grown),
              );

        final hovered = highlight?.seriesIndex == seriesIndex &&
            highlight?.pointIndex == index;
        _drawBar(canvas, rect, color, radius, horizontal, point.value, hovered);

        hits.add(
          ChartHit(
            seriesIndex: seriesIndex,
            pointIndex: index,
            rect: horizontal
                ? Rect.fromLTRB(
                    plot.left,
                    centre - span / 2,
                    plot.right,
                    centre + span / 2,
                  )
                : Rect.fromLTRB(
                    centre - span / 2,
                    plot.top,
                    centre + span / 2,
                    plot.bottom,
                  ),
            anchor: horizontal
                ? Offset(rect.right, rect.center.dy)
                : Offset(rect.center.dx, rect.top),
          ),
        );

        if (spec.showValues && progress > 0.9) {
          _paintValueLabel(canvas, rect, point.value, horizontal);
        }
      }
    }
  }

  void _drawBar(
    Canvas canvas,
    Rect rect,
    Color color,
    double radius,
    bool horizontal,
    double value,
    bool hovered,
  ) {
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }
    // Only the growing end is rounded, so a bar reads as rising from its base.
    final positive = value >= 0;
    final corner = Radius.circular(radius);
    final shape = horizontal
        ? RRect.fromRectAndCorners(
            rect,
            topRight: positive ? corner : Radius.zero,
            bottomRight: positive ? corner : Radius.zero,
            topLeft: positive ? Radius.zero : corner,
            bottomLeft: positive ? Radius.zero : corner,
          )
        : RRect.fromRectAndCorners(
            rect,
            topLeft: positive ? corner : Radius.zero,
            topRight: positive ? corner : Radius.zero,
            bottomLeft: positive ? Radius.zero : corner,
            bottomRight: positive ? Radius.zero : corner,
          );

    final lift = hovered ? emphasis.value : 0.0;
    final fill = Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        horizontal ? rect.centerLeft : rect.bottomCenter,
        horizontal ? rect.centerRight : rect.topCenter,
        [
          Color.lerp(color, palette.background, 0.16)!,
          Color.lerp(color, Colors.white, lift * 0.14) ?? color,
        ],
      );
    canvas.drawRRect(shape, fill);

    if (lift > 0.01) {
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: color.a * lift * 0.9),
      );
    }
  }

  void _paintValueLabel(
    Canvas canvas,
    Rect rect,
    double value,
    bool horizontal,
  ) {
    final painter = _text(
      formatChartNumber(value),
      ChartMetrics.axisLabelSize - 0.5,
      palette.strongLabel,
      weight: FontWeight.w600,
    );
    if (horizontal) {
      final outside = painter.width + 8 > rect.width;
      painter.paint(
        canvas,
        Offset(
          outside ? rect.right + 6 : rect.right - painter.width - 6,
          rect.center.dy - painter.height / 2,
        ),
      );
    } else {
      painter.paint(
        canvas,
        Offset(
          rect.center.dx - painter.width / 2,
          rect.top - painter.height - 5,
        ),
      );
    }
  }

  /// How far along a shape's own entrance is, so a chart draws left to right.
  double _stagger(int index, int count) {
    if (count <= 1) {
      return _t;
    }
    const overlap = 0.55;
    final step = (1 - overlap) / count;
    final begin = step * index;
    return ((_t - begin) / overlap).clamp(0.0, 1.0);
  }

  // ------------------------------------------------- lines and areas by band

  void _paintBands(Canvas canvas, Rect plot, List<int> visible) {
    final count = data.categories.length;
    if (count == 0) {
      return;
    }
    final span = _slotSpan(plot, count);
    final start = _slotStart(plot);
    Offset at(int seriesIndex, int index, double stackBelow) {
      final value = data.series[seriesIndex].points[index].value + stackBelow;
      return Offset(start + span * (index + 0.5), _measure(plot, value));
    }

    final below = List<double>.filled(count, 0);
    for (final seriesIndex in visible) {
      final series = data.series[seriesIndex];
      final points = <Offset>[];
      final baseline = <Offset>[];
      for (var index = 0;
          index < count && index < series.points.length;
          index++) {
        final stack = spec.type.isStacked ? below[index] : 0.0;
        points.add(at(seriesIndex, index, stack));
        baseline.add(
          Offset(
            start + span * (index + 0.5),
            spec.type.isStacked ? _measure(plot, stack) : _zeroLine(plot),
          ),
        );
      }
      if (spec.type.isStacked) {
        for (var index = 0;
            index < count && index < series.points.length;
            index++) {
          below[index] += series.points[index].value;
        }
      }
      _drawSeriesPath(canvas, plot, seriesIndex, points, baseline);
    }
  }

  void _paintMeasured(Canvas canvas, Rect plot, List<int> visible) {
    for (final seriesIndex in visible) {
      final series = data.series[seriesIndex];
      final points = <Offset>[];
      final baseline = <Offset>[];
      for (final point in series.points) {
        final x = _acrossPosition(plot, point.x ?? 0);
        points.add(Offset(x, _measure(plot, point.value)));
        baseline.add(Offset(x, _zeroLine(plot)));
      }
      if (spec.type.drawsPoints) {
        _drawCloud(canvas, plot, seriesIndex, points);
      } else {
        _drawSeriesPath(canvas, plot, seriesIndex, points, baseline);
      }
    }
  }

  void _drawSeriesPath(
    Canvas canvas,
    Rect plot,
    int seriesIndex,
    List<Offset> points,
    List<Offset> baseline,
  ) {
    if (points.isEmpty) {
      return;
    }
    final color = _colorFor(seriesIndex);
    final drawn = _revealed(points);
    if (drawn.isEmpty) {
      return;
    }

    final line = _smoothPath(drawn);

    if (spec.type.fillsArea && drawn.length > 1) {
      final area = Path.from(line);
      for (var index = drawn.length - 1; index >= 0; index--) {
        area.lineTo(baseline[index].dx, baseline[index].dy);
      }
      area.close();
      canvas.drawPath(
        area,
        Paint()
          ..isAntiAlias = true
          ..shader = ui.Gradient.linear(
            Offset(plot.center.dx, plot.top),
            Offset(plot.center.dx, plot.bottom),
            [
              color.withValues(alpha: color.a * 0.30),
              color.withValues(alpha: color.a * 0.02),
            ],
          ),
      );
    }

    if (drawn.length > 1) {
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ChartMetrics.lineWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..color = color,
      );
    }

    _plotDots(canvas, plot, seriesIndex, points, drawn.length);
  }

  void _drawCloud(
    Canvas canvas,
    Rect plot,
    int seriesIndex,
    List<Offset> points,
  ) {
    final series = data.series[seriesIndex];
    final color = _colorFor(seriesIndex);
    final bubbles = spec.type.sizesPoints && data.sizeMaximum > 0;

    for (var index = 0; index < points.length; index++) {
      final progress = _stagger(index, points.length);
      if (progress <= 0.01) {
        continue;
      }
      final centre = points[index];
      if (!plot.inflate(30).contains(centre)) {
        continue;
      }
      final hovered = highlight?.seriesIndex == seriesIndex &&
          highlight?.pointIndex == index;

      var radius = ChartMetrics.pointRadius + 0.6;
      if (bubbles) {
        final size = (series.points[index].size ?? 0).abs();
        // Area, not radius, carries the number — that is how a reader sees it.
        final fraction = math.sqrt(size / data.sizeMaximum).clamp(0.0, 1.0);
        radius = ChartMetrics.bubbleMinimumRadius +
            fraction *
                (ChartMetrics.bubbleMaximumRadius -
                    ChartMetrics.bubbleMinimumRadius);
      }
      radius *= progress;
      if (hovered) {
        radius *= 1 + 0.18 * emphasis.value;
      }

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..isAntiAlias = true
          ..color = color.withValues(alpha: color.a * (bubbles ? 0.55 : 0.9)),
      );
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bubbles ? 1.2 : 1
          ..isAntiAlias = true
          ..color = color.withValues(alpha: color.a * (hovered ? 1 : 0.75)),
      );

      hits.add(
        ChartHit(
          seriesIndex: seriesIndex,
          pointIndex: index,
          rect: Rect.fromCircle(center: centre, radius: math.max(radius, 9)),
          anchor: Offset(centre.dx, centre.dy - radius),
        ),
      );
    }
  }

  void _plotDots(
    Canvas canvas,
    Rect plot,
    int seriesIndex,
    List<Offset> points,
    int drawnCount,
  ) {
    final color = _colorFor(seriesIndex);
    // Dots crowd a dense line, so they appear only when there is room.
    final dense = points.length > 40;

    for (var index = 0; index < points.length; index++) {
      final centre = points[index];
      final hovered = highlight?.seriesIndex == seriesIndex &&
          highlight?.pointIndex == index;
      if (index < drawnCount && (!dense || hovered)) {
        final radius = ChartMetrics.pointRadius +
            (hovered
                ? (ChartMetrics.pointHoverRadius - ChartMetrics.pointRadius) *
                    emphasis.value
                : 0);
        if (hovered) {
          canvas.drawCircle(
            centre,
            radius + 5 * emphasis.value,
            Paint()..color = color.withValues(alpha: color.a * 0.16),
          );
        }
        canvas.drawCircle(
          centre,
          radius + 1.6,
          Paint()
            ..isAntiAlias = true
            ..color = palette.background,
        );
        canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..isAntiAlias = true
            ..color = color,
        );
      }
      hits.add(
        ChartHit(
          seriesIndex: seriesIndex,
          pointIndex: index,
          rect: Rect.fromCircle(center: centre, radius: 12),
          anchor: Offset(centre.dx, centre.dy - ChartMetrics.pointHoverRadius),
        ),
      );
    }
  }

  /// The stretch of a line that has been drawn so far.
  List<Offset> _revealed(List<Offset> points) {
    if (_t >= 1) {
      return points;
    }
    final shown = (points.length * _t).ceil().clamp(0, points.length);
    return points.take(shown).toList();
  }

  /// A gently rounded path, which reads better than hard corners without
  /// inventing values between the points.
  Path _smoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) {
      return path;
    }
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length < 3 || spec.type.drawsPoints) {
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path;
    }
    for (var index = 0; index < points.length - 1; index++) {
      final current = points[index];
      final next = points[index + 1];
      final controlX = (current.dx + next.dx) / 2;
      path.cubicTo(controlX, current.dy, controlX, next.dy, next.dx, next.dy);
    }
    return path;
  }

  // ------------------------------------------------------------- crosshair

  void _paintCrosshair(Canvas canvas, Rect plot) {
    final at = crosshair;
    final hit = highlight;
    if (at == null || hit == null || spec.type.drawsBars) {
      return;
    }
    final x = hit.anchor.dx;
    if (x < plot.left || x > plot.right) {
      return;
    }
    final paint = Paint()
      ..color = palette.axis.withValues(alpha: palette.axis.a * 0.9)
      ..strokeWidth = 1;
    // A dashed rule reads as a guide rather than as data.
    const dash = 4.0;
    const gap = 4.0;
    var y = plot.top;
    while (y < plot.bottom) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash, plot.bottom)),
        paint,
      );
      y += dash + gap;
    }
  }

  // --------------------------------------------------------------- circular

  void _paintCircular(Canvas canvas, Size size) {
    final visible = _visible;
    if (visible.isEmpty) {
      return;
    }
    final series = data.series[visible.first];
    final total = series.total;
    if (total <= 0) {
      return;
    }

    final side = math.min(size.width, size.height);
    final centre = Offset(size.width / 2, size.height / 2);
    final outer = side / 2 - 12;
    final donut = spec.type == ChartType.donut;
    final thickness = donut ? outer * 0.42 : outer;

    var angle = -math.pi / 2;
    for (var index = 0; index < series.points.length; index++) {
      final point = series.points[index];
      final sweep = (point.value.abs() / total) * math.pi * 2 * _t;
      if (sweep <= 0) {
        continue;
      }
      final hovered = highlight?.pointIndex == index;
      final lift = hovered ? 6.0 * emphasis.value : 0.0;
      final middle = angle + sweep / 2;
      final shift = Offset(math.cos(middle), math.sin(middle)) * lift;

      final color = _colorFor(visible.first, sliceIndex: index);
      final rect = Rect.fromCircle(
        center: centre + shift,
        radius: donut ? outer - thickness / 2 : outer,
      );

      canvas.drawArc(
        rect,
        angle,
        sweep,
        !donut,
        Paint()
          ..isAntiAlias = true
          ..style = donut ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = thickness
          ..color = color,
      );

      // A hairline between slices keeps neighbouring colours from merging.
      if (series.points.length > 1 && !donut) {
        canvas.drawArc(
          rect,
          angle,
          sweep,
          true,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = palette.background
            ..isAntiAlias = true,
        );
      }

      hits.add(
        ChartHit(
          seriesIndex: visible.first,
          pointIndex: index,
          rect: Rect.fromCircle(
            center: centre +
                Offset(math.cos(middle), math.sin(middle)) * (outer * 0.7),
            radius: math.max(outer * 0.22, 10),
          ),
          anchor: centre +
              Offset(math.cos(middle), math.sin(middle)) * (outer * 0.72),
        ),
      );

      if (spec.showValues && sweep > 0.34 && _t > 0.85) {
        final painter = _text(
          '${(point.value.abs() / total * 100).round()}%',
          11,
          Colors.white,
          weight: FontWeight.w600,
        );
        final anchor = centre +
            shift +
            Offset(math.cos(middle), math.sin(middle)) *
                (donut ? outer - thickness / 2 : outer * 0.62);
        painter.paint(
          canvas,
          anchor - Offset(painter.width / 2, painter.height / 2),
        );
      }
      angle += sweep;
    }

    if (donut) {
      _paintDonutCentre(canvas, centre, outer - thickness, series);
    }
  }

  void _paintDonutCentre(
    Canvas canvas,
    Offset centre,
    double radius,
    ChartSeries series,
  ) {
    if (radius < 26) {
      return;
    }
    final hit = highlight;
    final value = hit != null && hit.pointIndex < series.points.length
        ? series.points[hit.pointIndex].value
        : series.total;
    final caption = hit != null && hit.pointIndex < series.points.length
        ? series.points[hit.pointIndex].label
        : series.name;

    final number = _text(
      formatChartNumber(value),
      math.min(radius * 0.42, 24),
      palette.strongLabel,
      weight: FontWeight.w600,
      maxWidth: radius * 1.7,
    );
    number.paint(
      canvas,
      centre - Offset(number.width / 2, number.height / 2 + 2),
    );

    if (caption.isNotEmpty && radius > 40) {
      final label = _text(
        caption,
        10.5,
        palette.label,
        maxWidth: radius * 1.6,
      );
      label.paint(
        canvas,
        centre + Offset(-label.width / 2, number.height / 2 + 1),
      );
    }
  }

  // ------------------------------------------------------------------- text

  TextPainter _text(
    String value,
    double size,
    Color color, {
    FontWeight weight = FontWeight.w400,
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: palette.text(size: size, color: color, weight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    return painter;
  }

  /// The number a tooltip shows, in full.
  static String formatValue(double value) =>
      formatChartNumber(value, compact: false);

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.spec != spec ||
      oldDelegate.highlight != highlight ||
      oldDelegate.focusedSeries != focusedSeries ||
      oldDelegate.viewport != viewport ||
      oldDelegate.crosshair != crosshair ||
      !setEquals(oldDelegate.hidden, hidden) ||
      oldDelegate.palette.background != palette.background ||
      !listEquals(oldDelegate.colors.palette.series, colors.palette.series) ||
      !mapEquals(oldDelegate.colors.chosen, colors.chosen);
}
