import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'image_editor_theme.dart';

/// A compact square icon control. Deliberately not an [IconButton]: the editor
/// chrome uses its own hover, radius and motion language.
class ImageEditorIconButton extends StatefulWidget {
  const ImageEditorIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.palette,
    this.onPressed,
    this.isActive = false,
    this.dimension = 32,
    this.iconSize = 18,
  });

  final IconData icon;
  final String tooltip;
  final ImageEditorPalette palette;
  final VoidCallback? onPressed;
  final bool isActive;
  final double dimension;
  final double iconSize;

  @override
  State<ImageEditorIconButton> createState() => _ImageEditorIconButtonState();
}

class _ImageEditorIconButtonState extends State<ImageEditorIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null;
    final background = widget.isActive
        ? palette.controlActive
        : _hovering && enabled
            ? palette.controlHover
            : Colors.transparent;
    final foreground = !enabled
        ? palette.textMuted
        : widget.isActive
            ? palette.textPrimary
            : palette.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: ImageEditorMotion.instant,
            curve: ImageEditorMotion.curve,
            width: widget.dimension,
            height: widget.dimension,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// Text action used for Save / Export / Reset.
class ImageEditorTextButton extends StatefulWidget {
  const ImageEditorTextButton({
    super.key,
    required this.label,
    required this.palette,
    this.onPressed,
    this.filled = false,
    this.icon,
    this.busy = false,
  });

  final String label;
  final ImageEditorPalette palette;
  final VoidCallback? onPressed;
  final bool filled;
  final IconData? icon;
  final bool busy;

  @override
  State<ImageEditorTextButton> createState() => _ImageEditorTextButtonState();
}

class _ImageEditorTextButtonState extends State<ImageEditorTextButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null && !widget.busy;
    final Color background;
    final Color foreground;
    if (widget.filled) {
      background = enabled
          ? (_hovering
              ? Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.12),
                  palette.accent,
                )
              : palette.accent)
          : palette.control;
      foreground = enabled ? palette.onAccent : palette.textMuted;
    } else {
      background = _hovering && enabled ? palette.controlHover : Colors.transparent;
      foreground = enabled ? palette.textSecondary : palette.textMuted;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: ImageEditorMotion.instant,
          curve: ImageEditorMotion.curve,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.busy)
                SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              else if (widget.icon != null)
                Icon(widget.icon, size: 15, color: foreground),
              if (widget.busy || widget.icon != null) const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill used for crop ratios, filters and annotation tools.
class ImageEditorChip extends StatefulWidget {
  const ImageEditorChip({
    super.key,
    required this.label,
    required this.palette,
    required this.selected,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final ImageEditorPalette palette;
  final bool selected;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  State<ImageEditorChip> createState() => _ImageEditorChipState();
}

class _ImageEditorChipState extends State<ImageEditorChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final foreground =
        widget.selected ? palette.textPrimary : palette.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: ImageEditorMotion.instant,
          curve: ImageEditorMotion.curve,
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: widget.icon != null ? 10 : 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.controlActive
                : _hovering
                    ? palette.controlHover
                    : palette.control,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: widget.selected ? palette.accent : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 15, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Continuous control with a live value read-out. Bipolar sliders fill from
/// the centre so "no change" is visually obvious.
class ImageEditorSlider extends StatefulWidget {
  const ImageEditorSlider({
    super.key,
    required this.label,
    required this.value,
    required this.palette,
    required this.onChanged,
    this.onChangeEnd,
    this.min = -1,
    this.max = 1,
    this.neutral = 0,
  });

  final String label;
  final double value;
  final ImageEditorPalette palette;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;
  final double min;
  final double max;
  final double neutral;

  @override
  State<ImageEditorSlider> createState() => _ImageEditorSliderState();
}

class _ImageEditorSliderState extends State<ImageEditorSlider> {
  bool _hovering = false;
  bool _dragging = false;

  double get _fraction =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  double get _neutralFraction =>
      ((widget.neutral - widget.min) / (widget.max - widget.min))
          .clamp(0.0, 1.0);

  void _updateFromPosition(double dx, double width) {
    if (width <= 0) {
      return;
    }
    final fraction = (dx / width).clamp(0.0, 1.0);
    final value = widget.min + fraction * (widget.max - widget.min);
    // Snap gently to the neutral position so returning to "no change" is easy.
    final snapped =
        (value - widget.neutral).abs() < (widget.max - widget.min) * 0.02
            ? widget.neutral
            : value;
    widget.onChanged(double.parse(snapped.toStringAsFixed(3)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final display = ((widget.value - widget.neutral) * 100).round();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: ImageEditorMotion.instant,
                  opacity: display == 0 && !_hovering && !_dragging ? 0.45 : 1,
                  child: Text(
                    display > 0 ? '+$display' : '$display',
                    style: TextStyle(
                      color: display == 0
                          ? palette.textMuted
                          : palette.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _updateFromPosition(details.localPosition.dx, width),
                    onTapUp: (_) => widget.onChangeEnd?.call(),
                    onDoubleTap: () {
                      widget.onChanged(widget.neutral);
                      widget.onChangeEnd?.call();
                    },
                    onHorizontalDragStart: (details) {
                      setState(() => _dragging = true);
                      _updateFromPosition(details.localPosition.dx, width);
                    },
                    onHorizontalDragUpdate: (details) =>
                        _updateFromPosition(details.localPosition.dx, width),
                    onHorizontalDragEnd: (_) {
                      setState(() => _dragging = false);
                      widget.onChangeEnd?.call();
                    },
                    onHorizontalDragCancel: () {
                      setState(() => _dragging = false);
                      widget.onChangeEnd?.call();
                    },
                    child: SizedBox(
                      height: 18,
                      child: CustomPaint(
                        painter: _SliderPainter(
                          fraction: _fraction,
                          neutralFraction: _neutralFraction,
                          track: palette.control,
                          fill: palette.accent,
                          thumb: palette.chrome,
                          thumbBorder: palette.accent,
                          tick: palette.divider,
                          active: _hovering || _dragging,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.fraction,
    required this.neutralFraction,
    required this.track,
    required this.fill,
    required this.thumb,
    required this.thumbBorder,
    required this.tick,
    required this.active,
  });

  final double fraction;
  final double neutralFraction;
  final Color track;
  final Color fill;
  final Color thumb;
  final Color thumbBorder;
  final Color tick;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackRect = RRect.fromLTRBR(
      0,
      centerY - 1.75,
      size.width,
      centerY + 1.75,
      const Radius.circular(2),
    );
    canvas.drawRRect(trackRect, Paint()..color = track);

    final neutralX = neutralFraction * size.width;
    final valueX = fraction * size.width;
    final left = math.min(neutralX, valueX);
    final right = math.max(neutralX, valueX);
    if (right - left > 0.5) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          centerY - 1.75,
          right,
          centerY + 1.75,
          const Radius.circular(2),
        ),
        Paint()..color = fill,
      );
    }

    if (neutralFraction > 0.01 && neutralFraction < 0.99) {
      canvas.drawRect(
        Rect.fromLTWH(neutralX - 0.5, centerY - 4.5, 1, 9),
        Paint()..color = tick,
      );
    }

    final radius = active ? 7.0 : 6.0;
    canvas.drawCircle(
      Offset(valueX.clamp(radius, size.width - radius), centerY),
      radius,
      Paint()..color = thumb,
    );
    canvas.drawCircle(
      Offset(valueX.clamp(radius, size.width - radius), centerY),
      radius,
      Paint()
        ..color = thumbBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.neutralFraction != neutralFraction ||
      oldDelegate.active != active ||
      oldDelegate.fill != fill ||
      oldDelegate.track != track;
}

class ImageEditorSectionTitle extends StatelessWidget {
  const ImageEditorSectionTitle({
    super.key,
    required this.label,
    required this.palette,
    this.trailing,
  });

  final String label;
  final ImageEditorPalette palette;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                height: 1.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
