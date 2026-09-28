import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';
import '_static_channel.dart';
import 'windows_webview_gesture_scope.dart';
import 'windows_webview_wheel_scope.dart';

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
  Future<void>? _disposeFuture;
  Map<String, dynamic>? _disposalDiagnostics;

  /// Numeric native lifecycle stages, only when the private fixture probe was
  /// explicitly armed. Normal views return no diagnostic payload.
  Map<String, dynamic>? get disposalDiagnostics => _disposalDiagnostics;

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
    try {
      _textureId = (await _pluginChannel.invokeMethod<int>(
          'createInAppWebView', arguments))!;
    } catch (_) {
      // Creation failed without a native view. Do not strand a disposal waiter;
      // the initialization error still propagates to its original caller.
      _creatingCompleter.complete();
      rethrow;
    }
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
  Future<void> dispose() {
    final pending = _disposeFuture;
    if (pending != null) return pending;
    _isDisposed = true;
    super.dispose();
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    await _creatingCompleter.future;
    await _eventStreamSubscription?.cancel();
    try {
      if (_hasPlatformView) {
        // The native reply follows actual texture unregister completion, not
        // removal from the manager map. Repeated dispose calls await this same
        // future, including callers joining the widget's unawaited teardown.
        final reply =
            await _pluginChannel.invokeMethod('dispose', {"id": _textureId});
        if (reply is Map) {
          _disposalDiagnostics = Map<String, dynamic>.from(reply);
        }
      }
    } finally {
      await _cursorStreamController.close();
      await _historyEvents.close();
    }
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
      Offset position, double size, double pressure,
      {Duration? timeStamp,
      Duration inputAge = Duration.zero,
      Offset? secondContact,
      int? inputEpoch}) async {
    if (_isDisposed) {
      return;
    }
    assert(value.isInitialized);
    return _methodChannel.invokeMethod('setPointerUpdate', [
      pointer, kind.index, position.dx, position.dy, size, pressure,
      // Only synthetic trackpad contacts use CDP. Real touchscreen packets
      // retain their original six-value SendPointerInput path.
      if (timeStamp != null) ...[
        timeStamp.inMicroseconds,
        inputAge.inMicroseconds
      ],
      if (secondContact != null) ...[secondContact.dx, secondContact.dy],
      if (inputEpoch != null) inputEpoch,
    ]);
  }

  Future<dynamic> _querySiteGesturePolicy(Offset position) async {
    if (_isDisposed || !value.isInitialized) return null;
    return _methodChannel.invokeMethod<dynamic>(
        'querySiteGesturePolicyState', [position.dx, position.dy]);
  }

  Future<bool?> _siteGestureFallbackReady(int epoch) async {
    if (_isDisposed || !value.isInitialized) return null;
    return _methodChannel.invokeMethod<bool>('siteGestureFallbackReady', epoch);
  }

  Future<void> _cancelTrackpadGesture() async {
    if (_isDisposed || !value.isInitialized) return;
    try {
      await _methodChannel.invokeMethod<void>('cancelTrackpadGesture');
    } on MissingPluginException {
      // A stale bundle has no policy query or synthetic contact to cancel.
    }
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
  CustomPlatformViewState createState() => CustomPlatformViewState();
}

class CustomPlatformViewState extends State<CustomPlatformView>
    with WidgetsBindingObserver {
  /// Retain before unmount, then await [CustomPlatformViewController.dispose]
  /// before disposing an environment or closing the native window.
  CustomPlatformViewController get controller => _controller;

  final GlobalKey _key = GlobalKey();
  final _downButtons = <int, PointerButton>{};

  PointerDeviceKind _pointerKind = PointerDeviceKind.unknown;

  MouseCursor _cursor = SystemMouseCursors.basic;
  MouseCursor _rendererCursor = SystemMouseCursors.basic;

  final _controller = CustomPlatformViewController();
  final _focusNode = FocusNode();
  Offset? _trackpadPointerPosition;
  Duration? _trackpadStartTime;
  Duration? _trackpadLastTime;
  Duration? _trackpadLastContactTime;
  int? _trackpadGesturePointer;
  Offset? _mousePosition;
  double _trackpadScale = 1;
  bool _panning = false;
  bool _disposing = false;
  bool _attached = true;
  bool _historyResetPending = false;
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
  int _policyGeneration = 0;
  bool _awaitingPolicy = false;
  Timer? _policyTimer;
  bool _policyTimedOut = false;
  bool _recoveringPolicy = false;
  bool _fallbackReady = false;
  bool _fallbackProbePending = false;
  int? _fallbackEpoch;
  double _siteScaleOrigin = 1;
  double _siteRotationOrigin = 0;
  bool _websiteGesture = false;
  bool _scopeEnabled = false;
  bool _preferWebsiteGestures = false;
  bool _sitePinching = false;
  bool _browserPinching = false;
  double _pinchBaseScale = 1;
  double _pinchBaseRotation = 0;
  double _trackpadRotation = 0;
  Offset _pendingPolicyPan = Offset.zero;
  PointerPanZoomUpdateEvent? _pendingPolicyUpdate;
  Stopwatch? _pendingPolicyAge;
  Offset _directPendingPan = Offset.zero;
  Size? _reportedSurfaceSize;
  double? _reportedScaleFactor;

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
  void deactivate() {
    _attached = false;
    // Fence a settling history completion even if this State is reparented and
    // active again before its asynchronous isValid check runs.
    ++_historyRevision;
    _endTrackpadPointer(cancelled: true);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    if (_historyResetPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_attached || _disposing || !_historyResetPending)
          return;
        _historyResetPending = false;
        _historySwipe.cancel();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CustomPlatformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.creationParams;
    final after = widget.creationParams;
    final oldSettings = before is Map ? before['initialSettings'] : null;
    final newSettings = after is Map ? after['initialSettings'] : null;
    if (filterScrollDeltaForSettings(const Offset(1, 1), before) !=
            filterScrollDeltaForSettings(const Offset(1, 1), after) ||
        (oldSettings is Map
                ? oldSettings['allowsBackForwardNavigationGestures']
                : null) !=
            (newSettings is Map
                ? newSettings['allowsBackForwardNavigationGestures']
                : null) ||
        (before is Map ? before['windowId'] : null) !=
            (after is Map ? after['windowId'] : null) ||
        (before is Map ? before['keepAliveId'] : null) !=
            (after is Map ? after['keepAliveId'] : null)) {
      _endTrackpadPointer(cancelled: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = WindowsWebViewGestureScope.maybeOf(context);
    final enabled = scope != null;
    final prefer = scope?.preferWebsiteGestures ?? false;
    if (enabled != _scopeEnabled || prefer != _preferWebsiteGestures) {
      _endTrackpadPointer(cancelled: true);
      _scopeEnabled = enabled;
      _preferWebsiteGestures = prefer;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _historySubscription = _controller._historyEvents.stream.listen((event) {
      if (!mounted || _disposing) return;
      if (event == 'navigationStarting') {
        if (_allowsHistorySwipes) {
          if (!_historySwipe.isActive) _historySwipe.captureCurrent();
          _historyRevision++;
          _historyLoading = true;
        }
        // Native navigation already fences its queue. Also retire the Dart
        // gesture, including on surfaces that do not offer history swipes.
        _endTrackpadPointer(
            cancelled: true,
            preserveHistoryAnimation: _historySwipe.isSettling);
      } else if (event == 'navigationCompleted') {
        _historyLoading = false;
      }
      if (_allowsHistorySwipes) unawaited(_refreshHistory());
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
      onPointerSignal: _onPointerSignal,
      child: MouseRegion(
          cursor: _cursor,
          child: Texture(
            textureId: _controller._textureId,
            filterQuality: widget.filterQuality,
          )),
    );
    if (!hasEnabledWebViewScrollAxis(widget.creationParams) &&
        !_allowsHistorySwipes &&
        !_scopeEnabled) {
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
            ..canStart = (() =>
                _attached &&
                !_historyResetPending &&
                !_historySwipe.isSettling &&
                !_disposing)
            ..onStart = _handleTrackpadStart
            ..onUpdate = _handleTrackpadUpdate
            ..onEnd = _handleTrackpadEnd
            ..onCancel = () => _endTrackpadPointer(cancelled: true),
        ),
      },
      child: listener,
    );
  }

  void _onPointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent || !mounted || !_attached || _disposing)
      return;
    final scope = WindowsWebViewWheelScope.maybeOf(context);
    if (scope == null &&
        filterScrollDeltaForSettings(
                signal.scrollDelta, widget.creationParams) ==
            Offset.zero) {
      return;
    }
    // Register only when this listener actually receives the event. An inactive
    // host's ScrollGestureGate can still suppress delivery and let Flutter win.
    GestureBinding.instance.pointerSignalResolver.register(signal, (_) {
      if (!mounted || !_attached || _disposing) return;
      _endTrackpadPointer();
      final remaining = scope?.transform(signal) ?? signal.scrollDelta;
      if (!mounted || !_attached || _disposing || !remaining.isFinite) return;
      _sendScrollDelta(
          filterScrollDeltaForSettings(-remaining, widget.creationParams));
    });
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
    _trackpadStartTime = _trackpadLastTime = event.timeStamp;
    _trackpadLastContactTime = null;
    _trackpadGesturePointer = event.pointer;
    _trackpadTouchStarted = false;
    _sitePinching = _browserPinching = false;
    _siteScaleOrigin = 1;
    _siteRotationOrigin = 0;
    _trackpadRotation = 0;
    _directPendingPan = Offset.zero;
    _websiteGesture = _preferWebsiteGestures;
    _trackpadIntent = _allowsHistorySwipes
        ? _TrackpadIntent.undecided
        : _TrackpadIntent.direct;
    _historyPan = Offset.zero;
    _historyDirection = 0;
    _mousePosition = event.localPosition;
    // Keep the real mouse visible and anchored. Cursor changes caused by the
    // renderer's scrolling touch contact must not replace its shape.
    setState(() => _panning = true);
    if (_websiteGesture) {
      _trackpadIntent = _TrackpadIntent.direct;
    } else {
      _awaitingPolicy = true;
      final generation = _policyGeneration;
      _policyTimer = Timer(const Duration(milliseconds: 150), () {
        _policyTimer = null;
        if (!mounted || _disposing || generation != _policyGeneration) return;
        _policyTimedOut = true;
        _clearPendingPolicy();
        // Keep the actual native reply outstanding. A deadline is not a CDP
        // completion or authority to send input to an unverified document.
      });
      unawaited(_resolveSitePolicy(event, _policyGeneration));
    }
  }

  Future<void> _resolveSitePolicy(
      PointerPanZoomStartEvent start, int generation) async {
    dynamic policy;
    try {
      policy = await _controller._querySiteGesturePolicy(start.localPosition);
    } on PlatformException {
      // Unknown policy must not navigate away from an interactive page.
    } on MissingPluginException {
      // A stale native bundle cannot safely arbitrate this gesture.
    }
    if (!mounted || _disposing || generation != _policyGeneration) return;
    _policyTimer?.cancel();
    _policyTimer = null;
    final status = policy is Map ? policy['status'] : null;
    final epoch = policy is Map ? policy['epoch'] : null;
    final website = policy is bool
        ? policy
        : status == 'site'
            ? true
            : status == 'browser'
                ? false
                : null;
    if (!_isCurrentHistoryTarget(start) ||
        (website == null && status != 'indeterminate') ||
        ((_policyTimedOut || website == null) &&
            (epoch is! int || epoch < 0))) {
      _endTrackpadPointer(cancelled: true);
      return;
    }
    _awaitingPolicy = false;
    if (_policyTimedOut || website == null) {
      // No history/browser zoom for an unknown region. Drop old motion; after
      // the shared slot settles, rebase on a genuinely new sample at this hit.
      _clearPendingPolicy();
      _fallbackEpoch = epoch as int;
      _recoveringPolicy = true;
      _websiteGesture = true;
      _trackpadIntent = _TrackpadIntent.direct;
      return;
    }
    _websiteGesture = website;
    if (website) _trackpadIntent = _TrackpadIntent.direct;
    final update = _pendingPolicyUpdate;
    final pan = _pendingPolicyPan;
    final age = _pendingPolicyAge?.elapsed ?? Duration.zero;
    _clearPendingPolicy();
    if (update != null) {
      _handleTrackpadUpdate(update, accumulatedPan: pan, inputAge: age);
    }
  }

  void _clearPendingPolicy() {
    _pendingPolicyUpdate = null;
    _pendingPolicyPan = Offset.zero;
    _pendingPolicyAge?.stop();
    _pendingPolicyAge = null;
  }

  Future<void> _probeFallbackReady(int generation, int epoch) async {
    _fallbackProbePending = true;
    bool? ready;
    try {
      ready = await _controller._siteGestureFallbackReady(epoch);
    } on PlatformException {
      // An unavailable/retired channel is not an indeterminate hit region.
    } on MissingPluginException {
      // Do not recover through a legacy bundle with no native epoch fence.
    } finally {
      // Do not release a pending state read early, even on cancellation. There
      // is at most one actual probe per view; future samples can retry it.
      _fallbackProbePending = false;
    }
    if (!mounted || _disposing || generation != _policyGeneration) return;
    if (ready == null) {
      _endTrackpadPointer(cancelled: true);
    } else {
      _fallbackReady = ready;
    }
  }

  void _beginTrackpadTouch(Duration latestSampleTime,
      {Duration inputAge = Duration.zero}) {
    final position = _trackpadPointerPosition;
    final startTime = _trackpadStartTime;
    if (_trackpadTouchStarted || position == null || startTime == null) return;
    _trackpadTouchStarted = true;
    _controller._setPointerUpdate(
      InAppWebViewPointerEventKind.down,
      _trackpadPointerId,
      position,
      1,
      1,
      timeStamp: startTime,
      inputEpoch: _fallbackEpoch,
      // Classification can defer touchStart until the first vertical update.
      // Carry that known age so native time mapping doesn't move the start to
      // the update's arrival. Both values share Flutter's original time origin.
      inputAge: latestSampleTime > startTime
          ? latestSampleTime - startTime + inputAge
          : inputAge,
    );
  }

  void _handleTrackpadUpdate(PointerPanZoomUpdateEvent event,
      {Offset? accumulatedPan, Duration inputAge = Duration.zero}) {
    if (_trackpadPointerPosition == null ||
        _trackpadGesturePointer != event.pointer) return;
    if (!_isCurrentHistoryTarget(event)) {
      _endTrackpadPointer(cancelled: true);
      return;
    }
    var panDelta = accumulatedPan ?? event.localPanDelta;
    if (!panDelta.isFinite ||
        !event.scale.isFinite ||
        event.scale <= 0 ||
        !event.rotation.isFinite) {
      _endTrackpadPointer(cancelled: true);
      return;
    }
    if (_awaitingPolicy) {
      if (_policyTimedOut) return;
      _pendingPolicyPan += panDelta;
      _pendingPolicyUpdate = event;
      _pendingPolicyAge?.stop();
      _pendingPolicyAge = Stopwatch()..start();
      return;
    }
    final previousTime = _trackpadLastTime ?? event.timeStamp;
    if (event.timeStamp <= previousTime) {
      _endTrackpadPointer(cancelled: true);
      return;
    }
    if (_recoveringPolicy) {
      if (!_fallbackReady) {
        if (!_fallbackProbePending) {
          unawaited(_probeFallbackReady(_policyGeneration, _fallbackEpoch!));
        }
        return;
      }
      // This sample arrived AFTER readiness, rather than being retained by an
      // async callback. Discard accumulated displacement and cumulative scale.
      _recoveringPolicy = false;
      _trackpadStartTime = _trackpadLastTime = event.timeStamp;
      _trackpadScale = _siteScaleOrigin = event.scale;
      _trackpadRotation = _siteRotationOrigin = event.rotation;
      _directPendingPan = Offset.zero;
      return;
    }
    _trackpadLastTime = event.timeStamp;
    if (_websiteGesture &&
        (_sitePinching ||
            (event.scale / _siteScaleOrigin - 1).abs() >
                _trackpadZoomThreshold ||
            (event.rotation - _siteRotationOrigin).abs() > 0.01)) {
      _sendSitePinch(event, panDelta, previousTime, inputAge);
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
    if (!_websiteGesture &&
        (event.scale - _trackpadScale).abs() > _trackpadZoomThreshold) {
      // Once an article pan becomes browser zoom, cancel its old touch stream
      // rather than ending it into a click/fling underneath the pinch.
      if (_trackpadTouchStarted) {
        _controller._setPointerUpdate(InAppWebViewPointerEventKind.leave,
            _trackpadPointerId, _trackpadPointerPosition!, 1, 0,
            timeStamp: previousTime);
        _trackpadTouchStarted = false;
      }
      _browserPinching = true;
      final step = event.scale / _trackpadScale;
      _trackpadScale = event.scale;
      _controller._setZoomScale(step);
      return;
    }
    if (_browserPinching) return;

    if (!_trackpadTouchStarted) {
      _directPendingPan += panDelta;
      if (_directPendingPan.distance < 12) return;
      panDelta = _directPendingPan;
      _directPendingPan = Offset.zero;
    }

    final delta = webViewTrackpadDirectDelta(
      _websiteGesture
          ? panDelta
          : filterScrollDeltaForSettings(
              panDelta,
              widget.creationParams,
            ),
    );
    final currentPosition = _trackpadPointerPosition;
    if (currentPosition == null || delta == Offset.zero) {
      return;
    }
    _beginTrackpadTouch(event.timeStamp, inputAge: inputAge);
    final position = _boundTrackpadPosition(currentPosition + delta);
    _trackpadPointerPosition = position;
    _controller._setPointerUpdate(
      InAppWebViewPointerEventKind.update,
      _trackpadPointerId,
      position,
      1,
      1,
      timeStamp: event.timeStamp,
      inputAge: inputAge,
      inputEpoch: _fallbackEpoch,
    );
    _trackpadLastContactTime = event.timeStamp;
    _trackpadScale = event.scale;
    _trackpadRotation = event.rotation;
  }

  void _sendSitePinch(PointerPanZoomUpdateEvent event, Offset panDelta,
      Duration previousTime, Duration inputAge) {
    var center = _trackpadPointerPosition!;
    if (!_sitePinching) {
      // Late pinch starts at the last actual contact sample, not the original
      // gesture start (which can predate a dispatched one-contact move).
      final startTime = _trackpadTouchStarted
          ? _trackpadLastContactTime!
          : _trackpadStartTime!;
      // Native Start atomically fences the old contact with touchCancel, then
      // starts the pair using the existing source-clock mapping. A separate
      // Dart cancel here would discard that clock before it can be preserved.
      _sitePinching = true;
      _trackpadTouchStarted = true;
      _pinchBaseScale = _trackpadScale;
      _pinchBaseRotation = _trackpadRotation;
      final offset = const Offset(0, 24);
      _controller._setPointerUpdate(InAppWebViewPointerEventKind.down,
          _trackpadPointerId, _boundTrackpadPosition(center - offset), 1, 1,
          secondContact: _boundTrackpadPosition(center + offset),
          timeStamp: startTime,
          inputEpoch: _fallbackEpoch,
          inputAge: event.timeStamp - startTime + inputAge);
      panDelta += _directPendingPan;
      _directPendingPan = Offset.zero;
    }
    center =
        _boundTrackpadPosition(center + webViewTrackpadDirectDelta(panDelta));
    _trackpadPointerPosition = center;
    final angle = event.rotation - _pinchBaseRotation;
    final radius = (24 * event.scale / _pinchBaseScale).clamp(1.0, 240.0);
    final offset = Offset(math.sin(angle) * radius, math.cos(angle) * radius);
    _controller._setPointerUpdate(InAppWebViewPointerEventKind.update,
        _trackpadPointerId, _boundTrackpadPosition(center - offset), 1, 1,
        secondContact: _boundTrackpadPosition(center + offset),
        inputEpoch: _fallbackEpoch,
        timeStamp: event.timeStamp,
        inputAge: inputAge);
    _trackpadLastContactTime = event.timeStamp;
    _trackpadScale = event.scale;
    _trackpadRotation = event.rotation;
  }

  void _handleTrackpadEnd(PointerPanZoomEndEvent event) {
    if (_trackpadGesturePointer != event.pointer) return;
    final history = _trackpadIntent == _TrackpadIntent.history;
    final revision = _gestureRevision;
    final navigate = _trackpadIntent == _TrackpadIntent.history &&
        _historyPan.dx * _historyDirection >= 96 &&
        _historyPan.dx.abs() >= 2 * _historyPan.dy.abs() &&
        _isCurrentHistoryTarget(event) &&
        revision == _historyRevision;
    final forward = _historyDirection < 0;
    _trackpadScale = 1;
    _endTrackpadPointer(
      cancelled: !_isCurrentHistoryTarget(event),
      preserveHistoryAnimation: history,
      timeStamp: event.timeStamp,
    );
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

  bool _isCurrentHistoryTarget(PointerEvent event) {
    if (!mounted ||
        !_attached ||
        _historyResetPending ||
        _disposing ||
        ModalRoute.of(context)?.isCurrent == false) {
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
      {bool cancelled = true,
      bool preserveHistoryAnimation = false,
      Duration? timeStamp}) {
    ++_policyGeneration;
    _policyTimer?.cancel();
    _policyTimer = null;
    if (_awaitingPolicy || _recoveringPolicy) {
      unawaited(_controller._cancelTrackpadGesture());
    }
    _awaitingPolicy = false;
    _policyTimedOut = false;
    _recoveringPolicy = _fallbackReady = false;
    final epoch = _fallbackEpoch;
    _fallbackEpoch = null;
    _clearPendingPolicy();
    if (!preserveHistoryAnimation && !_disposing) {
      // cancel() writes AnimationController.value and notifies descendants.
      // During deactivate those descendants are still active, but cannot be
      // dirtied in the unrelated ancestor's build scope. Native input and all
      // policy generations are retired now; only the visual reset is deferred.
      if (!_attached || _historyResetPending) {
        _historyResetPending = true;
      } else {
        _historySwipe.cancel();
      }
    }
    _trackpadIntent = _TrackpadIntent.direct;
    _historyPan = Offset.zero;
    _historyDirection = 0;
    if (_panning) {
      _panning = false;
      _cursor = _rendererCursor;
      if (mounted && _attached && !_disposing) setState(() {});
    }
    final sampleTime = timeStamp ?? _trackpadLastTime ?? _trackpadStartTime;
    _trackpadStartTime = _trackpadLastTime = null;
    _trackpadGesturePointer = null;
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
        timeStamp: sampleTime,
        inputEpoch: epoch,
      );
    _trackpadTouchStarted = false;
    final mousePosition = _mousePosition;
    if (mounted && _attached && !_disposing && mousePosition != null) {
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
    final scale = widget.scaleFactor ?? window.devicePixelRatio;
    if (_reportedSurfaceSize != null &&
        (_reportedSurfaceSize != box.size || _reportedScaleFactor != scale)) {
      _endTrackpadPointer(cancelled: true);
    }
    _reportedSurfaceSize = box.size;
    _reportedScaleFactor = scale;
    unawaited(_controller._setSize(box.size, scale));
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
