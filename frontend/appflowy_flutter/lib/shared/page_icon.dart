import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/shared/page_icon_controller.dart';
import 'package:appflowy/shared/page_icon_size.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'page_icon_controller.dart';
export 'page_icon_size.dart';

/// Overrides only icon metadata IO/notifications for embedded or test hosts.
class PageIconBackendScope extends InheritedWidget {
  const PageIconBackendScope({
    super.key,
    required this.backend,
    required super.child,
  });

  final PageIconBackendService backend;

  static PageIconBackendService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PageIconBackendScope>()
      ?.backend;

  @override
  bool updateShouldNotify(PageIconBackendScope oldWidget) =>
      backend != oldWidget.backend;
}

/// Adds resizing around an existing PAGE identity picker/artwork, never around
/// a toolbar icon. The child remains at one depth for every size/access state.
class ResizablePageIcon extends StatefulWidget {
  const ResizablePageIcon({
    super.key,
    required this.view,
    required this.builder,
    required this.editable,
    required this.onSizeChanged,
    this.binding,
    this.canResize,
    this.isSameTarget,
    this.defaultSize = WorkspaceTokens.pageIconSize,
    this.maxSize = IconSize.maximum,
    this.backend,
  });

  final ViewPB view;

  /// Build the EXISTING picker at the resolved square size. Scale only its
  /// artwork (or its original glyph size by [scale]), not the picker itself:
  /// popover leaders must report the real resized layout/hit-test dimensions.
  final Widget Function(double size, double scale) builder;
  final bool editable;
  final ValueChanged<double?> onSizeChanged;

  /// Include source/controller identity when the same view can be rebound.
  final Object? binding;
  final bool Function()? canResize;
  final bool Function(ViewPB)? isSameTarget;
  final double defaultSize;

  /// Non-flex Row hosts can supply their actual local pane allocation. Wrap/
  /// bounded hosts automatically use incoming constraints, never window width.
  final double maxSize;
  final PageIconBackendService? backend;

  @override
  State<ResizablePageIcon> createState() => _ResizablePageIconState();
}

class _ResizablePageIconState extends State<ResizablePageIcon> {
  final _regionFocus = FocusNode(debugLabel: 'page-icon-region');
  final _gripFocus = FocusNode(debugLabel: 'page-icon-resize');
  late PageIconController _controller;
  PageIconBackendService? _backend;
  PageAccessLevelBloc? _access;
  StreamSubscription<PageAccessLevelState>? _accessSubscription;
  bool _hovered = false;
  bool _touchRevealed = false;
  Offset? _dragOrigin;
  double _dragSize = 0;
  double _maximum = IconSize.maximum;
  double _displayedSize = WorkspaceTokens.pageIconSize;
  bool _dragRtl = false;

  bool get _editable {
    if (!mounted || !widget.editable || widget.view.isLocked) return false;
    return _allowsAccess(_access?.state) && (widget.canResize?.call() ?? true);
  }

  bool _allowsAccess(PageAccessLevelState? access) =>
      access == null ||
      (access.view.id == widget.view.id &&
          !access.isLoadingLockStatus &&
          !access.isReadOnly &&
          access.isEditable);

  Object get _binding => (widget.binding ?? widget.view.id, _access);

  @override
  void initState() {
    super.initState();
    _regionFocus.addListener(_changed);
    _gripFocus.addListener(_changed);
  }

  void _createController(PageIconBackendService backend) {
    _backend = backend;
    _controller = PageIconController(
      view: widget.view,
      binding: _binding,
      editable: _editable,
      canEdit: () => _editable,
      isSameTarget: (view) => widget.isSameTarget?.call(view) ?? true,
      defaultSize: widget.defaultSize,
      backend: backend,
      onSaved: (size) {
        if (mounted && _editable) widget.onSizeChanged(size);
      },
    )..addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final access = context.watch<PageAccessLevelBloc?>();
    if (access != _access) {
      unawaited(_accessSubscription?.cancel());
      _access = access;
      _accessSubscription = access?.stream.listen((state) {
        if (mounted && identical(_access, access)) {
          // Use the delivered state as well as the live gate: a revoke/grant
          // pair in one frame must not resurrect an older queued resize.
          _controller.setEditable(_allowsAccess(state) && _editable);
        }
      });
    }
    _syncController();
  }

  @override
  void didUpdateWidget(covariant ResizablePageIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  void _syncController() {
    final backend = widget.backend ??
        PageIconBackendScope.maybeOf(context) ??
        const PageIconBackendService();
    if (_backend != backend) {
      if (_backend != null) {
        _controller.removeListener(_changed);
        _controller.dispose();
      }
      _dragOrigin = null;
      _createController(backend);
    }
    _rebind();
  }

  void _rebind() {
    _controller.rebind(
      view: widget.view,
      binding: _binding,
      editable: _editable,
      defaultSize: widget.defaultSize,
      notify: false,
    );
    if (!_controller.isResizing) _dragOrigin = null;
  }

  void _changed() {
    if (!mounted) return;
    if (!_controller.isResizing) _dragOrigin = null;
    setState(() {});
  }

  @override
  void dispose() {
    unawaited(_accessSubscription?.cancel());
    _controller.removeListener(_changed);
    _controller.dispose();
    _regionFocus.dispose();
    _gripFocus.dispose();
    super.dispose();
  }

  void _start(DragStartDetails details) {
    if (!_controller.beginResize(_displayedSize)) return;
    _dragOrigin = details.globalPosition;
    _dragSize = _displayedSize;
    _dragRtl = Directionality.of(context) == TextDirection.rtl;
    _gripFocus.requestFocus();
  }

  void _move(DragUpdateDetails details) {
    final origin = _dragOrigin;
    if (origin == null) return;
    if (_maximum < IconSize.minimum) {
      _cancel();
      return;
    }
    final delta = details.globalPosition - origin;
    // Project the GLOBAL pointer displacement onto the resize diagonal. Local
    // deltas drift as the header relays out between real pointer moves.
    final change = ((_dragRtl ? -delta.dx : delta.dx) + delta.dy) / 2;
    _controller.preview(
      (_dragSize + change).clamp(IconSize.minimum, _maximum).toDouble(),
    );
  }

  void _end(DragEndDetails _) {
    if (_dragOrigin == null) return;
    if (_maximum < IconSize.minimum || !_controller.canResize) {
      _cancel();
      return;
    }
    _dragOrigin = null;
    unawaited(_controller.commitResize());
  }

  void _cancel() {
    _dragOrigin = null;
    _controller.cancelResize();
  }

  void _step(double delta) {
    if (_maximum < IconSize.minimum) return;
    _cancel();
    unawaited(
      _controller.saveSize(
        (_displayedSize + delta).clamp(IconSize.minimum, _maximum).toDouble(),
      ),
    );
  }

  void _reset() {
    _cancel();
    unawaited(_controller.saveSize(null));
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (!_controller.canResize ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _step(step);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _step(-step);
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      _reset();
    } else if (event.logicalKey == LogicalKeyboardKey.escape &&
        _controller.isResizing) {
      _cancel();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _maximum = math.max(
          0.0,
          math.min(
            IconSize.maximum,
            math.min(
              widget.maxSize,
              math.min(constraints.maxWidth, constraints.maxHeight),
            ),
          ),
        );
        _displayedSize = math.min(_controller.size, _maximum);
        final editable = _controller.canResize && _maximum >= IconSize.minimum;
        final revealed = editable &&
            (_hovered ||
                _regionFocus.hasFocus ||
                _touchRevealed ||
                _controller.isResizing ||
                _controller.hasFailure ||
                MediaQuery.accessibleNavigationOf(context));
        // Keep the CENTER available to the original picker even at 16px.
        final gripSize = math.min(24.0, _displayedSize * 0.4);
        const hint = 'Drag to resize. Arrow keys: 1 pixel; Shift: 10 pixels. '
            'Home: reset. Escape: cancel drag.';
        final status = _controller.hasFailure
            ? 'Could not save icon size. Try resizing again.'
            : _controller.isSaving
                ? 'Saving icon size'
                : '';
        return SizedBox.square(
          key: const ValueKey('page-icon-frame'),
          dimension: _displayedSize,
          child: MouseRegion(
            // This control owns its whole square, including the picker. A
            // non-opaque region drops the enclosing layout from the hit path.
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Listener(
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.touch && !_touchRevealed) {
                  setState(() => _touchRevealed = true);
                }
              },
              child: Focus(
                focusNode: _regionFocus,
                canRequestFocus: false,
                skipTraversal: true,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeFocus(
                      excluding: !_controller.canResize,
                      child: IgnorePointer(
                        ignoring: !_controller.canResize,
                        child: MediaQuery.withNoTextScaling(
                          child: widget.builder(
                            _displayedSize,
                            _displayedSize / widget.defaultSize,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: revealed
                                ? palette.focus
                                : palette.focus.withValues(alpha: 0),
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      width: gripSize,
                      height: gripSize,
                      child: ExcludeSemantics(
                        excluding: !editable,
                        child: IgnorePointer(
                          ignoring: !revealed,
                          // No resize/reveal animation or ticker: real pointer
                          // motion and reduced-motion settings are immediate.
                          child: Opacity(
                            opacity: revealed ? 1 : 0,
                            child: Focus(
                              focusNode: _gripFocus,
                              canRequestFocus: editable,
                              skipTraversal: !editable,
                              onKeyEvent: _key,
                              child: Semantics(
                                key: const ValueKey('page-icon-resize'),
                                label: 'Page icon size',
                                hint: hint,
                                value: '${_displayedSize.toStringAsFixed(1)} '
                                    'pixels${status.isEmpty ? '' : ', $status'}',
                                increasedValue: editable
                                    ? '${math.min(_displayedSize + 1, _maximum).toStringAsFixed(1)} pixels'
                                    : null,
                                decreasedValue: editable
                                    ? '${math.max(_displayedSize - 1, IconSize.minimum).toStringAsFixed(1)} pixels'
                                    : null,
                                slider: true,
                                enabled: editable,
                                focusable: editable,
                                focused: _gripFocus.hasFocus,
                                liveRegion: _controller.hasFailure,
                                onIncrease:
                                    editable && _displayedSize < _maximum
                                        ? () => _step(1)
                                        : null,
                                onDecrease: editable &&
                                        _displayedSize > IconSize.minimum
                                    ? () => _step(-1)
                                    : null,
                                customSemanticsActions: editable
                                    ? {
                                        const CustomSemanticsAction(
                                          label: 'Reset icon size',
                                        ): _reset,
                                      }
                                    : null,
                                child: Tooltip(
                                  message: status.isEmpty ? hint : status,
                                  excludeFromSemantics: true,
                                  child: MouseRegion(
                                    cursor: Directionality.of(context) ==
                                            TextDirection.rtl
                                        ? SystemMouseCursors
                                            .resizeUpRightDownLeft
                                        : SystemMouseCursors
                                            .resizeUpLeftDownRight,
                                    child: RawGestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      excludeFromSemantics: true,
                                      gestures: {
                                        _PageIconPanRecognizer:
                                            GestureRecognizerFactoryWithHandlers<
                                                _PageIconPanRecognizer>(
                                          _PageIconPanRecognizer.new,
                                          (recognizer) => recognizer
                                            ..gestureSettings =
                                                MediaQuery.gestureSettingsOf(
                                              context,
                                            )
                                            ..dragStartBehavior =
                                                DragStartBehavior.down
                                            ..onStart = _start
                                            ..onUpdate = _move
                                            ..onEnd = _end
                                            ..onCancel = _cancel,
                                        ),
                                      },
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        excludeFromSemantics: true,
                                        onTap: _gripFocus.requestFocus,
                                        child: DecoratedBox(
                                          key: const ValueKey('page-icon-grip'),
                                          decoration: BoxDecoration(
                                            color: palette.surface,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color: palette.focus,
                                            ),
                                          ),
                                          child: Center(
                                            child: RotatedBox(
                                              quarterTurns:
                                                  Directionality.of(context) ==
                                                          TextDirection.rtl
                                                      ? 0
                                                      : 1,
                                              child: WorkspaceGlyph(
                                                Icons.open_in_full_rounded,
                                                size: math.min(14.0, gripSize),
                                                color: palette.primaryText,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Cancel an accepted drag before Flutter maps its terminal event to onEnd.
/// An outer Listener can run too late, after the metadata write is queued.
class _PageIconPanRecognizer extends PanGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    if (event is! PointerCancelEvent) {
      super.handleEvent(event);
      return;
    }
    final end = onEnd;
    onEnd = (_) => onCancel?.call();
    try {
      super.handleEvent(event);
    } finally {
      onEnd = end;
    }
  }

  // Two-finger trackpad scrolling over a grip must remain scrolling.
  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}
}

/// Aspect-preserving artwork INSIDE a native picker, never around its leader.
class PageIconArtwork extends StatelessWidget {
  const PageIconArtwork({
    super.key,
    required this.size,
    required this.child,
  });

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: FittedBox(child: child),
      );
}
