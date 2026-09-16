import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';
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

enum _TrackpadIntent { direct, undecided, history }

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
  final _historyEvents = StreamController<String>.broadcast();

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
        case 'historyChanged':
        case 'navigationStarting':
        case 'navigationCompleted':
          _historyEvents.add(map['type'] as String);
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
    await _historyEvents.close();
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

  Future<void> _navigateHistory(bool forward) async {
    if (_isDisposed) return;
    await _methodChannel.invokeMethod<bool>('navigateHistory', forward);
  }

  Future<Map<dynamic, dynamic>?> _getHistoryState() async {
    if (_isDisposed || !value.isInitialized) return null;
    return _methodChannel.invokeMapMethod('getHistoryState');
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

class _CustomPlatformViewState extends State<CustomPlatformView>
    with WidgetsBindingObserver {
  final GlobalKey _key = GlobalKey();
  final _downButtons = <int, PointerButton>{};

  PointerDeviceKind _pointerKind = PointerDeviceKind.unknown;

  MouseCursor _cursor = SystemMouseCursors.basic;
  MouseCursor _rendererCursor = SystemMouseCursors.basic;

  final _controller = CustomPlatformViewController();
  final _focusNode = FocusNode();
  Offset? _trackpadPointerPosition;
  Offset? _mousePosition;
  double _trackpadScale = 1;
  bool _panning = false;
  bool _disposing = false;
  bool _trackpadTouchStarted = false;
  _TrackpadIntent _trackpadIntent = _TrackpadIntent.direct;
  Offset _historyPan = Offset.zero;
  double _historyDirection = 0;
  final _historySwipe = HistorySwipeController();
  Map<dynamic, dynamic> _historyState = const {};
  int _historyRevision = 0;
  int _historyRequest = 0;
  int _gestureRevision = 0;
  bool _historyLoading = false;
  StreamSubscription<String>? _historySubscription;

  bool get _allowsHistorySwipes {
    final params = widget.creationParams;
    final settings = params is Map ? params['initialSettings'] : null;
    // Do not take horizontal pan away from a general-purpose webview. Bookmark
    // reading surfaces explicitly disable that axis and opt into navigation.
    return settings is Map &&
        settings['allowsBackForwardNavigationGestures'] == true &&
        settings['disableHorizontalScroll'] == true &&
        settings['disableVerticalScroll'] != true;
  }

  StreamSubscription? _cursorSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _historySubscription = _controller._historyEvents.stream.listen((event) {
      if (!_allowsHistorySwipes || !mounted || _disposing) return;
      if (event == 'navigationStarting') {
        if (!_historySwipe.isActive) _historySwipe.captureCurrent();
        _historyRevision++;
        _historyLoading = true;
        _endTrackpadPointer(
            cancelled: true,
            preserveHistoryAnimation: _historySwipe.isSettling);
      } else if (event == 'navigationCompleted') {
        _historyLoading = false;
      }
      unawaited(_refreshHistory());
    });

    _controller.initialize(
        onPlatformViewCreated: (id) {
          if (!mounted) {
            return;
          }
          widget.onPlatformViewCreated?.call(id);
          setState(() {});
          if (_allowsHistorySwipes) unawaited(_refreshHistory());
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
      _rendererCursor = cursor;
      if (!mounted || _disposing || _panning || cursor == _cursor) {
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
      child: SizedBox.expand(
        key: _key,
        // Remains hit-testable while the moving sheet blocks clicks. A hidden
        // IndexedStack tab is still excluded by its parent, not by its pixels.
        child: Listener(behavior: HitTestBehavior.opaque, child: _buildInner()),
      ),
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
                ? _allowsHistorySwipes
                    ? HistorySwipeSurface(
                        controller: _historySwipe,
                        pageKey: _historyState['current'],
                        scope: _controller,
                        pageReady: !_historyLoading,
                        // Native pixels can already belong to the new page
                        // when history-state replies arrive. Capture before
                        // navigation instead of relabelling those pixels.
                        captureOnPageChange: false,
                        child: _buildInputSurface(),
                      )
                    : _buildInputSurface()
                : const SizedBox()));
  }

  Widget _buildInputSurface() {
    final listener = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerHover: (ev) {
        _mousePosition = ev.localPosition;
        // ev.kind is for whatever reason not set to touch even on touch input.
        if (!_panning && _pointerKind != PointerDeviceKind.touch) {
          _controller._setCursorPos(ev.localPosition);
        }
      },
      onPointerDown: (ev) {
        if (ev.kind != PointerDeviceKind.touch) {
          _mousePosition = ev.localPosition;
        }
        _endTrackpadPointer();
        if (_allowsHistorySwipes) _historySwipe.captureCurrent();
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
        _controller._setCursorPos(ev.localPosition);
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
        _endTrackpadPointer(cancelled: true);
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
          _mousePosition = ev.localPosition;
          if (!_panning) _controller._setCursorPos(ev.localPosition);
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
          cursor: _cursor,
          child: Texture(
            textureId: _controller._textureId,
            filterQuality: widget.filterQuality,
          )),
    );
    if (!hasEnabledWebViewScrollAxis(widget.creationParams) &&
        !_allowsHistorySwipes) {
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
            ..canStart = (() => !_historySwipe.isSettling && !_disposing)
            ..onStart = _handleTrackpadStart
            ..onUpdate = _handleTrackpadUpdate
            ..onEnd = _handleTrackpadEnd
            ..onCancel = () => _endTrackpadPointer(cancelled: true),
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
    _gestureRevision = _historyRevision;
    _trackpadScale = 1;
    final position = _boundTrackpadPosition(event.localPosition);
    _trackpadPointerPosition = position;
    _trackpadTouchStarted = false;
    _trackpadIntent = _allowsHistorySwipes
        ? _TrackpadIntent.undecided
        : _TrackpadIntent.direct;
    _historyPan = Offset.zero;
    _historyDirection = 0;
    _mousePosition = event.localPosition;
    // Keep the real mouse visible and anchored. Cursor changes caused by the
    // renderer's scrolling touch contact must not replace its shape.
    setState(() => _panning = true);
    if (_trackpadIntent == _TrackpadIntent.direct) _beginTrackpadTouch();
  }

  void _beginTrackpadTouch() {
    final position = _trackpadPointerPosition;
    if (_trackpadTouchStarted || position == null) return;
    _trackpadTouchStarted = true;
    _controller._setPointerUpdate(
      InAppWebViewPointerEventKind.down,
      _trackpadPointerId,
      position,
      1,
      1,
    );
  }

  void _handleTrackpadUpdate(PointerPanZoomUpdateEvent event) {
    if (_trackpadPointerPosition == null) return;
    var panDelta = event.localPanDelta;
    if (!panDelta.isFinite ||
        !event.scale.isFinite ||
        !event.rotation.isFinite) {
      _endTrackpadPointer(cancelled: true);
      return;
    }
    if (_trackpadIntent != _TrackpadIntent.direct) {
      if ((event.scale - 1).abs() > _trackpadZoomThreshold ||
          event.rotation.abs() > 0.01) {
        // Pinching is never history. No touch start/end pair is generated for
        // a pinch-only gesture (which would click the link under the pointer).
        _historySwipe.cancel();
        _trackpadIntent = _TrackpadIntent.direct;
      } else {
        _historyPan += panDelta;
        if (_trackpadIntent == _TrackpadIntent.history) {
          _historySwipe.update(_historyPan.dx * _historyDirection);
          return;
        }
        if (_historyPan.dx.abs() < 12 && _historyPan.dy.abs() < 12) return;
        if (_historyPan.dx.abs() >= 2 * _historyPan.dy.abs()) {
          _trackpadIntent = _TrackpadIntent.history;
          _historyDirection = _historyPan.dx.sign;
          final forward = _historyDirection < 0;
          _historySwipe.begin(
            forward: forward,
            available: _historyState[forward ? 'forward' : 'back'] == true,
            target: _historyState[forward ? 'next' : 'previous'],
          );
          _historySwipe.update(_historyPan.dx * _historyDirection);
          return;
        }
        // Once vertical/diagonal, keep the gesture as scrolling. Replay the
        // small undecided distance once; do not lose or double its movement.
        _trackpadIntent = _TrackpadIntent.direct;
        panDelta = _historyPan;
      }
    }
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
        panDelta,
        widget.creationParams,
      ),
    );
    final currentPosition = _trackpadPointerPosition;
    if (currentPosition == null || delta == Offset.zero) {
      return;
    }
    _beginTrackpadTouch();
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
    final history = _trackpadIntent == _TrackpadIntent.history;
    final revision = _gestureRevision;
    final navigate = _trackpadIntent == _TrackpadIntent.history &&
        _historyPan.dx * _historyDirection >= 96 &&
        _historyPan.dx.abs() >= 2 * _historyPan.dy.abs() &&
        _isCurrentHistoryTarget(event) &&
        revision == _historyRevision;
    final forward = _historyDirection < 0;
    _trackpadScale = 1;
    _endTrackpadPointer(preserveHistoryAnimation: history);
    if (history && !_disposing) {
      unawaited(_historySwipe.finish(
        commit: navigate,
        isValid: () =>
            !_disposing &&
            mounted &&
            revision == _historyRevision &&
            _isCurrentHistoryTarget(event),
        navigate: () => _controller._navigateHistory(forward),
      ));
    }
  }

  Future<void> _refreshHistory() async {
    final request = ++_historyRequest;
    try {
      final state = await _controller._getHistoryState();
      if (!mounted || _disposing || state == null || request != _historyRequest)
        return;
      if (state['current'] != _historyState['current']) _historyRevision++;
      setState(() {
        _historyState = state;
        _historyLoading = state['loading'] == true;
      });
    } on PlatformException {
      // A renderer being disposed must not strand a transition.
      if (mounted && !_disposing) _historySwipe.cancel();
    } on MissingPluginException {
      // Older hosts have no preview state. No false navigation availability.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _endTrackpadPointer(cancelled: true);
    } else if (_allowsHistorySwipes) {
      unawaited(_refreshHistory());
    }
  }

  bool _isCurrentHistoryTarget(PointerPanZoomEndEvent event) {
    if (!mounted || _disposing || ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    // IndexedStack keeps background tabs alive. Only the currently hit-tested
    // webview may navigate; a tab switch/modal during the swipe cancels it.
    final target = _key.currentContext?.findRenderObject();
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    return hit.path.any((entry) => identical(entry.target, target));
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

  void _endTrackpadPointer(
      {bool cancelled = false, bool preserveHistoryAnimation = false}) {
    if (!preserveHistoryAnimation) _historySwipe.cancel();
    _trackpadIntent = _TrackpadIntent.direct;
    _historyPan = Offset.zero;
    _historyDirection = 0;
    if (_panning) {
      _panning = false;
      _cursor = _rendererCursor;
      if (mounted && !_disposing) setState(() {});
    }
    final position = _trackpadPointerPosition;
    if (position == null) {
      return;
    }
    _trackpadPointerPosition = null;
    if (_trackpadTouchStarted)
      _controller._setPointerUpdate(
        cancelled
            ? InAppWebViewPointerEventKind.leave
            : InAppWebViewPointerEventKind.up,
        _trackpadPointerId,
        position,
        1,
        0,
      );
    _trackpadTouchStarted = false;
    final mousePosition = _mousePosition;
    if (mounted && !_disposing && mousePosition != null) {
      _controller._setCursorPos(mousePosition);
    }
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
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _endTrackpadPointer(cancelled: true);
    _historySubscription?.cancel();
    _historySwipe.dispose();
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
  VoidCallback? onCancel;
  bool Function()? canStart;

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      (canStart?.call() ?? true) && super.isPointerPanZoomAllowed(event);

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
    } else if (event is PointerCancelEvent) {
      onCancel?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    onCancel?.call();
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'Windows WebView trackpad pan/zoom';
}
