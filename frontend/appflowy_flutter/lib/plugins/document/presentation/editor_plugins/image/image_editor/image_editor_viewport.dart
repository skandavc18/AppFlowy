import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'image_edit_pipeline.dart';
import 'image_edit_settings.dart';
import 'image_editor_theme.dart';

enum ImageEditorMode { view, crop, annotate }

/// The area the photo lives in: zoom, pan, crop handles and annotation
/// capture. Everything is painted by one [CustomPaint] so the picture stays
/// the only thing that moves.
class ImageEditorViewport extends StatefulWidget {
  const ImageEditorViewport({
    super.key,
    required this.image,
    required this.settings,
    required this.mode,
    required this.palette,
    required this.annotationTool,
    required this.annotationColor,
    required this.annotationStrokeWidth,
    required this.annotationText,
    required this.onCropChanged,
    required this.onAnnotationAdded,
    required this.onInteractionEnd,
    required this.onZoomChanged,
  });

  final ui.Image image;
  final ImageEditSettings settings;
  final ImageEditorMode mode;
  final ImageEditorPalette palette;
  final ImageAnnotationTool annotationTool;
  final Color annotationColor;
  final double annotationStrokeWidth;
  final String annotationText;
  final ValueChanged<Rect> onCropChanged;
  final ValueChanged<ImageAnnotation> onAnnotationAdded;
  final VoidCallback onInteractionEnd;
  final ValueChanged<double> onZoomChanged;

  @override
  State<ImageEditorViewport> createState() => ImageEditorViewportState();
}

enum _CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
  move,
}

class ImageEditorViewportState extends State<ImageEditorViewport>
    with SingleTickerProviderStateMixin {
  static const double _minZoom = 0.15;
  static const double _maxZoom = 24;
  static const double _fitPadding = 48;

  final FocusNode _focusNode = FocusNode(debugLabel: 'image_editor_viewport');

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: ImageEditorMotion.fast,
  )..addListener(_onAnimationTick);

  double _zoom = 1;
  Offset _pan = Offset.zero;

  double _zoomFrom = 1;
  double _zoomTo = 1;
  Offset _panFrom = Offset.zero;
  Offset _panTo = Offset.zero;

  Size _viewportSize = Size.zero;
  bool _spaceHeld = false;

  int? _panPointer;
  Offset? _panPointerPosition;
  double _panZoomStartZoom = 1;

  _CropHandle? _activeHandle;
  Rect? _cropAtDragStart;
  Offset? _dragStartNormalized;

  List<Offset>? _draftPoints;

  @override
  void dispose() {
    _animation.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ImageEditorViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Entering or leaving crop swaps the displayed frame, and a rotation
    // changes its aspect, so both have to refit.
    if (oldWidget.mode != widget.mode ||
        oldWidget.settings.transform.quarterTurns !=
            widget.settings.transform.quarterTurns) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          fit();
        }
      });
    }
  }

  void _onAnimationTick() {
    setState(() {
      final t = Curves.easeOutCubic.transform(_animation.value);
      _zoom = ui.lerpDouble(_zoomFrom, _zoomTo, t)!;
      _pan = Offset.lerp(_panFrom, _panTo, t)!;
    });
    widget.onZoomChanged(effectiveScale);
  }

  /// The scale the photo is displayed at relative to its own pixels.
  double get effectiveScale => _fitScale * _zoom;

  ImageEditSettings get _displaySettings => widget.mode == ImageEditorMode.crop
      ? widget.settings.copyWith(
          transform: widget.settings.transform
              .copyWith(crop: const Rect.fromLTRB(0, 0, 1, 1)),
        )
      : widget.settings;

  ImageEditGeometry get _geometry => ImageEditGeometry.forImage(
        widget.image,
        _displaySettings.transform,
      );

  Size get _displaySize => _geometry.outputSize;

  double get _fitScale {
    if (_viewportSize.isEmpty) {
      return 1;
    }
    final available = Size(
      math.max(1, _viewportSize.width - _fitPadding * 2),
      math.max(1, _viewportSize.height - _fitPadding * 2),
    );
    final size = _displaySize;
    return math.min(
      available.width / size.width,
      available.height / size.height,
    );
  }

  Rect get photoRect {
    final size = _displaySize * effectiveScale;
    final center = Offset(
          _viewportSize.width / 2,
          _viewportSize.height / 2,
        ) +
        _pan;
    return Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
  }

  void fit() {
    _animateTo(1, Offset.zero);
  }

  void zoomToActualPixels() {
    _animateTo(1 / _fitScale, Offset.zero);
  }

  void zoomBy(double factor) {
    _animateTo(_zoom * factor, _pan);
  }

  void _animateTo(double zoom, Offset pan) {
    _zoomFrom = _zoom;
    _panFrom = _pan;
    _zoomTo = zoom.clamp(_minZoom, _maxZoom);
    _panTo = _clampPan(pan, _zoomTo);
    _animation.forward(from: 0);
  }

  void _setTransform(double zoom, Offset pan) {
    if (_animation.isAnimating) {
      _animation.stop();
    }
    setState(() {
      _zoom = zoom.clamp(_minZoom, _maxZoom);
      _pan = _clampPan(pan, _zoom);
    });
    widget.onZoomChanged(effectiveScale);
  }

  /// Keeps a decent part of the photo on screen without snapping it back.
  Offset _clampPan(Offset pan, double zoom) {
    if (_viewportSize.isEmpty) {
      return pan;
    }
    final size = _displaySize * (_fitScale * zoom);
    final limitX = math.max(size.width, _viewportSize.width) / 2;
    final limitY = math.max(size.height, _viewportSize.height) / 2;
    return Offset(
      pan.dx.clamp(-limitX, limitX),
      pan.dy.clamp(-limitY, limitY),
    );
  }

  void _zoomAround(Offset focalPoint, double targetZoom, {bool animate = true}) {
    final clamped = targetZoom.clamp(_minZoom, _maxZoom);
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    // Keep whatever sits under the pointer pinned in place.
    final anchor = focalPoint - center - _pan;
    final nextPan = _pan - anchor * (clamped / _zoom - 1);
    if (animate) {
      _animateTo(clamped, nextPan);
    } else {
      _setTransform(clamped, nextPan);
    }
  }

  Offset _toNormalized(Offset local) {
    final rect = photoRect;
    if (rect.width <= 0 || rect.height <= 0) {
      return Offset.zero;
    }
    return Offset(
      ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  bool get _panModifierHeld => _spaceHeld;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _viewportSize) {
            _viewportSize = size;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                widget.onZoomChanged(effectiveScale);
              }
            });
          }
          return MouseRegion(
            cursor: _cursor,
            onEnter: (_) => _focusNode.requestFocus(),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: _onPointerSignal,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              onPointerPanZoomStart: _onPanZoomStart,
              onPointerPanZoomUpdate: _onPanZoomUpdate,
              onPointerPanZoomEnd: _onPanZoomEnd,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _onDoubleTap,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _ViewportPainter(
                      image: widget.image,
                      settings: _displaySettings,
                      photoRect: photoRect,
                      mode: widget.mode,
                      cropRect: widget.settings.transform.crop,
                      draft: _draftAnnotation(),
                      shadow: palette.shadow,
                      handleColor: const Color(0xFFFFFFFF),
                      gridColor: const Color(0x66FFFFFF),
                      shadeColor: const Color(0x99000000),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  MouseCursor get _cursor {
    if (_panModifierHeld || _panPointer != null) {
      return SystemMouseCursors.grabbing;
    }
    return switch (widget.mode) {
      ImageEditorMode.view => SystemMouseCursors.basic,
      ImageEditorMode.crop => SystemMouseCursors.precise,
      ImageEditorMode.annotate => SystemMouseCursors.precise,
    };
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        setState(() => _spaceHeld = true);
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        setState(() => _spaceHeld = false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onDoubleTap() {
    // First double click fits, the next one goes to actual pixels.
    if ((effectiveScale - 1).abs() < 0.01) {
      fit();
    } else {
      zoomToActualPixels();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }
    _zoomAround(
      event.localPosition,
      _zoom * math.exp(-delta * 0.0016),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _focusNode.requestFocus();
    final isMiddle = event.buttons & kMiddleMouseButton != 0;
    final isPrimary = event.buttons & kPrimaryMouseButton != 0;

    if (isMiddle || (_panModifierHeld && isPrimary)) {
      _panPointer = event.pointer;
      _panPointerPosition = event.localPosition;
      return;
    }

    if (!isPrimary) {
      return;
    }

    switch (widget.mode) {
      case ImageEditorMode.view:
        _panPointer = event.pointer;
        _panPointerPosition = event.localPosition;
      case ImageEditorMode.crop:
        _beginCrop(event);
      case ImageEditorMode.annotate:
        _beginAnnotation(event);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _panPointer) {
      final previous = _panPointerPosition ?? event.localPosition;
      _panPointerPosition = event.localPosition;
      _setTransform(_zoom, _pan + (event.localPosition - previous));
      return;
    }
    if (_activeHandle != null) {
      _updateCrop(event.localPosition);
      return;
    }
    if (_draftPoints != null) {
      _updateAnnotation(event.localPosition);
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer == _panPointer) {
      _panPointer = null;
      _panPointerPosition = null;
      return;
    }
    if (_activeHandle != null) {
      _activeHandle = null;
      _cropAtDragStart = null;
      _dragStartNormalized = null;
      widget.onInteractionEnd();
      return;
    }
    if (_draftPoints != null) {
      _commitAnnotation();
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomStartZoom = _zoom;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    // Trackpads deliver both at once; applying them directly keeps the
    // platform's own physics instead of layering another curve on top.
    final zoom = _panZoomStartZoom * event.scale;
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final anchor = event.localPosition - center - _pan;
    final scaled = _pan - anchor * (zoom / _zoom - 1);
    _setTransform(zoom, scaled + event.localPanDelta);
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    _panZoomStartZoom = _zoom;
  }

  // ---------------------------------------------------------------- cropping

  void _beginCrop(PointerDownEvent event) {
    final rect = photoRect;
    final crop = widget.settings.transform.crop;
    final cropRect = Rect.fromLTRB(
      rect.left + crop.left * rect.width,
      rect.top + crop.top * rect.height,
      rect.left + crop.right * rect.width,
      rect.top + crop.bottom * rect.height,
    );
    final handle = _hitTestHandle(event.localPosition, cropRect);
    if (handle == null) {
      // Outside the frame the drag pans, which matches every photo app.
      _panPointer = event.pointer;
      _panPointerPosition = event.localPosition;
      return;
    }
    _activeHandle = handle;
    _cropAtDragStart = crop;
    _dragStartNormalized = _toNormalized(event.localPosition);
  }

  _CropHandle? _hitTestHandle(Offset position, Rect cropRect) {
    const tolerance = 22.0;
    final nearLeft = (position.dx - cropRect.left).abs() < tolerance;
    final nearRight = (position.dx - cropRect.right).abs() < tolerance;
    final nearTop = (position.dy - cropRect.top).abs() < tolerance;
    final nearBottom = (position.dy - cropRect.bottom).abs() < tolerance;
    final withinX = position.dx > cropRect.left - tolerance &&
        position.dx < cropRect.right + tolerance;
    final withinY = position.dy > cropRect.top - tolerance &&
        position.dy < cropRect.bottom + tolerance;

    if (nearLeft && nearTop) return _CropHandle.topLeft;
    if (nearRight && nearTop) return _CropHandle.topRight;
    if (nearLeft && nearBottom) return _CropHandle.bottomLeft;
    if (nearRight && nearBottom) return _CropHandle.bottomRight;
    if (nearLeft && withinY) return _CropHandle.left;
    if (nearRight && withinY) return _CropHandle.right;
    if (nearTop && withinX) return _CropHandle.top;
    if (nearBottom && withinX) return _CropHandle.bottom;
    if (cropRect.contains(position)) return _CropHandle.move;
    return null;
  }

  void _updateCrop(Offset position) {
    final start = _cropAtDragStart;
    final origin = _dragStartNormalized;
    final handle = _activeHandle;
    if (start == null || origin == null || handle == null) {
      return;
    }
    final current = _toNormalized(position);
    final delta = current - origin;
    const minSize = 0.04;

    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;

    switch (handle) {
      case _CropHandle.move:
        final dx = delta.dx.clamp(-start.left, 1 - start.right);
        final dy = delta.dy.clamp(-start.top, 1 - start.bottom);
        left += dx;
        right += dx;
        top += dy;
        bottom += dy;
      case _CropHandle.left:
        left = (start.left + delta.dx).clamp(0.0, right - minSize);
      case _CropHandle.right:
        right = (start.right + delta.dx).clamp(left + minSize, 1.0);
      case _CropHandle.top:
        top = (start.top + delta.dy).clamp(0.0, bottom - minSize);
      case _CropHandle.bottom:
        bottom = (start.bottom + delta.dy).clamp(top + minSize, 1.0);
      case _CropHandle.topLeft:
        left = (start.left + delta.dx).clamp(0.0, right - minSize);
        top = (start.top + delta.dy).clamp(0.0, bottom - minSize);
      case _CropHandle.topRight:
        right = (start.right + delta.dx).clamp(left + minSize, 1.0);
        top = (start.top + delta.dy).clamp(0.0, bottom - minSize);
      case _CropHandle.bottomLeft:
        left = (start.left + delta.dx).clamp(0.0, right - minSize);
        bottom = (start.bottom + delta.dy).clamp(top + minSize, 1.0);
      case _CropHandle.bottomRight:
        right = (start.right + delta.dx).clamp(left + minSize, 1.0);
        bottom = (start.bottom + delta.dy).clamp(top + minSize, 1.0);
    }

    var next = Rect.fromLTRB(left, top, right, bottom);
    final ratio = widget.settings.transform.ratio
        .resolve(_geometry.orientedSize.aspectRatio);
    if (ratio != null && handle != _CropHandle.move) {
      next = _applyRatio(next, handle, ratio);
    }
    widget.onCropChanged(next);
  }

  /// Rebuilds [rect] so that its rendered shape matches [ratio], anchored on
  /// the edge opposite the handle being dragged.
  Rect _applyRatio(Rect rect, _CropHandle handle, double ratio) {
    final oriented = _geometry.orientedSize;
    // Normalized space is not square, so convert through pixels.
    var width = rect.width * oriented.width;
    var height = rect.height * oriented.height;
    if (width / height > ratio) {
      width = height * ratio;
    } else {
      height = width / ratio;
    }
    final normalizedWidth = (width / oriented.width).clamp(0.0, 1.0);
    final normalizedHeight = (height / oriented.height).clamp(0.0, 1.0);

    final anchorRight = handle == _CropHandle.left ||
        handle == _CropHandle.topLeft ||
        handle == _CropHandle.bottomLeft;
    final anchorBottom = handle == _CropHandle.top ||
        handle == _CropHandle.topLeft ||
        handle == _CropHandle.topRight;

    var left = anchorRight ? rect.right - normalizedWidth : rect.left;
    var top = anchorBottom ? rect.bottom - normalizedHeight : rect.top;
    left = left.clamp(0.0, 1 - normalizedWidth);
    top = top.clamp(0.0, 1 - normalizedHeight);
    return Rect.fromLTWH(left, top, normalizedWidth, normalizedHeight);
  }

  /// Recomputes a centred crop that honours [ratio]; used by the ratio chips.
  static Rect centeredCropForRatio(Size orientedSize, double? ratio) {
    if (ratio == null) {
      return const Rect.fromLTRB(0, 0, 1, 1);
    }
    var width = orientedSize.width;
    var height = width / ratio;
    if (height > orientedSize.height) {
      height = orientedSize.height;
      width = height * ratio;
    }
    final normalizedWidth = width / orientedSize.width;
    final normalizedHeight = height / orientedSize.height;
    return Rect.fromLTWH(
      (1 - normalizedWidth) / 2,
      (1 - normalizedHeight) / 2,
      normalizedWidth,
      normalizedHeight,
    );
  }

  // ------------------------------------------------------------- annotations

  void _beginAnnotation(PointerDownEvent event) {
    final normalized = _toNormalized(event.localPosition);
    if (!photoRect.contains(event.localPosition)) {
      _panPointer = event.pointer;
      _panPointerPosition = event.localPosition;
      return;
    }
    setState(() => _draftPoints = [normalized, normalized]);
  }

  void _updateAnnotation(Offset position) {
    final points = _draftPoints;
    if (points == null) {
      return;
    }
    final normalized = _toNormalized(position);
    setState(() {
      if (widget.annotationTool == ImageAnnotationTool.freehand) {
        points.add(normalized);
      } else {
        points[points.length - 1] = normalized;
      }
    });
  }

  void _commitAnnotation() {
    final points = _draftPoints;
    setState(() => _draftPoints = null);
    if (points == null || points.isEmpty) {
      return;
    }
    final tool = widget.annotationTool;
    final isPlacement = tool == ImageAnnotationTool.text ||
        tool == ImageAnnotationTool.marker;
    if (!isPlacement &&
        (points.first - points.last).distance < 0.008 &&
        tool != ImageAnnotationTool.freehand) {
      return;
    }
    if (tool == ImageAnnotationTool.text && widget.annotationText.isEmpty) {
      return;
    }
    widget.onAnnotationAdded(
      ImageAnnotation(
        id: DateTime.now().microsecondsSinceEpoch,
        tool: tool,
        points: isPlacement ? [points.first] : List<Offset>.from(points),
        color: widget.annotationColor,
        strokeWidth: widget.annotationStrokeWidth,
        text: tool == ImageAnnotationTool.text ? widget.annotationText : null,
      ),
    );
    widget.onInteractionEnd();
  }

  ImageAnnotation? _draftAnnotation() {
    final points = _draftPoints;
    if (points == null || points.isEmpty) {
      return null;
    }
    return ImageAnnotation(
      id: -1,
      tool: widget.annotationTool,
      points: points,
      color: widget.annotationColor,
      strokeWidth: widget.annotationStrokeWidth,
      text: widget.annotationText,
    );
  }
}

class _ViewportPainter extends CustomPainter {
  const _ViewportPainter({
    required this.image,
    required this.settings,
    required this.photoRect,
    required this.mode,
    required this.cropRect,
    required this.draft,
    required this.shadow,
    required this.handleColor,
    required this.gridColor,
    required this.shadeColor,
  });

  final ui.Image image;
  final ImageEditSettings settings;
  final Rect photoRect;
  final ImageEditorMode mode;
  final Rect cropRect;
  final ImageAnnotation? draft;
  final Color shadow;
  final Color handleColor;
  final Color gridColor;
  final Color shadeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (photoRect.isEmpty) {
      return;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        photoRect.inflate(1),
        const Radius.circular(3),
      ),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );

    paintEditedImage(canvas, image, photoRect, settings);

    if (draft != null) {
      paintAnnotations(canvas, photoRect, [draft!]);
    }

    if (mode == ImageEditorMode.crop) {
      _paintCropOverlay(canvas, size);
    }
  }

  void _paintCropOverlay(Canvas canvas, Size size) {
    final frame = Rect.fromLTRB(
      photoRect.left + cropRect.left * photoRect.width,
      photoRect.top + cropRect.top * photoRect.height,
      photoRect.left + cropRect.right * photoRect.width,
      photoRect.top + cropRect.bottom * photoRect.height,
    );

    canvas.save();
    canvas.clipRect(frame, clipOp: ui.ClipOp.difference);
    canvas.drawRect(photoRect, Paint()..color = shadeColor);
    canvas.restore();

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final dx = frame.left + frame.width * i / 3;
      final dy = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(dx, frame.top), Offset(dx, frame.bottom), gridPaint);
      canvas.drawLine(Offset(frame.left, dy), Offset(frame.right, dy), gridPaint);
    }

    canvas.drawRect(
      frame,
      Paint()
        ..color = handleColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    const armLength = 20.0;
    const armThickness = 3.0;
    final handlePaint = Paint()..color = handleColor;
    void corner(Offset origin, double dx, double dy) {
      canvas.drawRect(
        Rect.fromLTWH(
          dx > 0 ? origin.dx : origin.dx - armLength,
          dy > 0 ? origin.dy : origin.dy - armThickness,
          armLength,
          armThickness,
        ),
        handlePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          dx > 0 ? origin.dx : origin.dx - armThickness,
          dy > 0 ? origin.dy : origin.dy - armLength,
          armThickness,
          armLength,
        ),
        handlePaint,
      );
    }

    corner(frame.topLeft, 1, 1);
    corner(frame.topRight, -1, 1);
    corner(frame.bottomLeft, 1, -1);
    corner(frame.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_ViewportPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.settings != settings ||
      oldDelegate.photoRect != photoRect ||
      oldDelegate.mode != mode ||
      oldDelegate.cropRect != cropRect ||
      oldDelegate.draft != draft;
}
