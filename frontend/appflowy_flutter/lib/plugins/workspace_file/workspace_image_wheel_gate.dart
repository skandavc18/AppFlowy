import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// InteractiveViewer handles wheel zoom without consulting the signal
/// resolver. The page adapter owns plain vertical wheel instead. Filter only
/// pointer listeners: keep native gesture/hover/tap/Find hit identities, entry
/// subtypes and transforms, and forward every pan/zoom event unchanged.
class WorkspaceImageWheelGate extends SingleChildRenderObjectWidget {
  const WorkspaceImageWheelGate({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _ImageWheelGate();
}

bool isWorkspaceImagePageWheel(PointerEvent event) {
  final keys = HardwareKeyboard.instance;
  return event is PointerScrollEvent &&
      !keys.isControlPressed &&
      !keys.isMetaPressed &&
      !keys.isShiftPressed &&
      event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs();
}

class _ImageWheelGate extends RenderProxyBox {
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final childResult = BoxHitTestResult();
    final hit = super.hitTestChildren(childResult, position: position);
    for (final entry in childResult.path) {
      result.addWithRawTransform(
        transform: entry.transform,
        position: position,
        hitTest: (result, _) {
          if (entry.target is RenderPointerListener) {
            result.add(HitTestEntry(_ImageWheelTarget(entry)));
          } else if (entry is BoxHitTestEntry) {
            result.add(BoxHitTestEntry(entry.target, entry.localPosition));
          } else if (entry is SliverHitTestEntry) {
            result.add(
              SliverHitTestEntry(
                entry.target,
                mainAxisPosition: entry.mainAxisPosition,
                crossAxisPosition: entry.crossAxisPosition,
              ),
            );
          } else {
            result.add(HitTestEntry(entry.target));
          }
          return true;
        },
      );
    }
    return hit;
  }
}

class _ImageWheelTarget implements HitTestTarget {
  _ImageWheelTarget(this.original);
  final HitTestEntry original;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (!isWorkspaceImagePageWheel(event)) {
      original.target.handleEvent(event, original);
    }
  }
}
