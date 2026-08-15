import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_card.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_chrome.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_menus.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_node_body.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_painters.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_setup.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_view_resolver.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_geometry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_layout.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// The infinite surface.
///
/// Everything that happens on a canvas happens here: the camera, the
/// selection, dragging, resizing, connecting, drawing, framing and the
/// keyboard. The cards themselves are widgets in one transformed layer, and
/// only the ones on screen are built.
class CanvasBoard extends StatefulWidget {
  const CanvasBoard({
    super.key,
    required this.controller,
    this.editable = true,
    this.embedded = false,
    this.showChrome = true,
    this.onOpenView,
    this.onPickView,
    this.onCreatePage,
    this.onExport,
    this.onOpenStandalone,
  });

  final CanvasController controller;

  /// A canvas inside a locked page, or a preview, is read only.
  final bool editable;

  /// An embedded canvas leaves the page's scrolling alone until it has been
  /// clicked into, and hides the chrome it has no room for.
  final bool embedded;

  final bool showChrome;

  /// Open the workspace object a card points at.
  final void Function(ViewPB view)? onOpenView;

  /// Ask for an object to point a card at.
  final Future<ViewPB?> Function(CanvasNodeKind kind)? onPickView;

  /// Turn a card or a frame into a real page.
  final Future<ViewPB?> Function(String title, String body)? onCreatePage;

  final VoidCallback? onExport;

  /// Only an embedded canvas has somewhere else to go.
  final VoidCallback? onOpenStandalone;

  @override
  State<CanvasBoard> createState() => CanvasBoardState();
}

class CanvasBoardState extends State<CanvasBoard> {
  CanvasController get _controller => widget.controller;

  final CanvasViewResolver _resolver = CanvasViewResolver();
  final FocusNode _focus = FocusNode(debugLabel: 'canvas_board');
  final GlobalKey _surfaceKey = GlobalKey();

  CanvasCamera _camera = const CanvasCamera();
  Size _viewport = Size.zero;
  bool _readViewport = false;

  /// An embedded canvas only claims the wheel once it has been clicked into.
  bool _engaged = false;

  // Interaction
  Offset? _marqueeAnchor;
  Rect? _marquee;
  bool _marqueeAdds = false;
  List<CanvasGuide> _guides = const <CanvasGuide>[];
  Map<String, Rect> _dragOrigin = const <String, Rect>{};

  /// Where every object being dragged started, so each frame of the drag is
  /// applied as an absolute position rather than as an accumulated delta.
  Map<String, Offset> _dragStart = const <String, Offset>{};

  /// The document as it was before the gesture began, so the whole gesture is
  /// one thing to undo.
  CanvasDocument? _gestureBefore;

  Offset _dragTravel = Offset.zero;
  Rect? _resizeOrigin;
  String? _resizeId;
  String? _connectFrom;
  CanvasSide _connectSide = CanvasSide.auto;
  Offset? _connectPoint;
  String? _connectTarget;
  Rect? _dropTarget;
  List<Offset>? _stroke;
  Offset? _frameAnchor;
  Rect? _framing;
  bool _panning = false;

  // Find
  bool _searching = false;
  String _query = '';
  List<CanvasSearchHit> _hits = const <CanvasSearchHit>[];
  int _hitIndex = 0;

  /// What was last copied on this canvas. Kept in the widget rather than on the
  /// system clipboard because a card is a structure, not text.
  static CanvasDocument? _clipboard;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onDocumentChanged);
    _resolver.addListener(_onResolved);
  }

  @override
  void didUpdateWidget(covariant CanvasBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onDocumentChanged);
      widget.controller.addListener(_onDocumentChanged);
      _readViewport = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onDocumentChanged);
    _resolver
      ..removeListener(_onResolved)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onDocumentChanged() {
    if (mounted) {
      setState(() {
        if (_query.trim().isNotEmpty) {
          _hits = searchCanvas(_controller.document, _query);
        }
      });
    }
  }

  void _onResolved() {
    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------

  void _setCamera(CanvasCamera camera, {bool remember = true}) {
    if (camera == _camera) {
      return;
    }
    setState(() => _camera = camera);
    if (remember) {
      _controller.rememberViewport(camera);
    }
  }

  void _pan(Offset screenDelta) => _setCamera(_camera.panned(screenDelta));

  void _zoomBy(double factor, {Offset? screenFocus}) => _setCamera(
        _camera.zoomedBy(
          factor,
          screenFocus:
              screenFocus ?? Offset(_viewport.width / 2, _viewport.height / 2),
        ),
      );

  /// Frame everything, or the selection when there is one.
  void zoomToFit({bool selectionOnly = false}) {
    final document = _controller.document;
    final box = selectionOnly && _controller.hasSelection
        ? document.boundsOf(_controller.selection)
        : document.bounds;
    if (box.isEmpty) {
      _setCamera(const CanvasCamera());
      return;
    }
    _setCamera(CanvasCamera.fittedTo(box, _viewport));
  }

  void resetZoom() => _setCamera(
        _camera.zoomedTo(
          1,
          screenFocus: Offset(_viewport.width / 2, _viewport.height / 2),
        ),
      );

  /// Move the camera so [sceneRect] is in the middle, without changing zoom.
  void revealSceneRect(Rect rect, {double? atZoom}) {
    if (_viewport.width < 2) {
      return;
    }
    _setCamera(_camera.centeredOn(rect.center, _viewport, atZoom: atZoom));
  }

  void revealObject(String id) {
    final document = _controller.document;
    final node = document.nodeById(id);
    final frame = document.frameById(id);
    final rect = node?.rect ?? frame?.rect;
    if (rect == null) {
      return;
    }
    _controller.select([id]);
    revealSceneRect(rect);
  }

  /// What the camera can see, in scene units. Used by the exporter so
  /// "what is on screen" means what is actually on screen.
  Rect get visibleScene => _camera.visibleScene(_viewport);

  /// Open the find bar from outside — the page's own Ctrl+F, for instance.
  void openSearch() => _openSearch();

  // ---------------------------------------------------------------------
  // Making things
  // ---------------------------------------------------------------------

  Offset get _sceneCentre => _camera.toScene(
        Offset(_viewport.width / 2, _viewport.height / 2),
      );

  Iterable<Rect> get _occupied sync* {
    for (final node in _controller.document.nodes) {
      yield node.rect;
    }
  }

  String addCard(
    CanvasNodeKind kind, {
    Offset? at,
    bool startTyping = false,
    bool configure = true,
  }) {
    final size = defaultCanvasNodeSize(kind);
    final wanted = at ?? _sceneCentre - Offset(size.width / 2, size.height / 2);
    final position = at != null
        ? wanted
        : findFreeCanvasSpot(near: wanted, size: size, taken: _occupied);
    final node = CanvasNode.create(
      kind: kind,
      position: position,
      size: size,
      color: _controller.accent,
    );
    final id = _controller.addNode(
      node,
      editIt: startTyping && kind.carriesText,
    );
    // A card dropped inside a frame belongs to it, without anybody saying so.
    _controller.adoptFrameForNode(id);
    // A card put down where the camera cannot see it looks like nothing
    // happened at all, so the camera goes to meet it.
    _revealIfOffScreen(position & size);
    // A card that holds nothing yet asks what it holds straight away. Leaving
    // an empty picture card sitting on the canvas is a dead end.
    if (configure && node.needsSetUp) {
      unawaited(_setUpCard(id));
    }
    return id;
  }

  /// Pan the least amount that brings [sceneRect] fully into view.
  void _revealIfOffScreen(Rect sceneRect) {
    if (_viewport.width < 2 || _viewport.height < 2) {
      return;
    }
    const margin = 24.0;
    // The toolbar sits along the bottom, so a card is only really in view
    // when it clears it.
    const bottomMargin = 96.0;
    final screen = _camera.sceneToScreen(sceneRect);
    final room = Rect.fromLTRB(
      margin,
      margin,
      _viewport.width - margin,
      _viewport.height - bottomMargin,
    );
    if (room.width < 2 || room.height < 2) {
      return;
    }
    double shift(double low, double high, double roomLow, double roomHigh) {
      if (high - low > roomHigh - roomLow) {
        return roomLow - low;
      }
      if (low < roomLow) {
        return roomLow - low;
      }
      if (high > roomHigh) {
        return roomHigh - high;
      }
      return 0;
    }

    final delta = Offset(
      shift(screen.left, screen.right, room.left, room.right),
      shift(screen.top, screen.bottom, room.top, room.bottom),
    );
    if (delta == Offset.zero) {
      return;
    }
    _setCamera(_camera.panned(delta));
  }

  /// Change what a card already holds.
  ///
  /// The counterpart to [_setUpCard]: same routes, but starting from what is
  /// there rather than from nothing.
  Future<void> _editCard(String id, {Offset? globalPosition}) async {
    final node = _controller.document.nodeById(id);
    if (node == null || !widget.editable || node.locked) {
      return;
    }
    if (node.needsSetUp) {
      await _setUpCard(id, globalPosition: globalPosition);
      return;
    }
    switch (node.kind) {
      case CanvasNodeKind.diagram:
        if (node.diagramKind == CanvasDiagramKind.drawing) {
          await _openDrawing(id);
        } else {
          _controller
            ..select([id])
            ..beginEditing(id);
        }
      case CanvasNodeKind.text:
      case CanvasNodeKind.code:
        _controller
          ..select([id])
          ..beginEditing(id);
      case CanvasNodeKind.image:
      case CanvasNodeKind.web:
      case CanvasNodeKind.bookmark:
      case CanvasNodeKind.page:
      case CanvasNodeKind.database:
      case CanvasNodeKind.canvas:
      case CanvasNodeKind.file:
        await _setUpCard(id, globalPosition: globalPosition);
    }
  }

  /// Ask a card what it holds, and put the answer in it.
  ///
  /// One route for every kind, so a card is never left with an affordance that
  /// does nothing when it is clicked.
  Future<void> _setUpCard(String id, {Offset? globalPosition}) async {
    final node = _controller.document.nodeById(id);
    if (node == null || !widget.editable) {
      return;
    }
    final palette = canvasPaletteOf(context, theme: _controller.settings.theme);
    final anchor = globalPosition ?? _anchorFor(node);

    switch (node.kind) {
      case CanvasNodeKind.image:
        final chosen = await askForCanvasImage(
          context,
          palette: palette,
          globalPosition: anchor,
        );
        if (chosen == null || !mounted) {
          return;
        }
        final natural = chosen.naturalSize;
        _controller.updateNode(id, (current) {
          final shaped = current.copyWith(url: chosen.url);
          // A photograph arrives at the shape it actually is rather than
          // squeezed into whatever box the card was created with.
          return natural == null
              ? shaped
              : shaped.copyWith(size: canvasImageSizeFor(natural));
        });
      case CanvasNodeKind.web:
      case CanvasNodeKind.bookmark:
        final url = await askForCanvasLink(
          context,
          palette: palette,
          initialValue: node.url,
        );
        if (url == null || !mounted) {
          return;
        }
        _controller.updateNode(id, (current) => current.copyWith(url: url));
        unawaited(_describeLink(id, url));
      case CanvasNodeKind.diagram:
        final kind = await askForCanvasDiagramKind(
          context,
          globalPosition: anchor,
        );
        if (kind == null || !mounted) {
          return;
        }
        _controller.updateNode(
          id,
          (current) => current.withData(canvasDiagramKindKey, kind.id).copyWith(
                text: kind == CanvasDiagramKind.mermaid
                    ? sampleCanvasMermaid
                    : '',
              ),
        );
        if (kind == CanvasDiagramKind.drawing) {
          await _openDrawing(id);
        } else {
          _controller
            ..select([id])
            ..beginEditing(id);
        }
      case CanvasNodeKind.page:
      case CanvasNodeKind.database:
      case CanvasNodeKind.canvas:
      case CanvasNodeKind.file:
        unawaitedPick(id, node.kind);
      case CanvasNodeKind.text:
      case CanvasNodeKind.code:
        _controller
          ..select([id])
          ..beginEditing(id);
    }
  }

  /// Where a menu opened from a card should appear: just under the card, but
  /// never outside the board — a menu placed off screen reads as nothing
  /// having happened at all.
  Offset _anchorFor(CanvasNode node) {
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = _camera.toScreen(node.rect.bottomLeft);
    final local = _viewport.width < 2
        ? screen
        : Offset(
            screen.dx.clamp(8.0, math.max(8.0, _viewport.width - 8)),
            screen.dy.clamp(8.0, math.max(8.0, _viewport.height - 8)),
          );
    return box == null ? local : box.localToGlobal(local);
  }

  /// Fill in a saved link's title and picture, so it looks like the page it
  /// points at. Failure is normal and silent — plenty of sites refuse a fetch.
  Future<void> _describeLink(String id, String url) async {
    final info = await readCanvasLinkInfo(url);
    if (info == null || !mounted) {
      return;
    }
    _controller.updateNode(id, (current) {
      var next = current;
      final title = info.title?.trim();
      if (title != null && title.isNotEmpty && current.title.trim().isEmpty) {
        next = next.copyWith(title: title);
      }
      final description = info.description?.trim();
      if (description != null &&
          description.isNotEmpty &&
          current.text.trim().isEmpty) {
        next = next.copyWith(text: description);
      }
      final image = info.imageUrl?.trim();
      if (image != null && image.isNotEmpty) {
        next = next.withData('preview', image);
      }
      return next;
    });
  }

  /// Open a hand-drawn diagram in the Excalidraw editor.
  Future<void> _openDrawing(String id) async {
    final node = _controller.document.nodeById(id);
    if (node == null || node.diagramKind != CanvasDiagramKind.drawing) {
      return;
    }
    await openCanvasDrawing(
      context,
      scene: node.text,
      editable: widget.editable,
      onSceneChanged: (scene) => _controller.updateNode(
        id,
        (current) => current.copyWith(text: scene),
        transient: true,
      ),
    );
    if (!mounted) {
      return;
    }
    // The run of transient scene updates becomes one thing to undo.
    final landed = _controller.document.nodeById(id);
    if (landed != null && landed.text != node.text) {
      _controller.commitGesture(
        _controller.document.withNode(node),
      );
    }
  }

  /// Ask for the object a reference card should point at, right after it is
  /// made — an empty page card with no way to fill it is a dead end.
  void unawaitedPick(String id, CanvasNodeKind kind) {
    final pick = widget.onPickView;
    if (pick == null) {
      return;
    }
    pick(kind).then((view) {
      if (view == null || !mounted) {
        return;
      }
      _controller.updateNode(
        id,
        (node) => node.copyWith(reference: view.id, title: view.name),
      );
      _resolver.adopt(view);
    });
  }

  // ---------------------------------------------------------------------
  // The pointer
  // ---------------------------------------------------------------------

  Offset _toScene(Offset globalPosition) {
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return _camera.toScene(globalPosition);
    }
    return _camera.toScene(box.globalToLocal(globalPosition));
  }

  bool get _wantsPointerSignal =>
      !widget.embedded ||
      _engaged ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_wantsPointerSignal) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final zoomGesture = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      // A mouse wheel zooms, which is what a canvas is expected to do; a
      // trackpad's two-finger scroll arrives here too, so shift swaps the axis
      // the way every other canvas does.
      if (zoomGesture || event.scrollDelta.dx == 0) {
        final factor = event.scrollDelta.dy > 0 ? 1 / 1.12 : 1.12;
        _setCamera(_camera.zoomedBy(factor, screenFocus: event.localPosition));
      } else {
        _pan(-event.scrollDelta);
      }
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    if (_wantsPointerSignal) {
      _engaged = true;
    }
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_wantsPointerSignal) {
      return;
    }
    // Two fingers pan; a pinch zooms about where the fingers are. Doing both
    // at once is what makes a canvas slide out from under the hand, so the
    // gesture is one or the other.
    if ((event.scale - 1).abs() > 0.008) {
      _setCamera(
        _camera.zoomedTo(
          _camera.zoom * (event.scale / math.max(0.01, _lastScale)),
          screenFocus: event.localPosition,
        ),
      );
    } else {
      _pan(event.panDelta);
    }
    _lastScale = event.scale;
  }

  double _lastScale = 1;

  void _onPanZoomEnd(PointerPanZoomEndEvent event) => _lastScale = 1;

  bool get _handMode =>
      _controller.tool == CanvasTool.hand ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.space);

  // ---------------------------------------------------------------------
  // Background gestures
  // ---------------------------------------------------------------------

  void _backgroundDown(PointerDownEvent event) {
    _engaged = true;
    _focus.requestFocus();
    if (event.buttons & kSecondaryMouseButton != 0) {
      _showBackgroundMenu(event.position);
      return;
    }
    if (event.buttons & kMiddleMouseButton != 0) {
      _panning = true;
    }
  }

  void _backgroundStart(Offset globalPosition) {
    final scene = _toScene(globalPosition);
    switch (_controller.tool) {
      case CanvasTool.hand:
        _panning = true;
      case CanvasTool.draw:
        setState(() => _stroke = <Offset>[scene]);
      case CanvasTool.erase:
        _controller.eraseStrokesNear(scene, radius: 14 / _camera.zoom);
      case CanvasTool.frame:
        setState(() {
          _frameAnchor = scene;
          _framing = Rect.fromPoints(scene, scene);
        });
      case CanvasTool.text:
        addCard(CanvasNodeKind.text, at: scene, startTyping: true);
        _controller.setTool(CanvasTool.select);
      case CanvasTool.select:
      case CanvasTool.connect:
        if (_handMode) {
          _panning = true;
          return;
        }
        setState(() {
          _marqueeAnchor = scene;
          _marquee = Rect.fromPoints(scene, scene);
          _marqueeAdds = HardwareKeyboard.instance.isShiftPressed;
        });
    }
  }

  void _backgroundUpdate(Offset globalPosition, Offset delta) {
    if (_panning) {
      _pan(delta);
      return;
    }
    final scene = _toScene(globalPosition);
    if (_stroke != null) {
      setState(() => _stroke = [..._stroke!, scene]);
      return;
    }
    if (_controller.tool == CanvasTool.erase) {
      _controller.eraseStrokesNear(scene, radius: 14 / _camera.zoom);
      return;
    }
    final anchor = _frameAnchor;
    if (anchor != null) {
      setState(() => _framing = Rect.fromPoints(anchor, scene));
      return;
    }
    final marqueeAnchor = _marqueeAnchor;
    if (marqueeAnchor != null) {
      final box = Rect.fromPoints(marqueeAnchor, scene);
      setState(() => _marquee = box);
      _controller.select(
        canvasObjectsIn(box, _objectRects()),
        add: _marqueeAdds,
      );
    }
  }

  void _backgroundEnd() {
    if (_panning) {
      setState(() => _panning = false);
      return;
    }
    final stroke = _stroke;
    if (stroke != null) {
      if (stroke.length > 1) {
        _controller.addStroke(
          CanvasStroke.create(
            points: stroke,
            color: _controller.accent,
          ),
        );
      }
      setState(() => _stroke = null);
      return;
    }
    final framing = _framing;
    if (framing != null) {
      if (framing.width > 40 && framing.height > 40) {
        final frame = CanvasFrame.create(
          position: framing.topLeft,
          size: framing.size,
          color: _controller.accent,
        );
        _controller.edit(
          (document) => document.copyWith(frames: [...document.frames, frame]),
        );
        _controller.select([frame.id]);
        _controller.setTool(CanvasTool.select);
      }
      setState(() {
        _framing = null;
        _frameAnchor = null;
      });
      return;
    }
    setState(() {
      _marquee = null;
      _marqueeAnchor = null;
    });
  }

  void _backgroundTap() {
    if (_controller.tool == CanvasTool.select) {
      _controller
        ..clearSelection()
        ..beginEditing(null);
    }
  }

  void _backgroundDoubleTap(Offset globalPosition) {
    if (!widget.editable) {
      return;
    }
    final scene = _toScene(globalPosition);
    final size = defaultCanvasNodeSize(CanvasNodeKind.text);
    addCard(
      CanvasNodeKind.text,
      at: scene - Offset(size.width / 2, size.height / 2),
      startTyping: true,
    );
  }

  Map<String, Rect> _objectRects() {
    final document = _controller.document;
    return {
      for (final frame in document.frames) frame.id: frame.rect,
      for (final node in document.nodes) node.id: node.rect,
    };
  }

  // ---------------------------------------------------------------------
  // Moving and resizing
  // ---------------------------------------------------------------------

  void _beginDrag(String id) {
    if (!_controller.isSelected(id)) {
      _controller.select([id]);
    }
    final document = _controller.document;
    _gestureBefore = document;
    _dragOrigin = _controller.selectedRects();
    _dragTravel = Offset.zero;

    // Everything that will move, snapshotted where it started. Working from
    // absolute positions means a frame of the drag can be dropped or arrive
    // out of order without the objects creeping apart.
    final moving = <String, Offset>{};
    final movedFrames = <String>{};
    for (final selected in _controller.selection) {
      if (document.frameById(selected) != null) {
        movedFrames
          ..add(selected)
          ..addAll(document.descendantFrames(selected));
      }
    }
    for (final frame in document.frames) {
      if (movedFrames.contains(frame.id)) {
        moving[frame.id] = frame.position;
      }
    }
    for (final node in document.nodes) {
      if (node.locked) {
        continue;
      }
      if (_controller.isSelected(node.id) ||
          (node.frameId != null && movedFrames.contains(node.frameId))) {
        moving[node.id] = node.position;
      }
    }
    _dragStart = moving;
  }

  void _dragBy(Offset screenDelta, Offset globalPosition) {
    if (_dragStart.isEmpty) {
      return;
    }
    _dragTravel += screenDelta / _camera.zoom;

    final settings = _controller.settings;
    final anchorId = _dragOrigin.keys.first;
    final anchor = _dragOrigin[anchorId]!;
    final moving = anchor.shift(_dragTravel);

    final neighbours = <Rect>[
      for (final entry in _objectRects().entries)
        if (!_dragStart.containsKey(entry.key)) entry.value,
    ];
    final snap = snapCanvasRect(
      moving: moving,
      neighbours: neighbours,
      gridSize: settings.gridSize,
      tolerance: canvasSnapTolerance / _camera.zoom,
      snapToGrid: settings.snapToGrid,
      snapToObjects: settings.snapToObjects,
    );

    _applyDragPositions(snap.position - anchor.topLeft);

    // A card dropped over a frame joins it, and the frame lights up to say so.
    final under = _toScene(globalPosition);
    Rect? target;
    for (final frame in _controller.document.frames) {
      if (_dragStart.containsKey(frame.id)) {
        continue;
      }
      if (frame.rect.contains(under)) {
        target = frame.rect;
      }
    }
    setState(() {
      _guides = snap.guides;
      _dropTarget = target;
    });
  }

  void _applyDragPositions(Offset delta) {
    _controller.edit(
      (document) => document.copyWith(
        nodes: [
          for (final node in document.nodes)
            if (_dragStart[node.id] != null)
              node.copyWith(position: _dragStart[node.id]! + delta)
            else
              node,
        ],
        frames: [
          for (final frame in document.frames)
            if (_dragStart[frame.id] != null)
              frame.copyWith(position: _dragStart[frame.id]! + delta)
            else
              frame,
        ],
      ),
      transient: true,
    );
  }

  void _endDrag() {
    for (final id in _dragStart.keys) {
      _controller.adoptFrameForNode(id);
    }
    _commitGesture();
    setState(() {
      _dragOrigin = const <String, Rect>{};
      _dragStart = const <String, Offset>{};
      _dragTravel = Offset.zero;
      _guides = const <CanvasGuide>[];
      _dropTarget = null;
    });
  }

  /// One entry in the history for a whole gesture.
  void _commitGesture() {
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before != null) {
      _controller.commitGesture(before);
    }
  }

  void _beginResize(String id, Rect rect) {
    _gestureBefore = _controller.document;
    _resizeId = id;
    _resizeOrigin = rect;
    _dragTravel = Offset.zero;
  }

  void _resizeBy(
    CanvasHandle handle,
    Offset screenDelta, {
    required bool node,
  }) {
    final origin = _resizeOrigin;
    final id = _resizeId;
    if (origin == null || id == null) {
      return;
    }
    _dragTravel += screenDelta / _camera.zoom;
    final next = resizeCanvasRect(
      origin,
      handle,
      _dragTravel,
      minimumWidth: node ? minimumCanvasNodeWidth : minimumCanvasFrameWidth,
      minimumHeight: node ? minimumCanvasNodeHeight : minimumCanvasFrameHeight,
    );
    if (node) {
      _controller.updateNode(
        id,
        (current) => current.copyWith(position: next.topLeft, size: next.size),
        transient: true,
      );
    } else {
      _controller.updateFrame(
        id,
        (current) => current.copyWith(position: next.topLeft, size: next.size),
        transient: true,
      );
    }
  }

  void _endResize() {
    _commitGesture();
    setState(() {
      _resizeId = null;
      _resizeOrigin = null;
      _dragTravel = Offset.zero;
    });
  }

  // ---------------------------------------------------------------------
  // Connecting
  // ---------------------------------------------------------------------

  void _beginConnect(String nodeId, CanvasSide side) {
    final node = _controller.document.nodeById(nodeId);
    if (node == null) {
      return;
    }
    setState(() {
      _connectFrom = nodeId;
      _connectSide = side;
      _connectPoint = canvasAnchorPoint(node.rect, side);
    });
  }

  void _updateConnect(Offset globalPosition) {
    if (_connectFrom == null) {
      return;
    }
    final scene = _toScene(globalPosition);
    String? target;
    for (final node in _controller.document.nodes) {
      if (node.id != _connectFrom && node.rect.contains(scene)) {
        target = node.id;
      }
    }
    setState(() {
      _connectPoint = scene;
      _connectTarget = target;
    });
  }

  void _endConnect(Offset globalPosition) {
    final from = _connectFrom;
    final scene = _connectPoint ?? _toScene(globalPosition);
    setState(() {
      _connectFrom = null;
      _connectPoint = null;
      _connectTarget = null;
    });
    if (from == null) {
      return;
    }
    String? target;
    for (final node in _controller.document.nodes) {
      if (node.id != from && node.rect.contains(scene)) {
        target = node.id;
      }
    }
    if (target != null) {
      _controller.connect(from, target);
      return;
    }
    // Letting go over empty canvas makes the card that was being reached for,
    // which is how a mind map is drawn without stopping to create anything.
    final size = defaultCanvasNodeSize(CanvasNodeKind.text);
    final made = addCard(
      CanvasNodeKind.text,
      at: scene - Offset(size.width / 2, size.height / 2),
      startTyping: true,
    );
    _controller.connect(from, made);
  }

  void _connectSelected() {
    final ids = [
      for (final id in _controller.selection)
        if (_controller.document.nodeById(id) != null) id,
    ];
    for (var index = 0; index + 1 < ids.length; index++) {
      _controller.connect(ids[index], ids[index + 1]);
    }
  }

  // ---------------------------------------------------------------------
  // The keyboard
  // ---------------------------------------------------------------------

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _controller.selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            _controller.selectAll,
        const SingleActivator(LogicalKeyboardKey.delete):
            _controller.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.backspace):
            _controller.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _controller.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            _controller.undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _controller.redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): _controller.redo,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            _controller.duplicateSelection,
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            _controller.duplicateSelection,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _paste,
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
            _controller.groupSelection(),
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
            _controller.groupSelection(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.tab): _addBranch,
        const SingleActivator(LogicalKeyboardKey.enter): _addSibling,
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
            _zoomBy(1.2),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
            _zoomBy(1 / 1.2),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            resetZoom,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true):
            zoomToFit,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _nudge(const Offset(-1, 0)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _nudge(const Offset(1, 0)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _nudge(const Offset(0, -1)),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _nudge(const Offset(0, 1)),
      };

  void _nudge(Offset direction) {
    if (!_controller.hasSelection) {
      _pan(-direction * 60);
      return;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 20.0 : 2.0;
    _controller.moveSelection(direction * step);
  }

  void _escape() {
    if (_searching) {
      _closeSearch();
      return;
    }
    if (_controller.tool != CanvasTool.select) {
      _controller.setTool(CanvasTool.select);
      return;
    }
    _controller
      ..beginEditing(null)
      ..clearSelection();
  }

  /// Tab on a mind map puts a branch beside whatever is selected and joins it.
  void _addBranch() {
    final selection = _controller.selection;
    if (selection.length != 1) {
      return;
    }
    final parent = _controller.document.nodeById(selection.first);
    if (parent == null) {
      return;
    }
    final children = <Rect>[];
    for (final edge in _controller.document.edges) {
      if (edge.from != parent.id) {
        continue;
      }
      final child = _controller.document.nodeById(edge.to);
      if (child != null) {
        children.add(child.rect);
      }
    }
    final size = defaultCanvasNodeSize(CanvasNodeKind.text);
    final at = nextMindMapChildPosition(
      parent: parent.rect,
      siblings: children,
      size: size,
    );
    final made = addCard(CanvasNodeKind.text, at: at, startTyping: true);
    _controller.connect(parent.id, made);
    revealSceneRect(at & size, atZoom: _camera.zoom);
  }

  /// Enter puts one beside it, under the same parent.
  void _addSibling() {
    final selection = _controller.selection;
    if (selection.length != 1) {
      return;
    }
    final sibling = _controller.document.nodeById(selection.first);
    if (sibling == null) {
      return;
    }
    final size = defaultCanvasNodeSize(CanvasNodeKind.text);
    final at = nextMindMapSiblingPosition(sibling: sibling.rect, size: size);
    final made = addCard(CanvasNodeKind.text, at: at, startTyping: true);
    for (final edge in _controller.document.edges) {
      if (edge.to == sibling.id) {
        _controller.connect(edge.from, made);
        break;
      }
    }
  }

  void _copy() {
    if (!_controller.hasSelection) {
      return;
    }
    final ids = _controller.selection;
    final document = _controller.document;
    _clipboard = CanvasDocument(
      nodes: [
        for (final node in document.nodes)
          if (ids.contains(node.id)) node,
      ],
      frames: [
        for (final frame in document.frames)
          if (ids.contains(frame.id)) frame,
      ],
      edges: [
        for (final edge in document.edges)
          if (ids.contains(edge.from) && ids.contains(edge.to)) edge,
      ],
    );
  }

  void _paste() {
    final clipboard = _clipboard;
    if (clipboard == null || clipboard.isEmpty) {
      // Nothing was copied on a canvas, so paste whatever the system is
      // holding: an address becomes a saved link, a picture becomes a picture,
      // anything else becomes a card with the words in it.
      unawaited(_pasteFromSystem());
      return;
    }
    // Paste where the canvas is being looked at, not where it was copied
    // from: the two are usually nowhere near each other.
    final source = clipboard.bounds;
    final delta = _sceneCentre - source.center;
    final nodeIds = <String, String>{};
    final frameIds = <String, String>{};
    for (final node in clipboard.nodes) {
      nodeIds[node.id] = newCanvasId();
    }
    for (final frame in clipboard.frames) {
      frameIds[frame.id] = newCanvasId('f');
    }

    final made = <String>[];
    _controller.edit((document) {
      final nodes = <CanvasNode>[
        for (final node in clipboard.nodes)
          CanvasNode(
            id: nodeIds[node.id]!,
            kind: node.kind,
            position: node.position + delta,
            size: node.size,
            title: node.title,
            text: node.text,
            url: node.url,
            reference: node.reference,
            frameId: frameIds[node.frameId],
            color: node.color,
            data: node.data,
          ),
      ];
      final frames = <CanvasFrame>[
        for (final frame in clipboard.frames)
          CanvasFrame(
            id: frameIds[frame.id]!,
            position: frame.position + delta,
            size: frame.size,
            title: frame.title,
            description: frame.description,
            color: frame.color,
            parentId: frameIds[frame.parentId],
          ),
      ];
      final edges = <CanvasEdge>[
        for (final edge in clipboard.edges)
          CanvasEdge(
            id: newCanvasId('e'),
            from: nodeIds[edge.from]!,
            to: nodeIds[edge.to]!,
            fromSide: edge.fromSide,
            toSide: edge.toSide,
            label: edge.label,
            color: edge.color,
            style: edge.style,
            startMarker: edge.startMarker,
            endMarker: edge.endMarker,
            relation: edge.relation,
          ),
      ];
      made
        ..addAll(nodeIds.values)
        ..addAll(frameIds.values);
      return document.copyWith(
        nodes: [...document.nodes, ...nodes],
        frames: [...document.frames, ...frames],
        edges: [...document.edges, ...edges],
      );
    });
    _controller.select(made);
  }

  /// Paste whatever the system clipboard is holding.
  Future<void> _pasteFromSystem() async {
    final data = await getIt<ClipboardService>().getData();
    if (!mounted) {
      return;
    }
    final image = data.image;
    if (image != null && image.$2 != null && image.$2!.isNotEmpty) {
      final saved = await saveCanvasClipboardImage(image.$1, image.$2!);
      if (saved == null || !mounted) {
        return;
      }
      final id = addCard(CanvasNodeKind.image, configure: false);
      _controller.updateNode(id, (current) {
        final shaped = current.copyWith(url: saved.url);
        final natural = saved.naturalSize;
        return natural == null
            ? shaped
            : shaped.copyWith(size: canvasImageSizeFor(natural));
      });
      return;
    }

    final text = data.plainText?.trim();
    if (text == null || text.isEmpty) {
      return;
    }
    final url = Uri.tryParse(text);
    final isAddress = !text.contains(RegExp(r'\s')) &&
        url != null &&
        (url.scheme == 'http' || url.scheme == 'https');
    final id = addCard(
      isAddress ? CanvasNodeKind.bookmark : CanvasNodeKind.text,
      configure: false,
    );
    if (isAddress) {
      _controller.updateNode(id, (current) => current.copyWith(url: text));
      unawaited(_describeLink(id, text));
    } else {
      _controller.updateNode(id, (current) => current.copyWith(text: text));
    }
  }

  // ---------------------------------------------------------------------
  // Find
  // ---------------------------------------------------------------------

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() => setState(() {
        _searching = false;
        _query = '';
        _hits = const <CanvasSearchHit>[];
        _hitIndex = 0;
      });

  void _onQueryChanged(String query) {
    setState(() {
      _query = query;
      _hits = searchCanvas(_controller.document, query);
      _hitIndex = 0;
    });
    _goToHit();
  }

  void _stepHit(int step) {
    if (_hits.isEmpty) {
      return;
    }
    setState(() => _hitIndex = (_hitIndex + step) % _hits.length);
    _goToHit();
  }

  void _goToHit() {
    if (_hits.isEmpty || _hitIndex >= _hits.length) {
      return;
    }
    final hit = _hits[_hitIndex];
    final document = _controller.document;
    final rect = document.nodeById(hit.id)?.rect ??
        document.frameById(hit.id)?.rect ??
        _edgeRect(hit.id);
    if (rect != null) {
      revealSceneRect(rect, atZoom: math.max(_camera.zoom, 0.6));
    }
  }

  Rect? _edgeRect(String edgeId) {
    final document = _controller.document;
    final edge = document.edgeById(edgeId);
    if (edge == null) {
      return null;
    }
    final from = document.nodeById(edge.from);
    final to = document.nodeById(edge.to);
    if (from == null || to == null) {
      return null;
    }
    return from.rect.expandToInclude(to.rect);
  }

  Set<String> get _hitIds => {for (final hit in _hits) hit.id};

  // ---------------------------------------------------------------------
  // Menus
  // ---------------------------------------------------------------------

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showBackgroundMenu(Offset globalPosition) async {
    if (!widget.editable) {
      return;
    }
    final scene = _toScene(globalPosition);
    await showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: canvasBackgroundMenuEntries(
        controller: _controller,
        onChanged: _refresh,
        onAdd: (kind) => addCard(
          kind,
          at: scene,
          startTyping: kind == CanvasNodeKind.text,
        ),
        onAddFrame: () {
          final frame = CanvasFrame.create(
            position: scene,
            size: const Size(420, 320),
            color: _controller.accent,
          );
          _controller.edit(
            (document) =>
                document.copyWith(frames: [...document.frames, frame]),
          );
          _controller.select([frame.id]);
        },
        onPaste: _paste,
        onZoomToFit: zoomToFit,
        onTemplates: () => _showTemplates(globalPosition),
      ),
    );
  }

  Future<void> _showNodeMenu(CanvasNode node, Offset globalPosition) async {
    if (!_controller.isSelected(node.id)) {
      _controller.select([node.id]);
    }
    if (!widget.editable) {
      await _showReadOnlyNodeMenu(node, globalPosition);
      return;
    }
    await showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: canvasNodeMenuEntries(
        controller: _controller,
        node: node,
        onChanged: _refresh,
        onOpen: () {
          if (node.diagramKind == CanvasDiagramKind.drawing) {
            unawaited(_openDrawing(node.id));
          } else if (node.kind.referencesWorkspaceObject) {
            _openReference(node);
          } else if (node.url.trim().isNotEmpty) {
            unawaited(afLaunchUrlString(node.url.trim()));
          }
        },
        onSetUp: () => unawaited(
          _setUpCard(node.id, globalPosition: globalPosition),
        ),
        onConvertToPage: () => _convertNodeToPage(node),
        onChangeType: (kind) {
          _controller.updateNode(node.id, (current) {
            final size = defaultCanvasNodeSize(kind);
            return current.copyWith(
              kind: kind,
              size: Size(
                math.max(current.size.width, size.width * 0.7),
                math.max(current.size.height, size.height * 0.7),
              ),
            );
          });
          final changed = _controller.document.nodeById(node.id);
          if (changed != null && changed.needsSetUp) {
            unawaited(_setUpCard(node.id, globalPosition: globalPosition));
          }
        },
      ),
    );
  }

  /// The menu a canvas that cannot be changed still offers. Opening a card and
  /// copying what it says are not edits, and a right-click that answers with
  /// nothing at all reads as the canvas being broken.
  Future<void> _showReadOnlyNodeMenu(
    CanvasNode node,
    Offset globalPosition,
  ) async {
    final canOpen = node.kind.referencesWorkspaceObject
        ? node.reference.isNotEmpty
        : node.url.trim().isNotEmpty;
    final text = node.text.trim();
    await showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: [
        if (canOpen)
          AppMenuItem(
            label: LocaleKeys.canvas_menu_open.tr(),
            icon: Icons.open_in_new_rounded,
            onSelected: () {
              if (node.kind.referencesWorkspaceObject) {
                _openReference(node);
              } else {
                unawaited(afLaunchUrlString(node.url.trim()));
              }
            },
          ),
        if (text.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.canvas_card_copy.tr(),
            icon: Icons.content_copy_rounded,
            onSelected: () => unawaited(
              getIt<ClipboardService>().setData(
                ClipboardServiceData(plainText: text),
              ),
            ),
          ),
        AppMenuItem(
          label: LocaleKeys.canvas_readOnly.tr(),
          icon: Icons.lock_outline_rounded,
          enabled: false,
        ),
      ],
    );
  }

  Future<void> _showFrameMenu(CanvasFrame frame, Offset globalPosition) async {
    if (!widget.editable) {
      return;
    }
    if (!_controller.isSelected(frame.id)) {
      _controller.select([frame.id]);
    }
    await showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: canvasFrameMenuEntries(
        controller: _controller,
        frame: frame,
        onChanged: _refresh,
        onConvertToPage: () => _convertFrameToPage(frame),
      ),
    );
  }

  Future<void> _showEdgeMenu(CanvasEdge edge, Offset globalPosition) async {
    if (!widget.editable) {
      return;
    }
    await showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: canvasEdgeMenuEntries(
        controller: _controller,
        edge: edge,
        onChanged: _refresh,
        onEditLabel: () => _editEdgeLabel(edge),
      ),
    );
  }

  Future<void> _showAddMenu(Offset globalPosition) async {
    await showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: [
        for (final kind in CanvasNodeKind.values)
          AppMenuItem(
            label: canvasNodeLabel(kind),
            icon: canvasNodeIcon(kind),
            onSelected: () =>
                addCard(kind, startTyping: kind == CanvasNodeKind.text),
          ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.canvas_add_frame.tr(),
          icon: Icons.crop_free_rounded,
          onSelected: () => _controller.setTool(CanvasTool.frame),
        ),
      ],
    );
  }

  Future<void> _showMoreMenu(Offset globalPosition) async {
    await showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: canvasSettingsEntries(
        controller: _controller,
        onChanged: _refresh,
        onExport: widget.onExport ?? () {},
        onTemplates: () => _showTemplates(globalPosition),
        onOpenStandalone: widget.onOpenStandalone,
      ),
    );
  }

  Future<void> _showTemplates(Offset globalPosition) async {
    await showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: canvasTemplateEntries(
        onChosen: (template) {
          final built = template.build();
          // A template adds to what is already there rather than replacing it,
          // and lands where the canvas is being looked at.
          final delta =
              built.isEmpty ? Offset.zero : _sceneCentre - built.bounds.center;
          _controller.edit(
            (document) => document.copyWith(
              nodes: [
                ...document.nodes,
                for (final node in built.nodes)
                  node.copyWith(position: node.position + delta),
              ],
              frames: [
                ...document.frames,
                for (final frame in built.frames)
                  frame.copyWith(position: frame.position + delta),
              ],
              edges: [...document.edges, ...built.edges],
            ),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) => zoomToFit());
        },
      ),
    );
  }

  Future<void> _editEdgeLabel(CanvasEdge edge) async {
    final controller = TextEditingController(text: edge.label);
    final palette = canvasPaletteOf(context, theme: _controller.settings.theme);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          LocaleKeys.canvas_edge_labelHint.tr(),
          style: canvasLabelStyle(palette, size: 15, weight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: canvasLabelStyle(palette, size: 14),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(LocaleKeys.button_confirm.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label != null) {
      _controller.updateEdge(
        edge.id,
        (current) => current.copyWith(label: label),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Canvas to AppFlowy content
  // ---------------------------------------------------------------------

  void _openReference(CanvasNode node) {
    final open = widget.onOpenView;
    if (open == null || node.reference.isEmpty) {
      return;
    }
    final view = _resolver.peek(node.reference);
    if (view != null) {
      open(view);
    }
  }

  Future<void> _convertNodeToPage(CanvasNode node) async {
    final create = widget.onCreatePage;
    if (create == null) {
      return;
    }
    final lines = node.text.trim().split('\n');
    final title = node.title.trim().isNotEmpty
        ? node.title.trim()
        : (lines.isNotEmpty ? lines.first.trim() : '');
    final body = lines.length > 1 ? lines.sublist(1).join('\n') : '';
    final view = await create(title, body);
    if (view == null || !mounted) {
      return;
    }
    // The card becomes the page rather than being replaced by one, so the
    // canvas keeps its shape and the connections still mean something.
    _controller.updateNode(
      node.id,
      (current) => current.copyWith(
        kind: CanvasNodeKind.page,
        reference: view.id,
        title: view.name,
        text: '',
      ),
    );
    _resolver.adopt(view);
  }

  Future<void> _convertFrameToPage(CanvasFrame frame) async {
    final create = widget.onCreatePage;
    if (create == null) {
      return;
    }
    final cards = _controller.document.nodesInFrame(frame.id);
    final body = <String>[];
    for (final card in cards) {
      final label =
          card.title.trim().isNotEmpty ? card.title.trim() : card.text.trim();
      if (label.isNotEmpty) {
        body.add('- $label');
      }
    }
    await create(frame.title.trim(), body.join('\n'));
  }

  // ---------------------------------------------------------------------
  // Building
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = canvasPaletteOf(context, theme: _controller.settings.theme);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _viewport) {
          _viewport = size;
          // The canvas opens where it was left. Reading it once, after the
          // first real layout, is what stops a stored viewport being applied
          // against a zero-sized box.
          if (!_readViewport && size.width > 2 && size.height > 2) {
            _readViewport = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              final stored = _controller.settings.viewport;
              if (stored.offset == Offset.zero && stored.zoom == 1) {
                zoomToFit();
              } else {
                _setCamera(
                  CanvasCamera(offset: stored.offset, zoom: stored.zoom),
                  remember: false,
                );
              }
            });
          }
        }

        return PremiumScrollExclusion(
          child: Focus(
            focusNode: _focus,
            autofocus: !widget.embedded,
            child: CallbackShortcuts(
              bindings: widget.editable ? _shortcuts : const {},
              child: Listener(
                onPointerSignal: _onPointerSignal,
                onPointerPanZoomStart: _onPanZoomStart,
                onPointerPanZoomUpdate: _onPanZoomUpdate,
                onPointerPanZoomEnd: _onPanZoomEnd,
                child: MouseRegion(
                  cursor: _handMode
                      ? SystemMouseCursors.grab
                      : switch (_controller.tool) {
                          CanvasTool.draw ||
                          CanvasTool.erase =>
                            SystemMouseCursors.precise,
                          CanvasTool.text ||
                          CanvasTool.frame =>
                            SystemMouseCursors.cell,
                          _ => MouseCursor.defer,
                        },
                  child: ClipRect(
                    child: Stack(
                      key: _surfaceKey,
                      children: [
                        _background(palette),
                        _surface(palette, size),
                        _content(palette, size),
                        _overlay(palette),
                        if (widget.showChrome) ..._chrome(palette, size),
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

  Widget _background(CanvasPalette palette) => Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: CanvasBackgroundPainter(
              camera: _camera,
              palette: palette,
              background: _controller.settings.background,
              spacing: _controller.settings.gridSize,
            ),
          ),
        ),
      );

  /// The surface that answers a click on empty canvas.
  ///
  /// It is the FIRST child of the stack, so cards — which come later — are hit
  /// tested before it and keep their own gestures.
  Widget _surface(CanvasPalette palette, Size size) {
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _backgroundDown,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _SurfacePanRecognizer:
                GestureRecognizerFactoryWithHandlers<_SurfacePanRecognizer>(
              _SurfacePanRecognizer.new,
              (recognizer) {
                recognizer.onStart = (details) {
                  _backgroundStart(details.globalPosition);
                };
                recognizer.onUpdate = (details) {
                  _backgroundUpdate(details.globalPosition, details.delta);
                };
                recognizer.onEnd = (_) => _backgroundEnd();
                recognizer.onCancel = _backgroundEnd;
              },
            ),
            _SurfaceTapRecognizer:
                GestureRecognizerFactoryWithHandlers<_SurfaceTapRecognizer>(
              _SurfaceTapRecognizer.new,
              (recognizer) {
                recognizer.onTapUp = (details) => _handleSurfaceTap(details);
              },
            ),
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  DateTime? _lastSurfaceTap;

  void _handleSurfaceTap(TapUpDetails details) {
    // Timed by hand rather than with a double-tap recogniser, which would hold
    // every single click back by the double-tap window.
    final now = DateTime.now();
    final previous = _lastSurfaceTap;
    _lastSurfaceTap = now;
    if (previous != null && now.difference(previous) < kDoubleTapTimeout) {
      _lastSurfaceTap = null;
      _backgroundDoubleTap(details.globalPosition);
      return;
    }
    _backgroundTap();
  }

  /// Frames, connections and cards, in one transformed layer.
  Widget _content(CanvasPalette palette, Size size) {
    final document = _controller.document;
    // Only what is on screen is built. The margin means a card is ready before
    // it is reached, so panning does not flicker things into existence.
    final visible = _camera.visibleScene(size).inflate(280 / _camera.zoom);

    final collapsedFrames = <String>{
      for (final frame in document.frames)
        if (frame.collapsed) ...[
          frame.id,
          ...document.descendantFrames(frame.id),
        ],
    };

    final drawings = <CanvasEdgeDrawing>[];
    for (final edge in document.edges) {
      final from = document.nodeById(edge.from);
      final to = document.nodeById(edge.to);
      if (from == null || to == null) {
        continue;
      }
      if (collapsedFrames.contains(from.frameId) ||
          collapsedFrames.contains(to.frameId)) {
        continue;
      }
      final span = from.rect.expandToInclude(to.rect);
      if (!span.overlaps(visible)) {
        continue;
      }
      drawings.add(
        CanvasEdgeDrawing(
          edge: edge,
          geometry: canvasEdgeGeometry(
            from: from.rect,
            to: to.rect,
            fromSide: edge.fromSide,
            toSide: edge.toSide,
          ),
          colour: edge.color == null
              ? palette.textMuted
                  .withValues(alpha: palette.isDark ? 0.75 : 0.62)
              : palette.accentAt(edge.color),
          selected: _controller.isSelected(edge.id),
        ),
      );
    }

    final pendingFrom =
        _connectFrom == null ? null : document.nodeById(_connectFrom!);

    // The box the card layer is laid out in: everything the document holds,
    // everything the camera can see, and room around both for what is about
    // to be put down or dragged out.
    final layer = (document.bounds.isEmpty
            ? visible
            : document.bounds.expandToInclude(visible))
        .inflate(2000);

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: CanvasEdgePainter(
                  camera: _camera,
                  palette: palette,
                  edges: drawings,
                  pending: pendingFrom == null || _connectPoint == null
                      ? null
                      : (
                          from:
                              canvasAnchorPoint(pendingFrom.rect, _connectSide),
                          to: _connectPoint!,
                        ),
                  labelStyle: DefaultTextStyle.of(context).style,
                ),
              ),
            ),
          ),
          // Right-clicking a connection has to land somewhere, and a
          // connection is paint rather than a widget. This layer sits BELOW
          // the cards: a translucent listener reports a hit everywhere, so
          // above them it would swallow every card gesture on the canvas.
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                if (event.buttons & kSecondaryMouseButton == 0) {
                  return;
                }
                final edge = _edgeAt(event.position, drawings);
                if (edge != null) {
                  unawaited(_showEdgeMenu(edge, event.position));
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
          // One transform for every card, so a card is laid out in scene units
          // and never has to think about the camera.
          //
          // ⚠️ The layer is SIZED to hold everything on it, and its origin
          // moved to the top left of that. `RenderBox.hitTest` gives up as
          // soon as the position falls outside a box, so a card laid out
          // beyond the layer's own size is painted perfectly and can never be
          // clicked — which is every card once the canvas is panned or grows
          // past one screenful.
          Positioned.fill(
            child: Transform(
              transform: Matrix4.identity()
                ..translate(
                  _camera.offset.dx + layer.left * _camera.zoom,
                  _camera.offset.dy + layer.top * _camera.zoom,
                )
                ..scale(_camera.zoom, _camera.zoom, 1.0),
              alignment: Alignment.topLeft,
              child: _CanvasCardLayer(
                layerSize: layer.size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final frame in document.frames)
                      if (frame.rect.overlaps(visible))
                        Positioned(
                          left: frame.position.dx - layer.left,
                          top: frame.position.dy - layer.top,
                          width: frame.size.width,
                          height: frame.collapsed
                              ? CanvasMetrics.frameHeaderHeight
                              : frame.size.height,
                          child: _frameBox(frame, palette),
                        ),
                    for (final node in document.nodes)
                      if (node.rect.overlaps(visible) &&
                          !collapsedFrames.contains(node.frameId))
                        Positioned(
                          left: node.position.dx - layer.left,
                          top: node.position.dy - layer.top,
                          width: node.size.width,
                          height: node.size.height,
                          child: _card(node, palette),
                        ),
                  ],
                ),
              ),
            ),
          ),
          // Strokes go over the cards: a highlighter that cannot reach a card
          // is not a highlighter. It never takes the pointer.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: CanvasStrokePainter(
                    camera: _camera,
                    palette: palette,
                    strokes: document.strokes,
                    live: _stroke,
                    liveColour: _controller.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  CanvasEdge? _edgeAt(Offset globalPosition, List<CanvasEdgeDrawing> drawings) {
    final scene = _toScene(globalPosition);
    final tolerance = CanvasMetrics.edgeHitWidth / _camera.zoom;
    for (final drawing in drawings) {
      if (drawing.geometry.distanceTo(scene) <= tolerance) {
        return drawing.edge;
      }
    }
    return null;
  }

  Widget _card(CanvasNode node, CanvasPalette palette) {
    return CanvasCard(
      key: ValueKey(node.id),
      node: node,
      palette: palette,
      resolver: _resolver,
      zoom: _camera.zoom,
      selected: _controller.isSelected(node.id),
      editing: _controller.editing == node.id,
      editable: widget.editable && _controller.tool != CanvasTool.hand,
      searchHit: _query.trim().isNotEmpty && _hitIds.contains(node.id),
      connectingFrom: _connectFrom == node.id,
      connectTarget: _connectTarget == node.id,
      onTap: (shift) {
        if (_controller.tool == CanvasTool.connect) {
          final from = _connectFrom;
          if (from == null) {
            setState(() => _connectFrom = node.id);
          } else {
            _controller.connect(from, node.id);
            setState(() => _connectFrom = null);
          }
          return;
        }
        _controller
          ..select([node.id], toggle: shift)
          ..beginEditing(null);
      },
      onDoubleTap: () {
        if (!node.needsSetUp && node.kind.referencesWorkspaceObject) {
          _openReference(node);
        } else if (!node.needsSetUp &&
            (node.kind == CanvasNodeKind.web ||
                node.kind == CanvasNodeKind.bookmark)) {
          // A saved link opens where a link opens.
          unawaited(afLaunchUrlString(node.url.trim()));
        } else {
          unawaited(_editCard(node.id));
        }
      },
      onContextMenu: (position) => _showNodeMenu(node, position),
      onDragStart: () => _beginDrag(node.id),
      onDragUpdate: _dragBy,
      onDragEnd: _endDrag,
      onResizeStart: (_) => _beginResize(node.id, node.rect),
      onResizeUpdate: (handle, delta) => _resizeBy(handle, delta, node: true),
      onResizeEnd: _endResize,
      onConnectStart: (side) => _beginConnect(node.id, side),
      onConnectUpdate: _updateConnect,
      onConnectEnd: _endConnect,
      onTextChanged: (text) => _controller.updateNode(
        node.id,
        (current) => current.copyWith(text: text),
        transient: true,
      ),
      onEditingFinished: () {
        // Commit once when typing stops, so an edit is one thing to undo
        // rather than one per keystroke.
        final current = _controller.document.nodeById(node.id);
        if (current != null) {
          _controller.edit((document) => document.withNode(current));
        }
        _controller.beginEditing(null);
      },
      onOpen: () {
        if (node.kind.referencesWorkspaceObject) {
          _openReference(node);
        } else if (node.url.trim().isNotEmpty) {
          unawaited(afLaunchUrlString(node.url.trim()));
        }
      },
      onSetUp: () => unawaited(_setUpCard(node.id)),
      onEdit: () => unawaited(_editCard(node.id)),
    );
  }

  Widget _frameBox(CanvasFrame frame, CanvasPalette palette) {
    return CanvasFrameBox(
      key: ValueKey(frame.id),
      frame: frame,
      palette: palette,
      zoom: _camera.zoom,
      selected: _controller.isSelected(frame.id),
      editable: widget.editable && _controller.tool != CanvasTool.hand,
      cardCount: _controller.document.nodesInFrame(frame.id).length,
      onTap: (shift) => _controller.select([frame.id], toggle: shift),
      onDoubleTap: () => _controller.selectInsideFrame(frame.id),
      onContextMenu: (position) => _showFrameMenu(frame, position),
      onDragStart: () => _beginDrag(frame.id),
      onDragUpdate: _dragBy,
      onDragEnd: _endDrag,
      onResizeStart: (_) => _beginResize(frame.id, frame.rect),
      onResizeUpdate: (handle, delta) => _resizeBy(handle, delta, node: false),
      onResizeEnd: _endResize,
      onTitleChanged: (title) => _controller.updateFrame(
        frame.id,
        (current) => current.copyWith(title: title),
      ),
      onToggleCollapsed: () => _controller.updateFrame(
        frame.id,
        (current) => current.copyWith(collapsed: !current.collapsed),
      ),
    );
  }

  Widget _overlay(CanvasPalette palette) => Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: CanvasOverlayPainter(
              camera: _camera,
              palette: palette,
              guides: _guides,
              marquee: _marquee,
              dropTarget: _dropTarget ?? _framing,
            ),
          ),
        ),
      );

  List<Widget> _chrome(CanvasPalette palette, Size size) {
    final compact = size.width < 560;
    final document = _controller.document;

    return [
      if (document.isEmpty && widget.editable && !widget.embedded)
        Positioned.fill(
          child: CanvasEmptyState(
            palette: palette,
            onUseTemplate: () => _showTemplates(
              Offset(size.width / 2, size.height / 2),
            ),
          ),
        ),
      if (widget.editable)
        Positioned(
          left: 0,
          right: 0,
          bottom: CanvasMetrics.space4,
          child: Align(
            child: CanvasToolbar(
              palette: palette,
              tool: _controller.tool,
              compact: compact,
              onToolChanged: (tool) {
                _controller.setTool(tool);
                if (tool == CanvasTool.connect) {
                  setState(() => _connectFrom = null);
                }
              },
              onAdd: _showAddMenu,
              onMore: _showMoreMenu,
            ),
          ),
        ),
      if (!widget.editable)
        Positioned(
          left: CanvasMetrics.space4,
          bottom: CanvasMetrics.space4,
          child: Tooltip(
            message: LocaleKeys.canvas_readOnlyHint.tr(),
            child: CanvasSurface(
              palette: palette,
              padding: const EdgeInsets.symmetric(
                horizontal: CanvasMetrics.space3,
                vertical: CanvasMetrics.space1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: CanvasMetrics.space1),
                  Text(
                    LocaleKeys.canvas_readOnly.tr(),
                    style: canvasLabelStyle(palette, color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      Positioned(
        right: CanvasMetrics.space4,
        bottom: CanvasMetrics.space4,
        child: CanvasZoomCluster(
          palette: palette,
          zoom: _camera.zoom,
          onZoomIn: () => _zoomBy(1.2),
          onZoomOut: () => _zoomBy(1 / 1.2),
          onReset: resetZoom,
          onFit: () => zoomToFit(selectionOnly: _controller.hasSelection),
        ),
      ),
      if (_controller.settings.showMinimap && !document.isEmpty)
        Positioned(
          right: CanvasMetrics.space4,
          bottom: CanvasMetrics.space4 + CanvasMetrics.toolbarHeight + 8,
          child: CanvasMinimap(
            document: document,
            palette: palette,
            camera: _camera,
            viewport: size,
            onJump: (scene) => revealSceneRect(
              Rect.fromCenter(
                center: scene,
                width: 1,
                height: 1,
              ),
            ),
            onHide: () => _controller.updateSettings(
              (current) => current.copyWith(showMinimap: false),
            ),
          ),
        ),
      if (_controller.settings.showOutline)
        Positioned(
          left: CanvasMetrics.space4,
          top: CanvasMetrics.space4,
          child: CanvasOutlinePanel(
            palette: palette,
            entries: canvasOutline(document),
            selected: _controller.selection,
            onGoTo: revealObject,
            onHide: () => _controller.updateSettings(
              (current) => current.copyWith(showOutline: false),
            ),
          ),
        ),
      if (_searching)
        Positioned(
          right: CanvasMetrics.space4,
          top: CanvasMetrics.space4,
          child: CanvasSearchBar(
            palette: palette,
            query: _query,
            hits: _hits,
            index: _hitIndex,
            onQueryChanged: _onQueryChanged,
            onNext: () => _stepHit(1),
            onPrevious: () => _stepHit(-1),
            onClose: _closeSearch,
          ),
        ),
      if (_controller.tool == CanvasTool.connect ||
          _controller.tool == CanvasTool.draw ||
          _controller.tool == CanvasTool.frame)
        Positioned(
          left: 0,
          right: 0,
          top: CanvasMetrics.space4,
          child: Align(
            child: CanvasHintBar(
              palette: palette,
              message: switch (_controller.tool) {
                CanvasTool.connect => LocaleKeys.canvas_hint_connectFrom.tr(),
                CanvasTool.draw => LocaleKeys.canvas_hint_drawing.tr(),
                _ => LocaleKeys.canvas_hint_framing.tr(),
              },
              onDismiss: () => _controller.setTool(CanvasTool.select),
            ),
          ),
        ),
      if (_controller.selection.length > 1 && widget.editable)
        Positioned(
          left: 0,
          right: 0,
          top: CanvasMetrics.space4,
          child: Align(
            child: _SelectionBar(
              palette: palette,
              controller: _controller,
              onChanged: _refresh,
              onConnect: _connectSelected,
            ),
          ),
        ),
    ];
  }
}

/// What appears when several things are selected: the actions that only make
/// sense for a group, where they can be reached without a right click.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.palette,
    required this.controller,
    required this.onChanged,
    required this.onConnect,
  });

  final CanvasPalette palette;
  final CanvasController controller;
  final VoidCallback onChanged;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    void run(VoidCallback action) {
      action();
      onChanged();
    }

    return CanvasSurface(
      palette: palette,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: CanvasMetrics.space2),
            child: Text(
              '${controller.selection.length}',
              style: canvasLabelStyle(palette, size: 11.5),
            ),
          ),
          CanvasButton(
            icon: Icons.align_horizontal_left_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_align_left.tr(),
            onPressed: () =>
                run(() => controller.alignSelection(CanvasAlign.left)),
          ),
          CanvasButton(
            icon: Icons.align_vertical_top_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_align_top.tr(),
            onPressed: () =>
                run(() => controller.alignSelection(CanvasAlign.top)),
          ),
          CanvasButton(
            icon: Icons.horizontal_distribute_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_align_distributeHorizontally.tr(),
            onPressed: () => run(
              () => controller.distributeSelection(CanvasAxis.horizontal),
            ),
          ),
          CanvasButton(
            icon: Icons.timeline_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_toolbar_connect.tr(),
            onPressed: () => run(onConnect),
          ),
          CanvasButton(
            icon: Icons.crop_free_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_menu_group.tr(),
            onPressed: () => run(() => controller.groupSelection()),
          ),
          Builder(
            builder: (context) => CanvasButton(
              icon: Icons.palette_rounded,
              palette: palette,
              size: 28,
              iconSize: 16,
              tooltip: LocaleKeys.canvas_menu_colour.tr(),
              onPressed: () {
                final box = context.findRenderObject() as RenderBox?;
                showAppMenu<void>(
                  context: context,
                  globalPosition: box == null
                      ? Offset.zero
                      : box.localToGlobal(Offset(0, box.size.height + 6)),
                  entries: [
                    AppMenuCustom(
                      builder: (context) => CanvasSwatchRow(
                        palette: palette,
                        onPicked: (colour) {
                          controller.colourSelection(colour);
                          onChanged();
                          AppMenuScope.maybeOf(context)?.close();
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          CanvasButton(
            icon: Icons.delete_outline_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_menu_delete.tr(),
            onPressed: () => run(controller.deleteSelection),
          ),
        ],
      ),
    );
  }
}

/// The layer the cards are laid out in.
///
/// ⚠️ It exists for ONE reason: `RenderBox.hitTest` refuses a position that
/// falls outside a box, and the cards are laid out in scene units, which reach
/// far beyond the viewport. Laid out inside an ordinary box, every card past
/// the first screenful is painted perfectly and is completely dead to the
/// pointer — no click, no double click, no right click. So the child is given
/// the whole scene to be laid out in, while the layer itself still fills the
/// viewport, and the bounds check is dropped.
class _CanvasCardLayer extends SingleChildRenderObjectWidget {
  const _CanvasCardLayer({required this.layerSize, required super.child});

  final Size layerSize;

  @override
  _RenderCanvasCardLayer createRenderObject(BuildContext context) =>
      _RenderCanvasCardLayer(layerSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCanvasCardLayer renderObject,
  ) =>
      renderObject.layerSize = layerSize;
}

class _RenderCanvasCardLayer extends RenderProxyBox {
  _RenderCanvasCardLayer(this._layerSize);

  Size _layerSize;

  set layerSize(Size value) {
    if (_layerSize == value) {
      return;
    }
    _layerSize = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(BoxConstraints.tight(_layerSize));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);
}

/// The canvas surface's own pan. Ties with a scroll view at the hit slop so an
/// embedded canvas can be dragged in every direction, and declines pan-zoom so
/// two fingers on a trackpad reach the camera instead.
class _SurfacePanRecognizer extends PanGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      computeHitSlop(pointerDeviceKind, gestureSettings);

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}
}

class _SurfaceTapRecognizer extends TapGestureRecognizer {}
