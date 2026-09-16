import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_hover_suppression.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Only the page's rail uses projected metrics. The lazy editor, its physics,
/// selection/anchor APIs and nested viewers keep their original controllers.
class EditorPageScrollBehavior extends NoScrollbarBehavior {
  const EditorPageScrollBehavior(super.parent);

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final decorated = parent.buildScrollbar(context, child, details);
    final platform = getPlatform(context);
    if (identical(decorated, child) ||
        details.controller == null ||
        axisDirectionToAxis(details.direction) != Axis.vertical ||
        (platform != TargetPlatform.windows &&
            platform != TargetPlatform.linux &&
            platform != TargetPlatform.macOS)) {
      return decorated;
    }
    return EditorPageScrollbar(
      controller: details.controller!,
      child: child,
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      ScrollHoverSuppression(
        child: parent.buildOverscrollIndicator(context, child, details),
      );
}

/// A stable-width page rail. Lazy SliverLists revise their total-height estimate
/// as blocks are measured; feeding each estimate straight to the painter makes
/// the thumb jump backwards even while content scrolls forwards.
class EditorPageScrollbar extends RawScrollbar {
  const EditorPageScrollbar({
    super.key,
    required ScrollController controller,
    required super.child,
  }) : super(
          controller: controller,
          thickness: 4,
          radius: const Radius.circular(10),
          minThumbLength: 48,
          mainAxisMargin: 6,
        );

  @override
  RawScrollbarState<EditorPageScrollbar> createState() =>
      _EditorPageScrollbarState();
}

class _EditorPageScrollbarState extends RawScrollbarState<EditorPageScrollbar> {
  final _projection = EditorScrollbarMetrics();
  ScrollMetrics? _latest;
  bool _hovered = false;
  bool _dragging = false;
  bool _disposing = false;
  Drag? _pageDrag;
  Offset? _dragOrigin;
  double _dragThumbOffset = 0;

  Set<WidgetState> get _states => {
        if (_hovered) WidgetState.hovered,
        if (_dragging) WidgetState.dragged,
      };

  @override
  bool get showScrollbar =>
      _dragging ||
      (ScrollbarTheme.of(context).thumbVisibility?.resolve(_states) ?? false);

  @override
  void initState() {
    super.initState();
    scrollbarPainter.fadeoutOpacityAnimation.addStatusListener(_onFade);
  }

  void _onFade(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_dragging && _latest != null) {
      // Refresh mapping AND paint while invisible, not on the next hover.
      _updateMetrics(_latest!, reset: true);
    }
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    scrollbarPainter.color =
        ScrollbarTheme.of(context).thumbColor?.resolve(_states) ??
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.46);
  }

  void _updateMetrics(ScrollMetrics metrics, {bool reset = false}) {
    if (reset) _projection.reset();
    _latest = metrics;
    scrollbarPainter.update(
      _projection.project(metrics),
      metrics.axisDirection,
    );
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            _updateMetrics(
              notification.metrics,
              // Index navigation can re-anchor the lazy list at pixels=0
              // without dispatching a scroll update. Adopt its NEW dimensions.
              reset: !_dragging &&
                  !widget.controller!.position.isScrollingNotifier.value,
            );
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) {
              final position = widget.controller!.position;
              _updateMetrics(
                notification.metrics,
                // jumpTo/selection navigation is deliberate, not estimation
                // drift. Such updates are dispatched while the position is idle.
                reset: notification is ScrollUpdateNotification &&
                    !position.isScrollingNotifier.value,
              );
            }
            // Ancestors (embed loading, selection, etc.) still see REAL metrics.
            return false;
          },
          // Let RawScrollbar handle visibility and gestures first, then replace
          // only its painter's metrics before the same frame is painted.
          child: Listener(
            onPointerCancel: (_) => _pageDrag?.cancel(),
            child: super.build(context),
          ),
        ),
      );

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final hovered = isPointerOverScrollbar(
      event.position,
      event.kind,
      forHover: true,
    );
    if (hovered != _hovered) setState(() => _hovered = hovered);
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    _dragOrigin = localPosition;
    // Flutter's getThumbScrollOffset assumes a zero minimum. Indexed editor
    // navigation also uses negative ranges, so start from normalized pixels.
    final metrics = _projection.project(_latest!);
    _dragThumbOffset = metrics.pixels / scrollbarPainter.getTrackToScroll(1);
    final box = context.findRenderObject()! as RenderBox;
    // Replace RawScrollbar's drag with one we can feed real DragUpdateDetails
    // before setting mapped pixels. This preserves notifications/cancellation
    // without applying the page's trackpad gain to the mouse thumb.
    _pageDrag = widget.controller!.position.drag(
      DragStartDetails(
        localPosition: localPosition,
        globalPosition: box.localToGlobal(localPosition),
      ),
      _cancelPageDrag,
    );
    setState(() => _dragging = true);
  }

  @override
  void handleThumbPressUpdate(Offset localPosition) {
    final origin = _dragOrigin;
    final drag = _pageDrag;
    if (origin == null || drag == null || _latest == null) return;
    // Retain RawScrollbar's drag/hold lifecycle, but do not feed display-space
    // metrics to the document or apply trackpad gain to mouse thumb distance.
    super.handleThumbPressUpdate(origin);
    final position = widget.controller!.position;
    final sign = axisDirectionIsReversed(position.axisDirection) ? -1 : 1;
    final displayed = scrollbarPainter.getTrackToScroll(
      _dragThumbOffset + sign * (localPosition.dy - origin.dy),
    );
    final box = context.findRenderObject()! as RenderBox;
    drag.update(
      DragUpdateDetails(
        primaryDelta: 0,
        localPosition: localPosition,
        globalPosition: box.localToGlobal(localPosition),
      ),
    );
    if (position is ScrollActivityDelegate) {
      (position as ScrollActivityDelegate).setPixels(
        _projection.scrollPixelsFor(displayed).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
      );
    }
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    final drag = _pageDrag;
    _cancelPageDrag();
    drag?.end(DragEndDetails());
  }

  void _cancelPageDrag() {
    _pageDrag = null;
    _dragOrigin = null;
    if (!_dragging) return;
    _dragging = false;
    if (_disposing || !mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _pageDrag?.cancel();
    scrollbarPainter.fadeoutOpacityAnimation.removeStatusListener(_onFade);
    super.dispose();
  }
}

/// A piecewise-linear display mapping anchored at the last visible position.
/// Estimate changes alter future slope, never the current thumb position or
/// length. Real endpoints, viewport resizes and explicit jumps remain exact.
@visibleForTesting
class EditorScrollbarMetrics {
  ScrollMetrics? _previous;
  double _anchorPixels = 0;
  double _anchorFraction = 0;
  double _displayRange = 0;

  void reset() => _previous = null;

  ScrollMetrics project(ScrollMetrics metrics) {
    final previous = _previous;
    final range = metrics.maxScrollExtent - metrics.minScrollExtent;
    if (previous == null ||
        previous.maxScrollExtent <= previous.minScrollExtent ||
        previous.viewportDimension != metrics.viewportDimension ||
        previous.axisDirection != metrics.axisDirection ||
        !range.isFinite ||
        range <= 0) {
      _displayRange = range.isFinite ? range.clamp(0, double.infinity) : 0;
      _anchorPixels = metrics.pixels;
      _anchorFraction = range > 0
          ? ((metrics.pixels - metrics.minScrollExtent) / range).clamp(0, 1)
          : 0;
    } else if (previous.minScrollExtent != metrics.minScrollExtent ||
        previous.maxScrollExtent != metrics.maxScrollExtent) {
      _anchorFraction = _fraction(metrics.pixels);
      _anchorPixels = metrics.pixels;
      if ((_anchorFraction == 0 || _anchorFraction == 1) &&
          metrics.pixels > metrics.minScrollExtent &&
          metrics.pixels < metrics.maxScrollExtent) {
        // A real endpoint became interior after content growth. It must not
        // pin the newly scrollable interval to the end of the rail.
        _anchorFraction = (metrics.pixels - metrics.minScrollExtent) / range;
        _displayRange = range;
      }
    }
    _previous = metrics.copyWith();
    return FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: _displayRange,
      pixels: _fraction(metrics.pixels) * _displayRange,
      viewportDimension: metrics.viewportDimension,
      axisDirection: metrics.axisDirection,
      devicePixelRatio: metrics.devicePixelRatio,
    );
  }

  double _fraction(double pixels) {
    final metrics = _previous;
    if (metrics == null || pixels <= metrics.minScrollExtent) return 0;
    if (pixels >= metrics.maxScrollExtent) return 1;
    if (pixels >= _anchorPixels) {
      final remaining = metrics.maxScrollExtent - _anchorPixels;
      return remaining <= 0
          ? 1
          : (_anchorFraction +
                  (1 - _anchorFraction) * (pixels - _anchorPixels) / remaining)
              .clamp(0, 1);
    }
    final before = _anchorPixels - metrics.minScrollExtent;
    return before <= 0
        ? 0
        : (_anchorFraction * (pixels - metrics.minScrollExtent) / before)
            .clamp(0, 1);
  }

  double scrollPixelsFor(double displayedPixels) {
    final metrics = _previous!;
    final fraction = _displayRange > 0
        ? (displayedPixels / _displayRange).clamp(0.0, 1.0)
        : 0.0;
    if (fraction <= 0) return metrics.minScrollExtent;
    if (fraction >= 1) return metrics.maxScrollExtent;
    if (fraction >= _anchorFraction && _anchorFraction < 1) {
      return _anchorPixels +
          (metrics.maxScrollExtent - _anchorPixels) *
              (fraction - _anchorFraction) /
              (1 - _anchorFraction);
    }
    return metrics.minScrollExtent +
        (_anchorPixels - metrics.minScrollExtent) * fraction / _anchorFraction;
  }
}
