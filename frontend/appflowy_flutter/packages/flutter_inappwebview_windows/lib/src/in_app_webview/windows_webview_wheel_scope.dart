import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Lets a host consume part of a Windows WebView wheel event without replacing
/// hit-test targets or forwarding a second pointer event.
///
/// The nearest scope runs once, only when the WebView wins Flutter's pointer
/// signal resolver. Return the remaining delta in [PointerScrollEvent.scrollDelta]
/// units/sign; the WebView then negates it and applies its disabled-axis settings.
/// Return [Offset.zero] to consume all motion. Without a scope the original delta
/// is used. Trackpad gestures, mouse buttons and touchscreen input are unchanged.
class WindowsWebViewWheelScope extends InheritedWidget {
  const WindowsWebViewWheelScope({
    super.key,
    required this.transform,
    required super.child,
  });

  /// May synchronously consume host motion (for example, a page header).
  /// Hosts should return the original delta for modifiers/directions they do not
  /// consume. This is not called if an input gate blocks the native listener.
  final Offset Function(PointerScrollEvent event) transform;

  static WindowsWebViewWheelScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WindowsWebViewWheelScope>();

  @override
  bool updateShouldNotify(WindowsWebViewWheelScope oldWidget) =>
      transform != oldWidget.transform;
}
