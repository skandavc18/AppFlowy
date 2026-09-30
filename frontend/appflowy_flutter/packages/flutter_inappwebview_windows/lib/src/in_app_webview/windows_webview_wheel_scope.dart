import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Lets a host consume part of a Windows WebView wheel event without replacing
/// hit-test targets or forwarding a second pointer event.
///
/// The nearest scope runs once, only when the WebView wins Flutter's pointer
/// signal resolver. Return the remaining delta in [PointerScrollEvent.scrollDelta]
/// units/sign; the WebView then negates it and applies its disabled-axis settings.
/// Return [Offset.zero] to consume all motion. Without a scope the original delta
/// is used. Mouse buttons and touchscreen input are unchanged; trackpad pans
/// change only when [trackpad] is supplied.
class WindowsWebViewWheelScope extends InheritedWidget {
  const WindowsWebViewWheelScope({
    super.key,
    required this.transform,
    this.pixelWheel = false,
    this.trackpad,
    required super.child,
  });

  /// May synchronously consume host motion (for example, a page header).
  /// Hosts should return the original delta for modifiers/directions they do not
  /// consume. This is not called if an input gate blocks the native listener.
  final Offset Function(PointerScrollEvent event) transform;

  /// Delivers the remaining motion at Chromium's pixel scale, 120 wheel units
  /// per 100 logical pixels, instead of the default notch gain. A page script
  /// can then recover the exact logical distance from `wheelDeltaX/Y`.
  final bool pixelWheel;

  /// Delivers trackpad pans to the host, then to the page as wheel input,
  /// instead of emulating a touch contact. Pinch and rotation are ignored.
  final WindowsWebViewTrackpadWheel? trackpad;

  static WindowsWebViewWheelScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WindowsWebViewWheelScope>();

  @override
  bool updateShouldNotify(WindowsWebViewWheelScope oldWidget) =>
      transform != oldWidget.transform ||
      pixelWheel != oldWidget.pixelWheel ||
      trackpad != oldWidget.trackpad;
}

/// Host callbacks for trackpad pans delivered as wheel input.
@immutable
class WindowsWebViewTrackpadWheel {
  const WindowsWebViewTrackpadWheel({
    this.onStart,
    required this.onUpdate,
    this.onEnd,
    this.onInertiaCancel,
  });

  /// A new two-finger gesture started over the WebView.
  final VoidCallback? onStart;

  /// Receives each pan in [PointerScrollEvent.scrollDelta] units/sign
  /// (positive scrolls down/right) and returns the part the page receives.
  final Offset Function(Offset delta) onUpdate;

  /// Called once per gesture with the release velocity in logical pixels per
  /// second, scroll-delta sign; [Offset.zero] when cancelled or stationary.
  final ValueChanged<Offset>? onEnd;

  /// The platform reported that a touch interrupted the inertia following a
  /// release. A host that keeps moving after [onEnd] should stop.
  final VoidCallback? onInertiaCancel;
}
