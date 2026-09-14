import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets the enclosing page scroll over an embedded card until it is clicked.
///
/// Only scroll physics are gated: the first click still reaches buttons, text
/// fields and chart gestures. Keyboard focus and accessibility activation also
/// engage the card. An outside press, focus leaving, or an unhandled Escape
/// disengages it. Hover and trackpad pan/zoom never activate it.
///
/// Descendants must inherit the local ScrollConfiguration (possibly through a
/// delegating behavior). This covers native Scrollables, including the premium
/// wheel dispatcher, which checks the same shouldAcceptUserOffset contract.
/// [gateScrollGestures] also covers custom renderers with their own gestures.
class ScrollActivationRegion extends StatefulWidget {
  const ScrollActivationRegion({
    super.key,
    required this.child,
    this.active,
    this.onActiveChanged,
    this.gateScrollGestures = false,
  });

  final Widget child;

  /// Also gates custom PDF/canvas/platform-view gesture handlers, not just
  /// Flutter scroll physics. Ordinary clicks and touch editing are unaffected.
  final bool gateScrollGestures;

  /// When supplied, the host's visible selection is the only source of truth.
  /// Focus alone cannot enable scrolling in controlled mode; a completed click
  /// or accessibility activation asks the host to select the card instead.
  final bool? active;
  final ValueChanged<bool>? onActiveChanged;

  @override
  State<ScrollActivationRegion> createState() => _ScrollActivationRegionState();
}

class _ScrollActivationRegionState extends State<ScrollActivationRegion> {
  final _focus =
      FocusNode(debugLabel: 'Card scroll activation', skipTraversal: true);
  bool _localActive = false;
  int? _pointer;
  Offset _pressPosition = Offset.zero;
  FocusNode? _focusAtPress;

  bool get _active => widget.active ?? _localActive;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onGlobalKeyEvent);
  }

  bool _onGlobalKeyEvent(KeyEvent event) {
    // The document's keyboard service can retain focus after an embed header
    // click. Escape must still release that embed; don't steal the key or
    // change focus, and let an open dialog/menu handle its own Escape first.
    if (widget.gateScrollGestures &&
        _active &&
        (ModalRoute.isCurrentOf(context) ?? true)) {
      _onKeyEvent(_focus, event);
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant ScrollActivationRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.active ?? _localActive) && !_active) {
      // External deselection can arrive during an ancestor's build. Stop the
      // mounted positions after layout, without dispatching scroll notifications
      // into that build or reactivating a still-focused child.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_active) _stopScrolling();
      });
    }
  }

  void _activate({bool requestFocus = false, FocusNode? previousFocus}) {
    if (!mounted) return;
    if (!_active) {
      if (widget.active == null) setState(() => _localActive = true);
      widget.onActiveChanged?.call(true);
    }
    if (!requestFocus) return;
    // Child controls get their normal click/focus first. Do not steal focus
    // from a field or from a popup opened by that very same click.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_active ||
          _focus.hasFocus ||
          !(ModalRoute.isCurrentOf(context) ?? true) ||
          FocusManager.instance.primaryFocus != previousFocus) {
        return;
      }
      _focus.requestFocus();
    });
  }

  void _deactivate() {
    if (!mounted || !_active) return;
    _stopScrolling();
    if (widget.active == null) setState(() => _localActive = false);
    widget.onActiveChanged?.call(false);
  }

  void _stopScrolling() {
    // Cancel only descendant activities, never the enclosing page. Changing
    // physics alone can leave an already-running wheel/fling activity alive.
    void stop(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (position.hasPixels && position.isScrollingNotifier.value) {
          position.jumpTo(position.pixels);
        }
      }
      element.visitChildElements(stop);
    }

    context.visitChildElements(stop);
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null || event.buttons != kPrimaryButton) {
      _pointer = null;
      return;
    }
    _pointer = event.pointer;
    _pressPosition = event.position;
    _focusAtPress = FocusManager.instance.primaryFocus;
  }

  void _pointerMove(PointerMoveEvent event) {
    // Match a dashboard card's movement threshold. Dragging/resizing a card
    // must not accidentally turn the next wheel gesture into an inner scroll.
    if (_pointer == event.pointer &&
        (event.position - _pressPosition).distance >= 4) {
      _pointer = null;
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    if ((event.position - _pressPosition).distance >= 4) return;
    _activate(requestFocus: true, previousFocus: _focusAtPress);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _deactivate();
    }
    // Child controls (e.g. dasha Back or a menu) get first refusal. Let the
    // dashboard/editor also handle Escape; never capture editing shortcuts.
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKeyEvent);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TapRegion(
        onTapOutside: (_) => _deactivate(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: (_) => _pointer = null,
          child: Focus(
            focusNode: _focus,
            onFocusChange: (focused) {
              if (!focused) {
                _deactivate();
              } else if (widget.active == null) {
                _activate();
              }
            },
            onKeyEvent: _onKeyEvent,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              selected: _active,
              hint: _active
                  ? 'Scroll inside this card. Click outside or press Escape to scroll the page.'
                  : 'Click to scroll inside this card.',
              onTap: () => _activate(
                requestFocus: true,
                previousFocus: FocusManager.instance.primaryFocus,
              ),
              child: ScrollConfiguration(
                behavior: _ActivationScrollBehavior(
                  parent: ScrollConfiguration.of(context),
                  active: _active,
                  route: ModalRoute.of(context),
                ),
                child: ScrollGestureGate(
                  blocked: widget.gateScrollGestures && !_active,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      );
}

/// Delegate every platform detail, including premium-wheel region decoration.
/// Nested copyWith(scrollbars: ...) must retain the activation physics too.
class _ActivationScrollBehavior extends ScrollBehavior {
  const _ActivationScrollBehavior({
    required this.parent,
    required this.active,
    required this.route,
  });

  final ScrollBehavior parent;
  final bool active;
  final ModalRoute<dynamic>? route;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final physics = parent.getScrollPhysics(context);
    // A dialog/menu already explicitly opened from a card is not another
    // inactive card, even if its host carried this behavior into the route.
    return active || ModalRoute.of(context) != route
        ? physics
        : NeverScrollableScrollPhysics(parent: physics);
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      parent.buildScrollbar(context, child, details);

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
  bool shouldNotify(covariant _ActivationScrollBehavior oldDelegate) =>
      active != oldDelegate.active ||
      route != oldDelegate.route ||
      parent != oldDelegate.parent;
}
