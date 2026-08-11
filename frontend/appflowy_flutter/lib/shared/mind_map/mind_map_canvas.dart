import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'mind_map_controller.dart';
import 'mind_map_layout.dart';
import 'mind_map_model.dart';
import 'mind_map_theme.dart';

/// The interactive mind map surface.
///
/// Nodes are widgets and connectors are one painted layer, so a node can be
/// typed into, hovered and dragged without the canvas being rebuilt for it —
/// selection and hover ride on their own notifiers, and only the branch that
/// actually changed is laid out again.
class MindMapCanvas extends StatefulWidget {
  const MindMapCanvas({
    super.key,
    required this.controller,
    this.editable = true,
    this.showControls = true,
    this.padding = EdgeInsets.zero,
    this.autofocus = false,
    this.onRequestFullscreen,
  });

  final MindMapController controller;
  final bool editable;
  final bool showControls;
  final EdgeInsets padding;
  final bool autofocus;
  final VoidCallback? onRequestFullscreen;

  @override
  State<MindMapCanvas> createState() => MindMapCanvasState();
}

class MindMapCanvasState extends State<MindMapCanvas>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Matrix4> _transform =
      ValueNotifier<Matrix4>(Matrix4.identity());
  final ValueNotifier<String?> _hovered = ValueNotifier<String?>(null);
  final FocusNode _focus = FocusNode(debugLabel: 'mind_map_canvas');
  final GlobalKey _viewportKey = GlobalKey();

  late Ticker _ticker;
  Offset _velocity = Offset.zero;
  Duration _lastTick = Duration.zero;

  MindMapLayout _layout = MindMapLayout.empty;
  MindMapDocument? _laidOutFor;
  MindMapLayoutMode? _laidOutMode;
  String? _laidOutEditing;
  Size _viewportSize = Size.zero;
  bool _hasFitted = false;
  bool _engaged = false;
  String? _menuId;
  Offset? _menuAt;
  bool _spaceHeld = false;
  String? _draggingId;
  String? _dropTargetId;

  /// The zoom cluster is only there when it is being reached for.
  bool _controlsShown = false;
  bool _controlsHovered = false;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant MindMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _laidOutFor = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _controlsTimer?.cancel();
    _ticker.dispose();
    _transform.dispose();
    _hovered.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Shows the zoom cluster and starts counting down to hiding it again.
  void _revealControls() {
    _controlsTimer?.cancel();
    if (!_controlsShown && mounted) {
      setState(() => _controlsShown = true);
    }
    _controlsTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && !_controlsHovered) {
        setState(() => _controlsShown = false);
      }
    });
  }

  // -- viewport ------------------------------------------------------------

  double get _scale => _transform.value.getMaxScaleOnAxis();

  Offset get _translation {
    final storage = _transform.value.storage;
    return Offset(storage[12], storage[13]);
  }

  void _setViewport(double scale, Offset translation) {
    final clamped = scale.clamp(
      MindMapCanvasMetrics.minimumScale,
      MindMapCanvasMetrics.maximumScale,
    );
    _transform.value = Matrix4.identity()
      ..translate(translation.dx, translation.dy)
      ..scale(clamped, clamped, 1.0);
  }

  void _panBy(Offset delta) => _setViewport(_scale, _translation + delta);

  void _zoomAbout(Offset focalPoint, double factor) {
    final scale = _scale;
    final next = (scale * factor).clamp(
      MindMapCanvasMetrics.minimumScale,
      MindMapCanvasMetrics.maximumScale,
    );
    if (next == scale) {
      return;
    }
    // Keep whatever is under the pointer under the pointer.
    final scene = (focalPoint - _translation) / scale;
    _setViewport(next, focalPoint - scene * next);
  }

  /// Scales the whole map to fit and centres it.
  void fitToScreen() {
    // A viewport of no size gives a scale of zero, which lands the map far
    // off screen and reads as an empty canvas.
    if (_layout.size.isEmpty ||
        _viewportSize.width < 2 ||
        _viewportSize.height < 2) {
      return;
    }
    final scale = math
        .min(
          1.0,
          math.min(
            _viewportSize.width / _layout.size.width,
            _viewportSize.height / _layout.size.height,
          ),
        )
        .clamp(MindMapCanvasMetrics.minimumScale, 1.0);
    _hasFitted = true;
    _setViewport(
      scale,
      Offset(
        (_viewportSize.width - _layout.size.width * scale) / 2,
        (_viewportSize.height - _layout.size.height * scale) / 2,
      ),
    );
  }

  /// Puts the root back in the middle without changing the zoom.
  void centre() {
    final root = _layout.placementFor(widget.controller.document.root.id);
    if (root == null || _viewportSize.isEmpty) {
      return;
    }
    final scale = _scale;
    _setViewport(
      scale,
      Offset(
        _viewportSize.width / 2 - root.rect.center.dx * scale,
        _viewportSize.height / 2 - root.rect.center.dy * scale,
      ),
    );
  }

  void resetZoom() {
    final centreScene = _viewportSize.isEmpty
        ? Offset.zero
        : (Offset(_viewportSize.width / 2, _viewportSize.height / 2) -
                _translation) /
            _scale;
    _setViewport(
      1,
      Offset(_viewportSize.width / 2, _viewportSize.height / 2) - centreScene,
    );
  }

  void zoomBy(double factor) => _zoomAbout(
        Offset(_viewportSize.width / 2, _viewportSize.height / 2),
        factor,
      );

  // -- inertia -------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final delta = _lastTick == Duration.zero
        ? const Duration(milliseconds: 16)
        : elapsed - _lastTick;
    _lastTick = elapsed;
    final seconds = delta.inMicroseconds / Duration.microsecondsPerSecond;
    if (_velocity.distance < 24) {
      _velocity = Offset.zero;
      _ticker.stop();
      _lastTick = Duration.zero;
      return;
    }
    _panBy(_velocity * seconds);
    // A gentle exponential decay reads like the rest of the application's
    // scrolling rather than an abrupt stop.
    _velocity = _velocity * math.pow(0.0025, seconds).toDouble();
  }

  void _startInertia(Offset velocity) {
    _velocity = velocity;
    if (velocity.distance < 60) {
      _velocity = Offset.zero;
      return;
    }
    _lastTick = Duration.zero;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _stopInertia() {
    _velocity = Offset.zero;
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _lastTick = Duration.zero;
  }

  // -- layout --------------------------------------------------------------

  MindMapLayout _ensureLayout(BuildContext context) {
    final controller = widget.controller;
    // The text being typed is not in the document yet, so it has to take part
    // in the key or a growing node would keep its old, too-small box.
    final editingKey = '${controller.editingId}|${controller.editingText}';
    if (identical(_laidOutFor, controller.document) &&
        _laidOutMode == controller.mode &&
        _laidOutEditing == editingKey) {
      return _layout;
    }
    _layout = layoutMindMap(
      controller.document,
      _sizerFor(context),
      mode: controller.mode,
    );
    _laidOutFor = controller.document;
    _laidOutMode = controller.mode;
    _laidOutEditing = editingKey;
    return _layout;
  }

  MindMapNodeSizer _sizerFor(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final controller = widget.controller;
    final cache = <String, Size>{};
    return (node, depth) {
      final live =
          controller.editingId == node.id ? controller.editingText : node.text;
      final key = '$live|$depth';
      final hit = cache[key];
      if (hit != null) {
        return hit;
      }
      final text = live.isEmpty ? ' ' : live;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(
            fontSize: MindMapCanvasMetrics.fontSizeFor(depth),
            fontWeight: MindMapCanvasMetrics.weightFor(depth),
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: MindMapCanvasMetrics.maximumNodeLines,
      )..layout(
          maxWidth: MindMapCanvasMetrics.maximumNodeWidth -
              MindMapCanvasMetrics.nodePaddingX * 2,
        );
      final size = Size(
        math.max(
          MindMapCanvasMetrics.minimumNodeWidth,
          painter.width + MindMapCanvasMetrics.nodePaddingX * 2,
        ),
        math.max(
          MindMapCanvasMetrics.minimumNodeHeight,
          painter.height + MindMapCanvasMetrics.nodePaddingY * 2,
        ),
      );
      painter.dispose();
      cache[key] = size;
      return size;
    };
  }

  // -- interaction ---------------------------------------------------------

  Offset _toScene(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return global;
    }
    final local = box.globalToLocal(global);
    return (local - _translation) / _scale;
  }

  void _engage() {
    if (!_engaged) {
      setState(() => _engaged = true);
    }
    if (!_focus.hasFocus) {
      _focus.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final controller = widget.controller;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space &&
        controller.editingId == null) {
      _spaceHeld = true;
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.space) {
      _spaceHeld = false;
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (controller.editingId != null) {
      return KeyEventResult.ignored;
    }

    final selected = controller.selectedId ?? controller.document.root.id;
    final key = event.logicalKey;
    final control = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (control && key == LogicalKeyboardKey.keyZ) {
      HardwareKeyboard.instance.isShiftPressed
          ? controller.redo()
          : controller.undo();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyY) {
      controller.redo();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.digit0) {
      resetZoom();
      return KeyEventResult.handled;
    }
    if (control &&
        (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add)) {
      zoomBy(1.2);
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.minus) {
      zoomBy(1 / 1.2);
      return KeyEventResult.handled;
    }

    if (!widget.editable) {
      return KeyEventResult.ignored;
    }

    switch (key) {
      case LogicalKeyboardKey.tab:
        controller.addChild(selected);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (HardwareKeyboard.instance.isShiftPressed) {
          controller.beginEditing(selected);
        } else {
          controller.addSibling(selected);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f2:
        controller.beginEditing(selected);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        controller.remove(selected);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        controller.moveSelection(MindMapDirection.up, _layout);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        controller.moveSelection(MindMapDirection.down, _layout);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        controller.moveSelection(MindMapDirection.left, _layout);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        controller.moveSelection(MindMapDirection.right, _layout);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        controller.select(null);
        setState(() => _engaged = false);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // -- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = MindMapPalette.of(context);
    final controller = widget.controller;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = _ensureLayout(context);
        if (_viewportSize != size) {
          _viewportSize = size;
          // The first layout pass can hand out a box of no height; wait for a
          // real one before framing the map, or it ends up off screen.
          if (!_hasFitted && size.width > 2 && size.height > 2) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                fitToScreen();
              }
            });
          }
        }

        return Focus(
          focusNode: _focus,
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          onFocusChange: (value) {
            if (!value && _engaged) {
              setState(() => _engaged = false);
            }
          },
          child: Listener(
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomStart: (_) => _stopInertia(),
            onPointerPanZoomUpdate: (event) {
              _engage();
              _panBy(event.panDelta);
              if ((event.scale - 1).abs() > 0.01) {
                _zoomAbout(event.localPosition, 1 + (event.scale - 1) * 0.12);
              }
            },
            child: MouseRegion(
              cursor: _spaceHeld ? SystemMouseCursors.grab : MouseCursor.defer,
              onEnter: (_) => _revealControls(),
              onHover: (_) => _revealControls(),
              onExit: (_) {
                _controlsHovered = false;
                _revealControls();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _engage(),
                onTap: () {
                  _closeContextMenu();
                  controller.select(null);
                },
                onScaleStart: (_) => _stopInertia(),
                onScaleUpdate: (details) {
                  _engage();
                  _closeContextMenu();
                  _revealControls();
                  if (details.scale != 1) {
                    _zoomAbout(details.localFocalPoint, details.scale);
                  } else {
                    _panBy(details.focalPointDelta);
                  }
                },
                onScaleEnd: (details) =>
                    _startInertia(details.velocity.pixelsPerSecond),
                child: ClipRect(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: palette.canvas),
                    child: Stack(
                      key: _viewportKey,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: ValueListenableBuilder<Matrix4>(
                            valueListenable: _transform,
                            builder: (context, matrix, _) => Transform(
                              transform: matrix,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  RepaintBoundary(
                                    child: CustomPaint(
                                      size: layout.size,
                                      painter: _MindMapConnectors(
                                        layout: layout,
                                        palette: palette,
                                      ),
                                    ),
                                  ),
                                  ..._buildNodes(layout, palette),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (widget.editable && controller.selectedId != null)
                          _buildToolbar(layout, palette),
                        if (widget.showControls)
                          _buildControls(palette, layout),
                        if (_menuId != null) _buildContextMenu(palette),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final control = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    // Until the canvas has been clicked into, the page keeps its scroll —
    // that boundary is what stops a map swallowing a document.
    if (!_engaged && !control) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _stopInertia();
      _revealControls();
      final factor = event.scrollDelta.dy > 0 ? 1 / 1.12 : 1.12;
      _zoomAbout(event.localPosition, factor);
    });
  }

  List<Widget> _buildNodes(MindMapLayout layout, MindMapPalette palette) {
    final controller = widget.controller;
    return [
      for (final placement in layout.placements)
        Positioned(
          left: placement.rect.left,
          top: placement.rect.top,
          width: placement.rect.width,
          height: placement.rect.height,
          child: _MindMapNodeView(
            key: ValueKey(placement.node.id),
            placement: placement,
            palette: palette,
            controller: controller,
            hovered: _hovered,
            editable: widget.editable,
            isDropTarget: _dropTargetId == placement.node.id,
            onDragStart: (id) => setState(() => _draggingId = id),
            onDragUpdate: (global) {
              final scene = _toScene(global);
              final target = layout.hitTest(scene);
              final id = target?.node.id;
              final draggingId = _draggingId;
              final valid = id != null &&
                  draggingId != null &&
                  id != draggingId &&
                  !controller.document.isAncestor(draggingId, id);
              final next = valid ? id : null;
              if (_dropTargetId != next) {
                setState(() => _dropTargetId = next);
              }
            },
            onDragEnd: () {
              final moving = _draggingId;
              final target = _dropTargetId;
              if (moving != null && target != null) {
                controller.move(moving, target);
              }
              setState(() {
                _draggingId = null;
                _dropTargetId = null;
              });
            },
            onContextMenu: _openContextMenu,
          ),
        ),
    ];
  }

  void _openContextMenu(String id, Offset globalPosition) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    _engage();
    widget.controller.select(id);
    setState(() {
      _menuId = id;
      _menuAt = box.globalToLocal(globalPosition);
    });
  }

  void _closeContextMenu() {
    if (_menuId != null) {
      setState(() {
        _menuId = null;
        _menuAt = null;
      });
    }
  }

  Widget _buildContextMenu(MindMapPalette palette) {
    final id = _menuId;
    final at = _menuAt;
    final node = id == null ? null : widget.controller.document.find(id);
    if (node == null || at == null) {
      return const SizedBox.shrink();
    }
    const width = 218.0;
    final height = _MindMapContextMenu.heightFor(
      node,
      isRoot: node.id == widget.controller.document.root.id,
    );
    // The menu opens from the pointer but is nudged back inside the canvas
    // rather than being clipped by its edge.
    final left = math.max(
      6.0,
      math.min(at.dx, math.max(6.0, _viewportSize.width - width - 6)),
    );
    final top = math.max(
      6.0,
      math.min(at.dy, math.max(6.0, _viewportSize.height - height - 6)),
    );
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeContextMenu,
              onSecondaryTap: _closeContextMenu,
              child: const SizedBox.shrink(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: _MindMapContextMenu(
              controller: widget.controller,
              palette: palette,
              node: node,
              isRoot: node.id == widget.controller.document.root.id,
              onClose: _closeContextMenu,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(MindMapLayout layout, MindMapPalette palette) {
    final controller = widget.controller;
    final selected = controller.selectedId;
    final placement = selected == null ? null : layout.placementFor(selected);
    if (placement == null || controller.editingId != null) {
      return const SizedBox.shrink();
    }
    final scale = _scale;
    final origin = _translation + placement.rect.topCenter * scale;
    return Positioned(
      left: origin.dx - 132,
      top: math.max(6, origin.dy - 46),
      width: 264,
      child: Center(
        child: MindMapNodeToolbar(
          controller: controller,
          palette: palette,
          node: placement.node,
          isRoot: placement.node.id == controller.document.root.id,
        ),
      ),
    );
  }

  Widget _buildControls(MindMapPalette palette, MindMapLayout layout) =>
      Positioned(
        right: 12,
        bottom: 12,
        child: MouseRegion(
          onEnter: (_) {
            _controlsHovered = true;
            _revealControls();
          },
          onExit: (_) {
            _controlsHovered = false;
            _revealControls();
          },
          child: AnimatedOpacity(
            opacity: _controlsShown ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: !_controlsShown,
              child: MindMapViewportControls(
                palette: palette,
                onZoomIn: () => zoomBy(1.2),
                onZoomOut: () => zoomBy(1 / 1.2),
                onFit: fitToScreen,
                onCentre: centre,
                onReset: resetZoom,
                onFullscreen: widget.onRequestFullscreen,
                scale: _scale,
                transform: _transform,
              ),
            ),
          ),
        ),
      );
}

/// The connectors, painted as one layer under the nodes.
class _MindMapConnectors extends CustomPainter {
  const _MindMapConnectors({required this.layout, required this.palette});

  final MindMapLayout layout;
  final MindMapPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in layout.links) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        // A branch thins as it grows, which is what makes a big map legible.
        ..strokeWidth = link.depth <= 1 ? 2.6 : (link.depth == 2 ? 1.9 : 1.5)
        ..color = palette
            .branchAt(link.colorIndex)
            .withValues(alpha: link.depth <= 1 ? 0.85 : 0.62);
      final path = Path()
        ..moveTo(link.start.dx, link.start.dy)
        ..cubicTo(
          link.control1.dx,
          link.control1.dy,
          link.control2.dx,
          link.control2.dy,
          link.end.dx,
          link.end.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapConnectors oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.palette != palette;
}

/// One node: a rounded card that can be selected, renamed and dragged.
class _MindMapNodeView extends StatefulWidget {
  const _MindMapNodeView({
    super.key,
    required this.placement,
    required this.palette,
    required this.controller,
    required this.hovered,
    required this.editable,
    required this.isDropTarget,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onContextMenu,
  });

  final MindMapPlacement placement;
  final MindMapPalette palette;
  final MindMapController controller;
  final ValueNotifier<String?> hovered;
  final bool editable;
  final bool isDropTarget;
  final ValueChanged<String> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final void Function(String id, Offset globalPosition) onContextMenu;

  @override
  State<_MindMapNodeView> createState() => _MindMapNodeViewState();
}

class _MindMapNodeViewState extends State<_MindMapNodeView> {
  TextEditingController? _text;
  FocusNode? _focus;

  @override
  void dispose() {
    _text?.dispose();
    _focus?.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _text?.text;
    if (text != null) {
      widget.controller.rename(widget.placement.node.id, text.trim());
    }
    widget.controller.endEditing();
  }

  @override
  Widget build(BuildContext context) {
    final placement = widget.placement;
    final palette = widget.palette;
    final controller = widget.controller;
    final isRoot = placement.depth == 0;
    final selected = controller.selectedId == placement.node.id;
    final editing = controller.editingId == placement.node.id;
    final accent = palette.branchAt(
      MindMapMetrics.accentFor(placement.node, placement.depth),
    );

    if (editing && _text == null) {
      _text = TextEditingController(text: placement.node.text)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: placement.node.text.length,
        );
      _focus = FocusNode(debugLabel: 'mind_map_node');
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focus?.requestFocus());
    } else if (!editing && _text != null) {
      final text = _text;
      final focus = _focus;
      _text = null;
      _focus = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        text?.dispose();
        focus?.dispose();
      });
    }

    return ValueListenableBuilder<String?>(
      valueListenable: widget.hovered,
      builder: (context, hoveredId, _) {
        final hovered = hoveredId == placement.node.id;
        // A colour is a choice, so it paints the box rather than hinting at
        // it from the edge; the branch tint alone stays on the connectors.
        final chosen = placement.node.colorIndex != null;
        final Color fill;
        if (isRoot) {
          fill = chosen ? accent : palette.rootFill;
        } else if (chosen) {
          fill = palette.fillFor(accent, hovered: hovered);
        } else {
          fill = hovered ? palette.nodeHover : palette.node;
        }
        final ink = isRoot && !chosen ? palette.onRoot : palette.inkOn(fill);
        return MouseRegion(
          cursor: widget.editable
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => widget.hovered.value = placement.node.id,
          onExit: (_) {
            if (widget.hovered.value == placement.node.id) {
              widget.hovered.value = null;
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => controller.select(placement.node.id),
            onDoubleTap: widget.editable
                ? () => controller.beginEditing(placement.node.id)
                : null,
            onSecondaryTapDown: widget.editable
                ? (details) => widget.onContextMenu(
                      placement.node.id,
                      details.globalPosition,
                    )
                : null,
            onLongPressStart: widget.editable
                ? (details) => widget.onContextMenu(
                      placement.node.id,
                      details.globalPosition,
                    )
                : null,
            onPanStart: widget.editable && !isRoot
                ? (_) => widget.onDragStart(placement.node.id)
                : null,
            onPanUpdate: widget.editable && !isRoot
                ? (details) => widget.onDragUpdate(details.globalPosition)
                : null,
            onPanEnd:
                widget.editable && !isRoot ? (_) => widget.onDragEnd() : null,
            child: AnimatedContainer(
              duration: MindMapCanvasMetrics.motion,
              curve: MindMapCanvasMetrics.curve,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(
                  isRoot
                      ? MindMapCanvasMetrics.rootRadius
                      : MindMapCanvasMetrics.nodeRadius,
                ),
                border: Border.all(
                  color: widget.isDropTarget
                      ? palette.accent
                      : selected
                          ? palette.selection
                          : chosen
                              ? accent.withValues(alpha: 0.8)
                              : isRoot
                                  ? Colors.transparent
                                  : accent.withValues(alpha: 0.35),
                  width: selected || widget.isDropTarget ? 2 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: hovered || selected ? 12 : 7,
                    offset: Offset(0, hovered || selected ? 4 : 2),
                    spreadRadius: -2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: MindMapCanvasMetrics.nodePaddingX,
                vertical: MindMapCanvasMetrics.nodePaddingY,
              ),
              child: editing
                  ? _buildField(placement, palette, ink)
                  : _buildLabel(placement, palette, ink),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLabel(
    MindMapPlacement placement,
    MindMapPalette palette,
    Color ink,
  ) {
    final style = TextStyle(
      fontSize: MindMapCanvasMetrics.fontSizeFor(placement.depth),
      fontWeight: MindMapCanvasMetrics.weightFor(placement.depth),
      height: 1.3,
      color: ink,
    );
    return Semantics(
      label: placement.node.text,
      selected: widget.controller.selectedId == placement.node.id,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Text(
              placement.node.text.isEmpty ? ' ' : placement.node.text,
              textAlign: TextAlign.center,
              maxLines: MindMapCanvasMetrics.maximumNodeLines,
              style: style,
            ),
          ),
          if (placement.node.children.isNotEmpty)
            Positioned(
              right: placement.side == MindMapSide.right
                  ? -MindMapCanvasMetrics.nodePaddingX - 12
                  : null,
              left: placement.side == MindMapSide.left
                  ? -MindMapCanvasMetrics.nodePaddingX - 12
                  : null,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CollapseMarker(
                  collapsed: placement.node.collapsed,
                  count: placement.hiddenChildren,
                  palette: palette,
                  onTap: () =>
                      widget.controller.toggleCollapsed(placement.node.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildField(
    MindMapPlacement placement,
    MindMapPalette palette,
    Color ink,
  ) {
    return TextField(
      controller: _text,
      focusNode: _focus,
      autofocus: true,
      textAlign: TextAlign.center,
      maxLines: MindMapCanvasMetrics.maximumNodeLines,
      minLines: 1,
      cursorColor: ink,
      cursorWidth: 1.6,
      style: TextStyle(
        fontSize: MindMapCanvasMetrics.fontSizeFor(placement.depth),
        fontWeight: MindMapCanvasMetrics.weightFor(placement.depth),
        height: 1.3,
        color: ink,
      ),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        hoverColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
      ),
      // Reported live so the node is re-measured and grows with the words.
      onChanged: widget.controller.reportEditingText,
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _commit(),
      onEditingComplete: _commit,
    );
  }
}

class _CollapseMarker extends StatelessWidget {
  const _CollapseMarker({
    required this.collapsed,
    required this.count,
    required this.palette,
    required this.onTap,
  });

  final bool collapsed;
  final int count;
  final MindMapPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: collapsed ? 'Expand $count nodes' : 'Collapse branch',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18),
            height: 18,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 5 : 0),
            decoration: BoxDecoration(
              color: palette.node,
              shape: collapsed ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: collapsed ? BorderRadius.circular(9) : null,
              border: Border.all(color: palette.line, width: 1.2),
            ),
            alignment: Alignment.center,
            child: collapsed
                ? Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted,
                    ),
                  )
                : Icon(
                    Icons.remove_rounded,
                    size: 11,
                    color: palette.textMuted,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The contextual toolbar that appears above the selected node.
class MindMapNodeToolbar extends StatelessWidget {
  const MindMapNodeToolbar({
    super.key,
    required this.controller,
    required this.palette,
    required this.node,
    required this.isRoot,
  });

  final MindMapController controller;
  final MindMapPalette palette;
  final MindMapNode node;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: palette.node,
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 16,
              offset: const Offset(0, 4),
              spreadRadius: -3,
            ),
          ],
          border: Border.all(color: palette.line.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              icon: Icons.subdirectory_arrow_right_rounded,
              tooltip: 'Add child  ·  Tab',
              palette: palette,
              onTap: () => controller.addChild(node.id),
            ),
            if (!isRoot)
              _ToolbarButton(
                icon: Icons.add_rounded,
                tooltip: 'Add sibling  ·  Enter',
                palette: palette,
                onTap: () => controller.addSibling(node.id),
              ),
            _ToolbarButton(
              icon: Icons.edit_rounded,
              tooltip: 'Rename  ·  F2',
              palette: palette,
              onTap: () => controller.beginEditing(node.id),
            ),
            _ColourButton(
              palette: palette,
              selected: node.colorIndex,
              onSelected: (index) => controller.setColor(node.id, index),
            ),
            if (node.children.isNotEmpty)
              _ToolbarButton(
                icon: node.collapsed
                    ? Icons.unfold_more_rounded
                    : Icons.unfold_less_rounded,
                tooltip: node.collapsed ? 'Expand' : 'Collapse',
                palette: palette,
                onTap: () => controller.toggleCollapsed(node.id),
              ),
            if (!isRoot)
              _ToolbarButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete  ·  Del',
                palette: palette,
                destructive: true,
                onTap: () => controller.remove(node.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final MindMapPalette palette;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final ink = widget.destructive
        ? (palette.isDark ? const Color(0xFFE58B8B) : const Color(0xFFC0554F))
        : _hovered
            ? palette.text
            : palette.textMuted;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 380),
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MindMapCanvasMetrics.motion,
              curve: MindMapCanvasMetrics.curve,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _hovered
                    ? palette.nodeHover
                    : palette.nodeHover.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(widget.icon, size: 15, color: ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColourButton extends StatelessWidget {
  const _ColourButton({
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final MindMapPalette palette;
  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    // A sentinel stands in for "no colour", because a popup menu treats a
    // null result as a dismissal and would never report the choice.
    const clear = -1;
    return PopupMenuButton<int>(
      tooltip: 'Colour',
      padding: EdgeInsets.zero,
      color: palette.node,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: PopupMenuPosition.under,
      onSelected: (value) => onSelected(value == clear ? null : value),
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          height: 40,
          padding: EdgeInsets.zero,
          enabled: false,
          child: _SwatchRow(
            palette: palette,
            selected: selected,
            onSelected: (index) =>
                Navigator.of(context).pop<int>(index ?? clear),
          ),
        ),
      ],
      child: SizedBox(
        width: 26,
        height: 26,
        child: Center(
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: selected == null
                  ? palette.textMuted
                  : palette.branchAt(selected!),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// The right-click menu for a node.
///
/// It carries the same actions as the hovering toolbar, written out, so the
/// gesture people already have in their hands leads somewhere.
class _MindMapContextMenu extends StatelessWidget {
  const _MindMapContextMenu({
    required this.controller,
    required this.palette,
    required this.node,
    required this.isRoot,
    required this.onClose,
  });

  static const double _rowHeight = 30;
  static const double _swatchRow = 40;
  static const double _padding = 12;
  static const double _divider = 9;

  final MindMapController controller;
  final MindMapPalette palette;
  final MindMapNode node;
  final bool isRoot;
  final VoidCallback onClose;

  static double heightFor(MindMapNode node, {required bool isRoot}) {
    var rows = 2; // add child, rename
    if (!isRoot) {
      rows += 1; // add sibling
    }
    if (node.children.isNotEmpty) {
      rows += 2; // collapse, collapse everything
    }
    if (!isRoot) {
      rows += 1; // delete
    }
    return _padding + rows * _rowHeight + _swatchRow + _divider * 2;
  }

  void _run(VoidCallback action) {
    action();
    onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: palette.node,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.line.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 22,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuRow(
              palette: palette,
              icon: Icons.subdirectory_arrow_right_rounded,
              label: 'Add child',
              shortcut: 'Tab',
              onTap: () => _run(() => controller.addChild(node.id)),
            ),
            if (!isRoot)
              _MenuRow(
                palette: palette,
                icon: Icons.add_rounded,
                label: 'Add sibling',
                shortcut: 'Enter',
                onTap: () => _run(() => controller.addSibling(node.id)),
              ),
            _MenuRow(
              palette: palette,
              icon: Icons.edit_rounded,
              label: 'Rename',
              shortcut: 'F2',
              onTap: () => _run(() => controller.beginEditing(node.id)),
            ),
            _MenuDivider(palette: palette),
            _SwatchRow(
              palette: palette,
              selected: node.colorIndex,
              onSelected: (index) =>
                  _run(() => controller.setColor(node.id, index)),
            ),
            if (node.children.isNotEmpty) ...[
              _MenuDivider(palette: palette),
              _MenuRow(
                palette: palette,
                icon: node.collapsed
                    ? Icons.unfold_more_rounded
                    : Icons.unfold_less_rounded,
                label: node.collapsed ? 'Expand' : 'Collapse',
                onTap: () => _run(() => controller.toggleCollapsed(node.id)),
              ),
              _MenuRow(
                palette: palette,
                icon: Icons.account_tree_outlined,
                label: node.collapsed ? 'Expand all' : 'Collapse all',
                onTap: () => _run(
                  () => controller.setCollapsedEverywhere(
                    collapsed: !node.collapsed,
                  ),
                ),
              ),
            ],
            if (!isRoot) ...[
              _MenuDivider(palette: palette),
              _MenuRow(
                palette: palette,
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                shortcut: 'Del',
                destructive: true,
                onTap: () => _run(() => controller.remove(node.id)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider({required this.palette});

  final MindMapPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: ColoredBox(
          color: palette.line.withValues(alpha: 0.35),
          child: const SizedBox(height: 1, width: double.infinity),
        ),
      );
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.destructive = false,
  });

  final MindMapPalette palette;
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final ink = widget.destructive
        ? (palette.isDark ? const Color(0xFFE58B8B) : const Color(0xFFC0554F))
        : palette.text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? palette.nodeHover
                  : palette.nodeHover.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 15, color: ink),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(fontSize: 13, color: ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.shortcut != null)
                  Text(
                    widget.shortcut!,
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The colour choices, laid out in the menu rather than behind another one.
class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final MindMapPalette palette;
  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (var i = 0; i < palette.branches.length; i++)
              _Swatch(
                colour: palette.branchAt(i),
                palette: palette,
                selected: selected == i,
                onTap: () => onSelected(i),
              ),
            _Swatch(
              colour: palette.nodeHover,
              palette: palette,
              selected: selected == null,
              icon: Icons.format_color_reset_rounded,
              onTap: () => onSelected(null),
            ),
          ],
        ),
      );
}

class _Swatch extends StatefulWidget {
  const _Swatch({
    required this.colour,
    required this.palette,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final Color colour;
  final MindMapPalette palette;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _hovered ? 1.12 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: widget.colour,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.selected
                    ? palette.text
                    : palette.line.withValues(alpha: 0.5),
                width: widget.selected ? 2 : 1,
              ),
            ),
            child: widget.icon == null
                ? null
                : Icon(widget.icon, size: 11, color: palette.textMuted),
          ),
        ),
      ),
    );
  }
}

/// The zoom cluster in the corner of the canvas.
class MindMapViewportControls extends StatelessWidget {
  const MindMapViewportControls({
    super.key,
    required this.palette,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onCentre,
    required this.onReset,
    required this.scale,
    required this.transform,
    this.onFullscreen,
  });

  final MindMapPalette palette;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onCentre;
  final VoidCallback onReset;
  final VoidCallback? onFullscreen;
  final double scale;
  final ValueNotifier<Matrix4> transform;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.node.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 14,
            offset: const Offset(0, 3),
            spreadRadius: -3,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolbarButton(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom out',
            palette: palette,
            onTap: onZoomOut,
          ),
          ValueListenableBuilder<Matrix4>(
            valueListenable: transform,
            builder: (context, matrix, _) => GestureDetector(
              onTap: onReset,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 46,
                child: Center(
                  child: Text(
                    '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _ToolbarButton(
            icon: Icons.add_rounded,
            tooltip: 'Zoom in',
            palette: palette,
            onTap: onZoomIn,
          ),
          _ToolbarButton(
            icon: Icons.center_focus_strong_rounded,
            tooltip: 'Centre',
            palette: palette,
            onTap: onCentre,
          ),
          _ToolbarButton(
            icon: Icons.fit_screen_rounded,
            tooltip: 'Fit to screen',
            palette: palette,
            onTap: onFit,
          ),
          if (onFullscreen != null)
            _ToolbarButton(
              icon: Icons.open_in_full_rounded,
              tooltip: 'Fullscreen',
              palette: palette,
              onTap: onFullscreen!,
            ),
        ],
      ),
    );
  }
}
