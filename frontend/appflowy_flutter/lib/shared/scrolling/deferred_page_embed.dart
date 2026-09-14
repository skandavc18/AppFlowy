import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

/// Owns one page's mount budget. Nested pages get independent queues.
class PageEmbedLoadScope extends StatefulWidget {
  const PageEmbedLoadScope({super.key, required this.child});

  final Widget child;

  @override
  State<PageEmbedLoadScope> createState() => _PageEmbedLoadScopeState();
}

class _PageEmbedLoadScopeState extends State<PageEmbedLoadScope> {
  final _queue = _MountQueue();

  @override
  Widget build(BuildContext context) => _QueueScope(
        queue: _queue,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _queue.geometryChanged();
            return false;
          },
          child: widget.child,
        ),
      );

  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }
}

/// Opts eligible page blocks in; the first deferred frame consumes this marker.
class PageEmbedPreviewScope extends InheritedWidget {
  const PageEmbedPreviewScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  @override
  bool updateShouldNotify(PageEmbedPreviewScope oldWidget) =>
      enabled != oldWidget.enabled;
}

class _QueueScope extends InheritedWidget {
  const _QueueScope({required this.queue, required super.child});

  final _MountQueue queue;

  @override
  bool updateShouldNotify(_QueueScope oldWidget) => queue != oldWidget.queue;
}

class _MountQueue extends ChangeNotifier {
  final _ready = <_DeferredPageEmbedState>{};
  int? _frame;
  bool disposed = false;

  void geometryChanged() => notifyListeners();

  void add(_DeferredPageEmbedState entry) {
    if (disposed) return;
    _ready.add(entry);
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      while (!disposed && _ready.isNotEmpty) {
        final next = _ready.first;
        _ready.remove(next);
        if (next._tryAdmit(this)) break;
      }
      if (!disposed && _ready.isNotEmpty) add(_ready.first);
    });
  }

  void remove(_DeferredPageEmbedState entry) {
    _ready.remove(entry);
    if (_ready.isEmpty && _frame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
      _frame = null;
    }
  }

  @override
  void dispose() {
    disposed = true;
    if (_frame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
    }
    _ready.clear();
    super.dispose();
  }
}

/// Defers mounting, not constructing [child], in an opted-in, fixed page frame.
/// Once admitted, the child stays in the same slot for this State's lifetime.
/// [IntrinsicHeight]/[IntrinsicWidth] hosts and non-fixed frames load normally.
class DeferredPageEmbed extends StatefulWidget {
  const DeferredPageEmbed({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<DeferredPageEmbed> createState() => _DeferredPageEmbedState();
}

class _DeferredPageEmbedState extends State<DeferredPageEmbed> {
  _MountQueue? _queue;
  List<ScrollPosition> _positions = [];
  Timer? _idle;
  (RenderAbstractViewport, Rect, Rect)? _geometry;
  bool _preview = false, _intrinsic = false, _admitted = false;
  bool _useLayout = false, _active = true, _checkQueued = false, _ready = false;
  bool _permit = false;
  int _epoch = 0;

  bool get _mustLoad =>
      !widget.enabled ||
      !_preview ||
      _intrinsic ||
      (_queue?.disposed ?? true) ||
      _positions.isEmpty;

  void _bind() {
    final queue = context.dependOnInheritedWidgetOfExactType<_QueueScope>()?.queue;
    final preview = context
            .dependOnInheritedWidgetOfExactType<PageEmbedPreviewScope>()
            ?.enabled ??
        false;
    final positions = <ScrollPosition>[];
    _intrinsic = false;
    if (widget.enabled && preview && queue != null && !queue.disposed) {
      final nearest = Scrollable.maybeOf(context)?.position;
      if (nearest != null) positions.add(nearest);
      context.visitAncestorElements((element) {
        // Also watch enclosing scrollables: an idle inner viewport can be
        // carried through an outer viewport's fling or clipping boundary.
        if (element is StatefulElement && element.state is ScrollableState) {
          final position = (element.state as ScrollableState).position;
          if (!positions.contains(position)) positions.add(position);
        }
        if (element is RenderObjectElement) {
          final render = element.renderObject;
          _intrinsic |=
              render is RenderIntrinsicHeight || render is RenderIntrinsicWidth;
        }
        return true;
      });
    }
    if (queue == _queue && preview == _preview &&
        listEquals(positions, _positions)) {
      return;
    }
    _disconnect();
    _queue = queue;
    _preview = preview;
    _positions = positions;
    if (!(queue?.disposed ?? true)) queue!.addListener(_scheduleCheck);
    for (final position in _positions) {
      position.addListener(_scrollChanged);
      position.isScrollingNotifier.addListener(_scrollChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_admitted) return;
    _bind();
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(DeferredPageEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_admitted) return;
    _cancelPending();
    _scheduleCheck();
  }

  void _cancelPending() {
    _idle?.cancel();
    _idle = null;
    _ready = false;
    _permit = false;
    _queue?.remove(this);
  }

  void _scrollChanged() {
    _cancelPending();
    _scheduleCheck();
  }

  void _scheduleCheck() {
    if (!mounted || !_active || _admitted || _checkQueued) return;
    if (!_mustLoad && _positions.any((p) => p.isScrollingNotifier.value)) {
      return; // The position's idle notification will schedule the next check.
    }
    _checkQueued = true;
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (epoch != _epoch) return;
      _checkQueued = false;
      if (!mounted || !_active || _admitted) return;
      _bind();
      if (_mustLoad) return _load();
      // Pending embeds need no transform/clip walk during a fling. The idle
      // notification will recheck their final viewport position once.
      if (_positions.any((p) => p.isScrollingNotifier.value)) {
        _cancelPending();
        return;
      }
      final geometry = _nearViewport();
      if (geometry == null) {
        _cancelPending();
        return;
      }
      if (_geometry != geometry) _cancelPending();
      _geometry = geometry;
      if (_ready) {
        _queue!.add(this);
      } else {
        _idle ??= Timer(const Duration(milliseconds: 80), () {
          _idle = null;
          _ready = true;
          _scheduleCheck();
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _tryAdmit(_MountQueue owner) {
    if (!mounted || !_active || _admitted || owner != _queue) return false;
    _bind();
    if (_mustLoad) {
      _load();
      return true;
    }
    if (owner != _queue || !_canAdmit()) {
      _cancelPending();
      _scheduleCheck();
      return false;
    }
    // An ancestor may rebuild/move between this frame callback and layout.
    // Spend one slot now, but revalidate before actually mounting the child.
    setState(() => _permit = true);
    return true;
  }

    bool _canAdmit([Size? frameSize]) =>
      _active && _ready && _geometry != null &&
      !_positions.any((p) => p.isScrollingNotifier.value) &&
      _nearViewport(frameSize) == _geometry;

    (RenderAbstractViewport, Rect, Rect)? _nearViewport([Size? frameSize]) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box.parent);
    if (viewport == null || !viewport.attached) return null;
    final toGlobal = viewport.getTransformTo(null);
    var visible = MatrixUtils.transformRect(toGlobal, viewport.paintBounds);
    var rect = MatrixUtils.transformRect(
      toGlobal.clone()..multiply(box.getTransformTo(viewport)),
      Offset.zero & (frameSize ?? box.size),
    );
    var insideViewport = true;
    for (RenderObject child = box; child.parent != null; child = child.parent!) {
      final parent = child.parent!;
      if (!parent.paintsChild(child)) return null;
      if (parent is RenderIndexedStack) {
        // In 3.27 this class does not override paintsChild; its public
        // semantics traversal visits exactly the selected render child.
        var selected = false;
        parent.visitChildrenForSemantics((shown) => selected = shown == child);
        if (!selected) return null;
      }
      if (parent == viewport) {
        insideViewport = false;
        continue; // Only the nearest viewport gets a small preload margin.
      }
      final clip = parent.describeApproximatePaintClip(child);
      if (clip == null) continue;
      final globalClip = MatrixUtils.transformRect(parent.getTransformTo(null), clip);
      if (insideViewport) {
        rect = rect.intersect(globalClip);
      } else {
        visible = visible.intersect(globalClip);
      }
    }
    if (!rect.isFinite || rect.isEmpty || !visible.isFinite || visible.isEmpty) {
      return null;
    }
    final extent = _positions.first.axis == Axis.vertical
        ? visible.height
        : visible.width;
    final margin = math.min(128.0, extent * 0.2);
    return rect.overlaps(visible.inflate(margin)) ? (viewport, rect, visible) : null;
  }

  void _load({bool rebuild = true}) {
    if (!mounted || !_active || _admitted) return;
    _admitted = true;
    _disconnect();
    if (!rebuild) return; // Our build/layout callback already updates the slot.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _active) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _disconnect() {
    _cancelPending();
    _geometry = null;
    _queue?.removeListener(_scheduleCheck);
    _queue = null;
    for (final position in _positions) {
      position.removeListener(_scrollChanged);
      position.isScrollingNotifier.removeListener(_scrollChanged);
    }
    _positions = [];
  }

  @override
  void deactivate() {
    _active = false;
    _epoch++;
    _checkQueued = false;
    _disconnect();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    if (!_admitted) _scheduleCheck();
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_admitted) {
      if (_mustLoad) {
        _load(rebuild: false);
      } else {
        _useLayout = true;
      }
    }
    return PageEmbedPreviewScope(
      enabled: false,
      child: _useLayout
          ? _EmbedLayout(
              onGeometry: _admitted ? null : _scheduleCheck,
              builder: (_, constraints) {
                if (!constraints.isTight ||
                    !constraints.biggest.isFinite ||
                    constraints.biggest.isEmpty) {
                  _load(rebuild: false);
                }
                if (_permit) {
                  if (_canAdmit(constraints.biggest)) {
                    _load(rebuild: false);
                  } else {
                    _cancelPending();
                    _scheduleCheck();
                  }
                }
                return _admitted ? widget.child : _Preview(onActivate: _load);
              },
            )
          : widget.child,
    );
  }
}

// Unlike LayoutBuilder's render box, this adapter forwards the mounted child's
// intrinsics/dry layout. Intrinsic ancestors bypass it before the first layout.
// Never remove it after admission: native viewers may contain GlobalKeys.
class _EmbedLayout extends ConstrainedLayoutBuilder<BoxConstraints> {
  const _EmbedLayout({required super.builder, required this.onGeometry});

  final VoidCallback? onGeometry;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEmbedLayout()..onGeometry = onGeometry;

  @override
  void updateRenderObject(BuildContext context, _RenderEmbedLayout renderObject) {
    renderObject.onGeometry = onGeometry;
  }
}

class _RenderEmbedLayout extends RenderProxyBox
    with RenderConstrainedLayoutBuilder<BoxConstraints, RenderBox> {
  VoidCallback? onGeometry;

  @override
  void performLayout() {
    rebuildIfNecessary();
    super.performLayout();
    onGeometry?.call();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onGeometry?.call();
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = LocaleKeys.gallery_preview.tr();
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onActivate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: label,
        onTap: onActivate,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onActivate,
          child: ColoredBox(
            color: EditorSurfaceStyle.previewBackgroundFor(
              theme.brightness,
              theme.colorScheme.surfaceContainerLow,
              isPaper: PaperTheme.isEnabled(context),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_rounded, size: 22,
                        color: theme.colorScheme.onSurfaceVariant,),
                      const SizedBox(width: 8),
                      Text(label, style: theme.textTheme.bodySmall),
                    ],
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
