import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const defaultVisualMediaWidth = 640.0;
const defaultAudioMediaWidth = 520.0;

/// Portrait clips, such as YouTube Shorts, are framed like a phone screen so a
/// widescreen width does not make them tower over the document.
const defaultPortraitMediaWidth = 340.0;

/// A newly inserted picture lands as a thumbnail rather than a full-bleed
/// banner; the drag handles are there for anyone who wants it bigger.
const defaultImageWidth = 360.0;

typedef ResizableMediaFrameBuilder = Widget Function(Widget frame);

class ResizableMedia extends StatefulWidget {
  const ResizableMedia({
    super.key,
    required this.width,
    required this.onResize,
    required this.child,
    this.minWidth = 240,
    this.height,
    this.minHeight = 180,
    this.maxHeight = 1200,
    this.onResizeHeight,
    this.editable = true,
    this.alignment = Alignment.center,
    this.frameBuilder,
    this.footer,
  });

  final double width;
  final double minWidth;
  final double? height;
  final double minHeight;
  final double maxHeight;
  final bool editable;
  final Alignment alignment;
  final ValueChanged<double> onResize;
  final ValueChanged<double>? onResizeHeight;
  final ResizableMediaFrameBuilder? frameBuilder;

  /// Rendered under the frame at the same width. It stays outside the measured
  /// frame so intrinsic-height resizing is not thrown off by it.
  final Widget? footer;
  final Widget child;

  @override
  State<ResizableMedia> createState() => _ResizableMediaState();
}

class _ResizableMediaState extends State<ResizableMedia> {
  final mediaSizeKey = GlobalKey(debugLabel: 'resizable_media_size');
  double? dragWidth;
  double? dragHeight;
  Offset? cornerDragStartPosition;
  double? cornerDragStartWidth;
  double? cornerDragStartHeight;
  bool? cornerDragFromLeft;
  bool isHovering = false;

  @override
  void didUpdateWidget(covariant ResizableMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width && dragWidth != null) {
      dragWidth = null;
    }
    if (oldWidget.height != widget.height && dragHeight != null) {
      dragHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final palette = PremiumThemeExtension.maybeOf(context);
    final isLightPaper = materialTheme.brightness == Brightness.light &&
        PaperTheme.isEnabled(context);
    final gripColor = isLightPaper
        ? PaperTheme.resizeHandle
        : materialTheme.brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.72)
            : (palette?.textSecondary ?? Colors.black).withValues(alpha: 0.72);
    final gripBorderColor = palette?.floatingSurface ??
        (isLightPaper
            ? PaperTheme.popupBackground
            : materialTheme.colorScheme.surfaceBright);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : widget.width;
        final width = (dragWidth ?? widget.width)
            .clamp(widget.minWidth.clamp(0, maxWidth), maxWidth)
            .toDouble();
        final height = dragHeight ?? widget.height;
        final frame = SizedBox(
          key: const ValueKey('resizable_media'),
          width: width,
          height: height,
          child: Stack(
            fit: height == null ? StackFit.loose : StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (widget.editable) ...[
                _ResizeHandle(
                  left: true,
                  color: gripColor,
                  borderColor: gripBorderColor,
                  visible: isHovering || dragWidth != null,
                  onDrag: (delta) =>
                      _resize(width - delta * _resizeFactor, maxWidth),
                  onEnd: _finishResize,
                ),
                _ResizeHandle(
                  left: false,
                  color: gripColor,
                  borderColor: gripBorderColor,
                  visible: isHovering || dragWidth != null,
                  onDrag: (delta) =>
                      _resize(width + delta * _resizeFactor, maxWidth),
                  onEnd: _finishResize,
                ),
                if (widget.onResizeHeight != null) ...[
                  _BottomResizeHandle(
                    color: gripColor,
                    borderColor: gripBorderColor,
                    visible: isHovering || dragHeight != null,
                    onDrag: (delta) => _resizeHeight(
                      (height ?? _renderedHeight ?? widget.minHeight) + delta,
                    ),
                    onEnd: _finishHeightResize,
                  ),
                  _CornerResizeHandle(
                    left: true,
                    color: gripColor,
                    borderColor: gripBorderColor,
                    visible:
                        isHovering || dragWidth != null || dragHeight != null,
                    onStart: (position) => _startCornerResize(
                      position: position,
                      width: width,
                      height: height ?? _renderedHeight ?? widget.minHeight,
                      left: true,
                    ),
                    onDrag: (position) => _resizeFromCorner(position, maxWidth),
                    onEnd: _finishBothResize,
                  ),
                  _CornerResizeHandle(
                    left: false,
                    color: gripColor,
                    borderColor: gripBorderColor,
                    visible:
                        isHovering || dragWidth != null || dragHeight != null,
                    onStart: (position) => _startCornerResize(
                      position: position,
                      width: width,
                      height: height ?? _renderedHeight ?? widget.minHeight,
                      left: false,
                    ),
                    onDrag: (position) => _resizeFromCorner(position, maxWidth),
                    onEnd: _finishBothResize,
                  ),
                ],
              ],
            ],
          ),
        );

        return Align(
          alignment: widget.alignment,
          child: MouseRegion(
            onEnter: (_) => setState(() => isHovering = true),
            onExit: (_) => setState(() => isHovering = false),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  key: mediaSizeKey,
                  child: widget.frameBuilder?.call(frame) ?? frame,
                ),
                if (widget.footer != null)
                  SizedBox(width: width, child: widget.footer),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A centred frame grows from both edges at once, so a drag has to move the
  /// edge twice as far. Edge-anchored frames follow the pointer one to one.
  double get _resizeFactor => widget.alignment.x == 0 ? 2.0 : 1.0;

  void _resize(double width, double maxWidth) {
    setState(
      () => dragWidth = width.clamp(
        widget.minWidth.clamp(0, maxWidth),
        maxWidth,
      ),
    );
  }

  void _finishResize() {
    final width = dragWidth;
    if (width != null) {
      widget.onResize(width);
    }
  }

  void _resizeHeight(double height) {
    setState(
      () => dragHeight = height.clamp(widget.minHeight, widget.maxHeight),
    );
  }

  double? get _renderedHeight {
    final renderBox =
        mediaSizeKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.hasSize == true ? renderBox!.size.height : null;
  }

  void _finishHeightResize() {
    final height = dragHeight;
    if (height != null) {
      widget.onResizeHeight?.call(height);
    }
  }

  void _finishBothResize() {
    _finishResize();
    _finishHeightResize();
    cornerDragStartPosition = null;
    cornerDragStartWidth = null;
    cornerDragStartHeight = null;
    cornerDragFromLeft = null;
  }

  void _startCornerResize({
    required Offset position,
    required double width,
    required double height,
    required bool left,
  }) {
    cornerDragStartPosition = position;
    cornerDragStartWidth = width;
    cornerDragStartHeight = height;
    cornerDragFromLeft = left;
  }

  void _resizeFromCorner(Offset position, double maxWidth) {
    final startPosition = cornerDragStartPosition;
    final startWidth = cornerDragStartWidth;
    final startHeight = cornerDragStartHeight;
    final fromLeft = cornerDragFromLeft;
    if (startPosition == null ||
        startWidth == null ||
        startHeight == null ||
        fromLeft == null) {
      return;
    }
    final offset = position - startPosition;
    _resize(
      startWidth + (fromLeft ? -offset.dx : offset.dx) * _resizeFactor,
      maxWidth,
    );
    _resizeHeight(startHeight + offset.dy);
  }
}

class _BottomResizeHandle extends StatelessWidget {
  const _BottomResizeHandle({
    required this.color,
    required this.borderColor,
    required this.visible,
    required this.onDrag,
    required this.onEnd,
  });

  final Color color;
  final Color borderColor;
  final bool visible;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: const ValueKey('resizable_media_bottom_handle'),
      left: 0,
      right: 0,
      bottom: 0,
      height: 14,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: _EagerResizeDragRegion(
          onUpdate: (event) => onDrag(event.delta.dy),
          onEnd: onEnd,
          child: Center(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerResizeHandle extends StatelessWidget {
  const _CornerResizeHandle({
    required this.left,
    required this.color,
    required this.borderColor,
    required this.visible,
    required this.onStart,
    required this.onDrag,
    required this.onEnd,
  });

  final bool left;
  final Color color;
  final Color borderColor;
  final bool visible;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: ValueKey(
        left
            ? 'resizable_media_bottom_left_handle'
            : 'resizable_media_bottom_right_handle',
      ),
      left: left ? 0 : null,
      right: left ? null : 0,
      bottom: 0,
      width: 32,
      height: 32,
      child: MouseRegion(
        cursor: left
            ? SystemMouseCursors.resizeUpRightDownLeft
            : SystemMouseCursors.resizeUpLeftDownRight,
        child: _EagerResizeDragRegion(
          onStart: (event) => onStart(event.position),
          onUpdate: (event) => onDrag(event.position),
          onEnd: onEnd,
          child: Align(
            alignment: left ? Alignment.bottomLeft : Alignment.bottomRight,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(4),
                    topRight: const Radius.circular(4),
                    bottomLeft: Radius.circular(left ? 3 : 4),
                    bottomRight: Radius.circular(left ? 4 : 3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.left,
    required this.color,
    required this.borderColor,
    required this.visible,
    required this.onDrag,
    required this.onEnd,
  });

  final bool left;
  final Color color;
  final Color borderColor;
  final bool visible;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: ValueKey(
        left ? 'resizable_media_left_handle' : 'resizable_media_right_handle',
      ),
      top: 0,
      bottom: 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      width: 14,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: _EagerResizeDragRegion(
          onUpdate: (event) => onDrag(event.delta.dx),
          onEnd: onEnd,
          child: Center(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 5,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EagerResizeDragRegion extends StatefulWidget {
  const _EagerResizeDragRegion({
    required this.onUpdate,
    required this.onEnd,
    required this.child,
    this.onStart,
  });

  final ValueChanged<PointerDownEvent>? onStart;
  final ValueChanged<PointerMoveEvent> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_EagerResizeDragRegion> createState() => _EagerResizeDragRegionState();
}

class _EagerResizeDragRegionState extends State<_EagerResizeDragRegion> {
  int? activePointer;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          EagerGestureRecognizer.new,
          (_) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (activePointer != null) {
            return;
          }
          activePointer = event.pointer;
          widget.onStart?.call(event);
        },
        onPointerMove: (event) {
          if (event.pointer == activePointer) {
            widget.onUpdate(event);
          }
        },
        onPointerUp: _finishDrag,
        onPointerCancel: _finishDrag,
        child: widget.child,
      ),
    );
  }

  void _finishDrag(PointerEvent event) {
    if (event.pointer != activePointer) {
      return;
    }
    activePointer = null;
    widget.onEnd();
  }
}
