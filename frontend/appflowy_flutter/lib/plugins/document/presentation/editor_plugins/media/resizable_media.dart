import 'package:flutter/material.dart';

const defaultVisualMediaWidth = 640.0;
const defaultAudioMediaWidth = 520.0;
const defaultImageWidth = 640.0;

class ResizableMedia extends StatefulWidget {
  const ResizableMedia({
    super.key,
    required this.width,
    required this.onResize,
    required this.child,
    this.minWidth = 240,
    this.editable = true,
  });

  final double width;
  final double minWidth;
  final bool editable;
  final ValueChanged<double> onResize;
  final Widget child;

  @override
  State<ResizableMedia> createState() => _ResizableMediaState();
}

class _ResizableMediaState extends State<ResizableMedia> {
  double? dragWidth;
  bool isHovering = false;

  @override
  void didUpdateWidget(covariant ResizableMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width && dragWidth != null) {
      dragWidth = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : widget.width;
        final width = (dragWidth ?? widget.width)
            .clamp(widget.minWidth.clamp(0, maxWidth), maxWidth)
            .toDouble();

        return Align(
          child: MouseRegion(
            onEnter: (_) => setState(() => isHovering = true),
            onExit: (_) => setState(() => isHovering = false),
            child: SizedBox(
              key: const ValueKey('resizable_media'),
              width: width,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  widget.child,
                  if (widget.editable) ...[
                    _ResizeHandle(
                      left: true,
                      visible: isHovering || dragWidth != null,
                      onDrag: (delta) => _resize(width - delta * 2, maxWidth),
                      onEnd: _finishResize,
                    ),
                    _ResizeHandle(
                      left: false,
                      visible: isHovering || dragWidth != null,
                      onDrag: (delta) => _resize(width + delta * 2, maxWidth),
                      onEnd: _finishResize,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

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
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.left,
    required this.visible,
    required this.onDrag,
    required this.onEnd,
  });

  final bool left;
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
      left: left ? -3 : null,
      right: left ? null : -3,
      width: 10,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
          onHorizontalDragEnd: (_) => onEnd(),
          child: Center(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 100),
              child: Container(
                width: 5,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  border: Border.all(color: Colors.white),
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
