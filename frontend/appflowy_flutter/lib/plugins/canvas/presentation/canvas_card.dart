import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_node_body.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_view_resolver.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Which grip is being pulled.
enum CanvasHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get movesLeft => this == topLeft || this == left || this == bottomLeft;
  bool get movesTop => this == topLeft || this == top || this == topRight;
  bool get changesWidth => this != top && this != bottom;
  bool get changesHeight => this != left && this != right;

  Alignment get alignment => switch (this) {
        CanvasHandle.topLeft => Alignment.topLeft,
        CanvasHandle.top => Alignment.topCenter,
        CanvasHandle.topRight => Alignment.topRight,
        CanvasHandle.right => Alignment.centerRight,
        CanvasHandle.bottomRight => Alignment.bottomRight,
        CanvasHandle.bottom => Alignment.bottomCenter,
        CanvasHandle.bottomLeft => Alignment.bottomLeft,
        CanvasHandle.left => Alignment.centerLeft,
      };

  MouseCursor get cursor => switch (this) {
        CanvasHandle.topLeft ||
        CanvasHandle.bottomRight =>
          SystemMouseCursors.resizeUpLeftDownRight,
        CanvasHandle.topRight ||
        CanvasHandle.bottomLeft =>
          SystemMouseCursors.resizeUpRightDownLeft,
        CanvasHandle.top || CanvasHandle.bottom => SystemMouseCursors.resizeRow,
        CanvasHandle.left ||
        CanvasHandle.right =>
          SystemMouseCursors.resizeColumn,
      };
}

/// A card on the canvas: its surface, its selection ring, its grips and the
/// four points a connection can be pulled from.
///
/// The card is laid out in SCENE units — the board applies one transform to
/// the whole layer — so nothing here has to think about the camera except the
/// chrome that must stay the same size on screen whatever the zoom.
class CanvasCard extends StatefulWidget {
  const CanvasCard({
    super.key,
    required this.node,
    required this.palette,
    required this.resolver,
    required this.zoom,
    required this.selected,
    required this.editing,
    required this.editable,
    required this.onTap,
    required this.onDoubleTap,
    required this.onContextMenu,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    required this.onConnectStart,
    required this.onConnectUpdate,
    required this.onConnectEnd,
    required this.onTextChanged,
    required this.onEditingFinished,
    required this.onOpen,
    required this.onSetUp,
    required this.onEdit,
    this.connectingFrom = false,
    this.connectTarget = false,
    this.searchHit = false,
    this.showPorts = true,
  });

  final CanvasNode node;
  final CanvasPalette palette;
  final CanvasViewResolver resolver;
  final double zoom;
  final bool selected;
  final bool editing;
  final bool editable;

  /// Pointer, in scene units, reported by every gesture so the board can work
  /// in one coordinate space.
  final void Function(bool shift) onTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition) onContextMenu;

  final VoidCallback onDragStart;
  final void Function(Offset sceneDelta, Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;

  final void Function(CanvasHandle handle) onResizeStart;
  final void Function(CanvasHandle handle, Offset sceneDelta) onResizeUpdate;
  final VoidCallback onResizeEnd;

  final void Function(CanvasSide side) onConnectStart;
  final void Function(Offset globalPosition) onConnectUpdate;
  final void Function(Offset globalPosition) onConnectEnd;

  final ValueChanged<String> onTextChanged;
  final VoidCallback onEditingFinished;
  final VoidCallback onOpen;

  /// Ask the card what it holds — which picture, which address, which sort of
  /// diagram. Fired by a single click while the card is still empty.
  final VoidCallback onSetUp;

  /// Change what the card already holds: rewrite the diagram, swap the
  /// picture, point the link somewhere else.
  final VoidCallback onEdit;

  /// This card is where a connection being drawn started.
  final bool connectingFrom;

  /// A connection is being drawn and this card is under the pointer.
  final bool connectTarget;

  /// This card matches what is being searched for.
  final bool searchHit;

  /// Ports are hidden while a card is inside a collapsed frame, and on a
  /// canvas that cannot be changed.
  final bool showPorts;

  @override
  State<CanvasCard> createState() => _CanvasCardState();
}

class _CanvasCardState extends State<CanvasCard> {
  bool _hovered = false;
  Offset _travel = Offset.zero;
  bool _moving = false;
  DateTime? _lastTap;
  Offset? _pressedAt;

  bool get _showChrome =>
      widget.editable && (_hovered || widget.selected) && !widget.editing;

  /// What opening this card would do, when that means anything.
  String? get _openLabel {
    final node = widget.node;
    if (node.needsSetUp) {
      return null;
    }
    return switch (node.kind) {
      CanvasNodeKind.canvas => LocaleKeys.canvas_card_openCanvas.tr(),
      CanvasNodeKind.page ||
      CanvasNodeKind.database ||
      CanvasNodeKind.file =>
        LocaleKeys.canvas_card_openPage.tr(),
      CanvasNodeKind.web ||
      CanvasNodeKind.bookmark =>
        LocaleKeys.canvas_menu_open.tr(),
      CanvasNodeKind.diagram ||
      CanvasNodeKind.image ||
      CanvasNodeKind.text ||
      CanvasNodeKind.code =>
        null,
    };
  }

  IconData get _openIcon => switch (widget.node.kind) {
        CanvasNodeKind.web ||
        CanvasNodeKind.bookmark =>
          Icons.open_in_new_rounded,
        CanvasNodeKind.diagram => Icons.draw_rounded,
        _ => Icons.arrow_outward_rounded,
      };

  /// What changing this card would mean, and the icon for it. Every card that
  /// holds something says how to change it; a card that holds nothing yet says
  /// how to fill it.
  (String, IconData)? get _editAction {
    final node = widget.node;
    if (!widget.editable || node.locked) {
      return null;
    }
    if (node.needsSetUp) {
      return switch (node.kind) {
        CanvasNodeKind.image => (
            LocaleKeys.canvas_image_choose.tr(),
            Icons.image_rounded,
          ),
        CanvasNodeKind.diagram => (
            LocaleKeys.canvas_diagram_choose.tr(),
            Icons.account_tree_rounded,
          ),
        CanvasNodeKind.web || CanvasNodeKind.bookmark => (
            LocaleKeys.canvas_card_addUrl.tr(),
            Icons.link_rounded,
          ),
        _ => (
            LocaleKeys.canvas_card_chooseObject.tr(),
            Icons.search_rounded,
          ),
      };
    }
    return switch (node.kind) {
      CanvasNodeKind.image => (
          LocaleKeys.canvas_image_title.tr(),
          Icons.image_rounded,
        ),
      CanvasNodeKind.web || CanvasNodeKind.bookmark => (
          LocaleKeys.canvas_card_addUrl.tr(),
          Icons.link_rounded,
        ),
      CanvasNodeKind.diagram => node.diagramKind == CanvasDiagramKind.drawing
          ? (LocaleKeys.canvas_diagram_edit.tr(), Icons.draw_rounded)
          : (LocaleKeys.canvas_diagram_editSource.tr(), Icons.edit_rounded),
      CanvasNodeKind.text || CanvasNodeKind.code => (
          LocaleKeys.canvas_menu_edit.tr(),
          Icons.edit_rounded,
        ),
      CanvasNodeKind.page ||
      CanvasNodeKind.database ||
      CanvasNodeKind.canvas ||
      CanvasNodeKind.file =>
        (LocaleKeys.canvas_card_chooseObject.tr(), Icons.swap_horiz_rounded),
    };
  }

  /// The buttons drawn on the card itself.
  List<({String label, IconData icon, VoidCallback onPressed})>
      get _cardActions {
    final node = widget.node;
    if (widget.editing || !widget.editable) {
      return const [];
    }
    // A card that holds nothing shows its one action without waiting to be
    // hovered, because there is nothing else on it to aim at.
    if (!_showChrome && !node.needsSetUp) {
      return const [];
    }
    final edit = _editAction;
    final open = _openLabel;
    return [
      if (edit != null)
        (
          label: edit.$1,
          icon: edit.$2,
          onPressed: node.needsSetUp ? widget.onSetUp : widget.onEdit,
        ),
      if (open != null)
        (label: open, icon: _openIcon, onPressed: widget.onOpen),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final node = widget.node;
    // Chrome must keep its size on screen, so everything drawn in scene units
    // that is meant to read as a fixed weight is divided by the zoom.
    final inverse = 1 / math.max(0.0001, widget.zoom);

    final ringColour = widget.connectTarget
        ? palette.accent
        : widget.searchHit
            ? const Color(0xFFF59E0B)
            : palette.accent;
    final showRing =
        widget.selected || widget.connectTarget || widget.searchHit;

    final card = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.editing ? MouseCursor.defer : SystemMouseCursors.click,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceFor(node.color),
          borderRadius: BorderRadius.circular(CanvasMetrics.cardRadius),
          boxShadow:
              palette.cardShadow(raisedCard: _hovered || widget.selected),
          border: Border.all(
            color: palette.borderFor(node.color),
            width: node.color == null ? 0.8 : 1,
          ),
        ),
        foregroundDecoration: showRing
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(CanvasMetrics.cardRadius),
                border: Border.all(
                  color: ringColour,
                  width: CanvasMetrics.selectionRing * inverse,
                ),
              )
            : null,
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.all(
          node.kind == CanvasNodeKind.image ? 0 : CanvasMetrics.space3,
        ),
        // A card that is not being typed into must not take the pointer, or
        // the board could never drag it: the field would win the arena.
        child: IgnorePointer(
          ignoring: !widget.editing,
          child: CanvasNodeBody(
            node: node,
            palette: palette,
            resolver: widget.resolver,
            editable: widget.editable,
            editing: widget.editing,
            onTextChanged: widget.onTextChanged,
            onEditingFinished: widget.onEditingFinished,
            onOpen: widget.onOpen,
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: card),
        if (!widget.editing) Positioned.fill(child: _gestures(inverse)),
        if (_showChrome && !node.locked) ...[
          for (final handle in CanvasHandle.values)
            _grip(handle, inverse, palette),
        ],
        if (_showChrome && widget.showPorts && !node.locked)
          for (final side in const [
            CanvasSide.top,
            CanvasSide.right,
            CanvasSide.bottom,
            CanvasSide.left,
          ])
            _port(side, inverse, palette),
        // The card's own actions, drawn ABOVE the gesture layer so they can
        // actually be pressed. A button painted inside the body could never
        // be: the drag surface covers the whole card.
        if (_cardActions.isNotEmpty)
          Positioned(
            top: 5 * inverse,
            right: 26 * inverse,
            child: Transform.scale(
              scale: inverse,
              alignment: Alignment.topRight,
              child: CanvasSurface(
                palette: palette,
                padding: EdgeInsets.zero,
                radius: CanvasMetrics.controlRadius,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in _cardActions)
                      CanvasButton(
                        icon: action.icon,
                        palette: palette,
                        size: 24,
                        iconSize: 14,
                        tooltip: action.label,
                        onPressed: action.onPressed,
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (node.locked && _hovered)
          Positioned(
            top: 4 * inverse,
            right: 4 * inverse,
            child: Transform.scale(
              scale: inverse,
              alignment: Alignment.topRight,
              child: Icon(
                Icons.lock_rounded,
                size: 13,
                color: palette.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _gestures(double inverse) {
    // A canvas that cannot be changed still answers a click and a right-click:
    // selecting a card, opening it and reading its menu are not edits. The
    // listener is translucent, so a drag still pans the surface underneath.
    if (!widget.editable) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _pressedAt = event.position;
          if (event.buttons & kSecondaryMouseButton != 0) {
            widget.onContextMenu(event.position);
          }
        },
        onPointerUp: (event) {
          final from = _pressedAt;
          _pressedAt = null;
          if (from != null && (event.position - from).distance < 4) {
            _reportTap();
          }
        },
        child: const SizedBox.expand(),
      );
    }
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _CardPanRecognizer:
            GestureRecognizerFactoryWithHandlers<_CardPanRecognizer>(
          _CardPanRecognizer.new,
          (recognizer) {
            recognizer.onStart = (_) {
              _travel = Offset.zero;
              _moving = false;
            };
            recognizer.onUpdate = (details) {
              _travel += details.delta;
              if (!_moving) {
                // A click that wobbles is still a click; only real travel
                // picks the card up.
                if (_travel.distance * widget.zoom < 4) {
                  return;
                }
                _moving = true;
                widget.onDragStart();
                widget.onDragUpdate(_travel, details.globalPosition);
                return;
              }
              widget.onDragUpdate(details.delta, details.globalPosition);
            };
            recognizer.onEnd = (_) {
              if (_moving) {
                widget.onDragEnd();
              } else {
                _reportTap();
              }
              _moving = false;
            };
            // A cancelled pan means some other recogniser won and is already
            // reporting the click. Reporting it here as well would fire two
            // taps inside the double-click window.
            recognizer.onCancel = () => _moving = false;
          },
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) {
            widget.onContextMenu(event.position);
          }
        },
        child: const SizedBox.expand(),
      ),
    );
  }

  /// Single and double clicks are timed by hand. A `DoubleTapGestureRecognizer`
  /// in the same arena holds every single click back by the double-tap
  /// timeout, which on a canvas reads as the card not responding at all.
  void _reportTap() {
    final now = DateTime.now();
    final previous = _lastTap;
    _lastTap = now;
    if (previous != null && now.difference(previous) < kDoubleTapTimeout) {
      _lastTap = null;
      widget.onDoubleTap();
      return;
    }
    widget.onTap(HardwareKeyboard.instance.isShiftPressed);
    // An empty card has nothing to look at and nothing else a click could
    // mean, so one click asks it what it holds. Waiting for a second click on
    // a card that says "choose a picture" is what reads as nothing happening.
    if (widget.node.needsSetUp && widget.editable) {
      widget.onSetUp();
    }
  }

  Widget _grip(CanvasHandle handle, double inverse, CanvasPalette palette) {
    // Grips sit just INSIDE the card. A `Positioned` hanging off the edge is
    // outside the stack's own box and can never be hit.
    final size = CanvasMetrics.handleSize * inverse;
    final target = size * 2.4;
    final alignment = handle.alignment;

    return Positioned(
      left: alignment.x < 0 ? 0 : null,
      right: alignment.x > 0 ? 0 : null,
      top: alignment.y < 0 ? 0 : null,
      bottom: alignment.y > 0 ? 0 : null,
      width: alignment.x == 0 ? null : target,
      height: alignment.y == 0 ? null : target,
      child: Align(
        alignment: alignment,
        child: MouseRegion(
          cursor: handle.cursor,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              // Eager, because the card's own pan is a sibling that would
              // otherwise take a grip drag away from it.
              _EagerPanRecognizer:
                  GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
                _EagerPanRecognizer.new,
                (recognizer) {
                  recognizer.onStart = (_) {
                    widget.onResizeStart(handle);
                  };
                  recognizer.onUpdate = (details) {
                    widget.onResizeUpdate(handle, details.delta);
                  };
                  recognizer.onEnd = (_) => widget.onResizeEnd();
                  recognizer.onCancel = widget.onResizeEnd;
                },
              ),
            },
            child: SizedBox(
              width: alignment.x == 0 ? null : target,
              height: alignment.y == 0 ? null : target,
              child: Center(
                child: alignment.x == 0 || alignment.y == 0
                    ? Container(
                        width: alignment.x == 0 ? size * 2.6 : size * 0.7,
                        height: alignment.y == 0 ? size * 2.6 : size * 0.7,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          borderRadius: BorderRadius.circular(size),
                        ),
                      )
                    : Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: palette.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.accent,
                            width: 1.6 * inverse,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _port(CanvasSide side, double inverse, CanvasPalette palette) {
    final radius = CanvasMetrics.portRadius * inverse;
    final target = radius * 3;
    final alignment = switch (side) {
      CanvasSide.top => Alignment.topCenter,
      CanvasSide.right => Alignment.centerRight,
      CanvasSide.bottom => Alignment.bottomCenter,
      CanvasSide.left => Alignment.centerLeft,
      CanvasSide.auto => Alignment.center,
    };

    return Positioned(
      left: alignment.x <= 0 ? (alignment.x == 0 ? null : 0) : null,
      right: alignment.x >= 0 ? (alignment.x == 0 ? null : 0) : null,
      top: alignment.y <= 0 ? (alignment.y == 0 ? null : 0) : null,
      bottom: alignment.y >= 0 ? (alignment.y == 0 ? null : 0) : null,
      // A port on the left or right spans the full height so it can be
      // centred; the same the other way round.
      width: alignment.x == 0 ? null : target,
      height: alignment.y == 0 ? null : target,
      child: Align(
        alignment: alignment,
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: Tooltip(
            message: LocaleKeys.canvas_menu_addConnection.tr(),
            waitDuration: const Duration(milliseconds: 600),
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _EagerPanRecognizer:
                    GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
                  _EagerPanRecognizer.new,
                  (recognizer) {
                    recognizer.onStart = (_) => widget.onConnectStart(side);
                    recognizer.onUpdate = (details) =>
                        widget.onConnectUpdate(details.globalPosition);
                    recognizer.onEnd = (details) =>
                        widget.onConnectEnd(details.globalPosition);
                  },
                ),
              },
              child: SizedBox(
                width: target,
                height: target,
                child: Center(
                  child: Container(
                    width: radius * 1.5,
                    height: radius * 1.5,
                    decoration: BoxDecoration(
                      color: widget.connectingFrom
                          ? palette.accent
                          : palette.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: palette.accent,
                        width: 1.6 * inverse,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pan that keeps hold of a drag inside a scroll view.
///
/// `PanGestureRecognizer` accepts at `computePanSlop` (2px with a mouse) while
/// a `Scrollable` accepts at `computeHitSlop` (1px), so the page always won a
/// vertical drag. Tying at the hit slop lets the deeper recogniser — this one —
/// keep it.
class _CardPanRecognizer extends PanGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      computeHitSlop(pointerDeviceKind, gestureSettings);

  /// Two fingers on a trackpad pan the canvas, never a card. Declining
  /// pan-zoom leaves the gesture to the board.
  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}
}

/// Wins the arena outright. Used by grips and ports, which have no competing
/// children of their own and must beat the card's pan.
class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}
}

/// A frame: a titled box that gathers cards.
class CanvasFrameBox extends StatefulWidget {
  const CanvasFrameBox({
    super.key,
    required this.frame,
    required this.palette,
    required this.zoom,
    required this.selected,
    required this.editable,
    required this.cardCount,
    required this.onTap,
    required this.onDoubleTap,
    required this.onContextMenu,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    required this.onTitleChanged,
    required this.onToggleCollapsed,
  });

  final CanvasFrame frame;
  final CanvasPalette palette;
  final double zoom;
  final bool selected;
  final bool editable;
  final int cardCount;

  final void Function(bool shift) onTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition) onContextMenu;
  final VoidCallback onDragStart;
  final void Function(Offset sceneDelta, Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;
  final void Function(CanvasHandle handle) onResizeStart;
  final void Function(CanvasHandle handle, Offset sceneDelta) onResizeUpdate;
  final VoidCallback onResizeEnd;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onToggleCollapsed;

  @override
  State<CanvasFrameBox> createState() => _CanvasFrameBoxState();
}

class _CanvasFrameBoxState extends State<CanvasFrameBox> {
  bool _hovered = false;
  bool _renaming = false;
  Offset _travel = Offset.zero;
  bool _moving = false;
  DateTime? _lastTap;
  late final TextEditingController _title =
      TextEditingController(text: widget.frame.title);
  final FocusNode _titleFocus = FocusNode(debugLabel: 'canvas_frame_title');

  @override
  void didUpdateWidget(covariant CanvasFrameBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_renaming && widget.frame.title != _title.text) {
      _title.text = widget.frame.title;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final frame = widget.frame;
    final inverse = 1 / math.max(0.0001, widget.zoom);
    final accent = palette.accentAt(frame.color);
    final radius = BorderRadius.circular(CanvasMetrics.frameRadius);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: frame.color == null
                    ? palette.sunken
                    : accent.withValues(alpha: palette.isDark ? 0.09 : 0.055),
                borderRadius: radius,
                border: Border.all(
                  color: widget.selected
                      ? accent
                      : accent.withValues(alpha: palette.isDark ? 0.4 : 0.3),
                  width: (widget.selected ? 1.8 : 1.1) * inverse,
                ),
              ),
            ),
          ),
          // The body is the drag target, so a frame is moved by its own empty
          // space as well as by its heading.
          if (widget.editable) Positioned.fill(child: _gestures()),
          // The heading sits just INSIDE the frame for the same reason the
          // grips do: hanging off the edge puts it outside the stack's own
          // box, where it is painted but can never be clicked.
          Positioned(
            left: CanvasMetrics.space3 * inverse,
            top: CanvasMetrics.space1 * inverse,
            child: Transform.scale(
              scale: inverse,
              alignment: Alignment.topLeft,
              child: _heading(palette, accent),
            ),
          ),
          if (widget.editable && (widget.selected || _hovered))
            for (final handle in CanvasHandle.values)
              _grip(handle, inverse, palette, accent),
        ],
      ),
    );
  }

  Widget _heading(CanvasPalette palette, Color accent) {
    final frame = widget.frame;
    final style = canvasLabelStyle(
      palette,
      size: 13,
      weight: FontWeight.w600,
      color: frame.color == null ? palette.textSecondary : accent,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.editable ? widget.onToggleCollapsed : null,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: AnimatedRotation(
              duration: CanvasMetrics.hover,
              turns: frame.collapsed ? -0.25 : 0,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: palette.textMuted,
              ),
            ),
          ),
        ),
        if (_renaming)
          SizedBox(
            width: 180,
            height: 22,
            child: TextField(
              controller: _title,
              focusNode: _titleFocus,
              autofocus: true,
              style: style,
              cursorColor: palette.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                hintText: LocaleKeys.canvas_frame_titleHint.tr(),
                hintStyle: style.copyWith(color: palette.textMuted),
              ),
              onSubmitted: (value) {
                widget.onTitleChanged(value);
                setState(() => _renaming = false);
              },
              onTapOutside: (_) {
                widget.onTitleChanged(_title.text);
                setState(() => _renaming = false);
              },
            ),
          )
        else
          GestureDetector(
            onTap:
                widget.editable ? () => setState(() => _renaming = true) : null,
            behavior: HitTestBehavior.opaque,
            child: Text(
              frame.title.trim().isEmpty
                  ? LocaleKeys.canvas_frame_untitled.tr()
                  : frame.title.trim(),
              style: frame.title.trim().isEmpty
                  ? style.copyWith(color: palette.textMuted)
                  : style,
            ),
          ),
        if (widget.cardCount > 0) ...[
          const SizedBox(width: 6),
          Text(
            '${widget.cardCount}',
            style: canvasLabelStyle(
              palette,
              size: 11,
              color: palette.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _gestures() {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _CardPanRecognizer:
            GestureRecognizerFactoryWithHandlers<_CardPanRecognizer>(
          _CardPanRecognizer.new,
          (recognizer) {
            recognizer.onStart = (_) {
              _travel = Offset.zero;
              _moving = false;
            };
            recognizer.onUpdate = (details) {
              _travel += details.delta;
              if (!_moving) {
                if (_travel.distance * widget.zoom < 4) {
                  return;
                }
                _moving = true;
                widget.onDragStart();
                widget.onDragUpdate(_travel, details.globalPosition);
                return;
              }
              widget.onDragUpdate(details.delta, details.globalPosition);
            };
            recognizer.onEnd = (_) {
              if (_moving) {
                widget.onDragEnd();
              } else {
                _reportTap();
              }
              _moving = false;
            };
            recognizer.onCancel = () => _moving = false;
          },
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) {
            widget.onContextMenu(event.position);
          }
        },
        child: const SizedBox.expand(),
      ),
    );
  }

  void _reportTap() {
    final now = DateTime.now();
    final previous = _lastTap;
    _lastTap = now;
    if (previous != null && now.difference(previous) < kDoubleTapTimeout) {
      _lastTap = null;
      widget.onDoubleTap();
      return;
    }
    widget.onTap(HardwareKeyboard.instance.isShiftPressed);
  }

  Widget _grip(
    CanvasHandle handle,
    double inverse,
    CanvasPalette palette,
    Color accent,
  ) {
    final size = CanvasMetrics.handleSize * inverse;
    final target = size * 2.4;
    final alignment = handle.alignment;
    return Positioned(
      left: alignment.x < 0 ? 0 : null,
      right: alignment.x > 0 ? 0 : null,
      top: alignment.y < 0 ? 0 : null,
      bottom: alignment.y > 0 ? 0 : null,
      width: alignment.x == 0 ? null : target,
      height: alignment.y == 0 ? null : target,
      child: Align(
        alignment: alignment,
        child: MouseRegion(
          cursor: handle.cursor,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _EagerPanRecognizer:
                  GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
                _EagerPanRecognizer.new,
                (recognizer) {
                  recognizer.onStart = (_) => widget.onResizeStart(handle);
                  recognizer.onUpdate =
                      (details) => widget.onResizeUpdate(handle, details.delta);
                  recognizer.onEnd = (_) => widget.onResizeEnd();
                  recognizer.onCancel = widget.onResizeEnd;
                },
              ),
            },
            child: SizedBox(
              width: alignment.x == 0 ? null : target,
              height: alignment.y == 0 ? null : target,
              child: Center(
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 1.5 * inverse),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Work out the new box when a grip is pulled.
///
/// Pure, so the minimum sizes and the anchoring behaviour can be tested
/// without a gesture.
Rect resizeCanvasRect(
  Rect rect,
  CanvasHandle handle,
  Offset delta, {
  double minimumWidth = minimumCanvasNodeWidth,
  double minimumHeight = minimumCanvasNodeHeight,
}) {
  var left = rect.left;
  var top = rect.top;
  var width = rect.width;
  var height = rect.height;

  if (handle.changesWidth) {
    if (handle.movesLeft) {
      final next = math.max(minimumWidth, width - delta.dx);
      left += width - next;
      width = next;
    } else {
      width = math.max(minimumWidth, width + delta.dx);
    }
  }
  if (handle.changesHeight) {
    if (handle.movesTop) {
      final next = math.max(minimumHeight, height - delta.dy);
      top += height - next;
      height = next;
    } else {
      height = math.max(minimumHeight, height + delta.dy);
    }
  }
  return Rect.fromLTWH(left, top, width, height);
}
