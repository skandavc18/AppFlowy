import 'package:flutter/material.dart';

/// One scrolling document with a paint-only action overlay. Nested field
/// scrollers do not move the row actions, and scrolling never rebuilds cells.
class RowDetailScrollSurface extends StatefulWidget {
  const RowDetailScrollSurface({
    super.key,
    required this.child,
    required this.actions,
    required this.coverHeight,
  });

  final Widget child;
  final Widget actions;
  final double coverHeight;

  @override
  State<RowDetailScrollSurface> createState() => _RowDetailScrollSurfaceState();
}

class _RowDetailScrollSurfaceState extends State<RowDetailScrollSurface> {
  final _offset = ValueNotifier<double>(0);

  void _update(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return;
    // Indexed document navigation can use a negative minimum. Near the start
    // this is the real header offset; further down the actions simply pin.
    _offset.value = metrics.extentBefore.clamp(0.0, widget.coverHeight);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              _update(notification.metrics, notification.depth);
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                _update(notification.metrics, notification.depth);
                return false;
              },
              child: widget.child,
            ),
          ),
          Flow(
            delegate: _RowActionsPosition(
              offset: _offset,
              coverHeight: widget.coverHeight,
            ),
            children: [RepaintBoundary(child: widget.actions)],
          ),
        ],
      );
}

class _RowActionsPosition extends FlowDelegate {
  _RowActionsPosition({required this.offset, required this.coverHeight})
      : super(repaint: offset);

  final ValueNotifier<double> offset;
  final double coverHeight;

  @override
  BoxConstraints getConstraintsForChild(
          int index, BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  void paintChildren(FlowPaintingContext context) {
    final size = context.getChildSize(0)!;
    context.paintChild(
      0,
      transform: Matrix4.translationValues(
        (context.size.width - size.width - 12).clamp(0.0, double.infinity),
        12 + (coverHeight - offset.value).clamp(0.0, coverHeight),
        0,
      ),
    );
  }

  @override
  bool shouldRepaint(_RowActionsPosition oldDelegate) =>
      oldDelegate.offset != offset || oldDelegate.coverHeight != coverHeight;
}

/// Fields may contain an unsaved edit or an open picker. Lazy document layout
/// must not dispose that state just because the header leaves the viewport.
class RowDetailScrollHeader extends StatefulWidget {
  const RowDetailScrollHeader({super.key, required this.child});

  final Widget child;

  @override
  State<RowDetailScrollHeader> createState() => _RowDetailScrollHeaderState();
}

class _RowDetailScrollHeaderState extends State<RowDetailScrollHeader>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
