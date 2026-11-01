/// A WebKitGTK web view drawn into a Flutter texture, for Linux, where
/// Flutter has no platform views.
///
/// The page renders offscreen; [LinuxWebView] shows its pictures and forwards
/// pointer input, and key presses go to the page while the view has focus.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const MethodChannel _channel = MethodChannel('appflowy_linux_webview');

/// Logical pixels Flutter's Linux embedder reports per GDK scroll step.
const double _scrollStep = 53;

/// Pixels WebKitGTK scrolls per GDK scroll step for a precise device (one
/// that is not a mouse), so a precise wheel of `pixels / 40` steps reaches
/// the page as `deltaX/Y` of `pixels`.
const double _webKitScrollStep = 40;

/// A pause this long before the fingers lift is a stop, not a fling.
const Duration _flingPause = Duration(milliseconds: 100);

/// GDK state bits for the primary, middle and secondary buttons.
const int _gdkButton1Mask = 1 << 8;
const int _gdkButton2Mask = 1 << 9;
const int _gdkButton3Mask = 1 << 10;

/// A web view made by [create] and shown by [LinuxWebView].
class LinuxWebViewController {
  LinuxWebViewController._(this._id, this.textureId);

  /// The script message handler a page posts strings to for [messages]:
  /// `window.webkit.messageHandlers.appflowyLinuxWebViewMessage
  /// .postMessage(text)`, from any frame.
  static const String messageHandler = 'appflowyLinuxWebViewMessage';

  static final Map<String, LinuxWebViewController> _controllers = {};
  static bool _connected = false;
  static int _nextId = 0;

  /// Whether web views work here: Linux with WebKitGTK installed.
  static Future<bool> isSupported() async {
    if (kIsWeb || !Platform.isLinux) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Starts loading [url], running [userScripts] at the start of every frame.
  ///
  /// Links that would open a new window open in the browser instead, unless
  /// they lead back to [url]'s origin.
  static Future<LinuxWebViewController> create({
    required Uri url,
    List<String> userScripts = const [],
    Size size = const Size(800, 600),
  }) async {
    // Registering again keeps the handler in the zone of the latest caller.
    _channel.setMethodCallHandler(_handle);
    if (!_connected) {
      _connected = true;
      // A restarted isolate has no handle on views the previous one made.
      // Channel calls arrive in order, so this also runs before any create
      // that does not wait for it.
      await _channel.invokeMethod<void>('disposeAll');
    }
    final id = 'view-${_nextId++}';
    final textureId = await _channel.invokeMethod<int>('create', {
      'id': id,
      'url': url.toString(),
      'origin': url.origin,
      'userScripts': userScripts,
      'width': size.width.round(),
      'height': size.height.round(),
    });
    if (textureId == null) {
      throw PlatformException(
        code: 'create_failed',
        message: 'The web view did not start.',
      );
    }
    return _controllers[id] = LinuxWebViewController._(id, textureId);
  }

  static Future<void> _handle(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is! Map<Object?, Object?>) {
      return;
    }
    final controller = _controllers[arguments['id']];
    if (controller == null) {
      return;
    }
    switch (call.method) {
      case 'cursor':
        final cursor = arguments['cursor'];
        if (cursor is String) {
          controller._cursor.value = mouseCursorForCss(cursor);
        }
      case 'message':
        final message = arguments['message'];
        if (message is String && !controller._messages.isClosed) {
          controller._messages.add(message);
        }
    }
  }

  final String _id;

  /// The Flutter texture the page draws into.
  final int textureId;

  final ValueNotifier<MouseCursor> _cursor =
      ValueNotifier(SystemMouseCursors.basic);
  final StreamController<String> _messages = StreamController.broadcast();
  bool _disposed = false;

  /// The cursor the page shows under the pointer.
  ValueListenable<MouseCursor> get cursor => _cursor;

  /// The strings the page posts to [messageHandler].
  Stream<String> get messages => _messages.stream;

  bool get isDisposed => _disposed;

  /// Replaces the user scripts; the page runs them from its next load.
  Future<void> setUserScripts(List<String> userScripts) =>
      _invoke('setUserScripts', {'userScripts': userScripts});

  /// Runs [source] in the page's main frame, without waiting for a result.
  Future<void> evaluateJavascript(String source) =>
      _invoke('evaluate', {'source': source});

  /// Stops the view and frees its texture.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await _invoke('dispose');
    _disposed = true;
    _controllers.remove(_id);
    unawaited(_messages.close());
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (_disposed) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, {'id': _id, ...?arguments});
    } on PlatformException catch (error) {
      debugPrint('LinuxWebView $method failed: ${error.message}');
    } on MissingPluginException {
      // The engine is shutting down.
    }
  }

  void _geometry(Size size, Offset origin) => unawaited(
        _invoke('geometry', {
          'width': size.width.round(),
          'height': size.height.round(),
          'x': origin.dx,
          'y': origin.dy,
        }),
      );

  void _focus(bool focused) =>
      unawaited(_invoke('focus', {'focused': focused}));

  void _active(bool active) => unawaited(_invoke('active', {'active': active}));

  void _pointer(
    String kind,
    PointerEvent event, {
    int button = 0,
    required int buttons,
    Offset delta = Offset.zero,
    bool precise = false,
  }) {
    unawaited(
      _invoke('pointer', {
        'kind': kind,
        'x': event.localPosition.dx,
        'y': event.localPosition.dy,
        'button': button,
        'buttons': buttons,
        'dx': delta.dx,
        'dy': delta.dy,
        'precise': precise,
        'time': event.timeStamp.inMilliseconds,
      }),
    );
  }
}

/// Lets a host take part in the wheel and trackpad input over the
/// [LinuxWebView]s below it, for example to move a page header first.
class LinuxWebViewScrollScope extends InheritedWidget {
  const LinuxWebViewScrollScope({
    super.key,
    required this.transform,
    this.pixelWheel = false,
    this.trackpad,
    required super.child,
  });

  /// Runs once for each wheel event a view wins in Flutter's pointer signal
  /// resolver, and returns the motion left for the page in
  /// [PointerScrollEvent.scrollDelta] units and sign. [Offset.zero] consumes
  /// it all.
  final Offset Function(PointerScrollEvent event) transform;

  /// Delivers the page's motion at WebKit's pixel scale, so the page reads
  /// the exact logical distance from a wheel event's `deltaX/Y`, rather than
  /// one GDK scroll step per 53 pixels.
  final bool pixelWheel;

  /// Sends two-finger pans through the host before the page receives them as
  /// wheel input.
  final LinuxWebViewTrackpad? trackpad;

  static LinuxWebViewScrollScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LinuxWebViewScrollScope>();

  @override
  bool updateShouldNotify(LinuxWebViewScrollScope oldWidget) =>
      transform != oldWidget.transform ||
      pixelWheel != oldWidget.pixelWheel ||
      trackpad != oldWidget.trackpad;
}

/// Host callbacks for two-finger trackpad pans over a [LinuxWebView].
@immutable
class LinuxWebViewTrackpad {
  const LinuxWebViewTrackpad({
    this.onStart,
    required this.onUpdate,
    this.onEnd,
  });

  /// A two-finger gesture started over the view.
  final VoidCallback? onStart;

  /// Receives each pan in [PointerScrollEvent.scrollDelta] units and sign
  /// (positive scrolls down or right), and returns the part the page gets.
  final Offset Function(Offset delta) onUpdate;

  /// Called once per gesture with the release velocity in logical pixels per
  /// second, in scroll-delta sign: [Offset.zero] when the fingers paused
  /// before lifting, or the gesture was cut short.
  final ValueChanged<Offset>? onEnd;
}

/// A pan's velocity over its last 60 milliseconds.
class _RecentPanVelocity {
  static const _window = Duration(milliseconds: 60);

  final _samples = <(Duration, Offset)>[];

  void clear() => _samples.clear();

  void add(Duration time, Offset position) {
    _samples.add((time, position));
    while (_samples.length > 2 && time - _samples[1].$1 > _window) {
      _samples.removeAt(0);
    }
  }

  Offset get velocity {
    if (_samples.length < 2) {
      return Offset.zero;
    }
    final (lastTime, lastPosition) = _samples.last;
    var anchor = _samples.length - 2;
    while (anchor > 0 && lastTime - _samples[anchor - 1].$1 <= _window) {
      anchor--;
    }
    final (time, position) = _samples[anchor];
    final micros = (lastTime - time).inMicroseconds;
    if (micros <= 0) {
      return Offset.zero;
    }
    return (lastPosition - position) *
        (Duration.microsecondsPerSecond / micros);
  }
}

/// Shows a [LinuxWebViewController]'s page, filling the space it is given.
///
/// Tapping the view focuses it; while it has focus, key presses go to the
/// page rather than to Flutter. Wheel and trackpad input go to the page, or
/// through the nearest [LinuxWebViewScrollScope] first.
class LinuxWebView extends StatefulWidget {
  const LinuxWebView({super.key, required this.controller, this.focusNode});

  final LinuxWebViewController controller;
  final FocusNode? focusNode;

  @override
  State<LinuxWebView> createState() => _LinuxWebViewState();
}

class _LinuxWebViewState extends State<LinuxWebView> {
  FocusNode? _ownFocusNode;
  Size? _size;
  Offset _origin = Offset.zero;
  double? _devicePixelRatio;
  bool? _active;

  /// The Flutter buttons the page has been told are down.
  int _buttons = 0;

  /// The host of the two-finger pan in progress, if a scope supplied one.
  LinuxWebViewTrackpad? _pan;
  int? _panPointer;
  bool _panPixels = false;
  Offset _panTotal = Offset.zero;
  Duration? _panLastTime;
  final _panVelocity = _RecentPanVelocity();

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownFocusNode ??= FocusNode(debugLabel: 'LinuxWebView'));

  LinuxWebViewController get _controller => widget.controller;

  @override
  void didUpdateWidget(LinuxWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _size = null;
      _active = null;
      _buttons = 0;
      _endPan(Offset.zero);
      if (_focusNode.hasFocus) {
        oldWidget.controller._focus(false);
        widget.controller._focus(true);
      }
    }
  }

  @override
  void dispose() {
    _endPan(Offset.zero);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _sendGeometry() {
    final size = _size;
    if (!mounted || size == null) {
      return;
    }
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _origin = box.localToGlobal(Offset.zero);
    }
    _controller._geometry(size, _origin);
  }

  void _track(PointerEvent event) {
    final origin = event.position - event.localPosition;
    if (origin != _origin) {
      _origin = origin;
      _sendGeometry();
    }
  }

  void _setButtons(PointerEvent event, int buttons) {
    for (final bit in const [
      kPrimaryButton,
      kSecondaryButton,
      kMiddleMouseButton,
      kBackMouseButton,
      kForwardMouseButton,
    ]) {
      final down = (buttons & bit) != 0;
      if (down == ((_buttons & bit) != 0)) {
        continue;
      }
      // As in GDK, a button's own event carries the state from before it.
      _controller._pointer(
        down ? 'down' : 'up',
        event,
        button: _gdkButton(bit),
        buttons: _gdkButtonState(_buttons),
      );
      _buttons = down ? _buttons | bit : _buttons & ~bit;
    }
  }

  void _onDown(PointerDownEvent event) {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    // The page should be focused before it sees the press, as with a click.
    _controller._focus(true);
    _track(event);
    _setButtons(event, event.buttons);
  }

  void _onMove(PointerMoveEvent event) {
    _track(event);
    _setButtons(event, event.buttons);
    _controller._pointer('move', event, buttons: _gdkButtonState(_buttons));
  }

  void _onHover(PointerHoverEvent event) {
    _track(event);
    _controller._pointer('move', event, buttons: 0);
  }

  void _onUp(PointerEvent event) => _setButtons(event, 0);

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final scope = LinuxWebViewScrollScope.maybeOf(context);
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (!mounted) {
        return;
      }
      final scroll = event as PointerScrollEvent;
      _scroll(
        scroll,
        scope?.transform(scroll) ?? scroll.scrollDelta,
        pixels: scope?.pixelWheel ?? false,
      );
    });
  }

  /// Sends [delta], in [PointerScrollEvent.scrollDelta] units and sign, to
  /// the page as a smooth GDK scroll.
  void _scroll(PointerEvent event, Offset delta, {required bool pixels}) {
    if (!delta.isFinite || delta == Offset.zero) {
      return;
    }
    _controller._pointer(
      'scroll',
      event,
      buttons: _gdkButtonState(_buttons),
      delta: delta / (pixels ? _webKitScrollStep : _scrollStep),
      precise: pixels,
    );
  }

  void _onPanStart(PointerPanZoomStartEvent event) {
    _endPan(Offset.zero);
    final scope = LinuxWebViewScrollScope.maybeOf(context);
    final trackpad = scope?.trackpad;
    if (scope == null || trackpad == null) {
      return;
    }
    _pan = trackpad;
    _panPointer = event.pointer;
    _panPixels = scope.pixelWheel;
    _panTotal = Offset.zero;
    _panLastTime = event.timeStamp;
    _panVelocity
      ..clear()
      ..add(event.timeStamp, Offset.zero);
    trackpad.onStart?.call();
  }

  // Touchpads scroll by panning, which Flutter reports in the opposite sense.
  void _onPanUpdate(PointerPanZoomUpdateEvent event) {
    final trackpad = _pan;
    if (trackpad == null) {
      _scroll(event, -event.localPanDelta, pixels: false);
      return;
    }
    if (event.pointer != _panPointer) {
      return;
    }
    final pan = event.localPanDelta;
    if (!pan.isFinite) {
      _endPan(Offset.zero);
      return;
    }
    _panTotal += pan;
    _panLastTime = event.timeStamp;
    _panVelocity.add(event.timeStamp, _panTotal);
    if (pan == Offset.zero) {
      return;
    }
    final remaining = trackpad.onUpdate(-pan);
    if (mounted && identical(_pan, trackpad)) {
      _scroll(event, remaining, pixels: _panPixels);
    }
  }

  void _onPanEnd(PointerPanZoomEndEvent event) {
    if (_pan == null || event.pointer != _panPointer) {
      return;
    }
    final last = _panLastTime;
    _endPan(
      last != null && event.timeStamp - last <= _flingPause
          ? -_panVelocity.velocity
          : Offset.zero,
    );
  }

  void _endPan(Offset velocity) {
    final trackpad = _pan;
    if (trackpad == null) {
      return;
    }
    _pan = null;
    _panPointer = null;
    _panLastTime = null;
    _panTotal = Offset.zero;
    _panVelocity.clear();
    trackpad.onEnd?.call(velocity.isFinite ? velocity : Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final active = TickerMode.of(context);
    if (active != _active) {
      _active = active;
      _controller._active(active);
    }
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (devicePixelRatio != _devicePixelRatio) {
      _devicePixelRatio = devicePixelRatio;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendGeometry());
    }
    return Focus(
      focusNode: _focusNode,
      onFocusChange: _controller._focus,
      // Only releases reach Flutter while the page has focus; they are the
      // page's.
      onKeyEvent: (_, __) => KeyEventResult.handled,
      child: ValueListenableBuilder<MouseCursor>(
        valueListenable: _controller.cursor,
        builder: (context, cursor, child) => MouseRegion(
          cursor: cursor,
          onEnter: (event) => _controller._pointer('enter', event, buttons: 0),
          onExit: (event) => _controller._pointer('leave', event, buttons: 0),
          child: child,
        ),
        child: Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerHover: _onHover,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          onPointerSignal: _onSignal,
          onPointerPanZoomStart: _onPanStart,
          onPointerPanZoomUpdate: _onPanUpdate,
          onPointerPanZoomEnd: _onPanEnd,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(
                _whole(constraints.maxWidth, 800),
                _whole(constraints.maxHeight, 600),
              );
              if (size != _size) {
                _size = size;
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _sendGeometry());
              }
              // Whole pixels keep the page sharp: the texture is never
              // stretched.
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: Texture(
                    textureId: _controller.textureId,
                    filterQuality: FilterQuality.none,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

double _whole(double extent, double fallback) =>
    extent.isFinite ? extent.floorToDouble().clamp(1.0, 16384.0) : fallback;

int _gdkButton(int flutterButton) => switch (flutterButton) {
      kPrimaryButton => 1,
      kMiddleMouseButton => 2,
      kSecondaryButton => 3,
      kBackMouseButton => 8,
      kForwardMouseButton => 9,
      _ => 1,
    };

int _gdkButtonState(int flutterButtons) =>
    ((flutterButtons & kPrimaryButton) != 0 ? _gdkButton1Mask : 0) |
    ((flutterButtons & kMiddleMouseButton) != 0 ? _gdkButton2Mask : 0) |
    ((flutterButtons & kSecondaryButton) != 0 ? _gdkButton3Mask : 0);

/// The Flutter cursor for a CSS `cursor` keyword.
@visibleForTesting
MouseCursor mouseCursorForCss(String css) => switch (css.trim().toLowerCase()) {
      'pointer' => SystemMouseCursors.click,
      'text' => SystemMouseCursors.text,
      'vertical-text' => SystemMouseCursors.verticalText,
      'wait' => SystemMouseCursors.wait,
      'progress' => SystemMouseCursors.progress,
      'help' => SystemMouseCursors.help,
      'crosshair' => SystemMouseCursors.precise,
      'move' => SystemMouseCursors.move,
      'all-scroll' => SystemMouseCursors.allScroll,
      'grab' => SystemMouseCursors.grab,
      'grabbing' => SystemMouseCursors.grabbing,
      'not-allowed' => SystemMouseCursors.forbidden,
      'no-drop' => SystemMouseCursors.noDrop,
      'copy' => SystemMouseCursors.copy,
      'alias' => SystemMouseCursors.alias,
      'context-menu' => SystemMouseCursors.contextMenu,
      'cell' => SystemMouseCursors.cell,
      'zoom-in' => SystemMouseCursors.zoomIn,
      'zoom-out' => SystemMouseCursors.zoomOut,
      'col-resize' => SystemMouseCursors.resizeColumn,
      'row-resize' => SystemMouseCursors.resizeRow,
      'n-resize' => SystemMouseCursors.resizeUp,
      's-resize' => SystemMouseCursors.resizeDown,
      'e-resize' => SystemMouseCursors.resizeRight,
      'w-resize' => SystemMouseCursors.resizeLeft,
      'ne-resize' => SystemMouseCursors.resizeUpRight,
      'nw-resize' => SystemMouseCursors.resizeUpLeft,
      'se-resize' => SystemMouseCursors.resizeDownRight,
      'sw-resize' => SystemMouseCursors.resizeDownLeft,
      'ew-resize' => SystemMouseCursors.resizeLeftRight,
      'ns-resize' => SystemMouseCursors.resizeUpDown,
      'nesw-resize' => SystemMouseCursors.resizeUpRightDownLeft,
      'nwse-resize' => SystemMouseCursors.resizeUpLeftDownRight,
      'none' => SystemMouseCursors.none,
      _ => SystemMouseCursors.basic,
    };
