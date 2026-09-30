import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';

/// JavaScript handler the editor page relays scroll state through.
const officeScrollHandlerName = 'appflowyOfficeScroll';
const _commandFunction = '__appflowyOfficeScrollCommand';

/// Whether ONLYOFFICE scrolling is driven by [OfficeEditorScroll]. Only the
/// Windows WebView can deliver wheel input at an exact pixel scale.
bool get officeEditorScrollSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Physics shared with the rest of the app, and whether to animate at all.
({PremiumScrollPhysicsConfig config, bool smooth}) officeScrollPhysics(
  BuildContext context,
) {
  final behavior = ScrollConfiguration.of(context);
  return (
    config: behavior is PremiumScrollBehavior
        ? behavior.config
        : const PremiumScrollPhysicsConfig(),
    smooth: !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        (behavior is! PremiumScrollBehavior || behavior.kineticEnabled),
  );
}

/// Bootstrap-page relay between the editor frame and Flutter. Only messages
/// from [documentServerOrigin] are forwarded, and only their scroll fields.
String buildOfficeScrollRelayScript(String documentServerOrigin) {
  final origin = Uri.parse(documentServerOrigin).origin;
  return '''
(function () {
  var serverOrigin = ${jsonEncode(origin)};
  var editorWindow = null;
  window.addEventListener('message', function (event) {
    var data = event.data;
    if (event.origin !== serverOrigin || !data || data.appflowyOfficeScroll !== 1) return;
    editorWindow = event.source;
    var bridge = window.flutter_inappwebview;
    if (!bridge || typeof bridge.callHandler !== 'function') return;
    if (data.t === 'state' && typeof data.atTop === 'boolean') {
      bridge.callHandler('$officeScrollHandlerName', { t: 'state', atTop: data.atTop });
    } else if (data.t === 'over' && typeof data.dy === 'number' && isFinite(data.dy)) {
      bridge.callHandler('$officeScrollHandlerName', { t: 'over', dy: data.dy });
    }
  });
  window.$_commandFunction = function (command) {
    if (editorWindow && command && typeof command === 'object') {
      editorWindow.postMessage({ appflowyOfficeScroll: 1, command: command }, serverOrigin);
    }
  };
})();
''';
}

/// Smooth, pixel-exact scrolling inside the ONLYOFFICE editor frame.
///
/// Wheel input over the document reaches the frame at 1.2 wheel units per
/// logical pixel (see [WindowsWebViewWheelScope.pixelWheel]). Instead of
/// ONLYOFFICE's fixed 45px notch jumps, the frame eases each notch with the
/// app's exact-distance wheel curve and applies trackpad pans one-to-one,
/// through the editor's own scroll bars so they track every frame. Menus,
/// lists and panels keep their native wheel handling. The frame reports when
/// the document reaches its top so the page header can be scrolled back.
@visibleForTesting
String buildOfficeScrollRuntimeScript({
  required String documentServerOrigin,
  required String hostOrigin,
  required PremiumScrollPhysicsConfig config,
  required bool smooth,
}) =>
    '''
(() => {
  const ORIGIN = ${jsonEncode(Uri.parse(documentServerOrigin).origin)};
  const HOST = ${jsonEncode(Uri.parse(hostOrigin).origin)};
  if (window.location.origin !== ORIGIN || window.parent === window) return;
  const path = window.location.pathname;
  const kind = /\\/apps\\/documenteditor\\/main\\//.test(path) ? 'word'
    : /\\/apps\\/spreadsheeteditor\\/main\\//.test(path) ? 'cell'
    : /\\/apps\\/presentationeditor\\/main\\//.test(path) ? 'slide'
    : '';
  if (!kind || window.__appflowyOfficeScrollInstalled) return;
  window.__appflowyOfficeScrollInstalled = true;

  const UNITS_PER_PIXEL = 1.2;
  const SMOOTH = $smooth;
  const C = Object.freeze({
    rate: ${config.wheelSmoothingRate},
    speed: ${config.maxWheelScrollVelocity},
    queue: ${config.maxWheelQueuedDistance},
    notch: ${config.maxWheelDelta},
    stop: ${config.wheelStopDistance},
    precision: ${config.precisionDeltaThreshold},
    friction: ${config.desktopCoastFriction},
    maxVelocity: ${config.maxVelocity},
    minVelocity: ${config.minimumVelocity},
    stopVelocity: ${config.stopVelocity},
    frame: 1 / 30,
    // Milliseconds a release command waits for its gesture's last input.
    grace: 120,
  });
  const state = {
    qx: 0, qy: 0, vx: 0, vy: 0, rx: 0, ry: 0,
    fling: false, flingAt: 0, frame: 0, last: 0, precise: 0, atTop: null, bound: null,
  };
  const clamp = (value, limit) => Math.max(-limit, Math.min(limit, value));
  const finite = (value) => (Number.isFinite(value) ? value : 0);
  const post = (message) => {
    try {
      window.parent.postMessage(Object.assign({ appflowyOfficeScroll: 1 }, message), HOST);
    } catch (_) {}
  };
  const edges = (vertical, horizontal) => {
    const y = finite(vertical.scrollVCurrentY);
    const maxY = Number(vertical.maxScrollY2 !== undefined ? vertical.maxScrollY2 : vertical.maxScrollY);
    const x = horizontal ? finite(horizontal.scrollHCurrentX) : 0;
    const maxX = horizontal
      ? Number(horizontal.maxScrollX2 !== undefined ? horizontal.maxScrollX2 : horizontal.maxScrollX)
      : 0;
    return {
      top: !(y > 0.5),
      bottom: Number.isFinite(maxY) && y >= maxY - 0.5,
      left: !(x > 0.5),
      right: !horizontal || (Number.isFinite(maxX) && x >= maxX - 0.5),
    };
  };

  // Word and slides: ScrollObject positions are CSS pixels.
  const wordAdapter = () => {
    const api = window.editor;
    const control = api && api.WordControl;
    const vertical = control && control.m_oScrollVerApi;
    if (!vertical || typeof vertical.scrollByY !== 'function') return null;
    const horizontal = control.m_oScrollHorApi && control.m_bIsHorScrollVisible &&
      typeof control.m_oScrollHorApi.scrollByX === 'function'
      ? control.m_oScrollHorApi
      : null;
    return {
      vertical,
      root(target) {
        if (kind === 'slide' &&
            target.closest('#id_panel_notes, #id_panel_animation, #id_thumbnails')) {
          return null;
        }
        return target.closest('#id_main, #id_vertical_scroll, #id_horscrollpanel, #id_horizontal_scroll');
      },
      edges: () => edges(vertical, horizontal),
      scroll(dx, dy) {
        let x = 0;
        let y = 0;
        if (dy) {
          const before = vertical.scrollVCurrentY;
          // The editor's own wheel handler allows slide changes this way.
          if (kind === 'slide') control.m_nVerticalSlideChangeOnScrollEnabled = true;
          try {
            vertical.scrollByY(dy, undefined, { userScroll: true });
          } finally {
            if (kind === 'slide') control.m_nVerticalSlideChangeOnScrollEnabled = false;
          }
          y = finite(vertical.scrollVCurrentY - before);
        }
        if (dx && horizontal) {
          const before = horizontal.scrollHCurrentX;
          horizontal.scrollByX(dx, undefined, { userScroll: true });
          x = finite(horizontal.scrollHCurrentX - before);
        }
        return { x, y };
      },
    };
  };

  // Spreadsheets: scroll bar units convert through the sheet's step size.
  const cellAdapter = () => {
    const api = window.Asc && window.Asc.editor;
    const book = api && api.wb;
    const controller = book && book.controller;
    const vertical = controller && controller.vsbApi;
    const horizontal = controller && controller.hsbApi;
    if (!vertical || !horizontal || typeof book.getWorksheet !== 'function') return null;
    const sheet = book.getWorksheet();
    const settings = controller.settings;
    if (!sheet || !settings || typeof sheet.getVScrollStep !== 'function') return null;
    const browser = window.AscCommon && window.AscCommon.AscBrowser;
    const retina = (browser && browser.retinaPixelRatio) || window.devicePixelRatio || 1;
    const ky = retina * settings.vscrollStep / sheet.getVScrollStep();
    const kx = retina * settings.hscrollStep / sheet.getHScrollStep();
    if (!(ky > 0) || !(kx > 0) || !Number.isFinite(ky) || !Number.isFinite(kx)) return null;
    return {
      vertical,
      root(target) {
        if (controller.isFillHandleMode || controller.isMoveRangeMode ||
            controller.isMoveResizeRange || controller.isChangeVisibleAreaMode) {
          return null;
        }
        return target.closest('#ws-canvas-outer, #ws-v-scrollbar, #ws-h-scrollbar');
      },
      edges: () => edges(vertical, horizontal),
      scroll(dx, dy) {
        let x = 0;
        let y = 0;
        if (dy) {
          const before = vertical.scrollVCurrentY;
          vertical.scrollByY(dy * ky);
          y = finite((vertical.scrollVCurrentY - before) / ky);
        }
        if (dx) {
          const before = horizontal.scrollHCurrentX;
          horizontal.scrollByX(dx * kx);
          x = finite((horizontal.scrollHCurrentX - before) / kx);
        }
        return { x, y };
      },
    };
  };

  const adapter = () => {
    try {
      return kind === 'cell' ? cellAdapter() : wordAdapter();
    } catch (_) {
      return null;
    }
  };

  const report = () => {
    const current = adapter();
    if (!current) return;
    if (state.bound !== current.vertical) {
      state.bound = current.vertical;
      if (typeof current.vertical.bind === 'function') {
        try { current.vertical.bind('scrollvertical', schedule); } catch (_) {}
      }
    }
    const top = current.edges().top;
    if (top !== state.atTop) {
      state.atTop = top;
      post({ t: 'state', atTop: top });
    }
  };
  let scheduled = false;
  const schedule = () => {
    if (scheduled) return;
    scheduled = true;
    Promise.resolve().then(() => {
      scheduled = false;
      report();
    });
  };

  // Moves the document, carrying sub-pixel requests the editor rounds away.
  const apply = (current, dx, dy) => {
    if (dx && Math.sign(dx) !== Math.sign(state.rx)) state.rx = 0;
    if (dy && Math.sign(dy) !== Math.sign(state.ry)) state.ry = 0;
    const wantX = dx ? dx + state.rx : 0;
    const wantY = dy ? dy + state.ry : 0;
    let moved = { x: 0, y: 0 };
    try {
      moved = current.scroll(wantX, wantY);
    } catch (_) {}
    const edge = current.edges();
    const blockedX = (wantX < 0 && edge.left) || (wantX > 0 && edge.right);
    const blockedY = (wantY < 0 && edge.top) || (wantY > 0 && edge.bottom);
    // Slides can overshoot a request by paging; that is never a remainder.
    const restX = Math.sign(wantX - moved.x) === Math.sign(wantX) ? wantX - moved.x : 0;
    const restY = Math.sign(wantY - moved.y) === Math.sign(wantY) ? wantY - moved.y : 0;
    if (dx) state.rx = blockedX ? 0 : clamp(restX, 4);
    if (dy) state.ry = blockedY ? 0 : clamp(restY, 4);
    schedule();
    return { blockedX, blockedY, restY: blockedY ? restY : 0 };
  };

  const stopMotion = () => {
    if (state.frame) cancelAnimationFrame(state.frame);
    state.frame = 0;
    state.last = 0;
    state.qx = state.qy = state.vx = state.vy = 0;
    state.fling = false;
  };
  const overscroll = (dy) => {
    if (dy < -0.5) post({ t: 'over', dy });
  };

  const halt = () => {
    stopMotion();
    state.rx = state.ry = 0;
  };

  const frameStep = (remaining, seconds) => {
    if (!remaining || seconds <= 0) return 0;
    const step = remaining * (1 - Math.exp(-C.rate * seconds));
    return clamp(step, C.speed * seconds);
  };

  const tick = (time) => {
    state.frame = 0;
    const current = adapter();
    if (!current) {
      halt();
      return;
    }
    if (!state.last) {
      state.last = time;
      state.frame = requestAnimationFrame(tick);
      return;
    }
    const seconds = Math.min(Math.max((time - state.last) / 1000, 0), C.frame);
    state.last = time;
    if (state.fling) {
      const decay = Math.exp(-C.friction * seconds);
      const stepX = state.vx / C.friction * (1 - decay);
      const stepY = state.vy / C.friction * (1 - decay);
      state.vx *= decay;
      state.vy *= decay;
      const result = apply(current, stepX, stepY);
      if (result.blockedX) state.vx = 0;
      if (result.blockedY) {
        if (stepY < 0) overscroll(result.restY + state.vy / C.friction);
        state.vy = 0;
      }
      if (Math.hypot(state.vx, state.vy) < C.stopVelocity) {
        halt();
        return;
      }
    } else {
      const stepX = frameStep(state.qx, seconds);
      const stepY = frameStep(state.qy, seconds);
      state.qx -= stepX;
      state.qy -= stepY;
      const result = apply(current, stepX, stepY);
      if (result.blockedX) state.qx = 0;
      if (result.blockedY) {
        if (stepY < 0) overscroll(result.restY + state.qy);
        state.qy = 0;
      }
      if (Math.abs(state.qx) < C.stop && Math.abs(state.qy) < C.stop) {
        halt();
        return;
      }
    }
    state.frame = requestAnimationFrame(tick);
  };

  const start = () => {
    if (!state.frame) {
      state.last = 0;
      state.frame = requestAnimationFrame(tick);
    }
  };

  const queue = (dx, dy) => {
    if (state.fling) stopMotion();
    if (dx) state.qx = clamp(Math.sign(dx) === Math.sign(state.qx) ? state.qx + dx : dx, C.queue);
    if (dy) state.qy = clamp(Math.sign(dy) === Math.sign(state.qy) ? state.qy + dy : dy, C.queue);
    start();
  };

  const scrollsNatively = (target, root) => {
    for (let element = target; element && element !== root; element = element.parentElement) {
      if (element.classList && element.classList.contains('ps-container')) return true;
      if (element.scrollHeight - element.clientHeight > 1 ||
          element.scrollWidth - element.clientWidth > 1) {
        const style = getComputedStyle(element);
        if (/(auto|scroll)/.test(style.overflowY + ' ' + style.overflowX)) return true;
      }
    }
    return false;
  };

  window.addEventListener('wheel', (event) => {
    if (!event.isTrusted || event.defaultPrevented || event.ctrlKey || event.metaKey ||
        event.altKey || event.buttons) {
      return;
    }
    const target = event.target;
    const current = target && target.closest ? adapter() : null;
    const root = current && current.root(target);
    if (!root || scrollsNatively(target, root)) return;
    let dx = -finite(event.wheelDeltaX) / UNITS_PER_PIXEL;
    let dy = -finite(event.wheelDeltaY) / UNITS_PER_PIXEL;
    if (event.shiftKey && Math.abs(dx) < Math.abs(dy)) {
      dx = dy;
      dy = 0;
    }
    if (!dx && !dy) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const now = performance.now();
    // Input and commands travel separately, so a release can overtake the
    // gesture's last pan. Apply that input without cancelling the coast.
    if (state.fling && now - state.flingAt < C.grace) {
      apply(current, clamp(dx, C.notch), clamp(dy, C.notch));
      return;
    }
    const precise = now < state.precise ||
      Math.max(Math.abs(dx), Math.abs(dy)) < C.precision;
    if (now < state.precise) state.precise = now + 400;
    if (!SMOOTH || precise || kind === 'slide') {
      // Slides page with the editor's own rate limit; ease only documents.
      stopMotion();
      const result = apply(current, clamp(dx, C.notch), clamp(dy, C.notch));
      if (result.blockedY && dy < 0) overscroll(result.restY);
      return;
    }
    queue(clamp(dx, C.notch), clamp(dy, C.notch));
  }, { capture: true, passive: false });

  window.addEventListener('message', (event) => {
    const data = event.data;
    if (event.source !== window.parent || event.origin !== HOST || !data ||
        data.appflowyOfficeScroll !== 1 || !data.command) {
      return;
    }
    const command = data.command;
    if (command.c === 'precise') {
      // A new gesture takes over from any coast still running.
      if (command.on === true) halt();
      state.precise = command.on === true ? performance.now() + 400 : 0;
    } else if (command.c === 'fling') {
      halt();
      const vx = clamp(finite(Number(command.vx)), C.maxVelocity);
      const vy = clamp(finite(Number(command.vy)), C.maxVelocity);
      if (!SMOOTH || Math.hypot(vx, vy) < C.minVelocity || !adapter()) return;
      state.vx = vx;
      state.vy = vy;
      state.fling = true;
      state.flingAt = performance.now();
      start();
    } else if (command.c === 'stop') {
      halt();
    } else if (command.c === 'report') {
      state.atTop = null;
      report();
    }
  });
  window.addEventListener('pointerdown', halt, true);
  window.addEventListener('keydown', halt, true);
  setInterval(report, 800);
})();
''';

/// The editor frame's runtime, injected before ONLYOFFICE's own scripts.
UserScript buildOfficeScrollUserScript({
  required String documentServerUrl,
  required String hostUrl,
  required PremiumScrollPhysicsConfig config,
  required bool smooth,
}) {
  final origin = Uri.parse(documentServerUrl).origin;
  return UserScript(
    source: buildOfficeScrollRuntimeScript(
      documentServerOrigin: origin,
      hostOrigin: hostUrl,
      config: config,
      smooth: smooth,
    ),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
    allowedOriginRules: {origin},
  );
}

/// Carries the editor frame's scroll state to Flutter and commands back.
class OfficeEditorScrollController {
  InAppWebViewController? _webView;
  bool? _editorAtTop;
  ValueChanged<double>? _onOverscroll;

  /// Null until the frame reports; unknown is treated like the top.
  bool? get editorAtTop => _editorAtTop;

  /// Observes the commands sent to the editor frame.
  @visibleForTesting
  ValueChanged<Map<String, Object>>? debugOnCommand;

  void attach(InAppWebViewController webView) {
    detach();
    _webView = webView;
    webView.addJavaScriptHandler(
      handlerName: officeScrollHandlerName,
      callback: handleMessage,
    );
  }

  void detach() {
    _webView?.removeJavaScriptHandler(handlerName: officeScrollHandlerName);
    _webView = null;
    _editorAtTop = null;
  }

  @visibleForTesting
  Object? handleMessage(List<dynamic> args) {
    final message = args.isEmpty ? null : args.first;
    if (message is! Map) return null;
    switch (message['t']) {
      case 'state':
        final atTop = message['atTop'];
        if (atTop is bool) _editorAtTop = atTop;
      case 'over':
        final dy = message['dy'];
        if (dy is num && dy.isFinite && dy < 0) {
          // Overscroll only happens at the top, whatever the last state said.
          _editorAtTop = true;
          _onOverscroll?.call(dy.toDouble());
        }
    }
    return null;
  }

  void _send(Map<String, Object> command) {
    debugOnCommand?.call(command);
    final webView = _webView;
    if (webView == null) return;
    unawaited(
      webView
          .evaluateJavascript(
            source:
                'window.$_commandFunction && window.$_commandFunction(${jsonEncode(command)});',
          )
          .then<void>((_) {}, onError: (_) {}),
    );
  }
}

/// Coordinates the whole-file page header with ONLYOFFICE's own scroller.
///
/// Scrolling down retires the header before the document moves; scrolling up
/// moves the document first and brings the header back once the document is
/// at its top. Wheel travel is eased like the rest of the app, trackpad pans
/// follow the fingers, and everything else stays native.
class OfficeEditorScroll extends StatefulWidget {
  const OfficeEditorScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  final OfficeEditorScrollController controller;
  final Widget child;

  @override
  State<OfficeEditorScroll> createState() => _OfficeEditorScrollState();
}

class _OfficeEditorScrollState extends State<OfficeEditorScroll>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final WindowsWebViewTrackpadWheel _trackpad =
      WindowsWebViewTrackpadWheel(
    onStart: _panStart,
    onUpdate: _pan,
    onEnd: _panEnd,
    onInertiaCancel: _inertiaCancelled,
  );
  StandaloneFilePageScroll? _page;
  PremiumScrollPhysicsConfig _config = const PremiumScrollPhysicsConfig();
  bool _smooth = true;
  bool _panning = false;
  double _headerQueue = 0;

  /// Release inertia carried by the page header, in logical pixels/second.
  double _headerCoast = 0;
  Duration? _lastFrame;

  /// Finger travel before the gesture's axis is settled, and that axis.
  Offset _panTravel = Offset.zero;
  Axis? _panAxis;
  bool _panAxisSettled = false;

  /// Finger travel after which a pan keeps to one axis (or to none).
  static const double _railDistance = 6;

  double get _panScale => defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux
      ? _config.desktopDirectManipulationScale
      : 1;

  @override
  void initState() {
    super.initState();
    widget.controller._onOverscroll = _overscroll;
  }

  @override
  void didUpdateWidget(covariant OfficeEditorScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._onOverscroll = null;
      widget.controller._onOverscroll = _overscroll;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final page = StandaloneFilePageScroll.maybeOf(context);
    if (page?.outer != _page?.outer) _stopHeader();
    _page = page;
    final physics = officeScrollPhysics(context);
    _config = physics.config;
    _smooth = physics.smooth;
  }

  @override
  void deactivate() {
    _stopHeader();
    super.deactivate();
  }

  @override
  void dispose() {
    if (widget.controller._onOverscroll == _overscroll) {
      widget.controller._onOverscroll = null;
    }
    _ticker.dispose();
    super.dispose();
  }

  ScrollPosition? get _outer {
    final outer = _page?.outer;
    if (outer == null || outer.positions.length != 1) return null;
    final position = outer.position;
    return position.hasContentDimensions ? position : null;
  }

  /// Header travel for [dy], measured from where queued motion will land.
  double _route(double dy, {required bool animate}) {
    final position = _outer;
    if (position == null || dy == 0 || !dy.isFinite) return 0;
    final target = position.pixels + _headerQueue;
    final double used;
    if (dy > 0) {
      used = math.min(dy, math.max(0.0, position.maxScrollExtent - target));
    } else {
      if (widget.controller.editorAtTop == false) return 0;
      used = math.max(dy, -math.max(0.0, target - position.minScrollExtent));
    }
    if (used != 0) _moveHeader(used, animate: animate);
    return used;
  }

  void _moveHeader(double delta, {required bool animate}) {
    final outer = _page?.outer;
    if (outer == null) return;
    if (!animate || !_smooth) {
      final pending = _headerQueue;
      _stopHeader();
      StandaloneFilePageScroll.move(outer, pending + delta);
      return;
    }
    _headerCoast = 0;
    if (_headerQueue != 0 && _headerQueue.sign != delta.sign) _headerQueue = 0;
    _headerQueue += delta;
    if (!_ticker.isActive) {
      _lastFrame = null;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final previous = _lastFrame;
    _lastFrame = elapsed;
    if (previous == null) return;
    final outer = _page?.outer;
    if (!mounted || outer == null || _outer == null) {
      _stopHeader();
      return;
    }
    final seconds = math.min(
      (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond,
      1 / 30,
    );
    if (seconds <= 0) return;
    if (_headerCoast != 0) {
      _coast(outer, seconds);
      return;
    }
    final limit = _config.maxWheelScrollVelocity * seconds;
    final step =
        (_headerQueue * (1 - math.exp(-_config.wheelSmoothingRate * seconds)))
            .clamp(-limit, limit)
            .toDouble();
    final moved = StandaloneFilePageScroll.move(outer, step);
    _headerQueue -= step;
    if ((moved - step).abs() > 0.5) {
      _stopHeader();
    } else if (_headerQueue.abs() < _config.wheelStopDistance) {
      StandaloneFilePageScroll.move(outer, _headerQueue);
      _stopHeader();
    }
  }

  void _stopHeader() {
    _headerQueue = 0;
    _headerCoast = 0;
    _lastFrame = null;
    if (_ticker.isActive) _ticker.stop();
  }

  /// Coasts the header with the app's exponential release friction. Once it is
  /// fully retired, the document takes over at the speed that is left.
  void _coast(ScrollController outer, double seconds) {
    final friction = _config.desktopCoastFriction;
    final decay = math.exp(-friction * seconds);
    final step = _headerCoast / friction * (1 - decay);
    final velocity = _headerCoast * decay;
    _headerCoast = velocity;
    final moved = StandaloneFilePageScroll.move(outer, step);
    if ((moved - step).abs() > 0.5) {
      _stopHeader();
      if (velocity >= _config.minimumVelocity) {
        widget.controller._send({'c': 'fling', 'vx': 0.0, 'vy': velocity});
      }
    } else if (velocity.abs() < _config.stopVelocity) {
      _stopHeader();
    }
  }

  /// Starts release inertia on the header when the header, not the document,
  /// is next in line for a vertical [velocity]. Returns whether it did.
  bool _coastHeader(double velocity) {
    final position = _outer;
    if (position == null || velocity == 0) return false;
    final takes = velocity > 0
        ? position.maxScrollExtent - position.pixels > 0.5
        : widget.controller.editorAtTop != false &&
            position.pixels - position.minScrollExtent > 0.5;
    if (!takes) return false;
    _stopHeader();
    _headerCoast =
        velocity.clamp(-_config.maxVelocity, _config.maxVelocity).toDouble();
    _ticker.start();
    return true;
  }

  /// Two-finger pans are never perfectly straight. Like the platform's scroll
  /// rails, a pan that starts mostly vertical (or horizontal) keeps to that
  /// axis, so a spreadsheet does not drift sideways while it is scrolled.
  Offset _onRails(Offset delta, {bool travel = true}) {
    if (travel && !_panAxisSettled) {
      _panTravel += delta;
      final x = _panTravel.dx.abs();
      final y = _panTravel.dy.abs();
      if (_panTravel.distance < _railDistance) {
        _panAxis = y >= x ? Axis.vertical : Axis.horizontal;
      } else {
        _panAxisSettled = true;
        _panAxis = y >= 2 * x
            ? Axis.vertical
            : x >= 2 * y
                ? Axis.horizontal
                : null;
      }
    }
    return switch (_panAxis) {
      Axis.vertical => Offset(0, delta.dy),
      Axis.horizontal => Offset(delta.dx, 0),
      null => delta,
    };
  }

  Offset _wheel(PointerScrollEvent event) {
    final delta = event.scrollDelta;
    final keys = HardwareKeyboard.instance;
    if (!mounted ||
        keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isShiftPressed ||
        delta.dy == 0 ||
        delta.dy.abs() <= delta.dx.abs()) {
      return delta;
    }
    return Offset(delta.dx, delta.dy - _route(delta.dy, animate: true));
  }

  void _panStart() {
    _panning = true;
    _panTravel = Offset.zero;
    _panAxis = null;
    _panAxisSettled = false;
    _stopHeader();
    widget.controller._send(const {'c': 'precise', 'on': true});
  }

  Offset _pan(Offset raw) {
    final delta = _onRails(raw) * _panScale;
    if (!mounted || delta.dy.abs() <= delta.dx.abs()) return delta;
    return Offset(delta.dx, delta.dy - _route(delta.dy, animate: false));
  }

  void _panEnd(Offset velocity) {
    _panning = false;
    if (!mounted) return;
    widget.controller._send(const {'c': 'precise', 'on': false});
    final release = _onRails(velocity, travel: false) * _panScale;
    if (!_smooth ||
        !release.isFinite ||
        release.distance < _config.minimumVelocity) {
      return;
    }
    if (release.dy.abs() > release.dx.abs() && _coastHeader(release.dy)) {
      return;
    }
    widget.controller._send({'c': 'fling', 'vx': release.dx, 'vy': release.dy});
  }

  void _inertiaCancelled() {
    if (!mounted) return;
    if (_headerCoast != 0) _stopHeader();
    widget.controller._send(const {'c': 'stop'});
  }

  void _overscroll(double dy) {
    if (!mounted) return;
    _route(dy, animate: !_panning);
  }

  @override
  Widget build(BuildContext context) => WindowsWebViewWheelScope(
        transform: _wheel,
        pixelWheel: true,
        trackpad: _trackpad,
        child: widget.child,
      );
}
