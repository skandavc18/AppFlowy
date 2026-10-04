import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/shared/page_cover_controller.dart';
import 'package:appflowy/shared/page_cover_height.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/settings/cover_appearance.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'page_cover_controller.dart';
export 'page_cover_height.dart';
export 'package:appflowy/workspace/application/settings/cover_appearance.dart';

/// Dynamic-key translation while the normal locale generation is coordinated.
String coverLabel(String key, String fallback) {
  final path = 'coverAppearance.$key';
  final translated = path.tr();
  return translated == path ? fallback : translated;
}

class PageCoverBackendScope extends InheritedWidget {
  const PageCoverBackendScope({
    super.key,
    required this.backend,
    required super.child,
  });
  final PageCoverBackendService backend;
  static PageCoverBackendService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PageCoverBackendScope>()
      ?.backend;
  @override
  bool updateShouldNotify(PageCoverBackendScope oldWidget) =>
      backend != oldWidget.backend;
}

/// Synchronous gate for a host's pending media action; never takes focus.
class PageCoverInteractionGate extends InheritedWidget {
  const PageCoverInteractionGate({
    super.key,
    required this.allowed,
    required super.child,
  });
  final ValueNotifier<bool> allowed;
  static ValueNotifier<bool>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PageCoverInteractionGate>()
      ?.allowed;
  @override
  bool updateShouldNotify(PageCoverInteractionGate oldWidget) =>
      allowed != oldWidget.allowed;
}

/// Present only around actual page covers, never inline images/thumbnails.
class PageCoverPresentation extends InheritedWidget {
  const PageCoverPresentation({
    super.key,
    required this.appearance,
    required this.alignment,
    required super.child,
  });
  final CoverAppearance appearance;
  final Alignment alignment;
  static PageCoverPresentation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageCoverPresentation>();
  @override
  bool updateShouldNotify(PageCoverPresentation oldWidget) =>
      appearance != oldWidget.appearance || alignment != oldWidget.alignment;
}

/// Reusable geometry owner for page headers and separately docked file covers.
/// Builder must use [height] for BOTH image and identity-offset calculations.
/// Keep its tree shape constant when height/permissions change.
class PageCoverLayout extends StatefulWidget {
  const PageCoverLayout({
    super.key,
    required this.width,
    required this.fallbackHeight,
    required this.builder,
    this.view,
    this.editable = false,
    this.binding,
    this.canResize,
    this.isSameTarget,
    this.onHeightChanged,
    this.backend,
  });
  final double width;
  final double fallbackHeight;
  final Widget Function(BuildContext context, double height, Widget? grip)
      builder;
  final ViewPB? view;
  final bool editable;
  final Object? binding;
  final bool Function()? canResize;
  final bool Function(ViewPB)? isSameTarget;
  final ValueChanged<double?>? onHeightChanged;
  final PageCoverBackendService? backend;
  @override
  State<PageCoverLayout> createState() => _PageCoverLayoutState();
}

class _PageCoverLayoutState extends State<PageCoverLayout> {
  PageCoverController? _controller;
  PageCoverBackendService? _backend;
  PageAccessLevelBloc? _access;
  StreamSubscription<PageAccessLevelState>? _subscription;
  ValueNotifier<bool>? _interactionGate;
  final _focus = FocusNode(debugLabel: 'page-cover-resize');
  double? _origin;
  double _startHeight = 0;
  double _height = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  bool _allows(PageAccessLevelState? state) =>
      state == null ||
      (state.view.id == widget.view?.id &&
          !state.isLoadingLockStatus &&
          !state.isReadOnly &&
          state.isEditable);
  bool get _editable =>
      mounted &&
      widget.editable &&
      widget.view != null &&
      !widget.view!.isLocked &&
      _allows(_access?.state) &&
      (_interactionGate?.value ?? true) &&
      (widget.canResize?.call() ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final gate = PageCoverInteractionGate.maybeOf(context);
    if (gate != _interactionGate) {
      _interactionGate?.removeListener(_gateChanged);
      _interactionGate = gate;
      gate?.addListener(_gateChanged);
    }
    final access = context.watch<PageAccessLevelBloc?>();
    if (access != _access) {
      unawaited(_subscription?.cancel());
      _access = access;
      _subscription = access?.stream.listen((state) {
        if (mounted && identical(access, _access)) {
          _controller?.setEditable(_allows(state) && _editable);
        }
      });
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant PageCoverLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final view = widget.view;
    final backend = widget.backend ??
        PageCoverBackendScope.maybeOf(context) ??
        const PageCoverBackendService();
    if (view == null || _backend != backend) {
      _controller?.removeListener(_changed);
      _controller?.dispose();
      _controller = null;
      _backend = backend;
    }
    if (view == null) return;
    final binding = (widget.binding ?? view.id, _access);
    _controller ??= PageCoverController(
      view: view,
      binding: binding,
      editable: _editable,
      canEdit: () => _editable,
      isSameTarget: (fresh) => widget.isSameTarget?.call(fresh) ?? true,
      onSaved: (height) {
        if (mounted && _editable) widget.onHeightChanged?.call(height);
      },
      backend: backend,
    )..addListener(_changed);
    _controller!.rebind(view: view, binding: binding, editable: _editable);
    if (!_controller!.isResizing) _origin = null;
  }

  void _gateChanged() => _controller?.setEditable(_editable);

  void _changed() {
    if (!mounted) return;
    if (_controller?.isResizing != true) _origin = null;
    setState(() {});
  }

  void _cancel() {
    _origin = null;
    _controller?.cancel();
  }

  void _begin(DragStartDetails details) {
    if (_controller?.begin(_height) != true) return;
    _origin = details.globalPosition.dy;
    _startHeight = _height;
    _focus.requestFocus();
  }

  void _move(DragUpdateDetails details) {
    if (_origin == null) return;
    _controller?.preview(
      (_startHeight + details.globalPosition.dy - _origin!)
          .clamp(
            PageCoverHeight.minimum,
            PageCoverHeight.maximumFor(widget.width),
          )
          .toDouble(),
    );
  }

  void _end(DragEndDetails details) {
    if (_origin == null) return;
    _origin = null;
    // The pane may have narrowed since the last pointer event. Commit the
    // actual displayed geometry, not an out-of-bounds earlier drag draft.
    _controller?.preview(_height);
    unawaited(_controller?.commit());
  }

  void _step(double delta) {
    _cancel();
    unawaited(
      _controller?.save(
        (_height + delta)
            .clamp(
              PageCoverHeight.minimum,
              PageCoverHeight.maximumFor(widget.width),
            )
            .toDouble(),
      ),
    );
  }

  void _reset() {
    _cancel();
    unawaited(_controller?.save(null));
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _origin != null) {
      _cancel();
      return KeyEventResult.handled;
    }
    if (_controller?.canResize != true) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final delta = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _step(delta);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _step(-delta);
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      _reset();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _interactionGate?.removeListener(_gateChanged);
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _focus.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = CoverAppearanceScope.of(context);
    _height = PageCoverHeight.resolve(
      width: widget.width,
      appearance: appearance,
      fallback: widget.fallbackHeight,
      override: _controller != null
          ? _controller!.height
          : (widget.view == null
              ? null
              : PageCoverHeight.decode(widget.view!.extra)),
    );
    var alignment = appearance.alignment;
    // Optional independently-owned position metadata wins over the default.
    try {
      final position = ViewCoverCodec.decodeExtra(
        widget.view?.extra ?? '',
      )['page_cover_position'];
      if (position is num &&
          position.isFinite &&
          position >= -1 &&
          position <= 1) {
        alignment = Alignment(0, position.toDouble());
      }
    } on FormatException {
      // Display is tolerant; the writer refuses malformed metadata.
    }
    return PageCoverPresentation(
      appearance: appearance,
      alignment: alignment,
      child: Builder(
        builder: (context) => widget.builder(
          context,
          _height,
          _controller?.canResize == true ? _grip(context) : null,
        ),
      ),
    );
  }

  Widget _grip(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final hint = coverLabel(
      'resizeHint',
      'Drag to resize. Up/Down: 1 pixel; Shift: 10 pixels. Home: reset. Escape: cancel.',
    );
    final failed = _controller?.hasFailure == true;
    final status = failed
        ? coverLabel('saveFailed', 'Could not save cover height. Try again.')
        : _controller?.isSaving == true
            ? coverLabel('saving', 'Saving')
            : hint;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Semantics(
        key: const ValueKey('page-cover-resize'),
        label: coverLabel('height', 'Page cover height'),
        hint: status,
        value: _height.toStringAsFixed(1),
        increasedValue: (_height + 1)
            .clamp(
              PageCoverHeight.minimum,
              PageCoverHeight.maximumFor(widget.width),
            )
            .toStringAsFixed(1),
        decreasedValue: (_height - 1)
            .clamp(
              PageCoverHeight.minimum,
              PageCoverHeight.maximumFor(widget.width),
            )
            .toStringAsFixed(1),
        slider: true,
        enabled: true,
        focusable: true,
        focused: _focus.hasFocus,
        liveRegion: failed,
        onIncrease: () => _step(1),
        onDecrease: () => _step(-1),
        customSemanticsActions: {
          CustomSemanticsAction(
            label: coverLabel('resetHeight', 'Reset cover height'),
          ): _reset,
        },
        child: Tooltip(
          message: status,
          excludeFromSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              gestures: {
                PageCoverPanRecognizer: GestureRecognizerFactoryWithHandlers<
                    PageCoverPanRecognizer>(
                  PageCoverPanRecognizer.new,
                  (recognizer) => recognizer
                    ..gestureSettings = MediaQuery.gestureSettingsOf(context)
                    ..dragStartBehavior = DragStartBehavior.down
                    ..onStart = _begin
                    ..onUpdate = _move
                    ..onEnd = _end
                    ..onCancel = _cancel,
                ),
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _focus.requestFocus,
                child: SizedBox(
                  width: 96,
                  height: 24,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: palette.primaryText,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: palette.surface),
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

/// Flutter 3.27's DragGestureRecognizer is sealed; extend concrete Pan.
class PageCoverPanRecognizer extends PanGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      computeHitSlop(pointerDeviceKind, gestureSettings);

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

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}
}
