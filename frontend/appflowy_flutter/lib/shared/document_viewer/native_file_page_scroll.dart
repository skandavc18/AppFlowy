import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';

import '../scrolling/premium_scroll_behavior.dart';
import 'standalone_file_page.dart';

/// Optional native environment for local file viewers (for example an isolated
/// offline integration fixture). Does not change the renderer or resource host.
class NativeFileWebViewEnvironment extends InheritedWidget {
  const NativeFileWebViewEnvironment({
    super.key,
    required this.environment,
    this.onCreated,
    required super.child,
  });
  final WebViewEnvironment environment;
  final ValueChanged<InAppWebViewController>? onCreated;
  static NativeFileWebViewEnvironment? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NativeFileWebViewEnvironment>();
  @override
  bool updateShouldNotify(NativeFileWebViewEnvironment oldWidget) =>
      environment != oldWidget.environment || onCreated != oldWidget.onCreated;
}

/// Opaque Office editors cannot acknowledge body travel. Only retire the
/// header on DOWNWARD wheel input, passing the exact unused wheel delta once
/// through the native wheel hook. Reverse/pan/pinch/editing stay native.
/// This intentionally makes NO claim of reverse full-page Office handoff.
class NativeFilePageHeaderWheel extends StatelessWidget {
  const NativeFilePageHeaderWheel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final page = StandaloneFilePageScroll.maybeOf(context);
    return WindowsWebViewWheelScope(
      transform: (event) {
        final keys = HardwareKeyboard.instance;
        final delta = event.scrollDelta;
        if (!context.mounted ||
            page == null ||
            keys.isControlPressed ||
            keys.isMetaPressed ||
            keys.isShiftPressed ||
            delta.dy <= 0 ||
            delta.dy <= delta.dx.abs()) {
          return delta;
        }
        final used = StandaloneFilePageScroll.move(page.outer, delta.dy);
        return Offset(delta.dx, delta.dy - used);
      },
      child: child,
    );
  }
}

/// Measured body travel and a separately verified upper boundary. Rounded
/// partial travel while still inside a scroller must not reveal the header.
class NativeFilePageBodyTravel {
  const NativeFilePageBodyTravel(this.actual, {required this.atStart});

  final double actual;
  final bool atStart;
}

/// A failed/expired native operation is NOT an acknowledgement of zero travel.
/// Its result is null and cannot reveal the header. In particular, timing out
/// never releases the actual native slot: only completion of that Future does.
class NativeFilePageScrollDispatcher {
  NativeFilePageScrollDispatcher({
    required this.moveHeader,
    required this.consumeBody,
    required this.isCurrent,
    this.deadline = const Duration(milliseconds: 250),
    this.capacity = 8,
    this.devicePixelRatio = 1,
  });

  final double Function(double) moveHeader;
  final Future<NativeFilePageBodyTravel> Function(double, int) consumeBody;
  final bool Function() isCurrent;
  final Duration deadline;
  final int capacity;
  double devicePixelRatio;
  final _pending = Queue<_VerticalRequest>();
  _VerticalRequest? _running;
  int _epoch = 0;
  bool _disposed = false;

  int get epoch => _epoch;
  bool get inFlight => _running != null;
  int get pendingCount => _pending.length;

  Future<double?> consumeVertical(double delta) {
    if (_disposed ||
        !isCurrent() ||
        !delta.isFinite ||
        delta == 0 ||
        _pending.length >= capacity) {
      return Future.value(null);
    }
    final request = _VerticalRequest(delta, _epoch);
    request.expiry = Timer(deadline, () {
      if (request.epoch == _epoch && !request.result.isCompleted) cancel();
    });
    _pending.add(request);
    _drain();
    return request.result.future;
  }

  void cancel() {
    _epoch++;
    for (final request in _pending) {
      request.finish(null);
    }
    _pending.clear();
    _running?.finish(null);
    // Do not clear _running. A cancelled JS call can still be executing.
  }

  void dispose() {
    _disposed = true;
    cancel();
  }

  bool _valid(_VerticalRequest request) =>
      !_disposed &&
      request.epoch == _epoch &&
      !request.result.isCompleted &&
      isCurrent();

  static double _actual(double requested, double actual,
      {double tolerance = 0.01}) {
    if (!actual.isFinite ||
        actual.abs() > requested.abs() + tolerance ||
        (actual != 0 && actual.sign != requested.sign)) {
      throw StateError('Invalid native scroll acknowledgement');
    }
    return actual;
  }

  void _drain() {
    if (_running != null || _pending.isEmpty || _disposed) return;
    final request = _pending.removeFirst();
    _running = request; // reserve BEFORE calling user code
    unawaited(_run(request));
  }

  Future<void> _run(_VerticalRequest request) async {
    try {
      if (!_valid(request)) return;
      var header = 0.0;
      if (request.delta > 0) {
        header = _actual(request.delta, moveHeader(request.delta));
      }
      if (!_valid(request)) return;
      final remaining = request.delta - header;
      // CSS scrollTop may quantize to a device pixel. Convert that allowance
      // to Flutter logical pixels, not CSS pixels or native wheel units.
      final tolerance = devicePixelRatio.isFinite && devicePixelRatio > 0
          ? 1 / devicePixelRatio + 1e-9
          : 0.01;
      final travel = remaining == 0
          ? const NativeFilePageBodyTravel(0, atStart: false)
          : await consumeBody(remaining, request.epoch);
      final body = _actual(
        remaining,
        travel.actual,
        tolerance: tolerance,
      );
      if (!_valid(request)) return;
      if (request.delta < 0 && travel.atStart) {
        // An over-rounded body move is credit for the next input, never a
        // positive header correction during a reverse gesture.
        final rest =
            (remaining - body).clamp(double.negativeInfinity, 0.0).toDouble();
        header = _actual(rest, moveHeader(rest));
      }
      request.finish(header + body);
    } catch (_) {
      // Unknown travel is not a boundary. Discard all queued work as well.
      if (_valid(request)) cancel();
    } finally {
      request.finish(null);
      _running = null;
      _drain();
    }
  }
}

class _VerticalRequest {
  _VerticalRequest(this.delta, this.epoch);
  final double delta;
  final int epoch;
  final result = Completer<double?>();
  Timer? expiry;
  void finish(double? actual) {
    expiry?.cancel();
    if (!result.isCompleted) result.complete(actual);
  }
}

/// File-only bridge. Never install this in a remote/bookmark browser or an
/// opaque Office frame. Auth/history/selection stay in the same native view.
class NativeFilePageScrollBridge {
  static const handler = 'appflowyFilePageScroll';
  static const runtime = '__appflowyFilePageScroll';
  InAppWebViewController? _controller;
  ContentWorld _world = ContentWorld.PAGE;
  StandaloneFilePageScroll? _page;
  bool Function()? _eligible;
  NativeFilePageScrollDispatcher? _dispatcher;
  String? _document;
  int _revision = 0;
  int _gesture = -1;
  bool _disposed = false;
  double _devicePixelRatio = 1;
  bool _kinetic = true;
  PremiumScrollPhysicsConfig _config = const PremiumScrollPhysicsConfig();

  bool _cancelInFlight = false;
  (InAppWebViewController, ContentWorld, String, int)? _queuedCancel;

  void bind(StandaloneFilePageScroll? page, bool Function() eligible,
      {double devicePixelRatio = 1}) {
    if (_page?.outer != page?.outer) cancel();
    _page = page;
    _eligible = eligible;
    _devicePixelRatio = devicePixelRatio;
    _dispatcher?.devicePixelRatio = devicePixelRatio;
  }

  void attach(InAppWebViewController controller, {ContentWorld? world}) {
    invalidate();
    _controller = controller;
    _world = world ?? ContentWorld.PAGE;
    controller.addJavaScriptHandler(handlerName: handler, callback: _handle);
  }

  void invalidate() {
    _revision++;
    _document = null;
    _gesture = -1;
    _dispatcher?.cancel();
  }

  void cancel() {
    _dispatcher?.cancel();
    final controller = _controller;
    final document = _document;
    if (controller != null && document != null) {
      // One control call plus one coalesced cancellation, never an unbounded
      // queue. Control settlement does not release the consumption slot.
      _queuedCancel = (controller, _world, document, _gesture);
      if (!_cancelInFlight) unawaited(_flushCancellation());
    }
  }

  Future<void> _flushCancellation() async {
    _cancelInFlight = true;
    try {
      while (_queuedCancel != null) {
        final request = _queuedCancel!;
        _queuedCancel = null;
        try {
          await request.$1.evaluateJavascript(
            source: 'globalThis.$runtime?.cancel('
                '${jsonEncode(request.$3)},${request.$4});',
            contentWorld: request.$2,
          );
        } catch (_) {
          // A disposed/navigated renderer cannot acknowledge a stop.
        }
      }
    } finally {
      _cancelInFlight = false;
    }
  }

  void configure(
      {required bool kinetic, required PremiumScrollPhysicsConfig config}) {
    if (_kinetic == kinetic && _config == config) return;
    _kinetic = kinetic;
    _config = config;
    // Only the host runtime is replaced, never the native view/document.
    if (_document != null) unawaited(install());
  }

  Future<bool> install({bool? kinetic}) async {
    final controller = _controller;
    if (controller == null || _disposed) return false;
    if (kinetic != null) _kinetic = kinetic;
    _dispatcher?.cancel();
    _gesture = -1;
    final revision = ++_revision;
    final document = 'file-$revision-${DateTime.now().microsecondsSinceEpoch}';
    _document = document;
    _dispatcher ??= NativeFilePageScrollDispatcher(
      devicePixelRatio: _devicePixelRatio,
      moveHeader: (delta) => _page == null
          ? 0
          : StandaloneFilePageScroll.move(_page!.outer, delta),
      consumeBody: _consumeBody,
      isCurrent: () =>
          !_disposed && _document != null && (_eligible?.call() ?? false),
    );
    try {
      final result = await controller.evaluateJavascript(
        source: buildNativeFilePageScrollScript(document,
            kinetic: _kinetic,
            devicePixelRatio: _devicePixelRatio,
            revision: revision,
            config: _config),
        contentWorld: _world,
      );
      return revision == _revision && result == true;
    } catch (_) {
      if (revision == _revision) invalidate();
      return false;
    }
  }

  Future<dynamic> _handle(List<dynamic> args) async {
    if (_disposed ||
        args.length != 4 ||
        args[0] != _document ||
        args[1] is! num ||
        args[2] is! num ||
        args[3] is! String ||
        !(_eligible?.call() ?? false)) return null;
    final gestureValue = args[1] as num;
    if (!gestureValue.isFinite ||
        gestureValue < 0 ||
        gestureValue.toInt() != gestureValue ||
        !const {'input', 'cancel'}.contains(args[3])) return null;
    final gesture = gestureValue.toInt();
    if (gesture < _gesture) return null;
    if (gesture != _gesture) {
      _dispatcher?.cancel();
      _gesture = gesture;
      final outer = _page?.outer;
      if (outer?.positions.length == 1 && outer!.position.hasPixels) {
        outer.jumpTo(outer.offset);
      }
    }
    if (args[3] == 'cancel') {
      _dispatcher?.cancel();
      return null;
    }
    final document = _document;
    final actual =
        await _dispatcher?.consumeVertical((args[2] as num).toDouble());
    if (document != _document || gesture != _gesture || actual == null)
      return null;
    final outer = _page?.outer;
    final hidden = outer == null ||
        (outer.positions.length == 1 &&
            outer.position.hasContentDimensions &&
            outer.offset >= outer.position.maxScrollExtent);
    return {'actual': actual, 'headerHidden': hidden};
  }

  Future<NativeFilePageBodyTravel> _consumeBody(double delta, int epoch) async {
    final controller = _controller;
    final document = _document;
    final gesture = _gesture;
    if (controller == null || document == null || epoch != _dispatcher?.epoch) {
      throw StateError('Retired file scroll');
    }
    final expiry = DateTime.now()
        .add(const Duration(milliseconds: 250))
        .millisecondsSinceEpoch;
    final result = await controller.evaluateJavascript(
      source: 'globalThis.$runtime?.consumeVertical('
          '${jsonEncode(document)},$gesture,$delta,$expiry);',
      contentWorld: _world,
    );
    if (document != _document ||
        gesture != _gesture ||
        epoch != _dispatcher?.epoch ||
        result is! Map ||
        result['actual'] is! num ||
        result['atStart'] is! bool) {
      throw StateError('Missing or obsolete native scroll acknowledgement');
    }
    return NativeFilePageBodyTravel(
      (result['actual'] as num).toDouble(),
      atStart: result['atStart'] as bool,
    );
  }

  void dispose() {
    cancel();
    _disposed = true;
    _dispatcher?.dispose();
    _controller?.removeJavaScriptHandler(handlerName: handler);
    _controller = null;
    _eligible = null;
    _page = null;
  }
}

/// Input stays with WebView2. This marker only verifies that a late DOM reply
/// still belongs to an active, hit-testable file, including embed gates/tabs.
class NativeFilePageScroll extends StatefulWidget {
  const NativeFilePageScroll(
      {super.key, required this.bridge, required this.child});
  final NativeFilePageScrollBridge bridge;
  final Widget child;
  @override
  State<NativeFilePageScroll> createState() => _NativeFilePageScrollState();
}

class _NativeFilePageScrollState extends State<NativeFilePageScroll> {
  final _hitKey = GlobalKey();
  PointerEvent? _lastInput;
  bool _active = true;
  bool _inputEnabled = true;
  StandaloneFilePageScroll? _page;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_newInput);
  }

  void _newInput(PointerEvent event) {
    if (_lastInput == null || !mounted || !_active) return;
    if ((event is PointerDownEvent ||
            event is PointerPanZoomStartEvent ||
            event is PointerScrollEvent) &&
        !_hits(event)) {
      _lastInput = null;
      widget.bridge.cancel();
    }
  }

  bool _hits(PointerEvent event) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    final target = _hitKey.currentContext?.findRenderObject();
    return hit.path.any((entry) => identical(entry.target, target));
  }

  bool _eligible() {
    if (!mounted ||
        !_active ||
        !_inputEnabled ||
        !TickerMode.of(context) ||
        ModalRoute.of(context)?.isCurrent == false) return false;
    final event = _lastInput;
    if (event == null) return false;
    // Do not unwrap ScrollGestureGate's filtered targets.
    return _hits(event);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page = StandaloneFilePageScroll.maybeOf(context);
    _inputEnabled = ScrollConfiguration.of(context)
        .getScrollPhysics(context)
        .allowUserScrolling;
    widget.bridge.bind(_page, _eligible,
        devicePixelRatio: View.of(context).devicePixelRatio);
    if (!TickerMode.of(context) || !_inputEnabled) widget.bridge.cancel();
  }

  @override
  void deactivate() {
    _active = false;
    widget.bridge.cancel();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_newInput);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PremiumScrollExclusion(
        child: Listener(
          key: _hitKey,
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            _lastInput = event;
            if (event is PointerScrollInertiaCancelEvent)
              widget.bridge.cancel();
            if (event is PointerScrollEvent) {
              // WebView's native listener has already received this original event.
              // Prevent an ancestor Flutter Scrollable from consuming it as well.
              GestureBinding.instance.pointerSignalResolver
                  .register(event, (_) {});
            }
          },
          onPointerPanZoomStart: (event) {
            _lastInput = event;
            widget.bridge.cancel();
          },
          onPointerPanZoomUpdate: (event) => _lastInput = event,
          onPointerDown: (event) {
            _lastInput = event;
            widget.bridge.cancel();
          },
          onPointerCancel: (_) => widget.bridge.cancel(),
          child: LayoutBuilder(builder: (context, constraints) {
            final outer = _page?.outer;
            final position =
                outer?.positions.length == 1 ? outer!.position : null;
            final height = position?.hasViewportDimension == true
                ? position!.viewportDimension
                : constraints.maxHeight;
            // Constant finite texture geometry while the header clips/unclips it.
            // Native WebView cancels a touch stream if its composition size changes.
            return ClipRect(
                child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: height.isFinite ? height : null,
              maxHeight: height.isFinite ? height : null,
              child: widget.child,
            ));
          }),
        ),
      );
}

/// Trusted host runtime for already sanitized local HTML/Markdown/mail only.
/// The native WebView remains the sole recognizer. Site-owned/horizontal/pinch
/// gestures never enter this runtime. No document-wide query occurs per frame.
String buildNativeFilePageScrollScript(
  String document, {
  bool kinetic = true,
  double devicePixelRatio = 1,
  int revision = 0,
  PremiumScrollPhysicsConfig config = const PremiumScrollPhysicsConfig(),
}) =>
    '''
(() => {
  if (typeof globalThis.flutter_inappwebview?.callHandler !== 'function') return false;
  const key = '${NativeFilePageScrollBridge.runtime}';
  const revision = $revision;
  if ((globalThis[key]?.snapshot().revision ?? -1) > revision) return false;
  globalThis[key]?.dispose();
  globalThis.$premiumKineticJavaScriptObjectName?.stop();
  const documentId = ${jsonEncode(document)};
  const root = document.documentElement;
  const roundingLimit = 1 / $devicePixelRatio + 1e-9;
  let gesture = 0, target = null, pending = 0, busy = false;
  let chain = [], gestureScale = 1, residual = 0;
  let frame = 0, velocity = 0, lastFrame = 0, release = false;
  let touch = null, wheelTimer = 0, direction = 0, headerHidden = false;
  let wheelX = 0, wheelY = 0;
  const alive = () => root === document.documentElement && root.isConnected;
  const notify = (delta, action = 'input') =>
    globalThis.flutter_inappwebview.callHandler(
      '${NativeFilePageScrollBridge.handler}', documentId, gesture, delta, action);
  const halt = () => {
    if (frame) cancelAnimationFrame(frame);
    frame = 0; lastFrame = 0; velocity = 0; release = false;
  };
  const cancel = () => {
    halt(); pending = 0; residual = 0;
    touch = null; target = null; chain = []; direction = 0;
    clearTimeout(wheelTimer); wheelTimer = 0; gesture++;
    // Cancellation has its own generation, so an old ACK cannot start coast.
    Promise.resolve(notify(0, 'cancel')).catch(() => {});
  };
  const pick = (x, y) => {
    gestureScale = window.devicePixelRatio / $devicePixelRatio;
    if (!Number.isFinite(gestureScale) || gestureScale <= 0) return null;
    let node = document.elementFromPoint(x, y);
    const chosen = [];
    for (let depth = 0; node && depth < 64; depth++, node = node.parentElement) {
      const style = getComputedStyle(node);
      if (node.matches('input,textarea,select,canvas,iframe,video,audio') ||
          node.isContentEditable || style.touchAction === 'none' ||
          style.touchAction === 'pan-x' ||
          ['contain','none'].includes(style.overscrollBehaviorY) ||
          (node.scrollWidth > node.clientWidth + 1 &&
           ['auto','scroll'].includes(style.overflowX))) return null;
      if (node.scrollHeight > node.clientHeight + 1 &&
          ['auto','scroll'].includes(style.overflowY)) chosen.push(node);
    }
    if (node || !document.scrollingElement) return null;
    if (!chosen.includes(document.scrollingElement)) chosen.push(document.scrollingElement);
    chain = chosen;
    return chosen[0];
  };
  const canMove = delta => chain.some(node => delta < 0
    ? node.scrollTop > 0 : node.scrollTop < node.scrollHeight - node.clientHeight);
  const move = delta => {
    if (!alive() || !target || chain.some(node => !node.isConnected)) return null;
    let actual = 0;
    // Explicit instant behavior overrides authored smooth scrolling. Read the
    // very same element AFTER mutation; never infer travel from a root cache.
    for (const node of chain) {
      const rest = delta - actual;
      if (!rest || Math.sign(rest) !== Math.sign(delta)) break;
      const before = node.scrollTop;
      node.scrollBy({top: rest, left: 0, behavior: 'instant'});
      actual += node.scrollTop - before;
      // Only a real boundary may pass motion to the next pane. Rounding
      // inside this pane is neither a boundary nor reverse ancestor travel.
      if (delta < 0 ? node.scrollTop > 0
          : node.scrollTop < node.scrollHeight - node.clientHeight) break;
    }
    return actual;
  };
  const tick = time => {
    frame = 0;
    if (!alive() || busy || !target) { halt(); return; }
    if (!lastFrame) { lastFrame = time; frame = requestAnimationFrame(tick); return; }
    const dt = Math.min((time - lastFrame) / 1000, 1 / 30);
    lastFrame = time;
    const decay = Math.exp(-${config.friction} * dt);
    const delta = velocity / ${config.friction} * (1 - decay) + residual / gestureScale;
    residual = 0;
    // A preceding rounded-up movement can exceed this very small frame.
    const actual = Math.sign(delta) === Math.sign(velocity) ? move(delta) : 0;
    velocity *= decay;
    if (actual === null) { halt(); return; }
    const rest = delta - actual;
    if (rest && Math.sign(rest) === Math.sign(velocity) && !canMove(delta)) {
      // ONE boundary transfer; there is no Dart/JS animation-frame loop.
      // Reverify actual body consumption through consumeVertical before the
      // header is allowed to move. Stop this owner before handing off.
      halt(); enqueue(rest); return;
    }
    // Retain only quantization, never a backlog for a non-moving interior.
    if (Math.abs(rest * gestureScale) > roundingLimit) { halt(); return; }
    residual = rest * gestureScale;
    if (Math.abs(velocity) < ${config.stopVelocity}) { halt(); return; }
    frame = requestAnimationFrame(tick);
  };
  const coast = () => {
    if (${kinetic ? 'true' : 'false'} && (headerHidden || velocity < 0) &&
      release && !busy && !pending &&
        Math.abs(velocity) >= ${config.minimumVelocity} && target) {
      release = false; frame = requestAnimationFrame(tick);
    }
  };
  const flush = async () => {
    if (busy || !pending || !alive()) return;
    const generation = gesture, input = pending, delta = input + residual;
    pending = 0; residual = 0;
    if (!delta || Math.sign(delta) !== Math.sign(input)) {
      // Do not turn credit from a rounded-up move into backwards movement.
      residual = delta; coast(); return;
    }
    busy = true;
    try {
      const reply = await notify(delta);
      if (generation !== gesture) return;
      if (!reply || typeof reply.actual !== 'number' || !Number.isFinite(reply.actual)) {
        cancel(); return;
      }
      headerHidden = reply.headerHidden === true;
      const rest = delta - reply.actual;
      // Retain unrenderable fractions (or credit from rounded-up travel),
      // without immediately requeueing a zero-movement round trip. At a hard
      // page boundary, unused input is exhausted instead of replayed later.
      const retain = rest * delta < 0 || canMove(delta / gestureScale);
      if (retain && Math.abs(rest) > roundingLimit) { cancel(); return; }
      residual = retain ? rest : 0;
    } catch (_) { if (generation === gesture) cancel(); }
    finally {
      // True settlement, not a JS timeout, releases this transport slot.
      busy = false;
      if (pending) flush(); else coast();
    }
  };
  const enqueue = delta => {
    if (!Number.isFinite(delta) || !delta) return;
    // pending is logical pixels; wheel units and CSS scale are applied ONCE.
    pending = Math.max(-1600, Math.min(1600, pending + delta * gestureScale));
    flush();
  };
  const wheel = event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey ||
        Math.abs(event.deltaY) <= Math.abs(event.deltaX)) { cancel(); return; }
    if (!wheelTimer || direction !== Math.sign(event.deltaY) ||
        !target?.isConnected || chain.some(node => !node.isConnected) ||
        Math.hypot(event.clientX - wheelX, event.clientY - wheelY) > 8) {
      cancel(); target = pick(event.clientX, event.clientY);
      wheelX = event.clientX; wheelY = event.clientY;
    }
    if (!target || !event.cancelable) return;
    event.preventDefault();
    direction = Math.sign(event.deltaY);
    clearTimeout(wheelTimer);
    wheelTimer = setTimeout(() => { wheelTimer = 0; }, 160);
    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? innerHeight : 1;
    enqueue(event.deltaY * unit);
  };
  const start = event => {
    cancel();
    if (event.touches.length !== 1) return;
    const point = event.touches[0];
    target = pick(point.clientX, point.clientY);
    if (target) touch = {x: point.clientX, y: point.clientY,
      startX: point.clientX, startY: point.clientY, at: event.timeStamp, vertical: false};
  };
  const update = event => {
    if (!touch) return;
    if (event.touches.length !== 1) { cancel(); return; }
    const point = event.touches[0];
    if (!touch.vertical) {
      const dx = point.clientX - touch.startX, dy = point.clientY - touch.startY;
      if (Math.abs(dx) >= Math.abs(dy) && Math.abs(dx) > 1) { cancel(); return; }
      if (Math.abs(dy) <= 1) return;
      touch.vertical = true;
    }
    if (!event.cancelable) { cancel(); return; }
    event.preventDefault();
    const delta = touch.y - point.clientY;
    velocity = Math.max(-${config.maxVelocity}, Math.min(${config.maxVelocity},
      delta * 1000 / Math.max(1, event.timeStamp - touch.at)));
    touch.x = point.clientX; touch.y = point.clientY; touch.at = event.timeStamp;
    enqueue(delta);
  };
  const end = event => {
    if (touch?.vertical && event.timeStamp - touch.at < 100) release = true;
    touch = null; coast();
  };
  const options = {capture: true, passive: false};
  document.addEventListener('wheel', wheel, options);
  document.addEventListener('touchstart', start, options);
  document.addEventListener('touchmove', update, options);
  document.addEventListener('touchend', end, options);
  document.addEventListener('touchcancel', cancel, options);
  globalThis[key] = {
    snapshot() { return {documentId, revision, gesture, busy, pending, active: frame !== 0}; },
    consumeVertical(id, generation, delta, expiry) {
      if (id !== documentId || generation !== gesture || Date.now() > expiry ||
          !Number.isFinite(delta)) return null;
      const cssDelta = delta / gestureScale;
      const actual = move(cssDelta);
      return actual === null ? null : {
        actual: actual * gestureScale, atStart: !canMove(-1)
      };
    },
    cancel(id, generation) {
      if (id === documentId && generation === gesture) cancel();
    },
    dispose() {
      cancel();
      document.removeEventListener('wheel', wheel, options);
      document.removeEventListener('touchstart', start, options);
      document.removeEventListener('touchmove', update, options);
      document.removeEventListener('touchend', end, options);
      document.removeEventListener('touchcancel', cancel, options);
      delete globalThis[key];
    }
  };
  return true;
})();
''';
