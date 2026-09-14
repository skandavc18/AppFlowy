import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show MouseTrackerAnnotation;
import 'package:flutter/widgets.dart';

/// Suspends descendant mouse annotations while the immediate scroll view moves.
///
/// Only depth-zero start/end notifications change the state, so ballistic
/// scrolling stays suppressed until it ends and nested embeds do not activate
/// it. The child remains mounted with unchanged layout, painting and semantics.
/// Clicks, drags and scroll input still reach their original hit-test targets.
class ScrollHoverSuppression extends StatefulWidget {
  const ScrollHoverSuppression({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollHoverSuppression> createState() => _ScrollHoverSuppressionState();
}

class _ScrollHoverSuppressionState extends State<ScrollHoverSuppression> {
  bool _suppressing = false;
  bool? _pendingSuppressing;
  bool _updateScheduled = false;

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0) {
      if (notification is ScrollStartNotification) {
        _setSuppressing(true);
      } else if (notification is ScrollEndNotification) {
        _setSuppressing(false);
      }
    }
    return false;
  }

  void _setSuppressing(bool value) {
    if (!mounted || (_pendingSuppressing ?? _suppressing) == value) return;
    _pendingSuppressing = value;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // Scroll activities can end during a descendant's build/layout. Coalesce
      // those notifications without rebuilding an ancestor in the same frame.
      if (_updateScheduled) return;
      _updateScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _updateScheduled = false;
        if (mounted) _applyPendingSuppression();
      });
    } else {
      _applyPendingSuppression();
    }
  }

  void _applyPendingSuppression() {
    final value = _pendingSuppressing;
    _pendingSuppressing = null;
    if (value == null || value == _suppressing) return;
    setState(() {
      _suppressing = value;
    });
  }

  @override
  void dispose() {
    _pendingSuppressing = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: _HoverSuppression(
          suppressing: _suppressing,
          child: widget.child,
        ),
      );
}

class _HoverSuppression extends SingleChildRenderObjectWidget {
  const _HoverSuppression({required this.suppressing, required super.child});

  final bool suppressing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHoverSuppression(suppressing);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderHoverSuppression).suppressing = suppressing;
}

class _RenderHoverSuppression extends RenderProxyBox {
  _RenderHoverSuppression(this._suppressing);

  bool _suppressing;

  set suppressing(bool value) {
    if (_suppressing == value) return;
    _suppressing = value;
    // Re-hit-test even a stationary mouse: exit once at start, enter at idle.
    markNeedsPaint();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_suppressing) return super.hitTestChildren(result, position: position);

    final childResult = BoxHitTestResult();
    final hit = super.hitTestChildren(childResult, position: position);
    for (final entry in childResult.path) {
      // As in ScrollGestureGate, compose each child's transform with the
      // caller's transform, rather than adding already-transformed entries.
      result.addWithRawTransform(
        transform: entry.transform,
        position: position,
        hitTest: (result, _) {
          if (entry.target is MouseTrackerAnnotation) {
            result.add(HitTestEntry(_NonHoverTarget(entry)));
          } else {
            // Keep ALL other identities, notably RenderTapRegion and custom
            // scroll dispatchers. List slivers and boxes require their own
            // entry subtypes when a new click/hover arrives during a fling.
            result.add(
              entry is BoxHitTestEntry
                  ? BoxHitTestEntry(entry.target, entry.localPosition)
                  : entry is SliverHitTestEntry
                      ? SliverHitTestEntry(
                          entry.target,
                          mainAxisPosition: entry.mainAxisPosition,
                          crossAxisPosition: entry.crossAxisPosition,
                        )
                      : HitTestEntry(entry.target),
            );
          }
          return true;
        },
      );
    }
    return hit;
  }
}

class _NonHoverTarget implements HitTestTarget {
  _NonHoverTarget(this.original);

  final HitTestEntry original;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerHoverEvent) return;
    original.target.handleEvent(event, original);
  }
}
