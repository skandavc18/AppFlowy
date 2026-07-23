import 'dart:math' as math;

import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// Adds a barely-visible, non-repeating grain to the Paper canvas.
///
/// The painter is isolated from application repaints and ignores input, so it
/// behaves like stationery rather than another interactive UI layer.
class PremiumThemeBackdrop extends StatelessWidget {
  const PremiumThemeBackdrop({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = PremiumThemeExtension.maybeOf(context);
    final shouldPaint = Theme.of(context).brightness == Brightness.light &&
        palette?.isPaper == true &&
        palette!.paperGrain.a > 0;
    if (!shouldPaint) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _PaperGrainPainter(palette.paperGrain),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaperGrainPainter extends CustomPainter {
  const _PaperGrainPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final seed = size.width.round() * 73856093 ^ size.height.round() * 19349663;
    final random = math.Random(seed);
    final area = size.width * size.height;
    final speckCount = (area / 9000).round().clamp(80, 420);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var i = 0; i < speckCount; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(point, 0.25 + random.nextDouble() * 0.35, paint);
    }

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.35;
    final fiberCount = (speckCount / 20).round();
    for (var i = 0; i < fiberCount; i++) {
      final start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final length = 6 + random.nextDouble() * 14;
      final angle = (random.nextDouble() - 0.5) * 0.24;
      canvas.drawLine(
        start,
        start + Offset(math.cos(angle) * length, math.sin(angle) * length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGrainPainter oldDelegate) =>
      oldDelegate.color != color;
}
