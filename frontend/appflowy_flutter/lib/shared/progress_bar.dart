import 'dart:math' as math;

import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/material.dart';

/// Progress has a quiet green identity rather than borrowing the app's brand
/// colour. Surfaces still come from the active theme, including warm paper.
@immutable
class ProgressBarColors {
  const ProgressBarColors({
    required this.fill,
    required this.highlight,
    required this.track,
    required this.ink,
  });

  factory ProgressBarColors.of(BuildContext context, {Color? accent}) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final paper = PaperTheme.isEnabled(context);
    final surface = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      theme.colorScheme.surface,
      isPaper: paper,
    );
    final fill = accent == null
        ? paper
            ? const Color(0xFF588C42)
            : dark
                ? const Color(0xFF71C68B)
                : const Color(0xFF43955A)
        : Color.lerp(surface, accent, dark ? 0.85 : 0.72)!;
    return ProgressBarColors(
      fill: fill,
      highlight: Color.lerp(fill, surface, 0.035)!,
      track: Color.alphaBlend(
        fill.withValues(alpha: dark ? 0.15 : 0.07),
        surface,
      ),
      // Pale green is for the fill, not for small text or interactive glyphs.
      ink: Color.lerp(fill, theme.colorScheme.onSurface, dark ? 0.35 : 0.7)!,
    );
  }

  final Color fill;
  final Color highlight;
  final Color track;
  final Color ink;
}

/// A read-only label, never the value written back to a cell. Keep percentages
/// and checklist ratios recognisable while removing fractional display noise.
String progressDisplayLabel(String raw) {
  final text = raw.trim();
  final parts = text.split('/');
  if (parts.length == 2) {
    final numerator = _progressInteger(parts.first);
    final denominator = _progressInteger(parts.last);
    if (numerator != null && denominator != null) {
      return '$numerator/$denominator';
    }
  }
  final percent = text.endsWith('%');
  final number = _progressInteger(
    percent ? text.substring(0, text.length - 1) : text,
  );
  return number == null ? text : '$number${percent ? '%' : ''}';
}

String? _progressInteger(String text) {
  final number = double.tryParse(text.trim().replaceAll(',', ''));
  if (number == null || !number.isFinite) return null;
  final rounded = number.roundToDouble();
  // Avoid native int overflow for large bounds, and never print negative zero.
  return rounded == 0 ? '0' : rounded.toStringAsFixed(0);
}

/// The same softly rounded rail in a grid, form, mailbox or card. Painting
/// instead of measuring also supports the grid's intrinsic-height layout.
class AppFlowyProgressBar extends StatelessWidget {
  const AppFlowyProgressBar({
    super.key,
    required this.fraction,
    required this.fill,
    required this.track,
    this.highlight,
    this.height = 6,
    this.animate = true,
    this.duration = const Duration(milliseconds: 260),
  });

  final double fraction;
  final Color fill;
  final Color track;
  final Color? highlight;
  final double height;
  final bool animate;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final target = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    final animated = animate && !MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: target, end: target),
      duration: animated ? duration : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, drawn, _) => SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(
          painter: _ProgressPainter(
            fraction: animated ? drawn : target,
            fill: fill,
            track: track,
            highlight: highlight ?? fill,
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.highlight,
  });

  final double fraction;
  final Color fill;
  final Color track;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    if (fraction <= 0) return;
    final width = math.min(
      size.width,
      math.max(size.height, fraction * size.width),
    );
    final filled = Rect.fromLTWH(0, 0, width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(filled, radius),
      Paint()
        ..shader =
            LinearGradient(colors: [highlight, fill]).createShader(filled),
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.fill != fill ||
      oldDelegate.track != track ||
      oldDelegate.highlight != highlight;
}
