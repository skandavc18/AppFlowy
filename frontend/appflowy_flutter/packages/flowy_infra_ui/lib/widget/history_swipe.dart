import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Labels and surfaces shared by workspace and embedded-browser navigation.
class HistorySwipeTheme extends InheritedWidget {
  const HistorySwipeTheme({
    super.key,
    required super.child,
    required this.surface,
    this.back = 'Back',
    this.forward = 'Forward',
    this.noPrevious = 'No previous page',
    this.noNext = 'No next page',
    this.allowPreviews = true,
  });

  final Color surface;
  final String back;
  final String forward;
  final String noPrevious;
  final String noNext;
  final bool allowPreviews;

  static HistorySwipeTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HistorySwipeTheme>();

  @override
  bool updateShouldNotify(HistorySwipeTheme oldWidget) =>
      surface != oldWidget.surface ||
      back != oldWidget.back ||
      forward != oldWidget.forward ||
      noPrevious != oldWidget.noPrevious ||
      noNext != oldWidget.noNext ||
      allowPreviews != oldWidget.allowPreviews;
}

/// Small, memory-only LRU. Images are never written to disk or uploaded.
class HistorySwipePreviewCache {
  HistorySwipePreviewCache(
      {this.capacity = 4, this.maxBytes = 16 * 1024 * 1024})
      : assert(capacity > 0),
        assert(maxBytes > 0);

  final int capacity;
  final int maxBytes;
  final _images = <Object, ui.Image>{};
  int _bytes = 0;

  int get length => _images.length;
  int get bytes => _bytes;

  /// Transfers ownership to the cache. Readers receive independent handles.
  void store(Object key, ui.Image image) {
    final old = _images.remove(key);
    if (old != null) _release(old);
    final size = image.width * image.height * 4;
    if (size > maxBytes) {
      image.dispose();
      return;
    }
    _images[key] = image;
    _bytes += size;
    while (_images.length > capacity || _bytes > maxBytes) {
      _release(_images.remove(_images.keys.first)!);
    }
  }

  ui.Image? read(Object? key) {
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key!] = image;
    return image.clone();
  }

  void _release(ui.Image image) {
    _bytes -= image.width * image.height * 4;
    image.dispose();
  }

  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
  }
}

/// One controller per navigation surface, not per history entry.
class HistorySwipeController {
  final previews = HistorySwipePreviewCache();
  _HistorySwipeSurfaceState? _state;

  bool get isActive => _state?._active ?? false;
  bool get isSettling => _state?._settling ?? false;

  void begin(
          {required bool forward, required bool available, Object? target}) =>
      _state?._begin(forward: forward, available: available, target: target);

  void update(double distance) => _state?._update(distance);

  Future<void> finish({
    required bool commit,
    required bool Function() isValid,
    required FutureOr<void> Function() navigate,
  }) async =>
      _state?._finish(commit: commit, isValid: isValid, navigate: navigate);

  void cancel() => _state?._cancel();

  /// Useful before a native renderer changes its pixels on navigation.
  void captureCurrent() => _state?._capture(_state?.widget.pageKey);

  void clearPreviews() {
    _state?._reset();
    previews.clear();
  }

  void dispose() {
    _state = null;
    previews.clear();
  }
}

/// A paint-only, finger-following page sheet with resisted history edges.
/// The live child stays mounted; previews are inert images, never live editors.
class HistorySwipeSurface extends StatefulWidget {
  const HistorySwipeSurface({
    super.key,
    required this.controller,
    required this.child,
    this.pageKey,
    this.scope,
    this.allowPreviews = true,
    this.pageReady = true,
    this.captureOnPageChange = true,
  });

  final HistorySwipeController controller;
  final Widget child;
  final Object? pageKey;
  final Object? scope;
  final bool allowPreviews;
  final bool pageReady;
  final bool captureOnPageChange;

  @override
  State<HistorySwipeSurface> createState() => _HistorySwipeSurfaceState();
}

class _HistorySwipeSurfaceState extends State<HistorySwipeSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _boundary = GlobalKey();
  late final AnimationController _motion;
  ThemeData? _theme;
  ui.Image? _preview;
  Completer<void>? _arrival;
  Timer? _edgeDismiss;
  bool _active = false;
  bool _settling = false;
  bool _navigating = false;
  bool _forward = false;
  bool _available = false;
  bool _reducedMotion = false;
  bool _previewsAllowed = true;
  double _distance = 0;
  double _width = 1;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _motion = AnimationController.unbounded(vsync: this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final allowed = HistorySwipeTheme.maybeOf(context)?.allowPreviews ?? true;
    if ((_theme != null && _theme != theme) ||
        reduced != _reducedMotion ||
        allowed != _previewsAllowed) {
      _reset(rebuild: false);
      widget.controller.previews.clear();
    }
    _theme = theme;
    _reducedMotion = reduced;
    _previewsAllowed = allowed;
  }

  @override
  void didUpdateWidget(HistorySwipeSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._state = null;
      widget.controller._state = this;
      _reset(rebuild: false);
    }
    if (oldWidget.scope != widget.scope || !widget.allowPreviews) {
      widget.controller.previews.clear();
      if (oldWidget.scope != widget.scope || oldWidget.allowPreviews) {
        _reset(rebuild: false);
      }
    } else if (widget.captureOnPageChange &&
        oldWidget.pageKey != widget.pageKey &&
        !_active) {
      // didUpdateWidget runs before the old child is rebuilt/painted. Capture
      // its existing layer, not a second editor or a rebuilt old Plugin.
      _capture(oldWidget.pageKey);
    }
    if (oldWidget.pageKey != widget.pageKey ||
        oldWidget.pageReady != widget.pageReady) {
      if (_navigating && widget.pageReady) {
        if (_arrival?.isCompleted == false) _arrival!.complete();
      } else if (!_navigating && oldWidget.pageKey != widget.pageKey) {
        _reset(rebuild: false);
      }
    }
  }

  void _capture(Object? key) {
    if (!widget.allowPreviews ||
        !_previewsAllowed ||
        key == null ||
        _reducedMotion) {
      return;
    }
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return;
    }
    var needsPaint = false;
    assert(() {
      needsPaint = box.debugNeedsPaint;
      return true;
    }());
    if (needsPaint) return;
    try {
      // At most one megapixel per preview; no GPU readback/PNG encoding and
      // never a capture per input packet or animation frame.
      final ratio = math.min(
          1.0, math.sqrt(1000000 / (box.size.width * box.size.height)));
      widget.controller.previews.store(key, box.toImageSync(pixelRatio: ratio));
    } catch (_) {
      // External textures or a disappearing surface need not be capturable.
      // Navigation still works with the themed destination placeholder.
    }
  }

  void _begin(
      {required bool forward, required bool available, Object? target}) {
    if (_settling || !mounted) return;
    _reset(rebuild: false);
    _capture(widget.pageKey);
    _preview = widget.allowPreviews && _previewsAllowed && available
        ? widget.controller.previews.read(target)
        : null;
    setState(() {
      _forward = forward;
      _available = available;
      _active = true;
    });
  }

  void _update(double distance) {
    if (!_active || _settling || !distance.isFinite) return;
    _distance = math.max(0, distance);
    _motion.value = _reducedMotion
        ? 0
        : _available
            ? _distance.clamp(0.0, _width)
            : 64 * (1 - math.exp(-_distance / 140));
  }

  Future<void> _finish({
    required bool commit,
    required bool Function() isValid,
    required FutureOr<void> Function() navigate,
  }) async {
    if (!_active || _settling) return;
    final generation = _generation;
    _settling = true;
    final go = commit && _available && isValid();
    try {
      if (!_reducedMotion) {
        await _motion
            .animateTo(go ? _width : 0,
                duration: Duration(milliseconds: go ? 230 : 210),
                curve: Curves.easeOutCubic)
            .orCancel;
      }
      if (!mounted || generation != _generation) return;
      if (go && isValid()) {
        // The new page must lay out at its FINAL coordinates. Native viewers
        // report their initial screen position once; creating them under the
        // outgoing width-sized translation leaves that native position stale.
        setState(() => _navigating = true);
        _arrival = Completer<void>();
        await Future<void>.sync(navigate).timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
        if (!mounted || generation != _generation) return;
        if (widget.pageKey != null) {
          // The destination image covers asynchronous page loading. A failed
          // navigation must never strand an input-blocking transition.
          await _arrival!.future
              .timeout(const Duration(seconds: 2), onTimeout: () {});
        }
        if (!mounted || generation != _generation) return;
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 350),
          onTimeout: () {},
        );
      } else if (!_available) {
        // Keep the boundary explanation readable after a quick/reduced-motion
        // swipe, without blocking a new gesture.
        _settling = false;
        _edgeDismiss = Timer(const Duration(milliseconds: 550), _reset);
        return;
      }
    } on TickerCanceled {
      return;
    } finally {
      if (mounted && generation == _generation && _settling) _reset();
    }
  }

  void _cancel() {
    if (!_active) return;
    _reset();
  }

  void _reset({bool rebuild = true}) {
    _generation++;
    _edgeDismiss?.cancel();
    _edgeDismiss = null;
    _motion.stop();
    _motion.value = 0;
    _active = false;
    _settling = false;
    _navigating = false;
    _distance = 0;
    if (_arrival?.isCompleted == false) _arrival!.complete();
    _arrival = null;
    final old = _preview;
    _preview = null;
    // RawImage takes its own handle during the following rebuild.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (rebuild && mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _reset();
  }

  @override
  void didChangeMetrics() {
    _reset();
    widget.controller.previews.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _edgeDismiss?.cancel();
    _generation++;
    if (_arrival?.isCompleted == false) _arrival!.complete();
    _preview?.dispose();
    _motion.dispose();
    if (widget.controller._state == this) widget.controller._state = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = HistorySwipeTheme.maybeOf(context);
    final theme = Theme.of(context);
    final surface = style?.surface ?? theme.colorScheme.surface;
    final label = _available
        ? (_forward ? style?.forward ?? 'Forward' : style?.back ?? 'Back')
        : (_forward
            ? style?.noNext ?? 'No next page'
            : style?.noPrevious ?? 'No previous page');
    return LayoutBuilder(builder: (context, constraints) {
      _width =
          constraints.hasBoundedWidth ? math.max(1, constraints.maxWidth) : 1;
      return AnimatedBuilder(
        animation: _motion,
        child: RepaintBoundary(key: _boundary, child: widget.child),
        builder: (context, child) {
          final sign = _forward ? -1.0 : 1.0;
          final progress = (_motion.value / _width).clamp(0.0, 1.0);
          return ClipRect(
            child: Stack(fit: StackFit.passthrough, children: [
              if (_active)
                Positioned.fill(
                    child: IgnorePointer(
                        child: ExcludeSemantics(
                  child: ColoredBox(
                      color: surface,
                      child: Transform.translate(
                        offset: Offset(
                            _available && !_reducedMotion
                                ? -sign * _width * .22 * (1 - progress)
                                : 0,
                            0),
                        child: _preview == null
                            ? const SizedBox.expand()
                            : RawImage(
                                image: _preview,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.low,
                              ),
                      )),
                ))),
              Transform.translate(
                key: const ValueKey('history-swipe-sheet'),
                offset: Offset(_navigating ? 0 : sign * _motion.value, 0),
                transformHitTests: false,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      boxShadow: _active && !_reducedMotion
                          ? [
                              BoxShadow(
                                  color:
                                      theme.shadowColor.withValues(alpha: .14),
                                  blurRadius: 20,
                                  offset: Offset(-sign * 4, 0)),
                            ]
                          : const []),
                  child: IgnorePointer(ignoring: _settling, child: child),
                ),
              ),
              if (_active && _navigating && _preview != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: ColoredBox(
                        color: surface,
                        child: RawImage(
                          image: _preview,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_active && !_navigating)
                Positioned.fill(
                    child: IgnorePointer(
                        child: Align(
                  alignment:
                      _forward ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      liveRegion: true,
                      label: label,
                      child: ExcludeSemantics(
                          child: Material(
                        color: surface,
                        elevation: 2,
                        shadowColor: theme.shadowColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                                _forward
                                    ? Icons.arrow_forward_rounded
                                    : Icons.arrow_back_rounded,
                                size: 18,
                                color: _available
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Flexible(
                                child: Text(label,
                                    maxLines: 2,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                            color:
                                                theme.colorScheme.onSurface))),
                          ]),
                        ),
                      )),
                    ),
                  ),
                ))),
            ]),
          );
        },
      );
    });
  }
}
