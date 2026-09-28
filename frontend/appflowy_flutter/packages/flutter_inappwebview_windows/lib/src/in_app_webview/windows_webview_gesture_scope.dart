import 'package:flutter/widgets.dart';

/// Enables Windows WebView trackpad arbitration even in a host which disables
/// both browser scroll axes (for example an outer whole-page scroll region).
/// The host must let the descendant WebView win the trackpad gesture arena;
/// ancestor raw pointer listeners must not also scroll/navigate for that hit.
/// Wheel, physical mouse and touchscreen routing are not changed by this scope.
class WindowsWebViewGestureScope extends InheritedWidget {
  const WindowsWebViewGestureScope({
    super.key,
    this.preferWebsiteGestures = false,
    required super.child,
  });

  /// False: automatically inspect the hit region once per gesture and retain
  /// article history/browser zoom elsewhere. True: give the site all trackpad
  /// pans/pinches, including cross-origin frames or opaque/delegated handlers
  /// which cannot be detected. Chromium decides touch-action/default behavior.
  final bool preferWebsiteGestures;

  static WindowsWebViewGestureScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowsWebViewGestureScope>();

  @override
  bool updateShouldNotify(WindowsWebViewGestureScope oldWidget) =>
      preferWebsiteGestures != oldWidget.preferWebsiteGestures;
}
