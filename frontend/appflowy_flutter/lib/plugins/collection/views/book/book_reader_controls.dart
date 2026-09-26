import 'dart:math' as math;

import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:flutter/material.dart';

/// A borderless control on the reading chrome. Quiet until it is pointed at.
class BookControlButton extends StatelessWidget {
  const BookControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.palette,
    this.onPressed,
    this.selected = false,
    this.label,
  });

  final IconData icon;
  final String tooltip;
  final BookReaderPalette palette;
  final VoidCallback? onPressed;
  final bool selected;
  final String? label;

  @override
  Widget build(BuildContext context) => Theme(
        data: palette.themeFor(Theme.of(context)),
        child: CollectionWorkspaceAction(
          icon:
              icon == Icons.remove_done_rounded ? Icons.history_rounded : icon,
          tooltip: tooltip,
          label: label,
          selected: selected,
          onPressed: onPressed,
          size: BookReaderMetrics.controlSize,
          color: palette.inkMuted,
        ),
      );
}

/// The hairline reading progress line under the chapter.
class BookProgressBar extends StatelessWidget {
  const BookProgressBar({
    super.key,
    required this.value,
    required this.palette,
    this.height = 2.5,
  });

  final double value;
  final BookReaderPalette palette;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: palette.rule.withValues(alpha: 0.4)),
            ),
            AnimatedContainer(
              duration: BookReaderMetrics.motion,
              curve: BookReaderMetrics.curve,
              width: constraints.maxWidth * value.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(height),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The overall progress dial on the contents page.
class BookProgressRing extends StatelessWidget {
  const BookProgressRing({
    super.key,
    required this.value,
    required this.palette,
    this.size = 84,
    this.strokeWidth = 6,
    this.child,
  });

  final double value;
  final BookReaderPalette palette;
  final double size;
  final double strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => CustomPaint(
          painter: _BookProgressRingPainter(
            value: animated,
            track: palette.rule.withValues(alpha: 0.5),
            accent: palette.accent,
            strokeWidth: strokeWidth,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _BookProgressRingPainter extends CustomPainter {
  const _BookProgressRingPainter({
    required this.value,
    required this.track,
    required this.accent,
    required this.strokeWidth,
  });

  final double value;
  final Color track;
  final Color accent;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(inset, 0, math.pi * 2, false, base);
    if (value <= 0) {
      return;
    }
    canvas.drawArc(
      inset,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      base..color = accent,
    );
  }

  @override
  bool shouldRepaint(_BookProgressRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.track != track ||
      oldDelegate.accent != accent ||
      oldDelegate.strokeWidth != strokeWidth;
}
