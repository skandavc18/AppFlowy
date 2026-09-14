import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MouseTrackerAnnotation;
import 'package:flutter/widgets.dart';

/// Keeps scroll input out of an inactive embed without blocking other input.
///
/// ScrollPhysics cannot govern a platform view or a custom pan/zoom recognizer.
/// Filtering their hit-test targets prevents them from joining the scroll
/// gesture arena at all. The enclosing Scrollable receives the original event
/// and uses its own physics: no synthetic events or second scroll engine.
/// Layout, painting, semantics, mouse annotations and ordinary pointers remain
/// unchanged. The child stays mounted when ownership changes.
class ScrollGestureGate extends SingleChildRenderObjectWidget {
  const ScrollGestureGate({
    super.key,
    required this.blocked,
    required super.child,
  });

  final bool blocked;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollGestureGate(blocked);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) =>
      (renderObject as _RenderScrollGestureGate).blocked = blocked;
}

class _RenderScrollGestureGate extends RenderProxyBox {
  _RenderScrollGestureGate(this.blocked);

  bool blocked;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!blocked) return super.hitTestChildren(result, position: position);

    final childResult = BoxHitTestResult();
    final hit = super.hitTestChildren(childResult, position: position);
    for (final entry in childResult.path) {
      // Preserve both the child's transform and every transform above this
      // gate. Forward the original entry too: some targets require its subtype.
      result.addWithRawTransform(
        transform: entry.transform,
        position: position,
        hitTest: (result, _) {
          if (entry.target is MouseTrackerAnnotation ||
              entry.target is RenderTapRegion) {
            // MouseTracker compares annotation identity between frames. Keep
            // the real annotation (including TextSpans) so scrolling never
            // churns enter/exit/hover or drops a link's cursor. TapRegionSurface
            // also uses target identity to distinguish inside/outside presses.
            result.add(
              entry is BoxHitTestEntry
                  ? BoxHitTestEntry(entry.target, entry.localPosition)
                  : HitTestEntry(entry.target),
            );
          } else {
            result.add(HitTestEntry(_NonScrollTarget(entry)));
          }
          return true;
        },
      );
    }
    return hit;
  }
}

class _NonScrollTarget implements HitTestTarget {
  _NonScrollTarget(this.original);

  final HitTestEntry original;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerScrollEvent ||
        event is PointerScrollInertiaCancelEvent ||
        event is PointerPanZoomStartEvent ||
        event is PointerPanZoomUpdateEvent ||
        event is PointerPanZoomEndEvent) {
      return;
    }
    original.target.handleEvent(event, original);
  }
}
