import 'dart:ui' as ui;

import 'package:appflowy/extensions/dart/built_in/stock_extension.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The chart, the period picker and the colours a price is drawn in.
///
/// Shared so the document block and the dashboard card are the same chart at
/// two sizes, rather than two drifting copies of one idea.

Color stockAccent(bool rising) =>
    rising ? const Color(0xFF1B873F) : const Color(0xFFC0392B);

/// A line, its wash, the baseline it is measured from and a crosshair that
/// follows the pointer.
class StockChart extends StatelessWidget {
  const StockChart({
    super.key,
    required this.values,
    required this.color,
    required this.scrubbed,
    required this.onScrub,
    this.filled = true,
    this.baseline,
  });

  final List<double> values;
  final Color color;
  final bool filled;
  final double? baseline;
  final int? scrubbed;
  final ValueChanged<int?> onScrub;

  int _indexAt(double dx, double width) {
    if (values.length < 2 || width <= 0) {
      return 0;
    }
    final ratio = (dx / width).clamp(0.0, 1.0);
    return (ratio * (values.length - 1)).round();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          onHover: (event) =>
              onScrub(_indexAt(event.localPosition.dx, constraints.maxWidth)),
          onExit: (_) => onScrub(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => onScrub(
              _indexAt(details.localPosition.dx, constraints.maxWidth),
            ),
            onHorizontalDragUpdate: (details) => onScrub(
              _indexAt(details.localPosition.dx, constraints.maxWidth),
            ),
            onHorizontalDragEnd: (_) => onScrub(null),
            child: CustomPaint(
              size: Size.infinite,
              painter: _StockChartPainter(
                values: values,
                color: color,
                filled: filled,
                baseline: baseline,
                scrubbed: scrubbed,
              ),
            ),
          ),
        ),
      );
}

class _StockChartPainter extends CustomPainter {
  const _StockChartPainter({
    required this.values,
    required this.color,
    required this.filled,
    required this.baseline,
    required this.scrubbed,
  });

  final List<double> values;
  final Color color;
  final bool filled;
  final double? baseline;
  final int? scrubbed;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) {
      return;
    }

    var lowest = values.first;
    var highest = values.first;
    for (final value in values) {
      lowest = value < lowest ? value : lowest;
      highest = value > highest ? value : highest;
    }
    final start = baseline;
    if (start != null) {
      lowest = start < lowest ? start : lowest;
      highest = start > highest ? start : highest;
    }
    // Breathing room top and bottom, so the line never touches the edge.
    final pad = (highest - lowest) * 0.08;
    lowest -= pad;
    highest += pad;
    final span = highest - lowest;

    double yFor(double value) => span == 0
        ? size.height / 2
        : size.height - (value - lowest) / span * size.height;

    final step = size.width / (values.length - 1);
    final line = ui.Path();
    for (var index = 0; index < values.length; index++) {
      final point = Offset(step * index, yFor(values[index]));
      if (index == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }

    if (filled) {
      final wash = ui.Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        wash,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            Offset(0, size.height),
            [color.withValues(alpha: 0.26), color.withValues(alpha: 0.0)],
          ),
      );
    }

    if (start != null) {
      // The line the move is measured from, so a card reads at a glance.
      final y = yFor(start);
      final dashes = Paint()
        ..color = color.withValues(alpha: 0.32)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), dashes);
      }
    }

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    final at = scrubbed;
    if (at != null && at >= 0 && at < values.length) {
      final x = step * at;
      final y = yFor(values[at]);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      canvas
        ..drawCircle(Offset(x, y), 4.5, Paint()..color = color)
        ..drawCircle(Offset(x, y), 2, Paint()..color = const Color(0xFFFFFFFF));
    }
  }

  @override
  bool shouldRepaint(_StockChartPainter old) =>
      old.scrubbed != scrubbed ||
      old.color != color ||
      old.filled != filled ||
      old.baseline != baseline ||
      !listEquals(old.values, values);
}

/// `1D 5D 1M 6M YTD 1Y 5Y MAX`, scrollable so it never overflows a narrow card.
class StockRangePicker extends StatelessWidget {
  const StockRangePicker({
    super.key,
    required this.selected,
    required this.accent,
    required this.muted,
    required this.onSelected,
    this.enabled = true,
  });

  final StockRange selected;
  final Color accent;
  final Color muted;
  final bool enabled;
  final ValueChanged<StockRange> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 26,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final range in StockRange.values)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _RangeChip(
                  label: range.label,
                  selected: range == selected,
                  accent: accent,
                  muted: muted,
                  onTap: enabled ? () => onSelected(range) : null,
                ),
              ),
          ],
        ),
      );
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.muted,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: selected ? accent : muted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }
}
