import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A local scrollbar opt-out that also survives EditableText's internal
/// copyWith(scrollbars: true). Keep the surrounding physics, devices, and
/// overscroll behavior; only the rail is omitted.
class NoScrollbarBehavior extends ScrollBehavior {
  const NoScrollbarBehavior(this.parent);

  final ScrollBehavior parent;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      parent.buildOverscrollIndicator(context, child, details);

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      parent.getPlatform(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      parent.getScrollPhysics(context);

  @override
  Set<PointerDeviceKind> get dragDevices => parent.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      parent.pointerAxisModifiers;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      parent.getMultitouchDragStrategy(context);

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      parent.velocityTrackerBuilder(context);

  @override
  bool shouldNotify(covariant NoScrollbarBehavior oldDelegate) =>
      parent != oldDelegate.parent;
}
