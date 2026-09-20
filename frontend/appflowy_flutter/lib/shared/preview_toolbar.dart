import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A preview's interaction boundary, not a second frame or gesture owner.
///
/// Place this around the actual preview (not its full-width alignment row).
/// Only [PreviewToolbar] descendants rebuild when the pointer enters/leaves;
/// renderers, drafts, scroll positions and native views stay mounted verbatim.
class PreviewToolbarRegion extends StatefulWidget {
  const PreviewToolbarRegion({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  /// Keeps the originating preview's controls visible while a popup owns the
  /// pointer/focus. The returned release is safe after unmount and idempotent.
  static VoidCallback hold(BuildContext context) {
    final scopes = <_PreviewToolbarController>[];
    var scope = context.getInheritedWidgetOfExactType<_PreviewToolbarScope>();
    while (scope != null) {
      scopes.add(scope.controller);
      scope.controller.hold();
      scope = scope.parent;
    }
    var released = false;
    return () {
      if (released) return;
      released = true;
      for (final controller in scopes) {
        controller.release();
      }
    };
  }

  @override
  State<PreviewToolbarRegion> createState() => _PreviewToolbarRegionState();
}

class _PreviewToolbarRegionState extends State<PreviewToolbarRegion> {
  final _controller = _PreviewToolbarController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PreviewToolbarScope(
        controller: _controller,
        enabled: widget.enabled,
        parent:
            context.dependOnInheritedWidgetOfExactType<_PreviewToolbarScope>(),
        child: MouseRegion(
          opaque: false,
          hitTestBehavior: HitTestBehavior.translucent,
          onEnter: (_) => _controller.setHovered(true),
          onHover: (_) => _controller.setHovered(true),
          onExit: (_) => _controller.setHovered(false),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (event.kind == PointerDeviceKind.touch ||
                  event.kind == PointerDeviceKind.stylus ||
                  event.kind == PointerDeviceKind.invertedStylus) {
                _controller.revealForTouch();
              }
            },
            child: widget.child,
          ),
        ),
      );
}

class _PreviewToolbarController extends ChangeNotifier {
  bool _hovered = false;
  bool _touch = false;
  bool _disposed = false;
  int _holds = 0;

  bool get visible => _hovered || _touch || _holds > 0;

  void setHovered(bool value) {
    if (_disposed || (_hovered == value && !_touch)) return;
    _hovered = value;
    _touch = false;
    notifyListeners();
  }

  void revealForTouch() {
    if (_disposed || _touch) return;
    _touch = true;
    notifyListeners();
  }

  void hold() {
    if (_disposed) return;
    _holds++;
    if (_holds == 1) notifyListeners();
  }

  void release() {
    if (_disposed || _holds == 0) return;
    _holds--;
    if (_holds == 0) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _PreviewToolbarScope
    extends InheritedNotifier<_PreviewToolbarController> {
  const _PreviewToolbarScope({
    required _PreviewToolbarController controller,
    required this.enabled,
    required this.parent,
    required super.child,
  }) : super(notifier: controller);

  final bool enabled;
  final _PreviewToolbarScope? parent;
  _PreviewToolbarController get controller => notifier!;

  @override
  bool updateShouldNotify(_PreviewToolbarScope oldWidget) =>
      enabled != oldWidget.enabled || super.updateShouldNotify(oldWidget);
}

/// Quiet actions for a preview. Identity/content should remain outside this.
///
/// Without a [PreviewToolbarRegion], tools stay visible: standalone file and
/// database pages retain their fixed chrome. Hidden tools keep their geometry
/// and Tab order, but cannot intercept clicks or appear in the semantics tree.
class PreviewToolbar extends StatefulWidget {
  const PreviewToolbar({
    super.key,
    required this.child,
    this.keepVisible = false,
  });

  final Widget child;
  final bool keepVisible;

  @override
  State<PreviewToolbar> createState() => _PreviewToolbarState();
}

class _PreviewToolbarState extends State<PreviewToolbar> {
  final _focusNode = FocusNode(debugLabel: 'Preview toolbar');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // Removing a focused search field detaches its focus node before its old
    // ancestors necessarily receive onFocusChange(false). Observe the settled
    // primary-focus tree too, rather than retaining a stale visible toolbar.
    FocusManager.instance.addListener(_syncFocus);
  }

  void _syncFocus() {
    final focused = _focusNode.hasFocus;
    if (mounted && _focused != focused) {
      setState(() => _focused = focused);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncFocus);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_PreviewToolbarScope>();
    final media = MediaQuery.maybeOf(context);
    final platform = Theme.of(context).platform;
    final visible = scope == null ||
        !scope.enabled ||
        scope.controller.visible ||
        widget.keepVisible ||
        _focusNode.hasFocus ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        (media?.accessibleNavigation ?? false);
    final reducedMotion = (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (_) => _syncFocus(),
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
