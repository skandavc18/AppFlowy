import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '_static_channel.dart';

const Map<String, SystemMouseCursor> _cursors = {
  'none': SystemMouseCursors.none,
  'basic': SystemMouseCursors.basic,
  'click': SystemMouseCursors.click,
  'forbidden': SystemMouseCursors.forbidden,
  'wait': SystemMouseCursors.wait,
  'progress': SystemMouseCursors.progress,
  'contextMenu': SystemMouseCursors.contextMenu,
  'help': SystemMouseCursors.help,
  'text': SystemMouseCursors.text,
  'verticalText': SystemMouseCursors.verticalText,
  'cell': SystemMouseCursors.cell,
  'precise': SystemMouseCursors.precise,
  'move': SystemMouseCursors.move,
  'grab': SystemMouseCursors.grab,
  'grabbing': SystemMouseCursors.grabbing,
  'noDrop': SystemMouseCursors.noDrop,
  'alias': SystemMouseCursors.alias,
  'copy': SystemMouseCursors.copy,
  'disappearing': SystemMouseCursors.disappearing,
  'allScroll': SystemMouseCursors.allScroll,
  'resizeLeftRight': SystemMouseCursors.resizeLeftRight,
  'resizeUpDown': SystemMouseCursors.resizeUpDown,
  'resizeUpLeftDownRight': SystemMouseCursors.resizeUpLeftDownRight,
  'resizeUpRightDownLeft': SystemMouseCursors.resizeUpRightDownLeft,
  'resizeUp': SystemMouseCursors.resizeUp,
  'resizeDown': SystemMouseCursors.resizeDown,
  'resizeLeft': SystemMouseCursors.resizeLeft,
  'resizeRight': SystemMouseCursors.resizeRight,
  'resizeUpLeft': SystemMouseCursors.resizeUpLeft,
  'resizeUpRight': SystemMouseCursors.resizeUpRight,
  'resizeDownLeft': SystemMouseCursors.resizeDownLeft,
  'resizeDownRight': SystemMouseCursors.resizeDownRight,
  'resizeColumn': SystemMouseCursors.resizeColumn,
  'resizeRow': SystemMouseCursors.resizeRow,
  'zoomIn': SystemMouseCursors.zoomIn,
  'zoomOut': SystemMouseCursors.zoomOut,
};

SystemMouseCursor _getCursorByName(String name) =>
    _cursors[name] ?? SystemMouseCursors.basic;

/// Pointer button type
// Order must match InAppWebViewPointerEventKind (see in_app_webview.h)
enum PointerButton { none, primary, secondary, tertiary }

/// Pointer Event kind
// Order must match InAppWebViewPointerEventKind (see in_app_webview.h)
enum InAppWebViewPointerEventKind { activate, down, enter, leave, up, update }

/// Attempts to translate a button constant such as [kPrimaryMouseButton]
/// to a [PointerButton]
PointerButton _getButton(int value) {
  switch (value) {
    case kPrimaryMouseButton:
      return PointerButton.primary;
    case kSecondaryMouseButton:
      return PointerButton.secondary;
    case kTertiaryButton:
      return PointerButton.tertiary;
    default:
      return PointerButton.none;
  }
}

const MethodChannel _pluginChannel = IN_APP_WEBVIEW_STATIC_CHANNEL;

@visibleForTesting
Offset filterScrollDeltaForSettings(Offset delta, dynamic creationParams) {
  final initialSettings =
      creationParams is Map ? creationParams['initialSettings'] : null;
  if (initialSettings is! Map) {
    return delta;
  }
  return Offset(
    initialSettings['disableHorizontalScroll'] == true ? 0 : delta.dx,
    initialSettings['disableVerticalScroll'] == true ? 0 : delta.dy,
  );
}

/// Trackpad panning moves the page by exactly the distance the fingers
/// travelled. Scaling it down both lags the content behind the gesture and
/// weakens the renderer's own fling, which is estimated from this movement.
const _trackpadDirectManipulationScale = 1.0;
const _trackpadMaximumDirectDelta = 48.0;
const _trackpadPointerId = 0x3ffffffe;

/// How far a pinch has to travel before it counts as a zoom rather than the
/// scale noise a two-finger scroll carries.
const _trackpadZoomThreshold = 0.01;

@visibleForTesting
Offset webViewTrackpadDirectDelta(Offset delta) {
  return Offset(
        delta.dx.clamp(
          -_trackpadMaximumDirectDelta,
          _trackpadMaximumDirectDelta,
        ),
        delta.dy.clamp(
          -_trackpadMaximumDirectDelta,
          _trackpadMaximumDirectDelta,
        ),
      ) *
      _trackpadDirectManipulationScale;
}

@visibleForTesting
bool hasEnabledWebViewScrollAxis(dynamic creationParams) {
  final initialSettings =
      creationParams is Map ? creationParams['initialSettings'] : null;
  return initialSettings is! Map ||
      initialSettings['disableHorizontalScroll'] != true ||
      initialSettings['disableVerticalScroll'] != true;
}

class CustomFlutterViewControllerValue {
  const CustomFlutterViewControllerValue({
    required this.isInitialized,
  });

  final bool isInitialized;

  CustomFlutterViewControllerValue copyWith({
    bool? isInitialized,
  }) {
    return CustomFlutterViewControllerValue(
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  CustomFlutterViewControllerValue.uninitialized()
      : this(
          isInitialized: false,
        );
}

/// Controls a WebView and provides streams for various change events.
class CustomPlatformViewController
    extends ValueNotifier<CustomFlutterViewControllerValue> {
  Completer<void> _creatingCompleter = Completer<void>();
  int _textureId = 0;
  bool _isDisposed = false;
  bool _hasPlatformView = false;

  Future<void> get ready => _creatingCompleter.future;

  late MethodChannel _methodChannel;
  late EventChannel _eventChannel;
  StreamSubscription? _eventStreamSubscription;

  final StreamController<SystemMouseCursor> _cursorStreamController =
      StreamController<SystemMouseCursor>.broadcast();

  /// A stream reflecting the current cursor style.
  Stream<SystemMouseCursor> get _cursor => _cursorStreamController.stream;

  CustomPlatformViewController()
      : super(CustomFlutterViewControllerValue.uninitialized());

  /// Initializes the underlying platform view.
  Future<void> initialize(
      {Function(int id)? onPlatformViewCreated, dynamic arguments}) async {
    if (_isDisposed) {
      _creatingCompleter.complete();
      return;
    }
    _textureId = (await _pluginChannel.invokeMethod<int>(
        'createInAppWebView', arguments))!;
    _hasPlatformView = true;
    if (_isDisposed) {
      _creatingCompleter.complete();
      return;
    }

    _methodChannel =
        MethodChannel('com.pichillilorenzo/custom_platform_view_$_textureId');
    _eventChannel = EventChannel(
        'com.pichillilorenzo/custom_platform_view_${_textureId}_events');
    _eventStreamSubscription =
        _eventChannel.receiveBroadcastStream().listen((event) {
      final map = event as Map<dynamic, dynamic>;
      switch (map['type']) {
        case 'cursorChanged':
          _cursorStreamController.add(_getCursorByName(map['value']));
          break;
      }
    });

    _methodChannel.setMethodCallHandler((call) {
      throw MissingPluginException('Unknown method ${call.method}');
    });

    value = value.copyWith(isInitialized: true);

    _creatingCompleter.complete();

    onPlatformViewCreated?.call(_textureId);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    super.dispose();
    await _creatingCompleter.future;
    await _eventStreamSubscription?.cancel();
    if (_hasPlatformView) {
      await _pluginChannel.invokeMethod('dispose', {"id": _textureId});
    }
    await _cursorStreamController.close();
  }

  /// Limits the number of frames per second to the given value.
  Future<void> setFpsLimit([int? maxFps = 0]) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel.invokeMethod('setFpsLimit', maxFps);
  }

  /// Sends a Pointer (Touch) update
  Future<void> _setPointerUpdate(InAppWebViewPointerEventKind kind, int pointer,
      Offset position, double size, double pressure) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel.invokeMethod('setPointerUpdate',
        [pointer, kind.index, position.dx, position.dy, size, pressure]);
  }

  /// Moves the virtual cursor to [position].
  Future<void> _setCursorPos(Offset position) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel
        .invokeMethod('setCursorPos', [position.dx, position.dy]);
  }

  /// Indicates whether the specified [button] is currently down.
  Future<void> _setPointerButtonState(PointerButton button, bool isDown) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel.invokeMethod('setPointerButton',
        <String, dynamic>{'button': button.index, 'isDown': isDown});
  }

  /// Sets the horizontal and vertical scroll delta.
  Future<void> _setScrollDelta(double dx, double dy) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel.invokeMethod('setScrollDelta', [dx, dy]);
  }

  /// Zooms by [scale] relative to the current zoom factor.
  Future<void> _setZoomScale(double scale) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel.invokeMethod('setZoomScale', scale);
  }

  /// Sets the surface size to the provided [size].
  Future<void> _setSize(Size size, double scaleFactor) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel
        .invokeMethod('setSize', [size.width, size.height, scaleFactor]);
  }

  /// Sets the surface size to the provided [size].
  Future<void> _setPosition(Offset position, double scaleFactor) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel
        .invokeMethod('setPosition', [position.dx, position.dy, scaleFactor]);
  }
}

class CustomPlatformView extends StatefulWidget {
  /// An optional scale factor. Defaults to [FlutterView.devicePixelRatio] for
  /// rendering in native resolution.
  /// Setting this to 1.0 will disable high-DPI support.
  /// This should only be needed to mimic old behavior before high-DPI support
  /// was available.
  final double? scaleFactor;

  /// The [FilterQuality] used for scaling the texture's contents.
  /// Defaults to [FilterQuality.none] as this renders in native resolution
  /// unless specifying a [scaleFactor].
  final FilterQuality filterQuality;

  final dynamic creationParams;

  final Function(int id)? onPlatformViewCreated;

  const CustomPlatformView(
      {this.creationParams,
      this.onPlatformViewCreated,
      this.scaleFactor,
      this.filterQuality = FilterQuality.none});

  @override
  _CustomPlatformViewState createState() => _CustomPlatformViewState();
}

class _CustomPlatformViewState extends State<CustomPlatformView> {
  final GlobalKey _key = GlobalKey();
  final _downButtons = <int, PointerButton>{};

  PointerDeviceKind _pointerKind = PointerDeviceKind.unknown;

  MouseCursor _cursor = SystemMouseCursors.basic;

  final _controller = CustomPlatformViewController();
  final _focusNode = FocusNode();
  Offset? _trackpadPointerPosition;
  double _trackpadScale = 1;
  bool _panning = false;

  StreamSubscription? _cursorSubscription;

  @override
  void initState() {
    super.initState();

    _controller.initialize(
        onPlatformViewCreated: (id) {
          if (!mounted) {
            return;
          }
          widget.onPlatformViewCreated?.call(id);
          setState(() {});
        },
        arguments: widget.creationParams);

    // Report initial surface size and widget position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _reportSurfaceSize();
      _reportWidgetPosition();
    });

    _cursorSubscription = _controller._cursor.listen((cursor) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cursor = cursor;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      canRequestFocus: true,
      debugLabel: "flutter_inappwebview_windows_custom_platform_view",
      onFocusChange: (focused) {},
      child: SizedBox.expand(key: _key, child: _buildInner()),
    );
  }

  Widget _buildInner() {
    return NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (notification) {
          _reportSurfaceSize();
          _reportWidgetPosition();
          return true;
        },
        child: SizeChangedLayoutNotifier(
            child: _controller.value.isInitialized
                ? _buildInputSurface()
                : const SizedBox()));
  }

  Widget _buildInputSurface() {
    final listener = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerHover: (ev) {
        // ev.kind is for whatever reason not set to touch even on touch input.
        if (_pointerKind != PointerDeviceKind.touch) {
          _controller._setCursorPos(ev.localPosition);
        }
      },
      onPointerDown: (ev) {
        _endTrackpadPointer();
        _reportSurfaceSize();
        _reportWidgetPosition();

        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && !_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
          });
        }

        _pointerKind = ev.kind;
        if (ev.kind == PointerDeviceKind.touch) {
          _controller._setPointerUpdate(InAppWebViewPointerEventKind.down,
              ev.pointer, ev.localPosition, ev.size, ev.pressure);
          return;
        }
        final button = _getButton(ev.buttons);
        _downButtons[ev.pointer] = button;
        _controller._setPointerButtonState(button, true);
      },
      onPointerUp: (ev) {
        _pointerKind = ev.kind;
        if (ev.kind == PointerDeviceKind.touch) {
          _controller._setPointerUpdate(InAppWebViewPointerEventKind.up,
              ev.pointer, ev.localPosition, ev.size, ev.pressure);
          return;
        }
        final button = _downButtons.remove(ev.pointer);
        if (button != null) {
          _controller._setPointerButtonState(button, false);
        }
      },
      onPointerCancel: (ev) {
        _pointerKind = ev.kind;
        final button = _downButtons.remove(ev.pointer);
        if (button != null) {
          _controller._setPointerButtonState(button, false);
        }
      },
      onPointerMove: (ev) {
        _pointerKind = ev.kind;
        if (ev.kind == PointerDeviceKind.touch) {
          _controller._setPointerUpdate(InAppWebViewPointerEventKind.update,
              ev.pointer, ev.localPosition, ev.size, ev.pressure);
        } else {
          _controller._setCursorPos(ev.localPosition);
        }
      },
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          _endTrackpadPointer();
          _sendScrollDelta(
            filterScrollDeltaForSettings(
              -signal.scrollDelta,
              widget.creationParams,
            ),
          );
        }
      },
      child: MouseRegion(
          cursor: _panning ? SystemMouseCursors.none : _cursor,
          child: Texture(
            textureId: _controller._textureId,
            filterQuality: widget.filterQuality,
          )),
    );
    if (!hasEnabledWebViewScrollAxis(widget.creationParams)) {
      return listener;
    }
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      gestures: <Type, GestureRecognizerFactory>{
        _WebViewTrackpadGestureRecognizer: GestureRecognizerFactoryWithHandlers<
            _WebViewTrackpadGestureRecognizer>(
          _WebViewTrackpadGestureRecognizer.new,
          (recognizer) => recognizer
            ..onStart = _handleTrackpadStart
            ..onUpdate = _handleTrackpadUpdate
            ..onEnd = _handleTrackpadEnd,
        ),
      },
      child: listener,
    );
  }

  void _sendScrollDelta(Offset delta) {
    if (delta != Offset.zero) {
      _controller._setScrollDelta(delta.dx, delta.dy);
    }
  }

  void _handleTrackpadStart(PointerPanZoomStartEvent event) {
    _endTrackpadPointer();
    _trackpadScale = 1;
    final position = _boundTrackpadPosition(event.localPosition);
    _trackpadPointerPosition = position;
    // The renderer scrolls a dragged pointer on its compositor, which is what
    // makes this smooth; the cursor is hidden because that pointer sweeps the
    // page and would otherwise drag the hover and the cursor shape with it.
    setState(() => _panning = true);
    _controller._setPointerUpdate(
      InAppWebViewPointerEventKind.down,
      _trackpadPointerId,
      position,
      1,
      1,
    );
  }

  void _handleTrackpadUpdate(PointerPanZoomUpdateEvent event) {
    // `scale` is cumulative from the start of the gesture, so the renderer is
    // sent the step since the last update.
    if ((event.scale - _trackpadScale).abs() > _trackpadZoomThreshold) {
      final step = event.scale / _trackpadScale;
      _trackpadScale = event.scale;
      _controller._setZoomScale(step);
      return;
    }

    final delta = webViewTrackpadDirectDelta(
      filterScrollDeltaForSettings(
        event.localPanDelta,
        widget.creationParams,
      ),
    );
    final currentPosition = _trackpadPointerPosition;
    if (currentPosition == null || delta == Offset.zero) {
      return;
    }
    final position = _boundTrackpadPosition(currentPosition + delta);
    _trackpadPointerPosition = position;
    _controller._setPointerUpdate(
      InAppWebViewPointerEventKind.update,
      _trackpadPointerId,
      position,
      1,
      1,
    );
  }

  void _handleTrackpadEnd(PointerPanZoomEndEvent event) {
    _trackpadScale = 1;
    _endTrackpadPointer();
  }

  Offset _boundTrackpadPosition(Offset position) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size;
    if (size == null) {
      return position;
    }
    return Offset(
      position.dx.clamp(0, size.width).toDouble(),
      position.dy.clamp(0, size.height).toDouble(),
    );
  }

  void _endTrackpadPointer() {
    if (_panning && mounted) {
      setState(() => _panning = false);
    }
    final position = _trackpadPointerPosition;
    if (position == null) {
      return;
    }
    _trackpadPointerPosition = null;
    _controller._setPointerUpdate(
      InAppWebViewPointerEventKind.up,
      _trackpadPointerId,
      position,
      1,
      0,
    );
  }

  void _reportSurfaceSize() async {
    await _controller.ready;
    if (!mounted) {
      return;
    }
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      return;
    }
    unawaited(_controller._setSize(
        box.size, widget.scaleFactor ?? window.devicePixelRatio));
  }

  void _reportWidgetPosition() async {
    await _controller.ready;
    if (!mounted) {
      return;
    }
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      return;
    }
    final position = box.localToGlobal(Offset.zero);
    unawaited(_controller._setPosition(
        position, widget.scaleFactor ?? window.devicePixelRatio));
  }

  @override
  void dispose() {
    _endTrackpadPointer();
    _cursorSubscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

class _WebViewTrackpadGestureRecognizer extends OneSequenceGestureRecognizer {
  _WebViewTrackpadGestureRecognizer()
      : super(supportedDevices: const {PointerDeviceKind.trackpad});

  void Function(PointerPanZoomStartEvent event)? onStart;
  void Function(PointerPanZoomUpdateEvent event)? onUpdate;
  void Function(PointerPanZoomEndEvent event)? onEnd;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    resolve(GestureDisposition.rejected);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart?.call(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      onUpdate?.call(event);
    } else if (event is PointerPanZoomEndEvent) {
      onEnd?.call(event);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'Windows WebView trackpad pan/zoom';
}
